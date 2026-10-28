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

-- Independent sample-moment references for every core pair, including diagonal
-- and coverage counts; also cross-check the native aggregate against the SQL.
WITH expected AS (
  SELECT [[1.0/6000, 1.0/5000, 1.0/10000], [1.0/5000, 1.0/2500, -1.0/5000],
          [1.0/10000, -1.0/5000, 1.0/2500]] AS m,
         [[4, 3, 3], [3, 3, 2], [3, 2, 3]] AS n
), native AS (
  SELECT fin_cov_matrix(date, asset_id, return_decimal) AS estimate FROM selected_finite_returns
)
SELECT covariance_assert(count(*) = 9 AND max(abs(c.covariance - m[i][j])) < 1e-15
  AND max(abs(estimate.matrix[i][j] - m[i][j])) < 1e-15
  AND bool_and(c.n_obs = n[i][j]))
FROM pairwise_covariance c, expected, native,
     (VALUES ('AAA', 1), ('BBB', 2), ('CCC', 3)) a(asset_i, i),
     (VALUES ('AAA', 1), ('BBB', 2), ('CCC', 3)) b(asset_j, j)
WHERE c.asset_i = a.asset_i AND c.asset_j = b.asset_j;

-- A negative determinant independently proves that the symmetric pairwise
-- matrix is not PSD. This oracle uses SQL covariance rows, not fin_matrix_is_psd.
WITH rows AS (
  SELECT asset_i, list(covariance ORDER BY asset_j) AS r FROM pairwise_covariance
  WHERE asset_i <> 'DDD' AND asset_j <> 'DDD' GROUP BY asset_i
), matrix AS (
  SELECT list(r ORDER BY asset_i) AS m FROM rows
), determinant AS (
  SELECT m[1][1] * (m[2][2]*m[3][3] - m[2][3]*m[3][2])
       - m[1][2] * (m[2][1]*m[3][3] - m[2][3]*m[3][1])
       + m[1][3] * (m[2][1]*m[3][2] - m[2][2]*m[3][1]) AS d FROM matrix
)
SELECT covariance_assert(d < 0 AND abs(d + 1.0/125000000000) < 1e-24) FROM determinant;

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

-- Integer IDs must use the same string labels/order as fin_cov_matrix, even
-- when native numeric order differs. Four orthogonal zero-mean sign columns
-- over eight dates give an independently known full-rank sample covariance.
-- B in label order ['10','2','20','30'] is
-- [[1,2,0,0],[1,0,0,0],[0,1,3,0],[0,0,1,4]], scaled by 0.01.
-- Thus covariance = B B^T / 8750. Leading principal minors of B B^T
-- are 5, 4, 36, 576, all positive: this fixture is PD, unlike the first panel.
CREATE OR REPLACE TEMP TABLE sample_returns AS
WITH signs AS (
  SELECT i, CASE WHEN i % 2 = 0 THEN -1 ELSE 1 END AS u,
         CASE WHEN (i // 2) % 2 = 0 THEN -1 ELSE 1 END AS v,
         CASE WHEN i < 4 THEN -1 ELSE 1 END AS w
  FROM range(8) t(i)
)
SELECT DATE '2026-02-01' + i::INTEGER AS date, asset_id,
       CASE asset_id WHEN 2 THEN 0.01 + 0.01*u
                     WHEN 10 THEN 0.02 + 0.01*u + 0.02*v
                     WHEN 20 THEN -0.01 + 0.01*v + 0.03*w
                     WHEN 30 THEN 0.03 + 0.01*w + 0.04*u*v END::DOUBLE AS return_decimal
FROM signs CROSS JOIN (VALUES (2), (10), (20), (30)) a(asset_id);
CREATE OR REPLACE TEMP TABLE sample_weights AS
SELECT asset_id, weight::DOUBLE AS weight
FROM (VALUES (2, 0.4), (10, 0.3), (20, 0.2), (30, 0.1)) t(asset_id, weight);

SELECT covariance_assert(ready AND labels_match AND n_assets = 4
  AND candidate_dates = 8 AND complete_dates = 8 AND discarded_dates = 0
  AND unusable_pairs = 0 AND is_psd) FROM covariance_gate;
SELECT covariance_assert(estimate.labels = ['10', '2', '20', '30'])
FROM complete_covariance_matrix;
WITH expected AS (
  SELECT [[5,1,2,0],[1,1,0,0],[2,0,10,3],[0,0,3,17]] AS m
)
SELECT covariance_assert(count(*) = 16 AND bool_and(n_obs = 8)
  AND max(abs(c.covariance - m[i][j] / 8750.0)) < 1e-15)
FROM complete_covariance c, expected,
     (VALUES ('10', 1), ('2', 2), ('20', 3), ('30', 4)) a(asset_i, i),
     (VALUES ('10', 1), ('2', 2), ('20', 3), ('30', 4)) b(asset_j, j)
WHERE c.asset_i = a.asset_i AND c.asset_j = b.asset_j;
-- B^T weights = [0.7,0.8,0.7,0.4]; squared norm / 8750 = 89/437500.
SELECT covariance_assert(coverage_ready AND ready
  AND abs(portfolio_variance - 89.0/437500) < 1e-15) FROM complete_portfolio_risk;
SELECT covariance_assert(abs(var_samp(r) - 89.0/437500) < 1e-15)
FROM (SELECT date, sum(return_decimal * weight) r FROM complete_returns
      JOIN covariance_weights USING (asset_id) GROUP BY date);

INSERT INTO sample_weights VALUES (99, 0.1);
SELECT covariance_assert(NOT ready AND complete_dates = 0
  AND NOT labels_match AND unusable_pairs = 25) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
DELETE FROM sample_weights WHERE asset_id = 99;

-- String labels retain formatting: '02' must not join the integer ID 2.
CREATE OR REPLACE TEMP TABLE sample_weights AS
SELECT CASE WHEN asset_id = 2 THEN '02' ELSE asset_id::VARCHAR END AS asset_id, weight
FROM sample_weights;
SELECT covariance_assert(NOT ready AND complete_dates = 0 AND NOT labels_match) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;

-- Restore the initial input types and values for the remaining negative cases.
CREATE OR REPLACE TEMP TABLE sample_returns AS FROM saved_returns;
CREATE OR REPLACE TEMP TABLE sample_weights AS FROM saved_weights;

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

-- Finite inputs can overflow computed risk. Coverage readiness alone is not
-- risk readiness, and the final view must suppress non-finite/negative results.
UPDATE sample_weights SET weight = CASE WHEN asset_id = 'AAA' THEN 1e308 ELSE 0 END;
SELECT covariance_assert(ready) FROM covariance_gate;
SELECT covariance_assert(coverage_ready AND NOT ready AND portfolio_variance IS NULL)
FROM complete_portfolio_risk;
DELETE FROM sample_weights;
INSERT INTO sample_weights FROM saved_weights;

UPDATE sample_weights SET weight = NULL WHERE asset_id = 'AAA';
SELECT covariance_assert(NOT ready AND invalid_weights = 1) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
UPDATE sample_weights SET weight = 'Infinity'::DOUBLE WHERE asset_id = 'AAA';
SELECT covariance_assert(NOT ready AND invalid_weights = 1) FROM covariance_gate;
SELECT covariance_assert(NOT ready AND portfolio_variance IS NULL) FROM complete_portfolio_risk;
UPDATE sample_weights SET weight = 'NaN'::DOUBLE WHERE asset_id = 'AAA';
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
