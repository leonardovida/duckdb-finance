---
layout: default
title: Development Guide
description: Build, test, document, and extend DuckDB Finance.
permalink: /development/
nav_order: 9
---

# Development Guide

This guide explains how to build, test, document, and extend DuckDB Finance as a
standard out-of-tree DuckDB extension.

## Repository Shape

| Path | Purpose |
|---|---|
| `src/scalar.cpp` and `src/scalar/*.inc` | Native scalar functions for math, rates, options, cash flows, portfolios, validation, calendars, and GSQ-style descriptors. |
| `src/aggregate.cpp` and `src/aggregate/*.inc` | Native aggregate state for metrics such as Sortino, EWMA volatility, drawdowns, outliers, IV rank, and IV percentile. |
| `src/macros.cpp` and `src/macros/*.inc` | SQL macro registrations and compatibility aliases. |
| `src/table_functions.cpp` and `src/table_functions/*.inc` | Table functions and bind-replace SQL generators. |
| `include/finance/finance_extension.hpp` | Extension registration declarations. |
| `test/sql/gold_dataset.sql` | Small deterministic fixture tables. |
| `test/sql/gold_tests.sql` | Assertion-based behavior and edge-case tests. |
| `test/sql/smoke_queries.sql` | Broad callable-surface smoke coverage. |
| `docs/function_reference.md` | Public usage reference for registered `fin_*` functions. |

## Build Requirements

- DuckDB source checkout.
- CMake and a C++ toolchain supported by DuckDB.
- Python 3 for documentation coverage checks.
- `make`.

Build:

```sh
make debug DUCKDB_ROOT=/path/to/duckdb
```

## Test Commands

```sh
make smoke
make gold
make test
make check
```

`make check` runs:

1. `scripts/check_function_docs.py` to confirm registered functions are covered
   in `docs/function_reference.md`.
2. `scripts/check_docs_site.py` to confirm the GitHub Pages navigation and
   publishing workflow are wired.
3. `scripts/check_function_tests.py` to confirm registered functions are covered
   by the gold behavior tests.
4. `scripts/check_function_perf_tests.py` to confirm the profiled gold corpus
   covers registered functions.
5. `make smoke` to load the extension and run broad smoke queries.
6. `make gold` to run deterministic fixtures and assertions.

Manual load:

```sql
LOAD '/path/to/duckdb/build/debug/extension/finance/finance.duckdb_extension';
SELECT fin_version();
```

DuckDB requires `-unsigned` for local unsigned extension binaries:

```sh
/path/to/duckdb/build/debug/duckdb -unsigned
```

## Adding A Function

1. Choose the smallest native or SQL-macro implementation that fits the
   behavior.
2. Register the function under `fin_*`.
3. Add behavior tests in `test/sql/gold_tests.sql`.
4. Add or update deterministic fixture rows in `test/sql/gold_dataset.sql` only
   when a reusable fixture makes the test clearer.
5. Document the function in `docs/function_reference.md`.
6. Run `make check`.

Prefer native C++ for numerically sensitive models, custom list/struct output,
table-function binding, and hot row-wise execution. Prefer SQL macros when
DuckDB already exposes the right aggregate or window primitive.

## Numerical And Finance Conventions

- Rates and returns are decimal values.
- Volatility is annualized decimal volatility unless stated otherwise.
- Option `ttm` is a year fraction.
- Currency fields are labels unless a function explicitly performs FX pricing.
- Portfolio aggregation assumes caller-normalized units.
- Invalid dimensions should return `NULL` or throw consistently with nearby
  functions; do not silently fabricate successful results.

## Documentation Expectations

The public docs should make model assumptions explicit. Every new function
should describe:

- Purpose.
- SQL usage.
- Return type or shape.
- Units and important assumptions.
- NULL, invalid input, or approximation behavior when relevant.

The function reference is intentionally concise; longer workflows belong in
`docs/playbooks.md` or `examples/playbooks.sql`.
