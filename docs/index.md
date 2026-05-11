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

Until the community package is published, build from source with a DuckDB
checkout. The community install flow shown in the installation guide is the
intended public path after upstream acceptance.

```sql
-- After loading finance:

SELECT
  fin_bsm_price('call', 100, 100, 1, 0.05, 0.20) AS price,
  (fin_bsm_greeks('call', 100, 100, 1, 0.05, 0.20)).delta AS delta,
  fin_bsm_implied_vol('call', 10.45058357, 100, 100, 1, 0.05) AS implied_vol;
```

## Explore The Docs

<div class="doc-grid">
  <a class="doc-link" href="{{ '/getting-started/' | relative_url }}">
    <strong>Getting Started</strong>
    <span>Run a controlled first set of pricing, risk, fixed-income, portfolio, and table-function queries.</span>
  </a>
  <a class="doc-link" href="{{ '/agent-guide/' | relative_url }}">
    <strong>Agent Guide</strong>
    <span>Route agent tasks to the right docs, examples, checks, and source files.</span>
  </a>
  <a class="doc-link" href="{{ '/installation/' | relative_url }}">
    <strong>Installation</strong>
    <span>Build from source today or install from DuckDB Community Extensions after publication.</span>
  </a>
  <a class="doc-link" href="{{ '/function-cookbook/' | relative_url }}">
    <strong>Function Cookbook</strong>
    <span>Choose functions by task with small runnable SQL examples.</span>
  </a>
  <a class="doc-link" href="{{ '/function-reference/' | relative_url }}">
    <strong>Function Reference</strong>
    <span>Search every registered <code>fin_*</code> function by usage, purpose, and return shape.</span>
  </a>
  <a class="doc-link" href="{{ '/playbooks/' | relative_url }}">
    <strong>Finance SQL Playbooks</strong>
    <span>Run desk-style workflows for options, scenario PnL, rates, portfolios, factors, and ticks.</span>
  </a>
  <a class="doc-link" href="{{ '/best-practices/' | relative_url }}">
    <strong>Best Practices</strong>
    <span>Keep units, assumptions, validation, and aggregation explicit.</span>
  </a>
  <a class="doc-link" href="{{ '/quant-developer-guide/' | relative_url }}">
    <strong>Quant Developer Guide</strong>
    <span>Read the units, model boundaries, risk conventions, and reconciliation guidance.</span>
  </a>
  <a class="doc-link" href="{{ '/compatibility/' | relative_url }}">
    <strong>Compatibility</strong>
    <span>Understand the boundaries for compatibility helpers and ported workflows.</span>
  </a>
  <a class="doc-link" href="{{ '/performance-testing/' | relative_url }}">
    <strong>Performance Testing</strong>
    <span>Profile the full function surface and run focused hot-path benchmarks.</span>
  </a>
  <a class="doc-link" href="{{ '/development/' | relative_url }}">
    <strong>Development Guide</strong>
    <span>Build, test, document, and extend the out-of-tree extension.</span>
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
| Compatibility helpers | Local aliases and focused struct helpers for porting existing finance workflows. |
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

Because this is pre-1.0 OSS software, users should pin a commit for production
research workflows and reconcile model outputs against their official analytics
stack before relying on them for trading, valuation, or risk sign-off.

## Repository Map

| Path | Purpose |
|---|---|
| `src/scalar.cpp` | Native scalar registration unit; implementation lives in `src/scalar/*.inc`. |
| `src/aggregate.cpp` | Native aggregate registration unit; implementation lives in `src/aggregate/*.inc`. |
| `src/macros.cpp` | SQL macro registration unit; macro groups live in `src/macros/*.inc`. |
| `src/table_functions.cpp` | Table-function registration unit; implementation lives in `src/table_functions/*.inc`. |
| `test/sql/gold_dataset.sql` and `test/sql/gold_tests.sql` | Deterministic behavior coverage for the function surface. |
| `docs/function_reference.md` | Source-derived function reference with usage, purpose, returns, and examples. |

## Compatibility Layer

The compatibility layer is documented in
[Compatibility](compatibility.md). It preserves familiar finance helper
names and focused struct shapes where they make sense in SQL, while keeping all
analytics local to DuckDB.

These helpers are not affiliated with Goldman Sachs and do not use GS APIs,
sessions, entitlements, or market data.

## Playbooks

[Finance SQL Playbooks](playbooks.md) contains runnable examples for option desk
snapshots, cross-asset portfolio rollups, scenario PnL explain, rates curve
shifts, factor tear sheets, and market microstructure diagnostics. The companion
SQL is available at `examples/playbooks.sql`.

## Development And Contribution

Use [Development Guide](development.md) for local setup. Public contributions
should include focused SQL tests, updated docs, and a passing `make check`.
Synthetic fixtures are preferred; do not contribute proprietary market data,
vendor marks, credentials, or entitlement-dependent examples.

## Verification

Run the complete local verification before handing off source or docs changes:

```sh
make check
```
