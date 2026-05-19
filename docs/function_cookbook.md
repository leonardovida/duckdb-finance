---
layout: default
title: Function Cookbook
description: Task-based DuckDB Finance SQL examples for common analytics work.
permalink: /function-cookbook/
nav_order: 5
wide: true
---

# Function Cookbook

Use this page to choose the right functions for common finance tasks. Each
example is intentionally small and assumes the extension is already loaded.

For exact signatures, overloads, and return notes, use the
[Function Reference]({{ '/function-reference/' | relative_url }}).

## Returns And Risk

Turn prices or returns into common performance metrics:

```sql
WITH returns(r) AS (
  VALUES (0.01), (-0.02), (0.03), (0.015), (-0.005)
)
SELECT
  fin_total_return(r) AS total_return,
  fin_volatility(r) AS annualized_volatility,
  fin_sharpe(r, 0.0, 252) AS sharpe,
  fin_sortino(r, 0.0, 252) AS sortino,
  fin_max_drawdown(r) AS max_drawdown
FROM returns;
```

Use `fin_simple_return(price, previous_price)` or
`fin_log_return(price, previous_price)` when starting from prices.

## Option Pricing And Greeks

Price an option and return risk columns in one row:

```sql
SELECT
  fin_bsm_price(spec) AS price,
  fin_bsm_delta(spec) AS delta,
  fin_bsm_gamma(spec) AS gamma,
  fin_bsm_vega(spec) AS vega,
  fin_bsm_implied_vol('call', 10.450583572185565, 100.0, 100.0, 1.0, 0.05) AS implied_vol
FROM (
  SELECT fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS spec
);
```

Use `fin_black76_price` for futures or forward-style underliers,
`fin_bachelier_price` for normal-vol workflows, and `fin_binomial_price` when
you need tree-style pricing.

## Fixed Income And Cash Flows

Discount cash flows, solve yield, and inspect bond risk:

```sql
SELECT
  fin_discount_factor(0.05, 2.0, 'continuous') AS discount_factor,
  fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.10, 'periodic') AS npv,
  fin_irr([-100.0, 60.0, 60.0]) AS irr,
  fin_bond_price(0.05, 0.04, 5.0, 2, 100.0) AS bond_price,
  fin_bond_duration(0.05, 0.04, 5.0, 2, 100.0, 'modified') AS duration,
  fin_bond_convexity(0.05, 0.04, 5.0, 2, 100.0) AS convexity;
```

Inputs are caller-owned. The extension does not fetch curves or infer day-count
rules unless the function explicitly accepts that convention.

## Portfolio Construction

Use list and matrix helpers for small portfolio calculations:

```sql
SELECT
  fin_portfolio_return([0.5, 0.5], [0.08, 0.12]) AS expected_return,
  fin_portfolio_vol([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]]) AS volatility,
  fin_inverse_vol_weights([0.20, 0.30]) AS inverse_vol_weights;
```

For table-shaped optimizer output, use table functions:

```sql
SELECT *
FROM fin_efficient_frontier([0.08, 0.12], [[0.04, 0.01], [0.01, 0.09]], 5);
```

When portfolio inputs already live in tables, keep them table-shaped:

```sql
SELECT *
FROM fin_portfolio_return_table('portfolio_inputs', 'asset_id', 'weight', 'expected_return');

SELECT *
FROM fin_portfolio_variance_table(
  'portfolio_inputs',
  'asset_id',
  'weight',
  'covariance_rows',
  'asset_i',
  'asset_j',
  'covariance'
);
```

## Technical Indicators And Microstructure

Compute indicators from rows already in DuckDB:

```sql
WITH prices(ts, close, high, low, volume) AS (
  VALUES
    (TIMESTAMP '2026-01-01 09:30:00', 100.0, 101.0,  99.5, 1000.0),
    (TIMESTAMP '2026-01-01 09:31:00', 101.0, 102.0, 100.5, 1200.0),
    (TIMESTAMP '2026-01-01 09:32:00', 100.5, 101.5, 100.0,  900.0)
)
SELECT
  fin_sma(close) AS sma,
  fin_rsi(close) AS rsi,
  fin_vwap(close, volume) AS vwap
FROM prices;
```

For tick-derived bars, load ticks into a table and use
`fin_tick_bars`, `fin_volume_bars`, `fin_dollar_bars`, or
`fin_imbalance_bars`.

## Calendars And Validation

Generate dates and validate common market-data rows:

```sql
SELECT *
FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');

SELECT
  fin_is_price(100.0) AS valid_price,
  fin_validate_ohlc(100.0, 102.0, 99.0, 101.0) AS valid_ohlc,
  fin_parse_day_count('ACT/365F') AS convention;
```

Use validation helpers at ingestion boundaries so invalid data fails early.

## Source Normalization

Normalize source-specific column names before applying analytics. These helpers
do not fetch vendor data; they reshape tables, views, or external-file scans
that are already queryable by DuckDB.

```sql
SELECT *
FROM fin_normalize_returns('raw_returns', 'trade_date', 'ticker', 'return_1d');

SELECT
  option_kind,
  fin_bsm_price(option_spec) AS model_price
FROM fin_normalize_option_chain(
  'raw_options',
  'cp',
  'underlying_px',
  'strike_px',
  'expiry_dt',
  'valuation_dt',
  'zero_rate',
  'iv',
  'q'
);
```

## Choosing Between Similar Functions

| Need | Prefer | Notes |
|---|---|---|
| Pairwise return from two prices | `fin_simple_return`, `fin_log_return` | Use before aggregating returns. |
| Aggregate total performance | `fin_total_return` | Takes return rows. |
| Option PV and basic Greeks | `fin_option_spec` with `fin_bsm_price`, `fin_bsm_delta`, `fin_bsm_gamma`, `fin_bsm_vega` | Prefer specs when a workflow reuses the same option inputs across multiple functions. |
| Implied volatility | `fin_bsm_implied_vol`, `fin_black76_implied_vol`, `fin_bachelier_implied_vol` | Match the pricing model. |
| Bond analytics | `fin_bond_price`, `fin_bond_ytm`, `fin_bond_duration`, `fin_bond_convexity` | Caller owns coupon, yield, maturity, frequency, face. |
| Portfolio frontier rows | `fin_efficient_frontier` | Table function, useful for examples and local diagnostics. |
