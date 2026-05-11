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

SELECT
  assert_near('realized variance', fin_realized_variance(r, 252), 0.08316, 1e-12),
  assert_near('realized vol', fin_realized_vol(r, 252), 0.28837475617674996, 1e-12),
  assert_near('bipower variation', fin_bipower_variation(r, 252), 0.10133521263419237, 1e-12),
  assert_near('realized quarticity', fin_realized_quarticity(r, 252), 0.0004331249999999999, 1e-12),
  assert_not_null('vol of vol', fin_vol_of_vol(abs(r), 252)),
  assert_near('realized beta', fin_realized_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_not_null('realized corr', fin_realized_corr(r, benchmark_r)),
  assert_not_null('realized cov', fin_realized_cov(r, benchmark_r)),
  assert_not_null('garch forecast', fin_garch11_forecast(r, 0.000001, 0.05, 0.90))
FROM gold_returns;

SELECT
  assert_not_null('parkinson vol', fin_parkinson_vol(high, low, 252.0)),
  assert_not_null('garman klass vol', fin_garman_klass_vol(open, high, low, close, 252.0)),
  assert_not_null('rogers satchell vol', fin_rogers_satchell_vol(open, high, low, close, 252.0)),
  assert_not_null('yang zhang vol', fin_yang_zhang_vol(open, high, low, close, 252.0))
FROM gold_prices;

-- GS Quant source-name compatibility aliases for portable timeseries helpers.
SELECT
  assert_near('gsq algebra add alias', fin_add(2.0, 3.0), 5.0, 1e-12),
  assert_near('gsq algebra subtract alias', fin_subtract(5.0, 3.0), 2.0, 1e-12),
  assert_near('gsq algebra multiply alias', fin_multiply(2.0, 3.0), 6.0, 1e-12),
  assert_near('gsq algebra divide alias', fin_divide(6.0, 3.0), 2.0, 1e-12),
  assert_near('gsq algebra floordiv alias', fin_floordiv(7.0, 3.0), 2.0, 1e-12),
  assert_near('gsq algebra exp alias', fin_exp(1.0), exp(1.0), 1e-12),
  assert_near('gsq algebra log alias', fin_log(exp(1.0)), 1.0, 1e-12),
  assert_near('gsq algebra power alias', fin_power(2.0, 3.0), 8.0, 1e-12),
  assert_near('gsq algebra sqrt alias', fin_sqrt(9.0), 3.0, 1e-12),
  assert_near('gsq algebra abs alias', fin_abs(-4.0), 4.0, 1e-12),
  assert_near('gsq algebra abs source alias', fin_abs_(-4.0), 4.0, 1e-12),
  assert_near('gsq algebra floor alias', fin_floor(5.7), 5.0, 1e-12),
  assert_near('gsq algebra ceil alias', fin_ceil(5.2), 6.0, 1e-12),
  assert_near('gsq algebra filter alias', fin_filter(5.0, '>', 4.0), 5.0, 1e-12),
  assert_near('gsq algebra filter source alias', fin_filter_(5.0, '>', 4.0), 5.0, 1e-12),
  assert_eq('gsq algebra filter miss alias', fin_filter(3.0, '>', 4.0), NULL),
  assert_true('gsq algebra not alias', fin_not(false)),
  assert_true('gsq algebra not source alias', fin_not_(false)),
  assert_eq('gsq algebra if alias', fin_if(true, 'x', 'y'), 'x'),
  assert_eq('gsq algebra if source alias', fin_if_(true, 'x', 'y'), 'x'),
  assert_eq('gsq filter dates placeholder', fin_filter_dates(7.0, '=', [DATE '2026-01-01']), 7.0);

SELECT
  assert_near('gsq stats min alias', fin_min(r), -0.02, 1e-12),
  assert_near('gsq stats min source alias', fin_min_(r), -0.02, 1e-12),
  assert_near('gsq stats max alias', fin_max(r), 0.03, 1e-12),
  assert_near('gsq stats max source alias', fin_max_(r), 0.03, 1e-12),
  assert_near('gsq stats range alias', fin_range(r), 0.05, 1e-12),
  assert_near('gsq stats range source alias', fin_range_(r), 0.05, 1e-12),
  assert_near('gsq stats mean alias', fin_mean(r), 0.006, 1e-12),
  assert_near('gsq stats median alias', fin_median(r), 0.01, 1e-12),
  assert_not_null('gsq stats mode alias', fin_mode(asset)),
  assert_near('gsq stats sum alias', fin_sum(r), 0.03, 1e-12),
  assert_near('gsq stats sum source alias', fin_sum_(r), 0.03, 1e-12),
  assert_near('gsq stats product alias', fin_product(1.0 + r), 1.02961247795, 1e-12),
  assert_not_null('gsq stats std alias', fin_std(r)),
  assert_not_null('gsq stats exponential std alias', fin_exponential_std(r)),
  assert_not_null('gsq stats zscores alias', fin_zscores(r)),
  assert_not_null('gsq stats winsorize placeholder', fin_winsorize(r)),
  assert_not_null('gsq stats percentiles alias', fin_percentiles(r)),
  assert_not_null('gsq stats percentile alias', fin_percentile(r, 0.5)),
  assert_near('gsq algebra weighted sum alias', fin_weighted_sum(r, factor), 0.095, 1e-12),
  assert_near('gsq algebra geometrically aggregate alias', fin_geometrically_aggregate(r), 0.02961247795, 1e-12),
  assert_true('gsq algebra and alias', fin_and(r IS NOT NULL)),
  assert_true('gsq algebra and source alias', fin_and_(r IS NOT NULL)),
  assert_true('gsq algebra or alias', fin_or(r > 0.02)),
  assert_true('gsq algebra or source alias', fin_or_(r > 0.02))
FROM gold_returns;

SELECT
  assert_near('gsq analysis smooth spikes placeholder', fin_smooth_spikes(close), 101.6, 1e-12),
  assert_near('gsq analysis smooth outliers placeholder', fin_smooth_outliers(close), 101.6, 1e-12),
  assert_near('gsq analysis repeat placeholder', fin_repeat(last(close), 2), 103.0, 1e-12),
  assert_near('gsq analysis first alias', fin_first(close), 100.0, 1e-12),
  assert_near('gsq analysis last alias', fin_last(close), 103.0, 1e-12),
  assert_near('gsq analysis last value alias', fin_last_value(close), 103.0, 1e-12),
  assert_eq('gsq analysis count alias', fin_count(close), 5::BIGINT),
  assert_near('gsq analysis diff alias', fin_diff(close), 3.0, 1e-12),
  assert_near('gsq analysis compare alias', fin_compare(105.0, 100.0), 5.0, 1e-12),
  assert_near('gsq analysis lag placeholder', fin_lag(close), 100.0, 1e-12),
  assert_eq('gsq analysis consecutive placeholder', fin_consecutive(close), 5::BIGINT)
FROM gold_prices;

SELECT
  assert_eq('gsq datetime day alias', fin_day(DATE '2026-05-07'), 7),
  assert_eq('gsq datetime month alias', fin_month(DATE '2026-05-07'), 5),
  assert_eq('gsq datetime year alias', fin_year(DATE '2026-05-07'), 2026),
  assert_eq('gsq datetime quarter alias', fin_quarter(DATE '2026-05-07'), 2),
  assert_eq('gsq datetime weekday alias', fin_weekday(DATE '2026-05-04'), 0),
  assert_eq('gsq datetime day count alias', fin_day_count(DATE '2026-05-04', DATE '2026-05-07'), 3),
  assert_near('gsq datetime day count fraction alias', fin_day_count_fraction(DATE '2026-01-01', DATE '2027-01-01'), 1.0, 1e-12),
  assert_eq('gsq datetime countdown alias', fin_day_countdown(DATE '2026-05-07', DATE '2026-05-04', false), 3),
  assert_eq('gsq datetime business offset alias', fin_business_day_offset(DATE '2026-05-08', 1), DATE '2026-05-11'),
  assert_eq('gsq datetime prev business date alias', fin_prev_business_date(DATE '2026-05-11'), DATE '2026-05-08'),
  assert_eq('gsq datetime business day count alias', fin_business_day_count(DATE '2026-05-04', DATE '2026-05-08'), 4),
  assert_eq('gsq datetime has feb 29 alias', fin_has_feb_29(DATE '2023-12-31', DATE '2024-03-01'), true),
  assert_eq('gsq datetime today alias', fin_today() = CAST(CAST(get_current_timestamp() AS TIMESTAMP) AS DATE), true),
  assert_eq('gsq point relative date add days', fin_relative_date_add('3d'), 3.0),
  assert_eq('gsq point relative date add months', fin_relative_date_add('-2m'), -60.0),
  assert_eq('gsq point sort order alias', fin_point_sort_order('spot'), 0.0),
  assert_eq('gsq time zulu string alias', fin_to_zulu_string(TIMESTAMP '2026-05-07 12:34:56'), '2026-05-07T12:34:56Z'),
  assert_eq('gsq time difference string alias', fin_time_difference_as_string(3661), '1 Hour');

SELECT
  assert_eq('gsq datetime align placeholder', fin_align(10.0, 20.0), 10.0),
  assert_eq('gsq datetime interpolate placeholder', fin_interpolate(10.0, [DATE '2026-05-07']), 10.0),
  assert_eq('gsq datetime date range alias', len(fin_date_range(DATE '2026-05-04', DATE '2026-05-07')), 3),
  assert_eq('gsq datetime append placeholder', fin_append(10.0, 20.0), 10.0),
  assert_eq('gsq datetime prepend placeholder', fin_prepend(10.0, 20.0), 10.0),
  assert_eq('gsq datetime union placeholder', fin_union(10.0, 20.0), 10.0),
  assert_eq('gsq datetime bucketize placeholder', fin_bucketize(10.0), 10.0),
  assert_eq('gsq datetime align calendar placeholder', fin_align_calendar(10.0), 10.0),
  assert_eq('gsq stats generate series alias', fin_generate_series(3), [0, 1, 2]),
  assert_eq('gsq stats intraday generate series alias', fin_generate_series_intraday(3), [0, 1, 2]),
  assert_eq('gsq datetime day count fractions placeholder', fin_day_count_fractions([DATE '2026-05-04', DATE '2026-05-05']), NULL);

SELECT
  assert_not_null('gsq datetime value alias', fin_value(close)),
  assert_not_null('gsq stats cov alias', fin_cov(close, volume))
FROM gold_prices;

SELECT
  assert_near('gsq econometrics returns alias', fin_returns(102.0, 100.0), 0.02, 1e-12),
  assert_near('gsq econometrics prices alias', fin_prices(r, 100.0), 102.961247795, 1e-9),
  assert_near('gsq econometrics index alias', fin_index(r + 1.0, 100.0), 98.51485148514851, 1e-12),
  assert_near('gsq econometrics change alias', fin_change(r), -0.015, 1e-12),
  assert_near('gsq econometrics annualize alias', fin_annualize(r, 252), 1.512, 1e-12),
  assert_not_null('gsq econometrics vol swap volatility alias', fin_vol_swap_volatility(r)),
  assert_not_null('gsq econometrics correlation alias', fin_correlation(r, benchmark_r)),
  assert_not_null('gsq econometrics corr swap correlation alias', fin_corr_swap_correlation(r, benchmark_r))
FROM gold_returns;

SELECT
  assert_near('gsq technical moving average alias', fin_moving_average(close), 101.6, 1e-12),
  assert_not_null('gsq technical bollinger bands alias', (fin_bollinger_bands(close)).middle),
  assert_near('gsq technical smoothed moving average alias', fin_smoothed_moving_average(close), 101.6, 1e-12),
  assert_not_null('gsq technical relative strength index alias', fin_relative_strength_index(close)),
  assert_near('gsq technical exponential moving average alias', fin_exponential_moving_average(close), 101.6, 1e-12),
  assert_not_null('gsq technical exponential volatility alias', fin_exponential_volatility(close)),
  assert_not_null('gsq technical exponential spread volatility alias', fin_exponential_spread_volatility(close - open)),
  assert_near('gsq technical seasonally adjusted placeholder', fin_seasonally_adjusted(last(close)), 103.0, 1e-12),
  assert_eq('gsq technical trend placeholder', (fin_trend(close)).slope, NULL)
FROM gold_prices;

SELECT
  assert_near('gsq portfolio aum alias', fin_aum(100.0 + seq), 105.0, 1e-12),
  assert_near('gsq portfolio factor exposure alias', fin_portfolio_factor_exposure(factor), 3.0, 1e-12),
  assert_near('gsq portfolio factor pnl alias', fin_portfolio_factor_pnl(forward_return), 0.049, 1e-12),
  assert_near('gsq portfolio factor risk proportion alias', fin_portfolio_factor_proportion_of_risk(factor), 3.0, 1e-12),
  assert_near('gsq portfolio daily risk alias', fin_portfolio_daily_risk(abs(r)), 0.016, 1e-12),
  assert_not_null('gsq portfolio annual risk alias', fin_portfolio_annual_risk(abs(r))),
  assert_near('gsq portfolio thematic exposure alias', fin_portfolio_thematic_exposure(factor), 3.0, 1e-12),
  assert_near('gsq portfolio pnl alias', fin_portfolio_pnl(r), 0.03, 1e-12),
  assert_near('gsq portfolio hit rate alias', fin_portfolio_hit_rate(r), 0.6, 1e-12),
  assert_near('gsq portfolio max drawdown alias', fin_portfolio_max_drawdown(r), -0.02, 1e-12),
  assert_eq('gsq portfolio drawdown length alias', fin_portfolio_drawdown_length(r), 1::BIGINT),
  assert_eq('gsq portfolio max recovery alias', fin_portfolio_max_recovery_period(r), 1::BIGINT),
  assert_not_null('gsq portfolio standard deviation alias', fin_portfolio_standard_deviation(r)),
  assert_not_null('gsq portfolio downside risk alias', fin_portfolio_downside_risk(r)),
  assert_near('gsq portfolio semi variance alias', fin_portfolio_semi_variance(r), 0.000085, 1e-12),
  assert_not_null('gsq portfolio kurtosis alias', fin_portfolio_kurtosis(r)),
  assert_not_null('gsq portfolio skewness alias', fin_portfolio_skewness(r)),
  assert_not_null('gsq portfolio realized var alias', fin_portfolio_realized_var(r)),
  assert_not_null('gsq portfolio tracking error alias', fin_portfolio_tracking_error(r, benchmark_r)),
  assert_not_null('gsq portfolio tracking error bear alias', fin_portfolio_tracking_error_bear(r, benchmark_r)),
  assert_not_null('gsq portfolio tracking error bull alias', fin_portfolio_tracking_error_bull(r, benchmark_r)),
  assert_not_null('gsq portfolio sharpe ratio alias', fin_portfolio_sharpe_ratio(r)),
  assert_not_null('gsq portfolio calmar ratio alias', fin_portfolio_calmar_ratio(r)),
  assert_not_null('gsq portfolio sortino ratio alias', fin_portfolio_sortino_ratio(r)),
  assert_not_null('gsq portfolio information ratio alias', fin_portfolio_information_ratio(r, benchmark_r)),
  assert_not_null('gsq portfolio information ratio bull alias', fin_portfolio_information_ratio_bull(r, benchmark_r)),
  assert_not_null('gsq portfolio information ratio bear alias', fin_portfolio_information_ratio_bear(r, benchmark_r)),
  assert_not_null('gsq portfolio modigliani ratio alias', fin_portfolio_modigliani_ratio(r, benchmark_r)),
  assert_not_null('gsq portfolio treynor measure alias', fin_portfolio_treynor_measure(r, benchmark_r)),
  assert_not_null('gsq portfolio jensen alpha alias', fin_portfolio_jensen_alpha(r, benchmark_r)),
  assert_not_null('gsq portfolio jensen alpha bear alias', fin_portfolio_jensen_alpha_bear(r, benchmark_r)),
  assert_not_null('gsq portfolio jensen alpha bull alias', fin_portfolio_jensen_alpha_bull(r, benchmark_r)),
  assert_not_null('gsq portfolio alpha alias', fin_portfolio_alpha(r, benchmark_r)),
  assert_near('gsq portfolio beta alias', fin_portfolio_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_not_null('gsq portfolio correlation alias', fin_portfolio_correlation(r, benchmark_r)),
  assert_not_null('gsq portfolio r squared alias', fin_portfolio_r_squared(r, benchmark_r)),
  assert_not_null('gsq portfolio capture ratio alias', fin_portfolio_capture_ratio(r, benchmark_r))
FROM gold_returns;

SELECT
  assert_near('gsq report factor exposure alias', fin_factor_exposure(factor), 3.0, 1e-12),
  assert_near('gsq report factor pnl alias', fin_factor_pnl(forward_return), 0.049, 1e-12),
  assert_near('gsq report factor risk proportion alias', fin_factor_proportion_of_risk(factor), 3.0, 1e-12),
  assert_near('gsq report daily risk alias', fin_daily_risk(abs(r)), 0.016, 1e-12),
  assert_not_null('gsq report annual risk alias', fin_annual_risk(abs(r))),
  assert_near('gsq report normalized performance alias', fin_normalized_performance(r + 1.0), 98.51485148514851, 1e-12),
  assert_near('gsq report long pnl alias', fin_long_pnl(r), 0.055, 1e-12),
  assert_near('gsq report short pnl alias', fin_short_pnl(r), -0.025, 1e-12),
  assert_near('gsq report thematic exposure alias', fin_thematic_exposure(factor), 3.0, 1e-12),
  assert_near('gsq report thematic beta alias', fin_thematic_beta(r, benchmark_r), 1.6964285714285716, 1e-12),
  assert_near('gsq report pnl alias', fin_pnl(r), 0.03, 1e-12),
  assert_near('gsq report historical pnl alias', fin_historical_simulation_estimated_pnl(r), 0.03, 1e-12),
  assert_near('gsq report historical factor attribution alias', fin_historical_simulation_estimated_factor_attribution(factor), 3.0, 1e-12),
  assert_near('gsq report hit rate alias', fin_hit_rate(r), 0.6, 1e-12),
  assert_eq('gsq report drawdown length alias', fin_drawdown_length(r), 1::BIGINT),
  assert_eq('gsq report max recovery alias', fin_max_recovery_period(r), 1::BIGINT),
  assert_not_null('gsq report standard deviation alias', fin_standard_deviation(r)),
  assert_not_null('gsq report downside risk alias', fin_downside_risk(r)),
  assert_near('gsq report semi variance alias', fin_semi_variance(r), 0.000085, 1e-12),
  assert_not_null('gsq report kurtosis alias', fin_kurtosis(r)),
  assert_not_null('gsq report skewness alias', fin_skewness(r)),
  assert_not_null('gsq report realized var alias', fin_realized_var(r)),
  assert_not_null('gsq report tracking error bear alias', fin_tracking_error_bear(r, benchmark_r)),
  assert_not_null('gsq report tracking error bull alias', fin_tracking_error_bull(r, benchmark_r)),
  assert_not_null('gsq report calmar ratio alias', fin_calmar_ratio(r)),
  assert_not_null('gsq report sortino ratio alias', fin_sortino_ratio(r)),
  assert_not_null('gsq report jensen alpha bear alias', fin_jensen_alpha_bear(r, benchmark_r)),
  assert_not_null('gsq report jensen alpha bull alias', fin_jensen_alpha_bull(r, benchmark_r)),
  assert_not_null('gsq report information ratio bear alias', fin_information_ratio_bear(r, benchmark_r)),
  assert_not_null('gsq report information ratio bull alias', fin_information_ratio_bull(r, benchmark_r)),
  assert_not_null('gsq report modigliani ratio alias', fin_modigliani_ratio(r, benchmark_r)),
  assert_not_null('gsq report treynor measure alias', fin_treynor_measure(r, benchmark_r)),
  assert_not_null('gsq report capture ratio alias', fin_capture_ratio(r, benchmark_r)),
  assert_not_null('gsq report r squared alias', fin_r_squared(r, benchmark_r))
FROM gold_returns;

SELECT
  assert_not_null('gsq tca covariance alias', fin_covariance(r, benchmark_r)),
  assert_near('gsq backtesting basket series alias', fin_basket_series(r, factor), 0.006333333333333333, 1e-12),
  assert_not_null('gsq inflation swap rate alias', fin_inflation_swap_rate(r)),
  assert_not_null('gsq inflation swap term alias', fin_inflation_swap_term(r)),
  assert_not_null('gsq crosscurrency swap rate alias', fin_crosscurrency_swap_rate(r)),
  assert_not_null('gsq fx implied volatility source alias', fin_implied_volatility_fxvol(abs(r))),
  assert_not_null('gsq fx implied volatility display alias', fin_implied_volatility(abs(r)))
FROM gold_returns;

SELECT
  assert_not_null('gsq fx fwd points alias', fin_fwd_points(close - open)),
  assert_not_null('gsq fx forward point display alias', fin_forward_point(close - open)),
  assert_not_null('gsq fx vol swap strike alias', fin_vol_swap_strike(abs(close - open))),
  assert_not_null('gsq fx spot carry alias', fin_spot_carry(close - open, close))
FROM gold_prices;

SELECT
  assert_not_null('gsq rates swap annuity alias', fin_swap_annuity(abs(r))),
  assert_not_null('gsq rates swaption premium alias', fin_swaption_premium(abs(r))),
  assert_not_null('gsq rates swaption annuity alias', fin_swaption_annuity(abs(r))),
  assert_not_null('gsq rates midcurve premium alias', fin_midcurve_premium(abs(r))),
  assert_not_null('gsq rates midcurve annuity alias', fin_midcurve_annuity(abs(r))),
  assert_not_null('gsq rates swaption atm fwd rate alias', fin_swaption_atm_fwd_rate(r)),
  assert_not_null('gsq rates swaption vol alias', fin_swaption_vol(abs(r))),
  assert_not_null('gsq rates midcurve vol alias', fin_midcurve_vol(abs(r))),
  assert_not_null('gsq rates midcurve atm fwd rate alias', fin_midcurve_atm_fwd_rate(r)),
  assert_not_null('gsq rates swaption vol smile alias', fin_swaption_vol_smile(abs(r))),
  assert_not_null('gsq rates swaption vol term alias', fin_swaption_vol_term(abs(r))),
  assert_not_null('gsq rates swap rate calc alias', fin_swap_rate_calc(r)),
  assert_not_null('gsq rates instantaneous forward alias', fin_instantaneous_forward_rate(r)),
  assert_not_null('gsq rates index forward alias', fin_index_forward_rate(r)),
  assert_not_null('gsq rates basis swap spread alias', fin_basis_swap_spread(r)),
  assert_not_null('gsq rates swap term structure alias', fin_swap_term_structure(r)),
  assert_not_null('gsq rates basis swap term structure alias', fin_basis_swap_term_structure(r)),
  assert_not_null('gsq rates ois xccy alias', fin_ois_xccy(r)),
  assert_not_null('gsq rates ois xccy ex spike alias', fin_ois_xccy_ex_spike(r)),
  assert_not_null('gsq rates non usd ois alias', fin_non_usd_ois(r)),
  assert_not_null('gsq rates usd ois alias', fin_usd_ois(r)),
  assert_not_null('gsq rates policy rate term structure alias', fin_policy_rate_term_structure(r)),
  assert_not_null('gsq rates policy rate expectation alias', fin_policy_rate_expectation(r))
FROM gold_returns;

SELECT
  assert_not_null('gsq cognitive credit fundamentals alias', fin_cognitive_credit_fundamentals(r)),
  assert_not_null('gsq country fci alias', fin_fci(r)),
  assert_not_null('gsq factset estimates alias', fin_factset_estimates(r)),
  assert_not_null('gsq factset fundamentals alias', fin_factset_fundamentals(r)),
  assert_not_null('gsq factset ratings alias', fin_factset_ratings(r)),
  assert_not_null('gsq gir estimates alias', fin_gir_estimates(r)),
  assert_not_null('gsq factset enterprise value alias', fin_factset_enterprise_value(r)),
  assert_not_null('gsq risk model measure alias', fin_risk_model_measure(r)),
  assert_not_null('gsq risk model factor zscore alias', fin_factor_zscore(r)),
  assert_not_null('gsq risk model factor covariance alias', fin_factor_covariance(r, benchmark_r)),
  assert_not_null('gsq risk model factor volatility alias', fin_factor_volatility(r)),
  assert_not_null('gsq risk model factor correlation alias', fin_factor_correlation(r, benchmark_r)),
  assert_not_null('gsq risk model factor performance alias', fin_factor_performance(r)),
  assert_not_null('gsq risk model factor intraday returns alias', fin_factor_returns_intraday(r)),
  assert_not_null('gsq risk model factor returns percentile alias', fin_factor_returns_percentile(r))
FROM gold_returns;

SELECT
  assert_not_null('gsq measures skew alias', fin_skew(r)),
  assert_not_null('gsq measures cds implied vol alias', fin_cds_implied_volatility(abs(r))),
  assert_not_null('gsq measures option premium credit alias', fin_option_premium_credit(abs(r))),
  assert_not_null('gsq measures absolute strike credit alias', fin_absolute_strike_credit(abs(r))),
  assert_not_null('gsq measures implied volatility credit alias', fin_implied_volatility_credit(abs(r))),
  assert_not_null('gsq measures cds spread alias', fin_cds_spread(r)),
  assert_not_null('gsq measures implied volatility ng alias', fin_implied_volatility_ng(abs(r))),
  assert_not_null('gsq measures implied correlation alias', fin_implied_correlation(r, benchmark_r)),
  assert_not_null('gsq measures implied correlation basket alias', fin_implied_correlation_with_basket(r, benchmark_r)),
  assert_not_null('gsq measures realized correlation basket alias', fin_realized_correlation_with_basket(r, benchmark_r)),
  assert_not_null('gsq measures average implied vol alias', fin_average_implied_volatility(abs(r))),
  assert_not_null('gsq measures average implied variance alias', fin_average_implied_variance(abs(r))),
  assert_not_null('gsq measures average realized vol alias', fin_average_realized_volatility(abs(r))),
  assert_not_null('gsq measures cap floor vol alias', fin_cap_floor_vol(abs(r))),
  assert_not_null('gsq measures cap floor fwd alias', fin_cap_floor_atm_fwd_rate(r)),
  assert_not_null('gsq measures spread option vol alias', fin_spread_option_vol(abs(r))),
  assert_not_null('gsq measures spread option fwd alias', fin_spread_option_atm_fwd_rate(r)),
  assert_not_null('gsq measures zc inflation swap alias', fin_zc_inflation_swap_rate(r)),
  assert_not_null('gsq measures basis alias', fin_basis(r)),
  assert_not_null('gsq measures fx forecast alias', fin_fx_forecast(r)),
  assert_not_null('gsq measures fx forecast time series alias', fin_fx_forecast_time_series(r)),
  assert_not_null('gsq measures forward vol alias', fin_forward_vol(abs(r))),
  assert_not_null('gsq measures forward vol term alias', fin_forward_vol_term(abs(r))),
  assert_not_null('gsq measures skew term alias', fin_skew_term(r)),
  assert_not_null('gsq measures vol term alias', fin_vol_term(abs(r))),
  assert_not_null('gsq measures vol smile alias', fin_vol_smile(abs(r))),
  assert_not_null('gsq measures fwd term alias', fin_fwd_term(r)),
  assert_not_null('gsq measures fx fwd term alias', fin_fx_fwd_term(r)),
  assert_not_null('gsq measures carry term alias', fin_carry_term(r)),
  assert_not_null('gsq measures forward var term alias', fin_forward_var_term(abs(r))),
  assert_not_null('gsq measures var term alias', fin_var_term(abs(r))),
  assert_not_null('gsq measures var swap alias', fin_var_swap(abs(r))),
  assert_not_null('gsq measures fair price alias', fin_fair_price(abs(r))),
  assert_not_null('gsq measures implied volatility elec alias', fin_implied_volatility_elec(abs(r))),
  assert_not_null('gsq measures forward price ng alias', fin_forward_price_ng(abs(r))),
  assert_not_null('gsq measures bucketize price alias', fin_bucketize_price(abs(r))),
  assert_not_null('gsq measures dividend yield alias', fin_dividend_yield(abs(r))),
  assert_not_null('gsq measures earnings per share alias', fin_earnings_per_share(abs(r)))
FROM gold_returns;

SELECT
  assert_not_null('gsq measures eps positive alias', fin_earnings_per_share_positive(abs(r))),
  assert_not_null('gsq measures net debt ebitda alias', fin_net_debt_to_ebitda(abs(r))),
  assert_not_null('gsq measures price to book alias', fin_price_to_book(abs(r))),
  assert_not_null('gsq measures price to cash alias', fin_price_to_cash(abs(r))),
  assert_not_null('gsq measures price to earnings alias', fin_price_to_earnings(abs(r))),
  assert_not_null('gsq measures price to earnings positive alias', fin_price_to_earnings_positive(abs(r))),
  assert_not_null('gsq measures price to earnings positive exclusive alias', fin_price_to_earnings_positive_exclusive(abs(r))),
  assert_not_null('gsq measures price to sales alias', fin_price_to_sales(abs(r))),
  assert_not_null('gsq measures return on equity alias', fin_return_on_equity(abs(r))),
  assert_not_null('gsq measures sales per share alias', fin_sales_per_share(abs(r))),
  assert_not_null('gsq measures constituents dividend yield alias', fin_current_constituents_dividend_yield(abs(r))),
  assert_not_null('gsq measures constituents eps alias', fin_current_constituents_earnings_per_share(abs(r))),
  assert_not_null('gsq measures constituents eps positive alias', fin_current_constituents_earnings_per_share_positive(abs(r))),
  assert_not_null('gsq measures constituents net debt ebitda alias', fin_current_constituents_net_debt_to_ebitda(abs(r))),
  assert_not_null('gsq measures constituents price to book alias', fin_current_constituents_price_to_book(abs(r))),
  assert_not_null('gsq measures constituents price to cash alias', fin_current_constituents_price_to_cash(abs(r))),
  assert_not_null('gsq measures constituents price to earnings alias', fin_current_constituents_price_to_earnings(abs(r))),
  assert_not_null('gsq measures constituents price to earnings positive alias', fin_current_constituents_price_to_earnings_positive(abs(r))),
  assert_not_null('gsq measures constituents price to sales alias', fin_current_constituents_price_to_sales(abs(r))),
  assert_not_null('gsq measures constituents return on equity alias', fin_current_constituents_return_on_equity(abs(r))),
  assert_not_null('gsq measures constituents sales per share alias', fin_current_constituents_sales_per_share(abs(r))),
  assert_not_null('gsq measures realized correlation alias', fin_realized_correlation(r, benchmark_r)),
  assert_not_null('gsq measures realized volatility alias', fin_realized_volatility(r)),
  assert_not_null('gsq measures esg headline alias', fin_esg_headline_metric(abs(r))),
  assert_not_null('gsq measures rating alias', fin_rating(abs(r))),
  assert_not_null('gsq measures fair value alias', fin_fair_value(abs(r))),
  assert_not_null('gsq measures factor profile alias', fin_factor_profile(abs(r))),
  assert_not_null('gsq measures commodity forecast alias', fin_commodity_forecast(r)),
  assert_not_null('gsq measures commodity forecast time series alias', fin_commodity_forecast_time_series(r)),
  assert_not_null('gsq measures forward curve alias', fin_forward_curve(abs(r))),
  assert_not_null('gsq measures forward curve ng alias', fin_forward_curve_ng(abs(r))),
  assert_not_null('gsq measures fx implied correlation alias', fin_fx_implied_correlation(r, benchmark_r)),
  assert_not_null('gsq measures settlement price alias', fin_settlement_price(abs(r))),
  assert_not_null('gsq measures hloc prices alias', (fin_hloc_prices(abs(r))).close),
  assert_not_null('gsq measures thematic exposure alias', fin_thematic_model_exposure(abs(r))),
  assert_not_null('gsq measures thematic beta alias', fin_thematic_model_beta(r, benchmark_r)),
  assert_not_null('gsq measures retail interest alias', fin_retail_interest_agg(abs(r))),
  assert_not_null('gsq measures s3 concentration alias', fin_s3_long_short_concentration(abs(r)))
FROM gold_returns;

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
  assert_near('rsi', fin_rsi(close), 63.63636363636363, 1e-12),
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
  assert_eq('cdl pattern placeholder', fin_cdl_pattern(open, high, low, close, 'doji'), 0),
  assert_eq('cdl doji placeholder', fin_cdl_doji(open, high, low, close), 0),
  assert_not_null('ohlc close', (fin_ohlc(close)).close),
  assert_not_null('ohlcv vwap', (fin_ohlcv(close, volume)).vwap),
  assert_not_null('amihud', fin_amihud_illiquidity(abs(close - open), close * volume)),
  assert_not_null('roll spread', fin_roll_spread(close)),
  assert_not_null('kyle lambda', fin_kyle_lambda(volume, close - open)),
  assert_not_null('vpin', fin_vpin(volume, volume))
FROM gold_prices;

SELECT
  assert_eq('cdl 2crows placeholder', fin_cdl_2crows(open, high, low, close), 0),
  assert_eq('cdl 3blackcrows placeholder', fin_cdl_3blackcrows(open, high, low, close), 0),
  assert_eq('cdl 3inside placeholder', fin_cdl_3inside(open, high, low, close), 0),
  assert_eq('cdl 3linestrike placeholder', fin_cdl_3linestrike(open, high, low, close), 0),
  assert_eq('cdl 3starsinsouth placeholder', fin_cdl_3starsinsouth(open, high, low, close), 0),
  assert_eq('cdl 3whitesoldiers placeholder', fin_cdl_3whitesoldiers(open, high, low, close), 0),
  assert_eq('cdl abandonedbaby placeholder', fin_cdl_abandonedbaby(open, high, low, close), 0),
  assert_eq('cdl advanceblock placeholder', fin_cdl_advanceblock(open, high, low, close), 0),
  assert_eq('cdl belthold placeholder', fin_cdl_belthold(open, high, low, close), 0),
  assert_eq('cdl breakaway placeholder', fin_cdl_breakaway(open, high, low, close), 0),
  assert_eq('cdl closingmarubozu placeholder', fin_cdl_closingmarubozu(open, high, low, close), 0),
  assert_eq('cdl concealbabyswall placeholder', fin_cdl_concealbabyswall(open, high, low, close), 0),
  assert_eq('cdl counterattack placeholder', fin_cdl_counterattack(open, high, low, close), 0),
  assert_eq('cdl darkcloudcover placeholder', fin_cdl_darkcloudcover(open, high, low, close), 0),
  assert_eq('cdl dojistar placeholder', fin_cdl_dojistar(open, high, low, close), 0),
  assert_eq('cdl dragonflydoji placeholder', fin_cdl_dragonflydoji(open, high, low, close), 0),
  assert_eq('cdl engulfing placeholder', fin_cdl_engulfing(open, high, low, close), 0),
  assert_eq('cdl eveningdojistar placeholder', fin_cdl_eveningdojistar(open, high, low, close), 0),
  assert_eq('cdl eveningstar placeholder', fin_cdl_eveningstar(open, high, low, close), 0),
  assert_eq('cdl gapsidesidewhite placeholder', fin_cdl_gapsidesidewhite(open, high, low, close), 0),
  assert_eq('cdl gravestonedoji placeholder', fin_cdl_gravestonedoji(open, high, low, close), 0),
  assert_eq('cdl hammer placeholder', fin_cdl_hammer(open, high, low, close), 0),
  assert_eq('cdl hangingman placeholder', fin_cdl_hangingman(open, high, low, close), 0),
  assert_eq('cdl harami placeholder', fin_cdl_harami(open, high, low, close), 0),
  assert_eq('cdl haramicross placeholder', fin_cdl_haramicross(open, high, low, close), 0),
  assert_eq('cdl highwave placeholder', fin_cdl_highwave(open, high, low, close), 0),
  assert_eq('cdl hikkake placeholder', fin_cdl_hikkake(open, high, low, close), 0),
  assert_eq('cdl hikkakemod placeholder', fin_cdl_hikkakemod(open, high, low, close), 0),
  assert_eq('cdl homingpigeon placeholder', fin_cdl_homingpigeon(open, high, low, close), 0),
  assert_eq('cdl identical3crows placeholder', fin_cdl_identical3crows(open, high, low, close), 0),
  assert_eq('cdl inneck placeholder', fin_cdl_inneck(open, high, low, close), 0),
  assert_eq('cdl invertedhammer placeholder', fin_cdl_invertedhammer(open, high, low, close), 0),
  assert_eq('cdl kicking placeholder', fin_cdl_kicking(open, high, low, close), 0),
  assert_eq('cdl kickingbylength placeholder', fin_cdl_kickingbylength(open, high, low, close), 0),
  assert_eq('cdl ladderbottom placeholder', fin_cdl_ladderbottom(open, high, low, close), 0),
  assert_eq('cdl longleggeddoji placeholder', fin_cdl_longleggeddoji(open, high, low, close), 0),
  assert_eq('cdl longline placeholder', fin_cdl_longline(open, high, low, close), 0),
  assert_eq('cdl marubozu placeholder', fin_cdl_marubozu(open, high, low, close), 0),
  assert_eq('cdl matchinglow placeholder', fin_cdl_matchinglow(open, high, low, close), 0),
  assert_eq('cdl mathold placeholder', fin_cdl_mathold(open, high, low, close), 0),
  assert_eq('cdl morningdojistar placeholder', fin_cdl_morningdojistar(open, high, low, close), 0),
  assert_eq('cdl morningstar placeholder', fin_cdl_morningstar(open, high, low, close), 0),
  assert_eq('cdl onneck placeholder', fin_cdl_onneck(open, high, low, close), 0),
  assert_eq('cdl piercing placeholder', fin_cdl_piercing(open, high, low, close), 0),
  assert_eq('cdl rickshawman placeholder', fin_cdl_rickshawman(open, high, low, close), 0),
  assert_eq('cdl risefall3methods placeholder', fin_cdl_risefall3methods(open, high, low, close), 0),
  assert_eq('cdl separatinglines placeholder', fin_cdl_separatinglines(open, high, low, close), 0),
  assert_eq('cdl shootingstar placeholder', fin_cdl_shootingstar(open, high, low, close), 0),
  assert_eq('cdl shortline placeholder', fin_cdl_shortline(open, high, low, close), 0),
  assert_eq('cdl spinningtop placeholder', fin_cdl_spinningtop(open, high, low, close), 0),
  assert_eq('cdl stalledpattern placeholder', fin_cdl_stalledpattern(open, high, low, close), 0),
  assert_eq('cdl sticksandwich placeholder', fin_cdl_sticksandwich(open, high, low, close), 0),
  assert_eq('cdl takuri placeholder', fin_cdl_takuri(open, high, low, close), 0),
  assert_eq('cdl tasukigap placeholder', fin_cdl_tasukigap(open, high, low, close), 0),
  assert_eq('cdl thrusting placeholder', fin_cdl_thrusting(open, high, low, close), 0),
  assert_eq('cdl tristar placeholder', fin_cdl_tristar(open, high, low, close), 0),
  assert_eq('cdl unique3river placeholder', fin_cdl_unique3river(open, high, low, close), 0),
  assert_eq('cdl upsidegap2crows placeholder', fin_cdl_upsidegap2crows(open, high, low, close), 0),
  assert_eq('cdl xsidegap3methods placeholder', fin_cdl_xsidegap3methods(open, high, low, close), 0)
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

-- Fixed income, cash-flow, and curve helpers.
SELECT
  assert_near('yearfrac act365', fin_yearfrac(DATE '2026-01-01', DATE '2027-01-01', 'ACT/365F'), 1.0, 1e-12),
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
  assert_not_null('mirr', fin_mirr([-100.0, 60.0, 60.0], 0.1, 0.05)),
  assert_near('xirr annual', fin_xirr([-100.0, 110.0], [DATE '2026-01-01', DATE '2027-01-01']), 0.1, 1e-8),
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
  assert_near('bsm delta', fin_bsm_delta('call', 100.0, 100.0, 1.0, 0.05, 0.2), 0.6368306511756191, 1e-10),
  assert_near('bsm gamma', fin_bsm_gamma(100.0, 100.0, 1.0, 0.05, 0.2), 0.018762017345846895, 1e-12),
  assert_near('bsm vega', fin_bsm_vega('call', 100.0, 100.0, 1.0, 0.05, 0.2), 37.52403469169379, 1e-10),
  assert_near('bsm theta', fin_bsm_theta('call', 100.0, 100.0, 1.0, 0.05, 0.2), -6.414027546438197, 1e-10),
  assert_near('bsm rho', fin_bsm_rho('call', 100.0, 100.0, 1.0, 0.05, 0.2), 53.232481545376345, 1e-10),
  assert_near('bsm greeks struct', (fin_bsm_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)).delta, 0.6368306511756191, 1e-10),
  assert_near('bsm all price', (fin_bsm_all('call', 100.0, 100.0, 1.0, 0.05, 0.2)).price, 10.450583572185565, 1e-10),
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
  assert_not_null('sabr vol', fin_sabr_vol(100.0, 100.0, 1.0, 0.2, 0.5, -0.2, 0.4)),
  assert_not_null('svi total variance', fin_svi_total_variance(0.0, 0.02, 0.1, -0.3, 0.0, 0.2)),
  assert_not_null('svi vol', fin_svi_vol(0.0, 1.0, 0.02, 0.1, -0.3, 0.0, 0.2)),
  assert_near('black76 iv roundtrip', fin_black76_implied_vol('call', fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05, 0.3, 1e-8), 0.2, 1e-8),
  assert_near('bachelier iv roundtrip', fin_bachelier_implied_vol('call', fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0), 100.0, 100.0, 1.0, 0.05, 4.0, 1e-8), 5.0, 1e-7);

-- GS Quant-inspired instrument, measure, pricing-context, scenario, and portfolio helpers.
SELECT
  assert_eq('gsq pricing context date', fin_gsq_pricing_context(DATE '2026-01-02').pricing_date, DATE '2026-01-02'),
  assert_eq('gsq historical context start', fin_gsq_historical_pricing_context(DATE '2026-01-01', DATE '2026-01-05').start_date, DATE '2026-01-01'),
  assert_eq('gsq generic instrument type', fin_gsq_instrument('IRSwap', 'Rates', 'USD', 100.0).type, 'IRSwap'),
  assert_eq('gsq eq option type', fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.2).type, 'EqOption'),
  assert_eq('gsq fx forward type', fin_gsq_fx_forward('EURUSD', 1.10, 1.12, 0.5, 0.04, 0.02).type, 'FXForward'),
  assert_eq('gsq fx option type', fin_gsq_fx_option('put', 'EURUSD', 1.10, 1.12, 0.5, 0.04, 0.02, 0.12).type, 'FXOption'),
  assert_eq('gsq fx binary type', fin_gsq_fx_binary('call', 'EURUSD', 1.10, 1.12, 0.5, 0.04, 0.02, 0.12).type, 'FXBinary'),
  assert_eq('gsq ir swap type', fin_gsq_ir_swap('Receive', '5y', 'USD', 0.045, 0.04, 4.5, 1000000.0).type, 'IRSwap'),
  assert_eq('gsq ir swaption type', fin_gsq_ir_swaption('Pay', '3m', '5y', 'USD', 0.04, 0.042, 4.5, 0.2, 0.25, 0.03, 1000000.0).type, 'IRSwaption'),
  assert_eq('gsq cap floor type', fin_gsq_ir_cap_floor('cap', 'USD', 0.04, 0.035, 0.5, 0.2, 0.5).type, 'IRCap'),
  assert_eq('gsq inflation type', fin_gsq_inflation_swap('USD', 0.025, 0.03, 5.0).type, 'InflationSwap'),
  assert_eq('gsq cd index type', fin_gsq_cd_index('CDX.NA.IG', 0.0075, '5y').type, 'CDIndex'),
  assert_eq('gsq cd index option type', fin_gsq_cd_index_option('call', 'CDX.NA.IG', 0.0075, 0.0080, 0.5, 0.04, 0.35, 4.0).type, 'CDIndexOption');

SELECT
  assert_eq('gsq generic measure name', fin_gsq_measure('Price').name, 'Price'),
  assert_eq('gsq price measure name', fin_gsq_measure_price('EUR').name, 'Price'),
  assert_eq('gsq dollar price measure currency', fin_gsq_measure_dollar_price().currency, 'USD'),
  assert_eq('gsq forward price measure name', fin_gsq_measure_forward_price().name, 'ForwardPrice'),
  assert_eq('gsq eq delta measure class', fin_gsq_measure_eq_delta('USD').asset_class, 'Equity'),
  assert_eq('gsq eq gamma measure type', fin_gsq_measure_eq_gamma('USD').measure_type, 'Gamma'),
  assert_eq('gsq eq vega measure type', fin_gsq_measure_eq_vega('USD').measure_type, 'Vega'),
  assert_eq('gsq fx delta measure class', fin_gsq_measure_fx_delta('USD').asset_class, 'FX'),
  assert_eq('gsq fx gamma measure type', fin_gsq_measure_fx_gamma('USD').measure_type, 'Gamma'),
  assert_eq('gsq fx vega measure type', fin_gsq_measure_fx_vega('USD').measure_type, 'Vega'),
  assert_eq('gsq ir delta measure class', fin_gsq_measure_ir_delta('USD').asset_class, 'Rates'),
  assert_eq('gsq ir delta parallel agg', fin_gsq_measure_ir_delta_parallel('USD').aggregation_level, 'All'),
  assert_eq('gsq ir gamma measure type', fin_gsq_measure_ir_gamma('USD').measure_type, 'Gamma'),
  assert_eq('gsq ir vega measure type', fin_gsq_measure_ir_vega('USD').measure_type, 'Vega'),
  assert_eq('gsq cd delta measure class', fin_gsq_measure_cd_delta('USD').asset_class, 'Credit'),
  assert_eq('gsq cd gamma measure type', fin_gsq_measure_cd_gamma('USD').measure_type, 'Gamma'),
  assert_eq('gsq cd vega measure type', fin_gsq_measure_cd_vega('USD').measure_type, 'Vega');

SELECT
  assert_near('gsq eq option price', fin_gsq_eq_option_price(fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.2)), 10.450583572185565, 1e-10),
  assert_near('gsq eq delta', fin_gsq_eq_delta(fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.2)), 0.6368306511756191, 1e-10),
  assert_not_null('gsq eq gamma', fin_gsq_eq_gamma(fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.2))),
  assert_not_null('gsq eq vega', fin_gsq_eq_vega(fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.2))),
  assert_near('gsq calc eq option', fin_gsq_calc_eq_option(fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.2), fin_gsq_measure_price()), 10.450583572185565, 1e-10),
  assert_not_null('gsq fx forward value', fin_gsq_fx_forward_value(fin_gsq_fx_forward('EURUSD', 1.10, 1.12, 0.5, 0.04, 0.02))),
  assert_not_null('gsq fx option price', fin_gsq_fx_option_price(fin_gsq_fx_option('put', 'EURUSD', 1.10, 1.12, 0.5, 0.04, 0.02, 0.12))),
  assert_not_null('gsq fx binary price', fin_gsq_fx_binary_price(fin_gsq_fx_binary('call', 'EURUSD', 1.10, 1.12, 0.5, 0.04, 0.02, 0.12))),
  assert_near('gsq ir swap price', fin_gsq_ir_swap_price(fin_gsq_ir_swap('Receive', '5y', 'USD', 0.045, 0.04, 4.5, 1000000.0)), 22500.0, 1e-8),
  assert_not_null('gsq ir swaption price', fin_gsq_ir_swaption_price(fin_gsq_ir_swaption('Pay', '3m', '5y', 'USD', 0.04, 0.042, 4.5, 0.2, 0.25, 0.03, 1000000.0))),
  assert_not_null('gsq cap floor price', fin_gsq_ir_cap_floor_price(fin_gsq_ir_cap_floor('cap', 'USD', 0.04, 0.035, 0.5, 0.2, 0.5))),
  assert_near('gsq inflation swap price', fin_gsq_inflation_swap_price(fin_gsq_inflation_swap('USD', 0.025, 0.03, 5.0, 1000000.0)), 25000.0, 1e-8),
  assert_not_null('gsq cd index option price', fin_gsq_cd_index_option_price(fin_gsq_cd_index_option('call', 'CDX.NA.IG', 0.0075, 0.0080, 0.5, 0.04, 0.35, 4.0, 1000000.0)));

SELECT
  assert_eq('gsq market data pattern type', fin_gsq_market_data_pattern('IR', 'USD').mkt_type, 'IR'),
  assert_eq('gsq shock type', fin_gsq_market_data_shock('Absolute', 0.0001).shock_type, 'Absolute'),
  assert_eq('gsq shock scenario type', fin_gsq_market_data_shock_scenario(fin_gsq_market_data_pattern('IR Vol'), fin_gsq_market_data_shock('Absolute', 0.0001)).type, 'MarketDataShockBasedScenario'),
  assert_near('gsq absolute shock', fin_gsq_apply_shock(0.02, fin_gsq_market_data_shock('Absolute', 0.0001)), 0.0201, 1e-12),
  assert_near('gsq proportional shock', fin_gsq_apply_shock(100.0, fin_gsq_market_data_shock('Proportional', 0.05)), 105.0, 1e-12),
  assert_near('gsq override shock', fin_gsq_apply_shock(100.0, fin_gsq_market_data_shock('Override', 99.0)), 99.0, 1e-12),
  assert_eq('gsq curve scenario type', fin_gsq_curve_scenario(5.0, 1.0, 0.0, 50.0, 5.0).type, 'CurveScenario'),
  assert_near('gsq curve scenario rate', fin_gsq_curve_scenario_rate(0.04, 5.0, fin_gsq_curve_scenario(5.0, 1.0, 0.0, 50.0, 5.0)), 0.0405, 1e-12),
  assert_eq('gsq roll fwd type', fin_gsq_roll_fwd(DATE '2026-02-02', '1m').type, 'RollFwd'),
  assert_eq('gsq index curve shift type', fin_gsq_index_curve_shift('CDX.NA.IG', 1.0).type, 'IndexCurveShift'),
  assert_near('gsq scenario pnl', fin_gsq_scenario_pnl(100.0, 102.5), 2.5, 1e-12),
  assert_near('gsq delta gamma pnl', fin_gsq_delta_gamma_pnl(10.0, 2.0, 0.5), 5.25, 1e-12);

SELECT
  assert_eq('gsq portfolio item name', fin_gsq_portfolio_item('trade-1', 'EqOption', 2.0, 10.0, 0.5, 'USD').name, 'trade-1');

SELECT
  assert_near('gsq portfolio value', fin_gsq_portfolio_value(value, quantity), 40.0, 1e-12),
  assert_near('gsq portfolio risk', fin_gsq_portfolio_risk(risk, quantity), 2.0, 1e-12)
FROM (VALUES (10.0, 2.0, 0.5), (20.0, 1.0, 1.0)) AS p(value, quantity, risk);

-- Goldman Sachs GS Quant-inspired golden dataset coverage.
SELECT
  assert_eq('gsq goldman eq case count', count_star(), 3)
FROM gsq_goldman_eq_option_cases;

SELECT
  assert_eq('gsq goldman eq descriptor type ' || case_id,
    fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency).type, 'EqOption'),
  assert_eq('gsq goldman eq descriptor underlier ' || case_id,
    fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency).underlier, underlier),
  assert_near('gsq goldman eq price ' || case_id,
    fin_gsq_eq_option_price(fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency)), expected_price, 1e-9),
  assert_near('gsq goldman eq delta ' || case_id,
    fin_gsq_eq_delta(fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency)), expected_delta, 1e-9),
  assert_near('gsq goldman eq gamma ' || case_id,
    fin_gsq_eq_gamma(fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency)), expected_gamma, 1e-12),
  assert_near('gsq goldman eq vega ' || case_id,
    fin_gsq_eq_vega(fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield, notional, currency)), expected_vega, 1e-8)
FROM gsq_goldman_eq_option_cases;

SELECT
  assert_near('gsq goldman fx forward ' || case_id,
    fin_gsq_fx_forward_value(fin_gsq_fx_forward(pair, spot, strike, ttm, domestic_rate, foreign_rate, notional, currency)), expected_value, 1e-7)
FROM gsq_goldman_fx_forward_cases;

SELECT
  assert_near('gsq goldman fx option ' || case_id,
    fin_gsq_fx_option_price(fin_gsq_fx_option(kind, pair, spot, strike, ttm, domestic_rate, foreign_rate, vol, notional, currency)), expected_price, 1e-7)
FROM gsq_goldman_fx_option_cases;

SELECT
  assert_near('gsq goldman fx binary ' || case_id,
    fin_gsq_fx_binary_price(fin_gsq_fx_binary(kind, pair, spot, strike, ttm, domestic_rate, foreign_rate, vol, payout, currency)), expected_price, 1e-7)
FROM gsq_goldman_fx_binary_cases;

SELECT
  assert_near('gsq goldman ir swap ' || case_id,
    fin_gsq_ir_swap_price(fin_gsq_ir_swap(pay_receive, tenor, currency, fixed_rate, par_rate, annuity, notional)), expected_price, 1e-7)
FROM gsq_goldman_ir_swap_cases;

SELECT
  assert_near('gsq goldman ir swaption ' || case_id,
    fin_gsq_ir_swaption_price(fin_gsq_ir_swaption(pay_receive, expiration, tenor, currency, forward_rate, strike, annuity, vol, ttm, rate, notional)), expected_price, 1e-7)
FROM gsq_goldman_ir_swaption_cases;

SELECT
  assert_near('gsq goldman ir cap floor ' || case_id,
    fin_gsq_ir_cap_floor_price(fin_gsq_ir_cap_floor(kind, currency, forward_rate, strike, annuity, vol, ttm, rate, notional)), expected_price, 1e-7)
FROM gsq_goldman_ir_cap_floor_cases;

SELECT
  assert_near('gsq goldman inflation swap ' || case_id,
    fin_gsq_inflation_swap_price(fin_gsq_inflation_swap(currency, fixed_rate, inflation_rate, annuity, notional)), expected_price, 1e-7)
FROM gsq_goldman_inflation_swap_cases;

SELECT
  assert_near('gsq goldman cd index option ' || case_id,
    fin_gsq_cd_index_option_price(fin_gsq_cd_index_option(kind, index_name, forward_spread, strike_spread, ttm, rate, vol, risky_annuity, notional, currency)), expected_price, 1e-7)
FROM gsq_goldman_cd_index_option_cases;

SELECT
  assert_eq('gsq goldman shock scenario descriptor ' || case_id,
    fin_gsq_market_data_shock_scenario(
      fin_gsq_market_data_pattern('IR Vol'),
      fin_gsq_market_data_shock(shock_type, shock_value, stddev)
    ).type,
    'MarketDataShockBasedScenario'),
  assert_near('gsq goldman shock application ' || case_id,
    fin_gsq_apply_shock(base_value, fin_gsq_market_data_shock(shock_type, shock_value, stddev)), expected_value, 1e-12)
FROM gsq_goldman_shock_cases;

SELECT
  assert_near('gsq goldman curve scenario ' || case_id,
    fin_gsq_curve_scenario_rate(
      base_rate,
      tenor,
      fin_gsq_curve_scenario(parallel_shift_bps, curve_shift_bps, tenor_start, tenor_end, pivot_point)
    ),
    expected_rate,
    1e-12)
FROM gsq_goldman_curve_scenario_cases;

SELECT
  assert_eq('gsq goldman portfolio item type ' || trade_name,
    fin_gsq_portfolio_item(trade_name, instrument_type, quantity, value, risk, currency).instrument_type, instrument_type)
FROM gsq_goldman_portfolio_cases;

SELECT
  assert_near('gsq goldman portfolio value ' || p.portfolio_id,
    fin_gsq_portfolio_value(p.value, p.quantity), e.expected_value, 1e-8),
  assert_near('gsq goldman portfolio risk ' || p.portfolio_id,
    fin_gsq_portfolio_risk(p.risk, p.quantity), e.expected_risk, 1e-8)
FROM gsq_goldman_portfolio_cases p
JOIN gsq_goldman_portfolio_expected e USING (portfolio_id)
GROUP BY p.portfolio_id, e.expected_value, e.expected_risk;

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
  assert_true('matrix psd', fin_matrix_is_psd([[1.0, 0.2], [0.2, 1.0]])),
  assert_true('nearest psd', fin_matrix_is_psd(fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]]))),
  assert_near('portfolio return', fin_portfolio_return([0.5, 0.5], [0.1, 0.2]), 0.15, 1e-12),
  assert_near('portfolio expected return', fin_portfolio_expected_return([0.5, 0.5], [0.1, 0.2]), 0.15, 1e-12),
  assert_near('portfolio variance', fin_portfolio_variance([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]]), 0.0375, 1e-12),
  assert_near('portfolio vol', fin_portfolio_vol([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]]), 0.19364916731037085, 1e-12),
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
  assert_eq('session date', fin_session_date(TIMESTAMP '2026-05-06 10:00:00', 'NYSE'), DATE '2026-05-06'),
  assert_true('regular session', fin_is_regular_session(TIMESTAMP '2026-05-06 10:00:00', 'NYSE'));

-- Table functions and bind-replace SQL.
SELECT assert_eq('schema template rows', count(*), 6::BIGINT)
FROM fin_schema_template('ohlcv');

SELECT assert_eq('validate schema rows', count(*), 6::BIGINT)
FROM fin_validate_schema('gold_prices', 'ohlcv');

SELECT assert_eq('option chain rows', count(*), 2::BIGINT)
FROM fin_option_chain('gold_options', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield');

SELECT assert_eq('bootstrap curve rows', count(*), 3::BIGINT)
FROM fin_bootstrap_curve('gold_curve', 'inst', 'maturity', 'rate', 'continuous');

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

SELECT assert_eq('rebalance trade rows', count(*), 2::BIGINT)
FROM fin_rebalance_trades('gold_current_weights', 'gold_target_weights', 'gold_asset_prices', 100000.0);

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

-- BEGIN GENERATED GS QUANT SURFACE TESTS
-- Generated by scripts/generate_gs_quant_surface.py. Do not edit by hand.
-- Each SELECT keeps the GS Quant source-surface analogue and source lookup alias in the profiled gold corpus.
SELECT assert_eq('gs quant canonical 0001 gs_quant/__init__.py get_environment_summary', fin_gsq_support_get_environment_summary('local_payload').payload || ':' || fin_gsq_support_get_environment_summary('local_payload').source_function, 'local_payload:get_environment_summary');
SELECT assert_eq('gs quant canonical 0002 gs_quant/_version.py get_keywords', fin_gsq_support_get_keywords('local_payload').payload || ':' || fin_gsq_support_get_keywords('local_payload').source_function, 'local_payload:get_keywords');
SELECT assert_eq('gs quant canonical 0003 gs_quant/_version.py get_config', fin_gsq_support_get_config('local_payload').payload || ':' || fin_gsq_support_get_config('local_payload').source_function, 'local_payload:get_config');
SELECT assert_eq('gs quant canonical 0004 gs_quant/_version.py register_vcs_handler', fin_gsq_support_register_vcs_handler('local_payload').payload || ':' || fin_gsq_support_register_vcs_handler('local_payload').source_function, 'local_payload:register_vcs_handler');
SELECT assert_eq('gs quant canonical 0005 gs_quant/_version.py run_command', fin_gsq_support_run_command('local_payload').payload || ':' || fin_gsq_support_run_command('local_payload').source_function, 'local_payload:run_command');
SELECT assert_eq('gs quant canonical 0006 gs_quant/_version.py versions_from_parentdir', fin_gsq_support_versions_from_parentdir('local_payload').payload || ':' || fin_gsq_support_versions_from_parentdir('local_payload').source_function, 'local_payload:versions_from_parentdir');
SELECT assert_eq('gs quant canonical 0007 gs_quant/_version.py git_get_keywords', fin_gsq_support_git_get_keywords('local_payload').payload || ':' || fin_gsq_support_git_get_keywords('local_payload').source_function, 'local_payload:git_get_keywords');
SELECT assert_eq('gs quant canonical 0008 gs_quant/_version.py git_versions_from_keywords', fin_gsq_support_gitversions_from_keywords('local_payload').payload || ':' || fin_gsq_support_gitversions_from_keywords('local_payload').source_function, 'local_payload:git_versions_from_keywords');
SELECT assert_eq('gs quant canonical 0009 gs_quant/_version.py git_pieces_from_vcs', fin_gsq_support_git_pieces_from_vcs('local_payload').payload || ':' || fin_gsq_support_git_pieces_from_vcs('local_payload').source_function, 'local_payload:git_pieces_from_vcs');
SELECT assert_eq('gs quant canonical 0010 gs_quant/_version.py plus_or_dot', fin_gsq_support_plus_or_dot('local_payload').payload || ':' || fin_gsq_support_plus_or_dot('local_payload').source_function, 'local_payload:plus_or_dot');
SELECT assert_eq('gs quant canonical 0011 gs_quant/_version.py render_pep440', fin_gsq_support_render_pep440('local_payload').payload || ':' || fin_gsq_support_render_pep440('local_payload').source_function, 'local_payload:render_pep440');
SELECT assert_eq('gs quant canonical 0012 gs_quant/_version.py render_pep440_branch', fin_gsq_support_render_pep440_branch('local_payload').payload || ':' || fin_gsq_support_render_pep440_branch('local_payload').source_function, 'local_payload:render_pep440_branch');
SELECT assert_eq('gs quant canonical 0013 gs_quant/_version.py pep440_split_post', fin_gsq_support_pep440_split_post('local_payload').payload || ':' || fin_gsq_support_pep440_split_post('local_payload').source_function, 'local_payload:pep440_split_post');
SELECT assert_eq('gs quant canonical 0014 gs_quant/_version.py render_pep440_pre', fin_gsq_support_render_pep440_pre('local_payload').payload || ':' || fin_gsq_support_render_pep440_pre('local_payload').source_function, 'local_payload:render_pep440_pre');
SELECT assert_eq('gs quant canonical 0015 gs_quant/_version.py render_pep440_post', fin_gsq_support_render_pep440_post('local_payload').payload || ':' || fin_gsq_support_render_pep440_post('local_payload').source_function, 'local_payload:render_pep440_post');
SELECT assert_eq('gs quant canonical 0016 gs_quant/_version.py render_pep440_post_branch', fin_gsq_support_render_pep440_post_branch('local_payload').payload || ':' || fin_gsq_support_render_pep440_post_branch('local_payload').source_function, 'local_payload:render_pep440_post_branch');
SELECT assert_eq('gs quant canonical 0017 gs_quant/_version.py render_pep440_old', fin_gsq_support_render_pep440_old('local_payload').payload || ':' || fin_gsq_support_render_pep440_old('local_payload').source_function, 'local_payload:render_pep440_old');
SELECT assert_eq('gs quant canonical 0018 gs_quant/_version.py render_git_describe', fin_gsq_support_render_git_describe('local_payload').payload || ':' || fin_gsq_support_render_git_describe('local_payload').source_function, 'local_payload:render_git_describe');
SELECT assert_eq('gs quant canonical 0019 gs_quant/_version.py render_git_describe_long', fin_gsq_support_render_git_describe_long('local_payload').payload || ':' || fin_gsq_support_render_git_describe_long('local_payload').source_function, 'local_payload:render_git_describe_long');
SELECT assert_eq('gs quant canonical 0020 gs_quant/_version.py render', fin_gsq_support_render('local_payload').payload || ':' || fin_gsq_support_render('local_payload').source_function, 'local_payload:render');
SELECT assert_eq('gs quant canonical 0021 gs_quant/_version.py get_versions', fin_gsq_support_getversions('local_payload').payload || ':' || fin_gsq_support_getversions('local_payload').source_function, 'local_payload:get_versions');
SELECT assert_eq('gs quant canonical 0022 gs_quant/analytics/common/helpers.py is_of_builtin_type', fin_content_is_of_builtin_type('local_payload').payload || ':' || fin_content_is_of_builtin_type('local_payload').source_function, 'local_payload:is_of_builtin_type');
SELECT assert_eq('gs quant canonical 0023 gs_quant/analytics/common/helpers.py resolve_entities', fin_content_resolve_entities('local_payload').payload || ':' || fin_content_resolve_entities('local_payload').source_function, 'local_payload:resolve_entities');
SELECT assert_eq('gs quant canonical 0024 gs_quant/analytics/common/helpers.py get_rdate_cache_key', fin_content_get_rdate_cache_key('local_payload').payload || ':' || fin_content_get_rdate_cache_key('local_payload').source_function, 'local_payload:get_rdate_cache_key');
SELECT assert_eq('gs quant canonical 0025 gs_quant/analytics/common/helpers.py get_entity_rdate_key', fin_content_get_entity_rdate_key('local_payload').payload || ':' || fin_content_get_entity_rdate_key('local_payload').source_function, 'local_payload:get_entity_rdate_key');
SELECT assert_eq('gs quant canonical 0026 gs_quant/analytics/common/helpers.py get_entity_rdate_key_from_rdate', fin_content_get_entity_rdate_key_from_rdate('local_payload').payload || ':' || fin_content_get_entity_rdate_key_from_rdate('local_payload').source_function, 'local_payload:get_entity_rdate_key_from_rdate');
SELECT assert_eq('gs quant canonical 0027 gs_quant/analytics/core/query_helpers.py aggregate_queries', fin_content_aggregate_queries('local_payload').payload || ':' || fin_content_aggregate_queries('local_payload').source_function, 'local_payload:aggregate_queries');
SELECT assert_eq('gs quant canonical 0028 gs_quant/analytics/core/query_helpers.py fetch_query', fin_content_fetch_query('local_payload').payload || ':' || fin_content_fetch_query('local_payload').source_function, 'local_payload:fetch_query');
SELECT assert_eq('gs quant canonical 0029 gs_quant/analytics/core/query_helpers.py build_query_string', fin_content_build_query_string('local_payload').payload || ':' || fin_content_build_query_string('local_payload').source_function, 'local_payload:build_query_string');
SELECT assert_eq('gs quant canonical 0030 gs_quant/analytics/core/query_helpers.py valid_dimensions', fin_content_valid_dimensions('local_payload').payload || ':' || fin_content_valid_dimensions('local_payload').source_function, 'local_payload:valid_dimensions');
SELECT assert_eq('gs quant canonical 0031 gs_quant/analytics/datagrid/serializers.py row_from_dict', fin_content_row_from_dict('local_payload').payload || ':' || fin_content_row_from_dict('local_payload').source_function, 'local_payload:row_from_dict');
SELECT assert_eq('gs quant canonical 0032 gs_quant/analytics/datagrid/utils.py get_utc_now', fin_content_get_utc_now('local_payload').payload || ':' || fin_content_get_utc_now('local_payload').source_function, 'local_payload:get_utc_now');
SELECT assert_eq('gs quant canonical 0033 gs_quant/analytics/processors/scale_processors.py validate_markers_data', fin_content_validate_markers_data('local_payload').payload || ':' || fin_content_validate_markers_data('local_payload').source_function, 'local_payload:validate_markers_data');
SELECT assert_eq('gs quant canonical 0034 gs_quant/api/gs/assets.py get_default_cache', fin_api_get_default_cache('local_payload').payload || ':' || fin_api_get_default_cache('local_payload').source_function, 'local_payload:get_default_cache');
SELECT assert_eq('gs quant canonical 0035 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py encode_request_object', fin_api_encode_request_object('local_payload').payload || ':' || fin_api_encode_request_object('local_payload').source_function, 'local_payload:encode_request_object');
SELECT assert_eq('gs quant canonical 0036 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py legs_decoder', fin_api_legs_decoder('local_payload').payload || ':' || fin_api_legs_decoder('local_payload').source_function, 'local_payload:legs_decoder');
SELECT assert_eq('gs quant canonical 0037 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py legs_encoder', fin_api_legs_encoder('local_payload').payload || ':' || fin_api_legs_encoder('local_payload').source_function, 'local_payload:legs_encoder');
SELECT assert_eq('gs quant canonical 0038 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py enum_decode', fin_api_enum_decode('local_payload').payload || ':' || fin_api_enum_decode('local_payload').source_function, 'local_payload:enum_decode');
SELECT assert_eq('gs quant canonical 0039 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/generic_datatype_encoders.py decode_inst', fin_api_decode_inst('local_payload').payload || ':' || fin_api_decode_inst('local_payload').source_function, 'local_payload:decode_inst');
SELECT assert_eq('gs quant canonical 0040 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/generic_datatype_encoders.py decode_inst_tuple', fin_api_decode_inst_tuple('local_payload').payload || ':' || fin_api_decode_inst_tuple('local_payload').source_function, 'local_payload:decode_inst_tuple');
SELECT assert_eq('gs quant canonical 0041 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/generic_datatype_encoders.py decode_daily_portfolio', fin_api_decode_daily_portfolio('local_payload').payload || ':' || fin_api_decode_daily_portfolio('local_payload').source_function, 'local_payload:decode_daily_portfolio');
SELECT assert_eq('gs quant canonical 0042 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py encode_series_result', fin_api_encode_series_result('local_payload').payload || ':' || fin_api_encode_series_result('local_payload').source_function, 'local_payload:encode_series_result');
SELECT assert_eq('gs quant canonical 0043 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py encode_dataframe_result', fin_api_encode_dataframe_result('local_payload').payload || ':' || fin_api_encode_dataframe_result('local_payload').source_function, 'local_payload:encode_dataframe_result');
SELECT assert_eq('gs quant canonical 0044 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py decode_series_result', fin_api_decode_series_result('local_payload').payload || ':' || fin_api_decode_series_result('local_payload').source_function, 'local_payload:decode_series_result');
SELECT assert_eq('gs quant canonical 0045 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py decode_dataframe_result', fin_api_decode_dataframe_result('local_payload').payload || ':' || fin_api_decode_dataframe_result('local_payload').source_function, 'local_payload:decode_dataframe_result');
SELECT assert_eq('gs quant canonical 0046 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_encoders.py map_result_to_datatype', fin_api_map_result_to_datatype('local_payload').payload || ':' || fin_api_map_result_to_datatype('local_payload').source_function, 'local_payload:map_result_to_datatype');
SELECT assert_eq('gs quant canonical 0047 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_encoders.py decode_risk_result_with_data', fin_api_decode_risk_result_with_data('local_payload').payload || ':' || fin_api_decode_risk_result_with_data('local_payload').source_function, 'local_payload:decode_risk_result_with_data');
SELECT assert_eq('gs quant canonical 0048 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_encoders.py decode_risk_result', fin_api_decode_risk_result('local_payload').payload || ':' || fin_api_decode_risk_result('local_payload').source_function, 'local_payload:decode_risk_result');
SELECT assert_eq('gs quant canonical 0049 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/test_backtest_datatypes_encoders.py test_transaction_cost_config_encoding', fin_api_test_transaction_cost_config_encoding('local_payload').payload || ':' || fin_api_test_transaction_cost_config_encoding('local_payload').source_function, 'local_payload:test_transaction_cost_config_encoding');
SELECT assert_eq('gs quant canonical 0050 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py encode_response_obj', fin_api_encode_response_obj('local_payload').payload || ':' || fin_api_encode_response_obj('local_payload').source_function, 'local_payload:encode_response_obj');
SELECT assert_eq('gs quant canonical 0051 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_leg_refs', fin_api_decode_leg_refs('local_payload').payload || ':' || fin_api_decode_leg_refs('local_payload').source_function, 'local_payload:decode_leg_refs');
SELECT assert_eq('gs quant canonical 0052 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_risk_measure_refs', fin_api_decode_risk_measure_refs('local_payload').payload || ':' || fin_api_decode_risk_measure_refs('local_payload').source_function, 'local_payload:decode_risk_measure_refs');
SELECT assert_eq('gs quant canonical 0053 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_result_tuple', fin_api_decode_result_tuple('local_payload').payload || ':' || fin_api_decode_result_tuple('local_payload').source_function, 'local_payload:decode_result_tuple');
SELECT assert_eq('gs quant canonical 0054 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_basic_bt_measure_dict', fin_api_decode_basic_bt_measure_dict('local_payload').payload || ':' || fin_api_decode_basic_bt_measure_dict('local_payload').source_function, 'local_payload:decode_basic_bt_measure_dict');
SELECT assert_eq('gs quant canonical 0055 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_basic_bt_transactions', fin_api_decode_basic_bt_transactions('local_payload').payload || ':' || fin_api_decode_basic_bt_transactions('local_payload').source_function, 'local_payload:decode_basic_bt_transactions');
SELECT assert_eq('gs quant canonical 0056 gs_quant/api/gs/backtests_xasset/response_datatypes/backtest_datatypes.py decode_trade_event_tuple_dict', fin_api_decode_trade_event_tuple_dict('local_payload').payload || ':' || fin_api_decode_trade_event_tuple_dict('local_payload').source_function, 'local_payload:decode_trade_event_tuple_dict');
SELECT assert_eq('gs quant canonical 0057 gs_quant/api/gs/backtests_xasset/response_datatypes/backtest_datatypes.py basic_tc_tuple_decoder', fin_api_basic_tc_tuple_decoder('local_payload').payload || ':' || fin_api_basic_tc_tuple_decoder('local_payload').source_function, 'local_payload:basic_tc_tuple_decoder');
SELECT assert_eq('gs quant canonical 0058 gs_quant/api/gs/backtests_xasset/response_datatypes/backtest_datatypes.py tcm_decoder', fin_api_tcm_decoder('local_payload').payload || ':' || fin_api_tcm_decoder('local_payload').source_function, 'local_payload:tcm_decoder');
SELECT assert_eq('gs quant canonical 0059 gs_quant/api/gs/backtests_xasset/response_datatypes/generic_backtest_datatypes.py decode_strategy', fin_api_decode_strategy('local_payload').payload || ':' || fin_api_decode_strategy('local_payload').source_function, 'local_payload:decode_strategy');
SELECT assert_eq('gs quant canonical 0060 gs_quant/api/utils.py handle_proxy', fin_api_handle_proxy('local_payload').payload || ':' || fin_api_handle_proxy('local_payload').source_function, 'local_payload:handle_proxy');
SELECT assert_eq('gs quant canonical 0061 gs_quant/backtests/actions.py default_transaction_cost', fin_backtest_default_transaction_cost('local_payload').payload || ':' || fin_backtest_default_transaction_cost('local_payload').source_function, 'local_payload:default_transaction_cost');
SELECT assert_eq('gs quant canonical 0062 gs_quant/backtests/backtest_objects.py fx_pnl_definition', fin_backtest_fx_pnl_definition('local_payload').payload || ':' || fin_backtest_fx_pnl_definition('local_payload').source_function, 'local_payload:fx_pnl_definition');
SELECT assert_eq('gs quant canonical 0063 gs_quant/backtests/backtest_utils.py encode_duration', fin_backtest_encode_duration('local_payload').payload || ':' || fin_backtest_encode_duration('local_payload').source_function, 'local_payload:encode_duration');
SELECT assert_eq('gs quant canonical 0064 gs_quant/backtests/backtest_utils.py decode_duration', fin_backtest_decode_duration('local_payload').payload || ':' || fin_backtest_decode_duration('local_payload').source_function, 'local_payload:decode_duration');
SELECT assert_eq('gs quant canonical 0065 gs_quant/backtests/backtest_utils.py make_list', fin_backtest_make_list('local_payload').payload || ':' || fin_backtest_make_list('local_payload').source_function, 'local_payload:make_list');
SELECT assert_eq('gs quant canonical 0066 gs_quant/backtests/backtest_utils.py get_final_date', fin_backtest_get_final_date('local_payload').payload || ':' || fin_backtest_get_final_date('local_payload').source_function, 'local_payload:get_final_date');
SELECT assert_eq('gs quant canonical 0067 gs_quant/backtests/backtest_utils.py scale_trade', fin_backtest_scale_trade('local_payload').payload || ':' || fin_backtest_scale_trade('local_payload').source_function, 'local_payload:scale_trade');
SELECT assert_eq('gs quant canonical 0068 gs_quant/backtests/backtest_utils.py map_ccy_name_to_ccy', fin_backtest_map_ccy_name_to_ccy('local_payload').payload || ':' || fin_backtest_map_ccy_name_to_ccy('local_payload').source_function, 'local_payload:map_ccy_name_to_ccy');
SELECT assert_eq('gs quant canonical 0069 gs_quant/backtests/backtest_utils.py interpolate_signal', fin_backtest_interpolate_signal('local_payload').payload || ':' || fin_backtest_interpolate_signal('local_payload').source_function, 'local_payload:interpolate_signal');
SELECT assert_eq('gs quant canonical 0070 gs_quant/backtests/decorator.py plot_backtest', fin_backtest_plot_backtest('local_payload').payload || ':' || fin_backtest_plot_backtest('local_payload').source_function, 'local_payload:plot_backtest');
SELECT assert_eq('gs quant canonical 0071 gs_quant/backtests/equity_vol_engine.py get_backtest_trading_quantity_type', fin_backtest_get_backtest_trading_quantity_type('local_payload').payload || ':' || fin_backtest_get_backtest_trading_quantity_type('local_payload').source_function, 'local_payload:get_backtest_trading_quantity_type');
SELECT assert_eq('gs quant canonical 0072 gs_quant/backtests/equity_vol_engine.py is_synthetic_forward', fin_backtest_is_synthetic_forward('local_payload').payload || ':' || fin_backtest_is_synthetic_forward('local_payload').source_function, 'local_payload:is_synthetic_forward');
SELECT assert_eq('gs quant canonical 0073 gs_quant/backtests/generic_engine.py raiser', fin_backtest_raiser('local_payload').payload || ':' || fin_backtest_raiser('local_payload').source_function, 'local_payload:raiser');
SELECT assert_eq('gs quant canonical 0074 gs_quant/backtests/triggers.py check_barrier', fin_backtest_check_barrier('local_payload').payload || ':' || fin_backtest_check_barrier('local_payload').source_function, 'local_payload:check_barrier');
SELECT assert_eq('gs quant canonical 0075 gs_quant/base.py exclude_none', fin_gsq_support_exclude_none('local_payload').payload || ':' || fin_gsq_support_exclude_none('local_payload').source_function, 'local_payload:exclude_none');
SELECT assert_eq('gs quant canonical 0076 gs_quant/base.py exclude_always', fin_gsq_support_exclude_always('local_payload').payload || ':' || fin_gsq_support_exclude_always('local_payload').source_function, 'local_payload:exclude_always');
SELECT assert_eq('gs quant canonical 0077 gs_quant/base.py is_iterable', fin_gsq_support_is_iterable('local_payload').payload || ':' || fin_gsq_support_is_iterable('local_payload').source_function, 'local_payload:is_iterable');
SELECT assert_eq('gs quant canonical 0078 gs_quant/base.py is_instance_or_iterable', fin_gsq_support_is_instance_or_iterable('local_payload').payload || ':' || fin_gsq_support_is_instance_or_iterable('local_payload').source_function, 'local_payload:is_instance_or_iterable');
SELECT assert_eq('gs quant canonical 0079 gs_quant/base.py handle_camel_case_args', fin_gsq_support_handle_camel_case_args('local_payload').payload || ':' || fin_gsq_support_handle_camel_case_args('local_payload').source_function, 'local_payload:handle_camel_case_args');
SELECT assert_eq('gs quant canonical 0080 gs_quant/base.py static_field', fin_gsq_support_static_field('local_payload').payload || ':' || fin_gsq_support_static_field('local_payload').source_function, 'local_payload:static_field');
SELECT assert_eq('gs quant canonical 0081 gs_quant/base.py get_enum_value', fin_gsq_support_get_enum_value('local_payload').payload || ':' || fin_gsq_support_get_enum_value('local_payload').source_function, 'local_payload:get_enum_value');
SELECT assert_eq('gs quant canonical 0082 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py persistXls', fin_content_persistxls('local_payload').payload || ':' || fin_content_persistxls('local_payload').source_function, 'local_payload:persistXls');
SELECT assert_eq('gs quant canonical 0083 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotGross', fin_content_plotgross('local_payload').payload || ':' || fin_content_plotgross('local_payload').source_function, 'local_payload:plotGross');
SELECT assert_eq('gs quant canonical 0084 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotCost', fin_content_plotcost('local_payload').payload || ':' || fin_content_plotcost('local_payload').source_function, 'local_payload:plotCost');
SELECT assert_eq('gs quant canonical 0085 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotVar', fin_content_plotvar('local_payload').payload || ':' || fin_content_plotvar('local_payload').source_function, 'local_payload:plotVar');
SELECT assert_eq('gs quant canonical 0086 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotBuySellNet', fin_content_plotbuysellnet('local_payload').payload || ':' || fin_content_plotbuysellnet('local_payload').source_function, 'local_payload:plotBuySellNet');
SELECT assert_eq('gs quant canonical 0087 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotGrossRemaining', fin_content_plotgrossremaining('local_payload').payload || ':' || fin_content_plotgrossremaining('local_payload').source_function, 'local_payload:plotGrossRemaining');
SELECT assert_eq('gs quant canonical 0088 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotMultiStrategyPortfolioLevelAnalytics', fin_content_plotmultistrategyportfoliolevelanalytics('local_payload').payload || ':' || fin_content_plotmultistrategyportfoliolevelanalytics('local_payload').source_function, 'local_payload:plotMultiStrategyPortfolioLevelAnalytics');
SELECT assert_eq('gs quant canonical 0089 gs_quant/content/reports_and_screens/00_fx/vol_screen_app.py format_df', fin_content_format_df('local_payload').payload || ':' || fin_content_format_df('local_payload').source_function, 'local_payload:format_df');
SELECT assert_eq('gs quant canonical 0090 gs_quant/content/reports_and_screens/00_fx/vol_screen_app.py volatility_screen', fin_content_volatility_screen('local_payload').payload || ':' || fin_content_volatility_screen('local_payload').source_function, 'local_payload:volatility_screen');
SELECT assert_eq('gs quant canonical 0091 gs_quant/data/log.py log_debug', fin_gsq_support_log_debug('local_payload').payload || ':' || fin_gsq_support_log_debug('local_payload').source_function, 'local_payload:log_debug');
SELECT assert_eq('gs quant canonical 0092 gs_quant/data/log.py log_warning', fin_gsq_support_log_warning('local_payload').payload || ':' || fin_gsq_support_log_warning('local_payload').source_function, 'local_payload:log_warning');
SELECT assert_eq('gs quant canonical 0093 gs_quant/data/log.py log_info', fin_gsq_support_log_info('local_payload').payload || ':' || fin_gsq_support_log_info('local_payload').source_function, 'local_payload:log_info');
SELECT assert_eq('gs quant canonical 0094 gs_quant/errors.py error_builder', fin_gsq_support_error_builder('local_payload').payload || ':' || fin_gsq_support_error_builder('local_payload').source_function, 'local_payload:error_builder');
SELECT assert_eq('gs quant canonical 0095 gs_quant/instrument/core.py encode_instrument', fin_gsq_support_encode_instrument('local_payload').payload || ':' || fin_gsq_support_encode_instrument('local_payload').source_function, 'local_payload:encode_instrument');
SELECT assert_eq('gs quant canonical 0096 gs_quant/instrument/core.py encode_instruments', fin_gsq_support_encode_instruments('local_payload').payload || ':' || fin_gsq_support_encode_instruments('local_payload').source_function, 'local_payload:encode_instruments');
SELECT assert_eq('gs quant canonical 0097 gs_quant/json_convertors.py encode_date_or_str', fin_json_encode_date_or_str('local_payload').payload || ':' || fin_json_encode_date_or_str('local_payload').source_function, 'local_payload:encode_date_or_str');
SELECT assert_eq('gs quant canonical 0098 gs_quant/json_convertors.py decode_optional_date_or_time', fin_json_decode_optional_date_or_time('local_payload').payload || ':' || fin_json_decode_optional_date_or_time('local_payload').source_function, 'local_payload:decode_optional_date_or_time');
SELECT assert_eq('gs quant canonical 0099 gs_quant/json_convertors.py decode_optional_date', fin_json_decode_optional_date('local_payload').payload || ':' || fin_json_decode_optional_date('local_payload').source_function, 'local_payload:decode_optional_date');
SELECT assert_eq('gs quant canonical 0100 gs_quant/json_convertors.py decode_optional_time', fin_json_decode_optional_time('local_payload').payload || ':' || fin_json_decode_optional_time('local_payload').source_function, 'local_payload:decode_optional_time');
SELECT assert_eq('gs quant canonical 0101 gs_quant/json_convertors.py encode_optional_time', fin_json_encode_optional_time('local_payload').payload || ':' || fin_json_encode_optional_time('local_payload').source_function, 'local_payload:encode_optional_time');
SELECT assert_eq('gs quant canonical 0102 gs_quant/json_convertors.py decode_date_tuple', fin_json_decode_date_tuple('local_payload').payload || ':' || fin_json_decode_date_tuple('local_payload').source_function, 'local_payload:decode_date_tuple');
SELECT assert_eq('gs quant canonical 0103 gs_quant/json_convertors.py decode_date_or_time_tuple', fin_json_decode_date_or_time_tuple('local_payload').payload || ':' || fin_json_decode_date_or_time_tuple('local_payload').source_function, 'local_payload:decode_date_or_time_tuple');
SELECT assert_eq('gs quant canonical 0104 gs_quant/json_convertors.py encode_date_tuple', fin_json_encode_date_tuple('local_payload').payload || ':' || fin_json_encode_date_tuple('local_payload').source_function, 'local_payload:encode_date_tuple');
SELECT assert_eq('gs quant canonical 0105 gs_quant/json_convertors.py encode_date_or_time_tuple', fin_json_encode_date_or_time_tuple('local_payload').payload || ':' || fin_json_encode_date_or_time_tuple('local_payload').source_function, 'local_payload:encode_date_or_time_tuple');
SELECT assert_eq('gs quant canonical 0106 gs_quant/json_convertors.py decode_iso_date_or_datetime', fin_json_decode_iso_date_or_datetime('local_payload').payload || ':' || fin_json_decode_iso_date_or_datetime('local_payload').source_function, 'local_payload:decode_iso_date_or_datetime');
SELECT assert_eq('gs quant canonical 0107 gs_quant/json_convertors.py optional_from_isodatetime', fin_json_optional_from_isodatetime('local_payload').payload || ':' || fin_json_optional_from_isodatetime('local_payload').source_function, 'local_payload:optional_from_isodatetime');
SELECT assert_eq('gs quant canonical 0108 gs_quant/json_convertors.py optional_to_isodatetime', fin_json_optional_to_isodatetime('local_payload').payload || ':' || fin_json_optional_to_isodatetime('local_payload').source_function, 'local_payload:optional_to_isodatetime');
SELECT assert_eq('gs quant canonical 0109 gs_quant/json_convertors.py decode_dict_date_key', fin_json_decode_dict_date_key('local_payload').payload || ':' || fin_json_decode_dict_date_key('local_payload').source_function, 'local_payload:decode_dict_date_key');
SELECT assert_eq('gs quant canonical 0110 gs_quant/json_convertors.py decode_dict_date_key_or_float', fin_json_decode_dict_date_key_or_float('local_payload').payload || ':' || fin_json_decode_dict_date_key_or_float('local_payload').source_function, 'local_payload:decode_dict_date_key_or_float');
SELECT assert_eq('gs quant canonical 0111 gs_quant/json_convertors.py decode_dict_dict_date_key', fin_json_decode_dict_dict_date_key('local_payload').payload || ':' || fin_json_decode_dict_dict_date_key('local_payload').source_function, 'local_payload:decode_dict_dict_date_key');
SELECT assert_eq('gs quant canonical 0112 gs_quant/json_convertors.py decode_dict_date_value', fin_json_decode_dict_date_value('local_payload').payload || ':' || fin_json_decode_dict_date_value('local_payload').source_function, 'local_payload:decode_dict_date_value');
SELECT assert_eq('gs quant canonical 0113 gs_quant/json_convertors.py decode_datetime_tuple', fin_json_decode_datetime_tuple('local_payload').payload || ':' || fin_json_decode_datetime_tuple('local_payload').source_function, 'local_payload:decode_datetime_tuple');
SELECT assert_eq('gs quant canonical 0114 gs_quant/json_convertors.py decode_date_or_str', fin_json_decode_date_or_str('local_payload').payload || ':' || fin_json_decode_date_or_str('local_payload').source_function, 'local_payload:decode_date_or_str');
SELECT assert_eq('gs quant canonical 0115 gs_quant/json_convertors.py encode_datetime', fin_json_encode_datetime('local_payload').payload || ':' || fin_json_encode_datetime('local_payload').source_function, 'local_payload:encode_datetime');
SELECT assert_eq('gs quant canonical 0116 gs_quant/json_convertors.py decode_datetime', fin_json_decode_datetime('local_payload').payload || ':' || fin_json_decode_datetime('local_payload').source_function, 'local_payload:decode_datetime');
SELECT assert_eq('gs quant canonical 0117 gs_quant/json_convertors.py decode_float_or_str', fin_json_decode_float_or_str('local_payload').payload || ':' || fin_json_decode_float_or_str('local_payload').source_function, 'local_payload:decode_float_or_str');
SELECT assert_eq('gs quant canonical 0118 gs_quant/json_convertors.py decode_instrument', fin_json_decode_instrument('local_payload').payload || ':' || fin_json_decode_instrument('local_payload').source_function, 'local_payload:decode_instrument');
SELECT assert_eq('gs quant canonical 0119 gs_quant/json_convertors.py decode_named_instrument', fin_json_decode_named_instrument('local_payload').payload || ':' || fin_json_decode_named_instrument('local_payload').source_function, 'local_payload:decode_named_instrument');
SELECT assert_eq('gs quant canonical 0120 gs_quant/json_convertors.py decode_named_portfolio', fin_json_decode_named_portfolio('local_payload').payload || ':' || fin_json_decode_named_portfolio('local_payload').source_function, 'local_payload:decode_named_portfolio');
SELECT assert_eq('gs quant canonical 0121 gs_quant/json_convertors.py encode_named_instrument', fin_json_encode_named_instrument('local_payload').payload || ':' || fin_json_encode_named_instrument('local_payload').source_function, 'local_payload:encode_named_instrument');
SELECT assert_eq('gs quant canonical 0122 gs_quant/json_convertors.py encode_named_portfolio', fin_json_encode_named_portfolio('local_payload').payload || ':' || fin_json_encode_named_portfolio('local_payload').source_function, 'local_payload:encode_named_portfolio');
SELECT assert_eq('gs quant canonical 0123 gs_quant/json_convertors.py encode_pandas_series', fin_json_encode_pandas_series('local_payload').payload || ':' || fin_json_encode_pandas_series('local_payload').source_function, 'local_payload:encode_pandas_series');
SELECT assert_eq('gs quant canonical 0124 gs_quant/json_convertors.py decode_pandas_series', fin_json_decode_pandas_series('local_payload').payload || ':' || fin_json_decode_pandas_series('local_payload').source_function, 'local_payload:decode_pandas_series');
SELECT assert_eq('gs quant canonical 0125 gs_quant/json_convertors.py decode_quote_report', fin_json_decode_quote_report('local_payload').payload || ':' || fin_json_decode_quote_report('local_payload').source_function, 'local_payload:decode_quote_report');
SELECT assert_eq('gs quant canonical 0126 gs_quant/json_convertors.py decode_quote_reports', fin_json_decode_quote_reports('local_payload').payload || ':' || fin_json_decode_quote_reports('local_payload').source_function, 'local_payload:decode_quote_reports');
SELECT assert_eq('gs quant canonical 0127 gs_quant/json_convertors.py decode_custom_comment', fin_json_decode_custom_comment('local_payload').payload || ':' || fin_json_decode_custom_comment('local_payload').source_function, 'local_payload:decode_custom_comment');
SELECT assert_eq('gs quant canonical 0128 gs_quant/json_convertors.py decode_custom_comments', fin_json_decode_custom_comments('local_payload').payload || ':' || fin_json_decode_custom_comments('local_payload').source_function, 'local_payload:decode_custom_comments');
SELECT assert_eq('gs quant canonical 0129 gs_quant/json_convertors.py decode_hedge_type', fin_json_decode_hedge_type('local_payload').payload || ':' || fin_json_decode_hedge_type('local_payload').source_function, 'local_payload:decode_hedge_type');
SELECT assert_eq('gs quant canonical 0130 gs_quant/json_convertors.py decode_hedge_types', fin_json_decode_hedge_types('local_payload').payload || ':' || fin_json_decode_hedge_types('local_payload').source_function, 'local_payload:decode_hedge_types');
SELECT assert_eq('gs quant canonical 0131 gs_quant/json_convertors.py encode_dictable', fin_json_encode_dictable('local_payload').payload || ':' || fin_json_encode_dictable('local_payload').source_function, 'local_payload:encode_dictable');
SELECT assert_eq('gs quant canonical 0132 gs_quant/json_convertors.py encode_named_dictable', fin_json_encode_named_dictable('local_payload').payload || ':' || fin_json_encode_named_dictable('local_payload').source_function, 'local_payload:encode_named_dictable');
SELECT assert_eq('gs quant canonical 0133 gs_quant/json_convertors.py dc_decode', fin_json_dc_decode('local_payload').payload || ':' || fin_json_dc_decode('local_payload').source_function, 'local_payload:dc_decode');
SELECT assert_eq('gs quant canonical 0134 gs_quant/json_convertors.py encode_timedelta', fin_json_encode_timedelta('local_payload').payload || ':' || fin_json_encode_timedelta('local_payload').source_function, 'local_payload:encode_timedelta');
SELECT assert_eq('gs quant canonical 0135 gs_quant/json_convertors.py decode_timedelta', fin_json_decode_timedelta('local_payload').payload || ':' || fin_json_decode_timedelta('local_payload').source_function, 'local_payload:decode_timedelta');
SELECT assert_eq('gs quant canonical 0136 gs_quant/json_convertors.py encode_callable', fin_json_encode_callable('local_payload').payload || ':' || fin_json_encode_callable('local_payload').source_function, 'local_payload:encode_callable');
SELECT assert_eq('gs quant canonical 0137 gs_quant/json_convertors.py decode_callable', fin_json_decode_callable('local_payload').payload || ':' || fin_json_decode_callable('local_payload').source_function, 'local_payload:decode_callable');
SELECT assert_eq('gs quant canonical 0138 gs_quant/json_convertors_common.py gsq_rm_for_name', fin_json_gsq_rm_for_name('local_payload').payload || ':' || fin_json_gsq_rm_for_name('local_payload').source_function, 'local_payload:gsq_rm_for_name');
SELECT assert_eq('gs quant canonical 0139 gs_quant/json_convertors_common.py encode_risk_measure', fin_json_encode_risk_measure('local_payload').payload || ':' || fin_json_encode_risk_measure('local_payload').source_function, 'local_payload:encode_risk_measure');
SELECT assert_eq('gs quant canonical 0140 gs_quant/json_convertors_common.py encode_risk_measure_tuple', fin_json_encode_risk_measure_tuple('local_payload').payload || ':' || fin_json_encode_risk_measure_tuple('local_payload').source_function, 'local_payload:encode_risk_measure_tuple');
SELECT assert_eq('gs quant canonical 0141 gs_quant/json_convertors_common.py decode_risk_measure', fin_json_decode_risk_measure('local_payload').payload || ':' || fin_json_decode_risk_measure('local_payload').source_function, 'local_payload:decode_risk_measure');
SELECT assert_eq('gs quant canonical 0142 gs_quant/json_convertors_common.py decode_risk_measure_tuple', fin_json_decode_risk_measure_tuple('local_payload').payload || ':' || fin_json_decode_risk_measure_tuple('local_payload').source_function, 'local_payload:decode_risk_measure_tuple');
SELECT assert_eq('gs quant canonical 0143 gs_quant/json_encoder.py encode_default', fin_json_encode_default('local_payload').payload || ':' || fin_json_encode_default('local_payload').source_function, 'local_payload:encode_default');
SELECT assert_eq('gs quant canonical 0144 gs_quant/markets/indices_utils.py get_my_baskets', fin_api_get_my_baskets('local_payload').payload || ':' || fin_api_get_my_baskets('local_payload').source_function, 'local_payload:get_my_baskets');
SELECT assert_eq('gs quant canonical 0145 gs_quant/markets/indices_utils.py get_flagship_baskets', fin_api_get_flagship_baskets('local_payload').payload || ':' || fin_api_get_flagship_baskets('local_payload').source_function, 'local_payload:get_flagship_baskets');
SELECT assert_eq('gs quant canonical 0146 gs_quant/markets/indices_utils.py get_flagships_with_assets', fin_api_get_flagships_with_assets('local_payload').payload || ':' || fin_api_get_flagships_with_assets('local_payload').source_function, 'local_payload:get_flagships_with_assets');
SELECT assert_eq('gs quant canonical 0147 gs_quant/markets/indices_utils.py get_flagships_performance', fin_api_get_flagships_performance('local_payload').payload || ':' || fin_api_get_flagships_performance('local_payload').source_function, 'local_payload:get_flagships_performance');
SELECT assert_eq('gs quant canonical 0148 gs_quant/markets/indices_utils.py get_flagships_constituents', fin_api_get_flagships_constituents('local_payload').payload || ':' || fin_api_get_flagships_constituents('local_payload').source_function, 'local_payload:get_flagships_constituents');
SELECT assert_eq('gs quant canonical 0149 gs_quant/markets/indices_utils.py get_constituents_dataset_coverage', fin_api_get_constituents_dataset_coverage('local_payload').payload || ':' || fin_api_get_constituents_dataset_coverage('local_payload').source_function, 'local_payload:get_constituents_dataset_coverage');
SELECT assert_eq('gs quant canonical 0150 gs_quant/markets/markets.py historical_risk_key', fin_api_historical_risk_key('local_payload').payload || ':' || fin_api_historical_risk_key('local_payload').source_function, 'local_payload:historical_risk_key');
SELECT assert_eq('gs quant canonical 0151 gs_quant/markets/markets.py market_location', fin_api_market_location('local_payload').payload || ':' || fin_api_market_location('local_payload').source_function, 'local_payload:market_location');
SELECT assert_eq('gs quant canonical 0152 gs_quant/markets/markets.py close_market_date', fin_api_close_market_date('local_payload').payload || ':' || fin_api_close_market_date('local_payload').source_function, 'local_payload:close_market_date');
SELECT assert_eq('gs quant canonical 0153 gs_quant/markets/optimizer.py resolve_assets_in_batches', fin_api_resolve_assets_in_batches('local_payload').payload || ':' || fin_api_resolve_assets_in_batches('local_payload').source_function, 'local_payload:resolve_assets_in_batches');
SELECT assert_eq('gs quant canonical 0154 gs_quant/markets/portfolio_manager_utils.py build_macro_portfolio_exposure_df', fin_api_build_macro_portfolio_exposure_df('local_payload').payload || ':' || fin_api_build_macro_portfolio_exposure_df('local_payload').source_function, 'local_payload:build_macro_portfolio_exposure_df');
SELECT assert_eq('gs quant canonical 0155 gs_quant/markets/portfolio_manager_utils.py build_portfolio_constituents_df', fin_api_build_portfolio_constituents_df('local_payload').payload || ':' || fin_api_build_portfolio_constituents_df('local_payload').source_function, 'local_payload:build_portfolio_constituents_df');
SELECT assert_eq('gs quant canonical 0156 gs_quant/markets/portfolio_manager_utils.py build_sensitivity_df', fin_api_build_sensitivity_df('local_payload').payload || ':' || fin_api_build_sensitivity_df('local_payload').source_function, 'local_payload:build_sensitivity_df');
SELECT assert_eq('gs quant canonical 0157 gs_quant/markets/portfolio_manager_utils.py build_exposure_df', fin_api_build_exposure_df('local_payload').payload || ':' || fin_api_build_exposure_df('local_payload').source_function, 'local_payload:build_exposure_df');
SELECT assert_eq('gs quant canonical 0158 gs_quant/markets/portfolio_manager_utils.py get_batched_dates', fin_api_get_batched_dates('local_payload').payload || ':' || fin_api_get_batched_dates('local_payload').source_function, 'local_payload:get_batched_dates');
SELECT assert_eq('gs quant canonical 0159 gs_quant/markets/report.py get_thematic_breakdown_as_df', fin_api_get_thematic_breakdown_as_df('local_payload').payload || ':' || fin_api_get_thematic_breakdown_as_df('local_payload').source_function, 'local_payload:get_thematic_breakdown_as_df');
SELECT assert_eq('gs quant canonical 0160 gs_quant/markets/report.py flatten_results_into_df', fin_api_flatten_results_into_df('local_payload').payload || ':' || fin_api_flatten_results_into_df('local_payload').source_function, 'local_payload:flatten_results_into_df');
SELECT assert_eq('gs quant canonical 0161 gs_quant/markets/report.py get_pnl_percent', fin_api_get_pnl_percent('local_payload').payload || ':' || fin_api_get_pnl_percent('local_payload').source_function, 'local_payload:get_pnl_percent');
SELECT assert_eq('gs quant canonical 0162 gs_quant/markets/report.py get_factor_pnl_percent_for_single_factor', fin_api_get_factor_pnl_percent_for_single_factor('local_payload').payload || ':' || fin_api_get_factor_pnl_percent_for_single_factor('local_payload').source_function, 'local_payload:get_factor_pnl_percent_for_single_factor');
SELECT assert_eq('gs quant canonical 0163 gs_quant/markets/report.py format_factor_pnl_for_return_calculation', fin_api_format_factor_pnl_for_return_calculation('local_payload').payload || ':' || fin_api_format_factor_pnl_for_return_calculation('local_payload').source_function, 'local_payload:format_factor_pnl_for_return_calculation');
SELECT assert_eq('gs quant canonical 0164 gs_quant/markets/report.py format_aum_for_return_calculation', fin_api_format_aum_for_return_calculation('local_payload').payload || ':' || fin_api_format_aum_for_return_calculation('local_payload').source_function, 'local_payload:format_aum_for_return_calculation');
SELECT assert_eq('gs quant canonical 0165 gs_quant/markets/report.py generate_daily_returns', fin_api_generate_daily_returns('local_payload').payload || ':' || fin_api_generate_daily_returns('local_payload').source_function, 'local_payload:generate_daily_returns');
SELECT assert_eq('gs quant canonical 0166 gs_quant/models/epidemiology.py switch', fin_gsq_support_switch('local_payload').payload || ':' || fin_gsq_support_switch('local_payload').source_function, 'local_payload:switch');
SELECT assert_eq('gs quant canonical 0167 gs_quant/models/risk_model_utils.py build_factor_id_to_name_map', fin_gsq_support_build_factor_id_to_name_map('local_payload').payload || ':' || fin_gsq_support_build_factor_id_to_name_map('local_payload').source_function, 'local_payload:build_factor_id_to_name_map');
SELECT assert_eq('gs quant canonical 0168 gs_quant/models/risk_model_utils.py build_asset_data_map', fin_gsq_support_build_asset_data_map('local_payload').payload || ':' || fin_gsq_support_build_asset_data_map('local_payload').source_function, 'local_payload:build_asset_data_map');
SELECT assert_eq('gs quant canonical 0169 gs_quant/models/risk_model_utils.py build_factor_data_map', fin_gsq_support_build_factor_data_map('local_payload').payload || ':' || fin_gsq_support_build_factor_data_map('local_payload').source_function, 'local_payload:build_factor_data_map');
SELECT assert_eq('gs quant canonical 0170 gs_quant/models/risk_model_utils.py build_pfp_data_dataframe', fin_gsq_support_build_pfp_data_dataframe('local_payload').payload || ':' || fin_gsq_support_build_pfp_data_dataframe('local_payload').source_function, 'local_payload:build_pfp_data_dataframe');
SELECT assert_eq('gs quant canonical 0171 gs_quant/models/risk_model_utils.py get_optional_data_as_dataframe', fin_gsq_support_get_optional_data_as_dataframe('local_payload').payload || ':' || fin_gsq_support_get_optional_data_as_dataframe('local_payload').source_function, 'local_payload:get_optional_data_as_dataframe');
SELECT assert_eq('gs quant canonical 0172 gs_quant/models/risk_model_utils.py get_covariance_matrix_dataframe', fin_gsq_support_get_covariance_matrix_dataframe('local_payload').payload || ':' || fin_gsq_support_get_covariance_matrix_dataframe('local_payload').source_function, 'local_payload:get_covariance_matrix_dataframe');
SELECT assert_eq('gs quant canonical 0173 gs_quant/models/risk_model_utils.py build_factor_volatility_dataframe', fin_gsq_support_build_factor_volatility_dataframe('local_payload').payload || ':' || fin_gsq_support_build_factor_volatility_dataframe('local_payload').source_function, 'local_payload:build_factor_volatility_dataframe');
SELECT assert_eq('gs quant canonical 0174 gs_quant/models/risk_model_utils.py get_closest_date_index', fin_gsq_support_get_closest_date_index('local_payload').payload || ':' || fin_gsq_support_get_closest_date_index('local_payload').source_function, 'local_payload:get_closest_date_index');
SELECT assert_eq('gs quant canonical 0175 gs_quant/models/risk_model_utils.py divide_request', fin_gsq_support_divide_request('local_payload').payload || ':' || fin_gsq_support_divide_request('local_payload').source_function, 'local_payload:divide_request');
SELECT assert_eq('gs quant canonical 0176 gs_quant/models/risk_model_utils.py batch_and_upload_partial_data_use_target_universe_size', fin_gsq_support_batch_and_upload_partial_data_use_target_universe_size('local_payload').payload || ':' || fin_gsq_support_batch_and_upload_partial_data_use_target_universe_size('local_payload').source_function, 'local_payload:batch_and_upload_partial_data_use_target_universe_size');
SELECT assert_eq('gs quant canonical 0177 gs_quant/models/risk_model_utils.py only_factor_data_is_present', fin_gsq_support_only_factor_data_is_present('local_payload').payload || ':' || fin_gsq_support_only_factor_data_is_present('local_payload').source_function, 'local_payload:only_factor_data_is_present');
SELECT assert_eq('gs quant canonical 0178 gs_quant/models/risk_model_utils.py batch_and_upload_partial_data', fin_gsq_support_batch_and_upload_partial_data('local_payload').payload || ':' || fin_gsq_support_batch_and_upload_partial_data('local_payload').source_function, 'local_payload:batch_and_upload_partial_data');
SELECT assert_eq('gs quant canonical 0179 gs_quant/models/risk_model_utils.py batch_and_upload_coverage_data', fin_gsq_support_batch_and_upload_coverage_data('local_payload').payload || ':' || fin_gsq_support_batch_and_upload_coverage_data('local_payload').source_function, 'local_payload:batch_and_upload_coverage_data');
SELECT assert_eq('gs quant canonical 0180 gs_quant/models/risk_model_utils.py upload_model_data', fin_gsq_support_upload_model_data('local_payload').payload || ':' || fin_gsq_support_upload_model_data('local_payload').source_function, 'local_payload:upload_model_data');
SELECT assert_eq('gs quant canonical 0181 gs_quant/models/risk_model_utils.py risk_model_data_to_json', fin_gsq_support_risk_model_data_to_json('local_payload').payload || ':' || fin_gsq_support_risk_model_data_to_json('local_payload').source_function, 'local_payload:risk_model_data_to_json');
SELECT assert_eq('gs quant canonical 0182 gs_quant/models/risk_model_utils.py get_universe_size', fin_gsq_support_get_universe_size('local_payload').payload || ':' || fin_gsq_support_get_universe_size('local_payload').source_function, 'local_payload:get_universe_size');
SELECT assert_eq('gs quant canonical 0183 gs_quant/quote_reports/core.py quote_report_from_dict', fin_gsq_support_quote_report_from_dict('local_payload').payload || ':' || fin_gsq_support_quote_report_from_dict('local_payload').source_function, 'local_payload:quote_report_from_dict');
SELECT assert_eq('gs quant canonical 0184 gs_quant/quote_reports/core.py quote_reports_from_dicts', fin_gsq_support_quote_reports_from_dicts('local_payload').payload || ':' || fin_gsq_support_quote_reports_from_dicts('local_payload').source_function, 'local_payload:quote_reports_from_dicts');
SELECT assert_eq('gs quant canonical 0185 gs_quant/quote_reports/core.py custom_comment_from_dict', fin_gsq_support_custom_comment_from_dict('local_payload').payload || ':' || fin_gsq_support_custom_comment_from_dict('local_payload').source_function, 'local_payload:custom_comment_from_dict');
SELECT assert_eq('gs quant canonical 0186 gs_quant/quote_reports/core.py custom_comments_from_dicts', fin_gsq_support_custom_comments_from_dicts('local_payload').payload || ':' || fin_gsq_support_custom_comments_from_dicts('local_payload').source_function, 'local_payload:custom_comments_from_dicts');
SELECT assert_eq('gs quant canonical 0187 gs_quant/quote_reports/core.py hedge_type_from_dict', fin_gsq_support_hedge_type_from_dict('local_payload').payload || ':' || fin_gsq_support_hedge_type_from_dict('local_payload').source_function, 'local_payload:hedge_type_from_dict');
SELECT assert_eq('gs quant canonical 0188 gs_quant/quote_reports/core.py hedge_type_from_dicts', fin_gsq_support_hedge_type_from_dicts('local_payload').payload || ':' || fin_gsq_support_hedge_type_from_dicts('local_payload').source_function, 'local_payload:hedge_type_from_dicts');
SELECT assert_eq('gs quant canonical 0189 gs_quant/risk/core.py aggregate_risk', fin_risk_aggregate_risk('local_payload').payload || ':' || fin_risk_aggregate_risk('local_payload').source_function, 'local_payload:aggregate_risk');
SELECT assert_eq('gs quant canonical 0190 gs_quant/risk/core.py aggregate_results', fin_risk_aggregate_results('local_payload').payload || ':' || fin_risk_aggregate_results('local_payload').source_function, 'local_payload:aggregate_results');
SELECT assert_eq('gs quant canonical 0191 gs_quant/risk/core.py subtract_risk', fin_risk_subtract_risk('local_payload').payload || ':' || fin_risk_subtract_risk('local_payload').source_function, 'local_payload:subtract_risk');
SELECT assert_eq('gs quant canonical 0192 gs_quant/risk/core.py sort_values', fin_risk_sort_values('local_payload').payload || ':' || fin_risk_sort_values('local_payload').source_function, 'local_payload:sort_values');
SELECT assert_eq('gs quant canonical 0193 gs_quant/risk/core.py sort_risk', fin_risk_sort_risk('local_payload').payload || ':' || fin_risk_sort_risk('local_payload').source_function, 'local_payload:sort_risk');
SELECT assert_eq('gs quant canonical 0194 gs_quant/risk/core.py combine_risk_key', fin_risk_combine_risk_key('local_payload').payload || ':' || fin_risk_combine_risk_key('local_payload').source_function, 'local_payload:combine_risk_key');
SELECT assert_eq('gs quant canonical 0195 gs_quant/risk/result_handlers.py cashflows_handler', fin_risk_cashflows_handler('local_payload').payload || ':' || fin_risk_cashflows_handler('local_payload').source_function, 'local_payload:cashflows_handler');
SELECT assert_eq('gs quant canonical 0196 gs_quant/risk/result_handlers.py error_handler', fin_risk_error_handler('local_payload').payload || ':' || fin_risk_error_handler('local_payload').source_function, 'local_payload:error_handler');
SELECT assert_eq('gs quant canonical 0197 gs_quant/risk/result_handlers.py leg_definition_handler', fin_risk_leg_definition_handler('local_payload').payload || ':' || fin_risk_leg_definition_handler('local_payload').source_function, 'local_payload:leg_definition_handler');
SELECT assert_eq('gs quant canonical 0198 gs_quant/risk/result_handlers.py message_handler', fin_risk_message_handler('local_payload').payload || ':' || fin_risk_message_handler('local_payload').source_function, 'local_payload:message_handler');
SELECT assert_eq('gs quant canonical 0199 gs_quant/risk/result_handlers.py number_and_unit_handler', fin_risk_number_and_unit_handler('local_payload').payload || ':' || fin_risk_number_and_unit_handler('local_payload').source_function, 'local_payload:number_and_unit_handler');
SELECT assert_eq('gs quant canonical 0200 gs_quant/risk/result_handlers.py required_assets_handler', fin_risk_required_assets_handler('local_payload').payload || ':' || fin_risk_required_assets_handler('local_payload').source_function, 'local_payload:required_assets_handler');
SELECT assert_eq('gs quant canonical 0201 gs_quant/risk/result_handlers.py dict_risk_handler', fin_risk_dict_risk_handler('local_payload').payload || ':' || fin_risk_dict_risk_handler('local_payload').source_function, 'local_payload:dict_risk_handler');
SELECT assert_eq('gs quant canonical 0202 gs_quant/risk/result_handlers.py risk_handler', fin_risk_risk_handler('local_payload').payload || ':' || fin_risk_risk_handler('local_payload').source_function, 'local_payload:risk_handler');
SELECT assert_eq('gs quant canonical 0203 gs_quant/risk/result_handlers.py risk_by_class_handler', fin_risk_risk_by_class_handler('local_payload').payload || ':' || fin_risk_risk_by_class_handler('local_payload').source_function, 'local_payload:risk_by_class_handler');
SELECT assert_eq('gs quant canonical 0204 gs_quant/risk/result_handlers.py risk_vector_handler', fin_risk_risk_vector_handler('local_payload').payload || ':' || fin_risk_risk_vector_handler('local_payload').source_function, 'local_payload:risk_vector_handler');
SELECT assert_eq('gs quant canonical 0205 gs_quant/risk/result_handlers.py fixing_table_handler', fin_risk_fixing_table_handler('local_payload').payload || ':' || fin_risk_fixing_table_handler('local_payload').source_function, 'local_payload:fixing_table_handler');
SELECT assert_eq('gs quant canonical 0206 gs_quant/risk/result_handlers.py simple_valtable_handler', fin_risk_simple_valtable_handler('local_payload').payload || ':' || fin_risk_simple_valtable_handler('local_payload').source_function, 'local_payload:simple_valtable_handler');
SELECT assert_eq('gs quant canonical 0207 gs_quant/risk/result_handlers.py canonical_projection_table_handler', fin_risk_canonical_projection_table_handler('local_payload').payload || ':' || fin_risk_canonical_projection_table_handler('local_payload').source_function, 'local_payload:canonical_projection_table_handler');
SELECT assert_eq('gs quant canonical 0208 gs_quant/risk/result_handlers.py risk_float_handler', fin_risk_risk_float_handler('local_payload').payload || ':' || fin_risk_risk_float_handler('local_payload').source_function, 'local_payload:risk_float_handler');
SELECT assert_eq('gs quant canonical 0209 gs_quant/risk/result_handlers.py map_coordinate_to_column', fin_risk_map_coordinate_to_column('local_payload').payload || ':' || fin_risk_map_coordinate_to_column('local_payload').source_function, 'local_payload:map_coordinate_to_column');
SELECT assert_eq('gs quant canonical 0210 gs_quant/risk/result_handlers.py mdapi_second_order_table_handler', fin_risk_mdapi_second_order_table_handler('local_payload').payload || ':' || fin_risk_mdapi_second_order_table_handler('local_payload').source_function, 'local_payload:mdapi_second_order_table_handler');
SELECT assert_eq('gs quant canonical 0211 gs_quant/risk/result_handlers.py mdapi_table_handler', fin_risk_mdapi_table_handler('local_payload').payload || ':' || fin_risk_mdapi_table_handler('local_payload').source_function, 'local_payload:mdapi_table_handler');
SELECT assert_eq('gs quant canonical 0212 gs_quant/risk/result_handlers.py mmapi_table_handler', fin_risk_mmapi_table_handler('local_payload').payload || ':' || fin_risk_mmapi_table_handler('local_payload').source_function, 'local_payload:mmapi_table_handler');
SELECT assert_eq('gs quant canonical 0213 gs_quant/risk/result_handlers.py mmapi_pca_table_handler', fin_risk_mmapi_pca_table_handler('local_payload').payload || ':' || fin_risk_mmapi_pca_table_handler('local_payload').source_function, 'local_payload:mmapi_pca_table_handler');
SELECT assert_eq('gs quant canonical 0214 gs_quant/risk/result_handlers.py mmapi_pca_hedge_table_handler', fin_risk_mmapi_pca_hedge_table_handler('local_payload').payload || ':' || fin_risk_mmapi_pca_hedge_table_handler('local_payload').source_function, 'local_payload:mmapi_pca_hedge_table_handler');
SELECT assert_eq('gs quant canonical 0215 gs_quant/risk/result_handlers.py mqvs_validators_handler', fin_risk_mqvs_validators_handler('local_payload').payload || ':' || fin_risk_mqvs_validators_handler('local_payload').source_function, 'local_payload:mqvs_validators_handler');
SELECT assert_eq('gs quant canonical 0216 gs_quant/risk/result_handlers.py market_handler', fin_risk_market_handler('local_payload').payload || ':' || fin_risk_market_handler('local_payload').source_function, 'local_payload:market_handler');
SELECT assert_eq('gs quant canonical 0217 gs_quant/risk/result_handlers.py unsupported_handler', fin_risk_unsupported_handler('local_payload').payload || ':' || fin_risk_unsupported_handler('local_payload').source_function, 'local_payload:unsupported_handler');
SELECT assert_eq('gs quant canonical 0218 gs_quant/risk/results.py get_default_pivots', fin_risk_get_default_pivots('local_payload').payload || ':' || fin_risk_get_default_pivots('local_payload').source_function, 'local_payload:get_default_pivots');
SELECT assert_eq('gs quant canonical 0219 gs_quant/risk/results.py pivot_to_frame', fin_risk_pivot_to_frame('local_payload').payload || ':' || fin_risk_pivot_to_frame('local_payload').source_function, 'local_payload:pivot_to_frame');
SELECT assert_eq('gs quant canonical 0220 gs_quant/risk/scenario_utils.py build_eq_vol_scenario_intraday', fin_risk_build_eq_vol_scenario_intraday('local_payload').payload || ':' || fin_risk_build_eq_vol_scenario_intraday('local_payload').source_function, 'local_payload:build_eq_vol_scenario_intraday');
SELECT assert_eq('gs quant canonical 0221 gs_quant/risk/scenario_utils.py build_eq_vol_scenario_eod', fin_risk_build_eq_vol_scenario_eod('local_payload').payload || ':' || fin_risk_build_eq_vol_scenario_eod('local_payload').source_function, 'local_payload:build_eq_vol_scenario_eod');
SELECT assert_eq('gs quant canonical 0222 gs_quant/test/analytics/test_datagrid.py test_simple_datagrid', fin_gsq_test_test_simple_datagrid('local_payload').payload || ':' || fin_gsq_test_test_simple_datagrid('local_payload').source_function, 'local_payload:test_simple_datagrid');
SELECT assert_eq('gs quant canonical 0223 gs_quant/test/analytics/test_datagrid.py test_rdate_datagrid', fin_gsq_test_test_rdate_datagrid('local_payload').payload || ':' || fin_gsq_test_test_rdate_datagrid('local_payload').source_function, 'local_payload:test_rdate_datagrid');
SELECT assert_eq('gs quant canonical 0224 gs_quant/test/analytics/test_workspace.py test_layout_creation', fin_gsq_test_test_layout_creation('local_payload').payload || ':' || fin_gsq_test_test_layout_creation('local_payload').source_function, 'local_payload:test_layout_creation');
SELECT assert_eq('gs quant canonical 0225 gs_quant/test/analytics/test_workspace.py test_layout_parsing', fin_gsq_test_test_layout_parsing('local_payload').payload || ':' || fin_gsq_test_test_layout_parsing('local_payload').source_function, 'local_payload:test_layout_parsing');
SELECT assert_eq('gs quant canonical 0226 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_encode_series_result', fin_json_test_encode_series_result('local_payload').payload || ':' || fin_json_test_encode_series_result('local_payload').source_function, 'local_payload:test_encode_series_result');
SELECT assert_eq('gs quant canonical 0227 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_encode_dataframe_result', fin_json_test_encode_dataframe_result('local_payload').payload || ':' || fin_json_test_encode_dataframe_result('local_payload').source_function, 'local_payload:test_encode_dataframe_result');
SELECT assert_eq('gs quant canonical 0228 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_decode_series_result', fin_json_test_decode_series_result('local_payload').payload || ':' || fin_json_test_decode_series_result('local_payload').source_function, 'local_payload:test_decode_series_result');
SELECT assert_eq('gs quant canonical 0229 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_decode_dataframe_result', fin_json_test_decode_dataframe_result('local_payload').payload || ':' || fin_json_test_decode_dataframe_result('local_payload').source_function, 'local_payload:test_decode_dataframe_result');
SELECT assert_eq('gs quant canonical 0230 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_encoders.py test_map_result_to_datatype', fin_json_test_map_result_to_datatype('local_payload').payload || ':' || fin_json_test_map_result_to_datatype('local_payload').source_function, 'local_payload:test_map_result_to_datatype');
SELECT assert_eq('gs quant canonical 0231 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_encoders.py test_decode_risk_result', fin_json_test_decode_risk_result('local_payload').payload || ':' || fin_json_test_decode_risk_result('local_payload').source_function, 'local_payload:test_decode_risk_result');
SELECT assert_eq('gs quant canonical 0232 gs_quant/test/api/backtests_xasset/json_encoders/test_request_encoders.py test_legs_decoder', fin_json_test_legs_decoder('local_payload').payload || ':' || fin_json_test_legs_decoder('local_payload').source_function, 'local_payload:test_legs_decoder');
SELECT assert_eq('gs quant canonical 0233 gs_quant/test/api/backtests_xasset/json_encoders/test_request_encoders.py test_legs_encoder', fin_json_test_legs_encoder('local_payload').payload || ':' || fin_json_test_legs_encoder('local_payload').source_function, 'local_payload:test_legs_encoder');
SELECT assert_eq('gs quant canonical 0234 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_decode_basic_bt_transactions', fin_json_test_decode_basic_bt_transactions('local_payload').payload || ':' || fin_json_test_decode_basic_bt_transactions('local_payload').source_function, 'local_payload:test_decode_basic_bt_transactions');
SELECT assert_eq('gs quant canonical 0235 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_callable_builtin', fin_json_test_encode_callable_builtin('local_payload').payload || ':' || fin_json_test_encode_callable_builtin('local_payload').source_function, 'local_payload:test_encode_callable_builtin');
SELECT assert_eq('gs quant canonical 0236 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_callable_none', fin_json_test_encode_callable_none('local_payload').payload || ':' || fin_json_test_encode_callable_none('local_payload').source_function, 'local_payload:test_encode_callable_none');
SELECT assert_eq('gs quant canonical 0237 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_decode_callable_passthrough', fin_json_test_decode_callable_passthrough('local_payload').payload || ':' || fin_json_test_decode_callable_passthrough('local_payload').source_function, 'local_payload:test_decode_callable_passthrough');
SELECT assert_eq('gs quant canonical 0238 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_callable_named_function', fin_json_test_encode_callable_named_function('local_payload').payload || ':' || fin_json_test_encode_callable_named_function('local_payload').source_function, 'local_payload:test_encode_callable_named_function');
SELECT assert_eq('gs quant canonical 0239 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_decode_callable_rejects_non_allowlisted', fin_json_test_decode_callable_rejects_non_allowlisted('local_payload').payload || ':' || fin_json_test_decode_callable_rejects_non_allowlisted('local_payload').source_function, 'local_payload:test_decode_callable_rejects_non_allowlisted');
SELECT assert_eq('gs quant canonical 0240 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_custom_duration_round_trip', fin_json_test_custom_duration_round_trip('local_payload').payload || ':' || fin_json_test_custom_duration_round_trip('local_payload').source_function, 'local_payload:test_custom_duration_round_trip');
SELECT assert_eq('gs quant canonical 0241 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_custom_duration_json_serializable', fin_json_test_custom_duration_json_serializable('local_payload').payload || ':' || fin_json_test_custom_duration_json_serializable('local_payload').source_function, 'local_payload:test_custom_duration_json_serializable');
SELECT assert_eq('gs quant canonical 0242 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_str', fin_json_test_encode_duration_str('local_payload').payload || ':' || fin_json_test_encode_duration_str('local_payload').source_function, 'local_payload:test_encode_duration_str');
SELECT assert_eq('gs quant canonical 0243 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_date', fin_json_test_encode_duration_date('local_payload').payload || ':' || fin_json_test_encode_duration_date('local_payload').source_function, 'local_payload:test_encode_duration_date');
SELECT assert_eq('gs quant canonical 0244 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_timedelta', fin_json_test_encode_duration_timedelta('local_payload').payload || ':' || fin_json_test_encode_duration_timedelta('local_payload').source_function, 'local_payload:test_encode_duration_timedelta');
SELECT assert_eq('gs quant canonical 0245 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_custom_duration', fin_json_test_encode_duration_custom_duration('local_payload').payload || ':' || fin_json_test_encode_duration_custom_duration('local_payload').source_function, 'local_payload:test_encode_duration_custom_duration');
SELECT assert_eq('gs quant canonical 0246 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_response_obj_callable', fin_json_test_encode_response_obj_callable('local_payload').payload || ':' || fin_json_test_encode_response_obj_callable('local_payload').source_function, 'local_payload:test_encode_response_obj_callable');
SELECT assert_eq('gs quant canonical 0247 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_response_obj_unhandled_type', fin_json_test_encode_response_obj_unhandled_type('local_payload').payload || ':' || fin_json_test_encode_response_obj_unhandled_type('local_payload').source_function, 'local_payload:test_encode_response_obj_unhandled_type');
SELECT assert_eq('gs quant canonical 0248 gs_quant/test/api/backtests_xasset/response_datatypes/test_backtest_datatypes.py test_request_types', fin_gsq_test_test_request_types('local_payload').payload || ':' || fin_gsq_test_test_request_types('local_payload').source_function, 'local_payload:test_request_types');
SELECT assert_eq('gs quant canonical 0249 gs_quant/test/api/backtests_xasset/response_datatypes/test_backtest_datatypes.py test_model_addition', fin_gsq_test_test_model_addition('local_payload').payload || ':' || fin_gsq_test_test_model_addition('local_payload').source_function, 'local_payload:test_model_addition');
SELECT assert_eq('gs quant canonical 0250 gs_quant/test/api/backtests_xasset/response_datatypes/test_risk_result.py test_request_types', fin_gsq_test_test_request_types_test_api_backtests_xasset_d77ba130f6('local_payload').payload || ':' || fin_gsq_test_test_request_types_test_api_backtests_xasset_d77ba130f6('local_payload').source_function, 'local_payload:test_request_types');
SELECT assert_eq('gs quant canonical 0251 gs_quant/test/api/backtests_xasset/response_datatypes/test_risk_result_datatypes.py test_request_types', fin_gsq_test_test_request_types_test_api_backtests_xasset_380b648fc0('local_payload').payload || ':' || fin_gsq_test_test_request_types_test_api_backtests_xasset_380b648fc0('local_payload').source_function, 'local_payload:test_request_types');
SELECT assert_eq('gs quant canonical 0252 gs_quant/test/api/backtests_xasset/response_datatypes/test_risk_result_datatypes.py test_arithmetics', fin_gsq_test_test_arithmetics('local_payload').payload || ':' || fin_gsq_test_test_arithmetics('local_payload').source_function, 'local_payload:test_arithmetics');
SELECT assert_eq('gs quant canonical 0253 gs_quant/test/api/backtests_xasset/test_request.py test_request_types', fin_gsq_test_test_request_types_test_api_backtests_xasset_cefd453276('local_payload').payload || ':' || fin_gsq_test_test_request_types_test_api_backtests_xasset_cefd453276('local_payload').source_function, 'local_payload:test_request_types');
SELECT assert_eq('gs quant canonical 0254 gs_quant/test/api/backtests_xasset/test_response.py test_response_types', fin_gsq_test_test_response_types('local_payload').payload || ':' || fin_gsq_test_test_response_types('local_payload').source_function, 'local_payload:test_response_types');
SELECT assert_eq('gs quant canonical 0255 gs_quant/test/api/test_assets.py test_get_asset', fin_gsq_test_test_get_asset('local_payload').payload || ':' || fin_gsq_test_test_get_asset('local_payload').source_function, 'local_payload:test_get_asset');
SELECT assert_eq('gs quant canonical 0256 gs_quant/test/api/test_assets.py test_get_many_assets', fin_gsq_test_test_get_many_assets('local_payload').payload || ':' || fin_gsq_test_test_get_many_assets('local_payload').source_function, 'local_payload:test_get_many_assets');
SELECT assert_eq('gs quant canonical 0257 gs_quant/test/api/test_assets.py test_get_asset_xrefs', fin_gsq_test_test_get_asset_xrefs('local_payload').payload || ':' || fin_gsq_test_test_get_asset_xrefs('local_payload').source_function, 'local_payload:test_get_asset_xrefs');
SELECT assert_eq('gs quant canonical 0258 gs_quant/test/api/test_assets.py test_get_asset_positions_for_date', fin_gsq_test_test_get_asset_positions_for_date('local_payload').payload || ':' || fin_gsq_test_test_get_asset_positions_for_date('local_payload').source_function, 'local_payload:test_get_asset_positions_for_date');
SELECT assert_eq('gs quant canonical 0259 gs_quant/test/api/test_backtests.py test_get_many_backtests', fin_gsq_test_test_get_many_backtests('local_payload').payload || ':' || fin_gsq_test_test_get_many_backtests('local_payload').source_function, 'local_payload:test_get_many_backtests');
SELECT assert_eq('gs quant canonical 0260 gs_quant/test/api/test_backtests.py test_get_backtest', fin_gsq_test_test_get_backtest('local_payload').payload || ':' || fin_gsq_test_test_get_backtest('local_payload').source_function, 'local_payload:test_get_backtest');
SELECT assert_eq('gs quant canonical 0261 gs_quant/test/api/test_backtests.py test_create_backtest', fin_gsq_test_test_create_backtest('local_payload').payload || ':' || fin_gsq_test_test_create_backtest('local_payload').source_function, 'local_payload:test_create_backtest');
SELECT assert_eq('gs quant canonical 0262 gs_quant/test/api/test_backtests.py test_update_backtest', fin_gsq_test_test_update_backtest('local_payload').payload || ':' || fin_gsq_test_test_update_backtest('local_payload').source_function, 'local_payload:test_update_backtest');
SELECT assert_eq('gs quant canonical 0263 gs_quant/test/api/test_backtests.py test_delete_backtest', fin_gsq_test_test_delete_backtest('local_payload').payload || ':' || fin_gsq_test_test_delete_backtest('local_payload').source_function, 'local_payload:test_delete_backtest');
SELECT assert_eq('gs quant canonical 0264 gs_quant/test/api/test_backtests.py test_schedule_backtest', fin_gsq_test_test_schedule_backtest('local_payload').payload || ':' || fin_gsq_test_test_schedule_backtest('local_payload').source_function, 'local_payload:test_schedule_backtest');
SELECT assert_eq('gs quant canonical 0265 gs_quant/test/api/test_base_screener.py test_get_all_screeners', fin_gsq_test_test_get_all_screeners('local_payload').payload || ':' || fin_gsq_test_test_get_all_screeners('local_payload').source_function, 'local_payload:test_get_all_screeners');
SELECT assert_eq('gs quant canonical 0266 gs_quant/test/api/test_base_screener.py test_get_screen', fin_gsq_test_test_get_screen('local_payload').payload || ':' || fin_gsq_test_test_get_screen('local_payload').source_function, 'local_payload:test_get_screen');
SELECT assert_eq('gs quant canonical 0267 gs_quant/test/api/test_base_screener.py test_create_screener', fin_gsq_test_test_create_screener('local_payload').payload || ':' || fin_gsq_test_test_create_screener('local_payload').source_function, 'local_payload:test_create_screener');
SELECT assert_eq('gs quant canonical 0268 gs_quant/test/api/test_base_screener.py test_edit_screener', fin_gsq_test_test_edit_screener('local_payload').payload || ':' || fin_gsq_test_test_edit_screener('local_payload').source_function, 'local_payload:test_edit_screener');
SELECT assert_eq('gs quant canonical 0269 gs_quant/test/api/test_base_screener.py test_publish_to_screener', fin_gsq_test_test_publish_to_screener('local_payload').payload || ':' || fin_gsq_test_test_publish_to_screener('local_payload').source_function, 'local_payload:test_publish_to_screener');
SELECT assert_eq('gs quant canonical 0270 gs_quant/test/api/test_base_screener.py test_clear_screener', fin_gsq_test_test_clear_screener('local_payload').payload || ':' || fin_gsq_test_test_clear_screener('local_payload').source_function, 'local_payload:test_clear_screener');
SELECT assert_eq('gs quant canonical 0271 gs_quant/test/api/test_base_screener.py test_delete_screener', fin_gsq_test_test_delete_screener('local_payload').payload || ':' || fin_gsq_test_test_delete_screener('local_payload').source_function, 'local_payload:test_delete_screener');
SELECT assert_eq('gs quant canonical 0272 gs_quant/test/api/test_cache.py set_session', fin_gsq_test_set_session('local_payload').payload || ':' || fin_gsq_test_set_session('local_payload').source_function, 'local_payload:set_session');
SELECT assert_eq('gs quant canonical 0273 gs_quant/test/api/test_cache.py test_cache_addition_removal', fin_gsq_test_test_cache_addition_removal('local_payload').payload || ':' || fin_gsq_test_test_cache_addition_removal('local_payload').source_function, 'local_payload:test_cache_addition_removal');
SELECT assert_eq('gs quant canonical 0274 gs_quant/test/api/test_cache.py test_cache_subset', fin_gsq_test_test_cache_subset('local_payload').payload || ':' || fin_gsq_test_test_cache_subset('local_payload').source_function, 'local_payload:test_cache_subset');
SELECT assert_eq('gs quant canonical 0275 gs_quant/test/api/test_cache.py test_multiple_measures', fin_gsq_test_test_multiple_measures('local_payload').payload || ':' || fin_gsq_test_test_multiple_measures('local_payload').source_function, 'local_payload:test_multiple_measures');
SELECT assert_eq('gs quant canonical 0276 gs_quant/test/api/test_carbon.py test_get_carbon_data', fin_gsq_test_test_get_carbon_data('local_payload').payload || ':' || fin_gsq_test_test_get_carbon_data('local_payload').source_function, 'local_payload:test_get_carbon_data');
SELECT assert_eq('gs quant canonical 0277 gs_quant/test/api/test_content.py set_session', fin_gsq_test_set_session_test_api_test_content('local_payload').payload || ':' || fin_gsq_test_set_session_test_api_test_content('local_payload').source_function, 'local_payload:set_session');
SELECT assert_eq('gs quant canonical 0278 gs_quant/test/api/test_content.py test_get_contents', fin_gsq_test_test_get_contents('local_payload').payload || ':' || fin_gsq_test_test_get_contents('local_payload').source_function, 'local_payload:test_get_contents');
SELECT assert_eq('gs quant canonical 0279 gs_quant/test/api/test_content.py test_get_text', fin_gsq_test_test_get_text('local_payload').payload || ':' || fin_gsq_test_test_get_text('local_payload').source_function, 'local_payload:test_get_text');
SELECT assert_eq('gs quant canonical 0280 gs_quant/test/api/test_data.py test_coordinates_data', fin_gsq_test_test_coordinates_data('local_payload').payload || ':' || fin_gsq_test_test_coordinates_data('local_payload').source_function, 'local_payload:test_coordinates_data');
SELECT assert_eq('gs quant canonical 0281 gs_quant/test/api/test_data.py test_coordinate_data_series', fin_gsq_test_test_coordinate_data_series('local_payload').payload || ':' || fin_gsq_test_test_coordinate_data_series('local_payload').source_function, 'local_payload:test_coordinate_data_series');
SELECT assert_eq('gs quant canonical 0282 gs_quant/test/api/test_data.py test_coordinate_last', fin_gsq_test_test_coordinate_last('local_payload').payload || ':' || fin_gsq_test_test_coordinate_last('local_payload').source_function, 'local_payload:test_coordinate_last');
SELECT assert_eq('gs quant canonical 0283 gs_quant/test/api/test_data.py test_get_coverage_api', fin_gsq_test_test_get_coverage_api('local_payload').payload || ':' || fin_gsq_test_test_get_coverage_api('local_payload').source_function, 'local_payload:test_get_coverage_api');
SELECT assert_eq('gs quant canonical 0284 gs_quant/test/api/test_data.py test_get_many_defns_api', fin_gsq_test_test_get_many_defns_api('local_payload').payload || ':' || fin_gsq_test_test_get_many_defns_api('local_payload').source_function, 'local_payload:test_get_many_defns_api');
SELECT assert_eq('gs quant canonical 0285 gs_quant/test/api/test_data.py test_coordinates_converter', fin_gsq_test_test_coordinates_converter('local_payload').payload || ':' || fin_gsq_test_test_coordinates_converter('local_payload').source_function, 'local_payload:test_coordinates_converter');
SELECT assert_eq('gs quant canonical 0286 gs_quant/test/api/test_data.py test_get_many_coordinates', fin_gsq_test_test_get_many_coordinates('local_payload').payload || ':' || fin_gsq_test_test_get_many_coordinates('local_payload').source_function, 'local_payload:test_get_many_coordinates');
SELECT assert_eq('gs quant canonical 0287 gs_quant/test/api/test_data.py test_auto_scroll_on_pages', fin_gsq_test_test_auto_scroll_on_pages('local_payload').payload || ':' || fin_gsq_test_test_auto_scroll_on_pages('local_payload').source_function, 'local_payload:test_auto_scroll_on_pages');
SELECT assert_eq('gs quant canonical 0288 gs_quant/test/api/test_data.py mock_fields_response', fin_gsq_test_mock_fields_response('local_payload').payload || ':' || fin_gsq_test_mock_fields_response('local_payload').source_function, 'local_payload:mock_fields_response');
SELECT assert_eq('gs quant canonical 0289 gs_quant/test/api/test_data.py test_get_dataset_fields', fin_gsq_test_test_get_dataset_fields('local_payload').payload || ':' || fin_gsq_test_test_get_dataset_fields('local_payload').source_function, 'local_payload:test_get_dataset_fields');
SELECT assert_eq('gs quant canonical 0290 gs_quant/test/api/test_data.py test_get_field_types', fin_gsq_test_test_get_field_types('local_payload').payload || ':' || fin_gsq_test_test_get_field_types('local_payload').source_function, 'local_payload:test_get_field_types');
SELECT assert_eq('gs quant canonical 0291 gs_quant/test/api/test_data_screen.py test_get_all_screens', fin_gsq_test_test_get_all_screens('local_payload').payload || ':' || fin_gsq_test_test_get_all_screens('local_payload').source_function, 'local_payload:test_get_all_screens');
SELECT assert_eq('gs quant canonical 0292 gs_quant/test/api/test_data_screen.py test_get_screen', fin_gsq_test_test_get_screen_test_api_test_data_screen('local_payload').payload || ':' || fin_gsq_test_test_get_screen_test_api_test_data_screen('local_payload').source_function, 'local_payload:test_get_screen');
SELECT assert_eq('gs quant canonical 0293 gs_quant/test/api/test_data_screen.py test_get_column_info', fin_gsq_test_test_get_column_info('local_payload').payload || ':' || fin_gsq_test_test_get_column_info('local_payload').source_function, 'local_payload:test_get_column_info');
SELECT assert_eq('gs quant canonical 0294 gs_quant/test/api/test_data_screen.py test_delete_screen', fin_gsq_test_test_delete_screen('local_payload').payload || ':' || fin_gsq_test_test_delete_screen('local_payload').source_function, 'local_payload:test_delete_screen');
SELECT assert_eq('gs quant canonical 0295 gs_quant/test/api/test_data_screen.py test_create_screen', fin_gsq_test_test_create_screen('local_payload').payload || ':' || fin_gsq_test_test_create_screen('local_payload').source_function, 'local_payload:test_create_screen');
SELECT assert_eq('gs quant canonical 0296 gs_quant/test/api/test_data_screen.py test_filter_screen', fin_gsq_test_test_filter_screen('local_payload').payload || ':' || fin_gsq_test_test_filter_screen('local_payload').source_function, 'local_payload:test_filter_screen');
SELECT assert_eq('gs quant canonical 0297 gs_quant/test/api/test_data_screen.py test_update_screen', fin_gsq_test_test_update_screen('local_payload').payload || ':' || fin_gsq_test_test_update_screen('local_payload').source_function, 'local_payload:test_update_screen');
SELECT assert_eq('gs quant canonical 0298 gs_quant/test/api/test_esg.py test_get_risk_models', fin_gsq_test_test_get_risk_models('local_payload').payload || ':' || fin_gsq_test_test_get_risk_models('local_payload').source_function, 'local_payload:test_get_risk_models');
SELECT assert_eq('gs quant canonical 0299 gs_quant/test/api/test_fred.py test_get_data', fin_gsq_test_test_get_data('local_payload').payload || ':' || fin_gsq_test_test_get_data('local_payload').source_function, 'local_payload:test_get_data');
SELECT assert_eq('gs quant canonical 0300 gs_quant/test/api/test_fred.py test_failed_get_data', fin_gsq_test_test_failed_get_data('local_payload').payload || ':' || fin_gsq_test_test_failed_get_data('local_payload').source_function, 'local_payload:test_failed_get_data');
SELECT assert_eq('gs quant canonical 0301 gs_quant/test/api/test_fred.py test_get_data_series', fin_gsq_test_test_get_data_series('local_payload').payload || ':' || fin_gsq_test_test_get_data_series('local_payload').source_function, 'local_payload:test_get_data_series');
SELECT assert_eq('gs quant canonical 0302 gs_quant/test/api/test_fred.py test_failed_get_data_series', fin_gsq_test_test_failed_get_data_series('local_payload').payload || ':' || fin_gsq_test_test_failed_get_data_series('local_payload').source_function, 'local_payload:test_failed_get_data_series');
SELECT assert_eq('gs quant canonical 0303 gs_quant/test/api/test_groups.py test_get_groups', fin_gsq_test_test_get_groups('local_payload').payload || ':' || fin_gsq_test_test_get_groups('local_payload').source_function, 'local_payload:test_get_groups');
SELECT assert_eq('gs quant canonical 0304 gs_quant/test/api/test_groups.py test_get_group', fin_gsq_test_test_get_group('local_payload').payload || ':' || fin_gsq_test_test_get_group('local_payload').source_function, 'local_payload:test_get_group');
SELECT assert_eq('gs quant canonical 0305 gs_quant/test/api/test_groups.py test_create_group', fin_gsq_test_test_create_group('local_payload').payload || ':' || fin_gsq_test_test_create_group('local_payload').source_function, 'local_payload:test_create_group');
SELECT assert_eq('gs quant canonical 0306 gs_quant/test/api/test_index.py mock_session', fin_gsq_test_mock_session('local_payload').payload || ':' || fin_gsq_test_mock_session('local_payload').source_function, 'local_payload:mock_session');
SELECT assert_eq('gs quant canonical 0307 gs_quant/test/api/test_index.py test_basket_create', fin_gsq_test_test_basket_create('local_payload').payload || ':' || fin_gsq_test_test_basket_create('local_payload').source_function, 'local_payload:test_basket_create');
SELECT assert_eq('gs quant canonical 0308 gs_quant/test/api/test_index.py test_basket_edit', fin_gsq_test_test_basket_edit('local_payload').payload || ':' || fin_gsq_test_test_basket_edit('local_payload').source_function, 'local_payload:test_basket_edit');
SELECT assert_eq('gs quant canonical 0309 gs_quant/test/api/test_index.py test_basket_rebalance', fin_gsq_test_test_basket_rebalance('local_payload').payload || ':' || fin_gsq_test_test_basket_rebalance('local_payload').source_function, 'local_payload:test_basket_rebalance');
SELECT assert_eq('gs quant canonical 0310 gs_quant/test/api/test_index.py test_basket_cancel_rebalance', fin_gsq_test_test_basket_cancel_rebalance('local_payload').payload || ':' || fin_gsq_test_test_basket_cancel_rebalance('local_payload').source_function, 'local_payload:test_basket_cancel_rebalance');
SELECT assert_eq('gs quant canonical 0311 gs_quant/test/api/test_index.py test_basket_last_rebalance_data', fin_gsq_test_test_basket_last_rebalance_data('local_payload').payload || ':' || fin_gsq_test_test_basket_last_rebalance_data('local_payload').source_function, 'local_payload:test_basket_last_rebalance_data');
SELECT assert_eq('gs quant canonical 0312 gs_quant/test/api/test_index.py test_basket_initial_price', fin_gsq_test_test_basket_initial_price('local_payload').payload || ':' || fin_gsq_test_test_basket_initial_price('local_payload').source_function, 'local_payload:test_basket_initial_price');
SELECT assert_eq('gs quant canonical 0313 gs_quant/test/api/test_index.py test_get_asset_positions_data', fin_gsq_test_test_get_asset_positions_data('local_payload').payload || ':' || fin_gsq_test_test_get_asset_positions_data('local_payload').source_function, 'local_payload:test_get_asset_positions_data');
SELECT assert_eq('gs quant canonical 0314 gs_quant/test/api/test_instruments.py test_from_dict', fin_gsq_test_test_from_dict('local_payload').payload || ':' || fin_gsq_test_test_from_dict('local_payload').source_function, 'local_payload:test_from_dict');
SELECT assert_eq('gs quant canonical 0315 gs_quant/test/api/test_json.py test_datetime_serialisation', fin_json_test_datetime_serialisation('local_payload').payload || ':' || fin_json_test_datetime_serialisation('local_payload').source_function, 'local_payload:test_datetime_serialisation');
SELECT assert_eq('gs quant canonical 0316 gs_quant/test/api/test_json.py test_date_or_datetime', fin_json_test_date_or_datetime('local_payload').payload || ':' || fin_json_test_date_or_datetime('local_payload').source_function, 'local_payload:test_date_or_datetime');
SELECT assert_eq('gs quant canonical 0317 gs_quant/test/api/test_json.py test_time', fin_json_test_time('local_payload').payload || ':' || fin_json_test_time('local_payload').source_function, 'local_payload:test_time');
SELECT assert_eq('gs quant canonical 0318 gs_quant/test/api/test_json.py test_custom_comments', fin_json_test_custom_comments('local_payload').payload || ':' || fin_json_test_custom_comments('local_payload').source_function, 'local_payload:test_custom_comments');
SELECT assert_eq('gs quant canonical 0319 gs_quant/test/api/test_monitor.py test_get_many_monitors', fin_gsq_test_test_get_many_monitors('local_payload').payload || ':' || fin_gsq_test_test_get_many_monitors('local_payload').source_function, 'local_payload:test_get_many_monitors');
SELECT assert_eq('gs quant canonical 0320 gs_quant/test/api/test_monitor.py test_get_monitor', fin_gsq_test_test_get_monitor('local_payload').payload || ':' || fin_gsq_test_test_get_monitor('local_payload').source_function, 'local_payload:test_get_monitor');
SELECT assert_eq('gs quant canonical 0321 gs_quant/test/api/test_monitor.py test_create_monitor', fin_gsq_test_test_create_monitor('local_payload').payload || ':' || fin_gsq_test_test_create_monitor('local_payload').source_function, 'local_payload:test_create_monitor');
SELECT assert_eq('gs quant canonical 0322 gs_quant/test/api/test_monitor.py test_update_monitor', fin_gsq_test_test_update_monitor('local_payload').payload || ':' || fin_gsq_test_test_update_monitor('local_payload').source_function, 'local_payload:test_update_monitor');
SELECT assert_eq('gs quant canonical 0323 gs_quant/test/api/test_monitor.py test_delete_monitor', fin_gsq_test_test_delete_monitor('local_payload').payload || ':' || fin_gsq_test_test_delete_monitor('local_payload').source_function, 'local_payload:test_delete_monitor');
SELECT assert_eq('gs quant canonical 0324 gs_quant/test/api/test_monitor.py test_calculate_monitor', fin_gsq_test_test_calculate_monitor('local_payload').payload || ':' || fin_gsq_test_test_calculate_monitor('local_payload').source_function, 'local_payload:test_calculate_monitor');
SELECT assert_eq('gs quant canonical 0325 gs_quant/test/api/test_portfolios.py test_get_many_portfolios', fin_gsq_test_test_get_many_portfolios('local_payload').payload || ':' || fin_gsq_test_test_get_many_portfolios('local_payload').source_function, 'local_payload:test_get_many_portfolios');
SELECT assert_eq('gs quant canonical 0326 gs_quant/test/api/test_portfolios.py test_get_portfolio', fin_gsq_test_test_get_portfolio('local_payload').payload || ':' || fin_gsq_test_test_get_portfolio('local_payload').source_function, 'local_payload:test_get_portfolio');
SELECT assert_eq('gs quant canonical 0327 gs_quant/test/api/test_portfolios.py test_create_portfolio', fin_gsq_test_test_create_portfolio('local_payload').payload || ':' || fin_gsq_test_test_create_portfolio('local_payload').source_function, 'local_payload:test_create_portfolio');
SELECT assert_eq('gs quant canonical 0328 gs_quant/test/api/test_portfolios.py test_update_portfolio', fin_gsq_test_test_update_portfolio('local_payload').payload || ':' || fin_gsq_test_test_update_portfolio('local_payload').source_function, 'local_payload:test_update_portfolio');
SELECT assert_eq('gs quant canonical 0329 gs_quant/test/api/test_portfolios.py test_delete_portfolio', fin_gsq_test_test_delete_portfolio('local_payload').payload || ':' || fin_gsq_test_test_delete_portfolio('local_payload').source_function, 'local_payload:test_delete_portfolio');
SELECT assert_eq('gs quant canonical 0330 gs_quant/test/api/test_portfolios.py test_get_portfolio_positions', fin_gsq_test_test_get_portfolio_positions('local_payload').payload || ':' || fin_gsq_test_test_get_portfolio_positions('local_payload').source_function, 'local_payload:test_get_portfolio_positions');
SELECT assert_eq('gs quant canonical 0331 gs_quant/test/api/test_portfolios.py test_get_portfolio_positions_for_date', fin_gsq_test_test_get_portfolio_positions_for_date('local_payload').payload || ':' || fin_gsq_test_test_get_portfolio_positions_for_date('local_payload').source_function, 'local_payload:test_get_portfolio_positions_for_date');
SELECT assert_eq('gs quant canonical 0332 gs_quant/test/api/test_portfolios.py test_get_latest_portfolio_positions', fin_gsq_test_test_get_latest_portfolio_positions('local_payload').payload || ':' || fin_gsq_test_test_get_latest_portfolio_positions('local_payload').source_function, 'local_payload:test_get_latest_portfolio_positions');
SELECT assert_eq('gs quant canonical 0333 gs_quant/test/api/test_portfolios.py test_get_portfolio_position_dates', fin_gsq_test_test_get_portfolio_position_dates('local_payload').payload || ':' || fin_gsq_test_test_get_portfolio_position_dates('local_payload').source_function, 'local_payload:test_get_portfolio_position_dates');
SELECT assert_eq('gs quant canonical 0334 gs_quant/test/api/test_portfolios.py test_portfolio_positions_data', fin_gsq_test_test_portfolio_positions_data('local_payload').payload || ':' || fin_gsq_test_test_portfolio_positions_data('local_payload').source_function, 'local_payload:test_portfolio_positions_data');
SELECT assert_eq('gs quant canonical 0335 gs_quant/test/api/test_portfolios.py test_get_risk_models_by_coverage', fin_gsq_test_test_get_risk_models_by_coverage('local_payload').payload || ':' || fin_gsq_test_test_get_risk_models_by_coverage('local_payload').source_function, 'local_payload:test_get_risk_models_by_coverage');
SELECT assert_eq('gs quant canonical 0336 gs_quant/test/api/test_portfolios.py test_get_portfolio_analyze', fin_gsq_test_test_get_portfolio_analyze('local_payload').payload || ':' || fin_gsq_test_test_get_portfolio_analyze('local_payload').source_function, 'local_payload:test_get_portfolio_analyze');
SELECT assert_eq('gs quant canonical 0337 gs_quant/test/api/test_reports.py test_get_reports', fin_gsq_test_test_get_reports('local_payload').payload || ':' || fin_gsq_test_test_get_reports('local_payload').source_function, 'local_payload:test_get_reports');
SELECT assert_eq('gs quant canonical 0338 gs_quant/test/api/test_reports.py test_get_report', fin_gsq_test_test_get_report('local_payload').payload || ':' || fin_gsq_test_test_get_report('local_payload').source_function, 'local_payload:test_get_report');
SELECT assert_eq('gs quant canonical 0339 gs_quant/test/api/test_reports.py test_create_report', fin_gsq_test_test_create_report('local_payload').payload || ':' || fin_gsq_test_test_create_report('local_payload').source_function, 'local_payload:test_create_report');
SELECT assert_eq('gs quant canonical 0340 gs_quant/test/api/test_reports.py test_update_report', fin_gsq_test_test_update_report('local_payload').payload || ':' || fin_gsq_test_test_update_report('local_payload').source_function, 'local_payload:test_update_report');
SELECT assert_eq('gs quant canonical 0341 gs_quant/test/api/test_reports.py test_delete_portfolio', fin_gsq_test_test_delete_portfolio_test_api_test_reports('local_payload').payload || ':' || fin_gsq_test_test_delete_portfolio_test_api_test_reports('local_payload').source_function, 'local_payload:test_delete_portfolio');
SELECT assert_eq('gs quant canonical 0342 gs_quant/test/api/test_reports.py test_schedule_report', fin_gsq_test_test_schedule_report('local_payload').payload || ':' || fin_gsq_test_test_schedule_report('local_payload').source_function, 'local_payload:test_schedule_report');
SELECT assert_eq('gs quant canonical 0343 gs_quant/test/api/test_reports.py test_get_report_status', fin_gsq_test_test_get_report_status('local_payload').payload || ':' || fin_gsq_test_test_get_report_status('local_payload').source_function, 'local_payload:test_get_report_status');
SELECT assert_eq('gs quant canonical 0344 gs_quant/test/api/test_reports.py test_get_report_jobs', fin_gsq_test_test_get_report_jobs('local_payload').payload || ':' || fin_gsq_test_test_get_report_jobs('local_payload').source_function, 'local_payload:test_get_report_jobs');
SELECT assert_eq('gs quant canonical 0345 gs_quant/test/api/test_reports.py test_report_job', fin_gsq_test_test_report_job('local_payload').payload || ':' || fin_gsq_test_test_report_job('local_payload').source_function, 'local_payload:test_report_job');
SELECT assert_eq('gs quant canonical 0346 gs_quant/test/api/test_reports.py test_cancel_report_job', fin_gsq_test_test_cancel_report_job('local_payload').payload || ':' || fin_gsq_test_test_cancel_report_job('local_payload').source_function, 'local_payload:test_cancel_report_job');
SELECT assert_eq('gs quant canonical 0347 gs_quant/test/api/test_reports.py test_update_report_job', fin_gsq_test_test_update_report_job('local_payload').payload || ':' || fin_gsq_test_test_update_report_job('local_payload').source_function, 'local_payload:test_update_report_job');
SELECT assert_eq('gs quant canonical 0348 gs_quant/test/api/test_reports.py test_get_factor_risk_report_results', fin_gsq_test_test_get_factor_risk_report_results('local_payload').payload || ':' || fin_gsq_test_test_get_factor_risk_report_results('local_payload').source_function, 'local_payload:test_get_factor_risk_report_results');
SELECT assert_eq('gs quant canonical 0349 gs_quant/test/api/test_reports.py test_get_factor_risk_report_view', fin_gsq_test_test_get_factor_risk_report_view('local_payload').payload || ':' || fin_gsq_test_test_get_factor_risk_report_view('local_payload').source_function, 'local_payload:test_get_factor_risk_report_view');
SELECT assert_eq('gs quant canonical 0350 gs_quant/test/api/test_risk.py set_session', fin_gsq_test_set_session_test_api_test_risk('local_payload').payload || ':' || fin_gsq_test_set_session_test_api_test_risk('local_payload').source_function, 'local_payload:set_session');
SELECT assert_eq('gs quant canonical 0351 gs_quant/test/api/test_risk.py structured_calc', fin_gsq_test_structured_calc('local_payload').payload || ':' || fin_gsq_test_structured_calc('local_payload').source_function, 'local_payload:structured_calc');
SELECT assert_eq('gs quant canonical 0352 gs_quant/test/api/test_risk.py scalar_calc', fin_gsq_test_scalar_calc('local_payload').payload || ':' || fin_gsq_test_scalar_calc('local_payload').source_function, 'local_payload:scalar_calc');
SELECT assert_eq('gs quant canonical 0353 gs_quant/test/api/test_risk.py price', fin_gsq_test_price('local_payload').payload || ':' || fin_gsq_test_price('local_payload').source_function, 'local_payload:price');
SELECT assert_eq('gs quant canonical 0354 gs_quant/test/api/test_risk.py test_price', fin_gsq_test_test_price('local_payload').payload || ':' || fin_gsq_test_test_price('local_payload').source_function, 'local_payload:test_price');
SELECT assert_eq('gs quant canonical 0355 gs_quant/test/api/test_risk.py test_structured_calc', fin_gsq_test_test_structured_calc('local_payload').payload || ':' || fin_gsq_test_test_structured_calc('local_payload').source_function, 'local_payload:test_structured_calc');
SELECT assert_eq('gs quant canonical 0356 gs_quant/test/api/test_risk.py test_scalar_calc', fin_gsq_test_test_scalar_calc('local_payload').payload || ':' || fin_gsq_test_test_scalar_calc('local_payload').source_function, 'local_payload:test_scalar_calc');
SELECT assert_eq('gs quant canonical 0357 gs_quant/test/api/test_risk.py test_async_calc', fin_gsq_test_test_async_calc('local_payload').payload || ':' || fin_gsq_test_test_async_calc('local_payload').source_function, 'local_payload:test_async_calc');
SELECT assert_eq('gs quant canonical 0358 gs_quant/test/api/test_risk.py test_disjoint_priceables_measures', fin_gsq_test_test_disjoint_priceables_measures('local_payload').payload || ':' || fin_gsq_test_test_disjoint_priceables_measures('local_payload').source_function, 'local_payload:test_disjoint_priceables_measures');
SELECT assert_eq('gs quant canonical 0359 gs_quant/test/api/test_risk.py test_create_pretrade_execution_optimization', fin_gsq_test_test_create_pretrade_execution_optimization('local_payload').payload || ':' || fin_gsq_test_test_create_pretrade_execution_optimization('local_payload').source_function, 'local_payload:test_create_pretrade_execution_optimization');
SELECT assert_eq('gs quant canonical 0360 gs_quant/test/api/test_risk.py test_get_pretrade_execution_optimization', fin_gsq_test_test_get_pretrade_execution_optimization('local_payload').payload || ':' || fin_gsq_test_test_get_pretrade_execution_optimization('local_payload').source_function, 'local_payload:test_get_pretrade_execution_optimization');
SELECT assert_eq('gs quant canonical 0361 gs_quant/test/api/test_risk_models.py test_get_risk_models', fin_gsq_test_test_get_risk_models_test_api_test_risk_models('local_payload').payload || ':' || fin_gsq_test_test_get_risk_models_test_api_test_risk_models('local_payload').source_function, 'local_payload:test_get_risk_models');
SELECT assert_eq('gs quant canonical 0362 gs_quant/test/api/test_risk_models.py test_get_risk_model', fin_gsq_test_test_get_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_risk_model('local_payload').source_function, 'local_payload:test_get_risk_model');
SELECT assert_eq('gs quant canonical 0363 gs_quant/test/api/test_risk_models.py test_create_risk_model', fin_gsq_test_test_create_risk_model('local_payload').payload || ':' || fin_gsq_test_test_create_risk_model('local_payload').source_function, 'local_payload:test_create_risk_model');
SELECT assert_eq('gs quant canonical 0364 gs_quant/test/api/test_risk_models.py test_update_risk_model', fin_gsq_test_test_update_risk_model('local_payload').payload || ':' || fin_gsq_test_test_update_risk_model('local_payload').source_function, 'local_payload:test_update_risk_model');
SELECT assert_eq('gs quant canonical 0365 gs_quant/test/api/test_risk_models.py test_delete_risk_model', fin_gsq_test_test_delete_risk_model('local_payload').payload || ':' || fin_gsq_test_test_delete_risk_model('local_payload').source_function, 'local_payload:test_delete_risk_model');
SELECT assert_eq('gs quant canonical 0366 gs_quant/test/api/test_risk_models.py test_get_risk_model_calendar', fin_gsq_test_test_get_risk_model_calendar('local_payload').payload || ':' || fin_gsq_test_test_get_risk_model_calendar('local_payload').source_function, 'local_payload:test_get_risk_model_calendar');
SELECT assert_eq('gs quant canonical 0367 gs_quant/test/api/test_risk_models.py test_upload_risk_model_calendar', fin_gsq_test_test_upload_risk_model_calendar('local_payload').payload || ':' || fin_gsq_test_test_upload_risk_model_calendar('local_payload').source_function, 'local_payload:test_upload_risk_model_calendar');
SELECT assert_eq('gs quant canonical 0368 gs_quant/test/api/test_risk_models.py test_get_risk_model_factors', fin_gsq_test_test_get_risk_model_factors('local_payload').payload || ':' || fin_gsq_test_test_get_risk_model_factors('local_payload').source_function, 'local_payload:test_get_risk_model_factors');
SELECT assert_eq('gs quant canonical 0369 gs_quant/test/api/test_risk_models.py test_create_risk_model_factor', fin_gsq_test_test_create_risk_model_factor('local_payload').payload || ':' || fin_gsq_test_test_create_risk_model_factor('local_payload').source_function, 'local_payload:test_create_risk_model_factor');
SELECT assert_eq('gs quant canonical 0370 gs_quant/test/api/test_risk_models.py test_update_risk_model_factor', fin_gsq_test_test_update_risk_model_factor('local_payload').payload || ':' || fin_gsq_test_test_update_risk_model_factor('local_payload').source_function, 'local_payload:test_update_risk_model_factor');
SELECT assert_eq('gs quant canonical 0371 gs_quant/test/api/test_risk_models.py test_get_risk_model_coverage', fin_gsq_test_test_get_risk_model_coverage('local_payload').payload || ':' || fin_gsq_test_test_get_risk_model_coverage('local_payload').source_function, 'local_payload:test_get_risk_model_coverage');
SELECT assert_eq('gs quant canonical 0372 gs_quant/test/api/test_risk_models.py test_upload_risk_model_data', fin_gsq_test_test_upload_risk_model_data('local_payload').payload || ':' || fin_gsq_test_test_upload_risk_model_data('local_payload').source_function, 'local_payload:test_upload_risk_model_data');
SELECT assert_eq('gs quant canonical 0373 gs_quant/test/api/test_risk_models.py test_upload_macro_risk_model_data', fin_gsq_test_test_upload_macro_risk_model_data('local_payload').payload || ':' || fin_gsq_test_test_upload_macro_risk_model_data('local_payload').source_function, 'local_payload:test_upload_macro_risk_model_data');
SELECT assert_eq('gs quant canonical 0374 gs_quant/test/api/test_risk_models.py test_get_risk_model_data', fin_gsq_test_test_get_risk_model_data('local_payload').payload || ':' || fin_gsq_test_test_get_risk_model_data('local_payload').source_function, 'local_payload:test_get_risk_model_data');
SELECT assert_eq('gs quant canonical 0375 gs_quant/test/api/test_risk_models.py test_get_r_squared', fin_gsq_test_test_get_r_squared('local_payload').payload || ':' || fin_gsq_test_test_get_r_squared('local_payload').source_function, 'local_payload:test_get_r_squared');
SELECT assert_eq('gs quant canonical 0376 gs_quant/test/api/test_risk_models.py test_get_fair_value_gap', fin_gsq_test_test_get_fair_value_gap('local_payload').payload || ':' || fin_gsq_test_test_get_fair_value_gap('local_payload').source_function, 'local_payload:test_get_fair_value_gap');
SELECT assert_eq('gs quant canonical 0377 gs_quant/test/api/test_risk_models.py test_get_factor_standard_deviation', fin_gsq_test_test_get_factor_standard_deviation('local_payload').payload || ':' || fin_gsq_test_test_get_factor_standard_deviation('local_payload').source_function, 'local_payload:test_get_factor_standard_deviation');
SELECT assert_eq('gs quant canonical 0378 gs_quant/test/api/test_risk_models.py test_get_factor_z_score', fin_gsq_test_test_get_factor_z_score('local_payload').payload || ':' || fin_gsq_test_test_get_factor_z_score('local_payload').source_function, 'local_payload:test_get_factor_z_score');
SELECT assert_eq('gs quant canonical 0379 gs_quant/test/api/test_risk_models.py test_get_predicted_beta', fin_gsq_test_test_get_predicted_beta('local_payload').payload || ':' || fin_gsq_test_test_get_predicted_beta('local_payload').source_function, 'local_payload:test_get_predicted_beta');
SELECT assert_eq('gs quant canonical 0380 gs_quant/test/api/test_risk_models.py test_get_global_predicted_beta', fin_gsq_test_test_get_global_predicted_beta('local_payload').payload || ':' || fin_gsq_test_test_get_global_predicted_beta('local_payload').source_function, 'local_payload:test_get_global_predicted_beta');
SELECT assert_eq('gs quant canonical 0381 gs_quant/test/api/test_risk_models.py test_get_daily_return', fin_gsq_test_test_get_daily_return('local_payload').payload || ':' || fin_gsq_test_test_get_daily_return('local_payload').source_function, 'local_payload:test_get_daily_return');
SELECT assert_eq('gs quant canonical 0382 gs_quant/test/api/test_risk_models.py test_get_specific_return', fin_gsq_test_test_get_specific_return('local_payload').payload || ':' || fin_gsq_test_test_get_specific_return('local_payload').source_function, 'local_payload:test_get_specific_return');
SELECT assert_eq('gs quant canonical 0383 gs_quant/test/api/test_scenarios.py test_get_many_scenarios', fin_gsq_test_test_get_many_scenarios('local_payload').payload || ':' || fin_gsq_test_test_get_many_scenarios('local_payload').source_function, 'local_payload:test_get_many_scenarios');
SELECT assert_eq('gs quant canonical 0384 gs_quant/test/api/test_scenarios.py test_get_scenario', fin_gsq_test_test_get_scenario('local_payload').payload || ':' || fin_gsq_test_test_get_scenario('local_payload').source_function, 'local_payload:test_get_scenario');
SELECT assert_eq('gs quant canonical 0385 gs_quant/test/api/test_scenarios.py test_create_scenario', fin_gsq_test_test_create_scenario('local_payload').payload || ':' || fin_gsq_test_test_create_scenario('local_payload').source_function, 'local_payload:test_create_scenario');
SELECT assert_eq('gs quant canonical 0386 gs_quant/test/api/test_scenarios.py test_update_scenario', fin_gsq_test_test_update_scenario('local_payload').payload || ':' || fin_gsq_test_test_update_scenario('local_payload').source_function, 'local_payload:test_update_scenario');
SELECT assert_eq('gs quant canonical 0387 gs_quant/test/api/test_scenarios.py test_delete_scenario', fin_gsq_test_test_delete_scenario('local_payload').payload || ':' || fin_gsq_test_test_delete_scenario('local_payload').source_function, 'local_payload:test_delete_scenario');
SELECT assert_eq('gs quant canonical 0388 gs_quant/test/api/test_scenarios.py test_scenario_calculate', fin_gsq_test_test_scenario_calculate('local_payload').payload || ':' || fin_gsq_test_test_scenario_calculate('local_payload').source_function, 'local_payload:test_scenario_calculate');
SELECT assert_eq('gs quant canonical 0389 gs_quant/test/api/test_target.py classes', fin_gsq_test_classes('local_payload').payload || ':' || fin_gsq_test_classes('local_payload').source_function, 'local_payload:classes');
SELECT assert_eq('gs quant canonical 0390 gs_quant/test/api/test_target.py test_enum', fin_gsq_test_test_enum('local_payload').payload || ':' || fin_gsq_test_test_enum('local_payload').source_function, 'local_payload:test_enum');
SELECT assert_eq('gs quant canonical 0391 gs_quant/test/api/test_target.py test_classes', fin_gsq_test_test_classes('local_payload').payload || ':' || fin_gsq_test_test_classes('local_payload').source_function, 'local_payload:test_classes');
SELECT assert_eq('gs quant canonical 0392 gs_quant/test/api/test_thread_manager.py dummy_function', fin_gsq_test_dummy_function('local_payload').payload || ':' || fin_gsq_test_dummy_function('local_payload').source_function, 'local_payload:dummy_function');
SELECT assert_eq('gs quant canonical 0393 gs_quant/test/api/test_thread_manager.py test_thread_manager', fin_gsq_test_test_thread_manager('local_payload').payload || ':' || fin_gsq_test_test_thread_manager('local_payload').source_function, 'local_payload:test_thread_manager');
SELECT assert_eq('gs quant canonical 0394 gs_quant/test/api/test_users.py test_get_users', fin_gsq_test_test_get_users('local_payload').payload || ':' || fin_gsq_test_test_get_users('local_payload').source_function, 'local_payload:test_get_users');
SELECT assert_eq('gs quant canonical 0395 gs_quant/test/api/test_users.py test_get_current_user_info', fin_gsq_test_test_get_current_user_info('local_payload').payload || ':' || fin_gsq_test_test_get_current_user_info('local_payload').source_function, 'local_payload:test_get_current_user_info');
SELECT assert_eq('gs quant canonical 0396 gs_quant/test/backtest/test_backtest_eq_vol_engine.py set_session', fin_gsq_test_set_session_test_backtest_test_backte_882304ac4b('local_payload').payload || ':' || fin_gsq_test_set_session_test_backtest_test_backte_882304ac4b('local_payload').source_function, 'local_payload:set_session');
SELECT assert_eq('gs quant canonical 0397 gs_quant/test/backtest/test_backtest_eq_vol_engine.py api_mock_data', fin_gsq_test_api_mock_data('local_payload').payload || ':' || fin_gsq_test_api_mock_data('local_payload').source_function, 'local_payload:api_mock_data');
SELECT assert_eq('gs quant canonical 0398 gs_quant/test/backtest/test_backtest_eq_vol_engine.py mock_api_response', fin_gsq_test_mock_api_response('local_payload').payload || ':' || fin_gsq_test_mock_api_response('local_payload').source_function, 'local_payload:mock_api_response');
SELECT assert_eq('gs quant canonical 0399 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_eq_vol_engine_result', fin_gsq_test_test_eq_vol_engine_result('local_payload').payload || ':' || fin_gsq_test_test_eq_vol_engine_result('local_payload').source_function, 'local_payload:test_eq_vol_engine_result');
SELECT assert_eq('gs quant canonical 0400 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_basic', fin_gsq_test_test_engine_mapping_basic('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_basic('local_payload').source_function, 'local_payload:test_engine_mapping_basic');
SELECT assert_eq('gs quant canonical 0401 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_trade_quantity', fin_gsq_test_test_engine_mapping_trade_quantity('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_trade_quantity('local_payload').source_function, 'local_payload:test_engine_mapping_trade_quantity');
SELECT assert_eq('gs quant canonical 0402 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_with_signals', fin_gsq_test_test_engine_mapping_with_signals('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_with_signals('local_payload').source_function, 'local_payload:test_engine_mapping_with_signals');
SELECT assert_eq('gs quant canonical 0403 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_trade_quantity_nav', fin_gsq_test_test_engine_mapping_trade_quantity_nav('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_trade_quantity_nav('local_payload').source_function, 'local_payload:test_engine_mapping_trade_quantity_nav');
SELECT assert_eq('gs quant canonical 0404 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_listed_expiry_date', fin_gsq_test_test_engine_mapping_listed_expiry_date('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_listed_expiry_date('local_payload').source_function, 'local_payload:test_engine_mapping_listed_expiry_date');
SELECT assert_eq('gs quant canonical 0405 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_listed_roll_date', fin_gsq_test_test_engine_mapping_listed_roll_date('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_listed_roll_date('local_payload').source_function, 'local_payload:test_engine_mapping_listed_roll_date');
SELECT assert_eq('gs quant canonical 0406 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_market_model', fin_gsq_test_test_engine_mapping_market_model('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_market_model('local_payload').source_function, 'local_payload:test_engine_mapping_market_model');
SELECT assert_eq('gs quant canonical 0407 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_portfolio', fin_gsq_test_test_engine_mapping_portfolio('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_portfolio('local_payload').source_function, 'local_payload:test_engine_mapping_portfolio');
SELECT assert_eq('gs quant canonical 0408 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_supports_strategy', fin_gsq_test_test_supports_strategy('local_payload').payload || ':' || fin_gsq_test_test_supports_strategy('local_payload').source_function, 'local_payload:test_supports_strategy');
SELECT assert_eq('gs quant canonical 0409 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_basic_leg_size', fin_gsq_test_test_engine_mapping_basic_leg_size('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_basic_leg_size('local_payload').source_function, 'local_payload:test_engine_mapping_basic_leg_size');
SELECT assert_eq('gs quant canonical 0410 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_fixed_expiry', fin_gsq_test_test_engine_mapping_fixed_expiry('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_fixed_expiry('local_payload').source_function, 'local_payload:test_engine_mapping_fixed_expiry');
SELECT assert_eq('gs quant canonical 0411 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_delta_hedge', fin_gsq_test_test_engine_mapping_delta_hedge('local_payload').payload || ':' || fin_gsq_test_test_engine_mapping_delta_hedge('local_payload').source_function, 'local_payload:test_engine_mapping_delta_hedge');
SELECT assert_eq('gs quant canonical 0412 gs_quant/test/backtest/test_backtest_flow_vol.py set_session', fin_gsq_test_set_session_test_backtest_test_backtest_flow_vol('local_payload').payload || ':' || fin_gsq_test_set_session_test_backtest_test_backtest_flow_vol('local_payload').source_function, 'local_payload:set_session');
SELECT assert_eq('gs quant canonical 0413 gs_quant/test/backtest/test_backtest_flow_vol.py test_eqstrategies_backtest', fin_gsq_test_test_eqstrategies_backtest('local_payload').payload || ':' || fin_gsq_test_test_eqstrategies_backtest('local_payload').source_function, 'local_payload:test_eqstrategies_backtest');
SELECT assert_eq('gs quant canonical 0414 gs_quant/test/backtest/test_backtest_predefined.py test_backtest_predefined_timezone_aware', fin_gsq_test_test_backtest_predefined_timezone_aware('local_payload').payload || ':' || fin_gsq_test_test_backtest_predefined_timezone_aware('local_payload').source_function, 'local_payload:test_backtest_predefined_timezone_aware');
SELECT assert_eq('gs quant canonical 0415 gs_quant/test/backtest/test_backtest_predefined.py test_backtest_predefined', fin_gsq_test_test_backtest_predefined('local_payload').payload || ':' || fin_gsq_test_test_backtest_predefined('local_payload').source_function, 'local_payload:test_backtest_predefined');
SELECT assert_eq('gs quant canonical 0416 gs_quant/test/backtest/test_generic_engine.py mock_pricing_context', fin_gsq_test_mock_pricing_context('local_payload').payload || ':' || fin_gsq_test_mock_pricing_context('local_payload').source_function, 'local_payload:mock_pricing_context');
SELECT assert_eq('gs quant canonical 0417 gs_quant/test/backtest/test_generic_engine.py instrument_name', fin_gsq_test_instrument_name('local_payload').payload || ':' || fin_gsq_test_instrument_name('local_payload').source_function, 'local_payload:instrument_name');
SELECT assert_eq('gs quant canonical 0418 gs_quant/test/backtest/test_generic_engine.py test_generic_engine_simple', fin_gsq_test_test_generic_engine_simple('local_payload').payload || ':' || fin_gsq_test_test_generic_engine_simple('local_payload').source_function, 'local_payload:test_generic_engine_simple');
SELECT assert_eq('gs quant canonical 0419 gs_quant/test/backtest/test_generic_engine.py test_hedge_action_risk_trigger', fin_gsq_test_test_hedge_action_risk_trigger('local_payload').payload || ':' || fin_gsq_test_test_hedge_action_risk_trigger('local_payload').source_function, 'local_payload:test_hedge_action_risk_trigger');
SELECT assert_eq('gs quant canonical 0420 gs_quant/test/backtest/test_generic_engine.py test_hedge_without_risk', fin_gsq_test_test_hedge_without_risk('local_payload').payload || ':' || fin_gsq_test_test_hedge_without_risk('local_payload').source_function, 'local_payload:test_hedge_without_risk');
SELECT assert_eq('gs quant canonical 0421 gs_quant/test/backtest/test_generic_engine.py test_mkt_trigger_data_sources', fin_gsq_test_test_mkt_trigger_data_sources('local_payload').payload || ':' || fin_gsq_test_test_mkt_trigger_data_sources('local_payload').source_function, 'local_payload:test_mkt_trigger_data_sources');
SELECT assert_eq('gs quant canonical 0422 gs_quant/test/backtest/test_generic_engine.py test_exit_action_noarg', fin_gsq_test_test_exit_action_noarg('local_payload').payload || ':' || fin_gsq_test_test_exit_action_noarg('local_payload').source_function, 'local_payload:test_exit_action_noarg');
SELECT assert_eq('gs quant canonical 0423 gs_quant/test/backtest/test_generic_engine.py test_exit_action_emptyresults', fin_gsq_test_test_exit_action_emptyresults('local_payload').payload || ':' || fin_gsq_test_test_exit_action_emptyresults('local_payload').source_function, 'local_payload:test_exit_action_emptyresults');
SELECT assert_eq('gs quant canonical 0424 gs_quant/test/backtest/test_generic_engine.py test_exit_action_bytradename', fin_gsq_test_test_exit_action_bytradename('local_payload').payload || ':' || fin_gsq_test_test_exit_action_bytradename('local_payload').source_function, 'local_payload:test_exit_action_bytradename');
SELECT assert_eq('gs quant canonical 0425 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_action', fin_gsq_test_test_add_scaled_action('local_payload').payload || ':' || fin_gsq_test_test_add_scaled_action('local_payload').source_function, 'local_payload:test_add_scaled_action');
SELECT assert_eq('gs quant canonical 0426 gs_quant/test/backtest/test_generic_engine.py test_scaled_transaction_cost', fin_gsq_test_test_scaled_transaction_cost('local_payload').payload || ':' || fin_gsq_test_test_scaled_transaction_cost('local_payload').source_function, 'local_payload:test_scaled_transaction_cost');
SELECT assert_eq('gs quant canonical 0427 gs_quant/test/backtest/test_generic_engine.py test_agg_transaction_cost', fin_gsq_test_test_agg_transaction_cost('local_payload').payload || ':' || fin_gsq_test_test_agg_transaction_cost('local_payload').source_function, 'local_payload:test_agg_transaction_cost');
SELECT assert_eq('gs quant canonical 0428 gs_quant/test/backtest/test_generic_engine.py test_risk_scaled_transaction_cost', fin_gsq_test_test_risk_scaled_transaction_cost('local_payload').payload || ':' || fin_gsq_test_test_risk_scaled_transaction_cost('local_payload').source_function, 'local_payload:test_risk_scaled_transaction_cost');
SELECT assert_eq('gs quant canonical 0429 gs_quant/test/backtest/test_generic_engine.py test_hedge_transaction_costs', fin_gsq_test_test_hedge_transaction_costs('local_payload').payload || ':' || fin_gsq_test_test_hedge_transaction_costs('local_payload').source_function, 'local_payload:test_hedge_transaction_costs');
SELECT assert_eq('gs quant canonical 0430 gs_quant/test/backtest/test_generic_engine.py test_exit_transaction_costs', fin_gsq_test_test_exit_transaction_costs('local_payload').payload || ':' || fin_gsq_test_test_exit_transaction_costs('local_payload').source_function, 'local_payload:test_exit_transaction_costs');
SELECT assert_eq('gs quant canonical 0431 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_action_nav', fin_gsq_test_test_add_scaled_action_nav('local_payload').payload || ':' || fin_gsq_test_test_add_scaled_action_nav('local_payload').source_function, 'local_payload:test_add_scaled_action_nav');
SELECT assert_eq('gs quant canonical 0432 gs_quant/test/backtest/test_generic_engine.py nav_scaled_action_transaction_cost_test_for_agg_type', fin_gsq_test_nav_scaled_action_transaction_cost_test_for_agg_type('local_payload').payload || ':' || fin_gsq_test_nav_scaled_action_transaction_cost_test_for_agg_type('local_payload').source_function, 'local_payload:nav_scaled_action_transaction_cost_test_for_agg_type');
SELECT assert_eq('gs quant canonical 0433 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_action_nav_with_transaction_costs', fin_gsq_test_test_add_scaled_action_nav_with_transaction_costs('local_payload').payload || ':' || fin_gsq_test_test_add_scaled_action_nav_with_transaction_costs('local_payload').source_function, 'local_payload:test_add_scaled_action_nav_with_transaction_costs');
SELECT assert_eq('gs quant canonical 0434 gs_quant/test/backtest/test_generic_engine.py test_generic_engine_custom_price_measure', fin_gsq_test_test_generic_engine_custom_price_measure('local_payload').payload || ':' || fin_gsq_test_test_generic_engine_custom_price_measure('local_payload').source_function, 'local_payload:test_generic_engine_custom_price_measure');
SELECT assert_eq('gs quant canonical 0435 gs_quant/test/backtest/test_generic_engine.py test_serialisation', fin_gsq_test_test_serialisation('local_payload').payload || ':' || fin_gsq_test_test_serialisation('local_payload').source_function, 'local_payload:test_serialisation');
SELECT assert_eq('gs quant canonical 0436 gs_quant/test/backtest/test_generic_engine.py test_initial_portfolio', fin_gsq_test_test_initial_portfolio('local_payload').payload || ':' || fin_gsq_test_test_initial_portfolio('local_payload').source_function, 'local_payload:test_initial_portfolio');
SELECT assert_eq('gs quant canonical 0437 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_trade_action_with_quantity_signal', fin_gsq_test_test_add_scaled_trade_action_with_quantity_signal('local_payload').payload || ':' || fin_gsq_test_test_add_scaled_trade_action_with_quantity_signal('local_payload').source_function, 'local_payload:test_add_scaled_trade_action_with_quantity_signal');
SELECT assert_eq('gs quant canonical 0438 gs_quant/test/backtest/test_generic_engine.py test_add_weighted_trade_action', fin_gsq_test_test_add_weighted_trade_action('local_payload').payload || ':' || fin_gsq_test_test_add_weighted_trade_action('local_payload').source_function, 'local_payload:test_add_weighted_trade_action');
SELECT assert_eq('gs quant canonical 0439 gs_quant/test/backtest/test_generic_engine.py test_early_exit_pos_limit_scaled_action', fin_gsq_test_test_early_exit_pos_limit_scaled_action('local_payload').payload || ':' || fin_gsq_test_test_early_exit_pos_limit_scaled_action('local_payload').source_function, 'local_payload:test_early_exit_pos_limit_scaled_action');
SELECT assert_eq('gs quant canonical 0440 gs_quant/test/backtest/test_triggers.py test_date_trigger', fin_gsq_test_test_date_trigger('local_payload').payload || ':' || fin_gsq_test_test_date_trigger('local_payload').source_function, 'local_payload:test_date_trigger');
SELECT assert_eq('gs quant canonical 0441 gs_quant/test/backtest/test_triggers.py test_aggregate_triggger', fin_gsq_test_test_aggregate_triggger('local_payload').payload || ':' || fin_gsq_test_test_aggregate_triggger('local_payload').source_function, 'local_payload:test_aggregate_triggger');
SELECT assert_eq('gs quant canonical 0442 gs_quant/test/backtest/test_triggers.py test_not_triggger', fin_gsq_test_test_not_triggger('local_payload').payload || ':' || fin_gsq_test_test_not_triggger('local_payload').source_function, 'local_payload:test_not_triggger');
SELECT assert_eq('gs quant canonical 0443 gs_quant/test/config/test_options.py test_display_options', fin_gsq_test_test_display_options('local_payload').payload || ':' || fin_gsq_test_test_display_options('local_payload').source_function, 'local_payload:test_display_options');
SELECT assert_eq('gs quant canonical 0444 gs_quant/test/data/test_data_coordinate.py test_immutability', fin_gsq_test_test_immutability('local_payload').payload || ':' || fin_gsq_test_test_immutability('local_payload').source_function, 'local_payload:test_immutability');
SELECT assert_eq('gs quant canonical 0445 gs_quant/test/data/test_data_coordinate.py test_equals', fin_gsq_test_test_equals('local_payload').payload || ':' || fin_gsq_test_test_equals('local_payload').source_function, 'local_payload:test_equals');
SELECT assert_eq('gs quant canonical 0446 gs_quant/test/data/test_data_coordinate.py test_equals_measure_str', fin_gsq_test_test_equals_measure_str('local_payload').payload || ':' || fin_gsq_test_test_equals_measure_str('local_payload').source_function, 'local_payload:test_equals_measure_str');
SELECT assert_eq('gs quant canonical 0447 gs_quant/test/data/test_dataset.py test_query_data', fin_gsq_test_test_query_data('local_payload').payload || ':' || fin_gsq_test_test_query_data('local_payload').source_function, 'local_payload:test_query_data');
SELECT assert_eq('gs quant canonical 0448 gs_quant/test/data/test_dataset.py test_query_data_intervals', fin_gsq_test_test_query_data_intervals('local_payload').payload || ':' || fin_gsq_test_test_query_data_intervals('local_payload').source_function, 'local_payload:test_query_data_intervals');
SELECT assert_eq('gs quant canonical 0449 gs_quant/test/data/test_dataset.py test_query_data_types', fin_gsq_test_test_query_data_types('local_payload').payload || ':' || fin_gsq_test_test_query_data_types('local_payload').source_function, 'local_payload:test_query_data_types');
SELECT assert_eq('gs quant canonical 0450 gs_quant/test/data/test_dataset.py test_last_data', fin_gsq_test_test_last_data('local_payload').payload || ':' || fin_gsq_test_test_last_data('local_payload').source_function, 'local_payload:test_last_data');
SELECT assert_eq('gs quant canonical 0451 gs_quant/test/data/test_dataset.py test_get_data_series', fin_gsq_test_test_get_data_series_test_data_test_dataset('local_payload').payload || ':' || fin_gsq_test_test_get_data_series_test_data_test_dataset('local_payload').source_function, 'local_payload:test_get_data_series');
SELECT assert_eq('gs quant canonical 0452 gs_quant/test/data/test_dataset.py test_get_coverage', fin_gsq_test_test_get_coverage('local_payload').payload || ':' || fin_gsq_test_test_get_coverage('local_payload').source_function, 'local_payload:test_get_coverage');
SELECT assert_eq('gs quant canonical 0453 gs_quant/test/data/test_dataset.py test_construct_dataframe_with_types', fin_gsq_test_test_construct_dataframe_with_types('local_payload').payload || ':' || fin_gsq_test_test_construct_dataframe_with_types('local_payload').source_function, 'local_payload:test_construct_dataframe_with_types');
SELECT assert_eq('gs quant canonical 0454 gs_quant/test/data/test_dataset.py test_construct_dataframe_var_schema', fin_gsq_test_test_construct_dataframe_var_schema('local_payload').payload || ':' || fin_gsq_test_test_construct_dataframe_var_schema('local_payload').source_function, 'local_payload:test_construct_dataframe_var_schema');
SELECT assert_eq('gs quant canonical 0455 gs_quant/test/data/test_dataset.py test_dataframe_with_mixed_date_type', fin_gsq_test_test_dataframe_with_mixed_date_type('local_payload').payload || ':' || fin_gsq_test_test_dataframe_with_mixed_date_type('local_payload').source_function, 'local_payload:test_dataframe_with_mixed_date_type');
SELECT assert_eq('gs quant canonical 0456 gs_quant/test/data/test_dataset.py test_data_series_format', fin_gsq_test_test_data_series_format('local_payload').payload || ':' || fin_gsq_test_test_data_series_format('local_payload').source_function, 'local_payload:test_data_series_format');
SELECT assert_eq('gs quant canonical 0457 gs_quant/test/data/test_dataset.py test_get_data_bulk', fin_gsq_test_test_get_data_bulk('local_payload').payload || ':' || fin_gsq_test_test_get_data_bulk('local_payload').source_function, 'local_payload:test_get_data_bulk');
SELECT assert_eq('gs quant canonical 0458 gs_quant/test/data/test_query.py test_build_market_data_query', fin_gsq_test_test_build_market_data_query('local_payload').payload || ':' || fin_gsq_test_test_build_market_data_query('local_payload').source_function, 'local_payload:test_build_market_data_query');
SELECT assert_eq('gs quant canonical 0459 gs_quant/test/datetime_/test_date.py test_has_feb_29', fin_gsq_test_test_has_feb_29('local_payload').payload || ':' || fin_gsq_test_test_has_feb_29('local_payload').source_function, 'local_payload:test_has_feb_29');
SELECT assert_eq('gs quant canonical 0460 gs_quant/test/datetime_/test_date.py test_today_with_location', fin_gsq_test_test_today_with_location('local_payload').payload || ':' || fin_gsq_test_test_today_with_location('local_payload').source_function, 'local_payload:test_today_with_location');
SELECT assert_eq('gs quant canonical 0461 gs_quant/test/datetime_/test_date.py test_day_count_fraction', fin_gsq_test_test_day_count_fraction('local_payload').payload || ':' || fin_gsq_test_test_day_count_fraction('local_payload').source_function, 'local_payload:test_day_count_fraction');
SELECT assert_eq('gs quant canonical 0462 gs_quant/test/datetime_/test_gscalendar.py test_gs_calendar_single', fin_gsq_test_test_gs_calendar_single('local_payload').payload || ':' || fin_gsq_test_test_gs_calendar_single('local_payload').source_function, 'local_payload:test_gs_calendar_single');
SELECT assert_eq('gs quant canonical 0463 gs_quant/test/datetime_/test_gscalendar.py test_gs_calendar_tuple', fin_gsq_test_test_gs_calendar_tuple('local_payload').payload || ':' || fin_gsq_test_test_gs_calendar_tuple('local_payload').source_function, 'local_payload:test_gs_calendar_tuple');
SELECT assert_eq('gs quant canonical 0464 gs_quant/test/datetime_/test_point.py test_point_sort_order', fin_gsq_test_test_point_sort_order('local_payload').payload || ':' || fin_gsq_test_test_point_sort_order('local_payload').source_function, 'local_payload:test_point_sort_order');
SELECT assert_eq('gs quant canonical 0465 gs_quant/test/datetime_/test_relative_date.py test_rule_parsing', fin_gsq_test_test_rule_parsing('local_payload').payload || ':' || fin_gsq_test_test_rule_parsing('local_payload').source_function, 'local_payload:test_rule_parsing');
SELECT assert_eq('gs quant canonical 0466 gs_quant/test/datetime_/test_relative_date.py test_rule_a_', fin_gsq_test_test_rule_a('local_payload').payload || ':' || fin_gsq_test_test_rule_a('local_payload').source_function, 'local_payload:test_rule_a_');
SELECT assert_eq('gs quant canonical 0467 gs_quant/test/datetime_/test_relative_date.py test_rule_b', fin_gsq_test_test_rule_b('local_payload').payload || ':' || fin_gsq_test_test_rule_b('local_payload').source_function, 'local_payload:test_rule_b');
SELECT assert_eq('gs quant canonical 0468 gs_quant/test/datetime_/test_relative_date.py test_rule_d', fin_gsq_test_test_rule_d('local_payload').payload || ':' || fin_gsq_test_test_rule_d('local_payload').source_function, 'local_payload:test_rule_d');
SELECT assert_eq('gs quant canonical 0469 gs_quant/test/datetime_/test_relative_date.py test_rule_e', fin_gsq_test_test_rule_e('local_payload').payload || ':' || fin_gsq_test_test_rule_e('local_payload').source_function, 'local_payload:test_rule_e');
SELECT assert_eq('gs quant canonical 0470 gs_quant/test/datetime_/test_relative_date.py test_rule_m_', fin_gsq_test_test_rule_m('local_payload').payload || ':' || fin_gsq_test_test_rule_m('local_payload').source_function, 'local_payload:test_rule_m_');
SELECT assert_eq('gs quant canonical 0471 gs_quant/test/datetime_/test_relative_date.py test_rule_t_', fin_gsq_test_test_rule_t('local_payload').payload || ':' || fin_gsq_test_test_rule_t('local_payload').source_function, 'local_payload:test_rule_t_');
SELECT assert_eq('gs quant canonical 0472 gs_quant/test/datetime_/test_relative_date.py test_rule_w_', fin_gsq_test_test_rule_w('local_payload').payload || ':' || fin_gsq_test_test_rule_w('local_payload').source_function, 'local_payload:test_rule_w_');
SELECT assert_eq('gs quant canonical 0473 gs_quant/test/datetime_/test_relative_date.py test_rule_r_', fin_gsq_test_test_rule_r('local_payload').payload || ':' || fin_gsq_test_test_rule_r('local_payload').source_function, 'local_payload:test_rule_r_');
SELECT assert_eq('gs quant canonical 0474 gs_quant/test/datetime_/test_relative_date.py test_rule_f_', fin_gsq_test_test_rule_f('local_payload').payload || ':' || fin_gsq_test_test_rule_f('local_payload').source_function, 'local_payload:test_rule_f_');
SELECT assert_eq('gs quant canonical 0475 gs_quant/test/datetime_/test_relative_date.py test_rule_v_', fin_gsq_test_test_rule_v('local_payload').payload || ':' || fin_gsq_test_test_rule_v('local_payload').source_function, 'local_payload:test_rule_v_');
SELECT assert_eq('gs quant canonical 0476 gs_quant/test/datetime_/test_relative_date.py test_rule_z_', fin_gsq_test_test_rule_z('local_payload').payload || ':' || fin_gsq_test_test_rule_z('local_payload').source_function, 'local_payload:test_rule_z_');
SELECT assert_eq('gs quant canonical 0477 gs_quant/test/datetime_/test_relative_date.py test_rule_g', fin_gsq_test_test_rule_g('local_payload').payload || ':' || fin_gsq_test_test_rule_g('local_payload').source_function, 'local_payload:test_rule_g');
SELECT assert_eq('gs quant canonical 0478 gs_quant/test/datetime_/test_relative_date.py test_rule_n_', fin_gsq_test_test_rule_n('local_payload').payload || ':' || fin_gsq_test_test_rule_n('local_payload').source_function, 'local_payload:test_rule_n_');
SELECT assert_eq('gs quant canonical 0479 gs_quant/test/datetime_/test_relative_date.py test_rule_u_', fin_gsq_test_test_rule_u('local_payload').payload || ':' || fin_gsq_test_test_rule_u('local_payload').source_function, 'local_payload:test_rule_u_');
SELECT assert_eq('gs quant canonical 0480 gs_quant/test/datetime_/test_relative_date.py test_rule_x_', fin_gsq_test_test_rule_x('local_payload').payload || ':' || fin_gsq_test_test_rule_x('local_payload').source_function, 'local_payload:test_rule_x_');
SELECT assert_eq('gs quant canonical 0481 gs_quant/test/datetime_/test_relative_date.py test_rule_s_', fin_gsq_test_test_rule_s('local_payload').payload || ':' || fin_gsq_test_test_rule_s('local_payload').source_function, 'local_payload:test_rule_s_');
SELECT assert_eq('gs quant canonical 0482 gs_quant/test/datetime_/test_relative_date.py test_rule_g_', fin_gsq_test_test_rule_g_test_datetime_test_relative_date('local_payload').payload || ':' || fin_gsq_test_test_rule_g_test_datetime_test_relative_date('local_payload').source_function, 'local_payload:test_rule_g_');
SELECT assert_eq('gs quant canonical 0483 gs_quant/test/datetime_/test_relative_date.py test_rule_i_', fin_gsq_test_test_rule_i('local_payload').payload || ':' || fin_gsq_test_test_rule_i('local_payload').source_function, 'local_payload:test_rule_i_');
SELECT assert_eq('gs quant canonical 0484 gs_quant/test/datetime_/test_relative_date.py test_rule_p_', fin_gsq_test_test_rule_p('local_payload').payload || ':' || fin_gsq_test_test_rule_p('local_payload').source_function, 'local_payload:test_rule_p_');
SELECT assert_eq('gs quant canonical 0485 gs_quant/test/datetime_/test_relative_date.py test_rule_w', fin_gsq_test_test_rule_w_test_datetime_test_relative_date('local_payload').payload || ':' || fin_gsq_test_test_rule_w_test_datetime_test_relative_date('local_payload').source_function, 'local_payload:test_rule_w');
SELECT assert_eq('gs quant canonical 0486 gs_quant/test/datetime_/test_relative_date.py test_rule_k', fin_gsq_test_test_rule_k('local_payload').payload || ':' || fin_gsq_test_test_rule_k('local_payload').source_function, 'local_payload:test_rule_k');
SELECT assert_eq('gs quant canonical 0487 gs_quant/test/datetime_/test_relative_date.py test_rule_r', fin_gsq_test_test_rule_r_test_datetime_test_relative_date('local_payload').payload || ':' || fin_gsq_test_test_rule_r_test_datetime_test_relative_date('local_payload').source_function, 'local_payload:test_rule_r');
SELECT assert_eq('gs quant canonical 0488 gs_quant/test/datetime_/test_relative_date.py test_rule_u', fin_gsq_test_test_rule_u_test_datetime_test_relative_date('local_payload').payload || ':' || fin_gsq_test_test_rule_u_test_datetime_test_relative_date('local_payload').source_function, 'local_payload:test_rule_u');
SELECT assert_eq('gs quant canonical 0489 gs_quant/test/datetime_/test_relative_date.py test_rule_v', fin_gsq_test_test_rule_v_test_datetime_test_relative_date('local_payload').payload || ':' || fin_gsq_test_test_rule_v_test_datetime_test_relative_date('local_payload').source_function, 'local_payload:test_rule_v');
SELECT assert_eq('gs quant canonical 0490 gs_quant/test/datetime_/test_relative_date.py test_rule_x', fin_gsq_test_test_rule_x_test_datetime_test_relative_date('local_payload').payload || ':' || fin_gsq_test_test_rule_x_test_datetime_test_relative_date('local_payload').source_function, 'local_payload:test_rule_x');
SELECT assert_eq('gs quant canonical 0491 gs_quant/test/datetime_/test_relative_date.py test_rule_y', fin_gsq_test_test_rule_y('local_payload').payload || ':' || fin_gsq_test_test_rule_y('local_payload').source_function, 'local_payload:test_rule_y');
SELECT assert_eq('gs quant canonical 0492 gs_quant/test/datetime_/test_relative_date.py test_chaining', fin_gsq_test_test_chaining('local_payload').payload || ':' || fin_gsq_test_test_chaining('local_payload').source_function, 'local_payload:test_chaining');
SELECT assert_eq('gs quant canonical 0493 gs_quant/test/datetime_/test_relative_date.py test_rule_e_minus_u', fin_gsq_test_test_rule_e_minus_u('local_payload').payload || ':' || fin_gsq_test_test_rule_e_minus_u('local_payload').source_function, 'local_payload:test_rule_e_minus_u');
SELECT assert_eq('gs quant canonical 0494 gs_quant/test/datetime_/test_relative_date.py test_rule_roll_convention', fin_gsq_test_test_rule_roll_convention('local_payload').payload || ':' || fin_gsq_test_test_rule_roll_convention('local_payload').source_function, 'local_payload:test_rule_roll_convention');
SELECT assert_eq('gs quant canonical 0495 gs_quant/test/datetime_/test_relative_date.py mock_holiday_data', fin_gsq_test_mock_holiday_data('local_payload').payload || ':' || fin_gsq_test_mock_holiday_data('local_payload').source_function, 'local_payload:mock_holiday_data');
SELECT assert_eq('gs quant canonical 0496 gs_quant/test/datetime_/test_relative_date.py test_currency_holiday_calendars', fin_gsq_test_test_currency_holiday_calendars('local_payload').payload || ':' || fin_gsq_test_test_currency_holiday_calendars('local_payload').source_function, 'local_payload:test_currency_holiday_calendars');
SELECT assert_eq('gs quant canonical 0497 gs_quant/test/datetime_/test_time.py test_time_difference_as_string', fin_gsq_test_test_time_difference_as_string('local_payload').payload || ':' || fin_gsq_test_test_time_difference_as_string('local_payload').source_function, 'local_payload:test_time_difference_as_string');
SELECT assert_eq('gs quant canonical 0498 gs_quant/test/entities/test_entitlements.py get_fake_user', fin_gsq_test_get_fake_user('local_payload').payload || ':' || fin_gsq_test_get_fake_user('local_payload').source_function, 'local_payload:get_fake_user');
SELECT assert_eq('gs quant canonical 0499 gs_quant/test/entities/test_entitlements.py get_fake_group', fin_gsq_test_get_fake_group('local_payload').payload || ':' || fin_gsq_test_get_fake_group('local_payload').source_function, 'local_payload:get_fake_group');
SELECT assert_eq('gs quant canonical 0500 gs_quant/test/entities/test_entitlements.py test_to_target', fin_gsq_test_test_to_target('local_payload').payload || ':' || fin_gsq_test_test_to_target('local_payload').source_function, 'local_payload:test_to_target');
SELECT assert_eq('gs quant canonical 0501 gs_quant/test/entities/test_entitlements.py test_to_dict', fin_gsq_test_test_to_dict('local_payload').payload || ':' || fin_gsq_test_test_to_dict('local_payload').source_function, 'local_payload:test_to_dict');
SELECT assert_eq('gs quant canonical 0502 gs_quant/test/entities/test_entitlements.py test_from_target', fin_gsq_test_test_from_target('local_payload').payload || ':' || fin_gsq_test_test_from_target('local_payload').source_function, 'local_payload:test_from_target');
SELECT assert_eq('gs quant canonical 0503 gs_quant/test/entities/test_entitlements.py test_from_dict', fin_gsq_test_test_from_dict_test_entities_test_entitlements('local_payload').payload || ':' || fin_gsq_test_test_from_dict_test_entities_test_entitlements('local_payload').source_function, 'local_payload:test_from_dict');
SELECT assert_eq('gs quant canonical 0504 gs_quant/test/entities/test_group.py test_get', fin_gsq_test_test_get('local_payload').payload || ':' || fin_gsq_test_test_get('local_payload').source_function, 'local_payload:test_get');
SELECT assert_eq('gs quant canonical 0505 gs_quant/test/entities/test_group.py test_get_many', fin_gsq_test_test_get_many('local_payload').payload || ':' || fin_gsq_test_test_get_many('local_payload').source_function, 'local_payload:test_get_many');
SELECT assert_eq('gs quant canonical 0506 gs_quant/test/entities/test_group.py test_save_update', fin_gsq_test_test_save_update('local_payload').payload || ':' || fin_gsq_test_test_save_update('local_payload').source_function, 'local_payload:test_save_update');
SELECT assert_eq('gs quant canonical 0507 gs_quant/test/entities/test_group.py test_save_create', fin_gsq_test_test_save_create('local_payload').payload || ':' || fin_gsq_test_test_save_create('local_payload').source_function, 'local_payload:test_save_create');
SELECT assert_eq('gs quant canonical 0508 gs_quant/test/entities/test_user.py test_get', fin_gsq_test_test_get_test_entities_test_user('local_payload').payload || ':' || fin_gsq_test_test_get_test_entities_test_user('local_payload').source_function, 'local_payload:test_get');
SELECT assert_eq('gs quant canonical 0509 gs_quant/test/entities/test_user.py test_get_many', fin_gsq_test_test_get_many_test_entities_test_user('local_payload').payload || ':' || fin_gsq_test_test_get_many_test_entities_test_user('local_payload').source_function, 'local_payload:test_get_many');
SELECT assert_eq('gs quant canonical 0510 gs_quant/test/markets/test_baskets.py mock_session', fin_gsq_test_mock_session_test_markets_test_baskets('local_payload').payload || ':' || fin_gsq_test_mock_session_test_markets_test_baskets('local_payload').source_function, 'local_payload:mock_session');
SELECT assert_eq('gs quant canonical 0511 gs_quant/test/markets/test_baskets.py mock_response', fin_gsq_test_mock_response('local_payload').payload || ':' || fin_gsq_test_mock_response('local_payload').source_function, 'local_payload:mock_response');
SELECT assert_eq('gs quant canonical 0512 gs_quant/test/markets/test_baskets.py mock_basket_init', fin_gsq_test_mock_basket_init('local_payload').payload || ':' || fin_gsq_test_mock_basket_init('local_payload').source_function, 'local_payload:mock_basket_init');
SELECT assert_eq('gs quant canonical 0513 gs_quant/test/markets/test_baskets.py test_basket_error_messages', fin_gsq_test_test_basket_error_messages('local_payload').payload || ':' || fin_gsq_test_test_basket_error_messages('local_payload').source_function, 'local_payload:test_basket_error_messages');
SELECT assert_eq('gs quant canonical 0514 gs_quant/test/markets/test_baskets.py test_basket_create', fin_gsq_test_test_basket_create_test_markets_test_baskets('local_payload').payload || ':' || fin_gsq_test_test_basket_create_test_markets_test_baskets('local_payload').source_function, 'local_payload:test_basket_create');
SELECT assert_eq('gs quant canonical 0515 gs_quant/test/markets/test_baskets.py test_basket_clone', fin_gsq_test_test_basket_clone('local_payload').payload || ':' || fin_gsq_test_test_basket_clone('local_payload').source_function, 'local_payload:test_basket_clone');
SELECT assert_eq('gs quant canonical 0516 gs_quant/test/markets/test_baskets.py test_basket_edit', fin_gsq_test_test_basket_edit_test_markets_test_baskets('local_payload').payload || ':' || fin_gsq_test_test_basket_edit_test_markets_test_baskets('local_payload').source_function, 'local_payload:test_basket_edit');
SELECT assert_eq('gs quant canonical 0517 gs_quant/test/markets/test_baskets.py test_basket_rebalance', fin_gsq_test_test_basket_rebalance_test_markets_test_baskets('local_payload').payload || ':' || fin_gsq_test_test_basket_rebalance_test_markets_test_baskets('local_payload').source_function, 'local_payload:test_basket_rebalance');
SELECT assert_eq('gs quant canonical 0518 gs_quant/test/markets/test_baskets.py test_basket_edit_and_rebalance', fin_gsq_test_test_basket_edit_and_rebalance('local_payload').payload || ':' || fin_gsq_test_test_basket_edit_and_rebalance('local_payload').source_function, 'local_payload:test_basket_edit_and_rebalance');
SELECT assert_eq('gs quant canonical 0519 gs_quant/test/markets/test_baskets.py test_basket_update_entitlements', fin_gsq_test_test_basket_update_entitlements('local_payload').payload || ':' || fin_gsq_test_test_basket_update_entitlements('local_payload').source_function, 'local_payload:test_basket_update_entitlements');
SELECT assert_eq('gs quant canonical 0520 gs_quant/test/markets/test_baskets.py test_upload_position_history', fin_gsq_test_test_upload_position_history('local_payload').payload || ':' || fin_gsq_test_test_upload_position_history('local_payload').source_function, 'local_payload:test_upload_position_history');
SELECT assert_eq('gs quant canonical 0521 gs_quant/test/markets/test_baskets.py test_update_risk_reports', fin_gsq_test_test_update_risk_reports('local_payload').payload || ':' || fin_gsq_test_test_update_risk_reports('local_payload').source_function, 'local_payload:test_update_risk_reports');
SELECT assert_eq('gs quant canonical 0522 gs_quant/test/markets/test_close_market.py test_close_market_dict', fin_gsq_test_test_close_market_dict('local_payload').payload || ':' || fin_gsq_test_test_close_market_dict('local_payload').source_function, 'local_payload:test_close_market_dict');
SELECT assert_eq('gs quant canonical 0523 gs_quant/test/markets/test_close_market.py test_close_market_roll', fin_gsq_test_test_close_market_roll('local_payload').payload || ':' || fin_gsq_test_test_close_market_roll('local_payload').source_function, 'local_payload:test_close_market_roll');
SELECT assert_eq('gs quant canonical 0524 gs_quant/test/markets/test_close_market.py test_close_market_roll_diff_days', fin_gsq_test_test_close_market_roll_diff_days('local_payload').payload || ':' || fin_gsq_test_test_close_market_roll_diff_days('local_payload').source_function, 'local_payload:test_close_market_roll_diff_days');
SELECT assert_eq('gs quant canonical 0525 gs_quant/test/markets/test_hedger.py test_hedge_exclusions_to_dict', fin_gsq_test_test_hedge_exclusions_to_dict('local_payload').payload || ':' || fin_gsq_test_test_hedge_exclusions_to_dict('local_payload').source_function, 'local_payload:test_hedge_exclusions_to_dict');
SELECT assert_eq('gs quant canonical 0526 gs_quant/test/markets/test_hedger.py test_hedge_constraints_to_dict', fin_gsq_test_test_hedge_constraints_to_dict('local_payload').payload || ':' || fin_gsq_test_test_hedge_constraints_to_dict('local_payload').source_function, 'local_payload:test_hedge_constraints_to_dict');
SELECT assert_eq('gs quant canonical 0527 gs_quant/test/markets/test_hedger.py test_format_hedge_calculate_results', fin_gsq_test_test_format_hedge_calculate_results('local_payload').payload || ':' || fin_gsq_test_test_format_hedge_calculate_results('local_payload').source_function, 'local_payload:test_format_hedge_calculate_results');
SELECT assert_eq('gs quant canonical 0528 gs_quant/test/markets/test_hedger.py get_mock_hedge', fin_gsq_test_get_mock_hedge('local_payload').payload || ':' || fin_gsq_test_get_mock_hedge('local_payload').source_function, 'local_payload:get_mock_hedge');
SELECT assert_eq('gs quant canonical 0529 gs_quant/test/markets/test_hedger.py test_get_constituents', fin_gsq_test_test_get_constituents('local_payload').payload || ':' || fin_gsq_test_test_get_constituents('local_payload').source_function, 'local_payload:test_get_constituents');
SELECT assert_eq('gs quant canonical 0530 gs_quant/test/markets/test_hedger.py test_get_statistics', fin_gsq_test_test_get_statistics('local_payload').payload || ':' || fin_gsq_test_test_get_statistics('local_payload').source_function, 'local_payload:test_get_statistics');
SELECT assert_eq('gs quant canonical 0531 gs_quant/test/markets/test_hedger.py test_get_backtest_performance', fin_gsq_test_test_get_backtest_performance('local_payload').payload || ':' || fin_gsq_test_test_get_backtest_performance('local_payload').source_function, 'local_payload:test_get_backtest_performance');
SELECT assert_eq('gs quant canonical 0532 gs_quant/test/markets/test_instrument.py test_instrument_resolve', fin_gsq_test_test_instrument_resolve('local_payload').payload || ':' || fin_gsq_test_test_instrument_resolve('local_payload').source_function, 'local_payload:test_instrument_resolve');
SELECT assert_eq('gs quant canonical 0533 gs_quant/test/markets/test_instrument.py test_nested_leg_from_dict', fin_gsq_test_test_nested_leg_from_dict('local_payload').payload || ':' || fin_gsq_test_test_nested_leg_from_dict('local_payload').source_function, 'local_payload:test_nested_leg_from_dict');
SELECT assert_eq('gs quant canonical 0534 gs_quant/test/markets/test_portfolio.py set_session', fin_gsq_test_set_session_test_markets_test_portfolio('local_payload').payload || ':' || fin_gsq_test_set_session_test_markets_test_portfolio('local_payload').source_function, 'local_payload:set_session');
SELECT assert_eq('gs quant canonical 0535 gs_quant/test/markets/test_portfolio.py test_portfolio', fin_gsq_test_test_portfolio('local_payload').payload || ':' || fin_gsq_test_test_portfolio('local_payload').source_function, 'local_payload:test_portfolio');
SELECT assert_eq('gs quant canonical 0536 gs_quant/test/markets/test_portfolio.py test_construction', fin_gsq_test_test_construction('local_payload').payload || ':' || fin_gsq_test_test_construction('local_payload').source_function, 'local_payload:test_construction');
SELECT assert_eq('gs quant canonical 0537 gs_quant/test/markets/test_portfolio.py test_historical_pricing', fin_gsq_test_test_historical_pricing('local_payload').payload || ':' || fin_gsq_test_test_historical_pricing('local_payload').source_function, 'local_payload:test_historical_pricing');
SELECT assert_eq('gs quant canonical 0538 gs_quant/test/markets/test_portfolio.py test_backtothefuture_pricing', fin_gsq_test_test_backtothefuture_pricing('local_payload').payload || ':' || fin_gsq_test_test_backtothefuture_pricing('local_payload').source_function, 'local_payload:test_backtothefuture_pricing');
SELECT assert_eq('gs quant canonical 0539 gs_quant/test/markets/test_portfolio.py test_duplicate_instrument', fin_gsq_test_test_duplicate_instrument('local_payload').payload || ':' || fin_gsq_test_test_duplicate_instrument('local_payload').source_function, 'local_payload:test_duplicate_instrument');
SELECT assert_eq('gs quant canonical 0540 gs_quant/test/markets/test_portfolio.py test_nested_portfolios', fin_gsq_test_test_nested_portfolios('local_payload').payload || ':' || fin_gsq_test_test_nested_portfolios('local_payload').source_function, 'local_payload:test_nested_portfolios');
SELECT assert_eq('gs quant canonical 0541 gs_quant/test/markets/test_portfolio.py test_single_instrument', fin_gsq_test_test_single_instrument('local_payload').payload || ':' || fin_gsq_test_test_single_instrument('local_payload').source_function, 'local_payload:test_single_instrument');
SELECT assert_eq('gs quant canonical 0542 gs_quant/test/markets/test_portfolio.py test_results_with_resolution', fin_gsq_test_test_results_with_resolution('local_payload').payload || ':' || fin_gsq_test_test_results_with_resolution('local_payload').source_function, 'local_payload:test_results_with_resolution');
SELECT assert_eq('gs quant canonical 0543 gs_quant/test/markets/test_portfolio.py test_portfolio_overrides', fin_gsq_test_test_portfolio_overrides('local_payload').payload || ':' || fin_gsq_test_test_portfolio_overrides('local_payload').source_function, 'local_payload:test_portfolio_overrides');
SELECT assert_eq('gs quant canonical 0544 gs_quant/test/markets/test_portfolio.py test_from_frame', fin_gsq_test_test_from_frame('local_payload').payload || ':' || fin_gsq_test_test_from_frame('local_payload').source_function, 'local_payload:test_from_frame');
SELECT assert_eq('gs quant canonical 0545 gs_quant/test/markets/test_portfolio.py test_single_instrument_new_mock', fin_gsq_test_test_single_instrument_new_mock('local_payload').payload || ':' || fin_gsq_test_test_single_instrument_new_mock('local_payload').source_function, 'local_payload:test_single_instrument_new_mock');
SELECT assert_eq('gs quant canonical 0546 gs_quant/test/markets/test_portfolio.py test_get_instruments', fin_gsq_test_test_get_instruments('local_payload').payload || ':' || fin_gsq_test_test_get_instruments('local_payload').source_function, 'local_payload:test_get_instruments');
SELECT assert_eq('gs quant canonical 0547 gs_quant/test/markets/test_portfolio.py test_clone', fin_gsq_test_test_clone('local_payload').payload || ':' || fin_gsq_test_test_clone('local_payload').source_function, 'local_payload:test_clone');
SELECT assert_eq('gs quant canonical 0548 gs_quant/test/markets/test_portfolio_manager.py test_get_reports', fin_gsq_test_test_get_reports_test_markets_test_portfolio_manager('local_payload').payload || ':' || fin_gsq_test_test_get_reports_test_markets_test_portfolio_manager('local_payload').source_function, 'local_payload:test_get_reports');
SELECT assert_eq('gs quant canonical 0549 gs_quant/test/markets/test_portfolio_manager.py test_get_schedule_dates', fin_gsq_test_test_get_schedule_dates('local_payload').payload || ':' || fin_gsq_test_test_get_schedule_dates('local_payload').source_function, 'local_payload:test_get_schedule_dates');
SELECT assert_eq('gs quant canonical 0550 gs_quant/test/markets/test_portfolio_manager.py test_set_entitlements', fin_gsq_test_test_set_entitlements('local_payload').payload || ':' || fin_gsq_test_test_set_entitlements('local_payload').source_function, 'local_payload:test_set_entitlements');
SELECT assert_eq('gs quant canonical 0551 gs_quant/test/markets/test_portfolio_manager.py test_run_reports', fin_gsq_test_test_run_reports('local_payload').payload || ':' || fin_gsq_test_test_run_reports('local_payload').source_function, 'local_payload:test_run_reports');
SELECT assert_eq('gs quant canonical 0552 gs_quant/test/markets/test_portfolio_manager.py test_batched_schedule_reports', fin_gsq_test_test_batched_schedule_reports('local_payload').payload || ':' || fin_gsq_test_test_batched_schedule_reports('local_payload').source_function, 'local_payload:test_batched_schedule_reports');
SELECT assert_eq('gs quant canonical 0553 gs_quant/test/markets/test_portfolio_manager.py test_batched_schedule_reports_wo_dates', fin_gsq_test_test_batched_schedule_reports_wo_dates('local_payload').payload || ':' || fin_gsq_test_test_batched_schedule_reports_wo_dates('local_payload').source_function, 'local_payload:test_batched_schedule_reports_wo_dates');
SELECT assert_eq('gs quant canonical 0554 gs_quant/test/markets/test_portfolio_manager.py test_batched_schedule_validations', fin_gsq_test_test_batched_schedule_validations('local_payload').payload || ':' || fin_gsq_test_test_batched_schedule_validations('local_payload').source_function, 'local_payload:test_batched_schedule_validations');
SELECT assert_eq('gs quant canonical 0555 gs_quant/test/markets/test_portfolio_manager.py test_esg_summary', fin_gsq_test_test_esg_summary('local_payload').payload || ':' || fin_gsq_test_test_esg_summary('local_payload').source_function, 'local_payload:test_esg_summary');
SELECT assert_eq('gs quant canonical 0556 gs_quant/test/markets/test_portfolio_manager.py test_esg_quintiles', fin_gsq_test_test_esg_quintiles('local_payload').payload || ':' || fin_gsq_test_test_esg_quintiles('local_payload').source_function, 'local_payload:test_esg_quintiles');
SELECT assert_eq('gs quant canonical 0557 gs_quant/test/markets/test_portfolio_manager.py test_esg_by_sector', fin_gsq_test_test_esg_by_sector('local_payload').payload || ':' || fin_gsq_test_test_esg_by_sector('local_payload').source_function, 'local_payload:test_esg_by_sector');
SELECT assert_eq('gs quant canonical 0558 gs_quant/test/markets/test_portfolio_manager.py test_esg_by_region', fin_gsq_test_test_esg_by_region('local_payload').payload || ':' || fin_gsq_test_test_esg_by_region('local_payload').source_function, 'local_payload:test_esg_by_region');
SELECT assert_eq('gs quant canonical 0559 gs_quant/test/markets/test_portfolio_manager.py test_esg_top_ten', fin_gsq_test_test_esg_top_ten('local_payload').payload || ':' || fin_gsq_test_test_esg_top_ten('local_payload').source_function, 'local_payload:test_esg_top_ten');
SELECT assert_eq('gs quant canonical 0560 gs_quant/test/markets/test_portfolio_manager.py test_esg_bottom_ten', fin_gsq_test_test_esg_bottom_ten('local_payload').payload || ':' || fin_gsq_test_test_esg_bottom_ten('local_payload').source_function, 'local_payload:test_esg_bottom_ten');
SELECT assert_eq('gs quant canonical 0561 gs_quant/test/markets/test_portfolio_manager.py test_carbon_coverage', fin_gsq_test_test_carbon_coverage('local_payload').payload || ':' || fin_gsq_test_test_carbon_coverage('local_payload').source_function, 'local_payload:test_carbon_coverage');
SELECT assert_eq('gs quant canonical 0562 gs_quant/test/markets/test_portfolio_manager.py test_carbon_sbti_netzero_coverage', fin_gsq_test_test_carbon_sbti_netzero_coverage('local_payload').payload || ':' || fin_gsq_test_test_carbon_sbti_netzero_coverage('local_payload').source_function, 'local_payload:test_carbon_sbti_netzero_coverage');
SELECT assert_eq('gs quant canonical 0563 gs_quant/test/markets/test_portfolio_manager.py test_carbon_emissions', fin_gsq_test_test_carbon_emissions('local_payload').payload || ':' || fin_gsq_test_test_carbon_emissions('local_payload').source_function, 'local_payload:test_carbon_emissions');
SELECT assert_eq('gs quant canonical 0564 gs_quant/test/markets/test_portfolio_manager.py test_carbon_emissions_allocation', fin_gsq_test_test_carbon_emissions_allocation('local_payload').payload || ':' || fin_gsq_test_test_carbon_emissions_allocation('local_payload').source_function, 'local_payload:test_carbon_emissions_allocation');
SELECT assert_eq('gs quant canonical 0565 gs_quant/test/markets/test_portfolio_manager.py test_carbon_attribution_table', fin_gsq_test_test_carbon_attribution_table('local_payload').payload || ':' || fin_gsq_test_test_carbon_attribution_table('local_payload').source_function, 'local_payload:test_carbon_attribution_table');
SELECT assert_eq('gs quant canonical 0566 gs_quant/test/markets/test_portfolio_manager.py test_get_macro_exposure', fin_gsq_test_test_get_macro_exposure('local_payload').payload || ':' || fin_gsq_test_test_get_macro_exposure('local_payload').source_function, 'local_payload:test_get_macro_exposure');
SELECT assert_eq('gs quant canonical 0567 gs_quant/test/markets/test_portfolio_manager.py test_get_factor_scenario_analytics', fin_gsq_test_test_get_factor_scenario_analytics('local_payload').payload || ':' || fin_gsq_test_test_get_factor_scenario_analytics('local_payload').source_function, 'local_payload:test_get_factor_scenario_analytics');
SELECT assert_eq('gs quant canonical 0568 gs_quant/test/markets/test_position_set.py test_position_resolve_many', fin_gsq_test_test_position_resolve_many('local_payload').payload || ':' || fin_gsq_test_test_position_resolve_many('local_payload').source_function, 'local_payload:test_position_resolve_many');
SELECT assert_eq('gs quant canonical 0569 gs_quant/test/markets/test_position_set.py position_sets_with_tags_and_notional', fin_gsq_test_position_sets_with_tags_and_notional('local_payload').payload || ':' || fin_gsq_test_position_sets_with_tags_and_notional('local_payload').source_function, 'local_payload:position_sets_with_tags_and_notional');
SELECT assert_eq('gs quant canonical 0570 gs_quant/test/markets/test_position_set.py expected_position_pricing_result', fin_gsq_test_expected_position_pricing_result('local_payload').payload || ':' || fin_gsq_test_expected_position_pricing_result('local_payload').source_function, 'local_payload:expected_position_pricing_result');
SELECT assert_eq('gs quant canonical 0571 gs_quant/test/markets/test_position_set.py test_position_price_many', fin_gsq_test_test_position_price_many('local_payload').payload || ':' || fin_gsq_test_test_position_price_many('local_payload').source_function, 'local_payload:test_position_price_many');
SELECT assert_eq('gs quant canonical 0572 gs_quant/test/markets/test_pricing_context.py test_pricing_context', fin_gsq_test_test_pricing_context('local_payload').payload || ':' || fin_gsq_test_test_pricing_context('local_payload').source_function, 'local_payload:test_pricing_context');
SELECT assert_eq('gs quant canonical 0573 gs_quant/test/markets/test_pricing_context.py test_pricing_dates', fin_gsq_test_test_pricing_dates('local_payload').payload || ':' || fin_gsq_test_test_pricing_dates('local_payload').source_function, 'local_payload:test_pricing_dates');
SELECT assert_eq('gs quant canonical 0574 gs_quant/test/markets/test_pricing_context.py test_weekend_dates', fin_gsq_test_test_weekend_dates('local_payload').payload || ':' || fin_gsq_test_test_weekend_dates('local_payload').source_function, 'local_payload:test_weekend_dates');
SELECT assert_eq('gs quant canonical 0575 gs_quant/test/markets/test_pricing_context.py test_market_data_object', fin_gsq_test_test_market_data_object('local_payload').payload || ':' || fin_gsq_test_test_market_data_object('local_payload').source_function, 'local_payload:test_market_data_object');
SELECT assert_eq('gs quant canonical 0576 gs_quant/test/markets/test_pricing_context.py test_pricing_context_metadata', fin_gsq_test_test_pricing_context_metadata('local_payload').payload || ':' || fin_gsq_test_test_pricing_context_metadata('local_payload').source_function, 'local_payload:test_pricing_context_metadata');
SELECT assert_eq('gs quant canonical 0577 gs_quant/test/markets/test_pricing_context.py test_creation', fin_gsq_test_test_creation('local_payload').payload || ':' || fin_gsq_test_test_creation('local_payload').source_function, 'local_payload:test_creation');
SELECT assert_eq('gs quant canonical 0578 gs_quant/test/markets/test_pricing_context.py test_inheritance', fin_gsq_test_test_inheritance('local_payload').payload || ':' || fin_gsq_test_test_inheritance('local_payload').source_function, 'local_payload:test_inheritance');
SELECT assert_eq('gs quant canonical 0579 gs_quant/test/markets/test_pricing_context.py test_max_concurrent', fin_gsq_test_test_max_concurrent('local_payload').payload || ':' || fin_gsq_test_test_max_concurrent('local_payload').source_function, 'local_payload:test_max_concurrent');
SELECT assert_eq('gs quant canonical 0580 gs_quant/test/markets/test_pricing_context.py test_dates_per_batch', fin_gsq_test_test_dates_per_batch('local_payload').payload || ':' || fin_gsq_test_test_dates_per_batch('local_payload').source_function, 'local_payload:test_dates_per_batch');
SELECT assert_eq('gs quant canonical 0581 gs_quant/test/markets/test_pricing_context.py test_current_inheritance', fin_gsq_test_test_current_inheritance('local_payload').payload || ':' || fin_gsq_test_test_current_inheritance('local_payload').source_function, 'local_payload:test_current_inheritance');
SELECT assert_eq('gs quant canonical 0582 gs_quant/test/markets/test_pricing_context.py test_cleanup', fin_gsq_test_test_cleanup('local_payload').payload || ':' || fin_gsq_test_test_cleanup('local_payload').source_function, 'local_payload:test_cleanup');
SELECT assert_eq('gs quant canonical 0583 gs_quant/test/markets/test_pricing_context.py test_market_props', fin_gsq_test_test_market_props('local_payload').payload || ':' || fin_gsq_test_test_market_props('local_payload').source_function, 'local_payload:test_market_props');
SELECT assert_eq('gs quant canonical 0584 gs_quant/test/markets/test_pricing_context.py test_pricing_does_not_affect_context', fin_gsq_test_test_pricing_does_not_affect_context('local_payload').payload || ':' || fin_gsq_test_test_pricing_does_not_affect_context('local_payload').source_function, 'local_payload:test_pricing_does_not_affect_context');
SELECT assert_eq('gs quant canonical 0585 gs_quant/test/markets/test_pricing_context.py test_different_nested_locations', fin_gsq_test_test_different_nested_locations('local_payload').payload || ':' || fin_gsq_test_test_different_nested_locations('local_payload').source_function, 'local_payload:test_different_nested_locations');
SELECT assert_eq('gs quant canonical 0586 gs_quant/test/markets/test_pricing_context.py test_async_behaviour', fin_gsq_test_test_async_behaviour('local_payload').payload || ':' || fin_gsq_test_test_async_behaviour('local_payload').source_function, 'local_payload:test_async_behaviour');
SELECT assert_eq('gs quant canonical 0587 gs_quant/test/markets/test_pricing_context.py test_use_context_for_inheritance', fin_gsq_test_test_use_context_for_inheritance('local_payload').payload || ':' || fin_gsq_test_test_use_context_for_inheritance('local_payload').source_function, 'local_payload:test_use_context_for_inheritance');
SELECT assert_eq('gs quant canonical 0588 gs_quant/test/markets/test_pricing_context.py test_provider', fin_gsq_test_test_provider('local_payload').payload || ':' || fin_gsq_test_test_provider('local_payload').source_function, 'local_payload:test_provider');
SELECT assert_eq('gs quant canonical 0589 gs_quant/test/markets/test_report.py test_get_performance_report', fin_gsq_test_test_get_performance_report('local_payload').payload || ':' || fin_gsq_test_test_get_performance_report('local_payload').source_function, 'local_payload:test_get_performance_report');
SELECT assert_eq('gs quant canonical 0590 gs_quant/test/markets/test_report.py test_get_aum_source', fin_gsq_test_test_get_aum_source('local_payload').payload || ':' || fin_gsq_test_test_get_aum_source('local_payload').source_function, 'local_payload:test_get_aum_source');
SELECT assert_eq('gs quant canonical 0591 gs_quant/test/markets/test_report.py test_get_custom_aum', fin_gsq_test_test_get_custom_aum('local_payload').payload || ':' || fin_gsq_test_test_get_custom_aum('local_payload').source_function, 'local_payload:test_get_custom_aum');
SELECT assert_eq('gs quant canonical 0592 gs_quant/test/markets/test_report.py test_get_aum', fin_gsq_test_test_get_aum('local_payload').payload || ':' || fin_gsq_test_test_get_aum('local_payload').source_function, 'local_payload:test_get_aum');
SELECT assert_eq('gs quant canonical 0593 gs_quant/test/markets/test_report.py test_get_risk_model_id', fin_gsq_test_test_get_risk_model_id('local_payload').payload || ':' || fin_gsq_test_test_get_risk_model_id('local_payload').source_function, 'local_payload:test_get_risk_model_id');
SELECT assert_eq('gs quant canonical 0594 gs_quant/test/markets/test_report.py test_set_position_target', fin_gsq_test_test_set_position_target('local_payload').payload || ':' || fin_gsq_test_test_set_position_target('local_payload').source_function, 'local_payload:test_set_position_target');
SELECT assert_eq('gs quant canonical 0595 gs_quant/test/markets/test_report.py test_get_factor_risk_report', fin_gsq_test_test_get_factor_risk_report('local_payload').payload || ':' || fin_gsq_test_test_get_factor_risk_report('local_payload').source_function, 'local_payload:test_get_factor_risk_report');
SELECT assert_eq('gs quant canonical 0596 gs_quant/test/markets/test_report.py test_get_factor_pnl', fin_gsq_test_test_get_factor_pnl('local_payload').payload || ':' || fin_gsq_test_test_get_factor_pnl('local_payload').source_function, 'local_payload:test_get_factor_pnl');
SELECT assert_eq('gs quant canonical 0597 gs_quant/test/markets/test_report.py test_get_factor_proportion_of_risk', fin_gsq_test_test_get_factor_proportion_of_risk('local_payload').payload || ':' || fin_gsq_test_test_get_factor_proportion_of_risk('local_payload').source_function, 'local_payload:test_get_factor_proportion_of_risk');
SELECT assert_eq('gs quant canonical 0598 gs_quant/test/markets/test_report.py test_get_factor_exposure', fin_gsq_test_test_get_factor_exposure('local_payload').payload || ':' || fin_gsq_test_test_get_factor_exposure('local_payload').source_function, 'local_payload:test_get_factor_exposure');
SELECT assert_eq('gs quant canonical 0599 gs_quant/test/markets/test_report.py test_get_annual_risk', fin_gsq_test_test_get_annual_risk('local_payload').payload || ':' || fin_gsq_test_test_get_annual_risk('local_payload').source_function, 'local_payload:test_get_annual_risk');
SELECT assert_eq('gs quant canonical 0600 gs_quant/test/markets/test_report.py test_get_daily_risk', fin_gsq_test_test_get_daily_risk('local_payload').payload || ':' || fin_gsq_test_test_get_daily_risk('local_payload').source_function, 'local_payload:test_get_daily_risk');
SELECT assert_eq('gs quant canonical 0601 gs_quant/test/markets/test_report.py test_get_measures', fin_gsq_test_test_get_measures('local_payload').payload || ':' || fin_gsq_test_test_get_measures('local_payload').source_function, 'local_payload:test_get_measures');
SELECT assert_eq('gs quant canonical 0602 gs_quant/test/markets/test_report.py test_flatten_results_into_df', fin_gsq_test_test_flatten_results_into_df('local_payload').payload || ':' || fin_gsq_test_test_flatten_results_into_df('local_payload').source_function, 'local_payload:test_flatten_results_into_df');
SELECT assert_eq('gs quant canonical 0603 gs_quant/test/markets/test_report.py test_get_thematic_breakdown', fin_gsq_test_test_get_thematic_breakdown('local_payload').payload || ':' || fin_gsq_test_test_get_thematic_breakdown('local_payload').source_function, 'local_payload:test_get_thematic_breakdown');
SELECT assert_eq('gs quant canonical 0604 gs_quant/test/markets/test_scenarios.py mock_factor_scenario', fin_gsq_test_mock_factor_scenario('local_payload').payload || ':' || fin_gsq_test_mock_factor_scenario('local_payload').source_function, 'local_payload:mock_factor_scenario');
SELECT assert_eq('gs quant canonical 0605 gs_quant/test/markets/test_scenarios.py test_create_factor_scenario', fin_gsq_test_test_create_factor_scenario('local_payload').payload || ':' || fin_gsq_test_test_create_factor_scenario('local_payload').source_function, 'local_payload:test_create_factor_scenario');
SELECT assert_eq('gs quant canonical 0606 gs_quant/test/markets/test_scenarios.py test_update_scenario_entitlements', fin_gsq_test_test_update_scenario_entitlements('local_payload').payload || ':' || fin_gsq_test_test_update_scenario_entitlements('local_payload').source_function, 'local_payload:test_update_scenario_entitlements');
SELECT assert_eq('gs quant canonical 0607 gs_quant/test/markets/test_securities.py test_get_asset', fin_gsq_test_test_get_asset_test_markets_test_securities('local_payload').payload || ':' || fin_gsq_test_test_get_asset_test_markets_test_securities('local_payload').source_function, 'local_payload:test_get_asset');
SELECT assert_eq('gs quant canonical 0608 gs_quant/test/markets/test_securities.py test_asset_identifiers', fin_gsq_test_test_asset_identifiers('local_payload').payload || ':' || fin_gsq_test_test_asset_identifiers('local_payload').source_function, 'local_payload:test_asset_identifiers');
SELECT assert_eq('gs quant canonical 0609 gs_quant/test/markets/test_securities.py test_asset_types', fin_gsq_test_test_asset_types('local_payload').payload || ':' || fin_gsq_test_test_asset_types('local_payload').source_function, 'local_payload:test_asset_types');
SELECT assert_eq('gs quant canonical 0610 gs_quant/test/markets/test_securities.py test_get_security', fin_gsq_test_test_get_security('local_payload').payload || ':' || fin_gsq_test_test_get_security('local_payload').source_function, 'local_payload:test_get_security');
SELECT assert_eq('gs quant canonical 0611 gs_quant/test/markets/test_securities.py test_get_security_fields', fin_gsq_test_test_get_security_fields('local_payload').payload || ':' || fin_gsq_test_test_get_security_fields('local_payload').source_function, 'local_payload:test_get_security_fields');
SELECT assert_eq('gs quant canonical 0612 gs_quant/test/markets/test_securities.py test_get_identifiers', fin_gsq_test_test_get_identifiers('local_payload').payload || ':' || fin_gsq_test_test_get_identifiers('local_payload').source_function, 'local_payload:test_get_identifiers');
SELECT assert_eq('gs quant canonical 0613 gs_quant/test/markets/test_securities.py test_get_all_identifiers', fin_gsq_test_test_get_all_identifiers('local_payload').payload || ':' || fin_gsq_test_test_get_all_identifiers('local_payload').source_function, 'local_payload:test_get_all_identifiers');
SELECT assert_eq('gs quant canonical 0614 gs_quant/test/markets/test_securities.py test_get_all_identifiers_with_assetTypes_not_none', fin_gsq_test_test_get_all_identifiers_with_assettypes_not_none('local_payload').payload || ':' || fin_gsq_test_test_get_all_identifiers_with_assettypes_not_none('local_payload').source_function, 'local_payload:test_get_all_identifiers_with_assetTypes_not_none');
SELECT assert_eq('gs quant canonical 0615 gs_quant/test/markets/test_securities.py test_offset_key', fin_gsq_test_test_offset_key('local_payload').payload || ':' || fin_gsq_test_test_offset_key('local_payload').source_function, 'local_payload:test_offset_key');
SELECT assert_eq('gs quant canonical 0616 gs_quant/test/markets/test_securities.py test_map_identifiers', fin_gsq_test_test_map_identifiers('local_payload').payload || ':' || fin_gsq_test_test_map_identifiers('local_payload').source_function, 'local_payload:test_map_identifiers');
SELECT assert_eq('gs quant canonical 0617 gs_quant/test/markets/test_securities.py test_map_identifiers_change', fin_gsq_test_test_map_identifiers_change('local_payload').payload || ':' || fin_gsq_test_test_map_identifiers_change('local_payload').source_function, 'local_payload:test_map_identifiers_change');
SELECT assert_eq('gs quant canonical 0618 gs_quant/test/markets/test_securities.py test_map_identifiers_empty', fin_gsq_test_test_map_identifiers_empty('local_payload').payload || ':' || fin_gsq_test_test_map_identifiers_empty('local_payload').source_function, 'local_payload:test_map_identifiers_empty');
SELECT assert_eq('gs quant canonical 0619 gs_quant/test/markets/test_securities.py test_map_identifiers_eq_index', fin_gsq_test_test_map_identifiers_eq_index('local_payload').payload || ':' || fin_gsq_test_test_map_identifiers_eq_index('local_payload').source_function, 'local_payload:test_map_identifiers_eq_index');
SELECT assert_eq('gs quant canonical 0620 gs_quant/test/markets/test_securities.py test_secmaster_map_identifiers_with_passed_input_types', fin_gsq_test_test_secmaster_map_identifiers_with_passed_input_types('local_payload').payload || ':' || fin_gsq_test_test_secmaster_map_identifiers_with_passed_input_types('local_payload').source_function, 'local_payload:test_secmaster_map_identifiers_with_passed_input_types');
SELECT assert_eq('gs quant canonical 0621 gs_quant/test/markets/test_securities.py test_secmaster_map_identifiers_return_array_results', fin_gsq_test_test_secmaster_map_identifiers_return_array_results('local_payload').payload || ':' || fin_gsq_test_test_secmaster_map_identifiers_return_array_results('local_payload').source_function, 'local_payload:test_secmaster_map_identifiers_return_array_results');
SELECT assert_eq('gs quant canonical 0622 gs_quant/test/markets/test_securities.py test_secmaster_get_asset_no_asset_id_response_should_fail', fin_gsq_test_test_secmaster_get_asset_no_asset_id_response_should_fail('local_payload').payload || ':' || fin_gsq_test_test_secmaster_get_asset_no_asset_id_response_should_fail('local_payload').source_function, 'local_payload:test_secmaster_get_asset_no_asset_id_response_should_fail');
SELECT assert_eq('gs quant canonical 0623 gs_quant/test/markets/test_securities.py test_secmaster_get_asset_returning_secmasterassets', fin_gsq_test_test_secmaster_get_asset_returning_secmasterassets('local_payload').payload || ':' || fin_gsq_test_test_secmaster_get_asset_returning_secmasterassets('local_payload').source_function, 'local_payload:test_secmaster_get_asset_returning_secmasterassets');
SELECT assert_eq('gs quant canonical 0624 gs_quant/test/markets/test_securities.py test_get_asset_get_data_series_with_range_over_many_asset_id_should_throw_mqerror', fin_gsq_test_test_get_asset_get_data_series_with_range_over_many_asset_id_43ceec32f7('local_payload').payload || ':' || fin_gsq_test_test_get_asset_get_data_series_with_range_over_many_asset_id_43ceec32f7('local_payload').source_function, 'local_payload:test_get_asset_get_data_series_with_range_over_many_asset_id_should_throw_mqerror');
SELECT assert_eq('gs quant canonical 0625 gs_quant/test/markets/test_securities.py test_map_identifiers_asset_service', fin_gsq_test_test_map_identifiers_asset_service('local_payload').payload || ':' || fin_gsq_test_test_map_identifiers_asset_service('local_payload').source_function, 'local_payload:test_map_identifiers_asset_service');
SELECT assert_eq('gs quant canonical 0626 gs_quant/test/markets/test_securities.py test_map_identifiers_asset_service_exceptions', fin_gsq_test_test_map_identifiers_asset_service_exceptions('local_payload').payload || ':' || fin_gsq_test_test_map_identifiers_asset_service_exceptions('local_payload').source_function, 'local_payload:test_map_identifiers_asset_service_exceptions');
SELECT assert_eq('gs quant canonical 0627 gs_quant/test/mock_data_test_utils.py did_anything_fail', fin_gsq_test_did_anything_fail('local_payload').payload || ':' || fin_gsq_test_did_anything_fail('local_payload').source_function, 'local_payload:did_anything_fail');
SELECT assert_eq('gs quant canonical 0628 gs_quant/test/mock_data_test_utils.py did_anything_run', fin_gsq_test_did_anything_run('local_payload').payload || ':' || fin_gsq_test_did_anything_run('local_payload').source_function, 'local_payload:did_anything_run');
SELECT assert_eq('gs quant canonical 0629 gs_quant/test/mock_data_test_utils.py log_mock_data_event', fin_gsq_test_log_mock_data_event('local_payload').payload || ':' || fin_gsq_test_log_mock_data_event('local_payload').source_function, 'local_payload:log_mock_data_event');
SELECT assert_eq('gs quant canonical 0630 gs_quant/test/mock_data_test_utils.py pytest_addoption', fin_gsq_test_pytest_addoption('local_payload').payload || ':' || fin_gsq_test_pytest_addoption('local_payload').source_function, 'local_payload:pytest_addoption');
SELECT assert_eq('gs quant canonical 0631 gs_quant/test/mock_data_test_utils.py pytest_configure', fin_gsq_test_pytest_configure('local_payload').payload || ':' || fin_gsq_test_pytest_configure('local_payload').source_function, 'local_payload:pytest_configure');
SELECT assert_eq('gs quant canonical 0632 gs_quant/test/mock_data_test_utils.py pytest_runtest_makereport', fin_gsq_test_pytest_runtest_makereport('local_payload').payload || ':' || fin_gsq_test_pytest_runtest_makereport('local_payload').source_function, 'local_payload:pytest_runtest_makereport');
SELECT assert_eq('gs quant canonical 0633 gs_quant/test/mock_data_test_utils.py pytest_terminal_summary', fin_gsq_test_pytest_terminal_summary('local_payload').payload || ':' || fin_gsq_test_pytest_terminal_summary('local_payload').source_function, 'local_payload:pytest_terminal_summary');
SELECT assert_eq('gs quant canonical 0634 gs_quant/test/mock_data_test_utils.py pytest_collection_modifyitems', fin_gsq_test_pytest_collection_modifyitems('local_payload').payload || ':' || fin_gsq_test_pytest_collection_modifyitems('local_payload').source_function, 'local_payload:pytest_collection_modifyitems');
SELECT assert_eq('gs quant canonical 0635 gs_quant/test/models/test_epidemiology.py test_SIR', fin_gsq_test_test_sir('local_payload').payload || ':' || fin_gsq_test_test_sir('local_payload').source_function, 'local_payload:test_SIR');
SELECT assert_eq('gs quant canonical 0636 gs_quant/test/models/test_epidemiology.py test_SEIR', fin_gsq_test_test_seir('local_payload').payload || ':' || fin_gsq_test_test_seir('local_payload').source_function, 'local_payload:test_SEIR');
SELECT assert_eq('gs quant canonical 0637 gs_quant/test/models/test_risk_model.py mock_risk_model', fin_gsq_test_mock_risk_model('local_payload').payload || ':' || fin_gsq_test_mock_risk_model('local_payload').source_function, 'local_payload:mock_risk_model');
SELECT assert_eq('gs quant canonical 0638 gs_quant/test/models/test_risk_model.py mock_macro_risk_model', fin_gsq_test_mock_macro_risk_model('local_payload').payload || ':' || fin_gsq_test_mock_macro_risk_model('local_payload').source_function, 'local_payload:mock_macro_risk_model');
SELECT assert_eq('gs quant canonical 0639 gs_quant/test/models/test_risk_model.py test_create_risk_model', fin_gsq_test_test_create_risk_model_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_create_risk_model_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_create_risk_model');
SELECT assert_eq('gs quant canonical 0640 gs_quant/test/models/test_risk_model.py test_update_risk_model_entitlements', fin_gsq_test_test_update_risk_model_entitlements('local_payload').payload || ':' || fin_gsq_test_test_update_risk_model_entitlements('local_payload').source_function, 'local_payload:test_update_risk_model_entitlements');
SELECT assert_eq('gs quant canonical 0641 gs_quant/test/models/test_risk_model.py test_update_risk_model', fin_gsq_test_test_update_risk_model_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_update_risk_model_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_update_risk_model');
SELECT assert_eq('gs quant canonical 0642 gs_quant/test/models/test_risk_model.py test_get_r_squared', fin_gsq_test_test_get_r_squared_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_r_squared_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_get_r_squared');
SELECT assert_eq('gs quant canonical 0643 gs_quant/test/models/test_risk_model.py test_get_fair_value_gap_standard_deviation', fin_gsq_test_test_get_fair_value_gap_standard_deviation('local_payload').payload || ':' || fin_gsq_test_test_get_fair_value_gap_standard_deviation('local_payload').source_function, 'local_payload:test_get_fair_value_gap_standard_deviation');
SELECT assert_eq('gs quant canonical 0644 gs_quant/test/models/test_risk_model.py test_get_fair_value_gap_percent', fin_gsq_test_test_get_fair_value_gap_percent('local_payload').payload || ':' || fin_gsq_test_test_get_fair_value_gap_percent('local_payload').source_function, 'local_payload:test_get_fair_value_gap_percent');
SELECT assert_eq('gs quant canonical 0645 gs_quant/test/models/test_risk_model.py test_get_statistical_factor_data', fin_gsq_test_test_get_statistical_factor_data('local_payload').payload || ':' || fin_gsq_test_test_get_statistical_factor_data('local_payload').source_function, 'local_payload:test_get_statistical_factor_data');
SELECT assert_eq('gs quant canonical 0646 gs_quant/test/models/test_risk_model.py test_get_factor_z_score', fin_gsq_test_test_get_factor_z_score_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_factor_z_score_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_get_factor_z_score');
SELECT assert_eq('gs quant canonical 0647 gs_quant/test/models/test_risk_model.py test_get_predicted_beta', fin_gsq_test_test_get_predicted_beta_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_predicted_beta_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_get_predicted_beta');
SELECT assert_eq('gs quant canonical 0648 gs_quant/test/models/test_risk_model.py test_get_global_predicted_beta', fin_gsq_test_test_get_global_predicted_beta_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_global_predicted_beta_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_get_global_predicted_beta');
SELECT assert_eq('gs quant canonical 0649 gs_quant/test/models/test_risk_model.py test_get_estimation_universe_weights', fin_gsq_test_test_get_estimation_universe_weights('local_payload').payload || ':' || fin_gsq_test_test_get_estimation_universe_weights('local_payload').source_function, 'local_payload:test_get_estimation_universe_weights');
SELECT assert_eq('gs quant canonical 0650 gs_quant/test/models/test_risk_model.py test_get_daily_return', fin_gsq_test_test_get_daily_return_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_daily_return_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_get_daily_return');
SELECT assert_eq('gs quant canonical 0651 gs_quant/test/models/test_risk_model.py test_get_specific_return', fin_gsq_test_test_get_specific_return_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_get_specific_return_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_get_specific_return');
SELECT assert_eq('gs quant canonical 0652 gs_quant/test/models/test_risk_model.py test_upload_risk_model_data', fin_gsq_test_test_upload_risk_model_data_test_models_test_risk_model('local_payload').payload || ':' || fin_gsq_test_test_upload_risk_model_data_test_models_test_risk_model('local_payload').source_function, 'local_payload:test_upload_risk_model_data');
SELECT assert_eq('gs quant canonical 0653 gs_quant/test/models/test_risk_model.py test_get_bid_ask_spread', fin_gsq_test_test_get_bid_ask_spread('local_payload').payload || ':' || fin_gsq_test_test_get_bid_ask_spread('local_payload').source_function, 'local_payload:test_get_bid_ask_spread');
SELECT assert_eq('gs quant canonical 0654 gs_quant/test/models/test_risk_model.py test_get_trading_volume', fin_gsq_test_test_get_trading_volume('local_payload').payload || ':' || fin_gsq_test_test_get_trading_volume('local_payload').source_function, 'local_payload:test_get_trading_volume');
SELECT assert_eq('gs quant canonical 0655 gs_quant/test/models/test_risk_model.py test_get_traded_value', fin_gsq_test_test_get_traded_value('local_payload').payload || ':' || fin_gsq_test_test_get_traded_value('local_payload').source_function, 'local_payload:test_get_traded_value');
SELECT assert_eq('gs quant canonical 0656 gs_quant/test/models/test_risk_model.py test_get_composite_volume', fin_gsq_test_test_get_composite_volume('local_payload').payload || ':' || fin_gsq_test_test_get_composite_volume('local_payload').source_function, 'local_payload:test_get_composite_volume');
SELECT assert_eq('gs quant canonical 0657 gs_quant/test/models/test_risk_model.py test_get_composite_value', fin_gsq_test_test_get_composite_value('local_payload').payload || ':' || fin_gsq_test_test_get_composite_value('local_payload').source_function, 'local_payload:test_get_composite_value');
SELECT assert_eq('gs quant canonical 0658 gs_quant/test/models/test_risk_model.py test_get_issuer_market_cap', fin_gsq_test_test_get_issuer_market_cap('local_payload').payload || ':' || fin_gsq_test_test_get_issuer_market_cap('local_payload').source_function, 'local_payload:test_get_issuer_market_cap');
SELECT assert_eq('gs quant canonical 0659 gs_quant/test/models/test_risk_model.py test_get_asset_price', fin_gsq_test_test_get_asset_price('local_payload').payload || ':' || fin_gsq_test_test_get_asset_price('local_payload').source_function, 'local_payload:test_get_asset_price');
SELECT assert_eq('gs quant canonical 0660 gs_quant/test/models/test_risk_model.py test_get_asset_capitalization', fin_gsq_test_test_get_asset_capitalization('local_payload').payload || ':' || fin_gsq_test_test_get_asset_capitalization('local_payload').source_function, 'local_payload:test_get_asset_capitalization');
SELECT assert_eq('gs quant canonical 0661 gs_quant/test/models/test_risk_model.py test_get_currency', fin_gsq_test_test_get_currency('local_payload').payload || ':' || fin_gsq_test_test_get_currency('local_payload').source_function, 'local_payload:test_get_currency');
SELECT assert_eq('gs quant canonical 0662 gs_quant/test/models/test_risk_model.py test_get_unadjusted_specific_risk', fin_gsq_test_test_get_unadjusted_specific_risk('local_payload').payload || ':' || fin_gsq_test_test_get_unadjusted_specific_risk('local_payload').source_function, 'local_payload:test_get_unadjusted_specific_risk');
SELECT assert_eq('gs quant canonical 0663 gs_quant/test/models/test_risk_model.py test_get_dividend_yield', fin_gsq_test_test_get_dividend_yield('local_payload').payload || ':' || fin_gsq_test_test_get_dividend_yield('local_payload').source_function, 'local_payload:test_get_dividend_yield');
SELECT assert_eq('gs quant canonical 0664 gs_quant/test/models/test_risk_model.py test_get_model_price', fin_gsq_test_test_get_model_price('local_payload').payload || ':' || fin_gsq_test_test_get_model_price('local_payload').source_function, 'local_payload:test_get_model_price');
SELECT assert_eq('gs quant canonical 0665 gs_quant/test/models/test_risk_model.py test_get_covariance_matrix', fin_gsq_test_test_get_covariance_matrix('local_payload').payload || ':' || fin_gsq_test_test_get_covariance_matrix('local_payload').source_function, 'local_payload:test_get_covariance_matrix');
SELECT assert_eq('gs quant canonical 0666 gs_quant/test/models/test_risk_model.py test_get_unadjusted_covariance_matrix', fin_gsq_test_test_get_unadjusted_covariance_matrix('local_payload').payload || ':' || fin_gsq_test_test_get_unadjusted_covariance_matrix('local_payload').source_function, 'local_payload:test_get_unadjusted_covariance_matrix');
SELECT assert_eq('gs quant canonical 0667 gs_quant/test/models/test_risk_model.py test_get_pre_vra_covariance_matrix', fin_gsq_test_test_get_pre_vra_covariance_matrix('local_payload').payload || ':' || fin_gsq_test_test_get_pre_vra_covariance_matrix('local_payload').source_function, 'local_payload:test_get_pre_vra_covariance_matrix');
SELECT assert_eq('gs quant canonical 0668 gs_quant/test/models/test_risk_model.py test_get_risk_free_rate', fin_gsq_test_test_get_risk_free_rate('local_payload').payload || ':' || fin_gsq_test_test_get_risk_free_rate('local_payload').source_function, 'local_payload:test_get_risk_free_rate');
SELECT assert_eq('gs quant canonical 0669 gs_quant/test/models/test_risk_model.py test_get_currency_exchange_rate', fin_gsq_test_test_get_currency_exchange_rate('local_payload').payload || ':' || fin_gsq_test_test_get_currency_exchange_rate('local_payload').source_function, 'local_payload:test_get_currency_exchange_rate');
SELECT assert_eq('gs quant canonical 0670 gs_quant/test/models/test_risk_model_utils.py test__upload_factor_data_if_present', fin_gsq_test_test_upload_factor_data_if_present('local_payload').payload || ':' || fin_gsq_test_test_upload_factor_data_if_present('local_payload').source_function, 'local_payload:test__upload_factor_data_if_present');
SELECT assert_eq('gs quant canonical 0671 gs_quant/test/risk/test_measures.py test_currency_params', fin_gsq_test_test_currency_params('local_payload').payload || ':' || fin_gsq_test_test_currency_params('local_payload').source_function, 'local_payload:test_currency_params');
SELECT assert_eq('gs quant canonical 0672 gs_quant/test/risk/test_measures.py test_finite_difference_params', fin_gsq_test_test_finite_difference_params('local_payload').payload || ':' || fin_gsq_test_test_finite_difference_params('local_payload').source_function, 'local_payload:test_finite_difference_params');
SELECT assert_eq('gs quant canonical 0673 gs_quant/test/risk/test_measures.py test_risk_measure_setters', fin_gsq_test_test_risk_measure_setters('local_payload').payload || ':' || fin_gsq_test_test_risk_measure_setters('local_payload').source_function, 'local_payload:test_risk_measure_setters');
SELECT assert_eq('gs quant canonical 0674 gs_quant/test/risk/test_results.py get_attributes', fin_gsq_test_get_attributes('local_payload').payload || ':' || fin_gsq_test_get_attributes('local_payload').source_function, 'local_payload:get_attributes');
SELECT assert_eq('gs quant canonical 0675 gs_quant/test/risk/test_results.py default_pivot_table_test', fin_gsq_test_default_pivot_table_test('local_payload').payload || ':' || fin_gsq_test_default_pivot_table_test('local_payload').source_function, 'local_payload:default_pivot_table_test');
SELECT assert_eq('gs quant canonical 0676 gs_quant/test/risk/test_results.py price_values_test', fin_gsq_test_price_values_test('local_payload').payload || ':' || fin_gsq_test_price_values_test('local_payload').source_function, 'local_payload:price_values_test');
SELECT assert_eq('gs quant canonical 0677 gs_quant/test/risk/test_results.py test_multi_scenario', fin_gsq_test_test_multi_scenario('local_payload').payload || ':' || fin_gsq_test_test_multi_scenario('local_payload').source_function, 'local_payload:test_multi_scenario');
SELECT assert_eq('gs quant canonical 0678 gs_quant/test/risk/test_results.py test_historical_multi_scenario', fin_gsq_test_test_historical_multi_scenario('local_payload').payload || ':' || fin_gsq_test_test_historical_multi_scenario('local_payload').source_function, 'local_payload:test_historical_multi_scenario');
SELECT assert_eq('gs quant canonical 0679 gs_quant/test/risk/test_results.py test_series_with_info_arithmetics', fin_gsq_test_test_series_with_info_arithmetics('local_payload').payload || ':' || fin_gsq_test_test_series_with_info_arithmetics('local_payload').source_function, 'local_payload:test_series_with_info_arithmetics');
SELECT assert_eq('gs quant canonical 0680 gs_quant/test/risk/test_results.py test_composite_multi_scenario', fin_gsq_test_test_composite_multi_scenario('local_payload').payload || ':' || fin_gsq_test_test_composite_multi_scenario('local_payload').source_function, 'local_payload:test_composite_multi_scenario');
SELECT assert_eq('gs quant canonical 0681 gs_quant/test/risk/test_results.py test_one_portfolio', fin_gsq_test_test_one_portfolio('local_payload').payload || ':' || fin_gsq_test_test_one_portfolio('local_payload').source_function, 'local_payload:test_one_portfolio');
SELECT assert_eq('gs quant canonical 0682 gs_quant/test/risk/test_results.py test_dated_risk_values', fin_gsq_test_test_dated_risk_values('local_payload').payload || ':' || fin_gsq_test_test_dated_risk_values('local_payload').source_function, 'local_payload:test_dated_risk_values');
SELECT assert_eq('gs quant canonical 0683 gs_quant/test/risk/test_results.py test_bucketed_risks', fin_gsq_test_test_bucketed_risks('local_payload').payload || ':' || fin_gsq_test_test_bucketed_risks('local_payload').source_function, 'local_payload:test_bucketed_risks');
SELECT assert_eq('gs quant canonical 0684 gs_quant/test/risk/test_results.py test_cashflows_risk', fin_gsq_test_test_cashflows_risk('local_payload').payload || ':' || fin_gsq_test_test_cashflows_risk('local_payload').source_function, 'local_payload:test_cashflows_risk');
SELECT assert_eq('gs quant canonical 0685 gs_quant/test/risk/test_results.py test_nested_portfolio', fin_gsq_test_test_nested_portfolio('local_payload').payload || ':' || fin_gsq_test_test_nested_portfolio('local_payload').source_function, 'local_payload:test_nested_portfolio');
SELECT assert_eq('gs quant canonical 0686 gs_quant/test/risk/test_results.py test_diff_types_risk_measures', fin_gsq_test_test_diff_types_risk_measures('local_payload').payload || ':' || fin_gsq_test_test_diff_types_risk_measures('local_payload').source_function, 'local_payload:test_diff_types_risk_measures');
SELECT assert_eq('gs quant canonical 0687 gs_quant/test/risk/test_results.py test_empty_calc_request', fin_gsq_test_test_empty_calc_request('local_payload').payload || ':' || fin_gsq_test_test_empty_calc_request('local_payload').source_function, 'local_payload:test_empty_calc_request');
SELECT assert_eq('gs quant canonical 0688 gs_quant/test/risk/test_results.py test_adding_risk_results', fin_gsq_test_test_adding_risk_results('local_payload').payload || ':' || fin_gsq_test_test_adding_risk_results('local_payload').source_function, 'local_payload:test_adding_risk_results');
SELECT assert_eq('gs quant canonical 0689 gs_quant/test/risk/test_results.py test_unsupported_error_datums', fin_gsq_test_test_unsupported_error_datums('local_payload').payload || ':' || fin_gsq_test_test_unsupported_error_datums('local_payload').source_function, 'local_payload:test_unsupported_error_datums');
SELECT assert_eq('gs quant canonical 0690 gs_quant/test/risk/test_results.py test_resolution_of_error_trade', fin_gsq_test_test_resolution_of_error_trade('local_payload').payload || ':' || fin_gsq_test_test_resolution_of_error_trade('local_payload').source_function, 'local_payload:test_resolution_of_error_trade');
SELECT assert_eq('gs quant canonical 0691 gs_quant/test/risk/test_results.py test_resolve_to_frame', fin_gsq_test_test_resolve_to_frame('local_payload').payload || ':' || fin_gsq_test_test_resolve_to_frame('local_payload').source_function, 'local_payload:test_resolve_to_frame');
SELECT assert_eq('gs quant canonical 0692 gs_quant/test/risk/test_results.py test_unnamed_portfolio', fin_gsq_test_test_unnamed_portfolio('local_payload').payload || ':' || fin_gsq_test_test_unnamed_portfolio('local_payload').source_function, 'local_payload:test_unnamed_portfolio');
SELECT assert_eq('gs quant canonical 0693 gs_quant/test/risk/test_results.py test_leg_valuations', fin_gsq_test_test_leg_valuations('local_payload').payload || ':' || fin_gsq_test_test_leg_valuations('local_payload').source_function, 'local_payload:test_leg_valuations');
SELECT assert_eq('gs quant canonical 0694 gs_quant/test/risk/test_results.py test_aggregation_with_heterogeous_types', fin_gsq_test_test_aggregation_with_heterogeous_types('local_payload').payload || ':' || fin_gsq_test_test_aggregation_with_heterogeous_types('local_payload').source_function, 'local_payload:test_aggregation_with_heterogeous_types');
SELECT assert_eq('gs quant canonical 0695 gs_quant/test/risk/test_results.py test_aggregation_with_empty_measures', fin_gsq_test_test_aggregation_with_empty_measures('local_payload').payload || ':' || fin_gsq_test_test_aggregation_with_empty_measures('local_payload').source_function, 'local_payload:test_aggregation_with_empty_measures');
SELECT assert_eq('gs quant canonical 0696 gs_quant/test/risk/test_results.py test_filter_risk', fin_gsq_test_test_filter_risk('local_payload').payload || ':' || fin_gsq_test_test_filter_risk('local_payload').source_function, 'local_payload:test_filter_risk');
SELECT assert_eq('gs quant canonical 0697 gs_quant/test/risk/test_results.py test_transformation', fin_gsq_test_test_transformation('local_payload').payload || ':' || fin_gsq_test_test_transformation('local_payload').source_function, 'local_payload:test_transformation');
SELECT assert_eq('gs quant canonical 0698 gs_quant/test/risk/test_results.py test_aggregation_with_identical_trades', fin_gsq_test_test_aggregation_with_identical_trades('local_payload').payload || ':' || fin_gsq_test_test_aggregation_with_identical_trades('local_payload').source_function, 'local_payload:test_aggregation_with_identical_trades');
SELECT assert_eq('gs quant canonical 0699 gs_quant/test/risk/test_results.py test_scalar_with_info_on_instrument', fin_gsq_test_test_scalar_with_info_on_instrument('local_payload').payload || ':' || fin_gsq_test_test_scalar_with_info_on_instrument('local_payload').source_function, 'local_payload:test_scalar_with_info_on_instrument');
SELECT assert_eq('gs quant canonical 0700 gs_quant/test/risk/test_results.py test_display_unit', fin_gsq_test_test_display_unit('local_payload').payload || ':' || fin_gsq_test_test_display_unit('local_payload').source_function, 'local_payload:test_display_unit');
SELECT assert_eq('gs quant canonical 0701 gs_quant/test/test_base.py test_handle_camel_case_args', fin_gsq_test_test_handle_camel_case_args('local_payload').payload || ':' || fin_gsq_test_test_handle_camel_case_args('local_payload').source_function, 'local_payload:test_handle_camel_case_args');
SELECT assert_eq('gs quant canonical 0702 gs_quant/test/test_base.py test_base_getter', fin_gsq_test_test_base_getter('local_payload').payload || ':' || fin_gsq_test_test_base_getter('local_payload').source_function, 'local_payload:test_base_getter');
SELECT assert_eq('gs quant canonical 0703 gs_quant/test/test_base.py test_base_setter', fin_gsq_test_test_base_setter('local_payload').payload || ':' || fin_gsq_test_test_base_setter('local_payload').source_function, 'local_payload:test_base_setter');
SELECT assert_eq('gs quant canonical 0704 gs_quant/test/test_base.py test_setter_coercion', fin_gsq_test_test_setter_coercion('local_payload').payload || ':' || fin_gsq_test_test_setter_coercion('local_payload').source_function, 'local_payload:test_setter_coercion');
SELECT assert_eq('gs quant canonical 0705 gs_quant/test/test_base.py test_security_from_dict', fin_gsq_test_test_security_from_dict('local_payload').payload || ':' || fin_gsq_test_test_security_from_dict('local_payload').source_function, 'local_payload:test_security_from_dict');
SELECT assert_eq('gs quant canonical 0706 gs_quant/test/test_session.py test_session_pickle', fin_gsq_test_test_session_pickle('local_payload').payload || ':' || fin_gsq_test_test_session_pickle('local_payload').source_function, 'local_payload:test_session_pickle');
SELECT assert_eq('gs quant canonical 0707 gs_quant/test/timeseries/multi_measure/test_commod.py test_forward_price', fin_gsq_test_test_forward_price('local_payload').payload || ':' || fin_gsq_test_test_forward_price('local_payload').source_function, 'local_payload:test_forward_price');
SELECT assert_eq('gs quant canonical 0708 gs_quant/test/timeseries/multi_measure/test_measure_registry.py test_registry', fin_gsq_test_test_registry('local_payload').payload || ':' || fin_gsq_test_test_registry('local_payload').source_function, 'local_payload:test_registry');
SELECT assert_eq('gs quant canonical 0709 gs_quant/test/timeseries/multi_measure/test_measure_registry.py test_no_duplicate_plot_measure_function_names', fin_gsq_test_test_no_duplicate_plot_measure_function_names('local_payload').payload || ':' || fin_gsq_test_test_no_duplicate_plot_measure_function_names('local_payload').source_function, 'local_payload:test_no_duplicate_plot_measure_function_names');
SELECT assert_eq('gs quant canonical 0710 gs_quant/test/timeseries/test_algebra.py test_add', fin_gsq_test_test_add('local_payload').payload || ':' || fin_gsq_test_test_add('local_payload').source_function, 'local_payload:test_add');
SELECT assert_eq('gs quant canonical 0711 gs_quant/test/timeseries/test_algebra.py test_subtract', fin_gsq_test_test_subtract('local_payload').payload || ':' || fin_gsq_test_test_subtract('local_payload').source_function, 'local_payload:test_subtract');
SELECT assert_eq('gs quant canonical 0712 gs_quant/test/timeseries/test_algebra.py test_multiply', fin_gsq_test_test_multiply('local_payload').payload || ':' || fin_gsq_test_test_multiply('local_payload').source_function, 'local_payload:test_multiply');
SELECT assert_eq('gs quant canonical 0713 gs_quant/test/timeseries/test_algebra.py test_divide', fin_gsq_test_test_divide('local_payload').payload || ':' || fin_gsq_test_test_divide('local_payload').source_function, 'local_payload:test_divide');
SELECT assert_eq('gs quant canonical 0714 gs_quant/test/timeseries/test_algebra.py test_floordiv', fin_gsq_test_test_floordiv('local_payload').payload || ':' || fin_gsq_test_test_floordiv('local_payload').source_function, 'local_payload:test_floordiv');
SELECT assert_eq('gs quant canonical 0715 gs_quant/test/timeseries/test_algebra.py test_exp', fin_gsq_test_test_exp('local_payload').payload || ':' || fin_gsq_test_test_exp('local_payload').source_function, 'local_payload:test_exp');
SELECT assert_eq('gs quant canonical 0716 gs_quant/test/timeseries/test_algebra.py test_log', fin_gsq_test_test_log('local_payload').payload || ':' || fin_gsq_test_test_log('local_payload').source_function, 'local_payload:test_log');
SELECT assert_eq('gs quant canonical 0717 gs_quant/test/timeseries/test_algebra.py test_power', fin_gsq_test_test_power('local_payload').payload || ':' || fin_gsq_test_test_power('local_payload').source_function, 'local_payload:test_power');
SELECT assert_eq('gs quant canonical 0718 gs_quant/test/timeseries/test_algebra.py test_sqrt', fin_gsq_test_test_sqrt('local_payload').payload || ':' || fin_gsq_test_test_sqrt('local_payload').source_function, 'local_payload:test_sqrt');
SELECT assert_eq('gs quant canonical 0719 gs_quant/test/timeseries/test_algebra.py test_abs', fin_gsq_test_test_abs('local_payload').payload || ':' || fin_gsq_test_test_abs('local_payload').source_function, 'local_payload:test_abs');
SELECT assert_eq('gs quant canonical 0720 gs_quant/test/timeseries/test_algebra.py test_floor', fin_gsq_test_test_floor('local_payload').payload || ':' || fin_gsq_test_test_floor('local_payload').source_function, 'local_payload:test_floor');
SELECT assert_eq('gs quant canonical 0721 gs_quant/test/timeseries/test_algebra.py test_ceil', fin_gsq_test_test_ceil('local_payload').payload || ':' || fin_gsq_test_test_ceil('local_payload').source_function, 'local_payload:test_ceil');
SELECT assert_eq('gs quant canonical 0722 gs_quant/test/timeseries/test_algebra.py test_filter', fin_gsq_test_test_filter('local_payload').payload || ':' || fin_gsq_test_test_filter('local_payload').source_function, 'local_payload:test_filter');
SELECT assert_eq('gs quant canonical 0723 gs_quant/test/timeseries/test_algebra.py test_filter_dates', fin_gsq_test_test_filter_dates('local_payload').payload || ':' || fin_gsq_test_test_filter_dates('local_payload').source_function, 'local_payload:test_filter_dates');
SELECT assert_eq('gs quant canonical 0724 gs_quant/test/timeseries/test_algebra.py test_smooth_spikes', fin_gsq_test_test_smooth_spikes('local_payload').payload || ':' || fin_gsq_test_test_smooth_spikes('local_payload').source_function, 'local_payload:test_smooth_spikes');
SELECT assert_eq('gs quant canonical 0725 gs_quant/test/timeseries/test_algebra.py test_repeat', fin_gsq_test_test_repeat('local_payload').payload || ':' || fin_gsq_test_test_repeat('local_payload').source_function, 'local_payload:test_repeat');
SELECT assert_eq('gs quant canonical 0726 gs_quant/test/timeseries/test_algebra.py test_and', fin_gsq_test_test_and('local_payload').payload || ':' || fin_gsq_test_test_and('local_payload').source_function, 'local_payload:test_and');
SELECT assert_eq('gs quant canonical 0727 gs_quant/test/timeseries/test_algebra.py test_or', fin_gsq_test_test_or('local_payload').payload || ':' || fin_gsq_test_test_or('local_payload').source_function, 'local_payload:test_or');
SELECT assert_eq('gs quant canonical 0728 gs_quant/test/timeseries/test_algebra.py test_not', fin_gsq_test_test_not('local_payload').payload || ':' || fin_gsq_test_test_not('local_payload').source_function, 'local_payload:test_not');
SELECT assert_eq('gs quant canonical 0729 gs_quant/test/timeseries/test_algebra.py test_if', fin_gsq_test_test_if('local_payload').payload || ':' || fin_gsq_test_test_if('local_payload').source_function, 'local_payload:test_if');
SELECT assert_eq('gs quant canonical 0730 gs_quant/test/timeseries/test_algebra.py test_weighted_average', fin_gsq_test_test_weighted_average('local_payload').payload || ':' || fin_gsq_test_test_weighted_average('local_payload').source_function, 'local_payload:test_weighted_average');
SELECT assert_eq('gs quant canonical 0731 gs_quant/test/timeseries/test_algebra.py test_geometrically_aggregate', fin_gsq_test_test_geometrically_aggregate('local_payload').payload || ':' || fin_gsq_test_test_geometrically_aggregate('local_payload').source_function, 'local_payload:test_geometrically_aggregate');
SELECT assert_eq('gs quant canonical 0732 gs_quant/test/timeseries/test_analysis.py test_first', fin_gsq_test_test_first('local_payload').payload || ':' || fin_gsq_test_test_first('local_payload').source_function, 'local_payload:test_first');
SELECT assert_eq('gs quant canonical 0733 gs_quant/test/timeseries/test_analysis.py test_last', fin_gsq_test_test_last('local_payload').payload || ':' || fin_gsq_test_test_last('local_payload').source_function, 'local_payload:test_last');
SELECT assert_eq('gs quant canonical 0734 gs_quant/test/timeseries/test_analysis.py test_last_value', fin_gsq_test_test_last_value('local_payload').payload || ':' || fin_gsq_test_test_last_value('local_payload').source_function, 'local_payload:test_last_value');
SELECT assert_eq('gs quant canonical 0735 gs_quant/test/timeseries/test_analysis.py test_count', fin_gsq_test_test_count('local_payload').payload || ':' || fin_gsq_test_test_count('local_payload').source_function, 'local_payload:test_count');
SELECT assert_eq('gs quant canonical 0736 gs_quant/test/timeseries/test_analysis.py test_compare', fin_gsq_test_test_compare('local_payload').payload || ':' || fin_gsq_test_test_compare('local_payload').source_function, 'local_payload:test_compare');
SELECT assert_eq('gs quant canonical 0737 gs_quant/test/timeseries/test_analysis.py test_diff', fin_gsq_test_test_diff('local_payload').payload || ':' || fin_gsq_test_test_diff('local_payload').source_function, 'local_payload:test_diff');
SELECT assert_eq('gs quant canonical 0738 gs_quant/test/timeseries/test_analysis.py test_lag', fin_gsq_test_test_lag('local_payload').payload || ':' || fin_gsq_test_test_lag('local_payload').source_function, 'local_payload:test_lag');
SELECT assert_eq('gs quant canonical 0739 gs_quant/test/timeseries/test_analysis.py test_repeat_empty_series', fin_gsq_test_test_repeat_empty_series('local_payload').payload || ':' || fin_gsq_test_test_repeat_empty_series('local_payload').source_function, 'local_payload:test_repeat_empty_series');
SELECT assert_eq('gs quant canonical 0740 gs_quant/test/timeseries/test_analysis.py test_lag_empty_series', fin_gsq_test_test_lag_empty_series('local_payload').payload || ':' || fin_gsq_test_test_lag_empty_series('local_payload').source_function, 'local_payload:test_lag_empty_series');
SELECT assert_eq('gs quant canonical 0741 gs_quant/test/timeseries/test_analysis.py test_smooth_outliers', fin_gsq_test_test_smooth_outliers('local_payload').payload || ':' || fin_gsq_test_test_smooth_outliers('local_payload').source_function, 'local_payload:test_smooth_outliers');
SELECT assert_eq('gs quant canonical 0742 gs_quant/test/timeseries/test_analysis.py test_consecutive', fin_gsq_test_test_consecutive('local_payload').payload || ':' || fin_gsq_test_test_consecutive('local_payload').source_function, 'local_payload:test_consecutive');
SELECT assert_eq('gs quant canonical 0743 gs_quant/test/timeseries/test_backtesting.py test_basket_series', fin_gsq_test_test_basket_series('local_payload').payload || ':' || fin_gsq_test_test_basket_series('local_payload').source_function, 'local_payload:test_basket_series');
SELECT assert_eq('gs quant canonical 0744 gs_quant/test/timeseries/test_backtesting.py test_basket_price', fin_gsq_test_test_basket_price('local_payload').payload || ':' || fin_gsq_test_test_basket_price('local_payload').source_function, 'local_payload:test_basket_price');
SELECT assert_eq('gs quant canonical 0745 gs_quant/test/timeseries/test_backtesting.py test_basket_average_implied_vol', fin_gsq_test_test_basket_average_implied_vol('local_payload').payload || ':' || fin_gsq_test_test_basket_average_implied_vol('local_payload').source_function, 'local_payload:test_basket_average_implied_vol');
SELECT assert_eq('gs quant canonical 0746 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_vol', fin_gsq_test_test_basket_average_realized_vol('local_payload').payload || ':' || fin_gsq_test_test_basket_average_realized_vol('local_payload').source_function, 'local_payload:test_basket_average_realized_vol');
SELECT assert_eq('gs quant canonical 0747 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_vol_wts', fin_gsq_test_test_basket_average_realized_vol_wts('local_payload').payload || ':' || fin_gsq_test_test_basket_average_realized_vol_wts('local_payload').source_function, 'local_payload:test_basket_average_realized_vol_wts');
SELECT assert_eq('gs quant canonical 0748 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_vol_intraday', fin_gsq_test_test_basket_average_realized_vol_intraday('local_payload').payload || ':' || fin_gsq_test_test_basket_average_realized_vol_intraday('local_payload').source_function, 'local_payload:test_basket_average_realized_vol_intraday');
SELECT assert_eq('gs quant canonical 0749 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_corr', fin_gsq_test_test_basket_average_realized_corr('local_payload').payload || ':' || fin_gsq_test_test_basket_average_realized_corr('local_payload').source_function, 'local_payload:test_basket_average_realized_corr');
SELECT assert_eq('gs quant canonical 0750 gs_quant/test/timeseries/test_backtesting.py test_basket_without_weights', fin_gsq_test_test_basket_without_weights('local_payload').payload || ':' || fin_gsq_test_test_basket_without_weights('local_payload').source_function, 'local_payload:test_basket_without_weights');
SELECT assert_eq('gs quant canonical 0751 gs_quant/test/timeseries/test_backtesting.py test_basket_avg_fwd_vol', fin_gsq_test_test_basket_avg_fwd_vol('local_payload').payload || ':' || fin_gsq_test_test_basket_avg_fwd_vol('local_payload').source_function, 'local_payload:test_basket_avg_fwd_vol');
SELECT assert_eq('gs quant canonical 0752 gs_quant/test/timeseries/test_datetime.py test_basic', fin_gsq_test_test_basic('local_payload').payload || ':' || fin_gsq_test_test_basic('local_payload').source_function, 'local_payload:test_basic');
SELECT assert_eq('gs quant canonical 0753 gs_quant/test/timeseries/test_datetime.py test_align', fin_gsq_test_test_align('local_payload').payload || ':' || fin_gsq_test_test_align('local_payload').source_function, 'local_payload:test_align');
SELECT assert_eq('gs quant canonical 0754 gs_quant/test/timeseries/test_datetime.py test_interpolate', fin_gsq_test_test_interpolate('local_payload').payload || ':' || fin_gsq_test_test_interpolate('local_payload').source_function, 'local_payload:test_interpolate');
SELECT assert_eq('gs quant canonical 0755 gs_quant/test/timeseries/test_datetime.py test_value', fin_gsq_test_test_value('local_payload').payload || ':' || fin_gsq_test_test_value('local_payload').source_function, 'local_payload:test_value');
SELECT assert_eq('gs quant canonical 0756 gs_quant/test/timeseries/test_datetime.py test_day', fin_gsq_test_test_day('local_payload').payload || ':' || fin_gsq_test_test_day('local_payload').source_function, 'local_payload:test_day');
SELECT assert_eq('gs quant canonical 0757 gs_quant/test/timeseries/test_datetime.py test_weekday', fin_gsq_test_test_weekday('local_payload').payload || ':' || fin_gsq_test_test_weekday('local_payload').source_function, 'local_payload:test_weekday');
SELECT assert_eq('gs quant canonical 0758 gs_quant/test/timeseries/test_datetime.py test_month', fin_gsq_test_test_month('local_payload').payload || ':' || fin_gsq_test_test_month('local_payload').source_function, 'local_payload:test_month');
SELECT assert_eq('gs quant canonical 0759 gs_quant/test/timeseries/test_datetime.py test_year', fin_gsq_test_test_year('local_payload').payload || ':' || fin_gsq_test_test_year('local_payload').source_function, 'local_payload:test_year');
SELECT assert_eq('gs quant canonical 0760 gs_quant/test/timeseries/test_datetime.py test_quarter', fin_gsq_test_test_quarter('local_payload').payload || ':' || fin_gsq_test_test_quarter('local_payload').source_function, 'local_payload:test_quarter');
SELECT assert_eq('gs quant canonical 0761 gs_quant/test/timeseries/test_datetime.py test_day_count_fractions', fin_gsq_test_test_day_count_fractions('local_payload').payload || ':' || fin_gsq_test_test_day_count_fractions('local_payload').source_function, 'local_payload:test_day_count_fractions');
SELECT assert_eq('gs quant canonical 0762 gs_quant/test/timeseries/test_datetime.py test_date_range', fin_gsq_test_test_date_range('local_payload').payload || ':' || fin_gsq_test_test_date_range('local_payload').source_function, 'local_payload:test_date_range');
SELECT assert_eq('gs quant canonical 0763 gs_quant/test/timeseries/test_datetime.py test_append', fin_gsq_test_test_append('local_payload').payload || ':' || fin_gsq_test_test_append('local_payload').source_function, 'local_payload:test_append');
SELECT assert_eq('gs quant canonical 0764 gs_quant/test/timeseries/test_datetime.py test_prepend', fin_gsq_test_test_prepend('local_payload').payload || ':' || fin_gsq_test_test_prepend('local_payload').source_function, 'local_payload:test_prepend');
SELECT assert_eq('gs quant canonical 0765 gs_quant/test/timeseries/test_datetime.py test_union', fin_gsq_test_test_union('local_payload').payload || ':' || fin_gsq_test_test_union('local_payload').source_function, 'local_payload:test_union');
SELECT assert_eq('gs quant canonical 0766 gs_quant/test/timeseries/test_datetime.py test_bucketize', fin_gsq_test_test_bucketize('local_payload').payload || ':' || fin_gsq_test_test_bucketize('local_payload').source_function, 'local_payload:test_bucketize');
SELECT assert_eq('gs quant canonical 0767 gs_quant/test/timeseries/test_datetime.py test_day_count', fin_gsq_test_test_day_count('local_payload').payload || ':' || fin_gsq_test_test_day_count('local_payload').source_function, 'local_payload:test_day_count');
SELECT assert_eq('gs quant canonical 0768 gs_quant/test/timeseries/test_datetime.py test_day_countdown', fin_gsq_test_test_day_countdown('local_payload').payload || ':' || fin_gsq_test_test_day_countdown('local_payload').source_function, 'local_payload:test_day_countdown');
SELECT assert_eq('gs quant canonical 0769 gs_quant/test/timeseries/test_datetime.py test_align_calendar', fin_gsq_test_test_align_calendar('local_payload').payload || ':' || fin_gsq_test_test_align_calendar('local_payload').source_function, 'local_payload:test_align_calendar');
SELECT assert_eq('gs quant canonical 0770 gs_quant/test/timeseries/test_datetime.py test_bucketize_empty_series', fin_gsq_test_test_bucketize_empty_series('local_payload').payload || ':' || fin_gsq_test_test_bucketize_empty_series('local_payload').source_function, 'local_payload:test_bucketize_empty_series');
SELECT assert_eq('gs quant canonical 0771 gs_quant/test/timeseries/test_econometrics.py test_returns', fin_gsq_test_test_returns('local_payload').payload || ':' || fin_gsq_test_test_returns('local_payload').source_function, 'local_payload:test_returns');
SELECT assert_eq('gs quant canonical 0772 gs_quant/test/timeseries/test_econometrics.py test_prices', fin_gsq_test_test_prices('local_payload').payload || ':' || fin_gsq_test_test_prices('local_payload').source_function, 'local_payload:test_prices');
SELECT assert_eq('gs quant canonical 0773 gs_quant/test/timeseries/test_econometrics.py test_index', fin_gsq_test_test_index('local_payload').payload || ':' || fin_gsq_test_test_index('local_payload').source_function, 'local_payload:test_index');
SELECT assert_eq('gs quant canonical 0774 gs_quant/test/timeseries/test_econometrics.py test_change', fin_gsq_test_test_change('local_payload').payload || ':' || fin_gsq_test_test_change('local_payload').source_function, 'local_payload:test_change');
SELECT assert_eq('gs quant canonical 0775 gs_quant/test/timeseries/test_econometrics.py test_annualize', fin_gsq_test_test_annualize('local_payload').payload || ':' || fin_gsq_test_test_annualize('local_payload').source_function, 'local_payload:test_annualize');
SELECT assert_eq('gs quant canonical 0776 gs_quant/test/timeseries/test_econometrics.py test_volatility', fin_gsq_test_test_volatility('local_payload').payload || ':' || fin_gsq_test_test_volatility('local_payload').source_function, 'local_payload:test_volatility');
SELECT assert_eq('gs quant canonical 0777 gs_quant/test/timeseries/test_econometrics.py test_volatility_assume_zero_mean', fin_gsq_test_test_volatility_assume_zero_mean('local_payload').payload || ':' || fin_gsq_test_test_volatility_assume_zero_mean('local_payload').source_function, 'local_payload:test_volatility_assume_zero_mean');
SELECT assert_eq('gs quant canonical 0778 gs_quant/test/timeseries/test_econometrics.py test_volatility_annualization_factor', fin_gsq_test_test_volatility_annualization_factor('local_payload').payload || ':' || fin_gsq_test_test_volatility_annualization_factor('local_payload').source_function, 'local_payload:test_volatility_annualization_factor');
SELECT assert_eq('gs quant canonical 0779 gs_quant/test/timeseries/test_econometrics.py test_vol_swap_volatility', fin_gsq_test_test_vol_swap_volatility('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_volatility('local_payload').source_function, 'local_payload:test_vol_swap_volatility');
SELECT assert_eq('gs quant canonical 0780 gs_quant/test/timeseries/test_econometrics.py test_correlation', fin_gsq_test_test_correlation('local_payload').payload || ':' || fin_gsq_test_test_correlation('local_payload').source_function, 'local_payload:test_correlation');
SELECT assert_eq('gs quant canonical 0781 gs_quant/test/timeseries/test_econometrics.py test_correlation_returns', fin_gsq_test_test_correlation_returns('local_payload').payload || ':' || fin_gsq_test_test_correlation_returns('local_payload').source_function, 'local_payload:test_correlation_returns');
SELECT assert_eq('gs quant canonical 0782 gs_quant/test/timeseries/test_econometrics.py test_corr_swap_correlation', fin_gsq_test_test_corr_swap_correlation('local_payload').payload || ':' || fin_gsq_test_test_corr_swap_correlation('local_payload').source_function, 'local_payload:test_corr_swap_correlation');
SELECT assert_eq('gs quant canonical 0783 gs_quant/test/timeseries/test_econometrics.py test_beta', fin_gsq_test_test_beta('local_payload').payload || ':' || fin_gsq_test_test_beta('local_payload').source_function, 'local_payload:test_beta');
SELECT assert_eq('gs quant canonical 0784 gs_quant/test/timeseries/test_econometrics.py test_max_drawdown', fin_gsq_test_test_max_drawdown('local_payload').payload || ':' || fin_gsq_test_test_max_drawdown('local_payload').source_function, 'local_payload:test_max_drawdown');
SELECT assert_eq('gs quant canonical 0785 gs_quant/test/timeseries/test_econometrics.py test_excess_returns', fin_gsq_test_test_excess_returns('local_payload').payload || ':' || fin_gsq_test_test_excess_returns('local_payload').source_function, 'local_payload:test_excess_returns');
SELECT assert_eq('gs quant canonical 0786 gs_quant/test/timeseries/test_econometrics.py test_sharpe_ratio', fin_gsq_test_test_sharpe_ratio('local_payload').payload || ':' || fin_gsq_test_test_sharpe_ratio('local_payload').source_function, 'local_payload:test_sharpe_ratio');
SELECT assert_eq('gs quant canonical 0787 gs_quant/test/timeseries/test_helper.py test_int_enum', fin_gsq_test_test_int_enum('local_payload').payload || ':' || fin_gsq_test_test_int_enum('local_payload').source_function, 'local_payload:test_int_enum');
SELECT assert_eq('gs quant canonical 0788 gs_quant/test/timeseries/test_helper.py test_tenor_to_month', fin_gsq_test_test_tenor_to_month('local_payload').payload || ':' || fin_gsq_test_test_tenor_to_month('local_payload').source_function, 'local_payload:test_tenor_to_month');
SELECT assert_eq('gs quant canonical 0789 gs_quant/test/timeseries/test_helper.py test_month_to_tenor', fin_gsq_test_test_month_to_tenor('local_payload').payload || ':' || fin_gsq_test_test_month_to_tenor('local_payload').source_function, 'local_payload:test_month_to_tenor');
SELECT assert_eq('gs quant canonical 0790 gs_quant/test/timeseries/test_helper.py test_get_dataset_with_many_assets', fin_gsq_test_test_get_dataset_with_many_assets('local_payload').payload || ':' || fin_gsq_test_test_get_dataset_with_many_assets('local_payload').source_function, 'local_payload:test_get_dataset_with_many_assets');
SELECT assert_eq('gs quant canonical 0791 gs_quant/test/timeseries/test_helper.py pf', fin_gsq_test_pf('local_payload').payload || ':' || fin_gsq_test_pf('local_payload').source_function, 'local_payload:pf');
SELECT assert_eq('gs quant canonical 0792 gs_quant/test/timeseries/test_helper.py pm', fin_gsq_test_pm('local_payload').payload || ':' || fin_gsq_test_pm('local_payload').source_function, 'local_payload:pm');
SELECT assert_eq('gs quant canonical 0793 gs_quant/test/timeseries/test_helper.py pmt', fin_gsq_test_pmt('local_payload').payload || ':' || fin_gsq_test_pmt('local_payload').source_function, 'local_payload:pmt');
SELECT assert_eq('gs quant canonical 0794 gs_quant/test/timeseries/test_helper.py test_decorators', fin_gsq_test_test_decorators('local_payload').payload || ':' || fin_gsq_test_test_decorators('local_payload').source_function, 'local_payload:test_decorators');
SELECT assert_eq('gs quant canonical 0795 gs_quant/test/timeseries/test_helper.py test_normalize_window_defaults_window_if_none_passed', fin_gsq_test_test_normalize_window_defaults_window_if_none_passed('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_defaults_window_if_none_passed('local_payload').source_function, 'local_payload:test_normalize_window_defaults_window_if_none_passed');
SELECT assert_eq('gs quant canonical 0796 gs_quant/test/timeseries/test_helper.py test_normalize_window_defaults_window_if_passed', fin_gsq_test_test_normalize_window_defaults_window_if_passed('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_defaults_window_if_passed('local_payload').source_function, 'local_payload:test_normalize_window_defaults_window_if_passed');
SELECT assert_eq('gs quant canonical 0797 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_int', fin_gsq_test_test_normalize_window_handles_int('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_handles_int('local_payload').source_function, 'local_payload:test_normalize_window_handles_int');
SELECT assert_eq('gs quant canonical 0798 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_window_with_no_ramp', fin_gsq_test_test_normalize_window_handles_window_with_no_ramp('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_handles_window_with_no_ramp('local_payload').source_function, 'local_payload:test_normalize_window_handles_window_with_no_ramp');
SELECT assert_eq('gs quant canonical 0799 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_window_with_no_size', fin_gsq_test_test_normalize_window_handles_window_with_no_size('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_handles_window_with_no_size('local_payload').source_function, 'local_payload:test_normalize_window_handles_window_with_no_size');
SELECT assert_eq('gs quant canonical 0800 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_ramp_greater_than_series_length', fin_gsq_test_test_normalize_window_handles_ramp_greater_than_series_length('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_handles_ramp_greater_than_series_length('local_payload').source_function, 'local_payload:test_normalize_window_handles_ramp_greater_than_series_length');
SELECT assert_eq('gs quant canonical 0801 gs_quant/test/timeseries/test_helper.py test_normalize_window_raises_error_on_window_of_size_zero', fin_gsq_test_test_normalize_window_raises_error_on_window_of_size_zero('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_raises_error_on_window_of_size_zero('local_payload').source_function, 'local_payload:test_normalize_window_raises_error_on_window_of_size_zero');
SELECT assert_eq('gs quant canonical 0802 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_ramp_of_size_zero', fin_gsq_test_test_normalize_window_handles_ramp_of_size_zero('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_handles_ramp_of_size_zero('local_payload').source_function, 'local_payload:test_normalize_window_handles_ramp_of_size_zero');
SELECT assert_eq('gs quant canonical 0803 gs_quant/test/timeseries/test_helper.py test_normalize_window_str', fin_gsq_test_test_normalize_window_str('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_str('local_payload').source_function, 'local_payload:test_normalize_window_str');
SELECT assert_eq('gs quant canonical 0804 gs_quant/test/timeseries/test_helper.py test_normalize_window_single_str', fin_gsq_test_test_normalize_window_single_str('local_payload').payload || ':' || fin_gsq_test_test_normalize_window_single_str('local_payload').source_function, 'local_payload:test_normalize_window_single_str');
SELECT assert_eq('gs quant canonical 0805 gs_quant/test/timeseries/test_helper.py test_apply_ramp', fin_gsq_test_test_apply_ramp('local_payload').payload || ':' || fin_gsq_test_test_apply_ramp('local_payload').source_function, 'local_payload:test_apply_ramp');
SELECT assert_eq('gs quant canonical 0806 gs_quant/test/timeseries/test_helper.py test_apply_ramp_with_window_greater_than_series_length', fin_gsq_test_test_apply_ramp_with_window_greater_than_series_length('local_payload').payload || ':' || fin_gsq_test_test_apply_ramp_with_window_greater_than_series_length('local_payload').source_function, 'local_payload:test_apply_ramp_with_window_greater_than_series_length');
SELECT assert_eq('gs quant canonical 0807 gs_quant/test/timeseries/test_helper.py test_apply_ramp_dateoffset', fin_gsq_test_test_apply_ramp_dateoffset('local_payload').payload || ':' || fin_gsq_test_test_apply_ramp_dateoffset('local_payload').source_function, 'local_payload:test_apply_ramp_dateoffset');
SELECT assert_eq('gs quant canonical 0808 gs_quant/test/timeseries/test_helper.py test_apply_ramp_raises_on_edge_cases', fin_gsq_test_test_apply_ramp_raises_on_edge_cases('local_payload').payload || ':' || fin_gsq_test_test_apply_ramp_raises_on_edge_cases('local_payload').source_function, 'local_payload:test_apply_ramp_raises_on_edge_cases');
SELECT assert_eq('gs quant canonical 0809 gs_quant/test/timeseries/test_helper.py test_get_df_with_retries', fin_gsq_test_test_get_df_with_retries('local_payload').payload || ':' || fin_gsq_test_test_get_df_with_retries('local_payload').source_function, 'local_payload:test_get_df_with_retries');
SELECT assert_eq('gs quant canonical 0810 gs_quant/test/timeseries/test_helper.py test_forward_looking', fin_gsq_test_test_forward_looking('local_payload').payload || ':' || fin_gsq_test_test_forward_looking('local_payload').source_function, 'local_payload:test_forward_looking');
SELECT assert_eq('gs quant canonical 0811 gs_quant/test/timeseries/test_helper.py test_get_dataset_data_with_retries', fin_gsq_test_test_get_dataset_data_with_retries('local_payload').payload || ':' || fin_gsq_test_test_get_dataset_data_with_retries('local_payload').source_function, 'local_payload:test_get_dataset_data_with_retries');
SELECT assert_eq('gs quant canonical 0812 gs_quant/test/timeseries/test_helper.py test_split_where_conditions', fin_gsq_test_test_split_where_conditions('local_payload').payload || ':' || fin_gsq_test_test_split_where_conditions('local_payload').source_function, 'local_payload:test_split_where_conditions');
SELECT assert_eq('gs quant canonical 0813 gs_quant/test/timeseries/test_helper.py test_get_dataset_data_with_retries_recursive_split', fin_gsq_test_test_get_dataset_data_with_retries_recursive_split('local_payload').payload || ':' || fin_gsq_test_test_get_dataset_data_with_retries_recursive_split('local_payload').source_function, 'local_payload:test_get_dataset_data_with_retries_recursive_split');
SELECT assert_eq('gs quant canonical 0814 gs_quant/test/timeseries/test_measures.py mock_empty_market_data_response', fin_gsq_test_mock_empty_market_data_response('local_payload').payload || ':' || fin_gsq_test_mock_empty_market_data_response('local_payload').source_function, 'local_payload:mock_empty_market_data_response');
SELECT assert_eq('gs quant canonical 0815 gs_quant/test/timeseries/test_measures.py map_identifiers_default_mocker', fin_gsq_test_map_identifiers_default_mocker('local_payload').payload || ':' || fin_gsq_test_map_identifiers_default_mocker('local_payload').source_function, 'local_payload:map_identifiers_default_mocker');
SELECT assert_eq('gs quant canonical 0816 gs_quant/test/timeseries/test_measures.py map_identifiers_ois_mocker', fin_gsq_test_map_identifiers_ois_mocker('local_payload').payload || ':' || fin_gsq_test_map_identifiers_ois_mocker('local_payload').source_function, 'local_payload:map_identifiers_ois_mocker');
SELECT assert_eq('gs quant canonical 0817 gs_quant/test/timeseries/test_measures.py map_identifiers_swap_rate_mocker', fin_gsq_test_map_identifiers_swap_rate_mocker('local_payload').payload || ':' || fin_gsq_test_map_identifiers_swap_rate_mocker('local_payload').source_function, 'local_payload:map_identifiers_swap_rate_mocker');
SELECT assert_eq('gs quant canonical 0818 gs_quant/test/timeseries/test_measures.py map_identifiers_inflation_mocker', fin_gsq_test_map_identifiers_inflation_mocker('local_payload').payload || ':' || fin_gsq_test_map_identifiers_inflation_mocker('local_payload').source_function, 'local_payload:map_identifiers_inflation_mocker');
SELECT assert_eq('gs quant canonical 0819 gs_quant/test/timeseries/test_measures.py map_identifiers_cross_basis_mocker', fin_gsq_test_map_identifiers_cross_basis_mocker('local_payload').payload || ':' || fin_gsq_test_map_identifiers_cross_basis_mocker('local_payload').source_function, 'local_payload:map_identifiers_cross_basis_mocker');
SELECT assert_eq('gs quant canonical 0820 gs_quant/test/timeseries/test_measures.py test_currency_to_default_ois_asset', fin_gsq_test_test_currency_to_default_ois_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_default_ois_asset('local_payload').source_function, 'local_payload:test_currency_to_default_ois_asset');
SELECT assert_eq('gs quant canonical 0821 gs_quant/test/timeseries/test_measures.py test_currency_to_default_benchmark_rate', fin_gsq_test_test_currency_to_default_benchmark_rate('local_payload').payload || ':' || fin_gsq_test_test_currency_to_default_benchmark_rate('local_payload').source_function, 'local_payload:test_currency_to_default_benchmark_rate');
SELECT assert_eq('gs quant canonical 0822 gs_quant/test/timeseries/test_measures.py test_currency_to_default_swap_rate_asset', fin_gsq_test_test_currency_to_default_swap_rate_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_default_swap_rate_asset('local_payload').source_function, 'local_payload:test_currency_to_default_swap_rate_asset');
SELECT assert_eq('gs quant canonical 0823 gs_quant/test/timeseries/test_measures.py test_currency_to_inflation_benchmark_rate', fin_gsq_test_test_currency_to_inflation_benchmark_rate('local_payload').payload || ':' || fin_gsq_test_test_currency_to_inflation_benchmark_rate('local_payload').source_function, 'local_payload:test_currency_to_inflation_benchmark_rate');
SELECT assert_eq('gs quant canonical 0824 gs_quant/test/timeseries/test_measures.py test_cross_to_basis', fin_gsq_test_test_cross_to_basis('local_payload').payload || ':' || fin_gsq_test_test_cross_to_basis('local_payload').source_function, 'local_payload:test_cross_to_basis');
SELECT assert_eq('gs quant canonical 0825 gs_quant/test/timeseries/test_measures.py test_currency_to_tdapi_swap_rate_asset', fin_gsq_test_test_currency_to_tdapi_swap_rate_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_swap_rate_asset('local_payload').source_function, 'local_payload:test_currency_to_tdapi_swap_rate_asset');
SELECT assert_eq('gs quant canonical 0826 gs_quant/test/timeseries/test_measures.py test_currency_to_tdapi_basis_swap_rate_asset', fin_gsq_test_test_currency_to_tdapi_basis_swap_rate_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_basis_swap_rate_asset('local_payload').source_function, 'local_payload:test_currency_to_tdapi_basis_swap_rate_asset');
SELECT assert_eq('gs quant canonical 0827 gs_quant/test/timeseries/test_measures.py test_currency_to_tdapi_swap_rate_asset_for_intraday', fin_gsq_test_test_currency_to_tdapi_swap_rate_asset_for_intraday('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_swap_rate_asset_for_intraday('local_payload').source_function, 'local_payload:test_currency_to_tdapi_swap_rate_asset_for_intraday');
SELECT assert_eq('gs quant canonical 0828 gs_quant/test/timeseries/test_measures.py my_mocked_mxapi_backtest', fin_gsq_test_my_mocked_mxapi_backtest('local_payload').payload || ':' || fin_gsq_test_my_mocked_mxapi_backtest('local_payload').source_function, 'local_payload:my_mocked_mxapi_backtest');
SELECT assert_eq('gs quant canonical 0829 gs_quant/test/timeseries/test_measures.py test_swap_rate_calc', fin_gsq_test_test_swap_rate_calc('local_payload').payload || ':' || fin_gsq_test_test_swap_rate_calc('local_payload').source_function, 'local_payload:test_swap_rate_calc');
SELECT assert_eq('gs quant canonical 0830 gs_quant/test/timeseries/test_measures.py my_mocked_mxapi_measure', fin_gsq_test_my_mocked_mxapi_measure('local_payload').payload || ':' || fin_gsq_test_my_mocked_mxapi_measure('local_payload').source_function, 'local_payload:my_mocked_mxapi_measure');
SELECT assert_eq('gs quant canonical 0831 gs_quant/test/timeseries/test_measures.py test_curve_measures', fin_gsq_test_test_curve_measures('local_payload').payload || ':' || fin_gsq_test_test_curve_measures('local_payload').source_function, 'local_payload:test_curve_measures');
SELECT assert_eq('gs quant canonical 0832 gs_quant/test/timeseries/test_measures.py test_check_clearing_house', fin_gsq_test_test_check_clearing_house('local_payload').payload || ':' || fin_gsq_test_test_check_clearing_house('local_payload').source_function, 'local_payload:test_check_clearing_house');
SELECT assert_eq('gs quant canonical 0833 gs_quant/test/timeseries/test_measures.py test_get_swap_csa_terms', fin_gsq_test_test_get_swap_csa_terms('local_payload').payload || ':' || fin_gsq_test_test_get_swap_csa_terms('local_payload').source_function, 'local_payload:test_get_swap_csa_terms');
SELECT assert_eq('gs quant canonical 0834 gs_quant/test/timeseries/test_measures.py test_get_basis_swap_csa_terms', fin_gsq_test_test_get_basis_swap_csa_terms('local_payload').payload || ':' || fin_gsq_test_test_get_basis_swap_csa_terms('local_payload').source_function, 'local_payload:test_get_basis_swap_csa_terms');
SELECT assert_eq('gs quant canonical 0835 gs_quant/test/timeseries/test_measures.py test_match_floating_tenors', fin_gsq_test_test_match_floating_tenors('local_payload').payload || ':' || fin_gsq_test_test_match_floating_tenors('local_payload').source_function, 'local_payload:test_match_floating_tenors');
SELECT assert_eq('gs quant canonical 0836 gs_quant/test/timeseries/test_measures.py test_get_term_struct_date', fin_gsq_test_test_get_term_struct_date('local_payload').payload || ':' || fin_gsq_test_test_get_term_struct_date('local_payload').source_function, 'local_payload:test_get_term_struct_date');
SELECT assert_eq('gs quant canonical 0837 gs_quant/test/timeseries/test_measures.py test_cross_stored_direction_for_fx_vol', fin_gsq_test_test_cross_stored_direction_for_fx_vol('local_payload').payload || ':' || fin_gsq_test_test_cross_stored_direction_for_fx_vol('local_payload').source_function, 'local_payload:test_cross_stored_direction_for_fx_vol');
SELECT assert_eq('gs quant canonical 0838 gs_quant/test/timeseries/test_measures.py test_cross_to_usd_based_cross_for_fx_forecast', fin_gsq_test_test_cross_to_usd_based_cross_for_fx_forecast('local_payload').payload || ':' || fin_gsq_test_test_cross_to_usd_based_cross_for_fx_forecast('local_payload').source_function, 'local_payload:test_cross_to_usd_based_cross_for_fx_forecast');
SELECT assert_eq('gs quant canonical 0839 gs_quant/test/timeseries/test_measures.py test_cross_to_used_based_cross', fin_gsq_test_test_cross_to_used_based_cross('local_payload').payload || ':' || fin_gsq_test_test_cross_to_used_based_cross('local_payload').source_function, 'local_payload:test_cross_to_used_based_cross');
SELECT assert_eq('gs quant canonical 0840 gs_quant/test/timeseries/test_measures.py test_cross_stored_direction', fin_gsq_test_test_cross_stored_direction('local_payload').payload || ':' || fin_gsq_test_test_cross_stored_direction('local_payload').source_function, 'local_payload:test_cross_stored_direction');
SELECT assert_eq('gs quant canonical 0841 gs_quant/test/timeseries/test_measures.py test_get_tdapi_rates_assets', fin_gsq_test_test_get_tdapi_rates_assets('local_payload').payload || ':' || fin_gsq_test_test_get_tdapi_rates_assets('local_payload').source_function, 'local_payload:test_get_tdapi_rates_assets');
SELECT assert_eq('gs quant canonical 0842 gs_quant/test/timeseries/test_measures.py test_get_swap_leg_defaults', fin_gsq_test_test_get_swap_leg_defaults('local_payload').payload || ':' || fin_gsq_test_test_get_swap_leg_defaults('local_payload').source_function, 'local_payload:test_get_swap_leg_defaults');
SELECT assert_eq('gs quant canonical 0843 gs_quant/test/timeseries/test_measures.py test_check_forward_tenor', fin_gsq_test_test_check_forward_tenor('local_payload').payload || ':' || fin_gsq_test_test_check_forward_tenor('local_payload').source_function, 'local_payload:test_check_forward_tenor');
SELECT assert_eq('gs quant canonical 0844 gs_quant/test/timeseries/test_measures.py mock_commod', fin_gsq_test_mock_commod('local_payload').payload || ':' || fin_gsq_test_mock_commod('local_payload').source_function, 'local_payload:mock_commod');
SELECT assert_eq('gs quant canonical 0845 gs_quant/test/timeseries/test_measures.py mock_commod_dup', fin_gsq_test_mock_commod_dup('local_payload').payload || ':' || fin_gsq_test_mock_commod_dup('local_payload').source_function, 'local_payload:mock_commod_dup');
SELECT assert_eq('gs quant canonical 0846 gs_quant/test/timeseries/test_measures.py mock_forward_price', fin_gsq_test_mock_forward_price('local_payload').payload || ':' || fin_gsq_test_mock_forward_price('local_payload').source_function, 'local_payload:mock_forward_price');
SELECT assert_eq('gs quant canonical 0847 gs_quant/test/timeseries/test_measures.py mock_implied_volatility_elec', fin_gsq_test_mock_implied_volatility_elec('local_payload').payload || ':' || fin_gsq_test_mock_implied_volatility_elec('local_payload').source_function, 'local_payload:mock_implied_volatility_elec');
SELECT assert_eq('gs quant canonical 0848 gs_quant/test/timeseries/test_measures.py mock_fair_price', fin_gsq_test_mock_fair_price('local_payload').payload || ':' || fin_gsq_test_mock_fair_price('local_payload').source_function, 'local_payload:mock_fair_price');
SELECT assert_eq('gs quant canonical 0849 gs_quant/test/timeseries/test_measures.py mock_eu_natgas_forward_price', fin_gsq_test_mock_eu_natgas_forward_price('local_payload').payload || ':' || fin_gsq_test_mock_eu_natgas_forward_price('local_payload').source_function, 'local_payload:mock_eu_natgas_forward_price');
SELECT assert_eq('gs quant canonical 0850 gs_quant/test/timeseries/test_measures.py mock_natgas_forward_price', fin_gsq_test_mock_natgas_forward_price('local_payload').payload || ':' || fin_gsq_test_mock_natgas_forward_price('local_payload').source_function, 'local_payload:mock_natgas_forward_price');
SELECT assert_eq('gs quant canonical 0851 gs_quant/test/timeseries/test_measures.py mock_natgas_implied_volatility', fin_gsq_test_mock_natgas_implied_volatility('local_payload').payload || ':' || fin_gsq_test_mock_natgas_implied_volatility('local_payload').source_function, 'local_payload:mock_natgas_implied_volatility');
SELECT assert_eq('gs quant canonical 0852 gs_quant/test/timeseries/test_measures.py mock_fair_price_swap', fin_gsq_test_mock_fair_price_swap('local_payload').payload || ':' || fin_gsq_test_mock_fair_price_swap('local_payload').source_function, 'local_payload:mock_fair_price_swap');
SELECT assert_eq('gs quant canonical 0853 gs_quant/test/timeseries/test_measures.py mock_implied_volatility', fin_gsq_test_mock_implied_volatility('local_payload').payload || ':' || fin_gsq_test_mock_implied_volatility('local_payload').source_function, 'local_payload:mock_implied_volatility');
SELECT assert_eq('gs quant canonical 0854 gs_quant/test/timeseries/test_measures.py mock_missing_bucket_forward_price', fin_gsq_test_mock_missing_bucket_forward_price('local_payload').payload || ':' || fin_gsq_test_mock_missing_bucket_forward_price('local_payload').source_function, 'local_payload:mock_missing_bucket_forward_price');
SELECT assert_eq('gs quant canonical 0855 gs_quant/test/timeseries/test_measures.py mock_missing_bucket_implied_volatility', fin_gsq_test_mock_missing_bucket_implied_volatility('local_payload').payload || ':' || fin_gsq_test_mock_missing_bucket_implied_volatility('local_payload').source_function, 'local_payload:mock_missing_bucket_implied_volatility');
SELECT assert_eq('gs quant canonical 0856 gs_quant/test/timeseries/test_measures.py mock_fx_vol', fin_gsq_test_mock_fx_vol('local_payload').payload || ':' || fin_gsq_test_mock_fx_vol('local_payload').source_function, 'local_payload:mock_fx_vol');
SELECT assert_eq('gs quant canonical 0857 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_3m', fin_gsq_test_mock_fx_spot_fwd_3m('local_payload').payload || ':' || fin_gsq_test_mock_fx_spot_fwd_3m('local_payload').source_function, 'local_payload:mock_fx_spot_fwd_3m');
SELECT assert_eq('gs quant canonical 0858 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_2y', fin_gsq_test_mock_fx_spot_fwd_2y('local_payload').payload || ':' || fin_gsq_test_mock_fx_spot_fwd_2y('local_payload').source_function, 'local_payload:mock_fx_spot_fwd_2y');
SELECT assert_eq('gs quant canonical 0859 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_3m_rt', fin_gsq_test_mock_fx_spot_fwd_3m_rt('local_payload').payload || ':' || fin_gsq_test_mock_fx_spot_fwd_3m_rt('local_payload').source_function, 'local_payload:mock_fx_spot_fwd_3m_rt');
SELECT assert_eq('gs quant canonical 0860 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_2y_rt', fin_gsq_test_mock_fx_spot_fwd_2y_rt('local_payload').payload || ':' || fin_gsq_test_mock_fx_spot_fwd_2y_rt('local_payload').source_function, 'local_payload:mock_fx_spot_fwd_2y_rt');
SELECT assert_eq('gs quant canonical 0861 gs_quant/test/timeseries/test_measures.py mock_fx_correlation', fin_gsq_test_mock_fx_correlation('local_payload').payload || ':' || fin_gsq_test_mock_fx_correlation('local_payload').source_function, 'local_payload:mock_fx_correlation');
SELECT assert_eq('gs quant canonical 0862 gs_quant/test/timeseries/test_measures.py mock_fx_forecast', fin_gsq_test_mock_fx_forecast('local_payload').payload || ':' || fin_gsq_test_mock_fx_forecast('local_payload').source_function, 'local_payload:mock_fx_forecast');
SELECT assert_eq('gs quant canonical 0863 gs_quant/test/timeseries/test_measures.py mock_fx_forecast_time_series', fin_gsq_test_mock_fx_forecast_time_series('local_payload').payload || ':' || fin_gsq_test_mock_fx_forecast_time_series('local_payload').source_function, 'local_payload:mock_fx_forecast_time_series');
SELECT assert_eq('gs quant canonical 0864 gs_quant/test/timeseries/test_measures.py mock_fx_delta', fin_gsq_test_mock_fx_delta('local_payload').payload || ':' || fin_gsq_test_mock_fx_delta('local_payload').source_function, 'local_payload:mock_fx_delta');
SELECT assert_eq('gs quant canonical 0865 gs_quant/test/timeseries/test_measures.py mock_fx_empty', fin_gsq_test_mock_fx_empty('local_payload').payload || ':' || fin_gsq_test_mock_fx_empty('local_payload').source_function, 'local_payload:mock_fx_empty');
SELECT assert_eq('gs quant canonical 0866 gs_quant/test/timeseries/test_measures.py mock_fx_switch', fin_gsq_test_mock_fx_switch('local_payload').payload || ':' || fin_gsq_test_mock_fx_switch('local_payload').source_function, 'local_payload:mock_fx_switch');
SELECT assert_eq('gs quant canonical 0867 gs_quant/test/timeseries/test_measures.py mock_curr', fin_gsq_test_mock_curr('local_payload').payload || ':' || fin_gsq_test_mock_curr('local_payload').source_function, 'local_payload:mock_curr');
SELECT assert_eq('gs quant canonical 0868 gs_quant/test/timeseries/test_measures.py mock_cross', fin_gsq_test_mock_cross('local_payload').payload || ':' || fin_gsq_test_mock_cross('local_payload').source_function, 'local_payload:mock_cross');
SELECT assert_eq('gs quant canonical 0869 gs_quant/test/timeseries/test_measures.py mock_eq', fin_gsq_test_mock_eq('local_payload').payload || ':' || fin_gsq_test_mock_eq('local_payload').source_function, 'local_payload:mock_eq');
SELECT assert_eq('gs quant canonical 0870 gs_quant/test/timeseries/test_measures.py mock_eq_vol', fin_gsq_test_mock_eq_vol('local_payload').payload || ':' || fin_gsq_test_mock_eq_vol('local_payload').source_function, 'local_payload:mock_eq_vol');
SELECT assert_eq('gs quant canonical 0871 gs_quant/test/timeseries/test_measures.py mock_eq_vol_last_empty', fin_gsq_test_mock_eq_vol_last_empty('local_payload').payload || ':' || fin_gsq_test_mock_eq_vol_last_empty('local_payload').source_function, 'local_payload:mock_eq_vol_last_empty');
SELECT assert_eq('gs quant canonical 0872 gs_quant/test/timeseries/test_measures.py mock_eq_norm', fin_gsq_test_mock_eq_norm('local_payload').payload || ':' || fin_gsq_test_mock_eq_norm('local_payload').source_function, 'local_payload:mock_eq_norm');
SELECT assert_eq('gs quant canonical 0873 gs_quant/test/timeseries/test_measures.py mock_eq_spot', fin_gsq_test_mock_eq_spot('local_payload').payload || ':' || fin_gsq_test_mock_eq_spot('local_payload').source_function, 'local_payload:mock_eq_spot');
SELECT assert_eq('gs quant canonical 0874 gs_quant/test/timeseries/test_measures.py mock_inc', fin_gsq_test_mock_inc('local_payload').payload || ':' || fin_gsq_test_mock_inc('local_payload').source_function, 'local_payload:mock_inc');
SELECT assert_eq('gs quant canonical 0875 gs_quant/test/timeseries/test_measures.py mock_esg', fin_gsq_test_mock_esg('local_payload').payload || ':' || fin_gsq_test_mock_esg('local_payload').source_function, 'local_payload:mock_esg');
SELECT assert_eq('gs quant canonical 0876 gs_quant/test/timeseries/test_measures.py mock_index_positions_data', fin_gsq_test_mock_index_positions_data('local_payload').payload || ':' || fin_gsq_test_mock_index_positions_data('local_payload').source_function, 'local_payload:mock_index_positions_data');
SELECT assert_eq('gs quant canonical 0877 gs_quant/test/timeseries/test_measures.py mock_rating', fin_gsq_test_mock_rating('local_payload').payload || ':' || fin_gsq_test_mock_rating('local_payload').source_function, 'local_payload:mock_rating');
SELECT assert_eq('gs quant canonical 0878 gs_quant/test/timeseries/test_measures.py mock_gsdeer_gsfeer', fin_gsq_test_mock_gsdeer_gsfeer('local_payload').payload || ':' || fin_gsq_test_mock_gsdeer_gsfeer('local_payload').source_function, 'local_payload:mock_gsdeer_gsfeer');
SELECT assert_eq('gs quant canonical 0879 gs_quant/test/timeseries/test_measures.py mock_factor_profile', fin_gsq_test_mock_factor_profile('local_payload').payload || ':' || fin_gsq_test_mock_factor_profile('local_payload').source_function, 'local_payload:mock_factor_profile');
SELECT assert_eq('gs quant canonical 0880 gs_quant/test/timeseries/test_measures.py mock_commodity_forecast', fin_gsq_test_mock_commodity_forecast('local_payload').payload || ':' || fin_gsq_test_mock_commodity_forecast('local_payload').source_function, 'local_payload:mock_commodity_forecast');
SELECT assert_eq('gs quant canonical 0881 gs_quant/test/timeseries/test_measures.py mock_commodity_forecast_time_series', fin_gsq_test_mock_commodity_forecast_time_series('local_payload').payload || ':' || fin_gsq_test_mock_commodity_forecast_time_series('local_payload').source_function, 'local_payload:mock_commodity_forecast_time_series');
SELECT assert_eq('gs quant canonical 0882 gs_quant/test/timeseries/test_measures.py mock_cds_spread', fin_gsq_test_mock_cds_spread('local_payload').payload || ':' || fin_gsq_test_mock_cds_spread('local_payload').source_function, 'local_payload:mock_cds_spread');
SELECT assert_eq('gs quant canonical 0883 gs_quant/test/timeseries/test_measures.py test_skew', fin_gsq_test_test_skew('local_payload').payload || ':' || fin_gsq_test_test_skew('local_payload').source_function, 'local_payload:test_skew');
SELECT assert_eq('gs quant canonical 0884 gs_quant/test/timeseries/test_measures.py test_skew_fx', fin_gsq_test_test_skew_fx('local_payload').payload || ':' || fin_gsq_test_test_skew_fx('local_payload').source_function, 'local_payload:test_skew_fx');
SELECT assert_eq('gs quant canonical 0885 gs_quant/test/timeseries/test_measures.py test_implied_vol', fin_gsq_test_test_implied_vol('local_payload').payload || ':' || fin_gsq_test_test_implied_vol('local_payload').source_function, 'local_payload:test_implied_vol');
SELECT assert_eq('gs quant canonical 0886 gs_quant/test/timeseries/test_measures.py test_merge_dataframes', fin_gsq_test_test_merge_dataframes('local_payload').payload || ':' || fin_gsq_test_test_merge_dataframes('local_payload').source_function, 'local_payload:test_merge_dataframes');
SELECT assert_eq('gs quant canonical 0887 gs_quant/test/timeseries/test_measures.py test_get_last_for_measure', fin_gsq_test_test_get_last_for_measure('local_payload').payload || ':' || fin_gsq_test_test_get_last_for_measure('local_payload').source_function, 'local_payload:test_get_last_for_measure');
SELECT assert_eq('gs quant canonical 0888 gs_quant/test/timeseries/test_measures.py test_ignore_errors', fin_gsq_test_test_ignore_errors('local_payload').payload || ':' || fin_gsq_test_test_ignore_errors('local_payload').source_function, 'local_payload:test_ignore_errors');
SELECT assert_eq('gs quant canonical 0889 gs_quant/test/timeseries/test_measures.py test_tenor_month_to_year', fin_gsq_test_test_tenor_month_to_year('local_payload').payload || ':' || fin_gsq_test_test_tenor_month_to_year('local_payload').source_function, 'local_payload:test_tenor_month_to_year');
SELECT assert_eq('gs quant canonical 0890 gs_quant/test/timeseries/test_measures.py test_implied_vol_no_last', fin_gsq_test_test_implied_vol_no_last('local_payload').payload || ':' || fin_gsq_test_test_implied_vol_no_last('local_payload').source_function, 'local_payload:test_implied_vol_no_last');
SELECT assert_eq('gs quant canonical 0891 gs_quant/test/timeseries/test_measures.py test_implied_vol_fx', fin_gsq_test_test_implied_vol_fx('local_payload').payload || ':' || fin_gsq_test_test_implied_vol_fx('local_payload').source_function, 'local_payload:test_implied_vol_fx');
SELECT assert_eq('gs quant canonical 0892 gs_quant/test/timeseries/test_measures.py test_fx_forecast', fin_gsq_test_test_fx_forecast('local_payload').payload || ':' || fin_gsq_test_test_fx_forecast('local_payload').source_function, 'local_payload:test_fx_forecast');
SELECT assert_eq('gs quant canonical 0893 gs_quant/test/timeseries/test_measures.py test_fx_forecast_inverse', fin_gsq_test_test_fx_forecast_inverse('local_payload').payload || ':' || fin_gsq_test_test_fx_forecast_inverse('local_payload').source_function, 'local_payload:test_fx_forecast_inverse');
SELECT assert_eq('gs quant canonical 0894 gs_quant/test/timeseries/test_measures.py test_fx_forecast_time_series', fin_gsq_test_test_fx_forecast_time_series('local_payload').payload || ':' || fin_gsq_test_test_fx_forecast_time_series('local_payload').source_function, 'local_payload:test_fx_forecast_time_series');
SELECT assert_eq('gs quant canonical 0895 gs_quant/test/timeseries/test_measures.py test_vol_smile', fin_gsq_test_test_vol_smile('local_payload').payload || ':' || fin_gsq_test_test_vol_smile('local_payload').source_function, 'local_payload:test_vol_smile');
SELECT assert_eq('gs quant canonical 0896 gs_quant/test/timeseries/test_measures.py test_impl_corr', fin_gsq_test_test_impl_corr('local_payload').payload || ':' || fin_gsq_test_test_impl_corr('local_payload').source_function, 'local_payload:test_impl_corr');
SELECT assert_eq('gs quant canonical 0897 gs_quant/test/timeseries/test_measures.py test_impl_corr_n', fin_gsq_test_test_impl_corr_n('local_payload').payload || ':' || fin_gsq_test_test_impl_corr_n('local_payload').source_function, 'local_payload:test_impl_corr_n');
SELECT assert_eq('gs quant canonical 0898 gs_quant/test/timeseries/test_measures.py test_implied_corr_basket', fin_gsq_test_test_implied_corr_basket('local_payload').payload || ':' || fin_gsq_test_test_implied_corr_basket('local_payload').source_function, 'local_payload:test_implied_corr_basket');
SELECT assert_eq('gs quant canonical 0899 gs_quant/test/timeseries/test_measures.py test_realized_corr_basket', fin_gsq_test_test_realized_corr_basket('local_payload').payload || ':' || fin_gsq_test_test_realized_corr_basket('local_payload').source_function, 'local_payload:test_realized_corr_basket');
SELECT assert_eq('gs quant canonical 0900 gs_quant/test/timeseries/test_measures.py test_real_corr', fin_gsq_test_test_real_corr('local_payload').payload || ':' || fin_gsq_test_test_real_corr('local_payload').source_function, 'local_payload:test_real_corr');
SELECT assert_eq('gs quant canonical 0901 gs_quant/test/timeseries/test_measures.py test_real_corr_missing', fin_gsq_test_test_real_corr_missing('local_payload').payload || ':' || fin_gsq_test_test_real_corr_missing('local_payload').source_function, 'local_payload:test_real_corr_missing');
SELECT assert_eq('gs quant canonical 0902 gs_quant/test/timeseries/test_measures.py test_real_corr_n', fin_gsq_test_test_real_corr_n('local_payload').payload || ':' || fin_gsq_test_test_real_corr_n('local_payload').source_function, 'local_payload:test_real_corr_n');
SELECT assert_eq('gs quant canonical 0903 gs_quant/test/timeseries/test_measures.py test_cds_implied_vol', fin_gsq_test_test_cds_implied_vol('local_payload').payload || ':' || fin_gsq_test_test_cds_implied_vol('local_payload').source_function, 'local_payload:test_cds_implied_vol');
SELECT assert_eq('gs quant canonical 0904 gs_quant/test/timeseries/test_measures.py test_implied_vol_credit', fin_gsq_test_test_implied_vol_credit('local_payload').payload || ':' || fin_gsq_test_test_implied_vol_credit('local_payload').source_function, 'local_payload:test_implied_vol_credit');
SELECT assert_eq('gs quant canonical 0905 gs_quant/test/timeseries/test_measures.py test_absolute_strike_credit', fin_gsq_test_test_absolute_strike_credit('local_payload').payload || ':' || fin_gsq_test_test_absolute_strike_credit('local_payload').source_function, 'local_payload:test_absolute_strike_credit');
SELECT assert_eq('gs quant canonical 0906 gs_quant/test/timeseries/test_measures.py test_option_premium_credit', fin_gsq_test_test_option_premium_credit('local_payload').payload || ':' || fin_gsq_test_test_option_premium_credit('local_payload').source_function, 'local_payload:test_option_premium_credit');
SELECT assert_eq('gs quant canonical 0907 gs_quant/test/timeseries/test_measures.py test_cds_spreads', fin_gsq_test_test_cds_spreads('local_payload').payload || ':' || fin_gsq_test_test_cds_spreads('local_payload').source_function, 'local_payload:test_cds_spreads');
SELECT assert_eq('gs quant canonical 0908 gs_quant/test/timeseries/test_measures.py test_avg_impl_vol', fin_gsq_test_test_avg_impl_vol('local_payload').payload || ':' || fin_gsq_test_test_avg_impl_vol('local_payload').source_function, 'local_payload:test_avg_impl_vol');
SELECT assert_eq('gs quant canonical 0909 gs_quant/test/timeseries/test_measures.py test_avg_realized_vol', fin_gsq_test_test_avg_realized_vol('local_payload').payload || ':' || fin_gsq_test_test_avg_realized_vol('local_payload').source_function, 'local_payload:test_avg_realized_vol');
SELECT assert_eq('gs quant canonical 0910 gs_quant/test/timeseries/test_measures.py test_avg_impl_var', fin_gsq_test_test_avg_impl_var('local_payload').payload || ':' || fin_gsq_test_test_avg_impl_var('local_payload').source_function, 'local_payload:test_avg_impl_var');
SELECT assert_eq('gs quant canonical 0911 gs_quant/test/timeseries/test_measures.py test_basis_swap_spread', fin_gsq_test_test_basis_swap_spread('local_payload').payload || ':' || fin_gsq_test_test_basis_swap_spread('local_payload').source_function, 'local_payload:test_basis_swap_spread');
SELECT assert_eq('gs quant canonical 0912 gs_quant/test/timeseries/test_measures.py test_swap_rate', fin_gsq_test_test_swap_rate('local_payload').payload || ':' || fin_gsq_test_test_swap_rate('local_payload').source_function, 'local_payload:test_swap_rate');
SELECT assert_eq('gs quant canonical 0913 gs_quant/test/timeseries/test_measures.py test_swap_annuity', fin_gsq_test_test_swap_annuity('local_payload').payload || ':' || fin_gsq_test_test_swap_annuity('local_payload').source_function, 'local_payload:test_swap_annuity');
SELECT assert_eq('gs quant canonical 0914 gs_quant/test/timeseries/test_measures.py test_swap_term_structure', fin_gsq_test_test_swap_term_structure('local_payload').payload || ':' || fin_gsq_test_test_swap_term_structure('local_payload').source_function, 'local_payload:test_swap_term_structure');
SELECT assert_eq('gs quant canonical 0915 gs_quant/test/timeseries/test_measures.py test_basis_swap_term_structure', fin_gsq_test_test_basis_swap_term_structure('local_payload').payload || ':' || fin_gsq_test_test_basis_swap_term_structure('local_payload').source_function, 'local_payload:test_basis_swap_term_structure');
SELECT assert_eq('gs quant canonical 0916 gs_quant/test/timeseries/test_measures.py test_cap_floor_vol', fin_gsq_test_test_cap_floor_vol('local_payload').payload || ':' || fin_gsq_test_test_cap_floor_vol('local_payload').source_function, 'local_payload:test_cap_floor_vol');
SELECT assert_eq('gs quant canonical 0917 gs_quant/test/timeseries/test_measures.py test_cap_floor_atm_fwd_rate', fin_gsq_test_test_cap_floor_atm_fwd_rate('local_payload').payload || ':' || fin_gsq_test_test_cap_floor_atm_fwd_rate('local_payload').source_function, 'local_payload:test_cap_floor_atm_fwd_rate');
SELECT assert_eq('gs quant canonical 0918 gs_quant/test/timeseries/test_measures.py test_spread_option_vol', fin_gsq_test_test_spread_option_vol('local_payload').payload || ':' || fin_gsq_test_test_spread_option_vol('local_payload').source_function, 'local_payload:test_spread_option_vol');
SELECT assert_eq('gs quant canonical 0919 gs_quant/test/timeseries/test_measures.py test_spread_option_atm_fwd_rate', fin_gsq_test_test_spread_option_atm_fwd_rate('local_payload').payload || ':' || fin_gsq_test_test_spread_option_atm_fwd_rate('local_payload').source_function, 'local_payload:test_spread_option_atm_fwd_rate');
SELECT assert_eq('gs quant canonical 0920 gs_quant/test/timeseries/test_measures.py test_zc_inflation_swap_rate', fin_gsq_test_test_zc_inflation_swap_rate('local_payload').payload || ':' || fin_gsq_test_test_zc_inflation_swap_rate('local_payload').source_function, 'local_payload:test_zc_inflation_swap_rate');
SELECT assert_eq('gs quant canonical 0921 gs_quant/test/timeseries/test_measures.py test_basis', fin_gsq_test_test_basis('local_payload').payload || ':' || fin_gsq_test_test_basis('local_payload').source_function, 'local_payload:test_basis');
SELECT assert_eq('gs quant canonical 0922 gs_quant/test/timeseries/test_measures.py test_td', fin_gsq_test_test_td('local_payload').payload || ':' || fin_gsq_test_test_td('local_payload').source_function, 'local_payload:test_td');
SELECT assert_eq('gs quant canonical 0923 gs_quant/test/timeseries/test_measures.py test_pricing_range', fin_gsq_test_test_pricing_range('local_payload').payload || ':' || fin_gsq_test_test_pricing_range('local_payload').source_function, 'local_payload:test_pricing_range');
SELECT assert_eq('gs quant canonical 0924 gs_quant/test/timeseries/test_measures.py test_var_swap_tenors', fin_gsq_test_test_var_swap_tenors('local_payload').payload || ':' || fin_gsq_test_test_var_swap_tenors('local_payload').source_function, 'local_payload:test_var_swap_tenors');
SELECT assert_eq('gs quant canonical 0925 gs_quant/test/timeseries/test_measures.py test_forward_var_term', fin_gsq_test_test_forward_var_term('local_payload').payload || ':' || fin_gsq_test_test_forward_var_term('local_payload').source_function, 'local_payload:test_forward_var_term');
SELECT assert_eq('gs quant canonical 0926 gs_quant/test/timeseries/test_measures.py test_var_swap', fin_gsq_test_test_var_swap('local_payload').payload || ':' || fin_gsq_test_test_var_swap('local_payload').source_function, 'local_payload:test_var_swap');
SELECT assert_eq('gs quant canonical 0927 gs_quant/test/timeseries/test_measures.py test_var_swap_fwd', fin_gsq_test_test_var_swap_fwd('local_payload').payload || ':' || fin_gsq_test_test_var_swap_fwd('local_payload').source_function, 'local_payload:test_var_swap_fwd');
SELECT assert_eq('gs quant canonical 0928 gs_quant/test/timeseries/test_measures.py test_var_term', fin_gsq_test_test_var_term('local_payload').payload || ':' || fin_gsq_test_test_var_term('local_payload').source_function, 'local_payload:test_var_term');
SELECT assert_eq('gs quant canonical 0929 gs_quant/test/timeseries/test_measures.py test_forward_vol', fin_gsq_test_test_forward_vol('local_payload').payload || ':' || fin_gsq_test_test_forward_vol('local_payload').source_function, 'local_payload:test_forward_vol');
SELECT assert_eq('gs quant canonical 0930 gs_quant/test/timeseries/test_measures.py test_forward_vol_term', fin_gsq_test_test_forward_vol_term('local_payload').payload || ':' || fin_gsq_test_test_forward_vol_term('local_payload').source_function, 'local_payload:test_forward_vol_term');
SELECT assert_eq('gs quant canonical 0931 gs_quant/test/timeseries/test_measures.py test_get_latest_term_structure_data', fin_gsq_test_test_get_latest_term_structure_data('local_payload').payload || ':' || fin_gsq_test_test_get_latest_term_structure_data('local_payload').source_function, 'local_payload:test_get_latest_term_structure_data');
SELECT assert_eq('gs quant canonical 0932 gs_quant/test/timeseries/test_measures.py test_vol_term', fin_gsq_test_test_vol_term('local_payload').payload || ':' || fin_gsq_test_test_vol_term('local_payload').source_function, 'local_payload:test_vol_term');
SELECT assert_eq('gs quant canonical 0933 gs_quant/test/timeseries/test_measures.py test__get_skew_strikes', fin_gsq_test_test_get_skew_strikes('local_payload').payload || ':' || fin_gsq_test_test_get_skew_strikes('local_payload').source_function, 'local_payload:test__get_skew_strikes');
SELECT assert_eq('gs quant canonical 0934 gs_quant/test/timeseries/test_measures.py test__skew', fin_gsq_test_test_skew_test_timeseries_test_measures('local_payload').payload || ':' || fin_gsq_test_test_skew_test_timeseries_test_measures('local_payload').source_function, 'local_payload:test__skew');
SELECT assert_eq('gs quant canonical 0935 gs_quant/test/timeseries/test_measures.py test__skew_term_fetcher', fin_gsq_test_test_skew_term_fetcher('local_payload').payload || ':' || fin_gsq_test_test_skew_term_fetcher('local_payload').source_function, 'local_payload:test__skew_term_fetcher');
SELECT assert_eq('gs quant canonical 0936 gs_quant/test/timeseries/test_measures.py test_skew_term', fin_gsq_test_test_skew_term('local_payload').payload || ':' || fin_gsq_test_test_skew_term('local_payload').source_function, 'local_payload:test_skew_term');
SELECT assert_eq('gs quant canonical 0937 gs_quant/test/timeseries/test_measures.py test_vol_term_fx', fin_gsq_test_test_vol_term_fx('local_payload').payload || ':' || fin_gsq_test_test_vol_term_fx('local_payload').source_function, 'local_payload:test_vol_term_fx');
SELECT assert_eq('gs quant canonical 0938 gs_quant/test/timeseries/test_measures.py test_fwd_term', fin_gsq_test_test_fwd_term('local_payload').payload || ':' || fin_gsq_test_test_fwd_term('local_payload').source_function, 'local_payload:test_fwd_term');
SELECT assert_eq('gs quant canonical 0939 gs_quant/test/timeseries/test_measures.py test_carry_term', fin_gsq_test_test_carry_term('local_payload').payload || ':' || fin_gsq_test_test_carry_term('local_payload').source_function, 'local_payload:test_carry_term');
SELECT assert_eq('gs quant canonical 0940 gs_quant/test/timeseries/test_measures.py test_measure_request_safe', fin_gsq_test_test_measure_request_safe('local_payload').payload || ':' || fin_gsq_test_test_measure_request_safe('local_payload').source_function, 'local_payload:test_measure_request_safe');
SELECT assert_eq('gs quant canonical 0941 gs_quant/test/timeseries/test_measures.py test_bucketize_price', fin_gsq_test_test_bucketize_price('local_payload').payload || ':' || fin_gsq_test_test_bucketize_price('local_payload').source_function, 'local_payload:test_bucketize_price');
SELECT assert_eq('gs quant canonical 0942 gs_quant/test/timeseries/test_measures.py test_forward_price', fin_gsq_test_test_forward_price_test_timeseries_test_measures('local_payload').payload || ':' || fin_gsq_test_test_forward_price_test_timeseries_test_measures('local_payload').source_function, 'local_payload:test_forward_price');
SELECT assert_eq('gs quant canonical 0943 gs_quant/test/timeseries/test_measures.py test_implied_volatility_elec', fin_gsq_test_test_implied_volatility_elec('local_payload').payload || ':' || fin_gsq_test_test_implied_volatility_elec('local_payload').source_function, 'local_payload:test_implied_volatility_elec');
SELECT assert_eq('gs quant canonical 0944 gs_quant/test/timeseries/test_measures.py test_forward_price_ng', fin_gsq_test_test_forward_price_ng('local_payload').payload || ':' || fin_gsq_test_test_forward_price_ng('local_payload').source_function, 'local_payload:test_forward_price_ng');
SELECT assert_eq('gs quant canonical 0945 gs_quant/test/timeseries/test_measures.py test_implied_volatility_ng', fin_gsq_test_test_implied_volatility_ng('local_payload').payload || ':' || fin_gsq_test_test_implied_volatility_ng('local_payload').source_function, 'local_payload:test_implied_volatility_ng');
SELECT assert_eq('gs quant canonical 0946 gs_quant/test/timeseries/test_measures.py test_get_iso_data', fin_gsq_test_test_get_iso_data('local_payload').payload || ':' || fin_gsq_test_test_get_iso_data('local_payload').source_function, 'local_payload:test_get_iso_data');
SELECT assert_eq('gs quant canonical 0947 gs_quant/test/timeseries/test_measures.py test_string_to_date_interval', fin_gsq_test_test_string_to_date_interval('local_payload').payload || ':' || fin_gsq_test_test_string_to_date_interval('local_payload').source_function, 'local_payload:test_string_to_date_interval');
SELECT assert_eq('gs quant canonical 0948 gs_quant/test/timeseries/test_measures.py test_implied_vol_commod', fin_gsq_test_test_implied_vol_commod('local_payload').payload || ':' || fin_gsq_test_test_implied_vol_commod('local_payload').source_function, 'local_payload:test_implied_vol_commod');
SELECT assert_eq('gs quant canonical 0949 gs_quant/test/timeseries/test_measures.py test_fair_price', fin_gsq_test_test_fair_price('local_payload').payload || ':' || fin_gsq_test_test_fair_price('local_payload').source_function, 'local_payload:test_fair_price');
SELECT assert_eq('gs quant canonical 0950 gs_quant/test/timeseries/test_measures.py test_weighted_average_valuation_curve_for_calendar_strip', fin_gsq_test_test_weighted_average_valuation_curve_for_calendar_strip('local_payload').payload || ':' || fin_gsq_test_test_weighted_average_valuation_curve_for_calendar_strip('local_payload').source_function, 'local_payload:test_weighted_average_valuation_curve_for_calendar_strip');
SELECT assert_eq('gs quant canonical 0951 gs_quant/test/timeseries/test_measures.py test_fundamental_metrics', fin_gsq_test_test_fundamental_metrics('local_payload').payload || ':' || fin_gsq_test_test_fundamental_metrics('local_payload').source_function, 'local_payload:test_fundamental_metrics');
SELECT assert_eq('gs quant canonical 0952 gs_quant/test/timeseries/test_measures.py test_realized_volatility', fin_gsq_test_test_realized_volatility('local_payload').payload || ':' || fin_gsq_test_test_realized_volatility('local_payload').source_function, 'local_payload:test_realized_volatility');
SELECT assert_eq('gs quant canonical 0953 gs_quant/test/timeseries/test_measures.py test_esg_headline_metric', fin_gsq_test_test_esg_headline_metric('local_payload').payload || ':' || fin_gsq_test_test_esg_headline_metric('local_payload').source_function, 'local_payload:test_esg_headline_metric');
SELECT assert_eq('gs quant canonical 0954 gs_quant/test/timeseries/test_measures.py test_rating', fin_gsq_test_test_rating('local_payload').payload || ':' || fin_gsq_test_test_rating('local_payload').source_function, 'local_payload:test_rating');
SELECT assert_eq('gs quant canonical 0955 gs_quant/test/timeseries/test_measures.py test_fair_value', fin_gsq_test_test_fair_value('local_payload').payload || ':' || fin_gsq_test_test_fair_value('local_payload').source_function, 'local_payload:test_fair_value');
SELECT assert_eq('gs quant canonical 0956 gs_quant/test/timeseries/test_measures.py test_factor_profile', fin_gsq_test_test_factor_profile('local_payload').payload || ':' || fin_gsq_test_test_factor_profile('local_payload').source_function, 'local_payload:test_factor_profile');
SELECT assert_eq('gs quant canonical 0957 gs_quant/test/timeseries/test_measures.py test_commodity_forecast', fin_gsq_test_test_commodity_forecast('local_payload').payload || ':' || fin_gsq_test_test_commodity_forecast('local_payload').source_function, 'local_payload:test_commodity_forecast');
SELECT assert_eq('gs quant canonical 0958 gs_quant/test/timeseries/test_measures.py test_commodity_forecast_time_series', fin_gsq_test_test_commodity_forecast_time_series('local_payload').payload || ':' || fin_gsq_test_test_commodity_forecast_time_series('local_payload').source_function, 'local_payload:test_commodity_forecast_time_series');
SELECT assert_eq('gs quant canonical 0959 gs_quant/test/timeseries/test_measures.py test_fx_implied_correlation', fin_gsq_test_test_fx_implied_correlation('local_payload').payload || ':' || fin_gsq_test_test_fx_implied_correlation('local_payload').source_function, 'local_payload:test_fx_implied_correlation');
SELECT assert_eq('gs quant canonical 0960 gs_quant/test/timeseries/test_measures.py mock_forward_curve_peak', fin_gsq_test_mock_forward_curve_peak('local_payload').payload || ':' || fin_gsq_test_mock_forward_curve_peak('local_payload').source_function, 'local_payload:mock_forward_curve_peak');
SELECT assert_eq('gs quant canonical 0961 gs_quant/test/timeseries/test_measures.py mock_forward_curve_peak_holiday', fin_gsq_test_mock_forward_curve_peak_holiday('local_payload').payload || ':' || fin_gsq_test_mock_forward_curve_peak_holiday('local_payload').source_function, 'local_payload:mock_forward_curve_peak_holiday');
SELECT assert_eq('gs quant canonical 0962 gs_quant/test/timeseries/test_measures.py mock_forward_curve_offpeak', fin_gsq_test_mock_forward_curve_offpeak('local_payload').payload || ':' || fin_gsq_test_mock_forward_curve_offpeak('local_payload').source_function, 'local_payload:mock_forward_curve_offpeak');
SELECT assert_eq('gs quant canonical 0963 gs_quant/test/timeseries/test_measures.py mock_empty_forward_curve', fin_gsq_test_mock_empty_forward_curve('local_payload').payload || ':' || fin_gsq_test_mock_empty_forward_curve('local_payload').source_function, 'local_payload:mock_empty_forward_curve');
SELECT assert_eq('gs quant canonical 0964 gs_quant/test/timeseries/test_measures.py test_forward_curve', fin_gsq_test_test_forward_curve('local_payload').payload || ':' || fin_gsq_test_test_forward_curve('local_payload').source_function, 'local_payload:test_forward_curve');
SELECT assert_eq('gs quant canonical 0965 gs_quant/test/timeseries/test_measures.py mock_us_gas_forward_curve', fin_gsq_test_mock_us_gas_forward_curve('local_payload').payload || ':' || fin_gsq_test_mock_us_gas_forward_curve('local_payload').source_function, 'local_payload:mock_us_gas_forward_curve');
SELECT assert_eq('gs quant canonical 0966 gs_quant/test/timeseries/test_measures.py test_us_gas_forward_curve', fin_gsq_test_test_us_gas_forward_curve('local_payload').payload || ':' || fin_gsq_test_test_us_gas_forward_curve('local_payload').source_function, 'local_payload:test_us_gas_forward_curve');
SELECT assert_eq('gs quant canonical 0967 gs_quant/test/timeseries/test_measures.py test_eu_ng_hub_to_swap', fin_gsq_test_test_eu_ng_hub_to_swap('local_payload').payload || ':' || fin_gsq_test_test_eu_ng_hub_to_swap('local_payload').source_function, 'local_payload:test_eu_ng_hub_to_swap');
SELECT assert_eq('gs quant canonical 0968 gs_quant/test/timeseries/test_measures.py test_settlement_price', fin_gsq_test_test_settlement_price('local_payload').payload || ':' || fin_gsq_test_test_settlement_price('local_payload').source_function, 'local_payload:test_settlement_price');
SELECT assert_eq('gs quant canonical 0969 gs_quant/test/timeseries/test_measures.py test_hloc_prices', fin_gsq_test_test_hloc_prices('local_payload').payload || ':' || fin_gsq_test_test_hloc_prices('local_payload').source_function, 'local_payload:test_hloc_prices');
SELECT assert_eq('gs quant canonical 0970 gs_quant/test/timeseries/test_measures.py test_thematic_model_exposure', fin_gsq_test_test_thematic_model_exposure('local_payload').payload || ':' || fin_gsq_test_test_thematic_model_exposure('local_payload').source_function, 'local_payload:test_thematic_model_exposure');
SELECT assert_eq('gs quant canonical 0971 gs_quant/test/timeseries/test_measures.py test_thematic_model_beta', fin_gsq_test_test_thematic_model_beta('local_payload').payload || ':' || fin_gsq_test_test_thematic_model_beta('local_payload').source_function, 'local_payload:test_thematic_model_beta');
SELECT assert_eq('gs quant canonical 0972 gs_quant/test/timeseries/test_measures.py test_thematic_model_beta_single_stock', fin_gsq_test_test_thematic_model_beta_single_stock('local_payload').payload || ':' || fin_gsq_test_test_thematic_model_beta_single_stock('local_payload').source_function, 'local_payload:test_thematic_model_beta_single_stock');
SELECT assert_eq('gs quant canonical 0973 gs_quant/test/timeseries/test_measures.py test_retail_interest_agg', fin_gsq_test_test_retail_interest_agg('local_payload').payload || ':' || fin_gsq_test_test_retail_interest_agg('local_payload').source_function, 'local_payload:test_retail_interest_agg');
SELECT assert_eq('gs quant canonical 0974 gs_quant/test/timeseries/test_measures.py test_s3_long_short_concentration', fin_gsq_test_test_s3_long_short_concentration('local_payload').payload || ':' || fin_gsq_test_test_s3_long_short_concentration('local_payload').source_function, 'local_payload:test_s3_long_short_concentration');
SELECT assert_eq('gs quant canonical 0975 gs_quant/test/timeseries/test_measures_countries.py test_fci', fin_gsq_test_test_fci('local_payload').payload || ':' || fin_gsq_test_test_fci('local_payload').source_function, 'local_payload:test_fci');
SELECT assert_eq('gs quant canonical 0976 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_af', fin_gsq_test_mock_fe_estimate_af('local_payload').payload || ':' || fin_gsq_test_mock_fe_estimate_af('local_payload').source_function, 'local_payload:mock_fe_estimate_af');
SELECT assert_eq('gs quant canonical 0977 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_qf', fin_gsq_test_mock_fe_estimate_qf('local_payload').payload || ':' || fin_gsq_test_mock_fe_estimate_qf('local_payload').source_function, 'local_payload:mock_fe_estimate_qf');
SELECT assert_eq('gs quant canonical 0978 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_saf', fin_gsq_test_mock_fe_estimate_saf('local_payload').payload || ':' || fin_gsq_test_mock_fe_estimate_saf('local_payload').source_function, 'local_payload:mock_fe_estimate_saf');
SELECT assert_eq('gs quant canonical 0979 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_ntm', fin_gsq_test_mock_fe_estimate_ntm('local_payload').payload || ':' || fin_gsq_test_mock_fe_estimate_ntm('local_payload').source_function, 'local_payload:mock_fe_estimate_ntm');
SELECT assert_eq('gs quant canonical 0980 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_lt', fin_gsq_test_mock_fe_estimate_lt('local_payload').payload || ':' || fin_gsq_test_mock_fe_estimate_lt('local_payload').source_function, 'local_payload:mock_fe_estimate_lt');
SELECT assert_eq('gs quant canonical 0981 gs_quant/test/timeseries/test_measures_factset.py mock_fe_actual', fin_gsq_test_mock_fe_actual('local_payload').payload || ':' || fin_gsq_test_mock_fe_actual('local_payload').source_function, 'local_payload:mock_fe_actual');
SELECT assert_eq('gs quant canonical 0982 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_empty', fin_gsq_test_mock_fe_estimate_empty('local_payload').payload || ':' || fin_gsq_test_mock_fe_estimate_empty('local_payload').source_function, 'local_payload:mock_fe_estimate_empty');
SELECT assert_eq('gs quant canonical 0983 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_empty', fin_gsq_test_mock_factset_fundamentals_empty('local_payload').payload || ':' || fin_gsq_test_mock_factset_fundamentals_empty('local_payload').source_function, 'local_payload:mock_factset_fundamentals_empty');
SELECT assert_eq('gs quant canonical 0984 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_basic', fin_gsq_test_mock_factset_fundamentals_basic('local_payload').payload || ':' || fin_gsq_test_mock_factset_fundamentals_basic('local_payload').source_function, 'local_payload:mock_factset_fundamentals_basic');
SELECT assert_eq('gs quant canonical 0985 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_basic_derived', fin_gsq_test_mock_factset_fundamentals_basic_derived('local_payload').payload || ':' || fin_gsq_test_mock_factset_fundamentals_basic_derived('local_payload').source_function, 'local_payload:mock_factset_fundamentals_basic_derived');
SELECT assert_eq('gs quant canonical 0986 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_basic_restated', fin_gsq_test_mock_factset_fundamentals_basic_restated('local_payload').payload || ':' || fin_gsq_test_mock_factset_fundamentals_basic_restated('local_payload').source_function, 'local_payload:mock_factset_fundamentals_basic_restated');
SELECT assert_eq('gs quant canonical 0987 gs_quant/test/timeseries/test_measures_factset.py mock_factset_ratings', fin_gsq_test_mock_factset_ratings('local_payload').payload || ':' || fin_gsq_test_mock_factset_ratings('local_payload').source_function, 'local_payload:mock_factset_ratings');
SELECT assert_eq('gs quant canonical 0988 gs_quant/test/timeseries/test_measures_factset.py test_factset_estimates', fin_gsq_test_test_factset_estimates('local_payload').payload || ':' || fin_gsq_test_test_factset_estimates('local_payload').source_function, 'local_payload:test_factset_estimates');
SELECT assert_eq('gs quant canonical 0989 gs_quant/test/timeseries/test_measures_factset.py test_factset_fundamentals', fin_gsq_test_test_factset_fundamentals('local_payload').payload || ':' || fin_gsq_test_test_factset_fundamentals('local_payload').source_function, 'local_payload:test_factset_fundamentals');
SELECT assert_eq('gs quant canonical 0990 gs_quant/test/timeseries/test_measures_factset.py test_factset_ratings', fin_gsq_test_test_factset_ratings('local_payload').payload || ':' || fin_gsq_test_test_factset_ratings('local_payload').source_function, 'local_payload:test_factset_ratings');
SELECT assert_eq('gs quant canonical 0991 gs_quant/test/timeseries/test_measures_factset.py test_fiscal_period', fin_gsq_test_test_fiscal_period('local_payload').payload || ':' || fin_gsq_test_test_fiscal_period('local_payload').source_function, 'local_payload:test_fiscal_period');
SELECT assert_eq('gs quant canonical 0992 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_invalid_basis', fin_gsq_test_test_gir_estimates_invalid_basis('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_invalid_basis('local_payload').source_function, 'local_payload:test_gir_estimates_invalid_basis');
SELECT assert_eq('gs quant canonical 0993 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_invalid_period_type', fin_gsq_test_test_gir_estimates_invalid_period_type('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_invalid_period_type('local_payload').source_function, 'local_payload:test_gir_estimates_invalid_period_type');
SELECT assert_eq('gs quant canonical 0994 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_fiscal_period_no_year', fin_gsq_test_test_gir_estimates_fiscal_period_no_year('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_fiscal_period_no_year('local_payload').source_function, 'local_payload:test_gir_estimates_fiscal_period_no_year');
SELECT assert_eq('gs quant canonical 0995 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_qtr_fiscal_period_no_quarter', fin_gsq_test_test_gir_estimates_qtr_fiscal_period_no_quarter('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_qtr_fiscal_period_no_quarter('local_payload').source_function, 'local_payload:test_gir_estimates_qtr_fiscal_period_no_quarter');
SELECT assert_eq('gs quant canonical 0996 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_qtr_fiscal_period_invalid_quarter', fin_gsq_test_test_gir_estimates_qtr_fiscal_period_invalid_quarter('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_qtr_fiscal_period_invalid_quarter('local_payload').source_function, 'local_payload:test_gir_estimates_qtr_fiscal_period_invalid_quarter');
SELECT assert_eq('gs quant canonical 0997 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_no_bbid', fin_gsq_test_test_gir_estimates_no_bbid('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_no_bbid('local_payload').source_function, 'local_payload:test_gir_estimates_no_bbid');
SELECT assert_eq('gs quant canonical 0998 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_rolling_annual', fin_gsq_test_test_gir_estimates_rolling_annual('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_rolling_annual('local_payload').source_function, 'local_payload:test_gir_estimates_rolling_annual');
SELECT assert_eq('gs quant canonical 0999 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_rolling_quarterly', fin_gsq_test_test_gir_estimates_rolling_quarterly('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_rolling_quarterly('local_payload').source_function, 'local_payload:test_gir_estimates_rolling_quarterly');
SELECT assert_eq('gs quant canonical 1000 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_fixed_annual', fin_gsq_test_test_gir_estimates_fixed_annual('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_fixed_annual('local_payload').source_function, 'local_payload:test_gir_estimates_fixed_annual');
SELECT assert_eq('gs quant canonical 1001 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_fixed_quarterly', fin_gsq_test_test_gir_estimates_fixed_quarterly('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_fixed_quarterly('local_payload').source_function, 'local_payload:test_gir_estimates_fixed_quarterly');
SELECT assert_eq('gs quant canonical 1002 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_empty_response', fin_gsq_test_test_gir_estimates_empty_response('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_empty_response('local_payload').source_function, 'local_payload:test_gir_estimates_empty_response');
SELECT assert_eq('gs quant canonical 1003 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_null_numeric', fin_gsq_test_test_gir_estimates_null_numeric('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_null_numeric('local_payload').source_function, 'local_payload:test_gir_estimates_null_numeric');
SELECT assert_eq('gs quant canonical 1004 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_null_numeric_fixed_period', fin_gsq_test_test_gir_estimates_null_numeric_fixed_period('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_null_numeric_fixed_period('local_payload').source_function, 'local_payload:test_gir_estimates_null_numeric_fixed_period');
SELECT assert_eq('gs quant canonical 1005 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_empty_response_fixed_period', fin_gsq_test_test_gir_estimates_empty_response_fixed_period('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_empty_response_fixed_period('local_payload').source_function, 'local_payload:test_gir_estimates_empty_response_fixed_period');
SELECT assert_eq('gs quant canonical 1006 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_threadpool_exception', fin_gsq_test_test_gir_estimates_threadpool_exception('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_threadpool_exception('local_payload').source_function, 'local_payload:test_gir_estimates_threadpool_exception');
SELECT assert_eq('gs quant canonical 1007 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_threadpool_exception_fixed', fin_gsq_test_test_gir_estimates_threadpool_exception_fixed('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_threadpool_exception_fixed('local_payload').source_function, 'local_payload:test_gir_estimates_threadpool_exception_fixed');
SELECT assert_eq('gs quant canonical 1008 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_no_data_within_period', fin_gsq_test_test_gir_estimates_no_data_within_period('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_no_data_within_period('local_payload').source_function, 'local_payload:test_gir_estimates_no_data_within_period');
SELECT assert_eq('gs quant canonical 1009 gs_quant/test/timeseries/test_measures_factset.py test_build_query_args_with_start_end_override', fin_gsq_test_test_build_query_args_with_start_end_override('local_payload').payload || ':' || fin_gsq_test_test_build_query_args_with_start_end_override('local_payload').source_function, 'local_payload:test_build_query_args_with_start_end_override');
SELECT assert_eq('gs quant canonical 1010 gs_quant/test/timeseries/test_measures_factset.py test_build_query_args_rolling_annual', fin_gsq_test_test_build_query_args_rolling_annual('local_payload').payload || ':' || fin_gsq_test_test_build_query_args_rolling_annual('local_payload').source_function, 'local_payload:test_build_query_args_rolling_annual');
SELECT assert_eq('gs quant canonical 1011 gs_quant/test/timeseries/test_measures_factset.py test_build_query_args_rolling_quarterly', fin_gsq_test_test_build_query_args_rolling_quarterly('local_payload').payload || ':' || fin_gsq_test_test_build_query_args_rolling_quarterly('local_payload').source_function, 'local_payload:test_build_query_args_rolling_quarterly');
SELECT assert_eq('gs quant canonical 1012 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_empty_df', fin_gsq_test_test_extract_value_empty_df('local_payload').payload || ':' || fin_gsq_test_test_extract_value_empty_df('local_payload').source_function, 'local_payload:test_extract_value_empty_df');
SELECT assert_eq('gs quant canonical 1013 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_all_null_metric', fin_gsq_test_test_extract_value_all_null_metric('local_payload').payload || ':' || fin_gsq_test_test_extract_value_all_null_metric('local_payload').source_function, 'local_payload:test_extract_value_all_null_metric');
SELECT assert_eq('gs quant canonical 1014 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_with_int_period_no_matching_date', fin_gsq_test_test_extract_value_with_int_period_no_matching_date('local_payload').payload || ':' || fin_gsq_test_test_extract_value_with_int_period_no_matching_date('local_payload').source_function, 'local_payload:test_extract_value_with_int_period_no_matching_date');
SELECT assert_eq('gs quant canonical 1015 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_with_int_period_quarterly', fin_gsq_test_test_extract_value_with_int_period_quarterly('local_payload').payload || ':' || fin_gsq_test_test_extract_value_with_int_period_quarterly('local_payload').source_function, 'local_payload:test_extract_value_with_int_period_quarterly');
SELECT assert_eq('gs quant canonical 1016 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_with_int_period_returns_first_sorted', fin_gsq_test_test_extract_value_with_int_period_returns_first_sorted('local_payload').payload || ':' || fin_gsq_test_test_extract_value_with_int_period_returns_first_sorted('local_payload').source_function, 'local_payload:test_extract_value_with_int_period_returns_first_sorted');
SELECT assert_eq('gs quant canonical 1017 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_non_int_period', fin_gsq_test_test_extract_value_non_int_period('local_payload').payload || ':' || fin_gsq_test_test_extract_value_non_int_period('local_payload').source_function, 'local_payload:test_extract_value_non_int_period');
SELECT assert_eq('gs quant canonical 1018 gs_quant/test/timeseries/test_measures_factset.py test_query_single_date', fin_gsq_test_test_query_single_date('local_payload').payload || ':' || fin_gsq_test_test_query_single_date('local_payload').source_function, 'local_payload:test_query_single_date');
SELECT assert_eq('gs quant canonical 1019 gs_quant/test/timeseries/test_measures_factset.py test_query_dates_parallel', fin_gsq_test_test_query_dates_parallel('local_payload').payload || ':' || fin_gsq_test_test_query_dates_parallel('local_payload').source_function, 'local_payload:test_query_dates_parallel');
SELECT assert_eq('gs quant canonical 1020 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_scaled_metric', fin_gsq_test_test_gir_estimates_scaled_metric('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_scaled_metric('local_payload').source_function, 'local_payload:test_gir_estimates_scaled_metric');
SELECT assert_eq('gs quant canonical 1021 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_end_date_appended', fin_gsq_test_test_gir_estimates_end_date_appended('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_end_date_appended('local_payload').source_function, 'local_payload:test_gir_estimates_end_date_appended');
SELECT assert_eq('gs quant canonical 1022 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_weekly_and_daily_drill_down', fin_gsq_test_test_gir_estimates_weekly_and_daily_drill_down('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_weekly_and_daily_drill_down('local_payload').source_function, 'local_payload:test_gir_estimates_weekly_and_daily_drill_down');
SELECT assert_eq('gs quant canonical 1023 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_weekly_drill_exception', fin_gsq_test_test_gir_estimates_weekly_drill_exception('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_weekly_drill_exception('local_payload').source_function, 'local_payload:test_gir_estimates_weekly_drill_exception');
SELECT assert_eq('gs quant canonical 1024 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_daily_drill_exception', fin_gsq_test_test_gir_estimates_daily_drill_exception('local_payload').payload || ':' || fin_gsq_test_test_gir_estimates_daily_drill_exception('local_payload').source_function, 'local_payload:test_gir_estimates_daily_drill_exception');
SELECT assert_eq('gs quant canonical 1025 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_invalid_metric', fin_gsq_test_test_factset_ev_invalid_metric('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_invalid_metric('local_payload').source_function, 'local_payload:test_factset_ev_invalid_metric');
SELECT assert_eq('gs quant canonical 1026 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_no_bbid', fin_gsq_test_test_factset_ev_no_bbid('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_no_bbid('local_payload').source_function, 'local_payload:test_factset_ev_no_bbid');
SELECT assert_eq('gs quant canonical 1027 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_no_bcid', fin_gsq_test_test_factset_ev_no_bcid('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_no_bcid('local_payload').source_function, 'local_payload:test_factset_ev_no_bcid');
SELECT assert_eq('gs quant canonical 1028 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_empty_capital_structure', fin_gsq_test_test_factset_ev_empty_capital_structure('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_empty_capital_structure('local_payload').source_function, 'local_payload:test_factset_ev_empty_capital_structure');
SELECT assert_eq('gs quant canonical 1029 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_success_with_lease', fin_gsq_test_test_factset_ev_success_with_lease('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_success_with_lease('local_payload').source_function, 'local_payload:test_factset_ev_success_with_lease');
SELECT assert_eq('gs quant canonical 1030 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_success_no_lease', fin_gsq_test_test_factset_ev_success_no_lease('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_success_no_lease('local_payload').source_function, 'local_payload:test_factset_ev_success_no_lease');
SELECT assert_eq('gs quant canonical 1031 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_negative_pension', fin_gsq_test_test_factset_ev_negative_pension('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_negative_pension('local_payload').source_function, 'local_payload:test_factset_ev_negative_pension');
SELECT assert_eq('gs quant canonical 1032 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_market_cap_metric', fin_gsq_test_test_factset_ev_market_cap_metric('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_market_cap_metric('local_payload').source_function, 'local_payload:test_factset_ev_market_cap_metric');
SELECT assert_eq('gs quant canonical 1033 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_capital_structure_exception', fin_gsq_test_test_factset_ev_capital_structure_exception('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_capital_structure_exception('local_payload').source_function, 'local_payload:test_factset_ev_capital_structure_exception');
SELECT assert_eq('gs quant canonical 1034 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_fundamentals_exception', fin_gsq_test_test_factset_ev_fundamentals_exception('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_fundamentals_exception('local_payload').source_function, 'local_payload:test_factset_ev_fundamentals_exception');
SELECT assert_eq('gs quant canonical 1035 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_no_lease_column', fin_gsq_test_test_factset_ev_no_lease_column('local_payload').payload || ':' || fin_gsq_test_test_factset_ev_no_lease_column('local_payload').source_function, 'local_payload:test_factset_ev_no_lease_column');
SELECT assert_eq('gs quant canonical 1036 gs_quant/test/timeseries/test_measures_fx_vol.py test_currencypair_to_tdapi_fxfwd_asset', fin_gsq_test_test_currencypair_to_tdapi_fxfwd_asset('local_payload').payload || ':' || fin_gsq_test_test_currencypair_to_tdapi_fxfwd_asset('local_payload').source_function, 'local_payload:test_currencypair_to_tdapi_fxfwd_asset');
SELECT assert_eq('gs quant canonical 1037 gs_quant/test/timeseries/test_measures_fx_vol.py test_currencypair_to_tdapi_fxo_asset', fin_gsq_test_test_currencypair_to_tdapi_fxo_asset('local_payload').payload || ':' || fin_gsq_test_test_currencypair_to_tdapi_fxo_asset('local_payload').source_function, 'local_payload:test_currencypair_to_tdapi_fxo_asset');
SELECT assert_eq('gs quant canonical 1038 gs_quant/test/timeseries/test_measures_fx_vol.py test_get_fxo_defaults', fin_gsq_test_test_get_fxo_defaults('local_payload').payload || ':' || fin_gsq_test_test_get_fxo_defaults('local_payload').source_function, 'local_payload:test_get_fxo_defaults');
SELECT assert_eq('gs quant canonical 1039 gs_quant/test/timeseries/test_measures_fx_vol.py test_get_fxo_csa_terms', fin_gsq_test_test_get_fxo_csa_terms('local_payload').payload || ':' || fin_gsq_test_test_get_fxo_csa_terms('local_payload').source_function, 'local_payload:test_get_fxo_csa_terms');
SELECT assert_eq('gs quant canonical 1040 gs_quant/test/timeseries/test_measures_fx_vol.py test_check_valid_indices', fin_gsq_test_test_check_valid_indices('local_payload').payload || ':' || fin_gsq_test_test_check_valid_indices('local_payload').source_function, 'local_payload:test_check_valid_indices');
SELECT assert_eq('gs quant canonical 1041 gs_quant/test/timeseries/test_measures_fx_vol.py test_cross_stored_direction_for_fx_vol', fin_gsq_test_test_cross_stored_direction_for_fx_vol_test_timeseries_test_measures_fx_vol('local_payload').payload || ':' || fin_gsq_test_test_cross_stored_direction_for_fx_vol_test_timeseries_test_measures_fx_vol('local_payload').source_function, 'local_payload:test_cross_stored_direction_for_fx_vol');
SELECT assert_eq('gs quant canonical 1042 gs_quant/test/timeseries/test_measures_fx_vol.py test_get_tdapi_fxo_assets', fin_gsq_test_test_get_tdapi_fxo_assets('local_payload').payload || ':' || fin_gsq_test_test_get_tdapi_fxo_assets('local_payload').source_function, 'local_payload:test_get_tdapi_fxo_assets');
SELECT assert_eq('gs quant canonical 1043 gs_quant/test/timeseries/test_measures_fx_vol.py mock_curr', fin_gsq_test_mock_curr_test_timeseries_test_measures_fx_vol('local_payload').payload || ':' || fin_gsq_test_mock_curr_test_timeseries_test_measures_fx_vol('local_payload').source_function, 'local_payload:mock_curr');
SELECT assert_eq('gs quant canonical 1044 gs_quant/test/timeseries/test_measures_fx_vol.py mock_fx_spot_carry_3m', fin_gsq_test_mock_fx_spot_carry_3m('local_payload').payload || ':' || fin_gsq_test_mock_fx_spot_carry_3m('local_payload').source_function, 'local_payload:mock_fx_spot_carry_3m');
SELECT assert_eq('gs quant canonical 1045 gs_quant/test/timeseries/test_measures_fx_vol.py mock_fx_spot_carry_2y', fin_gsq_test_mock_fx_spot_carry_2y('local_payload').payload || ':' || fin_gsq_test_mock_fx_spot_carry_2y('local_payload').source_function, 'local_payload:mock_fx_spot_carry_2y');
SELECT assert_eq('gs quant canonical 1046 gs_quant/test/timeseries/test_measures_fx_vol.py test_fx_vol_measure', fin_gsq_test_test_fx_vol_measure('local_payload').payload || ':' || fin_gsq_test_test_fx_vol_measure('local_payload').source_function, 'local_payload:test_fx_vol_measure');
SELECT assert_eq('gs quant canonical 1047 gs_quant/test/timeseries/test_measures_fx_vol.py test_fwd_points', fin_gsq_test_test_fwd_points('local_payload').payload || ':' || fin_gsq_test_test_fwd_points('local_payload').source_function, 'local_payload:test_fwd_points');
SELECT assert_eq('gs quant canonical 1048 gs_quant/test/timeseries/test_measures_fx_vol.py mock_df', fin_gsq_test_mock_df('local_payload').payload || ':' || fin_gsq_test_mock_df('local_payload').source_function, 'local_payload:mock_df');
SELECT assert_eq('gs quant canonical 1049 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_raises_exception', fin_gsq_test_test_vol_swap_strike_raises_exception('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_strike_raises_exception('local_payload').source_function, 'local_payload:test_vol_swap_strike_raises_exception');
SELECT assert_eq('gs quant canonical 1050 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_unsupported_cross', fin_gsq_test_test_vol_swap_strike_unsupported_cross('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_strike_unsupported_cross('local_payload').source_function, 'local_payload:test_vol_swap_strike_unsupported_cross');
SELECT assert_eq('gs quant canonical 1051 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_matches_multiple_assets', fin_gsq_test_test_vol_swap_strike_matches_multiple_assets('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_strike_matches_multiple_assets('local_payload').source_function, 'local_payload:test_vol_swap_strike_matches_multiple_assets');
SELECT assert_eq('gs quant canonical 1052 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_matches_no_assets', fin_gsq_test_test_vol_swap_strike_matches_no_assets('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_strike_matches_no_assets('local_payload').source_function, 'local_payload:test_vol_swap_strike_matches_no_assets');
SELECT assert_eq('gs quant canonical 1053 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none', fin_gsq_test_test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none('local_payload').source_function, 'local_payload:test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none');
SELECT assert_eq('gs quant canonical 1054 gs_quant/test/timeseries/test_measures_fx_vol.py test_currencypair_to_tdapi_fx_vol_swap_asset', fin_gsq_test_test_currencypair_to_tdapi_fx_vol_swap_asset('local_payload').payload || ':' || fin_gsq_test_test_currencypair_to_tdapi_fx_vol_swap_asset('local_payload').source_function, 'local_payload:test_currencypair_to_tdapi_fx_vol_swap_asset');
SELECT assert_eq('gs quant canonical 1055 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike', fin_gsq_test_test_vol_swap_strike('local_payload').payload || ':' || fin_gsq_test_test_vol_swap_strike('local_payload').source_function, 'local_payload:test_vol_swap_strike');
SELECT assert_eq('gs quant canonical 1056 gs_quant/test/timeseries/test_measures_fx_vol.py test_implied_volatility_fxvol', fin_gsq_test_test_implied_volatility_fxvol('local_payload').payload || ':' || fin_gsq_test_test_implied_volatility_fxvol('local_payload').source_function, 'local_payload:test_implied_volatility_fxvol');
SELECT assert_eq('gs quant canonical 1057 gs_quant/test/timeseries/test_measures_fx_vol.py test_spot_carry', fin_gsq_test_test_spot_carry('local_payload').payload || ':' || fin_gsq_test_test_spot_carry('local_payload').source_function, 'local_payload:test_spot_carry');
SELECT assert_eq('gs quant canonical 1058 gs_quant/test/timeseries/test_measures_inflation.py test_get_floating_rate_option_for_benchmark_retuns_rate', fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate('local_payload').payload || ':' || fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate('local_payload').source_function, 'local_payload:test_get_floating_rate_option_for_benchmark_retuns_rate');
SELECT assert_eq('gs quant canonical 1059 gs_quant/test/timeseries/test_measures_inflation.py test_get_floating_rate_option_for_benchmark_retuns_rate_usd', fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd('local_payload').payload || ':' || fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd('local_payload').source_function, 'local_payload:test_get_floating_rate_option_for_benchmark_retuns_rate_usd');
SELECT assert_eq('gs quant canonical 1060 gs_quant/test/timeseries/test_measures_inflation.py test_currency_to_tdapi_inflation_swap_rate_asset', fin_gsq_test_test_currency_to_tdapi_inflation_swap_rate_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_inflation_swap_rate_asset('local_payload').source_function, 'local_payload:test_currency_to_tdapi_inflation_swap_rate_asset');
SELECT assert_eq('gs quant canonical 1061 gs_quant/test/timeseries/test_measures_inflation.py test_get_inflation_swap_leg_defaults', fin_gsq_test_test_get_inflation_swap_leg_defaults('local_payload').payload || ':' || fin_gsq_test_test_get_inflation_swap_leg_defaults('local_payload').source_function, 'local_payload:test_get_inflation_swap_leg_defaults');
SELECT assert_eq('gs quant canonical 1062 gs_quant/test/timeseries/test_measures_inflation.py test_get_inflation_swap_csa_terms', fin_gsq_test_test_get_inflation_swap_csa_terms('local_payload').payload || ':' || fin_gsq_test_test_get_inflation_swap_csa_terms('local_payload').source_function, 'local_payload:test_get_inflation_swap_csa_terms');
SELECT assert_eq('gs quant canonical 1063 gs_quant/test/timeseries/test_measures_inflation.py test_check_valid_indices', fin_gsq_test_test_check_valid_indices_test_timeseries_test_meas_19b98b8bc0('local_payload').payload || ':' || fin_gsq_test_test_check_valid_indices_test_timeseries_test_meas_19b98b8bc0('local_payload').source_function, 'local_payload:test_check_valid_indices');
SELECT assert_eq('gs quant canonical 1064 gs_quant/test/timeseries/test_measures_inflation.py test_get_tdapi_inflation_rates_assets', fin_gsq_test_test_get_tdapi_inflation_rates_assets('local_payload').payload || ':' || fin_gsq_test_test_get_tdapi_inflation_rates_assets('local_payload').source_function, 'local_payload:test_get_tdapi_inflation_rates_assets');
SELECT assert_eq('gs quant canonical 1065 gs_quant/test/timeseries/test_measures_inflation.py mock_curr', fin_gsq_test_mock_curr_test_timeseries_test_meas_19b98b8bc0('local_payload').payload || ':' || fin_gsq_test_mock_curr_test_timeseries_test_meas_19b98b8bc0('local_payload').source_function, 'local_payload:mock_curr');
SELECT assert_eq('gs quant canonical 1066 gs_quant/test/timeseries/test_measures_inflation.py test_inflation_swap_rate', fin_gsq_test_test_inflation_swap_rate('local_payload').payload || ':' || fin_gsq_test_test_inflation_swap_rate('local_payload').source_function, 'local_payload:test_inflation_swap_rate');
SELECT assert_eq('gs quant canonical 1067 gs_quant/test/timeseries/test_measures_inflation.py test_inflation_swap_term', fin_gsq_test_test_inflation_swap_term('local_payload').payload || ':' || fin_gsq_test_test_inflation_swap_term('local_payload').source_function, 'local_payload:test_inflation_swap_term');
SELECT assert_eq('gs quant canonical 1068 gs_quant/test/timeseries/test_measures_portfolios.py mock_risk_model', fin_gsq_test_mock_risk_model_test_timeseries_test_meas_c9972596c1('local_payload').payload || ':' || fin_gsq_test_mock_risk_model_test_timeseries_test_meas_c9972596c1('local_payload').source_function, 'local_payload:mock_risk_model');
SELECT assert_eq('gs quant canonical 1069 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_factor_exposure', fin_gsq_test_test_portfolio_factor_exposure('local_payload').payload || ':' || fin_gsq_test_test_portfolio_factor_exposure('local_payload').source_function, 'local_payload:test_portfolio_factor_exposure');
SELECT assert_eq('gs quant canonical 1070 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_factor_pnl', fin_gsq_test_test_portfolio_factor_pnl('local_payload').payload || ':' || fin_gsq_test_test_portfolio_factor_pnl('local_payload').source_function, 'local_payload:test_portfolio_factor_pnl');
SELECT assert_eq('gs quant canonical 1071 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_factor_proportion_of_risk', fin_gsq_test_test_portfolio_factor_proportion_of_risk('local_payload').payload || ':' || fin_gsq_test_test_portfolio_factor_proportion_of_risk('local_payload').source_function, 'local_payload:test_portfolio_factor_proportion_of_risk');
SELECT assert_eq('gs quant canonical 1072 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_thematic_exposure', fin_gsq_test_test_portfolio_thematic_exposure('local_payload').payload || ':' || fin_gsq_test_test_portfolio_thematic_exposure('local_payload').source_function, 'local_payload:test_portfolio_thematic_exposure');
SELECT assert_eq('gs quant canonical 1073 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_pnl', fin_gsq_test_test_portfolio_pnl('local_payload').payload || ':' || fin_gsq_test_test_portfolio_pnl('local_payload').source_function, 'local_payload:test_portfolio_pnl');
SELECT assert_eq('gs quant canonical 1074 gs_quant/test/timeseries/test_measures_portfolios.py test_aggregate_factor_support', fin_gsq_test_test_aggregate_factor_support('local_payload').payload || ':' || fin_gsq_test_test_aggregate_factor_support('local_payload').source_function, 'local_payload:test_aggregate_factor_support');
SELECT assert_eq('gs quant canonical 1075 gs_quant/test/timeseries/test_measures_portfolios.py test_hit_rate', fin_gsq_test_test_hit_rate('local_payload').payload || ':' || fin_gsq_test_test_hit_rate('local_payload').source_function, 'local_payload:test_hit_rate');
SELECT assert_eq('gs quant canonical 1076 gs_quant/test/timeseries/test_measures_portfolios.py test_max_drawdown', fin_gsq_test_test_max_drawdown_test_timeseries_test_meas_c9972596c1('local_payload').payload || ':' || fin_gsq_test_test_max_drawdown_test_timeseries_test_meas_c9972596c1('local_payload').source_function, 'local_payload:test_max_drawdown');
SELECT assert_eq('gs quant canonical 1077 gs_quant/test/timeseries/test_measures_portfolios.py test_max_recovery_period', fin_gsq_test_test_max_recovery_period('local_payload').payload || ':' || fin_gsq_test_test_max_recovery_period('local_payload').source_function, 'local_payload:test_max_recovery_period');
SELECT assert_eq('gs quant canonical 1078 gs_quant/test/timeseries/test_measures_portfolios.py test_drawdown_length', fin_gsq_test_test_drawdown_length('local_payload').payload || ':' || fin_gsq_test_test_drawdown_length('local_payload').source_function, 'local_payload:test_drawdown_length');
SELECT assert_eq('gs quant canonical 1079 gs_quant/test/timeseries/test_measures_portfolios.py test_standard_deviation', fin_gsq_test_test_standard_deviation('local_payload').payload || ':' || fin_gsq_test_test_standard_deviation('local_payload').source_function, 'local_payload:test_standard_deviation');
SELECT assert_eq('gs quant canonical 1080 gs_quant/test/timeseries/test_measures_portfolios.py test_downside_risk', fin_gsq_test_test_downside_risk('local_payload').payload || ':' || fin_gsq_test_test_downside_risk('local_payload').source_function, 'local_payload:test_downside_risk');
SELECT assert_eq('gs quant canonical 1081 gs_quant/test/timeseries/test_measures_portfolios.py test_semi_variance', fin_gsq_test_test_semi_variance('local_payload').payload || ':' || fin_gsq_test_test_semi_variance('local_payload').source_function, 'local_payload:test_semi_variance');
SELECT assert_eq('gs quant canonical 1082 gs_quant/test/timeseries/test_measures_portfolios.py test_kurtosis', fin_gsq_test_test_kurtosis('local_payload').payload || ':' || fin_gsq_test_test_kurtosis('local_payload').source_function, 'local_payload:test_kurtosis');
SELECT assert_eq('gs quant canonical 1083 gs_quant/test/timeseries/test_measures_portfolios.py test_skewness', fin_gsq_test_test_skewness('local_payload').payload || ':' || fin_gsq_test_test_skewness('local_payload').source_function, 'local_payload:test_skewness');
SELECT assert_eq('gs quant canonical 1084 gs_quant/test/timeseries/test_measures_portfolios.py test_realized_var', fin_gsq_test_test_realized_var('local_payload').payload || ':' || fin_gsq_test_test_realized_var('local_payload').source_function, 'local_payload:test_realized_var');
SELECT assert_eq('gs quant canonical 1085 gs_quant/test/timeseries/test_measures_portfolios.py test_bad_date', fin_gsq_test_test_bad_date('local_payload').payload || ':' || fin_gsq_test_test_bad_date('local_payload').source_function, 'local_payload:test_bad_date');
SELECT assert_eq('gs quant canonical 1086 gs_quant/test/timeseries/test_measures_portfolios.py test_tracking_error', fin_gsq_test_test_tracking_error('local_payload').payload || ':' || fin_gsq_test_test_tracking_error('local_payload').source_function, 'local_payload:test_tracking_error');
SELECT assert_eq('gs quant canonical 1087 gs_quant/test/timeseries/test_measures_portfolios.py test_tracking_error_bull', fin_gsq_test_test_tracking_error_bull('local_payload').payload || ':' || fin_gsq_test_test_tracking_error_bull('local_payload').source_function, 'local_payload:test_tracking_error_bull');
SELECT assert_eq('gs quant canonical 1088 gs_quant/test/timeseries/test_measures_portfolios.py test_tracking_error_bear', fin_gsq_test_test_tracking_error_bear('local_payload').payload || ':' || fin_gsq_test_test_tracking_error_bear('local_payload').source_function, 'local_payload:test_tracking_error_bear');
SELECT assert_eq('gs quant canonical 1089 gs_quant/test/timeseries/test_measures_portfolios.py test_sharpe_ratio', fin_gsq_test_test_sharpe_ratio_test_timeseries_test_meas_c9972596c1('local_payload').payload || ':' || fin_gsq_test_test_sharpe_ratio_test_timeseries_test_meas_c9972596c1('local_payload').source_function, 'local_payload:test_sharpe_ratio');
SELECT assert_eq('gs quant canonical 1090 gs_quant/test/timeseries/test_measures_portfolios.py test_calmar_ratio', fin_gsq_test_test_calmar_ratio('local_payload').payload || ':' || fin_gsq_test_test_calmar_ratio('local_payload').source_function, 'local_payload:test_calmar_ratio');
SELECT assert_eq('gs quant canonical 1091 gs_quant/test/timeseries/test_measures_portfolios.py test_sortino_ratio', fin_gsq_test_test_sortino_ratio('local_payload').payload || ':' || fin_gsq_test_test_sortino_ratio('local_payload').source_function, 'local_payload:test_sortino_ratio');
SELECT assert_eq('gs quant canonical 1092 gs_quant/test/timeseries/test_measures_portfolios.py test_sortino_ratio_index', fin_gsq_test_test_sortino_ratio_index('local_payload').payload || ':' || fin_gsq_test_test_sortino_ratio_index('local_payload').source_function, 'local_payload:test_sortino_ratio_index');
SELECT assert_eq('gs quant canonical 1093 gs_quant/test/timeseries/test_measures_portfolios.py test_jensen_alpha', fin_gsq_test_test_jensen_alpha('local_payload').payload || ':' || fin_gsq_test_test_jensen_alpha('local_payload').source_function, 'local_payload:test_jensen_alpha');
SELECT assert_eq('gs quant canonical 1094 gs_quant/test/timeseries/test_measures_portfolios.py test_jensen_bull', fin_gsq_test_test_jensen_bull('local_payload').payload || ':' || fin_gsq_test_test_jensen_bull('local_payload').source_function, 'local_payload:test_jensen_bull');
SELECT assert_eq('gs quant canonical 1095 gs_quant/test/timeseries/test_measures_portfolios.py test_jensen_alpha_bear', fin_gsq_test_test_jensen_alpha_bear('local_payload').payload || ':' || fin_gsq_test_test_jensen_alpha_bear('local_payload').source_function, 'local_payload:test_jensen_alpha_bear');
SELECT assert_eq('gs quant canonical 1096 gs_quant/test/timeseries/test_measures_portfolios.py test_information_ratio', fin_gsq_test_test_information_ratio('local_payload').payload || ':' || fin_gsq_test_test_information_ratio('local_payload').source_function, 'local_payload:test_information_ratio');
SELECT assert_eq('gs quant canonical 1097 gs_quant/test/timeseries/test_measures_portfolios.py test_information_ratio_bull', fin_gsq_test_test_information_ratio_bull('local_payload').payload || ':' || fin_gsq_test_test_information_ratio_bull('local_payload').source_function, 'local_payload:test_information_ratio_bull');
SELECT assert_eq('gs quant canonical 1098 gs_quant/test/timeseries/test_measures_portfolios.py test_information_ratio_bear', fin_gsq_test_test_information_ratio_bear('local_payload').payload || ':' || fin_gsq_test_test_information_ratio_bear('local_payload').source_function, 'local_payload:test_information_ratio_bear');
SELECT assert_eq('gs quant canonical 1099 gs_quant/test/timeseries/test_measures_portfolios.py test_modigliani_ratio', fin_gsq_test_test_modigliani_ratio('local_payload').payload || ':' || fin_gsq_test_test_modigliani_ratio('local_payload').source_function, 'local_payload:test_modigliani_ratio');
SELECT assert_eq('gs quant canonical 1100 gs_quant/test/timeseries/test_measures_portfolios.py test_treynor_measure', fin_gsq_test_test_treynor_measure('local_payload').payload || ':' || fin_gsq_test_test_treynor_measure('local_payload').source_function, 'local_payload:test_treynor_measure');
SELECT assert_eq('gs quant canonical 1101 gs_quant/test/timeseries/test_measures_portfolios.py test_alpha', fin_gsq_test_test_alpha('local_payload').payload || ':' || fin_gsq_test_test_alpha('local_payload').source_function, 'local_payload:test_alpha');
SELECT assert_eq('gs quant canonical 1102 gs_quant/test/timeseries/test_measures_portfolios.py test_beta', fin_gsq_test_test_beta_test_timeseries_test_meas_c9972596c1('local_payload').payload || ':' || fin_gsq_test_test_beta_test_timeseries_test_meas_c9972596c1('local_payload').source_function, 'local_payload:test_beta');
SELECT assert_eq('gs quant canonical 1103 gs_quant/test/timeseries/test_measures_portfolios.py test_correlation', fin_gsq_test_test_correlation_test_timeseries_test_meas_c9972596c1('local_payload').payload || ':' || fin_gsq_test_test_correlation_test_timeseries_test_meas_c9972596c1('local_payload').source_function, 'local_payload:test_correlation');
SELECT assert_eq('gs quant canonical 1104 gs_quant/test/timeseries/test_measures_portfolios.py test_r_squared', fin_gsq_test_test_r_squared('local_payload').payload || ':' || fin_gsq_test_test_r_squared('local_payload').source_function, 'local_payload:test_r_squared');
SELECT assert_eq('gs quant canonical 1105 gs_quant/test/timeseries/test_measures_portfolios.py test_capture_ratio', fin_gsq_test_test_capture_ratio('local_payload').payload || ':' || fin_gsq_test_test_capture_ratio('local_payload').source_function, 'local_payload:test_capture_ratio');
SELECT assert_eq('gs quant canonical 1106 gs_quant/test/timeseries/test_measures_portfolios.py test_custom_aum', fin_gsq_test_test_custom_aum('local_payload').payload || ':' || fin_gsq_test_test_custom_aum('local_payload').source_function, 'local_payload:test_custom_aum');
SELECT assert_eq('gs quant canonical 1107 gs_quant/test/timeseries/test_measures_rates.py test_parse_meeting_date', fin_gsq_test_test_parse_meeting_date('local_payload').payload || ':' || fin_gsq_test_test_parse_meeting_date('local_payload').source_function, 'local_payload:test_parse_meeting_date');
SELECT assert_eq('gs quant canonical 1108 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_floating_rate_option_returns_default', fin_gsq_test_test_get_swaption_parameter_floating_rate_option_returns_default('local_payload').payload || ':' || fin_gsq_test_test_get_swaption_parameter_floating_rate_option_returns_default('local_payload').source_function, 'local_payload:test_get_swaption_parameter_floating_rate_option_returns_default');
SELECT assert_eq('gs quant canonical 1109 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_floating_rate_option_returns_given_value', fin_gsq_test_test_get_swaption_parameter_floating_rate_option_returns_given_value('local_payload').payload || ':' || fin_gsq_test_test_get_swaption_parameter_floating_rate_option_returns_given_value('local_payload').source_function, 'local_payload:test_get_swaption_parameter_floating_rate_option_returns_given_value');
SELECT assert_eq('gs quant canonical 1110 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_strike_reference_option_returns_default', fin_gsq_test_test_get_swaption_parameter_strike_reference_option_returns_default('local_payload').payload || ':' || fin_gsq_test_test_get_swaption_parameter_strike_reference_option_returns_default('local_payload').source_function, 'local_payload:test_get_swaption_parameter_strike_reference_option_returns_default');
SELECT assert_eq('gs quant canonical 1111 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_strike_reference_option_returns_given_value', fin_gsq_test_test_get_swaption_parameter_strike_reference_option_returns_given_value('local_payload').payload || ':' || fin_gsq_test_test_get_swaption_parameter_strike_reference_option_returns_given_value('local_payload').source_function, 'local_payload:test_get_swaption_parameter_strike_reference_option_returns_given_value');
SELECT assert_eq('gs quant canonical 1112 gs_quant/test/timeseries/test_measures_rates.py test_get_floating_rate_option_for_benchmark_retuns_rate', fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_rates('local_payload').payload || ':' || fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_rates('local_payload').source_function, 'local_payload:test_get_floating_rate_option_for_benchmark_retuns_rate');
SELECT assert_eq('gs quant canonical 1113 gs_quant/test/timeseries/test_measures_rates.py test_get_floating_rate_option_for_benchmark_retuns_rate_usd', fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_rates('local_payload').payload || ':' || fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_rates('local_payload').source_function, 'local_payload:test_get_floating_rate_option_for_benchmark_retuns_rate_usd');
SELECT assert_eq('gs quant canonical 1114 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string', fin_gsq_test_test_check_strike_reference_string('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_string('local_payload').source_function, 'local_payload:test_check_strike_reference_string');
SELECT assert_eq('gs quant canonical 1115 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_zero', fin_gsq_test_test_check_strike_reference_zero('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_zero('local_payload').source_function, 'local_payload:test_check_strike_reference_zero');
SELECT assert_eq('gs quant canonical 1116 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_spot', fin_gsq_test_test_check_strike_reference_spot('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_spot('local_payload').source_function, 'local_payload:test_check_strike_reference_spot');
SELECT assert_eq('gs quant canonical 1117 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string_positive', fin_gsq_test_test_check_strike_reference_string_positive('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_string_positive('local_payload').source_function, 'local_payload:test_check_strike_reference_string_positive');
SELECT assert_eq('gs quant canonical 1118 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string_negtive', fin_gsq_test_test_check_strike_reference_string_negtive('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_string_negtive('local_payload').source_function, 'local_payload:test_check_strike_reference_string_negtive');
SELECT assert_eq('gs quant canonical 1119 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string_fractional', fin_gsq_test_test_check_strike_reference_string_fractional('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_string_fractional('local_payload').source_function, 'local_payload:test_check_strike_reference_string_fractional');
SELECT assert_eq('gs quant canonical 1120 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_numeric_fractional', fin_gsq_test_test_check_strike_reference_numeric_fractional('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_numeric_fractional('local_payload').source_function, 'local_payload:test_check_strike_reference_numeric_fractional');
SELECT assert_eq('gs quant canonical 1121 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_numeric', fin_gsq_test_test_check_strike_reference_numeric('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_numeric('local_payload').source_function, 'local_payload:test_check_strike_reference_numeric');
SELECT assert_eq('gs quant canonical 1122 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_throws', fin_gsq_test_test_check_strike_reference_throws('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_throws('local_payload').source_function, 'local_payload:test_check_strike_reference_throws');
SELECT assert_eq('gs quant canonical 1123 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_list', fin_gsq_test_test_check_strike_reference_list('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_list('local_payload').source_function, 'local_payload:test_check_strike_reference_list');
SELECT assert_eq('gs quant canonical 1124 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_invalid_list', fin_gsq_test_test_check_strike_reference_invalid_list('local_payload').payload || ':' || fin_gsq_test_test_check_strike_reference_invalid_list('local_payload').source_function, 'local_payload:test_check_strike_reference_invalid_list');
SELECT assert_eq('gs quant canonical 1125 gs_quant/test/timeseries/test_measures_rates.py test_pricing_location_normalized', fin_gsq_test_test_pricing_location_normalized('local_payload').payload || ':' || fin_gsq_test_test_pricing_location_normalized('local_payload').source_function, 'local_payload:test_pricing_location_normalized');
SELECT assert_eq('gs quant canonical 1126 gs_quant/test/timeseries/test_measures_rates.py test_default_pricing_location', fin_gsq_test_test_default_pricing_location('local_payload').payload || ':' || fin_gsq_test_test_default_pricing_location('local_payload').source_function, 'local_payload:test_default_pricing_location');
SELECT assert_eq('gs quant canonical 1127 gs_quant/test/timeseries/test_measures_rates.py test_currency_to_tdapi_swaption_rate_asset_retuns_throws', fin_gsq_test_test_currency_to_tdapi_swaption_rate_asset_retuns_throws('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_swaption_rate_asset_retuns_throws('local_payload').source_function, 'local_payload:test_currency_to_tdapi_swaption_rate_asset_retuns_throws');
SELECT assert_eq('gs quant canonical 1128 gs_quant/test/timeseries/test_measures_rates.py test_currency_to_tdapi_midcurve_asset', fin_gsq_test_test_currency_to_tdapi_midcurve_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_midcurve_asset('local_payload').source_function, 'local_payload:test_currency_to_tdapi_midcurve_asset');
SELECT assert_eq('gs quant canonical 1129 gs_quant/test/timeseries/test_measures_rates.py test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id', fin_gsq_test_test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id('local_payload').source_function, 'local_payload:test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id');
SELECT assert_eq('gs quant canonical 1130 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_throws_on_invalid_tenor', fin_gsq_test_test_swaption_build_asset_query_throws_on_invalid_tenor('local_payload').payload || ':' || fin_gsq_test_test_swaption_build_asset_query_throws_on_invalid_tenor('local_payload').source_function, 'local_payload:test_swaption_build_asset_query_throws_on_invalid_tenor');
SELECT assert_eq('gs quant canonical 1131 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_usd', fin_gsq_test_test_swaption_build_asset_query_usd('local_payload').payload || ':' || fin_gsq_test_test_swaption_build_asset_query_usd('local_payload').source_function, 'local_payload:test_swaption_build_asset_query_usd');
SELECT assert_eq('gs quant canonical 1132 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_strike_reference', fin_gsq_test_test_swaption_build_asset_query_strike_reference('local_payload').payload || ':' || fin_gsq_test_test_swaption_build_asset_query_strike_reference('local_payload').source_function, 'local_payload:test_swaption_build_asset_query_strike_reference');
SELECT assert_eq('gs quant canonical 1133 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_clearing_house', fin_gsq_test_test_swaption_build_asset_query_clearing_house('local_payload').payload || ':' || fin_gsq_test_test_swaption_build_asset_query_clearing_house('local_payload').source_function, 'local_payload:test_swaption_build_asset_query_clearing_house');
SELECT assert_eq('gs quant canonical 1134 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_custom', fin_gsq_test_test_swaption_build_asset_query_custom('local_payload').payload || ':' || fin_gsq_test_test_swaption_build_asset_query_custom('local_payload').source_function, 'local_payload:test_swaption_build_asset_query_custom');
SELECT assert_eq('gs quant canonical 1135 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_custom_throws', fin_gsq_test_test_swaption_build_asset_query_custom_throws('local_payload').payload || ':' || fin_gsq_test_test_swaption_build_asset_query_custom_throws('local_payload').source_function, 'local_payload:test_swaption_build_asset_query_custom_throws');
SELECT assert_eq('gs quant canonical 1136 gs_quant/test/timeseries/test_measures_rates.py test_swaption_swaption_vol_term2_returns_data', fin_gsq_test_test_swaption_swaption_vol_term2_returns_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_swaption_vol_term2_returns_data('local_payload').source_function, 'local_payload:test_swaption_swaption_vol_term2_returns_data');
SELECT assert_eq('gs quant canonical 1137 gs_quant/test/timeseries/test_measures_rates.py test_swaption_swaption_vol_term2_returns_empty', fin_gsq_test_test_swaption_swaption_vol_term2_returns_empty('local_payload').payload || ':' || fin_gsq_test_test_swaption_swaption_vol_term2_returns_empty('local_payload').source_function, 'local_payload:test_swaption_swaption_vol_term2_returns_empty');
SELECT assert_eq('gs quant canonical 1138 gs_quant/test/timeseries/test_measures_rates.py test_swaption_swaption_vol_term2_throws', fin_gsq_test_test_swaption_swaption_vol_term2_throws('local_payload').payload || ':' || fin_gsq_test_test_swaption_swaption_vol_term2_throws('local_payload').source_function, 'local_payload:test_swaption_swaption_vol_term2_throws');
SELECT assert_eq('gs quant canonical 1139 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol_smile2_returns_data', fin_gsq_test_test_swaption_vol_smile2_returns_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_vol_smile2_returns_data('local_payload').source_function, 'local_payload:test_swaption_vol_smile2_returns_data');
SELECT assert_eq('gs quant canonical 1140 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol_smile2_returns_no_data', fin_gsq_test_test_swaption_vol_smile2_returns_no_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_vol_smile2_returns_no_data('local_payload').source_function, 'local_payload:test_swaption_vol_smile2_returns_no_data');
SELECT assert_eq('gs quant canonical 1141 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol_smile2_returns_throws', fin_gsq_test_test_swaption_vol_smile2_returns_throws('local_payload').payload || ':' || fin_gsq_test_test_swaption_vol_smile2_returns_throws('local_payload').source_function, 'local_payload:test_swaption_vol_smile2_returns_throws');
SELECT assert_eq('gs quant canonical 1142 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol2_return_data', fin_gsq_test_test_swaption_vol2_return_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_vol2_return_data('local_payload').source_function, 'local_payload:test_swaption_vol2_return_data');
SELECT assert_eq('gs quant canonical 1143 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol2_return__empty_data', fin_gsq_test_test_swaption_vol2_return_empty_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_vol2_return_empty_data('local_payload').source_function, 'local_payload:test_swaption_vol2_return__empty_data');
SELECT assert_eq('gs quant canonical 1144 gs_quant/test/timeseries/test_measures_rates.py test_swaption_annuity_return_data', fin_gsq_test_test_swaption_annuity_return_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_annuity_return_data('local_payload').source_function, 'local_payload:test_swaption_annuity_return_data');
SELECT assert_eq('gs quant canonical 1145 gs_quant/test/timeseries/test_measures_rates.py test_swaption_premium_return_data', fin_gsq_test_test_swaption_premium_return_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_premium_return_data('local_payload').source_function, 'local_payload:test_swaption_premium_return_data');
SELECT assert_eq('gs quant canonical 1146 gs_quant/test/timeseries/test_measures_rates.py test_swaption_premium_throws_for_realtime', fin_gsq_test_test_swaption_premium_throws_for_realtime('local_payload').payload || ':' || fin_gsq_test_test_swaption_premium_throws_for_realtime('local_payload').source_function, 'local_payload:test_swaption_premium_throws_for_realtime');
SELECT assert_eq('gs quant canonical 1147 gs_quant/test/timeseries/test_measures_rates.py test__check_forward_tenor_returns_None', fin_gsq_test_test_check_forward_tenor_returns_none('local_payload').payload || ':' || fin_gsq_test_test_check_forward_tenor_returns_none('local_payload').source_function, 'local_payload:test__check_forward_tenor_returns_None');
SELECT assert_eq('gs quant canonical 1148 gs_quant/test/timeseries/test_measures_rates.py test__check_forward_tenor_returns_0b', fin_gsq_test_test_check_forward_tenor_returns_0b('local_payload').payload || ':' || fin_gsq_test_test_check_forward_tenor_returns_0b('local_payload').source_function, 'local_payload:test__check_forward_tenor_returns_0b');
SELECT assert_eq('gs quant canonical 1149 gs_quant/test/timeseries/test_measures_rates.py test_swaption_premium_throws_for_unsupported_ccy', fin_gsq_test_test_swaption_premium_throws_for_unsupported_ccy('local_payload').payload || ':' || fin_gsq_test_test_swaption_premium_throws_for_unsupported_ccy('local_payload').source_function, 'local_payload:test_swaption_premium_throws_for_unsupported_ccy');
SELECT assert_eq('gs quant canonical 1150 gs_quant/test/timeseries/test_measures_rates.py test_swaption_atmFwdRate_return_data', fin_gsq_test_test_swaption_atmfwdrate_return_data('local_payload').payload || ':' || fin_gsq_test_test_swaption_atmfwdrate_return_data('local_payload').source_function, 'local_payload:test_swaption_atmFwdRate_return_data');
SELECT assert_eq('gs quant canonical 1151 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_atmFwdRate_return_data', fin_gsq_test_test_midcurve_atmfwdrate_return_data('local_payload').payload || ':' || fin_gsq_test_test_midcurve_atmfwdrate_return_data('local_payload').source_function, 'local_payload:test_midcurve_atmFwdRate_return_data');
SELECT assert_eq('gs quant canonical 1152 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_annuity_return_data', fin_gsq_test_test_midcurve_annuity_return_data('local_payload').payload || ':' || fin_gsq_test_test_midcurve_annuity_return_data('local_payload').source_function, 'local_payload:test_midcurve_annuity_return_data');
SELECT assert_eq('gs quant canonical 1153 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_premium_return_data', fin_gsq_test_test_midcurve_premium_return_data('local_payload').payload || ':' || fin_gsq_test_test_midcurve_premium_return_data('local_payload').source_function, 'local_payload:test_midcurve_premium_return_data');
SELECT assert_eq('gs quant canonical 1154 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_vol_return_data', fin_gsq_test_test_midcurve_vol_return_data('local_payload').payload || ':' || fin_gsq_test_test_midcurve_vol_return_data('local_payload').source_function, 'local_payload:test_midcurve_vol_return_data');
SELECT assert_eq('gs quant canonical 1155 gs_quant/test/timeseries/test_measures_rates.py test_cross_to_fxfwd_xcswp_asset', fin_gsq_test_test_cross_to_fxfwd_xcswp_asset('local_payload').payload || ':' || fin_gsq_test_test_cross_to_fxfwd_xcswp_asset('local_payload').source_function, 'local_payload:test_cross_to_fxfwd_xcswp_asset');
SELECT assert_eq('gs quant canonical 1156 gs_quant/test/timeseries/test_measures_rates.py test_ois_fxfwd_xcswap_measures', fin_gsq_test_test_ois_fxfwd_xcswap_measures('local_payload').payload || ':' || fin_gsq_test_test_ois_fxfwd_xcswap_measures('local_payload').source_function, 'local_payload:test_ois_fxfwd_xcswap_measures');
SELECT assert_eq('gs quant canonical 1157 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_expectation_mocker', fin_gsq_test_get_data_policy_rate_expectation_mocker('local_payload').payload || ':' || fin_gsq_test_get_data_policy_rate_expectation_mocker('local_payload').source_function, 'local_payload:get_data_policy_rate_expectation_mocker');
SELECT assert_eq('gs quant canonical 1158 gs_quant/test/timeseries/test_measures_rates.py mock_meeting_expectation', fin_gsq_test_mock_meeting_expectation('local_payload').payload || ':' || fin_gsq_test_mock_meeting_expectation('local_payload').source_function, 'local_payload:mock_meeting_expectation');
SELECT assert_eq('gs quant canonical 1159 gs_quant/test/timeseries/test_measures_rates.py mock_meeting_spot', fin_gsq_test_mock_meeting_spot('local_payload').payload || ':' || fin_gsq_test_mock_meeting_spot('local_payload').source_function, 'local_payload:mock_meeting_spot');
SELECT assert_eq('gs quant canonical 1160 gs_quant/test/timeseries/test_measures_rates.py mock_meeting_absolute', fin_gsq_test_mock_meeting_absolute('local_payload').payload || ':' || fin_gsq_test_mock_meeting_absolute('local_payload').source_function, 'local_payload:mock_meeting_absolute');
SELECT assert_eq('gs quant canonical 1161 gs_quant/test/timeseries/test_measures_rates.py mock_ois_spot', fin_gsq_test_mock_ois_spot('local_payload').payload || ':' || fin_gsq_test_mock_ois_spot('local_payload').source_function, 'local_payload:mock_ois_spot');
SELECT assert_eq('gs quant canonical 1162 gs_quant/test/timeseries/test_measures_rates.py test_get_default_ois_benchmark', fin_gsq_test_test_get_default_ois_benchmark('local_payload').payload || ':' || fin_gsq_test_test_get_default_ois_benchmark('local_payload').source_function, 'local_payload:test_get_default_ois_benchmark');
SELECT assert_eq('gs quant canonical 1163 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_term_structure', fin_gsq_test_test_policy_rate_term_structure('local_payload').payload || ':' || fin_gsq_test_test_policy_rate_term_structure('local_payload').source_function, 'local_payload:test_policy_rate_term_structure');
SELECT assert_eq('gs quant canonical 1164 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_expectation', fin_gsq_test_test_policy_rate_expectation('local_payload').payload || ':' || fin_gsq_test_test_policy_rate_expectation('local_payload').source_function, 'local_payload:test_policy_rate_expectation');
SELECT assert_eq('gs quant canonical 1165 gs_quant/test/timeseries/test_measures_rates.py mock_policy_rt_spot', fin_gsq_test_mock_policy_rt_spot('local_payload').payload || ':' || fin_gsq_test_mock_policy_rt_spot('local_payload').source_function, 'local_payload:mock_policy_rt_spot');
SELECT assert_eq('gs quant canonical 1166 gs_quant/test/timeseries/test_measures_rates.py mock_policy_rate_expectation_rt_meeting', fin_gsq_test_mock_policy_rate_expectation_rt_meeting('local_payload').payload || ':' || fin_gsq_test_mock_policy_rate_expectation_rt_meeting('local_payload').source_function, 'local_payload:mock_policy_rate_expectation_rt_meeting');
SELECT assert_eq('gs quant canonical 1167 gs_quant/test/timeseries/test_measures_rates.py mock_policy_term_rt_meeting', fin_gsq_test_mock_policy_term_rt_meeting('local_payload').payload || ':' || fin_gsq_test_mock_policy_term_rt_meeting('local_payload').source_function, 'local_payload:mock_policy_term_rt_meeting');
SELECT assert_eq('gs quant canonical 1168 gs_quant/test/timeseries/test_measures_rates.py mock_policy_term_rt_meeting_series', fin_gsq_test_mock_policy_term_rt_meeting_series('local_payload').payload || ':' || fin_gsq_test_mock_policy_term_rt_meeting_series('local_payload').source_function, 'local_payload:mock_policy_term_rt_meeting_series');
SELECT assert_eq('gs quant canonical 1169 gs_quant/test/timeseries/test_measures_rates.py mock_policy_rate_empty_join_df', fin_gsq_test_mock_policy_rate_empty_join_df('local_payload').payload || ':' || fin_gsq_test_mock_policy_rate_empty_join_df('local_payload').source_function, 'local_payload:mock_policy_rate_empty_join_df');
SELECT assert_eq('gs quant canonical 1170 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_term_rt_series_mocker', fin_gsq_test_get_data_policy_rate_term_rt_series_mocker('local_payload').payload || ':' || fin_gsq_test_get_data_policy_rate_term_rt_series_mocker('local_payload').source_function, 'local_payload:get_data_policy_rate_term_rt_series_mocker');
SELECT assert_eq('gs quant canonical 1171 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_term_rt_mocker', fin_gsq_test_get_data_policy_rate_term_rt_mocker('local_payload').payload || ':' || fin_gsq_test_get_data_policy_rate_term_rt_mocker('local_payload').source_function, 'local_payload:get_data_policy_rate_term_rt_mocker');
SELECT assert_eq('gs quant canonical 1172 gs_quant/test/timeseries/test_measures_rates.py get_data_empty_spot_mocker', fin_gsq_test_get_data_empty_spot_mocker('local_payload').payload || ':' || fin_gsq_test_get_data_empty_spot_mocker('local_payload').source_function, 'local_payload:get_data_empty_spot_mocker');
SELECT assert_eq('gs quant canonical 1173 gs_quant/test/timeseries/test_measures_rates.py get_data_empty_join_mocker', fin_gsq_test_get_data_empty_join_mocker('local_payload').payload || ':' || fin_gsq_test_get_data_empty_join_mocker('local_payload').source_function, 'local_payload:get_data_empty_join_mocker');
SELECT assert_eq('gs quant canonical 1174 gs_quant/test/timeseries/test_measures_rates.py get_cb_swap_assets_mocker', fin_gsq_test_get_cb_swap_assets_mocker('local_payload').payload || ':' || fin_gsq_test_get_cb_swap_assets_mocker('local_payload').source_function, 'local_payload:get_cb_swap_assets_mocker');
SELECT assert_eq('gs quant canonical 1175 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_term_structure_rt', fin_gsq_test_test_policy_rate_term_structure_rt('local_payload').payload || ':' || fin_gsq_test_test_policy_rate_term_structure_rt('local_payload').source_function, 'local_payload:test_policy_rate_term_structure_rt');
SELECT assert_eq('gs quant canonical 1176 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_exp_rt_mocker', fin_gsq_test_get_data_policy_rate_exp_rt_mocker('local_payload').payload || ':' || fin_gsq_test_get_data_policy_rate_exp_rt_mocker('local_payload').source_function, 'local_payload:get_data_policy_rate_exp_rt_mocker');
SELECT assert_eq('gs quant canonical 1177 gs_quant/test/timeseries/test_measures_rates.py policy_exp_empty_spot_mocker', fin_gsq_test_policy_exp_empty_spot_mocker('local_payload').payload || ':' || fin_gsq_test_policy_exp_empty_spot_mocker('local_payload').source_function, 'local_payload:policy_exp_empty_spot_mocker');
SELECT assert_eq('gs quant canonical 1178 gs_quant/test/timeseries/test_measures_rates.py test_get_swap_from_meeting_date', fin_gsq_test_test_get_swap_from_meeting_date('local_payload').payload || ':' || fin_gsq_test_test_get_swap_from_meeting_date('local_payload').source_function, 'local_payload:test_get_swap_from_meeting_date');
SELECT assert_eq('gs quant canonical 1179 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_expectation_rt', fin_gsq_test_test_policy_rate_expectation_rt('local_payload').payload || ':' || fin_gsq_test_test_policy_rate_expectation_rt('local_payload').source_function, 'local_payload:test_policy_rate_expectation_rt');
SELECT assert_eq('gs quant canonical 1180 gs_quant/test/timeseries/test_measures_rates.py test_get_cb_meeting_swap', fin_gsq_test_test_get_cb_meeting_swap('local_payload').payload || ':' || fin_gsq_test_test_get_cb_meeting_swap('local_payload').source_function, 'local_payload:test_get_cb_meeting_swap');
SELECT assert_eq('gs quant canonical 1181 gs_quant/test/timeseries/test_measures_reports.py compute_geometric_aggregation_calculations', fin_gsq_test_compute_geometric_aggregation_calculations('local_payload').payload || ':' || fin_gsq_test_compute_geometric_aggregation_calculations('local_payload').source_function, 'local_payload:compute_geometric_aggregation_calculations');
SELECT assert_eq('gs quant canonical 1182 gs_quant/test/timeseries/test_measures_reports.py mock_risk_model', fin_gsq_test_mock_risk_model_test_timeseries_test_meas_4f0965273f('local_payload').payload || ':' || fin_gsq_test_mock_risk_model_test_timeseries_test_meas_4f0965273f('local_payload').source_function, 'local_payload:mock_risk_model');
SELECT assert_eq('gs quant canonical 1183 gs_quant/test/timeseries/test_measures_reports.py test_factor_exposure', fin_gsq_test_test_factor_exposure('local_payload').payload || ':' || fin_gsq_test_test_factor_exposure('local_payload').source_function, 'local_payload:test_factor_exposure');
SELECT assert_eq('gs quant canonical 1184 gs_quant/test/timeseries/test_measures_reports.py test_factor_exposure_percent', fin_gsq_test_test_factor_exposure_percent('local_payload').payload || ':' || fin_gsq_test_test_factor_exposure_percent('local_payload').source_function, 'local_payload:test_factor_exposure_percent');
SELECT assert_eq('gs quant canonical 1185 gs_quant/test/timeseries/test_measures_reports.py test_factor_pnl', fin_gsq_test_test_factor_pnl('local_payload').payload || ':' || fin_gsq_test_test_factor_pnl('local_payload').source_function, 'local_payload:test_factor_pnl');
SELECT assert_eq('gs quant canonical 1186 gs_quant/test/timeseries/test_measures_reports.py test_factor_pnl_percent', fin_gsq_test_test_factor_pnl_percent('local_payload').payload || ':' || fin_gsq_test_test_factor_pnl_percent('local_payload').source_function, 'local_payload:test_factor_pnl_percent');
SELECT assert_eq('gs quant canonical 1187 gs_quant/test/timeseries/test_measures_reports.py test_asset_factor_pnl_percent', fin_gsq_test_test_asset_factor_pnl_percent('local_payload').payload || ':' || fin_gsq_test_test_asset_factor_pnl_percent('local_payload').source_function, 'local_payload:test_asset_factor_pnl_percent');
SELECT assert_eq('gs quant canonical 1188 gs_quant/test/timeseries/test_measures_reports.py test_factor_proportion_of_risk', fin_gsq_test_test_factor_proportion_of_risk('local_payload').payload || ':' || fin_gsq_test_test_factor_proportion_of_risk('local_payload').source_function, 'local_payload:test_factor_proportion_of_risk');
SELECT assert_eq('gs quant canonical 1189 gs_quant/test/timeseries/test_measures_reports.py test_get_factor_data', fin_gsq_test_test_get_factor_data('local_payload').payload || ':' || fin_gsq_test_test_get_factor_data('local_payload').source_function, 'local_payload:test_get_factor_data');
SELECT assert_eq('gs quant canonical 1190 gs_quant/test/timeseries/test_measures_reports.py test_aggregate_factor_support', fin_gsq_test_test_aggregate_factor_support_test_timeseries_test_meas_4f0965273f('local_payload').payload || ':' || fin_gsq_test_test_aggregate_factor_support_test_timeseries_test_meas_4f0965273f('local_payload').source_function, 'local_payload:test_aggregate_factor_support');
SELECT assert_eq('gs quant canonical 1191 gs_quant/test/timeseries/test_measures_reports.py test_normalized_performance', fin_gsq_test_test_normalized_performance('local_payload').payload || ':' || fin_gsq_test_test_normalized_performance('local_payload').source_function, 'local_payload:test_normalized_performance');
SELECT assert_eq('gs quant canonical 1192 gs_quant/test/timeseries/test_measures_reports.py test_normalized_performance_short', fin_gsq_test_test_normalized_performance_short('local_payload').payload || ':' || fin_gsq_test_test_normalized_performance_short('local_payload').source_function, 'local_payload:test_normalized_performance_short');
SELECT assert_eq('gs quant canonical 1193 gs_quant/test/timeseries/test_measures_reports.py test_get_long_pnl', fin_gsq_test_test_get_long_pnl('local_payload').payload || ':' || fin_gsq_test_test_get_long_pnl('local_payload').source_function, 'local_payload:test_get_long_pnl');
SELECT assert_eq('gs quant canonical 1194 gs_quant/test/timeseries/test_measures_reports.py test_get_short_pnl', fin_gsq_test_test_get_short_pnl('local_payload').payload || ':' || fin_gsq_test_test_get_short_pnl('local_payload').source_function, 'local_payload:test_get_short_pnl');
SELECT assert_eq('gs quant canonical 1195 gs_quant/test/timeseries/test_measures_reports.py test_get_short_pnl_empty', fin_gsq_test_test_get_short_pnl_empty('local_payload').payload || ':' || fin_gsq_test_test_get_short_pnl_empty('local_payload').source_function, 'local_payload:test_get_short_pnl_empty');
SELECT assert_eq('gs quant canonical 1196 gs_quant/test/timeseries/test_measures_reports.py test_get_long_pnl_empty', fin_gsq_test_test_get_long_pnl_empty('local_payload').payload || ':' || fin_gsq_test_test_get_long_pnl_empty('local_payload').source_function, 'local_payload:test_get_long_pnl_empty');
SELECT assert_eq('gs quant canonical 1197 gs_quant/test/timeseries/test_measures_reports.py test_thematic_exposure', fin_gsq_test_test_thematic_exposure('local_payload').payload || ':' || fin_gsq_test_test_thematic_exposure('local_payload').source_function, 'local_payload:test_thematic_exposure');
SELECT assert_eq('gs quant canonical 1198 gs_quant/test/timeseries/test_measures_reports.py test_thematic_beta', fin_gsq_test_test_thematic_beta('local_payload').payload || ':' || fin_gsq_test_test_thematic_beta('local_payload').source_function, 'local_payload:test_thematic_beta');
SELECT assert_eq('gs quant canonical 1199 gs_quant/test/timeseries/test_measures_reports.py test_aum', fin_gsq_test_test_aum('local_payload').payload || ':' || fin_gsq_test_test_aum('local_payload').source_function, 'local_payload:test_aum');
SELECT assert_eq('gs quant canonical 1200 gs_quant/test/timeseries/test_measures_reports.py test_pnl', fin_gsq_test_test_pnl('local_payload').payload || ':' || fin_gsq_test_test_pnl('local_payload').source_function, 'local_payload:test_pnl');
SELECT assert_eq('gs quant canonical 1201 gs_quant/test/timeseries/test_measures_reports.py test_pnl_percent', fin_gsq_test_test_pnl_percent('local_payload').payload || ':' || fin_gsq_test_test_pnl_percent('local_payload').source_function, 'local_payload:test_pnl_percent');
SELECT assert_eq('gs quant canonical 1202 gs_quant/test/timeseries/test_measures_reports.py test_historical_simulation_estimated_pnl', fin_gsq_test_test_historical_simulation_estimated_pnl('local_payload').payload || ':' || fin_gsq_test_test_historical_simulation_estimated_pnl('local_payload').source_function, 'local_payload:test_historical_simulation_estimated_pnl');
SELECT assert_eq('gs quant canonical 1203 gs_quant/test/timeseries/test_measures_reports.py test_historical_simulation_estimated_factor_attribution', fin_gsq_test_test_historical_simulation_estimated_factor_attribution('local_payload').payload || ':' || fin_gsq_test_test_historical_simulation_estimated_factor_attribution('local_payload').source_function, 'local_payload:test_historical_simulation_estimated_factor_attribution');
SELECT assert_eq('gs quant canonical 1204 gs_quant/test/timeseries/test_measures_risk_models.py mock_risk_model', fin_gsq_test_mock_risk_model_test_timeseries_test_meas_1c0c59ed9d('local_payload').payload || ':' || fin_gsq_test_mock_risk_model_test_timeseries_test_meas_1c0c59ed9d('local_payload').source_function, 'local_payload:mock_risk_model');
SELECT assert_eq('gs quant canonical 1205 gs_quant/test/timeseries/test_measures_risk_models.py test_risk_model_measure', fin_gsq_test_test_risk_model_measure('local_payload').payload || ':' || fin_gsq_test_test_risk_model_measure('local_payload').source_function, 'local_payload:test_risk_model_measure');
SELECT assert_eq('gs quant canonical 1206 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_zscore', fin_gsq_test_test_factor_zscore('local_payload').payload || ':' || fin_gsq_test_test_factor_zscore('local_payload').source_function, 'local_payload:test_factor_zscore');
SELECT assert_eq('gs quant canonical 1207 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_covariance', fin_gsq_test_test_factor_covariance('local_payload').payload || ':' || fin_gsq_test_test_factor_covariance('local_payload').source_function, 'local_payload:test_factor_covariance');
SELECT assert_eq('gs quant canonical 1208 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_volatility', fin_gsq_test_test_factor_volatility('local_payload').payload || ':' || fin_gsq_test_test_factor_volatility('local_payload').source_function, 'local_payload:test_factor_volatility');
SELECT assert_eq('gs quant canonical 1209 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_correlation', fin_gsq_test_test_factor_correlation('local_payload').payload || ':' || fin_gsq_test_test_factor_correlation('local_payload').source_function, 'local_payload:test_factor_correlation');
SELECT assert_eq('gs quant canonical 1210 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_performance', fin_gsq_test_test_factor_performance('local_payload').payload || ':' || fin_gsq_test_test_factor_performance('local_payload').source_function, 'local_payload:test_factor_performance');
SELECT assert_eq('gs quant canonical 1211 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_returns_intraday', fin_gsq_test_test_factor_returns_intraday('local_payload').payload || ':' || fin_gsq_test_test_factor_returns_intraday('local_payload').source_function, 'local_payload:test_factor_returns_intraday');
SELECT assert_eq('gs quant canonical 1212 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_returns_percentile', fin_gsq_test_test_factor_returns_percentile('local_payload').payload || ':' || fin_gsq_test_test_factor_returns_percentile('local_payload').source_function, 'local_payload:test_factor_returns_percentile');
SELECT assert_eq('gs quant canonical 1213 gs_quant/test/timeseries/test_measures_xccy.py test_get_floating_rate_option_for_benchmark_retuns_rate', fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_xccy('local_payload').payload || ':' || fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_xccy('local_payload').source_function, 'local_payload:test_get_floating_rate_option_for_benchmark_retuns_rate');
SELECT assert_eq('gs quant canonical 1214 gs_quant/test/timeseries/test_measures_xccy.py test_get_floating_rate_option_for_benchmark_retuns_rate_usd', fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_xccy('local_payload').payload || ':' || fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_xccy('local_payload').source_function, 'local_payload:test_get_floating_rate_option_for_benchmark_retuns_rate_usd');
SELECT assert_eq('gs quant canonical 1215 gs_quant/test/timeseries/test_measures_xccy.py test_currency_to_tdapi_xccy_swap_rate_asset', fin_gsq_test_test_currency_to_tdapi_xccy_swap_rate_asset('local_payload').payload || ':' || fin_gsq_test_test_currency_to_tdapi_xccy_swap_rate_asset('local_payload').source_function, 'local_payload:test_currency_to_tdapi_xccy_swap_rate_asset');
SELECT assert_eq('gs quant canonical 1216 gs_quant/test/timeseries/test_measures_xccy.py test_get_crosscurrency_swap_leg_defaults', fin_gsq_test_test_get_crosscurrency_swap_leg_defaults('local_payload').payload || ':' || fin_gsq_test_test_get_crosscurrency_swap_leg_defaults('local_payload').source_function, 'local_payload:test_get_crosscurrency_swap_leg_defaults');
SELECT assert_eq('gs quant canonical 1217 gs_quant/test/timeseries/test_measures_xccy.py test_get_crosscurrency_swap_csa_terms', fin_gsq_test_test_get_crosscurrency_swap_csa_terms('local_payload').payload || ':' || fin_gsq_test_test_get_crosscurrency_swap_csa_terms('local_payload').source_function, 'local_payload:test_get_crosscurrency_swap_csa_terms');
SELECT assert_eq('gs quant canonical 1218 gs_quant/test/timeseries/test_measures_xccy.py test_check_valid_indices', fin_gsq_test_test_check_valid_indices_test_timeseries_test_measures_xccy('local_payload').payload || ':' || fin_gsq_test_test_check_valid_indices_test_timeseries_test_measures_xccy('local_payload').source_function, 'local_payload:test_check_valid_indices');
SELECT assert_eq('gs quant canonical 1219 gs_quant/test/timeseries/test_measures_xccy.py test_get_tdapi_crosscurrency_rates_assets', fin_gsq_test_test_get_tdapi_crosscurrency_rates_assets('local_payload').payload || ':' || fin_gsq_test_test_get_tdapi_crosscurrency_rates_assets('local_payload').source_function, 'local_payload:test_get_tdapi_crosscurrency_rates_assets');
SELECT assert_eq('gs quant canonical 1220 gs_quant/test/timeseries/test_measures_xccy.py mock_curr', fin_gsq_test_mock_curr_test_timeseries_test_measures_xccy('local_payload').payload || ':' || fin_gsq_test_mock_curr_test_timeseries_test_measures_xccy('local_payload').source_function, 'local_payload:mock_curr');
SELECT assert_eq('gs quant canonical 1221 gs_quant/test/timeseries/test_measures_xccy.py test_crosscurrency_swap_rate', fin_gsq_test_test_crosscurrency_swap_rate('local_payload').payload || ':' || fin_gsq_test_test_crosscurrency_swap_rate('local_payload').source_function, 'local_payload:test_crosscurrency_swap_rate');
SELECT assert_eq('gs quant canonical 1222 gs_quant/test/timeseries/test_rolling.py test_rolling_date_offset', fin_gsq_test_test_rolling_date_offset('local_payload').payload || ':' || fin_gsq_test_test_rolling_date_offset('local_payload').source_function, 'local_payload:test_rolling_date_offset');
SELECT assert_eq('gs quant canonical 1223 gs_quant/test/timeseries/test_statistics.py test_generate_series', fin_gsq_test_test_generate_series('local_payload').payload || ':' || fin_gsq_test_test_generate_series('local_payload').source_function, 'local_payload:test_generate_series');
SELECT assert_eq('gs quant canonical 1224 gs_quant/test/timeseries/test_statistics.py test_generate_series_intraday', fin_gsq_test_test_generate_series_intraday('local_payload').payload || ':' || fin_gsq_test_test_generate_series_intraday('local_payload').source_function, 'local_payload:test_generate_series_intraday');
SELECT assert_eq('gs quant canonical 1225 gs_quant/test/timeseries/test_statistics.py test_min', fin_gsq_test_test_min('local_payload').payload || ':' || fin_gsq_test_test_min('local_payload').source_function, 'local_payload:test_min');
SELECT assert_eq('gs quant canonical 1226 gs_quant/test/timeseries/test_statistics.py test_max', fin_gsq_test_test_max('local_payload').payload || ':' || fin_gsq_test_test_max('local_payload').source_function, 'local_payload:test_max');
SELECT assert_eq('gs quant canonical 1227 gs_quant/test/timeseries/test_statistics.py test_range', fin_gsq_test_test_range('local_payload').payload || ':' || fin_gsq_test_test_range('local_payload').source_function, 'local_payload:test_range');
SELECT assert_eq('gs quant canonical 1228 gs_quant/test/timeseries/test_statistics.py test_mean', fin_gsq_test_test_mean('local_payload').payload || ':' || fin_gsq_test_test_mean('local_payload').source_function, 'local_payload:test_mean');
SELECT assert_eq('gs quant canonical 1229 gs_quant/test/timeseries/test_statistics.py test_quadratic_mean', fin_gsq_test_test_quadratic_mean('local_payload').payload || ':' || fin_gsq_test_test_quadratic_mean('local_payload').source_function, 'local_payload:test_quadratic_mean');
SELECT assert_eq('gs quant canonical 1230 gs_quant/test/timeseries/test_statistics.py test_median', fin_gsq_test_test_median('local_payload').payload || ':' || fin_gsq_test_test_median('local_payload').source_function, 'local_payload:test_median');
SELECT assert_eq('gs quant canonical 1231 gs_quant/test/timeseries/test_statistics.py test_mode', fin_gsq_test_test_mode('local_payload').payload || ':' || fin_gsq_test_test_mode('local_payload').source_function, 'local_payload:test_mode');
SELECT assert_eq('gs quant canonical 1232 gs_quant/test/timeseries/test_statistics.py test_sum', fin_gsq_test_test_sum('local_payload').payload || ':' || fin_gsq_test_test_sum('local_payload').source_function, 'local_payload:test_sum');
SELECT assert_eq('gs quant canonical 1233 gs_quant/test/timeseries/test_statistics.py test_product', fin_gsq_test_test_product('local_payload').payload || ':' || fin_gsq_test_test_product('local_payload').source_function, 'local_payload:test_product');
SELECT assert_eq('gs quant canonical 1234 gs_quant/test/timeseries/test_statistics.py test_std', fin_gsq_test_test_std('local_payload').payload || ':' || fin_gsq_test_test_std('local_payload').source_function, 'local_payload:test_std');
SELECT assert_eq('gs quant canonical 1235 gs_quant/test/timeseries/test_statistics.py test_exponential_std', fin_gsq_test_test_exponential_std('local_payload').payload || ':' || fin_gsq_test_test_exponential_std('local_payload').source_function, 'local_payload:test_exponential_std');
SELECT assert_eq('gs quant canonical 1236 gs_quant/test/timeseries/test_statistics.py test_var', fin_gsq_test_test_var('local_payload').payload || ':' || fin_gsq_test_test_var('local_payload').source_function, 'local_payload:test_var');
SELECT assert_eq('gs quant canonical 1237 gs_quant/test/timeseries/test_statistics.py test_cov', fin_gsq_test_test_cov('local_payload').payload || ':' || fin_gsq_test_test_cov('local_payload').source_function, 'local_payload:test_cov');
SELECT assert_eq('gs quant canonical 1238 gs_quant/test/timeseries/test_statistics.py test_zscores', fin_gsq_test_test_zscores('local_payload').payload || ':' || fin_gsq_test_test_zscores('local_payload').source_function, 'local_payload:test_zscores');
SELECT assert_eq('gs quant canonical 1239 gs_quant/test/timeseries/test_statistics.py test_winsorize', fin_gsq_test_test_winsorize('local_payload').payload || ':' || fin_gsq_test_test_winsorize('local_payload').source_function, 'local_payload:test_winsorize');
SELECT assert_eq('gs quant canonical 1240 gs_quant/test/timeseries/test_statistics.py test_percentiles', fin_gsq_test_test_percentiles('local_payload').payload || ':' || fin_gsq_test_test_percentiles('local_payload').source_function, 'local_payload:test_percentiles');
SELECT assert_eq('gs quant canonical 1241 gs_quant/test/timeseries/test_statistics.py test_percentile', fin_gsq_test_test_percentile('local_payload').payload || ':' || fin_gsq_test_test_percentile('local_payload').source_function, 'local_payload:test_percentile');
SELECT assert_eq('gs quant canonical 1242 gs_quant/test/timeseries/test_statistics.py test_percentile_str', fin_gsq_test_test_percentile_str('local_payload').payload || ':' || fin_gsq_test_test_percentile_str('local_payload').source_function, 'local_payload:test_percentile_str');
SELECT assert_eq('gs quant canonical 1243 gs_quant/test/timeseries/test_statistics.py test_regression', fin_gsq_test_test_regression('local_payload').payload || ':' || fin_gsq_test_test_regression('local_payload').source_function, 'local_payload:test_regression');
SELECT assert_eq('gs quant canonical 1244 gs_quant/test/timeseries/test_statistics.py test_rolling_linear_regression', fin_gsq_test_test_rolling_linear_regression('local_payload').payload || ':' || fin_gsq_test_test_rolling_linear_regression('local_payload').source_function, 'local_payload:test_rolling_linear_regression');
SELECT assert_eq('gs quant canonical 1245 gs_quant/test/timeseries/test_statistics.py test_sir_model', fin_gsq_test_test_sir_model('local_payload').payload || ':' || fin_gsq_test_test_sir_model('local_payload').source_function, 'local_payload:test_sir_model');
SELECT assert_eq('gs quant canonical 1246 gs_quant/test/timeseries/test_statistics.py test_seir_model', fin_gsq_test_test_seir_model('local_payload').payload || ':' || fin_gsq_test_test_seir_model('local_payload').source_function, 'local_payload:test_seir_model');
SELECT assert_eq('gs quant canonical 1247 gs_quant/test/timeseries/test_tca.py test_covariance', fin_gsq_test_test_covariance('local_payload').payload || ':' || fin_gsq_test_test_covariance('local_payload').source_function, 'local_payload:test_covariance');
SELECT assert_eq('gs quant canonical 1248 gs_quant/test/timeseries/test_technicals.py test_moving_average', fin_gsq_test_test_moving_average('local_payload').payload || ':' || fin_gsq_test_test_moving_average('local_payload').source_function, 'local_payload:test_moving_average');
SELECT assert_eq('gs quant canonical 1249 gs_quant/test/timeseries/test_technicals.py test_smoothed_moving_average', fin_gsq_test_test_smoothed_moving_average('local_payload').payload || ':' || fin_gsq_test_test_smoothed_moving_average('local_payload').source_function, 'local_payload:test_smoothed_moving_average');
SELECT assert_eq('gs quant canonical 1250 gs_quant/test/timeseries/test_technicals.py test_macd', fin_gsq_test_test_macd('local_payload').payload || ':' || fin_gsq_test_test_macd('local_payload').source_function, 'local_payload:test_macd');
SELECT assert_eq('gs quant canonical 1251 gs_quant/test/timeseries/test_technicals.py test_bollinger_bands', fin_gsq_test_test_bollinger_bands('local_payload').payload || ':' || fin_gsq_test_test_bollinger_bands('local_payload').source_function, 'local_payload:test_bollinger_bands');
SELECT assert_eq('gs quant canonical 1252 gs_quant/test/timeseries/test_technicals.py test_relative_strength_index', fin_gsq_test_test_relative_strength_index('local_payload').payload || ':' || fin_gsq_test_test_relative_strength_index('local_payload').source_function, 'local_payload:test_relative_strength_index');
SELECT assert_eq('gs quant canonical 1253 gs_quant/test/timeseries/test_technicals.py test_exponential_moving_average', fin_gsq_test_test_exponential_moving_average('local_payload').payload || ':' || fin_gsq_test_test_exponential_moving_average('local_payload').source_function, 'local_payload:test_exponential_moving_average');
SELECT assert_eq('gs quant canonical 1254 gs_quant/test/timeseries/test_technicals.py test_exponential_volatility', fin_gsq_test_test_exponential_volatility('local_payload').payload || ':' || fin_gsq_test_test_exponential_volatility('local_payload').source_function, 'local_payload:test_exponential_volatility');
SELECT assert_eq('gs quant canonical 1255 gs_quant/test/timeseries/test_technicals.py test_exponential_spread_volatility', fin_gsq_test_test_exponential_spread_volatility('local_payload').payload || ':' || fin_gsq_test_test_exponential_spread_volatility('local_payload').source_function, 'local_payload:test_exponential_spread_volatility');
SELECT assert_eq('gs quant canonical 1256 gs_quant/test/timeseries/test_technicals.py test_trend', fin_gsq_test_test_trend('local_payload').payload || ':' || fin_gsq_test_test_trend('local_payload').source_function, 'local_payload:test_trend');
SELECT assert_eq('gs quant canonical 1257 gs_quant/test/timeseries/test_technicals.py test_seasonality_adjusted', fin_gsq_test_test_seasonality_adjusted('local_payload').payload || ':' || fin_gsq_test_test_seasonality_adjusted('local_payload').source_function, 'local_payload:test_seasonality_adjusted');
SELECT assert_eq('gs quant canonical 1258 gs_quant/test/timeseries/test_timeseries.py ts_map', fin_gsq_test_ts_map('local_payload').payload || ':' || fin_gsq_test_ts_map('local_payload').source_function, 'local_payload:ts_map');
SELECT assert_eq('gs quant canonical 1259 gs_quant/test/timeseries/test_timeseries.py test_have_docstrings', fin_gsq_test_test_have_docstrings('local_payload').payload || ':' || fin_gsq_test_test_have_docstrings('local_payload').source_function, 'local_payload:test_have_docstrings');
SELECT assert_eq('gs quant canonical 1260 gs_quant/test/timeseries/test_timeseries.py test_window_to_from_dict', fin_gsq_test_test_window_to_from_dict('local_payload').payload || ':' || fin_gsq_test_test_window_to_from_dict('local_payload').source_function, 'local_payload:test_window_to_from_dict');
SELECT assert_eq('gs quant canonical 1261 gs_quant/test/timeseries/test_timeseries.py test_docstrings', fin_gsq_test_test_docstrings('local_payload').payload || ':' || fin_gsq_test_test_docstrings('local_payload').source_function, 'local_payload:test_docstrings');
SELECT assert_eq('gs quant canonical 1262 gs_quant/test/timeseries/test_timeseries.py test_annotations', fin_gsq_test_test_annotations('local_payload').payload || ':' || fin_gsq_test_test_annotations('local_payload').source_function, 'local_payload:test_annotations');
SELECT assert_eq('gs quant canonical 1263 gs_quant/test/timeseries/test_timeseries.py test_measures', fin_gsq_test_test_measures('local_payload').payload || ':' || fin_gsq_test_test_measures('local_payload').source_function, 'local_payload:test_measures');
SELECT assert_eq('gs quant canonical 1264 gs_quant/test/timeseries/test_timeseries.py test_measures_on_entities', fin_gsq_test_test_measures_on_entities('local_payload').payload || ':' || fin_gsq_test_test_measures_on_entities('local_payload').source_function, 'local_payload:test_measures_on_entities');
SELECT assert_eq('gs quant canonical 1265 gs_quant/test/timeseries/utils.py handle_response', fin_gsq_test_handle_response('local_payload').payload || ':' || fin_gsq_test_handle_response('local_payload').source_function, 'local_payload:handle_response');
SELECT assert_eq('gs quant canonical 1266 gs_quant/test/timeseries/utils.py mock_request', fin_gsq_test_mock_request('local_payload').payload || ':' || fin_gsq_test_mock_request('local_payload').source_function, 'local_payload:mock_request');
SELECT assert_eq('gs quant canonical 1267 gs_quant/test/tracing/test_tracing.py make_zero_duration', fin_gsq_test_make_zero_duration('local_payload').payload || ':' || fin_gsq_test_make_zero_duration('local_payload').source_function, 'local_payload:make_zero_duration');
SELECT assert_eq('gs quant canonical 1268 gs_quant/test/tracing/test_tracing.py test_tracer_tags', fin_gsq_test_test_tracer_tags('local_payload').payload || ':' || fin_gsq_test_test_tracer_tags('local_payload').source_function, 'local_payload:test_tracer_tags');
SELECT assert_eq('gs quant canonical 1269 gs_quant/test/tracing/test_tracing.py test_tracer_events', fin_gsq_test_test_tracer_events('local_payload').payload || ':' || fin_gsq_test_test_tracer_events('local_payload').source_function, 'local_payload:test_tracer_events');
SELECT assert_eq('gs quant canonical 1270 gs_quant/test/tracing/test_tracing.py test_tracer_print', fin_gsq_test_test_tracer_print('local_payload').payload || ':' || fin_gsq_test_test_tracer_print('local_payload').source_function, 'local_payload:test_tracer_print');
SELECT assert_eq('gs quant canonical 1271 gs_quant/test/tracing/test_tracing.py test_tracer_plot', fin_gsq_test_test_tracer_plot('local_payload').payload || ':' || fin_gsq_test_test_tracer_plot('local_payload').source_function, 'local_payload:test_tracer_plot');
SELECT assert_eq('gs quant canonical 1272 gs_quant/test/tracing/test_tracing.py test_gather_when_multi_traces', fin_gsq_test_test_gather_when_multi_traces('local_payload').payload || ':' || fin_gsq_test_test_gather_when_multi_traces('local_payload').source_function, 'local_payload:test_gather_when_multi_traces');
SELECT assert_eq('gs quant canonical 1273 gs_quant/test/tracing/test_tracing.py test_tracer_wrapped_error', fin_gsq_test_test_tracer_wrapped_error('local_payload').payload || ':' || fin_gsq_test_test_tracer_wrapped_error('local_payload').source_function, 'local_payload:test_tracer_wrapped_error');
SELECT assert_eq('gs quant canonical 1274 gs_quant/test/tracing/test_tracing.py test_active_span', fin_gsq_test_test_active_span('local_payload').payload || ':' || fin_gsq_test_test_active_span('local_payload').source_function, 'local_payload:test_active_span');
SELECT assert_eq('gs quant canonical 1275 gs_quant/test/tracing/test_tracing.py test_span_activation', fin_gsq_test_test_span_activation('local_payload').payload || ':' || fin_gsq_test_test_span_activation('local_payload').source_function, 'local_payload:test_span_activation');
SELECT assert_eq('gs quant canonical 1276 gs_quant/test/tracing/test_tracing.py test_inject_extract', fin_gsq_test_test_inject_extract('local_payload').payload || ':' || fin_gsq_test_test_inject_extract('local_payload').source_function, 'local_payload:test_inject_extract');
SELECT assert_eq('gs quant canonical 1277 gs_quant/test/tracing/test_tracing.py test_ignore_active_span', fin_gsq_test_test_ignore_active_span('local_payload').payload || ':' || fin_gsq_test_test_ignore_active_span('local_payload').source_function, 'local_payload:test_ignore_active_span');
SELECT assert_eq('gs quant canonical 1278 gs_quant/test/tracing/test_tracing.py test_callback_in_scope', fin_gsq_test_test_callback_in_scope('local_payload').payload || ':' || fin_gsq_test_test_callback_in_scope('local_payload').source_function, 'local_payload:test_callback_in_scope');
SELECT assert_eq('gs quant canonical 1279 gs_quant/test/utils/datagrid_test_utils.py get_test_entity', fin_gsq_test_get_test_entity('local_payload').payload || ':' || fin_gsq_test_get_test_entity('local_payload').source_function, 'local_payload:get_test_entity');
SELECT assert_eq('gs quant canonical 1280 gs_quant/test/utils/mock_calc.py get_risk_request_id', fin_gsq_test_get_risk_request_id('local_payload').payload || ':' || fin_gsq_test_get_risk_request_id('local_payload').source_function, 'local_payload:get_risk_request_id');
SELECT assert_eq('gs quant canonical 1281 gs_quant/test/utils/test_utils.py test_fix_mock_data', fin_gsq_test_test_fix_mock_data('local_payload').payload || ':' || fin_gsq_test_test_fix_mock_data('local_payload').source_function, 'local_payload:test_fix_mock_data');
SELECT assert_eq('gs quant canonical 1282 gs_quant/test/utils/test_utils.py test_mock_data_file_sanity', fin_gsq_test_test_mock_data_file_sanity('local_payload').payload || ':' || fin_gsq_test_test_mock_data_file_sanity('local_payload').source_function, 'local_payload:test_mock_data_file_sanity');
SELECT assert_eq('gs quant canonical 1283 gs_quant/test/utils/test_utils.py load_json_from_resource', fin_gsq_test_load_json_from_resource('local_payload').payload || ':' || fin_gsq_test_load_json_from_resource('local_payload').source_function, 'local_payload:load_json_from_resource');
SELECT assert_eq('gs quant canonical 1284 gs_quant/test/utils/test_utils.py mock_request', fin_gsq_test_mock_request_test_utils_test_utils('local_payload').payload || ':' || fin_gsq_test_mock_request_test_utils_test_utils('local_payload').source_function, 'local_payload:mock_request');
SELECT assert_eq('gs quant canonical 1285 gs_quant/timeseries/backtesting.py backtest_basket', fin_gsq_timeseries_backtest_basket('local_payload').payload || ':' || fin_gsq_timeseries_backtest_basket('local_payload').source_function, 'local_payload:backtest_basket');
SELECT assert_eq('gs quant canonical 1286 gs_quant/timeseries/econometrics.py excess_returns_pure', fin_gsq_timeseries_excess_returns_pure('local_payload').payload || ':' || fin_gsq_timeseries_excess_returns_pure('local_payload').source_function, 'local_payload:excess_returns_pure');
SELECT assert_eq('gs quant canonical 1287 gs_quant/timeseries/econometrics.py excess_returns', fin_gsq_timeseries_excess_returns('local_payload').payload || ':' || fin_gsq_timeseries_excess_returns('local_payload').source_function, 'local_payload:excess_returns');
SELECT assert_eq('gs quant canonical 1288 gs_quant/timeseries/econometrics.py get_ratio_pure', fin_gsq_timeseries_get_ratio_pure('local_payload').payload || ':' || fin_gsq_timeseries_get_ratio_pure('local_payload').source_function, 'local_payload:get_ratio_pure');
SELECT assert_eq('gs quant canonical 1289 gs_quant/timeseries/econometrics.py excess_returns_', fin_gsq_timeseries_excess_returns_timeseries_econometrics('local_payload').payload || ':' || fin_gsq_timeseries_excess_returns_timeseries_econometrics('local_payload').source_function, 'local_payload:excess_returns_');
SELECT assert_eq('gs quant canonical 1290 gs_quant/timeseries/econometrics.py sharpe_ratio', fin_gsq_timeseries_sharpe_ratio('local_payload').payload || ':' || fin_gsq_timeseries_sharpe_ratio('local_payload').source_function, 'local_payload:sharpe_ratio');
SELECT assert_eq('gs quant canonical 1291 gs_quant/timeseries/helper.py apply_ramp', fin_gsq_timeseries_apply_ramp('local_payload').payload || ':' || fin_gsq_timeseries_apply_ramp('local_payload').source_function, 'local_payload:apply_ramp');
SELECT assert_eq('gs quant canonical 1292 gs_quant/timeseries/helper.py normalize_window', fin_gsq_timeseries_normalize_window('local_payload').payload || ':' || fin_gsq_timeseries_normalize_window('local_payload').source_function, 'local_payload:normalize_window');
SELECT assert_eq('gs quant canonical 1293 gs_quant/timeseries/helper.py plot_function', fin_gsq_timeseries_plot_function('local_payload').payload || ':' || fin_gsq_timeseries_plot_function('local_payload').source_function, 'local_payload:plot_function');
SELECT assert_eq('gs quant canonical 1294 gs_quant/timeseries/helper.py plot_session_function', fin_gsq_timeseries_plot_session_function('local_payload').payload || ':' || fin_gsq_timeseries_plot_session_function('local_payload').source_function, 'local_payload:plot_session_function');
SELECT assert_eq('gs quant canonical 1295 gs_quant/timeseries/helper.py check_forward_looking', fin_gsq_timeseries_check_forward_looking('local_payload').payload || ':' || fin_gsq_timeseries_check_forward_looking('local_payload').source_function, 'local_payload:check_forward_looking');
SELECT assert_eq('gs quant canonical 1296 gs_quant/timeseries/helper.py plot_measure', fin_gsq_timeseries_plot_measure('local_payload').payload || ':' || fin_gsq_timeseries_plot_measure('local_payload').source_function, 'local_payload:plot_measure');
SELECT assert_eq('gs quant canonical 1297 gs_quant/timeseries/helper.py plot_measure_entity', fin_gsq_timeseries_plot_measure_entity('local_payload').payload || ':' || fin_gsq_timeseries_plot_measure_entity('local_payload').source_function, 'local_payload:plot_measure_entity');
SELECT assert_eq('gs quant canonical 1298 gs_quant/timeseries/helper.py requires_session', fin_gsq_timeseries_requires_session('local_payload').payload || ':' || fin_gsq_timeseries_requires_session('local_payload').source_function, 'local_payload:requires_session');
SELECT assert_eq('gs quant canonical 1299 gs_quant/timeseries/helper.py plot_method', fin_gsq_timeseries_plot_method('local_payload').payload || ':' || fin_gsq_timeseries_plot_method('local_payload').source_function, 'local_payload:plot_method');
SELECT assert_eq('gs quant canonical 1300 gs_quant/timeseries/helper.py get_df_with_retries', fin_gsq_timeseries_get_df_with_retries('local_payload').payload || ':' || fin_gsq_timeseries_get_df_with_retries('local_payload').source_function, 'local_payload:get_df_with_retries');
SELECT assert_eq('gs quant canonical 1301 gs_quant/timeseries/helper.py get_dataset_data_with_retries', fin_gsq_timeseries_get_dataset_data_with_retries('local_payload').payload || ':' || fin_gsq_timeseries_get_dataset_data_with_retries('local_payload').source_function, 'local_payload:get_dataset_data_with_retries');
SELECT assert_eq('gs quant canonical 1302 gs_quant/timeseries/helper.py get_dataset_with_many_assets', fin_gsq_timeseries_get_dataset_with_many_assets('local_payload').payload || ':' || fin_gsq_timeseries_get_dataset_with_many_assets('local_payload').source_function, 'local_payload:get_dataset_with_many_assets');
SELECT assert_eq('gs quant canonical 1303 gs_quant/timeseries/helper.py rolling_offset', fin_gsq_timeseries_rolling_offset('local_payload').payload || ':' || fin_gsq_timeseries_rolling_offset('local_payload').source_function, 'local_payload:rolling_offset');
SELECT assert_eq('gs quant canonical 1304 gs_quant/timeseries/measure_registry.py register_measure', fin_gsq_timeseries_register_measure('local_payload').payload || ':' || fin_gsq_timeseries_register_measure('local_payload').source_function, 'local_payload:register_measure');
SELECT assert_eq('gs quant canonical 1305 gs_quant/timeseries/measures.py cross_stored_direction_for_fx_vol', fin_gsq_timeseries_cross_stored_direction_for_fx_vol('local_payload').payload || ':' || fin_gsq_timeseries_cross_stored_direction_for_fx_vol('local_payload').source_function, 'local_payload:cross_stored_direction_for_fx_vol');
SELECT assert_eq('gs quant canonical 1306 gs_quant/timeseries/measures.py cross_to_usd_based_cross', fin_gsq_timeseries_cross_to_usd_based_cross('local_payload').payload || ':' || fin_gsq_timeseries_cross_to_usd_based_cross('local_payload').source_function, 'local_payload:cross_to_usd_based_cross');
SELECT assert_eq('gs quant canonical 1307 gs_quant/timeseries/measures.py currency_to_default_benchmark_rate', fin_gsq_timeseries_currency_to_default_benchmark_rate('local_payload').payload || ':' || fin_gsq_timeseries_currency_to_default_benchmark_rate('local_payload').source_function, 'local_payload:currency_to_default_benchmark_rate');
SELECT assert_eq('gs quant canonical 1308 gs_quant/timeseries/measures.py currency_to_default_ois_asset', fin_gsq_timeseries_currency_to_default_ois_asset('local_payload').payload || ':' || fin_gsq_timeseries_currency_to_default_ois_asset('local_payload').source_function, 'local_payload:currency_to_default_ois_asset');
SELECT assert_eq('gs quant canonical 1309 gs_quant/timeseries/measures.py currency_to_default_swap_rate_asset', fin_gsq_timeseries_currency_to_default_swap_rate_asset('local_payload').payload || ':' || fin_gsq_timeseries_currency_to_default_swap_rate_asset('local_payload').source_function, 'local_payload:currency_to_default_swap_rate_asset');
SELECT assert_eq('gs quant canonical 1310 gs_quant/timeseries/measures.py currency_to_inflation_benchmark_rate', fin_gsq_timeseries_currency_to_inflation_benchmark_rate('local_payload').payload || ':' || fin_gsq_timeseries_currency_to_inflation_benchmark_rate('local_payload').source_function, 'local_payload:currency_to_inflation_benchmark_rate');
SELECT assert_eq('gs quant canonical 1311 gs_quant/timeseries/measures.py cross_to_basis', fin_gsq_timeseries_cross_to_basis('local_payload').payload || ':' || fin_gsq_timeseries_cross_to_basis('local_payload').source_function, 'local_payload:cross_to_basis');
SELECT assert_eq('gs quant canonical 1312 gs_quant/timeseries/measures.py convert_asset_for_rates_data_set', fin_gsq_timeseries_convert_asset_for_rates_data_set('local_payload').payload || ':' || fin_gsq_timeseries_convert_asset_for_rates_data_set('local_payload').source_function, 'local_payload:convert_asset_for_rates_data_set');
SELECT assert_eq('gs quant canonical 1313 gs_quant/timeseries/measures.py measure_request_safe', fin_gsq_timeseries_measure_request_safe('local_payload').payload || ':' || fin_gsq_timeseries_measure_request_safe('local_payload').source_function, 'local_payload:measure_request_safe');
SELECT assert_eq('gs quant canonical 1314 gs_quant/timeseries/measures.py get_weights_for_contracts', fin_gsq_timeseries_get_weights_for_contracts('local_payload').payload || ':' || fin_gsq_timeseries_get_weights_for_contracts('local_payload').source_function, 'local_payload:get_weights_for_contracts');
SELECT assert_eq('gs quant canonical 1315 gs_quant/timeseries/measures.py eu_ng_hub_to_swap', fin_gsq_timeseries_eu_ng_hub_to_swap('local_payload').payload || ':' || fin_gsq_timeseries_eu_ng_hub_to_swap('local_payload').source_function, 'local_payload:eu_ng_hub_to_swap');
SELECT assert_eq('gs quant canonical 1316 gs_quant/timeseries/measures.py get_contract_range', fin_gsq_timeseries_get_contract_range('local_payload').payload || ':' || fin_gsq_timeseries_get_contract_range('local_payload').source_function, 'local_payload:get_contract_range');
SELECT assert_eq('gs quant canonical 1317 gs_quant/timeseries/measures.py get_last_for_measure', fin_gsq_timeseries_get_last_for_measure('local_payload').payload || ':' || fin_gsq_timeseries_get_last_for_measure('local_payload').source_function, 'local_payload:get_last_for_measure');
SELECT assert_eq('gs quant canonical 1318 gs_quant/timeseries/measures.py merge_dataframes', fin_gsq_timeseries_merge_dataframes('local_payload').payload || ':' || fin_gsq_timeseries_merge_dataframes('local_payload').source_function, 'local_payload:merge_dataframes');
SELECT assert_eq('gs quant canonical 1319 gs_quant/timeseries/measures.py append_last_for_measure', fin_gsq_timeseries_append_last_for_measure('local_payload').payload || ':' || fin_gsq_timeseries_append_last_for_measure('local_payload').source_function, 'local_payload:append_last_for_measure');
SELECT assert_eq('gs quant canonical 1320 gs_quant/timeseries/measures.py get_market_data_tasks', fin_gsq_timeseries_get_market_data_tasks('local_payload').payload || ':' || fin_gsq_timeseries_get_market_data_tasks('local_payload').source_function, 'local_payload:get_market_data_tasks');
SELECT assert_eq('gs quant canonical 1321 gs_quant/timeseries/measures.py get_historical_and_last_for_measure', fin_gsq_timeseries_get_historical_and_last_for_measure('local_payload').payload || ':' || fin_gsq_timeseries_get_historical_and_last_for_measure('local_payload').source_function, 'local_payload:get_historical_and_last_for_measure');
SELECT assert_eq('gs quant canonical 1322 gs_quant/timeseries/measures_fx_vol.py get_fxo_asset', fin_gsq_timeseries_get_fxo_asset('local_payload').payload || ':' || fin_gsq_timeseries_get_fxo_asset('local_payload').source_function, 'local_payload:get_fxo_asset');
SELECT assert_eq('gs quant canonical 1323 gs_quant/timeseries/measures_fx_vol.py cross_stored_direction_for_fx_vol', fin_gsq_timeseries_cross_stored_direction_for_fx_vol_timeseries_measures_fx_vol('local_payload').payload || ':' || fin_gsq_timeseries_cross_stored_direction_for_fx_vol_timeseries_measures_fx_vol('local_payload').source_function, 'local_payload:cross_stored_direction_for_fx_vol');
SELECT assert_eq('gs quant canonical 1324 gs_quant/timeseries/measures_fx_vol.py implied_volatility_new', fin_gsq_timeseries_implied_volatility_new('local_payload').payload || ':' || fin_gsq_timeseries_implied_volatility_new('local_payload').source_function, 'local_payload:implied_volatility_new');
SELECT assert_eq('gs quant canonical 1325 gs_quant/timeseries/measures_helper.py preprocess_implied_vol_strikes_eq', fin_gsq_timeseries_preprocess_implied_vol_strikes_eq('local_payload').payload || ':' || fin_gsq_timeseries_preprocess_implied_vol_strikes_eq('local_payload').source_function, 'local_payload:preprocess_implied_vol_strikes_eq');
SELECT assert_eq('gs quant canonical 1326 gs_quant/timeseries/measures_rates.py get_cb_swaps_kwargs', fin_gsq_timeseries_get_cb_swaps_kwargs('local_payload').payload || ':' || fin_gsq_timeseries_get_cb_swaps_kwargs('local_payload').source_function, 'local_payload:get_cb_swaps_kwargs');
SELECT assert_eq('gs quant canonical 1327 gs_quant/timeseries/measures_rates.py get_cb_meeting_swaps', fin_gsq_timeseries_get_cb_meeting_swaps('local_payload').payload || ':' || fin_gsq_timeseries_get_cb_meeting_swaps('local_payload').source_function, 'local_payload:get_cb_meeting_swaps');
SELECT assert_eq('gs quant canonical 1328 gs_quant/timeseries/measures_rates.py get_cb_meeting_swap', fin_gsq_timeseries_get_cb_meeting_swap('local_payload').payload || ':' || fin_gsq_timeseries_get_cb_meeting_swap('local_payload').source_function, 'local_payload:get_cb_meeting_swap');
SELECT assert_eq('gs quant canonical 1329 gs_quant/timeseries/measures_rates.py get_cb_swap_data', fin_gsq_timeseries_get_cb_swap_data('local_payload').payload || ':' || fin_gsq_timeseries_get_cb_swap_data('local_payload').source_function, 'local_payload:get_cb_swap_data');
SELECT assert_eq('gs quant canonical 1330 gs_quant/timeseries/measures_rates.py parse_meeting_date', fin_gsq_timeseries_parse_meeting_date('local_payload').payload || ':' || fin_gsq_timeseries_parse_meeting_date('local_payload').source_function, 'local_payload:parse_meeting_date');
SELECT assert_eq('gs quant canonical 1331 gs_quant/timeseries/measures_rates.py policy_rate_expectation_rt', fin_gsq_timeseries_policy_rate_expectation_rt('local_payload').payload || ':' || fin_gsq_timeseries_policy_rate_expectation_rt('local_payload').source_function, 'local_payload:policy_rate_expectation_rt');
SELECT assert_eq('gs quant canonical 1332 gs_quant/timeseries/measures_rates.py policy_rate_term_structure_rt', fin_gsq_timeseries_policy_rate_term_structure_rt('local_payload').payload || ':' || fin_gsq_timeseries_policy_rate_term_structure_rt('local_payload').source_function, 'local_payload:policy_rate_term_structure_rt');
SELECT assert_eq('gs quant canonical 1333 gs_quant/tracing/tracing.py parse_tracing_line_args', fin_gsq_support_parse_tracing_line_args('local_payload').payload || ':' || fin_gsq_support_parse_tracing_line_args('local_payload').source_function, 'local_payload:parse_tracing_line_args');
SELECT assert_eq('gs quant compatibility 0001 gs_quant/__init__.py get_environment_summary', gs_support_get_environment_summary().canonical, 'fin_gsq_support_get_environment_summary');
SELECT assert_eq('gs quant compatibility 0002 gs_quant/_version.py get_keywords', gs_support_get_keywords().canonical, 'fin_gsq_support_get_keywords');
SELECT assert_eq('gs quant compatibility 0003 gs_quant/_version.py get_config', gs_support_get_config().canonical, 'fin_gsq_support_get_config');
SELECT assert_eq('gs quant compatibility 0004 gs_quant/_version.py register_vcs_handler', gs_support_register_vcs_handler().canonical, 'fin_gsq_support_register_vcs_handler');
SELECT assert_eq('gs quant compatibility 0005 gs_quant/_version.py run_command', gs_support_run_command().canonical, 'fin_gsq_support_run_command');
SELECT assert_eq('gs quant compatibility 0006 gs_quant/_version.py versions_from_parentdir', gs_support_versions_from_parentdir().canonical, 'fin_gsq_support_versions_from_parentdir');
SELECT assert_eq('gs quant compatibility 0007 gs_quant/_version.py git_get_keywords', gs_support_git_get_keywords().canonical, 'fin_gsq_support_git_get_keywords');
SELECT assert_eq('gs quant compatibility 0008 gs_quant/_version.py git_versions_from_keywords', gs_support_gitversions_from_keywords().canonical, 'fin_gsq_support_gitversions_from_keywords');
SELECT assert_eq('gs quant compatibility 0009 gs_quant/_version.py git_pieces_from_vcs', gs_support_git_pieces_from_vcs().canonical, 'fin_gsq_support_git_pieces_from_vcs');
SELECT assert_eq('gs quant compatibility 0010 gs_quant/_version.py plus_or_dot', gs_support_plus_or_dot().canonical, 'fin_gsq_support_plus_or_dot');
SELECT assert_eq('gs quant compatibility 0011 gs_quant/_version.py render_pep440', gs_support_render_pep440().canonical, 'fin_gsq_support_render_pep440');
SELECT assert_eq('gs quant compatibility 0012 gs_quant/_version.py render_pep440_branch', gs_support_render_pep440_branch().canonical, 'fin_gsq_support_render_pep440_branch');
SELECT assert_eq('gs quant compatibility 0013 gs_quant/_version.py pep440_split_post', gs_support_pep440_split_post().canonical, 'fin_gsq_support_pep440_split_post');
SELECT assert_eq('gs quant compatibility 0014 gs_quant/_version.py render_pep440_pre', gs_support_render_pep440_pre().canonical, 'fin_gsq_support_render_pep440_pre');
SELECT assert_eq('gs quant compatibility 0015 gs_quant/_version.py render_pep440_post', gs_support_render_pep440_post().canonical, 'fin_gsq_support_render_pep440_post');
SELECT assert_eq('gs quant compatibility 0016 gs_quant/_version.py render_pep440_post_branch', gs_support_render_pep440_post_branch().canonical, 'fin_gsq_support_render_pep440_post_branch');
SELECT assert_eq('gs quant compatibility 0017 gs_quant/_version.py render_pep440_old', gs_support_render_pep440_old().canonical, 'fin_gsq_support_render_pep440_old');
SELECT assert_eq('gs quant compatibility 0018 gs_quant/_version.py render_git_describe', gs_support_render_git_describe().canonical, 'fin_gsq_support_render_git_describe');
SELECT assert_eq('gs quant compatibility 0019 gs_quant/_version.py render_git_describe_long', gs_support_render_git_describe_long().canonical, 'fin_gsq_support_render_git_describe_long');
SELECT assert_eq('gs quant compatibility 0020 gs_quant/_version.py render', gs_support_render().canonical, 'fin_gsq_support_render');
SELECT assert_eq('gs quant compatibility 0021 gs_quant/_version.py get_versions', gs_support_getversions().canonical, 'fin_gsq_support_getversions');
SELECT assert_eq('gs quant compatibility 0022 gs_quant/analytics/common/helpers.py is_of_builtin_type', gs_content_is_of_builtin_type().canonical, 'fin_content_is_of_builtin_type');
SELECT assert_eq('gs quant compatibility 0023 gs_quant/analytics/common/helpers.py resolve_entities', gs_content_resolve_entities().canonical, 'fin_content_resolve_entities');
SELECT assert_eq('gs quant compatibility 0024 gs_quant/analytics/common/helpers.py get_rdate_cache_key', gs_content_get_rdate_cache_key().canonical, 'fin_content_get_rdate_cache_key');
SELECT assert_eq('gs quant compatibility 0025 gs_quant/analytics/common/helpers.py get_entity_rdate_key', gs_content_get_entity_rdate_key().canonical, 'fin_content_get_entity_rdate_key');
SELECT assert_eq('gs quant compatibility 0026 gs_quant/analytics/common/helpers.py get_entity_rdate_key_from_rdate', gs_content_get_entity_rdate_key_from_rdate().canonical, 'fin_content_get_entity_rdate_key_from_rdate');
SELECT assert_eq('gs quant compatibility 0027 gs_quant/analytics/core/query_helpers.py aggregate_queries', gs_content_aggregate_queries().canonical, 'fin_content_aggregate_queries');
SELECT assert_eq('gs quant compatibility 0028 gs_quant/analytics/core/query_helpers.py fetch_query', gs_content_fetch_query().canonical, 'fin_content_fetch_query');
SELECT assert_eq('gs quant compatibility 0029 gs_quant/analytics/core/query_helpers.py build_query_string', gs_content_build_query_string().canonical, 'fin_content_build_query_string');
SELECT assert_eq('gs quant compatibility 0030 gs_quant/analytics/core/query_helpers.py valid_dimensions', gs_content_valid_dimensions().canonical, 'fin_content_valid_dimensions');
SELECT assert_eq('gs quant compatibility 0031 gs_quant/analytics/datagrid/serializers.py row_from_dict', gs_content_row_from_dict().canonical, 'fin_content_row_from_dict');
SELECT assert_eq('gs quant compatibility 0032 gs_quant/analytics/datagrid/utils.py get_utc_now', gs_content_get_utc_now().canonical, 'fin_content_get_utc_now');
SELECT assert_eq('gs quant compatibility 0033 gs_quant/analytics/processors/scale_processors.py validate_markers_data', gs_content_validate_markers_data().canonical, 'fin_content_validate_markers_data');
SELECT assert_eq('gs quant compatibility 0034 gs_quant/api/gs/assets.py get_default_cache', gs_api_get_default_cache().canonical, 'fin_api_get_default_cache');
SELECT assert_eq('gs quant compatibility 0035 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py encode_request_object', gs_api_encode_request_object().canonical, 'fin_api_encode_request_object');
SELECT assert_eq('gs quant compatibility 0036 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py legs_decoder', gs_api_legs_decoder().canonical, 'fin_api_legs_decoder');
SELECT assert_eq('gs quant compatibility 0037 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py legs_encoder', gs_api_legs_encoder().canonical, 'fin_api_legs_encoder');
SELECT assert_eq('gs quant compatibility 0038 gs_quant/api/gs/backtests_xasset/json_encoders/request_encoders.py enum_decode', gs_api_enum_decode().canonical, 'fin_api_enum_decode');
SELECT assert_eq('gs quant compatibility 0039 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/generic_datatype_encoders.py decode_inst', gs_api_decode_inst().canonical, 'fin_api_decode_inst');
SELECT assert_eq('gs quant compatibility 0040 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/generic_datatype_encoders.py decode_inst_tuple', gs_api_decode_inst_tuple().canonical, 'fin_api_decode_inst_tuple');
SELECT assert_eq('gs quant compatibility 0041 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/generic_datatype_encoders.py decode_daily_portfolio', gs_api_decode_daily_portfolio().canonical, 'fin_api_decode_daily_portfolio');
SELECT assert_eq('gs quant compatibility 0042 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py encode_series_result', gs_api_encode_series_result().canonical, 'fin_api_encode_series_result');
SELECT assert_eq('gs quant compatibility 0043 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py encode_dataframe_result', gs_api_encode_dataframe_result().canonical, 'fin_api_encode_dataframe_result');
SELECT assert_eq('gs quant compatibility 0044 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py decode_series_result', gs_api_decode_series_result().canonical, 'fin_api_decode_series_result');
SELECT assert_eq('gs quant compatibility 0045 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_datatype_encoders.py decode_dataframe_result', gs_api_decode_dataframe_result().canonical, 'fin_api_decode_dataframe_result');
SELECT assert_eq('gs quant compatibility 0046 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_encoders.py map_result_to_datatype', gs_api_map_result_to_datatype().canonical, 'fin_api_map_result_to_datatype');
SELECT assert_eq('gs quant compatibility 0047 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_encoders.py decode_risk_result_with_data', gs_api_decode_risk_result_with_data().canonical, 'fin_api_decode_risk_result_with_data');
SELECT assert_eq('gs quant compatibility 0048 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/risk_result_encoders.py decode_risk_result', gs_api_decode_risk_result().canonical, 'fin_api_decode_risk_result');
SELECT assert_eq('gs quant compatibility 0049 gs_quant/api/gs/backtests_xasset/json_encoders/response_datatypes/test_backtest_datatypes_encoders.py test_transaction_cost_config_encoding', gs_api_test_transaction_cost_config_encoding().canonical, 'fin_api_test_transaction_cost_config_encoding');
SELECT assert_eq('gs quant compatibility 0050 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py encode_response_obj', gs_api_encode_response_obj().canonical, 'fin_api_encode_response_obj');
SELECT assert_eq('gs quant compatibility 0051 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_leg_refs', gs_api_decode_leg_refs().canonical, 'fin_api_decode_leg_refs');
SELECT assert_eq('gs quant compatibility 0052 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_risk_measure_refs', gs_api_decode_risk_measure_refs().canonical, 'fin_api_decode_risk_measure_refs');
SELECT assert_eq('gs quant compatibility 0053 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_result_tuple', gs_api_decode_result_tuple().canonical, 'fin_api_decode_result_tuple');
SELECT assert_eq('gs quant compatibility 0054 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_basic_bt_measure_dict', gs_api_decode_basic_bt_measure_dict().canonical, 'fin_api_decode_basic_bt_measure_dict');
SELECT assert_eq('gs quant compatibility 0055 gs_quant/api/gs/backtests_xasset/json_encoders/response_encoders.py decode_basic_bt_transactions', gs_api_decode_basic_bt_transactions().canonical, 'fin_api_decode_basic_bt_transactions');
SELECT assert_eq('gs quant compatibility 0056 gs_quant/api/gs/backtests_xasset/response_datatypes/backtest_datatypes.py decode_trade_event_tuple_dict', gs_api_decode_trade_event_tuple_dict().canonical, 'fin_api_decode_trade_event_tuple_dict');
SELECT assert_eq('gs quant compatibility 0057 gs_quant/api/gs/backtests_xasset/response_datatypes/backtest_datatypes.py basic_tc_tuple_decoder', gs_api_basic_tc_tuple_decoder().canonical, 'fin_api_basic_tc_tuple_decoder');
SELECT assert_eq('gs quant compatibility 0058 gs_quant/api/gs/backtests_xasset/response_datatypes/backtest_datatypes.py tcm_decoder', gs_api_tcm_decoder().canonical, 'fin_api_tcm_decoder');
SELECT assert_eq('gs quant compatibility 0059 gs_quant/api/gs/backtests_xasset/response_datatypes/generic_backtest_datatypes.py decode_strategy', gs_api_decode_strategy().canonical, 'fin_api_decode_strategy');
SELECT assert_eq('gs quant compatibility 0060 gs_quant/api/utils.py handle_proxy', gs_api_handle_proxy().canonical, 'fin_api_handle_proxy');
SELECT assert_eq('gs quant compatibility 0061 gs_quant/backtests/actions.py default_transaction_cost', gs_backtest_default_transaction_cost().canonical, 'fin_backtest_default_transaction_cost');
SELECT assert_eq('gs quant compatibility 0062 gs_quant/backtests/backtest_objects.py fx_pnl_definition', gs_backtest_fx_pnl_definition().canonical, 'fin_backtest_fx_pnl_definition');
SELECT assert_eq('gs quant compatibility 0063 gs_quant/backtests/backtest_utils.py encode_duration', gs_backtest_encode_duration().canonical, 'fin_backtest_encode_duration');
SELECT assert_eq('gs quant compatibility 0064 gs_quant/backtests/backtest_utils.py decode_duration', gs_backtest_decode_duration().canonical, 'fin_backtest_decode_duration');
SELECT assert_eq('gs quant compatibility 0065 gs_quant/backtests/backtest_utils.py make_list', gs_backtest_make_list().canonical, 'fin_backtest_make_list');
SELECT assert_eq('gs quant compatibility 0066 gs_quant/backtests/backtest_utils.py get_final_date', gs_backtest_get_final_date().canonical, 'fin_backtest_get_final_date');
SELECT assert_eq('gs quant compatibility 0067 gs_quant/backtests/backtest_utils.py scale_trade', gs_backtest_scale_trade().canonical, 'fin_backtest_scale_trade');
SELECT assert_eq('gs quant compatibility 0068 gs_quant/backtests/backtest_utils.py map_ccy_name_to_ccy', gs_backtest_map_ccy_name_to_ccy().canonical, 'fin_backtest_map_ccy_name_to_ccy');
SELECT assert_eq('gs quant compatibility 0069 gs_quant/backtests/backtest_utils.py interpolate_signal', gs_backtest_interpolate_signal().canonical, 'fin_backtest_interpolate_signal');
SELECT assert_eq('gs quant compatibility 0070 gs_quant/backtests/decorator.py plot_backtest', gs_backtest_plot_backtest().canonical, 'fin_backtest_plot_backtest');
SELECT assert_eq('gs quant compatibility 0071 gs_quant/backtests/equity_vol_engine.py get_backtest_trading_quantity_type', gs_backtest_get_backtest_trading_quantity_type().canonical, 'fin_backtest_get_backtest_trading_quantity_type');
SELECT assert_eq('gs quant compatibility 0072 gs_quant/backtests/equity_vol_engine.py is_synthetic_forward', gs_backtest_is_synthetic_forward().canonical, 'fin_backtest_is_synthetic_forward');
SELECT assert_eq('gs quant compatibility 0073 gs_quant/backtests/generic_engine.py raiser', gs_backtest_raiser().canonical, 'fin_backtest_raiser');
SELECT assert_eq('gs quant compatibility 0074 gs_quant/backtests/triggers.py check_barrier', gs_backtest_check_barrier().canonical, 'fin_backtest_check_barrier');
SELECT assert_eq('gs quant compatibility 0075 gs_quant/base.py exclude_none', gs_support_exclude_none().canonical, 'fin_gsq_support_exclude_none');
SELECT assert_eq('gs quant compatibility 0076 gs_quant/base.py exclude_always', gs_support_exclude_always().canonical, 'fin_gsq_support_exclude_always');
SELECT assert_eq('gs quant compatibility 0077 gs_quant/base.py is_iterable', gs_support_is_iterable().canonical, 'fin_gsq_support_is_iterable');
SELECT assert_eq('gs quant compatibility 0078 gs_quant/base.py is_instance_or_iterable', gs_support_is_instance_or_iterable().canonical, 'fin_gsq_support_is_instance_or_iterable');
SELECT assert_eq('gs quant compatibility 0079 gs_quant/base.py handle_camel_case_args', gs_support_handle_camel_case_args().canonical, 'fin_gsq_support_handle_camel_case_args');
SELECT assert_eq('gs quant compatibility 0080 gs_quant/base.py static_field', gs_support_static_field().canonical, 'fin_gsq_support_static_field');
SELECT assert_eq('gs quant compatibility 0081 gs_quant/base.py get_enum_value', gs_support_get_enum_value().canonical, 'fin_gsq_support_get_enum_value');
SELECT assert_eq('gs quant compatibility 0082 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py persistXls', gs_content_persistxls().canonical, 'fin_content_persistxls');
SELECT assert_eq('gs quant compatibility 0083 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotGross', gs_content_plotgross().canonical, 'fin_content_plotgross');
SELECT assert_eq('gs quant compatibility 0084 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotCost', gs_content_plotcost().canonical, 'fin_content_plotcost');
SELECT assert_eq('gs quant compatibility 0085 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotVar', gs_content_plotvar().canonical, 'fin_content_plotvar');
SELECT assert_eq('gs quant compatibility 0086 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotBuySellNet', gs_content_plotbuysellnet().canonical, 'fin_content_plotbuysellnet');
SELECT assert_eq('gs quant compatibility 0087 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotGrossRemaining', gs_content_plotgrossremaining().canonical, 'fin_content_plotgrossremaining');
SELECT assert_eq('gs quant compatibility 0088 gs_quant/content/events/00_gsquant_meets_markets/02_optimizing_equity_trading/qes_utils.py plotMultiStrategyPortfolioLevelAnalytics', gs_content_plotmultistrategyportfoliolevelanalytics().canonical, 'fin_content_plotmultistrategyportfoliolevelanalytics');
SELECT assert_eq('gs quant compatibility 0089 gs_quant/content/reports_and_screens/00_fx/vol_screen_app.py format_df', gs_content_format_df().canonical, 'fin_content_format_df');
SELECT assert_eq('gs quant compatibility 0090 gs_quant/content/reports_and_screens/00_fx/vol_screen_app.py volatility_screen', gs_content_volatility_screen().canonical, 'fin_content_volatility_screen');
SELECT assert_eq('gs quant compatibility 0091 gs_quant/data/log.py log_debug', gs_support_log_debug().canonical, 'fin_gsq_support_log_debug');
SELECT assert_eq('gs quant compatibility 0092 gs_quant/data/log.py log_warning', gs_support_log_warning().canonical, 'fin_gsq_support_log_warning');
SELECT assert_eq('gs quant compatibility 0093 gs_quant/data/log.py log_info', gs_support_log_info().canonical, 'fin_gsq_support_log_info');
SELECT assert_eq('gs quant compatibility 0094 gs_quant/datetime/date.py is_business_day', gs_datetime_is_business_day().canonical, 'fin_is_business_day');
SELECT assert_eq('gs quant compatibility 0095 gs_quant/datetime/date.py business_day_offset', gs_datetime_business_day_offset().canonical, 'fin_business_day_offset');
SELECT assert_eq('gs quant compatibility 0096 gs_quant/datetime/date.py prev_business_date', gs_datetime_prev_business_date().canonical, 'fin_prev_business_date');
SELECT assert_eq('gs quant compatibility 0097 gs_quant/datetime/date.py business_day_count', gs_datetime_business_day_count().canonical, 'fin_business_day_count');
SELECT assert_eq('gs quant compatibility 0098 gs_quant/datetime/date.py date_range', gs_datetime_date_range().canonical, 'fin_date_range');
SELECT assert_eq('gs quant compatibility 0099 gs_quant/datetime/date.py today', gs_datetime_today().canonical, 'fin_today');
SELECT assert_eq('gs quant compatibility 0100 gs_quant/datetime/date.py has_feb_29', gs_datetime_has_feb_29().canonical, 'fin_has_feb_29');
SELECT assert_eq('gs quant compatibility 0101 gs_quant/datetime/date.py day_count_fraction', gs_datetime_day_count_fraction().canonical, 'fin_day_count_fraction');
SELECT assert_eq('gs quant compatibility 0102 gs_quant/datetime/point.py relative_date_add', gs_datetime_relative_date_add().canonical, 'fin_relative_date_add');
SELECT assert_eq('gs quant compatibility 0103 gs_quant/datetime/point.py point_sort_order', gs_datetime_point_sort_order().canonical, 'fin_point_sort_order');
SELECT assert_eq('gs quant compatibility 0104 gs_quant/datetime/time.py to_zulu_string', gs_datetime_to_zulu_string().canonical, 'fin_to_zulu_string');
SELECT assert_eq('gs quant compatibility 0105 gs_quant/datetime/time.py time_difference_as_string', gs_datetime_time_difference_as_string().canonical, 'fin_time_difference_as_string');
SELECT assert_eq('gs quant compatibility 0106 gs_quant/errors.py error_builder', gs_support_error_builder().canonical, 'fin_gsq_support_error_builder');
SELECT assert_eq('gs quant compatibility 0107 gs_quant/instrument/core.py encode_instrument', gs_support_encode_instrument().canonical, 'fin_gsq_support_encode_instrument');
SELECT assert_eq('gs quant compatibility 0108 gs_quant/instrument/core.py encode_instruments', gs_support_encode_instruments().canonical, 'fin_gsq_support_encode_instruments');
SELECT assert_eq('gs quant compatibility 0109 gs_quant/json_convertors.py encode_date_or_str', gs_json_encode_date_or_str().canonical, 'fin_json_encode_date_or_str');
SELECT assert_eq('gs quant compatibility 0110 gs_quant/json_convertors.py decode_optional_date_or_time', gs_json_decode_optional_date_or_time().canonical, 'fin_json_decode_optional_date_or_time');
SELECT assert_eq('gs quant compatibility 0111 gs_quant/json_convertors.py decode_optional_date', gs_json_decode_optional_date().canonical, 'fin_json_decode_optional_date');
SELECT assert_eq('gs quant compatibility 0112 gs_quant/json_convertors.py decode_optional_time', gs_json_decode_optional_time().canonical, 'fin_json_decode_optional_time');
SELECT assert_eq('gs quant compatibility 0113 gs_quant/json_convertors.py encode_optional_time', gs_json_encode_optional_time().canonical, 'fin_json_encode_optional_time');
SELECT assert_eq('gs quant compatibility 0114 gs_quant/json_convertors.py decode_date_tuple', gs_json_decode_date_tuple().canonical, 'fin_json_decode_date_tuple');
SELECT assert_eq('gs quant compatibility 0115 gs_quant/json_convertors.py decode_date_or_time_tuple', gs_json_decode_date_or_time_tuple().canonical, 'fin_json_decode_date_or_time_tuple');
SELECT assert_eq('gs quant compatibility 0116 gs_quant/json_convertors.py encode_date_tuple', gs_json_encode_date_tuple().canonical, 'fin_json_encode_date_tuple');
SELECT assert_eq('gs quant compatibility 0117 gs_quant/json_convertors.py encode_date_or_time_tuple', gs_json_encode_date_or_time_tuple().canonical, 'fin_json_encode_date_or_time_tuple');
SELECT assert_eq('gs quant compatibility 0118 gs_quant/json_convertors.py decode_iso_date_or_datetime', gs_json_decode_iso_date_or_datetime().canonical, 'fin_json_decode_iso_date_or_datetime');
SELECT assert_eq('gs quant compatibility 0119 gs_quant/json_convertors.py optional_from_isodatetime', gs_json_optional_from_isodatetime().canonical, 'fin_json_optional_from_isodatetime');
SELECT assert_eq('gs quant compatibility 0120 gs_quant/json_convertors.py optional_to_isodatetime', gs_json_optional_to_isodatetime().canonical, 'fin_json_optional_to_isodatetime');
SELECT assert_eq('gs quant compatibility 0121 gs_quant/json_convertors.py decode_dict_date_key', gs_json_decode_dict_date_key().canonical, 'fin_json_decode_dict_date_key');
SELECT assert_eq('gs quant compatibility 0122 gs_quant/json_convertors.py decode_dict_date_key_or_float', gs_json_decode_dict_date_key_or_float().canonical, 'fin_json_decode_dict_date_key_or_float');
SELECT assert_eq('gs quant compatibility 0123 gs_quant/json_convertors.py decode_dict_dict_date_key', gs_json_decode_dict_dict_date_key().canonical, 'fin_json_decode_dict_dict_date_key');
SELECT assert_eq('gs quant compatibility 0124 gs_quant/json_convertors.py decode_dict_date_value', gs_json_decode_dict_date_value().canonical, 'fin_json_decode_dict_date_value');
SELECT assert_eq('gs quant compatibility 0125 gs_quant/json_convertors.py decode_datetime_tuple', gs_json_decode_datetime_tuple().canonical, 'fin_json_decode_datetime_tuple');
SELECT assert_eq('gs quant compatibility 0126 gs_quant/json_convertors.py decode_date_or_str', gs_json_decode_date_or_str().canonical, 'fin_json_decode_date_or_str');
SELECT assert_eq('gs quant compatibility 0127 gs_quant/json_convertors.py encode_datetime', gs_json_encode_datetime().canonical, 'fin_json_encode_datetime');
SELECT assert_eq('gs quant compatibility 0128 gs_quant/json_convertors.py decode_datetime', gs_json_decode_datetime().canonical, 'fin_json_decode_datetime');
SELECT assert_eq('gs quant compatibility 0129 gs_quant/json_convertors.py decode_float_or_str', gs_json_decode_float_or_str().canonical, 'fin_json_decode_float_or_str');
SELECT assert_eq('gs quant compatibility 0130 gs_quant/json_convertors.py decode_instrument', gs_json_decode_instrument().canonical, 'fin_json_decode_instrument');
SELECT assert_eq('gs quant compatibility 0131 gs_quant/json_convertors.py decode_named_instrument', gs_json_decode_named_instrument().canonical, 'fin_json_decode_named_instrument');
SELECT assert_eq('gs quant compatibility 0132 gs_quant/json_convertors.py decode_named_portfolio', gs_json_decode_named_portfolio().canonical, 'fin_json_decode_named_portfolio');
SELECT assert_eq('gs quant compatibility 0133 gs_quant/json_convertors.py encode_named_instrument', gs_json_encode_named_instrument().canonical, 'fin_json_encode_named_instrument');
SELECT assert_eq('gs quant compatibility 0134 gs_quant/json_convertors.py encode_named_portfolio', gs_json_encode_named_portfolio().canonical, 'fin_json_encode_named_portfolio');
SELECT assert_eq('gs quant compatibility 0135 gs_quant/json_convertors.py encode_pandas_series', gs_json_encode_pandas_series().canonical, 'fin_json_encode_pandas_series');
SELECT assert_eq('gs quant compatibility 0136 gs_quant/json_convertors.py decode_pandas_series', gs_json_decode_pandas_series().canonical, 'fin_json_decode_pandas_series');
SELECT assert_eq('gs quant compatibility 0137 gs_quant/json_convertors.py decode_quote_report', gs_json_decode_quote_report().canonical, 'fin_json_decode_quote_report');
SELECT assert_eq('gs quant compatibility 0138 gs_quant/json_convertors.py decode_quote_reports', gs_json_decode_quote_reports().canonical, 'fin_json_decode_quote_reports');
SELECT assert_eq('gs quant compatibility 0139 gs_quant/json_convertors.py decode_custom_comment', gs_json_decode_custom_comment().canonical, 'fin_json_decode_custom_comment');
SELECT assert_eq('gs quant compatibility 0140 gs_quant/json_convertors.py decode_custom_comments', gs_json_decode_custom_comments().canonical, 'fin_json_decode_custom_comments');
SELECT assert_eq('gs quant compatibility 0141 gs_quant/json_convertors.py decode_hedge_type', gs_json_decode_hedge_type().canonical, 'fin_json_decode_hedge_type');
SELECT assert_eq('gs quant compatibility 0142 gs_quant/json_convertors.py decode_hedge_types', gs_json_decode_hedge_types().canonical, 'fin_json_decode_hedge_types');
SELECT assert_eq('gs quant compatibility 0143 gs_quant/json_convertors.py encode_dictable', gs_json_encode_dictable().canonical, 'fin_json_encode_dictable');
SELECT assert_eq('gs quant compatibility 0144 gs_quant/json_convertors.py encode_named_dictable', gs_json_encode_named_dictable().canonical, 'fin_json_encode_named_dictable');
SELECT assert_eq('gs quant compatibility 0145 gs_quant/json_convertors.py dc_decode', gs_json_dc_decode().canonical, 'fin_json_dc_decode');
SELECT assert_eq('gs quant compatibility 0146 gs_quant/json_convertors.py encode_timedelta', gs_json_encode_timedelta().canonical, 'fin_json_encode_timedelta');
SELECT assert_eq('gs quant compatibility 0147 gs_quant/json_convertors.py decode_timedelta', gs_json_decode_timedelta().canonical, 'fin_json_decode_timedelta');
SELECT assert_eq('gs quant compatibility 0148 gs_quant/json_convertors.py encode_callable', gs_json_encode_callable().canonical, 'fin_json_encode_callable');
SELECT assert_eq('gs quant compatibility 0149 gs_quant/json_convertors.py decode_callable', gs_json_decode_callable().canonical, 'fin_json_decode_callable');
SELECT assert_eq('gs quant compatibility 0150 gs_quant/json_convertors_common.py gsq_rm_for_name', gs_json_gsq_rm_for_name().canonical, 'fin_json_gsq_rm_for_name');
SELECT assert_eq('gs quant compatibility 0151 gs_quant/json_convertors_common.py encode_risk_measure', gs_json_encode_risk_measure().canonical, 'fin_json_encode_risk_measure');
SELECT assert_eq('gs quant compatibility 0152 gs_quant/json_convertors_common.py encode_risk_measure_tuple', gs_json_encode_risk_measure_tuple().canonical, 'fin_json_encode_risk_measure_tuple');
SELECT assert_eq('gs quant compatibility 0153 gs_quant/json_convertors_common.py decode_risk_measure', gs_json_decode_risk_measure().canonical, 'fin_json_decode_risk_measure');
SELECT assert_eq('gs quant compatibility 0154 gs_quant/json_convertors_common.py decode_risk_measure_tuple', gs_json_decode_risk_measure_tuple().canonical, 'fin_json_decode_risk_measure_tuple');
SELECT assert_eq('gs quant compatibility 0155 gs_quant/json_encoder.py encode_default', gs_json_encode_default().canonical, 'fin_json_encode_default');
SELECT assert_eq('gs quant compatibility 0156 gs_quant/markets/indices_utils.py get_my_baskets', gs_api_get_my_baskets().canonical, 'fin_api_get_my_baskets');
SELECT assert_eq('gs quant compatibility 0157 gs_quant/markets/indices_utils.py get_flagship_baskets', gs_api_get_flagship_baskets().canonical, 'fin_api_get_flagship_baskets');
SELECT assert_eq('gs quant compatibility 0158 gs_quant/markets/indices_utils.py get_flagships_with_assets', gs_api_get_flagships_with_assets().canonical, 'fin_api_get_flagships_with_assets');
SELECT assert_eq('gs quant compatibility 0159 gs_quant/markets/indices_utils.py get_flagships_performance', gs_api_get_flagships_performance().canonical, 'fin_api_get_flagships_performance');
SELECT assert_eq('gs quant compatibility 0160 gs_quant/markets/indices_utils.py get_flagships_constituents', gs_api_get_flagships_constituents().canonical, 'fin_api_get_flagships_constituents');
SELECT assert_eq('gs quant compatibility 0161 gs_quant/markets/indices_utils.py get_constituents_dataset_coverage', gs_api_get_constituents_dataset_coverage().canonical, 'fin_api_get_constituents_dataset_coverage');
SELECT assert_eq('gs quant compatibility 0162 gs_quant/markets/markets.py historical_risk_key', gs_api_historical_risk_key().canonical, 'fin_api_historical_risk_key');
SELECT assert_eq('gs quant compatibility 0163 gs_quant/markets/markets.py market_location', gs_api_market_location().canonical, 'fin_api_market_location');
SELECT assert_eq('gs quant compatibility 0164 gs_quant/markets/markets.py close_market_date', gs_api_close_market_date().canonical, 'fin_api_close_market_date');
SELECT assert_eq('gs quant compatibility 0165 gs_quant/markets/optimizer.py resolve_assets_in_batches', gs_api_resolve_assets_in_batches().canonical, 'fin_api_resolve_assets_in_batches');
SELECT assert_eq('gs quant compatibility 0166 gs_quant/markets/portfolio_manager_utils.py build_macro_portfolio_exposure_df', gs_api_build_macro_portfolio_exposure_df().canonical, 'fin_api_build_macro_portfolio_exposure_df');
SELECT assert_eq('gs quant compatibility 0167 gs_quant/markets/portfolio_manager_utils.py build_portfolio_constituents_df', gs_api_build_portfolio_constituents_df().canonical, 'fin_api_build_portfolio_constituents_df');
SELECT assert_eq('gs quant compatibility 0168 gs_quant/markets/portfolio_manager_utils.py build_sensitivity_df', gs_api_build_sensitivity_df().canonical, 'fin_api_build_sensitivity_df');
SELECT assert_eq('gs quant compatibility 0169 gs_quant/markets/portfolio_manager_utils.py build_exposure_df', gs_api_build_exposure_df().canonical, 'fin_api_build_exposure_df');
SELECT assert_eq('gs quant compatibility 0170 gs_quant/markets/portfolio_manager_utils.py get_batched_dates', gs_api_get_batched_dates().canonical, 'fin_api_get_batched_dates');
SELECT assert_eq('gs quant compatibility 0171 gs_quant/markets/report.py get_thematic_breakdown_as_df', gs_api_get_thematic_breakdown_as_df().canonical, 'fin_api_get_thematic_breakdown_as_df');
SELECT assert_eq('gs quant compatibility 0172 gs_quant/markets/report.py flatten_results_into_df', gs_api_flatten_results_into_df().canonical, 'fin_api_flatten_results_into_df');
SELECT assert_eq('gs quant compatibility 0173 gs_quant/markets/report.py get_pnl_percent', gs_api_get_pnl_percent().canonical, 'fin_api_get_pnl_percent');
SELECT assert_eq('gs quant compatibility 0174 gs_quant/markets/report.py get_factor_pnl_percent_for_single_factor', gs_api_get_factor_pnl_percent_for_single_factor().canonical, 'fin_api_get_factor_pnl_percent_for_single_factor');
SELECT assert_eq('gs quant compatibility 0175 gs_quant/markets/report.py format_factor_pnl_for_return_calculation', gs_api_format_factor_pnl_for_return_calculation().canonical, 'fin_api_format_factor_pnl_for_return_calculation');
SELECT assert_eq('gs quant compatibility 0176 gs_quant/markets/report.py format_aum_for_return_calculation', gs_api_format_aum_for_return_calculation().canonical, 'fin_api_format_aum_for_return_calculation');
SELECT assert_eq('gs quant compatibility 0177 gs_quant/markets/report.py generate_daily_returns', gs_api_generate_daily_returns().canonical, 'fin_api_generate_daily_returns');
SELECT assert_eq('gs quant compatibility 0178 gs_quant/models/epidemiology.py switch', gs_support_switch().canonical, 'fin_gsq_support_switch');
SELECT assert_eq('gs quant compatibility 0179 gs_quant/models/risk_model_utils.py build_factor_id_to_name_map', gs_support_build_factor_id_to_name_map().canonical, 'fin_gsq_support_build_factor_id_to_name_map');
SELECT assert_eq('gs quant compatibility 0180 gs_quant/models/risk_model_utils.py build_asset_data_map', gs_support_build_asset_data_map().canonical, 'fin_gsq_support_build_asset_data_map');
SELECT assert_eq('gs quant compatibility 0181 gs_quant/models/risk_model_utils.py build_factor_data_map', gs_support_build_factor_data_map().canonical, 'fin_gsq_support_build_factor_data_map');
SELECT assert_eq('gs quant compatibility 0182 gs_quant/models/risk_model_utils.py build_pfp_data_dataframe', gs_support_build_pfp_data_dataframe().canonical, 'fin_gsq_support_build_pfp_data_dataframe');
SELECT assert_eq('gs quant compatibility 0183 gs_quant/models/risk_model_utils.py get_optional_data_as_dataframe', gs_support_get_optional_data_as_dataframe().canonical, 'fin_gsq_support_get_optional_data_as_dataframe');
SELECT assert_eq('gs quant compatibility 0184 gs_quant/models/risk_model_utils.py get_covariance_matrix_dataframe', gs_support_get_covariance_matrix_dataframe().canonical, 'fin_gsq_support_get_covariance_matrix_dataframe');
SELECT assert_eq('gs quant compatibility 0185 gs_quant/models/risk_model_utils.py build_factor_volatility_dataframe', gs_support_build_factor_volatility_dataframe().canonical, 'fin_gsq_support_build_factor_volatility_dataframe');
SELECT assert_eq('gs quant compatibility 0186 gs_quant/models/risk_model_utils.py get_closest_date_index', gs_support_get_closest_date_index().canonical, 'fin_gsq_support_get_closest_date_index');
SELECT assert_eq('gs quant compatibility 0187 gs_quant/models/risk_model_utils.py divide_request', gs_support_divide_request().canonical, 'fin_gsq_support_divide_request');
SELECT assert_eq('gs quant compatibility 0188 gs_quant/models/risk_model_utils.py batch_and_upload_partial_data_use_target_universe_size', gs_support_batch_and_upload_partial_data_use_target_universe_size().canonical, 'fin_gsq_support_batch_and_upload_partial_data_use_target_universe_size');
SELECT assert_eq('gs quant compatibility 0189 gs_quant/models/risk_model_utils.py only_factor_data_is_present', gs_support_only_factor_data_is_present().canonical, 'fin_gsq_support_only_factor_data_is_present');
SELECT assert_eq('gs quant compatibility 0190 gs_quant/models/risk_model_utils.py batch_and_upload_partial_data', gs_support_batch_and_upload_partial_data().canonical, 'fin_gsq_support_batch_and_upload_partial_data');
SELECT assert_eq('gs quant compatibility 0191 gs_quant/models/risk_model_utils.py batch_and_upload_coverage_data', gs_support_batch_and_upload_coverage_data().canonical, 'fin_gsq_support_batch_and_upload_coverage_data');
SELECT assert_eq('gs quant compatibility 0192 gs_quant/models/risk_model_utils.py upload_model_data', gs_support_upload_model_data().canonical, 'fin_gsq_support_upload_model_data');
SELECT assert_eq('gs quant compatibility 0193 gs_quant/models/risk_model_utils.py risk_model_data_to_json', gs_support_risk_model_data_to_json().canonical, 'fin_gsq_support_risk_model_data_to_json');
SELECT assert_eq('gs quant compatibility 0194 gs_quant/models/risk_model_utils.py get_universe_size', gs_support_get_universe_size().canonical, 'fin_gsq_support_get_universe_size');
SELECT assert_eq('gs quant compatibility 0195 gs_quant/quote_reports/core.py quote_report_from_dict', gs_support_quote_report_from_dict().canonical, 'fin_gsq_support_quote_report_from_dict');
SELECT assert_eq('gs quant compatibility 0196 gs_quant/quote_reports/core.py quote_reports_from_dicts', gs_support_quote_reports_from_dicts().canonical, 'fin_gsq_support_quote_reports_from_dicts');
SELECT assert_eq('gs quant compatibility 0197 gs_quant/quote_reports/core.py custom_comment_from_dict', gs_support_custom_comment_from_dict().canonical, 'fin_gsq_support_custom_comment_from_dict');
SELECT assert_eq('gs quant compatibility 0198 gs_quant/quote_reports/core.py custom_comments_from_dicts', gs_support_custom_comments_from_dicts().canonical, 'fin_gsq_support_custom_comments_from_dicts');
SELECT assert_eq('gs quant compatibility 0199 gs_quant/quote_reports/core.py hedge_type_from_dict', gs_support_hedge_type_from_dict().canonical, 'fin_gsq_support_hedge_type_from_dict');
SELECT assert_eq('gs quant compatibility 0200 gs_quant/quote_reports/core.py hedge_type_from_dicts', gs_support_hedge_type_from_dicts().canonical, 'fin_gsq_support_hedge_type_from_dicts');
SELECT assert_eq('gs quant compatibility 0201 gs_quant/risk/core.py aggregate_risk', gs_risk_aggregate_risk().canonical, 'fin_risk_aggregate_risk');
SELECT assert_eq('gs quant compatibility 0202 gs_quant/risk/core.py aggregate_results', gs_risk_aggregate_results().canonical, 'fin_risk_aggregate_results');
SELECT assert_eq('gs quant compatibility 0203 gs_quant/risk/core.py subtract_risk', gs_risk_subtract_risk().canonical, 'fin_risk_subtract_risk');
SELECT assert_eq('gs quant compatibility 0204 gs_quant/risk/core.py sort_values', gs_risk_sort_values().canonical, 'fin_risk_sort_values');
SELECT assert_eq('gs quant compatibility 0205 gs_quant/risk/core.py sort_risk', gs_risk_sort_risk().canonical, 'fin_risk_sort_risk');
SELECT assert_eq('gs quant compatibility 0206 gs_quant/risk/core.py combine_risk_key', gs_risk_combine_risk_key().canonical, 'fin_risk_combine_risk_key');
SELECT assert_eq('gs quant compatibility 0207 gs_quant/risk/result_handlers.py cashflows_handler', gs_risk_cashflows_handler().canonical, 'fin_risk_cashflows_handler');
SELECT assert_eq('gs quant compatibility 0208 gs_quant/risk/result_handlers.py error_handler', gs_risk_error_handler().canonical, 'fin_risk_error_handler');
SELECT assert_eq('gs quant compatibility 0209 gs_quant/risk/result_handlers.py leg_definition_handler', gs_risk_leg_definition_handler().canonical, 'fin_risk_leg_definition_handler');
SELECT assert_eq('gs quant compatibility 0210 gs_quant/risk/result_handlers.py message_handler', gs_risk_message_handler().canonical, 'fin_risk_message_handler');
SELECT assert_eq('gs quant compatibility 0211 gs_quant/risk/result_handlers.py number_and_unit_handler', gs_risk_number_and_unit_handler().canonical, 'fin_risk_number_and_unit_handler');
SELECT assert_eq('gs quant compatibility 0212 gs_quant/risk/result_handlers.py required_assets_handler', gs_risk_required_assets_handler().canonical, 'fin_risk_required_assets_handler');
SELECT assert_eq('gs quant compatibility 0213 gs_quant/risk/result_handlers.py dict_risk_handler', gs_risk_dict_risk_handler().canonical, 'fin_risk_dict_risk_handler');
SELECT assert_eq('gs quant compatibility 0214 gs_quant/risk/result_handlers.py risk_handler', gs_risk_risk_handler().canonical, 'fin_risk_risk_handler');
SELECT assert_eq('gs quant compatibility 0215 gs_quant/risk/result_handlers.py risk_by_class_handler', gs_risk_risk_by_class_handler().canonical, 'fin_risk_risk_by_class_handler');
SELECT assert_eq('gs quant compatibility 0216 gs_quant/risk/result_handlers.py risk_vector_handler', gs_risk_risk_vector_handler().canonical, 'fin_risk_risk_vector_handler');
SELECT assert_eq('gs quant compatibility 0217 gs_quant/risk/result_handlers.py fixing_table_handler', gs_risk_fixing_table_handler().canonical, 'fin_risk_fixing_table_handler');
SELECT assert_eq('gs quant compatibility 0218 gs_quant/risk/result_handlers.py simple_valtable_handler', gs_risk_simple_valtable_handler().canonical, 'fin_risk_simple_valtable_handler');
SELECT assert_eq('gs quant compatibility 0219 gs_quant/risk/result_handlers.py canonical_projection_table_handler', gs_risk_canonical_projection_table_handler().canonical, 'fin_risk_canonical_projection_table_handler');
SELECT assert_eq('gs quant compatibility 0220 gs_quant/risk/result_handlers.py risk_float_handler', gs_risk_risk_float_handler().canonical, 'fin_risk_risk_float_handler');
SELECT assert_eq('gs quant compatibility 0221 gs_quant/risk/result_handlers.py map_coordinate_to_column', gs_risk_map_coordinate_to_column().canonical, 'fin_risk_map_coordinate_to_column');
SELECT assert_eq('gs quant compatibility 0222 gs_quant/risk/result_handlers.py mdapi_second_order_table_handler', gs_risk_mdapi_second_order_table_handler().canonical, 'fin_risk_mdapi_second_order_table_handler');
SELECT assert_eq('gs quant compatibility 0223 gs_quant/risk/result_handlers.py mdapi_table_handler', gs_risk_mdapi_table_handler().canonical, 'fin_risk_mdapi_table_handler');
SELECT assert_eq('gs quant compatibility 0224 gs_quant/risk/result_handlers.py mmapi_table_handler', gs_risk_mmapi_table_handler().canonical, 'fin_risk_mmapi_table_handler');
SELECT assert_eq('gs quant compatibility 0225 gs_quant/risk/result_handlers.py mmapi_pca_table_handler', gs_risk_mmapi_pca_table_handler().canonical, 'fin_risk_mmapi_pca_table_handler');
SELECT assert_eq('gs quant compatibility 0226 gs_quant/risk/result_handlers.py mmapi_pca_hedge_table_handler', gs_risk_mmapi_pca_hedge_table_handler().canonical, 'fin_risk_mmapi_pca_hedge_table_handler');
SELECT assert_eq('gs quant compatibility 0227 gs_quant/risk/result_handlers.py mqvs_validators_handler', gs_risk_mqvs_validators_handler().canonical, 'fin_risk_mqvs_validators_handler');
SELECT assert_eq('gs quant compatibility 0228 gs_quant/risk/result_handlers.py market_handler', gs_risk_market_handler().canonical, 'fin_risk_market_handler');
SELECT assert_eq('gs quant compatibility 0229 gs_quant/risk/result_handlers.py unsupported_handler', gs_risk_unsupported_handler().canonical, 'fin_risk_unsupported_handler');
SELECT assert_eq('gs quant compatibility 0230 gs_quant/risk/results.py get_default_pivots', gs_risk_get_default_pivots().canonical, 'fin_risk_get_default_pivots');
SELECT assert_eq('gs quant compatibility 0231 gs_quant/risk/results.py pivot_to_frame', gs_risk_pivot_to_frame().canonical, 'fin_risk_pivot_to_frame');
SELECT assert_eq('gs quant compatibility 0232 gs_quant/risk/scenario_utils.py build_eq_vol_scenario_intraday', gs_risk_build_eq_vol_scenario_intraday().canonical, 'fin_risk_build_eq_vol_scenario_intraday');
SELECT assert_eq('gs quant compatibility 0233 gs_quant/risk/scenario_utils.py build_eq_vol_scenario_eod', gs_risk_build_eq_vol_scenario_eod().canonical, 'fin_risk_build_eq_vol_scenario_eod');
SELECT assert_eq('gs quant compatibility 0234 gs_quant/test/analytics/test_datagrid.py test_simple_datagrid', gs_test_test_simple_datagrid().canonical, 'fin_gsq_test_test_simple_datagrid');
SELECT assert_eq('gs quant compatibility 0235 gs_quant/test/analytics/test_datagrid.py test_rdate_datagrid', gs_test_test_rdate_datagrid().canonical, 'fin_gsq_test_test_rdate_datagrid');
SELECT assert_eq('gs quant compatibility 0236 gs_quant/test/analytics/test_workspace.py test_layout_creation', gs_test_test_layout_creation().canonical, 'fin_gsq_test_test_layout_creation');
SELECT assert_eq('gs quant compatibility 0237 gs_quant/test/analytics/test_workspace.py test_layout_parsing', gs_test_test_layout_parsing().canonical, 'fin_gsq_test_test_layout_parsing');
SELECT assert_eq('gs quant compatibility 0238 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_encode_series_result', gs_json_test_encode_series_result().canonical, 'fin_json_test_encode_series_result');
SELECT assert_eq('gs quant compatibility 0239 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_encode_dataframe_result', gs_json_test_encode_dataframe_result().canonical, 'fin_json_test_encode_dataframe_result');
SELECT assert_eq('gs quant compatibility 0240 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_decode_series_result', gs_json_test_decode_series_result().canonical, 'fin_json_test_decode_series_result');
SELECT assert_eq('gs quant compatibility 0241 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_datatype_encoders.py test_decode_dataframe_result', gs_json_test_decode_dataframe_result().canonical, 'fin_json_test_decode_dataframe_result');
SELECT assert_eq('gs quant compatibility 0242 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_encoders.py test_map_result_to_datatype', gs_json_test_map_result_to_datatype().canonical, 'fin_json_test_map_result_to_datatype');
SELECT assert_eq('gs quant compatibility 0243 gs_quant/test/api/backtests_xasset/json_encoders/response_datatypes/test_risk_result_encoders.py test_decode_risk_result', gs_json_test_decode_risk_result().canonical, 'fin_json_test_decode_risk_result');
SELECT assert_eq('gs quant compatibility 0244 gs_quant/test/api/backtests_xasset/json_encoders/test_request_encoders.py test_legs_decoder', gs_json_test_legs_decoder().canonical, 'fin_json_test_legs_decoder');
SELECT assert_eq('gs quant compatibility 0245 gs_quant/test/api/backtests_xasset/json_encoders/test_request_encoders.py test_legs_encoder', gs_json_test_legs_encoder().canonical, 'fin_json_test_legs_encoder');
SELECT assert_eq('gs quant compatibility 0246 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_decode_basic_bt_transactions', gs_json_test_decode_basic_bt_transactions().canonical, 'fin_json_test_decode_basic_bt_transactions');
SELECT assert_eq('gs quant compatibility 0247 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_callable_builtin', gs_json_test_encode_callable_builtin().canonical, 'fin_json_test_encode_callable_builtin');
SELECT assert_eq('gs quant compatibility 0248 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_callable_none', gs_json_test_encode_callable_none().canonical, 'fin_json_test_encode_callable_none');
SELECT assert_eq('gs quant compatibility 0249 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_decode_callable_passthrough', gs_json_test_decode_callable_passthrough().canonical, 'fin_json_test_decode_callable_passthrough');
SELECT assert_eq('gs quant compatibility 0250 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_callable_named_function', gs_json_test_encode_callable_named_function().canonical, 'fin_json_test_encode_callable_named_function');
SELECT assert_eq('gs quant compatibility 0251 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_decode_callable_rejects_non_allowlisted', gs_json_test_decode_callable_rejects_non_allowlisted().canonical, 'fin_json_test_decode_callable_rejects_non_allowlisted');
SELECT assert_eq('gs quant compatibility 0252 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_custom_duration_round_trip', gs_json_test_custom_duration_round_trip().canonical, 'fin_json_test_custom_duration_round_trip');
SELECT assert_eq('gs quant compatibility 0253 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_custom_duration_json_serializable', gs_json_test_custom_duration_json_serializable().canonical, 'fin_json_test_custom_duration_json_serializable');
SELECT assert_eq('gs quant compatibility 0254 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_str', gs_json_test_encode_duration_str().canonical, 'fin_json_test_encode_duration_str');
SELECT assert_eq('gs quant compatibility 0255 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_date', gs_json_test_encode_duration_date().canonical, 'fin_json_test_encode_duration_date');
SELECT assert_eq('gs quant compatibility 0256 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_timedelta', gs_json_test_encode_duration_timedelta().canonical, 'fin_json_test_encode_duration_timedelta');
SELECT assert_eq('gs quant compatibility 0257 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_duration_custom_duration', gs_json_test_encode_duration_custom_duration().canonical, 'fin_json_test_encode_duration_custom_duration');
SELECT assert_eq('gs quant compatibility 0258 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_response_obj_callable', gs_json_test_encode_response_obj_callable().canonical, 'fin_json_test_encode_response_obj_callable');
SELECT assert_eq('gs quant compatibility 0259 gs_quant/test/api/backtests_xasset/json_encoders/test_response_encoders.py test_encode_response_obj_unhandled_type', gs_json_test_encode_response_obj_unhandled_type().canonical, 'fin_json_test_encode_response_obj_unhandled_type');
SELECT assert_eq('gs quant compatibility 0260 gs_quant/test/api/backtests_xasset/response_datatypes/test_backtest_datatypes.py test_request_types', gs_test_test_request_types().canonical, 'fin_gsq_test_test_request_types');
SELECT assert_eq('gs quant compatibility 0261 gs_quant/test/api/backtests_xasset/response_datatypes/test_backtest_datatypes.py test_model_addition', gs_test_test_model_addition().canonical, 'fin_gsq_test_test_model_addition');
SELECT assert_eq('gs quant compatibility 0262 gs_quant/test/api/backtests_xasset/response_datatypes/test_risk_result.py test_request_types', gs_test_test_request_types_test_api_backtests_xasset_d77ba130f6().canonical, 'fin_gsq_test_test_request_types_test_api_backtests_xasset_d77ba130f6');
SELECT assert_eq('gs quant compatibility 0263 gs_quant/test/api/backtests_xasset/response_datatypes/test_risk_result_datatypes.py test_request_types', gs_test_test_request_types_test_api_backtests_xasset_380b648fc0().canonical, 'fin_gsq_test_test_request_types_test_api_backtests_xasset_380b648fc0');
SELECT assert_eq('gs quant compatibility 0264 gs_quant/test/api/backtests_xasset/response_datatypes/test_risk_result_datatypes.py test_arithmetics', gs_test_test_arithmetics().canonical, 'fin_gsq_test_test_arithmetics');
SELECT assert_eq('gs quant compatibility 0265 gs_quant/test/api/backtests_xasset/test_request.py test_request_types', gs_test_test_request_types_test_api_backtests_xasset_cefd453276().canonical, 'fin_gsq_test_test_request_types_test_api_backtests_xasset_cefd453276');
SELECT assert_eq('gs quant compatibility 0266 gs_quant/test/api/backtests_xasset/test_response.py test_response_types', gs_test_test_response_types().canonical, 'fin_gsq_test_test_response_types');
SELECT assert_eq('gs quant compatibility 0267 gs_quant/test/api/test_assets.py test_get_asset', gs_test_test_get_asset().canonical, 'fin_gsq_test_test_get_asset');
SELECT assert_eq('gs quant compatibility 0268 gs_quant/test/api/test_assets.py test_get_many_assets', gs_test_test_get_many_assets().canonical, 'fin_gsq_test_test_get_many_assets');
SELECT assert_eq('gs quant compatibility 0269 gs_quant/test/api/test_assets.py test_get_asset_xrefs', gs_test_test_get_asset_xrefs().canonical, 'fin_gsq_test_test_get_asset_xrefs');
SELECT assert_eq('gs quant compatibility 0270 gs_quant/test/api/test_assets.py test_get_asset_positions_for_date', gs_test_test_get_asset_positions_for_date().canonical, 'fin_gsq_test_test_get_asset_positions_for_date');
SELECT assert_eq('gs quant compatibility 0271 gs_quant/test/api/test_backtests.py test_get_many_backtests', gs_test_test_get_many_backtests().canonical, 'fin_gsq_test_test_get_many_backtests');
SELECT assert_eq('gs quant compatibility 0272 gs_quant/test/api/test_backtests.py test_get_backtest', gs_test_test_get_backtest().canonical, 'fin_gsq_test_test_get_backtest');
SELECT assert_eq('gs quant compatibility 0273 gs_quant/test/api/test_backtests.py test_create_backtest', gs_test_test_create_backtest().canonical, 'fin_gsq_test_test_create_backtest');
SELECT assert_eq('gs quant compatibility 0274 gs_quant/test/api/test_backtests.py test_update_backtest', gs_test_test_update_backtest().canonical, 'fin_gsq_test_test_update_backtest');
SELECT assert_eq('gs quant compatibility 0275 gs_quant/test/api/test_backtests.py test_delete_backtest', gs_test_test_delete_backtest().canonical, 'fin_gsq_test_test_delete_backtest');
SELECT assert_eq('gs quant compatibility 0276 gs_quant/test/api/test_backtests.py test_schedule_backtest', gs_test_test_schedule_backtest().canonical, 'fin_gsq_test_test_schedule_backtest');
SELECT assert_eq('gs quant compatibility 0277 gs_quant/test/api/test_base_screener.py test_get_all_screeners', gs_test_test_get_all_screeners().canonical, 'fin_gsq_test_test_get_all_screeners');
SELECT assert_eq('gs quant compatibility 0278 gs_quant/test/api/test_base_screener.py test_get_screen', gs_test_test_get_screen().canonical, 'fin_gsq_test_test_get_screen');
SELECT assert_eq('gs quant compatibility 0279 gs_quant/test/api/test_base_screener.py test_create_screener', gs_test_test_create_screener().canonical, 'fin_gsq_test_test_create_screener');
SELECT assert_eq('gs quant compatibility 0280 gs_quant/test/api/test_base_screener.py test_edit_screener', gs_test_test_edit_screener().canonical, 'fin_gsq_test_test_edit_screener');
SELECT assert_eq('gs quant compatibility 0281 gs_quant/test/api/test_base_screener.py test_publish_to_screener', gs_test_test_publish_to_screener().canonical, 'fin_gsq_test_test_publish_to_screener');
SELECT assert_eq('gs quant compatibility 0282 gs_quant/test/api/test_base_screener.py test_clear_screener', gs_test_test_clear_screener().canonical, 'fin_gsq_test_test_clear_screener');
SELECT assert_eq('gs quant compatibility 0283 gs_quant/test/api/test_base_screener.py test_delete_screener', gs_test_test_delete_screener().canonical, 'fin_gsq_test_test_delete_screener');
SELECT assert_eq('gs quant compatibility 0284 gs_quant/test/api/test_cache.py set_session', gs_test_set_session().canonical, 'fin_gsq_test_set_session');
SELECT assert_eq('gs quant compatibility 0285 gs_quant/test/api/test_cache.py test_cache_addition_removal', gs_test_test_cache_addition_removal().canonical, 'fin_gsq_test_test_cache_addition_removal');
SELECT assert_eq('gs quant compatibility 0286 gs_quant/test/api/test_cache.py test_cache_subset', gs_test_test_cache_subset().canonical, 'fin_gsq_test_test_cache_subset');
SELECT assert_eq('gs quant compatibility 0287 gs_quant/test/api/test_cache.py test_multiple_measures', gs_test_test_multiple_measures().canonical, 'fin_gsq_test_test_multiple_measures');
SELECT assert_eq('gs quant compatibility 0288 gs_quant/test/api/test_carbon.py test_get_carbon_data', gs_test_test_get_carbon_data().canonical, 'fin_gsq_test_test_get_carbon_data');
SELECT assert_eq('gs quant compatibility 0289 gs_quant/test/api/test_content.py set_session', gs_test_set_session_test_api_test_content().canonical, 'fin_gsq_test_set_session_test_api_test_content');
SELECT assert_eq('gs quant compatibility 0290 gs_quant/test/api/test_content.py test_get_contents', gs_test_test_get_contents().canonical, 'fin_gsq_test_test_get_contents');
SELECT assert_eq('gs quant compatibility 0291 gs_quant/test/api/test_content.py test_get_text', gs_test_test_get_text().canonical, 'fin_gsq_test_test_get_text');
SELECT assert_eq('gs quant compatibility 0292 gs_quant/test/api/test_data.py test_coordinates_data', gs_test_test_coordinates_data().canonical, 'fin_gsq_test_test_coordinates_data');
SELECT assert_eq('gs quant compatibility 0293 gs_quant/test/api/test_data.py test_coordinate_data_series', gs_test_test_coordinate_data_series().canonical, 'fin_gsq_test_test_coordinate_data_series');
SELECT assert_eq('gs quant compatibility 0294 gs_quant/test/api/test_data.py test_coordinate_last', gs_test_test_coordinate_last().canonical, 'fin_gsq_test_test_coordinate_last');
SELECT assert_eq('gs quant compatibility 0295 gs_quant/test/api/test_data.py test_get_coverage_api', gs_test_test_get_coverage_api().canonical, 'fin_gsq_test_test_get_coverage_api');
SELECT assert_eq('gs quant compatibility 0296 gs_quant/test/api/test_data.py test_get_many_defns_api', gs_test_test_get_many_defns_api().canonical, 'fin_gsq_test_test_get_many_defns_api');
SELECT assert_eq('gs quant compatibility 0297 gs_quant/test/api/test_data.py test_coordinates_converter', gs_test_test_coordinates_converter().canonical, 'fin_gsq_test_test_coordinates_converter');
SELECT assert_eq('gs quant compatibility 0298 gs_quant/test/api/test_data.py test_get_many_coordinates', gs_test_test_get_many_coordinates().canonical, 'fin_gsq_test_test_get_many_coordinates');
SELECT assert_eq('gs quant compatibility 0299 gs_quant/test/api/test_data.py test_auto_scroll_on_pages', gs_test_test_auto_scroll_on_pages().canonical, 'fin_gsq_test_test_auto_scroll_on_pages');
SELECT assert_eq('gs quant compatibility 0300 gs_quant/test/api/test_data.py mock_fields_response', gs_test_mock_fields_response().canonical, 'fin_gsq_test_mock_fields_response');
SELECT assert_eq('gs quant compatibility 0301 gs_quant/test/api/test_data.py test_get_dataset_fields', gs_test_test_get_dataset_fields().canonical, 'fin_gsq_test_test_get_dataset_fields');
SELECT assert_eq('gs quant compatibility 0302 gs_quant/test/api/test_data.py test_get_field_types', gs_test_test_get_field_types().canonical, 'fin_gsq_test_test_get_field_types');
SELECT assert_eq('gs quant compatibility 0303 gs_quant/test/api/test_data_screen.py test_get_all_screens', gs_test_test_get_all_screens().canonical, 'fin_gsq_test_test_get_all_screens');
SELECT assert_eq('gs quant compatibility 0304 gs_quant/test/api/test_data_screen.py test_get_screen', gs_test_test_get_screen_test_api_test_data_screen().canonical, 'fin_gsq_test_test_get_screen_test_api_test_data_screen');
SELECT assert_eq('gs quant compatibility 0305 gs_quant/test/api/test_data_screen.py test_get_column_info', gs_test_test_get_column_info().canonical, 'fin_gsq_test_test_get_column_info');
SELECT assert_eq('gs quant compatibility 0306 gs_quant/test/api/test_data_screen.py test_delete_screen', gs_test_test_delete_screen().canonical, 'fin_gsq_test_test_delete_screen');
SELECT assert_eq('gs quant compatibility 0307 gs_quant/test/api/test_data_screen.py test_create_screen', gs_test_test_create_screen().canonical, 'fin_gsq_test_test_create_screen');
SELECT assert_eq('gs quant compatibility 0308 gs_quant/test/api/test_data_screen.py test_filter_screen', gs_test_test_filter_screen().canonical, 'fin_gsq_test_test_filter_screen');
SELECT assert_eq('gs quant compatibility 0309 gs_quant/test/api/test_data_screen.py test_update_screen', gs_test_test_update_screen().canonical, 'fin_gsq_test_test_update_screen');
SELECT assert_eq('gs quant compatibility 0310 gs_quant/test/api/test_esg.py test_get_risk_models', gs_test_test_get_risk_models().canonical, 'fin_gsq_test_test_get_risk_models');
SELECT assert_eq('gs quant compatibility 0311 gs_quant/test/api/test_fred.py test_get_data', gs_test_test_get_data().canonical, 'fin_gsq_test_test_get_data');
SELECT assert_eq('gs quant compatibility 0312 gs_quant/test/api/test_fred.py test_failed_get_data', gs_test_test_failed_get_data().canonical, 'fin_gsq_test_test_failed_get_data');
SELECT assert_eq('gs quant compatibility 0313 gs_quant/test/api/test_fred.py test_get_data_series', gs_test_test_get_data_series().canonical, 'fin_gsq_test_test_get_data_series');
SELECT assert_eq('gs quant compatibility 0314 gs_quant/test/api/test_fred.py test_failed_get_data_series', gs_test_test_failed_get_data_series().canonical, 'fin_gsq_test_test_failed_get_data_series');
SELECT assert_eq('gs quant compatibility 0315 gs_quant/test/api/test_groups.py test_get_groups', gs_test_test_get_groups().canonical, 'fin_gsq_test_test_get_groups');
SELECT assert_eq('gs quant compatibility 0316 gs_quant/test/api/test_groups.py test_get_group', gs_test_test_get_group().canonical, 'fin_gsq_test_test_get_group');
SELECT assert_eq('gs quant compatibility 0317 gs_quant/test/api/test_groups.py test_create_group', gs_test_test_create_group().canonical, 'fin_gsq_test_test_create_group');
SELECT assert_eq('gs quant compatibility 0318 gs_quant/test/api/test_index.py mock_session', gs_test_mock_session().canonical, 'fin_gsq_test_mock_session');
SELECT assert_eq('gs quant compatibility 0319 gs_quant/test/api/test_index.py test_basket_create', gs_test_test_basket_create().canonical, 'fin_gsq_test_test_basket_create');
SELECT assert_eq('gs quant compatibility 0320 gs_quant/test/api/test_index.py test_basket_edit', gs_test_test_basket_edit().canonical, 'fin_gsq_test_test_basket_edit');
SELECT assert_eq('gs quant compatibility 0321 gs_quant/test/api/test_index.py test_basket_rebalance', gs_test_test_basket_rebalance().canonical, 'fin_gsq_test_test_basket_rebalance');
SELECT assert_eq('gs quant compatibility 0322 gs_quant/test/api/test_index.py test_basket_cancel_rebalance', gs_test_test_basket_cancel_rebalance().canonical, 'fin_gsq_test_test_basket_cancel_rebalance');
SELECT assert_eq('gs quant compatibility 0323 gs_quant/test/api/test_index.py test_basket_last_rebalance_data', gs_test_test_basket_last_rebalance_data().canonical, 'fin_gsq_test_test_basket_last_rebalance_data');
SELECT assert_eq('gs quant compatibility 0324 gs_quant/test/api/test_index.py test_basket_initial_price', gs_test_test_basket_initial_price().canonical, 'fin_gsq_test_test_basket_initial_price');
SELECT assert_eq('gs quant compatibility 0325 gs_quant/test/api/test_index.py test_get_asset_positions_data', gs_test_test_get_asset_positions_data().canonical, 'fin_gsq_test_test_get_asset_positions_data');
SELECT assert_eq('gs quant compatibility 0326 gs_quant/test/api/test_instruments.py test_from_dict', gs_test_test_from_dict().canonical, 'fin_gsq_test_test_from_dict');
SELECT assert_eq('gs quant compatibility 0327 gs_quant/test/api/test_json.py test_datetime_serialisation', gs_json_test_datetime_serialisation().canonical, 'fin_json_test_datetime_serialisation');
SELECT assert_eq('gs quant compatibility 0328 gs_quant/test/api/test_json.py test_date_or_datetime', gs_json_test_date_or_datetime().canonical, 'fin_json_test_date_or_datetime');
SELECT assert_eq('gs quant compatibility 0329 gs_quant/test/api/test_json.py test_time', gs_json_test_time().canonical, 'fin_json_test_time');
SELECT assert_eq('gs quant compatibility 0330 gs_quant/test/api/test_json.py test_custom_comments', gs_json_test_custom_comments().canonical, 'fin_json_test_custom_comments');
SELECT assert_eq('gs quant compatibility 0331 gs_quant/test/api/test_monitor.py test_get_many_monitors', gs_test_test_get_many_monitors().canonical, 'fin_gsq_test_test_get_many_monitors');
SELECT assert_eq('gs quant compatibility 0332 gs_quant/test/api/test_monitor.py test_get_monitor', gs_test_test_get_monitor().canonical, 'fin_gsq_test_test_get_monitor');
SELECT assert_eq('gs quant compatibility 0333 gs_quant/test/api/test_monitor.py test_create_monitor', gs_test_test_create_monitor().canonical, 'fin_gsq_test_test_create_monitor');
SELECT assert_eq('gs quant compatibility 0334 gs_quant/test/api/test_monitor.py test_update_monitor', gs_test_test_update_monitor().canonical, 'fin_gsq_test_test_update_monitor');
SELECT assert_eq('gs quant compatibility 0335 gs_quant/test/api/test_monitor.py test_delete_monitor', gs_test_test_delete_monitor().canonical, 'fin_gsq_test_test_delete_monitor');
SELECT assert_eq('gs quant compatibility 0336 gs_quant/test/api/test_monitor.py test_calculate_monitor', gs_test_test_calculate_monitor().canonical, 'fin_gsq_test_test_calculate_monitor');
SELECT assert_eq('gs quant compatibility 0337 gs_quant/test/api/test_portfolios.py test_get_many_portfolios', gs_test_test_get_many_portfolios().canonical, 'fin_gsq_test_test_get_many_portfolios');
SELECT assert_eq('gs quant compatibility 0338 gs_quant/test/api/test_portfolios.py test_get_portfolio', gs_test_test_get_portfolio().canonical, 'fin_gsq_test_test_get_portfolio');
SELECT assert_eq('gs quant compatibility 0339 gs_quant/test/api/test_portfolios.py test_create_portfolio', gs_test_test_create_portfolio().canonical, 'fin_gsq_test_test_create_portfolio');
SELECT assert_eq('gs quant compatibility 0340 gs_quant/test/api/test_portfolios.py test_update_portfolio', gs_test_test_update_portfolio().canonical, 'fin_gsq_test_test_update_portfolio');
SELECT assert_eq('gs quant compatibility 0341 gs_quant/test/api/test_portfolios.py test_delete_portfolio', gs_test_test_delete_portfolio().canonical, 'fin_gsq_test_test_delete_portfolio');
SELECT assert_eq('gs quant compatibility 0342 gs_quant/test/api/test_portfolios.py test_get_portfolio_positions', gs_test_test_get_portfolio_positions().canonical, 'fin_gsq_test_test_get_portfolio_positions');
SELECT assert_eq('gs quant compatibility 0343 gs_quant/test/api/test_portfolios.py test_get_portfolio_positions_for_date', gs_test_test_get_portfolio_positions_for_date().canonical, 'fin_gsq_test_test_get_portfolio_positions_for_date');
SELECT assert_eq('gs quant compatibility 0344 gs_quant/test/api/test_portfolios.py test_get_latest_portfolio_positions', gs_test_test_get_latest_portfolio_positions().canonical, 'fin_gsq_test_test_get_latest_portfolio_positions');
SELECT assert_eq('gs quant compatibility 0345 gs_quant/test/api/test_portfolios.py test_get_portfolio_position_dates', gs_test_test_get_portfolio_position_dates().canonical, 'fin_gsq_test_test_get_portfolio_position_dates');
SELECT assert_eq('gs quant compatibility 0346 gs_quant/test/api/test_portfolios.py test_portfolio_positions_data', gs_test_test_portfolio_positions_data().canonical, 'fin_gsq_test_test_portfolio_positions_data');
SELECT assert_eq('gs quant compatibility 0347 gs_quant/test/api/test_portfolios.py test_get_risk_models_by_coverage', gs_test_test_get_risk_models_by_coverage().canonical, 'fin_gsq_test_test_get_risk_models_by_coverage');
SELECT assert_eq('gs quant compatibility 0348 gs_quant/test/api/test_portfolios.py test_get_portfolio_analyze', gs_test_test_get_portfolio_analyze().canonical, 'fin_gsq_test_test_get_portfolio_analyze');
SELECT assert_eq('gs quant compatibility 0349 gs_quant/test/api/test_reports.py test_get_reports', gs_test_test_get_reports().canonical, 'fin_gsq_test_test_get_reports');
SELECT assert_eq('gs quant compatibility 0350 gs_quant/test/api/test_reports.py test_get_report', gs_test_test_get_report().canonical, 'fin_gsq_test_test_get_report');
SELECT assert_eq('gs quant compatibility 0351 gs_quant/test/api/test_reports.py test_create_report', gs_test_test_create_report().canonical, 'fin_gsq_test_test_create_report');
SELECT assert_eq('gs quant compatibility 0352 gs_quant/test/api/test_reports.py test_update_report', gs_test_test_update_report().canonical, 'fin_gsq_test_test_update_report');
SELECT assert_eq('gs quant compatibility 0353 gs_quant/test/api/test_reports.py test_delete_portfolio', gs_test_test_delete_portfolio_test_api_test_reports().canonical, 'fin_gsq_test_test_delete_portfolio_test_api_test_reports');
SELECT assert_eq('gs quant compatibility 0354 gs_quant/test/api/test_reports.py test_schedule_report', gs_test_test_schedule_report().canonical, 'fin_gsq_test_test_schedule_report');
SELECT assert_eq('gs quant compatibility 0355 gs_quant/test/api/test_reports.py test_get_report_status', gs_test_test_get_report_status().canonical, 'fin_gsq_test_test_get_report_status');
SELECT assert_eq('gs quant compatibility 0356 gs_quant/test/api/test_reports.py test_get_report_jobs', gs_test_test_get_report_jobs().canonical, 'fin_gsq_test_test_get_report_jobs');
SELECT assert_eq('gs quant compatibility 0357 gs_quant/test/api/test_reports.py test_report_job', gs_test_test_report_job().canonical, 'fin_gsq_test_test_report_job');
SELECT assert_eq('gs quant compatibility 0358 gs_quant/test/api/test_reports.py test_cancel_report_job', gs_test_test_cancel_report_job().canonical, 'fin_gsq_test_test_cancel_report_job');
SELECT assert_eq('gs quant compatibility 0359 gs_quant/test/api/test_reports.py test_update_report_job', gs_test_test_update_report_job().canonical, 'fin_gsq_test_test_update_report_job');
SELECT assert_eq('gs quant compatibility 0360 gs_quant/test/api/test_reports.py test_get_factor_risk_report_results', gs_test_test_get_factor_risk_report_results().canonical, 'fin_gsq_test_test_get_factor_risk_report_results');
SELECT assert_eq('gs quant compatibility 0361 gs_quant/test/api/test_reports.py test_get_factor_risk_report_view', gs_test_test_get_factor_risk_report_view().canonical, 'fin_gsq_test_test_get_factor_risk_report_view');
SELECT assert_eq('gs quant compatibility 0362 gs_quant/test/api/test_risk.py set_session', gs_test_set_session_test_api_test_risk().canonical, 'fin_gsq_test_set_session_test_api_test_risk');
SELECT assert_eq('gs quant compatibility 0363 gs_quant/test/api/test_risk.py structured_calc', gs_test_structured_calc().canonical, 'fin_gsq_test_structured_calc');
SELECT assert_eq('gs quant compatibility 0364 gs_quant/test/api/test_risk.py scalar_calc', gs_test_scalar_calc().canonical, 'fin_gsq_test_scalar_calc');
SELECT assert_eq('gs quant compatibility 0365 gs_quant/test/api/test_risk.py price', gs_test_price().canonical, 'fin_gsq_test_price');
SELECT assert_eq('gs quant compatibility 0366 gs_quant/test/api/test_risk.py test_price', gs_test_test_price().canonical, 'fin_gsq_test_test_price');
SELECT assert_eq('gs quant compatibility 0367 gs_quant/test/api/test_risk.py test_structured_calc', gs_test_test_structured_calc().canonical, 'fin_gsq_test_test_structured_calc');
SELECT assert_eq('gs quant compatibility 0368 gs_quant/test/api/test_risk.py test_scalar_calc', gs_test_test_scalar_calc().canonical, 'fin_gsq_test_test_scalar_calc');
SELECT assert_eq('gs quant compatibility 0369 gs_quant/test/api/test_risk.py test_async_calc', gs_test_test_async_calc().canonical, 'fin_gsq_test_test_async_calc');
SELECT assert_eq('gs quant compatibility 0370 gs_quant/test/api/test_risk.py test_disjoint_priceables_measures', gs_test_test_disjoint_priceables_measures().canonical, 'fin_gsq_test_test_disjoint_priceables_measures');
SELECT assert_eq('gs quant compatibility 0371 gs_quant/test/api/test_risk.py test_create_pretrade_execution_optimization', gs_test_test_create_pretrade_execution_optimization().canonical, 'fin_gsq_test_test_create_pretrade_execution_optimization');
SELECT assert_eq('gs quant compatibility 0372 gs_quant/test/api/test_risk.py test_get_pretrade_execution_optimization', gs_test_test_get_pretrade_execution_optimization().canonical, 'fin_gsq_test_test_get_pretrade_execution_optimization');
SELECT assert_eq('gs quant compatibility 0373 gs_quant/test/api/test_risk_models.py test_get_risk_models', gs_test_test_get_risk_models_test_api_test_risk_models().canonical, 'fin_gsq_test_test_get_risk_models_test_api_test_risk_models');
SELECT assert_eq('gs quant compatibility 0374 gs_quant/test/api/test_risk_models.py test_get_risk_model', gs_test_test_get_risk_model().canonical, 'fin_gsq_test_test_get_risk_model');
SELECT assert_eq('gs quant compatibility 0375 gs_quant/test/api/test_risk_models.py test_create_risk_model', gs_test_test_create_risk_model().canonical, 'fin_gsq_test_test_create_risk_model');
SELECT assert_eq('gs quant compatibility 0376 gs_quant/test/api/test_risk_models.py test_update_risk_model', gs_test_test_update_risk_model().canonical, 'fin_gsq_test_test_update_risk_model');
SELECT assert_eq('gs quant compatibility 0377 gs_quant/test/api/test_risk_models.py test_delete_risk_model', gs_test_test_delete_risk_model().canonical, 'fin_gsq_test_test_delete_risk_model');
SELECT assert_eq('gs quant compatibility 0378 gs_quant/test/api/test_risk_models.py test_get_risk_model_calendar', gs_test_test_get_risk_model_calendar().canonical, 'fin_gsq_test_test_get_risk_model_calendar');
SELECT assert_eq('gs quant compatibility 0379 gs_quant/test/api/test_risk_models.py test_upload_risk_model_calendar', gs_test_test_upload_risk_model_calendar().canonical, 'fin_gsq_test_test_upload_risk_model_calendar');
SELECT assert_eq('gs quant compatibility 0380 gs_quant/test/api/test_risk_models.py test_get_risk_model_factors', gs_test_test_get_risk_model_factors().canonical, 'fin_gsq_test_test_get_risk_model_factors');
SELECT assert_eq('gs quant compatibility 0381 gs_quant/test/api/test_risk_models.py test_create_risk_model_factor', gs_test_test_create_risk_model_factor().canonical, 'fin_gsq_test_test_create_risk_model_factor');
SELECT assert_eq('gs quant compatibility 0382 gs_quant/test/api/test_risk_models.py test_update_risk_model_factor', gs_test_test_update_risk_model_factor().canonical, 'fin_gsq_test_test_update_risk_model_factor');
SELECT assert_eq('gs quant compatibility 0383 gs_quant/test/api/test_risk_models.py test_get_risk_model_coverage', gs_test_test_get_risk_model_coverage().canonical, 'fin_gsq_test_test_get_risk_model_coverage');
SELECT assert_eq('gs quant compatibility 0384 gs_quant/test/api/test_risk_models.py test_upload_risk_model_data', gs_test_test_upload_risk_model_data().canonical, 'fin_gsq_test_test_upload_risk_model_data');
SELECT assert_eq('gs quant compatibility 0385 gs_quant/test/api/test_risk_models.py test_upload_macro_risk_model_data', gs_test_test_upload_macro_risk_model_data().canonical, 'fin_gsq_test_test_upload_macro_risk_model_data');
SELECT assert_eq('gs quant compatibility 0386 gs_quant/test/api/test_risk_models.py test_get_risk_model_data', gs_test_test_get_risk_model_data().canonical, 'fin_gsq_test_test_get_risk_model_data');
SELECT assert_eq('gs quant compatibility 0387 gs_quant/test/api/test_risk_models.py test_get_r_squared', gs_test_test_get_r_squared().canonical, 'fin_gsq_test_test_get_r_squared');
SELECT assert_eq('gs quant compatibility 0388 gs_quant/test/api/test_risk_models.py test_get_fair_value_gap', gs_test_test_get_fair_value_gap().canonical, 'fin_gsq_test_test_get_fair_value_gap');
SELECT assert_eq('gs quant compatibility 0389 gs_quant/test/api/test_risk_models.py test_get_factor_standard_deviation', gs_test_test_get_factor_standard_deviation().canonical, 'fin_gsq_test_test_get_factor_standard_deviation');
SELECT assert_eq('gs quant compatibility 0390 gs_quant/test/api/test_risk_models.py test_get_factor_z_score', gs_test_test_get_factor_z_score().canonical, 'fin_gsq_test_test_get_factor_z_score');
SELECT assert_eq('gs quant compatibility 0391 gs_quant/test/api/test_risk_models.py test_get_predicted_beta', gs_test_test_get_predicted_beta().canonical, 'fin_gsq_test_test_get_predicted_beta');
SELECT assert_eq('gs quant compatibility 0392 gs_quant/test/api/test_risk_models.py test_get_global_predicted_beta', gs_test_test_get_global_predicted_beta().canonical, 'fin_gsq_test_test_get_global_predicted_beta');
SELECT assert_eq('gs quant compatibility 0393 gs_quant/test/api/test_risk_models.py test_get_daily_return', gs_test_test_get_daily_return().canonical, 'fin_gsq_test_test_get_daily_return');
SELECT assert_eq('gs quant compatibility 0394 gs_quant/test/api/test_risk_models.py test_get_specific_return', gs_test_test_get_specific_return().canonical, 'fin_gsq_test_test_get_specific_return');
SELECT assert_eq('gs quant compatibility 0395 gs_quant/test/api/test_scenarios.py test_get_many_scenarios', gs_test_test_get_many_scenarios().canonical, 'fin_gsq_test_test_get_many_scenarios');
SELECT assert_eq('gs quant compatibility 0396 gs_quant/test/api/test_scenarios.py test_get_scenario', gs_test_test_get_scenario().canonical, 'fin_gsq_test_test_get_scenario');
SELECT assert_eq('gs quant compatibility 0397 gs_quant/test/api/test_scenarios.py test_create_scenario', gs_test_test_create_scenario().canonical, 'fin_gsq_test_test_create_scenario');
SELECT assert_eq('gs quant compatibility 0398 gs_quant/test/api/test_scenarios.py test_update_scenario', gs_test_test_update_scenario().canonical, 'fin_gsq_test_test_update_scenario');
SELECT assert_eq('gs quant compatibility 0399 gs_quant/test/api/test_scenarios.py test_delete_scenario', gs_test_test_delete_scenario().canonical, 'fin_gsq_test_test_delete_scenario');
SELECT assert_eq('gs quant compatibility 0400 gs_quant/test/api/test_scenarios.py test_scenario_calculate', gs_test_test_scenario_calculate().canonical, 'fin_gsq_test_test_scenario_calculate');
SELECT assert_eq('gs quant compatibility 0401 gs_quant/test/api/test_target.py classes', gs_test_classes().canonical, 'fin_gsq_test_classes');
SELECT assert_eq('gs quant compatibility 0402 gs_quant/test/api/test_target.py test_enum', gs_test_test_enum().canonical, 'fin_gsq_test_test_enum');
SELECT assert_eq('gs quant compatibility 0403 gs_quant/test/api/test_target.py test_classes', gs_test_test_classes().canonical, 'fin_gsq_test_test_classes');
SELECT assert_eq('gs quant compatibility 0404 gs_quant/test/api/test_thread_manager.py dummy_function', gs_test_dummy_function().canonical, 'fin_gsq_test_dummy_function');
SELECT assert_eq('gs quant compatibility 0405 gs_quant/test/api/test_thread_manager.py test_thread_manager', gs_test_test_thread_manager().canonical, 'fin_gsq_test_test_thread_manager');
SELECT assert_eq('gs quant compatibility 0406 gs_quant/test/api/test_users.py test_get_users', gs_test_test_get_users().canonical, 'fin_gsq_test_test_get_users');
SELECT assert_eq('gs quant compatibility 0407 gs_quant/test/api/test_users.py test_get_current_user_info', gs_test_test_get_current_user_info().canonical, 'fin_gsq_test_test_get_current_user_info');
SELECT assert_eq('gs quant compatibility 0408 gs_quant/test/backtest/test_backtest_eq_vol_engine.py set_session', gs_test_set_session_test_backtest_test_backte_882304ac4b().canonical, 'fin_gsq_test_set_session_test_backtest_test_backte_882304ac4b');
SELECT assert_eq('gs quant compatibility 0409 gs_quant/test/backtest/test_backtest_eq_vol_engine.py api_mock_data', gs_test_api_mock_data().canonical, 'fin_gsq_test_api_mock_data');
SELECT assert_eq('gs quant compatibility 0410 gs_quant/test/backtest/test_backtest_eq_vol_engine.py mock_api_response', gs_test_mock_api_response().canonical, 'fin_gsq_test_mock_api_response');
SELECT assert_eq('gs quant compatibility 0411 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_eq_vol_engine_result', gs_test_test_eq_vol_engine_result().canonical, 'fin_gsq_test_test_eq_vol_engine_result');
SELECT assert_eq('gs quant compatibility 0412 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_basic', gs_test_test_engine_mapping_basic().canonical, 'fin_gsq_test_test_engine_mapping_basic');
SELECT assert_eq('gs quant compatibility 0413 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_trade_quantity', gs_test_test_engine_mapping_trade_quantity().canonical, 'fin_gsq_test_test_engine_mapping_trade_quantity');
SELECT assert_eq('gs quant compatibility 0414 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_with_signals', gs_test_test_engine_mapping_with_signals().canonical, 'fin_gsq_test_test_engine_mapping_with_signals');
SELECT assert_eq('gs quant compatibility 0415 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_trade_quantity_nav', gs_test_test_engine_mapping_trade_quantity_nav().canonical, 'fin_gsq_test_test_engine_mapping_trade_quantity_nav');
SELECT assert_eq('gs quant compatibility 0416 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_listed_expiry_date', gs_test_test_engine_mapping_listed_expiry_date().canonical, 'fin_gsq_test_test_engine_mapping_listed_expiry_date');
SELECT assert_eq('gs quant compatibility 0417 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_listed_roll_date', gs_test_test_engine_mapping_listed_roll_date().canonical, 'fin_gsq_test_test_engine_mapping_listed_roll_date');
SELECT assert_eq('gs quant compatibility 0418 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_market_model', gs_test_test_engine_mapping_market_model().canonical, 'fin_gsq_test_test_engine_mapping_market_model');
SELECT assert_eq('gs quant compatibility 0419 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_portfolio', gs_test_test_engine_mapping_portfolio().canonical, 'fin_gsq_test_test_engine_mapping_portfolio');
SELECT assert_eq('gs quant compatibility 0420 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_supports_strategy', gs_test_test_supports_strategy().canonical, 'fin_gsq_test_test_supports_strategy');
SELECT assert_eq('gs quant compatibility 0421 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_basic_leg_size', gs_test_test_engine_mapping_basic_leg_size().canonical, 'fin_gsq_test_test_engine_mapping_basic_leg_size');
SELECT assert_eq('gs quant compatibility 0422 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_fixed_expiry', gs_test_test_engine_mapping_fixed_expiry().canonical, 'fin_gsq_test_test_engine_mapping_fixed_expiry');
SELECT assert_eq('gs quant compatibility 0423 gs_quant/test/backtest/test_backtest_eq_vol_engine.py test_engine_mapping_delta_hedge', gs_test_test_engine_mapping_delta_hedge().canonical, 'fin_gsq_test_test_engine_mapping_delta_hedge');
SELECT assert_eq('gs quant compatibility 0424 gs_quant/test/backtest/test_backtest_flow_vol.py set_session', gs_test_set_session_test_backtest_test_backtest_flow_vol().canonical, 'fin_gsq_test_set_session_test_backtest_test_backtest_flow_vol');
SELECT assert_eq('gs quant compatibility 0425 gs_quant/test/backtest/test_backtest_flow_vol.py test_eqstrategies_backtest', gs_test_test_eqstrategies_backtest().canonical, 'fin_gsq_test_test_eqstrategies_backtest');
SELECT assert_eq('gs quant compatibility 0426 gs_quant/test/backtest/test_backtest_predefined.py test_backtest_predefined_timezone_aware', gs_test_test_backtest_predefined_timezone_aware().canonical, 'fin_gsq_test_test_backtest_predefined_timezone_aware');
SELECT assert_eq('gs quant compatibility 0427 gs_quant/test/backtest/test_backtest_predefined.py test_backtest_predefined', gs_test_test_backtest_predefined().canonical, 'fin_gsq_test_test_backtest_predefined');
SELECT assert_eq('gs quant compatibility 0428 gs_quant/test/backtest/test_generic_engine.py mock_pricing_context', gs_test_mock_pricing_context().canonical, 'fin_gsq_test_mock_pricing_context');
SELECT assert_eq('gs quant compatibility 0429 gs_quant/test/backtest/test_generic_engine.py instrument_name', gs_test_instrument_name().canonical, 'fin_gsq_test_instrument_name');
SELECT assert_eq('gs quant compatibility 0430 gs_quant/test/backtest/test_generic_engine.py test_generic_engine_simple', gs_test_test_generic_engine_simple().canonical, 'fin_gsq_test_test_generic_engine_simple');
SELECT assert_eq('gs quant compatibility 0431 gs_quant/test/backtest/test_generic_engine.py test_hedge_action_risk_trigger', gs_test_test_hedge_action_risk_trigger().canonical, 'fin_gsq_test_test_hedge_action_risk_trigger');
SELECT assert_eq('gs quant compatibility 0432 gs_quant/test/backtest/test_generic_engine.py test_hedge_without_risk', gs_test_test_hedge_without_risk().canonical, 'fin_gsq_test_test_hedge_without_risk');
SELECT assert_eq('gs quant compatibility 0433 gs_quant/test/backtest/test_generic_engine.py test_mkt_trigger_data_sources', gs_test_test_mkt_trigger_data_sources().canonical, 'fin_gsq_test_test_mkt_trigger_data_sources');
SELECT assert_eq('gs quant compatibility 0434 gs_quant/test/backtest/test_generic_engine.py test_exit_action_noarg', gs_test_test_exit_action_noarg().canonical, 'fin_gsq_test_test_exit_action_noarg');
SELECT assert_eq('gs quant compatibility 0435 gs_quant/test/backtest/test_generic_engine.py test_exit_action_emptyresults', gs_test_test_exit_action_emptyresults().canonical, 'fin_gsq_test_test_exit_action_emptyresults');
SELECT assert_eq('gs quant compatibility 0436 gs_quant/test/backtest/test_generic_engine.py test_exit_action_bytradename', gs_test_test_exit_action_bytradename().canonical, 'fin_gsq_test_test_exit_action_bytradename');
SELECT assert_eq('gs quant compatibility 0437 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_action', gs_test_test_add_scaled_action().canonical, 'fin_gsq_test_test_add_scaled_action');
SELECT assert_eq('gs quant compatibility 0438 gs_quant/test/backtest/test_generic_engine.py test_scaled_transaction_cost', gs_test_test_scaled_transaction_cost().canonical, 'fin_gsq_test_test_scaled_transaction_cost');
SELECT assert_eq('gs quant compatibility 0439 gs_quant/test/backtest/test_generic_engine.py test_agg_transaction_cost', gs_test_test_agg_transaction_cost().canonical, 'fin_gsq_test_test_agg_transaction_cost');
SELECT assert_eq('gs quant compatibility 0440 gs_quant/test/backtest/test_generic_engine.py test_risk_scaled_transaction_cost', gs_test_test_risk_scaled_transaction_cost().canonical, 'fin_gsq_test_test_risk_scaled_transaction_cost');
SELECT assert_eq('gs quant compatibility 0441 gs_quant/test/backtest/test_generic_engine.py test_hedge_transaction_costs', gs_test_test_hedge_transaction_costs().canonical, 'fin_gsq_test_test_hedge_transaction_costs');
SELECT assert_eq('gs quant compatibility 0442 gs_quant/test/backtest/test_generic_engine.py test_exit_transaction_costs', gs_test_test_exit_transaction_costs().canonical, 'fin_gsq_test_test_exit_transaction_costs');
SELECT assert_eq('gs quant compatibility 0443 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_action_nav', gs_test_test_add_scaled_action_nav().canonical, 'fin_gsq_test_test_add_scaled_action_nav');
SELECT assert_eq('gs quant compatibility 0444 gs_quant/test/backtest/test_generic_engine.py nav_scaled_action_transaction_cost_test_for_agg_type', gs_test_nav_scaled_action_transaction_cost_test_for_agg_type().canonical, 'fin_gsq_test_nav_scaled_action_transaction_cost_test_for_agg_type');
SELECT assert_eq('gs quant compatibility 0445 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_action_nav_with_transaction_costs', gs_test_test_add_scaled_action_nav_with_transaction_costs().canonical, 'fin_gsq_test_test_add_scaled_action_nav_with_transaction_costs');
SELECT assert_eq('gs quant compatibility 0446 gs_quant/test/backtest/test_generic_engine.py test_generic_engine_custom_price_measure', gs_test_test_generic_engine_custom_price_measure().canonical, 'fin_gsq_test_test_generic_engine_custom_price_measure');
SELECT assert_eq('gs quant compatibility 0447 gs_quant/test/backtest/test_generic_engine.py test_serialisation', gs_test_test_serialisation().canonical, 'fin_gsq_test_test_serialisation');
SELECT assert_eq('gs quant compatibility 0448 gs_quant/test/backtest/test_generic_engine.py test_initial_portfolio', gs_test_test_initial_portfolio().canonical, 'fin_gsq_test_test_initial_portfolio');
SELECT assert_eq('gs quant compatibility 0449 gs_quant/test/backtest/test_generic_engine.py test_add_scaled_trade_action_with_quantity_signal', gs_test_test_add_scaled_trade_action_with_quantity_signal().canonical, 'fin_gsq_test_test_add_scaled_trade_action_with_quantity_signal');
SELECT assert_eq('gs quant compatibility 0450 gs_quant/test/backtest/test_generic_engine.py test_add_weighted_trade_action', gs_test_test_add_weighted_trade_action().canonical, 'fin_gsq_test_test_add_weighted_trade_action');
SELECT assert_eq('gs quant compatibility 0451 gs_quant/test/backtest/test_generic_engine.py test_early_exit_pos_limit_scaled_action', gs_test_test_early_exit_pos_limit_scaled_action().canonical, 'fin_gsq_test_test_early_exit_pos_limit_scaled_action');
SELECT assert_eq('gs quant compatibility 0452 gs_quant/test/backtest/test_triggers.py test_date_trigger', gs_test_test_date_trigger().canonical, 'fin_gsq_test_test_date_trigger');
SELECT assert_eq('gs quant compatibility 0453 gs_quant/test/backtest/test_triggers.py test_aggregate_triggger', gs_test_test_aggregate_triggger().canonical, 'fin_gsq_test_test_aggregate_triggger');
SELECT assert_eq('gs quant compatibility 0454 gs_quant/test/backtest/test_triggers.py test_not_triggger', gs_test_test_not_triggger().canonical, 'fin_gsq_test_test_not_triggger');
SELECT assert_eq('gs quant compatibility 0455 gs_quant/test/config/test_options.py test_display_options', gs_test_test_display_options().canonical, 'fin_gsq_test_test_display_options');
SELECT assert_eq('gs quant compatibility 0456 gs_quant/test/data/test_data_coordinate.py test_immutability', gs_test_test_immutability().canonical, 'fin_gsq_test_test_immutability');
SELECT assert_eq('gs quant compatibility 0457 gs_quant/test/data/test_data_coordinate.py test_equals', gs_test_test_equals().canonical, 'fin_gsq_test_test_equals');
SELECT assert_eq('gs quant compatibility 0458 gs_quant/test/data/test_data_coordinate.py test_equals_measure_str', gs_test_test_equals_measure_str().canonical, 'fin_gsq_test_test_equals_measure_str');
SELECT assert_eq('gs quant compatibility 0459 gs_quant/test/data/test_dataset.py test_query_data', gs_test_test_query_data().canonical, 'fin_gsq_test_test_query_data');
SELECT assert_eq('gs quant compatibility 0460 gs_quant/test/data/test_dataset.py test_query_data_intervals', gs_test_test_query_data_intervals().canonical, 'fin_gsq_test_test_query_data_intervals');
SELECT assert_eq('gs quant compatibility 0461 gs_quant/test/data/test_dataset.py test_query_data_types', gs_test_test_query_data_types().canonical, 'fin_gsq_test_test_query_data_types');
SELECT assert_eq('gs quant compatibility 0462 gs_quant/test/data/test_dataset.py test_last_data', gs_test_test_last_data().canonical, 'fin_gsq_test_test_last_data');
SELECT assert_eq('gs quant compatibility 0463 gs_quant/test/data/test_dataset.py test_get_data_series', gs_test_test_get_data_series_test_data_test_dataset().canonical, 'fin_gsq_test_test_get_data_series_test_data_test_dataset');
SELECT assert_eq('gs quant compatibility 0464 gs_quant/test/data/test_dataset.py test_get_coverage', gs_test_test_get_coverage().canonical, 'fin_gsq_test_test_get_coverage');
SELECT assert_eq('gs quant compatibility 0465 gs_quant/test/data/test_dataset.py test_construct_dataframe_with_types', gs_test_test_construct_dataframe_with_types().canonical, 'fin_gsq_test_test_construct_dataframe_with_types');
SELECT assert_eq('gs quant compatibility 0466 gs_quant/test/data/test_dataset.py test_construct_dataframe_var_schema', gs_test_test_construct_dataframe_var_schema().canonical, 'fin_gsq_test_test_construct_dataframe_var_schema');
SELECT assert_eq('gs quant compatibility 0467 gs_quant/test/data/test_dataset.py test_dataframe_with_mixed_date_type', gs_test_test_dataframe_with_mixed_date_type().canonical, 'fin_gsq_test_test_dataframe_with_mixed_date_type');
SELECT assert_eq('gs quant compatibility 0468 gs_quant/test/data/test_dataset.py test_data_series_format', gs_test_test_data_series_format().canonical, 'fin_gsq_test_test_data_series_format');
SELECT assert_eq('gs quant compatibility 0469 gs_quant/test/data/test_dataset.py test_get_data_bulk', gs_test_test_get_data_bulk().canonical, 'fin_gsq_test_test_get_data_bulk');
SELECT assert_eq('gs quant compatibility 0470 gs_quant/test/data/test_query.py test_build_market_data_query', gs_test_test_build_market_data_query().canonical, 'fin_gsq_test_test_build_market_data_query');
SELECT assert_eq('gs quant compatibility 0471 gs_quant/test/datetime_/test_date.py test_has_feb_29', gs_test_test_has_feb_29().canonical, 'fin_gsq_test_test_has_feb_29');
SELECT assert_eq('gs quant compatibility 0472 gs_quant/test/datetime_/test_date.py test_today_with_location', gs_test_test_today_with_location().canonical, 'fin_gsq_test_test_today_with_location');
SELECT assert_eq('gs quant compatibility 0473 gs_quant/test/datetime_/test_date.py test_day_count_fraction', gs_test_test_day_count_fraction().canonical, 'fin_gsq_test_test_day_count_fraction');
SELECT assert_eq('gs quant compatibility 0474 gs_quant/test/datetime_/test_gscalendar.py test_gs_calendar_single', gs_test_test_gs_calendar_single().canonical, 'fin_gsq_test_test_gs_calendar_single');
SELECT assert_eq('gs quant compatibility 0475 gs_quant/test/datetime_/test_gscalendar.py test_gs_calendar_tuple', gs_test_test_gs_calendar_tuple().canonical, 'fin_gsq_test_test_gs_calendar_tuple');
SELECT assert_eq('gs quant compatibility 0476 gs_quant/test/datetime_/test_point.py test_point_sort_order', gs_test_test_point_sort_order().canonical, 'fin_gsq_test_test_point_sort_order');
SELECT assert_eq('gs quant compatibility 0477 gs_quant/test/datetime_/test_relative_date.py test_rule_parsing', gs_test_test_rule_parsing().canonical, 'fin_gsq_test_test_rule_parsing');
SELECT assert_eq('gs quant compatibility 0478 gs_quant/test/datetime_/test_relative_date.py test_rule_a_', gs_test_test_rule_a().canonical, 'fin_gsq_test_test_rule_a');
SELECT assert_eq('gs quant compatibility 0479 gs_quant/test/datetime_/test_relative_date.py test_rule_b', gs_test_test_rule_b().canonical, 'fin_gsq_test_test_rule_b');
SELECT assert_eq('gs quant compatibility 0480 gs_quant/test/datetime_/test_relative_date.py test_rule_d', gs_test_test_rule_d().canonical, 'fin_gsq_test_test_rule_d');
SELECT assert_eq('gs quant compatibility 0481 gs_quant/test/datetime_/test_relative_date.py test_rule_e', gs_test_test_rule_e().canonical, 'fin_gsq_test_test_rule_e');
SELECT assert_eq('gs quant compatibility 0482 gs_quant/test/datetime_/test_relative_date.py test_rule_m_', gs_test_test_rule_m().canonical, 'fin_gsq_test_test_rule_m');
SELECT assert_eq('gs quant compatibility 0483 gs_quant/test/datetime_/test_relative_date.py test_rule_t_', gs_test_test_rule_t().canonical, 'fin_gsq_test_test_rule_t');
SELECT assert_eq('gs quant compatibility 0484 gs_quant/test/datetime_/test_relative_date.py test_rule_w_', gs_test_test_rule_w().canonical, 'fin_gsq_test_test_rule_w');
SELECT assert_eq('gs quant compatibility 0485 gs_quant/test/datetime_/test_relative_date.py test_rule_r_', gs_test_test_rule_r().canonical, 'fin_gsq_test_test_rule_r');
SELECT assert_eq('gs quant compatibility 0486 gs_quant/test/datetime_/test_relative_date.py test_rule_f_', gs_test_test_rule_f().canonical, 'fin_gsq_test_test_rule_f');
SELECT assert_eq('gs quant compatibility 0487 gs_quant/test/datetime_/test_relative_date.py test_rule_v_', gs_test_test_rule_v().canonical, 'fin_gsq_test_test_rule_v');
SELECT assert_eq('gs quant compatibility 0488 gs_quant/test/datetime_/test_relative_date.py test_rule_z_', gs_test_test_rule_z().canonical, 'fin_gsq_test_test_rule_z');
SELECT assert_eq('gs quant compatibility 0489 gs_quant/test/datetime_/test_relative_date.py test_rule_g', gs_test_test_rule_g().canonical, 'fin_gsq_test_test_rule_g');
SELECT assert_eq('gs quant compatibility 0490 gs_quant/test/datetime_/test_relative_date.py test_rule_n_', gs_test_test_rule_n().canonical, 'fin_gsq_test_test_rule_n');
SELECT assert_eq('gs quant compatibility 0491 gs_quant/test/datetime_/test_relative_date.py test_rule_u_', gs_test_test_rule_u().canonical, 'fin_gsq_test_test_rule_u');
SELECT assert_eq('gs quant compatibility 0492 gs_quant/test/datetime_/test_relative_date.py test_rule_x_', gs_test_test_rule_x().canonical, 'fin_gsq_test_test_rule_x');
SELECT assert_eq('gs quant compatibility 0493 gs_quant/test/datetime_/test_relative_date.py test_rule_s_', gs_test_test_rule_s().canonical, 'fin_gsq_test_test_rule_s');
SELECT assert_eq('gs quant compatibility 0494 gs_quant/test/datetime_/test_relative_date.py test_rule_g_', gs_test_test_rule_g_test_datetime_test_relative_date().canonical, 'fin_gsq_test_test_rule_g_test_datetime_test_relative_date');
SELECT assert_eq('gs quant compatibility 0495 gs_quant/test/datetime_/test_relative_date.py test_rule_i_', gs_test_test_rule_i().canonical, 'fin_gsq_test_test_rule_i');
SELECT assert_eq('gs quant compatibility 0496 gs_quant/test/datetime_/test_relative_date.py test_rule_p_', gs_test_test_rule_p().canonical, 'fin_gsq_test_test_rule_p');
SELECT assert_eq('gs quant compatibility 0497 gs_quant/test/datetime_/test_relative_date.py test_rule_w', gs_test_test_rule_w_test_datetime_test_relative_date().canonical, 'fin_gsq_test_test_rule_w_test_datetime_test_relative_date');
SELECT assert_eq('gs quant compatibility 0498 gs_quant/test/datetime_/test_relative_date.py test_rule_k', gs_test_test_rule_k().canonical, 'fin_gsq_test_test_rule_k');
SELECT assert_eq('gs quant compatibility 0499 gs_quant/test/datetime_/test_relative_date.py test_rule_r', gs_test_test_rule_r_test_datetime_test_relative_date().canonical, 'fin_gsq_test_test_rule_r_test_datetime_test_relative_date');
SELECT assert_eq('gs quant compatibility 0500 gs_quant/test/datetime_/test_relative_date.py test_rule_u', gs_test_test_rule_u_test_datetime_test_relative_date().canonical, 'fin_gsq_test_test_rule_u_test_datetime_test_relative_date');
SELECT assert_eq('gs quant compatibility 0501 gs_quant/test/datetime_/test_relative_date.py test_rule_v', gs_test_test_rule_v_test_datetime_test_relative_date().canonical, 'fin_gsq_test_test_rule_v_test_datetime_test_relative_date');
SELECT assert_eq('gs quant compatibility 0502 gs_quant/test/datetime_/test_relative_date.py test_rule_x', gs_test_test_rule_x_test_datetime_test_relative_date().canonical, 'fin_gsq_test_test_rule_x_test_datetime_test_relative_date');
SELECT assert_eq('gs quant compatibility 0503 gs_quant/test/datetime_/test_relative_date.py test_rule_y', gs_test_test_rule_y().canonical, 'fin_gsq_test_test_rule_y');
SELECT assert_eq('gs quant compatibility 0504 gs_quant/test/datetime_/test_relative_date.py test_chaining', gs_test_test_chaining().canonical, 'fin_gsq_test_test_chaining');
SELECT assert_eq('gs quant compatibility 0505 gs_quant/test/datetime_/test_relative_date.py test_rule_e_minus_u', gs_test_test_rule_e_minus_u().canonical, 'fin_gsq_test_test_rule_e_minus_u');
SELECT assert_eq('gs quant compatibility 0506 gs_quant/test/datetime_/test_relative_date.py test_rule_roll_convention', gs_test_test_rule_roll_convention().canonical, 'fin_gsq_test_test_rule_roll_convention');
SELECT assert_eq('gs quant compatibility 0507 gs_quant/test/datetime_/test_relative_date.py mock_holiday_data', gs_test_mock_holiday_data().canonical, 'fin_gsq_test_mock_holiday_data');
SELECT assert_eq('gs quant compatibility 0508 gs_quant/test/datetime_/test_relative_date.py test_currency_holiday_calendars', gs_test_test_currency_holiday_calendars().canonical, 'fin_gsq_test_test_currency_holiday_calendars');
SELECT assert_eq('gs quant compatibility 0509 gs_quant/test/datetime_/test_time.py test_time_difference_as_string', gs_test_test_time_difference_as_string().canonical, 'fin_gsq_test_test_time_difference_as_string');
SELECT assert_eq('gs quant compatibility 0510 gs_quant/test/entities/test_entitlements.py get_fake_user', gs_test_get_fake_user().canonical, 'fin_gsq_test_get_fake_user');
SELECT assert_eq('gs quant compatibility 0511 gs_quant/test/entities/test_entitlements.py get_fake_group', gs_test_get_fake_group().canonical, 'fin_gsq_test_get_fake_group');
SELECT assert_eq('gs quant compatibility 0512 gs_quant/test/entities/test_entitlements.py test_to_target', gs_test_test_to_target().canonical, 'fin_gsq_test_test_to_target');
SELECT assert_eq('gs quant compatibility 0513 gs_quant/test/entities/test_entitlements.py test_to_dict', gs_test_test_to_dict().canonical, 'fin_gsq_test_test_to_dict');
SELECT assert_eq('gs quant compatibility 0514 gs_quant/test/entities/test_entitlements.py test_from_target', gs_test_test_from_target().canonical, 'fin_gsq_test_test_from_target');
SELECT assert_eq('gs quant compatibility 0515 gs_quant/test/entities/test_entitlements.py test_from_dict', gs_test_test_from_dict_test_entities_test_entitlements().canonical, 'fin_gsq_test_test_from_dict_test_entities_test_entitlements');
SELECT assert_eq('gs quant compatibility 0516 gs_quant/test/entities/test_group.py test_get', gs_test_test_get().canonical, 'fin_gsq_test_test_get');
SELECT assert_eq('gs quant compatibility 0517 gs_quant/test/entities/test_group.py test_get_many', gs_test_test_get_many().canonical, 'fin_gsq_test_test_get_many');
SELECT assert_eq('gs quant compatibility 0518 gs_quant/test/entities/test_group.py test_save_update', gs_test_test_save_update().canonical, 'fin_gsq_test_test_save_update');
SELECT assert_eq('gs quant compatibility 0519 gs_quant/test/entities/test_group.py test_save_create', gs_test_test_save_create().canonical, 'fin_gsq_test_test_save_create');
SELECT assert_eq('gs quant compatibility 0520 gs_quant/test/entities/test_user.py test_get', gs_test_test_get_test_entities_test_user().canonical, 'fin_gsq_test_test_get_test_entities_test_user');
SELECT assert_eq('gs quant compatibility 0521 gs_quant/test/entities/test_user.py test_get_many', gs_test_test_get_many_test_entities_test_user().canonical, 'fin_gsq_test_test_get_many_test_entities_test_user');
SELECT assert_eq('gs quant compatibility 0522 gs_quant/test/markets/test_baskets.py mock_session', gs_test_mock_session_test_markets_test_baskets().canonical, 'fin_gsq_test_mock_session_test_markets_test_baskets');
SELECT assert_eq('gs quant compatibility 0523 gs_quant/test/markets/test_baskets.py mock_response', gs_test_mock_response().canonical, 'fin_gsq_test_mock_response');
SELECT assert_eq('gs quant compatibility 0524 gs_quant/test/markets/test_baskets.py mock_basket_init', gs_test_mock_basket_init().canonical, 'fin_gsq_test_mock_basket_init');
SELECT assert_eq('gs quant compatibility 0525 gs_quant/test/markets/test_baskets.py test_basket_error_messages', gs_test_test_basket_error_messages().canonical, 'fin_gsq_test_test_basket_error_messages');
SELECT assert_eq('gs quant compatibility 0526 gs_quant/test/markets/test_baskets.py test_basket_create', gs_test_test_basket_create_test_markets_test_baskets().canonical, 'fin_gsq_test_test_basket_create_test_markets_test_baskets');
SELECT assert_eq('gs quant compatibility 0527 gs_quant/test/markets/test_baskets.py test_basket_clone', gs_test_test_basket_clone().canonical, 'fin_gsq_test_test_basket_clone');
SELECT assert_eq('gs quant compatibility 0528 gs_quant/test/markets/test_baskets.py test_basket_edit', gs_test_test_basket_edit_test_markets_test_baskets().canonical, 'fin_gsq_test_test_basket_edit_test_markets_test_baskets');
SELECT assert_eq('gs quant compatibility 0529 gs_quant/test/markets/test_baskets.py test_basket_rebalance', gs_test_test_basket_rebalance_test_markets_test_baskets().canonical, 'fin_gsq_test_test_basket_rebalance_test_markets_test_baskets');
SELECT assert_eq('gs quant compatibility 0530 gs_quant/test/markets/test_baskets.py test_basket_edit_and_rebalance', gs_test_test_basket_edit_and_rebalance().canonical, 'fin_gsq_test_test_basket_edit_and_rebalance');
SELECT assert_eq('gs quant compatibility 0531 gs_quant/test/markets/test_baskets.py test_basket_update_entitlements', gs_test_test_basket_update_entitlements().canonical, 'fin_gsq_test_test_basket_update_entitlements');
SELECT assert_eq('gs quant compatibility 0532 gs_quant/test/markets/test_baskets.py test_upload_position_history', gs_test_test_upload_position_history().canonical, 'fin_gsq_test_test_upload_position_history');
SELECT assert_eq('gs quant compatibility 0533 gs_quant/test/markets/test_baskets.py test_update_risk_reports', gs_test_test_update_risk_reports().canonical, 'fin_gsq_test_test_update_risk_reports');
SELECT assert_eq('gs quant compatibility 0534 gs_quant/test/markets/test_close_market.py test_close_market_dict', gs_test_test_close_market_dict().canonical, 'fin_gsq_test_test_close_market_dict');
SELECT assert_eq('gs quant compatibility 0535 gs_quant/test/markets/test_close_market.py test_close_market_roll', gs_test_test_close_market_roll().canonical, 'fin_gsq_test_test_close_market_roll');
SELECT assert_eq('gs quant compatibility 0536 gs_quant/test/markets/test_close_market.py test_close_market_roll_diff_days', gs_test_test_close_market_roll_diff_days().canonical, 'fin_gsq_test_test_close_market_roll_diff_days');
SELECT assert_eq('gs quant compatibility 0537 gs_quant/test/markets/test_hedger.py test_hedge_exclusions_to_dict', gs_test_test_hedge_exclusions_to_dict().canonical, 'fin_gsq_test_test_hedge_exclusions_to_dict');
SELECT assert_eq('gs quant compatibility 0538 gs_quant/test/markets/test_hedger.py test_hedge_constraints_to_dict', gs_test_test_hedge_constraints_to_dict().canonical, 'fin_gsq_test_test_hedge_constraints_to_dict');
SELECT assert_eq('gs quant compatibility 0539 gs_quant/test/markets/test_hedger.py test_format_hedge_calculate_results', gs_test_test_format_hedge_calculate_results().canonical, 'fin_gsq_test_test_format_hedge_calculate_results');
SELECT assert_eq('gs quant compatibility 0540 gs_quant/test/markets/test_hedger.py get_mock_hedge', gs_test_get_mock_hedge().canonical, 'fin_gsq_test_get_mock_hedge');
SELECT assert_eq('gs quant compatibility 0541 gs_quant/test/markets/test_hedger.py test_get_constituents', gs_test_test_get_constituents().canonical, 'fin_gsq_test_test_get_constituents');
SELECT assert_eq('gs quant compatibility 0542 gs_quant/test/markets/test_hedger.py test_get_statistics', gs_test_test_get_statistics().canonical, 'fin_gsq_test_test_get_statistics');
SELECT assert_eq('gs quant compatibility 0543 gs_quant/test/markets/test_hedger.py test_get_backtest_performance', gs_test_test_get_backtest_performance().canonical, 'fin_gsq_test_test_get_backtest_performance');
SELECT assert_eq('gs quant compatibility 0544 gs_quant/test/markets/test_instrument.py test_instrument_resolve', gs_test_test_instrument_resolve().canonical, 'fin_gsq_test_test_instrument_resolve');
SELECT assert_eq('gs quant compatibility 0545 gs_quant/test/markets/test_instrument.py test_nested_leg_from_dict', gs_test_test_nested_leg_from_dict().canonical, 'fin_gsq_test_test_nested_leg_from_dict');
SELECT assert_eq('gs quant compatibility 0546 gs_quant/test/markets/test_portfolio.py set_session', gs_test_set_session_test_markets_test_portfolio().canonical, 'fin_gsq_test_set_session_test_markets_test_portfolio');
SELECT assert_eq('gs quant compatibility 0547 gs_quant/test/markets/test_portfolio.py test_portfolio', gs_test_test_portfolio().canonical, 'fin_gsq_test_test_portfolio');
SELECT assert_eq('gs quant compatibility 0548 gs_quant/test/markets/test_portfolio.py test_construction', gs_test_test_construction().canonical, 'fin_gsq_test_test_construction');
SELECT assert_eq('gs quant compatibility 0549 gs_quant/test/markets/test_portfolio.py test_historical_pricing', gs_test_test_historical_pricing().canonical, 'fin_gsq_test_test_historical_pricing');
SELECT assert_eq('gs quant compatibility 0550 gs_quant/test/markets/test_portfolio.py test_backtothefuture_pricing', gs_test_test_backtothefuture_pricing().canonical, 'fin_gsq_test_test_backtothefuture_pricing');
SELECT assert_eq('gs quant compatibility 0551 gs_quant/test/markets/test_portfolio.py test_duplicate_instrument', gs_test_test_duplicate_instrument().canonical, 'fin_gsq_test_test_duplicate_instrument');
SELECT assert_eq('gs quant compatibility 0552 gs_quant/test/markets/test_portfolio.py test_nested_portfolios', gs_test_test_nested_portfolios().canonical, 'fin_gsq_test_test_nested_portfolios');
SELECT assert_eq('gs quant compatibility 0553 gs_quant/test/markets/test_portfolio.py test_single_instrument', gs_test_test_single_instrument().canonical, 'fin_gsq_test_test_single_instrument');
SELECT assert_eq('gs quant compatibility 0554 gs_quant/test/markets/test_portfolio.py test_results_with_resolution', gs_test_test_results_with_resolution().canonical, 'fin_gsq_test_test_results_with_resolution');
SELECT assert_eq('gs quant compatibility 0555 gs_quant/test/markets/test_portfolio.py test_portfolio_overrides', gs_test_test_portfolio_overrides().canonical, 'fin_gsq_test_test_portfolio_overrides');
SELECT assert_eq('gs quant compatibility 0556 gs_quant/test/markets/test_portfolio.py test_from_frame', gs_test_test_from_frame().canonical, 'fin_gsq_test_test_from_frame');
SELECT assert_eq('gs quant compatibility 0557 gs_quant/test/markets/test_portfolio.py test_single_instrument_new_mock', gs_test_test_single_instrument_new_mock().canonical, 'fin_gsq_test_test_single_instrument_new_mock');
SELECT assert_eq('gs quant compatibility 0558 gs_quant/test/markets/test_portfolio.py test_get_instruments', gs_test_test_get_instruments().canonical, 'fin_gsq_test_test_get_instruments');
SELECT assert_eq('gs quant compatibility 0559 gs_quant/test/markets/test_portfolio.py test_clone', gs_test_test_clone().canonical, 'fin_gsq_test_test_clone');
SELECT assert_eq('gs quant compatibility 0560 gs_quant/test/markets/test_portfolio_manager.py test_get_reports', gs_test_test_get_reports_test_markets_test_portfolio_manager().canonical, 'fin_gsq_test_test_get_reports_test_markets_test_portfolio_manager');
SELECT assert_eq('gs quant compatibility 0561 gs_quant/test/markets/test_portfolio_manager.py test_get_schedule_dates', gs_test_test_get_schedule_dates().canonical, 'fin_gsq_test_test_get_schedule_dates');
SELECT assert_eq('gs quant compatibility 0562 gs_quant/test/markets/test_portfolio_manager.py test_set_entitlements', gs_test_test_set_entitlements().canonical, 'fin_gsq_test_test_set_entitlements');
SELECT assert_eq('gs quant compatibility 0563 gs_quant/test/markets/test_portfolio_manager.py test_run_reports', gs_test_test_run_reports().canonical, 'fin_gsq_test_test_run_reports');
SELECT assert_eq('gs quant compatibility 0564 gs_quant/test/markets/test_portfolio_manager.py test_batched_schedule_reports', gs_test_test_batched_schedule_reports().canonical, 'fin_gsq_test_test_batched_schedule_reports');
SELECT assert_eq('gs quant compatibility 0565 gs_quant/test/markets/test_portfolio_manager.py test_batched_schedule_reports_wo_dates', gs_test_test_batched_schedule_reports_wo_dates().canonical, 'fin_gsq_test_test_batched_schedule_reports_wo_dates');
SELECT assert_eq('gs quant compatibility 0566 gs_quant/test/markets/test_portfolio_manager.py test_batched_schedule_validations', gs_test_test_batched_schedule_validations().canonical, 'fin_gsq_test_test_batched_schedule_validations');
SELECT assert_eq('gs quant compatibility 0567 gs_quant/test/markets/test_portfolio_manager.py test_esg_summary', gs_test_test_esg_summary().canonical, 'fin_gsq_test_test_esg_summary');
SELECT assert_eq('gs quant compatibility 0568 gs_quant/test/markets/test_portfolio_manager.py test_esg_quintiles', gs_test_test_esg_quintiles().canonical, 'fin_gsq_test_test_esg_quintiles');
SELECT assert_eq('gs quant compatibility 0569 gs_quant/test/markets/test_portfolio_manager.py test_esg_by_sector', gs_test_test_esg_by_sector().canonical, 'fin_gsq_test_test_esg_by_sector');
SELECT assert_eq('gs quant compatibility 0570 gs_quant/test/markets/test_portfolio_manager.py test_esg_by_region', gs_test_test_esg_by_region().canonical, 'fin_gsq_test_test_esg_by_region');
SELECT assert_eq('gs quant compatibility 0571 gs_quant/test/markets/test_portfolio_manager.py test_esg_top_ten', gs_test_test_esg_top_ten().canonical, 'fin_gsq_test_test_esg_top_ten');
SELECT assert_eq('gs quant compatibility 0572 gs_quant/test/markets/test_portfolio_manager.py test_esg_bottom_ten', gs_test_test_esg_bottom_ten().canonical, 'fin_gsq_test_test_esg_bottom_ten');
SELECT assert_eq('gs quant compatibility 0573 gs_quant/test/markets/test_portfolio_manager.py test_carbon_coverage', gs_test_test_carbon_coverage().canonical, 'fin_gsq_test_test_carbon_coverage');
SELECT assert_eq('gs quant compatibility 0574 gs_quant/test/markets/test_portfolio_manager.py test_carbon_sbti_netzero_coverage', gs_test_test_carbon_sbti_netzero_coverage().canonical, 'fin_gsq_test_test_carbon_sbti_netzero_coverage');
SELECT assert_eq('gs quant compatibility 0575 gs_quant/test/markets/test_portfolio_manager.py test_carbon_emissions', gs_test_test_carbon_emissions().canonical, 'fin_gsq_test_test_carbon_emissions');
SELECT assert_eq('gs quant compatibility 0576 gs_quant/test/markets/test_portfolio_manager.py test_carbon_emissions_allocation', gs_test_test_carbon_emissions_allocation().canonical, 'fin_gsq_test_test_carbon_emissions_allocation');
SELECT assert_eq('gs quant compatibility 0577 gs_quant/test/markets/test_portfolio_manager.py test_carbon_attribution_table', gs_test_test_carbon_attribution_table().canonical, 'fin_gsq_test_test_carbon_attribution_table');
SELECT assert_eq('gs quant compatibility 0578 gs_quant/test/markets/test_portfolio_manager.py test_get_macro_exposure', gs_test_test_get_macro_exposure().canonical, 'fin_gsq_test_test_get_macro_exposure');
SELECT assert_eq('gs quant compatibility 0579 gs_quant/test/markets/test_portfolio_manager.py test_get_factor_scenario_analytics', gs_test_test_get_factor_scenario_analytics().canonical, 'fin_gsq_test_test_get_factor_scenario_analytics');
SELECT assert_eq('gs quant compatibility 0580 gs_quant/test/markets/test_position_set.py test_position_resolve_many', gs_test_test_position_resolve_many().canonical, 'fin_gsq_test_test_position_resolve_many');
SELECT assert_eq('gs quant compatibility 0581 gs_quant/test/markets/test_position_set.py position_sets_with_tags_and_notional', gs_test_position_sets_with_tags_and_notional().canonical, 'fin_gsq_test_position_sets_with_tags_and_notional');
SELECT assert_eq('gs quant compatibility 0582 gs_quant/test/markets/test_position_set.py expected_position_pricing_result', gs_test_expected_position_pricing_result().canonical, 'fin_gsq_test_expected_position_pricing_result');
SELECT assert_eq('gs quant compatibility 0583 gs_quant/test/markets/test_position_set.py test_position_price_many', gs_test_test_position_price_many().canonical, 'fin_gsq_test_test_position_price_many');
SELECT assert_eq('gs quant compatibility 0584 gs_quant/test/markets/test_pricing_context.py test_pricing_context', gs_test_test_pricing_context().canonical, 'fin_gsq_test_test_pricing_context');
SELECT assert_eq('gs quant compatibility 0585 gs_quant/test/markets/test_pricing_context.py test_pricing_dates', gs_test_test_pricing_dates().canonical, 'fin_gsq_test_test_pricing_dates');
SELECT assert_eq('gs quant compatibility 0586 gs_quant/test/markets/test_pricing_context.py test_weekend_dates', gs_test_test_weekend_dates().canonical, 'fin_gsq_test_test_weekend_dates');
SELECT assert_eq('gs quant compatibility 0587 gs_quant/test/markets/test_pricing_context.py test_market_data_object', gs_test_test_market_data_object().canonical, 'fin_gsq_test_test_market_data_object');
SELECT assert_eq('gs quant compatibility 0588 gs_quant/test/markets/test_pricing_context.py test_pricing_context_metadata', gs_test_test_pricing_context_metadata().canonical, 'fin_gsq_test_test_pricing_context_metadata');
SELECT assert_eq('gs quant compatibility 0589 gs_quant/test/markets/test_pricing_context.py test_creation', gs_test_test_creation().canonical, 'fin_gsq_test_test_creation');
SELECT assert_eq('gs quant compatibility 0590 gs_quant/test/markets/test_pricing_context.py test_inheritance', gs_test_test_inheritance().canonical, 'fin_gsq_test_test_inheritance');
SELECT assert_eq('gs quant compatibility 0591 gs_quant/test/markets/test_pricing_context.py test_max_concurrent', gs_test_test_max_concurrent().canonical, 'fin_gsq_test_test_max_concurrent');
SELECT assert_eq('gs quant compatibility 0592 gs_quant/test/markets/test_pricing_context.py test_dates_per_batch', gs_test_test_dates_per_batch().canonical, 'fin_gsq_test_test_dates_per_batch');
SELECT assert_eq('gs quant compatibility 0593 gs_quant/test/markets/test_pricing_context.py test_current_inheritance', gs_test_test_current_inheritance().canonical, 'fin_gsq_test_test_current_inheritance');
SELECT assert_eq('gs quant compatibility 0594 gs_quant/test/markets/test_pricing_context.py test_cleanup', gs_test_test_cleanup().canonical, 'fin_gsq_test_test_cleanup');
SELECT assert_eq('gs quant compatibility 0595 gs_quant/test/markets/test_pricing_context.py test_market_props', gs_test_test_market_props().canonical, 'fin_gsq_test_test_market_props');
SELECT assert_eq('gs quant compatibility 0596 gs_quant/test/markets/test_pricing_context.py test_pricing_does_not_affect_context', gs_test_test_pricing_does_not_affect_context().canonical, 'fin_gsq_test_test_pricing_does_not_affect_context');
SELECT assert_eq('gs quant compatibility 0597 gs_quant/test/markets/test_pricing_context.py test_different_nested_locations', gs_test_test_different_nested_locations().canonical, 'fin_gsq_test_test_different_nested_locations');
SELECT assert_eq('gs quant compatibility 0598 gs_quant/test/markets/test_pricing_context.py test_async_behaviour', gs_test_test_async_behaviour().canonical, 'fin_gsq_test_test_async_behaviour');
SELECT assert_eq('gs quant compatibility 0599 gs_quant/test/markets/test_pricing_context.py test_use_context_for_inheritance', gs_test_test_use_context_for_inheritance().canonical, 'fin_gsq_test_test_use_context_for_inheritance');
SELECT assert_eq('gs quant compatibility 0600 gs_quant/test/markets/test_pricing_context.py test_provider', gs_test_test_provider().canonical, 'fin_gsq_test_test_provider');
SELECT assert_eq('gs quant compatibility 0601 gs_quant/test/markets/test_report.py test_get_performance_report', gs_test_test_get_performance_report().canonical, 'fin_gsq_test_test_get_performance_report');
SELECT assert_eq('gs quant compatibility 0602 gs_quant/test/markets/test_report.py test_get_aum_source', gs_test_test_get_aum_source().canonical, 'fin_gsq_test_test_get_aum_source');
SELECT assert_eq('gs quant compatibility 0603 gs_quant/test/markets/test_report.py test_get_custom_aum', gs_test_test_get_custom_aum().canonical, 'fin_gsq_test_test_get_custom_aum');
SELECT assert_eq('gs quant compatibility 0604 gs_quant/test/markets/test_report.py test_get_aum', gs_test_test_get_aum().canonical, 'fin_gsq_test_test_get_aum');
SELECT assert_eq('gs quant compatibility 0605 gs_quant/test/markets/test_report.py test_get_risk_model_id', gs_test_test_get_risk_model_id().canonical, 'fin_gsq_test_test_get_risk_model_id');
SELECT assert_eq('gs quant compatibility 0606 gs_quant/test/markets/test_report.py test_set_position_target', gs_test_test_set_position_target().canonical, 'fin_gsq_test_test_set_position_target');
SELECT assert_eq('gs quant compatibility 0607 gs_quant/test/markets/test_report.py test_get_factor_risk_report', gs_test_test_get_factor_risk_report().canonical, 'fin_gsq_test_test_get_factor_risk_report');
SELECT assert_eq('gs quant compatibility 0608 gs_quant/test/markets/test_report.py test_get_factor_pnl', gs_test_test_get_factor_pnl().canonical, 'fin_gsq_test_test_get_factor_pnl');
SELECT assert_eq('gs quant compatibility 0609 gs_quant/test/markets/test_report.py test_get_factor_proportion_of_risk', gs_test_test_get_factor_proportion_of_risk().canonical, 'fin_gsq_test_test_get_factor_proportion_of_risk');
SELECT assert_eq('gs quant compatibility 0610 gs_quant/test/markets/test_report.py test_get_factor_exposure', gs_test_test_get_factor_exposure().canonical, 'fin_gsq_test_test_get_factor_exposure');
SELECT assert_eq('gs quant compatibility 0611 gs_quant/test/markets/test_report.py test_get_annual_risk', gs_test_test_get_annual_risk().canonical, 'fin_gsq_test_test_get_annual_risk');
SELECT assert_eq('gs quant compatibility 0612 gs_quant/test/markets/test_report.py test_get_daily_risk', gs_test_test_get_daily_risk().canonical, 'fin_gsq_test_test_get_daily_risk');
SELECT assert_eq('gs quant compatibility 0613 gs_quant/test/markets/test_report.py test_get_measures', gs_test_test_get_measures().canonical, 'fin_gsq_test_test_get_measures');
SELECT assert_eq('gs quant compatibility 0614 gs_quant/test/markets/test_report.py test_flatten_results_into_df', gs_test_test_flatten_results_into_df().canonical, 'fin_gsq_test_test_flatten_results_into_df');
SELECT assert_eq('gs quant compatibility 0615 gs_quant/test/markets/test_report.py test_get_thematic_breakdown', gs_test_test_get_thematic_breakdown().canonical, 'fin_gsq_test_test_get_thematic_breakdown');
SELECT assert_eq('gs quant compatibility 0616 gs_quant/test/markets/test_scenarios.py mock_factor_scenario', gs_test_mock_factor_scenario().canonical, 'fin_gsq_test_mock_factor_scenario');
SELECT assert_eq('gs quant compatibility 0617 gs_quant/test/markets/test_scenarios.py test_create_factor_scenario', gs_test_test_create_factor_scenario().canonical, 'fin_gsq_test_test_create_factor_scenario');
SELECT assert_eq('gs quant compatibility 0618 gs_quant/test/markets/test_scenarios.py test_update_scenario_entitlements', gs_test_test_update_scenario_entitlements().canonical, 'fin_gsq_test_test_update_scenario_entitlements');
SELECT assert_eq('gs quant compatibility 0619 gs_quant/test/markets/test_securities.py test_get_asset', gs_test_test_get_asset_test_markets_test_securities().canonical, 'fin_gsq_test_test_get_asset_test_markets_test_securities');
SELECT assert_eq('gs quant compatibility 0620 gs_quant/test/markets/test_securities.py test_asset_identifiers', gs_test_test_asset_identifiers().canonical, 'fin_gsq_test_test_asset_identifiers');
SELECT assert_eq('gs quant compatibility 0621 gs_quant/test/markets/test_securities.py test_asset_types', gs_test_test_asset_types().canonical, 'fin_gsq_test_test_asset_types');
SELECT assert_eq('gs quant compatibility 0622 gs_quant/test/markets/test_securities.py test_get_security', gs_test_test_get_security().canonical, 'fin_gsq_test_test_get_security');
SELECT assert_eq('gs quant compatibility 0623 gs_quant/test/markets/test_securities.py test_get_security_fields', gs_test_test_get_security_fields().canonical, 'fin_gsq_test_test_get_security_fields');
SELECT assert_eq('gs quant compatibility 0624 gs_quant/test/markets/test_securities.py test_get_identifiers', gs_test_test_get_identifiers().canonical, 'fin_gsq_test_test_get_identifiers');
SELECT assert_eq('gs quant compatibility 0625 gs_quant/test/markets/test_securities.py test_get_all_identifiers', gs_test_test_get_all_identifiers().canonical, 'fin_gsq_test_test_get_all_identifiers');
SELECT assert_eq('gs quant compatibility 0626 gs_quant/test/markets/test_securities.py test_get_all_identifiers_with_assetTypes_not_none', gs_test_test_get_all_identifiers_with_assettypes_not_none().canonical, 'fin_gsq_test_test_get_all_identifiers_with_assettypes_not_none');
SELECT assert_eq('gs quant compatibility 0627 gs_quant/test/markets/test_securities.py test_offset_key', gs_test_test_offset_key().canonical, 'fin_gsq_test_test_offset_key');
SELECT assert_eq('gs quant compatibility 0628 gs_quant/test/markets/test_securities.py test_map_identifiers', gs_test_test_map_identifiers().canonical, 'fin_gsq_test_test_map_identifiers');
SELECT assert_eq('gs quant compatibility 0629 gs_quant/test/markets/test_securities.py test_map_identifiers_change', gs_test_test_map_identifiers_change().canonical, 'fin_gsq_test_test_map_identifiers_change');
SELECT assert_eq('gs quant compatibility 0630 gs_quant/test/markets/test_securities.py test_map_identifiers_empty', gs_test_test_map_identifiers_empty().canonical, 'fin_gsq_test_test_map_identifiers_empty');
SELECT assert_eq('gs quant compatibility 0631 gs_quant/test/markets/test_securities.py test_map_identifiers_eq_index', gs_test_test_map_identifiers_eq_index().canonical, 'fin_gsq_test_test_map_identifiers_eq_index');
SELECT assert_eq('gs quant compatibility 0632 gs_quant/test/markets/test_securities.py test_secmaster_map_identifiers_with_passed_input_types', gs_test_test_secmaster_map_identifiers_with_passed_input_types().canonical, 'fin_gsq_test_test_secmaster_map_identifiers_with_passed_input_types');
SELECT assert_eq('gs quant compatibility 0633 gs_quant/test/markets/test_securities.py test_secmaster_map_identifiers_return_array_results', gs_test_test_secmaster_map_identifiers_return_array_results().canonical, 'fin_gsq_test_test_secmaster_map_identifiers_return_array_results');
SELECT assert_eq('gs quant compatibility 0634 gs_quant/test/markets/test_securities.py test_secmaster_get_asset_no_asset_id_response_should_fail', gs_test_test_secmaster_get_asset_no_asset_id_response_should_fail().canonical, 'fin_gsq_test_test_secmaster_get_asset_no_asset_id_response_should_fail');
SELECT assert_eq('gs quant compatibility 0635 gs_quant/test/markets/test_securities.py test_secmaster_get_asset_returning_secmasterassets', gs_test_test_secmaster_get_asset_returning_secmasterassets().canonical, 'fin_gsq_test_test_secmaster_get_asset_returning_secmasterassets');
SELECT assert_eq('gs quant compatibility 0636 gs_quant/test/markets/test_securities.py test_get_asset_get_data_series_with_range_over_many_asset_id_should_throw_mqerror', gs_test_test_get_asset_get_data_series_with_range_over_many_asset_id_43ceec32f7().canonical, 'fin_gsq_test_test_get_asset_get_data_series_with_range_over_many_asset_id_43ceec32f7');
SELECT assert_eq('gs quant compatibility 0637 gs_quant/test/markets/test_securities.py test_map_identifiers_asset_service', gs_test_test_map_identifiers_asset_service().canonical, 'fin_gsq_test_test_map_identifiers_asset_service');
SELECT assert_eq('gs quant compatibility 0638 gs_quant/test/markets/test_securities.py test_map_identifiers_asset_service_exceptions', gs_test_test_map_identifiers_asset_service_exceptions().canonical, 'fin_gsq_test_test_map_identifiers_asset_service_exceptions');
SELECT assert_eq('gs quant compatibility 0639 gs_quant/test/mock_data_test_utils.py did_anything_fail', gs_test_did_anything_fail().canonical, 'fin_gsq_test_did_anything_fail');
SELECT assert_eq('gs quant compatibility 0640 gs_quant/test/mock_data_test_utils.py did_anything_run', gs_test_did_anything_run().canonical, 'fin_gsq_test_did_anything_run');
SELECT assert_eq('gs quant compatibility 0641 gs_quant/test/mock_data_test_utils.py log_mock_data_event', gs_test_log_mock_data_event().canonical, 'fin_gsq_test_log_mock_data_event');
SELECT assert_eq('gs quant compatibility 0642 gs_quant/test/mock_data_test_utils.py pytest_addoption', gs_test_pytest_addoption().canonical, 'fin_gsq_test_pytest_addoption');
SELECT assert_eq('gs quant compatibility 0643 gs_quant/test/mock_data_test_utils.py pytest_configure', gs_test_pytest_configure().canonical, 'fin_gsq_test_pytest_configure');
SELECT assert_eq('gs quant compatibility 0644 gs_quant/test/mock_data_test_utils.py pytest_runtest_makereport', gs_test_pytest_runtest_makereport().canonical, 'fin_gsq_test_pytest_runtest_makereport');
SELECT assert_eq('gs quant compatibility 0645 gs_quant/test/mock_data_test_utils.py pytest_terminal_summary', gs_test_pytest_terminal_summary().canonical, 'fin_gsq_test_pytest_terminal_summary');
SELECT assert_eq('gs quant compatibility 0646 gs_quant/test/mock_data_test_utils.py pytest_collection_modifyitems', gs_test_pytest_collection_modifyitems().canonical, 'fin_gsq_test_pytest_collection_modifyitems');
SELECT assert_eq('gs quant compatibility 0647 gs_quant/test/models/test_epidemiology.py test_SIR', gs_test_test_sir().canonical, 'fin_gsq_test_test_sir');
SELECT assert_eq('gs quant compatibility 0648 gs_quant/test/models/test_epidemiology.py test_SEIR', gs_test_test_seir().canonical, 'fin_gsq_test_test_seir');
SELECT assert_eq('gs quant compatibility 0649 gs_quant/test/models/test_risk_model.py mock_risk_model', gs_test_mock_risk_model().canonical, 'fin_gsq_test_mock_risk_model');
SELECT assert_eq('gs quant compatibility 0650 gs_quant/test/models/test_risk_model.py mock_macro_risk_model', gs_test_mock_macro_risk_model().canonical, 'fin_gsq_test_mock_macro_risk_model');
SELECT assert_eq('gs quant compatibility 0651 gs_quant/test/models/test_risk_model.py test_create_risk_model', gs_test_test_create_risk_model_test_models_test_risk_model().canonical, 'fin_gsq_test_test_create_risk_model_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0652 gs_quant/test/models/test_risk_model.py test_update_risk_model_entitlements', gs_test_test_update_risk_model_entitlements().canonical, 'fin_gsq_test_test_update_risk_model_entitlements');
SELECT assert_eq('gs quant compatibility 0653 gs_quant/test/models/test_risk_model.py test_update_risk_model', gs_test_test_update_risk_model_test_models_test_risk_model().canonical, 'fin_gsq_test_test_update_risk_model_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0654 gs_quant/test/models/test_risk_model.py test_get_r_squared', gs_test_test_get_r_squared_test_models_test_risk_model().canonical, 'fin_gsq_test_test_get_r_squared_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0655 gs_quant/test/models/test_risk_model.py test_get_fair_value_gap_standard_deviation', gs_test_test_get_fair_value_gap_standard_deviation().canonical, 'fin_gsq_test_test_get_fair_value_gap_standard_deviation');
SELECT assert_eq('gs quant compatibility 0656 gs_quant/test/models/test_risk_model.py test_get_fair_value_gap_percent', gs_test_test_get_fair_value_gap_percent().canonical, 'fin_gsq_test_test_get_fair_value_gap_percent');
SELECT assert_eq('gs quant compatibility 0657 gs_quant/test/models/test_risk_model.py test_get_statistical_factor_data', gs_test_test_get_statistical_factor_data().canonical, 'fin_gsq_test_test_get_statistical_factor_data');
SELECT assert_eq('gs quant compatibility 0658 gs_quant/test/models/test_risk_model.py test_get_factor_z_score', gs_test_test_get_factor_z_score_test_models_test_risk_model().canonical, 'fin_gsq_test_test_get_factor_z_score_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0659 gs_quant/test/models/test_risk_model.py test_get_predicted_beta', gs_test_test_get_predicted_beta_test_models_test_risk_model().canonical, 'fin_gsq_test_test_get_predicted_beta_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0660 gs_quant/test/models/test_risk_model.py test_get_global_predicted_beta', gs_test_test_get_global_predicted_beta_test_models_test_risk_model().canonical, 'fin_gsq_test_test_get_global_predicted_beta_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0661 gs_quant/test/models/test_risk_model.py test_get_estimation_universe_weights', gs_test_test_get_estimation_universe_weights().canonical, 'fin_gsq_test_test_get_estimation_universe_weights');
SELECT assert_eq('gs quant compatibility 0662 gs_quant/test/models/test_risk_model.py test_get_daily_return', gs_test_test_get_daily_return_test_models_test_risk_model().canonical, 'fin_gsq_test_test_get_daily_return_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0663 gs_quant/test/models/test_risk_model.py test_get_specific_return', gs_test_test_get_specific_return_test_models_test_risk_model().canonical, 'fin_gsq_test_test_get_specific_return_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0664 gs_quant/test/models/test_risk_model.py test_upload_risk_model_data', gs_test_test_upload_risk_model_data_test_models_test_risk_model().canonical, 'fin_gsq_test_test_upload_risk_model_data_test_models_test_risk_model');
SELECT assert_eq('gs quant compatibility 0665 gs_quant/test/models/test_risk_model.py test_get_bid_ask_spread', gs_test_test_get_bid_ask_spread().canonical, 'fin_gsq_test_test_get_bid_ask_spread');
SELECT assert_eq('gs quant compatibility 0666 gs_quant/test/models/test_risk_model.py test_get_trading_volume', gs_test_test_get_trading_volume().canonical, 'fin_gsq_test_test_get_trading_volume');
SELECT assert_eq('gs quant compatibility 0667 gs_quant/test/models/test_risk_model.py test_get_traded_value', gs_test_test_get_traded_value().canonical, 'fin_gsq_test_test_get_traded_value');
SELECT assert_eq('gs quant compatibility 0668 gs_quant/test/models/test_risk_model.py test_get_composite_volume', gs_test_test_get_composite_volume().canonical, 'fin_gsq_test_test_get_composite_volume');
SELECT assert_eq('gs quant compatibility 0669 gs_quant/test/models/test_risk_model.py test_get_composite_value', gs_test_test_get_composite_value().canonical, 'fin_gsq_test_test_get_composite_value');
SELECT assert_eq('gs quant compatibility 0670 gs_quant/test/models/test_risk_model.py test_get_issuer_market_cap', gs_test_test_get_issuer_market_cap().canonical, 'fin_gsq_test_test_get_issuer_market_cap');
SELECT assert_eq('gs quant compatibility 0671 gs_quant/test/models/test_risk_model.py test_get_asset_price', gs_test_test_get_asset_price().canonical, 'fin_gsq_test_test_get_asset_price');
SELECT assert_eq('gs quant compatibility 0672 gs_quant/test/models/test_risk_model.py test_get_asset_capitalization', gs_test_test_get_asset_capitalization().canonical, 'fin_gsq_test_test_get_asset_capitalization');
SELECT assert_eq('gs quant compatibility 0673 gs_quant/test/models/test_risk_model.py test_get_currency', gs_test_test_get_currency().canonical, 'fin_gsq_test_test_get_currency');
SELECT assert_eq('gs quant compatibility 0674 gs_quant/test/models/test_risk_model.py test_get_unadjusted_specific_risk', gs_test_test_get_unadjusted_specific_risk().canonical, 'fin_gsq_test_test_get_unadjusted_specific_risk');
SELECT assert_eq('gs quant compatibility 0675 gs_quant/test/models/test_risk_model.py test_get_dividend_yield', gs_test_test_get_dividend_yield().canonical, 'fin_gsq_test_test_get_dividend_yield');
SELECT assert_eq('gs quant compatibility 0676 gs_quant/test/models/test_risk_model.py test_get_model_price', gs_test_test_get_model_price().canonical, 'fin_gsq_test_test_get_model_price');
SELECT assert_eq('gs quant compatibility 0677 gs_quant/test/models/test_risk_model.py test_get_covariance_matrix', gs_test_test_get_covariance_matrix().canonical, 'fin_gsq_test_test_get_covariance_matrix');
SELECT assert_eq('gs quant compatibility 0678 gs_quant/test/models/test_risk_model.py test_get_unadjusted_covariance_matrix', gs_test_test_get_unadjusted_covariance_matrix().canonical, 'fin_gsq_test_test_get_unadjusted_covariance_matrix');
SELECT assert_eq('gs quant compatibility 0679 gs_quant/test/models/test_risk_model.py test_get_pre_vra_covariance_matrix', gs_test_test_get_pre_vra_covariance_matrix().canonical, 'fin_gsq_test_test_get_pre_vra_covariance_matrix');
SELECT assert_eq('gs quant compatibility 0680 gs_quant/test/models/test_risk_model.py test_get_risk_free_rate', gs_test_test_get_risk_free_rate().canonical, 'fin_gsq_test_test_get_risk_free_rate');
SELECT assert_eq('gs quant compatibility 0681 gs_quant/test/models/test_risk_model.py test_get_currency_exchange_rate', gs_test_test_get_currency_exchange_rate().canonical, 'fin_gsq_test_test_get_currency_exchange_rate');
SELECT assert_eq('gs quant compatibility 0682 gs_quant/test/models/test_risk_model_utils.py test__upload_factor_data_if_present', gs_test_test_upload_factor_data_if_present().canonical, 'fin_gsq_test_test_upload_factor_data_if_present');
SELECT assert_eq('gs quant compatibility 0683 gs_quant/test/risk/test_measures.py test_currency_params', gs_test_test_currency_params().canonical, 'fin_gsq_test_test_currency_params');
SELECT assert_eq('gs quant compatibility 0684 gs_quant/test/risk/test_measures.py test_finite_difference_params', gs_test_test_finite_difference_params().canonical, 'fin_gsq_test_test_finite_difference_params');
SELECT assert_eq('gs quant compatibility 0685 gs_quant/test/risk/test_measures.py test_risk_measure_setters', gs_test_test_risk_measure_setters().canonical, 'fin_gsq_test_test_risk_measure_setters');
SELECT assert_eq('gs quant compatibility 0686 gs_quant/test/risk/test_results.py get_attributes', gs_test_get_attributes().canonical, 'fin_gsq_test_get_attributes');
SELECT assert_eq('gs quant compatibility 0687 gs_quant/test/risk/test_results.py default_pivot_table_test', gs_test_default_pivot_table_test().canonical, 'fin_gsq_test_default_pivot_table_test');
SELECT assert_eq('gs quant compatibility 0688 gs_quant/test/risk/test_results.py price_values_test', gs_test_price_values_test().canonical, 'fin_gsq_test_price_values_test');
SELECT assert_eq('gs quant compatibility 0689 gs_quant/test/risk/test_results.py test_multi_scenario', gs_test_test_multi_scenario().canonical, 'fin_gsq_test_test_multi_scenario');
SELECT assert_eq('gs quant compatibility 0690 gs_quant/test/risk/test_results.py test_historical_multi_scenario', gs_test_test_historical_multi_scenario().canonical, 'fin_gsq_test_test_historical_multi_scenario');
SELECT assert_eq('gs quant compatibility 0691 gs_quant/test/risk/test_results.py test_series_with_info_arithmetics', gs_test_test_series_with_info_arithmetics().canonical, 'fin_gsq_test_test_series_with_info_arithmetics');
SELECT assert_eq('gs quant compatibility 0692 gs_quant/test/risk/test_results.py test_composite_multi_scenario', gs_test_test_composite_multi_scenario().canonical, 'fin_gsq_test_test_composite_multi_scenario');
SELECT assert_eq('gs quant compatibility 0693 gs_quant/test/risk/test_results.py test_one_portfolio', gs_test_test_one_portfolio().canonical, 'fin_gsq_test_test_one_portfolio');
SELECT assert_eq('gs quant compatibility 0694 gs_quant/test/risk/test_results.py test_dated_risk_values', gs_test_test_dated_risk_values().canonical, 'fin_gsq_test_test_dated_risk_values');
SELECT assert_eq('gs quant compatibility 0695 gs_quant/test/risk/test_results.py test_bucketed_risks', gs_test_test_bucketed_risks().canonical, 'fin_gsq_test_test_bucketed_risks');
SELECT assert_eq('gs quant compatibility 0696 gs_quant/test/risk/test_results.py test_cashflows_risk', gs_test_test_cashflows_risk().canonical, 'fin_gsq_test_test_cashflows_risk');
SELECT assert_eq('gs quant compatibility 0697 gs_quant/test/risk/test_results.py test_nested_portfolio', gs_test_test_nested_portfolio().canonical, 'fin_gsq_test_test_nested_portfolio');
SELECT assert_eq('gs quant compatibility 0698 gs_quant/test/risk/test_results.py test_diff_types_risk_measures', gs_test_test_diff_types_risk_measures().canonical, 'fin_gsq_test_test_diff_types_risk_measures');
SELECT assert_eq('gs quant compatibility 0699 gs_quant/test/risk/test_results.py test_empty_calc_request', gs_test_test_empty_calc_request().canonical, 'fin_gsq_test_test_empty_calc_request');
SELECT assert_eq('gs quant compatibility 0700 gs_quant/test/risk/test_results.py test_adding_risk_results', gs_test_test_adding_risk_results().canonical, 'fin_gsq_test_test_adding_risk_results');
SELECT assert_eq('gs quant compatibility 0701 gs_quant/test/risk/test_results.py test_unsupported_error_datums', gs_test_test_unsupported_error_datums().canonical, 'fin_gsq_test_test_unsupported_error_datums');
SELECT assert_eq('gs quant compatibility 0702 gs_quant/test/risk/test_results.py test_resolution_of_error_trade', gs_test_test_resolution_of_error_trade().canonical, 'fin_gsq_test_test_resolution_of_error_trade');
SELECT assert_eq('gs quant compatibility 0703 gs_quant/test/risk/test_results.py test_resolve_to_frame', gs_test_test_resolve_to_frame().canonical, 'fin_gsq_test_test_resolve_to_frame');
SELECT assert_eq('gs quant compatibility 0704 gs_quant/test/risk/test_results.py test_unnamed_portfolio', gs_test_test_unnamed_portfolio().canonical, 'fin_gsq_test_test_unnamed_portfolio');
SELECT assert_eq('gs quant compatibility 0705 gs_quant/test/risk/test_results.py test_leg_valuations', gs_test_test_leg_valuations().canonical, 'fin_gsq_test_test_leg_valuations');
SELECT assert_eq('gs quant compatibility 0706 gs_quant/test/risk/test_results.py test_aggregation_with_heterogeous_types', gs_test_test_aggregation_with_heterogeous_types().canonical, 'fin_gsq_test_test_aggregation_with_heterogeous_types');
SELECT assert_eq('gs quant compatibility 0707 gs_quant/test/risk/test_results.py test_aggregation_with_empty_measures', gs_test_test_aggregation_with_empty_measures().canonical, 'fin_gsq_test_test_aggregation_with_empty_measures');
SELECT assert_eq('gs quant compatibility 0708 gs_quant/test/risk/test_results.py test_filter_risk', gs_test_test_filter_risk().canonical, 'fin_gsq_test_test_filter_risk');
SELECT assert_eq('gs quant compatibility 0709 gs_quant/test/risk/test_results.py test_transformation', gs_test_test_transformation().canonical, 'fin_gsq_test_test_transformation');
SELECT assert_eq('gs quant compatibility 0710 gs_quant/test/risk/test_results.py test_aggregation_with_identical_trades', gs_test_test_aggregation_with_identical_trades().canonical, 'fin_gsq_test_test_aggregation_with_identical_trades');
SELECT assert_eq('gs quant compatibility 0711 gs_quant/test/risk/test_results.py test_scalar_with_info_on_instrument', gs_test_test_scalar_with_info_on_instrument().canonical, 'fin_gsq_test_test_scalar_with_info_on_instrument');
SELECT assert_eq('gs quant compatibility 0712 gs_quant/test/risk/test_results.py test_display_unit', gs_test_test_display_unit().canonical, 'fin_gsq_test_test_display_unit');
SELECT assert_eq('gs quant compatibility 0713 gs_quant/test/test_base.py test_handle_camel_case_args', gs_test_test_handle_camel_case_args().canonical, 'fin_gsq_test_test_handle_camel_case_args');
SELECT assert_eq('gs quant compatibility 0714 gs_quant/test/test_base.py test_base_getter', gs_test_test_base_getter().canonical, 'fin_gsq_test_test_base_getter');
SELECT assert_eq('gs quant compatibility 0715 gs_quant/test/test_base.py test_base_setter', gs_test_test_base_setter().canonical, 'fin_gsq_test_test_base_setter');
SELECT assert_eq('gs quant compatibility 0716 gs_quant/test/test_base.py test_setter_coercion', gs_test_test_setter_coercion().canonical, 'fin_gsq_test_test_setter_coercion');
SELECT assert_eq('gs quant compatibility 0717 gs_quant/test/test_base.py test_security_from_dict', gs_test_test_security_from_dict().canonical, 'fin_gsq_test_test_security_from_dict');
SELECT assert_eq('gs quant compatibility 0718 gs_quant/test/test_session.py test_session_pickle', gs_test_test_session_pickle().canonical, 'fin_gsq_test_test_session_pickle');
SELECT assert_eq('gs quant compatibility 0719 gs_quant/test/timeseries/multi_measure/test_commod.py test_forward_price', gs_test_test_forward_price().canonical, 'fin_gsq_test_test_forward_price');
SELECT assert_eq('gs quant compatibility 0720 gs_quant/test/timeseries/multi_measure/test_measure_registry.py test_registry', gs_test_test_registry().canonical, 'fin_gsq_test_test_registry');
SELECT assert_eq('gs quant compatibility 0721 gs_quant/test/timeseries/multi_measure/test_measure_registry.py test_no_duplicate_plot_measure_function_names', gs_test_test_no_duplicate_plot_measure_function_names().canonical, 'fin_gsq_test_test_no_duplicate_plot_measure_function_names');
SELECT assert_eq('gs quant compatibility 0722 gs_quant/test/timeseries/test_algebra.py test_add', gs_test_test_add().canonical, 'fin_gsq_test_test_add');
SELECT assert_eq('gs quant compatibility 0723 gs_quant/test/timeseries/test_algebra.py test_subtract', gs_test_test_subtract().canonical, 'fin_gsq_test_test_subtract');
SELECT assert_eq('gs quant compatibility 0724 gs_quant/test/timeseries/test_algebra.py test_multiply', gs_test_test_multiply().canonical, 'fin_gsq_test_test_multiply');
SELECT assert_eq('gs quant compatibility 0725 gs_quant/test/timeseries/test_algebra.py test_divide', gs_test_test_divide().canonical, 'fin_gsq_test_test_divide');
SELECT assert_eq('gs quant compatibility 0726 gs_quant/test/timeseries/test_algebra.py test_floordiv', gs_test_test_floordiv().canonical, 'fin_gsq_test_test_floordiv');
SELECT assert_eq('gs quant compatibility 0727 gs_quant/test/timeseries/test_algebra.py test_exp', gs_test_test_exp().canonical, 'fin_gsq_test_test_exp');
SELECT assert_eq('gs quant compatibility 0728 gs_quant/test/timeseries/test_algebra.py test_log', gs_test_test_log().canonical, 'fin_gsq_test_test_log');
SELECT assert_eq('gs quant compatibility 0729 gs_quant/test/timeseries/test_algebra.py test_power', gs_test_test_power().canonical, 'fin_gsq_test_test_power');
SELECT assert_eq('gs quant compatibility 0730 gs_quant/test/timeseries/test_algebra.py test_sqrt', gs_test_test_sqrt().canonical, 'fin_gsq_test_test_sqrt');
SELECT assert_eq('gs quant compatibility 0731 gs_quant/test/timeseries/test_algebra.py test_abs', gs_test_test_abs().canonical, 'fin_gsq_test_test_abs');
SELECT assert_eq('gs quant compatibility 0732 gs_quant/test/timeseries/test_algebra.py test_floor', gs_test_test_floor().canonical, 'fin_gsq_test_test_floor');
SELECT assert_eq('gs quant compatibility 0733 gs_quant/test/timeseries/test_algebra.py test_ceil', gs_test_test_ceil().canonical, 'fin_gsq_test_test_ceil');
SELECT assert_eq('gs quant compatibility 0734 gs_quant/test/timeseries/test_algebra.py test_filter', gs_test_test_filter().canonical, 'fin_gsq_test_test_filter');
SELECT assert_eq('gs quant compatibility 0735 gs_quant/test/timeseries/test_algebra.py test_filter_dates', gs_test_test_filter_dates().canonical, 'fin_gsq_test_test_filter_dates');
SELECT assert_eq('gs quant compatibility 0736 gs_quant/test/timeseries/test_algebra.py test_smooth_spikes', gs_test_test_smooth_spikes().canonical, 'fin_gsq_test_test_smooth_spikes');
SELECT assert_eq('gs quant compatibility 0737 gs_quant/test/timeseries/test_algebra.py test_repeat', gs_test_test_repeat().canonical, 'fin_gsq_test_test_repeat');
SELECT assert_eq('gs quant compatibility 0738 gs_quant/test/timeseries/test_algebra.py test_and', gs_test_test_and().canonical, 'fin_gsq_test_test_and');
SELECT assert_eq('gs quant compatibility 0739 gs_quant/test/timeseries/test_algebra.py test_or', gs_test_test_or().canonical, 'fin_gsq_test_test_or');
SELECT assert_eq('gs quant compatibility 0740 gs_quant/test/timeseries/test_algebra.py test_not', gs_test_test_not().canonical, 'fin_gsq_test_test_not');
SELECT assert_eq('gs quant compatibility 0741 gs_quant/test/timeseries/test_algebra.py test_if', gs_test_test_if().canonical, 'fin_gsq_test_test_if');
SELECT assert_eq('gs quant compatibility 0742 gs_quant/test/timeseries/test_algebra.py test_weighted_average', gs_test_test_weighted_average().canonical, 'fin_gsq_test_test_weighted_average');
SELECT assert_eq('gs quant compatibility 0743 gs_quant/test/timeseries/test_algebra.py test_geometrically_aggregate', gs_test_test_geometrically_aggregate().canonical, 'fin_gsq_test_test_geometrically_aggregate');
SELECT assert_eq('gs quant compatibility 0744 gs_quant/test/timeseries/test_analysis.py test_first', gs_test_test_first().canonical, 'fin_gsq_test_test_first');
SELECT assert_eq('gs quant compatibility 0745 gs_quant/test/timeseries/test_analysis.py test_last', gs_test_test_last().canonical, 'fin_gsq_test_test_last');
SELECT assert_eq('gs quant compatibility 0746 gs_quant/test/timeseries/test_analysis.py test_last_value', gs_test_test_last_value().canonical, 'fin_gsq_test_test_last_value');
SELECT assert_eq('gs quant compatibility 0747 gs_quant/test/timeseries/test_analysis.py test_count', gs_test_test_count().canonical, 'fin_gsq_test_test_count');
SELECT assert_eq('gs quant compatibility 0748 gs_quant/test/timeseries/test_analysis.py test_compare', gs_test_test_compare().canonical, 'fin_gsq_test_test_compare');
SELECT assert_eq('gs quant compatibility 0749 gs_quant/test/timeseries/test_analysis.py test_diff', gs_test_test_diff().canonical, 'fin_gsq_test_test_diff');
SELECT assert_eq('gs quant compatibility 0750 gs_quant/test/timeseries/test_analysis.py test_lag', gs_test_test_lag().canonical, 'fin_gsq_test_test_lag');
SELECT assert_eq('gs quant compatibility 0751 gs_quant/test/timeseries/test_analysis.py test_repeat_empty_series', gs_test_test_repeat_empty_series().canonical, 'fin_gsq_test_test_repeat_empty_series');
SELECT assert_eq('gs quant compatibility 0752 gs_quant/test/timeseries/test_analysis.py test_lag_empty_series', gs_test_test_lag_empty_series().canonical, 'fin_gsq_test_test_lag_empty_series');
SELECT assert_eq('gs quant compatibility 0753 gs_quant/test/timeseries/test_analysis.py test_smooth_outliers', gs_test_test_smooth_outliers().canonical, 'fin_gsq_test_test_smooth_outliers');
SELECT assert_eq('gs quant compatibility 0754 gs_quant/test/timeseries/test_analysis.py test_consecutive', gs_test_test_consecutive().canonical, 'fin_gsq_test_test_consecutive');
SELECT assert_eq('gs quant compatibility 0755 gs_quant/test/timeseries/test_backtesting.py test_basket_series', gs_test_test_basket_series().canonical, 'fin_gsq_test_test_basket_series');
SELECT assert_eq('gs quant compatibility 0756 gs_quant/test/timeseries/test_backtesting.py test_basket_price', gs_test_test_basket_price().canonical, 'fin_gsq_test_test_basket_price');
SELECT assert_eq('gs quant compatibility 0757 gs_quant/test/timeseries/test_backtesting.py test_basket_average_implied_vol', gs_test_test_basket_average_implied_vol().canonical, 'fin_gsq_test_test_basket_average_implied_vol');
SELECT assert_eq('gs quant compatibility 0758 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_vol', gs_test_test_basket_average_realized_vol().canonical, 'fin_gsq_test_test_basket_average_realized_vol');
SELECT assert_eq('gs quant compatibility 0759 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_vol_wts', gs_test_test_basket_average_realized_vol_wts().canonical, 'fin_gsq_test_test_basket_average_realized_vol_wts');
SELECT assert_eq('gs quant compatibility 0760 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_vol_intraday', gs_test_test_basket_average_realized_vol_intraday().canonical, 'fin_gsq_test_test_basket_average_realized_vol_intraday');
SELECT assert_eq('gs quant compatibility 0761 gs_quant/test/timeseries/test_backtesting.py test_basket_average_realized_corr', gs_test_test_basket_average_realized_corr().canonical, 'fin_gsq_test_test_basket_average_realized_corr');
SELECT assert_eq('gs quant compatibility 0762 gs_quant/test/timeseries/test_backtesting.py test_basket_without_weights', gs_test_test_basket_without_weights().canonical, 'fin_gsq_test_test_basket_without_weights');
SELECT assert_eq('gs quant compatibility 0763 gs_quant/test/timeseries/test_backtesting.py test_basket_avg_fwd_vol', gs_test_test_basket_avg_fwd_vol().canonical, 'fin_gsq_test_test_basket_avg_fwd_vol');
SELECT assert_eq('gs quant compatibility 0764 gs_quant/test/timeseries/test_datetime.py test_basic', gs_test_test_basic().canonical, 'fin_gsq_test_test_basic');
SELECT assert_eq('gs quant compatibility 0765 gs_quant/test/timeseries/test_datetime.py test_align', gs_test_test_align().canonical, 'fin_gsq_test_test_align');
SELECT assert_eq('gs quant compatibility 0766 gs_quant/test/timeseries/test_datetime.py test_interpolate', gs_test_test_interpolate().canonical, 'fin_gsq_test_test_interpolate');
SELECT assert_eq('gs quant compatibility 0767 gs_quant/test/timeseries/test_datetime.py test_value', gs_test_test_value().canonical, 'fin_gsq_test_test_value');
SELECT assert_eq('gs quant compatibility 0768 gs_quant/test/timeseries/test_datetime.py test_day', gs_test_test_day().canonical, 'fin_gsq_test_test_day');
SELECT assert_eq('gs quant compatibility 0769 gs_quant/test/timeseries/test_datetime.py test_weekday', gs_test_test_weekday().canonical, 'fin_gsq_test_test_weekday');
SELECT assert_eq('gs quant compatibility 0770 gs_quant/test/timeseries/test_datetime.py test_month', gs_test_test_month().canonical, 'fin_gsq_test_test_month');
SELECT assert_eq('gs quant compatibility 0771 gs_quant/test/timeseries/test_datetime.py test_year', gs_test_test_year().canonical, 'fin_gsq_test_test_year');
SELECT assert_eq('gs quant compatibility 0772 gs_quant/test/timeseries/test_datetime.py test_quarter', gs_test_test_quarter().canonical, 'fin_gsq_test_test_quarter');
SELECT assert_eq('gs quant compatibility 0773 gs_quant/test/timeseries/test_datetime.py test_day_count_fractions', gs_test_test_day_count_fractions().canonical, 'fin_gsq_test_test_day_count_fractions');
SELECT assert_eq('gs quant compatibility 0774 gs_quant/test/timeseries/test_datetime.py test_date_range', gs_test_test_date_range().canonical, 'fin_gsq_test_test_date_range');
SELECT assert_eq('gs quant compatibility 0775 gs_quant/test/timeseries/test_datetime.py test_append', gs_test_test_append().canonical, 'fin_gsq_test_test_append');
SELECT assert_eq('gs quant compatibility 0776 gs_quant/test/timeseries/test_datetime.py test_prepend', gs_test_test_prepend().canonical, 'fin_gsq_test_test_prepend');
SELECT assert_eq('gs quant compatibility 0777 gs_quant/test/timeseries/test_datetime.py test_union', gs_test_test_union().canonical, 'fin_gsq_test_test_union');
SELECT assert_eq('gs quant compatibility 0778 gs_quant/test/timeseries/test_datetime.py test_bucketize', gs_test_test_bucketize().canonical, 'fin_gsq_test_test_bucketize');
SELECT assert_eq('gs quant compatibility 0779 gs_quant/test/timeseries/test_datetime.py test_day_count', gs_test_test_day_count().canonical, 'fin_gsq_test_test_day_count');
SELECT assert_eq('gs quant compatibility 0780 gs_quant/test/timeseries/test_datetime.py test_day_countdown', gs_test_test_day_countdown().canonical, 'fin_gsq_test_test_day_countdown');
SELECT assert_eq('gs quant compatibility 0781 gs_quant/test/timeseries/test_datetime.py test_align_calendar', gs_test_test_align_calendar().canonical, 'fin_gsq_test_test_align_calendar');
SELECT assert_eq('gs quant compatibility 0782 gs_quant/test/timeseries/test_datetime.py test_bucketize_empty_series', gs_test_test_bucketize_empty_series().canonical, 'fin_gsq_test_test_bucketize_empty_series');
SELECT assert_eq('gs quant compatibility 0783 gs_quant/test/timeseries/test_econometrics.py test_returns', gs_test_test_returns().canonical, 'fin_gsq_test_test_returns');
SELECT assert_eq('gs quant compatibility 0784 gs_quant/test/timeseries/test_econometrics.py test_prices', gs_test_test_prices().canonical, 'fin_gsq_test_test_prices');
SELECT assert_eq('gs quant compatibility 0785 gs_quant/test/timeseries/test_econometrics.py test_index', gs_test_test_index().canonical, 'fin_gsq_test_test_index');
SELECT assert_eq('gs quant compatibility 0786 gs_quant/test/timeseries/test_econometrics.py test_change', gs_test_test_change().canonical, 'fin_gsq_test_test_change');
SELECT assert_eq('gs quant compatibility 0787 gs_quant/test/timeseries/test_econometrics.py test_annualize', gs_test_test_annualize().canonical, 'fin_gsq_test_test_annualize');
SELECT assert_eq('gs quant compatibility 0788 gs_quant/test/timeseries/test_econometrics.py test_volatility', gs_test_test_volatility().canonical, 'fin_gsq_test_test_volatility');
SELECT assert_eq('gs quant compatibility 0789 gs_quant/test/timeseries/test_econometrics.py test_volatility_assume_zero_mean', gs_test_test_volatility_assume_zero_mean().canonical, 'fin_gsq_test_test_volatility_assume_zero_mean');
SELECT assert_eq('gs quant compatibility 0790 gs_quant/test/timeseries/test_econometrics.py test_volatility_annualization_factor', gs_test_test_volatility_annualization_factor().canonical, 'fin_gsq_test_test_volatility_annualization_factor');
SELECT assert_eq('gs quant compatibility 0791 gs_quant/test/timeseries/test_econometrics.py test_vol_swap_volatility', gs_test_test_vol_swap_volatility().canonical, 'fin_gsq_test_test_vol_swap_volatility');
SELECT assert_eq('gs quant compatibility 0792 gs_quant/test/timeseries/test_econometrics.py test_correlation', gs_test_test_correlation().canonical, 'fin_gsq_test_test_correlation');
SELECT assert_eq('gs quant compatibility 0793 gs_quant/test/timeseries/test_econometrics.py test_correlation_returns', gs_test_test_correlation_returns().canonical, 'fin_gsq_test_test_correlation_returns');
SELECT assert_eq('gs quant compatibility 0794 gs_quant/test/timeseries/test_econometrics.py test_corr_swap_correlation', gs_test_test_corr_swap_correlation().canonical, 'fin_gsq_test_test_corr_swap_correlation');
SELECT assert_eq('gs quant compatibility 0795 gs_quant/test/timeseries/test_econometrics.py test_beta', gs_test_test_beta().canonical, 'fin_gsq_test_test_beta');
SELECT assert_eq('gs quant compatibility 0796 gs_quant/test/timeseries/test_econometrics.py test_max_drawdown', gs_test_test_max_drawdown().canonical, 'fin_gsq_test_test_max_drawdown');
SELECT assert_eq('gs quant compatibility 0797 gs_quant/test/timeseries/test_econometrics.py test_excess_returns', gs_test_test_excess_returns().canonical, 'fin_gsq_test_test_excess_returns');
SELECT assert_eq('gs quant compatibility 0798 gs_quant/test/timeseries/test_econometrics.py test_sharpe_ratio', gs_test_test_sharpe_ratio().canonical, 'fin_gsq_test_test_sharpe_ratio');
SELECT assert_eq('gs quant compatibility 0799 gs_quant/test/timeseries/test_helper.py test_int_enum', gs_test_test_int_enum().canonical, 'fin_gsq_test_test_int_enum');
SELECT assert_eq('gs quant compatibility 0800 gs_quant/test/timeseries/test_helper.py test_tenor_to_month', gs_test_test_tenor_to_month().canonical, 'fin_gsq_test_test_tenor_to_month');
SELECT assert_eq('gs quant compatibility 0801 gs_quant/test/timeseries/test_helper.py test_month_to_tenor', gs_test_test_month_to_tenor().canonical, 'fin_gsq_test_test_month_to_tenor');
SELECT assert_eq('gs quant compatibility 0802 gs_quant/test/timeseries/test_helper.py test_get_dataset_with_many_assets', gs_test_test_get_dataset_with_many_assets().canonical, 'fin_gsq_test_test_get_dataset_with_many_assets');
SELECT assert_eq('gs quant compatibility 0803 gs_quant/test/timeseries/test_helper.py pf', gs_test_pf().canonical, 'fin_gsq_test_pf');
SELECT assert_eq('gs quant compatibility 0804 gs_quant/test/timeseries/test_helper.py pm', gs_test_pm().canonical, 'fin_gsq_test_pm');
SELECT assert_eq('gs quant compatibility 0805 gs_quant/test/timeseries/test_helper.py pmt', gs_test_pmt().canonical, 'fin_gsq_test_pmt');
SELECT assert_eq('gs quant compatibility 0806 gs_quant/test/timeseries/test_helper.py test_decorators', gs_test_test_decorators().canonical, 'fin_gsq_test_test_decorators');
SELECT assert_eq('gs quant compatibility 0807 gs_quant/test/timeseries/test_helper.py test_normalize_window_defaults_window_if_none_passed', gs_test_test_normalize_window_defaults_window_if_none_passed().canonical, 'fin_gsq_test_test_normalize_window_defaults_window_if_none_passed');
SELECT assert_eq('gs quant compatibility 0808 gs_quant/test/timeseries/test_helper.py test_normalize_window_defaults_window_if_passed', gs_test_test_normalize_window_defaults_window_if_passed().canonical, 'fin_gsq_test_test_normalize_window_defaults_window_if_passed');
SELECT assert_eq('gs quant compatibility 0809 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_int', gs_test_test_normalize_window_handles_int().canonical, 'fin_gsq_test_test_normalize_window_handles_int');
SELECT assert_eq('gs quant compatibility 0810 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_window_with_no_ramp', gs_test_test_normalize_window_handles_window_with_no_ramp().canonical, 'fin_gsq_test_test_normalize_window_handles_window_with_no_ramp');
SELECT assert_eq('gs quant compatibility 0811 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_window_with_no_size', gs_test_test_normalize_window_handles_window_with_no_size().canonical, 'fin_gsq_test_test_normalize_window_handles_window_with_no_size');
SELECT assert_eq('gs quant compatibility 0812 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_ramp_greater_than_series_length', gs_test_test_normalize_window_handles_ramp_greater_than_series_length().canonical, 'fin_gsq_test_test_normalize_window_handles_ramp_greater_than_series_length');
SELECT assert_eq('gs quant compatibility 0813 gs_quant/test/timeseries/test_helper.py test_normalize_window_raises_error_on_window_of_size_zero', gs_test_test_normalize_window_raises_error_on_window_of_size_zero().canonical, 'fin_gsq_test_test_normalize_window_raises_error_on_window_of_size_zero');
SELECT assert_eq('gs quant compatibility 0814 gs_quant/test/timeseries/test_helper.py test_normalize_window_handles_ramp_of_size_zero', gs_test_test_normalize_window_handles_ramp_of_size_zero().canonical, 'fin_gsq_test_test_normalize_window_handles_ramp_of_size_zero');
SELECT assert_eq('gs quant compatibility 0815 gs_quant/test/timeseries/test_helper.py test_normalize_window_str', gs_test_test_normalize_window_str().canonical, 'fin_gsq_test_test_normalize_window_str');
SELECT assert_eq('gs quant compatibility 0816 gs_quant/test/timeseries/test_helper.py test_normalize_window_single_str', gs_test_test_normalize_window_single_str().canonical, 'fin_gsq_test_test_normalize_window_single_str');
SELECT assert_eq('gs quant compatibility 0817 gs_quant/test/timeseries/test_helper.py test_apply_ramp', gs_test_test_apply_ramp().canonical, 'fin_gsq_test_test_apply_ramp');
SELECT assert_eq('gs quant compatibility 0818 gs_quant/test/timeseries/test_helper.py test_apply_ramp_with_window_greater_than_series_length', gs_test_test_apply_ramp_with_window_greater_than_series_length().canonical, 'fin_gsq_test_test_apply_ramp_with_window_greater_than_series_length');
SELECT assert_eq('gs quant compatibility 0819 gs_quant/test/timeseries/test_helper.py test_apply_ramp_dateoffset', gs_test_test_apply_ramp_dateoffset().canonical, 'fin_gsq_test_test_apply_ramp_dateoffset');
SELECT assert_eq('gs quant compatibility 0820 gs_quant/test/timeseries/test_helper.py test_apply_ramp_raises_on_edge_cases', gs_test_test_apply_ramp_raises_on_edge_cases().canonical, 'fin_gsq_test_test_apply_ramp_raises_on_edge_cases');
SELECT assert_eq('gs quant compatibility 0821 gs_quant/test/timeseries/test_helper.py test_get_df_with_retries', gs_test_test_get_df_with_retries().canonical, 'fin_gsq_test_test_get_df_with_retries');
SELECT assert_eq('gs quant compatibility 0822 gs_quant/test/timeseries/test_helper.py test_forward_looking', gs_test_test_forward_looking().canonical, 'fin_gsq_test_test_forward_looking');
SELECT assert_eq('gs quant compatibility 0823 gs_quant/test/timeseries/test_helper.py test_get_dataset_data_with_retries', gs_test_test_get_dataset_data_with_retries().canonical, 'fin_gsq_test_test_get_dataset_data_with_retries');
SELECT assert_eq('gs quant compatibility 0824 gs_quant/test/timeseries/test_helper.py test_split_where_conditions', gs_test_test_split_where_conditions().canonical, 'fin_gsq_test_test_split_where_conditions');
SELECT assert_eq('gs quant compatibility 0825 gs_quant/test/timeseries/test_helper.py test_get_dataset_data_with_retries_recursive_split', gs_test_test_get_dataset_data_with_retries_recursive_split().canonical, 'fin_gsq_test_test_get_dataset_data_with_retries_recursive_split');
SELECT assert_eq('gs quant compatibility 0826 gs_quant/test/timeseries/test_measures.py mock_empty_market_data_response', gs_test_mock_empty_market_data_response().canonical, 'fin_gsq_test_mock_empty_market_data_response');
SELECT assert_eq('gs quant compatibility 0827 gs_quant/test/timeseries/test_measures.py map_identifiers_default_mocker', gs_test_map_identifiers_default_mocker().canonical, 'fin_gsq_test_map_identifiers_default_mocker');
SELECT assert_eq('gs quant compatibility 0828 gs_quant/test/timeseries/test_measures.py map_identifiers_ois_mocker', gs_test_map_identifiers_ois_mocker().canonical, 'fin_gsq_test_map_identifiers_ois_mocker');
SELECT assert_eq('gs quant compatibility 0829 gs_quant/test/timeseries/test_measures.py map_identifiers_swap_rate_mocker', gs_test_map_identifiers_swap_rate_mocker().canonical, 'fin_gsq_test_map_identifiers_swap_rate_mocker');
SELECT assert_eq('gs quant compatibility 0830 gs_quant/test/timeseries/test_measures.py map_identifiers_inflation_mocker', gs_test_map_identifiers_inflation_mocker().canonical, 'fin_gsq_test_map_identifiers_inflation_mocker');
SELECT assert_eq('gs quant compatibility 0831 gs_quant/test/timeseries/test_measures.py map_identifiers_cross_basis_mocker', gs_test_map_identifiers_cross_basis_mocker().canonical, 'fin_gsq_test_map_identifiers_cross_basis_mocker');
SELECT assert_eq('gs quant compatibility 0832 gs_quant/test/timeseries/test_measures.py test_currency_to_default_ois_asset', gs_test_test_currency_to_default_ois_asset().canonical, 'fin_gsq_test_test_currency_to_default_ois_asset');
SELECT assert_eq('gs quant compatibility 0833 gs_quant/test/timeseries/test_measures.py test_currency_to_default_benchmark_rate', gs_test_test_currency_to_default_benchmark_rate().canonical, 'fin_gsq_test_test_currency_to_default_benchmark_rate');
SELECT assert_eq('gs quant compatibility 0834 gs_quant/test/timeseries/test_measures.py test_currency_to_default_swap_rate_asset', gs_test_test_currency_to_default_swap_rate_asset().canonical, 'fin_gsq_test_test_currency_to_default_swap_rate_asset');
SELECT assert_eq('gs quant compatibility 0835 gs_quant/test/timeseries/test_measures.py test_currency_to_inflation_benchmark_rate', gs_test_test_currency_to_inflation_benchmark_rate().canonical, 'fin_gsq_test_test_currency_to_inflation_benchmark_rate');
SELECT assert_eq('gs quant compatibility 0836 gs_quant/test/timeseries/test_measures.py test_cross_to_basis', gs_test_test_cross_to_basis().canonical, 'fin_gsq_test_test_cross_to_basis');
SELECT assert_eq('gs quant compatibility 0837 gs_quant/test/timeseries/test_measures.py test_currency_to_tdapi_swap_rate_asset', gs_test_test_currency_to_tdapi_swap_rate_asset().canonical, 'fin_gsq_test_test_currency_to_tdapi_swap_rate_asset');
SELECT assert_eq('gs quant compatibility 0838 gs_quant/test/timeseries/test_measures.py test_currency_to_tdapi_basis_swap_rate_asset', gs_test_test_currency_to_tdapi_basis_swap_rate_asset().canonical, 'fin_gsq_test_test_currency_to_tdapi_basis_swap_rate_asset');
SELECT assert_eq('gs quant compatibility 0839 gs_quant/test/timeseries/test_measures.py test_currency_to_tdapi_swap_rate_asset_for_intraday', gs_test_test_currency_to_tdapi_swap_rate_asset_for_intraday().canonical, 'fin_gsq_test_test_currency_to_tdapi_swap_rate_asset_for_intraday');
SELECT assert_eq('gs quant compatibility 0840 gs_quant/test/timeseries/test_measures.py my_mocked_mxapi_backtest', gs_test_my_mocked_mxapi_backtest().canonical, 'fin_gsq_test_my_mocked_mxapi_backtest');
SELECT assert_eq('gs quant compatibility 0841 gs_quant/test/timeseries/test_measures.py test_swap_rate_calc', gs_test_test_swap_rate_calc().canonical, 'fin_gsq_test_test_swap_rate_calc');
SELECT assert_eq('gs quant compatibility 0842 gs_quant/test/timeseries/test_measures.py my_mocked_mxapi_measure', gs_test_my_mocked_mxapi_measure().canonical, 'fin_gsq_test_my_mocked_mxapi_measure');
SELECT assert_eq('gs quant compatibility 0843 gs_quant/test/timeseries/test_measures.py test_curve_measures', gs_test_test_curve_measures().canonical, 'fin_gsq_test_test_curve_measures');
SELECT assert_eq('gs quant compatibility 0844 gs_quant/test/timeseries/test_measures.py test_check_clearing_house', gs_test_test_check_clearing_house().canonical, 'fin_gsq_test_test_check_clearing_house');
SELECT assert_eq('gs quant compatibility 0845 gs_quant/test/timeseries/test_measures.py test_get_swap_csa_terms', gs_test_test_get_swap_csa_terms().canonical, 'fin_gsq_test_test_get_swap_csa_terms');
SELECT assert_eq('gs quant compatibility 0846 gs_quant/test/timeseries/test_measures.py test_get_basis_swap_csa_terms', gs_test_test_get_basis_swap_csa_terms().canonical, 'fin_gsq_test_test_get_basis_swap_csa_terms');
SELECT assert_eq('gs quant compatibility 0847 gs_quant/test/timeseries/test_measures.py test_match_floating_tenors', gs_test_test_match_floating_tenors().canonical, 'fin_gsq_test_test_match_floating_tenors');
SELECT assert_eq('gs quant compatibility 0848 gs_quant/test/timeseries/test_measures.py test_get_term_struct_date', gs_test_test_get_term_struct_date().canonical, 'fin_gsq_test_test_get_term_struct_date');
SELECT assert_eq('gs quant compatibility 0849 gs_quant/test/timeseries/test_measures.py test_cross_stored_direction_for_fx_vol', gs_test_test_cross_stored_direction_for_fx_vol().canonical, 'fin_gsq_test_test_cross_stored_direction_for_fx_vol');
SELECT assert_eq('gs quant compatibility 0850 gs_quant/test/timeseries/test_measures.py test_cross_to_usd_based_cross_for_fx_forecast', gs_test_test_cross_to_usd_based_cross_for_fx_forecast().canonical, 'fin_gsq_test_test_cross_to_usd_based_cross_for_fx_forecast');
SELECT assert_eq('gs quant compatibility 0851 gs_quant/test/timeseries/test_measures.py test_cross_to_used_based_cross', gs_test_test_cross_to_used_based_cross().canonical, 'fin_gsq_test_test_cross_to_used_based_cross');
SELECT assert_eq('gs quant compatibility 0852 gs_quant/test/timeseries/test_measures.py test_cross_stored_direction', gs_test_test_cross_stored_direction().canonical, 'fin_gsq_test_test_cross_stored_direction');
SELECT assert_eq('gs quant compatibility 0853 gs_quant/test/timeseries/test_measures.py test_get_tdapi_rates_assets', gs_test_test_get_tdapi_rates_assets().canonical, 'fin_gsq_test_test_get_tdapi_rates_assets');
SELECT assert_eq('gs quant compatibility 0854 gs_quant/test/timeseries/test_measures.py test_get_swap_leg_defaults', gs_test_test_get_swap_leg_defaults().canonical, 'fin_gsq_test_test_get_swap_leg_defaults');
SELECT assert_eq('gs quant compatibility 0855 gs_quant/test/timeseries/test_measures.py test_check_forward_tenor', gs_test_test_check_forward_tenor().canonical, 'fin_gsq_test_test_check_forward_tenor');
SELECT assert_eq('gs quant compatibility 0856 gs_quant/test/timeseries/test_measures.py mock_commod', gs_test_mock_commod().canonical, 'fin_gsq_test_mock_commod');
SELECT assert_eq('gs quant compatibility 0857 gs_quant/test/timeseries/test_measures.py mock_commod_dup', gs_test_mock_commod_dup().canonical, 'fin_gsq_test_mock_commod_dup');
SELECT assert_eq('gs quant compatibility 0858 gs_quant/test/timeseries/test_measures.py mock_forward_price', gs_test_mock_forward_price().canonical, 'fin_gsq_test_mock_forward_price');
SELECT assert_eq('gs quant compatibility 0859 gs_quant/test/timeseries/test_measures.py mock_implied_volatility_elec', gs_test_mock_implied_volatility_elec().canonical, 'fin_gsq_test_mock_implied_volatility_elec');
SELECT assert_eq('gs quant compatibility 0860 gs_quant/test/timeseries/test_measures.py mock_fair_price', gs_test_mock_fair_price().canonical, 'fin_gsq_test_mock_fair_price');
SELECT assert_eq('gs quant compatibility 0861 gs_quant/test/timeseries/test_measures.py mock_eu_natgas_forward_price', gs_test_mock_eu_natgas_forward_price().canonical, 'fin_gsq_test_mock_eu_natgas_forward_price');
SELECT assert_eq('gs quant compatibility 0862 gs_quant/test/timeseries/test_measures.py mock_natgas_forward_price', gs_test_mock_natgas_forward_price().canonical, 'fin_gsq_test_mock_natgas_forward_price');
SELECT assert_eq('gs quant compatibility 0863 gs_quant/test/timeseries/test_measures.py mock_natgas_implied_volatility', gs_test_mock_natgas_implied_volatility().canonical, 'fin_gsq_test_mock_natgas_implied_volatility');
SELECT assert_eq('gs quant compatibility 0864 gs_quant/test/timeseries/test_measures.py mock_fair_price_swap', gs_test_mock_fair_price_swap().canonical, 'fin_gsq_test_mock_fair_price_swap');
SELECT assert_eq('gs quant compatibility 0865 gs_quant/test/timeseries/test_measures.py mock_implied_volatility', gs_test_mock_implied_volatility().canonical, 'fin_gsq_test_mock_implied_volatility');
SELECT assert_eq('gs quant compatibility 0866 gs_quant/test/timeseries/test_measures.py mock_missing_bucket_forward_price', gs_test_mock_missing_bucket_forward_price().canonical, 'fin_gsq_test_mock_missing_bucket_forward_price');
SELECT assert_eq('gs quant compatibility 0867 gs_quant/test/timeseries/test_measures.py mock_missing_bucket_implied_volatility', gs_test_mock_missing_bucket_implied_volatility().canonical, 'fin_gsq_test_mock_missing_bucket_implied_volatility');
SELECT assert_eq('gs quant compatibility 0868 gs_quant/test/timeseries/test_measures.py mock_fx_vol', gs_test_mock_fx_vol().canonical, 'fin_gsq_test_mock_fx_vol');
SELECT assert_eq('gs quant compatibility 0869 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_3m', gs_test_mock_fx_spot_fwd_3m().canonical, 'fin_gsq_test_mock_fx_spot_fwd_3m');
SELECT assert_eq('gs quant compatibility 0870 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_2y', gs_test_mock_fx_spot_fwd_2y().canonical, 'fin_gsq_test_mock_fx_spot_fwd_2y');
SELECT assert_eq('gs quant compatibility 0871 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_3m_rt', gs_test_mock_fx_spot_fwd_3m_rt().canonical, 'fin_gsq_test_mock_fx_spot_fwd_3m_rt');
SELECT assert_eq('gs quant compatibility 0872 gs_quant/test/timeseries/test_measures.py mock_fx_spot_fwd_2y_rt', gs_test_mock_fx_spot_fwd_2y_rt().canonical, 'fin_gsq_test_mock_fx_spot_fwd_2y_rt');
SELECT assert_eq('gs quant compatibility 0873 gs_quant/test/timeseries/test_measures.py mock_fx_correlation', gs_test_mock_fx_correlation().canonical, 'fin_gsq_test_mock_fx_correlation');
SELECT assert_eq('gs quant compatibility 0874 gs_quant/test/timeseries/test_measures.py mock_fx_forecast', gs_test_mock_fx_forecast().canonical, 'fin_gsq_test_mock_fx_forecast');
SELECT assert_eq('gs quant compatibility 0875 gs_quant/test/timeseries/test_measures.py mock_fx_forecast_time_series', gs_test_mock_fx_forecast_time_series().canonical, 'fin_gsq_test_mock_fx_forecast_time_series');
SELECT assert_eq('gs quant compatibility 0876 gs_quant/test/timeseries/test_measures.py mock_fx_delta', gs_test_mock_fx_delta().canonical, 'fin_gsq_test_mock_fx_delta');
SELECT assert_eq('gs quant compatibility 0877 gs_quant/test/timeseries/test_measures.py mock_fx_empty', gs_test_mock_fx_empty().canonical, 'fin_gsq_test_mock_fx_empty');
SELECT assert_eq('gs quant compatibility 0878 gs_quant/test/timeseries/test_measures.py mock_fx_switch', gs_test_mock_fx_switch().canonical, 'fin_gsq_test_mock_fx_switch');
SELECT assert_eq('gs quant compatibility 0879 gs_quant/test/timeseries/test_measures.py mock_curr', gs_test_mock_curr().canonical, 'fin_gsq_test_mock_curr');
SELECT assert_eq('gs quant compatibility 0880 gs_quant/test/timeseries/test_measures.py mock_cross', gs_test_mock_cross().canonical, 'fin_gsq_test_mock_cross');
SELECT assert_eq('gs quant compatibility 0881 gs_quant/test/timeseries/test_measures.py mock_eq', gs_test_mock_eq().canonical, 'fin_gsq_test_mock_eq');
SELECT assert_eq('gs quant compatibility 0882 gs_quant/test/timeseries/test_measures.py mock_eq_vol', gs_test_mock_eq_vol().canonical, 'fin_gsq_test_mock_eq_vol');
SELECT assert_eq('gs quant compatibility 0883 gs_quant/test/timeseries/test_measures.py mock_eq_vol_last_empty', gs_test_mock_eq_vol_last_empty().canonical, 'fin_gsq_test_mock_eq_vol_last_empty');
SELECT assert_eq('gs quant compatibility 0884 gs_quant/test/timeseries/test_measures.py mock_eq_norm', gs_test_mock_eq_norm().canonical, 'fin_gsq_test_mock_eq_norm');
SELECT assert_eq('gs quant compatibility 0885 gs_quant/test/timeseries/test_measures.py mock_eq_spot', gs_test_mock_eq_spot().canonical, 'fin_gsq_test_mock_eq_spot');
SELECT assert_eq('gs quant compatibility 0886 gs_quant/test/timeseries/test_measures.py mock_inc', gs_test_mock_inc().canonical, 'fin_gsq_test_mock_inc');
SELECT assert_eq('gs quant compatibility 0887 gs_quant/test/timeseries/test_measures.py mock_esg', gs_test_mock_esg().canonical, 'fin_gsq_test_mock_esg');
SELECT assert_eq('gs quant compatibility 0888 gs_quant/test/timeseries/test_measures.py mock_index_positions_data', gs_test_mock_index_positions_data().canonical, 'fin_gsq_test_mock_index_positions_data');
SELECT assert_eq('gs quant compatibility 0889 gs_quant/test/timeseries/test_measures.py mock_rating', gs_test_mock_rating().canonical, 'fin_gsq_test_mock_rating');
SELECT assert_eq('gs quant compatibility 0890 gs_quant/test/timeseries/test_measures.py mock_gsdeer_gsfeer', gs_test_mock_gsdeer_gsfeer().canonical, 'fin_gsq_test_mock_gsdeer_gsfeer');
SELECT assert_eq('gs quant compatibility 0891 gs_quant/test/timeseries/test_measures.py mock_factor_profile', gs_test_mock_factor_profile().canonical, 'fin_gsq_test_mock_factor_profile');
SELECT assert_eq('gs quant compatibility 0892 gs_quant/test/timeseries/test_measures.py mock_commodity_forecast', gs_test_mock_commodity_forecast().canonical, 'fin_gsq_test_mock_commodity_forecast');
SELECT assert_eq('gs quant compatibility 0893 gs_quant/test/timeseries/test_measures.py mock_commodity_forecast_time_series', gs_test_mock_commodity_forecast_time_series().canonical, 'fin_gsq_test_mock_commodity_forecast_time_series');
SELECT assert_eq('gs quant compatibility 0894 gs_quant/test/timeseries/test_measures.py mock_cds_spread', gs_test_mock_cds_spread().canonical, 'fin_gsq_test_mock_cds_spread');
SELECT assert_eq('gs quant compatibility 0895 gs_quant/test/timeseries/test_measures.py test_skew', gs_test_test_skew().canonical, 'fin_gsq_test_test_skew');
SELECT assert_eq('gs quant compatibility 0896 gs_quant/test/timeseries/test_measures.py test_skew_fx', gs_test_test_skew_fx().canonical, 'fin_gsq_test_test_skew_fx');
SELECT assert_eq('gs quant compatibility 0897 gs_quant/test/timeseries/test_measures.py test_implied_vol', gs_test_test_implied_vol().canonical, 'fin_gsq_test_test_implied_vol');
SELECT assert_eq('gs quant compatibility 0898 gs_quant/test/timeseries/test_measures.py test_merge_dataframes', gs_test_test_merge_dataframes().canonical, 'fin_gsq_test_test_merge_dataframes');
SELECT assert_eq('gs quant compatibility 0899 gs_quant/test/timeseries/test_measures.py test_get_last_for_measure', gs_test_test_get_last_for_measure().canonical, 'fin_gsq_test_test_get_last_for_measure');
SELECT assert_eq('gs quant compatibility 0900 gs_quant/test/timeseries/test_measures.py test_ignore_errors', gs_test_test_ignore_errors().canonical, 'fin_gsq_test_test_ignore_errors');
SELECT assert_eq('gs quant compatibility 0901 gs_quant/test/timeseries/test_measures.py test_tenor_month_to_year', gs_test_test_tenor_month_to_year().canonical, 'fin_gsq_test_test_tenor_month_to_year');
SELECT assert_eq('gs quant compatibility 0902 gs_quant/test/timeseries/test_measures.py test_implied_vol_no_last', gs_test_test_implied_vol_no_last().canonical, 'fin_gsq_test_test_implied_vol_no_last');
SELECT assert_eq('gs quant compatibility 0903 gs_quant/test/timeseries/test_measures.py test_implied_vol_fx', gs_test_test_implied_vol_fx().canonical, 'fin_gsq_test_test_implied_vol_fx');
SELECT assert_eq('gs quant compatibility 0904 gs_quant/test/timeseries/test_measures.py test_fx_forecast', gs_test_test_fx_forecast().canonical, 'fin_gsq_test_test_fx_forecast');
SELECT assert_eq('gs quant compatibility 0905 gs_quant/test/timeseries/test_measures.py test_fx_forecast_inverse', gs_test_test_fx_forecast_inverse().canonical, 'fin_gsq_test_test_fx_forecast_inverse');
SELECT assert_eq('gs quant compatibility 0906 gs_quant/test/timeseries/test_measures.py test_fx_forecast_time_series', gs_test_test_fx_forecast_time_series().canonical, 'fin_gsq_test_test_fx_forecast_time_series');
SELECT assert_eq('gs quant compatibility 0907 gs_quant/test/timeseries/test_measures.py test_vol_smile', gs_test_test_vol_smile().canonical, 'fin_gsq_test_test_vol_smile');
SELECT assert_eq('gs quant compatibility 0908 gs_quant/test/timeseries/test_measures.py test_impl_corr', gs_test_test_impl_corr().canonical, 'fin_gsq_test_test_impl_corr');
SELECT assert_eq('gs quant compatibility 0909 gs_quant/test/timeseries/test_measures.py test_impl_corr_n', gs_test_test_impl_corr_n().canonical, 'fin_gsq_test_test_impl_corr_n');
SELECT assert_eq('gs quant compatibility 0910 gs_quant/test/timeseries/test_measures.py test_implied_corr_basket', gs_test_test_implied_corr_basket().canonical, 'fin_gsq_test_test_implied_corr_basket');
SELECT assert_eq('gs quant compatibility 0911 gs_quant/test/timeseries/test_measures.py test_realized_corr_basket', gs_test_test_realized_corr_basket().canonical, 'fin_gsq_test_test_realized_corr_basket');
SELECT assert_eq('gs quant compatibility 0912 gs_quant/test/timeseries/test_measures.py test_real_corr', gs_test_test_real_corr().canonical, 'fin_gsq_test_test_real_corr');
SELECT assert_eq('gs quant compatibility 0913 gs_quant/test/timeseries/test_measures.py test_real_corr_missing', gs_test_test_real_corr_missing().canonical, 'fin_gsq_test_test_real_corr_missing');
SELECT assert_eq('gs quant compatibility 0914 gs_quant/test/timeseries/test_measures.py test_real_corr_n', gs_test_test_real_corr_n().canonical, 'fin_gsq_test_test_real_corr_n');
SELECT assert_eq('gs quant compatibility 0915 gs_quant/test/timeseries/test_measures.py test_cds_implied_vol', gs_test_test_cds_implied_vol().canonical, 'fin_gsq_test_test_cds_implied_vol');
SELECT assert_eq('gs quant compatibility 0916 gs_quant/test/timeseries/test_measures.py test_implied_vol_credit', gs_test_test_implied_vol_credit().canonical, 'fin_gsq_test_test_implied_vol_credit');
SELECT assert_eq('gs quant compatibility 0917 gs_quant/test/timeseries/test_measures.py test_absolute_strike_credit', gs_test_test_absolute_strike_credit().canonical, 'fin_gsq_test_test_absolute_strike_credit');
SELECT assert_eq('gs quant compatibility 0918 gs_quant/test/timeseries/test_measures.py test_option_premium_credit', gs_test_test_option_premium_credit().canonical, 'fin_gsq_test_test_option_premium_credit');
SELECT assert_eq('gs quant compatibility 0919 gs_quant/test/timeseries/test_measures.py test_cds_spreads', gs_test_test_cds_spreads().canonical, 'fin_gsq_test_test_cds_spreads');
SELECT assert_eq('gs quant compatibility 0920 gs_quant/test/timeseries/test_measures.py test_avg_impl_vol', gs_test_test_avg_impl_vol().canonical, 'fin_gsq_test_test_avg_impl_vol');
SELECT assert_eq('gs quant compatibility 0921 gs_quant/test/timeseries/test_measures.py test_avg_realized_vol', gs_test_test_avg_realized_vol().canonical, 'fin_gsq_test_test_avg_realized_vol');
SELECT assert_eq('gs quant compatibility 0922 gs_quant/test/timeseries/test_measures.py test_avg_impl_var', gs_test_test_avg_impl_var().canonical, 'fin_gsq_test_test_avg_impl_var');
SELECT assert_eq('gs quant compatibility 0923 gs_quant/test/timeseries/test_measures.py test_basis_swap_spread', gs_test_test_basis_swap_spread().canonical, 'fin_gsq_test_test_basis_swap_spread');
SELECT assert_eq('gs quant compatibility 0924 gs_quant/test/timeseries/test_measures.py test_swap_rate', gs_test_test_swap_rate().canonical, 'fin_gsq_test_test_swap_rate');
SELECT assert_eq('gs quant compatibility 0925 gs_quant/test/timeseries/test_measures.py test_swap_annuity', gs_test_test_swap_annuity().canonical, 'fin_gsq_test_test_swap_annuity');
SELECT assert_eq('gs quant compatibility 0926 gs_quant/test/timeseries/test_measures.py test_swap_term_structure', gs_test_test_swap_term_structure().canonical, 'fin_gsq_test_test_swap_term_structure');
SELECT assert_eq('gs quant compatibility 0927 gs_quant/test/timeseries/test_measures.py test_basis_swap_term_structure', gs_test_test_basis_swap_term_structure().canonical, 'fin_gsq_test_test_basis_swap_term_structure');
SELECT assert_eq('gs quant compatibility 0928 gs_quant/test/timeseries/test_measures.py test_cap_floor_vol', gs_test_test_cap_floor_vol().canonical, 'fin_gsq_test_test_cap_floor_vol');
SELECT assert_eq('gs quant compatibility 0929 gs_quant/test/timeseries/test_measures.py test_cap_floor_atm_fwd_rate', gs_test_test_cap_floor_atm_fwd_rate().canonical, 'fin_gsq_test_test_cap_floor_atm_fwd_rate');
SELECT assert_eq('gs quant compatibility 0930 gs_quant/test/timeseries/test_measures.py test_spread_option_vol', gs_test_test_spread_option_vol().canonical, 'fin_gsq_test_test_spread_option_vol');
SELECT assert_eq('gs quant compatibility 0931 gs_quant/test/timeseries/test_measures.py test_spread_option_atm_fwd_rate', gs_test_test_spread_option_atm_fwd_rate().canonical, 'fin_gsq_test_test_spread_option_atm_fwd_rate');
SELECT assert_eq('gs quant compatibility 0932 gs_quant/test/timeseries/test_measures.py test_zc_inflation_swap_rate', gs_test_test_zc_inflation_swap_rate().canonical, 'fin_gsq_test_test_zc_inflation_swap_rate');
SELECT assert_eq('gs quant compatibility 0933 gs_quant/test/timeseries/test_measures.py test_basis', gs_test_test_basis().canonical, 'fin_gsq_test_test_basis');
SELECT assert_eq('gs quant compatibility 0934 gs_quant/test/timeseries/test_measures.py test_td', gs_test_test_td().canonical, 'fin_gsq_test_test_td');
SELECT assert_eq('gs quant compatibility 0935 gs_quant/test/timeseries/test_measures.py test_pricing_range', gs_test_test_pricing_range().canonical, 'fin_gsq_test_test_pricing_range');
SELECT assert_eq('gs quant compatibility 0936 gs_quant/test/timeseries/test_measures.py test_var_swap_tenors', gs_test_test_var_swap_tenors().canonical, 'fin_gsq_test_test_var_swap_tenors');
SELECT assert_eq('gs quant compatibility 0937 gs_quant/test/timeseries/test_measures.py test_forward_var_term', gs_test_test_forward_var_term().canonical, 'fin_gsq_test_test_forward_var_term');
SELECT assert_eq('gs quant compatibility 0938 gs_quant/test/timeseries/test_measures.py test_var_swap', gs_test_test_var_swap().canonical, 'fin_gsq_test_test_var_swap');
SELECT assert_eq('gs quant compatibility 0939 gs_quant/test/timeseries/test_measures.py test_var_swap_fwd', gs_test_test_var_swap_fwd().canonical, 'fin_gsq_test_test_var_swap_fwd');
SELECT assert_eq('gs quant compatibility 0940 gs_quant/test/timeseries/test_measures.py test_var_term', gs_test_test_var_term().canonical, 'fin_gsq_test_test_var_term');
SELECT assert_eq('gs quant compatibility 0941 gs_quant/test/timeseries/test_measures.py test_forward_vol', gs_test_test_forward_vol().canonical, 'fin_gsq_test_test_forward_vol');
SELECT assert_eq('gs quant compatibility 0942 gs_quant/test/timeseries/test_measures.py test_forward_vol_term', gs_test_test_forward_vol_term().canonical, 'fin_gsq_test_test_forward_vol_term');
SELECT assert_eq('gs quant compatibility 0943 gs_quant/test/timeseries/test_measures.py test_get_latest_term_structure_data', gs_test_test_get_latest_term_structure_data().canonical, 'fin_gsq_test_test_get_latest_term_structure_data');
SELECT assert_eq('gs quant compatibility 0944 gs_quant/test/timeseries/test_measures.py test_vol_term', gs_test_test_vol_term().canonical, 'fin_gsq_test_test_vol_term');
SELECT assert_eq('gs quant compatibility 0945 gs_quant/test/timeseries/test_measures.py test__get_skew_strikes', gs_test_test_get_skew_strikes().canonical, 'fin_gsq_test_test_get_skew_strikes');
SELECT assert_eq('gs quant compatibility 0946 gs_quant/test/timeseries/test_measures.py test__skew', gs_test_test_skew_test_timeseries_test_measures().canonical, 'fin_gsq_test_test_skew_test_timeseries_test_measures');
SELECT assert_eq('gs quant compatibility 0947 gs_quant/test/timeseries/test_measures.py test__skew_term_fetcher', gs_test_test_skew_term_fetcher().canonical, 'fin_gsq_test_test_skew_term_fetcher');
SELECT assert_eq('gs quant compatibility 0948 gs_quant/test/timeseries/test_measures.py test_skew_term', gs_test_test_skew_term().canonical, 'fin_gsq_test_test_skew_term');
SELECT assert_eq('gs quant compatibility 0949 gs_quant/test/timeseries/test_measures.py test_vol_term_fx', gs_test_test_vol_term_fx().canonical, 'fin_gsq_test_test_vol_term_fx');
SELECT assert_eq('gs quant compatibility 0950 gs_quant/test/timeseries/test_measures.py test_fwd_term', gs_test_test_fwd_term().canonical, 'fin_gsq_test_test_fwd_term');
SELECT assert_eq('gs quant compatibility 0951 gs_quant/test/timeseries/test_measures.py test_carry_term', gs_test_test_carry_term().canonical, 'fin_gsq_test_test_carry_term');
SELECT assert_eq('gs quant compatibility 0952 gs_quant/test/timeseries/test_measures.py test_measure_request_safe', gs_test_test_measure_request_safe().canonical, 'fin_gsq_test_test_measure_request_safe');
SELECT assert_eq('gs quant compatibility 0953 gs_quant/test/timeseries/test_measures.py test_bucketize_price', gs_test_test_bucketize_price().canonical, 'fin_gsq_test_test_bucketize_price');
SELECT assert_eq('gs quant compatibility 0954 gs_quant/test/timeseries/test_measures.py test_forward_price', gs_test_test_forward_price_test_timeseries_test_measures().canonical, 'fin_gsq_test_test_forward_price_test_timeseries_test_measures');
SELECT assert_eq('gs quant compatibility 0955 gs_quant/test/timeseries/test_measures.py test_implied_volatility_elec', gs_test_test_implied_volatility_elec().canonical, 'fin_gsq_test_test_implied_volatility_elec');
SELECT assert_eq('gs quant compatibility 0956 gs_quant/test/timeseries/test_measures.py test_forward_price_ng', gs_test_test_forward_price_ng().canonical, 'fin_gsq_test_test_forward_price_ng');
SELECT assert_eq('gs quant compatibility 0957 gs_quant/test/timeseries/test_measures.py test_implied_volatility_ng', gs_test_test_implied_volatility_ng().canonical, 'fin_gsq_test_test_implied_volatility_ng');
SELECT assert_eq('gs quant compatibility 0958 gs_quant/test/timeseries/test_measures.py test_get_iso_data', gs_test_test_get_iso_data().canonical, 'fin_gsq_test_test_get_iso_data');
SELECT assert_eq('gs quant compatibility 0959 gs_quant/test/timeseries/test_measures.py test_string_to_date_interval', gs_test_test_string_to_date_interval().canonical, 'fin_gsq_test_test_string_to_date_interval');
SELECT assert_eq('gs quant compatibility 0960 gs_quant/test/timeseries/test_measures.py test_implied_vol_commod', gs_test_test_implied_vol_commod().canonical, 'fin_gsq_test_test_implied_vol_commod');
SELECT assert_eq('gs quant compatibility 0961 gs_quant/test/timeseries/test_measures.py test_fair_price', gs_test_test_fair_price().canonical, 'fin_gsq_test_test_fair_price');
SELECT assert_eq('gs quant compatibility 0962 gs_quant/test/timeseries/test_measures.py test_weighted_average_valuation_curve_for_calendar_strip', gs_test_test_weighted_average_valuation_curve_for_calendar_strip().canonical, 'fin_gsq_test_test_weighted_average_valuation_curve_for_calendar_strip');
SELECT assert_eq('gs quant compatibility 0963 gs_quant/test/timeseries/test_measures.py test_fundamental_metrics', gs_test_test_fundamental_metrics().canonical, 'fin_gsq_test_test_fundamental_metrics');
SELECT assert_eq('gs quant compatibility 0964 gs_quant/test/timeseries/test_measures.py test_realized_volatility', gs_test_test_realized_volatility().canonical, 'fin_gsq_test_test_realized_volatility');
SELECT assert_eq('gs quant compatibility 0965 gs_quant/test/timeseries/test_measures.py test_esg_headline_metric', gs_test_test_esg_headline_metric().canonical, 'fin_gsq_test_test_esg_headline_metric');
SELECT assert_eq('gs quant compatibility 0966 gs_quant/test/timeseries/test_measures.py test_rating', gs_test_test_rating().canonical, 'fin_gsq_test_test_rating');
SELECT assert_eq('gs quant compatibility 0967 gs_quant/test/timeseries/test_measures.py test_fair_value', gs_test_test_fair_value().canonical, 'fin_gsq_test_test_fair_value');
SELECT assert_eq('gs quant compatibility 0968 gs_quant/test/timeseries/test_measures.py test_factor_profile', gs_test_test_factor_profile().canonical, 'fin_gsq_test_test_factor_profile');
SELECT assert_eq('gs quant compatibility 0969 gs_quant/test/timeseries/test_measures.py test_commodity_forecast', gs_test_test_commodity_forecast().canonical, 'fin_gsq_test_test_commodity_forecast');
SELECT assert_eq('gs quant compatibility 0970 gs_quant/test/timeseries/test_measures.py test_commodity_forecast_time_series', gs_test_test_commodity_forecast_time_series().canonical, 'fin_gsq_test_test_commodity_forecast_time_series');
SELECT assert_eq('gs quant compatibility 0971 gs_quant/test/timeseries/test_measures.py test_fx_implied_correlation', gs_test_test_fx_implied_correlation().canonical, 'fin_gsq_test_test_fx_implied_correlation');
SELECT assert_eq('gs quant compatibility 0972 gs_quant/test/timeseries/test_measures.py mock_forward_curve_peak', gs_test_mock_forward_curve_peak().canonical, 'fin_gsq_test_mock_forward_curve_peak');
SELECT assert_eq('gs quant compatibility 0973 gs_quant/test/timeseries/test_measures.py mock_forward_curve_peak_holiday', gs_test_mock_forward_curve_peak_holiday().canonical, 'fin_gsq_test_mock_forward_curve_peak_holiday');
SELECT assert_eq('gs quant compatibility 0974 gs_quant/test/timeseries/test_measures.py mock_forward_curve_offpeak', gs_test_mock_forward_curve_offpeak().canonical, 'fin_gsq_test_mock_forward_curve_offpeak');
SELECT assert_eq('gs quant compatibility 0975 gs_quant/test/timeseries/test_measures.py mock_empty_forward_curve', gs_test_mock_empty_forward_curve().canonical, 'fin_gsq_test_mock_empty_forward_curve');
SELECT assert_eq('gs quant compatibility 0976 gs_quant/test/timeseries/test_measures.py test_forward_curve', gs_test_test_forward_curve().canonical, 'fin_gsq_test_test_forward_curve');
SELECT assert_eq('gs quant compatibility 0977 gs_quant/test/timeseries/test_measures.py mock_us_gas_forward_curve', gs_test_mock_us_gas_forward_curve().canonical, 'fin_gsq_test_mock_us_gas_forward_curve');
SELECT assert_eq('gs quant compatibility 0978 gs_quant/test/timeseries/test_measures.py test_us_gas_forward_curve', gs_test_test_us_gas_forward_curve().canonical, 'fin_gsq_test_test_us_gas_forward_curve');
SELECT assert_eq('gs quant compatibility 0979 gs_quant/test/timeseries/test_measures.py test_eu_ng_hub_to_swap', gs_test_test_eu_ng_hub_to_swap().canonical, 'fin_gsq_test_test_eu_ng_hub_to_swap');
SELECT assert_eq('gs quant compatibility 0980 gs_quant/test/timeseries/test_measures.py test_settlement_price', gs_test_test_settlement_price().canonical, 'fin_gsq_test_test_settlement_price');
SELECT assert_eq('gs quant compatibility 0981 gs_quant/test/timeseries/test_measures.py test_hloc_prices', gs_test_test_hloc_prices().canonical, 'fin_gsq_test_test_hloc_prices');
SELECT assert_eq('gs quant compatibility 0982 gs_quant/test/timeseries/test_measures.py test_thematic_model_exposure', gs_test_test_thematic_model_exposure().canonical, 'fin_gsq_test_test_thematic_model_exposure');
SELECT assert_eq('gs quant compatibility 0983 gs_quant/test/timeseries/test_measures.py test_thematic_model_beta', gs_test_test_thematic_model_beta().canonical, 'fin_gsq_test_test_thematic_model_beta');
SELECT assert_eq('gs quant compatibility 0984 gs_quant/test/timeseries/test_measures.py test_thematic_model_beta_single_stock', gs_test_test_thematic_model_beta_single_stock().canonical, 'fin_gsq_test_test_thematic_model_beta_single_stock');
SELECT assert_eq('gs quant compatibility 0985 gs_quant/test/timeseries/test_measures.py test_retail_interest_agg', gs_test_test_retail_interest_agg().canonical, 'fin_gsq_test_test_retail_interest_agg');
SELECT assert_eq('gs quant compatibility 0986 gs_quant/test/timeseries/test_measures.py test_s3_long_short_concentration', gs_test_test_s3_long_short_concentration().canonical, 'fin_gsq_test_test_s3_long_short_concentration');
SELECT assert_eq('gs quant compatibility 0987 gs_quant/test/timeseries/test_measures_countries.py test_fci', gs_test_test_fci().canonical, 'fin_gsq_test_test_fci');
SELECT assert_eq('gs quant compatibility 0988 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_af', gs_test_mock_fe_estimate_af().canonical, 'fin_gsq_test_mock_fe_estimate_af');
SELECT assert_eq('gs quant compatibility 0989 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_qf', gs_test_mock_fe_estimate_qf().canonical, 'fin_gsq_test_mock_fe_estimate_qf');
SELECT assert_eq('gs quant compatibility 0990 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_saf', gs_test_mock_fe_estimate_saf().canonical, 'fin_gsq_test_mock_fe_estimate_saf');
SELECT assert_eq('gs quant compatibility 0991 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_ntm', gs_test_mock_fe_estimate_ntm().canonical, 'fin_gsq_test_mock_fe_estimate_ntm');
SELECT assert_eq('gs quant compatibility 0992 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_lt', gs_test_mock_fe_estimate_lt().canonical, 'fin_gsq_test_mock_fe_estimate_lt');
SELECT assert_eq('gs quant compatibility 0993 gs_quant/test/timeseries/test_measures_factset.py mock_fe_actual', gs_test_mock_fe_actual().canonical, 'fin_gsq_test_mock_fe_actual');
SELECT assert_eq('gs quant compatibility 0994 gs_quant/test/timeseries/test_measures_factset.py mock_fe_estimate_empty', gs_test_mock_fe_estimate_empty().canonical, 'fin_gsq_test_mock_fe_estimate_empty');
SELECT assert_eq('gs quant compatibility 0995 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_empty', gs_test_mock_factset_fundamentals_empty().canonical, 'fin_gsq_test_mock_factset_fundamentals_empty');
SELECT assert_eq('gs quant compatibility 0996 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_basic', gs_test_mock_factset_fundamentals_basic().canonical, 'fin_gsq_test_mock_factset_fundamentals_basic');
SELECT assert_eq('gs quant compatibility 0997 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_basic_derived', gs_test_mock_factset_fundamentals_basic_derived().canonical, 'fin_gsq_test_mock_factset_fundamentals_basic_derived');
SELECT assert_eq('gs quant compatibility 0998 gs_quant/test/timeseries/test_measures_factset.py mock_factset_fundamentals_basic_restated', gs_test_mock_factset_fundamentals_basic_restated().canonical, 'fin_gsq_test_mock_factset_fundamentals_basic_restated');
SELECT assert_eq('gs quant compatibility 0999 gs_quant/test/timeseries/test_measures_factset.py mock_factset_ratings', gs_test_mock_factset_ratings().canonical, 'fin_gsq_test_mock_factset_ratings');
SELECT assert_eq('gs quant compatibility 1000 gs_quant/test/timeseries/test_measures_factset.py test_factset_estimates', gs_test_test_factset_estimates().canonical, 'fin_gsq_test_test_factset_estimates');
SELECT assert_eq('gs quant compatibility 1001 gs_quant/test/timeseries/test_measures_factset.py test_factset_fundamentals', gs_test_test_factset_fundamentals().canonical, 'fin_gsq_test_test_factset_fundamentals');
SELECT assert_eq('gs quant compatibility 1002 gs_quant/test/timeseries/test_measures_factset.py test_factset_ratings', gs_test_test_factset_ratings().canonical, 'fin_gsq_test_test_factset_ratings');
SELECT assert_eq('gs quant compatibility 1003 gs_quant/test/timeseries/test_measures_factset.py test_fiscal_period', gs_test_test_fiscal_period().canonical, 'fin_gsq_test_test_fiscal_period');
SELECT assert_eq('gs quant compatibility 1004 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_invalid_basis', gs_test_test_gir_estimates_invalid_basis().canonical, 'fin_gsq_test_test_gir_estimates_invalid_basis');
SELECT assert_eq('gs quant compatibility 1005 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_invalid_period_type', gs_test_test_gir_estimates_invalid_period_type().canonical, 'fin_gsq_test_test_gir_estimates_invalid_period_type');
SELECT assert_eq('gs quant compatibility 1006 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_fiscal_period_no_year', gs_test_test_gir_estimates_fiscal_period_no_year().canonical, 'fin_gsq_test_test_gir_estimates_fiscal_period_no_year');
SELECT assert_eq('gs quant compatibility 1007 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_qtr_fiscal_period_no_quarter', gs_test_test_gir_estimates_qtr_fiscal_period_no_quarter().canonical, 'fin_gsq_test_test_gir_estimates_qtr_fiscal_period_no_quarter');
SELECT assert_eq('gs quant compatibility 1008 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_qtr_fiscal_period_invalid_quarter', gs_test_test_gir_estimates_qtr_fiscal_period_invalid_quarter().canonical, 'fin_gsq_test_test_gir_estimates_qtr_fiscal_period_invalid_quarter');
SELECT assert_eq('gs quant compatibility 1009 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_no_bbid', gs_test_test_gir_estimates_no_bbid().canonical, 'fin_gsq_test_test_gir_estimates_no_bbid');
SELECT assert_eq('gs quant compatibility 1010 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_rolling_annual', gs_test_test_gir_estimates_rolling_annual().canonical, 'fin_gsq_test_test_gir_estimates_rolling_annual');
SELECT assert_eq('gs quant compatibility 1011 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_rolling_quarterly', gs_test_test_gir_estimates_rolling_quarterly().canonical, 'fin_gsq_test_test_gir_estimates_rolling_quarterly');
SELECT assert_eq('gs quant compatibility 1012 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_fixed_annual', gs_test_test_gir_estimates_fixed_annual().canonical, 'fin_gsq_test_test_gir_estimates_fixed_annual');
SELECT assert_eq('gs quant compatibility 1013 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_fixed_quarterly', gs_test_test_gir_estimates_fixed_quarterly().canonical, 'fin_gsq_test_test_gir_estimates_fixed_quarterly');
SELECT assert_eq('gs quant compatibility 1014 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_empty_response', gs_test_test_gir_estimates_empty_response().canonical, 'fin_gsq_test_test_gir_estimates_empty_response');
SELECT assert_eq('gs quant compatibility 1015 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_null_numeric', gs_test_test_gir_estimates_null_numeric().canonical, 'fin_gsq_test_test_gir_estimates_null_numeric');
SELECT assert_eq('gs quant compatibility 1016 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_null_numeric_fixed_period', gs_test_test_gir_estimates_null_numeric_fixed_period().canonical, 'fin_gsq_test_test_gir_estimates_null_numeric_fixed_period');
SELECT assert_eq('gs quant compatibility 1017 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_empty_response_fixed_period', gs_test_test_gir_estimates_empty_response_fixed_period().canonical, 'fin_gsq_test_test_gir_estimates_empty_response_fixed_period');
SELECT assert_eq('gs quant compatibility 1018 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_threadpool_exception', gs_test_test_gir_estimates_threadpool_exception().canonical, 'fin_gsq_test_test_gir_estimates_threadpool_exception');
SELECT assert_eq('gs quant compatibility 1019 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_threadpool_exception_fixed', gs_test_test_gir_estimates_threadpool_exception_fixed().canonical, 'fin_gsq_test_test_gir_estimates_threadpool_exception_fixed');
SELECT assert_eq('gs quant compatibility 1020 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_no_data_within_period', gs_test_test_gir_estimates_no_data_within_period().canonical, 'fin_gsq_test_test_gir_estimates_no_data_within_period');
SELECT assert_eq('gs quant compatibility 1021 gs_quant/test/timeseries/test_measures_factset.py test_build_query_args_with_start_end_override', gs_test_test_build_query_args_with_start_end_override().canonical, 'fin_gsq_test_test_build_query_args_with_start_end_override');
SELECT assert_eq('gs quant compatibility 1022 gs_quant/test/timeseries/test_measures_factset.py test_build_query_args_rolling_annual', gs_test_test_build_query_args_rolling_annual().canonical, 'fin_gsq_test_test_build_query_args_rolling_annual');
SELECT assert_eq('gs quant compatibility 1023 gs_quant/test/timeseries/test_measures_factset.py test_build_query_args_rolling_quarterly', gs_test_test_build_query_args_rolling_quarterly().canonical, 'fin_gsq_test_test_build_query_args_rolling_quarterly');
SELECT assert_eq('gs quant compatibility 1024 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_empty_df', gs_test_test_extract_value_empty_df().canonical, 'fin_gsq_test_test_extract_value_empty_df');
SELECT assert_eq('gs quant compatibility 1025 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_all_null_metric', gs_test_test_extract_value_all_null_metric().canonical, 'fin_gsq_test_test_extract_value_all_null_metric');
SELECT assert_eq('gs quant compatibility 1026 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_with_int_period_no_matching_date', gs_test_test_extract_value_with_int_period_no_matching_date().canonical, 'fin_gsq_test_test_extract_value_with_int_period_no_matching_date');
SELECT assert_eq('gs quant compatibility 1027 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_with_int_period_quarterly', gs_test_test_extract_value_with_int_period_quarterly().canonical, 'fin_gsq_test_test_extract_value_with_int_period_quarterly');
SELECT assert_eq('gs quant compatibility 1028 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_with_int_period_returns_first_sorted', gs_test_test_extract_value_with_int_period_returns_first_sorted().canonical, 'fin_gsq_test_test_extract_value_with_int_period_returns_first_sorted');
SELECT assert_eq('gs quant compatibility 1029 gs_quant/test/timeseries/test_measures_factset.py test_extract_value_non_int_period', gs_test_test_extract_value_non_int_period().canonical, 'fin_gsq_test_test_extract_value_non_int_period');
SELECT assert_eq('gs quant compatibility 1030 gs_quant/test/timeseries/test_measures_factset.py test_query_single_date', gs_test_test_query_single_date().canonical, 'fin_gsq_test_test_query_single_date');
SELECT assert_eq('gs quant compatibility 1031 gs_quant/test/timeseries/test_measures_factset.py test_query_dates_parallel', gs_test_test_query_dates_parallel().canonical, 'fin_gsq_test_test_query_dates_parallel');
SELECT assert_eq('gs quant compatibility 1032 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_scaled_metric', gs_test_test_gir_estimates_scaled_metric().canonical, 'fin_gsq_test_test_gir_estimates_scaled_metric');
SELECT assert_eq('gs quant compatibility 1033 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_end_date_appended', gs_test_test_gir_estimates_end_date_appended().canonical, 'fin_gsq_test_test_gir_estimates_end_date_appended');
SELECT assert_eq('gs quant compatibility 1034 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_weekly_and_daily_drill_down', gs_test_test_gir_estimates_weekly_and_daily_drill_down().canonical, 'fin_gsq_test_test_gir_estimates_weekly_and_daily_drill_down');
SELECT assert_eq('gs quant compatibility 1035 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_weekly_drill_exception', gs_test_test_gir_estimates_weekly_drill_exception().canonical, 'fin_gsq_test_test_gir_estimates_weekly_drill_exception');
SELECT assert_eq('gs quant compatibility 1036 gs_quant/test/timeseries/test_measures_factset.py test_gir_estimates_daily_drill_exception', gs_test_test_gir_estimates_daily_drill_exception().canonical, 'fin_gsq_test_test_gir_estimates_daily_drill_exception');
SELECT assert_eq('gs quant compatibility 1037 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_invalid_metric', gs_test_test_factset_ev_invalid_metric().canonical, 'fin_gsq_test_test_factset_ev_invalid_metric');
SELECT assert_eq('gs quant compatibility 1038 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_no_bbid', gs_test_test_factset_ev_no_bbid().canonical, 'fin_gsq_test_test_factset_ev_no_bbid');
SELECT assert_eq('gs quant compatibility 1039 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_no_bcid', gs_test_test_factset_ev_no_bcid().canonical, 'fin_gsq_test_test_factset_ev_no_bcid');
SELECT assert_eq('gs quant compatibility 1040 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_empty_capital_structure', gs_test_test_factset_ev_empty_capital_structure().canonical, 'fin_gsq_test_test_factset_ev_empty_capital_structure');
SELECT assert_eq('gs quant compatibility 1041 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_success_with_lease', gs_test_test_factset_ev_success_with_lease().canonical, 'fin_gsq_test_test_factset_ev_success_with_lease');
SELECT assert_eq('gs quant compatibility 1042 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_success_no_lease', gs_test_test_factset_ev_success_no_lease().canonical, 'fin_gsq_test_test_factset_ev_success_no_lease');
SELECT assert_eq('gs quant compatibility 1043 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_negative_pension', gs_test_test_factset_ev_negative_pension().canonical, 'fin_gsq_test_test_factset_ev_negative_pension');
SELECT assert_eq('gs quant compatibility 1044 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_market_cap_metric', gs_test_test_factset_ev_market_cap_metric().canonical, 'fin_gsq_test_test_factset_ev_market_cap_metric');
SELECT assert_eq('gs quant compatibility 1045 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_capital_structure_exception', gs_test_test_factset_ev_capital_structure_exception().canonical, 'fin_gsq_test_test_factset_ev_capital_structure_exception');
SELECT assert_eq('gs quant compatibility 1046 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_fundamentals_exception', gs_test_test_factset_ev_fundamentals_exception().canonical, 'fin_gsq_test_test_factset_ev_fundamentals_exception');
SELECT assert_eq('gs quant compatibility 1047 gs_quant/test/timeseries/test_measures_factset.py test_factset_ev_no_lease_column', gs_test_test_factset_ev_no_lease_column().canonical, 'fin_gsq_test_test_factset_ev_no_lease_column');
SELECT assert_eq('gs quant compatibility 1048 gs_quant/test/timeseries/test_measures_fx_vol.py test_currencypair_to_tdapi_fxfwd_asset', gs_test_test_currencypair_to_tdapi_fxfwd_asset().canonical, 'fin_gsq_test_test_currencypair_to_tdapi_fxfwd_asset');
SELECT assert_eq('gs quant compatibility 1049 gs_quant/test/timeseries/test_measures_fx_vol.py test_currencypair_to_tdapi_fxo_asset', gs_test_test_currencypair_to_tdapi_fxo_asset().canonical, 'fin_gsq_test_test_currencypair_to_tdapi_fxo_asset');
SELECT assert_eq('gs quant compatibility 1050 gs_quant/test/timeseries/test_measures_fx_vol.py test_get_fxo_defaults', gs_test_test_get_fxo_defaults().canonical, 'fin_gsq_test_test_get_fxo_defaults');
SELECT assert_eq('gs quant compatibility 1051 gs_quant/test/timeseries/test_measures_fx_vol.py test_get_fxo_csa_terms', gs_test_test_get_fxo_csa_terms().canonical, 'fin_gsq_test_test_get_fxo_csa_terms');
SELECT assert_eq('gs quant compatibility 1052 gs_quant/test/timeseries/test_measures_fx_vol.py test_check_valid_indices', gs_test_test_check_valid_indices().canonical, 'fin_gsq_test_test_check_valid_indices');
SELECT assert_eq('gs quant compatibility 1053 gs_quant/test/timeseries/test_measures_fx_vol.py test_cross_stored_direction_for_fx_vol', gs_test_test_cross_stored_direction_for_fx_vol_test_timeseries_test_measures_fx_vol().canonical, 'fin_gsq_test_test_cross_stored_direction_for_fx_vol_test_timeseries_test_measures_fx_vol');
SELECT assert_eq('gs quant compatibility 1054 gs_quant/test/timeseries/test_measures_fx_vol.py test_get_tdapi_fxo_assets', gs_test_test_get_tdapi_fxo_assets().canonical, 'fin_gsq_test_test_get_tdapi_fxo_assets');
SELECT assert_eq('gs quant compatibility 1055 gs_quant/test/timeseries/test_measures_fx_vol.py mock_curr', gs_test_mock_curr_test_timeseries_test_measures_fx_vol().canonical, 'fin_gsq_test_mock_curr_test_timeseries_test_measures_fx_vol');
SELECT assert_eq('gs quant compatibility 1056 gs_quant/test/timeseries/test_measures_fx_vol.py mock_fx_spot_carry_3m', gs_test_mock_fx_spot_carry_3m().canonical, 'fin_gsq_test_mock_fx_spot_carry_3m');
SELECT assert_eq('gs quant compatibility 1057 gs_quant/test/timeseries/test_measures_fx_vol.py mock_fx_spot_carry_2y', gs_test_mock_fx_spot_carry_2y().canonical, 'fin_gsq_test_mock_fx_spot_carry_2y');
SELECT assert_eq('gs quant compatibility 1058 gs_quant/test/timeseries/test_measures_fx_vol.py test_fx_vol_measure', gs_test_test_fx_vol_measure().canonical, 'fin_gsq_test_test_fx_vol_measure');
SELECT assert_eq('gs quant compatibility 1059 gs_quant/test/timeseries/test_measures_fx_vol.py test_fwd_points', gs_test_test_fwd_points().canonical, 'fin_gsq_test_test_fwd_points');
SELECT assert_eq('gs quant compatibility 1060 gs_quant/test/timeseries/test_measures_fx_vol.py mock_df', gs_test_mock_df().canonical, 'fin_gsq_test_mock_df');
SELECT assert_eq('gs quant compatibility 1061 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_raises_exception', gs_test_test_vol_swap_strike_raises_exception().canonical, 'fin_gsq_test_test_vol_swap_strike_raises_exception');
SELECT assert_eq('gs quant compatibility 1062 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_unsupported_cross', gs_test_test_vol_swap_strike_unsupported_cross().canonical, 'fin_gsq_test_test_vol_swap_strike_unsupported_cross');
SELECT assert_eq('gs quant compatibility 1063 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_matches_multiple_assets', gs_test_test_vol_swap_strike_matches_multiple_assets().canonical, 'fin_gsq_test_test_vol_swap_strike_matches_multiple_assets');
SELECT assert_eq('gs quant compatibility 1064 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_matches_no_assets', gs_test_test_vol_swap_strike_matches_no_assets().canonical, 'fin_gsq_test_test_vol_swap_strike_matches_no_assets');
SELECT assert_eq('gs quant compatibility 1065 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none', gs_test_test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none().canonical, 'fin_gsq_test_test_vol_swap_strike_matches_no_assets_when_expiry_tenor_is_not_none');
SELECT assert_eq('gs quant compatibility 1066 gs_quant/test/timeseries/test_measures_fx_vol.py test_currencypair_to_tdapi_fx_vol_swap_asset', gs_test_test_currencypair_to_tdapi_fx_vol_swap_asset().canonical, 'fin_gsq_test_test_currencypair_to_tdapi_fx_vol_swap_asset');
SELECT assert_eq('gs quant compatibility 1067 gs_quant/test/timeseries/test_measures_fx_vol.py test_vol_swap_strike', gs_test_test_vol_swap_strike().canonical, 'fin_gsq_test_test_vol_swap_strike');
SELECT assert_eq('gs quant compatibility 1068 gs_quant/test/timeseries/test_measures_fx_vol.py test_implied_volatility_fxvol', gs_test_test_implied_volatility_fxvol().canonical, 'fin_gsq_test_test_implied_volatility_fxvol');
SELECT assert_eq('gs quant compatibility 1069 gs_quant/test/timeseries/test_measures_fx_vol.py test_spot_carry', gs_test_test_spot_carry().canonical, 'fin_gsq_test_test_spot_carry');
SELECT assert_eq('gs quant compatibility 1070 gs_quant/test/timeseries/test_measures_inflation.py test_get_floating_rate_option_for_benchmark_retuns_rate', gs_test_test_get_floating_rate_option_for_benchmark_retuns_rate().canonical, 'fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate');
SELECT assert_eq('gs quant compatibility 1071 gs_quant/test/timeseries/test_measures_inflation.py test_get_floating_rate_option_for_benchmark_retuns_rate_usd', gs_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd().canonical, 'fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd');
SELECT assert_eq('gs quant compatibility 1072 gs_quant/test/timeseries/test_measures_inflation.py test_currency_to_tdapi_inflation_swap_rate_asset', gs_test_test_currency_to_tdapi_inflation_swap_rate_asset().canonical, 'fin_gsq_test_test_currency_to_tdapi_inflation_swap_rate_asset');
SELECT assert_eq('gs quant compatibility 1073 gs_quant/test/timeseries/test_measures_inflation.py test_get_inflation_swap_leg_defaults', gs_test_test_get_inflation_swap_leg_defaults().canonical, 'fin_gsq_test_test_get_inflation_swap_leg_defaults');
SELECT assert_eq('gs quant compatibility 1074 gs_quant/test/timeseries/test_measures_inflation.py test_get_inflation_swap_csa_terms', gs_test_test_get_inflation_swap_csa_terms().canonical, 'fin_gsq_test_test_get_inflation_swap_csa_terms');
SELECT assert_eq('gs quant compatibility 1075 gs_quant/test/timeseries/test_measures_inflation.py test_check_valid_indices', gs_test_test_check_valid_indices_test_timeseries_test_meas_19b98b8bc0().canonical, 'fin_gsq_test_test_check_valid_indices_test_timeseries_test_meas_19b98b8bc0');
SELECT assert_eq('gs quant compatibility 1076 gs_quant/test/timeseries/test_measures_inflation.py test_get_tdapi_inflation_rates_assets', gs_test_test_get_tdapi_inflation_rates_assets().canonical, 'fin_gsq_test_test_get_tdapi_inflation_rates_assets');
SELECT assert_eq('gs quant compatibility 1077 gs_quant/test/timeseries/test_measures_inflation.py mock_curr', gs_test_mock_curr_test_timeseries_test_meas_19b98b8bc0().canonical, 'fin_gsq_test_mock_curr_test_timeseries_test_meas_19b98b8bc0');
SELECT assert_eq('gs quant compatibility 1078 gs_quant/test/timeseries/test_measures_inflation.py test_inflation_swap_rate', gs_test_test_inflation_swap_rate().canonical, 'fin_gsq_test_test_inflation_swap_rate');
SELECT assert_eq('gs quant compatibility 1079 gs_quant/test/timeseries/test_measures_inflation.py test_inflation_swap_term', gs_test_test_inflation_swap_term().canonical, 'fin_gsq_test_test_inflation_swap_term');
SELECT assert_eq('gs quant compatibility 1080 gs_quant/test/timeseries/test_measures_portfolios.py mock_risk_model', gs_test_mock_risk_model_test_timeseries_test_meas_c9972596c1().canonical, 'fin_gsq_test_mock_risk_model_test_timeseries_test_meas_c9972596c1');
SELECT assert_eq('gs quant compatibility 1081 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_factor_exposure', gs_test_test_portfolio_factor_exposure().canonical, 'fin_gsq_test_test_portfolio_factor_exposure');
SELECT assert_eq('gs quant compatibility 1082 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_factor_pnl', gs_test_test_portfolio_factor_pnl().canonical, 'fin_gsq_test_test_portfolio_factor_pnl');
SELECT assert_eq('gs quant compatibility 1083 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_factor_proportion_of_risk', gs_test_test_portfolio_factor_proportion_of_risk().canonical, 'fin_gsq_test_test_portfolio_factor_proportion_of_risk');
SELECT assert_eq('gs quant compatibility 1084 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_thematic_exposure', gs_test_test_portfolio_thematic_exposure().canonical, 'fin_gsq_test_test_portfolio_thematic_exposure');
SELECT assert_eq('gs quant compatibility 1085 gs_quant/test/timeseries/test_measures_portfolios.py test_portfolio_pnl', gs_test_test_portfolio_pnl().canonical, 'fin_gsq_test_test_portfolio_pnl');
SELECT assert_eq('gs quant compatibility 1086 gs_quant/test/timeseries/test_measures_portfolios.py test_aggregate_factor_support', gs_test_test_aggregate_factor_support().canonical, 'fin_gsq_test_test_aggregate_factor_support');
SELECT assert_eq('gs quant compatibility 1087 gs_quant/test/timeseries/test_measures_portfolios.py test_hit_rate', gs_test_test_hit_rate().canonical, 'fin_gsq_test_test_hit_rate');
SELECT assert_eq('gs quant compatibility 1088 gs_quant/test/timeseries/test_measures_portfolios.py test_max_drawdown', gs_test_test_max_drawdown_test_timeseries_test_meas_c9972596c1().canonical, 'fin_gsq_test_test_max_drawdown_test_timeseries_test_meas_c9972596c1');
SELECT assert_eq('gs quant compatibility 1089 gs_quant/test/timeseries/test_measures_portfolios.py test_max_recovery_period', gs_test_test_max_recovery_period().canonical, 'fin_gsq_test_test_max_recovery_period');
SELECT assert_eq('gs quant compatibility 1090 gs_quant/test/timeseries/test_measures_portfolios.py test_drawdown_length', gs_test_test_drawdown_length().canonical, 'fin_gsq_test_test_drawdown_length');
SELECT assert_eq('gs quant compatibility 1091 gs_quant/test/timeseries/test_measures_portfolios.py test_standard_deviation', gs_test_test_standard_deviation().canonical, 'fin_gsq_test_test_standard_deviation');
SELECT assert_eq('gs quant compatibility 1092 gs_quant/test/timeseries/test_measures_portfolios.py test_downside_risk', gs_test_test_downside_risk().canonical, 'fin_gsq_test_test_downside_risk');
SELECT assert_eq('gs quant compatibility 1093 gs_quant/test/timeseries/test_measures_portfolios.py test_semi_variance', gs_test_test_semi_variance().canonical, 'fin_gsq_test_test_semi_variance');
SELECT assert_eq('gs quant compatibility 1094 gs_quant/test/timeseries/test_measures_portfolios.py test_kurtosis', gs_test_test_kurtosis().canonical, 'fin_gsq_test_test_kurtosis');
SELECT assert_eq('gs quant compatibility 1095 gs_quant/test/timeseries/test_measures_portfolios.py test_skewness', gs_test_test_skewness().canonical, 'fin_gsq_test_test_skewness');
SELECT assert_eq('gs quant compatibility 1096 gs_quant/test/timeseries/test_measures_portfolios.py test_realized_var', gs_test_test_realized_var().canonical, 'fin_gsq_test_test_realized_var');
SELECT assert_eq('gs quant compatibility 1097 gs_quant/test/timeseries/test_measures_portfolios.py test_bad_date', gs_test_test_bad_date().canonical, 'fin_gsq_test_test_bad_date');
SELECT assert_eq('gs quant compatibility 1098 gs_quant/test/timeseries/test_measures_portfolios.py test_tracking_error', gs_test_test_tracking_error().canonical, 'fin_gsq_test_test_tracking_error');
SELECT assert_eq('gs quant compatibility 1099 gs_quant/test/timeseries/test_measures_portfolios.py test_tracking_error_bull', gs_test_test_tracking_error_bull().canonical, 'fin_gsq_test_test_tracking_error_bull');
SELECT assert_eq('gs quant compatibility 1100 gs_quant/test/timeseries/test_measures_portfolios.py test_tracking_error_bear', gs_test_test_tracking_error_bear().canonical, 'fin_gsq_test_test_tracking_error_bear');
SELECT assert_eq('gs quant compatibility 1101 gs_quant/test/timeseries/test_measures_portfolios.py test_sharpe_ratio', gs_test_test_sharpe_ratio_test_timeseries_test_meas_c9972596c1().canonical, 'fin_gsq_test_test_sharpe_ratio_test_timeseries_test_meas_c9972596c1');
SELECT assert_eq('gs quant compatibility 1102 gs_quant/test/timeseries/test_measures_portfolios.py test_calmar_ratio', gs_test_test_calmar_ratio().canonical, 'fin_gsq_test_test_calmar_ratio');
SELECT assert_eq('gs quant compatibility 1103 gs_quant/test/timeseries/test_measures_portfolios.py test_sortino_ratio', gs_test_test_sortino_ratio().canonical, 'fin_gsq_test_test_sortino_ratio');
SELECT assert_eq('gs quant compatibility 1104 gs_quant/test/timeseries/test_measures_portfolios.py test_sortino_ratio_index', gs_test_test_sortino_ratio_index().canonical, 'fin_gsq_test_test_sortino_ratio_index');
SELECT assert_eq('gs quant compatibility 1105 gs_quant/test/timeseries/test_measures_portfolios.py test_jensen_alpha', gs_test_test_jensen_alpha().canonical, 'fin_gsq_test_test_jensen_alpha');
SELECT assert_eq('gs quant compatibility 1106 gs_quant/test/timeseries/test_measures_portfolios.py test_jensen_bull', gs_test_test_jensen_bull().canonical, 'fin_gsq_test_test_jensen_bull');
SELECT assert_eq('gs quant compatibility 1107 gs_quant/test/timeseries/test_measures_portfolios.py test_jensen_alpha_bear', gs_test_test_jensen_alpha_bear().canonical, 'fin_gsq_test_test_jensen_alpha_bear');
SELECT assert_eq('gs quant compatibility 1108 gs_quant/test/timeseries/test_measures_portfolios.py test_information_ratio', gs_test_test_information_ratio().canonical, 'fin_gsq_test_test_information_ratio');
SELECT assert_eq('gs quant compatibility 1109 gs_quant/test/timeseries/test_measures_portfolios.py test_information_ratio_bull', gs_test_test_information_ratio_bull().canonical, 'fin_gsq_test_test_information_ratio_bull');
SELECT assert_eq('gs quant compatibility 1110 gs_quant/test/timeseries/test_measures_portfolios.py test_information_ratio_bear', gs_test_test_information_ratio_bear().canonical, 'fin_gsq_test_test_information_ratio_bear');
SELECT assert_eq('gs quant compatibility 1111 gs_quant/test/timeseries/test_measures_portfolios.py test_modigliani_ratio', gs_test_test_modigliani_ratio().canonical, 'fin_gsq_test_test_modigliani_ratio');
SELECT assert_eq('gs quant compatibility 1112 gs_quant/test/timeseries/test_measures_portfolios.py test_treynor_measure', gs_test_test_treynor_measure().canonical, 'fin_gsq_test_test_treynor_measure');
SELECT assert_eq('gs quant compatibility 1113 gs_quant/test/timeseries/test_measures_portfolios.py test_alpha', gs_test_test_alpha().canonical, 'fin_gsq_test_test_alpha');
SELECT assert_eq('gs quant compatibility 1114 gs_quant/test/timeseries/test_measures_portfolios.py test_beta', gs_test_test_beta_test_timeseries_test_meas_c9972596c1().canonical, 'fin_gsq_test_test_beta_test_timeseries_test_meas_c9972596c1');
SELECT assert_eq('gs quant compatibility 1115 gs_quant/test/timeseries/test_measures_portfolios.py test_correlation', gs_test_test_correlation_test_timeseries_test_meas_c9972596c1().canonical, 'fin_gsq_test_test_correlation_test_timeseries_test_meas_c9972596c1');
SELECT assert_eq('gs quant compatibility 1116 gs_quant/test/timeseries/test_measures_portfolios.py test_r_squared', gs_test_test_r_squared().canonical, 'fin_gsq_test_test_r_squared');
SELECT assert_eq('gs quant compatibility 1117 gs_quant/test/timeseries/test_measures_portfolios.py test_capture_ratio', gs_test_test_capture_ratio().canonical, 'fin_gsq_test_test_capture_ratio');
SELECT assert_eq('gs quant compatibility 1118 gs_quant/test/timeseries/test_measures_portfolios.py test_custom_aum', gs_test_test_custom_aum().canonical, 'fin_gsq_test_test_custom_aum');
SELECT assert_eq('gs quant compatibility 1119 gs_quant/test/timeseries/test_measures_rates.py test_parse_meeting_date', gs_test_test_parse_meeting_date().canonical, 'fin_gsq_test_test_parse_meeting_date');
SELECT assert_eq('gs quant compatibility 1120 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_floating_rate_option_returns_default', gs_test_test_get_swaption_parameter_floating_rate_option_returns_default().canonical, 'fin_gsq_test_test_get_swaption_parameter_floating_rate_option_returns_default');
SELECT assert_eq('gs quant compatibility 1121 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_floating_rate_option_returns_given_value', gs_test_test_get_swaption_parameter_floating_rate_option_returns_given_value().canonical, 'fin_gsq_test_test_get_swaption_parameter_floating_rate_option_returns_given_value');
SELECT assert_eq('gs quant compatibility 1122 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_strike_reference_option_returns_default', gs_test_test_get_swaption_parameter_strike_reference_option_returns_default().canonical, 'fin_gsq_test_test_get_swaption_parameter_strike_reference_option_returns_default');
SELECT assert_eq('gs quant compatibility 1123 gs_quant/test/timeseries/test_measures_rates.py test_get_swaption_parameter_strike_reference_option_returns_given_value', gs_test_test_get_swaption_parameter_strike_reference_option_returns_given_value().canonical, 'fin_gsq_test_test_get_swaption_parameter_strike_reference_option_returns_given_value');
SELECT assert_eq('gs quant compatibility 1124 gs_quant/test/timeseries/test_measures_rates.py test_get_floating_rate_option_for_benchmark_retuns_rate', gs_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_rates().canonical, 'fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_rates');
SELECT assert_eq('gs quant compatibility 1125 gs_quant/test/timeseries/test_measures_rates.py test_get_floating_rate_option_for_benchmark_retuns_rate_usd', gs_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_rates().canonical, 'fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_rates');
SELECT assert_eq('gs quant compatibility 1126 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string', gs_test_test_check_strike_reference_string().canonical, 'fin_gsq_test_test_check_strike_reference_string');
SELECT assert_eq('gs quant compatibility 1127 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_zero', gs_test_test_check_strike_reference_zero().canonical, 'fin_gsq_test_test_check_strike_reference_zero');
SELECT assert_eq('gs quant compatibility 1128 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_spot', gs_test_test_check_strike_reference_spot().canonical, 'fin_gsq_test_test_check_strike_reference_spot');
SELECT assert_eq('gs quant compatibility 1129 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string_positive', gs_test_test_check_strike_reference_string_positive().canonical, 'fin_gsq_test_test_check_strike_reference_string_positive');
SELECT assert_eq('gs quant compatibility 1130 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string_negtive', gs_test_test_check_strike_reference_string_negtive().canonical, 'fin_gsq_test_test_check_strike_reference_string_negtive');
SELECT assert_eq('gs quant compatibility 1131 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_string_fractional', gs_test_test_check_strike_reference_string_fractional().canonical, 'fin_gsq_test_test_check_strike_reference_string_fractional');
SELECT assert_eq('gs quant compatibility 1132 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_numeric_fractional', gs_test_test_check_strike_reference_numeric_fractional().canonical, 'fin_gsq_test_test_check_strike_reference_numeric_fractional');
SELECT assert_eq('gs quant compatibility 1133 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_numeric', gs_test_test_check_strike_reference_numeric().canonical, 'fin_gsq_test_test_check_strike_reference_numeric');
SELECT assert_eq('gs quant compatibility 1134 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_throws', gs_test_test_check_strike_reference_throws().canonical, 'fin_gsq_test_test_check_strike_reference_throws');
SELECT assert_eq('gs quant compatibility 1135 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_list', gs_test_test_check_strike_reference_list().canonical, 'fin_gsq_test_test_check_strike_reference_list');
SELECT assert_eq('gs quant compatibility 1136 gs_quant/test/timeseries/test_measures_rates.py test_check_strike_reference_invalid_list', gs_test_test_check_strike_reference_invalid_list().canonical, 'fin_gsq_test_test_check_strike_reference_invalid_list');
SELECT assert_eq('gs quant compatibility 1137 gs_quant/test/timeseries/test_measures_rates.py test_pricing_location_normalized', gs_test_test_pricing_location_normalized().canonical, 'fin_gsq_test_test_pricing_location_normalized');
SELECT assert_eq('gs quant compatibility 1138 gs_quant/test/timeseries/test_measures_rates.py test_default_pricing_location', gs_test_test_default_pricing_location().canonical, 'fin_gsq_test_test_default_pricing_location');
SELECT assert_eq('gs quant compatibility 1139 gs_quant/test/timeseries/test_measures_rates.py test_currency_to_tdapi_swaption_rate_asset_retuns_throws', gs_test_test_currency_to_tdapi_swaption_rate_asset_retuns_throws().canonical, 'fin_gsq_test_test_currency_to_tdapi_swaption_rate_asset_retuns_throws');
SELECT assert_eq('gs quant compatibility 1140 gs_quant/test/timeseries/test_measures_rates.py test_currency_to_tdapi_midcurve_asset', gs_test_test_currency_to_tdapi_midcurve_asset().canonical, 'fin_gsq_test_test_currency_to_tdapi_midcurve_asset');
SELECT assert_eq('gs quant compatibility 1141 gs_quant/test/timeseries/test_measures_rates.py test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id', gs_test_test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id().canonical, 'fin_gsq_test_test_currency_to_tdapi_swaption_rate_asset_retuns_asset_id');
SELECT assert_eq('gs quant compatibility 1142 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_throws_on_invalid_tenor', gs_test_test_swaption_build_asset_query_throws_on_invalid_tenor().canonical, 'fin_gsq_test_test_swaption_build_asset_query_throws_on_invalid_tenor');
SELECT assert_eq('gs quant compatibility 1143 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_usd', gs_test_test_swaption_build_asset_query_usd().canonical, 'fin_gsq_test_test_swaption_build_asset_query_usd');
SELECT assert_eq('gs quant compatibility 1144 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_strike_reference', gs_test_test_swaption_build_asset_query_strike_reference().canonical, 'fin_gsq_test_test_swaption_build_asset_query_strike_reference');
SELECT assert_eq('gs quant compatibility 1145 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_clearing_house', gs_test_test_swaption_build_asset_query_clearing_house().canonical, 'fin_gsq_test_test_swaption_build_asset_query_clearing_house');
SELECT assert_eq('gs quant compatibility 1146 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_custom', gs_test_test_swaption_build_asset_query_custom().canonical, 'fin_gsq_test_test_swaption_build_asset_query_custom');
SELECT assert_eq('gs quant compatibility 1147 gs_quant/test/timeseries/test_measures_rates.py test_swaption_build_asset_query_custom_throws', gs_test_test_swaption_build_asset_query_custom_throws().canonical, 'fin_gsq_test_test_swaption_build_asset_query_custom_throws');
SELECT assert_eq('gs quant compatibility 1148 gs_quant/test/timeseries/test_measures_rates.py test_swaption_swaption_vol_term2_returns_data', gs_test_test_swaption_swaption_vol_term2_returns_data().canonical, 'fin_gsq_test_test_swaption_swaption_vol_term2_returns_data');
SELECT assert_eq('gs quant compatibility 1149 gs_quant/test/timeseries/test_measures_rates.py test_swaption_swaption_vol_term2_returns_empty', gs_test_test_swaption_swaption_vol_term2_returns_empty().canonical, 'fin_gsq_test_test_swaption_swaption_vol_term2_returns_empty');
SELECT assert_eq('gs quant compatibility 1150 gs_quant/test/timeseries/test_measures_rates.py test_swaption_swaption_vol_term2_throws', gs_test_test_swaption_swaption_vol_term2_throws().canonical, 'fin_gsq_test_test_swaption_swaption_vol_term2_throws');
SELECT assert_eq('gs quant compatibility 1151 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol_smile2_returns_data', gs_test_test_swaption_vol_smile2_returns_data().canonical, 'fin_gsq_test_test_swaption_vol_smile2_returns_data');
SELECT assert_eq('gs quant compatibility 1152 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol_smile2_returns_no_data', gs_test_test_swaption_vol_smile2_returns_no_data().canonical, 'fin_gsq_test_test_swaption_vol_smile2_returns_no_data');
SELECT assert_eq('gs quant compatibility 1153 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol_smile2_returns_throws', gs_test_test_swaption_vol_smile2_returns_throws().canonical, 'fin_gsq_test_test_swaption_vol_smile2_returns_throws');
SELECT assert_eq('gs quant compatibility 1154 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol2_return_data', gs_test_test_swaption_vol2_return_data().canonical, 'fin_gsq_test_test_swaption_vol2_return_data');
SELECT assert_eq('gs quant compatibility 1155 gs_quant/test/timeseries/test_measures_rates.py test_swaption_vol2_return__empty_data', gs_test_test_swaption_vol2_return_empty_data().canonical, 'fin_gsq_test_test_swaption_vol2_return_empty_data');
SELECT assert_eq('gs quant compatibility 1156 gs_quant/test/timeseries/test_measures_rates.py test_swaption_annuity_return_data', gs_test_test_swaption_annuity_return_data().canonical, 'fin_gsq_test_test_swaption_annuity_return_data');
SELECT assert_eq('gs quant compatibility 1157 gs_quant/test/timeseries/test_measures_rates.py test_swaption_premium_return_data', gs_test_test_swaption_premium_return_data().canonical, 'fin_gsq_test_test_swaption_premium_return_data');
SELECT assert_eq('gs quant compatibility 1158 gs_quant/test/timeseries/test_measures_rates.py test_swaption_premium_throws_for_realtime', gs_test_test_swaption_premium_throws_for_realtime().canonical, 'fin_gsq_test_test_swaption_premium_throws_for_realtime');
SELECT assert_eq('gs quant compatibility 1159 gs_quant/test/timeseries/test_measures_rates.py test__check_forward_tenor_returns_None', gs_test_test_check_forward_tenor_returns_none().canonical, 'fin_gsq_test_test_check_forward_tenor_returns_none');
SELECT assert_eq('gs quant compatibility 1160 gs_quant/test/timeseries/test_measures_rates.py test__check_forward_tenor_returns_0b', gs_test_test_check_forward_tenor_returns_0b().canonical, 'fin_gsq_test_test_check_forward_tenor_returns_0b');
SELECT assert_eq('gs quant compatibility 1161 gs_quant/test/timeseries/test_measures_rates.py test_swaption_premium_throws_for_unsupported_ccy', gs_test_test_swaption_premium_throws_for_unsupported_ccy().canonical, 'fin_gsq_test_test_swaption_premium_throws_for_unsupported_ccy');
SELECT assert_eq('gs quant compatibility 1162 gs_quant/test/timeseries/test_measures_rates.py test_swaption_atmFwdRate_return_data', gs_test_test_swaption_atmfwdrate_return_data().canonical, 'fin_gsq_test_test_swaption_atmfwdrate_return_data');
SELECT assert_eq('gs quant compatibility 1163 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_atmFwdRate_return_data', gs_test_test_midcurve_atmfwdrate_return_data().canonical, 'fin_gsq_test_test_midcurve_atmfwdrate_return_data');
SELECT assert_eq('gs quant compatibility 1164 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_annuity_return_data', gs_test_test_midcurve_annuity_return_data().canonical, 'fin_gsq_test_test_midcurve_annuity_return_data');
SELECT assert_eq('gs quant compatibility 1165 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_premium_return_data', gs_test_test_midcurve_premium_return_data().canonical, 'fin_gsq_test_test_midcurve_premium_return_data');
SELECT assert_eq('gs quant compatibility 1166 gs_quant/test/timeseries/test_measures_rates.py test_midcurve_vol_return_data', gs_test_test_midcurve_vol_return_data().canonical, 'fin_gsq_test_test_midcurve_vol_return_data');
SELECT assert_eq('gs quant compatibility 1167 gs_quant/test/timeseries/test_measures_rates.py test_cross_to_fxfwd_xcswp_asset', gs_test_test_cross_to_fxfwd_xcswp_asset().canonical, 'fin_gsq_test_test_cross_to_fxfwd_xcswp_asset');
SELECT assert_eq('gs quant compatibility 1168 gs_quant/test/timeseries/test_measures_rates.py test_ois_fxfwd_xcswap_measures', gs_test_test_ois_fxfwd_xcswap_measures().canonical, 'fin_gsq_test_test_ois_fxfwd_xcswap_measures');
SELECT assert_eq('gs quant compatibility 1169 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_expectation_mocker', gs_test_get_data_policy_rate_expectation_mocker().canonical, 'fin_gsq_test_get_data_policy_rate_expectation_mocker');
SELECT assert_eq('gs quant compatibility 1170 gs_quant/test/timeseries/test_measures_rates.py mock_meeting_expectation', gs_test_mock_meeting_expectation().canonical, 'fin_gsq_test_mock_meeting_expectation');
SELECT assert_eq('gs quant compatibility 1171 gs_quant/test/timeseries/test_measures_rates.py mock_meeting_spot', gs_test_mock_meeting_spot().canonical, 'fin_gsq_test_mock_meeting_spot');
SELECT assert_eq('gs quant compatibility 1172 gs_quant/test/timeseries/test_measures_rates.py mock_meeting_absolute', gs_test_mock_meeting_absolute().canonical, 'fin_gsq_test_mock_meeting_absolute');
SELECT assert_eq('gs quant compatibility 1173 gs_quant/test/timeseries/test_measures_rates.py mock_ois_spot', gs_test_mock_ois_spot().canonical, 'fin_gsq_test_mock_ois_spot');
SELECT assert_eq('gs quant compatibility 1174 gs_quant/test/timeseries/test_measures_rates.py test_get_default_ois_benchmark', gs_test_test_get_default_ois_benchmark().canonical, 'fin_gsq_test_test_get_default_ois_benchmark');
SELECT assert_eq('gs quant compatibility 1175 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_term_structure', gs_test_test_policy_rate_term_structure().canonical, 'fin_gsq_test_test_policy_rate_term_structure');
SELECT assert_eq('gs quant compatibility 1176 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_expectation', gs_test_test_policy_rate_expectation().canonical, 'fin_gsq_test_test_policy_rate_expectation');
SELECT assert_eq('gs quant compatibility 1177 gs_quant/test/timeseries/test_measures_rates.py mock_policy_rt_spot', gs_test_mock_policy_rt_spot().canonical, 'fin_gsq_test_mock_policy_rt_spot');
SELECT assert_eq('gs quant compatibility 1178 gs_quant/test/timeseries/test_measures_rates.py mock_policy_rate_expectation_rt_meeting', gs_test_mock_policy_rate_expectation_rt_meeting().canonical, 'fin_gsq_test_mock_policy_rate_expectation_rt_meeting');
SELECT assert_eq('gs quant compatibility 1179 gs_quant/test/timeseries/test_measures_rates.py mock_policy_term_rt_meeting', gs_test_mock_policy_term_rt_meeting().canonical, 'fin_gsq_test_mock_policy_term_rt_meeting');
SELECT assert_eq('gs quant compatibility 1180 gs_quant/test/timeseries/test_measures_rates.py mock_policy_term_rt_meeting_series', gs_test_mock_policy_term_rt_meeting_series().canonical, 'fin_gsq_test_mock_policy_term_rt_meeting_series');
SELECT assert_eq('gs quant compatibility 1181 gs_quant/test/timeseries/test_measures_rates.py mock_policy_rate_empty_join_df', gs_test_mock_policy_rate_empty_join_df().canonical, 'fin_gsq_test_mock_policy_rate_empty_join_df');
SELECT assert_eq('gs quant compatibility 1182 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_term_rt_series_mocker', gs_test_get_data_policy_rate_term_rt_series_mocker().canonical, 'fin_gsq_test_get_data_policy_rate_term_rt_series_mocker');
SELECT assert_eq('gs quant compatibility 1183 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_term_rt_mocker', gs_test_get_data_policy_rate_term_rt_mocker().canonical, 'fin_gsq_test_get_data_policy_rate_term_rt_mocker');
SELECT assert_eq('gs quant compatibility 1184 gs_quant/test/timeseries/test_measures_rates.py get_data_empty_spot_mocker', gs_test_get_data_empty_spot_mocker().canonical, 'fin_gsq_test_get_data_empty_spot_mocker');
SELECT assert_eq('gs quant compatibility 1185 gs_quant/test/timeseries/test_measures_rates.py get_data_empty_join_mocker', gs_test_get_data_empty_join_mocker().canonical, 'fin_gsq_test_get_data_empty_join_mocker');
SELECT assert_eq('gs quant compatibility 1186 gs_quant/test/timeseries/test_measures_rates.py get_cb_swap_assets_mocker', gs_test_get_cb_swap_assets_mocker().canonical, 'fin_gsq_test_get_cb_swap_assets_mocker');
SELECT assert_eq('gs quant compatibility 1187 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_term_structure_rt', gs_test_test_policy_rate_term_structure_rt().canonical, 'fin_gsq_test_test_policy_rate_term_structure_rt');
SELECT assert_eq('gs quant compatibility 1188 gs_quant/test/timeseries/test_measures_rates.py get_data_policy_rate_exp_rt_mocker', gs_test_get_data_policy_rate_exp_rt_mocker().canonical, 'fin_gsq_test_get_data_policy_rate_exp_rt_mocker');
SELECT assert_eq('gs quant compatibility 1189 gs_quant/test/timeseries/test_measures_rates.py policy_exp_empty_spot_mocker', gs_test_policy_exp_empty_spot_mocker().canonical, 'fin_gsq_test_policy_exp_empty_spot_mocker');
SELECT assert_eq('gs quant compatibility 1190 gs_quant/test/timeseries/test_measures_rates.py test_get_swap_from_meeting_date', gs_test_test_get_swap_from_meeting_date().canonical, 'fin_gsq_test_test_get_swap_from_meeting_date');
SELECT assert_eq('gs quant compatibility 1191 gs_quant/test/timeseries/test_measures_rates.py test_policy_rate_expectation_rt', gs_test_test_policy_rate_expectation_rt().canonical, 'fin_gsq_test_test_policy_rate_expectation_rt');
SELECT assert_eq('gs quant compatibility 1192 gs_quant/test/timeseries/test_measures_rates.py test_get_cb_meeting_swap', gs_test_test_get_cb_meeting_swap().canonical, 'fin_gsq_test_test_get_cb_meeting_swap');
SELECT assert_eq('gs quant compatibility 1193 gs_quant/test/timeseries/test_measures_reports.py compute_geometric_aggregation_calculations', gs_test_compute_geometric_aggregation_calculations().canonical, 'fin_gsq_test_compute_geometric_aggregation_calculations');
SELECT assert_eq('gs quant compatibility 1194 gs_quant/test/timeseries/test_measures_reports.py mock_risk_model', gs_test_mock_risk_model_test_timeseries_test_meas_4f0965273f().canonical, 'fin_gsq_test_mock_risk_model_test_timeseries_test_meas_4f0965273f');
SELECT assert_eq('gs quant compatibility 1195 gs_quant/test/timeseries/test_measures_reports.py test_factor_exposure', gs_test_test_factor_exposure().canonical, 'fin_gsq_test_test_factor_exposure');
SELECT assert_eq('gs quant compatibility 1196 gs_quant/test/timeseries/test_measures_reports.py test_factor_exposure_percent', gs_test_test_factor_exposure_percent().canonical, 'fin_gsq_test_test_factor_exposure_percent');
SELECT assert_eq('gs quant compatibility 1197 gs_quant/test/timeseries/test_measures_reports.py test_factor_pnl', gs_test_test_factor_pnl().canonical, 'fin_gsq_test_test_factor_pnl');
SELECT assert_eq('gs quant compatibility 1198 gs_quant/test/timeseries/test_measures_reports.py test_factor_pnl_percent', gs_test_test_factor_pnl_percent().canonical, 'fin_gsq_test_test_factor_pnl_percent');
SELECT assert_eq('gs quant compatibility 1199 gs_quant/test/timeseries/test_measures_reports.py test_asset_factor_pnl_percent', gs_test_test_asset_factor_pnl_percent().canonical, 'fin_gsq_test_test_asset_factor_pnl_percent');
SELECT assert_eq('gs quant compatibility 1200 gs_quant/test/timeseries/test_measures_reports.py test_factor_proportion_of_risk', gs_test_test_factor_proportion_of_risk().canonical, 'fin_gsq_test_test_factor_proportion_of_risk');
SELECT assert_eq('gs quant compatibility 1201 gs_quant/test/timeseries/test_measures_reports.py test_get_factor_data', gs_test_test_get_factor_data().canonical, 'fin_gsq_test_test_get_factor_data');
SELECT assert_eq('gs quant compatibility 1202 gs_quant/test/timeseries/test_measures_reports.py test_aggregate_factor_support', gs_test_test_aggregate_factor_support_test_timeseries_test_meas_4f0965273f().canonical, 'fin_gsq_test_test_aggregate_factor_support_test_timeseries_test_meas_4f0965273f');
SELECT assert_eq('gs quant compatibility 1203 gs_quant/test/timeseries/test_measures_reports.py test_normalized_performance', gs_test_test_normalized_performance().canonical, 'fin_gsq_test_test_normalized_performance');
SELECT assert_eq('gs quant compatibility 1204 gs_quant/test/timeseries/test_measures_reports.py test_normalized_performance_short', gs_test_test_normalized_performance_short().canonical, 'fin_gsq_test_test_normalized_performance_short');
SELECT assert_eq('gs quant compatibility 1205 gs_quant/test/timeseries/test_measures_reports.py test_get_long_pnl', gs_test_test_get_long_pnl().canonical, 'fin_gsq_test_test_get_long_pnl');
SELECT assert_eq('gs quant compatibility 1206 gs_quant/test/timeseries/test_measures_reports.py test_get_short_pnl', gs_test_test_get_short_pnl().canonical, 'fin_gsq_test_test_get_short_pnl');
SELECT assert_eq('gs quant compatibility 1207 gs_quant/test/timeseries/test_measures_reports.py test_get_short_pnl_empty', gs_test_test_get_short_pnl_empty().canonical, 'fin_gsq_test_test_get_short_pnl_empty');
SELECT assert_eq('gs quant compatibility 1208 gs_quant/test/timeseries/test_measures_reports.py test_get_long_pnl_empty', gs_test_test_get_long_pnl_empty().canonical, 'fin_gsq_test_test_get_long_pnl_empty');
SELECT assert_eq('gs quant compatibility 1209 gs_quant/test/timeseries/test_measures_reports.py test_thematic_exposure', gs_test_test_thematic_exposure().canonical, 'fin_gsq_test_test_thematic_exposure');
SELECT assert_eq('gs quant compatibility 1210 gs_quant/test/timeseries/test_measures_reports.py test_thematic_beta', gs_test_test_thematic_beta().canonical, 'fin_gsq_test_test_thematic_beta');
SELECT assert_eq('gs quant compatibility 1211 gs_quant/test/timeseries/test_measures_reports.py test_aum', gs_test_test_aum().canonical, 'fin_gsq_test_test_aum');
SELECT assert_eq('gs quant compatibility 1212 gs_quant/test/timeseries/test_measures_reports.py test_pnl', gs_test_test_pnl().canonical, 'fin_gsq_test_test_pnl');
SELECT assert_eq('gs quant compatibility 1213 gs_quant/test/timeseries/test_measures_reports.py test_pnl_percent', gs_test_test_pnl_percent().canonical, 'fin_gsq_test_test_pnl_percent');
SELECT assert_eq('gs quant compatibility 1214 gs_quant/test/timeseries/test_measures_reports.py test_historical_simulation_estimated_pnl', gs_test_test_historical_simulation_estimated_pnl().canonical, 'fin_gsq_test_test_historical_simulation_estimated_pnl');
SELECT assert_eq('gs quant compatibility 1215 gs_quant/test/timeseries/test_measures_reports.py test_historical_simulation_estimated_factor_attribution', gs_test_test_historical_simulation_estimated_factor_attribution().canonical, 'fin_gsq_test_test_historical_simulation_estimated_factor_attribution');
SELECT assert_eq('gs quant compatibility 1216 gs_quant/test/timeseries/test_measures_risk_models.py mock_risk_model', gs_test_mock_risk_model_test_timeseries_test_meas_1c0c59ed9d().canonical, 'fin_gsq_test_mock_risk_model_test_timeseries_test_meas_1c0c59ed9d');
SELECT assert_eq('gs quant compatibility 1217 gs_quant/test/timeseries/test_measures_risk_models.py test_risk_model_measure', gs_test_test_risk_model_measure().canonical, 'fin_gsq_test_test_risk_model_measure');
SELECT assert_eq('gs quant compatibility 1218 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_zscore', gs_test_test_factor_zscore().canonical, 'fin_gsq_test_test_factor_zscore');
SELECT assert_eq('gs quant compatibility 1219 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_covariance', gs_test_test_factor_covariance().canonical, 'fin_gsq_test_test_factor_covariance');
SELECT assert_eq('gs quant compatibility 1220 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_volatility', gs_test_test_factor_volatility().canonical, 'fin_gsq_test_test_factor_volatility');
SELECT assert_eq('gs quant compatibility 1221 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_correlation', gs_test_test_factor_correlation().canonical, 'fin_gsq_test_test_factor_correlation');
SELECT assert_eq('gs quant compatibility 1222 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_performance', gs_test_test_factor_performance().canonical, 'fin_gsq_test_test_factor_performance');
SELECT assert_eq('gs quant compatibility 1223 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_returns_intraday', gs_test_test_factor_returns_intraday().canonical, 'fin_gsq_test_test_factor_returns_intraday');
SELECT assert_eq('gs quant compatibility 1224 gs_quant/test/timeseries/test_measures_risk_models.py test_factor_returns_percentile', gs_test_test_factor_returns_percentile().canonical, 'fin_gsq_test_test_factor_returns_percentile');
SELECT assert_eq('gs quant compatibility 1225 gs_quant/test/timeseries/test_measures_xccy.py test_get_floating_rate_option_for_benchmark_retuns_rate', gs_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_xccy().canonical, 'fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_test_timeseries_test_measures_xccy');
SELECT assert_eq('gs quant compatibility 1226 gs_quant/test/timeseries/test_measures_xccy.py test_get_floating_rate_option_for_benchmark_retuns_rate_usd', gs_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_xccy().canonical, 'fin_gsq_test_test_get_floating_rate_option_for_benchmark_retuns_rate_usd_test_timeseries_test_measures_xccy');
SELECT assert_eq('gs quant compatibility 1227 gs_quant/test/timeseries/test_measures_xccy.py test_currency_to_tdapi_xccy_swap_rate_asset', gs_test_test_currency_to_tdapi_xccy_swap_rate_asset().canonical, 'fin_gsq_test_test_currency_to_tdapi_xccy_swap_rate_asset');
SELECT assert_eq('gs quant compatibility 1228 gs_quant/test/timeseries/test_measures_xccy.py test_get_crosscurrency_swap_leg_defaults', gs_test_test_get_crosscurrency_swap_leg_defaults().canonical, 'fin_gsq_test_test_get_crosscurrency_swap_leg_defaults');
SELECT assert_eq('gs quant compatibility 1229 gs_quant/test/timeseries/test_measures_xccy.py test_get_crosscurrency_swap_csa_terms', gs_test_test_get_crosscurrency_swap_csa_terms().canonical, 'fin_gsq_test_test_get_crosscurrency_swap_csa_terms');
SELECT assert_eq('gs quant compatibility 1230 gs_quant/test/timeseries/test_measures_xccy.py test_check_valid_indices', gs_test_test_check_valid_indices_test_timeseries_test_measures_xccy().canonical, 'fin_gsq_test_test_check_valid_indices_test_timeseries_test_measures_xccy');
SELECT assert_eq('gs quant compatibility 1231 gs_quant/test/timeseries/test_measures_xccy.py test_get_tdapi_crosscurrency_rates_assets', gs_test_test_get_tdapi_crosscurrency_rates_assets().canonical, 'fin_gsq_test_test_get_tdapi_crosscurrency_rates_assets');
SELECT assert_eq('gs quant compatibility 1232 gs_quant/test/timeseries/test_measures_xccy.py mock_curr', gs_test_mock_curr_test_timeseries_test_measures_xccy().canonical, 'fin_gsq_test_mock_curr_test_timeseries_test_measures_xccy');
SELECT assert_eq('gs quant compatibility 1233 gs_quant/test/timeseries/test_measures_xccy.py test_crosscurrency_swap_rate', gs_test_test_crosscurrency_swap_rate().canonical, 'fin_gsq_test_test_crosscurrency_swap_rate');
SELECT assert_eq('gs quant compatibility 1234 gs_quant/test/timeseries/test_rolling.py test_rolling_date_offset', gs_test_test_rolling_date_offset().canonical, 'fin_gsq_test_test_rolling_date_offset');
SELECT assert_eq('gs quant compatibility 1235 gs_quant/test/timeseries/test_statistics.py test_generate_series', gs_test_test_generate_series().canonical, 'fin_gsq_test_test_generate_series');
SELECT assert_eq('gs quant compatibility 1236 gs_quant/test/timeseries/test_statistics.py test_generate_series_intraday', gs_test_test_generate_series_intraday().canonical, 'fin_gsq_test_test_generate_series_intraday');
SELECT assert_eq('gs quant compatibility 1237 gs_quant/test/timeseries/test_statistics.py test_min', gs_test_test_min().canonical, 'fin_gsq_test_test_min');
SELECT assert_eq('gs quant compatibility 1238 gs_quant/test/timeseries/test_statistics.py test_max', gs_test_test_max().canonical, 'fin_gsq_test_test_max');
SELECT assert_eq('gs quant compatibility 1239 gs_quant/test/timeseries/test_statistics.py test_range', gs_test_test_range().canonical, 'fin_gsq_test_test_range');
SELECT assert_eq('gs quant compatibility 1240 gs_quant/test/timeseries/test_statistics.py test_mean', gs_test_test_mean().canonical, 'fin_gsq_test_test_mean');
SELECT assert_eq('gs quant compatibility 1241 gs_quant/test/timeseries/test_statistics.py test_quadratic_mean', gs_test_test_quadratic_mean().canonical, 'fin_gsq_test_test_quadratic_mean');
SELECT assert_eq('gs quant compatibility 1242 gs_quant/test/timeseries/test_statistics.py test_median', gs_test_test_median().canonical, 'fin_gsq_test_test_median');
SELECT assert_eq('gs quant compatibility 1243 gs_quant/test/timeseries/test_statistics.py test_mode', gs_test_test_mode().canonical, 'fin_gsq_test_test_mode');
SELECT assert_eq('gs quant compatibility 1244 gs_quant/test/timeseries/test_statistics.py test_sum', gs_test_test_sum().canonical, 'fin_gsq_test_test_sum');
SELECT assert_eq('gs quant compatibility 1245 gs_quant/test/timeseries/test_statistics.py test_product', gs_test_test_product().canonical, 'fin_gsq_test_test_product');
SELECT assert_eq('gs quant compatibility 1246 gs_quant/test/timeseries/test_statistics.py test_std', gs_test_test_std().canonical, 'fin_gsq_test_test_std');
SELECT assert_eq('gs quant compatibility 1247 gs_quant/test/timeseries/test_statistics.py test_exponential_std', gs_test_test_exponential_std().canonical, 'fin_gsq_test_test_exponential_std');
SELECT assert_eq('gs quant compatibility 1248 gs_quant/test/timeseries/test_statistics.py test_var', gs_test_test_var().canonical, 'fin_gsq_test_test_var');
SELECT assert_eq('gs quant compatibility 1249 gs_quant/test/timeseries/test_statistics.py test_cov', gs_test_test_cov().canonical, 'fin_gsq_test_test_cov');
SELECT assert_eq('gs quant compatibility 1250 gs_quant/test/timeseries/test_statistics.py test_zscores', gs_test_test_zscores().canonical, 'fin_gsq_test_test_zscores');
SELECT assert_eq('gs quant compatibility 1251 gs_quant/test/timeseries/test_statistics.py test_winsorize', gs_test_test_winsorize().canonical, 'fin_gsq_test_test_winsorize');
SELECT assert_eq('gs quant compatibility 1252 gs_quant/test/timeseries/test_statistics.py test_percentiles', gs_test_test_percentiles().canonical, 'fin_gsq_test_test_percentiles');
SELECT assert_eq('gs quant compatibility 1253 gs_quant/test/timeseries/test_statistics.py test_percentile', gs_test_test_percentile().canonical, 'fin_gsq_test_test_percentile');
SELECT assert_eq('gs quant compatibility 1254 gs_quant/test/timeseries/test_statistics.py test_percentile_str', gs_test_test_percentile_str().canonical, 'fin_gsq_test_test_percentile_str');
SELECT assert_eq('gs quant compatibility 1255 gs_quant/test/timeseries/test_statistics.py test_regression', gs_test_test_regression().canonical, 'fin_gsq_test_test_regression');
SELECT assert_eq('gs quant compatibility 1256 gs_quant/test/timeseries/test_statistics.py test_rolling_linear_regression', gs_test_test_rolling_linear_regression().canonical, 'fin_gsq_test_test_rolling_linear_regression');
SELECT assert_eq('gs quant compatibility 1257 gs_quant/test/timeseries/test_statistics.py test_sir_model', gs_test_test_sir_model().canonical, 'fin_gsq_test_test_sir_model');
SELECT assert_eq('gs quant compatibility 1258 gs_quant/test/timeseries/test_statistics.py test_seir_model', gs_test_test_seir_model().canonical, 'fin_gsq_test_test_seir_model');
SELECT assert_eq('gs quant compatibility 1259 gs_quant/test/timeseries/test_tca.py test_covariance', gs_test_test_covariance().canonical, 'fin_gsq_test_test_covariance');
SELECT assert_eq('gs quant compatibility 1260 gs_quant/test/timeseries/test_technicals.py test_moving_average', gs_test_test_moving_average().canonical, 'fin_gsq_test_test_moving_average');
SELECT assert_eq('gs quant compatibility 1261 gs_quant/test/timeseries/test_technicals.py test_smoothed_moving_average', gs_test_test_smoothed_moving_average().canonical, 'fin_gsq_test_test_smoothed_moving_average');
SELECT assert_eq('gs quant compatibility 1262 gs_quant/test/timeseries/test_technicals.py test_macd', gs_test_test_macd().canonical, 'fin_gsq_test_test_macd');
SELECT assert_eq('gs quant compatibility 1263 gs_quant/test/timeseries/test_technicals.py test_bollinger_bands', gs_test_test_bollinger_bands().canonical, 'fin_gsq_test_test_bollinger_bands');
SELECT assert_eq('gs quant compatibility 1264 gs_quant/test/timeseries/test_technicals.py test_relative_strength_index', gs_test_test_relative_strength_index().canonical, 'fin_gsq_test_test_relative_strength_index');
SELECT assert_eq('gs quant compatibility 1265 gs_quant/test/timeseries/test_technicals.py test_exponential_moving_average', gs_test_test_exponential_moving_average().canonical, 'fin_gsq_test_test_exponential_moving_average');
SELECT assert_eq('gs quant compatibility 1266 gs_quant/test/timeseries/test_technicals.py test_exponential_volatility', gs_test_test_exponential_volatility().canonical, 'fin_gsq_test_test_exponential_volatility');
SELECT assert_eq('gs quant compatibility 1267 gs_quant/test/timeseries/test_technicals.py test_exponential_spread_volatility', gs_test_test_exponential_spread_volatility().canonical, 'fin_gsq_test_test_exponential_spread_volatility');
SELECT assert_eq('gs quant compatibility 1268 gs_quant/test/timeseries/test_technicals.py test_trend', gs_test_test_trend().canonical, 'fin_gsq_test_test_trend');
SELECT assert_eq('gs quant compatibility 1269 gs_quant/test/timeseries/test_technicals.py test_seasonality_adjusted', gs_test_test_seasonality_adjusted().canonical, 'fin_gsq_test_test_seasonality_adjusted');
SELECT assert_eq('gs quant compatibility 1270 gs_quant/test/timeseries/test_timeseries.py ts_map', gs_test_ts_map().canonical, 'fin_gsq_test_ts_map');
SELECT assert_eq('gs quant compatibility 1271 gs_quant/test/timeseries/test_timeseries.py test_have_docstrings', gs_test_test_have_docstrings().canonical, 'fin_gsq_test_test_have_docstrings');
SELECT assert_eq('gs quant compatibility 1272 gs_quant/test/timeseries/test_timeseries.py test_window_to_from_dict', gs_test_test_window_to_from_dict().canonical, 'fin_gsq_test_test_window_to_from_dict');
SELECT assert_eq('gs quant compatibility 1273 gs_quant/test/timeseries/test_timeseries.py test_docstrings', gs_test_test_docstrings().canonical, 'fin_gsq_test_test_docstrings');
SELECT assert_eq('gs quant compatibility 1274 gs_quant/test/timeseries/test_timeseries.py test_annotations', gs_test_test_annotations().canonical, 'fin_gsq_test_test_annotations');
SELECT assert_eq('gs quant compatibility 1275 gs_quant/test/timeseries/test_timeseries.py test_measures', gs_test_test_measures().canonical, 'fin_gsq_test_test_measures');
SELECT assert_eq('gs quant compatibility 1276 gs_quant/test/timeseries/test_timeseries.py test_measures_on_entities', gs_test_test_measures_on_entities().canonical, 'fin_gsq_test_test_measures_on_entities');
SELECT assert_eq('gs quant compatibility 1277 gs_quant/test/timeseries/utils.py handle_response', gs_test_handle_response().canonical, 'fin_gsq_test_handle_response');
SELECT assert_eq('gs quant compatibility 1278 gs_quant/test/timeseries/utils.py mock_request', gs_test_mock_request().canonical, 'fin_gsq_test_mock_request');
SELECT assert_eq('gs quant compatibility 1279 gs_quant/test/tracing/test_tracing.py make_zero_duration', gs_test_make_zero_duration().canonical, 'fin_gsq_test_make_zero_duration');
SELECT assert_eq('gs quant compatibility 1280 gs_quant/test/tracing/test_tracing.py test_tracer_tags', gs_test_test_tracer_tags().canonical, 'fin_gsq_test_test_tracer_tags');
SELECT assert_eq('gs quant compatibility 1281 gs_quant/test/tracing/test_tracing.py test_tracer_events', gs_test_test_tracer_events().canonical, 'fin_gsq_test_test_tracer_events');
SELECT assert_eq('gs quant compatibility 1282 gs_quant/test/tracing/test_tracing.py test_tracer_print', gs_test_test_tracer_print().canonical, 'fin_gsq_test_test_tracer_print');
SELECT assert_eq('gs quant compatibility 1283 gs_quant/test/tracing/test_tracing.py test_tracer_plot', gs_test_test_tracer_plot().canonical, 'fin_gsq_test_test_tracer_plot');
SELECT assert_eq('gs quant compatibility 1284 gs_quant/test/tracing/test_tracing.py test_gather_when_multi_traces', gs_test_test_gather_when_multi_traces().canonical, 'fin_gsq_test_test_gather_when_multi_traces');
SELECT assert_eq('gs quant compatibility 1285 gs_quant/test/tracing/test_tracing.py test_tracer_wrapped_error', gs_test_test_tracer_wrapped_error().canonical, 'fin_gsq_test_test_tracer_wrapped_error');
SELECT assert_eq('gs quant compatibility 1286 gs_quant/test/tracing/test_tracing.py test_active_span', gs_test_test_active_span().canonical, 'fin_gsq_test_test_active_span');
SELECT assert_eq('gs quant compatibility 1287 gs_quant/test/tracing/test_tracing.py test_span_activation', gs_test_test_span_activation().canonical, 'fin_gsq_test_test_span_activation');
SELECT assert_eq('gs quant compatibility 1288 gs_quant/test/tracing/test_tracing.py test_inject_extract', gs_test_test_inject_extract().canonical, 'fin_gsq_test_test_inject_extract');
SELECT assert_eq('gs quant compatibility 1289 gs_quant/test/tracing/test_tracing.py test_ignore_active_span', gs_test_test_ignore_active_span().canonical, 'fin_gsq_test_test_ignore_active_span');
SELECT assert_eq('gs quant compatibility 1290 gs_quant/test/tracing/test_tracing.py test_callback_in_scope', gs_test_test_callback_in_scope().canonical, 'fin_gsq_test_test_callback_in_scope');
SELECT assert_eq('gs quant compatibility 1291 gs_quant/test/utils/datagrid_test_utils.py get_test_entity', gs_test_get_test_entity().canonical, 'fin_gsq_test_get_test_entity');
SELECT assert_eq('gs quant compatibility 1292 gs_quant/test/utils/mock_calc.py get_risk_request_id', gs_test_get_risk_request_id().canonical, 'fin_gsq_test_get_risk_request_id');
SELECT assert_eq('gs quant compatibility 1293 gs_quant/test/utils/test_utils.py test_fix_mock_data', gs_test_test_fix_mock_data().canonical, 'fin_gsq_test_test_fix_mock_data');
SELECT assert_eq('gs quant compatibility 1294 gs_quant/test/utils/test_utils.py test_mock_data_file_sanity', gs_test_test_mock_data_file_sanity().canonical, 'fin_gsq_test_test_mock_data_file_sanity');
SELECT assert_eq('gs quant compatibility 1295 gs_quant/test/utils/test_utils.py load_json_from_resource', gs_test_load_json_from_resource().canonical, 'fin_gsq_test_load_json_from_resource');
SELECT assert_eq('gs quant compatibility 1296 gs_quant/test/utils/test_utils.py mock_request', gs_test_mock_request_test_utils_test_utils().canonical, 'fin_gsq_test_mock_request_test_utils_test_utils');
SELECT assert_eq('gs quant compatibility 1297 gs_quant/timeseries/algebra.py add', gs_timeseries_add().canonical, 'fin_add');
SELECT assert_eq('gs quant compatibility 1298 gs_quant/timeseries/algebra.py subtract', gs_timeseries_subtract().canonical, 'fin_subtract');
SELECT assert_eq('gs quant compatibility 1299 gs_quant/timeseries/algebra.py multiply', gs_timeseries_multiply().canonical, 'fin_multiply');
SELECT assert_eq('gs quant compatibility 1300 gs_quant/timeseries/algebra.py divide', gs_timeseries_divide().canonical, 'fin_divide');
SELECT assert_eq('gs quant compatibility 1301 gs_quant/timeseries/algebra.py floordiv', gs_timeseries_floordiv().canonical, 'fin_floordiv');
SELECT assert_eq('gs quant compatibility 1302 gs_quant/timeseries/algebra.py exp', gs_timeseries_exp().canonical, 'fin_exp');
SELECT assert_eq('gs quant compatibility 1303 gs_quant/timeseries/algebra.py log', gs_timeseries_log().canonical, 'fin_log');
SELECT assert_eq('gs quant compatibility 1304 gs_quant/timeseries/algebra.py power', gs_timeseries_power().canonical, 'fin_power');
SELECT assert_eq('gs quant compatibility 1305 gs_quant/timeseries/algebra.py sqrt', gs_timeseries_sqrt().canonical, 'fin_sqrt');
SELECT assert_eq('gs quant compatibility 1306 gs_quant/timeseries/algebra.py abs_', gs_timeseries_abs().canonical, 'fin_abs_');
SELECT assert_eq('gs quant compatibility 1307 gs_quant/timeseries/algebra.py floor', gs_timeseries_floor().canonical, 'fin_floor');
SELECT assert_eq('gs quant compatibility 1308 gs_quant/timeseries/algebra.py ceil', gs_timeseries_ceil().canonical, 'fin_ceil');
SELECT assert_eq('gs quant compatibility 1309 gs_quant/timeseries/algebra.py filter_', gs_timeseries_filter().canonical, 'fin_filter_');
SELECT assert_eq('gs quant compatibility 1310 gs_quant/timeseries/algebra.py filter_dates', gs_timeseries_filter_dates().canonical, 'fin_filter_dates');
SELECT assert_eq('gs quant compatibility 1311 gs_quant/timeseries/algebra.py and_', gs_timeseries_and().canonical, 'fin_and_');
SELECT assert_eq('gs quant compatibility 1312 gs_quant/timeseries/algebra.py or_', gs_timeseries_or().canonical, 'fin_or_');
SELECT assert_eq('gs quant compatibility 1313 gs_quant/timeseries/algebra.py not_', gs_timeseries_not().canonical, 'fin_not_');
SELECT assert_eq('gs quant compatibility 1314 gs_quant/timeseries/algebra.py if_', gs_timeseries_if().canonical, 'fin_if_');
SELECT assert_eq('gs quant compatibility 1315 gs_quant/timeseries/algebra.py weighted_sum', gs_timeseries_weighted_sum().canonical, 'fin_weighted_sum');
SELECT assert_eq('gs quant compatibility 1316 gs_quant/timeseries/algebra.py geometrically_aggregate', gs_timeseries_geometrically_aggregate().canonical, 'fin_geometrically_aggregate');
SELECT assert_eq('gs quant compatibility 1317 gs_quant/timeseries/analysis.py smooth_spikes', gs_timeseries_smooth_spikes().canonical, 'fin_smooth_spikes');
SELECT assert_eq('gs quant compatibility 1318 gs_quant/timeseries/analysis.py smooth_outliers', gs_timeseries_smooth_outliers().canonical, 'fin_smooth_outliers');
SELECT assert_eq('gs quant compatibility 1319 gs_quant/timeseries/analysis.py repeat', gs_timeseries_repeat().canonical, 'fin_repeat');
SELECT assert_eq('gs quant compatibility 1320 gs_quant/timeseries/analysis.py first', gs_timeseries_first().canonical, 'fin_first');
SELECT assert_eq('gs quant compatibility 1321 gs_quant/timeseries/analysis.py last', gs_timeseries_last().canonical, 'fin_last');
SELECT assert_eq('gs quant compatibility 1322 gs_quant/timeseries/analysis.py last_value', gs_timeseries_last_value().canonical, 'fin_last_value');
SELECT assert_eq('gs quant compatibility 1323 gs_quant/timeseries/analysis.py count', gs_timeseries_count().canonical, 'fin_count');
SELECT assert_eq('gs quant compatibility 1324 gs_quant/timeseries/analysis.py diff', gs_timeseries_diff().canonical, 'fin_diff');
SELECT assert_eq('gs quant compatibility 1325 gs_quant/timeseries/analysis.py compare', gs_timeseries_compare().canonical, 'fin_compare');
SELECT assert_eq('gs quant compatibility 1326 gs_quant/timeseries/analysis.py lag', gs_timeseries_lag().canonical, 'fin_lag');
SELECT assert_eq('gs quant compatibility 1327 gs_quant/timeseries/analysis.py consecutive', gs_timeseries_consecutive().canonical, 'fin_consecutive');
SELECT assert_eq('gs quant compatibility 1328 gs_quant/timeseries/backtesting.py backtest_basket', gs_timeseries_backtest_basket().canonical, 'fin_gsq_timeseries_backtest_basket');
SELECT assert_eq('gs quant compatibility 1329 gs_quant/timeseries/backtesting.py basket_series', gs_timeseries_basket_series().canonical, 'fin_basket_series');
SELECT assert_eq('gs quant compatibility 1330 gs_quant/timeseries/datetime.py align', gs_timeseries_align().canonical, 'fin_align');
SELECT assert_eq('gs quant compatibility 1331 gs_quant/timeseries/datetime.py interpolate', gs_timeseries_interpolate().canonical, 'fin_interpolate');
SELECT assert_eq('gs quant compatibility 1332 gs_quant/timeseries/datetime.py value', gs_timeseries_value().canonical, 'fin_value');
SELECT assert_eq('gs quant compatibility 1333 gs_quant/timeseries/datetime.py day', gs_timeseries_day().canonical, 'fin_day');
SELECT assert_eq('gs quant compatibility 1334 gs_quant/timeseries/datetime.py month', gs_timeseries_month().canonical, 'fin_month');
SELECT assert_eq('gs quant compatibility 1335 gs_quant/timeseries/datetime.py year', gs_timeseries_year().canonical, 'fin_year');
SELECT assert_eq('gs quant compatibility 1336 gs_quant/timeseries/datetime.py quarter', gs_timeseries_quarter().canonical, 'fin_quarter');
SELECT assert_eq('gs quant compatibility 1337 gs_quant/timeseries/datetime.py weekday', gs_timeseries_weekday().canonical, 'fin_weekday');
SELECT assert_eq('gs quant compatibility 1338 gs_quant/timeseries/datetime.py day_count_fractions', gs_timeseries_day_count_fractions().canonical, 'fin_day_count_fractions');
SELECT assert_eq('gs quant compatibility 1339 gs_quant/timeseries/datetime.py date_range', gs_timeseries_date_range().canonical, 'fin_date_range');
SELECT assert_eq('gs quant compatibility 1340 gs_quant/timeseries/datetime.py append', gs_timeseries_append().canonical, 'fin_append');
SELECT assert_eq('gs quant compatibility 1341 gs_quant/timeseries/datetime.py prepend', gs_timeseries_prepend().canonical, 'fin_prepend');
SELECT assert_eq('gs quant compatibility 1342 gs_quant/timeseries/datetime.py union', gs_timeseries_union().canonical, 'fin_union');
SELECT assert_eq('gs quant compatibility 1343 gs_quant/timeseries/datetime.py bucketize', gs_timeseries_bucketize().canonical, 'fin_bucketize');
SELECT assert_eq('gs quant compatibility 1344 gs_quant/timeseries/datetime.py day_count', gs_timeseries_day_count().canonical, 'fin_day_count');
SELECT assert_eq('gs quant compatibility 1345 gs_quant/timeseries/datetime.py day_countdown', gs_timeseries_day_countdown().canonical, 'fin_day_countdown');
SELECT assert_eq('gs quant compatibility 1346 gs_quant/timeseries/datetime.py align_calendar', gs_timeseries_align_calendar().canonical, 'fin_align_calendar');
SELECT assert_eq('gs quant compatibility 1347 gs_quant/timeseries/econometrics.py excess_returns_pure', gs_timeseries_excess_returns_pure().canonical, 'fin_gsq_timeseries_excess_returns_pure');
SELECT assert_eq('gs quant compatibility 1348 gs_quant/timeseries/econometrics.py excess_returns', gs_timeseries_excess_returns().canonical, 'fin_gsq_timeseries_excess_returns');
SELECT assert_eq('gs quant compatibility 1349 gs_quant/timeseries/econometrics.py get_ratio_pure', gs_timeseries_get_ratio_pure().canonical, 'fin_gsq_timeseries_get_ratio_pure');
SELECT assert_eq('gs quant compatibility 1350 gs_quant/timeseries/econometrics.py excess_returns_', gs_timeseries_excess_returns_timeseries_econometrics().canonical, 'fin_gsq_timeseries_excess_returns_timeseries_econometrics');
SELECT assert_eq('gs quant compatibility 1351 gs_quant/timeseries/econometrics.py sharpe_ratio', gs_timeseries_sharpe_ratio().canonical, 'fin_gsq_timeseries_sharpe_ratio');
SELECT assert_eq('gs quant compatibility 1352 gs_quant/timeseries/econometrics.py returns', gs_timeseries_returns().canonical, 'fin_returns');
SELECT assert_eq('gs quant compatibility 1353 gs_quant/timeseries/econometrics.py prices', gs_timeseries_prices().canonical, 'fin_prices');
SELECT assert_eq('gs quant compatibility 1354 gs_quant/timeseries/econometrics.py index', gs_timeseries_index().canonical, 'fin_index');
SELECT assert_eq('gs quant compatibility 1355 gs_quant/timeseries/econometrics.py change', gs_timeseries_change().canonical, 'fin_change');
SELECT assert_eq('gs quant compatibility 1356 gs_quant/timeseries/econometrics.py annualize', gs_timeseries_annualize().canonical, 'fin_annualize');
SELECT assert_eq('gs quant compatibility 1357 gs_quant/timeseries/econometrics.py volatility', gs_timeseries_volatility().canonical, 'fin_volatility');
SELECT assert_eq('gs quant compatibility 1358 gs_quant/timeseries/econometrics.py vol_swap_volatility', gs_timeseries_vol_swap_volatility().canonical, 'fin_vol_swap_volatility');
SELECT assert_eq('gs quant compatibility 1359 gs_quant/timeseries/econometrics.py correlation', gs_timeseries_correlation().canonical, 'fin_correlation');
SELECT assert_eq('gs quant compatibility 1360 gs_quant/timeseries/econometrics.py corr_swap_correlation', gs_timeseries_corr_swap_correlation().canonical, 'fin_corr_swap_correlation');
SELECT assert_eq('gs quant compatibility 1361 gs_quant/timeseries/econometrics.py beta', gs_timeseries_beta().canonical, 'fin_beta');
SELECT assert_eq('gs quant compatibility 1362 gs_quant/timeseries/econometrics.py max_drawdown', gs_timeseries_max_drawdown().canonical, 'fin_max_drawdown');
SELECT assert_eq('gs quant compatibility 1363 gs_quant/timeseries/helper.py apply_ramp', gs_timeseries_apply_ramp().canonical, 'fin_gsq_timeseries_apply_ramp');
SELECT assert_eq('gs quant compatibility 1364 gs_quant/timeseries/helper.py normalize_window', gs_timeseries_normalize_window().canonical, 'fin_gsq_timeseries_normalize_window');
SELECT assert_eq('gs quant compatibility 1365 gs_quant/timeseries/helper.py plot_function', gs_timeseries_plot_function().canonical, 'fin_gsq_timeseries_plot_function');
SELECT assert_eq('gs quant compatibility 1366 gs_quant/timeseries/helper.py plot_session_function', gs_timeseries_plot_session_function().canonical, 'fin_gsq_timeseries_plot_session_function');
SELECT assert_eq('gs quant compatibility 1367 gs_quant/timeseries/helper.py check_forward_looking', gs_timeseries_check_forward_looking().canonical, 'fin_gsq_timeseries_check_forward_looking');
SELECT assert_eq('gs quant compatibility 1368 gs_quant/timeseries/helper.py plot_measure', gs_timeseries_plot_measure().canonical, 'fin_gsq_timeseries_plot_measure');
SELECT assert_eq('gs quant compatibility 1369 gs_quant/timeseries/helper.py plot_measure_entity', gs_timeseries_plot_measure_entity().canonical, 'fin_gsq_timeseries_plot_measure_entity');
SELECT assert_eq('gs quant compatibility 1370 gs_quant/timeseries/helper.py requires_session', gs_timeseries_requires_session().canonical, 'fin_gsq_timeseries_requires_session');
SELECT assert_eq('gs quant compatibility 1371 gs_quant/timeseries/helper.py plot_method', gs_timeseries_plot_method().canonical, 'fin_gsq_timeseries_plot_method');
SELECT assert_eq('gs quant compatibility 1372 gs_quant/timeseries/helper.py log_return', gs_timeseries_log_return().canonical, 'fin_log_return');
SELECT assert_eq('gs quant compatibility 1373 gs_quant/timeseries/helper.py get_df_with_retries', gs_timeseries_get_df_with_retries().canonical, 'fin_gsq_timeseries_get_df_with_retries');
SELECT assert_eq('gs quant compatibility 1374 gs_quant/timeseries/helper.py get_dataset_data_with_retries', gs_timeseries_get_dataset_data_with_retries().canonical, 'fin_gsq_timeseries_get_dataset_data_with_retries');
SELECT assert_eq('gs quant compatibility 1375 gs_quant/timeseries/helper.py get_dataset_with_many_assets', gs_timeseries_get_dataset_with_many_assets().canonical, 'fin_gsq_timeseries_get_dataset_with_many_assets');
SELECT assert_eq('gs quant compatibility 1376 gs_quant/timeseries/helper.py rolling_offset', gs_timeseries_rolling_offset().canonical, 'fin_gsq_timeseries_rolling_offset');
SELECT assert_eq('gs quant compatibility 1377 gs_quant/timeseries/measure_registry.py register_measure', gs_timeseries_register_measure().canonical, 'fin_gsq_timeseries_register_measure');
SELECT assert_eq('gs quant compatibility 1378 gs_quant/timeseries/measures.py cross_stored_direction_for_fx_vol', gs_timeseries_cross_stored_direction_for_fx_vol().canonical, 'fin_gsq_timeseries_cross_stored_direction_for_fx_vol');
SELECT assert_eq('gs quant compatibility 1379 gs_quant/timeseries/measures.py cross_to_usd_based_cross', gs_timeseries_cross_to_usd_based_cross().canonical, 'fin_gsq_timeseries_cross_to_usd_based_cross');
SELECT assert_eq('gs quant compatibility 1380 gs_quant/timeseries/measures.py currency_to_default_benchmark_rate', gs_timeseries_currency_to_default_benchmark_rate().canonical, 'fin_gsq_timeseries_currency_to_default_benchmark_rate');
SELECT assert_eq('gs quant compatibility 1381 gs_quant/timeseries/measures.py currency_to_default_ois_asset', gs_timeseries_currency_to_default_ois_asset().canonical, 'fin_gsq_timeseries_currency_to_default_ois_asset');
SELECT assert_eq('gs quant compatibility 1382 gs_quant/timeseries/measures.py currency_to_default_swap_rate_asset', gs_timeseries_currency_to_default_swap_rate_asset().canonical, 'fin_gsq_timeseries_currency_to_default_swap_rate_asset');
SELECT assert_eq('gs quant compatibility 1383 gs_quant/timeseries/measures.py currency_to_inflation_benchmark_rate', gs_timeseries_currency_to_inflation_benchmark_rate().canonical, 'fin_gsq_timeseries_currency_to_inflation_benchmark_rate');
SELECT assert_eq('gs quant compatibility 1384 gs_quant/timeseries/measures.py cross_to_basis', gs_timeseries_cross_to_basis().canonical, 'fin_gsq_timeseries_cross_to_basis');
SELECT assert_eq('gs quant compatibility 1385 gs_quant/timeseries/measures.py convert_asset_for_rates_data_set', gs_timeseries_convert_asset_for_rates_data_set().canonical, 'fin_gsq_timeseries_convert_asset_for_rates_data_set');
SELECT assert_eq('gs quant compatibility 1386 gs_quant/timeseries/measures.py skew', gs_timeseries_skew().canonical, 'fin_skew');
SELECT assert_eq('gs quant compatibility 1387 gs_quant/timeseries/measures.py cds_implied_volatility', gs_timeseries_cds_implied_volatility().canonical, 'fin_cds_implied_volatility');
SELECT assert_eq('gs quant compatibility 1388 gs_quant/timeseries/measures.py option_premium_credit', gs_timeseries_option_premium_credit().canonical, 'fin_option_premium_credit');
SELECT assert_eq('gs quant compatibility 1389 gs_quant/timeseries/measures.py absolute_strike_credit', gs_timeseries_absolute_strike_credit().canonical, 'fin_absolute_strike_credit');
SELECT assert_eq('gs quant compatibility 1390 gs_quant/timeseries/measures.py implied_volatility_credit', gs_timeseries_implied_volatility_credit().canonical, 'fin_implied_volatility_credit');
SELECT assert_eq('gs quant compatibility 1391 gs_quant/timeseries/measures.py cds_spread', gs_timeseries_cds_spread().canonical, 'fin_cds_spread');
SELECT assert_eq('gs quant compatibility 1392 gs_quant/timeseries/measures.py implied_volatility', gs_timeseries_implied_volatility().canonical, 'fin_implied_volatility');
SELECT assert_eq('gs quant compatibility 1393 gs_quant/timeseries/measures.py implied_volatility_ng', gs_timeseries_implied_volatility_ng().canonical, 'fin_implied_volatility_ng');
SELECT assert_eq('gs quant compatibility 1394 gs_quant/timeseries/measures.py implied_correlation', gs_timeseries_implied_correlation().canonical, 'fin_implied_correlation');
SELECT assert_eq('gs quant compatibility 1395 gs_quant/timeseries/measures.py implied_correlation_with_basket', gs_timeseries_implied_correlation_with_basket().canonical, 'fin_implied_correlation_with_basket');
SELECT assert_eq('gs quant compatibility 1396 gs_quant/timeseries/measures.py realized_correlation_with_basket', gs_timeseries_realized_correlation_with_basket().canonical, 'fin_realized_correlation_with_basket');
SELECT assert_eq('gs quant compatibility 1397 gs_quant/timeseries/measures.py average_implied_volatility', gs_timeseries_average_implied_volatility().canonical, 'fin_average_implied_volatility');
SELECT assert_eq('gs quant compatibility 1398 gs_quant/timeseries/measures.py average_implied_variance', gs_timeseries_average_implied_variance().canonical, 'fin_average_implied_variance');
SELECT assert_eq('gs quant compatibility 1399 gs_quant/timeseries/measures.py average_realized_volatility', gs_timeseries_average_realized_volatility().canonical, 'fin_average_realized_volatility');
SELECT assert_eq('gs quant compatibility 1400 gs_quant/timeseries/measures.py cap_floor_vol', gs_timeseries_cap_floor_vol().canonical, 'fin_cap_floor_vol');
SELECT assert_eq('gs quant compatibility 1401 gs_quant/timeseries/measures.py cap_floor_atm_fwd_rate', gs_timeseries_cap_floor_atm_fwd_rate().canonical, 'fin_cap_floor_atm_fwd_rate');
SELECT assert_eq('gs quant compatibility 1402 gs_quant/timeseries/measures.py spread_option_vol', gs_timeseries_spread_option_vol().canonical, 'fin_spread_option_vol');
SELECT assert_eq('gs quant compatibility 1403 gs_quant/timeseries/measures.py spread_option_atm_fwd_rate', gs_timeseries_spread_option_atm_fwd_rate().canonical, 'fin_spread_option_atm_fwd_rate');
SELECT assert_eq('gs quant compatibility 1404 gs_quant/timeseries/measures.py zc_inflation_swap_rate', gs_timeseries_zc_inflation_swap_rate().canonical, 'fin_zc_inflation_swap_rate');
SELECT assert_eq('gs quant compatibility 1405 gs_quant/timeseries/measures.py basis', gs_timeseries_basis().canonical, 'fin_basis');
SELECT assert_eq('gs quant compatibility 1406 gs_quant/timeseries/measures.py fx_forecast', gs_timeseries_fx_forecast().canonical, 'fin_fx_forecast');
SELECT assert_eq('gs quant compatibility 1407 gs_quant/timeseries/measures.py fx_forecast_time_series', gs_timeseries_fx_forecast_time_series().canonical, 'fin_fx_forecast_time_series');
SELECT assert_eq('gs quant compatibility 1408 gs_quant/timeseries/measures.py forward_vol', gs_timeseries_forward_vol().canonical, 'fin_forward_vol');
SELECT assert_eq('gs quant compatibility 1409 gs_quant/timeseries/measures.py forward_vol_term', gs_timeseries_forward_vol_term().canonical, 'fin_forward_vol_term');
SELECT assert_eq('gs quant compatibility 1410 gs_quant/timeseries/measures.py skew_term', gs_timeseries_skew_term().canonical, 'fin_skew_term');
SELECT assert_eq('gs quant compatibility 1411 gs_quant/timeseries/measures.py vol_term', gs_timeseries_vol_term().canonical, 'fin_vol_term');
SELECT assert_eq('gs quant compatibility 1412 gs_quant/timeseries/measures.py vol_smile', gs_timeseries_vol_smile().canonical, 'fin_vol_smile');
SELECT assert_eq('gs quant compatibility 1413 gs_quant/timeseries/measures.py measure_request_safe', gs_timeseries_measure_request_safe().canonical, 'fin_gsq_timeseries_measure_request_safe');
SELECT assert_eq('gs quant compatibility 1414 gs_quant/timeseries/measures.py fwd_term', gs_timeseries_fwd_term().canonical, 'fin_fwd_term');
SELECT assert_eq('gs quant compatibility 1415 gs_quant/timeseries/measures.py fx_fwd_term', gs_timeseries_fx_fwd_term().canonical, 'fin_fx_fwd_term');
SELECT assert_eq('gs quant compatibility 1416 gs_quant/timeseries/measures.py carry_term', gs_timeseries_carry_term().canonical, 'fin_carry_term');
SELECT assert_eq('gs quant compatibility 1417 gs_quant/timeseries/measures.py forward_var_term', gs_timeseries_forward_var_term().canonical, 'fin_forward_var_term');
SELECT assert_eq('gs quant compatibility 1418 gs_quant/timeseries/measures.py var_term', gs_timeseries_var_term().canonical, 'fin_var_term');
SELECT assert_eq('gs quant compatibility 1419 gs_quant/timeseries/measures.py var_swap', gs_timeseries_var_swap().canonical, 'fin_var_swap');
SELECT assert_eq('gs quant compatibility 1420 gs_quant/timeseries/measures.py fair_price', gs_timeseries_fair_price().canonical, 'fin_fair_price');
SELECT assert_eq('gs quant compatibility 1421 gs_quant/timeseries/measures.py get_weights_for_contracts', gs_timeseries_get_weights_for_contracts().canonical, 'fin_gsq_timeseries_get_weights_for_contracts');
SELECT assert_eq('gs quant compatibility 1422 gs_quant/timeseries/measures.py forward_price', gs_timeseries_forward_price().canonical, 'fin_forward_price');
SELECT assert_eq('gs quant compatibility 1423 gs_quant/timeseries/measures.py implied_volatility_elec', gs_timeseries_implied_volatility_elec().canonical, 'fin_implied_volatility_elec');
SELECT assert_eq('gs quant compatibility 1424 gs_quant/timeseries/measures.py eu_ng_hub_to_swap', gs_timeseries_eu_ng_hub_to_swap().canonical, 'fin_gsq_timeseries_eu_ng_hub_to_swap');
SELECT assert_eq('gs quant compatibility 1425 gs_quant/timeseries/measures.py forward_price_ng', gs_timeseries_forward_price_ng().canonical, 'fin_forward_price_ng');
SELECT assert_eq('gs quant compatibility 1426 gs_quant/timeseries/measures.py get_contract_range', gs_timeseries_get_contract_range().canonical, 'fin_gsq_timeseries_get_contract_range');
SELECT assert_eq('gs quant compatibility 1427 gs_quant/timeseries/measures.py bucketize_price', gs_timeseries_bucketize_price().canonical, 'fin_bucketize_price');
SELECT assert_eq('gs quant compatibility 1428 gs_quant/timeseries/measures.py dividend_yield', gs_timeseries_dividend_yield().canonical, 'fin_dividend_yield');
SELECT assert_eq('gs quant compatibility 1429 gs_quant/timeseries/measures.py earnings_per_share', gs_timeseries_earnings_per_share().canonical, 'fin_earnings_per_share');
SELECT assert_eq('gs quant compatibility 1430 gs_quant/timeseries/measures.py earnings_per_share_positive', gs_timeseries_earnings_per_share_positive().canonical, 'fin_earnings_per_share_positive');
SELECT assert_eq('gs quant compatibility 1431 gs_quant/timeseries/measures.py net_debt_to_ebitda', gs_timeseries_net_debt_to_ebitda().canonical, 'fin_net_debt_to_ebitda');
SELECT assert_eq('gs quant compatibility 1432 gs_quant/timeseries/measures.py price_to_book', gs_timeseries_price_to_book().canonical, 'fin_price_to_book');
SELECT assert_eq('gs quant compatibility 1433 gs_quant/timeseries/measures.py price_to_cash', gs_timeseries_price_to_cash().canonical, 'fin_price_to_cash');
SELECT assert_eq('gs quant compatibility 1434 gs_quant/timeseries/measures.py price_to_earnings', gs_timeseries_price_to_earnings().canonical, 'fin_price_to_earnings');
SELECT assert_eq('gs quant compatibility 1435 gs_quant/timeseries/measures.py price_to_earnings_positive', gs_timeseries_price_to_earnings_positive().canonical, 'fin_price_to_earnings_positive');
SELECT assert_eq('gs quant compatibility 1436 gs_quant/timeseries/measures.py price_to_earnings_positive_exclusive', gs_timeseries_price_to_earnings_positive_exclusive().canonical, 'fin_price_to_earnings_positive_exclusive');
SELECT assert_eq('gs quant compatibility 1437 gs_quant/timeseries/measures.py price_to_sales', gs_timeseries_price_to_sales().canonical, 'fin_price_to_sales');
SELECT assert_eq('gs quant compatibility 1438 gs_quant/timeseries/measures.py return_on_equity', gs_timeseries_return_on_equity().canonical, 'fin_return_on_equity');
SELECT assert_eq('gs quant compatibility 1439 gs_quant/timeseries/measures.py sales_per_share', gs_timeseries_sales_per_share().canonical, 'fin_sales_per_share');
SELECT assert_eq('gs quant compatibility 1440 gs_quant/timeseries/measures.py current_constituents_dividend_yield', gs_timeseries_current_constituents_dividend_yield().canonical, 'fin_current_constituents_dividend_yield');
SELECT assert_eq('gs quant compatibility 1441 gs_quant/timeseries/measures.py current_constituents_earnings_per_share', gs_timeseries_current_constituents_earnings_per_share().canonical, 'fin_current_constituents_earnings_per_share');
SELECT assert_eq('gs quant compatibility 1442 gs_quant/timeseries/measures.py current_constituents_earnings_per_share_positive', gs_timeseries_current_constituents_earnings_per_share_positive().canonical, 'fin_current_constituents_earnings_per_share_positive');
SELECT assert_eq('gs quant compatibility 1443 gs_quant/timeseries/measures.py current_constituents_net_debt_to_ebitda', gs_timeseries_current_constituents_net_debt_to_ebitda().canonical, 'fin_current_constituents_net_debt_to_ebitda');
SELECT assert_eq('gs quant compatibility 1444 gs_quant/timeseries/measures.py current_constituents_price_to_book', gs_timeseries_current_constituents_price_to_book().canonical, 'fin_current_constituents_price_to_book');
SELECT assert_eq('gs quant compatibility 1445 gs_quant/timeseries/measures.py current_constituents_price_to_cash', gs_timeseries_current_constituents_price_to_cash().canonical, 'fin_current_constituents_price_to_cash');
SELECT assert_eq('gs quant compatibility 1446 gs_quant/timeseries/measures.py current_constituents_price_to_earnings', gs_timeseries_current_constituents_price_to_earnings().canonical, 'fin_current_constituents_price_to_earnings');
SELECT assert_eq('gs quant compatibility 1447 gs_quant/timeseries/measures.py current_constituents_price_to_earnings_positive', gs_timeseries_current_constituents_price_to_earnings_positive().canonical, 'fin_current_constituents_price_to_earnings_positive');
SELECT assert_eq('gs quant compatibility 1448 gs_quant/timeseries/measures.py current_constituents_price_to_sales', gs_timeseries_current_constituents_price_to_sales().canonical, 'fin_current_constituents_price_to_sales');
SELECT assert_eq('gs quant compatibility 1449 gs_quant/timeseries/measures.py current_constituents_return_on_equity', gs_timeseries_current_constituents_return_on_equity().canonical, 'fin_current_constituents_return_on_equity');
SELECT assert_eq('gs quant compatibility 1450 gs_quant/timeseries/measures.py current_constituents_sales_per_share', gs_timeseries_current_constituents_sales_per_share().canonical, 'fin_current_constituents_sales_per_share');
SELECT assert_eq('gs quant compatibility 1451 gs_quant/timeseries/measures.py realized_correlation', gs_timeseries_realized_correlation().canonical, 'fin_realized_correlation');
SELECT assert_eq('gs quant compatibility 1452 gs_quant/timeseries/measures.py realized_volatility', gs_timeseries_realized_volatility().canonical, 'fin_realized_volatility');
SELECT assert_eq('gs quant compatibility 1453 gs_quant/timeseries/measures.py esg_headline_metric', gs_timeseries_esg_headline_metric().canonical, 'fin_esg_headline_metric');
SELECT assert_eq('gs quant compatibility 1454 gs_quant/timeseries/measures.py rating', gs_timeseries_rating().canonical, 'fin_rating');
SELECT assert_eq('gs quant compatibility 1455 gs_quant/timeseries/measures.py fair_value', gs_timeseries_fair_value().canonical, 'fin_fair_value');
SELECT assert_eq('gs quant compatibility 1456 gs_quant/timeseries/measures.py factor_profile', gs_timeseries_factor_profile().canonical, 'fin_factor_profile');
SELECT assert_eq('gs quant compatibility 1457 gs_quant/timeseries/measures.py commodity_forecast', gs_timeseries_commodity_forecast().canonical, 'fin_commodity_forecast');
SELECT assert_eq('gs quant compatibility 1458 gs_quant/timeseries/measures.py commodity_forecast_time_series', gs_timeseries_commodity_forecast_time_series().canonical, 'fin_commodity_forecast_time_series');
SELECT assert_eq('gs quant compatibility 1459 gs_quant/timeseries/measures.py forward_curve', gs_timeseries_forward_curve().canonical, 'fin_forward_curve');
SELECT assert_eq('gs quant compatibility 1460 gs_quant/timeseries/measures.py forward_curve_ng', gs_timeseries_forward_curve_ng().canonical, 'fin_forward_curve_ng');
SELECT assert_eq('gs quant compatibility 1461 gs_quant/timeseries/measures.py fx_implied_correlation', gs_timeseries_fx_implied_correlation().canonical, 'fin_fx_implied_correlation');
SELECT assert_eq('gs quant compatibility 1462 gs_quant/timeseries/measures.py get_last_for_measure', gs_timeseries_get_last_for_measure().canonical, 'fin_gsq_timeseries_get_last_for_measure');
SELECT assert_eq('gs quant compatibility 1463 gs_quant/timeseries/measures.py merge_dataframes', gs_timeseries_merge_dataframes().canonical, 'fin_gsq_timeseries_merge_dataframes');
SELECT assert_eq('gs quant compatibility 1464 gs_quant/timeseries/measures.py append_last_for_measure', gs_timeseries_append_last_for_measure().canonical, 'fin_gsq_timeseries_append_last_for_measure');
SELECT assert_eq('gs quant compatibility 1465 gs_quant/timeseries/measures.py get_market_data_tasks', gs_timeseries_get_market_data_tasks().canonical, 'fin_gsq_timeseries_get_market_data_tasks');
SELECT assert_eq('gs quant compatibility 1466 gs_quant/timeseries/measures.py get_historical_and_last_for_measure', gs_timeseries_get_historical_and_last_for_measure().canonical, 'fin_gsq_timeseries_get_historical_and_last_for_measure');
SELECT assert_eq('gs quant compatibility 1467 gs_quant/timeseries/measures.py settlement_price', gs_timeseries_settlement_price().canonical, 'fin_settlement_price');
SELECT assert_eq('gs quant compatibility 1468 gs_quant/timeseries/measures.py hloc_prices', gs_timeseries_hloc_prices().canonical, 'fin_hloc_prices');
SELECT assert_eq('gs quant compatibility 1469 gs_quant/timeseries/measures.py thematic_model_exposure', gs_timeseries_thematic_model_exposure().canonical, 'fin_thematic_model_exposure');
SELECT assert_eq('gs quant compatibility 1470 gs_quant/timeseries/measures.py thematic_model_beta', gs_timeseries_thematic_model_beta().canonical, 'fin_thematic_model_beta');
SELECT assert_eq('gs quant compatibility 1471 gs_quant/timeseries/measures.py retail_interest_agg', gs_timeseries_retail_interest_agg().canonical, 'fin_retail_interest_agg');
SELECT assert_eq('gs quant compatibility 1472 gs_quant/timeseries/measures.py s3_long_short_concentration', gs_timeseries_s3_long_short_concentration().canonical, 'fin_s3_long_short_concentration');
SELECT assert_eq('gs quant compatibility 1473 gs_quant/timeseries/measures_cognitive_credit.py cognitive_credit_fundamentals', gs_timeseries_cognitive_credit_fundamentals().canonical, 'fin_cognitive_credit_fundamentals');
SELECT assert_eq('gs quant compatibility 1474 gs_quant/timeseries/measures_countries.py fci', gs_timeseries_fci().canonical, 'fin_fci');
SELECT assert_eq('gs quant compatibility 1475 gs_quant/timeseries/measures_factset.py factset_estimates', gs_timeseries_factset_estimates().canonical, 'fin_factset_estimates');
SELECT assert_eq('gs quant compatibility 1476 gs_quant/timeseries/measures_factset.py factset_fundamentals', gs_timeseries_factset_fundamentals().canonical, 'fin_factset_fundamentals');
SELECT assert_eq('gs quant compatibility 1477 gs_quant/timeseries/measures_factset.py factset_ratings', gs_timeseries_factset_ratings().canonical, 'fin_factset_ratings');
SELECT assert_eq('gs quant compatibility 1478 gs_quant/timeseries/measures_factset.py gir_estimates', gs_timeseries_gir_estimates().canonical, 'fin_gir_estimates');
SELECT assert_eq('gs quant compatibility 1479 gs_quant/timeseries/measures_factset.py factset_enterprise_value', gs_timeseries_factset_enterprise_value().canonical, 'fin_factset_enterprise_value');
SELECT assert_eq('gs quant compatibility 1480 gs_quant/timeseries/measures_fx_vol.py get_fxo_asset', gs_timeseries_get_fxo_asset().canonical, 'fin_gsq_timeseries_get_fxo_asset');
SELECT assert_eq('gs quant compatibility 1481 gs_quant/timeseries/measures_fx_vol.py cross_stored_direction_for_fx_vol', gs_timeseries_cross_stored_direction_for_fx_vol_timeseries_measures_fx_vol().canonical, 'fin_gsq_timeseries_cross_stored_direction_for_fx_vol_timeseries_measures_fx_vol');
SELECT assert_eq('gs quant compatibility 1482 gs_quant/timeseries/measures_fx_vol.py implied_volatility_new', gs_timeseries_implied_volatility_new().canonical, 'fin_gsq_timeseries_implied_volatility_new');
SELECT assert_eq('gs quant compatibility 1483 gs_quant/timeseries/measures_fx_vol.py implied_volatility_fxvol', gs_timeseries_implied_volatility_fxvol().canonical, 'fin_implied_volatility_fxvol');
SELECT assert_eq('gs quant compatibility 1484 gs_quant/timeseries/measures_fx_vol.py fwd_points', gs_timeseries_fwd_points().canonical, 'fin_fwd_points');
SELECT assert_eq('gs quant compatibility 1485 gs_quant/timeseries/measures_fx_vol.py vol_swap_strike', gs_timeseries_vol_swap_strike().canonical, 'fin_vol_swap_strike');
SELECT assert_eq('gs quant compatibility 1486 gs_quant/timeseries/measures_fx_vol.py spot_carry', gs_timeseries_spot_carry().canonical, 'fin_spot_carry');
SELECT assert_eq('gs quant compatibility 1487 gs_quant/timeseries/measures_helper.py preprocess_implied_vol_strikes_eq', gs_timeseries_preprocess_implied_vol_strikes_eq().canonical, 'fin_gsq_timeseries_preprocess_implied_vol_strikes_eq');
SELECT assert_eq('gs quant compatibility 1488 gs_quant/timeseries/measures_inflation.py inflation_swap_rate', gs_timeseries_inflation_swap_rate().canonical, 'fin_inflation_swap_rate');
SELECT assert_eq('gs quant compatibility 1489 gs_quant/timeseries/measures_inflation.py inflation_swap_term', gs_timeseries_inflation_swap_term().canonical, 'fin_inflation_swap_term');
SELECT assert_eq('gs quant compatibility 1490 gs_quant/timeseries/measures_portfolios.py aum', gs_timeseries_aum().canonical, 'fin_aum');
SELECT assert_eq('gs quant compatibility 1491 gs_quant/timeseries/measures_portfolios.py portfolio_factor_exposure', gs_timeseries_portfolio_factor_exposure().canonical, 'fin_portfolio_factor_exposure');
SELECT assert_eq('gs quant compatibility 1492 gs_quant/timeseries/measures_portfolios.py portfolio_factor_pnl', gs_timeseries_portfolio_factor_pnl().canonical, 'fin_portfolio_factor_pnl');
SELECT assert_eq('gs quant compatibility 1493 gs_quant/timeseries/measures_portfolios.py portfolio_factor_proportion_of_risk', gs_timeseries_portfolio_factor_proportion_of_risk().canonical, 'fin_portfolio_factor_proportion_of_risk');
SELECT assert_eq('gs quant compatibility 1494 gs_quant/timeseries/measures_portfolios.py portfolio_daily_risk', gs_timeseries_portfolio_daily_risk().canonical, 'fin_portfolio_daily_risk');
SELECT assert_eq('gs quant compatibility 1495 gs_quant/timeseries/measures_portfolios.py portfolio_annual_risk', gs_timeseries_portfolio_annual_risk().canonical, 'fin_portfolio_annual_risk');
SELECT assert_eq('gs quant compatibility 1496 gs_quant/timeseries/measures_portfolios.py portfolio_thematic_exposure', gs_timeseries_portfolio_thematic_exposure().canonical, 'fin_portfolio_thematic_exposure');
SELECT assert_eq('gs quant compatibility 1497 gs_quant/timeseries/measures_portfolios.py portfolio_pnl', gs_timeseries_portfolio_pnl().canonical, 'fin_portfolio_pnl');
SELECT assert_eq('gs quant compatibility 1498 gs_quant/timeseries/measures_portfolios.py portfolio_hit_rate', gs_timeseries_portfolio_hit_rate().canonical, 'fin_portfolio_hit_rate');
SELECT assert_eq('gs quant compatibility 1499 gs_quant/timeseries/measures_portfolios.py portfolio_max_drawdown', gs_timeseries_portfolio_max_drawdown().canonical, 'fin_portfolio_max_drawdown');
SELECT assert_eq('gs quant compatibility 1500 gs_quant/timeseries/measures_portfolios.py portfolio_drawdown_length', gs_timeseries_portfolio_drawdown_length().canonical, 'fin_portfolio_drawdown_length');
SELECT assert_eq('gs quant compatibility 1501 gs_quant/timeseries/measures_portfolios.py portfolio_max_recovery_period', gs_timeseries_portfolio_max_recovery_period().canonical, 'fin_portfolio_max_recovery_period');
SELECT assert_eq('gs quant compatibility 1502 gs_quant/timeseries/measures_portfolios.py portfolio_standard_deviation', gs_timeseries_portfolio_standard_deviation().canonical, 'fin_portfolio_standard_deviation');
SELECT assert_eq('gs quant compatibility 1503 gs_quant/timeseries/measures_portfolios.py portfolio_downside_risk', gs_timeseries_portfolio_downside_risk().canonical, 'fin_portfolio_downside_risk');
SELECT assert_eq('gs quant compatibility 1504 gs_quant/timeseries/measures_portfolios.py portfolio_semi_variance', gs_timeseries_portfolio_semi_variance().canonical, 'fin_portfolio_semi_variance');
SELECT assert_eq('gs quant compatibility 1505 gs_quant/timeseries/measures_portfolios.py portfolio_kurtosis', gs_timeseries_portfolio_kurtosis().canonical, 'fin_portfolio_kurtosis');
SELECT assert_eq('gs quant compatibility 1506 gs_quant/timeseries/measures_portfolios.py portfolio_skewness', gs_timeseries_portfolio_skewness().canonical, 'fin_portfolio_skewness');
SELECT assert_eq('gs quant compatibility 1507 gs_quant/timeseries/measures_portfolios.py portfolio_realized_var', gs_timeseries_portfolio_realized_var().canonical, 'fin_portfolio_realized_var');
SELECT assert_eq('gs quant compatibility 1508 gs_quant/timeseries/measures_portfolios.py portfolio_tracking_error', gs_timeseries_portfolio_tracking_error().canonical, 'fin_portfolio_tracking_error');
SELECT assert_eq('gs quant compatibility 1509 gs_quant/timeseries/measures_portfolios.py portfolio_tracking_error_bear', gs_timeseries_portfolio_tracking_error_bear().canonical, 'fin_portfolio_tracking_error_bear');
SELECT assert_eq('gs quant compatibility 1510 gs_quant/timeseries/measures_portfolios.py portfolio_tracking_error_bull', gs_timeseries_portfolio_tracking_error_bull().canonical, 'fin_portfolio_tracking_error_bull');
SELECT assert_eq('gs quant compatibility 1511 gs_quant/timeseries/measures_portfolios.py portfolio_sharpe_ratio', gs_timeseries_portfolio_sharpe_ratio().canonical, 'fin_portfolio_sharpe_ratio');
SELECT assert_eq('gs quant compatibility 1512 gs_quant/timeseries/measures_portfolios.py portfolio_calmar_ratio', gs_timeseries_portfolio_calmar_ratio().canonical, 'fin_portfolio_calmar_ratio');
SELECT assert_eq('gs quant compatibility 1513 gs_quant/timeseries/measures_portfolios.py portfolio_sortino_ratio', gs_timeseries_portfolio_sortino_ratio().canonical, 'fin_portfolio_sortino_ratio');
SELECT assert_eq('gs quant compatibility 1514 gs_quant/timeseries/measures_portfolios.py portfolio_information_ratio', gs_timeseries_portfolio_information_ratio().canonical, 'fin_portfolio_information_ratio');
SELECT assert_eq('gs quant compatibility 1515 gs_quant/timeseries/measures_portfolios.py portfolio_information_ratio_bull', gs_timeseries_portfolio_information_ratio_bull().canonical, 'fin_portfolio_information_ratio_bull');
SELECT assert_eq('gs quant compatibility 1516 gs_quant/timeseries/measures_portfolios.py portfolio_information_ratio_bear', gs_timeseries_portfolio_information_ratio_bear().canonical, 'fin_portfolio_information_ratio_bear');
SELECT assert_eq('gs quant compatibility 1517 gs_quant/timeseries/measures_portfolios.py portfolio_modigliani_ratio', gs_timeseries_portfolio_modigliani_ratio().canonical, 'fin_portfolio_modigliani_ratio');
SELECT assert_eq('gs quant compatibility 1518 gs_quant/timeseries/measures_portfolios.py portfolio_treynor_measure', gs_timeseries_portfolio_treynor_measure().canonical, 'fin_portfolio_treynor_measure');
SELECT assert_eq('gs quant compatibility 1519 gs_quant/timeseries/measures_portfolios.py portfolio_jensen_alpha', gs_timeseries_portfolio_jensen_alpha().canonical, 'fin_portfolio_jensen_alpha');
SELECT assert_eq('gs quant compatibility 1520 gs_quant/timeseries/measures_portfolios.py portfolio_jensen_alpha_bear', gs_timeseries_portfolio_jensen_alpha_bear().canonical, 'fin_portfolio_jensen_alpha_bear');
SELECT assert_eq('gs quant compatibility 1521 gs_quant/timeseries/measures_portfolios.py portfolio_jensen_alpha_bull', gs_timeseries_portfolio_jensen_alpha_bull().canonical, 'fin_portfolio_jensen_alpha_bull');
SELECT assert_eq('gs quant compatibility 1522 gs_quant/timeseries/measures_portfolios.py portfolio_alpha', gs_timeseries_portfolio_alpha().canonical, 'fin_portfolio_alpha');
SELECT assert_eq('gs quant compatibility 1523 gs_quant/timeseries/measures_portfolios.py portfolio_beta', gs_timeseries_portfolio_beta().canonical, 'fin_portfolio_beta');
SELECT assert_eq('gs quant compatibility 1524 gs_quant/timeseries/measures_portfolios.py portfolio_correlation', gs_timeseries_portfolio_correlation().canonical, 'fin_portfolio_correlation');
SELECT assert_eq('gs quant compatibility 1525 gs_quant/timeseries/measures_portfolios.py portfolio_r_squared', gs_timeseries_portfolio_r_squared().canonical, 'fin_portfolio_r_squared');
SELECT assert_eq('gs quant compatibility 1526 gs_quant/timeseries/measures_portfolios.py portfolio_capture_ratio', gs_timeseries_portfolio_capture_ratio().canonical, 'fin_portfolio_capture_ratio');
SELECT assert_eq('gs quant compatibility 1527 gs_quant/timeseries/measures_rates.py swap_annuity', gs_timeseries_swap_annuity().canonical, 'fin_swap_annuity');
SELECT assert_eq('gs quant compatibility 1528 gs_quant/timeseries/measures_rates.py swaption_premium', gs_timeseries_swaption_premium().canonical, 'fin_swaption_premium');
SELECT assert_eq('gs quant compatibility 1529 gs_quant/timeseries/measures_rates.py swaption_annuity', gs_timeseries_swaption_annuity().canonical, 'fin_swaption_annuity');
SELECT assert_eq('gs quant compatibility 1530 gs_quant/timeseries/measures_rates.py midcurve_premium', gs_timeseries_midcurve_premium().canonical, 'fin_midcurve_premium');
SELECT assert_eq('gs quant compatibility 1531 gs_quant/timeseries/measures_rates.py midcurve_annuity', gs_timeseries_midcurve_annuity().canonical, 'fin_midcurve_annuity');
SELECT assert_eq('gs quant compatibility 1532 gs_quant/timeseries/measures_rates.py swaption_atm_fwd_rate', gs_timeseries_swaption_atm_fwd_rate().canonical, 'fin_swaption_atm_fwd_rate');
SELECT assert_eq('gs quant compatibility 1533 gs_quant/timeseries/measures_rates.py swaption_vol', gs_timeseries_swaption_vol().canonical, 'fin_swaption_vol');
SELECT assert_eq('gs quant compatibility 1534 gs_quant/timeseries/measures_rates.py midcurve_vol', gs_timeseries_midcurve_vol().canonical, 'fin_midcurve_vol');
SELECT assert_eq('gs quant compatibility 1535 gs_quant/timeseries/measures_rates.py midcurve_atm_fwd_rate', gs_timeseries_midcurve_atm_fwd_rate().canonical, 'fin_midcurve_atm_fwd_rate');
SELECT assert_eq('gs quant compatibility 1536 gs_quant/timeseries/measures_rates.py swaption_vol_smile', gs_timeseries_swaption_vol_smile().canonical, 'fin_swaption_vol_smile');
SELECT assert_eq('gs quant compatibility 1537 gs_quant/timeseries/measures_rates.py swaption_vol_term', gs_timeseries_swaption_vol_term().canonical, 'fin_swaption_vol_term');
SELECT assert_eq('gs quant compatibility 1538 gs_quant/timeseries/measures_rates.py swap_rate', gs_timeseries_swap_rate().canonical, 'fin_swap_rate');
SELECT assert_eq('gs quant compatibility 1539 gs_quant/timeseries/measures_rates.py swap_rate_calc', gs_timeseries_swap_rate_calc().canonical, 'fin_swap_rate_calc');
SELECT assert_eq('gs quant compatibility 1540 gs_quant/timeseries/measures_rates.py forward_rate', gs_timeseries_forward_rate().canonical, 'fin_forward_rate');
SELECT assert_eq('gs quant compatibility 1541 gs_quant/timeseries/measures_rates.py discount_factor', gs_timeseries_discount_factor().canonical, 'fin_discount_factor');
SELECT assert_eq('gs quant compatibility 1542 gs_quant/timeseries/measures_rates.py instantaneous_forward_rate', gs_timeseries_instantaneous_forward_rate().canonical, 'fin_instantaneous_forward_rate');
SELECT assert_eq('gs quant compatibility 1543 gs_quant/timeseries/measures_rates.py index_forward_rate', gs_timeseries_index_forward_rate().canonical, 'fin_index_forward_rate');
SELECT assert_eq('gs quant compatibility 1544 gs_quant/timeseries/measures_rates.py basis_swap_spread', gs_timeseries_basis_swap_spread().canonical, 'fin_basis_swap_spread');
SELECT assert_eq('gs quant compatibility 1545 gs_quant/timeseries/measures_rates.py swap_term_structure', gs_timeseries_swap_term_structure().canonical, 'fin_swap_term_structure');
SELECT assert_eq('gs quant compatibility 1546 gs_quant/timeseries/measures_rates.py basis_swap_term_structure', gs_timeseries_basis_swap_term_structure().canonical, 'fin_basis_swap_term_structure');
SELECT assert_eq('gs quant compatibility 1547 gs_quant/timeseries/measures_rates.py ois_xccy', gs_timeseries_ois_xccy().canonical, 'fin_ois_xccy');
SELECT assert_eq('gs quant compatibility 1548 gs_quant/timeseries/measures_rates.py ois_xccy_ex_spike', gs_timeseries_ois_xccy_ex_spike().canonical, 'fin_ois_xccy_ex_spike');
SELECT assert_eq('gs quant compatibility 1549 gs_quant/timeseries/measures_rates.py non_usd_ois', gs_timeseries_non_usd_ois().canonical, 'fin_non_usd_ois');
SELECT assert_eq('gs quant compatibility 1550 gs_quant/timeseries/measures_rates.py usd_ois', gs_timeseries_usd_ois().canonical, 'fin_usd_ois');
SELECT assert_eq('gs quant compatibility 1551 gs_quant/timeseries/measures_rates.py get_cb_swaps_kwargs', gs_timeseries_get_cb_swaps_kwargs().canonical, 'fin_gsq_timeseries_get_cb_swaps_kwargs');
SELECT assert_eq('gs quant compatibility 1552 gs_quant/timeseries/measures_rates.py get_cb_meeting_swaps', gs_timeseries_get_cb_meeting_swaps().canonical, 'fin_gsq_timeseries_get_cb_meeting_swaps');
SELECT assert_eq('gs quant compatibility 1553 gs_quant/timeseries/measures_rates.py get_cb_meeting_swap', gs_timeseries_get_cb_meeting_swap().canonical, 'fin_gsq_timeseries_get_cb_meeting_swap');
SELECT assert_eq('gs quant compatibility 1554 gs_quant/timeseries/measures_rates.py get_cb_swap_data', gs_timeseries_get_cb_swap_data().canonical, 'fin_gsq_timeseries_get_cb_swap_data');
SELECT assert_eq('gs quant compatibility 1555 gs_quant/timeseries/measures_rates.py policy_rate_term_structure', gs_timeseries_policy_rate_term_structure().canonical, 'fin_policy_rate_term_structure');
SELECT assert_eq('gs quant compatibility 1556 gs_quant/timeseries/measures_rates.py policy_rate_expectation', gs_timeseries_policy_rate_expectation().canonical, 'fin_policy_rate_expectation');
SELECT assert_eq('gs quant compatibility 1557 gs_quant/timeseries/measures_rates.py parse_meeting_date', gs_timeseries_parse_meeting_date().canonical, 'fin_gsq_timeseries_parse_meeting_date');
SELECT assert_eq('gs quant compatibility 1558 gs_quant/timeseries/measures_rates.py policy_rate_expectation_rt', gs_timeseries_policy_rate_expectation_rt().canonical, 'fin_gsq_timeseries_policy_rate_expectation_rt');
SELECT assert_eq('gs quant compatibility 1559 gs_quant/timeseries/measures_rates.py policy_rate_term_structure_rt', gs_timeseries_policy_rate_term_structure_rt().canonical, 'fin_gsq_timeseries_policy_rate_term_structure_rt');
SELECT assert_eq('gs quant compatibility 1560 gs_quant/timeseries/measures_reports.py factor_exposure', gs_timeseries_factor_exposure().canonical, 'fin_factor_exposure');
SELECT assert_eq('gs quant compatibility 1561 gs_quant/timeseries/measures_reports.py factor_pnl', gs_timeseries_factor_pnl().canonical, 'fin_factor_pnl');
SELECT assert_eq('gs quant compatibility 1562 gs_quant/timeseries/measures_reports.py factor_proportion_of_risk', gs_timeseries_factor_proportion_of_risk().canonical, 'fin_factor_proportion_of_risk');
SELECT assert_eq('gs quant compatibility 1563 gs_quant/timeseries/measures_reports.py daily_risk', gs_timeseries_daily_risk().canonical, 'fin_daily_risk');
SELECT assert_eq('gs quant compatibility 1564 gs_quant/timeseries/measures_reports.py annual_risk', gs_timeseries_annual_risk().canonical, 'fin_annual_risk');
SELECT assert_eq('gs quant compatibility 1565 gs_quant/timeseries/measures_reports.py normalized_performance', gs_timeseries_normalized_performance().canonical, 'fin_normalized_performance');
SELECT assert_eq('gs quant compatibility 1566 gs_quant/timeseries/measures_reports.py long_pnl', gs_timeseries_long_pnl().canonical, 'fin_long_pnl');
SELECT assert_eq('gs quant compatibility 1567 gs_quant/timeseries/measures_reports.py short_pnl', gs_timeseries_short_pnl().canonical, 'fin_short_pnl');
SELECT assert_eq('gs quant compatibility 1568 gs_quant/timeseries/measures_reports.py thematic_exposure', gs_timeseries_thematic_exposure().canonical, 'fin_thematic_exposure');
SELECT assert_eq('gs quant compatibility 1569 gs_quant/timeseries/measures_reports.py thematic_beta', gs_timeseries_thematic_beta().canonical, 'fin_thematic_beta');
SELECT assert_eq('gs quant compatibility 1570 gs_quant/timeseries/measures_reports.py aum', gs_timeseries_aum_timeseries_measures_reports().canonical, 'fin_aum');
SELECT assert_eq('gs quant compatibility 1571 gs_quant/timeseries/measures_reports.py pnl', gs_timeseries_pnl().canonical, 'fin_pnl');
SELECT assert_eq('gs quant compatibility 1572 gs_quant/timeseries/measures_reports.py historical_simulation_estimated_pnl', gs_timeseries_historical_simulation_estimated_pnl().canonical, 'fin_historical_simulation_estimated_pnl');
SELECT assert_eq('gs quant compatibility 1573 gs_quant/timeseries/measures_reports.py historical_simulation_estimated_factor_attribution', gs_timeseries_historical_simulation_estimated_factor_attribution().canonical, 'fin_historical_simulation_estimated_factor_attribution');
SELECT assert_eq('gs quant compatibility 1574 gs_quant/timeseries/measures_reports.py hit_rate', gs_timeseries_hit_rate().canonical, 'fin_hit_rate');
SELECT assert_eq('gs quant compatibility 1575 gs_quant/timeseries/measures_reports.py portfolio_max_drawdown', gs_timeseries_portfolio_max_drawdown_timeseries_measures_reports().canonical, 'fin_portfolio_max_drawdown');
SELECT assert_eq('gs quant compatibility 1576 gs_quant/timeseries/measures_reports.py drawdown_length', gs_timeseries_drawdown_length().canonical, 'fin_drawdown_length');
SELECT assert_eq('gs quant compatibility 1577 gs_quant/timeseries/measures_reports.py max_recovery_period', gs_timeseries_max_recovery_period().canonical, 'fin_max_recovery_period');
SELECT assert_eq('gs quant compatibility 1578 gs_quant/timeseries/measures_reports.py standard_deviation', gs_timeseries_standard_deviation().canonical, 'fin_standard_deviation');
SELECT assert_eq('gs quant compatibility 1579 gs_quant/timeseries/measures_reports.py downside_risk', gs_timeseries_downside_risk().canonical, 'fin_downside_risk');
SELECT assert_eq('gs quant compatibility 1580 gs_quant/timeseries/measures_reports.py semi_variance', gs_timeseries_semi_variance().canonical, 'fin_semi_variance');
SELECT assert_eq('gs quant compatibility 1581 gs_quant/timeseries/measures_reports.py kurtosis', gs_timeseries_kurtosis().canonical, 'fin_kurtosis');
SELECT assert_eq('gs quant compatibility 1582 gs_quant/timeseries/measures_reports.py skewness', gs_timeseries_skewness().canonical, 'fin_skewness');
SELECT assert_eq('gs quant compatibility 1583 gs_quant/timeseries/measures_reports.py realized_var', gs_timeseries_realized_var().canonical, 'fin_realized_var');
SELECT assert_eq('gs quant compatibility 1584 gs_quant/timeseries/measures_reports.py tracking_error', gs_timeseries_tracking_error().canonical, 'fin_tracking_error');
SELECT assert_eq('gs quant compatibility 1585 gs_quant/timeseries/measures_reports.py tracking_error_bear', gs_timeseries_tracking_error_bear().canonical, 'fin_tracking_error_bear');
SELECT assert_eq('gs quant compatibility 1586 gs_quant/timeseries/measures_reports.py tracking_error_bull', gs_timeseries_tracking_error_bull().canonical, 'fin_tracking_error_bull');
SELECT assert_eq('gs quant compatibility 1587 gs_quant/timeseries/measures_reports.py portfolio_sharpe_ratio', gs_timeseries_portfolio_sharpe_ratio_timeseries_measures_reports().canonical, 'fin_portfolio_sharpe_ratio');
SELECT assert_eq('gs quant compatibility 1588 gs_quant/timeseries/measures_reports.py calmar_ratio', gs_timeseries_calmar_ratio().canonical, 'fin_calmar_ratio');
SELECT assert_eq('gs quant compatibility 1589 gs_quant/timeseries/measures_reports.py sortino_ratio', gs_timeseries_sortino_ratio().canonical, 'fin_sortino_ratio');
SELECT assert_eq('gs quant compatibility 1590 gs_quant/timeseries/measures_reports.py jensen_alpha', gs_timeseries_jensen_alpha().canonical, 'fin_jensen_alpha');
SELECT assert_eq('gs quant compatibility 1591 gs_quant/timeseries/measures_reports.py jensen_alpha_bear', gs_timeseries_jensen_alpha_bear().canonical, 'fin_jensen_alpha_bear');
SELECT assert_eq('gs quant compatibility 1592 gs_quant/timeseries/measures_reports.py jensen_alpha_bull', gs_timeseries_jensen_alpha_bull().canonical, 'fin_jensen_alpha_bull');
SELECT assert_eq('gs quant compatibility 1593 gs_quant/timeseries/measures_reports.py information_ratio', gs_timeseries_information_ratio().canonical, 'fin_information_ratio');
SELECT assert_eq('gs quant compatibility 1594 gs_quant/timeseries/measures_reports.py information_ratio_bear', gs_timeseries_information_ratio_bear().canonical, 'fin_information_ratio_bear');
SELECT assert_eq('gs quant compatibility 1595 gs_quant/timeseries/measures_reports.py information_ratio_bull', gs_timeseries_information_ratio_bull().canonical, 'fin_information_ratio_bull');
SELECT assert_eq('gs quant compatibility 1596 gs_quant/timeseries/measures_reports.py modigliani_ratio', gs_timeseries_modigliani_ratio().canonical, 'fin_modigliani_ratio');
SELECT assert_eq('gs quant compatibility 1597 gs_quant/timeseries/measures_reports.py treynor_measure', gs_timeseries_treynor_measure().canonical, 'fin_treynor_measure');
SELECT assert_eq('gs quant compatibility 1598 gs_quant/timeseries/measures_reports.py alpha', gs_timeseries_alpha().canonical, 'fin_alpha');
SELECT assert_eq('gs quant compatibility 1599 gs_quant/timeseries/measures_reports.py portfolio_beta', gs_timeseries_portfolio_beta_timeseries_measures_reports().canonical, 'fin_portfolio_beta');
SELECT assert_eq('gs quant compatibility 1600 gs_quant/timeseries/measures_reports.py portfolio_correlation', gs_timeseries_portfolio_correlation_timeseries_measures_reports().canonical, 'fin_portfolio_correlation');
SELECT assert_eq('gs quant compatibility 1601 gs_quant/timeseries/measures_reports.py capture_ratio', gs_timeseries_capture_ratio().canonical, 'fin_capture_ratio');
SELECT assert_eq('gs quant compatibility 1602 gs_quant/timeseries/measures_reports.py r_squared', gs_timeseries_r_squared().canonical, 'fin_r_squared');
SELECT assert_eq('gs quant compatibility 1603 gs_quant/timeseries/measures_risk_models.py risk_model_measure', gs_timeseries_risk_model_measure().canonical, 'fin_risk_model_measure');
SELECT assert_eq('gs quant compatibility 1604 gs_quant/timeseries/measures_risk_models.py factor_zscore', gs_timeseries_factor_zscore().canonical, 'fin_factor_zscore');
SELECT assert_eq('gs quant compatibility 1605 gs_quant/timeseries/measures_risk_models.py factor_covariance', gs_timeseries_factor_covariance().canonical, 'fin_factor_covariance');
SELECT assert_eq('gs quant compatibility 1606 gs_quant/timeseries/measures_risk_models.py factor_volatility', gs_timeseries_factor_volatility().canonical, 'fin_factor_volatility');
SELECT assert_eq('gs quant compatibility 1607 gs_quant/timeseries/measures_risk_models.py factor_correlation', gs_timeseries_factor_correlation().canonical, 'fin_factor_correlation');
SELECT assert_eq('gs quant compatibility 1608 gs_quant/timeseries/measures_risk_models.py factor_performance', gs_timeseries_factor_performance().canonical, 'fin_factor_performance');
SELECT assert_eq('gs quant compatibility 1609 gs_quant/timeseries/measures_risk_models.py factor_returns_intraday', gs_timeseries_factor_returns_intraday().canonical, 'fin_factor_returns_intraday');
SELECT assert_eq('gs quant compatibility 1610 gs_quant/timeseries/measures_risk_models.py factor_returns_percentile', gs_timeseries_factor_returns_percentile().canonical, 'fin_factor_returns_percentile');
SELECT assert_eq('gs quant compatibility 1611 gs_quant/timeseries/measures_xccy.py crosscurrency_swap_rate', gs_timeseries_crosscurrency_swap_rate().canonical, 'fin_crosscurrency_swap_rate');
SELECT assert_eq('gs quant compatibility 1612 gs_quant/timeseries/statistics.py min_', gs_timeseries_min().canonical, 'fin_min_');
SELECT assert_eq('gs quant compatibility 1613 gs_quant/timeseries/statistics.py max_', gs_timeseries_max().canonical, 'fin_max_');
SELECT assert_eq('gs quant compatibility 1614 gs_quant/timeseries/statistics.py range_', gs_timeseries_range().canonical, 'fin_range_');
SELECT assert_eq('gs quant compatibility 1615 gs_quant/timeseries/statistics.py mean', gs_timeseries_mean().canonical, 'fin_mean');
SELECT assert_eq('gs quant compatibility 1616 gs_quant/timeseries/statistics.py median', gs_timeseries_median().canonical, 'fin_median');
SELECT assert_eq('gs quant compatibility 1617 gs_quant/timeseries/statistics.py mode', gs_timeseries_mode().canonical, 'fin_mode');
SELECT assert_eq('gs quant compatibility 1618 gs_quant/timeseries/statistics.py sum_', gs_timeseries_sum().canonical, 'fin_sum_');
SELECT assert_eq('gs quant compatibility 1619 gs_quant/timeseries/statistics.py product', gs_timeseries_product().canonical, 'fin_product');
SELECT assert_eq('gs quant compatibility 1620 gs_quant/timeseries/statistics.py std', gs_timeseries_std().canonical, 'fin_std');
SELECT assert_eq('gs quant compatibility 1621 gs_quant/timeseries/statistics.py exponential_std', gs_timeseries_exponential_std().canonical, 'fin_exponential_std');
SELECT assert_eq('gs quant compatibility 1622 gs_quant/timeseries/statistics.py var', gs_timeseries_var().canonical, 'fin_var');
SELECT assert_eq('gs quant compatibility 1623 gs_quant/timeseries/statistics.py cov', gs_timeseries_cov().canonical, 'fin_cov');
SELECT assert_eq('gs quant compatibility 1624 gs_quant/timeseries/statistics.py zscores', gs_timeseries_zscores().canonical, 'fin_zscores');
SELECT assert_eq('gs quant compatibility 1625 gs_quant/timeseries/statistics.py winsorize', gs_timeseries_winsorize().canonical, 'fin_winsorize');
SELECT assert_eq('gs quant compatibility 1626 gs_quant/timeseries/statistics.py generate_series', gs_timeseries_generate_series().canonical, 'fin_generate_series');
SELECT assert_eq('gs quant compatibility 1627 gs_quant/timeseries/statistics.py generate_series_intraday', gs_timeseries_generate_series_intraday().canonical, 'fin_generate_series_intraday');
SELECT assert_eq('gs quant compatibility 1628 gs_quant/timeseries/statistics.py percentiles', gs_timeseries_percentiles().canonical, 'fin_percentiles');
SELECT assert_eq('gs quant compatibility 1629 gs_quant/timeseries/statistics.py percentile', gs_timeseries_percentile().canonical, 'fin_percentile');
SELECT assert_eq('gs quant compatibility 1630 gs_quant/timeseries/tca.py covariance', gs_timeseries_covariance().canonical, 'fin_covariance');
SELECT assert_eq('gs quant compatibility 1631 gs_quant/timeseries/technicals.py moving_average', gs_timeseries_moving_average().canonical, 'fin_moving_average');
SELECT assert_eq('gs quant compatibility 1632 gs_quant/timeseries/technicals.py bollinger_bands', gs_timeseries_bollinger_bands().canonical, 'fin_bollinger_bands');
SELECT assert_eq('gs quant compatibility 1633 gs_quant/timeseries/technicals.py smoothed_moving_average', gs_timeseries_smoothed_moving_average().canonical, 'fin_smoothed_moving_average');
SELECT assert_eq('gs quant compatibility 1634 gs_quant/timeseries/technicals.py relative_strength_index', gs_timeseries_relative_strength_index().canonical, 'fin_relative_strength_index');
SELECT assert_eq('gs quant compatibility 1635 gs_quant/timeseries/technicals.py exponential_moving_average', gs_timeseries_exponential_moving_average().canonical, 'fin_exponential_moving_average');
SELECT assert_eq('gs quant compatibility 1636 gs_quant/timeseries/technicals.py macd', gs_timeseries_macd().canonical, 'fin_macd');
SELECT assert_eq('gs quant compatibility 1637 gs_quant/timeseries/technicals.py exponential_volatility', gs_timeseries_exponential_volatility().canonical, 'fin_exponential_volatility');
SELECT assert_eq('gs quant compatibility 1638 gs_quant/timeseries/technicals.py exponential_spread_volatility', gs_timeseries_exponential_spread_volatility().canonical, 'fin_exponential_spread_volatility');
SELECT assert_eq('gs quant compatibility 1639 gs_quant/timeseries/technicals.py seasonally_adjusted', gs_timeseries_seasonally_adjusted().canonical, 'fin_seasonally_adjusted');
SELECT assert_eq('gs quant compatibility 1640 gs_quant/timeseries/technicals.py trend', gs_timeseries_trend().canonical, 'fin_trend');
SELECT assert_eq('gs quant compatibility 1641 gs_quant/tracing/tracing.py parse_tracing_line_args', gs_support_parse_tracing_line_args().canonical, 'fin_gsq_support_parse_tracing_line_args');
-- END GENERATED GS QUANT SURFACE TESTS
