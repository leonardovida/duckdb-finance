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
