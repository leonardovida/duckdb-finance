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

CREATE OR REPLACE TEMP TABLE gold_source_options(
  cp VARCHAR,
  underlying_px DOUBLE,
  strike_px DOUBLE,
  expiry_dt DATE,
  valuation_dt DATE,
  zero_rate DOUBLE,
  iv DOUBLE,
  q DOUBLE
);

INSERT INTO gold_source_options VALUES
  ('C', 100.0, 100.0, DATE '2027-01-01', DATE '2026-01-01', 0.05, 0.20, 0.00),
  ('P', 100.0,  95.0, DATE '2026-07-01', DATE '2026-01-01', 0.04, 0.25, 0.01);

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

CREATE OR REPLACE TEMP TABLE gold_weighted_returns(asset VARCHAR, weight DOUBLE, expected_return DOUBLE);
INSERT INTO gold_weighted_returns VALUES ('AAA', 0.60, 0.10), ('BBB', 0.40, 0.20);

CREATE OR REPLACE TEMP TABLE gold_covariance(asset_i VARCHAR, asset_j VARCHAR, covariance DOUBLE);
INSERT INTO gold_covariance VALUES
  ('AAA', 'AAA', 0.04),
  ('AAA', 'BBB', 0.01),
  ('BBB', 'AAA', 0.01),
  ('BBB', 'BBB', 0.09);
