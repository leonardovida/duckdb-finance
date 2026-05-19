#!/usr/bin/env python3
import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class FunctionEntry:
    name: str
    source_file: str
    category: str
    documented: bool
    gold_tested: bool
    perf_tested: bool


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def source_files() -> list[Path]:
    suffixes = {".cpp", ".inc", ".hpp"}
    return sorted(path for path in (ROOT / "src").rglob("*") if path.suffix in suffixes)


def category_for(path: Path) -> str:
    relative = path.relative_to(ROOT)
    parts = relative.parts
    if len(parts) >= 3 and parts[0] == "src":
        return parts[1]
    if relative.name == "macros.cpp":
        return "macros"
    if relative.name == "scalar.cpp":
        return "scalar"
    if relative.name == "aggregate.cpp":
        return "aggregate"
    if relative.name == "table_functions.cpp":
        return "table_functions"
    return "other"


def registered_by_source() -> dict[str, tuple[Path, str]]:
    entries: dict[str, tuple[Path, str]] = {}
    for path in source_files():
        text = read(path)
        for function in sorted(set(re.findall(r'"(fin_[A-Za-z0-9_]+)"', text))):
            if function == "fin_cdl_":
                continue
            entries.setdefault(function, (path, category_for(path)))
    return entries


def referenced_functions(path: Path) -> set[str]:
    text = read(path)
    return set(re.findall(r"\b(fin_[A-Za-z0-9_]+)\s*\(", text))


def documented_functions() -> set[str]:
    text = read(ROOT / "docs" / "function_reference.md")
    return set(re.findall(r"`(fin_[A-Za-z0-9_]+)`", text))


def inventory() -> list[FunctionEntry]:
    docs = documented_functions()
    gold = referenced_functions(ROOT / "test" / "sql" / "gold_tests.sql")
    perf = gold
    entries = []
    for name, (source, category) in sorted(registered_by_source().items()):
        entries.append(
            FunctionEntry(
                name=name,
                source_file=str(source.relative_to(ROOT)),
                category=category,
                documented=name in docs,
                gold_tested=name in gold,
                perf_tested=name in perf,
            )
        )
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="print the inventory as JSON")
    args = parser.parse_args()

    entries = inventory()
    if args.json:
        print(json.dumps([asdict(entry) for entry in entries], indent=2, sort_keys=True))
        return 0

    failures = [
        entry for entry in entries if not entry.documented or not entry.gold_tested or not entry.perf_tested
    ]
    if failures:
        print("Function surface contract gaps:")
        for entry in failures:
            missing = []
            if not entry.documented:
                missing.append("docs")
            if not entry.gold_tested:
                missing.append("gold")
            if not entry.perf_tested:
                missing.append("perf")
            print(f"  {entry.name} ({entry.source_file}): missing {', '.join(missing)}")
        return 1

    print(f"Function surface inventory covers {len(entries)} registered functions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
