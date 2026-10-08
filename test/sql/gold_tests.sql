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
SELECT assert_eq('release version', fin_version(), 'finance 0.2.22');

-- Repository sweep regressions: NULLs must never be read as native values.
SELECT
  assert_near('irr tiny amounts', fin_irr([-1e-20, 2e-20]), 1.0, 1e-10),
  assert_near('irr large amounts', fin_irr([-1e200, 2e200]), 1.0, 1e-10),
  assert_near('xirr tiny amounts', fin_xirr([-1e-20, 2e-20], [DATE '2025-01-01', DATE '2026-01-01']), 1.0, 1e-10),
  assert_eq('npv invalid periodic base', fin_npv(-2, [-100, 110]), NULL),
  assert_eq('mirr invalid finance base', fin_mirr([-100, 110], -2, 0.1), NULL),
  assert_eq('mirr invalid reinvest base', fin_mirr([-100, 110], 0.1, -2), NULL),
  assert_eq('annuity invalid timing', fin_annuity_payment(0.05, 10, 100, 0, 'typo'), NULL),
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
  assert_eq('bond unknown duration kind', fin_bond_duration(0.05, 0.04, 5, 2, 100, 'typo'), NULL),
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

-- A recursive Wilder recurrence independently checks seed and tail handling.
WITH RECURSIVE prices AS (
  SELECT period, i, 100+sin(i::DOUBLE)*5 AS px
  FROM (VALUES (1),(2),(14),(200)) p(period), range(120) t(i)
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

-- Moving windows combine both partially seeded states and affine tails.
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
SELECT assert_true('rsi affine window oracle', bool_and(coalesce(abs(rsi-
  CASE WHEN loss=0 THEN 100 ELSE 100-100/(1+gain/loss) END)<1e-10,false))) FROM refs;

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
  assert_eq('round to tick rejects unknown mode', fin_round_to_tick(100.037, 0.05, 'typo'), NULL),
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
         (NULL, 900.0), (900.0, NULL), ('Infinity'::DOUBLE, 8.0),
         (8.0, 'NaN'::DOUBLE)
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

WITH fitted AS (
  SELECT fin_linear_trend(y) AS t FROM (VALUES (2.0), (4.0), (NULL)) p(y)
)
SELECT assert_eq('trend fallback slope', t.slope, NULL),
       assert_near('trend fallback mean', t.intercept, 3.0, 1e-12),
       assert_eq('trend fallback r2', t.r2, NULL),
       assert_eq('trend fallback stderr', t.stderr, NULL)
FROM fitted;

WITH fitted AS (
  SELECT fin_linear_trend(y, x := x) AS t
  FROM (VALUES (NULL::DOUBLE, 2.0), (NULL, 4.0), (NULL, NULL)) p(x, y)
)
SELECT assert_eq('trend all null axis slope', t.slope, NULL),
       assert_near('trend all null axis mean', t.intercept, 3.0, 1e-12),
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
  assert_eq('ks placeholder', fin_ks_test(r, benchmark_r), NULL),
  assert_eq('mann whitney placeholder', fin_mann_whitney_u(r, benchmark_r), NULL),
  assert_eq('anova placeholder', fin_anova_oneway(r, asset), NULL),
  assert_not_null('ttest 1 sample stat', (fin_ttest_1samp(r, 0.0)).stat),
  assert_not_null('ttest 2 sample stat', (fin_ttest_2samp(r, benchmark_r)).stat),
  assert_not_null('welch ttest stat', (fin_welch_ttest(r, benchmark_r)).stat),
  assert_not_null('ztest mean', fin_ztest_mean(r, 0.0)),
  assert_not_null('entropy', fin_entropy(asset)),
  assert_not_null('rank corr', fin_rank_corr(r, benchmark_r)),
  assert_eq('mutual information placeholder', fin_mutual_information(r, benchmark_r), NULL),
  assert_eq('cramers v placeholder', fin_cramers_v(asset, asset), NULL),
  assert_eq('theils u placeholder', fin_theils_u(asset, asset), NULL)
FROM gold_returns;

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

SELECT
  assert_near('delta aggregate', fin_delta(close), 3.0, 1e-12),
  assert_near('pct change aggregate', fin_pct_change(close), 0.03, 1e-12),
  assert_not_null('rate aggregate', fin_rate(close, ts)),
  assert_eq('changes aggregate', fin_changes(close), 4::BIGINT),
  assert_eq('resets aggregate', fin_resets(close - 100.0), 1::BIGINT),
  assert_eq('last non null', fin_last_non_null(close), 103.0),
  assert_eq('first non null', fin_first_non_null(close), 100.0),
  assert_near('ema default recurrence', fin_ema(close ORDER BY seq), 100.69349705112582, 1e-12),
  assert_near('ema halflife alias', fin_ema_halflife(close, ts, INTERVAL '1 minute'), 101.6, 1e-12),
  assert_near('exp decay sum alias', fin_exp_decay_sum(close, ts, INTERVAL '1 minute'), 508.0, 1e-12),
  assert_near('exp decay avg alias', fin_exp_decay_avg(close, ts, INTERVAL '1 minute'), 101.6, 1e-12),
  assert_eq('exp decay count alias', fin_exp_decay_count(ts, INTERVAL '1 minute'), 5::BIGINT),
  assert_eq('exp decay max alias', fin_exp_decay_max(close, ts, INTERVAL '1 minute'), 104.0),
  assert_not_null('rolling zscore', fin_rolling_zscore(close, seq)),
  assert_not_null('autocorr alias', fin_autocorr(close)),
  assert_not_null('crosscorr alias', fin_crosscorr(close, volume)),
  assert_near('hurst placeholder', fin_hurst(close), 0.5, 1e-12),
  assert_eq('half life placeholder', fin_half_life_mean_reversion(close), NULL),
  assert_eq('linear trend omitted axis compatibility', (fin_linear_trend(close)).slope, NULL),
  assert_eq('adf placeholder', fin_adf(close), NULL),
  assert_eq('ljung box placeholder', fin_ljung_box(close), NULL)
FROM gold_prices;

SELECT
  assert_near('sma alias', fin_sma(close), 101.6, 1e-12),
  assert_near('wma alias', fin_wma(close), 101.6, 1e-12),
  assert_near('dema alias', fin_dema(close), 101.6, 1e-12),
  assert_near('tema alias', fin_tema(close), 101.6, 1e-12),
  assert_near('trima alias', fin_trima(close), 101.6, 1e-12),
  assert_near('t3 alias', fin_t3(close), 101.6, 1e-12),
  assert_near('kama alias', fin_kama(close), 101.6, 1e-12),
  assert_near('hma alias', fin_hma(close), 101.6, 1e-12),
  assert_near('linearreg alias', fin_linearreg(close), 101.6, 1e-12),
  assert_eq('linearreg slope placeholder', fin_linearreg_slope(close), NULL),
  assert_near('linearreg intercept alias', fin_linearreg_intercept(close), 101.6, 1e-12),
  assert_near('tsf alias', fin_tsf(close), 101.6, 1e-12),
  assert_near('momentum', fin_mom(close), 3.0, 1e-12),
  assert_near('roc', fin_roc(close), 3.0, 1e-12),
  assert_near('rocp', fin_rocp(close), 0.03, 1e-12),
  assert_near('rocr', fin_rocr(close), 1.03, 1e-12),
  assert_near('rocr100', fin_rocr100(close), 103.0, 1e-12)
FROM gold_prices;

SELECT
  assert_near('rsi', fin_rsi(close ORDER BY ts), 63.63636363636363, 1e-12),
  assert_near('rsi honors period', fin_rsi(close, 2 ORDER BY ts), 63.15789473684211, 1e-12),
  assert_near('macd placeholder', (fin_macd(close)).macd, 0.0, 1e-12),
  assert_near('ppo placeholder', fin_ppo(close), 0.0, 1e-12),
  assert_near('apo placeholder', fin_apo(close), 0.0, 1e-12),
  assert_near('trix alias', fin_trix(close), 0.03, 1e-12),
  assert_near('cmo direction', fin_cmo(close), 100.0, 1e-12),
  assert_not_null('stoch', (fin_stoch(high, low, close)).k),
  assert_not_null('willr', fin_willr(high, low, close)),
  assert_not_null('ultosc', fin_ultosc(high, low, close)),
  assert_not_null('cci', fin_cci(high, low, close)),
  assert_not_null('mfi', fin_mfi(high, low, close, volume)),
  assert_near('true range', fin_true_range(high, low, close), 7.0, 1e-12),
  assert_not_null('atr', fin_atr(high, low, close)),
  assert_not_null('natr', fin_natr(high, low, close))
FROM gold_prices;

SELECT
  assert_not_null('stochrsi alias', (fin_stochrsi(close)).k)
FROM gold_prices;

SELECT
  assert_not_null('bbands middle', (fin_bbands(close)).middle),
  assert_not_null('keltner middle', (fin_keltner(high, low, close)).middle),
  assert_not_null('donchian middle', (fin_donchian(high, low)).middle),
  assert_not_null('stddev indicator', fin_stddev(close)),
  assert_not_null('var indicator', fin_var_indicator(close)),
  assert_not_null('adx alias', fin_adx(high, low, close)),
  assert_not_null('adxr alias', fin_adxr(high, low, close)),
  assert_not_null('dx alias', fin_dx(high, low, close)),
  assert_not_null('plus di', fin_plus_di(high, low, close)),
  assert_not_null('minus di', fin_minus_di(high, low, close)),
  assert_not_null('plus dm', fin_plus_dm(high, low)),
  assert_not_null('minus dm', fin_minus_dm(high, low)),
  assert_near('aroon placeholder', (fin_aroon(high, low)).oscillator, 0.0, 1e-12),
  assert_near('aroonosc placeholder', fin_aroonosc(high, low), 0.0, 1e-12),
  assert_not_null('sar alias', fin_sar(high, low)),
  assert_not_null('sarext alias', fin_sarext(high, low, NULL))
FROM gold_prices;

SELECT
  assert_not_null('obv', fin_obv(close, volume)),
  assert_not_null('ad line', fin_ad_line(high, low, close, volume)),
  assert_not_null('adosc alias', fin_adosc(high, low, close, volume)),
  assert_not_null('vwap', fin_vwap(close, volume)),
  assert_not_null('twap', fin_twap(close, ts)),
  assert_not_null('volume profile', fin_volume_profile(close, volume)),
  assert_not_null('bop', fin_bop(open, high, low, close)),
  assert_not_null('ohlc close', (fin_ohlc(close)).close),
  assert_not_null('ohlcv vwap', (fin_ohlcv(close, volume)).vwap),
  assert_not_null('amihud', fin_amihud_illiquidity(abs(close - open), close * volume)),
  assert_not_null('roll spread', fin_roll_spread(close)),
  assert_not_null('kyle lambda', fin_kyle_lambda(volume, close - open)),
  assert_not_null('vpin', fin_vpin(volume, volume))
FROM gold_prices;

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

WITH iv_path(seq, iv) AS (VALUES (1, 0.10), (2, 0.20), (3, 0.15))
SELECT
  assert_near('iv rank respects ascending aggregate order', fin_iv_rank(iv ORDER BY iv), 1.0, 1e-12),
  assert_near('iv rank respects descending aggregate order', fin_iv_rank(iv ORDER BY iv DESC), 0.0, 1e-12),
  assert_near('iv percentile respects ascending aggregate order', fin_iv_percentile(iv ORDER BY iv), 1.0, 1e-12),
  assert_near('iv percentile respects descending aggregate order', fin_iv_percentile(iv ORDER BY iv DESC), 0.0, 1e-12)
FROM iv_path;

-- Second sweep: exponential weighting and empirical percentiles have their
-- own independent expectations, including ordering, NULLs, ties and windows.
WITH path(i, x) AS (VALUES (1, 10.0), (2, 20.0), (3, NULL), (4, 40.0))
SELECT
  assert_near('ema default period', fin_ema(x ORDER BY i), 13.718820861678005, 1e-12),
  assert_near('ema period three', fin_ema(x, 3 ORDER BY i), 27.5, 1e-12),
  assert_near('ema named period', fin_ema(x, period := 3 ORDER BY i), 27.5, 1e-12),
  assert_near('ema reverse order', fin_ema(x, 3 ORDER BY i DESC), 20.0, 1e-12),
  assert_near('ema period one', fin_ema(x, 1 ORDER BY i), 40.0, 1e-12),
  assert_near('ema filtered rows', fin_ema(x, 3 ORDER BY i) FILTER (WHERE i <> 2), 25.0, 1e-12),
  assert_near('ema subset without ordering', fin_ema(x, 3) FILTER (WHERE i = 2), 20.0, 1e-12)
FROM path;

SELECT
  assert_eq('ema empty', fin_ema(x), NULL),
  assert_eq('iv percentile empty', fin_iv_percentile(x), NULL)
FROM (SELECT NULL::DOUBLE AS x WHERE false);

SELECT
  assert_eq('ema null input', fin_ema(NULL::DOUBLE), NULL),
  assert_eq('ema null period', fin_ema(10.0, NULL), NULL),
  assert_eq('iv percentile singleton', fin_iv_percentile(0.2), NULL);

WITH path(i, x) AS (VALUES (1, 10.0), (2, 20.0), (3, 40.0)), results AS (
  SELECT i, fin_ema(x, 3) OVER (ORDER BY i ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS ema
  FROM path
)
SELECT assert_true('ema sliding window reseeds', bool_and(ema = CASE i WHEN 1 THEN 10 WHEN 2 THEN 15 ELSE 30 END))
FROM results;

SELECT
  assert_near('ema constant batch default', fin_ema(7.0), 7.0, 1e-12),
  assert_near('ema constant batch period one', fin_ema(7.0, 1), 7.0, 1e-12),
  assert_near('ema extreme finite constant', fin_ema(1.7e308)/1.7e308, 1.0, 1e-12)
FROM range(10000);

SELECT assert_near('ema avoids extreme subtraction overflow', fin_ema(x, 3 ORDER BY i), 0.0, 0.0)
FROM (VALUES (1, -1e308), (2, 1e308)) t(i,x);

WITH path AS (SELECT i, CASE WHEN i = 0 THEN 1e200 ELSE 0.0 END AS x FROM range(1501) t(i))
SELECT
  assert_near('ema decay preserves finite late value', fin_ema(x,3 ORDER BY i)/(1e200*pow(2.0,-1000)), pow(2.0,-500), 1e-162),
  assert_near('ewma decay preserves finite late volatility', fin_ewma_vol(x,0.5,1 ORDER BY i)/1e200, pow(2.0,-750), 1e-237)
FROM path;

SELECT assert_near('ewma tiny lambda retains past contribution', fin_ewma_vol(x,1e-300,1 ORDER BY i)/1e50, 1.0, 1e-12)
FROM (VALUES (1,1e200),(2,0.0)) t(i,x);

SELECT assert_near('ewma repeated tiny lambda preserves decay', fin_ewma_vol(x,1e-190,1 ORDER BY i)/1e118, 1.0, 1e-12)
FROM (VALUES (1,1e308),(2,0.0),(3,0.0)) t(i,x);

SELECT assert_near('ema cancellation releases scale', fin_ema(x,3 ORDER BY i)/1e-320, 0.5, 1e-3)
FROM (VALUES (1,0.0),(2,1e308),(3,-5e307),(4,1e-320)) t(i,x);

WITH path(i,x) AS (VALUES (1,-1e308),(2,1e308),(3,1e-320))
SELECT assert_near('ema cancellation before tiny observation', fin_ema(x,3 ORDER BY i)/1e-320, 0.5, 1e-3)
FROM path;

WITH path(i,x) AS (VALUES (1,-1e308),(2,1e308),(3,1e-320)), results AS (
  SELECT i, fin_ema(x,3) OVER (ORDER BY i ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ema FROM path
)
SELECT assert_near('ema window merge retains tiny correction', ema/1e-320, 0.5, 1e-3) FROM results WHERE i=3;

SELECT assert_eq('ema period one returns tiny latest value', fin_ema(x,1 ORDER BY i), 1e-320)
FROM (VALUES (1,1e308),(2,1e-320)) t(i,x);

WITH path AS (
  SELECT i, CASE WHEN i=8193 THEN -1e308 WHEN i=8194 THEN 1e308 WHEN i=8195 THEN 1e-320 ELSE 0.0 END AS x
  FROM range(8196) t(i)
), results AS (
  SELECT i, fin_ema(x,3) OVER (ORDER BY i ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ema FROM path
)
SELECT assert_near('ema segment tree retains cancellation residual', ema/1e-320, 0.5, 1e-3)
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
  assert_near('accrued interest half period', fin_accrued_interest(DATE '2026-04-01', DATE '2026-01-01', DATE '2026-07-01', 0.04, 100.0, 'ACT/365F'), 1.9889502762430937, 1e-12),
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
  assert_eq('min variance weights placeholder', fin_min_variance_weights([[0.04, 0.01], [0.01, 0.09]]), [0.5, 0.5]),
  assert_eq('risk parity weights placeholder', fin_risk_parity_weights([[0.04, 0.01], [0.01, 0.09]]), [0.5, 0.5]),
  assert_eq('max sharpe weights placeholder', fin_max_sharpe_weights([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]]), [0.5, 0.5]),
  assert_eq('black litterman returns placeholder', fin_black_litterman_returns([0.6, 0.4], [[0.04, 0.01], [0.01, 0.09]], [[1.0, 0.0]], [0.1]), [0.6, 0.4]);

SELECT
  assert_not_null('cov matrix placeholder', fin_cov_matrix(asset, r)),
  assert_not_null('corr matrix placeholder', fin_corr_matrix(asset, r)),
  assert_eq('ols beta placeholder', (fin_ols(r, [factor])).beta, NULL),
  assert_eq('ols no intercept beta placeholder', (fin_ols_no_intercept(r, [factor])).beta, NULL),
  assert_not_null('rolling beta', fin_rolling_beta(r, benchmark_r)),
  assert_not_null('factor alpha', fin_factor_alpha(r, benchmark_r)),
  assert_not_null('factor ic', fin_factor_ic(factor, forward_return)),
  assert_not_null('rank ic', fin_rank_ic(factor, forward_return)),
  assert_not_null('factor turnover', fin_factor_turnover(factor)),
  assert_eq('newey west placeholder', fin_newey_west_tstat(r, factor), NULL)
FROM gold_returns;

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
  assert_eq('binomial rejects unsupported exercise', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'bermudan', 'crr'), NULL),
  assert_eq('binomial zero vol rejects unsupported exercise', fin_binomial_price('call', 100.0, 90.0, 1.0, 0.05, 0.0, 0.0, 20, 'bermudan', 'crr'), NULL),
  assert_eq('binomial rejects unknown tree', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'european', 'typo'), NULL),
  assert_eq('binomial zero vol rejects unknown tree', fin_binomial_price('call', 100.0, 90.0, 1.0, 0.05, 0.0, 0.0, 20, 'european', 'typo'), NULL),
  assert_eq('binomial caps excessive work', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 4097), NULL);

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

SELECT assert_eq('validate schema rows', count(*), 7::BIGINT)
FROM fin_validate_schema('gold_prices', 'ohlcv');

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

SELECT assert_eq('bootstrap curve rows', count(*), 3::BIGINT)
FROM fin_bootstrap_curve('gold_curve', 'inst', 'maturity', 'rate', 'continuous');

SELECT assert_near('bootstrap curve periodic compounding', discount_factor, fin_discount_factor(0.040, 0.5, 'periodic'), 1e-12)
FROM fin_bootstrap_curve('gold_curve', 'inst', 'maturity', 'rate', 'periodic')
WHERE instrument = 'bill';

SELECT assert_eq('curve bootstrap rows', count(*), 3::BIGINT)
FROM fin_curve_bootstrap('gold_curve', 'inst', 'maturity', 'rate', 'continuous');

SELECT assert_eq('calendar rows', count(*), 3::BIGINT)
FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-06');

SELECT assert_eq('hrp weight rows', count(*), 2::BIGINT)
FROM fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]], ['AAA', 'BBB'], 'single');

SELECT assert_eq('frontier default rows', count(*), 25::BIGINT)
FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]]);

SELECT assert_eq('optimizer full overload rows', count(*), 2::BIGINT)
FROM fin_portfolio_optimize([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 'max_sharpe', 0.0, true, 0.0, 1.0, 0.12, 0.2, 1.0);

SELECT assert_eq('optimizer table rows', count(*), 2::BIGINT)
FROM fin_portfolio_optimize_table('gold_current_weights', 'asset', 'weight', 'weight');

SELECT assert_eq('factor report rows', count(*), 1::BIGINT)
FROM fin_factor_report('gold_returns', 'd', 'asset', 'factor', 'forward_return', 2);

SELECT assert_eq('fama macbeth rows', count(*), 5::BIGINT)
FROM fin_fama_macbeth('gold_returns', 'd', 'asset', 'forward_return', ['factor'], 1);

SELECT assert_eq('garch fit rows', count(*), 1::BIGINT)
FROM fin_garch_fit('gold_returns', 'r', 1, 1, 'normal');

SELECT assert_eq('normalize returns rows', count(*), 5::BIGINT)
FROM fin_normalize_returns('gold_returns', 'd', 'asset', 'r');

SELECT assert_eq('normalize ohlcv rows', count(*), 5::BIGINT)
FROM fin_normalize_ohlcv('gold_prices', 'ts', 'open', 'high', 'low', 'close', 'volume');

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

SELECT assert_near('portfolio return table', portfolio_return, 0.14, 1e-12)
FROM fin_portfolio_return_table('gold_weighted_returns', 'asset', 'weight', 'expected_return');

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

SELECT assert_eq('tick bars default rows', count(*), 1::BIGINT)
FROM fin_tick_bars('gold_prices', 'ts', 'close');

SELECT assert_eq('volume bars rows', count(*), 5::BIGINT)
FROM fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 1000.0);

SELECT assert_eq('dollar bars rows', count(*), 5::BIGINT)
FROM fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 100000.0);

SELECT assert_eq('imbalance bars rows', count(*), 5::BIGINT)
FROM fin_imbalance_bars('gold_prices', 'ts', 'close', 'volume', 'signed');

-- Full rows protect threshold bucketing, time order, OHLC, volume and VWAP.
WITH actual AS (
  SELECT 'tick' AS kind, row_number() OVER (ORDER BY start_ts, end_ts) AS seq, *
  FROM fin_tick_bars('gold_prices', 'ts', 'close', 2::BIGINT)
  UNION ALL
  SELECT 'volume', row_number() OVER (ORDER BY start_ts, end_ts), *
  FROM fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 3000.0)
  UNION ALL
  SELECT 'dollar', row_number() OVER (ORDER BY start_ts, end_ts), *
  FROM fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 300000.0)
), expected(kind, seq, start_ts, end_ts, open, high, low, close, volume, vwap) AS (
  VALUES
    ('tick', 1, TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:31:00',
     100.0, 102.0, 100.0, 102.0, 2.0, 101.0),
    ('tick', 2, TIMESTAMP '2026-01-02 09:32:00', TIMESTAMP '2026-01-02 09:33:00',
     99.0, 104.0, 99.0, 104.0, 2.0, 101.5),
    ('tick', 3, TIMESTAMP '2026-01-02 09:34:00', TIMESTAMP '2026-01-02 09:34:00',
     103.0, 103.0, 103.0, 103.0, 1.0, 103.0),
    ('volume', 1, TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:31:00',
     100.0, 102.0, 100.0, 102.0, 2500.0, 101.2),
    ('volume', 2, TIMESTAMP '2026-01-02 09:32:00', TIMESTAMP '2026-01-02 09:32:00',
     99.0, 99.0, 99.0, 99.0, 2000.0, 99.0),
    ('volume', 3, TIMESTAMP '2026-01-02 09:33:00', TIMESTAMP '2026-01-02 09:34:00',
     104.0, 104.0, 103.0, 103.0, 3000.0, 103.6),
    ('dollar', 1, TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:31:00',
     100.0, 102.0, 100.0, 102.0, 2500.0, 101.2),
    ('dollar', 2, TIMESTAMP '2026-01-02 09:32:00', TIMESTAMP '2026-01-02 09:32:00',
     99.0, 99.0, 99.0, 99.0, 2000.0, 99.0),
    ('dollar', 3, TIMESTAMP '2026-01-02 09:33:00', TIMESTAMP '2026-01-02 09:34:00',
     104.0, 104.0, 103.0, 103.0, 3000.0, 103.6)
)
SELECT
  assert_eq('bar full row count', (SELECT count(*) FROM actual), 9::BIGINT),
  assert_eq('bar full row keys', count(*), 9::BIGINT),
  assert_true('bar full row values', bool_and(
    a.start_ts IS NOT DISTINCT FROM e.start_ts AND a.end_ts IS NOT DISTINCT FROM e.end_ts
    AND a.open IS NOT DISTINCT FROM e.open AND a.high IS NOT DISTINCT FROM e.high
    AND a.low IS NOT DISTINCT FROM e.low AND a.close IS NOT DISTINCT FROM e.close
    AND a.volume IS NOT DISTINCT FROM e.volume
    AND a.vwap IS NOT NULL AND abs(a.vwap - e.vwap) <= 1e-12))
FROM actual a JOIN expected e USING (kind, seq);

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
  INTERVAL '1 minute'
);
