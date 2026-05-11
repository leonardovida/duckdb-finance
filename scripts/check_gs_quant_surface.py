#!/usr/bin/env python3
import argparse
import ast
import csv
import os
import re
import sys
import warnings
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GS_QUANT_ROOT = Path(os.environ.get("GS_QUANT_ROOT", ROOT.parent / "gs-quant" / "gs_quant"))
SURFACE_CSV = ROOT / "test" / "fixtures" / "gs_quant_surface.csv"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def scan_gs_quant(root: Path) -> set[tuple[str, str]]:
    rows: set[tuple[str, str]] = set()
    for path in sorted(root.rglob("*.py")):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", SyntaxWarning)
            module = ast.parse(read(path), filename=str(path))
        source_path = path.relative_to(root.parent).as_posix()
        for node in module.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not node.name.startswith("_"):
                rows.add((source_path, node.name))
    return rows


def source_files() -> list[Path]:
    suffixes = {".cpp", ".inc", ".hpp"}
    return sorted(path for path in (ROOT / "src").rglob("*") if path.suffix in suffixes)


def registered_functions() -> set[str]:
    source = "\n".join(read(path) for path in source_files())
    return set(re.findall(r'"((?:fin|gs)_[A-Za-z0-9_]+)"', source))


def read_manifest() -> list[dict[str, str]]:
    if not SURFACE_CSV.exists():
        raise FileNotFoundError(f"Missing GS Quant surface manifest: {SURFACE_CSV}")
    with SURFACE_CSV.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def has_call(sql: str, function: str) -> bool:
    return re.search(r"\b" + re.escape(function) + r"\s*\(", sql) is not None


def report(title: str, values: list[str], limit: int = 30) -> None:
    print(title)
    for value in values[:limit]:
        print(f"  {value}")
    if len(values) > limit:
        print(f"  ... {len(values) - limit} more")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gs-quant-root", type=Path, default=DEFAULT_GS_QUANT_ROOT)
    parser.add_argument("--require-source", action="store_true")
    args = parser.parse_args()

    rows = read_manifest()
    errors: list[tuple[str, list[str]]] = []
    required_columns = {"source_path", "function", "canonical", "compatibility", "status", "category", "notes"}
    if rows and set(rows[0]) != required_columns:
        missing = sorted(required_columns.difference(rows[0]))
        extra = sorted(set(rows[0]).difference(required_columns))
        errors.append(("Manifest header mismatch:", [f"missing={missing} extra={extra}"]))

    manifest_sources = {(row["source_path"], row["function"]) for row in rows}
    if len(manifest_sources) != len(rows):
        errors.append(("Duplicate manifest source rows:", ["manifest contains duplicate source_path/function pairs"]))

    if args.gs_quant_root.exists():
        source_rows = scan_gs_quant(args.gs_quant_root)
        missing = sorted(source_rows.difference(manifest_sources))
        stale = sorted(manifest_sources.difference(source_rows))
        if missing:
            errors.append(("GS Quant functions missing from manifest:", [f"{path}:{fn}" for path, fn in missing]))
        if stale:
            errors.append(("Manifest rows no longer present in GS Quant source:", [f"{path}:{fn}" for path, fn in stale]))
    elif args.require_source:
        errors.append(("GS Quant source root not found:", [str(args.gs_quant_root)]))
    else:
        print(f"GS Quant source root not found at {args.gs_quant_root}; verifying checked-in manifest only.")

    registered = registered_functions()
    missing_canonical = sorted({row["canonical"] for row in rows}.difference(registered))
    missing_compat = sorted({row["compatibility"] for row in rows}.difference(registered))
    if missing_canonical:
        errors.append(("Canonical analogues not registered:", missing_canonical))
    if missing_compat:
        errors.append(("Compatibility aliases not registered:", missing_compat))

    function_reference = read(ROOT / "docs" / "function_reference.md")
    mapping_doc = read(ROOT / "docs" / "compatibility.md")
    docs_text = function_reference + "\n" + mapping_doc + "\n" + read(SURFACE_CSV)
    missing_docs = sorted(
        row["canonical"]
        for row in rows
        if row["status"] != "generated_descriptor"
        and row["canonical"].startswith("fin_")
        and f"`{row['canonical']}`" not in docs_text
    )
    if missing_docs:
        errors.append(("Canonical analogues missing docs entries:", missing_docs))

    gold = read(ROOT / "test" / "sql" / "gold_tests.sql")
    missing_canonical_tests = sorted({row["canonical"] for row in rows if not has_call(gold, row["canonical"])})
    missing_compat_tests = sorted({row["compatibility"] for row in rows if not has_call(gold, row["compatibility"])})
    if missing_canonical_tests:
        errors.append(("Canonical analogues missing gold test references:", missing_canonical_tests))
    if missing_compat_tests:
        errors.append(("Compatibility aliases missing gold test references:", missing_compat_tests))

    makefile = read(ROOT / "Makefile")
    if not re.search(r"^perf:", makefile, re.M) or "$(GOLD_TEST_SQL)" not in makefile:
        errors.append(("Performance profiling is not wired to the gold test corpus:", ["Makefile perf target must run GOLD_TEST_SQL"]))

    if errors:
        for title, values in errors:
            report(title, values)
        return 1

    statuses: dict[str, int] = {}
    for row in rows:
        statuses[row["status"]] = statuses.get(row["status"], 0) + 1
    status_summary = ", ".join(f"{key}={value}" for key, value in sorted(statuses.items()))
    print(f"GS Quant surface covers {len(rows)} public top-level functions ({status_summary}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
