-- DuckDB Finance playbook examples.
-- Run from a repository checkout after loading the extension.

CREATE OR REPLACE TEMP TABLE desk_options AS
SELECT * FROM (VALUES
  ('SPX_ATM_CALL', 'call', 'SPX', 100.0, 100.0, 1.00, 0.050, 0.200, 0.000, 10.0, 'USD'),
  ('SX5E_OTM_PUT', 'put', 'SX5E', 4100.0, 4200.0, 0.75, 0.025, 0.220, 0.015, 5.0, 'EUR')
) AS t(trade_id, kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency);

SELECT
  'equity_option_snapshot' AS playbook,
  trade_id,
  underlier,
  currency,
  round(notional * fin_bsm_price(option_spec), 6) AS model_price,
  round(notional * fin_bsm_delta(option_spec), 6) AS model_delta,
  round(notional * fin_bsm_gamma(option_spec), 9) AS model_gamma,
  round(notional * fin_bsm_vega(option_spec), 6) AS model_vega
FROM (
  SELECT *, fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield) AS option_spec
  FROM desk_options
)
ORDER BY trade_id;

CREATE OR REPLACE TEMP TABLE portfolio_lines AS
SELECT * FROM (VALUES
  ('CROSS_ASSET', 'SPX_ATM_CALL', 'EqOption', 2.0, 10.450583572185565, 0.6368306511756191, 'USD'),
  ('CROSS_ASSET', 'EURUSD_PUT', 'FXOption', 1.0, 41552.14735205903, 0.0, 'USD'),
  ('CROSS_ASSET', 'USD_5Y_RECEIVE', 'IRSwap', 1.0, 22499.99999999999, -450.0, 'USD'),
  ('CROSS_ASSET', 'CDX_IG_CALL', 'CDIndexOption', 1.0, 2112.902425772036, 75.0, 'USD')
) AS t(portfolio_id, trade_name, instrument_type, quantity, value, risk, currency);

SELECT
  'cross_asset_portfolio_rollup' AS playbook,
  portfolio_id,
  round(sum(value * quantity), 6) AS portfolio_value,
  round(sum(risk * quantity), 6) AS portfolio_risk
FROM portfolio_lines
GROUP BY portfolio_id;

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
  'scenario_pnl_explain' AS playbook,
  round(fin_bsm_price(fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield)), 6) AS base_price,
  round(fin_bsm_price(fin_option_spec(kind, shocked_spot, strike, ttm, rate, vol, dividend_yield)), 6) AS shocked_price,
  round(fin_bsm_price(fin_option_spec(kind, shocked_spot, strike, ttm, rate, vol, dividend_yield)) - fin_bsm_price(fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield)), 6) AS full_reval_pnl,
  round(
    fin_bsm_delta(fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield)) * (shocked_spot - spot)
      + 0.5 * fin_bsm_gamma(fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield)) * (shocked_spot - spot) * (shocked_spot - spot),
    6
  ) AS delta_gamma_pnl
FROM shocked;

WITH swap_inputs AS (
  SELECT
    0.045 AS fixed_rate,
    0.040 AS par_rate,
    0.0005 AS parallel_shift,
    4.5 AS annuity,
    1000000.0 AS notional
)
SELECT
  'rates_curve_shift' AS playbook,
  par_rate AS base_par_rate,
  par_rate + parallel_shift AS shocked_par_rate,
  round((fixed_rate - par_rate) * annuity * notional, 6) AS base_pv,
  round((fixed_rate - (par_rate + parallel_shift)) * annuity * notional, 6) AS shocked_pv
FROM swap_inputs;

CREATE OR REPLACE TEMP TABLE research_returns AS
SELECT * FROM (VALUES
  (DATE '2026-01-02', 'AAA', 0.010, 1.0, 0.012),
  (DATE '2026-01-05', 'AAA', -0.020, 2.0, -0.018),
  (DATE '2026-01-06', 'AAA', 0.030, 3.0, 0.034),
  (DATE '2026-01-07', 'AAA', 0.015, 4.0, 0.020),
  (DATE '2026-01-08', 'AAA', -0.005, 5.0, 0.001)
) AS t(d, asset, r, factor, forward_return);

SELECT
  'factor_return_tear_sheet' AS playbook,
  round(fin_total_return(r), 6) AS total_return,
  round(fin_volatility(r), 6) AS volatility,
  round(fin_sharpe(r), 6) AS sharpe,
  round(fin_max_drawdown(r), 6) AS max_drawdown
FROM research_returns;

SELECT
  'factor_report' AS playbook,
  round(ic, 6) AS ic,
  round(mean_return, 6) AS mean_return,
  round(quantile_spread, 6) AS quantile_spread
FROM fin_factor_report('research_returns', 'd', 'asset', 'factor', 'forward_return', 5);

CREATE OR REPLACE TEMP TABLE ticks AS
SELECT * FROM (VALUES
  (TIMESTAMP '2026-01-01 09:30:00', 100.00, 10.0,  99.95, 100.05, 500.0, 600.0),
  (TIMESTAMP '2026-01-01 09:30:01', 100.10, 20.0, 100.05, 100.15, 550.0, 450.0),
  (TIMESTAMP '2026-01-01 09:30:02',  99.90, 30.0,  99.85,  99.95, 400.0, 700.0)
) AS t(ts, price, volume, bid, ask, bid_size, ask_size);

SELECT
  'microstructure_diagnostics' AS playbook,
  ts,
  round(fin_mid(bid, ask), 6) AS mid,
  round(fin_spread_bps(bid, ask), 6) AS spread_bps,
  round(fin_order_imbalance(bid_size, ask_size), 6) AS order_imbalance,
  round(fin_microprice(bid, bid_size, ask, ask_size), 6) AS microprice
FROM ticks
ORDER BY ts;

SELECT
  'tick_bars' AS playbook,
  *
FROM fin_tick_bars('ticks', 'ts', 'price', 2);
