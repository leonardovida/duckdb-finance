#!/usr/bin/env python3
import re
import sys
from function_discovery import ROOT, read, registered_functions


def main() -> int:
    makefile = read(ROOT / "Makefile")
    if not re.search(r"^perf:", makefile, re.M):
        print("Missing Makefile perf target.")
        return 1
    if "PRAGMA enable_profiling" not in makefile or "$(GOLD_TEST_SQL)" not in makefile:
        print("The perf target must profile the gold test corpus.")
        return 1

    tests = read(ROOT / "test" / "sql" / "gold_tests.sql")
    missing = sorted(
        function for function in registered_functions()
        if not re.search(r"\b" + re.escape(function) + r"\s*\(", tests)
    )
    if missing:
        print("Missing performance-test references through the profiled gold corpus:")
        for function in missing:
            print(f"  {function}")
        return 1

    print(f"Performance tests profile {len(registered_functions())} registered functions through make perf.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
