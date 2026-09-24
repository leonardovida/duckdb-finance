-- Load the locally built finance extension first. Requires post-v0.2.17 code.
-- Large absolute levels can obscure small changes in DOUBLE regression.
-- Synthetic series with representable quarter-unit noise and known slope 2.
WITH observations AS (
  SELECT symbol, level + i::DOUBLE AS x,
         level + 2 * i::DOUBLE + CASE WHEN i % 2 = 0 THEN 0.25 ELSE -0.25 END AS y
  FROM (VALUES ('A', 1e15), ('B', 1e12)) series(symbol, level), range(1, 102) t(i)
), valid AS (
  -- Select origins from the same finite pairs used by the regression.
  SELECT * FROM observations WHERE isfinite(x) AND isfinite(y)
), centered AS (
  SELECT *, min(x) OVER (PARTITION BY symbol) AS x_origin,
            min(y) OVER (PARTITION BY symbol) AS y_origin
  FROM valid
), fits AS (
  SELECT symbol, x_origin, y_origin,
         fin_linear_trend(y - y_origin, x := x - x_origin) AS trend
  FROM centered
  GROUP BY symbol, x_origin, y_origin
)
SELECT symbol, x_origin, y_origin, trend.slope,
       trend.intercept AS y_change_at_x_origin, trend.r2, trend.stderr
FROM fits ORDER BY symbol;
-- Both slopes: 2. Both slope standard errors: approximately 0.000861770574038108.
-- Prediction: y_origin + y_change_at_x_origin + slope * (x_new - x_origin).
-- Keep origins with the fit. Its intercept is in shifted coordinates.
-- Centering cannot recover detail already lost when inputs were cast to DOUBLE,
-- and does not eliminate residual-variance cancellation for nearly perfect fits.
