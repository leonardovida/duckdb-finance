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

-- 60 deterministic OHLC bars for the TA-Lib technical indicator references in gold_tests.sql.
CREATE OR REPLACE TEMP TABLE gold_bars(i INTEGER, high DOUBLE, low DOUBLE, close DOUBLE);

INSERT INTO gold_bars VALUES
  (0, 101.40, 100.00, 100.80),
  (1, 102.71, 101.03, 101.72),
  (2, 103.23, 101.85, 102.42),
  (3, 104.29, 102.64, 103.41),
  (4, 102.36, 100.64, 101.41),
  (5, 99.09, 97.84, 98.40),
  (6, 99.00, 97.31, 98.00),
  (7, 98.73, 97.20, 98.00),
  (8, 98.74, 97.13, 97.81),
  (9, 101.26, 99.79, 100.36),
  (10, 104.03, 102.49, 103.26),
  (11, 104.14, 102.38, 103.15),
  (12, 103.25, 102.05, 102.61),
  (13, 103.30, 101.64, 102.33),
  (14, 100.52, 98.88, 99.68),
  (15, 98.17, 96.65, 97.33),
  (16, 99.25, 97.70, 98.28),
  (17, 100.14, 98.72, 99.50),
  (18, 101.24, 99.49, 100.25),
  (19, 103.71, 102.39, 102.94),
  (20, 105.65, 104.04, 104.74),
  (21, 105.65, 104.04, 104.74),
  (22, 105.65, 104.04, 104.74),
  (23, 101.77, 100.19, 100.77),
  (24, 99.19, 97.72, 98.50),
  (25, 98.53, 96.82, 97.58),
  (26, 100.87, 99.45, 100.00),
  (27, 102.72, 101.21, 101.91),
  (28, 103.65, 101.86, 102.66),
  (29, 105.13, 103.86, 104.53),
  (30, 105.72, 104.14, 104.73),
  (31, 102.66, 101.07, 101.85),
  (32, 100.93, 99.29, 100.05),
  (33, 100.71, 99.22, 99.76),
  (34, 99.32, 97.92, 98.63),
  (35, 100.28, 98.48, 99.28),
  (36, 103.34, 101.94, 102.61),
  (37, 105.16, 103.64, 104.23),
  (38, 104.99, 103.31, 104.09),
  (39, 105.42, 103.89, 104.65),
  (40, 104.99, 102.93, 103.47),
  (41, 100.81, 99.46, 100.17),
  (42, 100.12, 98.35, 99.15),
  (43, 100.89, 99.39, 100.05),
  (44, 101.03, 99.59, 100.19),
  (45, 102.85, 101.10, 101.88),
  (46, 105.73, 104.34, 105.09),
  (47, 106.52, 105.00, 105.53),
  (48, 104.83, 103.35, 104.06),
  (49, 104.45, 102.74, 103.54),
  (50, 102.73, 101.14, 101.80),
  (51, 99.84, 98.51, 99.11),
  (52, 100.58, 98.80, 99.58),
  (53, 102.44, 101.00, 101.75),
  (54, 103.57, 102.09, 102.62),
  (55, 105.23, 103.64, 104.36),
  (56, 107.34, 105.73, 106.53),
  (57, 106.33, 104.69, 105.34),
  (58, 103.44, 102.23, 102.84),
  (59, 103.04, 101.26, 102.05);

-- gold_bars with deterministic opens, volumes, signed volumes and irregular
-- timestamps for the volume, directional and microstructure indicators.
CREATE OR REPLACE TEMP TABLE gold_vbars AS
SELECT i, low + (high - low) * ((i * 7) % 10) / 10.0 AS open, high, low, close,
  1000.0 + ((i * 37) % 11) * 100.0 AS volume,
  (1000.0 + ((i * 37) % 11) * 100.0) * (((i * 5) % 7) / 3.0 - 1.0) AS signed_volume,
  TIMESTAMP '2026-01-02 09:30:00' + to_seconds(i * 60 + (i % 4) * 17) AS ts
FROM gold_bars;

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

CREATE OR REPLACE TEMP TABLE gold_factor_panel(d INTEGER, asset VARCHAR, factor DOUBLE, fwd DOUBLE);
INSERT INTO gold_factor_panel VALUES
  (1, 'A', 1.0, 0.010), (1, 'B', 2.0, 0.030), (1, 'C', 3.0, 0.020), (1, 'D', 4.0, 0.050),
  (2, 'A', 4.0, 0.040), (2, 'B', 3.0, -0.010), (2, 'C', 2.0, 0.000), (2, 'D', 1.0, -0.020),
  (3, 'A', 2.0, 0.015), (3, 'B', 2.0, 0.005), (3, 'C', 5.0, 0.030), (3, 'D', 1.0, -0.010);

-- Two assets with an exact duplicate timestamp, for bar/grid determinism checks.
CREATE OR REPLACE TEMP TABLE gold_ticks(sym VARCHAR, seq INTEGER, ts TIMESTAMP, price DOUBLE, volume DOUBLE, signed_volume DOUBLE);
INSERT INTO gold_ticks VALUES
  ('X', 1, TIMESTAMP '2026-01-02 09:30:00', 10.0, 10.0, 10.0),
  ('X', 2, TIMESTAMP '2026-01-02 09:30:01', 12.0, 20.0, 20.0),
  ('X', 3, TIMESTAMP '2026-01-02 09:30:01', 11.0, 5.0, -5.0),
  ('X', 4, TIMESTAMP '2026-01-02 09:30:03', 11.5, 40.0, -40.0),
  ('X', 5, TIMESTAMP '2026-01-02 09:30:04', 11.0, 5.0, 5.0),
  ('Y', 1, TIMESTAMP '2026-01-02 09:30:00', 50.0, 1.0, 1.0),
  ('Y', 2, TIMESTAMP '2026-01-02 09:30:02', 49.0, 2.0, -2.0),
  ('Y', 3, TIMESTAMP '2026-01-02 09:30:04', 51.0, 3.0, 3.0);
