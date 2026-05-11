---
layout: default
title: Finance SQL Playbooks
description: Runnable DuckDB Finance workflows for desk-style analysis.
permalink: /playbooks/
nav_order: 8
wide: true
---

# Finance SQL Playbooks

These playbooks show complete SQL workflows using the `finance` extension. They
are written for quant developers, desk strategists, and finance users who want
local, inspectable analytics in DuckDB without an external pricing service.

The examples assume market inputs are already normalized. Rates and returns are
decimals, vols are annualized decimals, option `ttm` values are year fractions,
and currency labels are metadata unless a query explicitly performs FX pricing
or conversion.

For model and unit conventions, read the
[Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}) first.

Run the companion SQL file from a checkout of this repository after installing
and loading the published extension:

```sql
INSTALL finance FROM community;
LOAD finance;
.read examples/playbooks.sql
```

Until the community package is published, build and validate through the local
Makefile flow:

```sh
make debug DUCKDB_ROOT=/path/to/duckdb
make smoke DUCKDB_ROOT=/path/to/duckdb
```

The `.read examples/playbooks.sql` path is relative to the repository checkout
where the DuckDB shell is running.

## Playbook 1: Equity Option Desk Snapshot

Goal: price a small listed-option sheet, calculate PV and Greeks, and keep the
input specification visible as structured data.

```sql
CREATE OR REPLACE TEMP TABLE desk_options AS
SELECT * FROM (VALUES
  ('SPX_ATM_CALL', 'call', 'SPX', 100.0, 100.0, 1.00, 0.050, 0.200, 0.000, 10.0, 'USD'),
  ('SX5E_OTM_PUT', 'put', 'SX5E', 4100.0, 4200.0, 0.75, 0.025, 0.220, 0.015, 5.0, 'EUR')
) AS t(trade_id, kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency);

SELECT
  trade_id,
  underlier,
  currency,
  notional * fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield) AS price,
  notional * fin_bsm_delta(kind, spot, strike, ttm, rate, vol, dividend_yield) AS delta,
  notional * fin_bsm_gamma(spot, strike, ttm, rate, vol, dividend_yield) AS gamma,
  notional * fin_bsm_vega(kind, spot, strike, ttm, rate, vol, dividend_yield) AS vega
FROM desk_options
ORDER BY trade_id;
```

Desk note: the model inputs are explicit: spot, strike, year fraction, rate,
vol, dividend yield, notional, and currency. Reconcile the returned Vega unit
before mixing it with a vendor or desk risk report.

## Playbook 2: Cross-Asset Portfolio Rollup

Goal: combine locally priced equity, FX, rates, and credit rows into aggregate
portfolio PV and a caller-normalized risk column.

```sql
CREATE OR REPLACE TEMP TABLE portfolio_lines AS
SELECT * FROM (VALUES
  ('CROSS_ASSET', 'SPX_ATM_CALL', 'EqOption', 2.0, 10.450583572185565, 0.6368306511756191, 'USD'),
  ('CROSS_ASSET', 'EURUSD_PUT', 'FXOption', 1.0, 41552.14735205903, 0.0, 'USD'),
  ('CROSS_ASSET', 'USD_5Y_RECEIVE', 'IRSwap', 1.0, 22499.99999999999, -450.0, 'USD'),
  ('CROSS_ASSET', 'CDX_IG_CALL', 'CDIndexOption', 1.0, 2112.902425772036, 75.0, 'USD')
) AS t(portfolio_id, trade_name, instrument_type, quantity, value, risk, currency);

SELECT
  portfolio_id,
  sum(value * quantity) AS portfolio_value,
  sum(risk * quantity) AS portfolio_risk
FROM portfolio_lines
GROUP BY portfolio_id;
```

Desk note: this assumes the input risk column is already in a common unit such
as USD PnL under a named scenario, USD DV01, or another explicitly normalized
quantity.

## Playbook 3: Scenario PnL Explain

Goal: apply a market-data shock and compare full revaluation with a second-order
Taylor approximation.

```sql
WITH base AS (
  SELECT
    'call' AS kind,
    100.0 AS spot,
    100.0 AS strike,
    1.0 AS ttm,
    0.05 AS rate,
    0.20 AS vol,
    0.0 AS dividend_yield,
    0.05 AS spot_shock
),
shocked AS (
  SELECT
    *,
    spot * (1.0 + spot_shock) AS shocked_spot
  FROM base
)
SELECT
  fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield) AS base_price,
  fin_bsm_price(kind, shocked_spot, strike, ttm, rate, vol, dividend_yield) AS shocked_price,
  fin_bsm_price(kind, shocked_spot, strike, ttm, rate, vol, dividend_yield)
    - fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield) AS full_reval_pnl,
  fin_bsm_delta(kind, spot, strike, ttm, rate, vol, dividend_yield) * (shocked_spot - spot)
    + 0.5 * fin_bsm_gamma(spot, strike, ttm, rate, vol, dividend_yield)
      * (shocked_spot - spot) * (shocked_spot - spot) AS delta_gamma_pnl
FROM shocked;
```

Desk note: this is the standard local sanity check for whether a proposed shock
is small enough for delta-gamma explain. Large spot, vol, or rate moves should
be treated as full-revaluation scenarios.

## Playbook 4: Rates Curve Shift And Swap PV

Goal: apply a curve scenario to a par rate and revalue a simple receive-fixed
swap PV.

```sql
WITH swap_inputs AS (
  SELECT
    0.045 AS fixed_rate,
    0.040 AS par_rate,
    0.0005 AS parallel_shift,
    4.5 AS annuity,
    1000000.0 AS notional
)
SELECT
  par_rate AS base_par_rate,
  par_rate + parallel_shift AS shocked_par_rate,
  (fixed_rate - par_rate) * annuity * notional AS base_pv,
  (fixed_rate - (par_rate + parallel_shift)) * annuity * notional AS shocked_pv
FROM swap_inputs;
```

Desk note: this query shocks a scalar par rate. It does not rebuild an
interpolated discount curve, project cash flows, or apply day-count conventions.
Use it as a deterministic rates what-if, not as a replacement for a full rates
library.

## Playbook 5: Factor And Return Tear Sheet

Goal: calculate return, volatility, drawdown, and a compact factor report from a
small research table.

```sql
CREATE OR REPLACE TEMP TABLE research_returns AS
SELECT * FROM (VALUES
  (DATE '2026-01-02', 'AAA', 0.010, 1.0, 0.012),
  (DATE '2026-01-05', 'AAA', -0.020, 2.0, -0.018),
  (DATE '2026-01-06', 'AAA', 0.030, 3.0, 0.034),
  (DATE '2026-01-07', 'AAA', 0.015, 4.0, 0.020),
  (DATE '2026-01-08', 'AAA', -0.005, 5.0, 0.001)
) AS t(d, asset, r, factor, forward_return);

SELECT
  fin_total_return(r) AS total_return,
  fin_volatility(r) AS volatility,
  fin_sharpe(r) AS sharpe,
  fin_max_drawdown(r) AS max_drawdown
FROM research_returns;

SELECT *
FROM fin_factor_report('research_returns', 'd', 'asset', 'factor', 'forward_return', 5);
```

Quant note: this is a research plumbing check. The factor report is useful for
fast local diagnostics, while production factor research should pin universe
selection, winsorization, neutralization, lagging, and transaction-cost
assumptions explicitly.

## Playbook 6: Market Microstructure Bars

Goal: turn ticks into simple bars and compute spread/imbalance diagnostics.

```sql
CREATE OR REPLACE TEMP TABLE ticks AS
SELECT * FROM (VALUES
  (TIMESTAMP '2026-01-01 09:30:00', 100.00, 10.0,  99.95, 100.05, 500.0, 600.0),
  (TIMESTAMP '2026-01-01 09:30:01', 100.10, 20.0, 100.05, 100.15, 550.0, 450.0),
  (TIMESTAMP '2026-01-01 09:30:02',  99.90, 30.0,  99.85,  99.95, 400.0, 700.0)
) AS t(ts, price, volume, bid, ask, bid_size, ask_size);

SELECT
  ts,
  fin_mid(bid, ask) AS mid,
  fin_spread_bps(bid, ask) AS spread_bps,
  fin_order_imbalance(bid_size, ask_size) AS order_imbalance,
  fin_microprice(bid, bid_size, ask, ask_size) AS microprice
FROM ticks
ORDER BY ts;

SELECT *
FROM fin_tick_bars('ticks', 'ts', 'price', 2);
```

Microstructure note: these helpers are designed for local validation and simple
signal construction. For exchange-grade analysis, normalize timestamps, session
filters, quote conditions, trade corrections, and venue-specific rules before
calling the functions.
