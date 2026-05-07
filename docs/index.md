# DuckDB Finance Extension

The `finance` extension is organized around normal DuckDB SQL types and a `fin_`
function namespace. It can be built as a standard out-of-tree DuckDB extension
against the adjacent DuckDB checkout.

For the full callable surface, see [Function Reference](function_reference.md).
For model and unit conventions, see
[Quant Developer Guide](quant_developer_guide.md). For complete workflow
examples, see [Finance SQL Playbooks](playbooks.md).

## API Areas

- Numerical helpers and distributions: normal, Student-t, chi-square, safe
  division, basis-point conversion, clipping, and tick rounding.
- Returns and risk: simple/log returns, total return, annualization, volatility,
  Sharpe, native Sortino/EWMA/drawdown/outlier/quantile-spread aggregates,
  VaR/CVaR-style helpers, capture ratios, and data-quality reports.
- Options: BSM, Black-76, Bachelier, binomial, digital, Asian geometric, barrier,
  SABR, SVI, Greeks, higher-order Greeks, and implied-vol solvers.
- Fixed income and cash flows: day count, discount factors, forward rates, PV/FV,
  NPV/IRR/XIRR/MIRR, annuities, bond price/YTM/duration/convexity/DV01, curve
  interpolation, and curve bootstrapping.
- Portfolio analytics: vector and matrix helpers, portfolio return, variance,
  volatility, Sharpe, equal/inverse-vol weights, optimizer table functions, HRP
  fallback weights, efficient-frontier points, and rebalance trades.
- GS Quant-inspired pricing and risk: SQL-native descriptors for pricing
  contexts, instruments, measures, scenarios, and portfolio aggregation, plus
  deterministic local pricing/risk helpers for equity, FX, rates, inflation, and
  credit fixtures.
- Time series and technical indicators: SQL macro wrappers for common rolling
  aggregates, OHLC/OHLCV, TA-style indicators, candlestick aliases, and grid/bar
  table functions.
- Market microstructure: mid, spread, spread bps, microprice, order imbalance,
  trade sign, VWAP/TWAP, bar construction, and impact proxies.
- Validation and schema helpers: OHLC validation, return validation, finite/price
  checks, convention parsers, schema templates, and schema validation scaffolding.

## Stability Notes

Native C++ functions are used for formulas that need numerical control, nested
list output, custom aggregate state, or table-function bind-time SQL generation.
Macros are used for broad aggregate compatibility where DuckDB already has a
good primitive such as `avg`, `stddev_samp`, `corr`, `quantile_cont`, or `fsum`.

The regression smoke suite exercises the high-risk callable surface: optional
aggregate arguments, bind-replace table-function overloads, option model
round-trips, fixed-income helpers, portfolio/matrix helpers, calendar/session
logic, grids, bars, and factor-report plumbing.

Some broad catalog entries are pragmatic v1 aliases or approximations so the API
surface is usable while the deeper statistical/optimization methods can be
improved behind stable names.

## Quant Developer Orientation

The extension is intended for users who already think in PV, Greeks, rates,
vols, curve shocks, returns, and portfolio aggregation. Inputs are explicit and
caller-owned: rates are decimal rates, vols are annualized decimals, `ttm` is a
year fraction, and portfolio risk aggregation assumes normalized risk units.

The library favors reproducible local analytics over opaque calibration. It is
appropriate for research, CI fixtures, desk sanity checks, and local scenario
analysis. Official pricing, market-data entitlement, curve construction,
calibration, and production risk governance remain outside the extension unless
the caller supplies those inputs explicitly.

## GS Quant-Inspired Surface

The GS Quant-inspired layer is documented in
[GS Quant-Inspired SQL Mapping](gs_quant_mapping.md). It follows the shape of GS
Quant pricing-and-risk workflows while remaining local to DuckDB: no Goldman
Sachs API calls, sessions, entitlements, or remote market-data dependencies are
required. The regression suite includes `gsq_goldman_*` fixtures in
`test/sql/gold_dataset.sql` and row-wise expected-value checks in
`test/sql/gold_tests.sql`.

## Playbooks

[Finance SQL Playbooks](playbooks.md) contains runnable examples for:

- Equity option desk snapshots.
- Cross-asset portfolio rollups.
- Scenario PnL explain.
- Rates curve shifts and swap PV.
- Factor and return tear sheets.
- Market microstructure diagnostics and bars.

The companion SQL is available at `examples/playbooks.sql`.
