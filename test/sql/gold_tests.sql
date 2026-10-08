CREATE OR REPLACE MACRO assert_true(name, condition) AS
  CASE WHEN coalesce(condition, false) THEN 1 ELSE CAST(name AS INTEGER) END;

CREATE OR REPLACE MACRO assert_eq(name, actual, expected) AS
  CASE WHEN actual IS NOT DISTINCT FROM expected THEN 1 ELSE CAST(name AS INTEGER) END;

CREATE OR REPLACE MACRO assert_near(name, actual, expected, tolerance) AS
  CASE
    WHEN actual IS NOT NULL AND abs(actual::DOUBLE - expected::DOUBLE) <= tolerance::DOUBLE THEN 1
    ELSE CAST(name AS INTEGER)
  END;

CREATE OR REPLACE MACRO assert_not_null(name, actual) AS
  CASE WHEN actual IS NOT NULL THEN 1 ELSE CAST(name AS INTEGER) END;

SELECT assert_true('version prefix', starts_with(fin_version(), 'finance'));
SELECT assert_eq('release version', fin_version(), 'finance 0.3.0');

-- Repository sweep regressions: NULLs must never be read as native values.
SELECT
  assert_near('irr tiny amounts', fin_irr([-1e-20, 2e-20]), 1.0, 1e-10),
  assert_near('irr large amounts', fin_irr([-1e200, 2e200]), 1.0, 1e-10),
  assert_near('xirr tiny amounts', fin_xirr([-1e-20, 2e-20], [DATE '2025-01-01', DATE '2026-01-01']), 1.0, 1e-10),
  assert_eq('npv invalid periodic base', fin_npv(-2, [-100, 110]), NULL),
  assert_eq('mirr invalid finance base', fin_mirr([-100, 110], -2, 0.1), NULL),
  assert_eq('mirr invalid reinvest base', fin_mirr([-100, 110], 0.1, -2), NULL),
  assert_near('annuity due timing', fin_annuity_payment(0.05, 10, 100, 0, 'begin'), -12.333769044329202, 1e-10),
  assert_eq('annuity invalid rate', fin_annuity_payment(-2, 10, 100), NULL),
  assert_near('annuity tiny rate long term', fin_annuity_payment(1e-15, 1e9, 100), -1.0000005000000838e-7, 1e-19);

SELECT
  assert_eq('rate rejects infinite discount factor', fin_rate_from_discount('Infinity'::DOUBLE, 1, 'simple'), NULL),
  assert_eq('rate rejects infinite time', fin_rate_from_discount(0.9, 'Infinity'::DOUBLE), NULL),
  assert_eq('forward rejects infinite time', fin_forward_price(100, 'Infinity'::DOUBLE, 0.05, 0.1), NULL),
  assert_eq('business maximum date overflow', fin_next_business_day(DATE '5881580-07-10'), NULL),
  assert_eq('business minimum date overflow', fin_prev_business_day(DATE '-5877641-06-25'), NULL);

SELECT
  assert_near('drawdown survives wealth overflow', fin_drawdown(r ORDER BY i), -0.1, 1e-12),
  assert_near('max drawdown survives wealth overflow', fin_max_drawdown(r ORDER BY i), -0.1, 1e-12),
  assert_near('large initial nav drawdown', fin_drawdown(r, 1e308 ORDER BY i), -0.1, 1e-12)
FROM (SELECT i, CASE WHEN i < 1100 THEN 1.0 ELSE -0.1 END AS r FROM range(1101) t(i));

SELECT
  assert_eq('weighted variance overflow cannot report zero', fin_weighted_var(x, w), NULL),
  assert_eq('weighted mean overflowing total weight', fin_weighted_mean(x, w), NULL)
FROM (VALUES (10.0::DOUBLE, 1e308), (20.0::DOUBLE, 1e308)) t(x, w);

SELECT assert_near('weighted mean avoids intermediate overflow', fin_weighted_mean(x, w), 15.0, 1e-12)
FROM (VALUES (10.0::DOUBLE, 1e307), (20.0::DOUBLE, 1e307)) t(x, w);

SELECT assert_near('weighted singleton finite zero variance', fin_weighted_var(20.0, 1e308), 0.0, 1e-12);

WITH large_weights AS MATERIALIZED (
  SELECT (i % 2)::DOUBLE AS x, 1e200 AS w FROM range(30000) t(i)
)
SELECT assert_near('weighted merge avoids intermediate overflow', fin_weighted_var(x, w), 0.25, 1e-10)
FROM large_weights;

SELECT
  assert_eq('vector null scale', fin_vector_scale([1.0, 2.0], NULL), NULL),
  assert_eq('empty matrix null vector', fin_matrix_vecmul([]::DOUBLE[][], NULL), NULL),
  assert_eq('vector nonfinite sum', fin_vector_sum([1.0, 'Infinity'::DOUBLE]), NULL),
  assert_eq('vector nonfinite dot', fin_dot([1.0], ['NaN'::DOUBLE]), NULL),
  assert_eq('vector scale overflow', fin_vector_scale([1e308], 10.0), NULL),
  assert_eq('vector add overflow', fin_vector_add([1e308], [1e308]), NULL),
  assert_eq('black76 null rate', fin_black76_greeks('call', 100, 100, 1, NULL, 0.2), NULL),
  assert_eq('bachelier null rate', fin_bachelier_greeks('call', 100, 100, 1, NULL, 5), NULL),
  assert_eq('bsm nonfinite struct', fin_bsm_greeks('call', 100, 100, 1, -1000, 0.2), NULL),
  assert_eq('bsm all nonfinite struct', fin_bsm_all('call', 100, 100, 1, -1000, 0.2), NULL);

-- Mixed rows cross chunk boundaries and filtered inputs exercise selection vectors.
WITH rows AS MATERIALIZED (
  SELECT i, CASE WHEN i % 3 = 0 THEN NULL ELSE 0.05 END AS rate,
         CASE WHEN i % 3 = 0 THEN NULL ELSE 2.0 END AS scale
  FROM range(5000) t(i)
)
SELECT
  assert_eq('black76 mixed null rows', count(*) FILTER (WHERE fin_black76_greeks('put', 100, 100, 1, rate, 0.2) IS NULL), 1667::BIGINT),
  assert_eq('bachelier mixed null rows', count(*) FILTER (WHERE fin_bachelier_greeks('put', 100, 100, 1, rate, 5) IS NULL), 1667::BIGINT),
  assert_eq('vector mixed null rows', count(*) FILTER (WHERE fin_vector_scale([1.0, 2.0], scale) IS NULL), 1667::BIGINT),
  assert_near('vector valid rows', fsum(fin_vector_scale([1.0, 2.0], scale)[2]), 13332.0, 1e-12)
FROM rows;

WITH rows AS MATERIALIZED (
  SELECT i, CASE WHEN i % 3 = 0 THEN NULL ELSE 0.05 END AS rate FROM range(5000) t(i)
)
SELECT assert_eq('greeks filtered selection',
                count(*) FILTER (WHERE fin_bachelier_greeks('call', 100, 100, 1, rate, 5) IS NULL), 834::BIGINT)
FROM rows WHERE i % 2 = 0;

-- Pairwise metrics must use the same observations in both numerator and denominator.
WITH pairs(r, b, volume) AS (VALUES (1.0, 1.0, 1.0), (2.0, 2.0, 1.0), (NULL, 100.0, 100.0), (100.0, NULL, NULL))
SELECT
  assert_near('beta complete pairs', fin_beta(r, b), 1.0, 1e-12),
  assert_near('alpha complete pairs', fin_alpha(r, b, 0, 1), 0.0, 1e-12),
  assert_near('up capture complete pairs', fin_up_capture(r, b), 1.0, 1e-12),
  assert_near('vwap complete pairs', fin_vwap(r, volume), 1.5, 1e-12)
FROM pairs;

WITH observations(r) AS (VALUES (-0.1), (0.1), (NULL))
SELECT
  assert_near('downside ignores nulls', fin_downside_deviation(r, 0, 1), sqrt(0.005), 1e-12),
  assert_near('upside ignores nulls', fin_upside_deviation(r, 0, 1), sqrt(0.005), 1e-12),
  assert_near('semivariance ignores nulls', fin_semivariance(r), 0.005, 1e-12),
  assert_near('hit ratio ignores nulls', fin_hit_ratio(r), 0.5, 1e-12),
  assert_near('win rate ignores nulls', fin_win_rate(r), 0.5, 1e-12),
  assert_near('loss rate ignores nulls', fin_loss_rate(r), 0.5, 1e-12)
FROM observations;

SELECT
  assert_eq('all-null downside', fin_downside_deviation(r), NULL),
  assert_eq('all-null hit ratio', fin_hit_ratio(r), NULL),
  assert_eq('all-null total return', fin_total_return(r), NULL)
FROM (VALUES (NULL::DOUBLE), (NULL::DOUBLE)) t(r);

SELECT
  assert_near('total loss compounds', fin_total_return(r), -1.0, 1e-12),
  assert_near('total loss nav', fin_nav(r, 100), 0.0, 1e-12),
  assert_eq('total loss log nav is undefined', fin_log_nav(r, 100), NULL),
  assert_near('total loss cagr', fin_cagr(r), -1.0, 1e-12)
FROM (VALUES (0.1), (-1.0), (0.2), (NULL)) t(r);

SELECT assert_eq('return below total loss', fin_total_return(r), NULL)
FROM (VALUES (0.1), (-1.1)) t(r);

SELECT
  assert_near('general ddof variance', fin_stable_var(x, 2), 2.5, 1e-12),
  assert_near('general ddof stddev', fin_stable_stddev(x, 2), sqrt(2.5), 1e-12),
  assert_eq('negative ddof', fin_stable_var(x, -1), NULL),
  assert_eq('exhausted ddof', fin_stable_var(x, 4), NULL)
FROM (VALUES (1.0), (2.0), (3.0), (4.0), (NULL)) t(x);

-- Euler decomposition: component volatility sums to portfolio volatility.
WITH risk AS (
  SELECT fin_component_risk([0.25, 0.75], [[0.04, 0.0], [0.0, 0.09]]) AS c,
         fin_risk_contribution([0.25, 0.75], [[0.04, 0.0], [0.0, 0.09]]) AS rc,
         sqrt(0.25 * 0.25 * 0.04 + 0.75 * 0.75 * 0.09) AS vol
)
SELECT
  assert_near('component risk first', c[1], 0.0025 / vol, 1e-12),
  assert_near('component risk second', c[2], 0.050625 / vol, 1e-12),
  assert_near('component risk sum', fin_vector_sum(c), vol, 1e-12),
  assert_near('risk contribution first', rc[1], 0.0025 / 0.053125, 1e-12),
  assert_near('risk contribution sum', fin_vector_sum(rc), 1.0, 1e-12),
  assert_eq('zero risk components', fin_component_risk([1.0], [[0.0]]), NULL)
FROM risk;

SELECT
  assert_near('iv honors supplied guess', fin_bsm_implied_vol('call', 10.450583572185565, 100, 100, 1, 0.05, 0, 0.2, 1e-12, 1), 0.2, 1e-12),
  assert_eq('iv rejects unconverged solve', fin_bsm_implied_vol('call', 10.450583572185565, 100, 100, 1, 0.05, 0, 3.0, 1e-12, 1), NULL),
  assert_near('iv zero volatility', fin_bsm_implied_vol('call', fin_bsm_price('call', 110, 100, 1, 0.05, 0), 110, 100, 1, 0.05), 0.0, 1e-12),
  assert_eq('iv rejects negative guess', fin_bsm_implied_vol('call', 10.0, 100, 100, 1, 0.05, 0, -1), NULL),
  assert_eq('black76 iv upper bound', fin_black76_implied_vol('call', 100, 100, 100, 1, 0), NULL),
  assert_eq('black76 expired iv', fin_black76_implied_vol('call', 0, 100, 100, 0, 0), NULL),
  assert_eq('bachelier expired iv', fin_bachelier_implied_vol('call', 0, 100, 100, 0, 0), NULL),
  assert_near('bachelier large normal vol', fin_bachelier_implied_vol('call', 1000e0 * 0.3989422804014327, 100, 100, 1, 0), 1000, 1e-7),
  assert_true('put delta retains tail', fin_bsm_delta('put', 1000, 100, 1, 0, 0.2) < 0.0);

-- Bond prices reconcile to an explicit cashflow schedule across yield regimes.
WITH cases(coupon, ytm, maturity, freq, face) AS (
  VALUES (0.05, 0.04, 5.0, 2, 100.0), (0.05, 0.0, 5.0, 2, 100.0),
         (0.05, 1e-14, 5.0, 2, 100.0), (0.03, -0.01, 5.0, 4, 1000.0),
         (0.0, 0.04, 10.0, 1, 100.0), (0.0, -0.04, 10.0, 1, 100.0)
), reconciled AS (
  SELECT *, (SELECT fsum((face * coupon / freq + CASE WHEN i = round(maturity * freq) THEN face ELSE 0 END) *
                        pow(1.0 + ytm / freq, -i)) FROM range(1, round(maturity * freq)::BIGINT + 1) t(i)) AS reference
  FROM cases
)
SELECT
  assert_near('bond explicit cashflow price', fin_bond_price(coupon, ytm, maturity, freq, face), reference, 1e-9),
  assert_near('bond ytm price roundtrip', fin_bond_price(coupon, fin_bond_ytm(reference, coupon, maturity, freq, face), maturity, freq, face), reference, 1e-9)
FROM reconciled;

SELECT
  assert_near('bond high yield', fin_bond_ytm(0.01, 0, 1, 1, 100), 9999.0, 1e-7),
  assert_eq('bond out of range periods', fin_bond_price(0.05, 0.04, 1e30, 2), NULL),
  assert_eq('bond duration invalid frequency', fin_bond_duration(0.05, 0.04, 5, 0), NULL),
  assert_eq('bond convexity out of range periods', fin_bond_convexity(0.05, 0.04, 1e30, 2), NULL),
  assert_near('bond convexity large period count', fin_bond_convexity(0, 0, 25000, 2), 50000.0 * 50001.0 / 4.0, 1e-6),
  assert_near('bond convexity large frequency', fin_bond_convexity(0, 0, 0.00002, 50000), 2.0 / 2500000000.0, 1e-18);

SELECT
  assert_eq('business null offset', fin_next_business_day(DATE '2026-05-08', 'weekday', NULL), NULL),
  assert_eq('business infinite date', fin_next_business_day(DATE 'infinity'), NULL),
  assert_eq('business huge offset', fin_next_business_day(DATE '2026-05-08', 'weekday', 2147483647), NULL),
  assert_eq('business next five', fin_next_business_day(DATE '2026-05-09', 'weekday', 5), DATE '2026-05-15'),
  assert_eq('business previous five', fin_prev_business_day(DATE '2026-05-10', 'weekday', 5), DATE '2026-05-04'),
  assert_eq('business zero offset', fin_next_business_day(DATE '2026-05-09', 'weekday', 0), DATE '2026-05-09'),
  assert_eq('business infinite interval', fin_business_days_between(DATE '2026-01-01', DATE 'infinity'), NULL),
  assert_eq('yearfrac infinite date', fin_yearfrac(DATE '2026-01-01', DATE 'infinity'), NULL),
  assert_near('yearfrac long actact', fin_yearfrac(DATE '1000-01-01', DATE '1000000-01-01', 'ACT/ACT'), 999000.0, 1e-9),
  assert_near('yearfrac wide dates', fin_yearfrac(DATE '-3999999-01-01', DATE '4000000-01-01', 'ACT/365F'),
              date_diff('day', DATE '-3999999-01-01', DATE '4000000-01-01')::DOUBLE / 365, 1e-9);

-- Numerical helpers and scalar edge cases.
-- Performance changes preserve explicit cashflow and distribution references.
WITH cases AS (
  SELECT .01 + (i % 5)::DOUBLE / 100 AS coupon,
         CASE i % 4 WHEN 0 THEN 0.0 WHEN 1 THEN 1e-14 WHEN 2 THEN -.025 ELSE .04 END AS ytm,
         1 + i % 40 AS maturity, (1 << (i % 3))::INTEGER AS freq
  FROM range(200) t(i)
), cashflows AS (
  SELECT *, (100 * coupon / freq + CASE WHEN j = maturity * freq THEN 100 ELSE 0 END)
    * pow(1 + ytm / freq, -j) AS pv
  FROM cases, LATERAL range(1, maturity * freq + 1) t(j)
), refs AS (
  SELECT coupon, ytm, maturity, freq,
    fsum(pv * j / freq) / fsum(pv) AS duration,
    fsum(pv * j * (j + 1) / pow(1 + ytm / freq, 2)) / (fsum(pv) * freq * freq) AS convexity
  FROM cashflows GROUP BY coupon, ytm, maturity, freq
)
SELECT
  assert_true('bond fast duration cashflow oracle', bool_and(coalesce(abs(fin_bond_duration(coupon, ytm, maturity, freq) - duration) < 1e-9, false))),
  assert_true('bond fast convexity cashflow oracle', bool_and(coalesce(abs(fin_bond_convexity(coupon, ytm, maturity, freq) - convexity) < 1e-7, false)))
FROM refs;

SELECT
  assert_near('billion period duration', fin_bond_duration(0, 0, 500000000), 500000000.0, 1e-5),
  assert_near('billion period convexity', fin_bond_convexity(0, 0, 500000000), 1e9 * (1e9 + 1) / 4, 100.0),
  assert_near('bond duration default', fin_bond_duration(.05, .04, 5), fin_bond_duration(.05, .04, 5, 2, 100, 'macaulay'), 1e-12),
  assert_near('bond convexity default', fin_bond_convexity(.05, .04, 5), fin_bond_convexity(.05, .04, 5, 2, 100), 1e-12),
  assert_near('binomial defaults', fin_binomial_price('call', 100, 100, 1, .05, .2), fin_binomial_price('call', 100, 100, 1, .05, .2, 0, 200, 'european', 'crr'), 1e-12);

-- Enumerate all eight-step paths independently of binomial recurrence weights.
WITH cases AS (
  SELECT CASE i % 2 WHEN 0 THEN 'call' ELSE 'put' END AS kind,
    90 + (i % 5)::DOUBLE * 5 AS s, .01 + (i % 3)::DOUBLE / 100 AS r,
    .1 + (i % 7)::DOUBLE / 10 AS v, (i % 4)::DOUBLE / 100 AS q,
    CASE WHEN i % 3 = 0 THEN 'jr' ELSE 'crr' END AS tree
  FROM range(30) t(i)
), trees AS (
  SELECT *, exp(CASE WHEN tree = 'jr' THEN (r-q-.5*v*v)/8 ELSE 0 END + v/sqrt(8)) AS u,
            exp(CASE WHEN tree = 'jr' THEN (r-q-.5*v*v)/8 ELSE 0 END - v/sqrt(8)) AS d
  FROM cases
), probabilities AS (
  SELECT *, CASE WHEN tree = 'jr' THEN .5 ELSE (exp((r-q)/8)-d)/(u-d) END AS p FROM trees
), refs AS (
  SELECT kind, s, r, v, q, tree,
    exp(-r) * fsum(pow(p, bit_count(path)) * pow(1-p, 8-bit_count(path)) *
      greatest(CASE WHEN kind = 'call' THEN s*pow(u,bit_count(path))*pow(d,8-bit_count(path))-100
               ELSE 100-s*pow(u,bit_count(path))*pow(d,8-bit_count(path)) END, 0)) AS price
  FROM probabilities, range(256) t(path) GROUP BY kind, s, r, v, q, tree
)
SELECT assert_true('european binomial path oracle', bool_and(coalesce(abs(fin_binomial_price(kind, s, 100, 1, r, v, q, 8, 'european', tree) - price) < 1e-10, false)))
FROM refs;

SELECT
  assert_near('american no-dividend crr call', fin_binomial_price('call', 100, 80, 1, .05, .2, 0, 200, 'american'), fin_binomial_price('call', 100, 80, 1, .05, .2), 1e-10),
  assert_true('american dividend early exercise retained', fin_binomial_price('call', 150, 100, 1, .02, .2, .2, 200, 'american') > fin_binomial_price('call', 150, 100, 1, .02, .2, .2)),
  assert_true('american put early exercise retained', fin_binomial_price('put', 80, 100, 1, .1, .2, 0, 200, 'american') > fin_binomial_price('put', 80, 100, 1, .1, .2));

WITH cases AS (
  SELECT .01 + (i % 31)::DOUBLE / 100 AS rate,
    CASE i % 3 WHEN 0 THEN 1e-20 WHEN 1 THEN 1.0 ELSE 1e200 END AS scale,
    90 + (i % 1000)::INTEGER AS days
  FROM range(200) t(i)
)
SELECT
  assert_true('analytic irr known roots', bool_and(coalesce(abs(fin_irr([-100*scale, 50*(1+rate)*scale, 50*pow(1+rate,2)*scale]) - rate) < 1e-10, false))),
  assert_true('analytic xirr known roots', bool_and(coalesce(abs(fin_xirr([-100*scale, 100*pow(1+rate,days/365.0)*scale], [DATE '2026-01-01', DATE '2026-01-01'+days]) - rate) < 1e-10, false)))
FROM cases;

WITH cases AS (
  SELECT CASE i % 2 WHEN 0 THEN 'call' ELSE 'put' END AS kind,
    80 + (i % 41)::DOUBLE AS f, .1 + (i % 20)::DOUBLE / 10 AS t,
    .01 + (i % 9)::DOUBLE / 100 AS r, .1 + (i % 23)::DOUBLE / 100 AS v
  FROM range(300) t(i)
), prices AS (
  SELECT *, fin_black76_price(kind, f, 100, t, r, v) AS black,
            fin_bachelier_price(kind, f-100, 0, t, r, v*100) AS normal FROM cases
)
SELECT
  assert_true('black76 safeguarded default solver', bool_and(coalesce(abs(fin_black76_price(kind, f, 100, t, r, fin_black76_implied_vol(kind, black, f, 100, t, r)) - black) < 1e-7, false))),
  assert_true('normal automatic default solver', bool_and(coalesce(abs(fin_bachelier_price(kind, f-100, 0, t, r, fin_bachelier_implied_vol(kind, normal, f-100, 0, t, r)) - normal) < 1e-7, false)))
FROM prices;

SELECT
  assert_near('normal default small price units', fin_bachelier_implied_vol('call', .0002*0.3989422804014327, .01, .01, 1, 0), .0002, 1e-12),
  assert_near('normal default large price units', fin_bachelier_implied_vol('call', 2000e0*0.3989422804014327, 10000, 10000, 1, 0), 2000, 1e-8),
  assert_eq('fast matrix ragged rows', fin_matrix_vecmul([[1,2],[3]], [1,2]), NULL),
  assert_eq('fast matrix null row', fin_matrix_vecmul([[1.0],NULL], [1.0]), NULL),
  assert_eq('fast matrix null element', fin_matrix_vecmul([[NULL::DOUBLE]], [1.0]), NULL),
  assert_eq('fast matrix overflow', fin_matrix_vecmul([[1e308]], [2.0]), NULL),
  assert_eq('fast empty matrix', fin_matrix_vecmul([]::DOUBLE[][], [1.0]), []::DOUBLE[]);

WITH inputs AS (
  SELECT i % 7 AS g, sin(i::DOUBLE)*100 + (i%3)::DOUBLE AS x FROM range(1500) t(i)
), cuts AS (
  SELECT g, quantile_cont(x,.05) lo, quantile_cont(x,.95) hi FROM inputs GROUP BY g
), expected AS (
  SELECT g, avg(x) FILTER (WHERE x >= lo AND x <= hi) trimmed,
    avg(greatest(lo,least(x,hi))) winsorized, -avg(x) FILTER (WHERE x <= lo) cvar
  FROM inputs JOIN cuts USING(g) GROUP BY g
), actual AS (
  SELECT g, fin_trimmed_mean(x) trimmed, fin_winsorized_mean(x) winsorized, fin_cvar(x) cvar
  FROM inputs GROUP BY g
)
SELECT assert_true('selection statistics sorted-quantile oracle', bool_and(
  abs(a.trimmed-e.trimmed)<1e-10 AND abs(a.winsorized-e.winsorized)<1e-10 AND abs(a.cvar-e.cvar)<1e-10))
FROM actual a JOIN expected e USING(g);

SELECT
  assert_near('robust finite large mean', fin_winsorized_mean(x), 1e308, 1e294),
  assert_near('robust finite large trimmed mean', fin_trimmed_mean(x), 1e308, 1e294)
FROM (VALUES (1e308), (1e308), (1e308)) t(x);

-- A recursive Wilder recurrence independently checks seed and tail handling
-- (TA-Lib RSI: seed with the mean of the first `period` changes).
WITH RECURSIVE prices AS (
  SELECT period, i, 100+sin(i::DOUBLE)*5 AS px
  FROM (VALUES (1),(2),(14),(119)) p(period), range(120) t(i)
), changes AS (
  SELECT *, px-lag(px) OVER (PARTITION BY period ORDER BY i) AS diff FROM prices
), recurrence(period,i,gain,loss) AS (
  SELECT period, least(period,119)::BIGINT, avg(greatest(diff,0)), avg(greatest(-diff,0))
  FROM changes WHERE i>0 AND i<=period GROUP BY period
  UNION ALL
  SELECT w.period,c.i,(w.gain*(w.period-1)+greatest(c.diff,0))/w.period,
    (w.loss*(w.period-1)+greatest(-c.diff,0))/w.period
  FROM recurrence w JOIN changes c ON c.period=w.period AND c.i=w.i+1
), native AS (
  SELECT period,fin_rsi(px,period ORDER BY i) AS rsi FROM prices GROUP BY period
)
SELECT assert_true('bounded rsi Wilder oracle', bool_and(coalesce(abs(n.rsi-
  CASE WHEN w.loss=0 THEN 100 ELSE 100-100/(1+w.gain/w.loss) END)<1e-10,false)))
FROM native n JOIN recurrence w USING(period) WHERE w.i=119;

SELECT assert_near('rsi default period', fin_rsi(px ORDER BY i), fin_rsi(px,14 ORDER BY i), 1e-12)
FROM (SELECT i,100+sin(i::DOUBLE)*5 px FROM range(10000) t(i));

SELECT
  assert_eq('rsi warm-up needs period changes', fin_rsi(px, 200 ORDER BY i), NULL),
  assert_eq('rsi bigint period', fin_rsi(px, 14::BIGINT ORDER BY i), fin_rsi(px, 14 ORDER BY i)),
  assert_eq('rsi decimal period', fin_rsi(px, 14.0 ORDER BY i), fin_rsi(px, 14 ORDER BY i))
FROM (SELECT i,100+sin(i::DOUBLE)*5 px FROM range(120) t(i));

-- TA-Lib conventions: no movement gives 0, only gains give 100, a non-finite
-- price makes the recursive indicator NULL for the rest of the series.
SELECT
  assert_eq('rsi flat series is zero', fin_rsi(5.0, 3 ORDER BY i), 0.0),
  assert_eq('rsi rising series is 100', fin_rsi(i::DOUBLE, 3 ORDER BY i), 100.0),
  assert_eq('rsi nan poisons the series', fin_rsi(CASE WHEN i = 2 THEN 'NaN'::DOUBLE ELSE i END, 3 ORDER BY i), NULL),
  assert_near('rsi skips null rows', fin_rsi(CASE WHEN i = 2 THEN NULL ELSE i END, 3 ORDER BY i), 100.0, 0.0)
FROM range(10) t(i);

-- Sliding frames reseed RSI at the frame start; frames shorter than period + 1 rows are NULL.
WITH prices AS (
  SELECT i,100+sin(i::DOUBLE)*5 AS px FROM range(4096) t(i)
), changes AS (
  SELECT *,px-lag(px) OVER (ORDER BY i) AS diff FROM prices
), native AS (
  SELECT i,fin_rsi(px) OVER (ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS rsi FROM prices
), refs AS (
  SELECT n.i,n.rsi,
    (fsum(greatest(c.diff,0)) FILTER (WHERE c.i<=greatest(n.i-30,0)+least(14,n.i)) / least(14,n.i)) *
      pow(13.0/14,greatest(least(n.i,30)-14,0)) +
    coalesce(fsum(greatest(c.diff,0)/14 * pow(13.0/14,n.i-c.i)) FILTER (WHERE c.i>greatest(n.i-30,0)+14),0) AS gain,
    (fsum(greatest(-c.diff,0)) FILTER (WHERE c.i<=greatest(n.i-30,0)+least(14,n.i)) / least(14,n.i)) *
      pow(13.0/14,greatest(least(n.i,30)-14,0)) +
    coalesce(fsum(greatest(-c.diff,0)/14 * pow(13.0/14,n.i-c.i)) FILTER (WHERE c.i>greatest(n.i-30,0)+14),0) AS loss
  FROM native n JOIN changes c ON c.i>greatest(n.i-30,0) AND c.i<=n.i GROUP BY n.i,n.rsi
)
SELECT assert_true('rsi affine window oracle', bool_and(CASE WHEN i < 14 THEN rsi IS NULL ELSE coalesce(abs(rsi-
  CASE WHEN loss=0 THEN 100 ELSE 100-100/(1+gain/loss) END)<1e-10,false) END)) FROM refs;

WITH results AS (
  SELECT i, least(i+1,10)::DOUBLE AS n,
    fin_drawdown(-.01) OVER frame AS current_dd,
    fin_max_drawdown(-.01) OVER frame AS max_dd,
    fin_avg_drawdown(-.01) OVER frame AS avg_dd,
    fin_drawdown_duration(-.01) OVER frame AS duration
  FROM range(4096) t(i)
  WINDOW frame AS (ORDER BY i ROWS BETWEEN 9 PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('drawdown merge current window', bool_and(abs(current_dd-(pow(.99,n)-1))<1e-12)),
  assert_true('drawdown merge maximum window', bool_and(abs(max_dd-(pow(.99,n)-1))<1e-12)),
  assert_true('drawdown merge average window', bool_and(abs(avg_dd-(.99*(1-pow(.99,n))/.01/n-1))<1e-12)),
  assert_true('drawdown merge duration window', bool_and(duration=n))
FROM results;

-- Returns/risk window frames: every framed value must equal the grouped
-- aggregate over the same rows (running, sliding and EXCLUDE frames).
CREATE OR REPLACE TEMP TABLE rr_window_input AS
  SELECT i, i % 3 AS g, sin(i * 0.7) * 0.02 + 0.0005 AS r, cos(i * 0.3) * 0.01 AS b FROM range(1, 1200) t(i);
WITH framed AS (
  SELECT i, g,
    fin_max_drawdown(r) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS run_mdd,
    fin_max_drawdown(r) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 20 PRECEDING AND CURRENT ROW) AS slide_mdd,
    fin_ulcer_index(r) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 20 PRECEDING AND CURRENT ROW) AS slide_ulcer,
    fin_cvar(r) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 50 PRECEDING AND CURRENT ROW) AS slide_cvar,
    fin_var(r, 0.9, 'cornish_fisher') OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_var,
    fin_trimmed_mean(r) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND 5 FOLLOWING EXCLUDE CURRENT ROW) AS excl_trim,
    fin_iv_percentile(abs(r)) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_ivp,
    fin_drawdown_at_risk(r, 0.9) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_dar,
    fin_weighted_quantile(r, 1 + abs(b), 0.3) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_wq,
    fin_outlier_count(r, 'zscore', 1.5) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_oc,
    fin_sharpe(r, 0.02, 252) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_sharpe,
    fin_beta(r, b) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_beta,
    fin_total_return(r) OVER (PARTITION BY g ORDER BY i ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS slide_tr
  FROM rr_window_input
), grouped AS (
  SELECT a.i, a.g,
    (SELECT fin_max_drawdown(x.r ORDER BY x.i) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i) AS run_mdd,
    (SELECT fin_max_drawdown(x.r ORDER BY x.i) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 63) AS slide_mdd,
    (SELECT fin_ulcer_index(x.r ORDER BY x.i) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 63) AS slide_ulcer,
    (SELECT fin_cvar(x.r) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 153) AS slide_cvar,
    (SELECT fin_var(x.r, 0.9, 'cornish_fisher') FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_var,
    (SELECT fin_trimmed_mean(x.r) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i + 15 AND x.i > a.i - 93 AND x.i <> a.i) AS excl_trim,
    (SELECT fin_iv_percentile(abs(x.r) ORDER BY x.i) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_ivp,
    (SELECT fin_drawdown_at_risk(x.r, 0.9 ORDER BY x.i) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_dar,
    (SELECT fin_weighted_quantile(x.r, 1 + abs(x.b), 0.3) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_wq,
    (SELECT fin_outlier_count(x.r, 'zscore', 1.5) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_oc,
    (SELECT fin_sharpe(x.r, 0.02, 252) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_sharpe,
    (SELECT fin_beta(x.r, x.b) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_beta,
    (SELECT fin_total_return(x.r) FROM rr_window_input x WHERE x.g = a.g AND x.i <= a.i AND x.i > a.i - 93) AS slide_tr
  FROM rr_window_input a WHERE a.i % 29 = 0
)
SELECT
  assert_true('returns risk window frames match grouped aggregates', bool_and(
    abs(f.run_mdd - e.run_mdd) < 1e-12 AND abs(f.slide_mdd - e.slide_mdd) < 1e-12 AND
    abs(f.slide_ulcer - e.slide_ulcer) < 1e-12 AND abs(f.slide_cvar - e.slide_cvar) < 1e-12 AND
    abs(f.slide_var - e.slide_var) < 1e-12 AND abs(f.excl_trim - e.excl_trim) < 1e-12 AND
    abs(f.slide_ivp - e.slide_ivp) < 1e-12 AND abs(f.slide_dar - e.slide_dar) < 1e-12 AND
    abs(f.slide_wq - e.slide_wq) < 1e-12 AND f.slide_oc = e.slide_oc AND
    abs(f.slide_sharpe - e.slide_sharpe) < 1e-9 AND abs(f.slide_beta - e.slide_beta) < 1e-9 AND
    abs(f.slide_tr - e.slide_tr) < 1e-12)),
  assert_eq('returns risk window frame rows', count(*), 41::BIGINT)
FROM framed f JOIN grouped e USING (i, g);

-- Order-dependent returns/risk aggregates must not depend on thread count or
-- physical row order.
CREATE OR REPLACE TEMP TABLE rr_order_input AS
  SELECT i % 97 AS g, i // 97 AS ts, sin(i * 1.3) * 0.03 AS r,
         100 + sin(i * 0.11) * 5 AS c, 0.2 + abs(sin(i * 0.5)) * 0.1 AS iv
  FROM range(40000) t(i) ORDER BY hash(i);
CREATE OR REPLACE MACRO rr_order_metrics() AS TABLE
  SELECT g, fin_drawdown(r ORDER BY ts) AS a, fin_max_drawdown(r ORDER BY ts) AS b, fin_avg_drawdown(r ORDER BY ts) AS c1,
    fin_drawdown_duration(r ORDER BY ts) AS d, fin_ulcer_index(r ORDER BY ts) AS e,
    fin_drawdown_at_risk(r, 0.9 ORDER BY ts) AS f, fin_conditional_drawdown_at_risk(r, 0.9 ORDER BY ts) AS h,
    fin_garch11_forecast(r, 0.000001, 0.05, 0.9 ORDER BY ts) AS k,
    fin_yang_zhang_vol(c, c * 1.01, c * 0.99, c * (1 + r / 10) ORDER BY ts) AS l,
    fin_calmar(r, ts) AS m, fin_recovery_factor(r, ts) AS n, fin_zscore_last(r, ts) AS o,
    fin_iv_rank(iv ORDER BY ts) AS p, fin_iv_percentile(iv ORDER BY ts) AS q,
    fin_ewma_vol(r ORDER BY ts) AS s, fin_bipower_variation(r ORDER BY ts) AS u
  FROM rr_order_input GROUP BY g;
SET threads = 1;
CREATE OR REPLACE TEMP TABLE rr_order_one AS SELECT * FROM rr_order_metrics();
SET threads = 8;
CREATE OR REPLACE TEMP TABLE rr_order_eight AS SELECT * FROM rr_order_metrics();
RESET threads;
SELECT assert_eq('returns risk order-dependent results are thread invariant', count(*), 0::BIGINT)
FROM (SELECT * FROM rr_order_one EXCEPT SELECT * FROM rr_order_eight);
SELECT assert_eq('returns risk order-dependent results are populated', count(*), 97::BIGINT)
FROM rr_order_one WHERE a IS NOT NULL AND k IS NOT NULL AND l IS NOT NULL AND m IS NOT NULL AND q IS NOT NULL;

-- Non-finite observations make only their own group NULL (no query abort).
WITH observations(g, i, r, b) AS (
  VALUES (1, 1, 0.01, 0.02), (1, 2, 'NaN'::DOUBLE, 0.01), (1, 3, -0.02, 0.0),
         (2, 1, 0.01, 0.01), (2, 2, 0.02, -0.01), (2, 3, -0.01, 0.02)
), metrics AS (
  SELECT g, [fin_volatility(r), fin_sharpe(r), fin_sortino(r), fin_total_return(r), fin_beta(r, b), fin_var(r),
    fin_cvar(r), fin_max_drawdown(r ORDER BY i), fin_downside_deviation(r), fin_hit_ratio(r), fin_ewma_vol(r ORDER BY i),
    fin_trimmed_mean(r), fin_garch11_forecast(r, 0.000001, 0.05, 0.9 ORDER BY i), fin_calmar(r, i), fin_cagr(r),
    fin_omega_ratio(r), fin_drawdown_at_risk(r ORDER BY i), fin_weighted_quantile(r, 1.0, 0.5), fin_win_rate(r),
    fin_upside_deviation(r), fin_semivariance(r), fin_gain_to_pain(r), fin_tail_ratio(r)] AS m
  FROM observations GROUP BY g
)
SELECT
  assert_true('non-finite group is NULL', bool_and(list_bool_and(list_transform(m, lambda x: x IS NULL))) FILTER (WHERE g = 1)),
  assert_true('finite group unaffected', bool_and(list_bool_and(list_transform(m, lambda x: x IS NOT NULL))) FILTER (WHERE g = 2))
FROM metrics;

WITH targets AS (SELECT ((i%260)-1)::DOUBLE*.05 AS t FROM range(5000) z(i))
SELECT assert_true('large constant curve binary oracle', bool_and(coalesce(abs(
  fin_curve_zero_rate(list_transform(range(1,129),lambda x: x/10.0),
    list_transform(range(1,129),lambda x: .03+.001*x),t) - (.03+.01*greatest(.1,least(12.8,t))))<1e-12,false)))
FROM targets;

SELECT
  assert_eq('curve unordered knots', fin_curve_zero_rate([1.0,.5,2.0],[.03,.04,.05],1.5), NULL),
  assert_eq('curve duplicate knots', fin_curve_zero_rate([1.0,1.0,2.0],[.03,.04,.05],1.5), NULL),
  assert_eq('curve infinite knots', fin_curve_zero_rate([1.0,'Infinity'::DOUBLE],[.03,.04],1.5), NULL),
  assert_eq('curve infinite values', fin_curve_zero_rate([1.0,2.0],[.03,'Infinity'::DOUBLE],1.5), NULL),
  assert_eq('curve nan target', fin_curve_zero_rate([1.0,2.0],[.03,.04],'NaN'::DOUBLE), NULL),
  assert_near('curve stable interpolation', fin_interpolate_curve([1.0,2.0],[-1e308,1e308],1.5),0.0,1e-12),
  assert_near('discount default continuous', fin_discount_factor(.05,2),exp(-.1),1e-12),
  assert_near('discount convention alias', fin_discount_factor(.05,2,' Semi '),pow(1+.05/2,-4),1e-12),
  assert_near('yearfrac default act365f', fin_yearfrac(DATE '2026-01-01',DATE '2026-07-01'),181.0/365,1e-12),
  assert_near('yearfrac convention alias', fin_yearfrac(DATE '2026-01-01',DATE '2026-07-01',' actual/360 '),181.0/360,1e-12);

SELECT
  assert_eq('weekday offset convenience', fin_next_business_day(DATE '2026-05-08',5), DATE '2026-05-15'),
  assert_eq('weekday reverse offset convenience', fin_prev_business_day(DATE '2026-05-11',5::BIGINT), DATE '2026-05-04'),
  assert_eq('weekday offset null default', fin_next_business_day(DATE '2026-05-08',NULL), NULL),
  assert_eq('weekday bigint overflow guard', fin_next_business_day(DATE '2026-05-08',9223372036854775807::BIGINT), NULL),
  assert_eq('weekday reverse bigint overflow guard', fin_prev_business_day(DATE '2026-05-08',9223372036854775807::BIGINT), NULL),
  assert_eq('weekday bigint full date range', fin_business_days_between(DATE '-5877641-06-25',fin_next_business_day(DATE '-5877641-06-25',2500000000::BIGINT)),2500000000::BIGINT);

SELECT
  assert_eq('curve validator rejects duplicates', fin_validate_curve_spec(fin_curve_spec([1.0,1.0],[.03,.04])).ok,false),
  assert_eq('curve validator rejects null elements', fin_validate_curve_spec(fin_curve_spec([1.0,2.0],[.03,NULL])).ok,false),
  assert_eq('curve validator rejects nonfinite values', fin_validate_curve_spec(fin_curve_spec([1.0,2.0],[.03,'Infinity'::DOUBLE])).ok,false),
  assert_eq('curve validator empty reason', fin_validate_curve_spec(fin_curve_spec([]::DOUBLE[],[]::DOUBLE[])).reason,'curve cannot be empty'),
  assert_eq('curve validator length reason', fin_validate_curve_spec(fin_curve_spec([1.0,2.0],[.03])).reason,'maturity/value length mismatch');

-- Deterministic property sweeps: derivatives, parity, round trips, and calendars.
WITH cases AS (
  SELECT CASE WHEN i % 2 = 0 THEN 'call' ELSE 'put' END AS kind,
         80.0 + (i % 41)::DOUBLE AS s, 85.0 + (i % 31)::DOUBLE AS k,
         0.2 + (i % 19)::DOUBLE / 10 AS t, 0.01 + (i % 7)::DOUBLE / 100 AS r,
         0.10 + (i % 23)::DOUBLE / 100 AS v, (i % 5)::DOUBLE / 100 AS q
  FROM range(400) x(i)
), priced AS (
  SELECT *, fin_bsm_all(kind, s, k, t, r, v, q) AS a FROM cases
)
SELECT
  assert_true('bsm swept parity', bool_and(abs(fin_bsm_price('call', s, k, t, r, v, q) -
    fin_bsm_price('put', s, k, t, r, v, q) - s * exp(-q*t) + k * exp(-r*t)) < 1e-10)),
  assert_true('bsm swept delta derivative', bool_and(abs(a.delta -
    (fin_bsm_price(kind, s+0.001, k, t, r, v, q) - fin_bsm_price(kind, s-0.001, k, t, r, v, q))/0.002) < 1e-8)),
  assert_true('bsm swept gamma derivative', bool_and(abs(a.gamma -
    (fin_bsm_delta(kind, s+0.001, k, t, r, v, q) - fin_bsm_delta(kind, s-0.001, k, t, r, v, q))/0.002) < 1e-8)),
  assert_true('bsm swept vega derivative', bool_and(abs(a.vega -
    (fin_bsm_price(kind, s, k, t, r, v+1e-5, q) - fin_bsm_price(kind, s, k, t, r, v-1e-5, q))/2e-5) < 1e-6)),
  assert_true('bsm swept iv price roundtrip', bool_and(coalesce(abs(a.price -
    fin_bsm_price(kind, s, k, t, r, fin_bsm_implied_vol(kind, a.price, s, k, t, r, q), q)) < 1e-7, false))),
  assert_true('black76 swept model equivalence', bool_and(abs(fin_black76_price(kind, s, k, t, r, v) -
    fin_bsm_price(kind, s, k, t, r, v, r)) < 1e-10)),
  assert_true('bachelier swept parity', bool_and(abs(fin_bachelier_price('call', s-100, k-100, t, r, v*100) -
    fin_bachelier_price('put', s-100, k-100, t, r, v*100) - (s-k)*exp(-r*t)) < 1e-10))
FROM priced;

WITH cases AS (
  SELECT DATE '2024-01-01' + i::INTEGER AS d, n::INTEGER AS n
  FROM range(70) starts(i), range(41) offsets(n)
), oracle AS (
  SELECT *, CASE WHEN n = 0 THEN d ELSE (
    SELECT d + j::INTEGER FROM range(1, 65) days(j) WHERE isodow(d + j::INTEGER) <= 5
    QUALIFY row_number() OVER (ORDER BY j) = n
  ) END AS next_d,
  CASE WHEN n = 0 THEN d ELSE (
    SELECT d - j::INTEGER FROM range(1, 65) days(j) WHERE isodow(d - j::INTEGER) <= 5
    QUALIFY row_number() OVER (ORDER BY j) = n
  ) END AS prev_d
  FROM cases
)
SELECT
  assert_true('next business day swept oracle', bool_and(fin_next_business_day(d, 'weekday', n) IS NOT DISTINCT FROM next_d)),
  assert_true('previous business day swept oracle', bool_and(fin_prev_business_day(d, 'weekday', n) IS NOT DISTINCT FROM prev_d))
FROM oracle;

SELECT
  assert_near('normal pdf', fin_norm_pdf(0.0), 0.3989422804014327, 1e-12),
  assert_near('normal cdf', fin_norm_cdf(0.0), 0.5, 1e-12),
  assert_near('normal inv', fin_norm_inv(0.5), 0.0, 1e-12),
  assert_near('student t symmetry', fin_student_t_cdf(0.0, 10.0), 0.5, 1e-12),
  assert_near('student t inv median', fin_student_t_inv(0.5, 10.0), 0.0, 1e-10),
  assert_near('student t inv lower tail', fin_student_t_inv(0.000001, 2.0), -707.1057205373853, 1e-5),
  assert_near('student t inv upper tail', fin_student_t_inv(0.999999, 2.0), 707.1057205373853, 1e-4),
  assert_near('student t inv tail cdf', fin_student_t_cdf(fin_student_t_inv(0.000001, 2.0), 2.0),
              0.000001, 1e-14),
  assert_near('chi2 cdf zero', fin_chi2_cdf(0.0, 3.0), 0.0, 1e-12),
  assert_near('chi2 inv median', fin_chi2_inv(0.5, 2.0), 1.3862943611198906, 1e-10),
  assert_eq('safe div zero null', fin_safe_div(1.0, 0.0), NULL),
  assert_near('safe div fallback', fin_safe_div(1.0, 0.0, 7.0), 7.0, 1e-12),
  assert_near('bps', fin_bps(0.0123), 123.0, 1e-12),
  assert_near('from bps', fin_from_bps(125.0), 0.0125, 1e-12),
  assert_near('clip upper', fin_clip(12.0, 0.0, 10.0), 10.0, 1e-12),
  assert_near('round to tick', fin_round_to_tick(100.037, 0.05), 100.05, 1e-12);

SELECT
  assert_near('round to tick keeps on-grid price down', fin_round_to_tick(1.13, 0.01, 'down'), 1.13, 0),
  assert_near('round to tick keeps on-grid price up', fin_round_to_tick(1.13, 0.01, 'up'), 1.13, 0),
  assert_near('round to tick down', fin_round_to_tick(1.137, 0.01, 'down'), 1.13, 0),
  assert_near('round to tick up', fin_round_to_tick(1.131, 0.01, 'up'), 1.14, 0),
  assert_eq('discount rejects invalid simple base', fin_discount_factor(-1.0, 1.0, 'simple'), NULL),
  assert_eq('discount rejects invalid periodic base', fin_discount_factor(-2.0, 1.0, 'periodic', 2), NULL);

-- Return transforms.
SELECT
  assert_near('simple return', fin_simple_return(102.0, 100.0), 0.02, 1e-12),
  assert_eq('simple return zero denominator', fin_simple_return(100.0, 0.0), NULL),
  assert_near('log return', fin_log_return(102.0, 100.0), 0.01980262729617973, 1e-12),
  assert_eq('log return nonpositive', fin_log_return(0.0, 100.0), NULL),
  assert_near('excess return annual rf', fin_excess_return(0.01, 0.0252, 252.0), 0.009901234347169599, 1e-12),
  assert_near('generic simple return', fin_return(102.0, 100.0, 'simple'), 0.02, 1e-12),
  assert_near('generic log return', fin_return(102.0, 100.0, 'log'), 0.01980262729617973, 1e-12),
  assert_near('gross return', fin_gross_return(0.02), 1.02, 1e-12),
  assert_near('to log return', fin_to_log_return(0.02), 0.01980262729617973, 1e-12),
  assert_near('from log return', fin_from_log_return(ln(1.02)), 0.02, 1e-12),
  assert_near('price from simple return', fin_price_from_return(100.0, 0.02, 'simple'), 102.0, 1e-12),
  assert_near('price from log return', fin_price_from_return(100.0, ln(1.02), 'log'), 102.0, 1e-12),
  -- log1p/expm1 precision: ln(1 + 1e-17) and exp(1e-17) - 1 both round to 0 in DOUBLE.
  assert_eq('to log return tiny', fin_to_log_return(1e-17), 1e-17),
  assert_eq('from log return tiny', fin_from_log_return(1e-17), 1e-17),
  assert_near('to log return small relative', fin_to_log_return(1e-10) / 9.9999999995e-11, 1.0, 1e-15);

-- Long gain series compound in log space instead of overflowing DOUBLE wealth:
-- 2000 returns of +100% and one -50% give log wealth 1999 ln 2 (wealth > 1e600).
SELECT
  assert_near('cagr survives wealth overflow', fin_cagr(r, 252) / (pow(2.0, 252.0 * 1999 / 2001) - 1), 1.0, 1e-12),
  assert_near('geometric return survives wealth overflow', fin_geometric_return(r), pow(2.0, 1999.0 / 2001) - 1, 1e-12),
  assert_near('log nav survives wealth overflow', fin_log_nav(r, 1.0), 1999 * ln(2), 1e-9),
  assert_near('calmar survives wealth overflow', fin_calmar(r, i, 252) / ((pow(2.0, 252.0 * 1999 / 2001) - 1) / 0.5), 1.0, 1e-12),
  assert_eq('total return overflow is NULL', fin_total_return(r), NULL)
FROM (SELECT i, CASE WHEN i = 1000 THEN -0.5 ELSE 1.0 END AS r FROM range(2001) t(i));

-- Aggregate return and risk metrics over the gold return series.
SELECT
  assert_near('total return', fin_total_return(r), 0.02961247795, 1e-12),
  assert_near('cagr', fin_cagr(r, 252), 3.3527064365220456, 1e-12),
  assert_near('annual return', fin_annual_return(r, 252), 3.3527064365220456, 1e-12),
  assert_near('arithmetic return', fin_arithmetic_return(r), 0.006, 1e-12),
  assert_near('geometric return', fin_geometric_return(r), 0.005853564836320935, 1e-12),
  assert_near('volatility', fin_volatility(r), 0.3043189116699782, 1e-12),
  assert_near('calmar', fin_calmar(r, seq), 167.63532182610447, 1e-10),
  assert_near('sortino', fin_sortino(r), 10.330992777303926, 1e-12),
  -- numpy: e = r - ((1.01)**(1/365) - 1); mean(e) / sqrt(mean(min(e, 0)**2)) * sqrt(365)
  assert_near('sortino optional args', fin_sortino(r, 0.01, 365.0), 12.357037941940932, 1e-10),
  -- numpy: r.mean() / r.std(ddof=1) * sqrt(252), and with a 5% annual rate de-annualized geometrically
  assert_near('sharpe', fin_sharpe(r), 4.96847202726495, 1e-10),
  assert_near('sharpe annual risk free', fin_sharpe(r, 0.05, 252), 4.808130734700137, 1e-10),
  assert_near('downside deviation annual mar', fin_downside_deviation(r, 0.05, 252), 0.14802610630566393, 1e-12),
  assert_near('upside deviation annual threshold', fin_upside_deviation(r, 0.05, 252), 0.24631723727544436, 1e-12),
  assert_near('semivariance annual threshold', fin_semivariance(r, 0.05, 252), 8.695130217466553e-05, 1e-15),
  assert_near('omega annual required return', fin_omega_ratio(r, 0.05, 252), 2.143559655857057, 1e-10),
  assert_near('hit ratio annual threshold', fin_hit_ratio(r, 2.0, 252), 0.6, 1e-12),
  assert_near('max drawdown', fin_max_drawdown(r ORDER BY seq), -0.02, 1e-12),
  assert_near('avg drawdown', fin_avg_drawdown(r ORDER BY seq), -0.005, 1e-12),
  assert_eq('drawdown duration', fin_drawdown_duration(r ORDER BY seq), 1::BIGINT),
  assert_near('ulcer index', fin_ulcer_index(r ORDER BY seq), 0.009219544457292884, 1e-12),
  assert_near('beta', fin_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_near('tracking error', fin_tracking_error(r, benchmark_r), 0.13535287215275485, 1e-12),
  assert_near('quantile spread', fin_quantile_spread(factor, forward_return, 2), 0.009, 1e-12)
FROM gold_returns;

-- Explicit-axis trend: hand-calculated noisy fit (Sxx=10, Sxy=6, SSE=2.4).
WITH points(x, y) AS (
  VALUES (1.0, 2.0), (2.0, 4.0), (3.0, 5.0), (4.0, 4.0), (5.0, 5.0),
         (NULL, 900.0), (900.0, NULL), (NULL, 'NaN'::DOUBLE)
), fitted AS (SELECT fin_linear_trend(y, x := x) AS t FROM points)
SELECT assert_near('trend noisy slope', t.slope, 0.6, 1e-12),
       assert_near('trend noisy intercept', t.intercept, 2.2, 1e-12),
       assert_near('trend noisy r2', t.r2, 0.6, 1e-12),
       assert_near('trend noisy slope stderr', t.stderr, sqrt(0.08), 1e-12)
FROM fitted;

WITH points(g, x, y) AS (
  VALUES ('up', 1.0, 3.0), ('up', 2.0, 5.0), ('up', 3.0, 7.0),
         ('down', 1.0, 7.0), ('down', 2.0, 5.0), ('down', 3.0, 3.0),
         ('flat', 1.0, 5.0), ('flat', 2.0, 5.0), ('flat', 3.0, 5.0)
), fitted AS (SELECT g, fin_linear_trend(y, x := x) AS t FROM points GROUP BY g)
SELECT assert_near('trend grouped slope', t.slope,
                    CASE g WHEN 'up' THEN 2 WHEN 'down' THEN -2 ELSE 0 END, 1e-12),
       assert_near('trend grouped intercept', t.intercept,
                    CASE g WHEN 'up' THEN 1 WHEN 'down' THEN 9 ELSE 5 END, 1e-12),
       assert_near('trend grouped r2', t.r2, 1.0, 1e-12),
       assert_near('trend grouped stderr', t.stderr, 0.0, 1e-12)
FROM fitted;

WITH points(g, x, y) AS (
  VALUES ('single', 1.0, 3.0), ('constant_x', 1.0, 3.0),
         ('constant_x', 1.0, 4.0), ('constant_x', 1.0, 5.0),
         ('missing_y', 1.0, NULL), ('nonfinite', 'Infinity'::DOUBLE, 2.0)
), fitted AS (SELECT g, fin_linear_trend(y, x := x) AS t FROM points GROUP BY g)
SELECT assert_eq('trend degenerate slope', t.slope, NULL),
       assert_eq('trend degenerate intercept', t.intercept, NULL),
       assert_eq('trend degenerate r2', t.r2, NULL),
       assert_eq('trend degenerate stderr', t.stderr, NULL)
FROM fitted;

WITH fitted AS (
  SELECT fin_linear_trend(y, x := x) AS t FROM (VALUES (1, 3), (2, 5)) p(x,y)
)
SELECT assert_near('trend two point slope', t.slope, 2.0, 1e-12),
       assert_near('trend two point intercept', t.intercept, 1.0, 1e-12),
       assert_eq('trend two point stderr', t.stderr, NULL)
FROM fitted;

-- A complete NaN/inf pair makes the whole trend NULL (0.3.0 non-finite policy).
SELECT assert_eq('trend nonfinite pair is NULL', fin_linear_trend(y, x), NULL)
FROM (VALUES (1.0, 2.0), (2.0, 4.0), (3.0, 5.0), ('Infinity'::DOUBLE, 8.0)) p(x, y);

WITH fitted AS (
  SELECT fin_linear_trend(y, x := x) AS t
  FROM (VALUES (NULL::DOUBLE, 2.0), (NULL, 4.0), (NULL, NULL)) p(x, y)
)
SELECT assert_eq('trend all null axis slope', t.slope, NULL),
       assert_eq('trend all null axis intercept', t.intercept, NULL),
       assert_eq('trend all null axis r2', t.r2, NULL),
       assert_eq('trend all null axis stderr', t.stderr, NULL)
FROM fitted;

WITH fitted AS (
  SELECT fin_linear_trend(y, x := x) AS t
  FROM (SELECT 1.0 x, 2.0 y WHERE false) p
)
SELECT assert_eq('trend empty slope', t.slope, NULL),
       assert_eq('trend empty intercept', t.intercept, NULL),
       assert_eq('trend empty r2', t.r2, NULL),
       assert_eq('trend empty stderr', t.stderr, NULL)
FROM fitted;

-- Center large levels before fitting, preserving group-specific origins.
-- Exact reference: Sxx=85850, slope=2, SSE=1275/202, n=101.
WITH observations AS (
  SELECT level, level + i::DOUBLE AS x,
         level + 2 * i::DOUBLE + CASE WHEN i % 2 = 0 THEN 0.25 ELSE -0.25 END AS y
  FROM (VALUES (1e15), (1e12)) levels(level), range(1, 102) t(i)
), centered AS (
  SELECT *, min(x) OVER (PARTITION BY level) AS x_origin,
            min(y) OVER (PARTITION BY level) AS y_origin
  FROM observations
), fitted AS (
  SELECT level, fin_linear_trend(y - y_origin, x := x - x_origin) AS t
  FROM centered GROUP BY level
)
SELECT assert_near('centered trend slope', t.slope, 2.0, 1e-12),
       assert_near('centered trend intercept', t.intercept, 25.0 / 101, 1e-12),
       assert_near('centered trend stderr', t.stderr,
                   sqrt((1275.0 / 202) / 99 / 85850), 1e-12)
FROM fitted;

WITH parameterized_returns(seq, r) AS (
  VALUES (1, 0.10), (2, -0.05), (3, 0.02)
)
SELECT
  assert_near('sortino constant annualization ascending order',
    fin_sortino(r, 0.0, 365.0 ORDER BY seq),
    fin_sortino(r, 0.0, 365.0 ORDER BY seq DESC), 1e-12)
FROM parameterized_returns;

WITH quantile_spread_inputs(seq, factor, forward_return) AS (
  SELECT i, i::DOUBLE, i::DOUBLE
  FROM generate_series(1, 10) AS t(i)
)
SELECT
  assert_near('quantile spread fixed buckets ascending',
    fin_quantile_spread(factor, forward_return, 5 ORDER BY seq), 8.0, 1e-12),
  assert_near('quantile spread fixed buckets descending',
    fin_quantile_spread(factor, forward_return, 5 ORDER BY seq DESC), 8.0, 1e-12)
FROM quantile_spread_inputs;

SELECT
  assert_near('constant scalar with aggregate', constant_simple_return, 0.05, 1e-12),
  assert_near('aggregate with constant scalar', total_return, 0.02961247795, 1e-12)
FROM (
  SELECT fin_simple_return(105.0, 100.0) AS constant_simple_return, fin_total_return(r) AS total_return
  FROM gold_returns
);

SELECT
  assert_near('cum return', fin_cum_return(r), 0.02961247795, 1e-12),
  assert_near('nav', fin_nav(r, 100.0), 102.961247795, 1e-9),
  assert_near('log nav', fin_log_nav(r, 100.0), 4.634352682435491, 1e-12),
  assert_near('recovery factor', fin_recovery_factor(r, seq), 1.4806238974999983, 1e-10),
  -- Bacon: sum(r) / |sum(r | r < 0)| = 0.03 / 0.025.
  assert_near('gain to pain', fin_gain_to_pain(r), 1.2, 1e-12),
  assert_near('aggregate return', fin_aggregate_return(r), 0.02961247795, 1e-12),
  assert_near('downside deviation', fin_downside_deviation(r), 0.14635573101180563, 1e-12),
  assert_near('upside deviation', fin_upside_deviation(r), 0.24847535089018388, 1e-12),
  assert_near('semivariance', fin_semivariance(r), 0.000085, 1e-12),
  assert_near('omega ratio', fin_omega_ratio(r), 2.2, 1e-12),
  assert_near('tail ratio', fin_tail_ratio(r), 1.5882352941176467, 1e-12),
  -- empyrical stability_of_timeseries: linregress(arange(n), cumsum(log1p(r))).rvalue**2
  assert_near('stability', fin_stability(r ORDER BY seq), 0.5541954553876519, 1e-12),
  assert_near('stability reversed order', fin_stability(r ORDER BY seq DESC), 0.5121894176470182, 1e-12),
  assert_not_null('information ratio', fin_information_ratio(r, benchmark_r)),
  assert_near('active return', fin_active_return(r, benchmark_r), -0.20160000000000017, 1e-12),
  assert_not_null('alpha', fin_alpha(r, benchmark_r)),
  assert_near('alpha annual risk free', fin_alpha(r, benchmark_r, 0.05, 252), -1.3610178461015328, 1e-10),
  assert_near('alpha beta beta', (fin_alpha_beta(r, benchmark_r)).beta, 1.6964285714285716, 1e-12),
  assert_near('treynor', fin_treynor_ratio(r, benchmark_r), 0.8912842105263157, 1e-12),
  assert_near('treynor annual risk free', fin_treynor_ratio(r, benchmark_r, 0.05, 252), 0.862520908333173, 1e-10),
  assert_not_null('jensen', fin_jensen_alpha(r, benchmark_r)),
  assert_not_null('up capture', fin_up_capture(r, benchmark_r)),
  assert_not_null('down capture', fin_down_capture(r, benchmark_r)),
  assert_near('hit ratio', fin_hit_ratio(r), 0.6, 1e-12),
  assert_near('win rate', fin_win_rate(r), 0.6, 1e-12),
  assert_near('loss rate', fin_loss_rate(r), 0.4, 1e-12),
  assert_near('payoff ratio', fin_payoff_ratio(r), 1.4666666666666666, 1e-12),
  assert_near('profit factor', fin_profit_factor(r), 2.2, 1e-12),
  assert_near('expectancy', fin_expectancy(r), 0.006, 1e-12),
  -- numpy/scipy references: quantile(r, .05) linear; normal and Cornish-Fisher with sample sd
  -- and population skewness/excess kurtosis.
  assert_near('var', fin_var(r), 0.017, 1e-12),
  assert_near('var parametric', fin_var(r, 0.95, 'parametric'), 0.025532320234642823, 1e-10),
  assert_near('var cornish fisher', fin_var(r, 0.95, 'cornish_fisher'), 0.02688471727971002, 1e-10),
  assert_near('var signed return', fin_var(r, 0.95, 'historical', false), -0.017, 1e-12),
  assert_near('cvar alias', fin_cvar(r), 0.02, 1e-12),
  assert_near('cvar parametric', fin_cvar(r, 0.95, 'parametric'), 0.033542801701432, 1e-10),
  assert_not_null('expected shortfall alias', fin_expected_shortfall(r)),
  assert_near('drawdown direct', fin_drawdown(r), -0.005, 1e-12),
  -- Drawdown magnitudes 1 - NAV/peak = [0, .02, 0, 0, .005]; numpy quantile(D, c).
  assert_near('drawdown at risk', fin_drawdown_at_risk(r ORDER BY seq), 0.017, 1e-12),
  assert_near('drawdown at risk 80', fin_drawdown_at_risk(r, 0.8 ORDER BY seq), 0.008, 1e-12),
  assert_near('conditional drawdown at risk', fin_conditional_drawdown_at_risk(r ORDER BY seq), 0.02, 1e-12),
  assert_near('conditional drawdown at risk 80', fin_conditional_drawdown_at_risk(r, 0.8 ORDER BY seq), 0.02, 1e-12),
  assert_near('parametric var', fin_parametric_var(0.0, 0.2, 0.95), 0.3289707253902946, 1e-10),
  assert_near('parametric cvar', fin_parametric_cvar(0.0, 0.2, 0.95), 0.4125425615014851, 1e-10),
  -- scipy: -(0.2 * sqrt(3/5) * t.ppf(.05, 5)) and the matching standardized-t expected shortfall.
  assert_near('parametric var student t', fin_parametric_var(0.0, 0.2, 0.95, 1.0, 't', 5), 0.3121699516688459, 1e-8),
  assert_near('parametric cvar student t', fin_parametric_cvar(0.0, 0.2, 0.95, 1.0, 't', 5), 0.4477368510923045, 1e-8)
FROM gold_returns;

WITH outlier_inputs(seq, x) AS (
  VALUES (1, 0.0), (2, 0.0), (3, 0.0), (4, 10.0)
)
SELECT
  assert_eq('outlier constant threshold ascending order',
    fin_outlier_count(x, 'zscore', 1.0 ORDER BY seq), 1::BIGINT),
  assert_eq('outlier constant threshold descending order',
    fin_outlier_count(x, 'zscore', 1.0 ORDER BY seq DESC), 1::BIGINT)
FROM outlier_inputs;

SELECT
  assert_near('realized variance', fin_realized_variance(r, 252), 0.08316, 1e-12),
  assert_near('realized vol', fin_realized_vol(r, 252), 0.28837475617674996, 1e-12),
  assert_near('bipower variation', fin_bipower_variation(r, 252 ORDER BY seq), 0.13112222337920398, 1e-12),
  assert_near('realized quarticity', fin_realized_quarticity(r, 252), 0.0004331249999999999, 1e-12),
  assert_not_null('vol of vol', fin_vol_of_vol(abs(r), 252)),
  assert_near('realized beta', fin_realized_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_not_null('realized corr', fin_realized_corr(r, benchmark_r)),
  assert_not_null('realized cov', fin_realized_cov(r, benchmark_r)),
  -- Python recursion s2 = omega + alpha r^2 + beta s2 seeded with var(r, ddof=1).
  assert_near('garch forecast', fin_garch11_forecast(r, 0.000001, 0.05, 0.90 ORDER BY seq), 0.07226999009999999, 1e-14),
  assert_near('garch forecast explicit seed', fin_garch11_forecast(r, 0.000001, 0.05, 0.90, 0.0004, 1 ORDER BY seq), 0.0003059766, 1e-15),
  assert_near('garch forecast null seed', fin_garch11_forecast(r, 0.000001, 0.05, 0.90, NULL, 252 ORDER BY seq), 0.07226999009999999, 1e-14)
FROM gold_returns;

WITH alternating_zero_returns(seq, r) AS (
  VALUES (1, 0.01), (2, 0.0), (3, -0.02), (4, 0.0)
)
SELECT
  assert_near('bipower variation uses adjacent returns',
    fin_bipower_variation(r ORDER BY seq), 0.0, 1e-12)
FROM alternating_zero_returns;

SELECT assert_eq(
  'bipower variation needs adjacent returns',
  fin_bipower_variation(r),
  NULL
)
FROM (VALUES (0.01)) AS single_return(r);

SELECT
  assert_not_null('parkinson vol', fin_parkinson_vol(high, low, 252.0)),
  assert_near('garman klass vol', fin_garman_klass_vol(open, high, low, close, 252.0), 0.37521992640640556, 1e-12),
  assert_near('rogers satchell vol', fin_rogers_satchell_vol(open, high, low, close, 252.0), 0.3466768621656672, 1e-12),
  -- Yang and Zhang (2000) over periods 2..N (numpy reference, sample variances).
  assert_near('yang zhang vol', fin_yang_zhang_vol(open, high, low, close, 252.0 ORDER BY seq), 0.3951310192495169, 1e-12),
  assert_near('yang zhang vol default annualization', fin_yang_zhang_vol(open, high, low, close ORDER BY seq), 0.3951310192495169, 1e-12)
FROM gold_prices;

SELECT
  assert_near('kahan sum', fin_kahan_sum(r), 0.03, 1e-12),
  assert_near('stable mean', fin_stable_mean(r), 0.006, 1e-12),
  assert_not_null('stable var', fin_stable_var(r)),
  assert_not_null('stable stddev', fin_stable_stddev(r)),
  assert_not_null('stable cov', fin_stable_cov(r, benchmark_r)),
  assert_not_null('stable corr', fin_stable_corr(r, benchmark_r)),
  assert_not_null('weighted mean', fin_weighted_mean(r, factor)),
  assert_not_null('weighted var', fin_weighted_var(r, factor)),
  assert_not_null('weighted stddev', fin_weighted_stddev(r, factor)),
  assert_not_null('weighted quantile', fin_weighted_quantile(r, factor, 0.5)),
  assert_not_null('winsorized mean alias', fin_winsorized_mean(r)),
  assert_not_null('trimmed mean alias', fin_trimmed_mean(r)),
  assert_not_null('mad', fin_mad(r)),
  assert_near('zscore last', fin_zscore_last(r, seq), -0.5738045840530311, 1e-12),
  assert_near('entropy of a single category', fin_entropy(asset), 0.0, 1e-12)
FROM gold_returns;

-- Statistical tests and association measures on gold_stats. Expected values:
-- scipy 1.16 (ttest_1samp, ttest_ind, ks_2samp statistic, kstwobign with
-- Stephens' correction, mannwhitneyu(method='asymptotic'), f_oneway,
-- spearmanr, kendalltau, contingency.association), sklearn mutual_info_score
-- on numpy histogram2d counts, and the Bergsma bias-corrected Cramer's V.
SELECT
  assert_near('ttest 1samp stat', (fin_ttest_1samp(x, 0.1)).stat, 0.05931848307317688, 1e-12),
  assert_near('ttest 1samp pvalue', (fin_ttest_1samp(x, 0.1)).pvalue, 0.9528862023830069, 1e-12),
  assert_eq('ttest 1samp df', (fin_ttest_1samp(x, 0.1)).df, 63.0::DOUBLE),
  assert_near('ttest 2samp pooled stat', (fin_ttest_2samp(x, y)).stat, 0.34314108933029613, 1e-12),
  assert_near('ttest 2samp pooled pvalue', (fin_ttest_2samp(x, y)).pvalue, 0.732064168020113, 1e-12),
  assert_eq('ttest 2samp pooled df', (fin_ttest_2samp(x, y)).df, 126.0::DOUBLE),
  assert_near('welch stat', (fin_welch_ttest(x, y)).stat, 0.3431410893302961, 1e-12),
  assert_near('welch pvalue', (fin_welch_ttest(x, y)).pvalue, 0.7320642879871965, 1e-12),
  assert_near('welch satterthwaite df', (fin_welch_ttest(x, y)).df, 125.97354285382625, 1e-9),
  assert_near('ttest unequal var named', (fin_ttest_2samp(x, y, equal_var := false)).df, 125.97354285382625, 1e-9),
  assert_eq('ttest df type', typeof((fin_ttest_2samp(x, y)).df), 'DOUBLE'),
  assert_near('ztest sample sigma stat', (fin_ztest_mean(x, 0.1)).stat, 0.05931848307317688, 1e-12),
  assert_near('ztest sample sigma pvalue', (fin_ztest_mean(x, 0.1)).pvalue, 0.9526984396725346, 1e-12),
  assert_near('ztest known sigma stat', (fin_ztest_mean(x, 0.1, 0.8)).stat, 0.058103649502982135, 1e-12),
  assert_near('ztest known sigma pvalue', (fin_ztest_mean(x, 0.1, 0.8)).pvalue, 0.9536660674235217, 1e-12),
  assert_near('ks stat', (fin_ks_test(x, y)).stat, 0.140625, 1e-15),
  assert_near('ks asymptotic pvalue', (fin_ks_test(x, y)).pvalue, 0.5197741925453158, 1e-12),
  assert_near('mann whitney u', (fin_mann_whitney_u(x, y)).stat, 2179.5, 1e-9),
  assert_near('mann whitney pvalue', (fin_mann_whitney_u(x, y)).pvalue, 0.53243413305854, 1e-12),
  assert_near('anova f', (fin_anova_oneway(x, g)).f_stat, 0.04221959435491558, 1e-12),
  assert_near('anova pvalue', (fin_anova_oneway(x, g)).pvalue, 0.9586872290712113, 1e-12),
  assert_eq('anova df', [(fin_anova_oneway(x, g)).df_between, (fin_anova_oneway(x, g)).df_within], [2.0, 61.0]),
  assert_near('anova varchar groups', (fin_anova_oneway(x, 'g' || g)).f_stat, 0.04221959435491558, 1e-12),
  assert_near('spearman rank corr', fin_rank_corr(x, y), 0.3975640191453417, 1e-12),
  assert_near('kendall tau-b', fin_rank_corr(x, y, 'kendall'), 0.29436592920776256, 1e-12),
  assert_near('factor ic spearman default', fin_factor_ic(x, y), 0.3975640191453417, 1e-12),
  assert_near('factor ic pearson', fin_factor_ic(x, y, 'pearson'), 0.4350683747600051, 1e-12),
  assert_near('rank ic', fin_rank_ic(x, y), 0.3975640191453417, 1e-12),
  assert_near('mutual information 5 bins', fin_mutual_information(x, y, 5), 0.30273720906793783, 1e-12),
  assert_near('cramers v uncorrected', fin_cramers_v(g, h, false), 0.33686123029444703, 1e-12),
  assert_near('cramers v bias corrected', fin_cramers_v(g, h), 0.2905324612645811, 1e-12),
  assert_near('theils u', fin_theils_u(g, h), 0.10850540650785828, 1e-12),
  assert_near('cramers v perfect association', fin_cramers_v(g, 'k' || g, false), 1.0, 1e-12),
  assert_eq('theils u constant x is NULL', fin_theils_u(1, h), NULL),
  assert_eq('ttest nonfinite input is NULL', fin_ttest_1samp(CASE WHEN i = 3 THEN 'NaN'::DOUBLE ELSE x END, 0.0), NULL),
  assert_eq('rank corr nonfinite input is NULL', fin_rank_corr(CASE WHEN i = 3 THEN 'Infinity'::DOUBLE ELSE x END, y), NULL)
FROM gold_stats;

SELECT
  assert_eq('ttest single row is NULL', fin_ttest_1samp(x, 0.0), NULL),
  assert_eq('two-sample ttest one row per sample is NULL', fin_ttest_2samp(x, x), NULL),
  assert_eq('ks empty sample is NULL', fin_ks_test(x, NULL::DOUBLE), NULL),
  assert_eq('anova single group is NULL', fin_anova_oneway(x, 1), NULL)
FROM (VALUES (1.0)) t(x);

-- Two-sample tests take independent NULLs in x and y.
SELECT assert_near('ks with independent nulls', (fin_ks_test(x, y)).stat, 1.0, 1e-15),
       assert_near('mann whitney with independent nulls', (fin_mann_whitney_u(x, y)).stat, 0.0, 1e-15)
FROM (VALUES (1.0, NULL), (2.0, 5.0), (NULL, 6.0), (3.0, 7.0)) t(x, y);

-- Weighted, robust, and tail statistics must honor every public parameter.
SELECT
  assert_near('weighted population variance', fin_weighted_var(x, w, 0), 2.0 / 3.0, 1e-12),
  assert_near('weighted sample variance', fin_weighted_var(x, w, 1), 1.0, 1e-12)
FROM (VALUES (1.0, 1.0), (2.0, 1.0), (3.0, 1.0)) AS weighted_values(x, w);

SELECT
  assert_near('weighted variance large offset', fin_weighted_var(x, w, 0), 2.0 / 3.0, 1e-12),
  assert_near('weighted stddev large offset', fin_weighted_stddev(x, w, 0), sqrt(2.0 / 3.0), 1e-12)
FROM (VALUES (1000000000001.0, 1.0), (1000000000002.0, 1.0), (1000000000003.0, 1.0)) AS weighted_offset(x, w);

SELECT assert_near('weighted null pairs', fin_weighted_mean(x, w), 2.0, 1e-12)
FROM (VALUES (1.0, 1.0), (NULL, 100.0), (3.0, 1.0)) AS weighted_nulls(x, w);

-- Zero-weight rows fix the group's ddof but do not contribute moments.
-- Rows with any NULL argument are skipped before validating ddof.
SELECT
  assert_near('weighted zero weight mean', fin_weighted_mean(CASE WHEN ddof IS NOT NULL THEN x END, w), 2.0, 1e-12),
  assert_near('weighted skipped ddof sample variance', fin_weighted_var(x, w, ddof), 2.0, 1e-12),
  assert_near('weighted skipped ddof sample stddev', fin_weighted_stddev(x, w, ddof), sqrt(2.0), 1e-12)
FROM (VALUES (999.0, 0.0, 1.0), (1.0, 1.0, 1.0), (3.0, 1.0, 1.0),
  (NULL, 1.0, -1.0), (100.0, NULL, -1.0), (100.0, 1.0, NULL)) AS weighted_skips(x, w, ddof);

SELECT
  assert_eq('weighted zero total mean', fin_weighted_mean(x, w), NULL),
  assert_eq('weighted zero total variance', fin_weighted_var(x, w, 0), NULL),
  assert_eq('weighted exhausted denominator', fin_weighted_var(x, 1.0, 2), NULL)
FROM (VALUES (1.0, 0.0), (3.0, 0.0)) AS weighted_zero(x, w);

-- A moving frame spanning multiple chunks also contains runs of zero weights.
-- Every contributing value is 7, so the moments are known independently.
WITH results AS (
  SELECT i,
    fin_weighted_mean(7.0, w) OVER frame AS mean,
    fin_weighted_var(7.0, w, 1) OVER frame AS variance
  FROM (SELECT i, CASE WHEN i < 4096 THEN 0.0 ELSE 1.0 END AS w FROM range(8192) AS r(i))
  WINDOW frame AS (ORDER BY i ROWS BETWEEN 2048 PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('weighted window zero states', bool_and(mean IS NULL AND variance IS NULL) FILTER (WHERE i < 4096)),
  assert_near('weighted window first contribution', max(mean) FILTER (WHERE i = 4096), 7.0, 1e-12),
  assert_eq('weighted window exhausted denominator', max(variance) FILTER (WHERE i = 4096), NULL),
  assert_true('weighted window combined moments', bool_and(mean = 7.0 AND variance = 0.0) FILTER (WHERE i > 4096))
FROM results;

SELECT
  assert_near('weighted median honors weights', fin_weighted_quantile(x, w, 0.5), 1.0, 1e-12),
  assert_near('weighted inverted cdf', fin_weighted_quantile(x, w, 0.995, 'inverted_cdf'), 100.0, 1e-12)
FROM (VALUES (1.0, 100.0), (100.0, 1.0)) AS weighted_tail(x, w);

SELECT
  assert_near('winsorized mean honors bounds', fin_winsorized_mean(x, 0.0, 0.5), 0.0, 1e-12),
  assert_near('trimmed mean honors bounds', fin_trimmed_mean(x, 0.0, 0.5), 0.0, 1e-12)
FROM (VALUES (0.0), (0.0), (100.0)) AS robust_values(x);

-- Ternary aggregates skip a row when any input is NULL, before validating
-- the other parameters, and route surviving rows to their own group state.
WITH inputs(g, x, lower_q, upper_q) AS (
  VALUES
    ('a', 0.0, 0.0, 1.0), ('b', 2.0, 0.0, 1.0),
    ('a', 0.0, 0.0, 1.0), ('b', 2.0, 0.0, 1.0),
    ('a', 10.0, 0.0, 1.0), ('b', 2.0, 0.0, 1.0),
    ('a', NULL, -1.0, 2.0), ('b', 999.0, NULL, -1.0),
    ('a', 999.0, -1.0, NULL), ('nulls', NULL, -1.0, 2.0),
    ('nulls', 999.0, NULL, -1.0), ('nulls', 999.0, -1.0, NULL)
), results AS (
  SELECT g, fin_winsorized_mean(x, lower_q, upper_q) AS actual
  FROM inputs GROUP BY g
)
SELECT
  assert_eq('numeric ternary group count', count(*), 3::BIGINT),
  assert_near('numeric ternary first group', max(actual) FILTER (WHERE g = 'a'), 10.0 / 3.0, 1e-12),
  assert_near('numeric ternary second group', max(actual) FILTER (WHERE g = 'b'), 2.0, 1e-12),
  assert_eq('numeric ternary all skipped group', max(actual) FILTER (WHERE g = 'nulls'), NULL)
FROM results;

WITH inputs(g, x, method, threshold) AS (
  VALUES
    ('a', 0.0, 'zscore', 1.0), ('b', 2.0, 'zscore', 1.0),
    ('a', 0.0, 'zscore', 1.0), ('b', 2.0, 'zscore', 1.0),
    ('a', 10.0, 'zscore', 1.0), ('b', 2.0, 'zscore', 1.0),
    ('a', NULL, 'invalid', -1.0), ('b', 999.0, NULL, -1.0),
    ('a', 999.0, 'invalid', NULL), ('nulls', NULL, 'invalid', -1.0),
    ('nulls', 999.0, NULL, -1.0), ('nulls', 999.0, 'invalid', NULL)
), results AS (
  SELECT g, fin_outlier_count(x, method, threshold) AS actual
  FROM inputs GROUP BY g
)
SELECT
  assert_eq('string ternary group count', count(*), 3::BIGINT),
  assert_eq('string ternary first group', max(actual) FILTER (WHERE g = 'a'), 1::BIGINT),
  assert_eq('string ternary second group', max(actual) FILTER (WHERE g = 'b'), 0::BIGINT),
  assert_eq('string ternary all skipped group', max(actual) FILTER (WHERE g = 'nulls'), 0::BIGINT)
FROM results;

WITH inputs AS (
  SELECT i % 7 AS g, (100 * (i % 7) + i % 3)::DOUBLE AS x
  FROM range(10000) AS r(i) WHERE i % 5 <> 0
), results AS (
  SELECT g, fin_weighted_mean(x, 1.0) AS mean, avg(x) AS expected_mean,
    fin_outlier_count(x, 'zscore', 100.0) AS outliers
  FROM inputs GROUP BY g
)
SELECT
  assert_eq('ternary multi-chunk group count', count(*), 7::BIGINT),
  assert_true('ternary multi-chunk numeric routing',
    bool_and(mean IS NOT NULL AND abs(mean - expected_mean) < 1e-10)),
  assert_true('ternary multi-chunk string routing',
    bool_and(outliers IS NOT NULL AND outliers = 0))
FROM results;

SELECT
  assert_near('historical cvar tail mean', fin_cvar(r, 0.5), 7.5, 1e-12),
  assert_near('historical expected shortfall', fin_expected_shortfall(r, 0.5), 7.5, 1e-12),
  assert_near('historical cvar return sign', fin_cvar(r, 0.5, 'historical', false), -7.5, 1e-12)
FROM (VALUES (-10.0), (-5.0), (0.0), (5.0)) AS tail_returns(r);

-- 1 - 0.9 = 0.09999999999999998 must still select the order statistic it
-- names: with 11 observations the 10% quantile is exactly the second smallest.
SELECT
  assert_near('var snaps fp quantile position', fin_var(r, 0.9), 9.0, 1e-12),
  assert_near('cvar includes var observation', fin_cvar(r, 0.9), 9.5, 1e-12),
  assert_near('cvar 80 includes var observation', fin_cvar(r, 0.8), 9.0, 1e-12)
FROM (SELECT -i::DOUBLE AS r FROM range(11) t(i));

-- Treynor uses the same complete pairs as beta in its numerator.
WITH pairs(r, b) AS (VALUES (0.01, 0.02), (0.03, 0.01), (-0.02, -0.01), (0.5, NULL))
SELECT assert_near('treynor complete pairs', fin_treynor_ratio(r, b, 0.0, 1), (0.02 / 3) / (17.0 / 14.0), 1e-12)
FROM pairs;

-- Invalid OHLC bars make range estimators NULL instead of NaN or an error.
SELECT
  assert_eq('garman klass invalid bar', fin_garman_klass_vol(o, h, l, c), NULL),
  assert_eq('rogers satchell invalid bar', fin_rogers_satchell_vol(o, h, l, c), NULL),
  assert_eq('parkinson invalid bar', fin_parkinson_vol(h, l), NULL),
  assert_eq('yang zhang invalid bar', fin_yang_zhang_vol(o, h, l, c ORDER BY i), NULL)
FROM (VALUES (1, 100.0, 101.0, 99.0, 100.5), (2, 100.0, 99.0, 101.0, 100.0), (3, 100.0, 102.0, 99.0, 101.0)) t(i, o, h, l, c);

SELECT
  assert_eq('empty outlier count', fin_outlier_count(x), 0::BIGINT),
  assert_eq('empty outlier count threshold', fin_outlier_count(x, 2.0), 0::BIGINT),
  assert_eq('empty outlier count method', fin_outlier_count(x, 'zscore', 2.0), 0::BIGINT),
  assert_eq('empty data quality outliers', (fin_data_quality_report(x)).outliers, 0::BIGINT),
  assert_eq('empty volatility', fin_volatility(x), NULL),
  assert_eq('empty var', fin_var(x), NULL)
FROM (SELECT 1.0::DOUBLE AS x WHERE false);

-- Physical row order must not matter; equal timestamps are ordered by value.
SELECT
  assert_near('delta ignores row order', fin_delta(x, t), 2.0, 1e-12),
  assert_eq('last tie takes largest value', fin_last_non_null(x, t), 7.0),
  assert_eq('first skips null value', fin_first_non_null(x, t), 5.0),
  assert_near('pct change ignores row order', fin_pct_change(x, t), 0.4, 1e-12),
  assert_eq('changes skips nulls', fin_changes(x, t), 2::BIGINT),
  assert_eq('resets counts decreases', fin_resets(x, t), 1::BIGINT),
  assert_near('rate uses non-null span', fin_rate(x, t, 'second'), 1.0, 1e-12)
FROM (VALUES
  (TIMESTAMP '2026-01-01 00:00:02', 7.0),
  (TIMESTAMP '2026-01-01 00:00:00', NULL),
  (TIMESTAMP '2026-01-01 00:00:02', 3.0),
  (TIMESTAMP '2026-01-01 00:00:00', 5.0)
) AS t(t, x);

SELECT
  assert_eq('changes empty is zero', fin_changes(x, t), 0::BIGINT),
  assert_eq('resets empty is zero', fin_resets(x, t), 0::BIGINT),
  assert_eq('delta empty is null', fin_delta(x, t), NULL)
FROM (SELECT 1.0 AS x, TIMESTAMP '2026-01-01' AS t WHERE false);

CREATE TEMP TABLE gold_ts_order AS
SELECT i AS g, TIMESTAMP '2026-01-01' + to_seconds(i) AS t, ((i * 7919) % 101)::DOUBLE AS x
FROM range(20000) r(i)
ORDER BY hash(i);
SET threads = 1;
CREATE TEMP TABLE gold_ts_order_t1 AS
SELECT g % 7 AS k, fin_delta(x, t) AS d, fin_pct_change(x, t) AS p, fin_rate(x, t) AS r, fin_changes(x, t) AS c,
  fin_resets(x, t) AS z, fin_first_non_null(x, t) AS f, fin_last_non_null(x, t) AS l
FROM gold_ts_order GROUP BY 1;
SET threads = 8;
SELECT assert_eq('ordered time-series macros thread determinism', count(*), 0::BIGINT)
FROM (
  SELECT g % 7 AS k, fin_delta(x, t) AS d, fin_pct_change(x, t) AS p, fin_rate(x, t) AS r, fin_changes(x, t) AS c,
    fin_resets(x, t) AS z, fin_first_non_null(x, t) AS f, fin_last_non_null(x, t) AS l
  FROM gold_ts_order GROUP BY 1
  EXCEPT SELECT * FROM gold_ts_order_t1
);
RESET threads;

-- Ordered time-series macros take an explicit ordering column; closes are
-- 100, 102, 99, 104, 103 at one-minute steps (independent hand computation).
SELECT
  assert_near('delta aggregate', fin_delta(close, ts), 3.0, 1e-12),
  assert_near('pct change aggregate', fin_pct_change(close, ts), 0.03, 1e-12),
  assert_near('rate aggregate per second', fin_rate(close, ts), 3.0 / 240.0, 1e-15),
  assert_near('rate aggregate per minute', fin_rate(close, ts, 'minute'), 0.75, 1e-12),
  assert_near('rate aggregate per hour', fin_rate(close, ts, 'hours'), 45.0, 1e-12),
  assert_eq('changes aggregate', fin_changes(close, ts), 4::BIGINT),
  assert_eq('resets aggregate', fin_resets(close, ts), 2::BIGINT),
  assert_eq('last non null', fin_last_non_null(close, ts), 103.0),
  assert_eq('first non null', fin_first_non_null(close, ts), 100.0),
  assert_eq('delta return type', typeof(fin_delta(close, ts)), 'DOUBLE'),
  assert_eq('changes return type', typeof(fin_changes(close, ts)), 'BIGINT'),
  assert_eq('ema warm-up before period rows', fin_ema(close ORDER BY seq), NULL),
  -- closes 100, 102, 99, 104, 103 one minute apart; weights 2^-(4 - k) with a 1-minute half-life.
  assert_near('ema halflife', fin_ema_halflife(close, ts, INTERVAL '1 minute'), 198.75 / 1.9375, 1e-12),
  assert_near('exp decay sum', fin_exp_decay_sum(close, ts, INTERVAL '1 minute'), 198.75, 1e-12),
  assert_near('exp decay avg', fin_exp_decay_avg(close, ts, INTERVAL '1 minute'), 198.75 / 1.9375, 1e-12),
  assert_near('exp decay count', fin_exp_decay_count(ts, INTERVAL '1 minute'), 1.9375, 1e-15),
  assert_near('exp decay max', fin_exp_decay_max(close, ts, INTERVAL '1 minute'), 103.0, 1e-12),
  assert_near('exp decay numeric axis', fin_exp_decay_sum(close, epoch(ts), 60.0), 198.75, 1e-12),
  assert_near('rolling zscore', fin_rolling_zscore(close, ts), 0.6751399510385797, 1e-12),
  assert_near('rolling zscore matches zscore_last', fin_rolling_zscore(close, ts) - fin_zscore_last(close, ts), 0.0, 1e-15)
FROM gold_prices;

-- Technical indicators are native TA-Lib-compatible aggregates. Expected values
-- below are TA-Lib outputs (python ta-lib 0.8.1, TA-Lib C 0.6) on gold_bars;
-- fin_hma and the custom-constant fin_kama use independent numpy recursions.
-- Grouped calls return the value at the last ordered row; running windows
-- reproduce the TA-Lib series and are NULL during warm-up.
SELECT
  assert_near('fin_sma(close, 5) grouped', fin_sma(close, 5 ORDER BY i), 104.22399999999993, 1e-08),
  assert_near('fin_sma(close) grouped', fin_sma(close ORDER BY i), 102.45549999999999, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_sma(close, 5) OVER run AS c0,
    fin_sma(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_sma(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_sma(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 101.952, 1e-08),
  assert_near('fin_sma(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 103.136, 1e-08),
  assert_true('fin_sma(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_sma(close) row 19', max(c1) FILTER (WHERE i = 19), 100.583, 1e-08),
  assert_near('fin_sma(close) row 39', max(c1) FILTER (WHERE i = 39), 102.00249999999998, 1e-08)
FROM series;

SELECT
  assert_near('fin_wma(close, 5) grouped', fin_wma(close, 5 ORDER BY i), 103.66999999999987, 1e-08),
  assert_near('fin_wma(close) grouped', fin_wma(close ORDER BY i), 102.8800476190475, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_wma(close, 5) OVER run AS c0,
    fin_wma(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_wma(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_wma(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 102.14599999999999, 1e-08),
  assert_near('fin_wma(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 103.26600000000005, 1e-08),
  assert_true('fin_wma(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_wma(close) row 19', max(c1) FILTER (WHERE i = 19), 100.44990476190476, 1e-08),
  assert_near('fin_wma(close) row 39', max(c1) FILTER (WHERE i = 39), 102.02233333333331, 1e-08)
FROM series;

SELECT
  assert_near('fin_ema(close, 5) grouped', fin_ema(close, 5 ORDER BY i), 103.26225509669199, 1e-08),
  assert_near('fin_ema(close) grouped', fin_ema(close ORDER BY i), 102.74406188643894, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_ema(close, 5) OVER run AS c0,
    fin_ema(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_ema(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_ema(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 101.952, 1e-08),
  assert_near('fin_ema(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 102.73005894523298, 1e-08),
  assert_true('fin_ema(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_ema(close) row 19', max(c1) FILTER (WHERE i = 19), 100.583, 1e-08),
  assert_near('fin_ema(close) row 39', max(c1) FILTER (WHERE i = 39), 101.96284677845344, 1e-08)
FROM series;

SELECT
  assert_near('fin_dema(close, 5) grouped', fin_dema(close, 5 ORDER BY i), 103.1406708547677, 1e-08),
  assert_near('fin_dema(close) grouped', fin_dema(close ORDER BY i), 103.35022365586487, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_dema(close, 5) OVER run AS c0,
    fin_dema(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_dema(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 8)),
  assert_near('fin_dema(close, 5) row 8', max(c0) FILTER (WHERE i = 8), 97.40315555555557, 1e-08),
  assert_near('fin_dema(close, 5) row 33', max(c0) FILTER (WHERE i = 33), 100.49476504400717, 1e-08),
  assert_true('fin_dema(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 38)),
  assert_near('fin_dema(close) row 38', max(c1) FILTER (WHERE i = 38), 102.08189664790092, 1e-08),
  assert_near('fin_dema(close) row 48', max(c1) FILTER (WHERE i = 48), 103.00228398099446, 1e-08)
FROM series;

SELECT
  assert_near('fin_tema(close, 5) grouped', fin_tema(close, 5 ORDER BY i), 102.67461933589873, 1e-08),
  assert_near('fin_tema(close) grouped', fin_tema(close ORDER BY i), 103.53304012053445, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_tema(close, 5) OVER run AS c0,
    fin_tema(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_tema(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 12)),
  assert_near('fin_tema(close, 5) row 12', max(c0) FILTER (WHERE i = 12), 102.89980138393533, 1e-08),
  assert_near('fin_tema(close, 5) row 35', max(c0) FILTER (WHERE i = 35), 98.72602558589409, 1e-08),
  assert_true('fin_tema(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 57)),
  assert_near('fin_tema(close) row 57', max(c1) FILTER (WHERE i = 57), 104.08395270430739, 1e-08),
  assert_near('fin_tema(close) row 58', max(c1) FILTER (WHERE i = 58), 103.89907440083327, 1e-08)
FROM series;

SELECT
  assert_near('fin_trima(close, 6) grouped', fin_trima(close, 6 ORDER BY i), 104.5566666666671, 1e-08),
  assert_near('fin_trima(close, 7) grouped', fin_trima(close, 7 ORDER BY i), 104.37125000000007, 1e-08),
  assert_near('fin_trima(close) grouped', fin_trima(close ORDER BY i), 102.47063636363632, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_trima(close, 6) OVER run AS c0,
    fin_trima(close, 7) OVER run AS c1,
    fin_trima(close) OVER run AS c2
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_trima(close, 6) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_trima(close, 6) row 5', max(c0) FILTER (WHERE i = 5), 101.9125, 1e-08),
  assert_near('fin_trima(close, 6) row 32', max(c0) FILTER (WHERE i = 32), 103.2300000000002, 1e-08),
  assert_true('fin_trima(close, 7) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 6)),
  assert_near('fin_trima(close, 7) row 6', max(c1) FILTER (WHERE i = 6), 101.51062499999999, 1e-08),
  assert_near('fin_trima(close, 7) row 32', max(c1) FILTER (WHERE i = 32), 102.99125000000018, 1e-08),
  assert_true('fin_trima(close) warm-up rows', bool_and(c2 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_trima(close) row 19', max(c2) FILTER (WHERE i = 19), 100.49463636363635, 1e-08),
  assert_near('fin_trima(close) row 39', max(c2) FILTER (WHERE i = 39), 101.64390909090906, 1e-08)
FROM series;

SELECT
  assert_near('fin_t3(close, 3) grouped', fin_t3(close, 3 ORDER BY i), 103.81709038854918, 1e-08),
  assert_near('fin_t3(close, 3, 0.5) grouped', fin_t3(close, 3, 0.5 ORDER BY i), 103.83638450621041, 1e-08),
  assert_eq('fin_t3(close) grouped warm-up', fin_t3(close ORDER BY i), NULL)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_t3(close, 3) OVER run AS c0,
    fin_t3(close, 3, 0.5) OVER run AS c1,
    fin_t3(close) OVER run AS c2
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_t3(close, 3) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 12)),
  assert_near('fin_t3(close, 3) row 12', max(c0) FILTER (WHERE i = 12), 102.56618325757276, 1e-08),
  assert_near('fin_t3(close, 3) row 35', max(c0) FILTER (WHERE i = 35), 99.25901596013618, 1e-08),
  assert_true('fin_t3(close, 3, 0.5) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 12)),
  assert_near('fin_t3(close, 3, 0.5) row 12', max(c1) FILTER (WHERE i = 12), 102.06793758983638, 1e-08),
  assert_near('fin_t3(close, 3, 0.5) row 35', max(c1) FILTER (WHERE i = 35), 99.68894986374828, 1e-08)
FROM series;

SELECT
  assert_near('fin_kama(close) grouped', fin_kama(close ORDER BY i), 101.4712618285204, 1e-08),
  assert_near('fin_kama(close, 5, 3, 20) grouped', fin_kama(close, 5, 3, 20 ORDER BY i), 103.3348130640134, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_kama(close) OVER run AS c0,
    fin_kama(close, 5, 3, 20) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_kama(close) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_kama(close) row 10', max(c0) FILTER (WHERE i = 10), 100.44675007976707, 1e-08),
  assert_near('fin_kama(close) row 34', max(c0) FILTER (WHERE i = 34), 100.82581179722685, 1e-08),
  assert_true('fin_kama(close, 5, 3, 20) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_kama(close, 5, 3, 20) row 5', max(c1) FILTER (WHERE i = 5), 101.26068846709121, 1e-08),
  assert_near('fin_kama(close, 5, 3, 20) row 32', max(c1) FILTER (WHERE i = 32), 102.35159686828713, 1e-08)
FROM series;

SELECT
  assert_near('fin_hma(close, 9) grouped', fin_hma(close, 9 ORDER BY i), 104.65344444444446, 1e-08),
  assert_near('fin_hma(close) grouped', fin_hma(close ORDER BY i), 103.71471385281386, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_hma(close, 9) OVER run AS c0,
    fin_hma(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_hma(close, 9) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_hma(close, 9) row 10', max(c0) FILTER (WHERE i = 10), 99.6234814814815, 1e-08),
  assert_near('fin_hma(close, 9) row 34', max(c0) FILTER (WHERE i = 34), 99.2788148148148, 1e-08),
  assert_true('fin_hma(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 22)),
  assert_near('fin_hma(close) row 22', max(c1) FILTER (WHERE i = 22), 102.36925800865801, 1e-08),
  assert_near('fin_hma(close) row 40', max(c1) FILTER (WHERE i = 40), 102.65942597402598, 1e-08)
FROM series;

SELECT
  assert_near('fin_linearreg(close, 5) grouped', fin_linearreg(close, 5 ORDER BY i), 102.56200000000096, 1e-08),
  assert_near('fin_linearreg(close) grouped', fin_linearreg(close ORDER BY i), 102.9977142857146, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_linearreg(close, 5) OVER run AS c0,
    fin_linearreg(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_linearreg(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_linearreg(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 102.53400000000005, 1e-08),
  assert_near('fin_linearreg(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 103.52600000000017, 1e-08),
  assert_true('fin_linearreg(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_linearreg(close) row 13', max(c1) FILTER (WHERE i = 13), 101.37971428571431, 1e-08),
  assert_near('fin_linearreg(close) row 36', max(c1) FILTER (WHERE i = 36), 101.329142857143, 1e-08)
FROM series;

SELECT
  assert_near('fin_linearreg_slope(close, 5) grouped', fin_linearreg_slope(close, 5 ORDER BY i), -0.8309999999994762, 1e-09),
  assert_near('fin_linearreg_slope(close) grouped', fin_linearreg_slope(close ORDER BY i), -0.024527472527416237, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_linearreg_slope(close, 5) OVER run AS c0,
    fin_linearreg_slope(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_linearreg_slope(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_linearreg_slope(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 0.29100000000002185, 1e-09),
  assert_near('fin_linearreg_slope(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 0.19500000000009096, 1e-09),
  assert_true('fin_linearreg_slope(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_linearreg_slope(close) row 13', max(c1) FILTER (WHERE i = 13), 0.06193406593406886, 1e-09),
  assert_near('fin_linearreg_slope(close) row 36', max(c1) FILTER (WHERE i = 36), 0.06316483516486039, 1e-09)
FROM series;

SELECT
  assert_near('fin_linearreg_intercept(close, 5) grouped', fin_linearreg_intercept(close, 5 ORDER BY i), 105.88599999999887, 1e-08),
  assert_near('fin_linearreg_intercept(close) grouped', fin_linearreg_intercept(close ORDER BY i), 103.31657142857101, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_linearreg_intercept(close, 5) OVER run AS c0,
    fin_linearreg_intercept(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_linearreg_intercept(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_linearreg_intercept(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 101.36999999999996, 1e-08),
  assert_near('fin_linearreg_intercept(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 102.7459999999998, 1e-08),
  assert_true('fin_linearreg_intercept(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_linearreg_intercept(close) row 13', max(c1) FILTER (WHERE i = 13), 100.57457142857142, 1e-08),
  assert_near('fin_linearreg_intercept(close) row 36', max(c1) FILTER (WHERE i = 36), 100.50799999999981, 1e-08)
FROM series;

SELECT
  assert_near('fin_tsf(close, 5) grouped', fin_tsf(close, 5 ORDER BY i), 101.73100000000149, 1e-08),
  assert_near('fin_tsf(close) grouped', fin_tsf(close ORDER BY i), 102.97318681318718, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_tsf(close, 5) OVER run AS c0,
    fin_tsf(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_tsf(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_tsf(close, 5) row 4', max(c0) FILTER (WHERE i = 4), 102.82500000000007, 1e-08),
  assert_near('fin_tsf(close, 5) row 31', max(c0) FILTER (WHERE i = 31), 103.72100000000025, 1e-08),
  assert_true('fin_tsf(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_tsf(close) row 13', max(c1) FILTER (WHERE i = 13), 101.44164835164838, 1e-08),
  assert_near('fin_tsf(close) row 36', max(c1) FILTER (WHERE i = 36), 101.39230769230785, 1e-08)
FROM series;

SELECT
  assert_near('fin_mom(close, 3) grouped', fin_mom(close, 3 ORDER BY i), -4.480000000000004, 1e-09),
  assert_near('fin_mom(close) grouped', fin_mom(close ORDER BY i), -1.490000000000009, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_mom(close, 3) OVER run AS c0,
    fin_mom(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_mom(close, 3) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 3)),
  assert_near('fin_mom(close, 3) row 3', max(c0) FILTER (WHERE i = 3), 2.6099999999999994, 1e-09),
  assert_near('fin_mom(close, 3) row 31', max(c0) FILTER (WHERE i = 31), -0.8100000000000023, 1e-09),
  assert_true('fin_mom(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_mom(close) row 10', max(c1) FILTER (WHERE i = 10), 2.460000000000008, 1e-09),
  assert_near('fin_mom(close) row 34', max(c1) FILTER (WHERE i = 34), 0.12999999999999545, 1e-09)
FROM series;

SELECT
  assert_near('fin_roc(close, 3) grouped', fin_roc(close, 3 ORDER BY i), -4.205388153571765, 1e-09),
  assert_near('fin_roc(close) grouped', fin_roc(close ORDER BY i), -1.4390573691327124, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_roc(close, 3) OVER run AS c0,
    fin_roc(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_roc(close, 3) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 3)),
  assert_near('fin_roc(close, 3) row 3', max(c0) FILTER (WHERE i = 3), 2.589285714285716, 1e-09),
  assert_near('fin_roc(close, 3) row 31', max(c0) FILTER (WHERE i = 31), -0.7890122735242588, 1e-09),
  assert_true('fin_roc(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_roc(close) row 10', max(c1) FILTER (WHERE i = 10), 2.440476190476204, 1e-09),
  assert_near('fin_roc(close) row 34', max(c1) FILTER (WHERE i = 34), 0.13197969543146115, 1e-09)
FROM series;

SELECT
  assert_near('fin_rocp(close, 3) grouped', fin_rocp(close, 3 ORDER BY i), -0.04205388153571767, 1e-09),
  assert_near('fin_rocp(close) grouped', fin_rocp(close ORDER BY i), -0.01439057369132711, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_rocp(close, 3) OVER run AS c0,
    fin_rocp(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_rocp(close, 3) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 3)),
  assert_near('fin_rocp(close, 3) row 3', max(c0) FILTER (WHERE i = 3), 0.025892857142857138, 1e-09),
  assert_near('fin_rocp(close, 3) row 31', max(c0) FILTER (WHERE i = 31), -0.007890122735242571, 1e-09),
  assert_true('fin_rocp(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_rocp(close) row 10', max(c1) FILTER (WHERE i = 10), 0.024404761904761985, 1e-09),
  assert_near('fin_rocp(close) row 34', max(c1) FILTER (WHERE i = 34), 0.0013197969543146746, 1e-09)
FROM series;

SELECT
  assert_near('fin_rocr(close, 3) grouped', fin_rocr(close, 3 ORDER BY i), 0.9579461184642823, 1e-09),
  assert_near('fin_rocr(close) grouped', fin_rocr(close ORDER BY i), 0.9856094263086729, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_rocr(close, 3) OVER run AS c0,
    fin_rocr(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_rocr(close, 3) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 3)),
  assert_near('fin_rocr(close, 3) row 3', max(c0) FILTER (WHERE i = 3), 1.0258928571428572, 1e-09),
  assert_near('fin_rocr(close, 3) row 31', max(c0) FILTER (WHERE i = 31), 0.9921098772647574, 1e-09),
  assert_true('fin_rocr(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_rocr(close) row 10', max(c1) FILTER (WHERE i = 10), 1.024404761904762, 1e-09),
  assert_near('fin_rocr(close) row 34', max(c1) FILTER (WHERE i = 34), 1.0013197969543146, 1e-09)
FROM series;

SELECT
  assert_near('fin_rocr100(close, 3) grouped', fin_rocr100(close, 3 ORDER BY i), 95.79461184642824, 1e-08),
  assert_near('fin_rocr100(close) grouped', fin_rocr100(close ORDER BY i), 98.56094263086729, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_rocr100(close, 3) OVER run AS c0,
    fin_rocr100(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_rocr100(close, 3) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 3)),
  assert_near('fin_rocr100(close, 3) row 3', max(c0) FILTER (WHERE i = 3), 102.58928571428572, 1e-08),
  assert_near('fin_rocr100(close, 3) row 31', max(c0) FILTER (WHERE i = 31), 99.21098772647574, 1e-08),
  assert_true('fin_rocr100(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_rocr100(close) row 10', max(c1) FILTER (WHERE i = 10), 102.4404761904762, 1e-08),
  assert_near('fin_rocr100(close) row 34', max(c1) FILTER (WHERE i = 34), 100.13197969543145, 1e-08)
FROM series;

-- Volatility, directional movement and volume indicators are native TA-Lib
-- aggregates. Expected values are TA-Lib outputs (python ta-lib 0.8.1, TA-Lib C
-- 0.6) on gold_vbars; grouped calls return the last ordered row and running
-- windows reproduce the TA-Lib series (NULL during warm-up).
SELECT assert_near('fin_true_range(high, low, close) grouped', fin_true_range(high, low, close ORDER BY i), 1.7800000000000011, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_true_range(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_true_range(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_true_range(high, low, close) row 1', max(v) FILTER (WHERE i = 1), 1.9099999999999966, 1e-08),
  assert_near('fin_true_range(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 3.660000000000011, 1e-08),
  assert_near('fin_true_range(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 1.7800000000000011, 1e-08)
FROM series;

SELECT assert_near('fin_atr(high, low, close) grouped', fin_atr(high, low, close ORDER BY i), 2.364580800273236, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_atr(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_atr(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_atr(high, low, close) row 14', max(v) FILTER (WHERE i = 14), 2.260714285714286, 1e-08),
  assert_near('fin_atr(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 2.463472186342371, 1e-08),
  assert_near('fin_atr(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 2.364580800273236, 1e-08)
FROM series;

SELECT assert_near('fin_atr(high, low, close, 5) grouped', fin_atr(high, low, close, 5 ORDER BY i), 2.361495557390808, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_atr(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_atr(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_atr(high, low, close, 5) row 5', max(v) FILTER (WHERE i = 5), 2.325999999999999, 1e-08),
  assert_near('fin_atr(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 2.5835674449770676, 1e-08),
  assert_near('fin_atr(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 2.361495557390808, 1e-08)
FROM series;

SELECT assert_near('fin_natr(high, low, close) grouped', fin_natr(high, low, close ORDER BY i), 2.3170806470095404, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_natr(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_natr(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_natr(high, low, close) row 14', max(v) FILTER (WHERE i = 14), 2.2679717954597574, 1e-08),
  assert_near('fin_natr(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 2.4187257597863243, 1e-08),
  assert_near('fin_natr(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 2.3170806470095404, 1e-08)
FROM series;

SELECT assert_near('fin_natr(high, low, close, 5) grouped', fin_natr(high, low, close, 5 ORDER BY i), 2.3140573810786944, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_natr(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_natr(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_natr(high, low, close, 5) row 5', max(v) FILTER (WHERE i = 5), 2.363821138211381, 1e-08),
  assert_near('fin_natr(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 2.536639612152251, 1e-08),
  assert_near('fin_natr(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 2.3140573810786944, 1e-08)
FROM series;

SELECT assert_near('fin_mfi(high, low, close, volume) grouped', fin_mfi(high, low, close, volume ORDER BY i), 49.42488929708656, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_mfi(high, low, close, volume) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_mfi(high, low, close, volume) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_mfi(high, low, close, volume) row 14', max(v) FILTER (WHERE i = 14), 35.61426981971938, 1e-08),
  assert_near('fin_mfi(high, low, close, volume) row 31', max(v) FILTER (WHERE i = 31), 70.69377756036249, 1e-08),
  assert_near('fin_mfi(high, low, close, volume) row 59', max(v) FILTER (WHERE i = 59), 49.42488929708656, 1e-08)
FROM series;

SELECT assert_near('fin_mfi(high, low, close, volume, 5) grouped', fin_mfi(high, low, close, volume, 5 ORDER BY i), 35.728913614065554, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_mfi(high, low, close, volume, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_mfi(high, low, close, volume, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_mfi(high, low, close, volume, 5) row 5', max(v) FILTER (WHERE i = 5), 56.51158418295403, 1e-08),
  assert_near('fin_mfi(high, low, close, volume, 5) row 31', max(v) FILTER (WHERE i = 31), 83.975012162329, 1e-08),
  assert_near('fin_mfi(high, low, close, volume, 5) row 59', max(v) FILTER (WHERE i = 59), 35.728913614065554, 1e-08)
FROM series;

SELECT assert_near('fin_ultosc(high, low, close) grouped', fin_ultosc(high, low, close ORDER BY i), 50.82970693379597, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_ultosc(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_ultosc(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 28)),
  assert_near('fin_ultosc(high, low, close) row 28', max(v) FILTER (WHERE i = 28), 44.583849674382016, 1e-08),
  assert_near('fin_ultosc(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 50.4785068034175, 1e-08),
  assert_near('fin_ultosc(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 50.82970693379597, 1e-08)
FROM series;

SELECT assert_near('fin_ultosc(high, low, close, 9, 3, 5) grouped', fin_ultosc(high, low, close, 9, 3, 5 ORDER BY i), 37.94684477222145, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_ultosc(high, low, close, 9, 3, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_ultosc(high, low, close, 9, 3, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_ultosc(high, low, close, 9, 3, 5) row 9', max(v) FILTER (WHERE i = 9), 53.8889578450077, 1e-08),
  assert_near('fin_ultosc(high, low, close, 9, 3, 5) row 31', max(v) FILTER (WHERE i = 31), 43.96271860823825, 1e-08),
  assert_near('fin_ultosc(high, low, close, 9, 3, 5) row 59', max(v) FILTER (WHERE i = 59), 37.94684477222145, 1e-08)
FROM series;

SELECT
  assert_near('fin_rsi(close, 5) grouped', fin_rsi(close, 5 ORDER BY i), 40.8696563404658, 4e-09),
  assert_near('fin_rsi(close) grouped', fin_rsi(close ORDER BY i), 48.746887976151264, 5e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_rsi(close, 5) OVER run AS c0,
    fin_rsi(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_rsi(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_rsi(close, 5) row 5', max(c0) FILTER (WHERE i = 5), 34.25196850393704, 3e-09),
  assert_near('fin_rsi(close, 5) row 32', max(c0) FILTER (WHERE i = 32), 36.517319311008684, 4e-09),
  assert_true('fin_rsi(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_rsi(close) row 14', max(c1) FILTER (WHERE i = 14), 46.751740139211165, 5e-09),
  assert_near('fin_rsi(close) row 36', max(c1) FILTER (WHERE i = 36), 53.915427323175514, 5e-09)
FROM series;

SELECT
  assert_near('fin_cmo(close, 5) grouped', fin_cmo(close, 5 ORDER BY i), -18.260687319068406, 2e-09),
  assert_near('fin_cmo(close) grouped', fin_cmo(close ORDER BY i), -2.5062240476974655, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_cmo(close, 5) OVER run AS c0,
    fin_cmo(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_cmo(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_cmo(close, 5) row 5', max(c0) FILTER (WHERE i = 5), -31.49606299212591, 3e-09),
  assert_near('fin_cmo(close, 5) row 32', max(c0) FILTER (WHERE i = 32), -26.96536137798264, 3e-09),
  assert_true('fin_cmo(close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_cmo(close) row 14', max(c1) FILTER (WHERE i = 14), -6.4965197215776715, 1e-09),
  assert_near('fin_cmo(close) row 36', max(c1) FILTER (WHERE i = 36), 7.830854646351075, 1e-09)
FROM series;

SELECT
  assert_near('fin_macd(close).macd grouped', (fin_macd(close ORDER BY i)).macd, 0.4758814095501691, 1e-09),
  assert_near('fin_macd(close).signal grouped', (fin_macd(close ORDER BY i)).signal, 0.41305311078516943, 1e-09),
  assert_near('fin_macd(close).hist grouped', (fin_macd(close ORDER BY i)).hist, 0.06282829876499968, 1e-09),
  assert_near('fin_macd(close, 5, 10, 4).macd grouped', (fin_macd(close, 5, 10, 4 ORDER BY i)).macd, 0.13475043643278184, 1e-09),
  assert_near('fin_macd(close, 5, 10, 4).signal grouped', (fin_macd(close, 5, 10, 4 ORDER BY i)).signal, 0.37219990983164575, 1e-09),
  assert_near('fin_macd(close, 5, 10, 4).hist grouped', (fin_macd(close, 5, 10, 4 ORDER BY i)).hist, -0.2374494733988639, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_macd(close) OVER run AS c0,
    fin_macd(close, 5, 10, 4) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_macd(close).macd warm-up rows', bool_and((c0).macd IS NULL) FILTER (WHERE i < 33)),
  assert_near('fin_macd(close).macd row 33', max((c0).macd) FILTER (WHERE i = 33), 0.13151910030791214, 1e-09),
  assert_near('fin_macd(close).macd row 46', max((c0).macd) FILTER (WHERE i = 46), 0.2415481957680754, 1e-09),
  assert_true('fin_macd(close).signal warm-up rows', bool_and((c0).signal IS NULL) FILTER (WHERE i < 33)),
  assert_near('fin_macd(close).signal row 33', max((c0).signal) FILTER (WHERE i = 33), 0.18234160555251971, 1e-09),
  assert_near('fin_macd(close).signal row 46', max((c0).signal) FILTER (WHERE i = 46), 0.13257199025446387, 1e-09),
  assert_true('fin_macd(close).hist warm-up rows', bool_and((c0).hist IS NULL) FILTER (WHERE i < 33)),
  assert_near('fin_macd(close).hist row 33', max((c0).hist) FILTER (WHERE i = 33), -0.050822505244607574, 1e-09),
  assert_near('fin_macd(close).hist row 46', max((c0).hist) FILTER (WHERE i = 46), 0.10897620551361153, 1e-09),
  assert_true('fin_macd(close, 5, 10, 4).macd warm-up rows', bool_and((c1).macd IS NULL) FILTER (WHERE i < 12)),
  assert_near('fin_macd(close, 5, 10, 4).macd row 12', max((c1).macd) FILTER (WHERE i = 12), 0.14512572001001445, 1e-09),
  assert_near('fin_macd(close, 5, 10, 4).macd row 35', max((c1).macd) FILTER (WHERE i = 35), -0.6834542121977876, 1e-09),
  assert_true('fin_macd(close, 5, 10, 4).signal warm-up rows', bool_and((c1).signal IS NULL) FILTER (WHERE i < 12)),
  assert_near('fin_macd(close, 5, 10, 4).signal row 12', max((c1).signal) FILTER (WHERE i = 12), -0.5902247683446085, 1e-09),
  assert_near('fin_macd(close, 5, 10, 4).signal row 35', max((c1).signal) FILTER (WHERE i = 35), -0.4169854430591846, 1e-09),
  assert_true('fin_macd(close, 5, 10, 4).hist warm-up rows', bool_and((c1).hist IS NULL) FILTER (WHERE i < 12)),
  assert_near('fin_macd(close, 5, 10, 4).hist row 12', max((c1).hist) FILTER (WHERE i = 12), 0.7353504883546229, 1e-09),
  assert_near('fin_macd(close, 5, 10, 4).hist row 35', max((c1).hist) FILTER (WHERE i = 35), -0.26646876913860296, 1e-09)
FROM series;

SELECT
  assert_near('fin_apo(close) grouped', fin_apo(close ORDER BY i), 0.390641025640889, 1e-09),
  assert_near('fin_apo(close, 5, 10, ''ema'') grouped', fin_apo(close, 5, 10, 'ema' ORDER BY i), 0.1347504376517037, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_apo(close) OVER run AS c0,
    fin_apo(close, 5, 10, 'ema') OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_apo(close) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 25)),
  assert_near('fin_apo(close) row 25', max(c0) FILTER (WHERE i = 25), -0.12006410256408628, 1e-09),
  assert_near('fin_apo(close) row 42', max(c0) FILTER (WHERE i = 42), -0.2561538461538646, 1e-09),
  assert_true('fin_apo(close, 5, 10, ''ema'') warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_apo(close, 5, 10, ''ema'') row 9', max(c1) FILTER (WHERE i = 9), -0.9417901234567978, 1e-09),
  assert_near('fin_apo(close, 5, 10, ''ema'') row 34', max(c1) FILTER (WHERE i = 34), -0.6452497427090123, 1e-09)
FROM series;

SELECT
  assert_near('fin_ppo(close) grouped', fin_ppo(close ORDER BY i), 0.3814567215001542, 1e-09),
  assert_near('fin_ppo(close, 5, 10, ''ema'') grouped', fin_ppo(close, 5, 10, 'ema' ORDER BY i), 0.130663917542866, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_ppo(close) OVER run AS c0,
    fin_ppo(close, 5, 10, 'ema') OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_ppo(close) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 25)),
  assert_near('fin_ppo(close) row 25', max(c0) FILTER (WHERE i = 25), -0.1190235619627733, 1e-09),
  assert_near('fin_ppo(close) row 42', max(c0) FILTER (WHERE i = 42), -0.2517453969526136, 1e-09),
  assert_true('fin_ppo(close, 5, 10, ''ema'') warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_ppo(close, 5, 10, ''ema'') row 9', max(c1) FILTER (WHERE i = 9), -0.9396008534682168, 1e-09),
  assert_near('fin_ppo(close, 5, 10, ''ema'') row 34', max(c1) FILTER (WHERE i = 34), -0.6391676565581739, 1e-09)
FROM series;

SELECT
  assert_near('fin_trix(close, 5) grouped', fin_trix(close, 5 ORDER BY i), 0.16743309973663578, 1e-09),
  assert_eq('fin_trix(close) grouped warm-up', fin_trix(close ORDER BY i), NULL)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_trix(close, 5) OVER run AS c0,
    fin_trix(close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_trix(close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_trix(close, 5) row 13', max(c0) FILTER (WHERE i = 13), 0.33476746138090263, 1e-09),
  assert_near('fin_trix(close, 5) row 36', max(c0) FILTER (WHERE i = 36), -0.17850187252730354, 1e-09)
FROM series;

SELECT
  assert_near('fin_stoch(high, low, close).k grouped', (fin_stoch(high, low, close ORDER BY i)).k, 55.49263873159683, 6e-09),
  assert_near('fin_stoch(high, low, close).d grouped', (fin_stoch(high, low, close ORDER BY i)).d, 69.49227124189805, 7e-09),
  assert_near('fin_stoch(high, low, close, 5, 3, 1).k grouped', (fin_stoch(high, low, close, 5, 3, 1 ORDER BY i)).k, 12.99342105263145, 1e-09),
  assert_near('fin_stoch(high, low, close, 5, 3, 1).d grouped', (fin_stoch(high, low, close, 5, 3, 1 ORDER BY i)).d, 31.9111313378082, 3e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_stoch(high, low, close) OVER run AS c0,
    fin_stoch(high, low, close, 5, 3, 1) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_stoch(high, low, close).k warm-up rows', bool_and((c0).k IS NULL) FILTER (WHERE i < 17)),
  assert_near('fin_stoch(high, low, close).k row 17', max((c0).k) FILTER (WHERE i = 17), 22.76211213555239, 2e-09),
  assert_near('fin_stoch(high, low, close).k row 38', max((c0).k) FILTER (WHERE i = 38), 76.66666666666676, 8e-09),
  assert_true('fin_stoch(high, low, close).d warm-up rows', bool_and((c0).d IS NULL) FILTER (WHERE i < 17)),
  assert_near('fin_stoch(high, low, close).d row 17', max((c0).d) FILTER (WHERE i = 17), 27.919690073828804, 3e-09),
  assert_near('fin_stoch(high, low, close).d row 38', max((c0).d) FILTER (WHERE i = 38), 57.66541822721609, 6e-09),
  assert_true('fin_stoch(high, low, close, 5, 3, 1).k warm-up rows', bool_and((c1).k IS NULL) FILTER (WHERE i < 6)),
  assert_near('fin_stoch(high, low, close, 5, 3, 1).k row 6', max((c1).k) FILTER (WHERE i = 6), 9.885386819484204, 1e-09),
  assert_near('fin_stoch(high, low, close, 5, 3, 1).k row 32', max((c1).k) FILTER (WHERE i = 32), 11.819595645412003, 1e-09),
  assert_true('fin_stoch(high, low, close, 5, 3, 1).d warm-up rows', bool_and((c1).d IS NULL) FILTER (WHERE i < 6)),
  assert_near('fin_stoch(high, low, close, 5, 3, 1).d row 6', max((c1).d) FILTER (WHERE i = 6), 17.14489674308421, 2e-09),
  assert_near('fin_stoch(high, low, close, 5, 3, 1).d row 32', max((c1).d) FILTER (WHERE i = 32), 37.60143850319623, 4e-09)
FROM series;

SELECT
  assert_near('fin_stochrsi(close).k grouped', (fin_stochrsi(close ORDER BY i)).k, 0.0, 1e-09),
  assert_near('fin_stochrsi(close).d grouped', (fin_stochrsi(close ORDER BY i)).d, 7.507804449893892, 1e-09),
  assert_near('fin_stochrsi(close, 5, 5, 2).k grouped', (fin_stochrsi(close, 5, 5, 2 ORDER BY i)).k, 0.0, 1e-09),
  assert_near('fin_stochrsi(close, 5, 5, 2).d grouped', (fin_stochrsi(close, 5, 5, 2 ORDER BY i)).d, 2.842170943040401e-14, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_stochrsi(close) OVER run AS c0,
    fin_stochrsi(close, 5, 5, 2) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_stochrsi(close).k warm-up rows', bool_and((c0).k IS NULL) FILTER (WHERE i < 18)),
  assert_near('fin_stochrsi(close).k row 18', max((c0).k) FILTER (WHERE i = 18), 100.0, 1e-08),
  assert_near('fin_stochrsi(close).k row 38', max((c0).k) FILTER (WHERE i = 38), 88.48041608594879, 9e-09),
  assert_true('fin_stochrsi(close).d warm-up rows', bool_and((c0).d IS NULL) FILTER (WHERE i < 18)),
  assert_near('fin_stochrsi(close).d row 18', max((c0).d) FILTER (WHERE i = 18), 84.08198515669129, 8e-09),
  assert_near('fin_stochrsi(close).d row 38', max((c0).d) FILTER (WHERE i = 38), 96.16013869531626, 1e-08),
  assert_true('fin_stochrsi(close, 5, 5, 2).k warm-up rows', bool_and((c1).k IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_stochrsi(close, 5, 5, 2).k row 10', max((c1).k) FILTER (WHERE i = 10), 100.0, 1e-08),
  assert_near('fin_stochrsi(close, 5, 5, 2).k row 34', max((c1).k) FILTER (WHERE i = 34), 0.0, 1e-09),
  assert_true('fin_stochrsi(close, 5, 5, 2).d warm-up rows', bool_and((c1).d IS NULL) FILTER (WHERE i < 10)),
  assert_near('fin_stochrsi(close, 5, 5, 2).d row 10', max((c1).d) FILTER (WHERE i = 10), 100.0, 1e-08),
  assert_near('fin_stochrsi(close, 5, 5, 2).d row 34', max((c1).d) FILTER (WHERE i = 34), 2.842170943040401e-14, 1e-09)
FROM series;

SELECT
  assert_near('fin_willr(high, low, close, 5) grouped', fin_willr(high, low, close, 5 ORDER BY i), -87.00657894736855, 9e-09),
  assert_near('fin_willr(high, low, close) grouped', fin_willr(high, low, close ORDER BY i), -59.909399773499516, 6e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_willr(high, low, close, 5) OVER run AS c0,
    fin_willr(high, low, close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_willr(high, low, close, 5) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_willr(high, low, close, 5) row 4', max(c0) FILTER (WHERE i = 4), -67.13286713286726, 7e-09),
  assert_near('fin_willr(high, low, close, 5) row 31', max(c0) FILTER (WHERE i = 31), -83.22580645161291, 8e-09),
  assert_true('fin_willr(high, low, close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_willr(high, low, close) row 13', max(c1) FILTER (WHERE i = 13), -27.374301675977726, 3e-09),
  assert_near('fin_willr(high, low, close) row 36', max(c1) FILTER (WHERE i = 36), -34.943820224719076, 3e-09)
FROM series;

SELECT
  assert_near('fin_cci(high, low, close, 10, 0.03) grouped', fin_cci(high, low, close, 10, 0.03 ORDER BY i), -10.257879656160585, 1e-09),
  assert_near('fin_cci(high, low, close) grouped', fin_cci(high, low, close ORDER BY i), -14.171569057863142, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_cci(high, low, close, 10, 0.03) OVER run AS c0,
    fin_cci(high, low, close) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_cci(high, low, close, 10, 0.03) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_cci(high, low, close, 10, 0.03) row 9', max(c0) FILTER (WHERE i = 9), 3.520768074974064, 1e-09),
  assert_near('fin_cci(high, low, close, 10, 0.03) row 34', max(c0) FILTER (WHERE i = 34), -44.39895371318119, 4e-09),
  assert_true('fin_cci(high, low, close) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_cci(high, low, close) row 19', max(c1) FILTER (WHERE i = 19), 87.21896383186625, 9e-09),
  assert_near('fin_cci(high, low, close) row 39', max(c1) FILTER (WHERE i = 39), 79.73775865601397, 8e-09)
FROM series;

-- Directional movement (TA-Lib PLUS_DM/MINUS_DM/PLUS_DI/MINUS_DI/DX/ADX/ADXR
-- with Wilder sums) on gold_vbars.
SELECT assert_near('fin_plus_dm(high, low) grouped', fin_plus_dm(high, low ORDER BY i), 10.19980544488768, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_plus_dm(high, low) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_plus_dm(high, low) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_plus_dm(high, low) row 13', max(v) FILTER (WHERE i = 13), 8.180000000000007, 1e-08),
  assert_near('fin_plus_dm(high, low) row 31', max(v) FILTER (WHERE i = 31), 10.678408255863333, 1e-08),
  assert_near('fin_plus_dm(high, low) row 59', max(v) FILTER (WHERE i = 59), 10.19980544488768, 1e-08)
FROM series;

SELECT assert_near('fin_plus_dm(high, low, 1) grouped', fin_plus_dm(high, low, 1 ORDER BY i), 0.0, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_plus_dm(high, low, 1) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_plus_dm(high, low, 1) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_plus_dm(high, low, 1) row 1', max(v) FILTER (WHERE i = 1), 1.309999999999988, 1e-08),
  assert_near('fin_plus_dm(high, low, 1) row 31', max(v) FILTER (WHERE i = 31), 0.0, 1e-08),
  assert_near('fin_plus_dm(high, low, 1) row 59', max(v) FILTER (WHERE i = 59), 0.0, 1e-08)
FROM series;

SELECT assert_near('fin_minus_dm(high, low) grouped', fin_minus_dm(high, low ORDER BY i), 10.735334908332721, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_minus_dm(high, low) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_minus_dm(high, low) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_minus_dm(high, low) row 13', max(v) FILTER (WHERE i = 13), 6.25, 1e-08),
  assert_near('fin_minus_dm(high, low) row 31', max(v) FILTER (WHERE i = 31), 10.35610514677282, 1e-08),
  assert_near('fin_minus_dm(high, low) row 59', max(v) FILTER (WHERE i = 59), 10.735334908332721, 1e-08)
FROM series;

SELECT assert_near('fin_minus_dm(high, low, 5) grouped', fin_minus_dm(high, low, 5 ORDER BY i), 4.58957408623036, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_minus_dm(high, low, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_minus_dm(high, low, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_minus_dm(high, low, 5) row 4', max(v) FILTER (WHERE i = 4), 2.0, 1e-08),
  assert_near('fin_minus_dm(high, low, 5) row 31', max(v) FILTER (WHERE i = 31), 4.623142394044454, 1e-08),
  assert_near('fin_minus_dm(high, low, 5) row 59', max(v) FILTER (WHERE i = 59), 4.58957408623036, 1e-08)
FROM series;

SELECT assert_near('fin_plus_di(high, low, close) grouped', fin_plus_di(high, low, close ORDER BY i), 30.878200366443913, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_plus_di(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_plus_di(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_plus_di(high, low, close) row 14', max(v) FILTER (WHERE i = 14), 25.630272354784307, 1e-08),
  assert_near('fin_plus_di(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 31.48379580549971, 1e-08),
  assert_near('fin_plus_di(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 30.878200366443913, 1e-08)
FROM series;

SELECT assert_near('fin_plus_di(high, low, close, 5) grouped', fin_plus_di(high, low, close, 5 ORDER BY i), 26.60339520427338, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_plus_di(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_plus_di(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_plus_di(high, low, close, 5) row 5', max(v) FILTER (WHERE i = 5), 23.078458774206442, 1e-08),
  assert_near('fin_plus_di(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 30.5508338806234, 1e-08),
  assert_near('fin_plus_di(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 26.60339520427338, 1e-08)
FROM series;

SELECT assert_near('fin_minus_di(high, low, close) grouped', fin_minus_di(high, low, close ORDER BY i), 32.49942600292685, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_minus_di(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_minus_di(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_minus_di(high, low, close) row 14', max(v) FILTER (WHERE i = 14), 28.89611954687878, 1e-08),
  assert_near('fin_minus_di(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 30.5335300888362, 1e-08),
  assert_near('fin_minus_di(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 32.49942600292685, 1e-08)
FROM series;

SELECT assert_near('fin_minus_di(high, low, close, 5) grouped', fin_minus_di(high, low, close, 5 ORDER BY i), 38.870094291659214, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_minus_di(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_minus_di(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_minus_di(high, low, close, 5) row 5', max(v) FILTER (WHERE i = 5), 43.92094230385305, 1e-08),
  assert_near('fin_minus_di(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 35.802329698613605, 1e-08),
  assert_near('fin_minus_di(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 38.870094291659214, 1e-08)
FROM series;

SELECT assert_near('fin_dx(high, low, close) grouped', fin_dx(high, low, close ORDER BY i), 2.558040951288211, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_dx(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_dx(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_dx(high, low, close) row 14', max(v) FILTER (WHERE i = 14), 5.989479733015054, 1e-08),
  assert_near('fin_dx(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 1.5322584502958991, 1e-08),
  assert_near('fin_dx(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 2.558040951288211, 1e-08)
FROM series;

SELECT assert_near('fin_dx(high, low, close, 5) grouped', fin_dx(high, low, close, 5 ORDER BY i), 18.735367828757436, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_dx(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_dx(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_dx(high, low, close, 5) row 5', max(v) FILTER (WHERE i = 5), 31.108462455303897, 1e-08),
  assert_near('fin_dx(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 7.914461850366821, 1e-08),
  assert_near('fin_dx(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 18.735367828757436, 1e-08)
FROM series;

SELECT assert_near('fin_adx(high, low, close) grouped', fin_adx(high, low, close ORDER BY i), 9.855838693793169, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_adx(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_adx(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 27)),
  assert_near('fin_adx(high, low, close) row 27', max(v) FILTER (WHERE i = 27), 12.278823087782824, 1e-08),
  assert_near('fin_adx(high, low, close) row 31', max(v) FILTER (WHERE i = 31), 12.052354533735155, 1e-08),
  assert_near('fin_adx(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 9.855838693793169, 1e-08)
FROM series;

SELECT assert_near('fin_adx(high, low, close, 5) grouped', fin_adx(high, low, close, 5 ORDER BY i), 24.320132994039987, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_adx(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_adx(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_adx(high, low, close, 5) row 9', max(v) FILTER (WHERE i = 9), 33.86096134949646, 1e-08),
  assert_near('fin_adx(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 28.31074807831474, 1e-08),
  assert_near('fin_adx(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 24.320132994039987, 1e-08)
FROM series;

SELECT assert_near('fin_adxr(high, low, close) grouped', fin_adxr(high, low, close ORDER BY i), 10.39486627548551, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_adxr(high, low, close) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_adxr(high, low, close) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 40)),
  assert_near('fin_adxr(high, low, close) row 40', max(v) FILTER (WHERE i = 40), 11.997015178297643, 1e-08),
  assert_near('fin_adxr(high, low, close) row 59', max(v) FILTER (WHERE i = 59), 10.39486627548551, 1e-08)
FROM series;

SELECT assert_near('fin_adxr(high, low, close, 5) grouped', fin_adxr(high, low, close, 5 ORDER BY i), 24.507792837236362, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_adxr(high, low, close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_adxr(high, low, close, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 13)),
  assert_near('fin_adxr(high, low, close, 5) row 13', max(v) FILTER (WHERE i = 13), 36.038785825411594, 1e-08),
  assert_near('fin_adxr(high, low, close, 5) row 31', max(v) FILTER (WHERE i = 31), 29.336274349048452, 1e-08),
  assert_near('fin_adxr(high, low, close, 5) row 59', max(v) FILTER (WHERE i = 59), 24.507792837236362, 1e-08)
FROM series;

SELECT
  assert_near('fin_bbands(close).lower grouped', (fin_bbands(close ORDER BY i)).lower, 98.03171214342277, 1e-08),
  assert_near('fin_bbands(close).middle grouped', (fin_bbands(close ORDER BY i)).middle, 102.45549999999999, 1e-08),
  assert_near('fin_bbands(close).upper grouped', (fin_bbands(close ORDER BY i)).upper, 106.8792878565772, 1e-08),
  assert_near('fin_bbands(close).width grouped', (fin_bbands(close ORDER BY i)).width, 0.08635530267437515, 1e-09),
  assert_near('fin_bbands(close).percent_b grouped', (fin_bbands(close ORDER BY i)).percent_b, 0.45416823623254243, 1e-09),
  assert_near('fin_bbands(close, 10, 1.5, 1).lower grouped', (fin_bbands(close, 10, 1.5, 1 ORDER BY i)).lower, 99.0953738423863, 1e-08),
  assert_near('fin_bbands(close, 10, 1.5, 1).middle grouped', (fin_bbands(close, 10, 1.5, 1 ORDER BY i)).middle, 102.59800000000004, 1e-08),
  assert_near('fin_bbands(close, 10, 1.5, 1).upper grouped', (fin_bbands(close, 10, 1.5, 1 ORDER BY i)).upper, 106.10062615761379, 1e-08),
  assert_near('fin_bbands(close, 10, 1.5, 1).width grouped', (fin_bbands(close, 10, 1.5, 1 ORDER BY i)).width, 0.06827864398163211, 1e-09),
  assert_near('fin_bbands(close, 10, 1.5, 1).percent_b grouped', (fin_bbands(close, 10, 1.5, 1 ORDER BY i)).percent_b, 0.4217729818512257, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_bbands(close) OVER run AS c0,
    fin_bbands(close, 10, 1.5, 1) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_bbands(close).lower warm-up rows', bool_and((c0).lower IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_bbands(close).lower row 19', max((c0).lower) FILTER (WHERE i = 19), 96.4916476563366, 1e-08),
  assert_near('fin_bbands(close).lower row 39', max((c0).lower) FILTER (WHERE i = 39), 97.13520146795986, 1e-08),
  assert_true('fin_bbands(close).middle warm-up rows', bool_and((c0).middle IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_bbands(close).middle row 19', max((c0).middle) FILTER (WHERE i = 19), 100.583, 1e-08),
  assert_near('fin_bbands(close).middle row 39', max((c0).middle) FILTER (WHERE i = 39), 102.00249999999998, 1e-08),
  assert_true('fin_bbands(close).upper warm-up rows', bool_and((c0).upper IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_bbands(close).upper row 19', max((c0).upper) FILTER (WHERE i = 19), 104.6743523436634, 1e-08),
  assert_near('fin_bbands(close).upper row 39', max((c0).upper) FILTER (WHERE i = 39), 106.86979853204011, 1e-08),
  assert_true('fin_bbands(close).width warm-up rows', bool_and((c0).width IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_bbands(close).width row 19', max((c0).width) FILTER (WHERE i = 19), 0.0813527602808308, 1e-09),
  assert_near('fin_bbands(close).width row 39', max((c0).width) FILTER (WHERE i = 39), 0.09543488702806548, 1e-09),
  assert_true('fin_bbands(close).percent_b warm-up rows', bool_and((c0).percent_b IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_bbands(close).percent_b row 19', max((c0).percent_b) FILTER (WHERE i = 19), 0.7880465677382283, 1e-09),
  assert_near('fin_bbands(close).percent_b row 39', max((c0).percent_b) FILTER (WHERE i = 39), 0.7719681135821276, 1e-09),
  assert_true('fin_bbands(close, 10, 1.5, 1).lower warm-up rows', bool_and((c1).lower IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_bbands(close, 10, 1.5, 1).lower row 9', max((c1).lower) FILTER (WHERE i = 9), 97.15023297993508, 1e-08),
  assert_near('fin_bbands(close, 10, 1.5, 1).lower row 34', max((c1).lower) FILTER (WHERE i = 34), 97.59423434772356, 1e-08),
  assert_true('fin_bbands(close, 10, 1.5, 1).middle warm-up rows', bool_and((c1).middle IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_bbands(close, 10, 1.5, 1).middle row 9', max((c1).middle) FILTER (WHERE i = 9), 100.233, 1e-08),
  assert_near('fin_bbands(close, 10, 1.5, 1).middle row 34', max((c1).middle) FILTER (WHERE i = 34), 101.17, 1e-08),
  assert_true('fin_bbands(close, 10, 1.5, 1).upper warm-up rows', bool_and((c1).upper IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_bbands(close, 10, 1.5, 1).upper row 9', max((c1).upper) FILTER (WHERE i = 9), 103.31576702006492, 1e-08),
  assert_near('fin_bbands(close, 10, 1.5, 1).upper row 34', max((c1).upper) FILTER (WHERE i = 34), 104.74576565227645, 1e-08),
  assert_true('fin_bbands(close, 10, 1.5, 1).width warm-up rows', bool_and((c1).width IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_bbands(close, 10, 1.5, 1).width row 9', max((c1).width) FILTER (WHERE i = 9), 0.061512017400754654, 1e-09),
  assert_near('fin_bbands(close, 10, 1.5, 1).width row 34', max((c1).width) FILTER (WHERE i = 34), 0.07068826039886221, 1e-09),
  assert_true('fin_bbands(close, 10, 1.5, 1).percent_b warm-up rows', bool_and((c1).percent_b IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_bbands(close, 10, 1.5, 1).percent_b row 9', max((c1).percent_b) FILTER (WHERE i = 9), 0.5205983778815242, 1e-09),
  assert_near('fin_bbands(close, 10, 1.5, 1).percent_b row 34', max((c1).percent_b) FILTER (WHERE i = 34), 0.14483131068964736, 1e-09)
FROM series;

SELECT
  assert_near('fin_stddev(close) grouped', fin_stddev(close ORDER BY i), 2.2118939282886063, 1e-09),
  assert_near('fin_stddev(close, 10, 1) grouped', fin_stddev(close, 10, 1 ORDER BY i), 2.3350841050758286, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_stddev(close) OVER run AS c0,
    fin_stddev(close, 10, 1) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_stddev(close) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_stddev(close) row 19', max(c0) FILTER (WHERE i = 19), 2.0456761718317, 1e-09),
  assert_near('fin_stddev(close) row 39', max(c0) FILTER (WHERE i = 39), 2.433649266020065, 1e-09),
  assert_true('fin_stddev(close, 10, 1) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_stddev(close, 10, 1) row 9', max(c1) FILTER (WHERE i = 9), 2.0551780133766178, 1e-09),
  assert_near('fin_stddev(close, 10, 1) row 34', max(c1) FILTER (WHERE i = 34), 2.3838437681842986, 1e-09)
FROM series;

SELECT
  assert_near('fin_var_indicator(close) grouped', fin_var_indicator(close ORDER BY i), 4.892474750000002, 1e-09),
  assert_near('fin_var_indicator(close, 10, 1) grouped', fin_var_indicator(close, 10, 1 ORDER BY i), 5.4526177777777844, 1e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_var_indicator(close) OVER run AS c0,
    fin_var_indicator(close, 10, 1) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_var_indicator(close) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_var_indicator(close) row 19', max(c0) FILTER (WHERE i = 19), 4.184790999999998, 1e-09),
  assert_near('fin_var_indicator(close) row 39', max(c0) FILTER (WHERE i = 39), 5.9226487500000005, 1e-09),
  assert_true('fin_var_indicator(close, 10, 1) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_var_indicator(close, 10, 1) row 9', max(c1) FILTER (WHERE i = 9), 4.22375666666666, 1e-09),
  assert_near('fin_var_indicator(close, 10, 1) row 34', max(c1) FILTER (WHERE i = 34), 5.682711111111115, 1e-09)
FROM series;

SELECT
  assert_near('fin_keltner(high, low, close).lower grouped', (fin_keltner(high, low, close ORDER BY i)).lower, 98.01229603803272, 1e-08),
  assert_near('fin_keltner(high, low, close).middle grouped', (fin_keltner(high, low, close ORDER BY i)).middle, 102.74406188643894, 1e-08),
  assert_near('fin_keltner(high, low, close).upper grouped', (fin_keltner(high, low, close ORDER BY i)).upper, 107.47582773484517, 1e-08),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).lower grouped', (fin_keltner(high, low, close, 5, 3, 1.5 ORDER BY i)).lower, 99.78019792649772, 1e-08),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).middle grouped', (fin_keltner(high, low, close, 5, 3, 1.5 ORDER BY i)).middle, 103.26225509669199, 1e-08),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).upper grouped', (fin_keltner(high, low, close, 5, 3, 1.5 ORDER BY i)).upper, 106.74431226688625, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_keltner(high, low, close) OVER run AS c0,
    fin_keltner(high, low, close, 5, 3, 1.5) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_keltner(high, low, close).lower warm-up rows', bool_and((c0).lower IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_keltner(high, low, close).lower row 19', max((c0).lower) FILTER (WHERE i = 19), 95.919880147956, 1e-08),
  assert_near('fin_keltner(high, low, close).lower row 39', max((c0).lower) FILTER (WHERE i = 39), 97.33499964298807, 1e-08),
  assert_true('fin_keltner(high, low, close).middle warm-up rows', bool_and((c0).middle IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_keltner(high, low, close).middle row 19', max((c0).middle) FILTER (WHERE i = 19), 100.583, 1e-08),
  assert_near('fin_keltner(high, low, close).middle row 39', max((c0).middle) FILTER (WHERE i = 39), 101.96284677845344, 1e-08),
  assert_true('fin_keltner(high, low, close).upper warm-up rows', bool_and((c0).upper IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_keltner(high, low, close).upper row 19', max((c0).upper) FILTER (WHERE i = 19), 105.246119852044, 1e-08),
  assert_near('fin_keltner(high, low, close).upper row 39', max((c0).upper) FILTER (WHERE i = 39), 106.59069391391881, 1e-08),
  assert_true('fin_keltner(high, low, close, 5, 3, 1.5).lower warm-up rows', bool_and((c1).lower IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).lower row 4', max((c1).lower) FILTER (WHERE i = 4), 98.80366666666666, 1e-08),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).lower row 31', max((c1).lower) FILTER (WHERE i = 31), 98.74118882119036, 1e-08),
  assert_true('fin_keltner(high, low, close, 5, 3, 1.5).middle warm-up rows', bool_and((c1).middle IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).middle row 4', max((c1).middle) FILTER (WHERE i = 4), 101.952, 1e-08),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).middle row 31', max((c1).middle) FILTER (WHERE i = 31), 102.73005894523298, 1e-08),
  assert_true('fin_keltner(high, low, close, 5, 3, 1.5).upper warm-up rows', bool_and((c1).upper IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).upper row 4', max((c1).upper) FILTER (WHERE i = 4), 105.10033333333334, 1e-08),
  assert_near('fin_keltner(high, low, close, 5, 3, 1.5).upper row 31', max((c1).upper) FILTER (WHERE i = 31), 106.7189290692756, 1e-08)
FROM series;

SELECT
  assert_near('fin_donchian(high, low).lower grouped', (fin_donchian(high, low ORDER BY i)).lower, 98.35, 1e-08),
  assert_near('fin_donchian(high, low).middle grouped', (fin_donchian(high, low ORDER BY i)).middle, 102.845, 1e-08),
  assert_near('fin_donchian(high, low).upper grouped', (fin_donchian(high, low ORDER BY i)).upper, 107.34, 1e-08),
  assert_near('fin_donchian(high, low, 5).lower grouped', (fin_donchian(high, low, 5 ORDER BY i)).lower, 101.26, 1e-08),
  assert_near('fin_donchian(high, low, 5).middle grouped', (fin_donchian(high, low, 5 ORDER BY i)).middle, 104.30000000000001, 1e-08),
  assert_near('fin_donchian(high, low, 5).upper grouped', (fin_donchian(high, low, 5 ORDER BY i)).upper, 107.34, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_donchian(high, low) OVER run AS c0,
    fin_donchian(high, low, 5) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_donchian(high, low).lower warm-up rows', bool_and((c0).lower IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_donchian(high, low).lower row 19', max((c0).lower) FILTER (WHERE i = 19), 96.65, 1e-08),
  assert_near('fin_donchian(high, low).lower row 39', max((c0).lower) FILTER (WHERE i = 39), 96.82, 1e-08),
  assert_true('fin_donchian(high, low).middle warm-up rows', bool_and((c0).middle IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_donchian(high, low).middle row 19', max((c0).middle) FILTER (WHERE i = 19), 100.47, 1e-08),
  assert_near('fin_donchian(high, low).middle row 39', max((c0).middle) FILTER (WHERE i = 39), 101.27, 1e-08),
  assert_true('fin_donchian(high, low).upper warm-up rows', bool_and((c0).upper IS NULL) FILTER (WHERE i < 19)),
  assert_near('fin_donchian(high, low).upper row 19', max((c0).upper) FILTER (WHERE i = 19), 104.29, 1e-08),
  assert_near('fin_donchian(high, low).upper row 39', max((c0).upper) FILTER (WHERE i = 39), 105.72, 1e-08),
  assert_true('fin_donchian(high, low, 5).lower warm-up rows', bool_and((c1).lower IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_donchian(high, low, 5).lower row 4', max((c1).lower) FILTER (WHERE i = 4), 100.0, 1e-08),
  assert_near('fin_donchian(high, low, 5).lower row 31', max((c1).lower) FILTER (WHERE i = 31), 101.07, 1e-08),
  assert_true('fin_donchian(high, low, 5).middle warm-up rows', bool_and((c1).middle IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_donchian(high, low, 5).middle row 4', max((c1).middle) FILTER (WHERE i = 4), 102.14500000000001, 1e-08),
  assert_near('fin_donchian(high, low, 5).middle row 31', max((c1).middle) FILTER (WHERE i = 31), 103.395, 1e-08),
  assert_true('fin_donchian(high, low, 5).upper warm-up rows', bool_and((c1).upper IS NULL) FILTER (WHERE i < 4)),
  assert_near('fin_donchian(high, low, 5).upper row 4', max((c1).upper) FILTER (WHERE i = 4), 104.29, 1e-08),
  assert_near('fin_donchian(high, low, 5).upper row 31', max((c1).upper) FILTER (WHERE i = 31), 105.72, 1e-08)
FROM series;

SELECT
  assert_near('fin_aroon(high, low).aroon_down grouped', (fin_aroon(high, low ORDER BY i)).aroon_down, 42.85714285714286, 4e-09),
  assert_near('fin_aroon(high, low).aroon_up grouped', (fin_aroon(high, low ORDER BY i)).aroon_up, 78.57142857142857, 8e-09),
  assert_near('fin_aroon(high, low, 5).aroon_down grouped', (fin_aroon(high, low, 5 ORDER BY i)).aroon_down, 100.0, 1e-08),
  assert_near('fin_aroon(high, low, 5).aroon_up grouped', (fin_aroon(high, low, 5 ORDER BY i)).aroon_up, 40.0, 4e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_aroon(high, low) OVER run AS c0,
    fin_aroon(high, low, 5) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_aroon(high, low).aroon_down warm-up rows', bool_and((c0).aroon_down IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_aroon(high, low).aroon_down row 14', max((c0).aroon_down) FILTER (WHERE i = 14), 57.142857142857146, 6e-09),
  assert_near('fin_aroon(high, low).aroon_down row 36', max((c0).aroon_down) FILTER (WHERE i = 36), 21.42857142857143, 2e-09),
  assert_true('fin_aroon(high, low).aroon_up warm-up rows', bool_and((c0).aroon_up IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_aroon(high, low).aroon_up row 14', max((c0).aroon_up) FILTER (WHERE i = 14), 21.42857142857143, 2e-09),
  assert_near('fin_aroon(high, low).aroon_up row 36', max((c0).aroon_up) FILTER (WHERE i = 36), 57.142857142857146, 6e-09),
  assert_true('fin_aroon(high, low, 5).aroon_down warm-up rows', bool_and((c1).aroon_down IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_aroon(high, low, 5).aroon_down row 5', max((c1).aroon_down) FILTER (WHERE i = 5), 100.0, 1e-08),
  assert_near('fin_aroon(high, low, 5).aroon_down row 32', max((c1).aroon_down) FILTER (WHERE i = 32), 100.0, 1e-08),
  assert_true('fin_aroon(high, low, 5).aroon_up warm-up rows', bool_and((c1).aroon_up IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_aroon(high, low, 5).aroon_up row 5', max((c1).aroon_up) FILTER (WHERE i = 5), 60.0, 6e-09),
  assert_near('fin_aroon(high, low, 5).aroon_up row 32', max((c1).aroon_up) FILTER (WHERE i = 32), 60.0, 6e-09)
FROM series;

SELECT
  assert_near('fin_aroonosc(high, low) grouped', fin_aroonosc(high, low ORDER BY i), 35.714285714285715, 4e-09),
  assert_near('fin_aroonosc(high, low, 5) grouped', fin_aroonosc(high, low, 5 ORDER BY i), -60.0, 6e-09)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_aroonosc(high, low) OVER run AS c0,
    fin_aroonosc(high, low, 5) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_aroonosc(high, low) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 14)),
  assert_near('fin_aroonosc(high, low) row 14', max(c0) FILTER (WHERE i = 14), -35.714285714285715, 4e-09),
  assert_near('fin_aroonosc(high, low) row 36', max(c0) FILTER (WHERE i = 36), 35.714285714285715, 4e-09),
  assert_true('fin_aroonosc(high, low, 5) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 5)),
  assert_near('fin_aroonosc(high, low, 5) row 5', max(c1) FILTER (WHERE i = 5), -40.0, 4e-09),
  assert_near('fin_aroonosc(high, low, 5) row 32', max(c1) FILTER (WHERE i = 32), -40.0, 4e-09)
FROM series;

SELECT
  assert_near('fin_sar(high, low) grouped', fin_sar(high, low ORDER BY i), 99.02927464, 1e-08),
  assert_near('fin_sar(high, low, 0.05, 0.1) grouped', fin_sar(high, low, 0.05, 0.1 ORDER BY i), 101.147874, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_sar(high, low) OVER run AS c0,
    fin_sar(high, low, 0.05, 0.1) OVER run AS c1
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_sar(high, low) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_sar(high, low) row 1', max(c0) FILTER (WHERE i = 1), 100.0, 1e-08),
  assert_near('fin_sar(high, low) row 30', max(c0) FILTER (WHERE i = 30), 96.9862, 1e-08),
  assert_true('fin_sar(high, low, 0.05, 0.1) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_sar(high, low, 0.05, 0.1) row 1', max(c1) FILTER (WHERE i = 1), 100.0, 1e-08),
  assert_near('fin_sar(high, low, 0.05, 0.1) row 30', max(c1) FILTER (WHERE i = 30), 97.95835, 1e-08)
FROM series;

SELECT
  assert_near('fin_sarext(high, low) grouped', fin_sarext(high, low ORDER BY i), 99.02927464, 1e-08),
  assert_near('fin_sarext(high, low, 0, 0.01, 0.03, 0.02, 0.25, 0.01, 0.04, 0.15) grouped', fin_sarext(high, low, 0, 0.01, 0.03, 0.02, 0.25, 0.01, 0.04, 0.15 ORDER BY i), 98.3820232377, 1e-08),
  assert_near('fin_sarext(high, low, -105, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) grouped', fin_sarext(high, low, -105, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2 ORDER BY i), 99.02927464, 1e-08)
FROM gold_bars;

WITH series AS (
  SELECT i, fin_sarext(high, low) OVER run AS c0,
    fin_sarext(high, low, 0, 0.01, 0.03, 0.02, 0.25, 0.01, 0.04, 0.15) OVER run AS c1,
    fin_sarext(high, low, -105, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) OVER run AS c2
  FROM gold_bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('fin_sarext(high, low) warm-up rows', bool_and(c0 IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_sarext(high, low) row 1', max(c0) FILTER (WHERE i = 1), 100.0, 1e-08),
  assert_near('fin_sarext(high, low) row 30', max(c0) FILTER (WHERE i = 30), 96.9862, 1e-08),
  assert_true('fin_sarext(high, low, 0, 0.01, 0.03, 0.02, 0.25, 0.01, 0.04, 0.15) warm-up rows', bool_and(c1 IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_sarext(high, low, 0, 0.01, 0.03, 0.02, 0.25, 0.01, 0.04, 0.15) row 1', max(c1) FILTER (WHERE i = 1), 100.0, 1e-08),
  assert_near('fin_sarext(high, low, 0, 0.01, 0.03, 0.02, 0.25, 0.01, 0.04, 0.15) row 30', max(c1) FILTER (WHERE i = 30), -106.22196312833634, 1e-08),
  assert_true('fin_sarext(high, low, -105, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) warm-up rows', bool_and(c2 IS NULL) FILTER (WHERE i < 1)),
  assert_near('fin_sarext(high, low, -105, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) row 1', max(c2) FILTER (WHERE i = 1), -105.0, 1e-08),
  assert_near('fin_sarext(high, low, -105, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) row 30', max(c2) FILTER (WHERE i = 30), 96.9862, 1e-08)
FROM series;

-- Window semantics shared by the technical indicators: bounded indicators
-- slide over their lookback, recursive ones reseed at the frame start, NULL
-- rows are skipped, and a non-finite input yields NULL while it is inside a
-- bounded lookback (for the rest of the series for recursive indicators).
WITH series AS (
  SELECT i,
    fin_sma(close, 5) OVER (ORDER BY i ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS sma_slide,
    fin_sma(close, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS sma_run,
    fin_ema(close, 5) OVER (ORDER BY i ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS ema_slide
  FROM gold_bars
)
SELECT
  assert_true('bounded sliding frame equals running value', bool_and(sma_slide IS NOT DISTINCT FROM sma_run)),
  assert_near('recursive sliding frame reseeds at the frame start', max(ema_slide) FILTER (WHERE i = 59),
    (SELECT fin_ema(close, 5 ORDER BY i) FROM gold_bars WHERE i >= 50), 1e-12)
FROM series;

WITH bars AS (
  SELECT i, CASE WHEN i = 30 THEN 'NaN'::DOUBLE WHEN i = 40 THEN NULL ELSE close END AS c FROM gold_bars
), series AS (
  SELECT i, fin_sma(c, 5) OVER run AS sma, fin_ema(c, 5) OVER run AS ema
  FROM bars WINDOW run AS (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT
  assert_true('bounded indicator is NULL while a NaN is in the lookback', bool_and(sma IS NULL) FILTER (WHERE i BETWEEN 30 AND 34)),
  assert_near('bounded indicator recovers after the lookback', max(sma) FILTER (WHERE i = 35),
    (SELECT avg(close) FROM gold_bars WHERE i BETWEEN 31 AND 35), 1e-9),
  assert_true('recursive indicator stays NULL after a NaN', bool_and(ema IS NULL) FILTER (WHERE i >= 30)),
  assert_near('NULL rows are skipped', max(sma) FILTER (WHERE i = 41),
    (SELECT avg(close) FROM gold_bars WHERE i IN (36, 37, 38, 39, 41)), 1e-9),
  assert_near('grouped bounded indicator ignores an old NaN', (SELECT fin_sma(c, 5 ORDER BY i) FROM bars),
    (SELECT avg(close) FROM gold_bars WHERE i >= 55), 1e-9),
  assert_eq('grouped recursive indicator is NULL after a NaN', (SELECT fin_ema(c, 5 ORDER BY i) FROM bars), NULL)
FROM series;

SELECT
  assert_eq('roc zero base is NULL', fin_roc(x, 1 ORDER BY i), NULL),
  assert_eq('rocr zero base is NULL', fin_rocr(x, 1 ORDER BY i), NULL),
  assert_eq('mom zero base is defined', fin_mom(x, 1 ORDER BY i), 5.0),
  assert_eq('willr flat range is zero', fin_willr(1.0, 1.0, 1.0, 2 ORDER BY i), 0.0),
  assert_eq('stoch flat range is zero', (fin_stoch(1.0, 1.0, 1.0, 2, 1, 1 ORDER BY i)).k, 0.0),
  assert_eq('cmo flat series is zero', fin_cmo(1.0, 1 ORDER BY i), 0.0)
FROM (VALUES (1, 0.0), (2, 5.0)) t(i, x);

-- Parameters live in the bind data, which is serialized: calls that differ
-- only in their parameters must not be merged as a common subplan.
SELECT
  assert_eq('parameters keep union branches distinct', (SELECT count(DISTINCT v) FROM (
    SELECT fin_sma(close, 5 ORDER BY i) AS v FROM gold_bars
    UNION ALL SELECT fin_sma(close, 20 ORDER BY i) FROM gold_bars
    UNION ALL SELECT fin_sma(close, 5 ORDER BY i) FROM gold_bars)), 2::BIGINT),
  assert_eq('ma_type keeps union branches distinct', (SELECT count(DISTINCT v) FROM (
    SELECT fin_apo(close, 5, 10, 'sma' ORDER BY i) AS v FROM gold_bars
    UNION ALL SELECT fin_apo(close, 5, 10, 'ema' ORDER BY i) FROM gold_bars)), 2::BIGINT);

-- Ordered indicators are deterministic: grouped and windowed results are
-- bit-identical for one and eight threads.
CREATE OR REPLACE TEMP TABLE tech_determinism AS
SELECT i % 7 AS sym, i, 100 + 5 * sin(i / 9.0) + (i % 13) * 0.07 AS close,
  101 + 5 * sin(i / 9.0) + (i % 3) * 0.05 AS high, 99 + 5 * sin(i / 9.0) - (i % 5) * 0.03 AS low
FROM range(20000) t(i);

CREATE OR REPLACE TEMP MACRO tech_grouped() AS TABLE
SELECT sym,
  fin_sma(close, 20 ORDER BY i) AS g0,
  fin_wma(close, 20 ORDER BY i) AS g1,
  fin_ema(close, 20 ORDER BY i) AS g2,
  fin_dema(close, 20 ORDER BY i) AS g3,
  fin_tema(close, 20 ORDER BY i) AS g4,
  fin_trima(close, 20 ORDER BY i) AS g5,
  fin_t3(close, 5, 0.7 ORDER BY i) AS g6,
  fin_kama(close, 10, 2, 30 ORDER BY i) AS g7,
  fin_hma(close, 20 ORDER BY i) AS g8,
  fin_linearreg(close, 14 ORDER BY i) AS g9,
  fin_linearreg_slope(close, 14 ORDER BY i) AS g10,
  fin_linearreg_intercept(close, 14 ORDER BY i) AS g11,
  fin_tsf(close, 14 ORDER BY i) AS g12,
  fin_mom(close, 10 ORDER BY i) AS g13,
  fin_roc(close, 10 ORDER BY i) AS g14,
  fin_rocp(close, 10 ORDER BY i) AS g15,
  fin_rocr(close, 10 ORDER BY i) AS g16,
  fin_rocr100(close, 10 ORDER BY i) AS g17,
  fin_rsi(close, 14 ORDER BY i) AS g18,
  fin_cmo(close, 14 ORDER BY i) AS g19,
  fin_macd(close, 12, 26, 9 ORDER BY i) AS g20,
  fin_apo(close, 12, 26, 'ema' ORDER BY i) AS g21,
  fin_ppo(close, 12, 26, 'sma' ORDER BY i) AS g22,
  fin_trix(close, 15 ORDER BY i) AS g23,
  fin_stochrsi(close, 14, 5, 3 ORDER BY i) AS g24,
  fin_bbands(close, 20, 2.0, 0 ORDER BY i) AS g25,
  fin_stddev(close, 20, 1 ORDER BY i) AS g26,
  fin_var_indicator(close, 20, 0 ORDER BY i) AS g27,
  fin_stoch(high, low, close, 14, 3, 3 ORDER BY i) AS g28,
  fin_willr(high, low, close, 14 ORDER BY i) AS g29,
  fin_cci(high, low, close, 20, 0.015 ORDER BY i) AS g30,
  fin_keltner(high, low, close, 20, 10, 2.0 ORDER BY i) AS g31,
  fin_donchian(high, low, 20 ORDER BY i) AS g32,
  fin_aroon(high, low, 14 ORDER BY i) AS g33,
  fin_aroonosc(high, low, 14 ORDER BY i) AS g34,
  fin_sar(high, low, 0.02, 0.2 ORDER BY i) AS g35,
  fin_sarext(high, low, 0, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2 ORDER BY i) AS g36
FROM tech_determinism GROUP BY sym;

CREATE OR REPLACE TEMP MACRO tech_windowed() AS TABLE
SELECT sym, i,
  fin_sma(close, 20) OVER run AS w0, fin_sma(close, 20) OVER slide AS s0,
  fin_wma(close, 20) OVER run AS w1, fin_wma(close, 20) OVER slide AS s1,
  fin_ema(close, 20) OVER run AS w2, fin_ema(close, 20) OVER slide AS s2,
  fin_dema(close, 20) OVER run AS w3, fin_dema(close, 20) OVER slide AS s3,
  fin_tema(close, 20) OVER run AS w4, fin_tema(close, 20) OVER slide AS s4,
  fin_trima(close, 20) OVER run AS w5, fin_trima(close, 20) OVER slide AS s5,
  fin_t3(close, 5, 0.7) OVER run AS w6, fin_t3(close, 5, 0.7) OVER slide AS s6,
  fin_kama(close, 10, 2, 30) OVER run AS w7, fin_kama(close, 10, 2, 30) OVER slide AS s7,
  fin_hma(close, 20) OVER run AS w8, fin_hma(close, 20) OVER slide AS s8,
  fin_linearreg(close, 14) OVER run AS w9, fin_linearreg(close, 14) OVER slide AS s9,
  fin_linearreg_slope(close, 14) OVER run AS w10, fin_linearreg_slope(close, 14) OVER slide AS s10,
  fin_linearreg_intercept(close, 14) OVER run AS w11, fin_linearreg_intercept(close, 14) OVER slide AS s11,
  fin_tsf(close, 14) OVER run AS w12, fin_tsf(close, 14) OVER slide AS s12,
  fin_mom(close, 10) OVER run AS w13, fin_mom(close, 10) OVER slide AS s13,
  fin_roc(close, 10) OVER run AS w14, fin_roc(close, 10) OVER slide AS s14,
  fin_rocp(close, 10) OVER run AS w15, fin_rocp(close, 10) OVER slide AS s15,
  fin_rocr(close, 10) OVER run AS w16, fin_rocr(close, 10) OVER slide AS s16,
  fin_rocr100(close, 10) OVER run AS w17, fin_rocr100(close, 10) OVER slide AS s17,
  fin_rsi(close, 14) OVER run AS w18, fin_rsi(close, 14) OVER slide AS s18,
  fin_cmo(close, 14) OVER run AS w19, fin_cmo(close, 14) OVER slide AS s19,
  fin_macd(close, 12, 26, 9) OVER run AS w20, fin_macd(close, 12, 26, 9) OVER slide AS s20,
  fin_apo(close, 12, 26, 'ema') OVER run AS w21, fin_apo(close, 12, 26, 'ema') OVER slide AS s21,
  fin_ppo(close, 12, 26, 'sma') OVER run AS w22, fin_ppo(close, 12, 26, 'sma') OVER slide AS s22,
  fin_trix(close, 15) OVER run AS w23, fin_trix(close, 15) OVER slide AS s23,
  fin_stochrsi(close, 14, 5, 3) OVER run AS w24, fin_stochrsi(close, 14, 5, 3) OVER slide AS s24,
  fin_bbands(close, 20, 2.0, 0) OVER run AS w25, fin_bbands(close, 20, 2.0, 0) OVER slide AS s25,
  fin_stddev(close, 20, 1) OVER run AS w26, fin_stddev(close, 20, 1) OVER slide AS s26,
  fin_var_indicator(close, 20, 0) OVER run AS w27, fin_var_indicator(close, 20, 0) OVER slide AS s27,
  fin_stoch(high, low, close, 14, 3, 3) OVER run AS w28, fin_stoch(high, low, close, 14, 3, 3) OVER slide AS s28,
  fin_willr(high, low, close, 14) OVER run AS w29, fin_willr(high, low, close, 14) OVER slide AS s29,
  fin_cci(high, low, close, 20, 0.015) OVER run AS w30, fin_cci(high, low, close, 20, 0.015) OVER slide AS s30,
  fin_keltner(high, low, close, 20, 10, 2.0) OVER run AS w31, fin_keltner(high, low, close, 20, 10, 2.0) OVER slide AS s31,
  fin_donchian(high, low, 20) OVER run AS w32, fin_donchian(high, low, 20) OVER slide AS s32,
  fin_aroon(high, low, 14) OVER run AS w33, fin_aroon(high, low, 14) OVER slide AS s33,
  fin_aroonosc(high, low, 14) OVER run AS w34, fin_aroonosc(high, low, 14) OVER slide AS s34,
  fin_sar(high, low, 0.02, 0.2) OVER run AS w35, fin_sar(high, low, 0.02, 0.2) OVER slide AS s35,
  fin_sarext(high, low, 0, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) OVER run AS w36, fin_sarext(high, low, 0, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2) OVER slide AS s36
FROM tech_determinism
WINDOW run AS (PARTITION BY sym ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
  slide AS (PARTITION BY sym ORDER BY i ROWS BETWEEN 40 PRECEDING AND CURRENT ROW);

SET threads = 1;
CREATE OR REPLACE TEMP TABLE tech_grouped_1 AS FROM tech_grouped();
CREATE OR REPLACE TEMP TABLE tech_windowed_1 AS FROM tech_windowed();
SET threads = 8;
CREATE OR REPLACE TEMP TABLE tech_grouped_8 AS FROM tech_grouped();
CREATE OR REPLACE TEMP TABLE tech_windowed_8 AS FROM tech_windowed();
RESET threads;

SELECT
  assert_eq('technical grouped results independent of threads',
    (SELECT count(*) FROM (FROM tech_grouped_1 EXCEPT FROM tech_grouped_8)), 0::BIGINT),
  assert_eq('technical window results independent of threads',
    (SELECT count(*) FROM (FROM tech_windowed_1 EXCEPT FROM tech_windowed_8)), 0::BIGINT),
  assert_eq('technical grouped value equals last running value',
    (SELECT count(*) FROM tech_grouped_1 g
     JOIN (SELECT sym, max(i) AS i FROM tech_determinism GROUP BY sym) l USING (sym)
     JOIN tech_windowed_1 w ON w.sym = g.sym AND w.i = l.i
     WHERE g.g18 IS DISTINCT FROM w.w18 OR g.g20 IS DISTINCT FROM w.w20 OR g.g35 IS DISTINCT FROM w.w35), 0::BIGINT);

-- Volume indicators (TA-Lib OBV and ADOSC) on gold_vbars.
SELECT assert_near('fin_obv(close, volume) grouped', fin_obv(close, volume ORDER BY i), 4000.0, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_obv(close, volume) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_near('fin_obv(close, volume) row 0', max(v) FILTER (WHERE i = 0), 1000.0, 1e-08),
  assert_near('fin_obv(close, volume) row 31', max(v) FILTER (WHERE i = 31), 5500.0, 1e-08),
  assert_near('fin_obv(close, volume) row 59', max(v) FILTER (WHERE i = 59), 4000.0, 1e-08)
FROM series;

SELECT assert_near('fin_adosc(high, low, close, volume) grouped', fin_adosc(high, low, close, volume ORDER BY i), -549.5996353980081, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_adosc(high, low, close, volume) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_adosc(high, low, close, volume) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 9)),
  assert_near('fin_adosc(high, low, close, volume) row 9', max(v) FILTER (WHERE i = 9), -507.61977315928823, 1e-08),
  assert_near('fin_adosc(high, low, close, volume) row 31', max(v) FILTER (WHERE i = 31), -575.0298845475027, 1e-08),
  assert_near('fin_adosc(high, low, close, volume) row 59', max(v) FILTER (WHERE i = 59), -549.5996353980081, 1e-08)
FROM series;

SELECT assert_near('fin_adosc(high, low, close, volume, 12, 5) grouped', fin_adosc(high, low, close, volume, 12, 5 ORDER BY i), 555.5982206756635, 1e-08)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_adosc(high, low, close, volume, 12, 5) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_true('fin_adosc(high, low, close, volume, 12, 5) warm-up rows', bool_and(v IS NULL) FILTER (WHERE i < 11)),
  assert_near('fin_adosc(high, low, close, volume, 12, 5) row 11', max(v) FILTER (WHERE i = 11), 439.6788808103897, 1e-08),
  assert_near('fin_adosc(high, low, close, volume, 12, 5) row 31', max(v) FILTER (WHERE i = 31), 576.6403022252334, 1e-08),
  assert_near('fin_adosc(high, low, close, volume, 12, 5) row 59', max(v) FILTER (WHERE i = 59), 555.5982206756635, 1e-08)
FROM series;

-- Order-independent volume aggregates (independent numpy references).
SELECT
  assert_near('vwap gold_vbars', fin_vwap(close, volume), 101.64584546472564, 1e-10),
  assert_near('ad line equals TA-Lib AD at the last row', fin_ad_line(high, low, close, volume), -9615.37294238774, 1e-07),
  assert_near('kyle lambda (price_change, signed_volume)', fin_kyle_lambda(dp, signed_volume), 9.133967405374617e-05, 1e-15),
  assert_near('amihud mean abs return per dollar volume', fin_amihud_illiquidity(ret, close * volume), 9.505952773757311e-08, 1e-20)
FROM (SELECT *, close - lag(close) OVER (ORDER BY i) AS dp, ln(close / lag(close) OVER (ORDER BY i)) AS ret FROM gold_vbars);

WITH series AS (
  SELECT i, fin_ad_line(high, low, close, volume) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_near('ad line running row 0', max(v) FILTER (WHERE i = 0), 142.85714285713416, 1e-08),
  assert_near('ad line running row 31', max(v) FILTER (WHERE i = 31), -5159.844059444931, 1e-07)
FROM series;

SELECT
  assert_near('twap irregular timestamps', fin_twap(close, ts ORDER BY ts), 101.69483987747145, 1e-10),
  assert_near('twap epoch seconds', fin_twap(close, epoch(ts) ORDER BY ts), 101.69483987747145, 1e-10),
  assert_near('twap date axis', fin_twap(close, DATE '2026-01-01' + i ORDER BY i), (sum(close) - last(close ORDER BY i)) / 59, 1e-10)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_twap(close, ts) OVER (ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v FROM gold_vbars
)
SELECT
  assert_near('twap running row 0 is the price', max(v) FILTER (WHERE i = 0), 100.8, 1e-12),
  assert_near('twap running row 31', max(v) FILTER (WHERE i = 31), 101.2058817373103, 1e-10)
FROM series;

SELECT
  assert_near('twap averages tied timestamps', fin_twap(price, ts ORDER BY ts), (10.0 * 1 + 11.5 * 2 + 11.5 * 1) / 4, 1e-12),
  assert_near('twap single timestamp', fin_twap(price, ts) FILTER (WHERE seq IN (2, 3)), 11.5, 1e-12)
FROM gold_ticks WHERE sym = 'X';

SELECT assert_eq('volume profile bins', fin_volume_profile(close, volume, 4),
  [{'price_low': 97.33, 'price_high': 99.63, 'volume': 22300.0},
   {'price_low': 99.63, 'price_high': 101.93, 'volume': 25300.0},
   {'price_low': 101.93, 'price_high': 104.23, 'volume': 24300.0},
   {'price_low': 104.23, 'price_high': 106.53, 'volume': 17400.0}])
FROM gold_vbars;

SELECT assert_eq('volume profile window frame equals grouped',
  (SELECT v FROM (SELECT i, fin_volume_profile(close, volume, 4) OVER (ORDER BY i ROWS BETWEEN 59 PRECEDING AND CURRENT ROW) AS v FROM gold_vbars) WHERE i = 59),
  (SELECT fin_volume_profile(close, volume, 4) FROM gold_vbars));

-- More than 1024 distinct prices switch to the bounded power-of-two grid: volume
-- is conserved and moves at most one grid cell (about 1.2 rows here) per edge.
SELECT
  assert_near('volume profile grid conserves volume', list_sum([b.volume FOR b IN p]), 5000.0, 1e-9),
  assert_true('volume profile grid bins within one cell', list_bool_and([abs(b.volume - 1000) <= 3 FOR b IN p])),
  assert_near('volume profile grid edges are exact', p[5].price_high, 4.999, 1e-12)
FROM (SELECT fin_volume_profile(i * 0.001, 1.0, 5) AS p FROM range(5000) t(i));

-- VPIN: independent reference that intersects cumulative-volume intervals
-- with the 2500-share buckets (last 10 buckets).
SELECT assert_near('vpin grouped', fin_vpin(signed_volume, volume, 10, 2500 ORDER BY i), 0.396, 1e-12)
FROM gold_vbars;

WITH series AS (
  SELECT i, fin_vpin(signed_volume, volume, 10, 2500) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v
  FROM gold_vbars
)
SELECT
  assert_true('vpin warm-up until 10 buckets complete', bool_and(v IS NULL) FILTER (WHERE i < 16)),
  assert_near('vpin row 16', max(v) FILTER (WHERE i = 16), 0.20399999999999996, 1e-12),
  assert_near('vpin row 40', max(v) FILTER (WHERE i = 40), 0.38400000000000006, 1e-12)
FROM series;

SELECT
  assert_near('vpin one-sided flow is 1', fin_vpin(volume, volume, 5, 1000 ORDER BY i), 1.0, 1e-12),
  assert_eq('vpin rejects |signed| > volume', fin_vpin(2 * volume, volume, 5, 1000 ORDER BY i), NULL)
FROM gold_vbars;

-- Roll (1984): 2 * sqrt(-cov(dP_t, dP_t-1)) with the sample covariance (numpy).
CREATE OR REPLACE TEMP TABLE gold_roll AS
SELECT i, 100 + 0.05 * ((i * 7) % 3) - 0.02 * (i % 2) AS price FROM range(40) t(i);

SELECT
  assert_near('roll spread', fin_roll_spread(price ORDER BY i), 0.10933134416304795, 1e-12),
  assert_eq('roll spread trending series is NULL', (SELECT fin_roll_spread(close ORDER BY i) FROM gold_vbars), NULL)
FROM gold_roll;

WITH series AS (
  SELECT i, fin_roll_spread(price) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS v,
    fin_roll_spread(price) OVER (ORDER BY i ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS w
  FROM gold_roll
)
SELECT
  assert_true('roll spread needs four prices', bool_and(v IS NULL) FILTER (WHERE i < 3)),
  assert_near('roll spread row 3', max(v) FILTER (WHERE i = 3), 0.12328828005936192, 1e-12),
  assert_near('roll spread row 10', max(v) FILTER (WHERE i = 10), 0.12660086009887542, 1e-12),
  assert_near('roll spread sliding frame', max(w) FILTER (WHERE i = 39), 0.1108257774219274, 1e-12)
FROM series;

-- Volume, directional and microstructure indicators are deterministic: grouped
-- and windowed results are bit-identical for one and eight threads.
CREATE OR REPLACE TEMP TABLE volume_determinism AS
SELECT i % 7 AS sym, i, 100 + 5 * sin(i / 9.0) + (i % 13) * 0.07 AS close,
  101 + 5 * sin(i / 9.0) + (i % 3) * 0.05 AS high, 99 + 5 * sin(i / 9.0) - (i % 5) * 0.03 AS low,
  1000.0 + (i % 11) * 10 AS volume, (1000.0 + (i % 11) * 10) * ((i % 5) / 2.0 - 1.0) AS signed_volume,
  TIMESTAMP '2026-01-01' + to_seconds(i) AS ts
FROM range(20000) t(i);

CREATE OR REPLACE TEMP MACRO volume_grouped() AS TABLE
SELECT sym,
  fin_true_range(high, low, close ORDER BY i) AS g0,
  fin_atr(high, low, close, 14 ORDER BY i) AS g1,
  fin_natr(high, low, close, 14 ORDER BY i) AS g2,
  fin_plus_dm(high, low, 14 ORDER BY i) AS g3,
  fin_minus_dm(high, low, 14 ORDER BY i) AS g4,
  fin_plus_di(high, low, close, 14 ORDER BY i) AS g5,
  fin_minus_di(high, low, close, 14 ORDER BY i) AS g6,
  fin_dx(high, low, close, 14 ORDER BY i) AS g7,
  fin_adx(high, low, close, 14 ORDER BY i) AS g8,
  fin_adxr(high, low, close, 14 ORDER BY i) AS g9,
  fin_mfi(high, low, close, volume, 14 ORDER BY i) AS g10,
  fin_ultosc(high, low, close, 7, 14, 28 ORDER BY i) AS g11,
  fin_obv(close, volume ORDER BY i) AS g12,
  fin_adosc(high, low, close, volume, 3, 10 ORDER BY i) AS g13,
  fin_roll_spread(close ORDER BY i) AS g14,
  fin_vpin(signed_volume, volume, 20, 5000 ORDER BY i) AS g15,
  fin_twap(close, ts ORDER BY ts) AS g16,
  fin_ohlc(close, ts) AS g17,
  fin_ohlcv(close, volume, ts) AS g18,
  fin_vwap(close, volume) AS g19,
  fin_ad_line(high, low, close, volume) AS g20,
  fin_amihud_illiquidity(close / 100 - 1, close * volume) AS g21,
  fin_kyle_lambda(close - 100, signed_volume) AS g22,
  fin_volume_profile(close, volume, 7) AS g23
FROM volume_determinism GROUP BY sym;

CREATE OR REPLACE TEMP MACRO volume_windowed() AS TABLE
SELECT sym, i,
  fin_true_range(high, low, close) OVER run AS w0, fin_true_range(high, low, close) OVER slide AS s0,
  fin_atr(high, low, close, 14) OVER run AS w1, fin_atr(high, low, close, 14) OVER slide AS s1,
  fin_natr(high, low, close, 14) OVER run AS w2, fin_natr(high, low, close, 14) OVER slide AS s2,
  fin_plus_dm(high, low, 14) OVER run AS w3, fin_plus_dm(high, low, 14) OVER slide AS s3,
  fin_minus_dm(high, low, 14) OVER run AS w4, fin_minus_dm(high, low, 14) OVER slide AS s4,
  fin_plus_di(high, low, close, 14) OVER run AS w5, fin_plus_di(high, low, close, 14) OVER slide AS s5,
  fin_minus_di(high, low, close, 14) OVER run AS w6, fin_minus_di(high, low, close, 14) OVER slide AS s6,
  fin_dx(high, low, close, 14) OVER run AS w7, fin_dx(high, low, close, 14) OVER slide AS s7,
  fin_adx(high, low, close, 14) OVER run AS w8, fin_adx(high, low, close, 14) OVER slide AS s8,
  fin_adxr(high, low, close, 14) OVER run AS w9, fin_adxr(high, low, close, 14) OVER slide AS s9,
  fin_mfi(high, low, close, volume, 14) OVER run AS w10, fin_mfi(high, low, close, volume, 14) OVER slide AS s10,
  fin_ultosc(high, low, close, 7, 14, 28) OVER run AS w11, fin_ultosc(high, low, close, 7, 14, 28) OVER slide AS s11,
  fin_obv(close, volume) OVER run AS w12, fin_obv(close, volume) OVER slide AS s12,
  fin_adosc(high, low, close, volume, 3, 10) OVER run AS w13, fin_adosc(high, low, close, volume, 3, 10) OVER slide AS s13,
  fin_roll_spread(close) OVER run AS w14, fin_roll_spread(close) OVER slide AS s14,
  fin_vpin(signed_volume, volume, 20, 5000) OVER run AS w15, fin_vpin(signed_volume, volume, 20, 5000) OVER slide AS s15,
  fin_twap(close, ts) OVER run AS w16, fin_twap(close, ts) OVER slide AS s16,
  fin_vwap(close, volume) OVER slide AS s17,
  fin_ad_line(high, low, close, volume) OVER run AS w18
FROM volume_determinism
WINDOW run AS (PARTITION BY sym ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
  slide AS (PARTITION BY sym ORDER BY i ROWS BETWEEN 40 PRECEDING AND CURRENT ROW);

SET threads = 1;
CREATE OR REPLACE TEMP TABLE volume_grouped_1 AS FROM volume_grouped();
CREATE OR REPLACE TEMP TABLE volume_windowed_1 AS FROM volume_windowed();
SET threads = 8;
CREATE OR REPLACE TEMP TABLE volume_grouped_8 AS FROM volume_grouped();
CREATE OR REPLACE TEMP TABLE volume_windowed_8 AS FROM volume_windowed();
RESET threads;

SELECT
  assert_eq('volume indicators grouped results independent of threads',
    (SELECT count(*) FROM (FROM volume_grouped_1 EXCEPT FROM volume_grouped_8)), 0::BIGINT),
  assert_eq('volume indicators window results independent of threads',
    (SELECT count(*) FROM (FROM volume_windowed_1 EXCEPT FROM volume_windowed_8)), 0::BIGINT),
  assert_eq('volume indicators grouped value equals last running value',
    (SELECT count(*) FROM volume_grouped_1 g
     JOIN (SELECT sym, max(i) AS i FROM volume_determinism GROUP BY sym) l USING (sym)
     JOIN volume_windowed_1 w ON w.sym = g.sym AND w.i = l.i
     WHERE g.g9 IS DISTINCT FROM w.w9 OR g.g11 IS DISTINCT FROM w.w11 OR g.g15 IS DISTINCT FROM w.w15
       OR g.g16 IS DISTINCT FROM w.w16), 0::BIGINT);

SELECT
  assert_near('ewma variance optional args', fin_ewma_variance(r, 0.94, 252.0), 0.040298154624000014, 1e-12),
  assert_near('ewma vol optional args', fin_ewma_vol(r, 0.94, 252.0), 0.20074400270991913, 1e-12),
  assert_near('iv rank', fin_iv_rank(factor), 1.0, 1e-12),
  assert_near('iv percentile', fin_iv_percentile(factor), 1.0, 1e-12),
  assert_eq('outlier count default', fin_outlier_count(r), 0::BIGINT),
  assert_eq('outlier count threshold', fin_outlier_count(r, 'zscore', 1.0), 2::BIGINT),
  assert_eq('missing count', fin_missing_count(r), 0::BIGINT),
  assert_eq('data quality n', (fin_data_quality_report(r)).n, 5::BIGINT)
FROM gold_returns;

SELECT
  assert_eq('data quality finite', (fin_data_quality_report(x)).finite, 3::BIGINT),
  assert_eq('data quality min ignores non-finite', (fin_data_quality_report(x)).min, -1.0::DOUBLE),
  assert_eq('data quality max ignores non-finite', (fin_data_quality_report(x)).max, 2.0::DOUBLE),
  assert_eq('data quality max type', typeof((fin_data_quality_report(x)).max), 'DOUBLE')
FROM (VALUES (1.0), (NULL), ('nan'::DOUBLE), ('inf'::DOUBLE), (-1.0), (2.0)) t(x);

WITH iv_path(seq, iv) AS (VALUES (1, 0.10), (2, 0.20), (3, 0.15))
SELECT
  assert_near('iv rank respects ascending aggregate order', fin_iv_rank(iv ORDER BY iv), 1.0, 1e-12),
  assert_near('iv rank respects descending aggregate order', fin_iv_rank(iv ORDER BY iv DESC), 0.0, 1e-12),
  assert_near('iv percentile respects ascending aggregate order', fin_iv_percentile(iv ORDER BY iv), 1.0, 1e-12),
  assert_near('iv percentile respects descending aggregate order', fin_iv_percentile(iv ORDER BY iv DESC), 0.0, 1e-12)
FROM iv_path;

-- Second sweep: exponential weighting and empirical percentiles have their
-- own independent expectations, including ordering, NULLs, ties and windows.
-- fin_ema follows TA-Lib: the SMA of the first `period` values seeds the
-- recurrence ema = k * x + (1 - k) * ema with k = 2 / (period + 1).
WITH path(i, x) AS (VALUES (1, 10.0), (2, 20.0), (3, NULL), (4, 40.0))
SELECT
  assert_eq('ema default period warm-up', fin_ema(x ORDER BY i), NULL),
  assert_near('ema period two', fin_ema(x, 2 ORDER BY i), 95.0/3.0, 1e-12),
  assert_near('ema period three seeds with the mean', fin_ema(x, 3 ORDER BY i), 70.0/3.0, 1e-12),
  assert_near('ema reverse order', fin_ema(x, 2 ORDER BY i DESC), 50.0/3.0, 1e-12),
  assert_near('ema period one', fin_ema(x, 1 ORDER BY i), 40.0, 1e-12),
  assert_near('ema filtered rows', fin_ema(x, 2 ORDER BY i) FILTER (WHERE i <> 2), 25.0, 1e-12),
  assert_near('ema subset without ordering', fin_ema(x, 1) FILTER (WHERE i = 2), 20.0, 1e-12)
FROM path;

SELECT
  assert_eq('ema empty', fin_ema(x), NULL),
  assert_eq('iv percentile empty', fin_iv_percentile(x), NULL)
FROM (SELECT NULL::DOUBLE AS x WHERE false);

SELECT
  assert_eq('ema null input', fin_ema(NULL::DOUBLE), NULL),
  assert_eq('iv percentile singleton', fin_iv_percentile(0.2), NULL);

WITH path(i, x) AS (VALUES (1, 10.0), (2, 20.0), (3, 40.0)), results AS (
  SELECT i, fin_ema(x, 2) OVER (ORDER BY i ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS ema
  FROM path
)
SELECT assert_true('ema sliding window reseeds', bool_and(ema IS NOT DISTINCT FROM CASE i WHEN 2 THEN 15 WHEN 3 THEN 30 END))
FROM results;

SELECT
  assert_near('ema constant batch default', fin_ema(7.0), 7.0, 1e-12),
  assert_near('ema constant batch period one', fin_ema(7.0, 1), 7.0, 1e-12),
  assert_near('ema extreme finite constant', fin_ema(1.7e308)/1.7e308, 1.0, 1e-12)
FROM range(10000);

SELECT assert_near('ema seed avoids extreme overflow', fin_ema(x, 2 ORDER BY i), 0.0, 0.0)
FROM (VALUES (1, -1e308), (2, 1e308)) t(i,x);

WITH path AS (SELECT i, CASE WHEN i = 0 THEN 1e200 ELSE 0.0 END AS x FROM range(1501) t(i))
SELECT
  assert_near('ema decays geometrically after the seed', fin_ema(x,3 ORDER BY i)/(1e200/3*pow(2.0,-1000)), pow(2.0,-498), 1e-162),
  assert_near('ewma decay preserves finite late volatility', fin_ewma_vol(x,0.5,1 ORDER BY i)/1e200, pow(2.0,-750), 1e-237)
FROM path;

SELECT assert_near('ewma tiny lambda retains past contribution', fin_ewma_vol(x,1e-300,1 ORDER BY i)/1e50, 1.0, 1e-12)
FROM (VALUES (1,1e200),(2,0.0)) t(i,x);

SELECT assert_near('ewma repeated tiny lambda preserves decay', fin_ewma_vol(x,1e-190,1 ORDER BY i)/1e118, 1.0, 1e-12)
FROM (VALUES (1,1e308),(2,0.0),(3,0.0)) t(i,x);

WITH path(i,x) AS (VALUES (1,-1e308),(2,1e308),(3,1e-320))
SELECT assert_near('ema seed cancels extreme values exactly', fin_ema(x,3 ORDER BY i)/1e-320, 1.0/3.0, 1e-3)
FROM path;

SELECT assert_eq('ema period one returns tiny latest value', fin_ema(x,1 ORDER BY i), 1e-320)
FROM (VALUES (1,1e308),(2,1e-320)) t(i,x);

WITH path AS (
  SELECT i, CASE WHEN i=8193 THEN -1e308 WHEN i=8194 THEN 1e308 WHEN i=8195 THEN 1e-320 ELSE 0.0 END AS x
  FROM range(8196) t(i)
), results AS (
  SELECT i, fin_ema(x,3) OVER (ORDER BY i ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ema FROM path
)
SELECT assert_near('ema sliding frame seeds from the frame rows', ema/1e-320, 1.0/3.0, 1e-3)
FROM results WHERE i=8195;

WITH path(i, iv) AS (VALUES (1, 0.1), (2, 0.11), (3, 0.9), (4, NULL), (5, 0.2))
SELECT
  assert_near('iv empirical percentile differs from rank', fin_iv_percentile(iv ORDER BY i), 2.0/3.0, 1e-12),
  assert_near('iv minmax rank remains separate', fin_iv_rank(iv ORDER BY i), 0.125, 1e-12)
FROM path;

WITH path(i, iv) AS (VALUES (1, 0.1), (2, 0.2), (3, 0.2), (4, 0.2))
SELECT assert_near('iv strict ties', fin_iv_percentile(iv ORDER BY i), 1.0/3.0, 1e-12)
FROM path;

SELECT
  assert_near('iv constant percentile', fin_iv_percentile(0.2), 0.0, 0.0),
  assert_eq('iv constant rank undefined', fin_iv_rank(0.2), NULL)
FROM range(4);

WITH path(i, iv) AS (VALUES (1, 0.1), (2, 0.11), (3, 0.9), (4, 0.2)), results AS (
  SELECT i, fin_iv_percentile(iv) OVER (ORDER BY i ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS p
  FROM path
)
SELECT assert_true('iv percentile sliding window',
  bool_and(p IS NOT DISTINCT FROM CASE WHEN i = 1 THEN NULL WHEN i < 4 THEN 1.0 ELSE 0.5 END))
FROM results;

-- Large values and weights must not overflow intermediate arithmetic.
SELECT
  assert_near('weighted linear opposite extremes', fin_weighted_quantile(x,w,0.75)/1e308, 0.0, 0.0),
  assert_near('weighted midpoint opposite extremes', fin_weighted_quantile(x,w,0.75,'midpoint')/1e308, 0.0, 0.0),
  assert_near('weighted quantile large weight', fin_weighted_quantile(x,w,0.875)/1e308, 0.5, 1e-12),
  assert_near('weighted quantile case compatibility', fin_weighted_quantile(x,w,0.875,'LiNeAr')/1e308, 0.5, 1e-12),
  assert_near('weighted quantile zero endpoint', fin_weighted_quantile(x,w,0)/1e308, -1.0, 1e-12),
  assert_near('weighted quantile one endpoint', fin_weighted_quantile(x,w,1)/1e308, 1.0, 1e-12)
FROM (VALUES (-1e308,1e308), (1e308,1e308)) t(x,w);

SELECT assert_near('weighted midpoint large same sign', fin_weighted_quantile(x,1.0,0.75,'midpoint')/1e308, 1.4, 1e-12)
FROM (VALUES (1.2e308), (1.6e308)) t(x);

SELECT assert_near('weighted tiny scale invariant', fin_weighted_quantile(x,w,0.75), 15.0, 1e-12)
FROM (VALUES (10.0,1e-300), (20.0,1e-300)) t(x,w);

SELECT assert_near('weighted subnormal weights', fin_weighted_quantile(x,w,0.75), 15.0, 1e-12)
FROM (VALUES (10.0,1e-320), (20.0,1e-320)) t(x,w);

SELECT assert_near('weighted value ties canonicalize weights', fin_weighted_quantile(x,w,0.4), 10.0, 1e-12)
FROM (VALUES (0.0,1.0),(10.0,2.0),(10.0,5.0),(20.0,3.0)) t(x,w);

SELECT assert_near('weighted reversed ties same knots', fin_weighted_quantile(x,w,0.4), 10.0, 1e-12)
FROM (VALUES (20.0,3.0),(10.0,5.0),(10.0,2.0),(0.0,1.0)) t(x,w);

WITH observations AS (
  SELECT i, CASE WHEN i = 9 THEN 1.0 ELSE 0.0 END AS x FROM range(10) t(i)
)
SELECT
  assert_eq('outlier extreme scale', fin_outlier_count(x*1e308,2.0), 1::BIGINT),
  assert_eq('outlier tiny scale', fin_outlier_count(x*1e-300,2.0), 1::BIGINT),
  assert_eq('outlier affine shift', fin_outlier_count((1+x)*1e200,2.0), 1::BIGINT),
  assert_eq('outlier sign reversal', fin_outlier_count(-x*1e308,2.0), 1::BIGINT)
FROM observations;

WITH observations AS (
  SELECT CASE WHEN i = 9 THEN 1e-320 ELSE 0.0 END AS x FROM range(10) t(i)
)
SELECT assert_eq('outlier subnormal scale', fin_outlier_count(x,2.0), 1::BIGINT) FROM observations;

WITH observations AS (
  SELECT CASE WHEN i < 5 THEN 1.0 ELSE -1.0 END AS x FROM range(10) t(i)
)
SELECT assert_eq('outlier huge opposite signs', fin_outlier_count(x*1e308,0.5), 10::BIGINT)
FROM observations;

SELECT
  assert_eq('outlier extreme constant', fin_outlier_count(1e308), 0::BIGINT),
  assert_eq('outlier zero constant', fin_outlier_count(0.0), 0::BIGINT)
FROM range(10);

SELECT assert_eq('outlier constant rounding cannot create variance', fin_outlier_count(0.1,0.5), 0::BIGINT)
FROM range(3);

SELECT assert_eq('outlier non-finite and null fallback', fin_outlier_count(x,2.0), 1::BIGINT)
FROM (VALUES (0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(10.0),
             ('NaN'::DOUBLE),('Infinity'::DOUBLE),(NULL)) t(x);

SELECT assert_eq('outlier non-finite chunk cannot append twice', fin_outlier_count(x,2.0), 1::BIGINT)
FROM (VALUES (0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(0.0),(10.0),
             ('NaN'::DOUBLE)) t(x);

-- Non-finite observations validate thresholds but do not fix the group's
-- threshold until a finite observation arrives. NULL arguments skip the row.
WITH observations(seq, x, threshold) AS (
  VALUES (1, 'NaN'::DOUBLE, 7.0), (2, 'Infinity'::DOUBLE, 4.0),
         (3, NULL, -1.0), (4, 999.0, NULL),
         (5, 0.0, 1.0), (6, 0.0, 1.0), (7, 10.0, 1.0)
)
SELECT
  assert_eq('outlier ignored prefix does not fix threshold',
    fin_outlier_count(x, threshold ORDER BY seq), 1::BIGINT),
  assert_eq('outlier ignored prefix with method overload',
    fin_outlier_count(x, 'ZSCORE', threshold ORDER BY seq), 1::BIGINT)
FROM observations;

SELECT assert_eq('outlier all non-finite thresholds may differ',
  fin_outlier_count(x, threshold ORDER BY seq), 0::BIGINT)
FROM (VALUES (1, 'NaN'::DOUBLE, 1.0), (2, 'Infinity'::DOUBLE, 2.0)) t(seq, x, threshold);

CREATE TEMP TABLE outlier_threshold_batches AS
SELECT i, CASE WHEN i = 4095 THEN 10.0 ELSE 0.0 END AS x, 2.0::DOUBLE AS threshold
FROM range(4096) t(i);
SELECT
  assert_eq('outlier flat threshold across chunks', fin_outlier_count(x, 2.0), 1::BIGINT),
  assert_eq('outlier row threshold across chunks', fin_outlier_count(x, threshold), 1::BIGINT),
  assert_eq('outlier method threshold across chunks', fin_outlier_count(x, 'zscore', threshold), 1::BIGINT)
FROM outlier_threshold_batches;
DROP TABLE outlier_threshold_batches;

WITH samples(factor, r) AS (VALUES (0.0,0.0),(0.0,6.0),(0.0,12.0),(1.0,20.0),(2.0,40.0))
SELECT
  assert_near('quantile spread proportional boundary ties', fin_quantile_spread(factor,r,2), 16.0, 1e-12),
  assert_near('quantile spread tie order invariant', fin_quantile_spread(factor,r,2 ORDER BY r DESC), 16.0, 1e-12),
  assert_near('quantile spread constant factor', fin_quantile_spread(1.0,r,2), 0.0, 0.0)
FROM samples;

SELECT assert_near('quantile spread avoids sum overflow', fin_quantile_spread(factor,r,2)/1e307, 1.0, 1e-12)
FROM (VALUES (1.0,1e308),(2.0,1e308),(3.0,1.1e308),(4.0,1.1e308)) t(factor,r);

SELECT assert_eq('quantile spread unrepresentable result', fin_quantile_spread(factor,r,2), NULL)
FROM (VALUES (1.0,-1e308),(2.0,1e308)) t(factor,r);

SELECT
  assert_near('ewma extreme finite volatility', fin_ewma_vol(1e200)/1e200, sqrt(252.0), 1e-12),
  assert_eq('ewma unrepresentable variance', fin_ewma_variance(1e200), NULL),
  assert_near('ewma tiny finite volatility', fin_ewma_vol(1e-200)/1e-200, sqrt(252.0), 1e-12),
  assert_near('ewma small annualization', fin_ewma_variance(1e200,0.94,1e-200)/1e200, 1.0, 1e-12)
FROM range(100);

SELECT
  assert_near('sortino huge scale invariance', fin_sortino(x*1e200,0,1), 2.0/sqrt(3.0), 1e-12),
  assert_near('sortino tiny scale invariance', fin_sortino(x*1e-200,0,1), 2.0/sqrt(3.0), 1e-12)
FROM (VALUES (-1.0),(1.0),(2.0)) t(x);

SELECT assert_near('sortino compensated cancellation', fin_sortino(x,0,1), 1e-16/sqrt(3.0), 1e-28)
FROM (VALUES (1e16),(1.0),(-1e16)) t(x);

SELECT assert_near('sortino asymmetric extreme scales', fin_sortino(x,0,1)/1e208, 1.0/sqrt(2.0), 1e-12)
FROM (VALUES (-1e100),(1e308)) t(x);

SELECT assert_near('sortino annualization rescues ratio overflow', fin_sortino(x,0,1e-200)/1e208, 1.0/sqrt(2.0), 1e-12)
FROM (VALUES (-1.0),(1e308)) t(x);

-- Fixed income, cash-flow, and curve helpers.
SELECT
  assert_near('yearfrac act365', fin_yearfrac(DATE '2026-01-01', DATE '2027-01-01', 'ACT/365F'), 1.0, 1e-12),
  assert_near('yearfrac actact reverse dates',
    fin_yearfrac(DATE '2027-07-01', DATE '2026-01-01', 'ACT/ACT'),
    -fin_yearfrac(DATE '2026-01-01', DATE '2027-07-01', 'ACT/ACT'), 1e-12),
  assert_near('discount continuous', fin_discount_factor(0.05, 1.0, 'continuous'), 0.951229424500714, 1e-12),
  assert_near('discount periodic', fin_discount_factor(0.05, 1.0, 'periodic'), 0.9523809523809523, 1e-12),
  assert_near('rate from discount', fin_rate_from_discount(0.951229424500714, 1.0, 'continuous'), 0.05, 1e-12),
  assert_near('forward rate', fin_forward_rate(0.9607894391523232, 0.8869204367171575, 1.0, 2.0, 'continuous'), 0.08, 1e-12),
  assert_near('present value', fin_present_value(105.12710963760242, 0.05, 1.0, 'continuous'), 100.0, 1e-10),
  assert_near('future value', fin_future_value(100.0, 0.05, 1.0, 'continuous'), 105.12710963760242, 1e-10),
  assert_near('annuity payment zero rate', fin_annuity_payment(0.0, 10.0, 100.0), -10.0, 1e-12),
  assert_near('bond price', fin_bond_price(0.05, 0.04, 5.0, 2, 100.0), 104.4912925031211, 1e-10),
  assert_near('bond ytm roundtrip', fin_bond_ytm(fin_bond_price(0.05, 0.04, 5.0, 2, 100.0), 0.05, 5.0, 2, 100.0), 0.04, 1e-10),
  assert_not_null('bond duration', fin_bond_duration(0.05, 0.04, 5.0, 2, 100.0, 'modified')),
  assert_not_null('bond convexity', fin_bond_convexity(0.05, 0.04, 5.0, 2, 100.0)),
  assert_not_null('dv01', fin_dv01(0.05, 0.04, 5.0, 2, 100.0)),
  assert_near('accrued interest half period', fin_accrued_interest(DATE '2026-04-01', DATE '2026-01-01', DATE '2026-07-01', 0.04, 100.0, 'ACT/365F'), 0.9863013698630136, 1e-12),
  assert_near('npv timed periodic', fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic'), 4.132231404958667, 1e-12),
  assert_near('irr', fin_irr([-100.0, 60.0, 60.0]), 0.1306623862918075, 1e-10),
  assert_near('irr multiple roots default guess', fin_irr([-100.0, 230.0, -132.0]), 0.1, 1e-10),
  assert_near('irr multiple roots high guess', fin_irr([-100.0, 230.0, -132.0], 0.25), 0.2, 1e-10),
  assert_eq('irr requires opposing cashflows', fin_irr([100.0, 60.0, 60.0]), NULL),
  assert_not_null('mirr', fin_mirr([-100.0, 60.0, 60.0], 0.1, 0.05)),
  assert_near('xirr annual', fin_xirr([-100.0, 110.0], [DATE '2026-01-01', DATE '2027-01-01']), 0.1, 1e-8),
  assert_near('xirr multiple roots high guess',
    fin_xirr(
      [-100.0, 230.0, -132.0],
      [DATE '2026-01-01', DATE '2027-01-01', DATE '2028-01-01'],
      0.25
    ),
    0.2,
    1e-10),
  assert_near('curve interpolation', fin_interpolate_curve([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5), 0.0475, 1e-12),
  assert_near('curve zero rate', fin_curve_zero_rate([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5), 0.0475, 1e-12),
  assert_near('curve discount factor', fin_curve_discount_factor([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5), 0.9312290557603188, 1e-12),
  assert_not_null('swap rate', fin_swap_rate([1.0, 2.0], [0.95, 0.90])),
  assert_near('fra rate', fin_fra_rate(0.04, 0.05, 1.0, 2.0), 0.06, 1e-12);

-- Option models and Greeks.
SELECT
  assert_near('option payoff', fin_option_payoff('call', 105.0, 100.0), 5.0, 1e-12),
  assert_near('bsm d1', fin_bsm_d1(100.0, 100.0, 1.0, 0.05, 0.2, 0.0), 0.35, 1e-12),
  assert_near('bsm d2', fin_bsm_d2(100.0, 100.0, 1.0, 0.05, 0.2, 0.0), 0.15, 1e-12),
  assert_near('bsm call price', fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 10.450583572185565, 1e-10),
  assert_near('bsm put price', fin_bsm_price('put', 100.0, 100.0, 1.0, 0.05, 0.2), 5.573526022256971, 1e-10),
  assert_near('bsm spec price', fin_bsm_price(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2)), 10.450583572185565, 1e-10),
  assert_near('bsm delta', fin_bsm_delta('call', 100.0, 100.0, 1.0, 0.05, 0.2), 0.6368306511756191, 1e-10),
  assert_near('bsm spec delta', fin_bsm_delta(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2)), 0.6368306511756191, 1e-10),
  assert_near('bsm gamma', fin_bsm_gamma(100.0, 100.0, 1.0, 0.05, 0.2), 0.018762017345846895, 1e-12),
  assert_near('bsm spec gamma', fin_bsm_gamma(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2)), 0.018762017345846895, 1e-12),
  assert_near('bsm vega', fin_bsm_vega('call', 100.0, 100.0, 1.0, 0.05, 0.2), 37.52403469169379, 1e-10),
  assert_near('bsm spec vega', fin_bsm_vega(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2)), 37.52403469169379, 1e-10),
  assert_near('bsm theta', fin_bsm_theta('call', 100.0, 100.0, 1.0, 0.05, 0.2), -6.414027546438197, 1e-10),
  assert_near('bsm rho', fin_bsm_rho('call', 100.0, 100.0, 1.0, 0.05, 0.2), 53.232481545376345, 1e-10),
  assert_near('bsm greeks struct', (fin_bsm_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)).delta, 0.6368306511756191, 1e-10),
  assert_near('bsm spec greeks struct', (fin_bsm_greeks(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))).delta, 0.6368306511756191, 1e-10),
  assert_near('bsm all price', (fin_bsm_all('call', 100.0, 100.0, 1.0, 0.05, 0.2)).price, 10.450583572185565, 1e-10),
  assert_near('bsm spec all price', (fin_bsm_all(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))).price, 10.450583572185565, 1e-10),
  assert_near('bsm implied vol', fin_bsm_implied_vol('call', fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05), 0.2, 1e-8),
  assert_near('bsm prob itm', fin_bsm_prob_itm('call', 100.0, 100.0, 1.0, 0.05, 0.2), 0.5596176923702425, 1e-10),
  assert_near('bsm prob touch', fin_bsm_prob_touch('call', 100.0, 100.0, 1.0, 0.05, 0.2), 1.0, 1e-12),
  assert_not_null('bsm elasticity', fin_bsm_elasticity('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm vanna', fin_bsm_vanna('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm vomma', fin_bsm_vomma('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm speed', fin_bsm_speed('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm zomma', fin_bsm_zomma('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm ultima', fin_bsm_ultima('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm charm', fin_bsm_charm('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_not_null('bsm color', fin_bsm_color('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_near('bsm price dates', fin_bsm_price_dates('call', 100.0, 100.0, DATE '2026-01-01', DATE '2027-01-01', 0.05, 0.2), 10.450583572185565, 1e-10),
  assert_near('put call parity residual', fin_put_call_parity(10.450583572185565, 5.573526022256971, 100.0, 100.0, 1.0, 0.05, 0.0), 0.0, 1e-10),
  assert_near('forward price', fin_forward_price(100.0, 1.0, 0.05, 0.0), 105.12710963760242, 1e-10),
  assert_not_null('black76 greeks', (fin_black76_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)).delta),
  assert_not_null('bachelier greeks', (fin_bachelier_greeks('call', 100.0, 100.0, 1.0, 0.05, 5.0)).delta),
  assert_not_null('binomial price', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'european', 'crr')),
  assert_near('binomial zero vol european call discounts deterministic payoff',
    fin_binomial_price('call', 100.0, 90.0, 1.0, 0.05, 0.0, 0.0, 20, 'european', 'crr'),
    exp(-0.05) * greatest(100.0 * exp(0.05) - 90.0, 0.0), 1e-12),
  assert_near('binomial zero vol european put includes dividend yield',
    fin_binomial_price('put', 100.0, 110.0, 2.0, 0.03, 0.0, 0.02, 20, 'european', 'jr'),
    exp(-0.03 * 2.0) * greatest(110.0 - 100.0 * exp((0.03 - 0.02) * 2.0), 0.0), 1e-12),
  assert_near('binomial zero vol american call reaches deterministic maturity value',
    fin_binomial_price('call', 100.0, 90.0, 1.0, 0.05, 0.0, 0.0, 20, 'american', 'crr'),
    exp(-0.05) * greatest(100.0 * exp(0.05) - 90.0, 0.0), 1e-12),
  assert_near('binomial zero vol american put can exercise immediately',
    fin_binomial_price('put', 90.0, 100.0, 1.0, 0.05, 0.0, 0.0, 20, 'american', 'crr'), 10.0, 1e-12),
  assert_near('digital price', fin_digital_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 0.5323248154537634, 1e-10),
  assert_near('asset or nothing price', fin_asset_or_nothing_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 63.68306511756191, 1e-10),
  assert_not_null('asian geometric price', fin_asian_geometric_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)),
  assert_near('barrier out knocked out', fin_barrier_price('call', 'up-out', 100.0, 100.0, 100.0, 1.0, 0.05, 0.2), 0.0, 1e-12),
  assert_near('barrier Haug down-out call with rebate', fin_barrier_price('call', 'down-out', 100.0, 90.0, 95.0, 3.0, 0.5, 0.08, 0.25, 0.04), 9.0246, 1e-4),
  assert_near('barrier Haug up-in put with rebate', fin_barrier_price('put', 'up-in', 100.0, 100.0, 105.0, 3.0, 0.5, 0.08, 0.25, 0.04), 3.3721, 1e-4),
  assert_near('barrier in-out parity',
    fin_barrier_price('call', 'down-in', 100.0, 100.0, 90.0, 1.0, 0.05, 0.2) +
    fin_barrier_price('call', 'down-out', 100.0, 100.0, 90.0, 1.0, 0.05, 0.2),
    fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 1e-10),
  assert_eq('bsm iv rejects impossible price', fin_bsm_implied_vol('call', 200.0, 100.0, 100.0, 1.0, 0.05), NULL),
  assert_eq('black76 iv rejects impossible price', fin_black76_implied_vol('call', 200.0, 100.0, 100.0, 1.0, 0.05), NULL),
  assert_eq('black76 greeks reject zero expiry', fin_black76_greeks('call', 100.0, 100.0, 0.0, 0.05, 0.2), NULL),
  assert_eq('bachelier greeks reject zero volatility', fin_bachelier_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.0), NULL),
  assert_not_null('sabr vol', fin_sabr_vol(100.0, 100.0, 1.0, 0.2, 0.5, -0.2, 0.4)),
  assert_near('sabr zero vol-of-vol limit',
    fin_sabr_vol(100.0, 90.0, 1.25, 0.2, 0.5, -0.2, 0.0),
    0.020531540432521474, 1e-14),
  assert_near('sabr near-zero vol-of-vol continuity',
    fin_sabr_vol(100.0, 90.0, 1.25, 0.2, 0.5, -0.2, 1e-12),
    fin_sabr_vol(100.0, 90.0, 1.25, 0.2, 0.5, -0.2, 0.0), 1e-12),
  assert_not_null('svi total variance', fin_svi_total_variance(0.0, 0.02, 0.1, -0.3, 0.0, 0.2)),
  assert_not_null('svi vol', fin_svi_vol(0.0, 1.0, 0.02, 0.1, -0.3, 0.0, 0.2)),
  assert_near('black76 iv roundtrip', fin_black76_implied_vol('call', fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05, 0.3, 1e-8), 0.2, 1e-8),
  assert_near('bachelier iv roundtrip', fin_bachelier_implied_vol('call', fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0), 100.0, 100.0, 1.0, 0.05, 4.0, 1e-8), 5.0, 1e-7);

-- 0.3.0 scalar contract: tails, units, conventions and calendars against independent references
-- (scipy, QuantLib, numpy and exchange_calendars XNYS).
SELECT
  assert_near('t cdf deep tail', fin_student_t_cdf(-40, 3) / 1.7190340394579253e-05, 1.0, 1e-10),
  assert_near('t inv deep tail', fin_student_t_inv(1e-10, 5), -156.8255927088943, 1e-8),
  assert_near('chi2 cdf deep tail', fin_chi2_cdf(1e-4, 10) / 2.604058162047335e-24, 1.0, 1e-10),
  assert_near('chi2 inv deep tail', fin_chi2_inv(1e-10, 5), 0.0003233557146249697, 1e-15),
  assert_near('norm inv deep tail', fin_norm_inv(1e-300), -37.0470962993612, 1e-10),
  assert_eq('clip inverted bounds', fin_clip(1.0, 2.0, 0.0), NULL);

SELECT
  assert_near('vega raw', fin_bsm_vega('call', 100, 95, 1, 0.05, 0.2, 0.02), 34.397280608802596, 1e-9),
  assert_near('vega market', fin_bsm_vega('call', 100, 95, 1, 0.05, 0.2, 0.02, 'market'), 0.34397280608802596, 1e-11),
  assert_near('rho raw put', fin_bsm_rho('put', 100, 95, 1, 0.05, 0.2, 0.02), -34.305472264900565, 1e-9),
  assert_near('rho market is per 1pct', fin_bsm_rho('call', 100, 95, 1, 0.05, 0.2, 0.02, 'market'), 0.5606132306266723, 1e-11),
  assert_near('theta year', fin_bsm_theta('call', 100, 95, 1, 0.05, 0.2, 0.02), -4.882797197108126, 1e-9),
  assert_near('theta day', fin_bsm_theta('put', 100, 95, 1, 0.05, 0.2, 0.02, 'day'), -0.006369465143406135, 1e-12),
  assert_near('charm calendar decay', fin_bsm_charm('call', 100, 95, 1, 0.05, 0.2, 0.02), 0.014712115644632817, 1e-8),
  assert_near('color calendar decay', fin_bsm_color('put', 100, 95, 1, 0.05, 0.2, 0.02), 0.008915129790631332, 1e-8),
  assert_near('touch up reflection', fin_bsm_prob_touch('call', 100, 110, 0.5, 0.05, 0.25, 0.01), 0.5976395361093655, 1e-12),
  assert_near('touch down reflection', fin_bsm_prob_touch('put', 100, 90, 0.5, 0.05, 0.25, 0.01), 0.5430377590342794, 1e-12),
  assert_eq('touch already crossed', fin_bsm_prob_touch('call', 120, 110, 0.5, 0.05, 0.25), 1.0);

SELECT
  assert_near('iv spec overload', fin_bsm_implied_vol(fin_option_spec('call', 100, 100, 1, 0.05, 0.2), 14.231254785985843), 0.3, 1e-10),
  assert_near('theta spec overload', fin_bsm_theta(spec, 'day'), fin_bsm_theta('call', 100, 95, 1, 0.05, 0.2, 0.02, 'day'), 1e-15),
  assert_near('rho spec overload', fin_bsm_rho(spec), fin_bsm_rho('call', 100, 95, 1, 0.05, 0.2, 0.02), 1e-12),
  assert_near('vanna spec overload', fin_bsm_vanna(spec), fin_bsm_vanna('call', 100, 95, 1, 0.05, 0.2, 0.02), 1e-15),
  assert_near('digital spec payout', fin_digital_price(spec, 10.0), 10 * fin_digital_price('call', 100, 95, 1, 0.05, 0.2, 0.02), 1e-12),
  assert_eq('digital at expiry', fin_digital_price('call', 105, 100, 0, 0.05, 0.2), 1.0),
  assert_eq('prob itm at expiry', fin_bsm_prob_itm('put', 105, 100, 0, 0.05, 0.2), 0.0),
  assert_eq('asset or nothing at expiry', fin_asset_or_nothing_price('call', 105, 100, 0, 0.05, 0.2), 105.0),
  assert_true('validate spec rejects nan', NOT fin_validate_option_spec(fin_option_spec('call', 'NaN'::DOUBLE, 100, 1, 0.05, 0.2)).ok),
  assert_eq('validate spec null', fin_validate_option_spec(NULL).reason, 'missing option spec'),
  assert_eq('spec model normalized', fin_option_spec('call', 100, 100, 1, 0.05, 0.2, model := 'Black76').model, 'black76')
FROM (SELECT fin_option_spec('call', 100, 95, 1, 0.05, 0.2, 0.02) AS spec);

SELECT
  assert_near('30U/360 february end', fin_yearfrac(DATE '2026-02-28', DATE '2026-08-31', '30U/360'), 0.5, 1e-15),
  assert_near('30/360 bond basis', fin_yearfrac(DATE '2026-02-28', DATE '2026-08-31', '30/360'), 0.5083333333333333, 1e-15),
  assert_near('30E/360', fin_yearfrac(DATE '2026-02-28', DATE '2026-08-31', '30E/360'), 0.5055555555555555, 1e-15),
  assert_near('act/act isda', fin_yearfrac(DATE '2025-10-15', DATE '2026-03-15', 'ACT/ACT ISDA'), 0.4136986301369863, 1e-15),
  assert_eq('parse 30U/360', fin_parse_day_count('30U/360'), '30U/360'),
  assert_near('yearfrac timestamp inputs', fin_yearfrac(TIMESTAMP '2026-01-01 09:00', TIMESTAMP '2026-07-01 17:00', 'ACT/360'), 181.0 / 360, 1e-15),
  assert_near('yearfrac string literals', fin_yearfrac('2026-01-01', '2026-07-01', 'ACT/360'), 181.0 / 360, 1e-15),
  assert_near('accrued act/act icma', fin_accrued_interest(DATE '2026-03-01', DATE '2026-01-15', DATE '2026-07-15', 0.05, 100, 'ACT/ACT ICMA'), 0.6215469613259669, 1e-12),
  assert_eq('accrued settle before coupon', fin_accrued_interest(DATE '2026-01-01', DATE '2026-01-15', DATE '2026-07-15', 0.05), NULL),
  assert_near('npv times default periodic', fin_npv([-100.0, 110.0], [0.0, 1.0], 0.1), 0.0, 1e-12),
  assert_near('bond ytm round trip', fin_bond_ytm(fin_bond_price(0.05, 0.0712345, 30, 2), 0.05, 30, 2), 0.0712345, 1e-12),
  assert_eq('swap rate unsorted maturities', fin_swap_rate([2.0, 1.0], [0.95, 0.97]), NULL),
  assert_eq('swap rate non-positive discount', fin_swap_rate([1.0, 2.0], [0.97, 0.0]), NULL),
  assert_eq('curve discount negative time', fin_curve_discount_factor([1.0, 2.0], [0.03, 0.04], -0.5), NULL),
  assert_near('xirr timestamp dates', fin_xirr([-100.0, 110.0], [TIMESTAMP '2026-01-01 12:00', TIMESTAMP '2027-01-01 08:00']), 0.1, 1e-10);

SELECT
  assert_eq('matrix mul', fin_matrix_mul([[1.0, 2, 3], [4.0, 5, 6]], [[7.0, 8], [9.0, 10], [11.0, 12]]), [[58.0, 64.0], [139.0, 154.0]]),
  assert_true('is psd relative tolerance', fin_matrix_is_psd([[1e10, 0.0], [0.0, 1e-3]])),
  assert_true('is psd rejects indefinite', NOT fin_matrix_is_psd([[1.0, 2.0], [2.0, 1.0]])),
  assert_true('nearest psd clip', list_max(list_transform(list_zip(flatten(fin_nearest_psd([[1.0, 0.9, -0.9], [0.9, 1.0, 0.9], [-0.9, 0.9, 1.0]], 'clip')),
    [1.2666666666666664, 0.6333333333333335, -0.6333333333333333, 0.6333333333333334, 1.2666666666666673, 0.6333333333333331, -0.6333333333333333, 0.6333333333333331, 1.266666666666666]),
    lambda p: abs(p[1] - p[2]))) < 1e-12),
  assert_true('nearest psd default is clip', fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]]) = fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]], 'clip')),
  assert_true('nearest correlation higham', list_max(list_transform(list_zip(flatten(fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]], 'higham')), [1.0, 1.0, 1.0, 1.0]), lambda p: abs(p[1] - p[2]))) < 1e-8),
  assert_eq('portfolio variance empty', fin_portfolio_variance([]::DOUBLE[], []::DOUBLE[][]), NULL),
  assert_true('validate return total loss', fin_validate_return(-1.0)),
  assert_true('validate ohlc non-positive', NOT fin_validate_ohlc(0.0, 1.0, 0.0, 0.5).ok);

SELECT
  assert_eq('nyse 2026 sessions', fin_business_days_between(DATE '2026-01-01', DATE '2027-01-01', 'NYSE'), 251),
  assert_eq('weekday 2026 days', fin_business_days_between(DATE '2026-01-01', DATE '2027-01-01'), 261),
  assert_true('nyse good friday', NOT fin_is_business_day(DATE '2026-04-03', 'NYSE')),
  assert_true('nyse juneteenth', NOT fin_is_business_day(DATE '2026-06-19', 'NYSE')),
  assert_true('nyse observed independence day', NOT fin_is_business_day(DATE '2026-07-03', 'NYSE')),
  assert_eq('nyse next business day over christmas', fin_next_business_day(DATE '2026-12-24', 'NYSE'), DATE '2026-12-28'),
  assert_eq('next business day bigint offset', fin_next_business_day(TIMESTAMP '2026-12-24 10:00', 2::BIGINT), DATE '2026-12-28'),
  assert_eq('prev business day nyse offset', fin_prev_business_day(DATE '2026-01-05', 'NYSE', 2), DATE '2025-12-31'),
  assert_true('nyse dst open utc', fin_is_regular_session(TIMESTAMPTZ '2026-03-09 13:30:00+00', 'NYSE')),
  assert_true('nyse pre dst open utc', NOT fin_is_regular_session(TIMESTAMPTZ '2026-03-06 13:30:00+00', 'NYSE')),
  assert_true('nyse close exclusive', NOT fin_is_regular_session(TIMESTAMP '2026-07-06 16:00:00', 'NYSE')),
  assert_true('nyse early close', NOT fin_is_regular_session(TIMESTAMP '2026-11-27 13:00:00', 'NYSE')),
  assert_true('nyse before early close', fin_is_regular_session(TIMESTAMP '2026-11-27 12:59:00', 'NYSE')),
  assert_true('session wall clock in utc', fin_is_regular_session(TIMESTAMP '2026-07-06 14:00:00', 'NYSE', 'UTC')),
  assert_eq('session date of utc instant', fin_session_date(TIMESTAMPTZ '2026-07-07 02:00:00+00', 'NYSE'), DATE '2026-07-06');

-- Price transforms and microstructure scalars.
SELECT
  assert_near('avg price', fin_avg_price(open, high, low, close), 100.0, 1e-12),
  assert_near('typ price', fin_typ_price(high, low, close), 100.0, 1e-12),
  assert_near('median price', fin_median_price(high, low), 100.0, 1e-12),
  assert_near('weighted close', fin_weighted_close(high, low, close), 100.0, 1e-12),
  assert_near('mid', fin_mid(bid, ask), 100.0, 1e-12),
  assert_near('spread', fin_spread(bid, ask), 0.2, 1e-12),
  assert_near('spread bps', fin_spread_bps(bid, ask), 20.0, 1e-10),
  assert_near('microprice', fin_microprice(bid, bid_size, ask, ask_size), 99.99090909090908, 1e-12),
  assert_near('order imbalance', fin_order_imbalance(bid_size, ask_size), -0.09090909090909091, 1e-12),
  assert_near('queue imbalance', fin_queue_imbalance(bid_size, ask_size), -0.09090909090909091, 1e-12),
  assert_near('trade sign ask hit', fin_trade_sign(102.0::DOUBLE, 100.0::DOUBLE, 101.0::DOUBLE), 1.0, 1e-12)
FROM gold_prices
WHERE seq = 1;

-- Price transforms and BOP against TA-Lib on gold_vbars.
SELECT
  assert_near('avg price TA-Lib', max(fin_avg_price(open, high, low, close)) FILTER (WHERE i = 5), 98.44875000000002, 1e-12),
  assert_near('typ price TA-Lib', max(fin_typ_price(high, low, close)) FILTER (WHERE i = 5), 98.44333333333334, 1e-12),
  assert_near('median price TA-Lib', max(fin_median_price(high, low)) FILTER (WHERE i = 5), 98.465, 1e-12),
  assert_near('weighted close TA-Lib', max(fin_weighted_close(high, low, close)) FILTER (WHERE i = 5), 98.4325, 1e-12),
  assert_near('bop TA-Lib row 0', max(fin_bop(open, high, low, close)) FILTER (WHERE i = 0), 0.5714285714285671, 1e-12),
  assert_near('bop TA-Lib row 59', max(fin_bop(open, high, low, close)) FILTER (WHERE i = 59), 0.14382022471909317, 1e-12)
FROM gold_vbars;

-- Microstructure domain rules: crossed books, negative or empty sizes -> NULL.
SELECT
  assert_eq('mid crossed quotes', fin_mid(101.0, 100.0), NULL),
  assert_near('mid locked quotes', fin_mid(100.0, 100.0), 100.0, 1e-12),
  assert_eq('spread crossed quotes', fin_spread(101.0, 100.0), NULL),
  assert_eq('spread bps non-positive mid', fin_spread_bps(-1.0, 0.5), NULL),
  assert_eq('microprice crossed quotes', fin_microprice(101.0, 5.0, 100.0, 5.0), NULL),
  assert_eq('microprice empty book', fin_microprice(99.0, 0.0, 100.0, 0.0), NULL),
  assert_eq('order imbalance negative size', fin_order_imbalance(-5.0, 3.0), NULL),
  assert_eq('queue imbalance empty book', fin_queue_imbalance(0.0, 0.0), NULL),
  assert_near('order imbalance one-sided', fin_order_imbalance(5.0, 0.0), 1.0, 1e-12),
  assert_eq('mid NULL input', fin_mid(NULL, 100.0), NULL),
  assert_eq('typ price NaN input', fin_typ_price('NaN'::DOUBLE, 1.0, 1.0), NULL),
  assert_near('bop flat bar is 0 (TA-Lib)', fin_bop(2.0, 2.0, 2.0, 2.0), 0.0, 1e-12),
  assert_eq('price transforms return DOUBLE', typeof(fin_mid(1, 2)), 'DOUBLE');

-- Trade signs: Lee-Ready (default) uses the quote midpoint, then the tick test
-- at the midpoint; EMO uses the touch, then the tick test.
SELECT
  assert_near('lee-ready above mid', fin_trade_sign(100.06, 100.0, 100.1), 1.0, 1e-12),
  assert_near('lee-ready below mid', fin_trade_sign(100.04, 100.0, 100.1), -1.0, 1e-12),
  assert_near('lee-ready at mid without previous price', fin_trade_sign(100.05, 100.0, 100.1), 0.0, 1e-12),
  assert_near('lee-ready at mid, NULL previous price', fin_trade_sign(100.05, 100.0, 100.1, NULL), 0.0, 1e-12),
  assert_near('lee-ready at mid, uptick', fin_trade_sign(100.05, 100.0, 100.1, 100.0), 1.0, 1e-12),
  assert_near('lee-ready at mid, downtick', fin_trade_sign(100.05, 100.0, 100.1, 100.08), -1.0, 1e-12),
  assert_near('lee-ready ignores previous price off the mid', fin_trade_sign(100.06, 100.0, 100.1, 100.09), 1.0, 1e-12),
  assert_near('quote rule NULL previous price still classifies', fin_trade_sign(102.0, 100.0, 101.0, NULL), 1.0, 1e-12),
  assert_near('explicit lee_ready method', fin_trade_sign(100.06, 100.0, 100.1, NULL, 'lee_ready'), 1.0, 1e-12),
  assert_near('emo at the ask', fin_trade_sign(100.1, 100.0, 100.1, NULL, 'emo'), 1.0, 1e-12),
  assert_near('emo at the bid', fin_trade_sign(100.0, 100.0, 100.1, NULL, 'emo'), -1.0, 1e-12),
  assert_near('emo inside uses tick test', fin_trade_sign(100.06, 100.0, 100.1, 100.08, 'emo'), -1.0, 1e-12),
  assert_near('emo inside without previous price', fin_trade_sign(100.06, 100.0, 100.1, NULL, 'emo'), 0.0, 1e-12),
  assert_eq('trade sign crossed quotes', fin_trade_sign(100.0, 101.0, 100.0), NULL),
  assert_eq('trade sign NaN price', fin_trade_sign('NaN'::DOUBLE, 100.0, 101.0), NULL),
  assert_eq('trade sign NULL quote', fin_trade_sign(100.0, NULL, 101.0, 99.0), NULL);

-- Bar builders take an explicit ordering key; ts ties pick the smaller open and
-- the larger close, and every field uses the same non-NULL rows.
SELECT
  assert_near('ohlc open by ts', (fin_ohlc(price, ts)).open, 10.0, 1e-12),
  assert_near('ohlc close by ts', (fin_ohlc(price, ts)).close, 11.0, 1e-12),
  assert_near('ohlc high', (fin_ohlc(price, ts)).high, 12.0, 1e-12),
  assert_near('ohlcv volume', (fin_ohlcv(price, volume, ts)).volume, 80.0, 1e-12),
  assert_near('ohlcv vwap', (fin_ohlcv(price, volume, ts)).vwap, (10.0 * 10 + 12.0 * 20 + 11.0 * 5 + 11.5 * 40 + 11.0 * 5) / 80, 1e-12)
FROM gold_ticks WHERE sym = 'X';

SELECT
  assert_near('ohlc tie open picks the smaller price', (fin_ohlc(price, ts)).open, 11.0, 1e-12),
  assert_near('ohlc tie close picks the larger price', (fin_ohlc(price, ts)).close, 12.0, 1e-12)
FROM gold_ticks WHERE sym = 'X' AND seq IN (2, 3);

SELECT
  assert_near('ohlcv skips rows with NULL volume for every field', (fin_ohlcv(p, v, t)).high, 2.0, 1e-12),
  assert_near('ohlcv NULL-volume row is not the close', (fin_ohlcv(p, v, t)).close, 2.0, 1e-12),
  assert_near('ohlcv volume', (fin_ohlcv(p, v, t)).volume, 3.0, 1e-12),
  assert_near('ohlc keeps rows with NULL volume', (fin_ohlc(p, t)).high, 9.0, 1e-12)
FROM (VALUES (1.0, 1.0, 1), (2.0, 2.0, 2), (9.0, NULL, 3), (NULL, 5.0, 4)) t(p, v, t);

-- Vector, matrix, and portfolio helpers.
SELECT
  assert_near('dot', fin_dot([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]), 32.0, 1e-12),
  assert_near('vector sum', fin_vector_sum([1.0, 2.0, 3.0]), 6.0, 1e-12),
  assert_near('vector mean', fin_vector_mean([1.0, 2.0, 3.0]), 2.0, 1e-12),
  assert_eq('vector scale', fin_vector_scale([1.0, 2.0], 2.0), [2.0, 4.0]),
  assert_eq('vector add', fin_vector_add([1.0, 2.0], [3.0, 4.0]), [4.0, 6.0]),
  assert_eq('vector sub', fin_vector_sub([3.0, 4.0], [1.0, 2.0]), [2.0, 2.0]),
  assert_eq('vector normalize', fin_vector_normalize_sum([2.0, 2.0]), [0.5, 0.5]),
  assert_near('turnover', fin_turnover([0.6, 0.4], [0.5, 0.5]), 0.1, 1e-12),
  assert_eq('equal weights', fin_equal_weights(2), [0.5, 0.5]),
  assert_eq('inverse vol weights', fin_inverse_vol_weights([0.2, 0.4]), [0.6666666666666666, 0.3333333333333333]),
  assert_eq('matrix shape rows', (fin_matrix_shape([[1.0, 2.0], [3.0, 4.0]])).rows, 2::BIGINT),
  assert_eq('matrix transpose', fin_matrix_transpose([[1.0, 2.0], [3.0, 4.0]]), [[1.0, 3.0], [2.0, 4.0]]),
  assert_eq('matrix vecmul', fin_matrix_vecmul([[1.0, 2.0], [3.0, 4.0]], [1.0, 1.0]), [3.0, 7.0]),
  assert_eq('matrix mul', fin_matrix_mul([[1.0, 2.0]], [[3.0], [4.0]]), [[11.0]]),
  assert_eq('matrix cholesky', fin_matrix_cholesky([[4.0, 2.0], [2.0, 3.0]]), [[2.0, 0.0], [1.0, 1.4142135623730951]]),
  assert_eq('matrix cholesky rejects nonsymmetric input', fin_matrix_cholesky([[1.0, 99.0], [0.0, 1.0]]), NULL),
  assert_eq('matrix cholesky rejects indefinite zero pivot', fin_matrix_cholesky([[0.0, 0.1], [0.1, 0.1]]), NULL),
  assert_not_null('matrix cholesky accepts small positive pivot', fin_matrix_cholesky([[1e-26, 2e-12], [2e-12, 400.0]])),
  assert_true('matrix psd', fin_matrix_is_psd([[1.0, 0.2], [0.2, 1.0]])),
  assert_eq('matrix psd rejects indefinite zero pivot', fin_matrix_is_psd([[0.0, 0.1], [0.1, 0.1]]), false),
  assert_true('matrix psd accepts singular matrix', fin_matrix_is_psd([[0.0, 0.0], [0.0, 1.0]])),
  assert_true('nearest psd', fin_matrix_is_psd(fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]]))),
  assert_near('portfolio return', fin_portfolio_return([0.5, 0.5], [0.1, 0.2]), 0.15, 1e-12),
  assert_near('portfolio expected return', fin_portfolio_expected_return([0.5, 0.5], [0.1, 0.2]), 0.15, 1e-12),
  assert_near('portfolio variance', fin_portfolio_variance([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]]), 0.0375, 1e-12),
  assert_eq('portfolio variance rejects negative result', fin_portfolio_variance([1.0], [[-1.0]]), NULL),
  assert_near('portfolio vol', fin_portfolio_vol([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]]), 0.19364916731037085, 1e-12),
  assert_eq('portfolio vol rejects negative variance', fin_portfolio_vol([1.0], [[-1.0]]), NULL),
  assert_near('portfolio sharpe', fin_portfolio_sharpe([0.5, 0.5], [0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 0.02), 0.671317, 1e-6);

SELECT
  assert_near('marginal risk first', fin_marginal_risk([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]])[1], 0.025, 1e-12),
  assert_near('marginal risk second', fin_marginal_risk([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]])[2], 0.05, 1e-12),
  assert_not_null('component risk', fin_component_risk([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]])),
  assert_not_null('risk contribution', fin_risk_contribution([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]])),
  assert_near('two asset min variance', fin_min_variance_weights([[0.04, 0.01], [0.01, 0.09]])[1], 0.8 / 1.1, 1e-12),
  assert_near('two asset risk parity', fin_risk_parity_weights([[0.04, 0.0], [0.0, 0.09]])[1], 0.6, 1e-9),
  assert_near('two asset max sharpe', fin_max_sharpe_weights([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]])[1], 0.5, 1e-12),
  assert_near('black litterman single view', fin_black_litterman_returns([0.6, 0.4], [[0.04, 0.01], [0.01, 0.09]], [[1.0, 0.0]], [0.1])[1],
              0.085, 1e-12);

-- Portfolio construction against closed forms / KKT-verified numpy solutions
-- (see docs: long-only solves use an exact active-set QP). S is a 4-asset
-- covariance whose unconstrained minimum-variance and maximum-Sharpe
-- portfolios short asset 2.
WITH inputs AS (
  SELECT [[0.04, 0.006, 0.012, 0.0], [0.006, 0.09, 0.018, 0.009], [0.012, 0.018, 0.0625, -0.005], [0.0, 0.009, -0.005, 0.01]] AS s,
         [0.08, 0.03, 0.10, 0.025] AS mu
), w AS (
  SELECT s, mu,
    fin_min_variance_weights(s, false) AS mv_free, fin_min_variance_weights(s) AS mv_long,
    fin_max_sharpe_weights(mu, s, 0.02, false) AS ms_free, fin_max_sharpe_weights(mu, s, 0.02) AS ms_long,
    fin_risk_parity_weights(s, [0.4, 0.3, 0.2, 0.1]) AS rp_budget, fin_risk_parity_weights(s) AS rp_equal,
    fin_black_litterman_returns([0.3, 0.3, 0.2, 0.2], s, [[1, -1, 0, 0], [0, 0, 1, 0.0]], [0.02, 0.09]) AS bl,
    fin_black_litterman_returns([0.3, 0.3, 0.2, 0.2], s, [[1, -1, 0, 0], [0, 0, 1, 0.0]], [0.02, 0.09], 0.05, [[0.001, 0], [0, 0.002]]) AS bl_omega
  FROM inputs
)
SELECT
  assert_true('min variance unconstrained', list_reduce(list_transform(list_zip(mv_free, [0.12277312854459042, -0.04343908457547364, 0.15427470980736274, 0.7663912462235204]), p -> abs(p[1] - p[2]) < 1e-12), (a, b) -> a AND b)),
  assert_true('min variance long only', list_reduce(list_transform(list_zip(mv_long, [0.12367491166077739, 0.0, 0.14134275618374556, 0.734982332155477]), p -> abs(p[1] - p[2]) < 1e-12), (a, b) -> a AND b)),
  assert_near('max sharpe unconstrained shorts asset 2', ms_free[2], -0.10416449, 1e-8),
  assert_true('max sharpe long only', list_reduce(list_transform(list_zip(ms_long, [0.3430599369085173, 0.0, 0.3391167192429022, 0.31782334384858046]), p -> abs(p[1] - p[2]) < 1e-12), (a, b) -> a AND b)),
  assert_true('max sharpe beats equal weight', fin_portfolio_sharpe(ms_long, mu, s, 0.02) > fin_portfolio_sharpe([0.25, 0.25, 0.25, 0.25], mu, s, 0.02)),
  assert_true('risk parity hits budgets', list_reduce(list_transform(list_zip(fin_risk_contribution(rp_budget, s), [0.4, 0.3, 0.2, 0.1]), p -> abs(p[1] - p[2]) < 1e-8), (a, b) -> a AND b)),
  assert_true('risk parity reference', list_reduce(list_transform(list_zip(rp_equal, [0.21355818119019918, 0.12264755883586934, 0.17976156921275435, 0.4840326907611773]), p -> abs(p[1] - p[2]) < 1e-7), (a, b) -> a AND b)),
  assert_true('black litterman default omega', list_reduce(list_transform(list_zip(bl, [0.054027525115395054, 0.0674983708932935, 0.06977404629378224, 0.005079062584849304]), p -> abs(p[1] - p[2]) < 1e-12), (a, b) -> a AND b)),
  assert_true('black litterman explicit omega', list_reduce(list_transform(list_zip(bl_omega, [0.06199549932667091, 0.05176940250903677, 0.07373378694450353, 0.0028184669359982957]), p -> abs(p[1] - p[2]) < 1e-12), (a, b) -> a AND b)),
  assert_eq('min variance non-PD covariance is NULL', fin_min_variance_weights([[1.0, 2.0], [2.0, 1.0]]), NULL),
  assert_eq('max sharpe needs positive excess return long only', fin_max_sharpe_weights([0.01, 0.0], [[0.04, 0.0], [0.0, 0.09]], 0.02), NULL),
  assert_eq('risk parity budget length mismatch is NULL', fin_risk_parity_weights(s, [0.5, 0.5]), NULL),
  assert_eq('risk parity non-convergence is NULL', fin_risk_parity_weights(s, NULL, 1e-12, 1), NULL),
  assert_eq('black litterman view shape mismatch is NULL', fin_black_litterman_returns([0.5, 0.5], [[0.04, 0.0], [0.0, 0.09]], [[1.0, 0.0, 0.0]], [0.1]), NULL)
FROM w;

SELECT
  assert_near('ols single factor beta', (fin_ols(r, [benchmark_r])).beta[1], 1.6964285714285716, 1e-12),
  assert_near('ols single factor intercept', (fin_ols(r, [benchmark_r])).intercept, -0.005535714285714281, 1e-12),
  assert_near('ols single factor r2', (fin_ols(r, [benchmark_r])).r2, 0.9647716229348883, 1e-12),
  assert_near('ols single factor stderr', (fin_ols(r, [benchmark_r])).stderr[1], 0.18715826412901804, 1e-12),
  assert_near('ols intercept stderr', (fin_ols(r, [benchmark_r])).intercept_stderr, 0.002252129137603524, 1e-12),
  assert_eq('ols nobs', (fin_ols(r, [benchmark_r])).nobs, 5::BIGINT),
  assert_near('rolling beta grouped equals beta', fin_rolling_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_near('factor alpha', fin_factor_alpha(r, benchmark_r), fin_alpha(r, benchmark_r), 1e-15),
  assert_near('factor ic spearman', fin_factor_ic(factor, forward_return), 0.1, 1e-12),
  assert_near('factor ic pearson', fin_factor_ic(factor, forward_return, 'pearson'), 0.12873121026029494, 1e-12),
  assert_near('factor ic kendall', fin_factor_ic(factor, forward_return, 'kendall'), 0.0, 1e-12),
  assert_near('rank ic', fin_rank_ic(factor, forward_return), 0.1, 1e-12)
FROM gold_returns;

-- Regression, matrix and ordered diagnostics on gold_stats. References:
-- statsmodels 0.15 OLS (bse, uncentered R^2 without a constant), HAC with
-- maxlags 3 and use_correction=False, adfuller(autolag=None), acorr_ljungbox,
-- pandas autocorr/corr(shift), DataFrame.cov/corr (pairwise complete), the
-- alphalens rank autocorrelation, and a numpy R/S Hurst implementation.
SELECT
  assert_near('ols two factor beta 1', (fin_ols(oy, [f1, f2])).beta[1], 1.2019142848429625, 1e-12),
  assert_near('ols two factor beta 2', (fin_ols(oy, [f1, f2])).beta[2], -0.704929823348132, 1e-12),
  assert_near('ols two factor intercept', (fin_ols(oy, [f1, f2])).intercept, 0.5013749754795397, 1e-12),
  assert_near('ols two factor r2', (fin_ols(oy, [f1, f2])).r2, 0.9583237680170038, 1e-12),
  assert_near('ols two factor stderr 2', (fin_ols(oy, [f1, f2])).stderr[2], 0.037875113018565054, 1e-12),
  assert_near('ols two factor intercept stderr', (fin_ols(oy, [f1, f2])).intercept_stderr, 0.026894285705937666, 1e-12),
  assert_near('ols no intercept beta 1', (fin_ols_no_intercept(oy, [f1, f2])).beta[1], 1.2206889185338872, 1e-12),
  assert_near('ols no intercept uncentered r2', (fin_ols_no_intercept(oy, [f1, f2])).r2, 0.7741168572435024, 1e-12),
  assert_near('ols no intercept stderr 2', (fin_ols_no_intercept(oy, [f1, f2])).stderr[2], 0.09710677139336973, 1e-12),
  assert_eq('ols no intercept has no intercept stderr', (fin_ols_no_intercept(oy, [f1, f2])).intercept_stderr, NULL),
  assert_eq('ols collinear design is NULL', fin_ols(oy, [f1, 2 * f1]), NULL),
  assert_near('newey west tstat', fin_newey_west_tstat(y, x, i, 3), 3.132567893408392, 1e-10),
  assert_near('autocorr lag 1', fin_autocorr(x, i), -0.11833985791502655, 1e-12),
  assert_near('autocorr lag 2', fin_autocorr(x, i, 2), -0.7844807623772095, 1e-12),
  assert_near('crosscorr lag 1', fin_crosscorr(x, y, i, 1), -0.07694083267100597, 1e-12),
  assert_near('crosscorr lag 0 is pearson', fin_crosscorr(x, y, i), 0.4350683747600051, 1e-12),
  assert_near('hurst rescaled range', fin_hurst(x, i), 0.29204213557909403, 1e-12),
  assert_near('half life ar1', fin_half_life_mean_reversion(ar, i), 1.7302267683904657, 1e-10),
  assert_near('adf constant stat', (fin_adf(ar, i)).stat, -3.092598291133777, 1e-10),
  assert_near('adf constant pvalue', (fin_adf(ar, i)).pvalue, 0.02710581929864506, 1e-10),
  assert_eq('adf nobs', (fin_adf(ar, i)).nobs, 62.0::DOUBLE),
  assert_near('adf trend stat', (fin_adf(ar, i, 0, 'ct')).stat, -3.7708138093687005, 1e-10),
  assert_near('adf trend pvalue', (fin_adf(ar, i, 0, 'ct')).pvalue, 0.0180974415334357, 1e-10),
  assert_near('adf no constant stat', (fin_adf(ar, i, max_lag := 2, regression := 'n')).stat, -2.212652001840801, 1e-10),
  assert_near('adf no constant pvalue', (fin_adf(ar, i, max_lag := 2, regression := 'n')).pvalue, 0.025867889872054003, 1e-10),
  assert_near('ljung box stat', (fin_ljung_box(x, i, 5)).stat, 80.26708456678584, 1e-9),
  assert_near('ljung box pvalue', (fin_ljung_box(x, i, 5)).pvalue, 7.378660165348503e-16, 1e-20),
  assert_near('factor turnover', fin_factor_turnover(i // 8, i % 8, x), 0.5034013605442176, 1e-12),
  assert_near('factor turnover period 2', fin_factor_turnover(i // 8, 'a' || (i % 8), x, 2), 1.376984126984127, 1e-12),
  assert_eq('factor turnover duplicate asset is NULL', fin_factor_turnover(i // 8, i % 4, x), NULL),
  assert_near('exp decay sum numeric', fin_exp_decay_sum(x, i, 10.0), 0.9625694363858702, 1e-12),
  assert_near('exp decay avg pandas ewm times', fin_exp_decay_avg(x, TIMESTAMP '2026-01-01' + i * INTERVAL 1 MINUTE, INTERVAL 10 MINUTE), 0.06523285274589181, 1e-12),
  assert_near('exp decay count numeric', fin_exp_decay_count(i::DOUBLE, 10.0), 14.755899763198531, 1e-12),
  assert_near('exp decay max numeric', fin_exp_decay_max(x, i, 10.0), 1.2139238480000343, 1e-12)
FROM gold_stats;

WITH long_returns AS (
  SELECT i, 'x' AS asset, x AS r FROM gold_stats UNION ALL
  SELECT i, 'y', y FROM gold_stats UNION ALL
  SELECT i, 'oy', oy FROM gold_stats WHERE i % 7 <> 0
), m AS (
  SELECT fin_cov_matrix(i, asset, r) AS cov, fin_corr_matrix(i, asset, r) AS corr FROM long_returns
)
SELECT
  assert_eq('cov matrix labels sorted', cov.labels, ['oy', 'x', 'y']),
  assert_near('cov matrix pairwise variance', cov.matrix[1][1], 0.8646536020002162, 1e-12),
  assert_near('cov matrix pairwise covariance', cov.matrix[1][2], -0.02726141315817192, 1e-12),
  assert_near('cov matrix symmetric', cov.matrix[2][3] - cov.matrix[3][2], 0.0, 0),
  assert_near('cov matrix full pair', cov.matrix[2][3], 0.27105568867940405, 1e-12),
  assert_near('corr matrix pairwise', corr.matrix[1][3], -0.0316212523808466, 1e-12),
  assert_near('corr matrix diagonal', corr.matrix[2][2], 1.0, 0),
  assert_near('corr matrix full pair', corr.matrix[3][2], 0.4350683747600051, 1e-12)
FROM m;

SELECT assert_eq('cov matrix duplicate key and asset is NULL', fin_cov_matrix(d, a, r), NULL)
FROM (VALUES (1, 1, 0.1), (1, 1, 0.2), (2, 1, 0.3)) t(d, a, r);

SELECT assert_eq('cov matrix integer labels cast to varchar', fin_cov_matrix(d, a, r).labels, ['10', '2'])
FROM (VALUES (1, 10, 0.1), (1, 2, 0.2), (2, 10, 0.3), (2, 2, 0.1)) t(d, a, r);

-- Window use: rolling beta and z-score over explicit frames equal grouped
-- results over the same rows.
WITH framed AS (
  SELECT i,
    fin_rolling_beta(y, x) OVER (ORDER BY i ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS rb,
    fin_rolling_zscore(x, i) OVER (ORDER BY i ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS rz,
    fin_exp_decay_avg(x, i, 3.0) OVER (ORDER BY i ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS ed
  FROM gold_stats
), grouped AS (
  SELECT f.i, fin_beta(s.y, s.x) AS rb, fin_zscore_last(s.x, s.i) AS rz, fin_exp_decay_avg(s.x, s.i, 3.0) AS ed
  FROM gold_stats f JOIN gold_stats s ON s.i BETWEEN f.i - 9 AND f.i GROUP BY f.i
)
SELECT
  assert_true('rolling beta window equals grouped', bool_and(abs(framed.rb - grouped.rb) < 1e-12 OR (framed.rb IS NULL AND grouped.rb IS NULL))),
  assert_true('rolling zscore window equals grouped', bool_and(abs(framed.rz - grouped.rz) < 1e-12 OR (framed.rz IS NULL AND grouped.rz IS NULL))),
  assert_true('exp decay window equals grouped', bool_and(abs(framed.ed - grouped.ed) < 1e-12))
FROM framed JOIN grouped USING (i);

-- Ordered statistics depend only on the ordering key, never on threads or row order.
CREATE OR REPLACE TEMP TABLE sp_order_input AS
  SELECT i % 50 AS g, i // 50 AS ts, sin(i * 1.3) + 0.5 * sin(0.37 * i * i) AS x, cos(i * 0.7) AS y,
         (i // 50) // 20 AS d, (i // 50) % 20 AS asset
  FROM range(20000) t(i) ORDER BY hash(i);
CREATE OR REPLACE MACRO sp_order_metrics() AS TABLE
  SELECT g, fin_autocorr(x, ts, 2) AS a, fin_crosscorr(x, y, ts, 1) AS b, fin_hurst(x, ts) AS c,
    fin_half_life_mean_reversion(x, ts) AS e, (fin_adf(x, ts, 2, 'ct')).stat AS f, (fin_ljung_box(x, ts, 4)).stat AS h,
    fin_newey_west_tstat(y, x, ts, 2) AS k, fin_rolling_zscore(x, ts) AS l, fin_exp_decay_avg(x, ts, 5.0) AS m,
    fin_rank_corr(x, y, 'kendall') AS n, (fin_ks_test(x, y)).pvalue AS o, fin_mutual_information(x, y) AS p,
    fin_factor_turnover(d, asset, x) AS q, (fin_ols(y, [x, x * x])).beta[2] AS s
  FROM sp_order_input GROUP BY g;
SET threads = 1;
CREATE OR REPLACE TEMP TABLE sp_order_one AS SELECT * FROM sp_order_metrics();
SET threads = 8;
CREATE OR REPLACE TEMP TABLE sp_order_eight AS SELECT * FROM sp_order_metrics();
RESET threads;
SELECT assert_eq('statistics ordered results are thread invariant', count(*), 0::BIGINT)
FROM (SELECT * FROM sp_order_one EXCEPT SELECT * FROM sp_order_eight);
SELECT assert_eq('statistics ordered results are populated', count(*), 50::BIGINT)
FROM sp_order_one WHERE a IS NOT NULL AND c IS NOT NULL AND f IS NOT NULL AND k IS NOT NULL AND q IS NOT NULL AND s IS NOT NULL;

-- Complex invariant and edge-case regressions.
CREATE OR REPLACE TEMP TABLE complex_option_surface(
  case_id VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  vol DOUBLE,
  dividend_yield DOUBLE
);

INSERT INTO complex_option_surface VALUES
  ('ATM_DIVIDEND_INDEX', 100.0, 100.0, 1.25, 0.043, 0.215, 0.012),
  ('OTM_HIGH_CARRY_CALL', 82.5, 95.0, 0.70, 0.061, 0.330, 0.018),
  ('ITM_LOW_VOL_PUT', 140.0, 120.0, 2.10, 0.027, 0.145, 0.022);

WITH priced AS (
  SELECT
    *,
    fin_bsm_all('call', spot, strike, ttm, rate, vol, dividend_yield) AS call_all,
    fin_bsm_all('put', spot, strike, ttm, rate, vol, dividend_yield) AS put_all,
    0.01 AS bump
  FROM complex_option_surface
)
SELECT
  assert_near('complex parity ' || case_id,
    call_all.price - put_all.price - (spot * exp(-dividend_yield * ttm) - strike * exp(-rate * ttm)), 0.0, 1e-9),
  assert_near('complex delta parity ' || case_id,
    call_all.delta - put_all.delta, exp(-dividend_yield * ttm), 1e-10),
  assert_near('complex gamma call put equality ' || case_id, call_all.gamma - put_all.gamma, 0.0, 1e-12),
  assert_near('complex vega call put equality ' || case_id, call_all.vega - put_all.vega, 0.0, 1e-10),
  assert_near('complex call delta finite difference ' || case_id,
    call_all.delta,
    (
      fin_bsm_price('call', spot + bump, strike, ttm, rate, vol, dividend_yield) -
      fin_bsm_price('call', spot - bump, strike, ttm, rate, vol, dividend_yield)
    ) / (2.0 * bump),
    1e-5),
  assert_near('complex call gamma finite difference ' || case_id,
    call_all.gamma,
    (
      fin_bsm_price('call', spot + bump, strike, ttm, rate, vol, dividend_yield) -
      2.0 * call_all.price +
      fin_bsm_price('call', spot - bump, strike, ttm, rate, vol, dividend_yield)
    ) / (bump * bump),
    1e-5),
  assert_near('complex implied vol call roundtrip ' || case_id,
    fin_bsm_implied_vol('call', call_all.price, spot, strike, ttm, rate, dividend_yield, 0.20, 1e-10), vol, 1e-8),
  assert_near('complex implied vol put roundtrip ' || case_id,
    fin_bsm_implied_vol('put', put_all.price, spot, strike, ttm, rate, dividend_yield, 0.20, 1e-10), vol, 1e-8)
FROM priced;

CREATE OR REPLACE TEMP TABLE complex_binomial_cases(
  case_id VARCHAR,
  kind VARCHAR,
  spot DOUBLE,
  strike DOUBLE,
  ttm DOUBLE,
  rate DOUBLE,
  vol DOUBLE,
  dividend_yield DOUBLE
);

INSERT INTO complex_binomial_cases VALUES
  ('EUROPEAN_CALL_CONVERGENCE', 'call', 105.0, 100.0, 1.30, 0.035, 0.240, 0.010),
  ('EUROPEAN_PUT_CONVERGENCE', 'put', 88.0, 95.0, 0.85, 0.052, 0.310, 0.000);

SELECT
  assert_near('binomial convergence to bsm ' || case_id,
    fin_binomial_price(kind, spot, strike, ttm, rate, vol, dividend_yield, 500, 'european', 'crr'),
    fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield),
    0.04)
FROM complex_binomial_cases;

SELECT
  assert_true('american put early exercise premium positive',
    fin_binomial_price('put', 72.0, 100.0, 1.0, 0.085, 0.22, 0.0, 350, 'american', 'crr') >
    fin_binomial_price('put', 72.0, 100.0, 1.0, 0.085, 0.22, 0.0, 350, 'european', 'crr')),
  assert_true('american call no dividend near european',
    abs(
      fin_binomial_price('call', 105.0, 100.0, 1.0, 0.045, 0.20, 0.0, 350, 'american', 'crr') -
      fin_binomial_price('call', 105.0, 100.0, 1.0, 0.045, 0.20, 0.0, 350, 'european', 'crr')
    ) <= 1e-10);

CREATE OR REPLACE TEMP TABLE complex_cashflow_cases(
  cashflows DOUBLE[],
  times DOUBLE[],
  rate DOUBLE,
  expected_npv DOUBLE
);

INSERT INTO complex_cashflow_cases VALUES
  ([-1000.0, 120.0, 260.0, 330.0, 520.0], [0.0, 0.15, 0.75, 1.40, 2.25], 0.077,
   97.59088633551092);

SELECT
  assert_near('complex continuous npv irregular times',
    fin_npv(cashflows, times, rate, 'continuous'), expected_npv, 1e-10),
  assert_near('complex continuous npv explicit formula',
    fin_npv(cashflows, times, rate, 'continuous'),
    cashflows[1] * exp(-rate * times[1]) +
    cashflows[2] * exp(-rate * times[2]) +
    cashflows[3] * exp(-rate * times[3]) +
    cashflows[4] * exp(-rate * times[4]) +
    cashflows[5] * exp(-rate * times[5]),
    1e-12)
FROM complex_cashflow_cases;

SELECT
  assert_near('complex xirr multi-date roundtrip',
    fin_xirr(
      [-1000.0, 120.0, 260.0, 330.0, 436.40319676914424],
      [DATE '2026-01-01', DATE '2026-02-15', DATE '2026-07-01', DATE '2027-02-05', DATE '2028-01-01']
    ),
    0.1234,
    1e-8),
  assert_near('complex mirr independent formula',
    fin_mirr([-1000.0, 120.0, 260.0, 330.0, 520.0], 0.055, 0.071),
    pow(
      (
        120.0 * pow(1.071, 3.0) +
        260.0 * pow(1.071, 2.0) +
        330.0 * pow(1.071, 1.0) +
        520.0
      ) / (1000.0),
      0.25
    ) - 1.0,
    1e-12);

CREATE OR REPLACE TEMP TABLE complex_curve_cases(
  target DOUBLE,
  expected_zero DOUBLE,
  expected_df DOUBLE
);

INSERT INTO complex_curve_cases VALUES
  (0.10, 0.0310, 0.996904800038679),
  (0.25, 0.0310, 0.9922799538193509),
  (0.75, 0.0365, 0.9729962994896734),
  (3.50, 0.0480, 0.8453538346846587),
  (7.00, 0.0520, 0.6948911947429106);

SELECT
  assert_near('complex curve interpolation boundary ' || target,
    fin_curve_zero_rate([0.25, 0.5, 1.0, 2.0, 5.0], [0.031, 0.034, 0.039, 0.044, 0.052], target),
    expected_zero,
    1e-12),
  assert_near('complex curve discount boundary ' || target,
    fin_curve_discount_factor([0.25, 0.5, 1.0, 2.0, 5.0], [0.031, 0.034, 0.039, 0.044, 0.052], target),
    expected_df,
    1e-12)
FROM complex_curve_cases;

SELECT
  assert_near('complex swap rate irregular accruals',
    fin_swap_rate([0.25, 0.5, 1.0, 2.0, 3.0], [0.9901, 0.9798, 0.9580, 0.9125, 0.8610]),
    0.05063798395249502,
    1e-12);

SELECT
  assert_near('complex 4 asset portfolio expected return',
    fin_portfolio_expected_return([0.40, -0.10, 0.55, 0.15], [0.08, -0.02, 0.13, 0.04]),
    0.1115,
    1e-12),
  assert_near('complex 4 asset portfolio variance',
    fin_portfolio_variance(
      [0.40, -0.10, 0.55, 0.15],
      [[0.040, 0.006, -0.002, 0.001], [0.006, 0.090, 0.004, -0.003], [-0.002, 0.004, 0.062, 0.008], [0.001, -0.003, 0.008, 0.030]]
    ),
    0.02646,
    1e-12),
  assert_near('complex 4 asset portfolio vol',
    fin_portfolio_vol(
      [0.40, -0.10, 0.55, 0.15],
      [[0.040, 0.006, -0.002, 0.001], [0.006, 0.090, 0.004, -0.003], [-0.002, 0.004, 0.062, 0.008], [0.001, -0.003, 0.008, 0.030]]
    ),
    0.16266530054071152,
    1e-12),
  assert_near('complex 4 asset portfolio sharpe',
    fin_portfolio_sharpe(
      [0.40, -0.10, 0.55, 0.15],
      [0.08, -0.02, 0.13, 0.04],
      [[0.040, 0.006, -0.002, 0.001], [0.006, 0.090, 0.004, -0.003], [-0.002, 0.004, 0.062, 0.008], [0.001, -0.003, 0.008, 0.030]],
      0.015
    ),
    0.5932426871571679,
    1e-12),
  assert_eq('complex dot mismatched length null', fin_dot([1.0, 2.0], [1.0, 2.0, 3.0]), NULL),
  assert_eq('complex portfolio mismatched covariance null',
    fin_portfolio_variance([0.5, 0.5], [[0.04, 0.01]]), NULL);

WITH chol AS (
  SELECT fin_matrix_cholesky([[6.0, 3.0, 4.0], [3.0, 6.0, 5.0], [4.0, 5.0, 10.0]]) AS l
), reconstructed AS (
  SELECT fin_matrix_mul(l, fin_matrix_transpose(l)) AS m
  FROM chol
)
SELECT
  assert_near('complex cholesky reconstruct 11', m[1][1], 6.0, 1e-10),
  assert_near('complex cholesky reconstruct 12', m[1][2], 3.0, 1e-10),
  assert_near('complex cholesky reconstruct 23', m[2][3], 5.0, 1e-10),
  assert_near('complex cholesky reconstruct 33', m[3][3], 10.0, 1e-10)
FROM reconstructed;

CREATE OR REPLACE TEMP TABLE complex_filtered_list_inputs AS
SELECT * FROM (VALUES
  (1, [1.0, 2.0]::DOUBLE[], [3.0, 4.0]::DOUBLE[]),
  (2, [1.0, NULL]::DOUBLE[], [3.0, 4.0]::DOUBLE[]),
  (3, [2.0, 3.0]::DOUBLE[], [4.0, 5.0]::DOUBLE[])
) AS t(id, x, y);

SELECT
  assert_near('filtered list dot ignores unselected null child', sum(fin_dot(x, y)), 34.0, 1e-12),
  assert_near('filtered list sum ignores unselected null child', sum(fin_vector_sum(x)), 8.0, 1e-12)
FROM complex_filtered_list_inputs
WHERE id <> 2;

CREATE OR REPLACE TEMP TABLE complex_filtered_cashflow_inputs AS
SELECT * FROM (VALUES
  (1, [-100.0, 55.0, 60.0]::DOUBLE[], [0.0, 1.0, 2.0]::DOUBLE[]),
  (2, [-100.0, NULL, 60.0]::DOUBLE[], [0.0, 1.0, 2.0]::DOUBLE[]),
  (3, [-200.0, 120.0, 130.0]::DOUBLE[], [0.0, 0.5, 1.5]::DOUBLE[])
) AS t(id, cashflows, times);

SELECT
  assert_near('filtered cashflow npv ignores unselected null child',
    sum(fin_npv(cashflows, times, 0.05, 'continuous')),
    (
      -100.0 + 55.0 * exp(-0.05 * 1.0) + 60.0 * exp(-0.05 * 2.0) +
      -200.0 + 120.0 * exp(-0.05 * 0.5) + 130.0 * exp(-0.05 * 1.5)
    ),
    1e-12)
FROM complex_filtered_cashflow_inputs
WHERE id <> 2;

CREATE OR REPLACE TEMP TABLE complex_filtered_matrix_inputs AS
SELECT * FROM (VALUES
  (1, [[1.0, 0.0], [0.0, 1.0]]::DOUBLE[][], [0.5, 0.5]::DOUBLE[], [0.10, 0.20]::DOUBLE[]),
  (2, [[1.0, NULL], [0.0, 1.0]]::DOUBLE[][], [0.5, 0.5]::DOUBLE[], [0.10, 0.20]::DOUBLE[]),
  (3, [[2.0, 0.1], [0.1, 2.0]]::DOUBLE[][], [0.25, 0.75]::DOUBLE[], [0.03, 0.07]::DOUBLE[])
) AS t(id, m, w, mu);

SELECT
  assert_eq('filtered matrix psd ignores unselected null child', bool_and(fin_matrix_is_psd(m)), true),
  assert_near('filtered portfolio variance ignores unselected null child',
    sum(fin_portfolio_variance(w, m)),
    0.5 + 1.2875,
    1e-12),
  assert_near('filtered portfolio sharpe ignores unselected null child',
    sum(fin_portfolio_sharpe(w, mu, m, 0.01)),
    ((0.15 - 0.01) / sqrt(0.5)) + ((0.06 - 0.01) / sqrt(1.2875)),
    1e-12)
FROM complex_filtered_matrix_inputs
WHERE id <> 2;

-- List result offsets must survive empty/invalid rows between different lengths.
WITH inputs(id, x, m) AS (VALUES
  (1, [1.0, 2.0]::DOUBLE[], [[1.0, 2.0], [3.0, 4.0]]::DOUBLE[][]),
  (2, NULL::DOUBLE[], NULL::DOUBLE[][]),
  (3, []::DOUBLE[], []::DOUBLE[][]),
  (4, [1.0, NULL]::DOUBLE[], [[1.0, NULL]]::DOUBLE[][]),
  (5, [7.0]::DOUBLE[], [[7.0]]::DOUBLE[][])
)
SELECT
  assert_eq('list results retain offsets after empty and null rows',
    list(fin_vector_scale(x, 2.0) ORDER BY id),
    [[2.0, 4.0], NULL, [], NULL, [14.0]]::DOUBLE[][]),
  assert_eq('nested list results retain offsets after empty and null rows',
    list(fin_matrix_transpose(m) ORDER BY id),
    [[[1.0, 3.0], [2.0, 4.0]], NULL, [], NULL, [[7.0]]]::DOUBLE[][][])
FROM inputs;

SELECT
  assert_true('list results retain offsets across chunks',
    bool_and(fin_vector_add([i::DOUBLE], [1.0]) = [i::DOUBLE + 1.0])),
  assert_true('nested list results retain offsets across chunks',
    bool_and(fin_matrix_transpose([[i::DOUBLE, i::DOUBLE + 1.0]]) =
             [[i::DOUBLE], [i::DOUBLE + 1.0]]))
FROM range(5000) AS t(i);

-- Validation, parsers, and calendar helpers.
SELECT
  assert_near('money sum', fin_money_sum(10.25), 10.25, 1e-12),
  assert_near('money weighted sum', fin_money_weighted_sum(10.0, 0.25), 2.5, 1e-12),
  assert_near('money round', fin_money_round(10.255, 2), 10.26, 1e-12),
  assert_near('cents to money', fin_cents_to_money(1234, 2), 12.34, 1e-12),
  assert_eq('money to cents', fin_money_to_cents(12.34), 1234::BIGINT),
  assert_eq('money to cents exact decimal half', fin_money_to_cents(1.005::DOUBLE), 101::BIGINT),
  assert_eq('money to cents negative half', fin_money_to_cents(-1.005), -101::BIGINT),
  assert_eq('money to cents half even', fin_money_to_cents(0.125, 'half_even'), 12::BIGINT),
  assert_eq('money to cents floor', fin_money_to_cents(-0.121, 'floor'), -13::BIGINT),
  assert_eq('money round exact double literal', fin_money_round(1.005::DOUBLE, 2), 1.01::DECIMAL(38,2)),
  assert_eq('money round type', typeof(fin_money_round(1.005, 2)), 'DECIMAL(38,2)'),
  assert_eq('money round half even down', fin_money_round(2.345, 2, 'half_even'), 2.34::DECIMAL(38,2)),
  assert_eq('money round half even up', fin_money_round(2.355, 2, 'half_even'), 2.36::DECIMAL(38,2)),
  assert_eq('money round ceil negative', fin_money_round(-1.231, 2, 'ceil'), -1.23::DECIMAL(38,2)),
  assert_eq('money round truncate', fin_money_round(-1.239, 2, 'truncate'), -1.23::DECIMAL(38,2)),
  assert_eq('cents to money exact decimal', fin_cents_to_money(-5), -0.05::DECIMAL(38,2)),
  assert_eq('cents to money scale type', typeof(fin_cents_to_money(1234, 3)), 'DECIMAL(38,3)'),
  assert_near('money weighted sum avoids decimal overflow', fin_money_weighted_sum(123456789012345.67::DECIMAL(18,2), 0.123456::DECIMAL(18,6)), 15241481344308.146, 1e-2),
  assert_true('valid ohlc ok', fin_validate_ohlc(100.0, 101.0, 99.0, 100.0).ok),
  assert_true('invalid ohlc fails', NOT fin_validate_ohlc(100.0, 99.0, 98.0, 100.0).ok),
  assert_true('return validation ok', fin_validate_return(0.05)),
  assert_true('decimal return alias', fin_is_decimal_return(0.05)),
  assert_true('outlier zscore', fin_is_outlier_zscore(3.1, 0.0, 1.0, 3.0)),
  assert_true('finite check', fin_is_finite(1.0)),
  assert_true('price check', fin_is_price(1.0)),
  assert_true('rate check', fin_is_rate(0.05)),
  assert_true('vol check', fin_is_vol(0.2)),
  assert_eq('parse option kind', fin_parse_option_kind('CALL'), 'call'),
  assert_eq('parse exercise', fin_parse_exercise_style('American'), 'american'),
  assert_eq('parse day count', fin_parse_day_count('actual/365 fixed'), 'ACT/365F'),
  assert_eq('parse compounding', fin_parse_compounding('continuous'), 'continuous'),
  assert_eq('parse return method', fin_parse_return_method('log'), 'log'),
  assert_eq('currency normalize', fin_normalize_currency('usd'), 'USD'),
  assert_eq('typeof helper', fin_typeof(1.0::DOUBLE), 'DOUBLE'),
  assert_eq('option spec kind', fin_option_spec('CALL', 100.0, 100.0, 1.0, 0.05, 0.2).kind, 'call'),
  assert_eq('option spec dates kind', fin_option_spec_dates('CALL', 100.0, 100.0, DATE '2026-01-01', DATE '2027-01-01', 0.05, 0.2).kind, 'call'),
  assert_eq('option market spec kind', fin_option_market_spec('CALL', 100.0, 100.0, DATE '2027-01-01', DATE '2026-01-01', 0.05, 0.2).kind, 'call'),
  assert_true('validate option spec ok', fin_validate_option_spec(fin_option_spec('CALL', 100.0, 100.0, 1.0, 0.05, 0.2)).ok),
  assert_eq('rate spec compounding', fin_rate_spec(0.05, 'continuous').compounding, 'continuous'),
  assert_true('validate rate spec ok', fin_validate_rate_spec(fin_rate_spec(0.05, 'continuous')).ok),
  assert_eq('curve spec type', fin_curve_spec([1.0, 2.0], [0.04, 0.05]).value_type, 'zero_rate'),
  assert_true('validate curve spec ok', fin_validate_curve_spec(fin_curve_spec([1.0, 2.0], [0.04, 0.05])).ok),
  assert_eq('cashflow spec currency', fin_cashflow_spec(100.0, DATE '2026-01-01', 'USD').currency, 'USD'),
  assert_eq('portfolio vector label', fin_portfolio_vector([0.5, 0.5], ['AAA', 'BBB']).labels[1], 'AAA'),
  assert_eq('portfolio spec currency', fin_portfolio_spec(['AAA', 'BBB'], [0.5, 0.5], 'USD').base_currency, 'USD'),
  assert_eq('optimizer spec objective', fin_optimizer_spec('min_variance').objective, 'min_variance'),
  assert_eq('var spec tail', fin_var_spec(0.95, 'historical', 'left').tail, 'left'),
  assert_eq('risk spec annualization', fin_risk_spec(252).annualization, 252),
  assert_eq('ts grid spec method', fin_ts_grid_spec(TIMESTAMP '2026-01-01 00:00:00', TIMESTAMP '2026-01-01 00:01:00', INTERVAL '1 minute').method, 'last'),
  assert_eq('bar spec kind', fin_bar_spec('volume', 1000.0).kind, 'volume'),
  assert_eq('calendar spec kind', fin_calendar_spec('weekday').calendar, 'weekday'),
  assert_eq('rate spec canonical names', fin_rate_spec(0.05, 'Semi-Annually', 2, 'act/360'), {'rate': 0.05, 'compounding': 'semiannual', 'frequency': 2, 'day_count': 'ACT/360'}),
  assert_eq('validate rate spec percentage', fin_validate_rate_spec(fin_rate_spec(5.0)).reason, 'rate above 1 (100%) looks like a percentage; pass decimal rates'),
  assert_eq('validate rate spec unknown compounding', fin_validate_rate_spec({'rate': 0.05, 'compounding': 'bogus', 'frequency': 1, 'day_count': 'ACT/360'}).reason, 'unknown compounding ''bogus'''),
  assert_eq('validate rate spec unknown day count', fin_validate_rate_spec({'rate': 0.05, 'compounding': 'simple', 'frequency': 1, 'day_count': 'nope'}).ok, false),
  assert_eq('validate rate spec frequency', fin_validate_rate_spec({'rate': 0.05, 'compounding': 'periodic', 'frequency': -3, 'day_count': 'ACT/360'}).reason, 'frequency must be a positive integer'),
  assert_eq('validate rate spec rate floor', fin_validate_rate_spec(fin_rate_spec(-1.5)).reason, 'rate must be greater than -1'),
  assert_eq('validate rate spec nonfinite', fin_validate_rate_spec(fin_rate_spec('NaN'::DOUBLE)).ok, false),
  assert_eq('optimizer spec fixed types', typeof(fin_optimizer_spec('min_variance', target_return := 0.08)), 'STRUCT(objective VARCHAR, risk_free DOUBLE, long_only BOOLEAN, weight_min DOUBLE, weight_max DOUBLE, target_return DOUBLE, target_vol DOUBLE, risk_aversion DOUBLE)'),
  assert_near('optimizer spec keeps decimal target', fin_optimizer_spec('target_return', target_return := 0.08).target_return, 0.08, 1e-15),
  assert_eq('risk spec annualization double', fin_risk_spec(252).annualization, 252.0::DOUBLE),
  assert_eq('bar spec threshold double', typeof(fin_bar_spec('volume', 1000).threshold), 'DOUBLE'),
  assert_eq('calendar spec canonical', fin_calendar_spec('XNYS').calendar, 'nyse'),
  assert_eq('portfolio vector typed', typeof(fin_portfolio_vector([1, 0], ['A', 'B']).weights), 'DOUBLE[]'),
  assert_true('business day', fin_is_business_day(DATE '2026-05-06', 'weekday')),
  assert_true('weekend not business day', NOT fin_is_business_day(DATE '2026-05-09', 'weekday')),
  assert_eq('next business day', fin_next_business_day(DATE '2026-05-08', 'weekday', 1), DATE '2026-05-11'),
  assert_eq('previous business day', fin_prev_business_day(DATE '2026-05-11', 'weekday', 1), DATE '2026-05-08'),
  assert_eq('business days between', fin_business_days_between(DATE '2026-05-04', DATE '2026-05-08', 'weekday'), 4),
  assert_eq('business days weekend to monday', fin_business_days_between(DATE '2026-05-09', DATE '2026-05-11', 'weekday'), 0),
  assert_eq('business days reverse weekend boundary', fin_business_days_between(DATE '2026-05-11', DATE '2026-05-09', 'weekday'), 0),
  assert_eq('business days reverse sign', fin_business_days_between(DATE '2026-05-09', DATE '2026-05-12', 'weekday'), -fin_business_days_between(DATE '2026-05-12', DATE '2026-05-09', 'weekday')),
  assert_eq('business days large range', fin_business_days_between(DATE '0001-01-01', DATE '9999-12-31', 'weekday'), 2608614),
  assert_eq('session date', fin_session_date(TIMESTAMP '2026-05-06 10:00:00', 'NYSE'), DATE '2026-05-06'),
  assert_true('regular session', fin_is_regular_session(TIMESTAMP '2026-05-06 10:00:00', 'NYSE'));

SELECT
  assert_eq('currency rejects non-letters', fin_normalize_currency('12!'), NULL),
  assert_near('binomial accepts more than 4096 steps', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20000), 10.450583572185565, 1e-3),
  assert_near('binomial accepts BIGINT steps', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 200::BIGINT), fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 200), 0);

-- Window aggregation must combine states exactly, not treat each segment as a
-- fresh history.
WITH RECURSIVE series AS (
  SELECT i, ((i % 17) - 8)::DOUBLE / 100.0 AS x
  FROM range(1, 701) t(i)
), expected(i, variance) AS (
  SELECT i, x * x FROM series WHERE i = 1
  UNION ALL
  SELECT s.i, 0.94 * e.variance + 0.06 * s.x * s.x
  FROM expected e JOIN series s ON s.i = e.i + 1
), actual AS (
  SELECT i, fin_ewma_variance(x) OVER (
    ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) / 252.0 AS variance
  FROM series
)
SELECT assert_eq('ewma window combine', count(*) FILTER (
  WHERE abs(actual.variance - expected.variance) > 1e-12
), 0::BIGINT)
FROM actual JOIN expected USING (i);

WITH series AS (
  SELECT i, ((i % 17) - 8)::DOUBLE / 100.0 AS x
  FROM range(1, 701) t(i)
), nav AS (
  SELECT i, x, product(1.0 + x) OVER (ORDER BY i) AS nav
  FROM series
), expected AS (
  SELECT i, nav / greatest(1.0, max(nav) OVER (
    ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )) - 1.0 AS drawdown
  FROM nav
), actual AS (
  SELECT i, fin_drawdown(x) OVER (
    ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS drawdown
  FROM series
)
SELECT assert_eq('drawdown window combine', count(*) FILTER (
  WHERE abs(actual.drawdown - expected.drawdown) > 1e-12
), 0::BIGINT)
FROM actual JOIN expected USING (i);

-- Table functions and bind-replace SQL.
SELECT assert_eq('schema template rows', count(*), 7::BIGINT)
FROM fin_schema_template('ohlcv');

SELECT assert_eq('schema template kind is case-insensitive', count(*), 3::BIGINT)
FROM fin_schema_template(' Returns ');

SELECT
  assert_eq('validate schema rows', count(*), 7::BIGINT),
  assert_true('validate schema all valid', bool_and(valid)),
  assert_eq('validate schema optional missing', max(status) FILTER (WHERE column_name = 'asset_id'), 'missing_optional'),
  assert_eq('validate schema present rows', count(*) FILTER (WHERE present AND compatible AND status = 'ok'), 6::BIGINT),
  assert_eq('validate schema reports actual type', max(actual_type) FILTER (WHERE column_name = 'ts'), 'TIMESTAMP')
FROM fin_validate_schema('gold_prices', 'ohlcv');

SELECT
  assert_eq('validate schema missing required', count(*) FILTER (WHERE status = 'missing'), 1::BIGINT),
  assert_eq('validate schema type mismatch', max(status) FILTER (WHERE column_name = 'asset_id'), 'type_mismatch'),
  assert_eq('validate schema compatible numeric', max(status) FILTER (WHERE column_name = 'return_decimal'), 'ok'),
  assert_eq('validate schema invalid rows', count(*) FILTER (WHERE NOT valid), 2::BIGINT)
FROM fin_validate_schema('(SELECT seq AS asset_id, r::DECIMAL(10, 4) AS return_decimal FROM gold_returns)', 'returns');

SELECT assert_eq('option chain rows', count(*), 2::BIGINT)
FROM fin_option_chain('gold_options', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield');

SELECT assert_near('option chain model price column', model_price, 10.450583572185565, 1e-10)
FROM fin_option_chain('gold_options', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield')
WHERE kind = 'call';

-- User columns must not shadow option-chain calculations or disappear.
CREATE TEMP TABLE gold_chain_collision AS
SELECT *, 'source marker' AS __finance_bsm_all, -123.0 AS bsm,
       struct_pack(bsm := struct_pack(price := -456.0)) AS __finance_model,
       struct_pack(spot := -789.0) AS __finance_source,
       'prefix marker' AS __finance_source_bsm,
       ['kept', NULL] AS "source\1", from_hex('00FF') AS "source ""blob""",
       'multiline marker' AS "line
name"
FROM gold_options;

SELECT
  assert_eq('option chain preserves helper-named scalar', __finance_bsm_all, 'source marker'),
  assert_eq('option chain preserves calculation-named column', bsm, -123.0),
  assert_eq('option chain preserves model-named struct', __finance_model.bsm.price, -456.0),
  assert_eq('option chain preserves source-named struct', __finance_source.spot, -789.0),
  assert_eq('option chain restores internal-prefix source name', __finance_source_bsm, 'prefix marker'),
  assert_eq('option chain preserves backslash name and list type', "source\1", ['kept', NULL]),
  assert_eq('option chain preserves quoted name and blob type', "source ""blob""", from_hex('00FF')),
  assert_eq('option chain preserves multiline source name', "line
name", 'multiline marker'),
  assert_near('option chain collision price', model_price,
    fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield), 1e-10),
  assert_near('option chain collision delta', model_delta,
    fin_bsm_delta(kind, spot, strike, ttm, rate, vol, dividend_yield), 1e-10)
FROM fin_option_chain('gold_chain_collision', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield');

CREATE TEMP TABLE gold_chain_struct_collision AS
SELECT * EXCLUDE (dividend_yield),
       struct_pack(price := 999.0, delta := -9.0, gamma := -9.0,
                   vega := -9.0, theta := -9.0, rho := -9.0) AS __finance_bsm_all
FROM gold_options;

SELECT
  assert_eq('option chain preserves helper-named struct', __finance_bsm_all.price, 999.0),
  assert_near('option chain struct collision price', model_price,
    fin_bsm_price(kind, spot, strike, ttm, rate, vol), 1e-10),
  assert_near('option chain struct collision delta', model_delta,
    fin_bsm_delta(kind, spot, strike, ttm, rate, vol), 1e-10),
  assert_near('option chain struct collision gamma', model_gamma,
    fin_bsm_gamma(spot, strike, ttm, rate, vol), 1e-10),
  assert_near('option chain struct collision vega', model_vega,
    fin_bsm_vega(kind, spot, strike, ttm, rate, vol), 1e-10),
  assert_near('option chain struct collision theta', model_theta,
    fin_bsm_theta(kind, spot, strike, ttm, rate, vol), 1e-10),
  assert_near('option chain struct collision rho', model_rho,
    fin_bsm_rho(kind, spot, strike, ttm, rate, vol), 1e-10),
  assert_near('option chain struct collision implied vol', model_implied_volatility, vol, 1e-10)
FROM fin_option_chain('gold_chain_struct_collision', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol');

CREATE TEMP TABLE gold_chain_named_inputs AS
SELECT kind AS __finance_model, spot AS __finance_source, vol AS bsm,
       strike AS "strike with space", ttm, rate, dividend_yield
FROM gold_options;

SELECT
  assert_near('option chain qualified input price', model_price,
    fin_bsm_price(__finance_model, __finance_source, "strike with space", ttm, rate, bsm, dividend_yield), 1e-10),
  assert_near('option chain qualified input implied vol', model_implied_volatility, bsm, 1e-10)
FROM fin_option_chain('gold_chain_named_inputs', '__finance_model', '__finance_source', 'strike with space',
                      'ttm', 'rate', 'bsm', 'dividend_yield');

CREATE TEMP TABLE gold_chain_nulls AS
SELECT i, 'call' AS kind, 100.0 AS spot, 100.0 AS strike, 1.0 AS ttm, 0.05 AS rate,
       CASE WHEN i % 3 = 0 THEN NULL::DOUBLE ELSE 0.2 END AS vol
FROM range(4096) r(i);

SELECT
  assert_eq('option chain preserves repeated inputs across vectors', count(*), 4096::BIGINT),
  assert_eq('option chain preserves null-price rows', count(*) FILTER (WHERE model_price IS NULL), 1366::BIGINT),
  assert_eq('option chain null-price agreement', count(*) FILTER (
    WHERE model_price IS DISTINCT FROM fin_bsm_price(kind, spot, strike, ttm, rate, vol)), 0::BIGINT)
FROM fin_option_chain('gold_chain_nulls', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol');

CREATE TEMP TABLE gold_chain_reprice AS
SELECT *, 999.0 AS model_price, -9.0 AS "MODEL_DELTA", -9.0 AS model_gamma,
       -9.0 AS model_vega, -9.0 AS model_theta, -9.0 AS model_rho,
       -9.0 AS model_implied_volatility, 'custom marker' AS model_discount,
       'prefix marker' AS __finance_source_model_price
FROM gold_options;

CREATE TEMP VIEW gold_chain_repriced AS
SELECT * FROM fin_option_chain('gold_chain_reprice', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield');

WITH expected AS (
  SELECT *, fin_bsm_all(kind, spot, strike, ttm, rate, vol, dividend_yield) AS reference
  FROM gold_chain_repriced
)
SELECT
  assert_near('repricing replaces price', model_price, reference.price, 1e-10),
  assert_near('repricing replaces case-insensitive delta', model_delta, reference.delta, 1e-10),
  assert_near('repricing replaces gamma', model_gamma, reference.gamma, 1e-10),
  assert_near('repricing replaces vega', model_vega, reference.vega, 1e-10),
  assert_near('repricing replaces theta', model_theta, reference.theta, 1e-10),
  assert_near('repricing replaces rho', model_rho, reference.rho, 1e-10),
  assert_near('repricing replaces implied vol', model_implied_volatility, vol, 1e-10),
  assert_eq('repricing preserves other model names', model_discount, 'custom marker'),
  assert_eq('repricing preserves prefixed source name', __finance_source_model_price, 'prefix marker')
FROM expected;

SELECT assert_eq('repricing has one price column', count(*), 1::BIGINT)
FROM pragma_table_info('gold_chain_repriced') WHERE name LIKE 'model_price%';

SELECT assert_eq('repricing leaves source table unchanged', min(model_price), 999.0)
FROM gold_chain_reprice;

CREATE TEMP TABLE gold_chain_model_input AS
SELECT * EXCLUDE (vol), vol AS model_price, vol AS expected_vol FROM gold_options;

SELECT assert_near('repricing uses conflicting input before replacement', model_implied_volatility, expected_vol, 1e-10)
FROM fin_option_chain('gold_chain_model_input', 'kind', 'spot', 'strike', 'ttm', 'rate', 'model_price');

-- Curve bootstrap references: QuantLib 1.43 PiecewiseLogLinearDiscount with SimpleDayCounter,
-- NullCalendar, Unadjusted, zero fixing days (DepositRateHelper, FraRateHelper, SwapRateHelper),
-- cross-checked by an independent numpy sequential bootstrap.
CREATE OR REPLACE TEMP TABLE gold_curve_expected(inst VARCHAR, df_annual DOUBLE, df_semiannual DOUBLE,
  zero_cont DOUBLE, fwd_cont DOUBLE, zero_quarterly DOUBLE, zero_simple DOUBLE);
INSERT INTO gold_curve_expected VALUES
  ('d3m', 0.992555831265509, 0.992555831265509, 0.02988805935480511, 0.02988805935480511, 0.030000000000001137, 0.030000000000001137),
  ('d6m', 0.984251968503937, 0.984251968503937, 0.031746698312580326, 0.033605337270355785, 0.03187301387332919, 0.03200000000000003),
  ('f6x9', 0.975956339617191, 0.975956339617191, 0.03244990342455955, 0.033856313648517454, 0.032581884610245915, 0.032848000000000134),
  ('s2y', 0.931651086060209, 0.931044586864458, 0.03539845278548928, 0.03716758240204719, 0.03555554715913711, 0.0366816048209857),
  ('s3y', 0.893886246796388, 0.892924250610456, 0.03739225087477797, 0.041379847053355366, 0.037567569298002645, 0.03957019273384973),
  ('s5y', 0.816975632682333, 0.815275842012498, 0.040429201985028626, 0.04498462865040451, 0.040634207132411504, 0.0448053430227179);

SELECT assert_eq('bootstrap curve rows', count(*), 6::BIGINT)
FROM fin_bootstrap_curve('gold_curve', 'kind', 'maturity', 'rate', instrument_col := 'inst', start_col := 'start_time');

SELECT assert_eq('bootstrap curve maturity order', list(instrument), ['d3m', 'd6m', 'f6x9', 's2y', 's3y', 's5y'])
FROM fin_bootstrap_curve('gold_curve', 'kind', 'maturity', 'rate', instrument_col := 'inst', start_col := 'start_time');

SELECT
  assert_near('bootstrap curve quantlib annual df ' || c.instrument, c.discount_factor, e.df_annual, 1e-12),
  assert_near('bootstrap curve continuous zero ' || c.instrument, c.zero_rate, e.zero_cont, 1e-12),
  assert_near('bootstrap curve continuous forward ' || c.instrument, c.forward_rate, e.fwd_cont, 1e-12),
  assert_eq('bootstrap curve echoes quote ' || c.instrument, c.rate, g.rate),
  assert_eq('bootstrap curve echoes type ' || c.instrument, c.instrument_type, g.kind)
FROM fin_bootstrap_curve('gold_curve', 'kind', 'maturity', 'rate', 'continuous', instrument_col := 'inst', start_col := 'start_time') c
JOIN gold_curve_expected e ON e.inst = c.instrument
JOIN gold_curve g ON g.inst = c.instrument;

SELECT assert_near('curve bootstrap quantlib semiannual swap df ' || c.instrument, c.discount_factor, e.df_semiannual, 1e-12)
FROM fin_curve_bootstrap('gold_curve', 'kind', 'maturity', 'rate', instrument_col := 'inst', start_col := 'start_time', fixed_frequency := 2) c
JOIN gold_curve_expected e ON e.inst = c.instrument;

SELECT assert_near('bootstrap curve quarterly zero ' || c.instrument, c.zero_rate, e.zero_quarterly, 1e-12)
FROM fin_bootstrap_curve('gold_curve', 'kind', 'maturity', 'rate', 'quarterly', instrument_col := 'inst', start_col := 'start_time') c
JOIN gold_curve_expected e ON e.inst = c.instrument;

SELECT
  assert_near('bootstrap curve simple zero ' || c.instrument, c.zero_rate, e.zero_simple, 1e-12),
  assert_near('bootstrap curve compounding keeps df ' || c.instrument, c.discount_factor, e.df_annual, 1e-12)
FROM fin_bootstrap_curve('gold_curve', 'kind', 'maturity', 'rate', 'simple', instrument_col := 'inst', start_col := 'start_time') c
JOIN gold_curve_expected e ON e.inst = c.instrument;

-- Annual swaps at 1.25y and 2.25y have a 0.25y front stub (numpy reference).
SELECT
  assert_near('bootstrap curve stub swap df ' || maturity, discount_factor,
    CASE maturity WHEN 0.5 THEN 0.9852216748768473 WHEN 1.25 THEN 0.9577921698818882 ELSE 0.9151562306394376 END, 1e-12),
  assert_near('bootstrap curve stub swap forward ' || maturity, forward_rate,
    CASE maturity WHEN 0.5 THEN 0.029777224987501117 WHEN 1.25 THEN 0.037647804961264845 ELSE 0.045536018198753754 END, 1e-12),
  assert_eq('bootstrap curve instrument defaults to null', instrument, NULL::VARCHAR)
FROM fin_bootstrap_curve('(FROM (VALUES (''deposit'', 0.5, 0.030), (''swap'', 1.25, 0.035), (''swap'', 2.25, 0.040)) t(k, m, r))', 'k', 'm', 'r');

SELECT
  assert_near('bootstrap curve zero df ' || maturity, discount_factor, fin_discount_factor(rate, maturity, 'semiannual'), 1e-12),
  assert_near('bootstrap curve zero roundtrip ' || maturity, zero_rate, rate, 1e-12),
  assert_near('bootstrap curve zero forward ' || maturity, forward_rate,
    CASE maturity WHEN 1.0 THEN 0.05 ELSE 0.06001219512195188 END, 1e-12),
  assert_eq('bootstrap curve normalizes type', instrument_type, 'zero')
FROM fin_bootstrap_curve('(FROM (VALUES (''ZERO'', 2.0, 0.055), ('' zero'', 1.0, 0.05)) t(k, m, r))', 'k', 'm', 'r', 'semiannual');

SELECT assert_eq('bootstrap curve empty input', count(*), 0::BIGINT)
FROM fin_bootstrap_curve('(SELECT ''swap'' AS k, 1.0 AS m, 0.05 AS r WHERE false)', 'k', 'm', 'r');

SELECT assert_eq('calendar rows', count(*), 3::BIGINT)
FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-06');

SELECT assert_eq('hrp weight rows', count(*), 2::BIGINT)
FROM fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]], ['AAA', 'BBB'], 'single');

-- HRP reference: PyPortfolioOpt-style recursion with scipy.cluster.hierarchy linkage.
SELECT
  assert_near('hrp weight 0', list(weight ORDER BY asset_idx)[1], 0.18574376670909412, 1e-12),
  assert_near('hrp weight 1', list(weight ORDER BY asset_idx)[2], 0.07151635870486522, 1e-12),
  assert_near('hrp weight 2', list(weight ORDER BY asset_idx)[3], 0.08551510965720086, 1e-12),
  assert_near('hrp weight 3', list(weight ORDER BY asset_idx)[4], 0.28606543481946095, 1e-12),
  assert_near('hrp weight 4', list(weight ORDER BY asset_idx)[5], 0.3711593301093789, 1e-12),
  assert_near('hrp weights sum to one', sum(weight), 1.0, 1e-12),
  assert_eq('hrp labels', list(asset ORDER BY asset_idx), ['A', 'B', 'C', 'D', 'E'])
FROM fin_hrp_weights(
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]],
  ['A', 'B', 'C', 'D', 'E'], 'ward');

SELECT assert_near('hrp two assets inverse variance', max(weight) FILTER (WHERE asset_idx = 0), 0.09 / 0.13, 1e-12)
FROM fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]]);

SELECT assert_eq('frontier default rows', count(*), 25::BIGINT)
FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]]);

SELECT
  assert_eq('frontier bigint points', count(*), 3000::BIGINT),
  assert_near('frontier last target', max(expected_return), 0.2, 1e-12)
FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 3000::BIGINT);

-- Unconstrained frontier: closed form sigma^2 = (A m^2 - 2 B m + C) / D (Merton 1972, numpy reference).
SELECT
  assert_near('frontier short gmv return', list(expected_return ORDER BY point_idx)[1], 0.05472224591838816, 1e-12),
  assert_near('frontier short gmv vol', list(volatility ORDER BY point_idx)[1], 0.09091231166889194, 1e-12),
  assert_near('frontier short mid vol', list(volatility ORDER BY point_idx)[3], 0.13492180447927882, 1e-12),
  assert_near('frontier short top vol', list(volatility ORDER BY point_idx)[5], 0.21913563849094408, 1e-12),
  assert_near('frontier short weights sum', list_sum(list(weights ORDER BY point_idx)[4]), 1.0, 1e-12)
FROM fin_efficient_frontier([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 5, true);

-- Long-only frontier (scipy SLSQP reference, tolerance limited by SLSQP).
SELECT
  assert_near('frontier long gmv return', list(expected_return ORDER BY point_idx)[1], 0.057612461393783336, 1e-9),
  assert_near('frontier long gmv vol', list(volatility ORDER BY point_idx)[1], 0.09167876144517254, 1e-9),
  assert_near('frontier long mid vol', list(volatility ORDER BY point_idx)[3], 0.13821531956459598, 1e-9),
  assert_near('frontier long upper vol', list(volatility ORDER BY point_idx)[4], 0.18116017671525664, 1e-9),
  assert_eq('frontier long top is best asset', list(weights ORDER BY point_idx)[5], [0.0, 1.0, 0.0, 0.0, 0.0]),
  assert_true('frontier long weights non-negative', bool_and(list_min(weights) >= 0.0)),
  assert_eq('frontier long gmv support', list_transform(list(weights ORDER BY point_idx)[1], lambda w: w > 0),
    [true, false, false, true, true])
FROM fin_efficient_frontier([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 5);

-- Bounded QP optimizer. References: exact KKT solves on the optimal active set
-- (numpy), cross-checked against scipy SLSQP.
SELECT
  assert_eq('optimizer full overload rows', count(*), 2::BIGINT),
  assert_near('optimizer 2 asset tangency', max(weight) FILTER (WHERE asset_idx = 0), 0.5, 1e-12)
FROM fin_portfolio_optimize([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 'max_sharpe', 0.0, true, 0.0, 1.0, 0.12, 0.2, 1.0);

SELECT
  assert_near('optimizer min variance w0', list(weight ORDER BY asset_idx)[1], 0.14113065664025784, 1e-12),
  assert_eq('optimizer min variance excluded', list(weight ORDER BY asset_idx)[2:3], [0.0, 0.0]),
  assert_near('optimizer min variance w3', list(weight ORDER BY asset_idx)[4], 0.33785416946421376, 1e-12),
  assert_near('optimizer min variance w4', list(weight ORDER BY asset_idx)[5], 0.5210151738955284, 1e-12)
FROM fin_portfolio_optimize([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]]);

-- Unbounded tangency portfolio equals Sigma^-1 (mu - rf) normalized.
SELECT
  assert_near('optimizer tangency w0', list(weight ORDER BY asset_idx)[1], 0.25946089402163214, 1e-12),
  assert_near('optimizer tangency w4', list(weight ORDER BY asset_idx)[5], 0.20135885408474086, 1e-12)
FROM fin_portfolio_optimize([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 'max_sharpe', 0.02, false);

SELECT
  assert_eq('optimizer capped sharpe cap', list(weight ORDER BY asset_idx)[1], 0.25),
  assert_near('optimizer capped sharpe w1', list(weight ORDER BY asset_idx)[2], 0.17355952868695226, 1e-12),
  assert_near('optimizer capped sharpe w3', list(weight ORDER BY asset_idx)[4], 0.20290156573354723, 1e-12),
  assert_near('optimizer capped sharpe sum', sum(weight), 1.0, 1e-14)
FROM fin_portfolio_optimize([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 'max_sharpe', 0.02, true, NULL, 0.25);

SELECT
  assert_near('optimizer target vol w0', list(weight ORDER BY asset_idx)[1], 0.30960157447276515, 1e-11),
  assert_near('optimizer target vol w3', list(weight ORDER BY asset_idx)[4], 0.08179736039649857, 1e-11),
  assert_near('optimizer target vol floor', list(weight ORDER BY asset_idx)[5], 0.05, 1e-15)
FROM fin_portfolio_optimize([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 'target_vol', 0.0, true, 0.05, 0.5, NULL, 0.15);

SELECT
  assert_near('optimizer target return w0', list(weight ORDER BY asset_idx)[1], 0.385131476729678, 1e-12),
  assert_near('optimizer target return w3', list(weight ORDER BY asset_idx)[4], 0.004129099084253651, 1e-12),
  assert_near('optimizer target return short floor', list(weight ORDER BY asset_idx)[5], -0.2, 1e-15),
  assert_near('optimizer target return attained', sum(weight * [0.08, 0.12, 0.10, 0.06, 0.05][asset_idx + 1]), 0.11, 1e-14)
FROM fin_portfolio_optimize([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 'target_return', 0.0, false, -0.2, NULL, 0.11);

-- max_utility: max mu'w - risk_aversion / 2 w'Sigma w (scipy SLSQP reference).
SELECT
  assert_near('optimizer utility w0', list(weight ORDER BY asset_idx)[1], 0.30445442408957096, 1e-7),
  assert_near('optimizer utility w4', list(weight ORDER BY asset_idx)[5], 0.05523801334225375, 1e-7)
FROM fin_portfolio_optimize([0.08, 0.12, 0.10, 0.06, 0.05],
  [[0.040, 0.006, 0.010, 0.002, 0.004], [0.006, 0.090, 0.012, 0.020, 0.003], [0.010, 0.012, 0.0625, 0.005, 0.015],
   [0.002, 0.020, 0.005, 0.0225, 0.001], [0.004, 0.003, 0.015, 0.001, 0.0144]], 'max_utility', 0.0, true, NULL, 0.6, NULL, NULL, 3.0);

-- Table optimizer: sample means and pairwise covariance of the return history
-- (pandas mean/cov, scipy SLSQP reference); asset keeps its source type.
SELECT
  assert_eq('optimizer table assets', list(asset ORDER BY asset_idx), ['A', 'B', 'C', 'D']),
  assert_near('optimizer table sharpe w0', list(weight ORDER BY asset_idx)[1], 0.1594705003533707, 1e-7),
  assert_near('optimizer table sharpe w3', list(weight ORDER BY asset_idx)[4], 0.2724011546600638, 1e-7)
FROM fin_portfolio_optimize_table('(SELECT i // 4 AS d, chr(65 + (i % 4)::INTEGER) AS a, x / 10 + 0.01 * (i % 4) AS r FROM gold_stats)',
  'a', 'd', 'r', 'max_sharpe', 0.0, true, NULL, 0.6);

SELECT
  assert_eq('optimizer table integer asset', typeof(any_value(asset)), 'BIGINT'),
  assert_near('optimizer table min variance w0', list(weight ORDER BY asset_idx)[1], 0.20390342313284646, 1e-7),
  assert_near('optimizer table min variance w2', list(weight ORDER BY asset_idx)[3], 0.2657306503042067, 1e-7)
FROM fin_portfolio_optimize_table('(SELECT i // 4 AS d, i % 4 AS a, x / 10 + 0.01 * (i % 4) AS r FROM gold_stats)',
  'a', 'd', 'r');

SELECT assert_eq('factor report rows', count(*), 1::BIGINT)
FROM fin_factor_report('gold_returns', 'd', 'asset', 'factor', 'forward_return', 2);

-- Per-date cross-sectional IC averaged over dates (scipy pearsonr/spearmanr reference).
SELECT
  assert_near('factor report mean ic', ic, 0.8602260468752781, 1e-12),
  assert_near('factor report ic std', ic_std, 0.047163893068661984, 1e-12),
  assert_near('factor report ic ir', ic_ir, 18.239080595466255, 1e-9),
  assert_near('factor report ic tstat', ic_tstat, 31.591014274691165, 1e-9),
  assert_near('factor report rank ic', rank_ic, 0.8495610993501712, 1e-12),
  assert_near('factor report mean return', mean_return, 0.013333333333333334, 1e-15),
  assert_near('factor report quantile spread', quantile_spread, 0.018333333333333337, 1e-15),
  assert_eq('factor report dates', n_dates, 3::BIGINT),
  assert_eq('factor report observations', n_obs, 12::BIGINT)
FROM fin_factor_report('gold_factor_panel', 'd', 'asset', 'factor', 'fwd', 2::BIGINT);

-- Fama-MacBeth: per-date OLS, then the time-series mean of each coefficient
-- (numpy/statsmodels reference; Newey-West = OLS on a constant with
-- cov_type='HAC', maxlags=L, use_correction=False).
SELECT
  assert_eq('fama macbeth terms', list(term ORDER BY term = 'intercept' DESC, term), ['intercept', 'f1', 'f2']),
  assert_near('fama macbeth intercept', max(estimate) FILTER (WHERE term = 'intercept'), 0.4919074928170733, 1e-12),
  assert_near('fama macbeth f1', max(estimate) FILTER (WHERE term = 'f1'), 1.1979860539704417, 1e-12),
  assert_near('fama macbeth f2', max(estimate) FILTER (WHERE term = 'f2'), -0.6859207392729733, 1e-12),
  assert_near('fama macbeth classic se f1', max(stderr) FILTER (WHERE term = 'f1'), 0.017695044165216837, 1e-12),
  assert_near('fama macbeth classic se f2', max(stderr) FILTER (WHERE term = 'f2'), 0.03212088857842378, 1e-12),
  assert_eq('fama macbeth periods', min(n_periods), 8::BIGINT)
FROM fin_fama_macbeth('(SELECT i // 8 AS d, i % 8 AS a, oy, f1, f2 FROM gold_stats)', 'd', 'a', 'oy', ['f1', 'f2']);

SELECT
  assert_near('fama macbeth nw2 se intercept', max(stderr) FILTER (WHERE term = 'intercept'), 0.0156725138345265, 1e-12),
  assert_near('fama macbeth nw2 se f1', max(stderr) FILTER (WHERE term = 'f1'), 0.009448102636082955, 1e-12),
  assert_near('fama macbeth nw2 tstat f2', max(tstat) FILTER (WHERE term = 'f2'),
    -0.6859207392729733 / 0.014347694072117443, 1e-9)
FROM fin_fama_macbeth('(SELECT i // 8 AS d, i % 8 AS a, oy, f1, f2 FROM gold_stats)', 'd', 'a', 'oy', ['f1', 'f2'], 2);

SELECT assert_near('fama macbeth nw0 se f1', max(stderr) FILTER (WHERE term = 'f1'), 0.016552198177518674, 1e-12)
FROM fin_fama_macbeth('(SELECT i // 8 AS d, i % 8 AS a, oy, f1, f2 FROM gold_stats)', 'd', 'a', 'oy', ['f1', 'f2'], 0);

-- Grouping uses the date argument even when the source also has a column named date.
SELECT
  assert_eq('fama macbeth groups by date argument', max(n_periods), 3::BIGINT),
  assert_near('fama macbeth slope mean', max(estimate) FILTER (WHERE term = 'factor'),
    (0.011000000000000005 + 0.016999999999999998 + 0.008888888888888887) / 3, 1e-12)
FROM fin_fama_macbeth('(SELECT d, DATE ''2000-01-01'' AS date, asset, factor, fwd FROM gold_factor_panel)',
  'd', 'asset', 'fwd', ['factor']);

-- GARCH(1,1) MLE on a simulated path stored out of order (scipy Nelder-Mead
-- reference on the same likelihood, h_1 = sample variance).
SELECT
  assert_eq('garch fit rows', count(*), 1::BIGINT),
  assert_near('garch fit loglik', any_value(loglik), 857.213331159131, 1e-8),
  assert_near('garch fit omega', any_value(omega), 9.667622579178341e-06, 1e-10),
  assert_near('garch fit alpha', any_value(alpha), 0.11024234033021169, 1e-6),
  assert_near('garch fit beta', any_value(beta), 0.8428890079171752, 1e-6),
  assert_near('garch fit unconditional variance', any_value(unconditional_variance),
    any_value(omega) / (1 - any_value(alpha) - any_value(beta)), 1e-15),
  assert_eq('garch fit nobs', any_value(nobs), 300::BIGINT)
FROM fin_garch_fit('gold_garch', 'r', 't', 1, 1, 'normal');

-- Table-function estimators do not depend on threads or row order.
CREATE OR REPLACE MACRO sp_tf_metrics() AS TABLE
  SELECT 'garch' AS k, alpha AS v FROM fin_garch_fit('(SELECT ts, x / 10 AS r FROM sp_order_input WHERE g = 3)', 'r', 'ts')
  UNION ALL
  SELECT term, stderr FROM fin_fama_macbeth('(SELECT ts // 10 AS d, g AS a, y, x FROM sp_order_input)', 'd', 'a', 'y', ['x'], 2)
  UNION ALL
  SELECT asset::VARCHAR, weight FROM fin_portfolio_optimize_table(
    '(SELECT ts AS d, g AS a, x / 100 + 0.001 * (g % 7) AS r FROM sp_order_input WHERE g < 10)', 'a', 'd', 'r', 'max_sharpe');
SET threads = 1;
CREATE OR REPLACE TEMP TABLE sp_tf_one AS SELECT * FROM sp_tf_metrics();
SET threads = 8;
CREATE OR REPLACE TEMP TABLE sp_tf_eight AS SELECT * FROM sp_tf_metrics();
RESET threads;
SELECT
  assert_eq('table estimators populated', count(*) FILTER (WHERE a.v IS NOT NULL), 13::BIGINT),
  assert_true('table estimators are thread invariant', max(abs(a.v - b.v)) <= 1e-12)
FROM sp_tf_one a JOIN sp_tf_eight b USING (k);

SELECT assert_true('garch fit too short is null', omega IS NULL AND loglik IS NULL)
FROM fin_garch_fit('(SELECT t, r FROM gold_garch WHERE t < 9)', 'r', 't');

-- Fitted parameters plug into fin_garch11_forecast with the same recursion.
SELECT assert_true('garch fit feeds forecast', fin_garch11_forecast(g.r, f.omega, f.alpha, f.beta ORDER BY g.t) > 0)
FROM gold_garch g, fin_garch_fit('gold_garch', 'r', 't') f;

SELECT assert_eq('normalize returns rows', count(*), 5::BIGINT)
FROM fin_normalize_returns('gold_returns', 'd', 'asset', 'r');

SELECT assert_eq('normalize ohlcv rows', count(*), 5::BIGINT)
FROM fin_normalize_ohlcv('gold_prices', 'ts', 'open', 'high', 'low', 'close', 'volume');

-- Normalizers pass non-consumed source columns through after the canonical ones.
SELECT
  assert_eq('normalize ohlcv passes extra columns', list(column_name),
    ['ts', 'asset_id', 'open', 'high', 'low', 'close', 'volume', 'seq', 'bid', 'ask', 'bid_size', 'ask_size'])
FROM (DESCRIBE SELECT * FROM fin_normalize_ohlcv('gold_prices', 'ts', 'open', 'high', 'low', 'close', 'volume'));

SELECT
  assert_eq('normalize returns keeps identifiers', list(column_name),
    ['date', 'asset_id', 'return_decimal', 'seq', 'benchmark_r', 'factor', 'forward_return'])
FROM (DESCRIBE SELECT * FROM fin_normalize_returns('gold_returns', 'd', 'asset', 'r'));

SELECT assert_eq('normalize returns all columns consumed', count(*), 5::BIGINT)
FROM fin_normalize_returns('(SELECT d, asset, r FROM gold_returns)', 'd', 'asset', 'r');

SELECT assert_near('normalize option spec price', fin_bsm_price(option_spec), 10.450583572185565, 1e-10)
FROM fin_normalize_option_chain(
  'gold_source_options',
  'cp',
  'underlying_px',
  'strike_px',
  'expiry_dt',
  'valuation_dt',
  'zero_rate',
  'iv',
  'q'
)
WHERE option_kind = 'call';

SELECT assert_eq('rebalance trade rows', count(*), 2::BIGINT)
FROM fin_rebalance_trades('gold_current_weights', 'gold_target_weights', 'gold_asset_prices', 100000.0);

SELECT
  assert_near('rebalance named columns quantity', sum(quantity_delta) FILTER (WHERE asset_id = 'BBB'), 200.0, 1e-12),
  assert_near('rebalance named columns notional', sum(notional_delta), 0.0, 1e-9)
FROM fin_rebalance_trades(
  '(SELECT asset AS asset_id, weight AS w FROM gold_current_weights)',
  '(SELECT asset AS asset_id, weight AS w FROM gold_target_weights)',
  '(SELECT asset AS asset_id, price AS px FROM gold_asset_prices)',
  100000.0, asset_col := 'asset_id', weight_col := 'w', price_col := 'px');

SELECT assert_near('portfolio return table', portfolio_return, 0.14, 1e-12)
FROM fin_portfolio_return_table('gold_weighted_returns', 'asset', 'weight', 'expected_return');

SELECT
  assert_eq('portfolio return table per date rows', count(*), 3::BIGINT),
  assert_near('portfolio return table date 2', max(portfolio_return) FILTER (WHERE d = 2),
    0.25 * (0.040 - 0.010 + 0.000 - 0.020), 1e-15),
  assert_eq('portfolio return table per date assets', min(asset_count), 4::BIGINT)
FROM fin_portfolio_return_table('(SELECT *, 0.25 AS w FROM gold_factor_panel)', 'asset', 'w', 'fwd', 'd');

SELECT assert_near('portfolio variance table', portfolio_variance, 0.0336, 1e-12)
FROM fin_portfolio_variance_table(
  'gold_weighted_returns',
  'asset',
  'weight',
  'gold_covariance',
  'asset_i',
  'asset_j',
  'covariance'
);

-- Upper-triangle covariance storage is mirrored; w'Cw = 0.36*0.04 + 2*0.24*0.01 + 0.16*0.09.
SELECT
  assert_near('portfolio variance upper triangle', portfolio_variance, 0.0336, 1e-12),
  assert_near('portfolio volatility upper triangle', portfolio_volatility, sqrt(0.0336), 1e-12)
FROM fin_portfolio_variance_table(
  'gold_weighted_returns', 'asset', 'weight',
  '(FROM gold_covariance WHERE asset_i <= asset_j)', 'asset_i', 'asset_j', 'covariance');

SELECT
  assert_eq('portfolio variance empty weights', portfolio_variance, NULL),
  assert_eq('portfolio volatility empty weights', portfolio_volatility, NULL)
FROM fin_portfolio_variance_table(
  '(FROM gold_weighted_returns WHERE false)', 'asset', 'weight',
  'gold_covariance', 'asset_i', 'asset_j', 'covariance');

SELECT assert_eq('tick bars default rows', count(*), 1::BIGINT)
FROM fin_tick_bars('gold_prices', 'ts', 'close');

SELECT assert_eq('volume bars rows', count(*), 5::BIGINT)
FROM fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 1000.0);

SELECT assert_eq('dollar bars rows', count(*), 5::BIGINT)
FROM fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 100000.0);

-- AFML tick-rule imbalance: signs 0, +, -, +, - give signed volumes 0, 1500, -2000, 1800, -1200;
-- with threshold 1500 the accumulator closes after rows 2, 3 and 4 and resets to zero.
SELECT
  assert_eq('imbalance bars rows', count(*), 4::BIGINT),
  assert_eq('imbalance bars tick rule', list(imbalance ORDER BY bar_id), [1500.0, -2000.0, 1800.0, -1200.0]),
  assert_eq('imbalance bars traded volume', list(volume ORDER BY bar_id), [2500.0, 2000.0, 1800.0, 1200.0])
FROM fin_imbalance_bars('gold_prices', 'ts', 'close', 'volume', 1500.0, 'tick_rule');

-- AFML reset-accumulator bars (Lopez de Prado 2018, ch. 2.3): the overshoot does not carry into the next bar.
-- Volumes 1000, 1500, 2000, 1800, 1200 with threshold 3000 close after rows 3 and 5; dollar values
-- 100000, 153000, 198000, 187200, 123600 with threshold 300000 give the same bars.
WITH actual AS (
  SELECT 'tick' AS kind, bar_id, start_ts, end_ts, open, high, low, close, volume, vwap, ticks
  FROM fin_tick_bars('gold_prices', 'ts', 'close', 2::BIGINT)
  UNION ALL
  SELECT 'volume', bar_id, start_ts, end_ts, open, high, low, close, volume, vwap, ticks
  FROM fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 3000.0)
  UNION ALL
  SELECT 'dollar', bar_id, start_ts, end_ts, open, high, low, close, volume, vwap, ticks
  FROM fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 300000.0)
), expected(kind, bar_id, start_ts, end_ts, open, high, low, close, volume, vwap, ticks) AS (
  VALUES
    ('tick', 0, TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:31:00',
     100.0, 102.0, 100.0, 102.0, NULL, NULL, 2),
    ('tick', 1, TIMESTAMP '2026-01-02 09:32:00', TIMESTAMP '2026-01-02 09:33:00',
     99.0, 104.0, 99.0, 104.0, NULL, NULL, 2),
    ('tick', 2, TIMESTAMP '2026-01-02 09:34:00', TIMESTAMP '2026-01-02 09:34:00',
     103.0, 103.0, 103.0, 103.0, NULL, NULL, 1),
    ('volume', 0, TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:32:00',
     100.0, 102.0, 99.0, 99.0, 4500.0, 451000.0 / 4500.0, 3),
    ('volume', 1, TIMESTAMP '2026-01-02 09:33:00', TIMESTAMP '2026-01-02 09:34:00',
     104.0, 104.0, 103.0, 103.0, 3000.0, 103.6, 2),
    ('dollar', 0, TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:32:00',
     100.0, 102.0, 99.0, 99.0, 4500.0, 451000.0 / 4500.0, 3),
    ('dollar', 1, TIMESTAMP '2026-01-02 09:33:00', TIMESTAMP '2026-01-02 09:34:00',
     104.0, 104.0, 103.0, 103.0, 3000.0, 103.6, 2)
)
SELECT
  assert_eq('bar full row count', (SELECT count(*) FROM actual), 7::BIGINT),
  assert_eq('bar full row keys', count(*), 7::BIGINT),
  assert_true('bar full row values', bool_and(
    a.start_ts IS NOT DISTINCT FROM e.start_ts AND a.end_ts IS NOT DISTINCT FROM e.end_ts
    AND a.open IS NOT DISTINCT FROM e.open AND a.high IS NOT DISTINCT FROM e.high
    AND a.low IS NOT DISTINCT FROM e.low AND a.close IS NOT DISTINCT FROM e.close
    AND a.volume IS NOT DISTINCT FROM e.volume AND a.ticks = e.ticks
    AND ((a.vwap IS NULL AND e.vwap IS NULL) OR abs(a.vwap - e.vwap) <= 1e-12)))
FROM actual a JOIN expected e USING (kind, bar_id);

-- Bars per asset: equal timestamps are ordered by seq_col when given, else by price then volume.
SELECT
  assert_eq('tick bars per asset count', count(*), 5::BIGINT),
  assert_eq('tick bars tie order without seq', list(close ORDER BY bar_id) FILTER (WHERE sym = 'X'), [11.0, 11.5, 11.0]),
  assert_near('tick bars volume and vwap', max(vwap) FILTER (WHERE sym = 'X' AND bar_id = 0), 155.0 / 15.0, 1e-12)
FROM fin_tick_bars('gold_ticks', 'ts', 'price', 2, asset_col := 'sym', volume_col := 'volume');

SELECT assert_eq('tick bars tie order with seq', list(close ORDER BY bar_id), [12.0, 11.5, 11.0])
FROM fin_tick_bars('(FROM gold_ticks WHERE sym = ''X'')', 'ts', 'price', 2, seq_col := 'seq');

SELECT
  assert_eq('volume bars per asset', list(volume ORDER BY sym, bar_id), [35.0, 40.0, 5.0, 6.0]),
  assert_near('volume bars per asset vwap', min(vwap) FILTER (WHERE sym = 'X' AND bar_id = 0), 395.0 / 35.0, 1e-12)
FROM fin_volume_bars('gold_ticks', 'ts', 'price', 'volume', 25, asset_col := 'sym');

SELECT
  assert_eq('signed imbalance bars', list(imbalance ORDER BY bar_id), [25.0, -40.0, 5.0]),
  assert_eq('signed imbalance traded volume', list(volume ORDER BY bar_id), [35.0, 40.0, 5.0])
FROM fin_imbalance_bars('(FROM gold_ticks WHERE sym = ''X'')', 'ts', 'price', 'signed_volume', 15);

SELECT assert_eq('tick rule imbalance bars', list(imbalance ORDER BY bar_id), [25.0, -40.0, -5.0])
FROM fin_imbalance_bars('(FROM gold_ticks WHERE sym = ''X'')', 'ts', 'price', 'volume', 15, 'tick_rule');

-- Exact multiples use a relative tolerance: ten volumes of 0.1 close a bar of 1.0.
SELECT assert_eq('volume bars relative epsilon', list(ticks ORDER BY bar_id), [10::BIGINT, 10, 10])
FROM fin_volume_bars('(SELECT TIMESTAMP ''2026-01-01'' + to_seconds(i) AS ts, 1.0 AS price, 0.1 AS volume FROM range(30) r(i))',
  'ts', 'price', 'volume', 1.0);

-- NULL timestamps and prices are skipped.
SELECT assert_eq('bars skip null rows', sum(ticks), 3::BIGINT)
FROM fin_tick_bars('(SELECT * FROM (VALUES (TIMESTAMP ''2026-01-01'', 1.0), (NULL, 2.0), (TIMESTAMP ''2026-01-02'', NULL), (TIMESTAMP ''2026-01-03'', 3.0), (TIMESTAMP ''2026-01-04'', 4.0)) t(ts, p))',
  'ts', 'p', 10);

CREATE TEMP TABLE gold_bar_order AS
SELECT (i % 13)::VARCHAR AS sym, TIMESTAMP '2026-01-01' + to_seconds(i // 40) AS ts,
  (100 + (i * 7919) % 1000 / 100.0)::DOUBLE AS price, (1 + (i * 104729) % 9)::DOUBLE AS volume
FROM range(30000) r(i)
ORDER BY hash(i);
SET threads = 1;
CREATE TEMP TABLE gold_bar_order_t1 AS
SELECT * FROM fin_volume_bars('gold_bar_order', 'ts', 'price', 'volume', 333, asset_col := 'sym');
SET threads = 8;
SELECT assert_eq('volume bars thread determinism', count(*), 0::BIGINT)
FROM (SELECT * FROM fin_volume_bars('gold_bar_order', 'ts', 'price', 'volume', 333, asset_col := 'sym')
      EXCEPT SELECT * FROM gold_bar_order_t1);
SELECT assert_eq('imbalance bars thread determinism', count(*), 0::BIGINT)
FROM (SELECT * FROM fin_imbalance_bars('gold_bar_order', 'ts', 'price', 'volume', 50, 'tick_rule', asset_col := 'sym')
      EXCEPT SELECT * FROM fin_imbalance_bars('(FROM gold_bar_order ORDER BY ts DESC)', 'ts', 'price', 'volume', 50,
        'tick_rule', asset_col := 'sym'));
RESET threads;

SELECT assert_eq('tick threshold overload equivalence',
  (SELECT list(struct_pack(start_ts, end_ts, open, high, low, close, volume, vwap) ORDER BY start_ts)
   FROM fin_tick_bars('gold_prices', 'ts', 'close', 2::INTEGER)),
  (SELECT list(struct_pack(start_ts, end_ts, open, high, low, close, volume, vwap) ORDER BY start_ts)
   FROM fin_tick_bars('gold_prices', 'ts', 'close', 2::BIGINT)));

SELECT assert_eq('tick omitted threshold equals explicit default',
  (SELECT list(struct_pack(start_ts, end_ts, open, high, low, close, volume, vwap) ORDER BY start_ts)
   FROM fin_tick_bars('gold_prices', 'ts', 'close')),
  (SELECT list(struct_pack(start_ts, end_ts, open, high, low, close, volume, vwap) ORDER BY start_ts)
   FROM fin_tick_bars('gold_prices', 'ts', 'close', 100)));

SELECT assert_eq('grid rows', count(*), 5::BIGINT)
FROM fin_resample_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute',
  'last',
  INTERVAL '10 minutes'
);

SELECT assert_eq('grid staleness nulls stale samples', count(*) FILTER (WHERE value IS NULL), 1::BIGINT)
FROM fin_resample_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:31:00',
  INTERVAL '30 seconds',
  'last',
  INTERVAL '29 seconds'
);

SELECT assert_eq('last grid rows', count(*), 5::BIGINT)
FROM fin_last_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute'
);

SELECT assert_eq('delta grid rows', count(*), 5::BIGINT)
FROM fin_delta_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute'
);

SELECT assert_eq('rate grid rows', count(*), 5::BIGINT)
FROM fin_rate_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute'
);

SELECT assert_eq('changes grid rows', count(*), 5::BIGINT)
FROM fin_changes_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute'
);

SELECT assert_eq('resets grid rows', count(*), 5::BIGINT)
FROM fin_resets_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute'
);

SELECT assert_eq('predict grid rows', count(*), 5::BIGINT)
FROM fin_predict_linear_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00',
  TIMESTAMP '2026-01-02 09:34:00',
  INTERVAL '1 minute',
  INTERVAL '3 minutes'
);

-- Least-squares fit over (g - 3 minutes, g], predicted one minute ahead (numpy.polyfit reference).
SELECT
  assert_eq('predict linear needs two samples', list(value ORDER BY ts)[1], NULL),
  assert_near('predict linear two samples', list(value ORDER BY ts)[2], 104.0, 1e-9),
  assert_near('predict linear three samples', list(value ORDER BY ts)[3], 99.33333333333333, 1e-9),
  assert_near('predict linear window slides', list(value ORDER BY ts)[4], 103.66666666666666, 1e-9),
  assert_near('predict linear last', list(value ORDER BY ts)[5], 106.0, 1e-9)
FROM fin_predict_linear_to_grid(
  'gold_prices', 'ts', 'close',
  TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute',
  INTERVAL '3 minutes', INTERVAL '1 minute'
);

-- Grid siblings compare consecutive grid samples; the first sample has no predecessor.
SELECT
  assert_eq('delta grid values', (SELECT list(value ORDER BY ts) FROM fin_delta_to_grid('gold_prices', 'ts', 'close',
    TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')), [NULL, 2.0, -3.0, 5.0, -1.0]),
  assert_near('rate grid per second', (SELECT list(value ORDER BY ts)[3] FROM fin_rate_to_grid('gold_prices', 'ts', 'close',
    TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')), -3.0 / 60.0, 1e-15),
  assert_eq('changes grid values', (SELECT list(value ORDER BY ts) FROM fin_changes_to_grid('gold_prices', 'ts', 'close',
    TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')), [NULL, 1.0, 1.0, 1.0, 1.0]),
  assert_eq('resets grid values', (SELECT list(value ORDER BY ts) FROM fin_resets_to_grid('gold_prices', 'ts', 'close',
    TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')), [NULL, 0.0, 1.0, 0.0, 1.0]),
  assert_eq('changes grid type', (SELECT typeof(any_value(value)) FROM fin_changes_to_grid('gold_prices', 'ts', 'close',
    TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')), 'DOUBLE');

-- Per-asset grids; duplicate timestamps keep the largest seq_col, else the largest value.
SELECT
  assert_eq('grid per asset rows', count(*), 10::BIGINT),
  assert_eq('grid duplicate ts without seq', list(value ORDER BY ts) FILTER (WHERE sym = 'X'), [10.0, 12.0, 12.0, 11.5, 11.0]),
  assert_eq('grid asset keyed asof', list(value ORDER BY ts) FILTER (WHERE sym = 'Y'), [50.0, 50.0, 49.0, 49.0, 51.0])
FROM fin_resample_grid('gold_ticks', 'ts', 'price',
  TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:30:04', INTERVAL '1 second', asset_col := 'sym');

SELECT assert_eq('grid duplicate ts with seq', list(value ORDER BY ts), [10.0, 11.0, 11.0, 11.5, 11.0])
FROM fin_last_to_grid('(FROM gold_ticks WHERE sym = ''X'')', 'ts', 'price',
  TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:30:04', INTERVAL '1 second', seq_col := 'seq');

-- Month steps are anchored at start_ts (start + i * step).
SELECT assert_eq('grid month anchored', list(ts ORDER BY ts),
  [TIMESTAMP '2026-01-31', TIMESTAMP '2026-02-28', TIMESTAMP '2026-03-31'])
FROM fin_resample_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-31', TIMESTAMP '2026-03-31', INTERVAL '1 month');

-- NULL values do not overwrite the carried sample.
SELECT assert_eq('grid skips null values', list(value ORDER BY ts), [1.0, 1.0])
FROM fin_resample_grid('(SELECT * FROM (VALUES (TIMESTAMP ''2026-01-01 00:00:00'', 1.0), (TIMESTAMP ''2026-01-01 00:00:01'', NULL)) t(ts, v))',
  'ts', 'v', TIMESTAMP '2026-01-01 00:00:00', TIMESTAMP '2026-01-01 00:00:01', INTERVAL '1 second');

CREATE TEMP TABLE gold_grid_order AS
SELECT (i % 5)::VARCHAR AS sym, TIMESTAMP '2026-01-01' + to_seconds(i // 20) AS ts, ((i * 7919) % 1000)::DOUBLE AS x
FROM range(20000) r(i)
ORDER BY hash(i);
SET threads = 1;
CREATE TEMP TABLE gold_grid_order_t1 AS
SELECT * FROM fin_delta_to_grid('gold_grid_order', 'ts', 'x', TIMESTAMP '2026-01-01', TIMESTAMP '2026-01-01 00:16:39',
  INTERVAL '1 second', asset_col := 'sym');
SET threads = 8;
SELECT assert_eq('grid thread determinism', count(*), 0::BIGINT)
FROM (SELECT * FROM fin_delta_to_grid('gold_grid_order', 'ts', 'x', TIMESTAMP '2026-01-01', TIMESTAMP '2026-01-01 00:16:39',
        INTERVAL '1 second', asset_col := 'sym')
      EXCEPT SELECT * FROM gold_grid_order_t1);
RESET threads;
