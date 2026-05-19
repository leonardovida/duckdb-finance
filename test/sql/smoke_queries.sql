SELECT CASE WHEN starts_with(fin_version(), 'finance') THEN 1 ELSE CAST('fin_version failed' AS INTEGER) END;

SELECT
  round(fin_simple_return(105, 100), 6) AS simple_return,
  round(fin_total_return(r), 6) AS total_return,
  round(fin_volatility(r), 6) AS volatility,
  round(fin_sortino(r), 6) AS sortino,
  round(fin_iv_rank(r), 6) AS iv_rank
FROM (VALUES (0.01), (-0.02), (0.03), (0.015)) AS t(r);

SELECT
  round(fin_sortino(r, 0.01, 365.0), 6) AS sortino_annualized,
  round(fin_ewma_variance(r, 0.94, 365.0), 6) AS ewma_variance,
  round(fin_ewma_vol(r, 0.94, 365.0), 6) AS ewma_vol,
  round(fin_max_drawdown(r), 6) AS max_drawdown,
  fin_drawdown_duration(r) AS drawdown_duration,
  round(fin_ulcer_index(r), 6) AS ulcer_index,
  fin_outlier_count(r, 'zscore', 1.0) AS outlier_count
FROM (VALUES (0.01), (-0.02), (0.03), (0.015), (2.0)) AS t(r);

SELECT round(fin_quantile_spread(factor, fwd_return, 2), 6) AS quantile_spread
FROM (VALUES (1.0, 0.01), (2.0, -0.02), (3.0, 0.03), (4.0, 0.04)) AS t(factor, fwd_return);

SELECT
  round(fin_bsm_price('call', 100, 100, 1, 0.05, 0.2), 6) AS bsm_price,
  round((fin_bsm_greeks('call', 100, 100, 1, 0.05, 0.2)).delta, 6) AS delta,
  round(fin_bsm_implied_vol('call', fin_bsm_price('call', 100, 100, 1, 0.05, 0.2), 100, 100, 1, 0.05), 6) AS implied_vol,
  round(fin_black76_implied_vol('call', fin_black76_price('call', 100, 100, 1, 0.05, 0.2), 100, 100, 1, 0.05, 0.3, 1e-8), 6) AS black_iv,
  round(fin_bachelier_implied_vol('call', fin_bachelier_price('call', 100, 100, 1, 0.05, 5.0), 100, 100, 1, 0.05, 4.0, 1e-8), 6) AS bachelier_iv;

SELECT
  round(fin_bond_price(0.05, 0.04, 5, 2, 100), 6) AS bond_price,
  round(fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic'), 6) AS npv,
  round(fin_irr([-100.0, 60.0, 60.0]), 6) AS irr;

SELECT
  fin_equal_weights(3) AS equal_weights,
  fin_min_variance_weights([[0.04, 0.01], [0.01, 0.09]]) AS min_variance_weights,
  fin_inverse_vol_weights([0.2, 0.4]) AS inverse_vol_weights,
  round(fin_portfolio_sharpe([0.5, 0.5], [0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 0.02), 6) AS sharpe,
  fin_matrix_transpose([[1.0, 2.0], [3.0, 4.0]]) AS matrix_transpose,
  fin_matrix_is_psd([[1.0, 0.2], [0.2, 1.0]]) AS matrix_is_psd;

SELECT
  fin_validate_ohlc(10, 12, 9, 11).ok AS valid_ohlc,
  fin_parse_day_count('actual/365 fixed') AS day_count,
  fin_is_regular_session(TIMESTAMP '2026-05-06 10:00:00', 'NYSE') AS regular_session;

CREATE OR REPLACE TEMP TABLE option_inputs(kind VARCHAR, spot DOUBLE, strike DOUBLE, ttm DOUBLE, rate DOUBLE, vol DOUBLE);
INSERT INTO option_inputs VALUES ('call', 100, 100, 1, 0.05, 0.2), ('put', 100, 95, 0.5, 0.04, 0.25);
SELECT kind, round(model_price, 6) AS model_price, round(model_delta, 6) AS model_delta
FROM fin_option_chain('option_inputs', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol')
ORDER BY kind;

CREATE OR REPLACE TEMP TABLE curve(inst VARCHAR, mat DOUBLE, rate DOUBLE);
INSERT INTO curve VALUES ('bill', 0.5, 0.04), ('note', 1.0, 0.045), ('bond', 2.0, 0.05);
SELECT instrument, maturity, round(discount_factor, 6) AS discount_factor
FROM fin_bootstrap_curve('curve', 'inst', 'mat', 'rate')
ORDER BY maturity;
SELECT count(*) AS bootstrapped_with_convention
FROM fin_bootstrap_curve('curve', 'inst', 'mat', 'rate', 'continuous');

CREATE OR REPLACE TEMP TABLE factor_inputs(d DATE, asset VARCHAR, factor DOUBLE, ret DOUBLE);
INSERT INTO factor_inputs VALUES
  (DATE '2026-01-01', 'A', 1.0, 0.01),
  (DATE '2026-01-01', 'B', 2.0, 0.02),
  (DATE '2026-01-02', 'A', 1.5, 0.015),
  (DATE '2026-01-02', 'B', 0.5, -0.005);
SELECT round(ic, 6) AS ic, round(mean_return, 6) AS mean_return, round(quantile_spread, 6) AS quantile_spread
FROM fin_factor_report('factor_inputs', 'd', 'asset', 'factor', 'ret', 2);
SELECT p, q, round(annualized_vol, 6) AS annualized_vol
FROM fin_garch_fit('factor_inputs', 'ret', 1, 1, 'normal');

SELECT * FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-06');
SELECT count(*) AS default_calendar_rows FROM fin_calendar('weekday');
SELECT * FROM fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]]);
SELECT * FROM fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]], ['A', 'B'], 'single');
SELECT * FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 3);
SELECT count(*) AS default_frontier_points
FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]]);
SELECT * FROM fin_portfolio_optimize([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 'max_sharpe', 0.0, true, 0.0, 1.0, 0.12, 0.2, 1.0);

CREATE OR REPLACE TEMP TABLE ticks(ts TIMESTAMP, price DOUBLE, volume DOUBLE);
INSERT INTO ticks VALUES
  (TIMESTAMP '2026-01-01 09:30:00', 100, 10),
  (TIMESTAMP '2026-01-01 09:30:01', 101, 20),
  (TIMESTAMP '2026-01-01 09:30:02', 99, 30);
SELECT count(*) AS tick_bar_count FROM fin_tick_bars('ticks', 'ts', 'price');
SELECT count(*) AS imbalance_bar_count FROM fin_imbalance_bars('ticks', 'ts', 'price', 'volume', 'signed');

CREATE OR REPLACE TEMP TABLE grid_inputs(ts TIMESTAMP, value DOUBLE);
INSERT INTO grid_inputs VALUES
  (TIMESTAMP '2026-01-01 09:30:00', 10),
  (TIMESTAMP '2026-01-01 09:30:02', 12);
SELECT count(*) AS grid_count
FROM fin_resample_grid(
  'grid_inputs', 'ts', 'value',
  TIMESTAMP '2026-01-01 09:30:00',
  TIMESTAMP '2026-01-01 09:30:02',
  INTERVAL '1 second',
  'last',
  INTERVAL '1 minute'
);
