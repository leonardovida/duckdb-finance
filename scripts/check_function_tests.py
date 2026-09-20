#!/usr/bin/env python3
import re
import sys
from function_discovery import ROOT, read, registered_functions


def main() -> int:
    tests = read(ROOT / "test" / "sql" / "gold_tests.sql")
    missing = sorted(
        function for function in registered_functions()
        if not re.search(r"\b" + re.escape(function) + r"\s*\(", tests)
    )
    if missing:
        print("Missing gold test references:")
        for function in missing:
            print(f"  {function}")
        return 1
    print(f"Gold tests reference {len(registered_functions())} registered functions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
