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
SELECT assert_eq('release version', fin_version(), 'finance 0.2.15');

-- Numerical helpers and scalar edge cases.
SELECT
  assert_near('normal pdf', fin_norm_pdf(0.0), 0.3989422804014327, 1e-12),
  assert_near('normal cdf', fin_norm_cdf(0.0), 0.5, 1e-12),
  assert_near('normal inv', fin_norm_inv(0.5), 0.0, 1e-12),
  assert_near('student t symmetry', fin_student_t_cdf(0.0, 10.0), 0.5, 1e-12),
  assert_near('student t inv median', fin_student_t_inv(0.5, 10.0), 0.0, 1e-10),
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
  assert_near('price from log return', fin_price_from_return(100.0, ln(1.02), 'log'), 102.0, 1e-12);

-- Aggregate return and risk metrics over the gold return series.
SELECT
  assert_near('total return', fin_total_return(r), 0.02961247795, 1e-12),
  assert_near('cagr', fin_cagr(r, 252), 3.3527064365220456, 1e-12),
  assert_near('annual return', fin_annual_return(r, 252), 3.3527064365220456, 1e-12),
  assert_near('arithmetic return', fin_arithmetic_return(r), 0.006, 1e-12),
  assert_near('geometric return', fin_geometric_return(r), 0.005853564836320935, 1e-12),
  assert_near('volatility', fin_volatility(r), 0.3043189116699782, 1e-12),
  assert_near('calmar', fin_calmar(r), 167.63532182610227, 1e-10),
  assert_near('sortino', fin_sortino(r), 10.330992777303926, 1e-12),
  assert_near('sortino optional args', fin_sortino(r, 0.01, 365.0), 12.35665863411524, 1e-12),
  assert_near('max drawdown', fin_max_drawdown(r), -0.02, 1e-12),
  assert_near('avg drawdown', fin_avg_drawdown(r), -0.005, 1e-12),
  assert_eq('drawdown duration', fin_drawdown_duration(r), 1::BIGINT),
  assert_near('ulcer index', fin_ulcer_index(r), 0.009219544457292884, 1e-12),
  assert_near('beta', fin_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_near('tracking error', fin_tracking_error(r, benchmark_r), 0.13535287215275485, 1e-12),
  assert_near('quantile spread', fin_quantile_spread(factor, forward_return, 2), 0.009, 1e-12)
FROM gold_returns;

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
  assert_near('log nav', fin_log_nav(r, 100.0), 102.961247795, 1e-9),
  assert_near('recovery factor', fin_recovery_factor(r), 1.4806238975, 1e-10),
  assert_near('gain to pain', fin_gain_to_pain(r), 2.2, 1e-12),
  assert_near('aggregate return', fin_aggregate_return(r, d), 0.02961247795, 1e-12),
  assert_near('downside deviation', fin_downside_deviation(r), 0.14635573101180563, 1e-12),
  assert_near('upside deviation', fin_upside_deviation(r), 0.24847535089018388, 1e-12),
  assert_near('semivariance', fin_semivariance(r), 0.000085, 1e-12),
  assert_not_null('sharpe', fin_sharpe(r)),
  assert_near('omega ratio', fin_omega_ratio(r), 2.2, 1e-12),
  assert_not_null('tail ratio', fin_tail_ratio(r)),
  assert_near('stability placeholder', fin_stability(r), 0.0, 1e-12),
  assert_not_null('information ratio', fin_information_ratio(r, benchmark_r)),
  assert_near('active return', fin_active_return(r, benchmark_r), -0.20160000000000017, 1e-12),
  assert_not_null('alpha', fin_alpha(r, benchmark_r)),
  assert_near('alpha beta beta', (fin_alpha_beta(r, benchmark_r)).beta, 1.6964285714285716, 1e-12),
  assert_not_null('treynor', fin_treynor_ratio(r, benchmark_r)),
  assert_not_null('jensen', fin_jensen_alpha(r, benchmark_r)),
  assert_not_null('up capture', fin_up_capture(r, benchmark_r)),
  assert_not_null('down capture', fin_down_capture(r, benchmark_r)),
  assert_near('hit ratio', fin_hit_ratio(r), 0.6, 1e-12),
  assert_near('win rate', fin_win_rate(r), 0.6, 1e-12),
  assert_near('loss rate', fin_loss_rate(r), 0.4, 1e-12),
  assert_near('payoff ratio', fin_payoff_ratio(r), 1.4666666666666666, 1e-12),
  assert_near('profit factor', fin_profit_factor(r), 2.2, 1e-12),
  assert_near('expectancy', fin_expectancy(r), 0.006, 1e-12),
  assert_not_null('var', fin_var(r)),
  assert_not_null('cvar alias', fin_cvar(r)),
  assert_not_null('expected shortfall alias', fin_expected_shortfall(r)),
  assert_near('drawdown direct', fin_drawdown(r), -0.005, 1e-12),
  assert_not_null('drawdown at risk', fin_drawdown_at_risk(r)),
  assert_not_null('conditional drawdown at risk', fin_conditional_drawdown_at_risk(r)),
  assert_not_null('parametric var', fin_parametric_var(0.0, 0.2, 0.95)),
  assert_not_null('parametric cvar', fin_parametric_cvar(0.0, 0.2, 0.95))
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
  assert_not_null('garch forecast', fin_garch11_forecast(r, 0.000001, 0.05, 0.90))
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
  assert_not_null('garman klass vol', fin_garman_klass_vol(open, high, low, close, 252.0)),
  assert_not_null('rogers satchell vol', fin_rogers_satchell_vol(open, high, low, close, 252.0)),
  assert_not_null('yang zhang vol', fin_yang_zhang_vol(open, high, low, close, 252.0))
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
  assert_not_null('zscore last', fin_zscore_last(r)),
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

SELECT
  assert_near('weighted median honors weights', fin_weighted_quantile(x, w, 0.5), 1.0, 1e-12),
  assert_near('weighted inverted cdf', fin_weighted_quantile(x, w, 0.995, 'inverted_cdf'), 100.0, 1e-12)
FROM (VALUES (1.0, 100.0), (100.0, 1.0)) AS weighted_tail(x, w);

SELECT
  assert_near('winsorized mean honors bounds', fin_winsorized_mean(x, 0.0, 0.5), 0.0, 1e-12),
  assert_near('trimmed mean honors bounds', fin_trimmed_mean(x, 0.0, 0.5), 0.0, 1e-12)
FROM (VALUES (0.0), (0.0), (100.0)) AS robust_values(x);

SELECT
  assert_near('historical cvar tail mean', fin_cvar(r, 0.5), 7.5, 1e-12),
  assert_near('historical expected shortfall', fin_expected_shortfall(r, 0.5), 7.5, 1e-12),
  assert_near('historical cvar return sign', fin_cvar(r, 0.5, 'historical', false), -7.5, 1e-12)
FROM (VALUES (-10.0), (-5.0), (0.0), (5.0)) AS tail_returns(r);

SELECT
  assert_near('delta aggregate', fin_delta(close), 3.0, 1e-12),
  assert_near('pct change aggregate', fin_pct_change(close), 0.03, 1e-12),
  assert_not_null('rate aggregate', fin_rate(close, ts)),
  assert_eq('changes aggregate', fin_changes(close), 4::BIGINT),
  assert_eq('resets aggregate', fin_resets(close - 100.0), 1::BIGINT),
  assert_eq('last non null', fin_last_non_null(close), 103.0),
  assert_eq('first non null', fin_first_non_null(close), 100.0),
  assert_near('ema alias', fin_ema(close), 101.6, 1e-12),
  assert_near('ema halflife alias', fin_ema_halflife(close, ts, INTERVAL '1 minute'), 101.6, 1e-12),
  assert_near('exp decay sum alias', fin_exp_decay_sum(close, ts, INTERVAL '1 minute'), 508.0, 1e-12),
  assert_near('exp decay avg alias', fin_exp_decay_avg(close, ts, INTERVAL '1 minute'), 101.6, 1e-12),
  assert_eq('exp decay count alias', fin_exp_decay_count(ts, INTERVAL '1 minute'), 5::BIGINT),
  assert_eq('exp decay max alias', fin_exp_decay_max(close, ts, INTERVAL '1 minute'), 104.0),
  assert_not_null('rolling zscore', fin_rolling_zscore(close)),
  assert_not_null('autocorr alias', fin_autocorr(close)),
  assert_not_null('crosscorr alias', fin_crosscorr(close, volume)),
  assert_near('hurst placeholder', fin_hurst(close), 0.5, 1e-12),
  assert_eq('half life placeholder', fin_half_life_mean_reversion(close), NULL),
  assert_eq('linear trend slope placeholder', (fin_linear_trend(close)).slope, NULL),
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
  assert_true('matrix psd', fin_matrix_is_psd([[1.0, 0.2], [0.2, 1.0]])),
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
  assert_eq('binomial rejects unknown tree', fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'european', 'typo'), NULL),
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
