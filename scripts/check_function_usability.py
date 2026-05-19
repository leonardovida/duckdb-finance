#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTAL_PATH = ROOT / "config" / "experimental_functions.json"
REFERENCE_PATH = ROOT / "docs" / "function_reference.md"
EXPERIMENTAL_DOC_PATH = ROOT / "docs" / "experimental_functions.md"


PLACEHOLDER_PATTERNS = (
    re.compile(r"\bAS\s+NULL\b"),
    re.compile(r"\bAS\s+0\.0\b"),
    re.compile(r"\bAS\s+0\.5\b"),
    re.compile(r"\bAS\s+market_weights\b"),
    re.compile(r"\bAS\s+\[\[1\.0\]\]\b"),
    re.compile(r"struct_pack\([^}]*:=\s*NULL", re.DOTALL),
    re.compile(r"/\s+NULL\b"),
)

DOC_QUALITY_FUNCTIONS = {
    "fin_bsm_all",
    "fin_bsm_delta",
    "fin_bsm_gamma",
    "fin_bsm_greeks",
    "fin_bsm_price",
    "fin_bsm_vega",
    "fin_normalize_ohlcv",
    "fin_normalize_option_chain",
    "fin_normalize_returns",
    "fin_option_chain",
    "fin_option_spec",
    "fin_option_spec_dates",
    "fin_portfolio_return_table",
    "fin_portfolio_variance_table",
}

EQUAL_WEIGHT_PLACEHOLDERS = {
    "fin_max_sharpe_weights",
    "fin_min_variance_weights",
    "fin_risk_parity_weights",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def experimental_functions() -> dict[str, dict[str, str]]:
    data = json.loads(read_text(EXPERIMENTAL_PATH))
    entries = data.get("functions")
    if not isinstance(entries, list):
        raise ValueError("config/experimental_functions.json must contain a functions list")
    result: dict[str, dict[str, str]] = {}
    for entry in entries:
        name = entry.get("name")
        reason = entry.get("reason")
        replacement = entry.get("replacement")
        if not all(isinstance(value, str) and value.strip() for value in (name, reason, replacement)):
            raise ValueError("Every experimental function needs name, reason, and replacement")
        if name in result:
            raise ValueError(f"Duplicate experimental function entry: {name}")
        result[name] = entry
    return result


def registered_functions() -> set[str]:
    functions: set[str] = set()
    for path in (ROOT / "src").rglob("*"):
        if path.suffix not in {".cpp", ".inc", ".hpp"}:
            continue
        functions.update(re.findall(r'"(fin_[A-Za-z0-9_]+)"', read_text(path)))
    return functions


def placeholder_functions() -> dict[str, list[str]]:
    placeholders: dict[str, list[str]] = {}
    for path in (ROOT / "src" / "macros").glob("*.inc"):
        for line_no, line in enumerate(read_text(path).splitlines(), start=1):
            match = re.search(r'\{"(fin_[A-Za-z0-9_]+)"\s*,\s*"([^"]*)"\}', line)
            if not match:
                continue
            function_name = match.group(1)
            definition = match.group(2)
            is_placeholder = any(pattern.search(definition) for pattern in PLACEHOLDER_PATTERNS)
            if function_name in EQUAL_WEIGHT_PLACEHOLDERS and re.search(r"\bAS\s+fin_equal_weights\(", definition):
                is_placeholder = True
            if is_placeholder:
                placeholders.setdefault(function_name, []).append(f"{path.relative_to(ROOT)}:{line_no}")
    return placeholders


def documented_functions(path: Path) -> set[str]:
    return set(re.findall(r"`(fin_[A-Za-z0-9_]+)`", read_text(path)))


def reference_rows() -> dict[str, tuple[str, str, str]]:
    rows: dict[str, tuple[str, str, str]] = {}
    for line in read_text(REFERENCE_PATH).splitlines():
        if not line.startswith("| `fin_"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 4:
            continue
        match = re.fullmatch(r"`(fin_[A-Za-z0-9_]+)`", cells[0])
        if match:
            rows[match.group(1)] = (cells[1], cells[2], cells[3])
    return rows


def main() -> int:
    failures: list[str] = []
    experimental = experimental_functions()
    registered = registered_functions()
    placeholders = placeholder_functions()
    reference_functions = documented_functions(REFERENCE_PATH)
    experimental_doc_functions = documented_functions(EXPERIMENTAL_DOC_PATH)
    rows = reference_rows()

    for name in sorted(placeholders):
        if name not in experimental:
            locations = ", ".join(placeholders[name])
            failures.append(f"{name} looks experimental/placeholder but is missing from {EXPERIMENTAL_PATH.relative_to(ROOT)} ({locations})")

    for name in sorted(experimental):
        if name not in registered:
            failures.append(f"{name} is listed as experimental but is not registered")
        if name not in reference_functions:
            failures.append(f"{name} is listed as experimental but is missing from docs/function_reference.md")
        if name not in experimental_doc_functions:
            failures.append(f"{name} is listed as experimental but is missing from docs/experimental_functions.md")
        for field in ("reason", "replacement"):
            value = experimental[name][field].strip()
            if value.endswith("."):
                failures.append(f"{name} {field} should be a concise fragment without trailing period")

    unregistered_doc_entries = sorted(experimental_doc_functions - registered)
    for name in unregistered_doc_entries:
        failures.append(f"{name} is documented in docs/experimental_functions.md but is not registered")

    for name in sorted(DOC_QUALITY_FUNCTIONS):
        if name not in registered:
            failures.append(f"{name} is in the docs quality set but is not registered")
            continue
        row = rows.get(name)
        if not row:
            failures.append(f"{name} is in the docs quality set but is missing from docs/function_reference.md")
            continue
        _, purpose, notes = row
        if re.search(r"\bCompute\b.*\bfor SQL finance workflows\b", purpose):
            failures.append(f"{name} reference purpose is still generic")
        if notes in {"DOUBLE unless noted by DuckDB overloads.", "Aggregate or scalar SQL macro result.", "Table result."}:
            failures.append(f"{name} reference return notes are too generic")

    if failures:
        print("Function usability check failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print(f"Function usability check covers {len(experimental)} experimental functions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
