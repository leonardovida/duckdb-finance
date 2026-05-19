---
layout: default
title: Quant Developer Guide
description: Units, model boundaries, risk conventions, and reconciliation guidance.
permalink: /quant-developer-guide/
nav_order: 6
---

# Quant Developer Guide

This extension is aimed at quant developers, desk strategists, risk engineers,
and finance users who want deterministic analytics directly in DuckDB. It is not
a market-data platform or a calibrated vendor pricing stack. The design goal is
to keep common analytics close to the data, with explicit assumptions and
repeatable tests.

## Mental Model

Use DuckDB Finance as a local analytics layer:

- Load positions, marks, curves, vol inputs, ticks, or returns into DuckDB.
- Normalize inputs into standard SQL types: `DOUBLE`, `DATE`, `TIMESTAMP`,
  `VARCHAR`, `STRUCT`, and `LIST`.
- Price or transform records with `fin_*` scalar functions and macros.
- Aggregate with DuckDB SQL for portfolio, strategy, or risk reporting.
- Keep model assumptions in SQL so they are reviewable and reproducible.

This is useful for research notebooks, CI regression datasets, strategy
prototypes, data-quality gates, local PnL explain, and pre-trade sanity checks.
For production trading, treat the output as a controlled local model result
unless it has been independently reconciled to the desk's official model stack.

## Core Conventions

| Area | Convention |
|---|---|
| Returns | Simple returns are decimal returns, not percentages. A 1% return is `0.01`. |
| Volatility | Vol inputs are decimal annualized vols unless a function explicitly says otherwise. A 20% vol is `0.20`. |
| Rates | Rates are decimal annualized rates. A 5bp shock is `0.0005` or `5.0` when a function takes bps. |
| Option time | `ttm` is year fraction. The caller owns day-count and calendar conversion. |
| Discounting | Local option helpers use continuous-rate formulas where the underlying primitive does. |
| Notional | Core model helpers return per-unit values unless the function explicitly accepts or applies notional. |
| Currency | Currency fields are labels. No FX conversion is performed unless the query explicitly prices an FX instrument or applies an FX conversion. |
| Portfolio aggregation | Portfolio helpers aggregate supplied values and risks. They do not net Greeks across different units without caller normalization. |
| NULLs | Functions generally follow DuckDB semantics. Validate upstream inputs where missing data should fail a workflow. |

## Model Boundaries

The library deliberately exposes compact primitives, not hidden calibration:

- BSM, Black-76, Bachelier, digital, barrier, SABR, and SVI helpers operate on
  caller-supplied model inputs.
- Rates and credit helpers are deterministic approximations: annuity x spread,
  Black-76 on a forward rate or spread, and scalar curve shocks.
- Scenario helpers transform scalar inputs. They do not rebuild curves, surfaces,
  or dependency graphs.
- Portfolio helpers are row aggregators. They do not perform official risk
  decomposition, cross-currency conversion, or capital calculations.

That tradeoff is intentional: the SQL should be fast to audit, easy to pin in a
golden dataset, and stable under CI.

## Risk Units

Be explicit about the unit of every risk column you aggregate:

| Risk | Typical local meaning |
|---|---|
| Delta | Change in PV per one unit move in the underlying input used by the helper. |
| Gamma | Change in delta per one unit move in the same underlying input. |
| Vega | Change in PV per absolute volatility point, as returned by the underlying model helper. |
| IR delta | Caller-defined PV sensitivity, usually normalized before portfolio aggregation. |
| Credit delta | Caller-defined PV sensitivity to spread, usually normalized before portfolio aggregation. |

For example, do not add equity spot delta, FX delta, and IR DV01 into one
`portfolio_risk` unless they have first been mapped to a common scenario or
currency-normalized PnL unit.

## Recommended Development Workflow

1. Start from a small deterministic dataset.
2. Add expected values as constants, not expressions that mirror the production
   query.
3. Run `make gold` while developing a function or playbook.
4. Run `make check` before handing off changes.
5. If a model assumption changes, update the corresponding golden constants and
   document the behavior change.

The repository follows that pattern with `test/sql/gold_dataset.sql` and
`test/sql/gold_tests.sql`.

## Query Design Patterns

Prefer CTEs that make the economic inputs explicit:

```sql
WITH option_inputs AS (
  SELECT 'call' AS kind, 100.0 AS spot, 100.0 AS strike, 1.0 AS ttm, 0.05 AS rate, 0.20 AS vol
)
SELECT
  fin_bsm_price(spec) AS pv,
  fin_bsm_delta(spec) AS delta,
  fin_bsm_vega(spec) AS vega
FROM (
  SELECT fin_option_spec(kind, spot, strike, ttm, rate, vol) AS spec
  FROM option_inputs
);
```

For scenario work, separate base inputs, shocked inputs, and comparison:

```sql
WITH base AS (
  SELECT 0.04 AS par_rate, 0.0005 AS parallel_shift
),
shocked AS (
  SELECT par_rate, par_rate + parallel_shift AS shocked_par_rate
  FROM base
)
SELECT par_rate, shocked_par_rate, shocked_par_rate - par_rate AS rate_move
FROM shocked;
```

For portfolio risk, normalize first and aggregate second:

```sql
WITH normalized AS (
  SELECT
    portfolio_id,
    trade_id,
    quantity,
    pv,
    dv01_usd AS risk_usd_per_bp
  FROM desk_risk
)
SELECT
  portfolio_id,
  sum(pv * quantity) AS portfolio_pv,
  sum(risk_usd_per_bp * quantity) AS portfolio_dv01_usd
FROM normalized
GROUP BY portfolio_id;
```

## What To Reconcile

For any serious desk or research workflow, reconcile at least:

- Option PV and Greeks against a trusted library for a representative grid.
- Rate, vol, and spread units against the source system.
- Sign conventions for pay/receive, long/short, and premium direction.
- Calendar and day-count conversion before `ttm` reaches the pricing function.
- Portfolio aggregation units before presenting totals.

The included playbooks are intentionally small so these checks are visible.
