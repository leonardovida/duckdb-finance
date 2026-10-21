-- Run after loading a source build of finance 0.3.0. No market data is fetched.
-- Returns are same-interval decimal fractions; covariance is not annualized.
-- Replace sample_returns with a source keyed uniquely by (date, asset_id).
CREATE OR REPLACE TEMP TABLE sample_returns AS
SELECT date, asset_id, return_decimal::DOUBLE AS return_decimal FROM (VALUES
  (DATE '2026-01-01', 'AAA', 0.01), (DATE '2026-01-01', 'BBB', 0.02),
  (DATE '2026-01-02', 'AAA', 0.02), (DATE '2026-01-02', 'BBB', 0.04), (DATE '2026-01-02', 'CCC', 0.03),
  (DATE '2026-01-03', 'AAA', 0.03), (DATE '2026-01-03', 'BBB', 0.06), (DATE '2026-01-03', 'CCC', 0.01),
  (DATE '2026-01-04', 'AAA', 0.04), (DATE '2026-01-04', 'CCC', 0.05),
  (DATE '2026-01-05', 'DDD', 0.10)
) AS t(date, asset_id, return_decimal);

-- Every asset pair appears, even when it has zero or one shared observation.
CREATE OR REPLACE TEMP VIEW pairwise_covariance AS
WITH assets AS (
  SELECT DISTINCT asset_id FROM sample_returns WHERE asset_id IS NOT NULL
), finite_returns AS (
  SELECT date, asset_id, return_decimal
  FROM sample_returns
  WHERE date IS NOT NULL AND asset_id IS NOT NULL AND isfinite(return_decimal)
), pair_stats AS (
  SELECT a.asset_id AS asset_i, b.asset_id AS asset_j,
         count(*) AS n_obs, covar_samp(a.return_decimal, b.return_decimal) AS covariance
  FROM finite_returns a
  JOIN finite_returns b ON a.date = b.date
  GROUP BY a.asset_id, b.asset_id
)
SELECT a.asset_id AS asset_i, b.asset_id AS asset_j,
       coalesce(s.n_obs, 0) AS n_obs, s.covariance
FROM assets a CROSS JOIN assets b
LEFT JOIN pair_stats s ON s.asset_i = a.asset_id AND s.asset_j = b.asset_id;

SELECT * FROM pairwise_covariance ORDER BY asset_i, asset_j;
-- AAA/BBB: n=3, covariance=0.0002. AAA/CCC: n=3, covariance=0.0001.
-- BBB/CCC: n=2, covariance=-0.0002. DDD/DDD: n=1, covariance=NULL.

-- The portfolio universe is explicit, including assets absent from the source.
-- DDD is intentionally excluded. Do not infer the universe from surviving data.
CREATE OR REPLACE TEMP TABLE sample_weights AS
SELECT asset_id, weight::DOUBLE AS weight
FROM (VALUES ('AAA', 0.5), ('BBB', 0.3), ('CCC', 0.2)) t(asset_id, weight);

CREATE OR REPLACE TEMP VIEW selected_assets AS
SELECT DISTINCT asset_id FROM sample_weights WHERE asset_id IS NOT NULL;

CREATE OR REPLACE TEMP VIEW selected_finite_returns AS
SELECT r.* FROM sample_returns r JOIN selected_assets USING (asset_id)
WHERE date IS NOT NULL AND isfinite(return_decimal);

-- Complete-case deletion is an explicit choice. No imputation, PSD repair or
-- automatic asset removal takes place. NULL/non-finite returns exclude a date.
CREATE OR REPLACE TEMP VIEW complete_dates AS
SELECT date FROM selected_finite_returns
GROUP BY date
HAVING count(DISTINCT asset_id) = (SELECT count(*) FROM selected_assets);

CREATE OR REPLACE TEMP VIEW complete_returns AS
SELECT r.* FROM selected_finite_returns r JOIN complete_dates USING (date);

CREATE OR REPLACE TEMP VIEW complete_covariance_matrix AS
SELECT fin_cov_matrix(date, asset_id, return_decimal) AS estimate FROM complete_returns;

-- Preserve label order when turning a matrix into table-shaped covariance.
CREATE OR REPLACE TEMP VIEW complete_covariance AS
SELECT estimate.labels[i] AS asset_i, estimate.labels[j] AS asset_j,
       (SELECT count(*) FROM complete_dates) AS n_obs,
       estimate.matrix[i][j] AS covariance
FROM complete_covariance_matrix,
     LATERAL range(1, len(estimate.labels) + 1) a(i),
     LATERAL range(1, len(estimate.labels) + 1) b(j);

CREATE OR REPLACE TEMP VIEW covariance_coverage AS
SELECT
  (SELECT count(*) FROM selected_assets) AS n_assets,
  (SELECT count(DISTINCT date) FROM sample_returns JOIN selected_assets USING (asset_id)) AS candidate_dates,
  (SELECT count(*) FROM complete_dates) AS complete_dates,
  (SELECT count(*) FROM sample_returns JOIN selected_assets USING (asset_id)
   WHERE date IS NULL) AS invalid_date_rows,
  (SELECT count(*) FROM sample_returns JOIN selected_assets USING (asset_id)
   WHERE return_decimal IS NULL OR NOT isfinite(return_decimal)) AS invalid_return_rows,
  (SELECT count(*) FROM (
     SELECT date, asset_id FROM sample_returns JOIN selected_assets USING (asset_id)
     GROUP BY date, asset_id HAVING count(*) > 1
   )) AS duplicate_keys,
  (SELECT count(*) FROM sample_weights
   WHERE asset_id IS NULL OR weight IS NULL OR NOT isfinite(weight)) AS invalid_weights,
  (SELECT count(*) - count(DISTINCT asset_id) FROM sample_weights) AS duplicate_weights,
  coalesce(estimate.labels = (SELECT list(asset_id ORDER BY asset_id) FROM selected_assets), false) AS labels_match,
  coalesce(fin_matrix_is_psd(estimate.matrix, 1e-10), false) AS is_psd,
  (SELECT count(*) FROM selected_assets a CROSS JOIN selected_assets b
   LEFT JOIN complete_covariance c ON c.asset_i = a.asset_id AND c.asset_j = b.asset_id
   WHERE c.n_obs IS NULL OR c.n_obs < 2 OR c.covariance IS NULL OR NOT isfinite(c.covariance)) AS unusable_pairs
FROM complete_covariance_matrix;

CREATE OR REPLACE TEMP VIEW covariance_gate AS
SELECT *, candidate_dates - complete_dates AS discarded_dates,
       n_assets > 0 AND complete_dates >= 2 AND labels_match AND is_psd
       AND duplicate_keys = 0 AND invalid_date_rows = 0
       AND invalid_weights = 0 AND duplicate_weights = 0 AND unusable_pairs = 0 AS ready
FROM covariance_coverage;

SELECT * FROM covariance_gate;
SELECT * FROM complete_covariance ORDER BY asset_i, asset_j;
-- Four candidate dates, two complete dates. AAA/CCC is now -0.0001.
-- All nine entries share the same two dates. This rank-one matrix is PSD,
-- but not positive definite: passing this gate does not guarantee optimizer use.

-- Pairwise coverage alone is insufficient: the core matrix is NOT PSD.
SELECT fin_matrix_is_psd(estimate.matrix, 1e-10) AS pairwise_is_psd
FROM (SELECT fin_cov_matrix(date, asset_id, return_decimal) AS estimate
      FROM selected_finite_returns);

-- Retain a status row when blocked; never emit an unchecked risk estimate.
CREATE OR REPLACE TEMP VIEW approved_weights AS
SELECT * FROM sample_weights WHERE (SELECT ready FROM covariance_gate);

CREATE OR REPLACE TEMP VIEW complete_portfolio_risk AS
SELECT ready, portfolio_variance
FROM covariance_gate CROSS JOIN fin_portfolio_variance_table(
  'approved_weights', 'asset_id', 'weight',
  'complete_covariance', 'asset_i', 'asset_j', 'covariance');

SELECT * FROM complete_portfolio_risk;
-- Direct sample variance of the weighted returns 0.028 and 0.035 is 0.0000245.
