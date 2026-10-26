#!/usr/bin/env python3
"""Run a sqllogictest file (test/sql/*.test) through the DuckDB CLI.

DuckDB's own unittest runner executes these files when it is built with the
extension's tests; the release pipeline skips that runner, so this script keeps
the records exercised by `make test`. It supports the subset the finance tests
use: `require`, `statement ok`, `statement error` (the expected text must occur
in the error message) and `query <types> [nosort|rowsort]` with tab-separated
expected rows. As in DuckDB's runner, the type string sets the expected column
count. Every record runs in a fresh in-memory database.
"""
import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Record:
    line: int
    kind: str  # "ok", "error" or "query"
    sql: str
    expected: list[str] = field(default_factory=list)
    sort: str = "nosort"
    columns: int = 0


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def parse(path: Path) -> list[Record]:
    lines = path.read_text().splitlines()
    records = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line or line.startswith("#") or line.startswith("require "):
            i += 1
            continue
        header = line.split()
        start = i + 1
        columns = 0
        if header[0] == "statement" and len(header) == 2 and header[1] in ("ok", "error"):
            kind = header[1]
            sort = "nosort"
        elif header[0] == "query" and len(header) in (2, 3):
            kind = "query"
            columns = len(header[1])
            sort = header[2] if len(header) == 3 else "nosort"
            if sort not in ("nosort", "rowsort"):
                raise ValueError(f"{path}:{start}: unsupported sort mode {sort!r}")
        else:
            raise ValueError(f"{path}:{start}: unsupported record {line!r}")
        i += 1
        sql = []
        while i < len(lines) and lines[i].strip() and lines[i] != "----":
            sql.append(lines[i])
            i += 1
        expected = []
        if i < len(lines) and lines[i] == "----":
            i += 1
            while i < len(lines) and lines[i].strip():
                expected.append(lines[i])
                i += 1
        if kind == "ok" and expected:
            raise ValueError(f"{path}:{start}: statement ok cannot have expected output")
        records.append(Record(start, kind, "\n".join(sql), expected, sort, columns))
    return records


def run(duckdb: str, extension: str, record: Record) -> str | None:
    # The extension is loaded by path; `LOAD finance` records are covered by that.
    if record.kind == "ok" and record.sql.strip().rstrip(";").lower() == "load finance":
        return None
    script = (
        f"LOAD {sql_literal(extension)};\n.bail on\n.mode tabs\n.headers off\n.nullvalue NULL\n"
        f"{record.sql.rstrip().rstrip(';')};\n"
    )
    try:
        process = subprocess.run(
            [duckdb, "-no-agent", "-unsigned", ":memory:"], input=script, capture_output=True, text=True, timeout=300
        )
    except subprocess.TimeoutExpired:
        return f"line {record.line}: timed out"
    output = process.stdout.splitlines()
    error = process.stderr.strip()
    if record.kind == "error":
        if process.returncode == 0:
            return f"line {record.line}: expected an error, the statement succeeded"
        expected = "\n".join(record.expected).strip()
        if expected and expected not in error:
            return f"line {record.line}: expected error containing {expected!r}, got {error!r}"
        return None
    if process.returncode != 0:
        return f"line {record.line}: unexpected error {error!r}"
    if record.kind == "query":
        widths = {len(row.split("\t")) for row in output}
        if widths and widths != {record.columns}:
            return f"line {record.line}: expected {record.columns} columns, got {sorted(widths)}"
        actual = sorted(output) if record.sort == "rowsort" else output
        expected = sorted(record.expected) if record.sort == "rowsort" else record.expected
        if actual != expected:
            return f"line {record.line}: expected {expected!r}, got {actual!r}"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--duckdb", required=True)
    parser.add_argument("--extension", required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("tests", nargs="+", type=Path)
    args = parser.parse_args()

    failures = 0
    for path in args.tests:
        records = parse(path)
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(lambda record: run(args.duckdb, args.extension, record), records))
        for result in results:
            if result:
                failures += 1
                print(f"{path}: {result}", file=sys.stderr)
        print(f"{path}: {len(records) - sum(1 for r in results if r)}/{len(records)} records passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
