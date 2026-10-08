-- Runnable example for every registered fin_* function.
--
-- scripts/generate_function_metadata.py copies each example into the
-- duckdb_functions() `examples` column, and `make check-examples` runs every
-- example against a fresh in-memory database with only the extension loaded.
-- Examples must therefore be self-contained: inline VALUES, range(), literals
-- or CTEs, no fixture tables, files, or network access.
--
-- Format: one block per function, in docs/function_reference.md order.
--   -- fin_name                              header for SQL macros (their
--                                            parameter names come from DuckDB)
--   -- fin_name(arg, arg, ...)               header for native functions: the
--                                            parameter names shown by
--                                            duckdb_functions(); repeat the
--                                            line for overload shapes that
--                                            differ, shortest first
--   SELECT ...;                              exactly one statement
-- An overload with N positional arguments takes the first N names of the first
-- signature that has at least N names and whose `name:TYPE` hints (optional)
-- match its argument types.

-- fin_bps(x)
SELECT fin_bps(0.0125) AS bps;

-- fin_cents_to_money
SELECT fin_cents_to_money(12345, 2) AS amount;

-- fin_chi2_cdf(x, df)
SELECT fin_chi2_cdf(11.0705, 5.0) AS p;

-- fin_chi2_inv(p, df)
SELECT fin_chi2_inv(0.95, 5.0) AS x;

-- fin_clip(x, lower, upper)
SELECT fin_clip(12.0, 0.0, 10.0) AS clipped;

-- fin_from_bps(bps)
SELECT fin_from_bps(125.0) AS decimal_rate;

-- fin_money_round
SELECT fin_money_round(2.345, 2, 'half_even') AS rounded;

-- fin_money_sum
SELECT fin_money_sum(amount) AS total
FROM (VALUES (10.10::DECIMAL(18, 2)), (20.20), (0.05)) t(amount);

-- fin_money_to_cents
SELECT fin_money_to_cents(12.345, 'nearest') AS cents;

-- fin_money_weighted_sum
SELECT fin_money_weighted_sum(amount, weight) AS weighted
FROM (VALUES (100.0, 0.5), (200.0, 0.25)) t(amount, weight);

-- fin_norm_cdf(x)
SELECT fin_norm_cdf(1.96) AS p;

-- fin_norm_inv(p)
SELECT fin_norm_inv(0.975) AS z;

-- fin_norm_pdf(x)
SELECT fin_norm_pdf(0.0) AS density;

-- fin_round_to_tick(price, tick, mode)
SELECT fin_round_to_tick(100.037, 0.05, 'nearest') AS price;

-- fin_safe_div(numerator, denominator, fallback)
SELECT fin_safe_div(1.0, 0.0, 0.0) AS ratio;

-- fin_student_t_cdf(x, df)
SELECT fin_student_t_cdf(2.228139, 10.0) AS p;

-- fin_student_t_inv(p, df)
SELECT fin_student_t_inv(0.975, 10.0) AS t;

-- fin_active_return
SELECT fin_active_return(r, benchmark_r, 252) AS active_return
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_aggregate_return
SELECT month, fin_aggregate_return(r, 'simple') AS monthly_return
FROM (VALUES (1, 0.01), (1, 0.02), (2, -0.01), (2, 0.03)) t(month, r)
GROUP BY month ORDER BY month;

-- fin_alpha
SELECT fin_alpha(r, benchmark_r, 0.02, 252) AS alpha
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_alpha_beta
SELECT fin_alpha_beta(r, benchmark_r, 0.02, 252) AS capm
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_annual_return
SELECT fin_annual_return(r, 252) AS annual_return
FROM (VALUES (0.001), (0.002), (-0.001), (0.0015)) t(r);

-- fin_anova_oneway
SELECT fin_anova_oneway(value, grp) AS anova
FROM (VALUES (1.0, 'a'), (2.0, 'a'), (3.0, 'a'), (4.0, 'b'), (5.0, 'b'), (7.0, 'b')) t(value, grp);

-- fin_arithmetic_return
SELECT fin_arithmetic_return(r) AS mean_return
FROM (VALUES (0.01), (-0.02), (0.015)) t(r);

-- fin_avg_drawdown(r, initial_nav)
SELECT fin_avg_drawdown(r ORDER BY ts) AS avg_drawdown
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_beta(r, benchmark_r)
SELECT fin_beta(r, benchmark_r) AS beta
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_calmar
SELECT fin_calmar(r, ts, 252) AS calmar
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_conditional_drawdown_at_risk(r, confidence)
SELECT fin_conditional_drawdown_at_risk(r, 0.8 ORDER BY ts) AS cdar
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_cramers_v
SELECT fin_cramers_v(x, y, false) AS cramers_v
FROM (VALUES ('a', 'u'), ('a', 'u'), ('b', 'v'), ('b', 'v'), ('a', 'v'), ('b', 'u'), ('a', 'u')) t(x, y);

-- fin_cum_return
SELECT fin_cum_return(r, 'simple') AS cumulative_return
FROM (VALUES (0.01), (0.02), (-0.01)) t(r);

-- fin_cvar(r, confidence, method, loss_positive)
SELECT fin_cvar(r, 0.8, 'historical', true) AS cvar
FROM (VALUES (0.01), (-0.04), (0.02), (-0.01), (0.03), (-0.02), (0.005), (0.015), (-0.03), (0.01)) t(r);

-- fin_data_quality_report
SELECT fin_data_quality_report(x) AS report
FROM (VALUES (1.0), (NULL), ('nan'::DOUBLE), (2.0)) t(x);

-- fin_down_capture
SELECT fin_down_capture(r, benchmark_r) AS down_capture
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (-0.004, -0.006)) t(r, benchmark_r);

-- fin_downside_deviation(r, mar, annualization)
SELECT fin_downside_deviation(r, 0.0, 252) AS downside_deviation
FROM (VALUES (0.01), (-0.02), (0.015), (-0.005), (0.012)) t(r);

-- fin_drawdown(r, initial_nav)
SELECT fin_drawdown(r ORDER BY ts) AS current_drawdown
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02)) t(ts, r);

-- fin_drawdown_at_risk(r, confidence)
SELECT fin_drawdown_at_risk(r, 0.8 ORDER BY ts) AS dar
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_drawdown_duration(r, initial_nav)
SELECT fin_drawdown_duration(r ORDER BY ts) AS longest_drawdown_rows
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.20)) t(ts, r);

-- fin_entropy
SELECT fin_entropy(x) AS entropy_bits
FROM (VALUES ('a'), ('a'), ('b'), ('c')) t(x);

-- fin_ewma_variance(r, lambda, annualization)
SELECT fin_ewma_variance(r, 0.94, 252.0 ORDER BY ts) AS ewma_variance
FROM (VALUES (1, 0.01), (2, -0.02), (3, 0.015), (4, -0.005)) t(ts, r);

-- fin_excess_return
SELECT fin_excess_return(0.001, 0.05, 252, 'annual') AS excess_return;

-- fin_expectancy
SELECT fin_expectancy(r) AS expectancy
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_from_log_return
SELECT fin_from_log_return(0.05) AS simple_return;

-- fin_gain_to_pain
SELECT fin_gain_to_pain(r) AS gain_to_pain
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_garch11_forecast(r, omega, alpha, beta, initial_var, annualization)
SELECT fin_garch11_forecast(r, 0.000002, 0.08, 0.9 ORDER BY ts) AS annualized_variance
FROM (VALUES (1, 0.01), (2, -0.02), (3, 0.015), (4, -0.005), (5, 0.007)) t(ts, r);

-- fin_geometric_return
SELECT fin_geometric_return(r) AS geometric_mean
FROM (VALUES (0.10), (-0.05), (0.08)) t(r);

-- fin_gross_return
SELECT fin_gross_return(r) AS gross_return
FROM (VALUES (0.10), (-0.05), (0.08)) t(r);

-- fin_hit_ratio
SELECT fin_hit_ratio(r, 0.0, 252) AS hit_ratio
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_information_ratio
SELECT fin_information_ratio(r, benchmark_r, 252) AS information_ratio
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_is_decimal_return
SELECT fin_is_decimal_return(0.05) AS decimal_ok, fin_is_decimal_return(5.0) AS percent_like;

-- fin_is_outlier_zscore(x, mean, stddev, threshold)
SELECT fin_is_outlier_zscore(3.1, 0.0, 1.0, 3.0) AS is_outlier;

-- fin_iv_percentile(iv)
SELECT fin_iv_percentile(iv ORDER BY quote_date) AS iv_percentile
FROM (VALUES (DATE '2026-01-02', 0.20), (DATE '2026-01-05', 0.25), (DATE '2026-01-06', 0.18), (DATE '2026-01-07', 0.22)) t(quote_date, iv);

-- fin_iv_rank(iv)
SELECT fin_iv_rank(iv ORDER BY quote_date) AS iv_rank
FROM (VALUES (DATE '2026-01-02', 0.20), (DATE '2026-01-05', 0.25), (DATE '2026-01-06', 0.18), (DATE '2026-01-07', 0.22)) t(quote_date, iv);

-- fin_jensen_alpha
SELECT fin_jensen_alpha(r, benchmark_r, 0.02, 252) AS jensen_alpha
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_kahan_sum
SELECT fin_kahan_sum(0.1::DOUBLE) AS total
FROM range(10);

-- fin_ks_test(x, y)
SELECT fin_ks_test(x, y) AS ks
FROM (VALUES (0.1, 0.4), (0.2, 0.5), (0.3, 0.6), (0.35, 0.7), (NULL, 0.8)) t(x, y);

-- fin_log_return
SELECT fin_log_return(105.0, 100.0) AS log_return;

-- fin_loss_rate
SELECT fin_loss_rate(r) AS loss_rate
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_mad
SELECT fin_mad(x) AS mad
FROM (VALUES (1.0), (2.0), (2.0), (4.0), (10.0)) t(x);

-- fin_mann_whitney_u(x, y)
SELECT fin_mann_whitney_u(x, y) AS mwu
FROM (VALUES (1.0, 4.0), (2.0, 5.0), (3.0, 6.0), (3.5, 7.0)) t(x, y);

-- fin_max_drawdown(r, initial_nav)
SELECT fin_max_drawdown(r ORDER BY ts) AS max_drawdown
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_missing_count
SELECT fin_missing_count(x) AS missing
FROM (VALUES (1.0), (NULL), ('nan'::DOUBLE), (2.0)) t(x);

-- fin_mutual_information
SELECT fin_mutual_information(x, y, 2) AS mutual_information_nats
FROM (VALUES (1.0, 1.1), (2.0, 2.2), (3.0, 2.9), (4.0, 4.2), (5.0, 5.1), (6.0, 5.8)) t(x, y);

-- fin_omega_ratio
SELECT fin_omega_ratio(r, 0.0, 252) AS omega
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_outlier_count(x, threshold:DOUBLE)
-- fin_outlier_count(x, method, threshold)
SELECT fin_outlier_count(x, 'zscore', 2.0) AS outliers
FROM (VALUES (1.0), (1.1), (0.9), (1.0), (1.2), (0.8), (1.0), (9.0)) t(x);

-- fin_parametric_cvar
SELECT fin_parametric_cvar(0.0005, 0.02, 0.99, 10.0, 'normal', NULL) AS cvar_10d;

-- fin_parse_return_method(method)
SELECT fin_parse_return_method('LOG') AS method;

-- fin_payoff_ratio
SELECT fin_payoff_ratio(r) AS payoff_ratio
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_price_from_return
SELECT fin_price_from_return(100.0, 0.05, 'simple') AS price;

-- fin_rank_corr
SELECT fin_rank_corr(x, y, 'kendall') AS kendall_tau
FROM (VALUES (1.0, 2.0), (2.0, 1.0), (3.0, 4.0), (4.0, 3.0), (5.0, 5.0)) t(x, y);

-- fin_realized_beta
SELECT fin_realized_beta(r, benchmark_r) AS beta
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_realized_corr
SELECT fin_realized_corr(r1, r2) AS corr
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r1, r2);

-- fin_realized_cov
SELECT fin_realized_cov(r1, r2) AS cov
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r1, r2);

-- fin_realized_quarticity
SELECT fin_realized_quarticity(log_r, 252) AS quarticity
FROM (VALUES (0.001), (-0.002), (0.0015), (-0.0005)) t(log_r);

-- fin_realized_variance
SELECT fin_realized_variance(log_r, 252) AS realized_variance
FROM (VALUES (0.001), (-0.002), (0.0015), (-0.0005)) t(log_r);

-- fin_realized_vol
SELECT fin_realized_vol(log_r, 252) AS realized_vol
FROM (VALUES (0.001), (-0.002), (0.0015), (-0.0005)) t(log_r);

-- fin_return
SELECT fin_return(105.0, 100.0, 'log') AS log_return;

-- fin_rolling_beta(r, factor_r)
SELECT ts, fin_rolling_beta(r, factor_r) OVER (ORDER BY ts ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS beta_3
FROM (VALUES (1, 0.010, 0.008), (2, -0.020, -0.015), (3, 0.015, 0.010), (4, 0.004, 0.002)) t(ts, r, factor_r)
ORDER BY ts;

-- fin_rolling_zscore(x, ts)
SELECT ts, fin_rolling_zscore(x, ts) OVER (ORDER BY ts ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS zscore_4
FROM (VALUES (1, 10.0), (2, 11.0), (3, 9.5), (4, 12.0), (5, 10.5)) t(ts, x)
ORDER BY ts;

-- fin_semivariance
SELECT fin_semivariance(r, 0.0, 252) AS semivariance
FROM (VALUES (0.01), (-0.02), (0.015), (-0.005)) t(r);

-- fin_sharpe(r, risk_free, annualization)
SELECT fin_sharpe(r, 0.02, 252) AS sharpe
FROM (VALUES (0.010), (-0.004), (0.006), (0.002), (0.008)) t(r);

-- fin_simple_return
SELECT fin_simple_return(105.0, 100.0) AS simple_return;

-- fin_sortino(r, mar, annualization)
SELECT fin_sortino(r, 0.0, 252) AS sortino
FROM (VALUES (0.010), (-0.004), (0.006), (-0.002), (0.008)) t(r);

-- fin_stability(r)
SELECT fin_stability(r ORDER BY ts) AS stability
FROM (VALUES (1, 0.010), (2, 0.004), (3, 0.006), (4, -0.002), (5, 0.008)) t(ts, r);

-- fin_stable_corr
SELECT fin_stable_corr(y, x) AS corr
FROM (VALUES (1.0, 1.0), (2.1, 2.0), (2.9, 3.0), (4.2, 4.0)) t(y, x);

-- fin_stable_cov
SELECT fin_stable_cov(y, x) AS cov
FROM (VALUES (1.0, 1.0), (2.1, 2.0), (2.9, 3.0), (4.2, 4.0)) t(y, x);

-- fin_stable_mean
SELECT fin_stable_mean(x) AS mean
FROM (VALUES (1e9 + 1.0), (1e9 + 2.0), (1e9 + 3.0)) t(x);

-- fin_stable_stddev
SELECT fin_stable_stddev(x, 1) AS stddev
FROM (VALUES (1.0), (2.0), (4.0)) t(x);

-- fin_stable_var
SELECT fin_stable_var(x, 0) AS population_variance
FROM (VALUES (1.0), (2.0), (4.0)) t(x);

-- fin_tail_ratio
SELECT fin_tail_ratio(r, 0.9, 0.1) AS tail_ratio
FROM (VALUES (0.01), (-0.04), (0.02), (-0.01), (0.03), (-0.02), (0.005), (0.015)) t(r);

-- fin_theils_u
SELECT fin_theils_u(x, y) AS theils_u
FROM (VALUES ('a', 'u'), ('a', 'u'), ('b', 'v'), ('b', 'v'), ('a', 'v'), ('b', 'u')) t(x, y);

-- fin_to_log_return
SELECT fin_to_log_return(0.05) AS log_return;

-- fin_total_return(r, method)
SELECT fin_total_return(r, 'simple') AS total_return
FROM (VALUES (0.01), (0.02), (-0.01)) t(r);

-- fin_tracking_error
SELECT fin_tracking_error(r, benchmark_r, 252) AS tracking_error
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_treynor_ratio
SELECT fin_treynor_ratio(r, benchmark_r, 0.02, 252) AS treynor
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_trimmed_mean(x, lower_q, upper_q)
SELECT fin_trimmed_mean(x, 0.1, 0.9) AS trimmed_mean
FROM (VALUES (1.0), (2.0), (3.0), (4.0), (100.0)) t(x);

-- fin_ttest_1samp
SELECT fin_ttest_1samp(x, 0.0) AS ttest
FROM (VALUES (0.5), (1.2), (0.8), (1.5), (0.9)) t(x);

-- fin_ttest_2samp
SELECT fin_ttest_2samp(x, y, true) AS ttest
FROM (VALUES (1.0, 2.0), (2.0, 3.0), (3.0, 4.5), (2.5, 3.5)) t(x, y);

-- fin_ulcer_index(r)
SELECT fin_ulcer_index(r ORDER BY ts) AS ulcer_index
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_up_capture
SELECT fin_up_capture(r, benchmark_r) AS up_capture
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, benchmark_r);

-- fin_upside_deviation
SELECT fin_upside_deviation(r, 0.0, 252) AS upside_deviation
FROM (VALUES (0.01), (-0.02), (0.015), (-0.005)) t(r);

-- fin_validate_return(r, max_abs)
SELECT fin_validate_return(0.05) AS ok, fin_validate_return(-1.5) AS below_total_loss;

-- fin_volatility(r, annualization, ddof)
SELECT fin_volatility(r, 252, 1) AS volatility
FROM (VALUES (0.010), (-0.004), (0.006), (0.002), (0.008)) t(r);

-- fin_weighted_mean
SELECT fin_weighted_mean(x, w) AS weighted_mean
FROM (VALUES (1.0, 1.0), (2.0, 2.0), (3.0, 1.0)) t(x, w);

-- fin_weighted_quantile(x, w, q, method)
SELECT fin_weighted_quantile(x, w, 0.5, 'linear') AS weighted_median
FROM (VALUES (1.0, 1.0), (2.0, 2.0), (3.0, 1.0)) t(x, w);

-- fin_weighted_stddev
SELECT fin_weighted_stddev(x, w, 0) AS weighted_stddev
FROM (VALUES (1.0, 1.0), (2.0, 2.0), (3.0, 1.0)) t(x, w);

-- fin_weighted_var
SELECT fin_weighted_var(x, w, 0) AS weighted_variance
FROM (VALUES (1.0, 1.0), (2.0, 2.0), (3.0, 1.0)) t(x, w);

-- fin_welch_ttest
SELECT fin_welch_ttest(x, y) AS welch
FROM (VALUES (1.0, 2.0), (2.0, 3.0), (3.0, 6.5), (2.5, 3.5)) t(x, y);

-- fin_win_rate
SELECT fin_win_rate(r) AS win_rate
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_winsorized_mean(x, lower_q, upper_q)
SELECT fin_winsorized_mean(x, 0.1, 0.9) AS winsorized_mean
FROM (VALUES (1.0), (2.0), (3.0), (4.0), (100.0)) t(x);

-- fin_zscore_last
SELECT fin_zscore_last(x, ts) AS zscore
FROM (VALUES (1, 10.0), (2, 11.0), (3, 9.5), (4, 12.0)) t(ts, x);

-- fin_ztest_mean
SELECT fin_ztest_mean(x, 0.0, 1.0) AS ztest
FROM (VALUES (0.5), (1.2), (0.8), (1.5), (0.9)) t(x);

-- fin_accrued_interest(settlement_date, last_coupon_date, next_coupon_date, coupon_rate, face, day_count)
SELECT fin_accrued_interest(DATE '2026-04-01', DATE '2026-01-01', DATE '2026-07-01', 0.04, 100.0, 'ACT/365F') AS accrued;

-- fin_annuity_payment(rate, periods, present_value, future_value, timing)
SELECT fin_annuity_payment(0.05 / 12, 360.0, 300000.0, 0.0, 'end') AS monthly_payment;

-- fin_bond_convexity(coupon_rate, ytm, maturity, frequency, face)
SELECT fin_bond_convexity(0.05, 0.04, 5.0, 2, 100.0) AS convexity;

-- fin_bond_duration(coupon_rate, ytm, maturity, frequency, face, kind)
SELECT fin_bond_duration(0.05, 0.04, 5.0, 2, 100.0, 'modified') AS modified_duration;

-- fin_bond_price(coupon_rate, ytm, maturity, frequency, face)
SELECT fin_bond_price(0.05, 0.04, 5.0, 2, 100.0) AS price;

-- fin_bond_ytm(price, coupon_rate, maturity, frequency, face)
SELECT fin_bond_ytm(104.49, 0.05, 5.0, 2, 100.0) AS ytm;

-- fin_cashflow_spec
SELECT fin_cashflow_spec(1000.0, DATE '2026-06-30', 'usd') AS cashflow;

-- fin_curve_spec
SELECT fin_curve_spec([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 'zero_rate', 'linear', 'continuous', 'ACT/365F') AS curve;

-- fin_curve_zero_rate(maturities, zero_rates, t)
SELECT fin_curve_zero_rate([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5) AS zero_rate;

-- fin_forward_rate(df1, df2, t1, t2, compounding)
SELECT fin_forward_rate(0.9608, 0.8869, 1.0, 2.0, 'continuous') AS forward_rate;

-- fin_fra_rate(r1, r2, t1, t2)
SELECT fin_fra_rate(0.04, 0.05, 1.0, 2.0) AS forward_rate;

-- fin_future_value(present_value, rate, t, compounding)
SELECT fin_future_value(100.0, 0.05, 2.0, 'annual') AS future_value;

-- fin_interpolate_curve(maturities, values, t)
SELECT fin_interpolate_curve([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5) AS value;

-- fin_irr(cashflows, guess)
SELECT fin_irr([-100.0, 60.0, 60.0]) AS irr;

-- fin_mirr(cashflows, finance_rate, reinvest_rate)
SELECT fin_mirr([-100.0, 60.0, 60.0], 0.1, 0.05) AS mirr;

-- fin_npv(rate, cashflows)
-- fin_npv(cashflows, times, rate, compounding)
SELECT fin_npv(0.1, [-100.0, 60.0, 60.0]) AS npv;

-- fin_present_value(future_value, rate, t, compounding)
SELECT fin_present_value(110.25, 0.05, 2.0, 'annual') AS present_value;

-- fin_rate_from_discount(discount_factor, t, compounding, frequency)
SELECT fin_rate_from_discount(0.9512, 1.0, 'continuous') AS zero_rate;

-- fin_swap_rate(times, discount_factors)
SELECT fin_swap_rate([1.0, 2.0, 3.0], [0.96, 0.92, 0.88]) AS par_rate;

-- fin_validate_curve_spec
SELECT fin_validate_curve_spec(fin_curve_spec([1.0, 0.5], [0.04, 0.05])) AS check;

-- fin_xirr(cashflows, dates, guess)
SELECT fin_xirr([-100.0, 50.0, 60.0], [DATE '2026-01-01', DATE '2026-07-01', DATE '2027-01-01']) AS xirr;

-- fin_yearfrac(start_date, end_date, day_count)
SELECT fin_yearfrac(DATE '2026-01-15', DATE '2026-07-15', '30/360') AS year_fraction;

-- fin_asian_geometric_price(spec)
-- fin_asian_geometric_price(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_asian_geometric_price('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS price;

-- fin_asset_or_nothing_price(spec)
-- fin_asset_or_nothing_price(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_asset_or_nothing_price('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS price;

-- fin_bachelier_greeks(kind, forward, strike, ttm, rate, normal_vol)
SELECT fin_bachelier_greeks('call', 100.0, 100.0, 1.0, 0.05, 5.0) AS greeks;

-- fin_bachelier_implied_vol(kind, price, forward, strike, ttm, rate, guess, tolerance)
SELECT fin_bachelier_implied_vol('call', 1.9, 100.0, 100.0, 1.0, 0.05) AS normal_vol;

-- fin_bachelier_price(kind, forward, strike, ttm, rate, normal_vol)
SELECT fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0) AS price;

-- fin_barrier_price(kind, barrier_type, spot, strike, barrier, ttm, rate, vol)
-- fin_barrier_price(kind, barrier_type, spot, strike, barrier, rebate, ttm, rate, vol, dividend_yield)
SELECT fin_barrier_price('call', 'up-out', 100.0, 100.0, 120.0, 0.0, 1.0, 0.05, 0.2, 0.0) AS price;

-- fin_binomial_price(kind, spot, strike, ttm, rate, vol, dividend_yield, steps, exercise, tree)
SELECT fin_binomial_price('put', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 200, 'american', 'crr') AS price;

-- fin_black76_greeks(kind, forward, strike, ttm, rate, vol)
SELECT fin_black76_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS greeks;

-- fin_black76_implied_vol(kind, price, forward, strike, ttm, rate, guess, tolerance)
SELECT fin_black76_implied_vol('call', 7.58, 100.0, 100.0, 1.0, 0.05) AS vol;

-- fin_black76_price(kind, forward, strike, ttm, rate, vol)
SELECT fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS price;

-- fin_bsm_all(spec)
-- fin_bsm_all(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_all('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS bsm;

-- fin_bsm_charm(spec)
-- fin_bsm_charm(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_charm('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS charm;

-- fin_bsm_color(spec)
-- fin_bsm_color(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_color('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS color;

-- fin_bsm_d1(spec)
-- fin_bsm_d1(spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_d1(100.0, 100.0, 1.0, 0.05, 0.2, 0.0) AS d1;

-- fin_bsm_d2(spec)
-- fin_bsm_d2(spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_d2(100.0, 100.0, 1.0, 0.05, 0.2, 0.0) AS d2;

-- fin_bsm_delta(spec)
-- fin_bsm_delta(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_delta('put', 100.0, 100.0, 1.0, 0.05, 0.2) AS delta;

-- fin_bsm_elasticity(spec)
-- fin_bsm_elasticity(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_elasticity('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS elasticity;

-- fin_bsm_gamma(spec)
-- fin_bsm_gamma(spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_gamma(100.0, 100.0, 1.0, 0.05, 0.2, 0.0) AS gamma;

-- fin_bsm_greeks(spec)
-- fin_bsm_greeks(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_greeks(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2)) AS greeks;

-- fin_bsm_implied_vol(spec, price)
-- fin_bsm_implied_vol(kind, price, spot, strike, ttm, rate, dividend_yield, guess, tolerance, max_iterations)
SELECT fin_bsm_implied_vol('call', 10.4506, 100.0, 100.0, 1.0, 0.05) AS implied_vol;

-- fin_bsm_price(spec)
-- fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.01) AS price;

-- fin_bsm_price_dates(kind, spot, strike, valuation_date, expiry_date, rate, vol, dividend_yield, day_count)
SELECT fin_bsm_price_dates('call', 100.0, 100.0, DATE '2026-01-02', DATE '2026-12-18', 0.05, 0.2) AS price;

-- fin_bsm_prob_itm(spec)
-- fin_bsm_prob_itm(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_prob_itm('call', 100.0, 110.0, 0.5, 0.05, 0.25) AS prob_itm;

-- fin_bsm_prob_touch(spec)
-- fin_bsm_prob_touch(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_prob_touch('call', 100.0, 110.0, 0.5, 0.05, 0.25) AS prob_touch;

-- fin_bsm_rho(spec, unit)
-- fin_bsm_rho(kind, spot, strike, ttm, rate, vol, dividend_yield, unit)
SELECT fin_bsm_rho('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 'market') AS rho_per_point;

-- fin_bsm_speed(spec)
-- fin_bsm_speed(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_speed('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS speed;

-- fin_bsm_theta(spec, unit)
-- fin_bsm_theta(kind, spot, strike, ttm, rate, vol, dividend_yield, unit)
SELECT fin_bsm_theta('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 'day') AS theta_per_day;

-- fin_bsm_ultima(spec)
-- fin_bsm_ultima(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_ultima('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS ultima;

-- fin_bsm_vanna(spec)
-- fin_bsm_vanna(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_vanna('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS vanna;

-- fin_bsm_vega(spec, unit)
-- fin_bsm_vega(kind, spot, strike, ttm, rate, vol, dividend_yield, unit)
SELECT fin_bsm_vega('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 'market') AS vega_per_point;

-- fin_bsm_vomma(spec)
-- fin_bsm_vomma(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_vomma('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS vomma;

-- fin_bsm_zomma(spec)
-- fin_bsm_zomma(kind, spot, strike, ttm, rate, vol, dividend_yield)
SELECT fin_bsm_zomma('call', 100.0, 100.0, 1.0, 0.05, 0.2) AS zomma;

-- fin_digital_price(spec, payout)
-- fin_digital_price(kind, spot, strike, ttm, rate, vol, dividend_yield, payout)
SELECT fin_digital_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 10.0) AS price;

-- fin_forward_price(spot, ttm, rate, dividend_yield)
SELECT fin_forward_price(100.0, 1.0, 0.05, 0.02) AS forward;

-- fin_option_market_spec
SELECT fin_option_market_spec('call', 100.0, 100.0, DATE '2026-12-18', DATE '2026-01-02', 0.05, 0.2) AS spec;

-- fin_option_payoff(kind, spot, strike)
SELECT fin_option_payoff('put', 95.0, 100.0) AS payoff;

-- fin_option_spec
SELECT fin_bsm_price(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2, dividend_yield := 0.01)) AS price;

-- fin_option_spec_dates
SELECT fin_option_spec_dates('put', 100.0, 95.0, DATE '2026-01-02', DATE '2026-07-02', 0.05, 0.25) AS spec;

-- fin_parse_option_kind(kind)
SELECT fin_parse_option_kind('C') AS kind;

-- fin_put_call_parity(call_price, put_price, spot, strike, ttm, rate, dividend_yield)
SELECT fin_put_call_parity(10.4506, 5.5735, 100.0, 100.0, 1.0, 0.05, 0.0) AS parity_gap;

-- fin_sabr_vol(forward, strike, ttm, alpha, beta, rho, nu, shift)
SELECT fin_sabr_vol(100.0, 110.0, 1.0, 2.0, 0.5, -0.2, 0.4) AS implied_vol;

-- fin_svi_total_variance(log_moneyness, a, b, rho, m, sigma)
SELECT fin_svi_total_variance(0.1, 0.02, 0.1, -0.3, 0.0, 0.2) AS total_variance;

-- fin_svi_vol(log_moneyness, ttm, a, b, rho, m, sigma)
SELECT fin_svi_vol(0.1, 0.5, 0.02, 0.1, -0.3, 0.0, 0.2) AS implied_vol;

-- fin_validate_option_spec
SELECT fin_validate_option_spec(fin_option_spec('call', 100.0, 100.0, 0.0, 0.05, 0.2)) AS check;

-- fin_ad_line(high, low, close, volume)
SELECT fin_ad_line(high, low, close, volume) AS ad_line
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low, 1000 + 10 * (i % 9) AS volume FROM range(60) t(i));

-- fin_adosc(high, low, close, volume, fast_period, slow_period)
SELECT fin_adosc(high, low, close, volume, 3, 10 ORDER BY ts) AS adosc
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low, 1000 + 10 * (i % 9) AS volume FROM range(60) t(i));

-- fin_adx(high, low, close, period)
SELECT fin_adx(high, low, close, 14 ORDER BY ts) AS adx
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_adxr(high, low, close, period)
SELECT fin_adxr(high, low, close, 14 ORDER BY ts) AS adxr
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_amihud_illiquidity(ret, dollar_volume)
SELECT fin_amihud_illiquidity(ret, dollar_volume) AS illiquidity
FROM (VALUES (0.010, 1.0e6), (-0.020, 2.5e6), (0.005, 0.8e6)) t(ret, dollar_volume);

-- fin_apo(close, fast_period, slow_period, ma_type)
SELECT fin_apo(close, 12, 26, 'ema' ORDER BY ts) AS apo
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_aroon(high, low, period)
SELECT fin_aroon(high, low, 14 ORDER BY ts) AS aroon
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_aroonosc(high, low, period)
SELECT fin_aroonosc(high, low, 14 ORDER BY ts) AS aroon_oscillator
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_atr(high, low, close, period)
SELECT fin_atr(high, low, close, 14 ORDER BY ts) AS atr
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_avg_price(open, high, low, close)
SELECT fin_avg_price(100.0, 102.0, 99.0, 101.0) AS avg_price;

-- fin_bbands(close, period, k, ddof)
SELECT fin_bbands(close, 20, 2.0, 0 ORDER BY ts) AS bands
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_bop(open, high, low, close)
SELECT fin_bop(100.0, 102.0, 99.0, 101.0) AS balance_of_power;

-- fin_cci(high, low, close, period, constant)
SELECT fin_cci(high, low, close, 20, 0.015 ORDER BY ts) AS cci
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_cmo(close, period)
SELECT fin_cmo(close, 14 ORDER BY ts) AS cmo
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_dema(close, period)
SELECT fin_dema(close, 20 ORDER BY ts) AS dema
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_donchian(high, low, period)
SELECT fin_donchian(high, low, 20 ORDER BY ts) AS channel
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_dx(high, low, close, period)
SELECT fin_dx(high, low, close, 14 ORDER BY ts) AS dx
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_hma(close, period)
SELECT fin_hma(close, 16 ORDER BY ts) AS hma
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_kama(close, period, fast_period, slow_period)
SELECT fin_kama(close, 10, 2, 30 ORDER BY ts) AS kama
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_keltner(high, low, close, period, atr_period, multiplier)
SELECT fin_keltner(high, low, close, 20, 10, 2.0 ORDER BY ts) AS channel
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_kyle_lambda(price_change, signed_volume)
SELECT fin_kyle_lambda(price_change, signed_volume) AS kyle_lambda
FROM (VALUES (0.02, 100.0), (-0.01, -60.0), (0.03, 140.0), (-0.02, -90.0)) t(price_change, signed_volume);

-- fin_linearreg(close, period)
SELECT fin_linearreg(close, 14 ORDER BY ts) AS linearreg
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_linearreg_intercept(close, period)
SELECT fin_linearreg_intercept(close, 14 ORDER BY ts) AS intercept
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_linearreg_slope(close, period)
SELECT fin_linearreg_slope(close, 14 ORDER BY ts) AS slope
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_macd(close, fast_period, slow_period, signal_period)
SELECT fin_macd(close, 12, 26, 9 ORDER BY ts) AS macd
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_median_price(high, low)
SELECT fin_median_price(102.0, 99.0) AS median_price;

-- fin_mfi(high, low, close, volume, period)
SELECT fin_mfi(high, low, close, volume, 14 ORDER BY ts) AS mfi
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low, 1000 + 10 * (i % 9) AS volume FROM range(60) t(i));

-- fin_microprice(bid, bid_size, ask, ask_size)
SELECT fin_microprice(99.98, 500.0, 100.02, 300.0) AS microprice;

-- fin_mid(bid, ask)
SELECT fin_mid(99.98, 100.02) AS mid;

-- fin_minus_di(high, low, close, period)
SELECT fin_minus_di(high, low, close, 14 ORDER BY ts) AS minus_di
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_minus_dm(high, low, period)
SELECT fin_minus_dm(high, low, 14 ORDER BY ts) AS minus_dm
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_mom(close, period)
SELECT fin_mom(close, 10 ORDER BY ts) AS momentum
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_natr(high, low, close, period)
SELECT fin_natr(high, low, close, 14 ORDER BY ts) AS natr
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_obv(close, volume)
SELECT fin_obv(close, volume ORDER BY ts) AS obv
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low, 1000 + 10 * (i % 9) AS volume FROM range(60) t(i));

-- fin_ohlc
SELECT fin_ohlc(price, ts) AS bar
FROM (VALUES (TIMESTAMP '2026-01-02 09:30:00', 100.0), (TIMESTAMP '2026-01-02 09:30:20', 101.5), (TIMESTAMP '2026-01-02 09:30:40', 99.5), (TIMESTAMP '2026-01-02 09:30:59', 100.5)) t(ts, price);

-- fin_ohlcv
SELECT fin_ohlcv(price, volume, ts) AS bar
FROM (VALUES (TIMESTAMP '2026-01-02 09:30:00', 100.0, 200.0), (TIMESTAMP '2026-01-02 09:30:20', 101.5, 100.0), (TIMESTAMP '2026-01-02 09:30:59', 100.5, 300.0)) t(ts, price, volume);

-- fin_order_imbalance(bid_size, ask_size)
SELECT fin_order_imbalance(500.0, 300.0) AS imbalance;

-- fin_plus_di(high, low, close, period)
SELECT fin_plus_di(high, low, close, 14 ORDER BY ts) AS plus_di
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_plus_dm(high, low, period)
SELECT fin_plus_dm(high, low, 14 ORDER BY ts) AS plus_dm
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_ppo(close, fast_period, slow_period, ma_type)
SELECT fin_ppo(close, 12, 26, 'sma' ORDER BY ts) AS ppo
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_queue_imbalance(bid_size, ask_size)
SELECT fin_queue_imbalance(500.0, 300.0) AS imbalance;

-- fin_roc(close, period)
SELECT fin_roc(close, 10 ORDER BY ts) AS roc_percent
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_rocp(close, period)
SELECT fin_rocp(close, 10 ORDER BY ts) AS roc_fraction
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_rocr(close, period)
SELECT fin_rocr(close, 10 ORDER BY ts) AS roc_ratio
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_rocr100(close, period)
SELECT fin_rocr100(close, 10 ORDER BY ts) AS roc_ratio_percent
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_roll_spread(price)
SELECT fin_roll_spread(price ORDER BY ts) AS roll_spread
FROM (VALUES (1, 100.00), (2, 100.02), (3, 100.00), (4, 100.03), (5, 100.01), (6, 100.03), (7, 100.00)) t(ts, price);

-- fin_rsi(close, period)
SELECT fin_rsi(close, 14 ORDER BY ts) AS rsi
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_sar(high, low, acceleration, maximum)
SELECT fin_sar(high, low, 0.02, 0.2 ORDER BY ts) AS sar
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_sarext(high, low, start_value, offset_on_reverse, af_init_long, af_long, af_max_long, af_init_short, af_short, af_max_short)
SELECT fin_sarext(high, low, 0, 0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2 ORDER BY ts) AS sar
FROM (SELECT i AS ts, 101 + 3 * sin(i / 4) + i / 10 AS high, 99 + 3 * sin(i / 4) + i / 10 AS low FROM range(60) t(i));

-- fin_sma(close, period)
SELECT fin_sma(close, 20 ORDER BY ts) AS sma
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_spread(bid, ask)
SELECT fin_spread(99.98, 100.02) AS spread;

-- fin_spread_bps(bid, ask)
SELECT fin_spread_bps(99.98, 100.02) AS spread_bps;

-- fin_stddev(close, period, ddof)
SELECT fin_stddev(close, 20, 0 ORDER BY ts) AS stddev
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_stoch(high, low, close, k_period, d_period, smooth_period)
SELECT fin_stoch(high, low, close, 14, 3, 3 ORDER BY ts) AS stoch
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_stochrsi(close, period, k_period, d_period)
SELECT fin_stochrsi(close, 14, 3, 3 ORDER BY ts) AS stochrsi
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_t3(close, period, vfactor)
SELECT fin_t3(close, 5, 0.7 ORDER BY ts) AS t3
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_tema(close, period)
SELECT fin_tema(close, 10 ORDER BY ts) AS tema
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_trade_sign(price, bid, ask, prev_price, method)
SELECT fin_trade_sign(100.03, 99.98, 100.02, 100.01, 'lee_ready') AS sign;

-- fin_trima(close, period)
SELECT fin_trima(close, 20 ORDER BY ts) AS trima
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_trix(close, period)
SELECT fin_trix(close, 10 ORDER BY ts) AS trix
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_true_range(high, low, close)
SELECT fin_true_range(high, low, close ORDER BY ts) AS true_range
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_tsf(close, period)
SELECT fin_tsf(close, 14 ORDER BY ts) AS forecast
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_twap(price, ts)
SELECT fin_twap(price, ts ORDER BY ts) AS twap
FROM (VALUES (TIMESTAMP '2026-01-02 09:30:00', 100.0), (TIMESTAMP '2026-01-02 09:30:40', 101.0), (TIMESTAMP '2026-01-02 09:31:00', 100.5)) t(ts, price);

-- fin_typ_price(high, low, close)
SELECT fin_typ_price(102.0, 99.0, 101.0) AS typical_price;

-- fin_ultosc(high, low, close, short_period, medium_period, long_period)
SELECT fin_ultosc(high, low, close, 7, 14, 28 ORDER BY ts) AS ultosc
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_var_indicator(close, period, ddof)
SELECT fin_var_indicator(close, 20, 0 ORDER BY ts) AS variance
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_volume_profile(price, volume, bins)
SELECT fin_volume_profile(price, volume, 3) AS profile
FROM (VALUES (100.0, 200.0), (100.5, 100.0), (101.0, 300.0), (101.5, 50.0), (102.0, 150.0)) t(price, volume);

-- fin_vpin(signed_volume, volume, buckets, bucket_volume)
SELECT fin_vpin(signed_volume, volume, 5, 100.0 ORDER BY ts) AS vpin
FROM (SELECT i AS ts, 50.0 AS volume, CASE WHEN i % 3 = 0 THEN -30.0 ELSE 20.0 END AS signed_volume FROM range(20) t(i));

-- fin_vwap(price, volume)
SELECT fin_vwap(price, volume) AS vwap
FROM (VALUES (100.0, 200.0), (101.0, 100.0), (100.5, 300.0)) t(price, volume);

-- fin_weighted_close(high, low, close)
SELECT fin_weighted_close(102.0, 99.0, 101.0) AS weighted_close;

-- fin_willr(high, low, close, period)
SELECT fin_willr(high, low, close, 14 ORDER BY ts) AS williams_r
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close, close + 1.5 AS high, close - 0.5 AS low FROM range(60) t(i));

-- fin_wma(close, period)
SELECT fin_wma(close, 20 ORDER BY ts) AS wma
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_black_litterman_returns
SELECT fin_black_litterman_returns([0.6, 0.4], [[0.04, 0.006], [0.006, 0.09]], [[1.0, -1.0]], [0.02], 0.05, NULL, 2.5) AS posterior_returns;

-- fin_component_risk
SELECT fin_component_risk([0.7, 0.3], [[0.04, 0.006], [0.006, 0.09]]) AS component_vol;

-- fin_corr_matrix(ts, asset, r)
SELECT fin_corr_matrix(ts, asset, r) AS corr
FROM (VALUES (1, 'AAA', 0.010), (1, 'BBB', 0.004), (2, 'AAA', -0.020), (2, 'BBB', -0.006), (3, 'AAA', 0.015), (3, 'BBB', 0.009), (4, 'AAA', 0.003), (4, 'BBB', -0.002)) t(ts, asset, r);

-- fin_cov_matrix(ts, asset, r)
SELECT fin_cov_matrix(ts, asset, r) AS cov
FROM (VALUES (1, 'AAA', 0.010), (1, 'BBB', 0.004), (2, 'AAA', -0.020), (2, 'BBB', -0.006), (3, 'AAA', 0.015), (3, 'BBB', 0.009), (4, 'AAA', 0.003), (4, 'BBB', -0.002)) t(ts, asset, r);

-- fin_curve_discount_factor(maturities, zero_rates, t)
SELECT fin_curve_discount_factor([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5) AS discount_factor;

-- fin_discount_factor(rate, t, compounding, frequency)
SELECT fin_discount_factor(0.05, 2.0, 'semiannual', 2) AS discount_factor;

-- fin_equal_weights(n)
SELECT fin_equal_weights(4) AS weights;

-- fin_factor_alpha
SELECT fin_factor_alpha(r, factor_r, 0.02, 252) AS alpha
FROM (VALUES (0.010, 0.008), (-0.020, -0.015), (0.015, 0.010), (0.004, 0.002)) t(r, factor_r);

-- fin_factor_ic
SELECT fin_factor_ic(factor, forward_return, 'spearman') AS ic
FROM (VALUES (1.0, 0.01), (2.0, 0.00), (3.0, 0.02), (4.0, 0.03), (5.0, 0.025)) t(factor, forward_return);

-- fin_factor_turnover
SELECT fin_factor_turnover(ts, asset, factor, 1) AS turnover
FROM (VALUES (1, 'A', 1.0), (1, 'B', 2.0), (1, 'C', 3.0), (2, 'A', 1.0), (2, 'B', 3.0), (2, 'C', 2.0), (3, 'A', 2.0), (3, 'B', 3.0), (3, 'C', 1.0)) t(ts, asset, factor);

-- fin_inverse_vol_weights(vols)
SELECT fin_inverse_vol_weights([0.10, 0.20, 0.40]) AS weights;

-- fin_marginal_risk
SELECT fin_marginal_risk([0.7, 0.3], [[0.04, 0.006], [0.006, 0.09]]) AS cov_times_weights;

-- fin_matrix_cholesky(matrix)
SELECT fin_matrix_cholesky([[4.0, 2.0], [2.0, 3.0]]) AS lower;

-- fin_matrix_is_psd(matrix, tolerance)
SELECT fin_matrix_is_psd([[1.0, 0.9], [0.9, 1.0]]) AS psd, fin_matrix_is_psd([[1.0, 2.0], [2.0, 1.0]]) AS not_psd;

-- fin_matrix_mul(a, b)
SELECT fin_matrix_mul([[1.0, 2.0], [3.0, 4.0]], [[5.0], [6.0]]) AS product;

-- fin_matrix_shape(matrix)
SELECT fin_matrix_shape([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]) AS shape;

-- fin_matrix_transpose(matrix)
SELECT fin_matrix_transpose([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]) AS transposed;

-- fin_matrix_vecmul(matrix, vector)
SELECT fin_matrix_vecmul([[1.0, 2.0], [3.0, 4.0]], [1.0, 0.5]) AS product;

-- fin_max_sharpe_weights
SELECT fin_max_sharpe_weights([0.08, 0.12], [[0.04, 0.006], [0.006, 0.09]], 0.02, true) AS weights;

-- fin_min_variance_weights
SELECT fin_min_variance_weights([[0.04, 0.006], [0.006, 0.09]], true) AS weights;

-- fin_newey_west_tstat
SELECT fin_newey_west_tstat(y, x, ts, 1) AS hac_tstat
FROM (VALUES (1, 0.9, 1.0), (2, 2.3, 2.0), (3, 2.8, 3.0), (4, 4.4, 4.0), (5, 4.9, 5.0), (6, 6.2, 6.0)) t(ts, y, x);

-- fin_ols(y, x)
SELECT fin_ols(y, [x1, x2]) AS fit
FROM (VALUES (3.1, 1.0, 0.0), (4.9, 2.0, 0.5), (7.2, 3.0, 0.8), (8.8, 4.0, 1.5), (11.1, 5.0, 1.9)) t(y, x1, x2);

-- fin_ols_no_intercept(y, x)
SELECT fin_ols_no_intercept(y, [x]) AS fit
FROM (VALUES (2.1, 1.0), (3.9, 2.0), (6.2, 3.0)) t(y, x);

-- fin_portfolio_expected_return(weights, expected_returns)
SELECT fin_portfolio_expected_return([0.6, 0.4], [0.08, 0.12]) AS expected_return;

-- fin_portfolio_return(weights, returns)
SELECT fin_portfolio_return([0.6, 0.4], [0.010, -0.005]) AS portfolio_return;

-- fin_portfolio_sharpe(weights, mu, cov_matrix, risk_free)
SELECT fin_portfolio_sharpe([0.6, 0.4], [0.08, 0.12], [[0.04, 0.006], [0.006, 0.09]], 0.02) AS sharpe;

-- fin_portfolio_spec
SELECT fin_portfolio_spec(['AAA', 'BBB'], [0.6, 0.4], 'usd') AS spec;

-- fin_portfolio_variance(weights, cov_matrix)
SELECT fin_portfolio_variance([0.6, 0.4], [[0.04, 0.006], [0.006, 0.09]]) AS variance;

-- fin_portfolio_vector
SELECT fin_portfolio_vector([0.6, 0.4], ['AAA', 'BBB']) AS portfolio;

-- fin_portfolio_vol(weights, cov_matrix)
SELECT fin_portfolio_vol([0.6, 0.4], [[0.04, 0.006], [0.006, 0.09]]) AS volatility;

-- fin_profit_factor
SELECT fin_profit_factor(r) AS profit_factor
FROM (VALUES (0.02), (-0.01), (0.03), (-0.015)) t(r);

-- fin_recovery_factor
SELECT fin_recovery_factor(r, ts) AS recovery_factor
FROM (VALUES (1, 0.05), (2, -0.10), (3, 0.02), (4, -0.03), (5, 0.08)) t(ts, r);

-- fin_risk_contribution
SELECT fin_risk_contribution([0.7, 0.3], [[0.04, 0.006], [0.006, 0.09]]) AS risk_shares;

-- fin_risk_parity_weights
SELECT fin_risk_parity_weights([[0.04, 0.006], [0.006, 0.09]]) AS weights;

-- fin_turnover(old_weights, new_weights)
SELECT fin_turnover([0.5, 0.3, 0.2], [0.4, 0.4, 0.2]) AS turnover;

-- fin_vector_add(a, b)
SELECT fin_vector_add([1.0, 2.0], [3.0, 4.0]) AS total;

-- fin_vector_mean(x)
SELECT fin_vector_mean([1.0, 2.0, 6.0]) AS mean;

-- fin_vector_normalize_sum(x)
SELECT fin_vector_normalize_sum([2.0, 1.0, 1.0]) AS weights;

-- fin_vector_scale(x, factor)
SELECT fin_vector_scale([1.0, 2.0], 0.5) AS scaled;

-- fin_vector_sub(a, b)
SELECT fin_vector_sub([3.0, 4.0], [1.0, 2.0]) AS difference;

-- fin_vector_sum(x)
SELECT fin_vector_sum([1.0, 2.0, 3.0]) AS total;

-- fin_bar_spec
SELECT fin_bar_spec('volume', 1000.0) AS spec;

-- fin_business_days_between(start_date, end_date, calendar)
SELECT fin_business_days_between(DATE '2026-12-21', DATE '2026-12-28', 'NYSE') AS business_days;

-- fin_calendar_spec
SELECT fin_calendar_spec('NYSE', 'America/New_York', TIME '09:30:00', TIME '16:00:00') AS spec;

-- fin_is_business_day(date, calendar)
SELECT fin_is_business_day(DATE '2026-12-25', 'NYSE') AS is_business_day;

-- fin_is_finite(x)
SELECT fin_is_finite('inf'::DOUBLE) AS finite;

-- fin_is_price(x, allow_zero)
SELECT fin_is_price(0.0) AS zero_ok, fin_is_price(0.0, false) AS strictly_positive;

-- fin_is_rate(x, allow_negative)
SELECT fin_is_rate(-0.005) AS negative_ok, fin_is_rate(-0.005, false) AS non_negative;

-- fin_is_regular_session(ts, calendar, timezone)
SELECT fin_is_regular_session(TIMESTAMP '2026-11-27 14:00:00', 'NYSE') AS in_session;

-- fin_is_vol(x)
SELECT fin_is_vol(0.2) AS valid_vol;

-- fin_next_business_day(date, days:BIGINT)
-- fin_next_business_day(date, calendar, days)
SELECT fin_next_business_day(DATE '2026-12-24', 'NYSE', 1) AS next_day;

-- fin_normalize_currency(code)
SELECT fin_normalize_currency(' usd ') AS currency;

-- fin_optimizer_spec
SELECT fin_optimizer_spec('min_variance', weight_max := 0.6) AS spec;

-- fin_parse_compounding(compounding)
SELECT fin_parse_compounding('Semi-Annually') AS compounding;

-- fin_parse_day_count(day_count)
SELECT fin_parse_day_count('actual/365 fixed') AS day_count;

-- fin_parse_exercise_style(exercise)
SELECT fin_parse_exercise_style('American') AS exercise;

-- fin_prev_business_day(date, days:BIGINT)
-- fin_prev_business_day(date, calendar, days)
SELECT fin_prev_business_day(DATE '2026-01-05', 'NYSE', 2) AS previous_day;

-- fin_rate_spec
SELECT fin_rate_spec(0.05, 'semiannual', 2, 'ACT/360') AS spec;

-- fin_risk_spec
SELECT fin_risk_spec(252, 0.02, 0.99) AS spec;

-- fin_session_date(ts, calendar, timezone)
SELECT fin_session_date(TIMESTAMP '2026-05-06 23:30:00', 'NYSE', 'UTC') AS session_date;

-- fin_ts_grid_spec
SELECT fin_ts_grid_spec(TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 16:00:00', INTERVAL '5 minutes') AS spec;

-- fin_typeof
SELECT fin_typeof(1.5) AS type_name;

-- fin_validate_ohlc(open, high, low, close)
SELECT fin_validate_ohlc(100.0, 101.0, 99.0, 100.5) AS valid_bar, fin_validate_ohlc(100.0, 99.0, 101.0, 100.5) AS invalid_bar;

-- fin_validate_rate_spec
SELECT fin_validate_rate_spec(fin_rate_spec(0.05)) AS check;

-- fin_var_spec
SELECT fin_var_spec(0.99, 'parametric') AS spec;

-- fin_bootstrap_curve(table_name, type_col, maturity_col, rate_col, compounding)
WITH quotes AS (SELECT * FROM (VALUES ('deposit', 0.25, 0.040, NULL), ('fra', 0.75, 0.042, 0.25), ('swap', 2.0, 0.045, NULL)) t(kind, maturity, rate, start_time))
SELECT * FROM fin_bootstrap_curve('quotes', 'kind', 'maturity', 'rate', 'continuous', start_col := 'start_time', fixed_frequency := 2);

-- fin_calendar(calendar, start_date, end_date)
SELECT * FROM fin_calendar('NYSE', DATE '2026-12-23', DATE '2026-12-28');

-- fin_changes_to_grid(table_name, ts_col, value_col, start_ts, end_ts, step, method, staleness)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_changes_to_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute');

-- fin_curve_bootstrap(table_name, type_col, maturity_col, rate_col, compounding)
WITH quotes AS (SELECT * FROM (VALUES ('deposit', 0.5, 0.040), ('swap', 1.0, 0.042), ('swap', 2.0, 0.045)) t(kind, maturity, rate))
SELECT * FROM fin_curve_bootstrap('quotes', 'kind', 'maturity', 'rate', fixed_frequency := 2);

-- fin_delta_to_grid(table_name, ts_col, value_col, start_ts, end_ts, step, method, staleness)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_delta_to_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute');

-- fin_dollar_bars(table_name, ts_col, price_col, volume_col, threshold)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_dollar_bars('ticks', 'ts', 'price', 'volume', 40000.0);

-- fin_efficient_frontier(mu, cov_matrix, points, allow_short)
SELECT * FROM fin_efficient_frontier([0.08, 0.12], [[0.04, 0.006], [0.006, 0.09]], 5, false);

-- fin_factor_report(table_name, date_col, asset_col, factor_col, return_col, buckets)
WITH panel AS (SELECT d, asset, (asset * 7 + d * 3) % 10 AS factor, ((asset * 7 + d * 3) % 10) * 0.002 + ((asset + d) % 3) * 0.001 AS fwd FROM range(1, 5) a(asset), range(1, 4) b(d))
SELECT * FROM fin_factor_report('panel', 'd', 'asset', 'factor', 'fwd', 2);

-- fin_fama_macbeth(table_name, date_col, asset_col, y_col, x_cols, lags)
WITH panel AS (SELECT d, asset, (asset * 7 + d * 3) % 10 AS factor, ((asset * 7 + d * 3) % 10) * 0.002 + ((asset + d) % 3) * 0.001 AS fwd FROM range(1, 6) a(asset), range(1, 5) b(d))
SELECT * FROM fin_fama_macbeth('panel', 'd', 'asset', 'fwd', ['factor']);

-- fin_garch_fit(table_name, return_col, order_col, p, q, distribution)
WITH returns AS (SELECT i AS t, 0.01 * sin(i * 1.7) * (1 + (i % 7) / 3) AS r FROM range(200) t(i))
SELECT * FROM fin_garch_fit('returns', 'r', 't', 1, 1, 'normal');

-- fin_hrp_weights(cov_matrix, labels, linkage)
SELECT * FROM fin_hrp_weights([[0.04, 0.006, 0.01], [0.006, 0.09, 0.02], [0.01, 0.02, 0.0625]], ['AAA', 'BBB', 'CCC'], 'single');

-- fin_imbalance_bars(table_name, ts_col, price_col, volume_col, threshold, method)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_imbalance_bars('ticks', 'ts', 'price', 'volume', 300.0, 'tick_rule');

-- fin_last_to_grid(table_name, ts_col, value_col, start_ts, end_ts, step, method, staleness)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_last_to_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute');

-- fin_normalize_ohlcv(table_name, ts_col, open_col, high_col, low_col, close_col, volume_col, asset_col)
WITH bars AS (SELECT * FROM (VALUES (TIMESTAMP '2026-01-02 09:30:00', 'AAA', 100, 101, 99, 100.5, 1200)) t(bar_time, symbol, o, h, l, c, v))
SELECT * FROM fin_normalize_ohlcv('bars', 'bar_time', 'o', 'h', 'l', 'c', 'v', 'symbol');

-- fin_normalize_option_chain(table_name, kind_col, underlying_price_col, strike_col, expiry_col, valuation_date_col, rate_col, vol_col, dividend_yield_col)
WITH quotes AS (SELECT * FROM (VALUES ('C', 100.0, 105.0, DATE '2026-12-18', DATE '2026-06-18', 0.05, 0.22, 0.01)) t(cp, underlying_px, strike_px, expiry_dt, valuation_dt, zero_rate, iv, q))
SELECT * FROM fin_normalize_option_chain('quotes', 'cp', 'underlying_px', 'strike_px', 'expiry_dt', 'valuation_dt', 'zero_rate', 'iv', 'q');

-- fin_normalize_returns(table_name, date_col, asset_col, return_col)
WITH returns AS (SELECT * FROM (VALUES (DATE '2026-01-02', 'AAA', 0.010), (DATE '2026-01-05', 'AAA', -0.004)) t(d, symbol, ret))
SELECT * FROM fin_normalize_returns('returns', 'd', 'symbol', 'ret');

-- fin_option_chain(table_name, kind_col, spot_col, strike_col, ttm_col, rate_col, vol_col, dividend_yield_col)
WITH chain AS (SELECT * FROM (VALUES ('call', 100.0, 95.0, 0.5, 0.05, 0.2), ('put', 100.0, 105.0, 0.5, 0.05, 0.25)) t(kind, spot, strike, ttm, rate, vol))
SELECT * FROM fin_option_chain('chain', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol');

-- fin_portfolio_optimize(mu, cov_matrix, objective, risk_free, long_only, min_weight, max_weight, target_return, target_vol, risk_aversion)
SELECT * FROM fin_portfolio_optimize([0.08, 0.12, 0.10], [[0.04, 0.006, 0.01], [0.006, 0.09, 0.02], [0.01, 0.02, 0.0625]], 'max_sharpe', 0.02, true, 0.0, 0.6);

-- fin_portfolio_optimize_table(table_name, asset_col, date_col, return_col, objective, risk_free, long_only, min_weight, max_weight, target_return, target_vol, risk_aversion)
WITH returns AS (SELECT d, asset, 0.001 * asset + 0.01 * sin(d * asset) AS r FROM range(1, 4) a(asset), range(20) b(d))
SELECT * FROM fin_portfolio_optimize_table('returns', 'asset', 'd', 'r', 'min_variance');

-- fin_portfolio_return_table(table_name, asset_col, weight_col, return_col, date_col)
WITH holdings AS (SELECT * FROM (VALUES (DATE '2026-01-02', 'AAA', 0.6, 0.010), (DATE '2026-01-02', 'BBB', 0.4, -0.005), (DATE '2026-01-05', 'AAA', 0.6, 0.002), (DATE '2026-01-05', 'BBB', 0.4, 0.004)) t(d, asset, weight, ret))
SELECT * FROM fin_portfolio_return_table('holdings', 'asset', 'weight', 'ret', 'd');

-- fin_portfolio_variance_table(weights_table, asset_col, weight_col, covariance_table, asset_i_col, asset_j_col, covariance_col)
WITH weights AS (SELECT * FROM (VALUES ('AAA', 0.6), ('BBB', 0.4)) t(asset, weight)), cov AS (SELECT * FROM (VALUES ('AAA', 'AAA', 0.04), ('AAA', 'BBB', 0.006), ('BBB', 'BBB', 0.09)) t(asset_i, asset_j, covariance))
SELECT * FROM fin_portfolio_variance_table('weights', 'asset', 'weight', 'cov', 'asset_i', 'asset_j', 'covariance');

-- fin_predict_linear_to_grid(table_name, ts_col, value_col, start_ts, end_ts, step, lookback, horizon)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_predict_linear_to_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute', INTERVAL '2 minutes', INTERVAL '1 minute');

-- fin_rate_to_grid(table_name, ts_col, value_col, start_ts, end_ts, step, method, staleness)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_rate_to_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute');

-- fin_rebalance_trades(current_table, target_table, price_table, portfolio_value)
WITH current_w AS (SELECT * FROM (VALUES ('AAA', 0.7), ('BBB', 0.3)) t(asset, weight)), target_w AS (SELECT * FROM (VALUES ('AAA', 0.5), ('BBB', 0.5)) t(asset, weight)), prices AS (SELECT * FROM (VALUES ('AAA', 50.0), ('BBB', 20.0)) t(asset, price))
SELECT * FROM fin_rebalance_trades('current_w', 'target_w', 'prices', 100000.0);

-- fin_resample_grid(table_name, ts_col, value_col, start_ts, end_ts, step, method, staleness)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_resample_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute', 'last', INTERVAL '30 seconds');

-- fin_resets_to_grid(table_name, ts_col, value_col, start_ts, end_ts, step, method, staleness)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_resets_to_grid('ticks', 'ts', 'price', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute');

-- fin_schema_template(kind)
SELECT * FROM fin_schema_template('ohlcv');

-- fin_tick_bars(table_name, ts_col, price_col, threshold)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_tick_bars('ticks', 'ts', 'price', 4, volume_col := 'volume');

-- fin_validate_schema(table_name, kind)
WITH returns AS (SELECT DATE '2026-01-02' AS date, 'AAA' AS asset_id, 0.01 AS return_decimal)
SELECT * FROM fin_validate_schema('returns', 'returns');

-- fin_volume_bars(table_name, ts_col, price_col, volume_col, threshold)
WITH ticks AS (SELECT TIMESTAMP '2026-01-02 09:30:00' + i * INTERVAL '20 seconds' AS ts, 100 + (i % 5) * 0.1 AS price, 100.0 + 50 * (i % 3) AS volume FROM range(12) t(i))
SELECT * FROM fin_volume_bars('ticks', 'ts', 'price', 'volume', 500.0);

-- fin_adf
SELECT fin_adf(x, ts, 1, 'c') AS adf
FROM (SELECT i AS ts, sin(i * 1.7) + 0.3 * cos(i * 0.9) AS x FROM range(40) t(i));

-- fin_autocorr
SELECT fin_autocorr(x, ts, 1) AS lag1_autocorr
FROM (SELECT i AS ts, sin(i / 3) AS x FROM range(30) t(i));

-- fin_bipower_variation(log_r, annualization)
SELECT fin_bipower_variation(log_r, 252 ORDER BY ts) AS bipower_variation
FROM (VALUES (1, 0.001), (2, -0.002), (3, 0.0015), (4, -0.0005)) t(ts, log_r);

-- fin_cagr
SELECT fin_cagr(r, 12) AS cagr
FROM (VALUES (0.01), (0.02), (-0.01), (0.015)) t(r);

-- fin_changes
SELECT fin_changes(x, ts) AS changes
FROM (VALUES (1, 1.0), (2, 1.0), (3, 2.0), (4, 2.0), (5, 1.0)) t(ts, x);

-- fin_crosscorr
SELECT fin_crosscorr(x, y, ts, 1) AS lagged_corr
FROM (SELECT i AS ts, sin(i / 3) AS x, sin((i - 1) / 3) AS y FROM range(30) t(i));

-- fin_delta
SELECT fin_delta(x, ts) AS delta
FROM (VALUES (1, 10.0), (2, 12.0), (3, 11.5)) t(ts, x);

-- fin_dot(a, b)
SELECT fin_dot([1.0, 2.0, 3.0], [4.0, 5.0, 6.0]) AS dot;

-- fin_dv01(coupon_rate, ytm, maturity, frequency, face)
SELECT fin_dv01(0.05, 0.04, 5.0, 2, 100.0) AS dv01;

-- fin_ema(close, period)
SELECT fin_ema(close, 10 ORDER BY ts) AS ema
FROM (SELECT i AS ts, 100 + 3 * sin(i / 4) + i / 10 AS close FROM range(60) t(i));

-- fin_ema_halflife(x, ts, halflife)
SELECT fin_ema_halflife(x, ts, INTERVAL '1 day') AS ema
FROM (VALUES (TIMESTAMP '2026-01-01', 10.0), (TIMESTAMP '2026-01-02', 12.0), (TIMESTAMP '2026-01-03', 11.0)) t(ts, x);

-- fin_ewma_vol(r, lambda, annualization)
SELECT fin_ewma_vol(r, 0.94, 252.0 ORDER BY ts) AS ewma_vol
FROM (VALUES (1, 0.01), (2, -0.02), (3, 0.015), (4, -0.005)) t(ts, r);

-- fin_exp_decay_avg(x, ts, halflife)
SELECT fin_exp_decay_avg(x, ts, 2.0) AS decayed_mean
FROM (VALUES (1.0, 10.0), (2.0, 12.0), (3.0, 11.0)) t(ts, x);

-- fin_exp_decay_count(ts, halflife)
SELECT fin_exp_decay_count(ts, INTERVAL '1 hour') AS decayed_count
FROM (VALUES (TIMESTAMP '2026-01-02 09:00:00'), (TIMESTAMP '2026-01-02 10:00:00'), (TIMESTAMP '2026-01-02 11:00:00')) t(ts);

-- fin_exp_decay_max(x, ts, halflife)
SELECT fin_exp_decay_max(x, ts, 1.0) AS decayed_max
FROM (VALUES (1.0, 20.0), (2.0, 12.0), (3.0, 11.0)) t(ts, x);

-- fin_exp_decay_sum(x, ts, halflife)
SELECT fin_exp_decay_sum(x, ts, 2.0) AS decayed_sum
FROM (VALUES (1.0, 10.0), (2.0, 12.0), (3.0, 11.0)) t(ts, x);

-- fin_expected_shortfall
SELECT fin_expected_shortfall(r, 0.8, 'historical') AS expected_shortfall
FROM (VALUES (0.01), (-0.04), (0.02), (-0.01), (0.03), (-0.02), (0.005), (0.015), (-0.03), (0.01)) t(r);

-- fin_first_non_null
SELECT fin_first_non_null(x, ts) AS first_value
FROM (VALUES (1, NULL), (2, 12.0), (3, 11.0)) t(ts, x);

-- fin_garman_klass_vol
SELECT fin_garman_klass_vol(open, high, low, close, 252) AS vol
FROM (VALUES (100.0, 102.0, 99.0, 101.0), (101.0, 103.0, 100.5, 102.5), (102.5, 103.0, 100.0, 100.5)) t(open, high, low, close);

-- fin_half_life_mean_reversion
SELECT fin_half_life_mean_reversion(x, ts) AS half_life
FROM (VALUES (1, 1.0), (2, 0.6), (3, 0.5), (4, 0.2), (5, 0.25), (6, 0.05), (7, 0.1), (8, -0.05)) t(ts, x);

-- fin_hurst
SELECT fin_hurst(x, ts) AS hurst
FROM (SELECT i AS ts, sin(i * 1.3) + 0.5 * sin(i * 0.37) AS x FROM range(64) t(i));

-- fin_last_non_null
SELECT fin_last_non_null(x, ts) AS last_value
FROM (VALUES (1, 10.0), (2, 12.0), (3, NULL)) t(ts, x);

-- fin_linear_trend
SELECT fin_linear_trend(y, x) AS trend
FROM (VALUES (1.0, 1.0), (2.1, 2.0), (2.9, 3.0), (4.2, 4.0)) t(y, x);

-- fin_ljung_box
SELECT fin_ljung_box(x, ts, 5) AS ljung_box
FROM (SELECT i AS ts, sin(i / 3) AS x FROM range(40) t(i));

-- fin_log_nav
SELECT fin_log_nav(r, 100.0) AS log_nav
FROM (VALUES (0.01), (0.02), (-0.01)) t(r);

-- fin_nav
SELECT fin_nav(r, 100.0) AS nav
FROM (VALUES (0.01), (0.02), (-0.01)) t(r);

-- fin_nearest_psd(matrix, method)
SELECT fin_nearest_psd([[1.0, 0.9, 0.2], [0.9, 1.0, 0.9], [0.2, 0.9, 1.0]], 'higham') AS nearest_correlation;

-- fin_parametric_var
SELECT fin_parametric_var(0.0005, 0.02, 0.99, 10.0, 't', 5.0) AS var_10d;

-- fin_parkinson_vol
SELECT fin_parkinson_vol(high, low, 252) AS vol
FROM (VALUES (102.0, 99.0), (103.0, 100.5), (103.0, 100.0)) t(high, low);

-- fin_pct_change
SELECT fin_pct_change(x, ts) AS pct_change
FROM (VALUES (1, 100.0), (2, 104.0), (3, 110.0)) t(ts, x);

-- fin_quantile_spread(factor, forward_return, buckets)
SELECT fin_quantile_spread(factor, forward_return, 2) AS top_minus_bottom
FROM (VALUES (1.0, 0.00), (2.0, 0.01), (3.0, 0.02), (4.0, 0.03)) t(factor, forward_return);

-- fin_rank_ic
SELECT fin_rank_ic(factor, forward_return) AS rank_ic
FROM (VALUES (1.0, 0.01), (2.0, 0.00), (3.0, 0.02), (4.0, 0.03), (5.0, 0.025)) t(factor, forward_return);

-- fin_rate
SELECT fin_rate(x, ts, 'minute') AS per_minute
FROM (VALUES (TIMESTAMP '2026-01-02 09:30:00', 100.0), (TIMESTAMP '2026-01-02 09:35:00', 160.0)) t(ts, x);

-- fin_resets
SELECT fin_resets(x, ts) AS resets
FROM (VALUES (1, 5.0), (2, 9.0), (3, 2.0), (4, 4.0), (5, 1.0)) t(ts, x);

-- fin_rogers_satchell_vol
SELECT fin_rogers_satchell_vol(open, high, low, close, 252) AS vol
FROM (VALUES (100.0, 102.0, 99.0, 101.0), (101.0, 103.0, 100.5, 102.5), (102.5, 103.0, 100.0, 100.5)) t(open, high, low, close);

-- fin_var(r, confidence, method, loss_positive)
SELECT fin_var(r, 0.9, 'historical', true) AS var
FROM (VALUES (0.01), (-0.04), (0.02), (-0.01), (0.03), (-0.02), (0.005), (0.015), (-0.03), (0.01)) t(r);

-- fin_version()
SELECT fin_version() AS version;

-- fin_vol_of_vol
SELECT fin_vol_of_vol(vol, 252) AS vol_of_vol
FROM (VALUES (0.20), (0.22), (0.19), (0.25)) t(vol);

-- fin_yang_zhang_vol(open, high, low, close, annualization)
SELECT fin_yang_zhang_vol(open, high, low, close, 252 ORDER BY ts) AS vol
FROM (VALUES (1, 100.0, 102.0, 99.0, 101.0), (2, 101.0, 103.0, 100.5, 102.5), (3, 102.5, 103.0, 100.0, 100.5), (4, 100.0, 101.5, 99.0, 101.0)) t(ts, open, high, low, close);
