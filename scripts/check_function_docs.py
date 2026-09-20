#!/usr/bin/env python3
import re
import sys
from function_discovery import ROOT, read, registered_functions


def main() -> int:
    docs = read(ROOT / "docs" / "function_reference.md")
    documented = set(re.findall(r"`(fin_[A-Za-z0-9_]+)`", docs))
    functions = registered_functions()
    missing = sorted(function for function in functions if function not in documented)
    if missing:
        print("Missing function reference entries:")
        for function in missing:
            print(f"  {function}")
        return 1
    print(f"Function reference covers {len(functions)} registered functions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
