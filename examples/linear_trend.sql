-- Load the locally built finance extension before running this example.
-- Requires the explicit-axis fin_linear_trend implementation, not v0.2.17.
-- Synthetic daily prices. Use elapsed calendar days rather than row order so
-- missing dates retain their meaning. Slope is price units per calendar day.
WITH prices(symbol, day, close) AS (
  VALUES ('A', DATE '2026-01-01', 100.0),
         ('A', DATE '2026-01-02', 102.0),
         ('A', DATE '2026-01-04', 106.0),
         ('B', DATE '2026-01-01', 50.0),
         ('B', DATE '2026-01-02', 49.0),
         ('B', DATE '2026-01-04', 47.0)
), reports AS (
  SELECT symbol,
         fin_linear_trend(close, x := date_diff('day', DATE '2026-01-01', day)) AS trend
  FROM prices
  GROUP BY symbol
)
SELECT symbol, trend.slope AS price_per_day, trend.intercept AS price_at_origin,
       trend.r2, trend.stderr AS slope_standard_error
FROM reports
ORDER BY symbol;
-- Expected A: 2, 100, 1, 0. Expected B: -1, 50, 1, 0 (within rounding).
-- This descriptive fit is not a forecast or a stationarity test.
