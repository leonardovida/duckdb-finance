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

-- Deterministic 64-row sample for statistical tests and series diagnostics.
-- Rows are stored in a scrambled order so ordered statistics must use the
-- explicit ordering key i. ar is an AR(1) (phi 0.7) driven by e.
CREATE OR REPLACE TEMP TABLE gold_stats AS
WITH base AS (
  SELECT i, sin(1.7 * i) + 0.5 * cos(0.37 * i * i) AS x, sin(0.77 * i * i + 0.3) AS e,
         cos(0.9 * i) AS f1, sin(0.45 * i + 1) AS f2
  FROM range(64) t(i)
)
SELECT i, x,
       CASE WHEN i % 5 = 0 THEN round(0.4 * x + cos(2.3 * i), 1) ELSE 0.4 * x + cos(2.3 * i) END AS y,
       pow(0.7, i) * sum(pow(0.7, -i) * e) OVER (ORDER BY i) AS ar,
       i % 3 AS g, CASE WHEN i % 4 = 0 THEN i % 3 ELSE (i * i) % 4 END AS h, f1, f2,
       0.5 + 1.2 * f1 - 0.7 * f2 + 0.3 * sin(3.7 * i) AS oy
FROM base
ORDER BY (i * 37) % 64;

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

-- Deterministic GARCH(1,1) path (omega 1e-5, alpha 0.1, beta 0.85) driven by a
-- chirp innovation, stored in scrambled order; t is the ordering key.
CREATE OR REPLACE TEMP TABLE gold_garch AS
WITH RECURSIVE g(t, h, r) AS (
  SELECT 0, 0.0001::DOUBLE, sqrt(0.0001) * sqrt(2.0) * sin(0.3)
  UNION ALL
  SELECT t + 1, 0.00001 + 0.1 * r * r + 0.85 * h,
         sqrt(0.00001 + 0.1 * r * r + 0.85 * h) * sqrt(2.0) * sin(0.77 * (t + 1) * (t + 1) + 0.3)
  FROM g WHERE t < 299
)
SELECT t, r FROM g ORDER BY (t * 37) % 300;
