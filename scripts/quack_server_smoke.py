#!/usr/bin/env python3
"""Serve finance over the DuckDB Quack protocol and query it from a clean client.

The server installs and loads finance from the community repository. The client
runs with an empty HOME, so it has no finance extension and must rely on the
server for every fin_* call except the expected local failure.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


TOKEN = "finance_smoke_token"

SERVER_SQL = """
INSTALL finance FROM community;
LOAD finance;
CREATE TABLE prices AS
SELECT * FROM (VALUES
  (TIMESTAMP '2026-01-02 09:30:00', 100.0, 101.0, 99.5, 100.5, 1200.0),
  (TIMESTAMP '2026-01-02 09:31:00', 100.5, 101.2, 100.1, 101.0, 1500.0),
  (TIMESTAMP '2026-01-02 09:32:00', 101.0, 101.5, 99.0, 99.0, 900.0)
) AS t(ts, open, high, low, close, volume);
CREATE VIEW returns AS
SELECT ts, fin_simple_return(close, lag(close) OVER (ORDER BY ts)) AS r FROM prices;
CALL quack_serve('{uri}', token := '{token}');
"""

# (name, client SQL, expected last output line). Every query runs on the server.
REMOTE_CASES = [
    (
        "CONNECT scalar",
        "CONNECT remote; SELECT round(fin_bsm_price(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.20)), 6);",
        "10.450584",
    ),
    (
        "CONNECT table function",
        "CONNECT remote; SELECT count(*) FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');",
        "5",
    ),
    (
        "CONNECT bind-replace table function",
        "CONNECT remote; SELECT count(*) FROM fin_normalize_ohlcv('prices', 'ts', 'open', 'high', 'low', 'close', 'volume');",
        "3",
    ),
    (
        "quack_query",
        "SELECT round(bp, 6) FROM quack_query('{uri}', 'SELECT fin_bond_price(0.05, 0.04, 5.0, 2, 100.0) AS bp', token := '{token}');",
        "104.491293",
    ),
    (
        "aggregate over attached table",
        "SELECT round(fin_total_return(r), 6) FROM remote.returns;",
        "-0.014925",
    ),
    (
        "server view through ATTACH",
        "SELECT count(r) FROM remote.returns;",
        "2",
    ),
]

LOCAL_CASE = "SELECT fin_simple_return(101.0, 100.0);"


def run_client(duckdb: str, home: Path, uri: str, sql: str) -> subprocess.CompletedProcess:
    attach = f"ATTACH '{uri}' AS remote (TOKEN '{TOKEN}');"
    env = dict(os.environ, HOME=str(home))
    return subprocess.run(
        [duckdb, "-no-agent", "-list", "-noheader", "-c", attach + " " + sql],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def wait_for_server(duckdb: str, home: Path, uri: str, server: subprocess.Popen, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if server.poll() is not None:
            raise RuntimeError(f"server exited early:\n{server.stdout.read()}")
        if run_client(duckdb, home, uri, "SELECT 1;").returncode == 0:
            return
        time.sleep(1)
    raise RuntimeError("timed out waiting for the Quack server")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duckdb", default="duckdb", help="DuckDB 2.0+ CLI binary")
    parser.add_argument("--port", type=int, default=9494)
    args = parser.parse_args()

    uri = f"quack:localhost:{args.port}"
    failures = 0
    with tempfile.TemporaryDirectory(prefix="finance-quack-") as tmp:
        client_home = Path(tmp) / "client-home"
        client_home.mkdir()
        server = subprocess.Popen(
            [args.duckdb, "-no-agent", str(Path(tmp) / "server.duckdb")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            server.stdin.write(SERVER_SQL.format(uri=uri, token=TOKEN))
            server.stdin.flush()
            wait_for_server(args.duckdb, client_home, uri, server, timeout=60)

            for name, sql, expected in REMOTE_CASES:
                result = run_client(args.duckdb, client_home, uri, sql.format(uri=uri, token=TOKEN))
                lines = result.stdout.strip().splitlines()
                actual = lines[-1].strip() if lines else ""
                if result.returncode == 0 and actual == expected:
                    print(f"ok   {name}: {actual}")
                else:
                    failures += 1
                    print(f"FAIL {name}: expected {expected!r}, got {actual!r}\n{result.stdout}{result.stderr}")

            result = run_client(args.duckdb, client_home, uri, LOCAL_CASE)
            if result.returncode != 0 and "fin_simple_return does not exist" in result.stdout + result.stderr:
                print("ok   client-local fin_* call fails without finance on the client")
            else:
                failures += 1
                print(f"FAIL client-local fin_* call should fail on a clean client\n{result.stdout}{result.stderr}")
        finally:
            server.stdin.close()
            server.terminate()
            server.wait(timeout=10)

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
