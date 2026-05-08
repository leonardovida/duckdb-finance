# Contributing

DuckDB Finance is an OSS DuckDB extension for SQL-native finance and quant
analytics. Contributions are welcome when they keep the extension deterministic,
well-tested, and easy to reason about from SQL.

## Development Setup

Clone DuckDB and this repository, then point `DUCKDB_ROOT` at the DuckDB
checkout:

```sh
git clone https://github.com/duckdb/duckdb.git /path/to/duckdb
git clone https://github.com/leonardovida/duckdb-finance.git /path/to/duckdb-finance
cd /path/to/duckdb-finance
```

Then build and test the extension:

```sh
make debug DUCKDB_ROOT=/path/to/duckdb
make check DUCKDB_ROOT=/path/to/duckdb
```

## Contribution Standards

- Keep functions under the `fin_` namespace unless there is a compatibility
  alias with a clear reason.
- Use standard DuckDB SQL types (`DOUBLE`, `DATE`, `TIMESTAMP`, `VARCHAR`,
  `STRUCT`, and `LIST`) instead of hidden external state.
- Prefer deterministic local models with explicit inputs over opaque
  calibration or network calls.
- Add or update tests in `test/sql/gold_tests.sql` for behavior changes.
- Keep fixtures small and focused in `test/sql/gold_dataset.sql`.
- Update `docs/function_reference.md` when the callable function surface changes.
- Run `make check` before opening a pull request.

## Pull Request Checklist

- The change is scoped to one coherent behavior or documentation improvement.
- New finance behavior has an executable DuckDB test.
- Edge cases are covered, especially NULLs, invalid dimensions, boundary rates,
  zero denominators, and option model round trips.
- Public docs describe units, assumptions, and return semantics.
- `make check` passes locally, or the PR explains the environment blocker.

## Model And Data Policy

Do not add proprietary market data, desk marks, vendor calibration data, API
credentials, or examples that imply entitlement to non-public data. Golden
datasets should be synthetic, deterministic, and small enough to audit in code
review.

## Code Style

Match the surrounding C++ and SQL style. Optimize hot paths when the function is
called row-by-row, but prefer clarity for scaffolding, descriptors, and docs.
Comments should explain non-obvious financial or numerical intent rather than
restating the code.
