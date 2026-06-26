#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path


def split_statements(sql: str) -> list[str]:
    statements: list[str] = []
    start = 0
    in_string = False
    in_identifier = False
    i = 0

    while i < len(sql):
        current = sql[i]
        if in_string:
            if current == "'" and i + 1 < len(sql) and sql[i + 1] == "'":
                i += 2
                continue
            if current == "'":
                in_string = False
            i += 1
            continue
        if in_identifier:
            if current == '"' and i + 1 < len(sql) and sql[i + 1] == '"':
                i += 2
                continue
            if current == '"':
                in_identifier = False
            i += 1
            continue
        if current == "'":
            in_string = True
        elif current == '"':
            in_identifier = True
        elif current == ";":
            statement = sql[start : i + 1].strip()
            if statement:
                statements.append(statement)
            start = i + 1
        i += 1

    trailing = sql[start:].strip()
    if trailing:
        statements.append(trailing)
    return statements


def main() -> int:
    parser = argparse.ArgumentParser(description="Run DuckDB SQL while printing the current statement.")
    parser.add_argument("--duckdb", required=True, help="Path to the DuckDB shell")
    parser.add_argument("--extension", required=True, help="Path to the loadable extension")
    parser.add_argument("sql_file", type=Path)
    args = parser.parse_args()

    statements = split_statements(args.sql_file.read_text(encoding="utf-8"))
    process = subprocess.Popen(
        [args.duckdb, "-unsigned"],
        stdin=subprocess.PIPE,
        text=True,
    )
    assert process.stdin is not None
    process.stdin.write(f"LOAD '{args.extension}';\n.bail on\n")
    process.stdin.flush()
    for index, statement in enumerate(statements, start=1):
        preview = " ".join(statement.split())
        print(f"duckdb-finance: running statement {index}: {preview}", file=sys.stderr, flush=True)
        process.stdin.write(statement + "\n")
        process.stdin.flush()
    process.stdin.close()
    return process.wait()


if __name__ == "__main__":
    sys.exit(main())
