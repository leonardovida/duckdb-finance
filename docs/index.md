---
layout: default
title: DuckDB Finance Extension
description: SQL-native quant analytics for DuckDB.
permalink: /
nav_order: 1
---

# DuckDB Finance Extension

<p class="lead"><code>finance</code> is an out-of-tree DuckDB extension for quant developers, desk
strategists, risk engineers, and finance users who want deterministic analytics
close to their data.</p>

The public API lives in the `fin_` namespace and uses ordinary DuckDB types:
`DOUBLE`, `DATE`, `TIMESTAMP`, `VARCHAR`, `STRUCT`, `LIST`, and table results.
It is built for local research, CI fixtures, scenario checks, desk sanity
checks, and SQL-native portfolio analytics.

```sql
LOAD '/Users/leov/workspace/motherduck/duckdb/build/debug/extension/finance/finance.duckdb_extension';

SELECT
  fin_bsm_price('call', 100, 100, 1, 0.05, 0.20) AS price,
  (fin_bsm_greeks('call', 100, 100, 1, 0.05, 0.20)).delta AS delta,
  fin_bsm_implied_vol('call', 10.45058357, 100, 100, 1, 0.05) AS implied_vol;
```

## Explore The Docs

<div class="doc-grid">
  <a class="doc-link" href="{{ '/getting-started/' | relative_url }}">
    <strong>Getting Started</strong>
    <span>Build the extension, load it in DuckDB, and run the first pricing and risk queries.</span>
  </a>
  <a class="doc-link" href="{{ '/function-reference/' | relative_url }}">
    <strong>Function Reference</strong>
    <span>Search every registered <code>fin_*</code> function by usage, purpose, and return shape.</span>
  </a>
  <a class="doc-link" href="{{ '/performance-testing/' | relative_url }}">
    <strong>Performance Testing</strong>
    <span>Profile the full function surface and run focused hot-path benchmarks.</span>
  </a>
  <a class="doc-link" href="{{ '/quant-developer-guide/' | relative_url }}">
    <strong>Quant Developer Guide</strong>
    <span>Read the units, model boundaries, risk conventions, and reconciliation guidance.</span>
  </a>
  <a class="doc-link" href="{{ '/playbooks/' | relative_url }}">
    <strong>Finance SQL Playbooks</strong>
    <span>Run desk-style examples for options, scenario PnL, rates, portfolios, factors, and ticks.</span>
  </a>
</div>

## API Areas

| Area | What It Covers |
|---|---|
| Numerical helpers and distributions | Normal, Student-t, chi-square, safe division, basis-point conversion, clipping, and tick rounding. |
| Returns and risk | Simple/log returns, total return, annualization, volatility, Sharpe, Sortino, EWMA, drawdown, VaR/CVaR-style helpers, capture ratios, outliers, and data quality. |
| Options and volatility | BSM, Black-76, Bachelier, binomial, digital, Asian geometric, barrier, SABR, SVI, Greeks, higher-order Greeks, and implied-vol solvers. |
| Fixed income and cash flows | Day count, discount factors, forward rates, PV/FV, NPV/IRR/XIRR/MIRR, annuities, bond price/YTM/duration/convexity/DV01, and curve helpers. |
| Portfolio analytics | Vector and matrix helpers, portfolio return/variance/volatility/Sharpe, equal and inverse-vol weights, optimizer table functions, HRP fallback weights, efficient-frontier points, and rebalance trades. |
| GS Quant-inspired workflows | SQL-native descriptors for pricing contexts, instruments, measures, scenarios, and portfolio aggregation. |
| Time series and technical indicators | Rolling aggregate macros, OHLC/OHLCV, TA-style indicators, candlestick aliases, grid functions, and bars. |
| Market microstructure | Mid, spread, spread bps, microprice, order imbalance, trade sign, VWAP/TWAP, bar construction, and impact proxies. |
| Validation and schema helpers | OHLC validation, return validation, finite/price checks, convention parsers, schema templates, and schema validation scaffolding. |

## Stability Notes

Native C++ functions are used where numerical control, nested list output,
custom aggregate state, or table-function bind-time SQL generation matters.
SQL macros are used where DuckDB already has the right primitive, such as `avg`,
`stddev_samp`, `corr`, `quantile_cont`, or `fsum`.

Some broad catalog entries are pragmatic v1 aliases or approximations so the API
surface is usable while deeper statistical and optimization methods can improve
behind stable names. Placeholder behavior is explicitly documented and covered
by tests.

## Repository Map

| Path | Purpose |
|---|---|
| `src/scalar.cpp` | Native scalar math, option models, fixed income, cash-flow, portfolio, matrix, validation, and calendar/session functions. |
| `src/aggregate.cpp` | Native aggregates with custom state, including Sortino, EWMA variance/volatility, RSI, drawdown metrics, outlier counts, quantile spread, IV rank, and IV percentile. |
| `src/macros.cpp` | SQL macro wrappers for aggregate-style analytics and compatibility aliases. |
| `src/table_functions.cpp` | DuckDB table functions and bind-replace SQL table functions. |
| `test/sql/gold_dataset.sql` and `test/sql/gold_tests.sql` | Deterministic behavior coverage for the function surface. |
| `docs/function_reference.md` | Source-derived function reference with usage, purpose, returns, and examples. |

## Verification

Run the complete local verification before handing off source or docs changes:

```sh
make check
```
