---
layout: default
title: Performance Testing
description: Profiling and benchmark coverage for DuckDB Finance functions.
permalink: /performance-testing/
nav_order: 5
---

# Performance Testing

The extension keeps two layers of performance coverage:

1. `make perf` profiles the complete gold-test corpus with DuckDB JSON
   profiling enabled. Because `scripts/check_function_tests.py` and
   `scripts/check_function_perf_tests.py` both verify that every registered
   `fin_*` function is referenced by `test/sql/gold_tests.sql`, this gives every
   function at least one profiled execution.
2. `examples/hot_path_benchmark.sql` contains heavier benchmark queries for the
   highest-volume model families, including option pricing and Greeks, binomial
   pricing, bond analytics, cash-flow solvers, curve helpers, portfolio math,
   returns/risk aggregates, and date/calendar helpers.

Run the full function-surface profile:

```sh
make perf DUCKDB_ROOT=/path/to/duckdb
```

By default the profile is written to:

```text
/tmp/duckdb-finance-profile.json
```

Use `PERF_OUTPUT` to write somewhere else:

```sh
make perf DUCKDB_ROOT=/path/to/duckdb PERF_OUTPUT=/tmp/finance-profile.json
```

Run the focused hot-path benchmark from a checkout of this repository after
installing and loading the published extension:

```sql
INSTALL finance FROM community;
LOAD finance;
.read examples/hot_path_benchmark.sql
```

When developing from source, use the same source-built DuckDB and local
extension flow as the Makefile targets above. The `.read` path is relative to
the repository checkout where the DuckDB shell is running.

## CI Coverage

`make check` runs:

- `scripts/check_function_docs.py`, which verifies every registered function has
  a Function Reference entry.
- `scripts/check_function_tests.py`, which verifies every registered function is
  referenced by the gold behavior tests.
- `scripts/check_function_perf_tests.py`, which verifies the profiled corpus
  used by `make perf` covers every registered function.
- `scripts/check_function_surface.py`, which writes and validates the
  machine-readable source/docs/gold/perf inventory for every registered
  function.
- The DuckDB-backed smoke and gold SQL suites.

The GitHub Pages workflow publishes the `docs/` site from `main`, so this page
and the generated function reference are deployed with the rest of the
documentation website.
