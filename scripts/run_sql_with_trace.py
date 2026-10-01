#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def split_statements(sql: str) -> list[str]:
    statements: list[str] = []
    start = 0
    in_string = False
    in_identifier = False
    in_line_comment = False
    block_comment_depth = 0
    dollar_quote: str | None = None
    i = 0

    while i < len(sql):
        current = sql[i]
        if dollar_quote is not None:
            if sql.startswith(dollar_quote, i):
                i += len(dollar_quote)
                dollar_quote = None
            else:
                i += 1
            continue
        if in_line_comment:
            if current in "\r\n":
                in_line_comment = False
            i += 1
            continue
        if block_comment_depth:
            if sql.startswith("/*", i):
                block_comment_depth += 1
                i += 2
            elif sql.startswith("*/", i):
                block_comment_depth -= 1
                i += 2
            else:
                i += 1
            continue
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
        if sql.startswith("--", i):
            in_line_comment = True
            i += 2
            continue
        if sql.startswith("/*", i):
            block_comment_depth = 1
            i += 2
            continue
        if current == "'":
            in_string = True
        elif current == '"':
            in_identifier = True
        elif current == "$":
            match = re.match(r"\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$", sql[i:])
            if match:
                dollar_quote = match.group(0)
                i += len(dollar_quote)
                continue
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


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def profile_path(output: Path, index: int) -> Path:
    return Path(str(output) + ".d") / f"statement-{index:04d}.json"


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
        process.stdin.write(f".bail on\nLOAD {sql_literal(args.extension)};\n")
        profile_output = getattr(args, "profile_output", None)
        if profile_output and trace:
            process.stdin.write("PRAGMA enable_profiling='json';\n")
        process.stdin.flush()
        for index, statement in enumerate(statements[:count], start=1):
            if profile_output and trace:
                path = profile_path(profile_output, index).resolve()
                process.stdin.write(f"PRAGMA profiling_output={sql_literal(str(path))};\n")
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
    parser.add_argument("--profile-output", type=Path, help="Save per-statement profiles in PATH.d and the last profile at PATH")
    args = parser.parse_args()

    statements = split_statements(args.sql_file.read_text(encoding="utf-8"))
    if args.profile_output:
        profile_directory = Path(str(args.profile_output) + ".d")
        profile_directory.mkdir(parents=True, exist_ok=True)
        args.profile_output.unlink(missing_ok=True)
        # A rerun must not mistake an old profile for a newly executed query.
        for index in range(1, len(statements) + 1):
            profile_path(args.profile_output, index).unlink(missing_ok=True)
    status = run_prefix(args, statements, len(statements), trace=True)
    if args.profile_output:
        profiles = [
            {"statement": index, "sql": statement,
             "profile": str(profile_path(args.profile_output, index).resolve())
                        if profile_path(args.profile_output, index).exists() else None}
            for index, statement in enumerate(statements, start=1)
        ]
        (profile_directory / "statements.json").write_text(json.dumps(profiles, indent=2) + "\n", encoding="utf-8")
        written = [entry["profile"] for entry in profiles if entry["profile"]]
        if written:
            shutil.copyfile(written[-1], args.profile_output)
    if status == 0:
        return 0

    print("duckdb-finance: SQL failed; bisecting first failing statement", file=sys.stderr, flush=True)
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
