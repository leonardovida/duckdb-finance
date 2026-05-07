# DuckDB Finance Documentation

DuckDB Finance is an out-of-tree DuckDB extension that exposes SQL-native quant
finance analytics through the `fin_` function namespace. It uses standard
DuckDB values such as `DOUBLE`, `DATE`, `TIMESTAMP`, `VARCHAR`, `STRUCT`, and
`LIST`, so workflows stay inspectable and portable.

Start here:

- [Function Reference](function_reference.md) for callable `fin_*` usage.
- [Quant Developer Guide](quant_developer_guide.md) for units, conventions, and
  model boundaries.
- [GS Quant-Inspired SQL Mapping](gs_quant_mapping.md) for local SQL analogues
  of pricing-and-risk workflows.
- [Finance SQL Playbooks](playbooks.md) for complete runnable workflows.
- [Development Guide](development.md) for build, test, and contribution details.

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

Because this is pre-1.0 OSS software, users should pin a commit for production
research workflows and reconcile model outputs against their official analytics
stack before relying on them for trading, valuation, or risk sign-off.

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

These helpers are not affiliated with Goldman Sachs and do not use GS APIs,
sessions, entitlements, or market data.

## Playbooks

[Finance SQL Playbooks](playbooks.md) contains runnable examples for:

- Equity option desk snapshots.
- Cross-asset portfolio rollups.
- Scenario PnL explain.
- Rates curve shifts and swap PV.
- Factor and return tear sheets.
- Market microstructure diagnostics and bars.

The companion SQL is available at `examples/playbooks.sql`.

## Development And Contribution

Use [Development Guide](development.md) for local setup. Public contributions
should include focused SQL tests, updated docs, and a passing `make check`.
Synthetic fixtures are preferred; do not contribute proprietary market data,
vendor marks, credentials, or entitlement-dependent examples.
