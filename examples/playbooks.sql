-- DuckDB Finance playbook examples.
-- Run after loading the extension:
-- LOAD '/Users/leov/workspace/motherduck/duckdb/build/debug/extension/finance/finance.duckdb_extension';

CREATE OR REPLACE TEMP TABLE desk_options AS
SELECT * FROM (VALUES
  ('SPX_ATM_CALL', 'call', 'SPX', 100.0, 100.0, 1.00, 0.050, 0.200, 0.000, 10.0, 'USD'),
  ('SX5E_OTM_PUT', 'put', 'SX5E', 4100.0, 4200.0, 0.75, 0.025, 0.220, 0.015, 5.0, 'EUR')
) AS t(trade_id, kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency);

WITH instruments AS (
  SELECT
    trade_id,
    fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency) AS inst
  FROM desk_options
)
SELECT
  'equity_option_snapshot' AS playbook,
  trade_id,
  inst.underlier,
  inst.currency,
  round(fin_gsq_eq_option_price(inst), 6) AS price,
  round(fin_gsq_eq_delta(inst), 6) AS delta,
  round(fin_gsq_eq_gamma(inst), 9) AS gamma,
  round(fin_gsq_eq_vega(inst), 6) AS vega
FROM instruments
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
  round(fin_gsq_portfolio_value(value, quantity), 6) AS portfolio_value,
  round(fin_gsq_portfolio_risk(risk, quantity), 6) AS portfolio_risk
FROM portfolio_lines
GROUP BY portfolio_id;

WITH base AS (
  SELECT
    fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20, 0.0, 1.0, 'USD') AS inst,
    fin_gsq_market_data_shock('Proportional', 0.05) AS spot_shock
),
shocked AS (
  SELECT
    inst,
    inst.spot AS base_spot,
    fin_gsq_apply_shock(inst.spot, spot_shock) AS shocked_spot
  FROM base
)
SELECT
  'scenario_pnl_explain' AS playbook,
  round(fin_gsq_eq_option_price(inst), 6) AS base_price,
  round(
    fin_gsq_eq_option_price(fin_gsq_eq_option(inst.kind, inst.underlier, shocked_spot, inst.strike, inst.ttm, inst.rate, inst.vol, inst.dividend_yield, inst.notional, inst.currency)),
    6
  ) AS shocked_price,
  round(
    fin_gsq_scenario_pnl(
      fin_gsq_eq_option_price(inst),
      fin_gsq_eq_option_price(fin_gsq_eq_option(inst.kind, inst.underlier, shocked_spot, inst.strike, inst.ttm, inst.rate, inst.vol, inst.dividend_yield, inst.notional, inst.currency))
    ),
    6
  ) AS full_reval_pnl,
  round(fin_gsq_delta_gamma_pnl(fin_gsq_eq_delta(inst), fin_gsq_eq_gamma(inst), shocked_spot - base_spot), 6) AS delta_gamma_pnl
FROM shocked;

WITH scenario AS (
  SELECT fin_gsq_curve_scenario(5.0, 10.0, 0.0, 30.0, 15.0) AS shock
),
swap_inputs AS (
  SELECT
    0.045 AS fixed_rate,
    0.040 AS par_rate,
    4.5 AS annuity,
    1000000.0 AS notional
)
SELECT
  'rates_curve_shift' AS playbook,
  par_rate AS base_par_rate,
  fin_gsq_curve_scenario_rate(par_rate, 5.0, shock) AS shocked_par_rate,
  round(fin_gsq_ir_swap_price(fin_gsq_ir_swap('Receive', '5y', 'USD', fixed_rate, par_rate, annuity, notional)), 6) AS base_pv,
  round(
    fin_gsq_ir_swap_price(fin_gsq_ir_swap('Receive', '5y', 'USD', fixed_rate, fin_gsq_curve_scenario_rate(par_rate, 5.0, shock), annuity, notional)),
    6
  ) AS shocked_pv
FROM swap_inputs, scenario;

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
