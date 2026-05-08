---
layout: default
title: Performance Testing
description: Profiling and benchmark coverage for DuckDB Finance functions.
permalink: /performance-testing/
nav_order: 4
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
   pricing, bond analytics, cash-flow solvers, curve helpers, and portfolio
   math.

Run the full function-surface profile:

```sh
make perf
```

By default the profile is written to:

```text
/tmp/duckdb-finance-profile.json
```

Use `PERF_OUTPUT` to write somewhere else:

```sh
make perf PERF_OUTPUT=/tmp/finance-profile.json
```

Run the focused hot-path benchmark from DuckDB after loading the extension:

```sql
LOAD '/Users/leov/workspace/motherduck/duckdb/build/debug/extension/finance/finance.duckdb_extension';
.read examples/hot_path_benchmark.sql
```

## CI Coverage

`make check` runs:

- `scripts/check_function_docs.py`, which verifies every registered function has
  a Function Reference entry.
- `scripts/check_function_tests.py`, which verifies every registered function is
  referenced by the gold behavior tests.
- `scripts/check_function_perf_tests.py`, which verifies the profiled corpus
  used by `make perf` covers every registered function.
- The DuckDB-backed smoke and gold SQL suites.

The GitHub Pages workflow publishes the `docs/` site from `main`, so this page
and the generated function reference are deployed with the rest of the
documentation website.
