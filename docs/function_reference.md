---
layout: default
title: Function Reference
description: Every registered DuckDB Finance fin_* function with usage and return notes.
permalink: /function-reference/
nav_order: 4
reference_search: true
wide: true
---

# Finance Function Reference

This document is generated from the extension registration surface in `src/` and the executable SQL coverage in `test/sql/`. All functions live in the `fin_` namespace and use standard DuckDB types such as `DOUBLE`, `VARCHAR`, `DATE`, `TIMESTAMP`, `LIST`, `STRUCT`, and table results.

## Usage Conventions

- Load the extension before use, for example:
  `INSTALL finance FROM community; LOAD finance;`.
- Scalar functions are called in ordinary `SELECT` expressions.
- Aggregate macros are called over grouped rows, for example `SELECT fin_total_return(r) FROM returns;`.
- Table functions and bind-replace functions appear in `FROM`, for example `SELECT * FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');`.
- Several broad compatibility entries are v1 aliases or placeholders. Those entries are documented explicitly as placeholders and are covered by tests so future implementations can be swapped in behind stable names.
- `make check` verifies this reference against every registered `fin_*` function and verifies that every registered function appears in the gold SQL tests. The checks scan split `.cpp` and `.inc` source units under `src/`.

## GS Quant Source-Name Compatibility

These entries preserve names from GS Quant's portable `timeseries` and
`datetime` helper modules where a SQL shape is practical. Most are aliases over
the canonical `fin_*` implementation already documented below; entries marked
as v1 placeholders intentionally keep a stable callable surface while local
SQL-native semantics mature.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_abs` | `fin_abs(x)` | GS Quant `algebra.abs_` compatibility. | Scalar alias for `abs`. |
| `fin_abs_` | `fin_abs_(x)` | Exact GS Quant `algebra.abs_` source-name compatibility. | Scalar alias for `abs`. |
| `fin_add` | `fin_add(x, y, method := 'intersect')` | GS Quant `algebra.add` compatibility. | Scalar arithmetic alias. |
| `fin_align` | `fin_align(x, y := NULL, method := 'intersect')` | GS Quant `timeseries.datetime.align` compatibility. | v1 pass-through placeholder. |
| `fin_align_calendar` | `fin_align_calendar(x, calendar := 'weekday')` | GS Quant `timeseries.datetime.align_calendar` compatibility. | v1 pass-through placeholder. |
| `fin_and` | `fin_and(flag)` | GS Quant `algebra.and_` compatibility. | Aggregate boolean alias. |
| `fin_and_` | `fin_and_(flag)` | Exact GS Quant `algebra.and_` source-name compatibility. | Aggregate boolean alias. |
| `fin_append` | `fin_append(x, y := NULL)` | GS Quant `timeseries.datetime.append` compatibility. | v1 pass-through placeholder. |
| `fin_annualize` | `fin_annualize(x, annualization := 252)` | GS Quant `econometrics.annualize` compatibility. | Aggregate v1 alias. |
| `fin_bollinger_bands` | `fin_bollinger_bands(close, w := NULL, k := 2.0)` | GS Quant `technicals.bollinger_bands` compatibility. | STRUCT alias for `fin_bbands`. |
| `fin_business_day_count` | `fin_business_day_count(begin_date, end_date, calendar := 'weekday')` | GS Quant `datetime.date.business_day_count` compatibility. | Scalar alias for local weekday calendar count. |
| `fin_business_day_offset` | `fin_business_day_offset(date, offsets := 1, calendar := 'weekday')` | GS Quant `datetime.date.business_day_offset` compatibility. | Scalar weekday-calendar alias. |
| `fin_ceil` | `fin_ceil(x, value := NULL)` | GS Quant `algebra.ceil` compatibility. | Scalar rounding alias. |
| `fin_change` | `fin_change(x)` | GS Quant `econometrics.change` compatibility. | Aggregate first/last difference alias. |
| `fin_compare` | `fin_compare(x, y, method := 'diff')` | GS Quant `analysis.compare` compatibility. | Scalar diff/ratio helper. |
| `fin_consecutive` | `fin_consecutive(x, direction := 'any')` | GS Quant `analysis.consecutive` compatibility. | Aggregate v1 placeholder count. |
| `fin_corr_swap_correlation` | `fin_corr_swap_correlation(x, y, n_days := 252, assume_zero_mean := false)` | GS Quant `econometrics.corr_swap_correlation` compatibility. | Aggregate correlation alias. |
| `fin_correlation` | `fin_correlation(x, y, w := NULL, type := 'levels', returns_type := 'simple', assume_zero_mean := false)` | GS Quant `econometrics.correlation` compatibility. | Aggregate correlation alias. |
| `fin_count` | `fin_count(x)` | GS Quant `analysis.count` compatibility. | Aggregate count alias. |
| `fin_cov` | `fin_cov(x, y, w := NULL)` | GS Quant `statistics.cov` compatibility. | Aggregate covariance alias. |
| `fin_bucketize` | `fin_bucketize(x, aggregate_function := 'mean', period := 'month')` | GS Quant `timeseries.datetime.bucketize` compatibility. | v1 pass-through placeholder. |
| `fin_date_range` | `fin_date_range(begin_date, end_date, calendar := 'weekday')` | GS Quant `timeseries.datetime.date_range` compatibility. | LIST of dates/timestamps. |
| `fin_day` | `fin_day(x)` | GS Quant `timeseries.datetime.day` compatibility. | Date-part scalar. |
| `fin_day_count` | `fin_day_count(first_date, second_date)` | GS Quant `timeseries.datetime.day_count` compatibility. | Calendar day difference. |
| `fin_day_count_fraction` | `fin_day_count_fraction(start_date, end_date, convention := 'ACT/365F', frequency := 1)` | GS Quant day-count-fraction compatibility. | Scalar alias for `fin_yearfrac`. |
| `fin_day_count_fractions` | `fin_day_count_fractions(dates, convention := 'ACT/365F', frequency := 1)` | GS Quant `timeseries.datetime.day_count_fractions` compatibility. | NULL v1 placeholder for series day counts. |
| `fin_day_countdown` | `fin_day_countdown(end_date, start_date := current_date, business_days := false, calendar := 'weekday')` | GS Quant `timeseries.datetime.day_countdown` compatibility. | Scalar countdown helper. |
| `fin_diff` | `fin_diff(x, obs := 1)` | GS Quant `analysis.diff` compatibility. | Aggregate first/last difference alias. |
| `fin_divide` | `fin_divide(x, y, method := 'intersect')` | GS Quant `algebra.divide` compatibility. | Scalar safe division alias. |
| `fin_exponential_moving_average` | `fin_exponential_moving_average(close, beta := 0.75)` | GS Quant `technicals.exponential_moving_average` compatibility. | Aggregate v1 alias for `fin_ema`. |
| `fin_exponential_spread_volatility` | `fin_exponential_spread_volatility(spread, beta := 0.75)` | GS Quant `technicals.exponential_spread_volatility` compatibility. | Aggregate EWMA volatility alias. |
| `fin_exponential_std` | `fin_exponential_std(x, beta := 0.75)` | GS Quant `statistics.exponential_std` compatibility. | Aggregate EWMA stddev alias. |
| `fin_exponential_volatility` | `fin_exponential_volatility(r, beta := 0.75)` | GS Quant `technicals.exponential_volatility` compatibility. | Aggregate EWMA volatility alias. |
| `fin_exp` | `fin_exp(x)` | GS Quant `algebra.exp` compatibility. | Scalar exponential alias. |
| `fin_filter` | `fin_filter(x, op, value)` | GS Quant `algebra.filter_` compatibility. | Scalar predicate filter. |
| `fin_filter_` | `fin_filter_(x, op, value)` | Exact GS Quant `algebra.filter_` source-name compatibility. | Scalar predicate filter. |
| `fin_filter_dates` | `fin_filter_dates(x, op, dates)` | GS Quant `algebra.filter_dates` compatibility. | v1 pass-through placeholder. |
| `fin_first` | `fin_first(x)` | GS Quant `analysis.first` compatibility. | Aggregate first-value alias. |
| `fin_floor` | `fin_floor(x, value := NULL)` | GS Quant `algebra.floor` compatibility. | Scalar rounding alias. |
| `fin_floordiv` | `fin_floordiv(x, y, method := 'intersect')` | GS Quant `algebra.floordiv` compatibility. | Scalar floor-division alias. |
| `fin_geometrically_aggregate` | `fin_geometrically_aggregate(r)` | GS Quant `algebra.geometrically_aggregate` compatibility. | Aggregate alias for `fin_total_return`. |
| `fin_generate_series` | `fin_generate_series(length, direction := 'start_today')` | GS Quant `statistics.generate_series` compatibility. | LIST v1 index sequence. |
| `fin_generate_series_intraday` | `fin_generate_series_intraday(length, direction := 'start_today')` | GS Quant `statistics.generate_series_intraday` compatibility. | LIST v1 index sequence. |
| `fin_has_feb_29` | `fin_has_feb_29(start_date, end_date)` | GS Quant `datetime.date.has_feb_29` compatibility. | Scalar v1 leap-day helper. |
| `fin_if` | `fin_if(flag, x, y)` | GS Quant `algebra.if_` compatibility. | Scalar CASE alias. |
| `fin_if_` | `fin_if_(flag, x, y)` | Exact GS Quant `algebra.if_` source-name compatibility. | Scalar CASE alias. |
| `fin_index` | `fin_index(x, initial := 1.0)` | GS Quant `econometrics.index` compatibility. | Aggregate index-level alias. |
| `fin_interpolate` | `fin_interpolate(x, dates := NULL, method := 'linear')` | GS Quant `timeseries.datetime.interpolate` compatibility. | v1 pass-through placeholder. |
| `fin_lag` | `fin_lag(x, obs := 1, mode := 'before')` | GS Quant `analysis.lag` compatibility. | Aggregate v1 alias. |
| `fin_last` | `fin_last(x)` | GS Quant `analysis.last` compatibility. | Aggregate last-value alias. |
| `fin_last_value` | `fin_last_value(x)` | GS Quant `analysis.last_value` compatibility. | Aggregate alias for `last`. |
| `fin_log` | `fin_log(x)` | GS Quant `algebra.log` compatibility. | Scalar natural-log alias. |
| `fin_max` | `fin_max(x, w := NULL)` | GS Quant `statistics.max_` compatibility. | Aggregate max alias. |
| `fin_max_` | `fin_max_(x, w := NULL)` | Exact GS Quant `statistics.max_` source-name compatibility. | Aggregate max alias. |
| `fin_mean` | `fin_mean(x, w := NULL, mean_type := 'arithmetic')` | GS Quant `statistics.mean` compatibility. | Aggregate average alias. |
| `fin_median` | `fin_median(x, w := NULL)` | GS Quant `statistics.median` compatibility. | Aggregate median alias. |
| `fin_min` | `fin_min(x, w := NULL)` | GS Quant `statistics.min_` compatibility. | Aggregate min alias. |
| `fin_min_` | `fin_min_(x, w := NULL)` | Exact GS Quant `statistics.min_` source-name compatibility. | Aggregate min alias. |
| `fin_mode` | `fin_mode(x, w := NULL)` | GS Quant `statistics.mode` compatibility. | Aggregate mode alias. |
| `fin_month` | `fin_month(x)` | GS Quant `timeseries.datetime.month` compatibility. | Date-part scalar. |
| `fin_moving_average` | `fin_moving_average(x, w := NULL)` | GS Quant `technicals.moving_average` compatibility. | Aggregate alias for `fin_sma`. |
| `fin_multiply` | `fin_multiply(x, y, method := 'intersect')` | GS Quant `algebra.multiply` compatibility. | Scalar arithmetic alias. |
| `fin_not` | `fin_not(x)` | GS Quant `algebra.not_` compatibility. | Scalar boolean alias. |
| `fin_not_` | `fin_not_(x)` | Exact GS Quant `algebra.not_` source-name compatibility. | Scalar boolean alias. |
| `fin_or` | `fin_or(flag)` | GS Quant `algebra.or_` compatibility. | Aggregate boolean alias. |
| `fin_or_` | `fin_or_(flag)` | Exact GS Quant `algebra.or_` source-name compatibility. | Aggregate boolean alias. |
| `fin_percentile` | `fin_percentile(x, n, w := NULL)` | GS Quant `statistics.percentile` compatibility. | Aggregate quantile alias. |
| `fin_percentiles` | `fin_percentiles(x, y := NULL, w := NULL)` | GS Quant `statistics.percentiles` compatibility. | Window percent-rank alias. |
| `fin_point_sort_order` | `fin_point_sort_order(point, ref_date := current_date)` | GS Quant `datetime.point.point_sort_order` compatibility. | v1 point-order helper. |
| `fin_power` | `fin_power(x, y)` | GS Quant `algebra.power` compatibility. | Scalar power alias. |
| `fin_prepend` | `fin_prepend(x, y := NULL)` | GS Quant `timeseries.datetime.prepend` compatibility. | v1 pass-through placeholder. |
| `fin_prev_business_date` | `fin_prev_business_date(date, calendar := 'weekday')` | GS Quant `datetime.date.prev_business_date` compatibility. | Scalar weekday-calendar alias. |
| `fin_prices` | `fin_prices(r, initial := 1.0, method := 'simple')` | GS Quant `econometrics.prices` compatibility. | Aggregate v1 price-index alias. |
| `fin_product` | `fin_product(x, w := NULL)` | GS Quant `statistics.product` compatibility. | Aggregate product alias. |
| `fin_quarter` | `fin_quarter(x)` | GS Quant `timeseries.datetime.quarter` compatibility. | Date-part scalar. |
| `fin_range` | `fin_range(x, w := NULL)` | GS Quant `statistics.range_` compatibility. | Aggregate max-minus-min alias. |
| `fin_range_` | `fin_range_(x, w := NULL)` | Exact GS Quant `statistics.range_` source-name compatibility. | Aggregate max-minus-min alias. |
| `fin_relative_date_add` | `fin_relative_date_add(date_rule, strict := false)` | GS Quant `datetime.point.relative_date_add` compatibility. | Scalar v1 relative-day conversion. |
| `fin_relative_strength_index` | `fin_relative_strength_index(close, w := 14)` | GS Quant `technicals.relative_strength_index` compatibility. | Aggregate alias for `fin_rsi`. |
| `fin_repeat` | `fin_repeat(x, n := 1)` | GS Quant `analysis.repeat` compatibility. | v1 pass-through placeholder. |
| `fin_returns` | `fin_returns(price, prev_price, method := 'simple')` | GS Quant `econometrics.returns` compatibility. | Scalar pairwise return alias. |
| `fin_seasonally_adjusted` | `fin_seasonally_adjusted(x, method := 'additive', freq := 'year')` | GS Quant `technicals.seasonally_adjusted` compatibility. | v1 pass-through placeholder. |
| `fin_smooth_outliers` | `fin_smooth_outliers(x, threshold := 3.0)` | GS Quant `analysis.smooth_outliers` compatibility. | Aggregate v1 smoothing placeholder. |
| `fin_smooth_spikes` | `fin_smooth_spikes(x, threshold := 3.0, threshold_type := 'percentage')` | GS Quant `analysis.smooth_spikes` compatibility. | v1 pass-through placeholder. |
| `fin_smoothed_moving_average` | `fin_smoothed_moving_average(close, w := NULL)` | GS Quant `technicals.smoothed_moving_average` compatibility. | Aggregate alias for `fin_sma`. |
| `fin_sqrt` | `fin_sqrt(x)` | GS Quant `algebra.sqrt` compatibility. | Scalar square-root alias. |
| `fin_std` | `fin_std(x, w := NULL)` | GS Quant `statistics.std` compatibility. | Aggregate sample-standard-deviation alias. |
| `fin_subtract` | `fin_subtract(x, y, method := 'intersect')` | GS Quant `algebra.subtract` compatibility. | Scalar arithmetic alias. |
| `fin_sum` | `fin_sum(x, w := NULL)` | GS Quant `statistics.sum_` compatibility. | Aggregate stable-sum alias. |
| `fin_sum_` | `fin_sum_(x, w := NULL)` | Exact GS Quant `statistics.sum_` source-name compatibility. | Aggregate stable-sum alias. |
| `fin_time_difference_as_string` | `fin_time_difference_as_string(seconds, resolution := 'Second')` | GS Quant `datetime.time.time_difference_as_string` compatibility. | Scalar v1 duration string helper. |
| `fin_today` | `fin_today(location := NULL)` | GS Quant `datetime.date.today` compatibility. | Scalar alias for local `current_date`. |
| `fin_to_zulu_string` | `fin_to_zulu_string(ts)` | GS Quant `datetime.time.to_zulu_string` compatibility. | Scalar timestamp formatting helper. |
| `fin_trend` | `fin_trend(x, method := 'additive', freq := 'year')` | GS Quant `technicals.trend` compatibility. | STRUCT v1 alias for `fin_linear_trend`. |
| `fin_union` | `fin_union(x, y := NULL)` | GS Quant `timeseries.datetime.union` compatibility. | v1 pass-through placeholder. |
| `fin_value` | `fin_value(x, date := NULL, method := 'step')` | GS Quant `timeseries.datetime.value` compatibility. | Aggregate last-value alias. |
| `fin_vol_swap_volatility` | `fin_vol_swap_volatility(r, n_days := 252, annualization := 252, assume_zero_mean := false)` | GS Quant `econometrics.vol_swap_volatility` compatibility. | Aggregate volatility alias. |
| `fin_weekday` | `fin_weekday(x)` | GS Quant `timeseries.datetime.weekday` compatibility. | Monday-zero date-part scalar. |
| `fin_weighted_sum` | `fin_weighted_sum(x, w)` | GS Quant `algebra.weighted_sum` compatibility. | Aggregate weighted-sum alias. |
| `fin_winsorize` | `fin_winsorize(x, threshold := 2.5, w := NULL)` | GS Quant `statistics.winsorize` compatibility. | Aggregate v1 placeholder. |
| `fin_year` | `fin_year(x)` | GS Quant `timeseries.datetime.year` compatibility. | Date-part scalar. |
| `fin_zscores` | `fin_zscores(x, w := NULL)` | GS Quant `statistics.zscores` compatibility. | Aggregate last-zscore alias. |

### GS Quant Portfolio Measure Compatibility

These names mirror `gs_quant.timeseries.measures_portfolios`. They operate on
local SQL series supplied by the caller instead of fetching entitled Marquee
portfolio reports.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_aum` | `fin_aum(value)` | Custom AUM measure compatibility. | Aggregate last-value alias. |
| `fin_portfolio_factor_exposure` | `fin_portfolio_factor_exposure(value, factor_name := NULL, unit := 'Notional')` | Portfolio factor exposure compatibility. | Aggregate v1 alias. |
| `fin_portfolio_factor_pnl` | `fin_portfolio_factor_pnl(value, factor_name := NULL, unit := 'Notional')` | Portfolio factor PnL compatibility. | Aggregate sum alias. |
| `fin_portfolio_factor_proportion_of_risk` | `fin_portfolio_factor_proportion_of_risk(value, factor_name := NULL)` | Factor proportion of risk compatibility. | Aggregate v1 alias. |
| `fin_portfolio_daily_risk` | `fin_portfolio_daily_risk(risk, factor_name := 'Total')` | Daily risk compatibility. | Aggregate v1 alias. |
| `fin_portfolio_annual_risk` | `fin_portfolio_annual_risk(risk, factor_name := 'Total', annualization := 252)` | Annual risk compatibility. | Annualized aggregate alias. |
| `fin_portfolio_thematic_exposure` | `fin_portfolio_thematic_exposure(value, basket_ticker := NULL)` | Thematic exposure compatibility. | Aggregate v1 alias. |
| `fin_portfolio_pnl` | `fin_portfolio_pnl(pnl, unit := 'Notional')` | Portfolio PnL compatibility. | Aggregate sum alias. |
| `fin_portfolio_hit_rate` | `fin_portfolio_hit_rate(r, rolling_window := NULL)` | Portfolio hit rate compatibility. | Alias for `fin_hit_ratio`. |
| `fin_portfolio_max_drawdown` | `fin_portfolio_max_drawdown(r, rolling_window := NULL)` | Portfolio max drawdown compatibility. | Alias for `fin_max_drawdown`. |
| `fin_portfolio_drawdown_length` | `fin_portfolio_drawdown_length(r, rolling_window := NULL)` | Drawdown length compatibility. | Alias for `fin_drawdown_duration`. |
| `fin_portfolio_max_recovery_period` | `fin_portfolio_max_recovery_period(r, rolling_window := NULL)` | Max recovery period compatibility. | Alias for `fin_drawdown_duration`. |
| `fin_portfolio_standard_deviation` | `fin_portfolio_standard_deviation(r, rolling_window := NULL)` | Portfolio standard deviation compatibility. | Aggregate stddev alias. |
| `fin_portfolio_downside_risk` | `fin_portfolio_downside_risk(r, rolling_window := NULL, annualization := 252)` | Portfolio downside risk compatibility. | Alias for downside deviation. |
| `fin_portfolio_semi_variance` | `fin_portfolio_semi_variance(r, rolling_window := NULL)` | Portfolio semi variance compatibility. | Alias for semivariance. |
| `fin_portfolio_kurtosis` | `fin_portfolio_kurtosis(r, rolling_window := NULL)` | Portfolio kurtosis compatibility. | Aggregate kurtosis alias. |
| `fin_portfolio_skewness` | `fin_portfolio_skewness(r, rolling_window := NULL)` | Portfolio skewness compatibility. | Aggregate skewness alias. |
| `fin_portfolio_realized_var` | `fin_portfolio_realized_var(r, rolling_window := NULL, confidence := 0.95)` | Portfolio realized VaR compatibility. | Alias for `fin_var`. |
| `fin_portfolio_tracking_error` | `fin_portfolio_tracking_error(r, benchmark_r, rolling_window := NULL, annualization := 252)` | Portfolio tracking error compatibility. | Alias for `fin_tracking_error`. |
| `fin_portfolio_tracking_error_bear` | `fin_portfolio_tracking_error_bear(r, benchmark_r, rolling_window := NULL, annualization := 252)` | Bear-market tracking error compatibility. | Filtered aggregate alias. |
| `fin_portfolio_tracking_error_bull` | `fin_portfolio_tracking_error_bull(r, benchmark_r, rolling_window := NULL, annualization := 252)` | Bull-market tracking error compatibility. | Filtered aggregate alias. |
| `fin_portfolio_sharpe_ratio` | `fin_portfolio_sharpe_ratio(r, risk_free := 0.0, annualization := 252)` | Portfolio Sharpe ratio compatibility. | Alias for `fin_sharpe`. |
| `fin_portfolio_calmar_ratio` | `fin_portfolio_calmar_ratio(r, annualization := 252)` | Portfolio Calmar ratio compatibility. | Alias for `fin_calmar`. |
| `fin_portfolio_sortino_ratio` | `fin_portfolio_sortino_ratio(r, mar := 0.0, annualization := 252)` | Portfolio Sortino ratio compatibility. | Alias for `fin_sortino`. |
| `fin_portfolio_information_ratio` | `fin_portfolio_information_ratio(r, benchmark_r, annualization := 252)` | Portfolio information ratio compatibility. | Alias for `fin_information_ratio`. |
| `fin_portfolio_information_ratio_bull` | `fin_portfolio_information_ratio_bull(r, benchmark_r, annualization := 252)` | Bull-market information ratio compatibility. | Filtered aggregate alias. |
| `fin_portfolio_information_ratio_bear` | `fin_portfolio_information_ratio_bear(r, benchmark_r, annualization := 252)` | Bear-market information ratio compatibility. | Filtered aggregate alias. |
| `fin_portfolio_modigliani_ratio` | `fin_portfolio_modigliani_ratio(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Portfolio Modigliani ratio compatibility. | Local Sharpe-scaled alias. |
| `fin_portfolio_treynor_measure` | `fin_portfolio_treynor_measure(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Portfolio Treynor measure compatibility. | Alias for Treynor ratio. |
| `fin_portfolio_jensen_alpha` | `fin_portfolio_jensen_alpha(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Portfolio Jensen alpha compatibility. | Alias for `fin_jensen_alpha`. |
| `fin_portfolio_jensen_alpha_bear` | `fin_portfolio_jensen_alpha_bear(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Bear-market Jensen alpha compatibility. | v1 alias for full-sample Jensen alpha. |
| `fin_portfolio_jensen_alpha_bull` | `fin_portfolio_jensen_alpha_bull(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Bull-market Jensen alpha compatibility. | v1 alias for full-sample Jensen alpha. |
| `fin_portfolio_alpha` | `fin_portfolio_alpha(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Portfolio alpha compatibility. | Alias for `fin_alpha`. |
| `fin_portfolio_beta` | `fin_portfolio_beta(r, benchmark_r)` | Portfolio beta compatibility. | Alias for `fin_beta`. |
| `fin_portfolio_correlation` | `fin_portfolio_correlation(r, benchmark_r)` | Portfolio correlation compatibility. | Aggregate correlation alias. |
| `fin_portfolio_r_squared` | `fin_portfolio_r_squared(r, benchmark_r)` | Portfolio R-squared compatibility. | Squared correlation alias. |
| `fin_portfolio_capture_ratio` | `fin_portfolio_capture_ratio(r, benchmark_r, direction := 'all')` | Portfolio capture ratio compatibility. | Aggregate capture alias. |

### GS Quant Report Measure Compatibility

These names mirror `gs_quant.timeseries.measures_reports` and use local SQL
series supplied by the caller.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_factor_exposure` | `fin_factor_exposure(value, factor_name := NULL, unit := 'Notional')` | Report factor exposure compatibility. | Aggregate v1 alias. |
| `fin_factor_pnl` | `fin_factor_pnl(value, factor_name := NULL, unit := 'Notional')` | Report factor PnL compatibility. | Aggregate sum alias. |
| `fin_factor_proportion_of_risk` | `fin_factor_proportion_of_risk(value, factor_name := NULL)` | Report factor proportion of risk compatibility. | Aggregate v1 alias. |
| `fin_daily_risk` | `fin_daily_risk(risk, factor_name := 'Total')` | Report daily risk compatibility. | Aggregate v1 alias. |
| `fin_annual_risk` | `fin_annual_risk(risk, factor_name := 'Total', annualization := 252)` | Report annual risk compatibility. | Annualized aggregate alias. |
| `fin_normalized_performance` | `fin_normalized_performance(value, initial := 100.0)` | Report normalized performance compatibility. | Aggregate index-level alias. |
| `fin_long_pnl` | `fin_long_pnl(pnl)` | Report long PnL compatibility. | Positive PnL sum alias. |
| `fin_short_pnl` | `fin_short_pnl(pnl)` | Report short PnL compatibility. | Negative PnL sum alias. |
| `fin_thematic_exposure` | `fin_thematic_exposure(value, basket_ticker := NULL)` | Report thematic exposure compatibility. | Aggregate v1 alias. |
| `fin_thematic_beta` | `fin_thematic_beta(r, thematic_r)` | Report thematic beta compatibility. | Alias for `fin_beta`. |
| `fin_pnl` | `fin_pnl(pnl, unit := 'Notional')` | Report PnL compatibility. | Aggregate sum alias. |
| `fin_historical_simulation_estimated_pnl` | `fin_historical_simulation_estimated_pnl(pnl)` | Historical simulation PnL compatibility. | Aggregate sum alias. |
| `fin_historical_simulation_estimated_factor_attribution` | `fin_historical_simulation_estimated_factor_attribution(value, factor_name := NULL)` | Historical simulation factor attribution compatibility. | Aggregate v1 alias. |
| `fin_hit_rate` | `fin_hit_rate(r, rolling_window := NULL)` | Report hit rate compatibility. | Alias for `fin_hit_ratio`. |
| `fin_drawdown_length` | `fin_drawdown_length(r, rolling_window := NULL)` | Report drawdown length compatibility. | Alias for drawdown duration. |
| `fin_max_recovery_period` | `fin_max_recovery_period(r, rolling_window := NULL)` | Report max recovery period compatibility. | Alias for drawdown duration. |
| `fin_standard_deviation` | `fin_standard_deviation(r, rolling_window := NULL)` | Report standard deviation compatibility. | Aggregate stddev alias. |
| `fin_downside_risk` | `fin_downside_risk(r, rolling_window := NULL, annualization := 252)` | Report downside risk compatibility. | Alias for downside deviation. |
| `fin_semi_variance` | `fin_semi_variance(r, rolling_window := NULL)` | Report semi variance compatibility. | Alias for semivariance. |
| `fin_kurtosis` | `fin_kurtosis(r, rolling_window := NULL)` | Report kurtosis compatibility. | Aggregate kurtosis alias. |
| `fin_skewness` | `fin_skewness(r, rolling_window := NULL)` | Report skewness compatibility. | Aggregate skewness alias. |
| `fin_realized_var` | `fin_realized_var(r, rolling_window := NULL, confidence := 0.95)` | Report realized VaR compatibility. | Alias for `fin_var`. |
| `fin_tracking_error_bear` | `fin_tracking_error_bear(r, benchmark_r, rolling_window := NULL, annualization := 252)` | Report bear tracking error compatibility. | Filtered aggregate alias. |
| `fin_tracking_error_bull` | `fin_tracking_error_bull(r, benchmark_r, rolling_window := NULL, annualization := 252)` | Report bull tracking error compatibility. | Filtered aggregate alias. |
| `fin_calmar_ratio` | `fin_calmar_ratio(r, annualization := 252)` | Report Calmar ratio compatibility. | Alias for `fin_calmar`. |
| `fin_sortino_ratio` | `fin_sortino_ratio(r, mar := 0.0, annualization := 252)` | Report Sortino ratio compatibility. | Alias for `fin_sortino`. |
| `fin_jensen_alpha_bear` | `fin_jensen_alpha_bear(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Report bear Jensen alpha compatibility. | v1 full-sample alias. |
| `fin_jensen_alpha_bull` | `fin_jensen_alpha_bull(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Report bull Jensen alpha compatibility. | v1 full-sample alias. |
| `fin_information_ratio_bear` | `fin_information_ratio_bear(r, benchmark_r, annualization := 252)` | Report bear information ratio compatibility. | Filtered aggregate alias. |
| `fin_information_ratio_bull` | `fin_information_ratio_bull(r, benchmark_r, annualization := 252)` | Report bull information ratio compatibility. | Filtered aggregate alias. |
| `fin_modigliani_ratio` | `fin_modigliani_ratio(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Report Modigliani ratio compatibility. | Local Sharpe-scaled alias. |
| `fin_treynor_measure` | `fin_treynor_measure(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Report Treynor measure compatibility. | Alias for Treynor ratio. |
| `fin_capture_ratio` | `fin_capture_ratio(r, benchmark_r, direction := 'all')` | Report capture ratio compatibility. | Aggregate capture alias. |
| `fin_r_squared` | `fin_r_squared(r, benchmark_r)` | Report R-squared compatibility. | Squared correlation alias. |

### GS Quant Market Measure Compatibility

These entries represent smaller GS Quant `timeseries` market-data modules whose
Python implementations fetch entitled Marquee datasets. The DuckDB forms operate
on local SQL series supplied by the caller and keep exact source names where
possible; display-name aliases are included when GS Quant exposes a different
plot name.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_basket_series` | `fin_basket_series(r, weight := NULL, cost := 0.0, rebal_freq := 'daily', return_type := 'excess_return')` | GS Quant `backtesting.basket_series` compatibility. | Weighted aggregate return minus supplied costs. |
| `fin_covariance` | `fin_covariance(x, y, bucket_start := '08:00:00', bucket_end := '08:30:00')` | GS Quant `tca.covariance` compatibility. | Aggregate covariance over local series. |
| `fin_crosscurrency_swap_rate` | `fin_crosscurrency_swap_rate(spread, swap_tenor := NULL, rateoption_type := NULL, forward_tenor := NULL)` | GS Quant `measures_xccy.crosscurrency_swap_rate` compatibility. | Last-value local xccy spread alias. |
| `fin_forward_point` | `fin_forward_point(points, settlement_date := NULL, location := NULL)` | GS Quant FX-vol display-name compatibility for `forward_point`. | Last-value alias for forward points. |
| `fin_fwd_points` | `fin_fwd_points(points, settlement_date := NULL, location := NULL)` | GS Quant `measures_fx_vol.fwd_points` compatibility. | Last-value local forward-points alias. |
| `fin_implied_volatility` | `fin_implied_volatility(vol, tenor := NULL, strike_reference := NULL, relative_strike := NULL)` | GS Quant FX-vol display-name compatibility for `implied_volatility`. | Last-value local volatility alias. |
| `fin_implied_volatility_fxvol` | `fin_implied_volatility_fxvol(vol, tenor := NULL, strike_reference := NULL, relative_strike := NULL)` | GS Quant `measures_fx_vol.implied_volatility_fxvol` compatibility. | Last-value local volatility alias. |
| `fin_inflation_swap_rate` | `fin_inflation_swap_rate(rate, swap_tenor := NULL, index_type := NULL, forward_tenor := NULL)` | GS Quant `measures_inflation.inflation_swap_rate` compatibility. | Last-value local inflation-swap-rate alias. |
| `fin_inflation_swap_term` | `fin_inflation_swap_term(rate, index_type := NULL, forward_tenor := NULL, pricing_date := NULL)` | GS Quant `measures_inflation.inflation_swap_term` compatibility. | Last-value local term-structure alias. |
| `fin_spot_carry` | `fin_spot_carry(forward_points, spot := 1.0, tenor_days := 365.0, annualized := 'daily')` | GS Quant `measures_fx_vol.spot_carry` compatibility. | Average forward-points-to-spot carry, optionally annualized. |
| `fin_vol_swap_strike` | `fin_vol_swap_strike(strike_vol, expiry_tenor := NULL, strike_type := NULL)` | GS Quant `measures_fx_vol.vol_swap_strike` compatibility. | Last-value local vol-swap strike alias. |

### GS Quant Rates Measure Compatibility

These names mirror additional decorated functions in
`gs_quant.timeseries.measures_rates`. The Python source retrieves rates,
swaption, curve, OIS, and policy-rate datasets. The DuckDB forms operate on
local SQL series and preserve the market-data parameters as optional metadata
arguments.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_basis_swap_spread` | `fin_basis_swap_spread(spread, swap_tenor := NULL, spread_benchmark_type := NULL, spread_tenor := NULL)` | GS Quant basis swap spread compatibility. | Last-value local spread alias. |
| `fin_basis_swap_term_structure` | `fin_basis_swap_term_structure(spread, spread_benchmark_type := NULL, spread_tenor := NULL, reference_benchmark_type := NULL)` | GS Quant basis swap term-structure compatibility. | Last-value local spread alias. |
| `fin_index_forward_rate` | `fin_index_forward_rate(rate, forward_start_tenor := NULL, benchmark_type := NULL, fixing_tenor := NULL)` | GS Quant index forward rate compatibility. | Last-value local rate alias. |
| `fin_instantaneous_forward_rate` | `fin_instantaneous_forward_rate(rate, tenor := NULL, csa := NULL, close_location := NULL)` | GS Quant instantaneous forward rate compatibility. | Last-value local rate alias. |
| `fin_midcurve_annuity` | `fin_midcurve_annuity(annuity, expiration_tenor := NULL, forward_tenor := NULL, termination_tenor := NULL)` | GS Quant midcurve annuity compatibility. | Last-value local annuity alias. |
| `fin_midcurve_atm_fwd_rate` | `fin_midcurve_atm_fwd_rate(rate, expiration_tenor := NULL, forward_tenor := NULL, termination_tenor := NULL)` | GS Quant midcurve ATM forward rate compatibility. | Last-value local rate alias. |
| `fin_midcurve_premium` | `fin_midcurve_premium(premium, expiration_tenor := NULL, forward_tenor := NULL, termination_tenor := NULL)` | GS Quant midcurve premium compatibility. | Last-value local premium alias. |
| `fin_midcurve_vol` | `fin_midcurve_vol(vol, expiration_tenor := NULL, forward_tenor := NULL, termination_tenor := NULL)` | GS Quant midcurve volatility compatibility. | Last-value local vol alias. |
| `fin_non_usd_ois` | `fin_non_usd_ois(rate, tenor := NULL)` | GS Quant non-USD OIS compatibility. | Last-value local rate alias. |
| `fin_ois_xccy` | `fin_ois_xccy(rate, tenor := NULL)` | GS Quant OIS xccy compatibility. | Last-value local rate alias. |
| `fin_ois_xccy_ex_spike` | `fin_ois_xccy_ex_spike(rate, tenor := NULL)` | GS Quant OIS xccy ex-spike compatibility. | Last-value local rate alias. |
| `fin_policy_rate_expectation` | `fin_policy_rate_expectation(rate, event_type := NULL, rate_type := NULL, meeting_date := NULL)` | GS Quant policy rate expectation compatibility. | Last-value local rate alias. |
| `fin_policy_rate_term_structure` | `fin_policy_rate_term_structure(rate, event_type := NULL, rate_type := NULL, valuation_date := NULL)` | GS Quant policy rate term-structure compatibility. | Last-value local rate alias. |
| `fin_swap_annuity` | `fin_swap_annuity(annuity, swap_tenor := NULL, benchmark_type := NULL, floating_rate_tenor := NULL)` | GS Quant swap annuity compatibility. | Last-value local annuity alias. |
| `fin_swap_rate_calc` | `fin_swap_rate_calc(rate, swap_tenor := NULL, benchmark_type := NULL, floating_rate_tenor := NULL)` | GS Quant swap rate calc compatibility. | Last-value local rate alias. |
| `fin_swap_term_structure` | `fin_swap_term_structure(rate, benchmark_type := NULL, floating_rate_tenor := NULL, tenor_type := NULL)` | GS Quant swap term-structure compatibility. | Last-value local rate alias. |
| `fin_swaption_annuity` | `fin_swaption_annuity(annuity, expiration_tenor := NULL, termination_tenor := NULL, relative_strike := 0.0)` | GS Quant swaption annuity compatibility. | Last-value local annuity alias. |
| `fin_swaption_atm_fwd_rate` | `fin_swaption_atm_fwd_rate(rate, expiration_tenor := NULL, termination_tenor := NULL, benchmark_type := NULL)` | GS Quant swaption ATM forward rate compatibility. | Last-value local rate alias. |
| `fin_swaption_premium` | `fin_swaption_premium(premium, expiration_tenor := NULL, termination_tenor := NULL, relative_strike := 0.0)` | GS Quant swaption premium compatibility. | Last-value local premium alias. |
| `fin_swaption_vol` | `fin_swaption_vol(vol, expiration_tenor := NULL, termination_tenor := NULL, relative_strike := 0.0)` | GS Quant swaption volatility compatibility. | Last-value local vol alias. |
| `fin_swaption_vol_smile` | `fin_swaption_vol_smile(vol, expiration_tenor := NULL, termination_tenor := NULL, pricing_date := NULL)` | GS Quant swaption vol-smile compatibility. | Last-value local vol alias. |
| `fin_swaption_vol_term` | `fin_swaption_vol_term(vol, tenor_type := NULL, tenor := NULL, relative_strike := 0.0, pricing_date := NULL)` | GS Quant swaption vol-term compatibility. | Last-value local vol alias. |
| `fin_usd_ois` | `fin_usd_ois(rate, tenor := NULL)` | GS Quant USD OIS compatibility. | Last-value local rate alias. |

### GS Quant Data Vendor And Risk Model Compatibility

These names mirror decorated GS Quant functions for cognitive credit,
countries, FactSet/GIR, and risk-model datasets. The SQL forms operate on local
series supplied by the caller.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_cognitive_credit_fundamentals` | `fin_cognitive_credit_fundamentals(value, kpi := NULL, report_type := NULL)` | GS Quant cognitive credit fundamentals compatibility. | Last-value local metric alias. |
| `fin_factor_correlation` | `fin_factor_correlation(x, y := NULL, risk_model_id := NULL, factor_name_1 := NULL, factor_name_2 := NULL)` | GS Quant risk-model factor correlation compatibility. | Correlation over local series; returns 1 for a single supplied series. |
| `fin_factor_covariance` | `fin_factor_covariance(x, y := NULL, risk_model_id := NULL, factor_name_1 := NULL, factor_name_2 := NULL)` | GS Quant risk-model factor covariance compatibility. | Covariance over local series, or variance when one series is supplied. |
| `fin_factor_performance` | `fin_factor_performance(r, risk_model_id := NULL, factor_name := NULL)` | GS Quant risk-model factor performance compatibility. | Aggregate total-return alias. |
| `fin_factor_returns_intraday` | `fin_factor_returns_intraday(r, risk_model_id := NULL, factor_name := NULL, data_source := NULL)` | GS Quant intraday factor returns compatibility. | Last-value local return alias. |
| `fin_factor_returns_percentile` | `fin_factor_returns_percentile(r, risk_model_id := NULL, factor_name := NULL, lookback_days := NULL, n_percentile := 0.5)` | GS Quant factor returns percentile compatibility. | Aggregate quantile alias. |
| `fin_factor_volatility` | `fin_factor_volatility(value, risk_model_id := NULL, factor_name := NULL)` | GS Quant risk-model factor volatility compatibility. | Aggregate standard-deviation alias. |
| `fin_factor_zscore` | `fin_factor_zscore(value, risk_model_id := NULL, factor_name := NULL)` | GS Quant risk-model factor z-score compatibility. | Last-value z-score alias. |
| `fin_factset_enterprise_value` | `fin_factset_enterprise_value(value, metric := NULL)` | GS Quant FactSet enterprise-value compatibility. | Last-value local metric alias. |
| `fin_factset_estimates` | `fin_factset_estimates(value, metric := NULL, statistic := NULL, report_basis := NULL, period := NULL)` | GS Quant FactSet estimates compatibility. | Last-value local metric alias. |
| `fin_factset_fundamentals` | `fin_factset_fundamentals(value, metric := NULL, report_basis := NULL, report_format := NULL)` | GS Quant FactSet fundamentals compatibility. | Last-value local metric alias. |
| `fin_factset_ratings` | `fin_factset_ratings(value, rating_type := NULL)` | GS Quant FactSet ratings compatibility. | Last-value local metric alias. |
| `fin_fci` | `fin_fci(value, measure := NULL)` | GS Quant country FCI compatibility. | Last-value local measure alias. |
| `fin_gir_estimates` | `fin_gir_estimates(value, metric := NULL, report_basis := NULL, period := NULL)` | GS Quant GIR estimates compatibility. | Last-value local metric alias. |
| `fin_risk_model_measure` | `fin_risk_model_measure(value, risk_model_id := NULL, risk_model_measure_selected := NULL)` | GS Quant generic risk-model measure compatibility. | Last-value local metric alias. |

### GS Quant General Measure Compatibility

These names mirror the remaining decorated functions in
`gs_quant.timeseries.measures`. They are local-data equivalents for GS Quant
market, fundamentals, ESG, thematic, forecast, and commodity dataset wrappers.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_skew` | `fin_skew(value)` | GS Quant `measures.skew` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_cds_implied_volatility` | `fin_cds_implied_volatility(value)` | GS Quant `measures.cds_implied_volatility` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_option_premium_credit` | `fin_option_premium_credit(value)` | GS Quant `measures.option_premium_credit` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_absolute_strike_credit` | `fin_absolute_strike_credit(value)` | GS Quant `measures.absolute_strike_credit` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_implied_volatility_credit` | `fin_implied_volatility_credit(value)` | GS Quant `measures.implied_volatility_credit` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_cds_spread` | `fin_cds_spread(value)` | GS Quant `measures.cds_spread` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_implied_volatility_ng` | `fin_implied_volatility_ng(value)` | GS Quant `measures.implied_volatility_ng` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_implied_correlation` | `fin_implied_correlation(x, y := NULL)` | GS Quant `measures.implied_correlation` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_implied_correlation_with_basket` | `fin_implied_correlation_with_basket(x, y := NULL)` | GS Quant `measures.implied_correlation_with_basket` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_realized_correlation_with_basket` | `fin_realized_correlation_with_basket(x, y := NULL)` | GS Quant `measures.realized_correlation_with_basket` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_average_implied_volatility` | `fin_average_implied_volatility(value)` | GS Quant `measures.average_implied_volatility` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_average_implied_variance` | `fin_average_implied_variance(value)` | GS Quant `measures.average_implied_variance` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_average_realized_volatility` | `fin_average_realized_volatility(value)` | GS Quant `measures.average_realized_volatility` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_cap_floor_vol` | `fin_cap_floor_vol(value)` | GS Quant `measures.cap_floor_vol` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_cap_floor_atm_fwd_rate` | `fin_cap_floor_atm_fwd_rate(value)` | GS Quant `measures.cap_floor_atm_fwd_rate` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_spread_option_vol` | `fin_spread_option_vol(value)` | GS Quant `measures.spread_option_vol` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_spread_option_atm_fwd_rate` | `fin_spread_option_atm_fwd_rate(value)` | GS Quant `measures.spread_option_atm_fwd_rate` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_zc_inflation_swap_rate` | `fin_zc_inflation_swap_rate(value)` | GS Quant `measures.zc_inflation_swap_rate` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_basis` | `fin_basis(value)` | GS Quant `measures.basis` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fx_forecast` | `fin_fx_forecast(value)` | GS Quant `measures.fx_forecast` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fx_forecast_time_series` | `fin_fx_forecast_time_series(value)` | GS Quant `measures.fx_forecast_time_series` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_forward_vol` | `fin_forward_vol(value)` | GS Quant `measures.forward_vol` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_forward_vol_term` | `fin_forward_vol_term(value)` | GS Quant `measures.forward_vol_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_skew_term` | `fin_skew_term(value)` | GS Quant `measures.skew_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_vol_term` | `fin_vol_term(value)` | GS Quant `measures.vol_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_vol_smile` | `fin_vol_smile(value)` | GS Quant `measures.vol_smile` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fwd_term` | `fin_fwd_term(value)` | GS Quant `measures.fwd_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fx_fwd_term` | `fin_fx_fwd_term(value)` | GS Quant `measures.fx_fwd_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_carry_term` | `fin_carry_term(value)` | GS Quant `measures.carry_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_forward_var_term` | `fin_forward_var_term(value)` | GS Quant `measures.forward_var_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_var_term` | `fin_var_term(value)` | GS Quant `measures.var_term` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_var_swap` | `fin_var_swap(value)` | GS Quant `measures.var_swap` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fair_price` | `fin_fair_price(value)` | GS Quant `measures.fair_price` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_implied_volatility_elec` | `fin_implied_volatility_elec(value)` | GS Quant `measures.implied_volatility_elec` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_forward_price_ng` | `fin_forward_price_ng(value)` | GS Quant `measures.forward_price_ng` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_bucketize_price` | `fin_bucketize_price(value)` | GS Quant `measures.bucketize_price` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_dividend_yield` | `fin_dividend_yield(value)` | GS Quant `measures.dividend_yield` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_earnings_per_share` | `fin_earnings_per_share(value)` | GS Quant `measures.earnings_per_share` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_earnings_per_share_positive` | `fin_earnings_per_share_positive(value)` | GS Quant `measures.earnings_per_share_positive` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_net_debt_to_ebitda` | `fin_net_debt_to_ebitda(value)` | GS Quant `measures.net_debt_to_ebitda` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_price_to_book` | `fin_price_to_book(value)` | GS Quant `measures.price_to_book` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_price_to_cash` | `fin_price_to_cash(value)` | GS Quant `measures.price_to_cash` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_price_to_earnings` | `fin_price_to_earnings(value)` | GS Quant `measures.price_to_earnings` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_price_to_earnings_positive` | `fin_price_to_earnings_positive(value)` | GS Quant `measures.price_to_earnings_positive` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_price_to_earnings_positive_exclusive` | `fin_price_to_earnings_positive_exclusive(value)` | GS Quant `measures.price_to_earnings_positive_exclusive` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_price_to_sales` | `fin_price_to_sales(value)` | GS Quant `measures.price_to_sales` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_return_on_equity` | `fin_return_on_equity(value)` | GS Quant `measures.return_on_equity` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_sales_per_share` | `fin_sales_per_share(value)` | GS Quant `measures.sales_per_share` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_dividend_yield` | `fin_current_constituents_dividend_yield(value)` | GS Quant `measures.current_constituents_dividend_yield` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_earnings_per_share` | `fin_current_constituents_earnings_per_share(value)` | GS Quant `measures.current_constituents_earnings_per_share` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_earnings_per_share_positive` | `fin_current_constituents_earnings_per_share_positive(value)` | GS Quant `measures.current_constituents_earnings_per_share_positive` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_net_debt_to_ebitda` | `fin_current_constituents_net_debt_to_ebitda(value)` | GS Quant `measures.current_constituents_net_debt_to_ebitda` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_price_to_book` | `fin_current_constituents_price_to_book(value)` | GS Quant `measures.current_constituents_price_to_book` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_price_to_cash` | `fin_current_constituents_price_to_cash(value)` | GS Quant `measures.current_constituents_price_to_cash` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_price_to_earnings` | `fin_current_constituents_price_to_earnings(value)` | GS Quant `measures.current_constituents_price_to_earnings` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_price_to_earnings_positive` | `fin_current_constituents_price_to_earnings_positive(value)` | GS Quant `measures.current_constituents_price_to_earnings_positive` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_price_to_sales` | `fin_current_constituents_price_to_sales(value)` | GS Quant `measures.current_constituents_price_to_sales` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_return_on_equity` | `fin_current_constituents_return_on_equity(value)` | GS Quant `measures.current_constituents_return_on_equity` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_current_constituents_sales_per_share` | `fin_current_constituents_sales_per_share(value)` | GS Quant `measures.current_constituents_sales_per_share` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_realized_correlation` | `fin_realized_correlation(x, y := NULL)` | GS Quant `measures.realized_correlation` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_realized_volatility` | `fin_realized_volatility(r)` | GS Quant `measures.realized_volatility` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_esg_headline_metric` | `fin_esg_headline_metric(value)` | GS Quant `measures.esg_headline_metric` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_rating` | `fin_rating(value)` | GS Quant `measures.rating` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fair_value` | `fin_fair_value(value)` | GS Quant `measures.fair_value` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_factor_profile` | `fin_factor_profile(value)` | GS Quant `measures.factor_profile` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_commodity_forecast` | `fin_commodity_forecast(value)` | GS Quant `measures.commodity_forecast` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_commodity_forecast_time_series` | `fin_commodity_forecast_time_series(value)` | GS Quant `measures.commodity_forecast_time_series` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_forward_curve` | `fin_forward_curve(value)` | GS Quant `measures.forward_curve` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_forward_curve_ng` | `fin_forward_curve_ng(value)` | GS Quant `measures.forward_curve_ng` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_fx_implied_correlation` | `fin_fx_implied_correlation(x, y := NULL)` | GS Quant `measures.fx_implied_correlation` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_settlement_price` | `fin_settlement_price(value)` | GS Quant `measures.settlement_price` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_hloc_prices` | `fin_hloc_prices(price_value)` | GS Quant `measures.hloc_prices` compatibility. | STRUCT with high, low, open, and close. |
| `fin_thematic_model_exposure` | `fin_thematic_model_exposure(value)` | GS Quant `measures.thematic_model_exposure` compatibility. | Average exposure scaled by notional. |
| `fin_thematic_model_beta` | `fin_thematic_model_beta(x, y := NULL)` | GS Quant `measures.thematic_model_beta` compatibility. | Local beta-style aggregate alias. |
| `fin_retail_interest_agg` | `fin_retail_interest_agg(value)` | GS Quant `measures.retail_interest_agg` compatibility. | Local SQL measure alias over caller-supplied series. |
| `fin_s3_long_short_concentration` | `fin_s3_long_short_concentration(value)` | GS Quant `measures.s3_long_short_concentration` compatibility. | Local SQL measure alias over caller-supplied series. |

## Function Index

### Numerical And Money Helpers

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_bps` | `fin_bps(0.0123)` | Compute bps for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_cents_to_money` | `fin_cents_to_money(cents, scale := 2)` | Compute cents to money for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_chi2_cdf` | `fin_chi2_cdf(0.0, 3.0)` | Evaluate the chi-square CDF. | DOUBLE unless noted by DuckDB overloads. |
| `fin_chi2_inv` | `fin_chi2_inv(0.5, 2.0)` | Invert the chi-square CDF. | DOUBLE unless noted by DuckDB overloads. |
| `fin_clip` | `fin_clip(12.0, 0.0, 10.0)` | Compute clip for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_from_bps` | `fin_from_bps(125.0)` | Compute from bps for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_money_round` | `fin_money_round(amount, scale := 2, mode := 'nearest')` | Compute money round for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_money_sum` | `fin_money_sum(x)` | Compute money sum for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_money_to_cents` | `fin_money_to_cents(amount, rounding := 'nearest')` | Compute money to cents for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_money_weighted_sum` | `fin_money_weighted_sum(amount, weight)` | Compute money weighted sum for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_norm_cdf` | `fin_norm_cdf(0.0)` | Evaluate the standard normal cumulative distribution function. | DOUBLE unless noted by DuckDB overloads. |
| `fin_norm_inv` | `fin_norm_inv(0.5)` | Invert the standard normal CDF. | DOUBLE unless noted by DuckDB overloads. |
| `fin_norm_pdf` | `fin_norm_pdf(0.0)` | Evaluate the standard normal probability density function. | DOUBLE unless noted by DuckDB overloads. |
| `fin_round_to_tick` | `fin_round_to_tick(100.037, 0.05)` | Compute round to tick for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_safe_div` | `fin_safe_div(1.0, 0.0)` | Divide two numbers and return NULL or a fallback when the denominator is zero. | DOUBLE unless noted by DuckDB overloads. |
| `fin_student_t_cdf` | `fin_student_t_cdf(0.0, 10.0)` | Evaluate the Student-t CDF. | DOUBLE unless noted by DuckDB overloads. |
| `fin_student_t_inv` | `fin_student_t_inv(0.5, 10.0)` | Invert the Student-t CDF. | DOUBLE unless noted by DuckDB overloads. |

### Returns, Risk, And Statistics

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_active_return` | `fin_active_return(r, benchmark_r, annualization := 252)` | Compute active return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_aggregate_return` | `fin_aggregate_return(r, period_key, method := 'simple')` | Compute aggregate return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_alpha` | `fin_alpha(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Compute alpha for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_alpha_beta` | `fin_alpha_beta(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Compute alpha beta for SQL finance workflows. | STRUCT. |
| `fin_annual_return` | `fin_annual_return(r, annualization := 252)` | Compute annual return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_anova_oneway` | `fin_anova_oneway(r, asset)` | Compute anova oneway for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_arithmetic_return` | `fin_arithmetic_return(r)` | Compute arithmetic return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_avg_drawdown` | `fin_avg_drawdown(r, initial_nav := 1.0)` | Compute avg drawdown for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_beta` | `fin_beta(r, benchmark_r)` | Compute beta for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_calmar` | `fin_calmar(r, annualization := 252)` | Compute calmar for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_conditional_drawdown_at_risk` | `fin_conditional_drawdown_at_risk(r, confidence := 0.95)` | Compute conditional drawdown at risk for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_cramers_v` | `fin_cramers_v(x, y, bias_corrected := true)` | Compute cramers v for SQL finance workflows. | NULL placeholder. |
| `fin_cum_return` | `fin_cum_return(r, method := 'simple')` | Compute cum return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_cvar` | `fin_cvar(r, confidence := 0.95, method := 'historical', loss_positive := true)` | Compute cvar for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_data_quality_report` | `fin_data_quality_report(x)` | Compute data quality report for SQL finance workflows. | STRUCT. |
| `fin_down_capture` | `fin_down_capture(r, benchmark_r)` | Compute down capture for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_downside_deviation` | `fin_downside_deviation(r, mar := 0.0, annualization := 252)` | Compute downside deviation for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_drawdown` | `fin_drawdown(r, initial_nav := 1.0)` | Compute drawdown for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_drawdown_at_risk` | `fin_drawdown_at_risk(r, confidence := 0.95)` | Compute drawdown at risk for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_drawdown_duration` | `fin_drawdown_duration(r, initial_nav := 1.0)` | Compute drawdown duration for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_entropy` | `fin_entropy(x)` | Compute entropy for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ewma_variance` | `fin_ewma_variance(r, lambda := 0.94, annualization := 252)` | Compute ewma variance for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_excess_return` | `fin_excess_return(r, rf, annualization := 252, rf_convention := 'annual')` | Compute excess return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_expectancy` | `fin_expectancy(r)` | Compute expectancy for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_from_log_return` | `fin_from_log_return(lr)` | Compute from log return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_gain_to_pain` | `fin_gain_to_pain(r)` | Compute gain to pain for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_garch11_forecast` | `fin_garch11_forecast(r, omega, alpha, beta, initial_var := NULL, annualization := 252)` | Compute garch11 forecast for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_geometric_return` | `fin_geometric_return(r)` | Compute geometric return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_gross_return` | `fin_gross_return(r)` | Compute gross return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_hit_ratio` | `fin_hit_ratio(r, threshold := 0.0)` | Compute hit ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_information_ratio` | `fin_information_ratio(r, benchmark_r, annualization := 252)` | Compute information ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_is_decimal_return` | `fin_is_decimal_return(x)` | Predicate helper for finance input validation. | Aggregate or scalar SQL macro result. |
| `fin_is_outlier_zscore` | `fin_is_outlier_zscore(3.1, 0.0, 1.0, 3.0)` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_iv_percentile` | `fin_iv_percentile(factor)` | Compute iv percentile for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_iv_rank` | `fin_iv_rank(factor)` | Compute iv rank for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_jensen_alpha` | `fin_jensen_alpha(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Compute jensen alpha for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_kahan_sum` | `fin_kahan_sum(x)` | Compute kahan sum for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ks_test` | `fin_ks_test(x, y)` | Compute ks test for SQL finance workflows. | NULL placeholder. |
| `fin_log_return` | `fin_log_return(price, prev_price)` | Compute log return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_loss_rate` | `fin_loss_rate(r)` | Compute loss rate for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_mad` | `fin_mad(x)` | Compute mad for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_mann_whitney_u` | `fin_mann_whitney_u(x, y)` | Compute mann whitney u for SQL finance workflows. | NULL placeholder. |
| `fin_max_drawdown` | `fin_max_drawdown(r, initial_nav := 1.0)` | Compute max drawdown for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_missing_count` | `fin_missing_count(x)` | Compute missing count for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_mutual_information` | `fin_mutual_information(x, y, bins := 10)` | Compute mutual information for SQL finance workflows. | NULL placeholder. |
| `fin_omega_ratio` | `fin_omega_ratio(r, required_return := 0.0, annualization := 252)` | Compute omega ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_outlier_count` | `fin_outlier_count(x, method := 'zscore', threshold := 3.0)` | Compute outlier count for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_parametric_cvar` | `fin_parametric_cvar(mean, vol, confidence := 0.95, horizon := 1.0, distribution := 'normal')` | Compute parametric cvar for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_parse_return_method` | `fin_parse_return_method('log')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_payoff_ratio` | `fin_payoff_ratio(r)` | Compute payoff ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_price_from_return` | `fin_price_from_return(prev_price, r, method := 'simple')` | Compute price from return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rank_corr` | `fin_rank_corr(x, y, method := 'spearman')` | Compute rank corr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_realized_beta` | `fin_realized_beta(r, benchmark_r)` | Compute realized beta for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_realized_corr` | `fin_realized_corr(r1, r2)` | Compute realized corr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_realized_cov` | `fin_realized_cov(r1, r2)` | Compute realized cov for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_realized_quarticity` | `fin_realized_quarticity(log_r, annualization := 252)` | Compute realized quarticity for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_realized_variance` | `fin_realized_variance(log_r, annualization := 252)` | Compute realized variance for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_realized_vol` | `fin_realized_vol(log_r, annualization := 252)` | Compute realized vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_return` | `fin_return(price, prev_price, method := 'simple')` | Compute return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rolling_beta` | `fin_rolling_beta(r, factor_r)` | Compute rolling beta for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rolling_zscore` | `fin_rolling_zscore(x)` | Compute rolling zscore for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_semivariance` | `fin_semivariance(r, threshold := 0.0)` | Compute semivariance for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sharpe` | `fin_sharpe(r, risk_free := 0.0, annualization := 252)` | Compute sharpe for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_simple_return` | `fin_simple_return(price, prev_price)` | Compute simple return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sortino` | `fin_sortino(r, mar := 0.0, annualization := 252)` | Compute sortino for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stability` | `fin_stability(r)` | Compute stability for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_corr` | `fin_stable_corr(y, x)` | Compute stable corr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_cov` | `fin_stable_cov(y, x)` | Compute stable cov for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_mean` | `fin_stable_mean(x)` | Compute stable mean for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_stddev` | `fin_stable_stddev(x, ddof := 1)` | Compute stable stddev for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_var` | `fin_stable_var(x, ddof := 1)` | Compute stable var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_tail_ratio` | `fin_tail_ratio(r, upper_q := 0.95, lower_q := 0.05)` | Compute tail ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_theils_u` | `fin_theils_u(x, y)` | Compute theils u for SQL finance workflows. | NULL placeholder. |
| `fin_to_log_return` | `fin_to_log_return(r)` | Compute to log return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_total_return` | `fin_total_return(r, method := 'simple')` | Compute total return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_tracking_error` | `fin_tracking_error(r, benchmark_r, annualization := 252)` | Compute tracking error for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_treynor_ratio` | `fin_treynor_ratio(r, benchmark_r, risk_free := 0.0, annualization := 252)` | Compute treynor ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_trimmed_mean` | `fin_trimmed_mean(x, lower_q := 0.05, upper_q := 0.95)` | Compute trimmed mean for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ttest_1samp` | `fin_ttest_1samp(x, mu)` | Compute ttest 1samp for SQL finance workflows. | STRUCT. |
| `fin_ttest_2samp` | `fin_ttest_2samp(x, y, equal_var := true)` | Compute ttest 2samp for SQL finance workflows. | STRUCT. |
| `fin_ulcer_index` | `fin_ulcer_index(r)` | Compute ulcer index for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_up_capture` | `fin_up_capture(r, benchmark_r)` | Compute up capture for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_upside_deviation` | `fin_upside_deviation(r, threshold := 0.0, annualization := 252)` | Compute upside deviation for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_validate_return` | `fin_validate_return(0.05)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | BOOLEAN. |
| `fin_volatility` | `fin_volatility(r, annualization := 252, ddof := 1)` | Compute volatility for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_mean` | `fin_weighted_mean(x, w)` | Compute weighted mean for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_quantile` | `fin_weighted_quantile(x, w, q, method := 'linear')` | Compute weighted quantile for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_stddev` | `fin_weighted_stddev(x, w, ddof := 0)` | Compute weighted stddev for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_var` | `fin_weighted_var(x, w, ddof := 0)` | Compute weighted var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_welch_ttest` | `fin_welch_ttest(x, y)` | Compute welch ttest for SQL finance workflows. | STRUCT. |
| `fin_win_rate` | `fin_win_rate(r)` | Compute win rate for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_winsorized_mean` | `fin_winsorized_mean(x, lower_q := 0.05, upper_q := 0.95)` | Compute winsorized mean for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_zscore_last` | `fin_zscore_last(x)` | Compute zscore last for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ztest_mean` | `fin_ztest_mean(x, mu, sigma := NULL)` | Compute ztest mean for SQL finance workflows. | Aggregate or scalar SQL macro result. |

### Fixed Income, Rates, And Cash Flows

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_accrued_interest` | `fin_accrued_interest(DATE '2026-04-01', DATE '2026-01-01', DATE '2026-07-01', 0.04, 100.0, 'ACT/365F')` | Compute accrued interest for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_annuity_payment` | `fin_annuity_payment(0.0, 10.0, 100.0)` | Compute annuity payment for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bond_convexity` | `fin_bond_convexity(0.05, 0.04, 5.0, 2, 100.0)` | Compute bond convexity for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bond_duration` | `fin_bond_duration(0.05, 0.04, 5.0, 2, 100.0, 'modified')` | Compute bond duration for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bond_price` | `fin_bond_price(0.05, 0.04, 5.0, 2, 100.0)` | Compute bond price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bond_ytm` | `fin_bond_ytm(fin_bond_price(0.05, 0.04, 5.0, 2, 100.0), 0.05, 5.0, 2, 100.0)` | Compute bond ytm for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_cashflow_spec` | `fin_cashflow_spec(amount, date, currency := NULL)` | Compute cashflow spec for SQL finance workflows. | STRUCT. |
| `fin_curve_spec` | `fin_curve_spec(maturities, values, value_type := 'zero_rate', interpolation := 'linear', compounding := 'continuous', day_count := 'ACT/365F')` | Compute curve spec for SQL finance workflows. | STRUCT. |
| `fin_curve_zero_rate` | `fin_curve_zero_rate([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5)` | Compute curve zero rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_forward_rate` | `fin_forward_rate(0.9607894391523232, 0.8869204367171575, 1.0, 2.0, 'continuous')` | Compute forward rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_fra_rate` | `fin_fra_rate(0.04, 0.05, 1.0, 2.0)` | Compute fra rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_future_value` | `fin_future_value(100.0, 0.05, 1.0, 'continuous')` | Compute future value for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_interpolate_curve` | `fin_interpolate_curve([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5)` | Compute interpolate curve for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_irr` | `fin_irr([-100.0, 60.0, 60.0])` | Compute irr for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_mirr` | `fin_mirr([-100.0, 60.0, 60.0], 0.1, 0.05)` | Compute mirr for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_npv` | `fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic')` | Compute npv for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_present_value` | `fin_present_value(105.12710963760242, 0.05, 1.0, 'continuous')` | Compute present value for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_rate_from_discount` | `fin_rate_from_discount(0.951229424500714, 1.0, 'continuous')` | Compute rate from discount for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_swap_rate` | `fin_swap_rate([1.0, 2.0], [0.95, 0.90])` | Compute swap rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_validate_curve_spec` | `fin_validate_curve_spec(spec)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | STRUCT. |
| `fin_xirr` | `fin_xirr([-100.0, 110.0], [DATE '2026-01-01', DATE '2027-01-01'])` | Compute xirr for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_yearfrac` | `fin_yearfrac(DATE '2026-01-01', DATE '2027-01-01', 'ACT/365F')` | Compute yearfrac for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |

### Options And Volatility Models

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_asian_geometric_price` | `fin_asian_geometric_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute asian geometric price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_asset_or_nothing_price` | `fin_asset_or_nothing_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute asset or nothing price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bachelier_greeks` | `fin_bachelier_greeks('call', 100.0, 100.0, 1.0, 0.05, 5.0)` | Compute bachelier greeks for SQL finance workflows. | STRUCT. |
| `fin_bachelier_implied_vol` | `fin_bachelier_implied_vol('call', fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0), 100.0, 100.0, 1.0, 0.05, 4.0, 1e-8)` | Compute bachelier implied vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bachelier_price` | `fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0)` | Compute bachelier price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_barrier_price` | `fin_barrier_price('call', 'up-out', 100.0, 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute barrier price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_binomial_price` | `fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'european', 'crr')` | Compute binomial price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_black76_greeks` | `fin_black76_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute black76 greeks for SQL finance workflows. | STRUCT. |
| `fin_black76_implied_vol` | `fin_black76_implied_vol('call', fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05, 0.3, 1e-8)` | Compute black76 implied vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_black76_price` | `fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute black76 price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_all` | `fin_bsm_all('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm all for SQL finance workflows. | STRUCT. |
| `fin_bsm_charm` | `fin_bsm_charm('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm charm for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_color` | `fin_bsm_color('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm color for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_d1` | `fin_bsm_d1(100.0, 100.0, 1.0, 0.05, 0.2, 0.0)` | Compute bsm d1 for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_d2` | `fin_bsm_d2(100.0, 100.0, 1.0, 0.05, 0.2, 0.0)` | Compute bsm d2 for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_delta` | `fin_bsm_delta('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm delta for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_elasticity` | `fin_bsm_elasticity('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm elasticity for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_gamma` | `fin_bsm_gamma(100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm gamma for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_greeks` | `fin_bsm_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm greeks for SQL finance workflows. | STRUCT. |
| `fin_bsm_implied_vol` | `fin_bsm_implied_vol('call', fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05)` | Compute bsm implied vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_price` | `fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_price_dates` | `fin_bsm_price_dates('call', 100.0, 100.0, DATE '2026-01-01', DATE '2027-01-01', 0.05, 0.2)` | Compute bsm price dates for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_prob_itm` | `fin_bsm_prob_itm('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm prob itm for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_prob_touch` | `fin_bsm_prob_touch('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm prob touch for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_rho` | `fin_bsm_rho('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm rho for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_speed` | `fin_bsm_speed('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm speed for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_theta` | `fin_bsm_theta('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm theta for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_ultima` | `fin_bsm_ultima('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm ultima for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_vanna` | `fin_bsm_vanna('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm vanna for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_vega` | `fin_bsm_vega('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm vega for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_vomma` | `fin_bsm_vomma('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm vomma for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_zomma` | `fin_bsm_zomma('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm zomma for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_digital_price` | `fin_digital_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute digital price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_forward_price` | `fin_forward_price(100.0, 1.0, 0.05, 0.0)` | Compute forward price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_option_market_spec` | `fin_option_market_spec(kind, spot, strike, expiry, valuation_date, rate, vol, dividend_yield := 0.0, calendar := 'weekday', day_count := 'ACT/365F')` | Compute option market spec for SQL finance workflows. | STRUCT. |
| `fin_option_payoff` | `fin_option_payoff('call', 105.0, 100.0)` | Compute option payoff for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_option_spec` | `fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield := 0.0, exercise := 'european', model := 'bsm')` | Compute option spec for SQL finance workflows. | STRUCT. |
| `fin_option_spec_dates` | `fin_option_spec_dates(kind, spot, strike, valuation_date, expiry_date, rate, vol, dividend_yield := 0.0, day_count := 'ACT/365F', exercise := 'european', model := 'bsm')` | Compute option spec dates for SQL finance workflows. | STRUCT. |
| `fin_parse_option_kind` | `fin_parse_option_kind('CALL')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_put_call_parity` | `fin_put_call_parity(10.450583572185565, 5.573526022256971, 100.0, 100.0, 1.0, 0.05, 0.0)` | Compute put call parity for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_sabr_vol` | `fin_sabr_vol(100.0, 100.0, 1.0, 0.2, 0.5, -0.2, 0.4)` | Compute sabr vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_svi_total_variance` | `fin_svi_total_variance(0.0, 0.02, 0.1, -0.3, 0.0, 0.2)` | Compute svi total variance for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_svi_vol` | `fin_svi_vol(0.0, 1.0, 0.02, 0.1, -0.3, 0.0, 0.2)` | Compute svi vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_validate_option_spec` | `fin_validate_option_spec(spec)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | STRUCT. |

### Technical Indicators And Microstructure

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_ad_line` | `fin_ad_line(high, low, close, volume)` | Compute ad line for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_adosc` | `fin_adosc(high, low, close, volume, fast := 3, slow := 10)` | Compute adosc for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_adx` | `fin_adx(high, low, close, period := 14)` | Compute adx for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_adxr` | `fin_adxr(high, low, close, period := 14)` | Compute adxr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_amihud_illiquidity` | `fin_amihud_illiquidity(abs_return, dollar_volume)` | Compute amihud illiquidity for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_apo` | `fin_apo(close, fast := 12, slow := 26)` | Compute apo for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_aroon` | `fin_aroon(high, low, period := 14)` | Compute aroon for SQL finance workflows. | STRUCT. |
| `fin_aroonosc` | `fin_aroonosc(high, low, period := 14)` | Compute aroonosc for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_atr` | `fin_atr(high, low, close, period := 14)` | Compute atr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_avg_price` | `fin_avg_price(open, high, low, close)` | Compute avg price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bbands` | `fin_bbands(close, period := 20, k := 2.0)` | Compute bbands for SQL finance workflows. | STRUCT. |
| `fin_bop` | `fin_bop(open, high, low, close)` | Compute bop for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_cci` | `fin_cci(high, low, close, period := 20, constant := 0.015)` | Compute cci for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_cdl_2crows` | `fin_cdl_2crows(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_3blackcrows` | `fin_cdl_3blackcrows(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_3inside` | `fin_cdl_3inside(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_3linestrike` | `fin_cdl_3linestrike(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_3starsinsouth` | `fin_cdl_3starsinsouth(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_3whitesoldiers` | `fin_cdl_3whitesoldiers(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_abandonedbaby` | `fin_cdl_abandonedbaby(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_advanceblock` | `fin_cdl_advanceblock(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_belthold` | `fin_cdl_belthold(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_breakaway` | `fin_cdl_breakaway(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_closingmarubozu` | `fin_cdl_closingmarubozu(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_concealbabyswall` | `fin_cdl_concealbabyswall(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_counterattack` | `fin_cdl_counterattack(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_darkcloudcover` | `fin_cdl_darkcloudcover(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_doji` | `fin_cdl_doji(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_dojistar` | `fin_cdl_dojistar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_dragonflydoji` | `fin_cdl_dragonflydoji(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_engulfing` | `fin_cdl_engulfing(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_eveningdojistar` | `fin_cdl_eveningdojistar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_eveningstar` | `fin_cdl_eveningstar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_gapsidesidewhite` | `fin_cdl_gapsidesidewhite(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_gravestonedoji` | `fin_cdl_gravestonedoji(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_hammer` | `fin_cdl_hammer(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_hangingman` | `fin_cdl_hangingman(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_harami` | `fin_cdl_harami(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_haramicross` | `fin_cdl_haramicross(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_highwave` | `fin_cdl_highwave(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_hikkake` | `fin_cdl_hikkake(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_hikkakemod` | `fin_cdl_hikkakemod(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_homingpigeon` | `fin_cdl_homingpigeon(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_identical3crows` | `fin_cdl_identical3crows(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_inneck` | `fin_cdl_inneck(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_invertedhammer` | `fin_cdl_invertedhammer(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_kicking` | `fin_cdl_kicking(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_kickingbylength` | `fin_cdl_kickingbylength(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_ladderbottom` | `fin_cdl_ladderbottom(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_longleggeddoji` | `fin_cdl_longleggeddoji(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_longline` | `fin_cdl_longline(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_marubozu` | `fin_cdl_marubozu(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_matchinglow` | `fin_cdl_matchinglow(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_mathold` | `fin_cdl_mathold(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_morningdojistar` | `fin_cdl_morningdojistar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_morningstar` | `fin_cdl_morningstar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_onneck` | `fin_cdl_onneck(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_pattern` | `fin_cdl_pattern(open, high, low, close, pattern)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_piercing` | `fin_cdl_piercing(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_rickshawman` | `fin_cdl_rickshawman(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_risefall3methods` | `fin_cdl_risefall3methods(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_separatinglines` | `fin_cdl_separatinglines(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_shootingstar` | `fin_cdl_shootingstar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_shortline` | `fin_cdl_shortline(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_spinningtop` | `fin_cdl_spinningtop(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_stalledpattern` | `fin_cdl_stalledpattern(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_sticksandwich` | `fin_cdl_sticksandwich(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_takuri` | `fin_cdl_takuri(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_tasukigap` | `fin_cdl_tasukigap(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_thrusting` | `fin_cdl_thrusting(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_tristar` | `fin_cdl_tristar(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_unique3river` | `fin_cdl_unique3river(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_upsidegap2crows` | `fin_cdl_upsidegap2crows(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cdl_xsidegap3methods` | `fin_cdl_xsidegap3methods(open, high, low, close)` | Candlestick pattern compatibility macro. Current v1 returns a placeholder integer signal. | INTEGER signal; v1 placeholder returns 0. |
| `fin_cmo` | `fin_cmo(close, period := 14)` | Compute cmo for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_dema` | `fin_dema(x, period := 20)` | Compute dema for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_donchian` | `fin_donchian(high, low, period := 20)` | Compute donchian for SQL finance workflows. | STRUCT. |
| `fin_dx` | `fin_dx(high, low, close, period := 14)` | Compute dx for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_hma` | `fin_hma(x, period := 20)` | Compute hma for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_kama` | `fin_kama(x, period := 10, fast := 2, slow := 30)` | Compute kama for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_keltner` | `fin_keltner(high, low, close, period := 20, atr_period := 10, multiplier := 2.0)` | Compute keltner for SQL finance workflows. | STRUCT. |
| `fin_kyle_lambda` | `fin_kyle_lambda(signed_volume, price_change)` | Compute kyle lambda for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_linearreg` | `fin_linearreg(x, period := 14)` | Compute linearreg for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_linearreg_intercept` | `fin_linearreg_intercept(x, period := 14)` | Compute linearreg intercept for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_linearreg_slope` | `fin_linearreg_slope(x, period := 14)` | Compute linearreg slope for SQL finance workflows. | NULL placeholder. |
| `fin_macd` | `fin_macd(close, fast := 12, slow := 26, signal := 9)` | Compute macd for SQL finance workflows. | STRUCT. |
| `fin_median_price` | `fin_median_price(high, low)` | Compute median price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_mfi` | `fin_mfi(high, low, close, volume, period := 14)` | Compute mfi for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_microprice` | `fin_microprice(bid, bid_size, ask, ask_size)` | Compute microprice for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_mid` | `fin_mid(bid, ask)` | Compute mid for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_minus_di` | `fin_minus_di(high, low, close, period := 14)` | Compute minus di for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_minus_dm` | `fin_minus_dm(high, low, period := 14)` | Compute minus dm for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_mom` | `fin_mom(close, period := 10)` | Compute mom for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_natr` | `fin_natr(high, low, close, period := 14)` | Compute natr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_obv` | `fin_obv(close, volume)` | Compute obv for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ohlc` | `fin_ohlc(price)` | Compute ohlc for SQL finance workflows. | STRUCT. |
| `fin_ohlcv` | `fin_ohlcv(price, volume)` | Compute ohlcv for SQL finance workflows. | STRUCT. |
| `fin_order_imbalance` | `fin_order_imbalance(bid_size, ask_size)` | Compute order imbalance for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_plus_di` | `fin_plus_di(high, low, close, period := 14)` | Compute plus di for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_plus_dm` | `fin_plus_dm(high, low, period := 14)` | Compute plus dm for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ppo` | `fin_ppo(close, fast := 12, slow := 26, signal := 9)` | Compute ppo for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_queue_imbalance` | `fin_queue_imbalance(bid_size, ask_size)` | Compute queue imbalance for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_roc` | `fin_roc(close, period := 10)` | Compute roc for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rocp` | `fin_rocp(close, period := 10)` | Compute rocp for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rocr` | `fin_rocr(close, period := 10)` | Compute rocr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rocr100` | `fin_rocr100(close, period := 10)` | Compute rocr100 for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_roll_spread` | `fin_roll_spread(price)` | Compute roll spread for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rsi` | `fin_rsi(close, period := 14)` | Compute rsi for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sar` | `fin_sar(high, low, acceleration := 0.02, maximum := 0.2)` | Compute sar for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sarext` | `fin_sarext(high, low, options)` | Compute sarext for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sma` | `fin_sma(x, period := 20)` | Compute sma for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_spread` | `fin_spread(bid, ask)` | Compute spread for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_spread_bps` | `fin_spread_bps(bid, ask)` | Compute spread bps for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_stddev` | `fin_stddev(close, period := 20, ddof := 1)` | Compute stddev for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stoch` | `fin_stoch(high, low, close, k := 14, d := 3, smooth := 3)` | Compute stoch for SQL finance workflows. | STRUCT. |
| `fin_stochrsi` | `fin_stochrsi(close, period := 14, k := 3, d := 3)` | Compute stochrsi for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_t3` | `fin_t3(x, period := 20, vfactor := 0.7)` | Compute t3 for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_tema` | `fin_tema(x, period := 20)` | Compute tema for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_trade_sign` | `fin_trade_sign(102.0::DOUBLE, 100.0::DOUBLE, 101.0::DOUBLE)` | Compute trade sign for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_trima` | `fin_trima(x, period := 20)` | Compute trima for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_trix` | `fin_trix(close, period := 30)` | Compute trix for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_true_range` | `fin_true_range(high, low, close)` | Compute true range for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_tsf` | `fin_tsf(x, period := 14)` | Compute tsf for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_twap` | `fin_twap(price, ts)` | Compute twap for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_typ_price` | `fin_typ_price(high, low, close)` | Compute typ price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_ultosc` | `fin_ultosc(high, low, close, short := 7, medium := 14, long := 28)` | Compute ultosc for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_var_indicator` | `fin_var_indicator(close, period := 20, ddof := 1)` | Compute var indicator for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_volume_profile` | `fin_volume_profile(price, volume, bins := 10)` | Compute volume profile for SQL finance workflows. | LIST. |
| `fin_vpin` | `fin_vpin(signed_volume, volume, buckets := 50)` | Compute vpin for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_vwap` | `fin_vwap(price, volume)` | Compute vwap for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_close` | `fin_weighted_close(high, low, close)` | Compute weighted close for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_willr` | `fin_willr(high, low, close, period := 14)` | Compute willr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_wma` | `fin_wma(x, period := 20)` | Compute wma for SQL finance workflows. | Aggregate or scalar SQL macro result. |

### Portfolio, Matrix, And Factor Analytics

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_black_litterman_returns` | `fin_black_litterman_returns(market_weights, cov_matrix, views_p, views_q, tau := 0.05, omega := NULL)` | Compute black litterman returns for SQL finance workflows. | LIST. |
| `fin_component_risk` | `fin_component_risk(weights, cov_matrix)` | Compute component risk for SQL finance workflows. | LIST. |
| `fin_corr_matrix` | `fin_corr_matrix(asset, r)` | Compute corr matrix for SQL finance workflows. | LIST. |
| `fin_cov_matrix` | `fin_cov_matrix(asset, r)` | Compute cov matrix for SQL finance workflows. | LIST. |
| `fin_curve_discount_factor` | `fin_curve_discount_factor([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5)` | Compute curve discount factor for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_discount_factor` | `fin_discount_factor(0.05, 1.0, 'continuous')` | Compute discount factor for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_equal_weights` | `fin_equal_weights(n)` | Compute equal weights for SQL finance workflows. | LIST. |
| `fin_factor_alpha` | `fin_factor_alpha(r, factor_r, risk_free := 0.0, annualization := 252)` | Compute factor alpha for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_factor_ic` | `fin_factor_ic(factor, forward_return, method := 'spearman')` | Compute factor ic for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_factor_turnover` | `fin_factor_turnover(factor_rank, period := 1)` | Compute factor turnover for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_inverse_vol_weights` | `fin_inverse_vol_weights(vols)` | Compute inverse vol weights for SQL finance workflows. | LIST. |
| `fin_marginal_risk` | `fin_marginal_risk(weights, cov_matrix)` | Compute marginal risk for SQL finance workflows. | LIST. |
| `fin_matrix_cholesky` | `fin_matrix_cholesky([[4.0, 2.0], [2.0, 3.0]])` | Compute matrix cholesky for SQL finance workflows. | LIST. |
| `fin_matrix_is_psd` | `fin_matrix_is_psd([[1.0, 0.2], [0.2, 1.0]])` | Compute matrix is psd for SQL finance workflows. | LIST. |
| `fin_matrix_mul` | `fin_matrix_mul([[1.0, 2.0]], [[3.0], [4.0]])` | Compute matrix mul for SQL finance workflows. | LIST. |
| `fin_matrix_shape` | `fin_matrix_shape([[1.0, 2.0], [3.0, 4.0]])` | Compute matrix shape for SQL finance workflows. | STRUCT. |
| `fin_matrix_transpose` | `fin_matrix_transpose([[1.0, 2.0], [3.0, 4.0]])` | Compute matrix transpose for SQL finance workflows. | LIST. |
| `fin_matrix_vecmul` | `fin_matrix_vecmul([[1.0, 2.0], [3.0, 4.0]], [1.0, 1.0])` | Compute matrix vecmul for SQL finance workflows. | LIST. |
| `fin_max_sharpe_weights` | `fin_max_sharpe_weights(mu, cov_matrix, risk_free := 0.0, long_only := true)` | Compute max sharpe weights for SQL finance workflows. | LIST. |
| `fin_min_variance_weights` | `fin_min_variance_weights(cov_matrix, long_only := true)` | Minimum-variance optimizer compatibility macro. | LIST of weights; v1 placeholder returns equal weights sized from the covariance matrix. |
| `fin_newey_west_tstat` | `fin_newey_west_tstat(y, x, lags := 1)` | Compute newey west tstat for SQL finance workflows. | NULL placeholder. |
| `fin_ols` | `fin_ols(y, x_list)` | Compute ols for SQL finance workflows. | STRUCT. |
| `fin_ols_no_intercept` | `fin_ols_no_intercept(y, x_list)` | Compute ols no intercept for SQL finance workflows. | STRUCT. |
| `fin_portfolio_expected_return` | `fin_portfolio_expected_return([0.5, 0.5], [0.1, 0.2])` | Compute portfolio expected return for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_portfolio_return` | `fin_portfolio_return([0.5, 0.5], [0.1, 0.2])` | Compute portfolio return for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_portfolio_sharpe` | `fin_portfolio_sharpe(weights, mu, cov_matrix, risk_free := 0.0)` | Compute portfolio sharpe for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_portfolio_spec` | `fin_portfolio_spec(labels, weights, base_currency := NULL)` | Compute portfolio spec for SQL finance workflows. | STRUCT. |
| `fin_portfolio_variance` | `fin_portfolio_variance([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]])` | Compute portfolio variance for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_portfolio_vector` | `fin_portfolio_vector(weights, labels)` | Compute portfolio vector for SQL finance workflows. | STRUCT. |
| `fin_portfolio_vol` | `fin_portfolio_vol([0.5, 0.5], [[0.04, 0.01], [0.01, 0.09]])` | Compute portfolio vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_profit_factor` | `fin_profit_factor(r)` | Compute profit factor for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_recovery_factor` | `fin_recovery_factor(r)` | Compute recovery factor for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_risk_contribution` | `fin_risk_contribution(weights, cov_matrix)` | Compute risk contribution for SQL finance workflows. | LIST. |
| `fin_risk_parity_weights` | `fin_risk_parity_weights(cov_matrix, budgets := NULL, tol := 1e-8, max_iter := 1000)` | Compute risk parity weights for SQL finance workflows. | LIST. |
| `fin_turnover` | `fin_turnover(old_weights, new_weights)` | Compute turnover for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_vector_add` | `fin_vector_add([1.0, 2.0], [3.0, 4.0])` | Compute vector add for SQL finance workflows. | LIST. |
| `fin_vector_mean` | `fin_vector_mean([1.0, 2.0, 3.0])` | Compute vector mean for SQL finance workflows. | LIST. |
| `fin_vector_normalize_sum` | `fin_vector_normalize_sum([2.0, 2.0])` | Compute vector normalize sum for SQL finance workflows. | LIST. |
| `fin_vector_scale` | `fin_vector_scale([1.0, 2.0], 2.0)` | Compute vector scale for SQL finance workflows. | LIST. |
| `fin_vector_sub` | `fin_vector_sub([3.0, 4.0], [1.0, 2.0])` | Compute vector sub for SQL finance workflows. | LIST. |
| `fin_vector_sum` | `fin_vector_sum([1.0, 2.0, 3.0])` | Compute vector sum for SQL finance workflows. | LIST. |

### Validation, Parsers, Specs, And Calendars

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_bar_spec` | `fin_bar_spec(kind, threshold, price_col := 'price', volume_col := 'volume')` | Compute bar spec for SQL finance workflows. | STRUCT. |
| `fin_business_days_between` | `fin_business_days_between(DATE '2026-05-04', DATE '2026-05-08', 'weekday')` | Compute business days between for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_calendar_spec` | `fin_calendar_spec(calendar := 'weekday', timezone := NULL, regular_open := NULL, regular_close := NULL)` | Compute calendar spec for SQL finance workflows. | STRUCT. |
| `fin_is_business_day` | `fin_is_business_day(DATE '2026-05-06', 'weekday')` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_is_finite` | `fin_is_finite(1.0)` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_is_price` | `fin_is_price(1.0)` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_is_rate` | `fin_is_rate(0.05)` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_is_regular_session` | `fin_is_regular_session(TIMESTAMP '2026-05-06 10:00:00', 'NYSE')` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_is_vol` | `fin_is_vol(0.2)` | Predicate helper for finance input validation. | BOOLEAN. |
| `fin_next_business_day` | `fin_next_business_day(DATE '2026-05-08', 'weekday', 1)` | Compute next business day for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_normalize_currency` | `fin_normalize_currency('usd')` | Compute normalize currency for SQL finance workflows. | VARCHAR. |
| `fin_optimizer_spec` | `fin_optimizer_spec(objective := 'max_sharpe', risk_free := 0.0, long_only := true, weight_min := 0.0, weight_max := 1.0, target_return := NULL, target_vol := NULL, risk_aversion := 1.0)` | Compute optimizer spec for SQL finance workflows. | STRUCT. |
| `fin_parse_compounding` | `fin_parse_compounding('continuous')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_parse_day_count` | `fin_parse_day_count('actual/365 fixed')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_parse_exercise_style` | `fin_parse_exercise_style('American')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_prev_business_day` | `fin_prev_business_day(DATE '2026-05-11', 'weekday', 1)` | Compute prev business day for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_rate_spec` | `fin_rate_spec(rate, compounding := 'continuous', frequency := 1, day_count := 'ACT/365F')` | Compute rate spec for SQL finance workflows. | STRUCT. |
| `fin_risk_spec` | `fin_risk_spec(annualization := 252, risk_free := 0.0, var_confidence := 0.95, tail := 'left', loss_positive := true)` | Compute risk spec for SQL finance workflows. | STRUCT. |
| `fin_session_date` | `fin_session_date(TIMESTAMP '2026-05-06 10:00:00', 'NYSE')` | Compute session date for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_ts_grid_spec` | `fin_ts_grid_spec(start_ts, end_ts, step, staleness := NULL, method := 'last')` | Compute ts grid spec for SQL finance workflows. | STRUCT. |
| `fin_typeof` | `fin_typeof(x)` | Compute typeof for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_validate_ohlc` | `fin_validate_ohlc(100.0, 101.0, 99.0, 100.0)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | STRUCT. |
| `fin_validate_rate_spec` | `fin_validate_rate_spec(spec)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | STRUCT. |
| `fin_var_spec` | `fin_var_spec(confidence := 0.95, method := 'historical', tail := 'left', loss_positive := true)` | Compute var spec for SQL finance workflows. | STRUCT. |

### Table Functions And Time-Series Builders

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_bootstrap_curve` | `fin_bootstrap_curve('gold_curve', 'inst', 'maturity', 'rate', 'continuous')` | Build a simple bootstrapped curve table from instrument maturities and rates. | Table result. |
| `fin_calendar` | `fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-06')` | Return business-calendar dates for a calendar name and date range. | Table result. |
| `fin_changes_to_grid` | `fin_changes_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute changes to grid for SQL finance workflows. | Table result. |
| `fin_curve_bootstrap` | `fin_curve_bootstrap('gold_curve', 'inst', 'maturity', 'rate', 'continuous')` | Alias for curve bootstrapping. | Table result. |
| `fin_delta_to_grid` | `fin_delta_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute delta to grid for SQL finance workflows. | Table result. |
| `fin_dollar_bars` | `fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 100000.0)` | Compute dollar bars for SQL finance workflows. | Table result. |
| `fin_efficient_frontier` | `fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]])` | Compute efficient frontier for SQL finance workflows. | Table result. |
| `fin_factor_report` | `fin_factor_report('gold_returns', 'd', 'asset', 'factor', 'forward_return', 2)` | Compute factor report for SQL finance workflows. | Table result. |
| `fin_fama_macbeth` | `fin_fama_macbeth('gold_returns', 'd', 'asset', 'forward_return', ['factor'], 1)` | Compute fama macbeth for SQL finance workflows. | Table result. |
| `fin_garch_fit` | `fin_garch_fit('gold_returns', 'r', 1, 1, 'normal')` | Compute garch fit for SQL finance workflows. | Table result. |
| `fin_hrp_weights` | `fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]], ['AAA', 'BBB'], 'single')` | Compute hrp weights for SQL finance workflows. | Table result. |
| `fin_imbalance_bars` | `fin_imbalance_bars('gold_prices', 'ts', 'close', 'volume', 'signed')` | Compute imbalance bars for SQL finance workflows. | Table result. |
| `fin_last_to_grid` | `fin_last_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute last to grid for SQL finance workflows. | Table result. |
| `fin_option_chain` | `fin_option_chain('gold_options', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield')` | Project option input rows and compute model prices/Greeks. | Table result. |
| `fin_portfolio_optimize` | `fin_portfolio_optimize([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 'max_sharpe', 0.0, true, 0.0, 1.0, 0.12, 0.2, 1.0)` | Compute portfolio optimize for SQL finance workflows. | Table result. |
| `fin_portfolio_optimize_table` | `fin_portfolio_optimize_table('gold_current_weights', 'asset', 'weight', 'weight')` | Compute portfolio optimize table for SQL finance workflows. | Table result. |
| `fin_predict_linear_to_grid` | `fin_predict_linear_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute predict linear to grid for SQL finance workflows. | Table result. |
| `fin_rate_to_grid` | `fin_rate_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute rate to grid for SQL finance workflows. | Table result. |
| `fin_rebalance_trades` | `fin_rebalance_trades('gold_current_weights', 'gold_target_weights', 'gold_asset_prices', 100000.0)` | Compute rebalance trades for SQL finance workflows. | Table result. |
| `fin_resample_grid` | `fin_resample_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute', 'last', INTERVAL '10 minutes' )` | Compute resample grid for SQL finance workflows. | Table result. |
| `fin_resets_to_grid` | `fin_resets_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute resets to grid for SQL finance workflows. | Table result. |
| `fin_schema_template` | `fin_schema_template('ohlcv')` | Return the expected columns for a named finance schema template. | Table result. |
| `fin_tick_bars` | `fin_tick_bars('gold_prices', 'ts', 'close')` | Compute tick bars for SQL finance workflows. | Table result. |
| `fin_validate_schema` | `fin_validate_schema('gold_prices', 'ohlcv')` | Return schema-template rows for validating a table against a template. | Table result. |
| `fin_volume_bars` | `fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 1000.0)` | Compute volume bars for SQL finance workflows. | Table result. |

### General Helpers

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_adf` | `fin_adf(x, max_lag := 1, regression := 'c')` | Compute adf for SQL finance workflows. | NULL placeholder. |
| `fin_autocorr` | `fin_autocorr(x, lag := 1)` | Compute autocorr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_bipower_variation` | `fin_bipower_variation(log_r, annualization := 252)` | Compute bipower variation for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_cagr` | `fin_cagr(r, annualization := 252)` | Compute cagr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_changes` | `fin_changes(x)` | Compute changes for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_crosscorr` | `fin_crosscorr(x, y, lag := 0)` | Compute crosscorr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_delta` | `fin_delta(x)` | Compute delta for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_dot` | `fin_dot([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])` | Compute dot for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_dv01` | `fin_dv01(0.05, 0.04, 5.0, 2, 100.0)` | Compute dv01 for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_ema` | `fin_ema(x, period := 20)` | Compute ema for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ema_halflife` | `fin_ema_halflife(x, ts, halflife)` | Compute ema halflife for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ewma_vol` | `fin_ewma_vol(r, lambda := 0.94, annualization := 252)` | Compute ewma vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_exp_decay_avg` | `fin_exp_decay_avg(x, ts, halflife)` | Compute exp decay avg for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_exp_decay_count` | `fin_exp_decay_count(ts, halflife)` | Compute exp decay count for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_exp_decay_max` | `fin_exp_decay_max(x, ts, halflife)` | Compute exp decay max for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_exp_decay_sum` | `fin_exp_decay_sum(x, ts, halflife)` | Compute exp decay sum for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_expected_shortfall` | `fin_expected_shortfall(r, confidence := 0.95, method := 'historical')` | Compute expected shortfall for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_first_non_null` | `fin_first_non_null(x)` | Compute first non null for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_garman_klass_vol` | `fin_garman_klass_vol(open, high, low, close, annualization := 252)` | Compute garman klass vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_half_life_mean_reversion` | `fin_half_life_mean_reversion(x)` | Compute half life mean reversion for SQL finance workflows. | NULL placeholder. |
| `fin_hurst` | `fin_hurst(x)` | Compute hurst for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_last_non_null` | `fin_last_non_null(x)` | Compute last non null for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_linear_trend` | `fin_linear_trend(y, x := NULL)` | Compute linear trend for SQL finance workflows. | STRUCT. |
| `fin_ljung_box` | `fin_ljung_box(x, lags := 10)` | Compute ljung box for SQL finance workflows. | NULL placeholder. |
| `fin_log_nav` | `fin_log_nav(r, initial_nav := 1.0)` | Compute log nav for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_nav` | `fin_nav(r, initial_nav := 1.0)` | Compute nav for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_nearest_psd` | `fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]])` | Compute nearest psd for SQL finance workflows. | LIST. |
| `fin_parametric_var` | `fin_parametric_var(mean, vol, confidence := 0.95, horizon := 1.0, distribution := 'normal')` | Compute parametric var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_parkinson_vol` | `fin_parkinson_vol(high, low, annualization := 252)` | Compute parkinson vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_pct_change` | `fin_pct_change(x)` | Compute pct change for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_quantile_spread` | `fin_quantile_spread(factor, forward_return, buckets := 5)` | Compute quantile spread for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rank_ic` | `fin_rank_ic(factor, forward_return)` | Compute rank ic for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rate` | `fin_rate(x, ts, unit := 'second')` | Compute rate for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_resets` | `fin_resets(x)` | Compute resets for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rogers_satchell_vol` | `fin_rogers_satchell_vol(open, high, low, close, annualization := 252)` | Compute rogers satchell vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_var` | `fin_var(r, confidence := 0.95, method := 'historical', loss_positive := true)` | Compute var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_version` | `fin_version()` | Return the loaded finance extension version string. | VARCHAR. |
| `fin_vol_of_vol` | `fin_vol_of_vol(vol, annualization := 252)` | Compute vol of vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_yang_zhang_vol` | `fin_yang_zhang_vol(open, high, low, close, annualization := 252)` | Compute yang zhang vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |

## Testing

The reference surface is exercised by `make test`, which builds the extension, runs smoke SQL, loads `test/sql/gold_dataset.sql`, and evaluates `test/sql/gold_tests.sql`. The gold dataset is intentionally small and deterministic so expected values are easy to audit.

For model and unit conventions, see
[Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}). For workflow-oriented
examples, see [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}).

## GS Quant-Inspired Pricing And Risk Helpers

These helpers port the parts of GS Quant's pricing-and-risk model that fit a local SQL extension: instrument descriptors, risk-measure descriptors, pricing context descriptors, scenario transforms, and portfolio aggregation. They are independent DuckDB implementations and do not call Goldman Sachs APIs. See [GS Quant-Inspired SQL Mapping]({{ '/gs-quant-mapping/' | relative_url }}) for model semantics, source-shape mapping, and the Goldman-style golden dataset.

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_gsq_pricing_context` | `fin_gsq_pricing_context(pricing_date, market_data_as_of := NULL, market_data_location := 'NYC', is_async := false, is_batch := false)` | Describe a pricing date, market data date/location, and computation mode. | STRUCT. |
| `fin_gsq_historical_pricing_context` | `fin_gsq_historical_pricing_context(start_date, end_date, market_data_location := 'NYC', is_async := false, is_batch := false)` | Describe a historical pricing window. | STRUCT. |
| `fin_gsq_instrument` | `fin_gsq_instrument(kind, asset_class, currency, notional := 1.0, underlier := NULL, maturity := NULL)` | Build a generic instrument descriptor. | STRUCT. |
| `fin_gsq_eq_option` | `fin_gsq_eq_option(kind, underlier, spot, strike, ttm, rate, vol, dividend_yield := 0.0, notional := 1.0, currency := 'USD')` | Build an equity option descriptor. | STRUCT. |
| `fin_gsq_fx_forward` | `fin_gsq_fx_forward(pair, spot, strike, ttm, domestic_rate, foreign_rate, notional := 1.0, currency := 'USD')` | Build an FX forward descriptor. | STRUCT. |
| `fin_gsq_fx_option` | `fin_gsq_fx_option(kind, pair, spot, strike, ttm, domestic_rate, foreign_rate, vol, notional := 1.0, currency := 'USD')` | Build an FX option descriptor using Garman-Kohlhagen style inputs. | STRUCT. |
| `fin_gsq_fx_binary` | `fin_gsq_fx_binary(kind, pair, spot, strike, ttm, domestic_rate, foreign_rate, vol, payout := 1.0, currency := 'USD')` | Build an FX digital/binary option descriptor. | STRUCT. |
| `fin_gsq_ir_swap` | `fin_gsq_ir_swap(pay_receive, tenor, currency, fixed_rate, par_rate, annuity, notional := 1.0)` | Build a vanilla interest-rate swap descriptor. | STRUCT. |
| `fin_gsq_ir_swaption` | `fin_gsq_ir_swaption(pay_receive, expiration, tenor, currency, forward_rate, strike, annuity, vol, ttm, rate := 0.0, notional := 1.0)` | Build an interest-rate swaption descriptor. | STRUCT. |
| `fin_gsq_ir_cap_floor` | `fin_gsq_ir_cap_floor(kind, currency, forward_rate, strike, annuity, vol, ttm, rate := 0.0, notional := 1.0)` | Build an interest-rate cap or floor descriptor. | STRUCT. |
| `fin_gsq_inflation_swap` | `fin_gsq_inflation_swap(currency, fixed_rate, inflation_rate, annuity, notional := 1.0)` | Build a zero-coupon style inflation swap descriptor. | STRUCT. |
| `fin_gsq_cd_index` | `fin_gsq_cd_index(index_name, spread, maturity, notional := 1.0, currency := 'USD')` | Build a credit index descriptor. | STRUCT. |
| `fin_gsq_cd_index_option` | `fin_gsq_cd_index_option(kind, index_name, forward_spread, strike_spread, ttm, rate, vol, risky_annuity, notional := 1.0, currency := 'USD')` | Build a credit index option descriptor. | STRUCT. |
| `fin_gsq_measure` | `fin_gsq_measure(name, asset_class := NULL, measure_type := NULL, currency := NULL, bump_size := NULL, aggregation_level := NULL)` | Build a generic risk-measure descriptor. | STRUCT. |
| `fin_gsq_measure_price` | `fin_gsq_measure_price(currency := NULL)` | Descriptor for local-currency price. | STRUCT. |
| `fin_gsq_measure_dollar_price` | `fin_gsq_measure_dollar_price()` | Descriptor for USD dollar price. | STRUCT. |
| `fin_gsq_measure_forward_price` | `fin_gsq_measure_forward_price()` | Descriptor for forward price. | STRUCT. |
| `fin_gsq_measure_eq_delta` | `fin_gsq_measure_eq_delta(currency := NULL, bump_size := 0.01)` | Descriptor for equity delta. | STRUCT. |
| `fin_gsq_measure_eq_gamma` | `fin_gsq_measure_eq_gamma(currency := NULL, bump_size := 0.01)` | Descriptor for equity gamma. | STRUCT. |
| `fin_gsq_measure_eq_vega` | `fin_gsq_measure_eq_vega(currency := NULL, bump_size := 0.0001)` | Descriptor for equity vega. | STRUCT. |
| `fin_gsq_measure_fx_delta` | `fin_gsq_measure_fx_delta(currency := NULL)` | Descriptor for FX delta. | STRUCT. |
| `fin_gsq_measure_fx_gamma` | `fin_gsq_measure_fx_gamma(currency := NULL)` | Descriptor for FX gamma. | STRUCT. |
| `fin_gsq_measure_fx_vega` | `fin_gsq_measure_fx_vega(currency := NULL)` | Descriptor for FX vega. | STRUCT. |
| `fin_gsq_measure_ir_delta` | `fin_gsq_measure_ir_delta(currency := NULL, bump_size := 0.0001, aggregation_level := 'Type')` | Descriptor for interest-rate delta. | STRUCT. |
| `fin_gsq_measure_ir_delta_parallel` | `fin_gsq_measure_ir_delta_parallel(currency := NULL, bump_size := 0.0001)` | Descriptor for parallel interest-rate delta. | STRUCT. |
| `fin_gsq_measure_ir_gamma` | `fin_gsq_measure_ir_gamma(currency := NULL, bump_size := 0.0001)` | Descriptor for interest-rate gamma. | STRUCT. |
| `fin_gsq_measure_ir_vega` | `fin_gsq_measure_ir_vega(currency := NULL, bump_size := 0.0001)` | Descriptor for interest-rate vega. | STRUCT. |
| `fin_gsq_measure_cd_delta` | `fin_gsq_measure_cd_delta(currency := NULL, bump_size := 0.0001)` | Descriptor for credit delta. | STRUCT. |
| `fin_gsq_measure_cd_gamma` | `fin_gsq_measure_cd_gamma(currency := NULL, bump_size := 0.0001)` | Descriptor for credit gamma. | STRUCT. |
| `fin_gsq_measure_cd_vega` | `fin_gsq_measure_cd_vega(currency := NULL, bump_size := 0.0001)` | Descriptor for credit vega. | STRUCT. |
| `fin_gsq_eq_option_price` | `fin_gsq_eq_option_price(instrument)` | Price an equity option descriptor using the local BSM implementation. | DOUBLE. |
| `fin_gsq_eq_delta` | `fin_gsq_eq_delta(instrument)` | Compute notional-scaled equity option delta. | DOUBLE. |
| `fin_gsq_eq_gamma` | `fin_gsq_eq_gamma(instrument)` | Compute notional-scaled equity option gamma. | DOUBLE. |
| `fin_gsq_eq_vega` | `fin_gsq_eq_vega(instrument)` | Compute notional-scaled equity option vega. | DOUBLE. |
| `fin_gsq_calc_eq_option` | `fin_gsq_calc_eq_option(instrument, measure)` | Dispatch supported equity option measures from a measure descriptor. | DOUBLE or NULL for unsupported measures. |
| `fin_gsq_fx_forward_value` | `fin_gsq_fx_forward_value(instrument)` | Present value an FX forward descriptor from domestic/foreign rates. | DOUBLE. |
| `fin_gsq_fx_option_price` | `fin_gsq_fx_option_price(instrument)` | Price an FX option descriptor with domestic discounting and foreign yield. | DOUBLE. |
| `fin_gsq_fx_binary_price` | `fin_gsq_fx_binary_price(instrument)` | Price an FX binary option descriptor. | DOUBLE. |
| `fin_gsq_ir_swap_price` | `fin_gsq_ir_swap_price(instrument)` | Approximate fixed-vs-floating swap PV from fixed rate, par rate, annuity, notional, and pay/receive direction. | DOUBLE. |
| `fin_gsq_ir_swaption_price` | `fin_gsq_ir_swaption_price(instrument)` | Price a swaption descriptor with Black-76 on the forward swap rate. | DOUBLE. |
| `fin_gsq_ir_cap_floor_price` | `fin_gsq_ir_cap_floor_price(instrument)` | Price a cap/floor period descriptor with Black-76. | DOUBLE. |
| `fin_gsq_inflation_swap_price` | `fin_gsq_inflation_swap_price(instrument)` | Approximate inflation swap PV from inflation rate, fixed rate, annuity, and notional. | DOUBLE. |
| `fin_gsq_cd_index_option_price` | `fin_gsq_cd_index_option_price(instrument)` | Approximate credit index option PV with Black-76 on forward spread. | DOUBLE. |
| `fin_gsq_market_data_pattern` | `fin_gsq_market_data_pattern(mkt_type, mkt_asset := NULL, mkt_class := NULL, mkt_point := NULL, mkt_quoting_style := NULL)` | Build a market-data pattern descriptor for scenario matching. | STRUCT. |
| `fin_gsq_market_data_shock` | `fin_gsq_market_data_shock(shock_type, value, stddev := NULL)` | Build a market-data shock descriptor. Supported shock types include `Absolute`, `Proportional`, `Override`, and `StdDev`. | STRUCT. |
| `fin_gsq_market_data_shock_scenario` | `fin_gsq_market_data_shock_scenario(pattern, shock)` | Build a market-data-shock scenario descriptor. | STRUCT. |
| `fin_gsq_apply_shock` | `fin_gsq_apply_shock(base_value, shock)` | Apply a market-data shock descriptor to a scalar value. | DOUBLE. |
| `fin_gsq_curve_scenario` | `fin_gsq_curve_scenario(parallel_shift_bps := 0.0, curve_shift_bps := 0.0, tenor_start := 0.0, tenor_end := 30.0, pivot_point := NULL)` | Build a curve scenario with parallel and slope shifts in basis points. | STRUCT. |
| `fin_gsq_curve_scenario_rate` | `fin_gsq_curve_scenario_rate(base_rate, tenor, scenario)` | Apply a curve scenario to a scalar rate at a tenor. | DOUBLE. |
| `fin_gsq_roll_fwd` | `fin_gsq_roll_fwd(date, tenor)` | Build a roll-forward scenario descriptor. | STRUCT. |
| `fin_gsq_index_curve_shift` | `fin_gsq_index_curve_shift(index_name, parallel_shift_bps := 0.0)` | Build an index curve shift descriptor. | STRUCT. |
| `fin_gsq_scenario_pnl` | `fin_gsq_scenario_pnl(base_value, scenario_value)` | Compute scenario PnL as shocked value minus base value. | DOUBLE. |
| `fin_gsq_delta_gamma_pnl` | `fin_gsq_delta_gamma_pnl(delta, gamma, shock)` | Approximate PnL from delta, gamma, and a scalar shock. | DOUBLE. |
| `fin_gsq_portfolio_item` | `fin_gsq_portfolio_item(name, instrument_type, quantity, value, risk := 0.0, currency := NULL)` | Build a portfolio item descriptor. | STRUCT. |
| `fin_gsq_portfolio_value` | `fin_gsq_portfolio_value(value, quantity := 1.0)` | Aggregate quantity-weighted portfolio value. | Aggregate DOUBLE. |
| `fin_gsq_portfolio_risk` | `fin_gsq_portfolio_risk(risk, quantity := 1.0)` | Aggregate quantity-weighted portfolio risk. | Aggregate DOUBLE. |

### GS Quant-Inspired Examples

Price and risk an equity option descriptor:

```sql
WITH option AS (
  SELECT fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20) AS inst
)
SELECT
  fin_gsq_eq_option_price(inst) AS price,
  fin_gsq_eq_delta(inst) AS delta,
  fin_gsq_eq_gamma(inst) AS gamma,
  fin_gsq_eq_vega(inst) AS vega
FROM option;
```

Use a risk-measure descriptor for local dispatch:

```sql
SELECT fin_gsq_calc_eq_option(
  fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20),
  fin_gsq_measure_price('USD')
) AS price;
```

Apply a GS Quant-style market-data shock:

```sql
SELECT fin_gsq_apply_shock(
  0.20,
  fin_gsq_market_data_shock('Absolute', 0.0001)
) AS shocked_vol;
```

Aggregate a local portfolio result set:

```sql
SELECT
  portfolio_id,
  fin_gsq_portfolio_value(value, quantity) AS portfolio_value,
  fin_gsq_portfolio_risk(risk, quantity) AS portfolio_risk
FROM gsq_goldman_portfolio_cases
GROUP BY portfolio_id;
```

### GS Quant-Inspired Golden Dataset

The deterministic fixtures in `test/sql/gold_dataset.sql` use the prefix
`gsq_goldman_`. They cover equity, FX, rates, inflation, credit, scenario, and
portfolio cases. The expected values are constants, and `test/sql/gold_tests.sql`
compares public `fin_gsq_*` functions against those constants with explicit
tolerances.
