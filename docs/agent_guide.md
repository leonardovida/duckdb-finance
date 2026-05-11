---
layout: default
title: Agent Guide
description: How agents should navigate DuckDB Finance docs and choose functions.
permalink: /agent-guide/
nav_order: 3
---

# Agent Guide

Use this page when an automated agent needs to answer questions, write SQL, or
modify the DuckDB Finance extension. It is a routing guide, not a substitute for
the function reference.

## Fast Routing

| User intent | Start here | Then verify with |
|---|---|---|
| Install or load the extension | [Installation]({{ '/installation/' | relative_url }}) | `make smoke DUCKDB_ROOT=/path/to/duckdb` |
| Learn the first queries | [Getting Started]({{ '/getting-started/' | relative_url }}) | Run the SQL snippets against a loaded extension |
| Choose a function for a task | [Function Cookbook]({{ '/function-cookbook/' | relative_url }}) | [Function Reference]({{ '/function-reference/' | relative_url }}) |
| Build a desk-style workflow | [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}) | `examples/playbooks.sql` |
| Explain units or model boundaries | [Best Practices]({{ '/best-practices/' | relative_url }}) and [Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}) | Relevant gold tests |
| Check compatibility behavior | [Compatibility]({{ '/compatibility/' | relative_url }}) | `scripts/check_gs_quant_surface.py` |
| Change code or docs | [Development Guide]({{ '/development/' | relative_url }}) | `make check DUCKDB_ROOT=/path/to/duckdb` |

## Working Rules

1. Prefer core `fin_*` functions before compatibility helpers.
2. Keep all rates, returns, and volatilities in decimal units unless a function
   says it takes basis points.
3. Treat currency fields as labels unless the function explicitly performs FX
   pricing or conversion.
4. Do not infer market data, curves, calendars, or official risk units. Ask the
   caller or make the assumption explicit in SQL.
5. Use the function reference for signatures and return shapes, then run the
   query. Do not rely on memory for exact overloads.
6. For source builds, use the Makefile targets. They load the local unsigned
   extension correctly.

## Function Lookup Pattern

When asked for a function, search in this order:

```sh
rg -n 'fin_bsm_|fin_var|fin_calendar' docs/function_reference.md
rg -n 'fin_bsm_|fin_var|fin_calendar' test/sql/gold_tests.sql
rg -n 'fin_bsm_|fin_var|fin_calendar' src
```

Use the reference for the user-facing contract, gold tests for executable
examples, and source only when behavior or edge cases are unclear.

## SQL Answer Pattern

A useful answer should include:

- A minimal SQL query that can run after `LOAD finance`.
- The assumptions for rates, returns, volatility, time, notional, and currency.
- The expected shape of the result.
- A pointer to the relevant docs page or function reference entry.

Example:

```sql
SELECT
  fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS price,
  fin_bsm_delta('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS delta,
  fin_bsm_vega('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS vega;
```

Assumptions: `ttm` is a year fraction, rate is decimal annualized, volatility
is decimal annualized, and the result is per unit notional.

## Change Checklist

When editing functions or docs:

- Add or update focused behavior coverage in `test/sql/gold_tests.sql`.
- Keep fixture data small and synthetic in `test/sql/gold_dataset.sql`.
- Update [Function Reference]({{ '/function-reference/' | relative_url }}) when
  the public callable surface changes.
- Update examples or playbooks when a common workflow changes.
- Run `make check DUCKDB_ROOT=/path/to/duckdb` before handing off.
