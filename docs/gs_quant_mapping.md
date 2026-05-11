---
layout: default
title: Compatibility Notes
description: Boundaries for DuckDB Finance compatibility helpers.
permalink: /gs-quant-mapping/
nav_order: 7
---

# Compatibility Notes

DuckDB Finance is a local SQL extension first. Use the core `fin_*` functions
for pricing, returns, risk, portfolios, calendars, technical indicators, and
validation.

This page exists for teams porting existing GS Quant-shaped workflows into
DuckDB. The compatibility helpers preserve familiar names and data shapes where
they make sense in SQL, but they do not call Goldman Sachs APIs, Marquee,
authenticated sessions, pandas runtime code, or entitled market-data services.

For model and unit conventions, read the
[Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}).

## What Is Supported

| Area | SQL surface | Boundary |
|---|---|---|
| Portable time-series helpers | `fin_*` aliases such as `fin_returns`, `fin_correlation`, `fin_bollinger_bands`, and `fin_trend` | Operate on local DuckDB rows and aggregates. They do not preserve pandas indexes. |
| Instrument-shaped structs | Focused `fin_gsq_*` constructors for equity options, FX forwards/options, rates, inflation, credit index options, scenarios, and portfolio rows | Structs hold explicit local inputs. They do not dispatch pricing jobs. |
| Local pricing helpers | Functions such as `fin_gsq_eq_option_price`, `fin_gsq_fx_option_price`, and `fin_gsq_ir_swap_price` | Deterministic formulas using caller-supplied marks, rates, vols, tenors, notionals, and currencies. |
| Scenario helpers | `fin_gsq_apply_shock`, `fin_gsq_curve_scenario_rate`, and related scalar transforms | Transform scalar marks. They do not rebuild curves, dependency graphs, or vol surfaces. |
| Portfolio aggregation | `fin_gsq_portfolio_value` and `fin_gsq_portfolio_risk` | Sum values already normalized by the caller. They do not infer risk units or FX conversion. |

The public [Function Reference]({{ '/function-reference/' | relative_url }})
lists the documented compatibility helpers alongside the rest of the `fin_*`
surface.

## What Is Not Documented As Public API

The project keeps internal compatibility coverage outside the user-facing docs.
That coverage is useful for regression tests, not for finance workflows.

If you are writing a query for a desk, model-validation, research, or CI
workflow, prefer the documented finance helpers and the focused compatibility
helpers above.

## Example

Core finance functions are usually the clearest choice:

```sql
SELECT
  fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS price,
  fin_bsm_delta('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS delta,
  fin_bsm_vega('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS vega;
```

Use a compatibility struct when carrying the instrument shape through multiple
queries is useful:

```sql
WITH option AS (
  SELECT fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20) AS inst
)
SELECT
  fin_gsq_eq_option_price(inst) AS price,
  fin_gsq_eq_delta(inst) AS delta,
  fin_gsq_eq_vega(inst) AS vega
FROM option;
```

## Verification

Run the complete extension verification before relying on compatibility
behavior:

```sh
make check DUCKDB_ROOT=/path/to/duckdb
```
