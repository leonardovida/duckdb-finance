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

- Load the extension before use. Most users can run
  `INSTALL finance FROM community; LOAD finance;`; for source builds, use the
  repository Makefile targets to build and load the unsigned local extension
  during validation.
- Scalar functions are called in ordinary `SELECT` expressions.
- Aggregate macros are called over grouped rows, for example `SELECT fin_total_return(r) FROM returns;`.
- Table functions and bind-replace functions appear in `FROM`, for example `SELECT * FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');`.
- `make check` verifies this reference against every registered `fin_*`
  function and verifies that every registered function appears in the gold SQL
  tests. The checks scan split `.cpp` and `.inc` source units under `src/`.

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
| `fin_cvar` | `fin_cvar(r, confidence := 0.95, method := 'historical', loss_positive := true)` | Compute the mean of returns in the historical VaR tail. | Positive loss by default; set `loss_positive := false` for the signed tail return. |
| `fin_data_quality_report` | `fin_data_quality_report(x)` | Compute data quality report for SQL finance workflows. | STRUCT. |
| `fin_down_capture` | `fin_down_capture(r, benchmark_r)` | Compute down capture for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_downside_deviation` | `fin_downside_deviation(r, mar := 0.0, annualization := 252)` | Compute downside deviation for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_drawdown` | `fin_drawdown(r, initial_nav := 1.0)` | Compute current drawdown from the ordered return series. | Order-sensitive aggregate; window states preserve the preceding peak. |
| `fin_drawdown_at_risk` | `fin_drawdown_at_risk(r, confidence := 0.95)` | Compute drawdown at risk for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_drawdown_duration` | `fin_drawdown_duration(r, initial_nav := 1.0)` | Compute the longest drawdown duration from the ordered return series. | Order-sensitive aggregate. |
| `fin_entropy` | `fin_entropy(x)` | Compute entropy for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_ewma_variance` | `fin_ewma_variance(r, lambda := 0.94, annualization := 252)` | Compute annualized exponentially weighted variance from ordered returns. | Order-sensitive aggregate; `lambda` and `annualization` must be constant within a group. |
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
| `fin_iv_percentile` | `fin_iv_percentile(implied_volatility ORDER BY quote_ts)` | Compute where the latest implied volatility sits within the observed min/max range. | Order-sensitive aggregate; use aggregate `ORDER BY` to define the latest observation. |
| `fin_iv_rank` | `fin_iv_rank(implied_volatility ORDER BY quote_ts)` | Compute where the latest implied volatility sits within the observed min/max range. | Order-sensitive aggregate; use aggregate `ORDER BY` to define the latest observation. |
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
| `fin_outlier_count` | `fin_outlier_count(x, method := 'zscore', threshold := 3.0)` | Compute outlier count for SQL finance workflows. | Aggregate result; method and threshold must be constant within each group. |
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
| `fin_sortino` | `fin_sortino(r, mar := 0.0, annualization := 252)` | Compute sortino for SQL finance workflows. | Aggregate result; annualization must be constant within each group. |
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
| `fin_trimmed_mean` | `fin_trimmed_mean(x, lower_q := 0.05, upper_q := 0.95)` | Average observations between the inclusive lower and upper quantiles. | Quantile bounds must satisfy `0 <= lower_q <= upper_q <= 1`. |
| `fin_ttest_1samp` | `fin_ttest_1samp(x, mu)` | Compute ttest 1samp for SQL finance workflows. | STRUCT. |
| `fin_ttest_2samp` | `fin_ttest_2samp(x, y, equal_var := true)` | Compute ttest 2samp for SQL finance workflows. | STRUCT. |
| `fin_ulcer_index` | `fin_ulcer_index(r)` | Compute ulcer index for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_up_capture` | `fin_up_capture(r, benchmark_r)` | Compute up capture for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_upside_deviation` | `fin_upside_deviation(r, threshold := 0.0, annualization := 252)` | Compute upside deviation for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_validate_return` | `fin_validate_return(0.05)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | BOOLEAN. |
| `fin_volatility` | `fin_volatility(r, annualization := 252, ddof := 1)` | Compute volatility for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_mean` | `fin_weighted_mean(x, w)` | Compute the mean over value/weight pairs. | Null pairs are skipped; weights must be finite and non-negative. |
| `fin_weighted_quantile` | `fin_weighted_quantile(x, w, q, method := 'linear')` | Compute a quantile from the weighted empirical distribution. | Supports `linear`, `lower`, `higher`, `nearest`, `midpoint`, and `inverted_cdf`; zero weights are ignored. |
| `fin_weighted_stddev` | `fin_weighted_stddev(x, w, ddof := 0)` | Compute weighted standard deviation with a weight-sum degrees-of-freedom correction. | Null pairs are skipped; weights must be finite and non-negative. |
| `fin_weighted_var` | `fin_weighted_var(x, w, ddof := 0)` | Compute weighted variance with denominator `sum(w) - ddof`. | Returns `NULL` when the denominator is not positive. |
| `fin_welch_ttest` | `fin_welch_ttest(x, y)` | Compute welch ttest for SQL finance workflows. | STRUCT. |
| `fin_win_rate` | `fin_win_rate(r)` | Compute win rate for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_winsorized_mean` | `fin_winsorized_mean(x, lower_q := 0.05, upper_q := 0.95)` | Clamp observations to the lower and upper quantiles, then average them. | Quantile bounds must satisfy `0 <= lower_q <= upper_q <= 1`. |
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
| `fin_irr` | `fin_irr([-100.0, 60.0, 60.0], 0.1)` | Compute IRR for periodic cash flows. | Uses a 10% default guess; a supplied guess selects among multiple valid roots. |
| `fin_mirr` | `fin_mirr([-100.0, 60.0, 60.0], 0.1, 0.05)` | Compute mirr for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_npv` | `fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic')` | Compute npv for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_present_value` | `fin_present_value(105.12710963760242, 0.05, 1.0, 'continuous')` | Compute present value for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_rate_from_discount` | `fin_rate_from_discount(0.951229424500714, 1.0, 'continuous')` | Compute rate from discount for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_swap_rate` | `fin_swap_rate([1.0, 2.0], [0.95, 0.90])` | Compute swap rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_validate_curve_spec` | `fin_validate_curve_spec(spec)` | Validate input shape or finance-specific invariants and return a boolean or validation struct. | STRUCT. |
| `fin_xirr` | `fin_xirr([-100.0, 110.0], [DATE '2026-01-01', DATE '2027-01-01'], 0.1)` | Compute IRR for dated cash flows. | Uses a 10% default guess; a supplied guess selects among multiple valid roots. |
| `fin_yearfrac` | `fin_yearfrac(DATE '2026-01-01', DATE '2027-01-01', 'ACT/365F')` | Compute yearfrac for SQL finance workflows. | DOUBLE; reversed `ACT/ACT` dates return the negative forward fraction. |

### Options And Volatility Models

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_asian_geometric_price` | `fin_asian_geometric_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute asian geometric price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_asset_or_nothing_price` | `fin_asset_or_nothing_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute asset or nothing price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bachelier_greeks` | `fin_bachelier_greeks('call', 100.0, 100.0, 1.0, 0.05, 5.0)` | Compute bachelier greeks for SQL finance workflows. | STRUCT. |
| `fin_bachelier_implied_vol` | `fin_bachelier_implied_vol('call', fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0), 100.0, 100.0, 1.0, 0.05, 4.0, 1e-8)` | Compute bachelier implied vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bachelier_price` | `fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0)` | Compute bachelier price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_barrier_price` | `fin_barrier_price('call', 'up-out', 100.0, 100.0, 120.0, 3.0, 1.0, 0.05, 0.2, 0.0)` | Price a continuously monitored European single-barrier option with an optional rebate. | Reiner-Rubinstein `DOUBLE`; kinds are `down-in`, `down-out`, `up-in`, and `up-out`; inputs after barrier are `[rebate,] ttm, rate, vol[, dividend_yield]`. |
| `fin_binomial_price` | `fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'european', 'crr')` | Compute binomial price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_black76_greeks` | `fin_black76_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute black76 greeks for SQL finance workflows. | STRUCT. |
| `fin_black76_implied_vol` | `fin_black76_implied_vol('call', fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05, 0.3, 1e-8)` | Compute black76 implied vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_black76_price` | `fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute black76 price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_all` | `fin_bsm_all(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))` | Return Black-Scholes-Merton price, Greeks, d1/d2, intrinsic value, and time value from explicit inputs or an option spec. | STRUCT with `price`, Greek fields, `d1`, `d2`, `intrinsic`, and `time_value`. |
| `fin_bsm_charm` | `fin_bsm_charm('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm charm for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_color` | `fin_bsm_color('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm color for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_d1` | `fin_bsm_d1(100.0, 100.0, 1.0, 0.05, 0.2, 0.0)` | Compute bsm d1 for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_d2` | `fin_bsm_d2(100.0, 100.0, 1.0, 0.05, 0.2, 0.0)` | Compute bsm d2 for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_delta` | `fin_bsm_delta(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))` | Return Black-Scholes-Merton spot delta from explicit inputs or an option spec. | DOUBLE. |
| `fin_bsm_elasticity` | `fin_bsm_elasticity('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm elasticity for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_gamma` | `fin_bsm_gamma(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))` | Return Black-Scholes-Merton gamma from explicit inputs or an option spec. | DOUBLE. |
| `fin_bsm_greeks` | `fin_bsm_greeks(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))` | Return Black-Scholes-Merton delta, gamma, vega, theta, and rho from explicit inputs or an option spec. | STRUCT with `delta`, `gamma`, `vega`, `theta`, and `rho`. |
| `fin_bsm_implied_vol` | `fin_bsm_implied_vol('call', fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05)` | Compute bsm implied vol for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_price` | `fin_bsm_price(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))` | Price a Black-Scholes-Merton option from explicit inputs or an option spec; `ttm`, rate, volatility, and dividend yield are annual decimal values. | DOUBLE. |
| `fin_bsm_price_dates` | `fin_bsm_price_dates('call', 100.0, 100.0, DATE '2026-01-01', DATE '2027-01-01', 0.05, 0.2)` | Compute bsm price dates for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_prob_itm` | `fin_bsm_prob_itm('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm prob itm for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_prob_touch` | `fin_bsm_prob_touch('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm prob touch for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_rho` | `fin_bsm_rho('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm rho for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_speed` | `fin_bsm_speed('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm speed for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_theta` | `fin_bsm_theta('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm theta for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_ultima` | `fin_bsm_ultima('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm ultima for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_vanna` | `fin_bsm_vanna('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm vanna for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_vega` | `fin_bsm_vega(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.2))` | Return Black-Scholes-Merton vega from explicit inputs or an option spec. | DOUBLE. |
| `fin_bsm_vomma` | `fin_bsm_vomma('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm vomma for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bsm_zomma` | `fin_bsm_zomma('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute bsm zomma for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_digital_price` | `fin_digital_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute digital price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_forward_price` | `fin_forward_price(100.0, 1.0, 0.05, 0.0)` | Compute forward price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_option_market_spec` | `fin_option_market_spec(kind, spot, strike, expiry, valuation_date, rate, vol, dividend_yield := 0.0, calendar := 'weekday', day_count := 'ACT/365F')` | Compute option market spec for SQL finance workflows. | STRUCT. |
| `fin_option_payoff` | `fin_option_payoff('call', 105.0, 100.0)` | Compute option payoff for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_option_spec` | `fin_option_spec(kind, spot, strike, ttm, rate, vol, dividend_yield := 0.0, exercise := 'european', model := 'bsm')` | Pack reusable option inputs into a struct accepted by BSM pricing and Greek functions. | STRUCT with normalized option kind, annual decimal inputs, exercise style, and model name. |
| `fin_option_spec_dates` | `fin_option_spec_dates(kind, spot, strike, valuation_date, expiry_date, rate, vol, dividend_yield := 0.0, day_count := 'ACT/365F', exercise := 'european', model := 'bsm')` | Build an option spec from valuation and expiry dates using a day-count convention for time to expiry. | STRUCT compatible with `fin_bsm_price`, `fin_bsm_greeks`, and `fin_bsm_all`. |
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
| `fin_cdl_pattern` | `fin_cdl_pattern(open, high, low, close, pattern)` | Candlestick pattern pattern helper. | INTEGER signal. |
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
| `fin_rsi` | `fin_rsi(close, period := 14)` | Compute Wilder-smoothed relative strength from the ordered price series. | Order-sensitive aggregate; `period` must be positive and constant within a group. |
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
| `fin_min_variance_weights` | `fin_min_variance_weights(cov_matrix, long_only := true)` | Minimum-variance optimizer fallback. | LIST of weights; current implementation returns equal weights sized from the covariance matrix. |
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
| `fin_business_days_between` | `fin_business_days_between(DATE '2026-05-04', DATE '2026-05-08', 'weekday')` | Count weekdays in the half-open date range. | BIGINT; reversed ranges return the negated forward count. |
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
| `fin_bootstrap_curve` | `fin_bootstrap_curve('gold_curve', 'inst', 'maturity', 'rate', 'continuous')` | Build a simple bootstrapped curve table from instrument maturities and rates using the requested compounding convention. | Table result. |
| `fin_calendar` | `fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-06')` | Return business-calendar dates for a calendar name and date range. | Table result. |
| `fin_changes_to_grid` | `fin_changes_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute changes to grid for SQL finance workflows. | Table result. |
| `fin_curve_bootstrap` | `fin_curve_bootstrap('gold_curve', 'inst', 'maturity', 'rate', 'continuous')` | Alias for curve bootstrapping with the requested compounding convention. | Table result. |
| `fin_delta_to_grid` | `fin_delta_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute delta to grid for SQL finance workflows. | Table result. |
| `fin_dollar_bars` | `fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 100000.0)` | Compute dollar bars for SQL finance workflows. | Table result; threshold must be positive and finite. |
| `fin_efficient_frontier` | `fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]])` | Compute efficient frontier for SQL finance workflows. | Table result. |
| `fin_factor_report` | `fin_factor_report('gold_returns', 'd', 'asset', 'factor', 'forward_return', 2)` | Compute factor report for SQL finance workflows. | Table result. |
| `fin_fama_macbeth` | `fin_fama_macbeth('gold_returns', 'd', 'asset', 'forward_return', ['factor'], 1)` | Compute fama macbeth for SQL finance workflows. | Table result. |
| `fin_garch_fit` | `fin_garch_fit('gold_returns', 'r', 1, 1, 'normal')` | Compute garch fit for SQL finance workflows. | Table result. |
| `fin_hrp_weights` | `fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]], ['AAA', 'BBB'], 'single')` | Compute hrp weights for SQL finance workflows. | Table result. |
| `fin_imbalance_bars` | `fin_imbalance_bars('gold_prices', 'ts', 'close', 'volume', 'signed')` | Aggregate signed-volume observations into imbalance bars. | Table result; the optional method currently accepts only `signed`. |
| `fin_last_to_grid` | `fin_last_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute last to grid for SQL finance workflows. | Table result. |
| `fin_normalize_ohlcv` | `fin_normalize_ohlcv('gold_prices', 'ts', 'open', 'high', 'low', 'close', 'volume')` | Project source OHLCV columns into canonical `ts`, `asset_id`, `open`, `high`, `low`, `close`, and `volume` fields. | Table result with canonical OHLCV columns. |
| `fin_normalize_option_chain` | `fin_normalize_option_chain('gold_source_options', 'cp', 'underlying_px', 'strike_px', 'expiry_dt', 'valuation_dt', 'zero_rate', 'iv', 'q')` | Project source option columns into canonical option fields and an `option_spec` struct for BSM functions. | Table result with canonical option fields plus `option_spec`. |
| `fin_normalize_returns` | `fin_normalize_returns('gold_returns', 'd', 'asset', 'r')` | Project source return columns into canonical `date`, `asset_id`, and `return_decimal` fields. | Table result with one row per normalized asset return. |
| `fin_option_chain` | `fin_option_chain('gold_options', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield')` | Project option input rows and append model-prefixed BSM columns such as `model_price`, `model_delta`, and `model_implied_volatility`. | Table result preserving source columns and adding model-prefixed analytics columns. |
| `fin_portfolio_optimize` | `fin_portfolio_optimize([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 'max_sharpe', 0.0, true, 0.0, 1.0, 0.12, 0.2, 1.0)` | Compute portfolio optimize for SQL finance workflows. | Table result. |
| `fin_portfolio_optimize_table` | `fin_portfolio_optimize_table('gold_current_weights', 'asset', 'weight', 'weight')` | Compute portfolio optimize table for SQL finance workflows. | Table result. |
| `fin_portfolio_return_table` | `fin_portfolio_return_table('gold_weighted_returns', 'asset', 'weight', 'expected_return')` | Compute portfolio return directly from table-shaped asset, weight, and return columns. | One-row table with `portfolio_return`, `weight_sum`, and `asset_count`. |
| `fin_portfolio_variance_table` | `fin_portfolio_variance_table('gold_weighted_returns', 'asset', 'weight', 'gold_covariance', 'asset_i', 'asset_j', 'covariance')` | Compute portfolio variance and volatility from table-shaped weights and pairwise covariance rows. | One-row table with `portfolio_variance` and `portfolio_volatility`. |
| `fin_predict_linear_to_grid` | `fin_predict_linear_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute predict linear to grid for SQL finance workflows. | Table result. |
| `fin_rate_to_grid` | `fin_rate_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute rate to grid for SQL finance workflows. | Table result. |
| `fin_rebalance_trades` | `fin_rebalance_trades('gold_current_weights', 'gold_target_weights', 'gold_asset_prices', 100000.0)` | Compute rebalance trades for SQL finance workflows. | Table result. |
| `fin_resample_grid` | `fin_resample_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute', 'last', INTERVAL '10 minutes' )` | Resample values onto a regular timestamp grid using the last observation at or before each grid timestamp. | Table result; optional staleness returns `NULL` when the carried value is older than the interval. |
| `fin_resets_to_grid` | `fin_resets_to_grid( 'gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute' )` | Compute resets to grid for SQL finance workflows. | Table result. |
| `fin_schema_template` | `fin_schema_template('ohlcv')` | Return the expected columns for a named finance schema template. | Table result. |
| `fin_tick_bars` | `fin_tick_bars('gold_prices', 'ts', 'close')` | Compute tick bars for SQL finance workflows. | Table result; optional threshold must be positive and finite. |
| `fin_validate_schema` | `fin_validate_schema('gold_prices', 'ohlcv')` | Return schema-template rows for validating a table against a template. | Table result. |
| `fin_volume_bars` | `fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 1000.0)` | Compute volume bars for SQL finance workflows. | Table result; threshold must be positive and finite. |

### General Helpers

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_adf` | `fin_adf(x, max_lag := 1, regression := 'c')` | Compute adf for SQL finance workflows. | NULL placeholder. |
| `fin_autocorr` | `fin_autocorr(x, lag := 1)` | Compute autocorr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_bipower_variation` | `fin_bipower_variation(log_r ORDER BY observation_key)` | Estimate annualized bipower variation from adjacent absolute log-return products. | Order-dependent aggregate; defaults to 252 periods and returns `NULL` with fewer than two non-`NULL` returns. |
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
| `fin_expected_shortfall` | `fin_expected_shortfall(r, confidence := 0.95, method := 'historical')` | Compute the positive mean loss beyond historical VaR. | Alias of historical `fin_cvar(..., loss_positive := true)`. |
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
| `fin_quantile_spread` | `fin_quantile_spread(factor, forward_return, buckets := 5)` | Compute the mean forward-return spread between the top and bottom factor buckets. | `buckets` must be greater than one and constant within each group. |
| `fin_rank_ic` | `fin_rank_ic(factor, forward_return)` | Compute rank ic for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rate` | `fin_rate(x, ts, unit := 'second')` | Compute rate for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_resets` | `fin_resets(x)` | Compute resets for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rogers_satchell_vol` | `fin_rogers_satchell_vol(open, high, low, close, annualization := 252)` | Compute rogers satchell vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_var` | `fin_var(r, confidence := 0.95, method := 'historical', loss_positive := true)` | Compute var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_version` | `fin_version()` | Return the loaded finance extension version string. | VARCHAR in `finance <version>` form for releases. |
| `fin_vol_of_vol` | `fin_vol_of_vol(vol, annualization := 252)` | Compute vol of vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_yang_zhang_vol` | `fin_yang_zhang_vol(open, high, low, close, annualization := 252)` | Compute yang zhang vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |

## Testing

The reference surface is exercised by `make test`, which builds the extension, runs smoke SQL, loads `test/sql/gold_dataset.sql`, and evaluates `test/sql/gold_tests.sql`. The gold dataset is intentionally small and deterministic so expected values are easy to audit.

For model and unit conventions, see
[Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}). For workflow-oriented
examples, see [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}).
