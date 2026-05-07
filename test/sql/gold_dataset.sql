CREATE OR REPLACE TEMP TABLE gold_returns(
  seq INTEGER,
  d DATE,
  asset VARCHAR,
  r DOUBLE,
  benchmark_r DOUBLE,
  factor DOUBLE,
  forward_return DOUBLE
);

INSERT INTO gold_returns VALUES
  (1, DATE '2026-01-02', 'AAA',  0.010000000000,  0.008000000000, 1.0,  0.012000000000),
  (2, DATE '2026-01-05', 'AAA', -0.020000000000, -0.010000000000, 2.0, -0.018000000000),
  (3, DATE '2026-01-06', 'AAA',  0.030000000000,  0.020000000000, 3.0,  0.034000000000),
  (4, DATE '2026-01-07', 'AAA',  0.015000000000,  0.012000000000, 4.0,  0.020000000000),
  (5, DATE '2026-01-08', 'AAA', -0.005000000000,  0.004000000000, 5.0,  0.001000000000);

CREATE OR REPLACE TEMP TABLE gold_prices(
  seq INTEGER,
  ts TIMESTAMP,
  open DOUBLE,
  high DOUBLE,
  low DOUBLE,
  close DOUBLE,
  volume DOUBLE,
  bid DOUBLE,
  ask DOUBLE,
  bid_size DOUBLE,
  ask_size DOUBLE
);

INSERT INTO gold_prices VALUES
  (1, TIMESTAMP '2026-01-02 09:30:00', 100.0, 101.0,  99.0, 100.0, 1000.0,  99.90, 100.10, 500.0, 600.0),
  (2, TIMESTAMP '2026-01-02 09:31:00', 100.0, 103.0,  99.5, 102.0, 1500.0, 101.90, 102.10, 550.0, 450.0),
  (3, TIMESTAMP '2026-01-02 09:32:00', 102.0, 102.5,  98.5,  99.0, 2000.0,  98.90,  99.10, 400.0, 700.0),
  (4, TIMESTAMP '2026-01-02 09:33:00',  99.0, 105.0,  98.0, 104.0, 1800.0, 103.90, 104.10, 800.0, 500.0),
  (5, TIMESTAMP '2026-01-02 09:34:00', 104.0, 104.5, 102.0, 103.0, 1200.0, 102.90, 103.10, 450.0, 550.0);

CREATE OR REPLACE TEMP TABLE gold_options(
  kind VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  vol DOUBLE,
  dividend_yield DOUBLE
);

INSERT INTO gold_options VALUES
  ('call', 100.0, 100.0, 1.0, 0.05, 0.20, 0.00),
  ('put',  100.0,  95.0, 0.5, 0.04, 0.25, 0.01);

-- Goldman Sachs GS Quant-inspired pricing and risk golden cases.
-- These fixtures mirror the instrument families, measure names, context fields,
-- scenario forms, and portfolio aggregation patterns documented by GS Quant,
-- while keeping all expected values deterministic and local to DuckDB Finance.
CREATE OR REPLACE TEMP TABLE gsq_goldman_eq_option_cases(
  case_id VARCHAR,
  kind VARCHAR,
  underlier VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  vol DOUBLE,
  dividend_yield DOUBLE,
  notional DOUBLE,
  currency VARCHAR,
  expected_price DOUBLE,
  expected_delta DOUBLE,
  expected_gamma DOUBLE,
  expected_vega DOUBLE
);

INSERT INTO gsq_goldman_eq_option_cases VALUES
  ('GSQ_EQ_SPX_ATM_CALL', 'call', 'SPX', 100.0, 100.0, 1.0, 0.050, 0.20, 0.000, 1.0, 'USD',
    10.450583572185565, 0.6368306511756191, 0.018762017345846895, 37.52403469169379),
  ('GSQ_EQ_SX5E_PUT', 'put', 'SX5E', 4100.0, 4200.0, 0.75, 0.025, 0.22, 0.015, 10.0, 'EUR',
    3453.56772974947, -4.9119224520254345, 0.005049782424081444, 14006.329020553494),
  ('GSQ_EQ_NDX_ITM_CALL', 'call', 'NDX', 15000.0, 14500.0, 0.25, 0.045, 0.18, 0.005, 2.0, 'USD',
    1818.4790324620405, 1.4040683347127816, 0.0005121789460364343, 5185.811828618897);

CREATE OR REPLACE TEMP TABLE gsq_goldman_fx_forward_cases(
  case_id VARCHAR,
  pair VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  domestic_rate DOUBLE,
  foreign_rate DOUBLE,
  notional DOUBLE,
  currency VARCHAR,
  expected_value DOUBLE
);

INSERT INTO gsq_goldman_fx_forward_cases VALUES
  ('GSQ_FX_EURUSD_FWD', 'EURUSD', 1.10, 1.12, 0.50, 0.040, 0.020, 1000000.0, 'USD',
    -8767.696979481214),
  ('GSQ_FX_USDJPY_FWD', 'USDJPY', 145.0, 144.0, 0.25, 0.015, 0.001, 500000.0, 'JPY',
    751371.6476558978);

CREATE OR REPLACE TEMP TABLE gsq_goldman_fx_option_cases(
  case_id VARCHAR,
  kind VARCHAR,
  pair VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  domestic_rate DOUBLE,
  foreign_rate DOUBLE,
  vol DOUBLE,
  notional DOUBLE,
  currency VARCHAR,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_fx_option_cases VALUES
  ('GSQ_FX_EURUSD_PUT', 'put', 'EURUSD', 1.10, 1.12, 0.50, 0.040, 0.020, 0.12, 1000000.0, 'USD',
    41552.14735205903),
  ('GSQ_FX_GBPUSD_CALL', 'call', 'GBPUSD', 1.28, 1.30, 0.75, 0.035, 0.025, 0.11, 750000.0, 'USD',
    32277.670648152547);

CREATE OR REPLACE TEMP TABLE gsq_goldman_fx_binary_cases(
  case_id VARCHAR,
  kind VARCHAR,
  pair VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  domestic_rate DOUBLE,
  foreign_rate DOUBLE,
  vol DOUBLE,
  payout DOUBLE,
  currency VARCHAR,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_fx_binary_cases VALUES
  ('GSQ_FX_EURUSD_DIGITAL_CALL', 'call', 'EURUSD', 1.10, 1.12, 0.50, 0.040, 0.020, 0.12, 1000000.0, 'USD',
    436722.50089038245);

CREATE OR REPLACE TEMP TABLE gsq_goldman_ir_swap_cases(
  case_id VARCHAR,
  pay_receive VARCHAR,
  tenor VARCHAR,
  currency VARCHAR,
  fixed_rate DOUBLE,
  par_rate DOUBLE,
  annuity DOUBLE,
  notional DOUBLE,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_ir_swap_cases VALUES
  ('GSQ_IR_USD_5Y_RECEIVE', 'Receive', '5y', 'USD', 0.045, 0.040, 4.5, 1000000.0,
    22499.99999999999),
  ('GSQ_IR_EUR_10Y_PAY', 'Pay', '10y', 'EUR', 0.030, 0.033, 8.7, 2000000.0,
    52200.000000000044);

CREATE OR REPLACE TEMP TABLE gsq_goldman_ir_swaption_cases(
  case_id VARCHAR,
  pay_receive VARCHAR,
  expiration VARCHAR,
  tenor VARCHAR,
  currency VARCHAR,
  forward_rate DOUBLE,
  strike DOUBLE,
  annuity DOUBLE,
  vol DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  notional DOUBLE,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_ir_swaption_cases VALUES
  ('GSQ_IR_USD_3M5Y_PAY_SWAPTION', 'Pay', '3m', '5y', 'USD', 0.040, 0.042, 4.5, 0.20, 0.25, 0.030, 1000000.0,
    3687.474420086758);

CREATE OR REPLACE TEMP TABLE gsq_goldman_ir_cap_floor_cases(
  case_id VARCHAR,
  kind VARCHAR,
  currency VARCHAR,
  forward_rate DOUBLE,
  strike DOUBLE,
  annuity DOUBLE,
  vol DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  notional DOUBLE,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_ir_cap_floor_cases VALUES
  ('GSQ_IR_USD_CAPLET', 'cap', 'USD', 0.040, 0.035, 0.5, 0.20, 0.5, 0.030, 1000000.0,
    2703.6245802358944),
  ('GSQ_IR_USD_FLOORLET', 'floor', 'USD', 0.030, 0.035, 0.5, 0.22, 0.5, 0.030, 1000000.0,
    2672.843158711786);

CREATE OR REPLACE TEMP TABLE gsq_goldman_inflation_swap_cases(
  case_id VARCHAR,
  currency VARCHAR,
  fixed_rate DOUBLE,
  inflation_rate DOUBLE,
  annuity DOUBLE,
  notional DOUBLE,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_inflation_swap_cases VALUES
  ('GSQ_INFL_USD_5Y', 'USD', 0.025, 0.030, 5.0, 1000000.0,
    24999.99999999999);

CREATE OR REPLACE TEMP TABLE gsq_goldman_cd_index_option_cases(
  case_id VARCHAR,
  kind VARCHAR,
  index_name VARCHAR,
  forward_spread DOUBLE,
  strike_spread DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  vol DOUBLE,
  risky_annuity DOUBLE,
  notional DOUBLE,
  currency VARCHAR,
  expected_price DOUBLE
);

INSERT INTO gsq_goldman_cd_index_option_cases VALUES
  ('GSQ_CDX_IG_CALL', 'call', 'CDX.NA.IG', 0.0075, 0.0080, 0.50, 0.040, 0.35, 4.0, 1000000.0, 'USD',
    2112.902425772036);

CREATE OR REPLACE TEMP TABLE gsq_goldman_shock_cases(
  case_id VARCHAR,
  shock_type VARCHAR,
  base_value DOUBLE,
  shock_value DOUBLE,
  stddev DOUBLE,
  expected_value DOUBLE
);

INSERT INTO gsq_goldman_shock_cases VALUES
  ('GSQ_SCENARIO_IR_VOL_ABSOLUTE_1BP', 'Absolute', 0.2000, 0.0001, NULL, 0.2001),
  ('GSQ_SCENARIO_EQ_SPOT_PROPORTIONAL_5PCT', 'Proportional', 100.0, 0.05, NULL, 105.0),
  ('GSQ_SCENARIO_OVERRIDE_MARK', 'Override', 100.0, 99.0, NULL, 99.0),
  ('GSQ_SCENARIO_STDDEV_MOVE', 'StdDev', 100.0, -2.0, 1.5, 97.0);

CREATE OR REPLACE TEMP TABLE gsq_goldman_curve_scenario_cases(
  case_id VARCHAR,
  base_rate DOUBLE,
  tenor DOUBLE,
  parallel_shift_bps DOUBLE,
  curve_shift_bps DOUBLE,
  tenor_start DOUBLE,
  tenor_end DOUBLE,
  pivot_point DOUBLE,
  expected_rate DOUBLE
);

INSERT INTO gsq_goldman_curve_scenario_cases VALUES
  ('GSQ_CURVE_PARALLEL_5BP_AT_5Y', 0.0400, 5.0, 5.0, 0.0, 0.0, 30.0, 15.0, 0.0405),
  ('GSQ_CURVE_STEEPER_10BP_30Y', 0.0350, 30.0, 0.0, 10.0, 0.0, 30.0, 15.0, 0.0355),
  ('GSQ_CURVE_FLATTER_NEG_8BP_2Y', 0.0300, 2.0, 0.0, -8.0, 0.0, 30.0, 15.0, 0.030346666666666666);

CREATE OR REPLACE TEMP TABLE gsq_goldman_portfolio_cases(
  portfolio_id VARCHAR,
  trade_name VARCHAR,
  instrument_type VARCHAR,
  quantity DOUBLE,
  value DOUBLE,
  risk DOUBLE,
  currency VARCHAR
);

INSERT INTO gsq_goldman_portfolio_cases VALUES
  ('GSQ_PORTFOLIO_RATE_VOL', 'EUR3m5y', 'IRSwaption', 1.0, 3687.474420086758, -293.405359, 'EUR'),
  ('GSQ_PORTFOLIO_RATE_VOL', 'EUR6m5y', 'IRSwaption', 1.0, 3650.000000000000, -296.666754, 'EUR'),
  ('GSQ_PORTFOLIO_CROSS_ASSET', 'SPX_ATM_CALL', 'EqOption', 2.0, 10.450583572185565, 0.6368306511756191, 'USD'),
  ('GSQ_PORTFOLIO_CROSS_ASSET', 'EURUSD_PUT', 'FXOption', 1.0, 41552.14735205903, 0.0, 'USD');

CREATE OR REPLACE TEMP TABLE gsq_goldman_portfolio_expected(
  portfolio_id VARCHAR,
  expected_value DOUBLE,
  expected_risk DOUBLE
);

INSERT INTO gsq_goldman_portfolio_expected VALUES
  ('GSQ_PORTFOLIO_RATE_VOL', 7337.474420086758, -590.072113),
  ('GSQ_PORTFOLIO_CROSS_ASSET', 41573.048519203404, 1.2736613023512382);

CREATE OR REPLACE TEMP TABLE gold_curve(
  inst VARCHAR,
  maturity DOUBLE,
  rate DOUBLE
);

INSERT INTO gold_curve VALUES
  ('bill', 0.5, 0.040),
  ('note', 1.0, 0.045),
  ('bond', 2.0, 0.050);

CREATE OR REPLACE TEMP TABLE gold_current_weights(asset VARCHAR, weight DOUBLE);
INSERT INTO gold_current_weights VALUES ('AAA', 0.60), ('BBB', 0.40);

CREATE OR REPLACE TEMP TABLE gold_target_weights(asset VARCHAR, weight DOUBLE);
INSERT INTO gold_target_weights VALUES ('AAA', 0.50), ('BBB', 0.50);

CREATE OR REPLACE TEMP TABLE gold_asset_prices(asset VARCHAR, price DOUBLE);
INSERT INTO gold_asset_prices VALUES ('AAA', 100.0), ('BBB', 50.0);
