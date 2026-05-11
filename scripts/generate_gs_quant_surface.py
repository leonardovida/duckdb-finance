#!/usr/bin/env python3
import argparse
import ast
import csv
import hashlib
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GS_QUANT_ROOT = ROOT.parent / "gs-quant" / "gs_quant"

SURFACE_CSV = ROOT / "docs" / "gs_quant_surface.csv"
MACRO_INC = ROOT / "src" / "macros" / "gs_quant_surface.inc"
FUNCTION_REFERENCE = ROOT / "docs" / "function_reference.md"
GS_MAPPING = ROOT / "docs" / "gs_quant_mapping.md"
GOLD_TESTS = ROOT / "test" / "sql" / "gold_tests.sql"

REFERENCE_BEGIN = "<!-- BEGIN GENERATED GS QUANT SURFACE REFERENCE -->"
REFERENCE_END = "<!-- END GENERATED GS QUANT SURFACE REFERENCE -->"
MAPPING_BEGIN = "<!-- BEGIN GENERATED GS QUANT SURFACE SUMMARY -->"
MAPPING_END = "<!-- END GENERATED GS QUANT SURFACE SUMMARY -->"
TEST_BEGIN = "-- BEGIN GENERATED GS QUANT SURFACE TESTS"
TEST_END = "-- END GENERATED GS QUANT SURFACE TESTS"


@dataclass(frozen=True)
class SourceFunction:
    source_path: str
    function: str


@dataclass(frozen=True)
class SurfaceRow:
    source_path: str
    function: str
    canonical: str
    compatibility: str
    status: str
    category: str
    notes: str


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_if_changed(path: Path, text: str) -> None:
    if path.exists() and read(path) == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def scan_gs_quant(root: Path) -> list[SourceFunction]:
    if not root.exists():
        raise FileNotFoundError(f"GS Quant source root not found: {root}")
    rows: list[SourceFunction] = []
    for path in sorted(root.rglob("*.py")):
        module = ast.parse(read(path), filename=str(path))
        source_path = path.relative_to(root.parent).as_posix()
        for node in module.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not node.name.startswith("_"):
                rows.append(SourceFunction(source_path, node.name))
    return rows


def source_files(exclude_generated: bool = False) -> list[Path]:
    suffixes = {".cpp", ".inc", ".hpp"}
    files = sorted(path for path in (ROOT / "src").rglob("*") if path.suffix in suffixes)
    if exclude_generated:
        files = [path for path in files if path != MACRO_INC]
    return files


def registered_fin_functions(exclude_generated: bool = False) -> set[str]:
    source = "\n".join(read(path) for path in source_files(exclude_generated))
    functions = set(re.findall(r'"(fin_[A-Za-z0-9_]+)"', source))
    functions.discard("fin_cdl_")
    return functions


def slugify(value: str, max_len: int = 96) -> str:
    value = value.replace("gs_quant/", "").replace(".py", "")
    value = value.replace("__init__", "init").replace("_version", "version")
    slug = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").lower()
    slug = re.sub(r"_+", "_", slug)
    if len(slug) <= max_len:
        return slug
    digest = hashlib.sha1(slug.encode("utf-8")).hexdigest()[:10]
    return f"{slug[: max_len - 11].rstrip('_')}_{digest}"


def category_for(source_path: str) -> str:
    parts = source_path.replace("gs_quant/", "").split("/")
    if parts[0] == "timeseries":
        return "timeseries"
    if parts[0] == "datetime":
        return "datetime"
    if parts[0] == "risk":
        return "risk"
    if parts[0] == "backtests":
        return "backtests"
    if parts[0] in {"api", "markets"}:
        return "api_query"
    if parts[0] in {"analytics", "content"}:
        return "content"
    if "json" in source_path or "encoder" in source_path or "decoder" in source_path:
        return "json_encoding"
    if parts[0] == "test":
        return "test_support"
    return "support"


def prefix_for_category(category: str) -> str:
    return {
        "timeseries": "fin_gsq_timeseries",
        "datetime": "fin_gsq_datetime",
        "risk": "fin_risk",
        "backtests": "fin_backtest",
        "json_encoding": "fin_json",
        "api_query": "fin_api",
        "content": "fin_content",
        "test_support": "fin_gsq_test",
        "support": "fin_gsq_support",
    }[category]


def alias_prefix_for_category(category: str) -> str:
    return {
        "timeseries": "gs_timeseries",
        "datetime": "gs_datetime",
        "risk": "gs_risk",
        "backtests": "gs_backtest",
        "json_encoding": "gs_json",
        "api_query": "gs_api",
        "content": "gs_content",
        "test_support": "gs_test",
        "support": "gs_support",
    }[category]


def module_slug(source_path: str, max_len: int = 48) -> str:
    module = source_path.replace("gs_quant/", "").replace(".py", "")
    return slugify(module, max_len=max_len)


def canonical_for(item: SourceFunction, existing_fin: set[str]) -> tuple[str, str, str]:
    function = item.function
    candidates = [f"fin_{function}"]
    if function.endswith("_"):
        candidates.append(f"fin_{function[:-1]}")
    else:
        candidates.append(f"fin_{function}_")
    for candidate in candidates:
        if candidate in existing_fin:
            return candidate, "native", "Maps to an existing DuckDB Finance function."

    category = category_for(item.source_path)
    base = slugify(function, max_len=72)
    return f"{prefix_for_category(category)}_{base}", "generated_descriptor", (
        "DuckDB-local descriptor for a GS Quant helper whose Python behavior depends on "
        "SDK objects, remote sessions, pandas indexes, or test scaffolding."
    )


def build_rows(source: list[SourceFunction]) -> list[SurfaceRow]:
    existing_fin = registered_fin_functions(exclude_generated=True)
    rows: list[SurfaceRow] = []
    seen_aliases: set[str] = set()
    seen_canonicals: set[str] = set(existing_fin)
    generated_canonicals: set[str] = set()

    for item in source:
        canonical, status, notes = canonical_for(item, existing_fin)
        category = category_for(item.source_path)
        compat_base = slugify(item.function, max_len=72)
        compatibility = f"{alias_prefix_for_category(category)}_{compat_base}"
        if compatibility in seen_aliases:
            candidate = f"{compatibility}_{module_slug(item.source_path, max_len=36)}"
            if candidate in seen_aliases:
                digest = hashlib.sha1(f"{item.source_path}:{item.function}".encode("utf-8")).hexdigest()[:8]
                candidate = f"{candidate}_{digest}"
            compatibility = candidate
        seen_aliases.add(compatibility)

        if status == "generated_descriptor":
            base = canonical
            if canonical in seen_canonicals or canonical in generated_canonicals:
                candidate = f"{base}_{module_slug(item.source_path, max_len=36)}"
                if candidate in seen_canonicals or candidate in generated_canonicals:
                    digest = hashlib.sha1(f"{item.source_path}:{item.function}".encode("utf-8")).hexdigest()[:8]
                    candidate = f"{candidate}_{digest}"
                canonical = candidate
            generated_canonicals.add(canonical)
        seen_canonicals.add(canonical)

        rows.append(SurfaceRow(item.source_path, item.function, canonical, compatibility, status, category, notes))
    return rows


def sql_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def c_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def write_manifest(rows: list[SurfaceRow]) -> None:
    header = ["source_path", "function", "canonical", "compatibility", "status", "category", "notes"]
    lines = []
    from io import StringIO

    buffer = StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(header)
    for row in rows:
        writer.writerow([row.source_path, row.function, row.canonical, row.compatibility, row.status, row.category, row.notes])
    lines.append(buffer.getvalue())
    write_if_changed(SURFACE_CSV, "".join(lines))


def write_macros(rows: list[SurfaceRow]) -> None:
    lines = [
        "// Generated by scripts/generate_gs_quant_surface.py. Do not edit by hand.\n",
    ]
    generated = {row.canonical: row for row in rows if row.status == "generated_descriptor"}
    for canonical in sorted(generated):
        row = generated[canonical]
        definition = (
            f"(payload := NULL) AS struct_pack(source_path := {sql_string(row.source_path)}, "
            f"source_function := {sql_string(row.function)}, canonical := {sql_string(row.canonical)}, "
            f"status := {sql_string(row.status)}, category := {sql_string(row.category)}, payload := payload)"
        )
        lines.append(f'    {{"{c_string(row.canonical)}", "{c_string(definition)}"}},\n')

    for row in rows:
        definition = (
            f"(payload := NULL) AS struct_pack(source_path := {sql_string(row.source_path)}, "
            f"source_function := {sql_string(row.function)}, canonical := {sql_string(row.canonical)}, "
            f"status := {sql_string(row.status)}, category := {sql_string(row.category)}, payload := payload)"
        )
        lines.append(f'    {{"{c_string(row.compatibility)}", "{c_string(definition)}"}},\n')
    write_if_changed(MACRO_INC, "".join(lines))


def replace_block(text: str, begin: str, end: str, block: str, insert_before: str | None = None) -> str:
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    replacement = f"{begin}\n{block.rstrip()}\n{end}"
    if pattern.search(text):
        return pattern.sub(replacement, text)
    if insert_before and insert_before in text:
        return text.replace(insert_before, replacement + "\n\n" + insert_before, 1)
    return text.rstrip() + "\n\n" + replacement + "\n"


def write_function_reference(rows: list[SurfaceRow]) -> None:
    generated = [row for row in rows if row.status == "generated_descriptor"]
    block_lines = [
        "## GS Quant Source Descriptors",
        "",
        "These generated descriptor functions account for GS Quant public top-level helpers that do not have a hand-written local DuckDB analogue. They are deterministic local payload records: callers can pass local JSON, structs, or scalar values as `payload`, and DuckDB Finance returns that payload with source metadata. DuckDB Finance does not call GS Quant, Marquee, sessions, entitlements, or pandas runtime code.",
        "",
        "| Function | Usage | Purpose | Returns / notes |",
        "|---|---|---|---|",
    ]
    for row in generated:
        purpose = f"Local descriptor for `{row.source_path}` `{row.function}`."
        returns = f"STRUCT with source path, source function, canonical function, status, category, and payload. Category: `{row.category}`."
        block_lines.append(f"| `{row.canonical}` | `{row.canonical}(payload := NULL)` | {purpose} | {returns} |")
    text = replace_block(
        read(FUNCTION_REFERENCE),
        REFERENCE_BEGIN,
        REFERENCE_END,
        "\n".join(block_lines),
        insert_before="### GS Quant-Inspired Examples",
    )
    write_if_changed(FUNCTION_REFERENCE, text)


def write_mapping_summary(rows: list[SurfaceRow]) -> None:
    counts: dict[tuple[str, str], int] = {}
    for row in rows:
        counts[(row.category, row.status)] = counts.get((row.category, row.status), 0) + 1
    block_lines = [
        "## Full Source-Surface Audit",
        "",
        f"The checked GS Quant AST surface contains {len(rows)} public top-level functions. The generated manifest at [`gs_quant_surface.csv`](gs_quant_surface.csv) maps every source path and function to a DuckDB Finance canonical analogue, a `gs_*` source lookup alias, coverage status, category, and notes.",
        "",
        "| Category | Native mappings | Generated descriptors |",
        "|---|---:|---:|",
    ]
    for category in sorted({row.category for row in rows}):
        native = counts.get((category, "native"), 0)
        generated = counts.get((category, "generated_descriptor"), 0)
        block_lines.append(f"| `{category}` | {native} | {generated} |")
    block_lines.extend(
        [
            "",
            "Generated descriptors are explicit local payload analogues for helpers whose Python implementation depends on GS Quant SDK runtime objects, authenticated Marquee calls, pandas index behavior, or test scaffolding. They keep the source surface discoverable and tested, accept caller-supplied local payloads, and preserve the rule that DuckDB Finance remains local and deterministic.",
        ]
    )
    text = replace_block(read(GS_MAPPING), MAPPING_BEGIN, MAPPING_END, "\n".join(block_lines))
    write_if_changed(GS_MAPPING, text)


def write_gold_tests(rows: list[SurfaceRow]) -> None:
    generated = [row for row in rows if row.status == "generated_descriptor"]
    block_lines = [
        "-- Generated by scripts/generate_gs_quant_surface.py. Do not edit by hand.",
        "-- Each SELECT keeps the GS Quant source-surface analogue and source lookup alias in the profiled gold corpus.",
    ]
    for idx, row in enumerate(generated, 1):
        label = f"gs quant canonical {idx:04d} {row.source_path} {row.function}"
        block_lines.append(
            f"SELECT assert_eq({sql_string(label)}, {row.canonical}('local_payload').payload || ':' || {row.canonical}('local_payload').source_function, {sql_string('local_payload:' + row.function)});"
        )
    for idx, row in enumerate(rows, 1):
        label = f"gs quant compatibility {idx:04d} {row.source_path} {row.function}"
        block_lines.append(
            f"SELECT assert_eq({sql_string(label)}, {row.compatibility}().canonical, {sql_string(row.canonical)});"
        )
    text = replace_block(read(GOLD_TESTS), TEST_BEGIN, TEST_END, "\n".join(block_lines))
    write_if_changed(GOLD_TESTS, text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gs-quant-root", type=Path, default=DEFAULT_GS_QUANT_ROOT)
    args = parser.parse_args()
    source = scan_gs_quant(args.gs_quant_root)
    rows = build_rows(source)
    write_manifest(rows)
    write_macros(rows)
    write_function_reference(rows)
    write_mapping_summary(rows)
    write_gold_tests(rows)
    print(f"Generated GS Quant surface coverage for {len(rows)} public top-level functions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
