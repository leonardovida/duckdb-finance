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


def preview(statement: str) -> str:
    return " ".join(statement.split())


def run_prefix(args: argparse.Namespace, statements: list[str], count: int, *, trace: bool) -> int:
    stderr = None if trace else subprocess.DEVNULL
    process = subprocess.Popen(
        [args.duckdb, "-unsigned"],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=stderr,
        text=True,
    )
    assert process.stdin is not None
    try:
        process.stdin.write(f"LOAD '{args.extension}';\n.bail on\n")
        process.stdin.flush()
        for index, statement in enumerate(statements[:count], start=1):
            if trace:
                print(
                    f"duckdb-finance: running statement {index}: {preview(statement)}",
                    file=sys.stderr,
                    flush=True,
                )
            process.stdin.write(statement + "\n")
            process.stdin.flush()
        process.stdin.close()
    except BrokenPipeError:
        return process.wait()
    return process.wait()


def find_first_failing_statement(args: argparse.Namespace, statements: list[str]) -> int | None:
    low = 1
    high = len(statements)
    result: int | None = None
    while low <= high:
        mid = (low + high) // 2
        print(f"duckdb-finance: checking statements 1..{mid}", file=sys.stderr, flush=True)
        if run_prefix(args, statements, mid, trace=False) == 0:
            low = mid + 1
        else:
            result = mid
            high = mid - 1
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Run DuckDB SQL while printing the current statement.")
    parser.add_argument("--duckdb", required=True, help="Path to the DuckDB shell")
    parser.add_argument("--extension", required=True, help="Path to the loadable extension")
    parser.add_argument("sql_file", type=Path)
    args = parser.parse_args()

    statements = split_statements(args.sql_file.read_text(encoding="utf-8"))
    status = run_prefix(args, statements, len(statements), trace=True)
    if status == 0:
        return 0

    print("duckdb-finance: smoke failed; bisecting first failing statement", file=sys.stderr, flush=True)
    failing = find_first_failing_statement(args, statements)
    if failing is not None:
        print(
            f"duckdb-finance: first failing statement {failing}: {preview(statements[failing - 1])}",
            file=sys.stderr,
            flush=True,
        )
    return status


if __name__ == "__main__":
    sys.exit(main())
