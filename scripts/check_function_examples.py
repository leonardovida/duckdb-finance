#!/usr/bin/env python3
"""Check docs/function_examples.sql.

Without arguments this is a static check: every registered fin_* function has
exactly one self-contained example. With --duckdb and --extension it also runs
every example in a fresh in-memory database and checks that duckdb_functions()
reports the generated description, example, and parameter names.
"""
import argparse
import csv
import io
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

from function_discovery import registered_functions
from function_examples import EXAMPLES, ROOT, ExampleError, FunctionExample, parse_examples


# Examples run against an empty database: no files, network, or fixture tables.
FORBIDDEN = re.compile(
    r"\b(read_\w+|ATTACH|COPY|INSTALL|LOAD|EXPORT|IMPORT|CREATE|INSERT|UPDATE|DELETE|DROP|PRAGMA|SET)\b"
    r"|https?://|'gold_|\bgold_",
    re.IGNORECASE,
)


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def static_errors(examples: list[FunctionExample]) -> list[str]:
    errors = []
    registered = registered_functions()
    seen: dict[str, int] = {}
    for example in examples:
        if example.name in seen:
            errors.append(f"{example.name}: duplicate example (lines {seen[example.name]} and {example.line})")
        seen[example.name] = example.line
        if example.name not in registered:
            errors.append(f"{example.name}: example for an unregistered function (line {example.line})")
        if not re.search(r"\b" + re.escape(example.name) + r"\s*\(", example.sql):
            errors.append(f"{example.name}: example does not call {example.name} (line {example.line})")
        forbidden = FORBIDDEN.search(example.sql)
        if forbidden:
            errors.append(
                f"{example.name}: example is not self-contained ({forbidden.group(0)!r}, line {example.line})"
            )
    for name in sorted(registered - set(seen)):
        errors.append(f"{name}: missing example in {EXAMPLES.relative_to(ROOT)}")
    return errors


def run_example(duckdb: str, extension: str, example: FunctionExample) -> str | None:
    script = f".bail on\nLOAD {sql_literal(extension)};\n.mode csv\n.headers on\n{example.sql}\n"
    try:
        process = subprocess.run(
            [duckdb, "-unsigned", ":memory:"], input=script, capture_output=True, text=True, timeout=120
        )
    except subprocess.TimeoutExpired:
        return "timed out after 120 s"
    output = process.stdout.strip()
    if process.returncode != 0 or process.stderr.strip():
        message = (process.stderr.strip() or output or f"exit code {process.returncode}").splitlines()
        return " ".join(message)[:400]
    if len(output.splitlines()) < 2:
        return "returned no rows"
    return None


def catalog_errors(duckdb: str, extension: str, examples: list[FunctionExample]) -> list[str]:
    # CSV keeps the check free of the json extension, which CI builds without.
    query = (
        "SELECT function_name, function_type, "
        "function_name || '(' || array_to_string(parameters, ', ') || ')' AS signature, "
        "description IS NOT NULL AS has_description, len(examples) AS example_count, examples[1] AS example, "
        "len(list_filter(parameters, lambda p: regexp_full_match(p, 'col[0-9]+'))) AS unnamed "
        "FROM duckdb_functions() WHERE starts_with(function_name, 'fin_') ORDER BY ALL"
    )
    script = f".bail on\nLOAD {sql_literal(extension)};\n.mode csv\n.headers on\n{query};\n"
    process = subprocess.run([duckdb, "-unsigned", ":memory:"], input=script, capture_output=True, text=True)
    if process.returncode != 0 or process.stderr.strip():
        return [f"duckdb_functions() failed: {(process.stderr or process.stdout).strip()[:400]}"]
    expected = {example.name: example for example in examples}
    errors = []
    rows = list(csv.DictReader(io.StringIO(process.stdout)))
    if not rows:
        return ["duckdb_functions() returned no fin_* functions"]
    for row in rows:
        example = expected.get(row["function_name"])
        signature = row["signature"]
        if example is None:
            errors.append(f"{signature}: registered but has no example")
            continue
        if row["has_description"] != "true":
            errors.append(f"{signature}: duckdb_functions() has no description")
        if row["example_count"] != "1" or row["example"] != example.sql:
            errors.append(f"{signature}: duckdb_functions() example differs; regenerate src/function_metadata.inc")
        if row["function_type"] != "macro" and row["unnamed"] != "0":
            errors.append(f"{signature}: positional parameters are unnamed; add or fix the signature header")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--duckdb", help="DuckDB shell used to execute the examples")
    parser.add_argument("--extension", help="finance extension to load")
    parser.add_argument("--jobs", type=int, default=4, help="examples to run in parallel")
    parser.add_argument("--only", action="append", default=[], help="run only these functions")
    args = parser.parse_args()
    if bool(args.duckdb) != bool(args.extension):
        parser.error("--duckdb and --extension must be given together")

    try:
        examples = parse_examples()
    except ExampleError as error:
        print(f"{EXAMPLES.relative_to(ROOT)}: {error}")
        return 1
    errors = [] if args.only else static_errors(examples)
    if errors:
        print("Function example problems:")
        for error in errors:
            print(f"  {error}")
        return 1
    if not args.duckdb:
        print(f"Function examples cover {len(examples)} registered functions.")
        return 0

    selected = [example for example in examples if not args.only or example.name in args.only]
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(lambda example: run_example(args.duckdb, args.extension, example), selected))
    failures = [(example, error) for example, error in zip(selected, results) if error]
    if not args.only:
        failures += [(None, error) for error in catalog_errors(args.duckdb, args.extension, examples)]
    if failures:
        print("Function example failures:")
        for example, error in failures:
            if example is None:
                print(f"  {error}")
            else:
                print(f"  {example.name} (line {example.line}): {error}\n    {example.sql}")
        return 1
    print(f"Executed {len(selected)} function examples; duckdb_functions() metadata matches.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
