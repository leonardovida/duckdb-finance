-- Executed immediately after examples/pairwise_covariance.sql in one connection.
CREATE OR REPLACE TEMP MACRO covariance_assert(ok) AS
  CASE WHEN coalesce(ok, false) THEN true ELSE error('covariance workflow assertion failed') END;

SELECT covariance_assert(count(*) = 16 AND count(*) FILTER (WHERE n_obs < 2) = 7
  AND count(*) FILTER (WHERE n_obs < 2 AND covariance IS NOT NULL) = 0)
FROM pairwise_covariance;

SELECT covariance_assert(n_obs = 3 AND abs(covariance - 0.0001) < 1e-15)
FROM pairwise_covariance WHERE asset_i = 'AAA' AND asset_j = 'CCC';

SELECT covariance_assert(NOT fin_matrix_is_psd(m.matrix, 1e-10))
FROM (SELECT fin_cov_matrix(date, asset_id, return_decimal) AS m FROM selected_finite_returns);

-- Independent exact reference: the two complete return vectors differ by
-- [0.01, 0.02, -0.02]; sample covariance is their outer product divided by 2.
WITH expected AS (
  SELECT [[0.00005, 0.0001, -0.0001], [0.0001, 0.0002, -0.0002],
          [-0.0001, -0.0002, 0.0002]] AS m
)
SELECT covariance_assert(count(*) = 9 AND max(abs(c.covariance - m[i][j])) < 1e-15
  AND min(n_obs) = 2 AND max(n_obs) = 2)
FROM complete_covariance c, expected,
     (VALUES ('AAA', 1), ('BBB', 2), ('CCC', 3)) a(asset_i, i),
     (VALUES ('AAA', 1), ('BBB', 2), ('CCC', 3)) b(asset_j, j)
WHERE c.asset_i = a.asset_i AND c.asset_j = b.asset_j;

SELECT covariance_assert(ready AND candidate_dates = 4 AND complete_dates = 2
  AND discarded_dates = 2 AND is_psd AND unusable_pairs = 0) FROM covariance_gate;
SELECT covariance_assert(ready AND abs(portfolio_variance - 0.0000245) < 1e-15)
FROM complete_portfolio_risk;
SELECT covariance_assert(abs(var_samp(r) - 0.0000245) < 1e-15)
FROM (SELECT date, sum(return_decimal * weight) r FROM complete_returns
      JOIN sample_weights USING (asset_id) GROUP BY date);

-- Views must track edits, including empty and all-invalid histories.
CREATE TEMP TABLE saved_returns AS FROM sample_returns;
CREATE TEMP TABLE saved_weights AS FROM sample_weights;

INSERT INTO sample_weights VALUES ('MISSING', 0.1);
SELECT covariance_assert(NOT ready AND complete_dates = 0 AND NOT labels_match
  AND unusable_pairs = 16) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
DELETE FROM sample_weights WHERE asset_id = 'MISSING';

INSERT INTO sample_weights VALUES ('AAA', 0.1);
SELECT covariance_assert(NOT ready AND duplicate_weights = 1) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
DELETE FROM sample_weights;
INSERT INTO sample_weights FROM saved_weights;

INSERT INTO sample_returns SELECT * FROM saved_returns WHERE date = DATE '2026-01-02' AND asset_id = 'AAA';
SELECT covariance_assert(NOT ready AND duplicate_keys = 1) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
DELETE FROM sample_returns;
INSERT INTO sample_returns FROM saved_returns;

-- NULL/NaN/inf are counted and remove entire dates from the common panel.
UPDATE sample_returns SET return_decimal = 'NaN'::DOUBLE
WHERE date = DATE '2026-01-02' AND asset_id = 'AAA';
UPDATE sample_returns SET return_decimal = 'Infinity'::DOUBLE
WHERE date = DATE '2026-01-04' AND asset_id = 'AAA';
UPDATE sample_returns SET return_decimal = NULL
WHERE date = DATE '2026-01-01' AND asset_id = 'AAA';
SELECT covariance_assert(NOT ready AND complete_dates = 1 AND invalid_return_rows = 3
  AND discarded_dates = 3 AND unusable_pairs = 9) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;

UPDATE sample_returns SET return_decimal = NULL;
SELECT covariance_assert(NOT ready AND complete_dates = 0) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
DELETE FROM sample_returns;
SELECT covariance_assert(NOT ready AND candidate_dates = 0) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
INSERT INTO sample_returns FROM saved_returns;

INSERT INTO sample_returns VALUES (NULL, 'AAA', 0.01);
SELECT covariance_assert(NOT ready AND invalid_date_rows = 1) FROM covariance_gate;
DELETE FROM sample_returns WHERE date IS NULL;

UPDATE sample_weights SET weight = NULL WHERE asset_id = 'AAA';
SELECT covariance_assert(NOT ready AND invalid_weights = 1) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
DELETE FROM sample_weights;
SELECT covariance_assert(NOT ready AND n_assets = 0) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
INSERT INTO sample_weights FROM saved_weights;

-- Common scaling preserves PSD and changes covariance by the square of scale.
UPDATE sample_returns SET return_decimal = return_decimal * 1e-6;
SELECT covariance_assert(ready AND abs(portfolio_variance / 2.45e-17 - 1) < 1e-12)
FROM complete_portfolio_risk;
DELETE FROM sample_returns;
INSERT INTO sample_returns FROM saved_returns;
