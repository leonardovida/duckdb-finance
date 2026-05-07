#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def registered_functions() -> set[str]:
    source = "\n".join(read(path) for path in (ROOT / "src").glob("*.cpp"))
    functions = set(re.findall(r'"(fin_[A-Za-z0-9_]+)"', source))
    functions.discard("fin_cdl_")

    macros = read(ROOT / "src" / "macros.cpp")
    match = re.search(r"static const char \*CDL_PATTERNS\[\] = \{(.*?)nullptr\};", macros, re.S)
    if match:
        functions.update(f"fin_cdl_{name}" for name in re.findall(r'"([a-z0-9]+)"', match.group(1)))
    return functions


def main() -> int:
    docs = read(ROOT / "docs" / "function_reference.md")
    documented = set(re.findall(r"`(fin_[A-Za-z0-9_]+)`", docs))
    missing = sorted(function for function in registered_functions() if function not in documented)
    if missing:
        print("Missing function reference entries:")
        for function in missing:
            print(f"  {function}")
        return 1
    print(f"Function reference covers {len(registered_functions())} registered functions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
