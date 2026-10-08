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
| `fin_student_t_inv` | `fin_student_t_inv(0.000001, 2.0)` | Invert the Student-t CDF. | DOUBLE; brackets heavy-tailed lower and upper probabilities. |

### Returns, Risk, And Statistics

`fin_stable_var` and `fin_stable_stddev` use denominator `count(x) - ddof` for
any finite non-negative `ddof`; an exhausted denominator returns `NULL`.
Downside/upside deviation, semivariance, and hit/win/loss rates skip NULL
observations. Beta, alpha, capture ratios, and VWAP use complete input pairs.
Drawdown ratios track wealth relative to the running peak to avoid overflow;
the positive `initial_nav` scale does not change those ratios. Weighted moments
that overflow return `NULL` rather than a fabricated zero variance.

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
| `fin_beta` | `fin_beta(r, benchmark_r)` | Compute the regression slope of returns against benchmark returns. | `DOUBLE`; both moments use complete pairs. Returns `NULL` for constant or insufficient benchmark observations. |
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
| `fin_ewma_variance` | `fin_ewma_variance(r, 0.94, 252.0 ORDER BY ts)` | Compute annualized exponentially weighted variance from ordered returns. | `DOUBLE`; defaults to lambda 0.94 and annualization 252. Seeds with the first non-NULL squared return, then uses `lambda * variance + (1-lambda) * r^2`. Inputs must be finite, lambda in (0,1), and annualization positive and finite; parameters must be constant within each group. Empty input or an unrepresentable result yields `NULL`. Scaled state avoids intermediate overflow. |
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
| `fin_iv_percentile` | `fin_iv_percentile(implied_volatility ORDER BY quote_ts)` | Count the fraction of prior IV observations strictly below the latest IV. | `DOUBLE` in [0,1]; excludes the latest observation from the denominator and gives ties no credit. Requires at least two non-NULL observations; otherwise `NULL`. Inputs must be finite and non-negative. Retains history for an exact result; use a bounded window for rolling percentiles. |
| `fin_iv_rank` | `fin_iv_rank(implied_volatility ORDER BY quote_ts)` | Compute where the latest implied volatility sits within the observed min/max range. | `DOUBLE` in [0,1]; `NULL` for empty or constant history. Inputs must be finite and non-negative. Use aggregate `ORDER BY` to define the latest observation. |
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
| `fin_outlier_count` | `fin_outlier_count(x, 'zscore', 3.0)` | Count observations whose absolute sample z-score exceeds the threshold. | `BIGINT`; one-argument default is threshold 3, and `(x, threshold)` is supported. Ignores NULL and non-finite observations; fewer than two observations or zero sample variance yields 0. Only `zscore` is supported; threshold must be positive, finite, and constant within each group. Normalized arithmetic avoids intermediate overflow. |
| `fin_parametric_cvar` | `fin_parametric_cvar(mean, vol, confidence := 0.95, horizon := 1.0, distribution := 'normal')` | Compute parametric cvar for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_parse_return_method` | `fin_parse_return_method('log')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_payoff_ratio` | `fin_payoff_ratio(r)` | Compute payoff ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_price_from_return` | `fin_price_from_return(prev_price, r, method := 'simple')` | Compute price from return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_rank_corr` | `fin_rank_corr(x, y, method := 'spearman')` | Compute rank corr for SQL finance workflows. | Experimental Pearson correlation on raw values; method is ignored. |
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
| `fin_sortino` | `fin_sortino(r, 0.0, 252.0)` | Compute the annualized mean excess return divided by downside deviation. | `DOUBLE`; defaults to annualized MAR 0 and 252 observations per year. Downside deviation uses all observations in its denominator, with excess return `r - mar / annualization`. Returns and MAR must be finite; annualization must be positive, finite, and constant within each group. Empty input, no downside, or an unrepresentable result yields `NULL`. Scaled, compensated state supports very large and tiny returns. |
| `fin_stability` | `fin_stability(r)` | Compute stability for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_corr` | `fin_stable_corr(y, x)` | Compute stable corr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_cov` | `fin_stable_cov(y, x)` | Compute stable cov for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_mean` | `fin_stable_mean(x)` | Compute stable mean for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_stddev` | `fin_stable_stddev(x, ddof := 1)` | Compute stable stddev for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stable_var` | `fin_stable_var(x, ddof := 1)` | Compute stable var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_tail_ratio` | `fin_tail_ratio(r, upper_q := 0.95, lower_q := 0.05)` | Compute tail ratio for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_theils_u` | `fin_theils_u(x, y)` | Compute theils u for SQL finance workflows. | NULL placeholder. |
| `fin_to_log_return` | `fin_to_log_return(r)` | Compute to log return for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_total_return` | `fin_total_return(r, method := 'simple')` | Compound decimal simple or log returns. | `DOUBLE`; skips NULL observations. A simple return of -1 produces total loss; returns below -1, non-finite observations, invalid methods, and empty groups return `NULL`. |
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
| `fin_weighted_quantile` | `fin_weighted_quantile(x, w, q, method := 'linear')` | Compute a quantile from the weighted empirical distribution. | `DOUBLE`; interpolates between successive cumulative-weight knots, rather than unweighted `quantile_cont` positions. Equal values use increasing-weight order to define interpolation knots. Supports `linear`, `lower`, `higher`, `nearest`, `midpoint`, and `inverted_cdf` case-insensitively. Finite values and non-negative finite weights are required; zero weights and NULL pairs are ignored. Quantile must be in [0,1] and constant within each group, as must method. Normalized weights preserve scale invariance; endpoints use a linear scan. |
| `fin_weighted_stddev` | `fin_weighted_stddev(x, w, ddof := 0)` | Compute weighted standard deviation with a weight-sum degrees-of-freedom correction. | Null pairs are skipped; weights must be finite and non-negative. |
| `fin_weighted_var` | `fin_weighted_var(x, w, ddof := 0)` | Compute weighted variance with denominator `sum(w) - ddof`. | Returns `NULL` when the denominator is not positive or the accumulated moments overflow. |
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
| `fin_bond_convexity` | `fin_bond_convexity(0.05, 0.04, 5.0, 2, 100.0)` | Compute convexity for the regular coupon model. | `DOUBLE`; defaults to frequency 2 and face 100. Geometric moments require logarithmic rather than linear work in coupon periods. |
| `fin_bond_duration` | `fin_bond_duration(0.05, 0.04, 5.0, 2, 100.0, 'modified')` | Compute duration for the regular coupon model. | `DOUBLE`; defaults to frequency 2, face 100, and Macaulay duration in years. Specify `modified` for the first-order yield sensitivity. Uses logarithmic-time geometric moments. |
| `fin_bond_price` | `fin_bond_price(0.05, 0.04, 5.0, 2, 100.0)` | Discount a regular coupon bond using nominal annual YTM. | `DOUBLE`; coupon periods are rounded from maturity times frequency. Uses a constant-time geometric sum, including zero and small yields. Invalid inputs or out-of-range period counts return `NULL`. No settlement or stub-period model. |
| `fin_bond_ytm` | `fin_bond_ytm(fin_bond_price(0.05, 0.04, 5.0, 2, 100.0), 0.05, 5.0, 2, 100.0)` | Solve nominal annual yield for the regular coupon model. | `DOUBLE`; requires positive price and non-negative coupon. Brackets yields above -frequency, including yields above 100; returns `NULL` if it cannot bracket or converge. |
| `fin_cashflow_spec` | `fin_cashflow_spec(amount, date, currency := NULL)` | Compute cashflow spec for SQL finance workflows. | STRUCT. |
| `fin_curve_spec` | `fin_curve_spec(maturities, values, value_type := 'zero_rate', interpolation := 'linear', compounding := 'continuous', day_count := 'ACT/365F')` | Compute curve spec for SQL finance workflows. | STRUCT. |
| `fin_curve_zero_rate` | `fin_curve_zero_rate([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5)` | Linearly interpolate zero rates. | `DOUBLE`; finite, strictly increasing maturities and finite values are required. Lists must be non-empty and equal length. Flat extrapolation uses the nearest endpoint. Large curves use binary lookup; constant curves are validated once per input chunk. |
| `fin_forward_rate` | `fin_forward_rate(0.9607894391523232, 0.8869204367171575, 1.0, 2.0, 'continuous')` | Compute forward rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_fra_rate` | `fin_fra_rate(0.04, 0.05, 1.0, 2.0)` | Compute fra rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_future_value` | `fin_future_value(100.0, 0.05, 1.0, 'continuous')` | Compute future value for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_interpolate_curve` | `fin_interpolate_curve([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5)` | Linearly interpolate finite values over strictly increasing maturities. | `DOUBLE`; flat endpoint extrapolation. Invalid curves or non-finite targets return `NULL`. |
| `fin_irr` | `fin_irr([-100.0, 60.0, 60.0], 0.1)` | Compute IRR for periodic cash flows. | Uses a 10% default guess; a supplied guess selects among multiple valid roots. Cash flows are normalized before solving so their currency scale does not set the convergence tolerance. |
| `fin_mirr` | `fin_mirr([-100.0, 60.0, 60.0], 0.1, 0.05)` | Compute mirr for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_npv` | `fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic')` | Compute npv for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_present_value` | `fin_present_value(105.12710963760242, 0.05, 1.0, 'continuous')` | Compute present value for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_rate_from_discount` | `fin_rate_from_discount(0.951229424500714, 1.0, 'continuous')` | Compute rate from discount for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_swap_rate` | `fin_swap_rate([1.0, 2.0], [0.95, 0.90])` | Compute swap rate for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_validate_curve_spec` | `fin_validate_curve_spec(spec)` | Validate the numerical inputs used by curve interpolation. | `STRUCT(ok, reason)`; requires non-empty, equal-length lists, finite non-null values, and strictly increasing finite maturities. Reports the failed constraint. It does not validate pricing-model metadata. |
| `fin_xirr` | `fin_xirr([-100.0, 110.0], [DATE '2026-01-01', DATE '2027-01-01'], 0.1)` | Compute IRR for dated cash flows. | Uses a 10% default guess and ACT/365F times; a supplied guess selects among multiple valid roots. Normalizes cash-flow amounts before solving. Infinite dates return `NULL`. |
| `fin_yearfrac` | `fin_yearfrac(DATE '2026-01-01', DATE '2027-01-01', 'ACT/365F')` | Compute yearfrac for SQL finance workflows. | DOUBLE; reversed `ACT/ACT` dates return the negative forward fraction. |

### Options And Volatility Models

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_asian_geometric_price` | `fin_asian_geometric_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute asian geometric price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_asset_or_nothing_price` | `fin_asset_or_nothing_price('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute asset or nothing price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_bachelier_greeks` | `fin_bachelier_greeks('call', 100.0, 100.0, 1.0, 0.05, 5.0)` | Compute Greeks under the normal forward-price model. | `STRUCT(delta, gamma, vega, theta, rho)`; any NULL input, invalid domain, or non-finite output returns a NULL struct. |
| `fin_bachelier_implied_vol` | `fin_bachelier_implied_vol('call', fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0), 100.0, 100.0, 1.0, 0.05, 4.0, 1e-8)` | Solve normal volatility in forward-price units per square root year. | `DOUBLE`; omitted guess uses the quote's price, discount factor, and time scale rather than fixed price units. Optional explicit guess and absolute price tolerance (default `1e-8`). Uses bracketed Newton steps with bisection fallback and cached pricing terms. Requires positive time; expands the bracket for large normal volatilities. Returns zero at intrinsic within tolerance, or `NULL` on invalid inputs or failure to converge. |
| `fin_bachelier_price` | `fin_bachelier_price('call', 100.0, 100.0, 1.0, 0.05, 5.0)` | Compute bachelier price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_barrier_price` | `fin_barrier_price('call', 'up-out', 100.0, 100.0, 120.0, 3.0, 1.0, 0.05, 0.2, 0.0)` | Price a continuously monitored European single-barrier option with an optional rebate. | Reiner-Rubinstein `DOUBLE`; kinds are `down-in`, `down-out`, `up-in`, and `up-out`; inputs after barrier are `[rebate,] ttm, rate, vol[, dividend_yield]`. |
| `fin_binomial_price` | `fin_binomial_price('call', 100.0, 100.0, 1.0, 0.05, 0.2, 0.0, 20, 'european', 'crr')` | Price European or American options with CRR or Jarrow-Rudd trees. | Defaults: dividend yield 0, 200 steps, European exercise, CRR tree. European prices use a linear-time terminal distribution; American prices retain backward induction where early exercise matters. Non-dividend CRR calls with non-negative rates use the European path. Zero volatility follows the discounted deterministic path; Bermudan schedules are unsupported. |
| `fin_black76_greeks` | `fin_black76_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.2)` | Compute Greeks under the lognormal forward-price model. | `STRUCT(delta, gamma, vega, theta, rho)`; any NULL input, invalid domain, or non-finite output returns a NULL struct. |
| `fin_black76_implied_vol` | `fin_black76_implied_vol('call', fin_black76_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05, 0.3, 1e-8)` | Solve annualized decimal Black-76 volatility. | `DOUBLE`; defaults to guess 0.2 and absolute price tolerance `1e-8`. Uses bracketed Newton steps with bisection fallback and cached pricing terms. Requires positive time and price below the no-arbitrage upper bound. Returns zero at intrinsic within tolerance, or `NULL` on invalid inputs or failure to converge. |
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
| `fin_bsm_implied_vol` | `fin_bsm_implied_vol('call', fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.2), 100.0, 100.0, 1.0, 0.05)` | Solve annualized decimal BSM volatility. | `DOUBLE`; optional dividend yield, guess (default 0.2), absolute price tolerance (default 1e-8), and iteration limit (default 100). Returns zero at intrinsic within tolerance, or `NULL` for impossible prices, invalid inputs, or failure to converge. Tiny time value can make volatility unidentifiable at the supplied tolerance. |
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
| `fin_sabr_vol` | `fin_sabr_vol(100.0, 100.0, 1.0, 0.2, 0.5, -0.2, 0.4)` | Compute Hagan's lognormal SABR implied-volatility approximation. | `DOUBLE`; `nu = 0` is supported through the finite zero-vol-of-vol limit, including away from the money. |
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
| `fin_cmo` | `fin_cmo(close, period := 14)` | Compute cmo for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_dema` | `fin_dema(x, period := 20)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not compute DEMA. |
| `fin_donchian` | `fin_donchian(high, low, period := 20)` | Compute donchian for SQL finance workflows. | STRUCT. |
| `fin_dx` | `fin_dx(high, low, close, period := 14)` | Compute dx for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_hma` | `fin_hma(x, period := 20)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not compute HMA. |
| `fin_kama` | `fin_kama(x, period := 10, fast := 2, slow := 30)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores the adaptive smoothing parameters. |
| `fin_keltner` | `fin_keltner(high, low, close, period := 20, atr_period := 10, multiplier := 2.0)` | Compute keltner for SQL finance workflows. | STRUCT. |
| `fin_kyle_lambda` | `fin_kyle_lambda(signed_volume, price_change)` | Compute kyle lambda for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_linearreg` | `fin_linearreg(x, period := 14)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not fit a regression. |
| `fin_linearreg_intercept` | `fin_linearreg_intercept(x, period := 14)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not estimate a regression intercept. |
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
| `fin_rsi` | `fin_rsi(close, period := 14)` | Compute Wilder-smoothed relative strength from the ordered price series. | Default period 14; supply aggregate `ORDER BY` or a window order. Positive period must be constant within a group. Retains at most `period + 1` seed prices and merges the remaining recurrence without retaining its history. Fewer than two observations return `NULL`; short histories seed from available changes. |
| `fin_sar` | `fin_sar(high, low, acceleration := 0.02, maximum := 0.2)` | Compute sar for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sarext` | `fin_sarext(high, low, options)` | Compute sarext for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_sma` | `fin_sma(x, period := 20)` | Return the arithmetic mean of supplied rows. | Partial experimental implementation: period is ignored. Apply an explicit SQL window for the desired lookback. |
| `fin_spread` | `fin_spread(bid, ask)` | Compute spread for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_spread_bps` | `fin_spread_bps(bid, ask)` | Compute spread bps for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_stddev` | `fin_stddev(close, period := 20, ddof := 1)` | Compute stddev for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_stoch` | `fin_stoch(high, low, close, k := 14, d := 3, smooth := 3)` | Compute stoch for SQL finance workflows. | STRUCT. |
| `fin_stochrsi` | `fin_stochrsi(close, period := 14, k := 3, d := 3)` | Compute stochrsi for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_t3` | `fin_t3(x, period := 20, vfactor := 0.7)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and volume factor and does not compute T3. |
| `fin_tema` | `fin_tema(x, period := 20)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not compute TEMA. |
| `fin_trade_sign` | `fin_trade_sign(102.0::DOUBLE, 100.0::DOUBLE, 101.0::DOUBLE)` | Compute trade sign for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_trima` | `fin_trima(x, period := 20)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not apply triangular weights. |
| `fin_trix` | `fin_trix(close, period := 30)` | Compute trix for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_true_range` | `fin_true_range(high, low, close)` | Compute true range for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_tsf` | `fin_tsf(x, period := 14)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not forecast a regression trend. |
| `fin_twap` | `fin_twap(price, ts)` | Compute twap for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_typ_price` | `fin_typ_price(high, low, close)` | Compute typ price for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_ultosc` | `fin_ultosc(high, low, close, short := 7, medium := 14, long := 28)` | Compute ultosc for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_var_indicator` | `fin_var_indicator(close, period := 20, ddof := 1)` | Compute var indicator for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_volume_profile` | `fin_volume_profile(price, volume, bins := 10)` | Compute volume profile for SQL finance workflows. | LIST. |
| `fin_vpin` | `fin_vpin(signed_volume, volume, buckets := 50)` | Compute vpin for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_vwap` | `fin_vwap(price, volume)` | Compute vwap for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_weighted_close` | `fin_weighted_close(high, low, close)` | Compute weighted close for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_willr` | `fin_willr(high, low, close, period := 14)` | Compute willr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_wma` | `fin_wma(x, period := 20)` | Return the arithmetic mean of supplied rows. | Experimental arithmetic-mean alias; ignores period and does not apply chronological weights. |

### Portfolio, Matrix, And Factor Analytics

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_black_litterman_returns` | `fin_black_litterman_returns(market_weights, cov_matrix, views_p, views_q, tau := 0.05, omega := NULL)` | Compute black litterman returns for SQL finance workflows. | LIST. |
| `fin_component_risk` | `fin_component_risk(weights, cov_matrix)` | Compute each weight's contribution to portfolio volatility. | `LIST`; component i is weight i times (covariance times weights) i divided by portfolio volatility. Components sum to portfolio volatility; zero portfolio volatility returns `NULL`. |
| `fin_corr_matrix` | `fin_corr_matrix(asset, r)` | Compute corr matrix for SQL finance workflows. | LIST. |
| `fin_cov_matrix` | `fin_cov_matrix(asset, r)` | Compute cov matrix for SQL finance workflows. | LIST. |
| `fin_curve_discount_factor` | `fin_curve_discount_factor([0.5, 1.0, 2.0], [0.04, 0.045, 0.05], 1.5)` | Discount using linearly interpolated zero rates and continuous compounding. | `DOUBLE`; finite values and strictly increasing maturities are required. Flat extrapolation uses the nearest endpoint rate. |
| `fin_discount_factor` | `fin_discount_factor(0.05, 1.0, 'continuous')` | Compute discount factor for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_equal_weights` | `fin_equal_weights(n)` | Compute equal weights for SQL finance workflows. | LIST. |
| `fin_factor_alpha` | `fin_factor_alpha(r, factor_r, risk_free := 0.0, annualization := 252)` | Compute factor alpha for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_factor_ic` | `fin_factor_ic(factor, forward_return, method := 'spearman')` | Compute factor ic for SQL finance workflows. | Experimental Pearson correlation on raw values; method is ignored. |
| `fin_factor_turnover` | `fin_factor_turnover(factor_rank, period := 1)` | Compute factor turnover for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_inverse_vol_weights` | `fin_inverse_vol_weights(vols)` | Compute inverse vol weights for SQL finance workflows. | LIST. |
| `fin_marginal_risk` | `fin_marginal_risk(weights, cov_matrix)` | Multiply the covariance matrix by portfolio weights. | `LIST`; returns covariance times weights, which is half the variance gradient. Divide by portfolio volatility for the marginal volatility gradient. |
| `fin_matrix_cholesky` | `fin_matrix_cholesky([[4.0, 2.0], [2.0, 3.0]])` | Compute a Cholesky factor for a symmetric positive semidefinite matrix. | Matrix result; `NULL` when no valid factor exists. |
| `fin_matrix_is_psd` | `fin_matrix_is_psd([[1.0, 0.2], [0.2, 1.0]])` | Check whether a symmetric matrix is positive semidefinite. | BOOLEAN. |
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
| `fin_risk_contribution` | `fin_risk_contribution(weights, cov_matrix)` | Normalize component volatility contributions. | `LIST`; contributions sum to one for nonzero portfolio volatility. Includes weight factors; short positions can produce negative contributions. |
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
| `fin_next_business_day` | `fin_next_business_day(DATE '2026-05-08', 5)` | Advance by weekday business days, excluding the start for positive offsets. | `DATE`; omitted offset defaults to 1. The two-argument overload accepts a `BIGINT` offset and uses weekdays automatically. The existing `(date, calendar, INTEGER offset)` overload remains available. Skips whole weeks in constant time. Zero returns the input date. NULL, infinite dates, or out-of-range results return `NULL`; negative offsets raise an error. No exchange holiday calendar. |
| `fin_normalize_currency` | `fin_normalize_currency('usd')` | Compute normalize currency for SQL finance workflows. | VARCHAR. |
| `fin_optimizer_spec` | `fin_optimizer_spec(objective := 'max_sharpe', risk_free := 0.0, long_only := true, weight_min := 0.0, weight_max := 1.0, target_return := NULL, target_vol := NULL, risk_aversion := 1.0)` | Compute optimizer spec for SQL finance workflows. | STRUCT. |
| `fin_parse_compounding` | `fin_parse_compounding('continuous')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_parse_day_count` | `fin_parse_day_count('actual/365 fixed')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_parse_exercise_style` | `fin_parse_exercise_style('American')` | Normalize and validate a finance convention string. | VARCHAR. |
| `fin_prev_business_day` | `fin_prev_business_day(DATE '2026-05-11', 5)` | Move backward by weekday business days. | `DATE`; omitted offset defaults to 1. Accepts `(date, BIGINT offset)` or `(date, calendar, INTEGER offset)`. Uses the same constant-time and validation rules as `fin_next_business_day`. |
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
| `fin_bootstrap_curve` | `fin_bootstrap_curve('gold_curve', 'inst', 'maturity', 'rate', 'continuous')` | Project quoted rates and maturities into a zero-rate curve with discount factors under the requested compounding (default `continuous`). | Experimental zero-rate projection: quoted instrument rates are treated as zero rates, not bootstrapped from cash flows. Unknown compounding names raise an error. Ordered by maturity, instrument. |
| `fin_calendar` | `fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-06')` | Return business-calendar dates for a calendar name and date range. | Table with `calendar`, `date`, `is_business_day`, `is_regular_session`. NULL arguments raise an error; omitted dates default to the local current date. |
| `fin_changes_to_grid` | `fin_changes_to_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')` | Flag whether each grid sample differs from the previous grid sample (1.0 changed, 0.0 unchanged). | DOUBLE `value`; NULL for the first grid point or when either sample is NULL. Grid points are `start_ts + i * step` for every point not after `end_ts` (at most 10,000,000 points; month steps are anchored at `start_ts`). Each point samples the last observation at or before it via an ASOF join; rows with NULL timestamp or value are skipped, and duplicate timestamps keep the row with the largest `seq_col` (else the largest value). Optional named `asset_col := 'col'` builds one grid per asset (output keeps that column) and `seq_col := 'col'` breaks timestamp ties. Optional 7th/8th args: method (only `last`) and a non-negative staleness interval after which the sample is NULL. Invalid start/end/step/method/staleness raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_curve_bootstrap` | `fin_curve_bootstrap('gold_curve', 'inst', 'maturity', 'rate', 'continuous')` | Alias of `fin_bootstrap_curve`. | Experimental, same zero-rate projection as `fin_bootstrap_curve`. |
| `fin_delta_to_grid` | `fin_delta_to_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')` | Difference between each grid sample and the previous grid sample. | DOUBLE `value`; NULL for the first grid point. Grid points are `start_ts + i * step` for every point not after `end_ts` (at most 10,000,000 points; month steps are anchored at `start_ts`). Each point samples the last observation at or before it via an ASOF join; rows with NULL timestamp or value are skipped, and duplicate timestamps keep the row with the largest `seq_col` (else the largest value). Optional named `asset_col := 'col'` builds one grid per asset (output keeps that column) and `seq_col := 'col'` breaks timestamp ties. Optional 7th/8th args: method (only `last`) and a non-negative staleness interval after which the sample is NULL. Invalid start/end/step/method/staleness raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_dollar_bars` | `fin_dollar_bars('gold_prices', 'ts', 'close', 'volume', 100000.0)` | Aggregate trades into dollar bars that close once accumulated abs(price) * volume reaches the threshold. | Rows are ordered by (`asset_col`, ts, `seq_col`, price, volume), so ties are deterministic; rows with NULL ts or price (or NULL volume for volume-based bars) are skipped. AFML reset-accumulator convention (Lopez de Prado 2018, ch. 2.3): the bar closes on the first row whose running total reaches the threshold (relative tolerance 1e-12) and the next bar restarts at zero, so overshoot does not carry over. Returns [asset_col,] `bar_id` (0-based per asset), `start_ts`, `end_ts`, `open`, `high`, `low`, `close`, `volume`, `vwap`, `ticks`; the last bar of each asset may be incomplete. Volume must be finite and non-negative and the threshold positive, else an error. Named `asset_col`, `seq_col`. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_efficient_frontier` | `fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 25)` | Diagnostic frontier grid of evenly spaced target returns between min(mu) and max(mu). | Experimental: volatility stays at the equal-weight portfolio volatility, not an optimized frontier. `points` (BIGINT, default 25) must be 1 to 100000; rows are generated lazily. NULL or non-finite inputs raise an error. |
| `fin_factor_report` | `fin_factor_report('gold_returns', 'd', 'asset', 'factor', 'forward_return', 5)` | Cross-sectional factor diagnostics: per-date Pearson IC, Spearman rank IC, and top-minus-bottom quantile spread, averaged across dates. | One row: `ic` (mean per-date IC), `ic_std`, `ic_ir` (mean/std), `ic_tstat` (mean/(std/sqrt(n_dates))), `rank_ic` (average ranks for ties), `mean_return`, `quantile_spread` (ntile buckets per date ordered by factor then asset), `n_dates` (dates with a defined IC), `n_obs`. Rows with NULL or non-finite factor/return are skipped. `buckets` (BIGINT, default 5) must be 2 to 1000. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_fama_macbeth` | `fin_fama_macbeth('gold_returns', 'd', 'asset', 'forward_return', ['factor'], 1)` | Per-date cross-sectional regression of y on the first x column. | Experimental: uses only the first x column and has no second-stage inference or lag correction (`lags` is validated, not used). Returns `date`, `intercept`, `beta`, `r2`, `n` (BIGINT) grouped by the date argument. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_garch_fit` | `fin_garch_fit('gold_returns', 'r', 1, 1, 'normal')` | GARCH(1,1) parameter placeholder with the sample variance of the return column. | Experimental: omega, alpha, beta are fixed (1e-6, 0.05, 0.90), not fitted. Only p = 1, q = 1 and `normal` are accepted; other values raise an error. All parameter columns are DOUBLE. |
| `fin_hrp_weights` | `fin_hrp_weights([[0.04, 0.01], [0.01, 0.09]], ['AAA', 'BBB'], 'single')` | Hierarchical risk parity weight placeholder. | Experimental equal-weight fallback; no hierarchical clustering or risk allocation. NULL or non-square inputs raise an error. |
| `fin_imbalance_bars` | `fin_imbalance_bars('gold_prices', 'ts', 'close', 'volume', 1500.0, 'tick_rule')` | Fixed-threshold volume imbalance bars (AFML ch. 2.3.2): the bar closes once abs(sum of signed volume) reaches the threshold. | Rows are ordered by (`asset_col`, ts, `seq_col`, price, volume), so ties are deterministic; rows with NULL ts or price (or NULL volume for volume-based bars) are skipped. AFML reset-accumulator convention (Lopez de Prado 2018, ch. 2.3): the bar closes on the first row whose running total reaches the threshold (relative tolerance 1e-12) and the next bar restarts at zero, so overshoot does not carry over. Returns [asset_col,] `bar_id` (0-based per asset), `start_ts`, `end_ts`, `open`, `high`, `low`, `close`, `volume`, `vwap`, `ticks`; the last bar of each asset may be incomplete. Method `signed` (default) reads the volume column as signed (buy positive, sell negative); `tick_rule` signs non-negative volume by the tick rule (sign of the last non-zero price change, 0 before the first change). Extra `imbalance` column is the signed total at close; `volume` is traded (absolute) volume. The AFML expected-imbalance (EWMA) threshold is not implemented; pass a fixed threshold. Named `asset_col`, `seq_col`. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_last_to_grid` | `fin_last_to_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')` | Alias of `fin_resample_grid` (last observation at or before each grid point). | DOUBLE `value`. Grid points are `start_ts + i * step` for every point not after `end_ts` (at most 10,000,000 points; month steps are anchored at `start_ts`). Each point samples the last observation at or before it via an ASOF join; rows with NULL timestamp or value are skipped, and duplicate timestamps keep the row with the largest `seq_col` (else the largest value). Optional named `asset_col := 'col'` builds one grid per asset (output keeps that column) and `seq_col := 'col'` breaks timestamp ties. Optional 7th/8th args: method (only `last`) and a non-negative staleness interval after which the sample is NULL. Invalid start/end/step/method/staleness raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_normalize_ohlcv` | `fin_normalize_ohlcv('gold_prices', 'ts', 'open', 'high', 'low', 'close', 'volume')` | Project source OHLCV columns into canonical `ts`, `asset_id`, `open`, `high`, `low`, `close`, and `volume` fields. | Canonical columns first, then every other source column unchanged (consumed columns and names colliding with canonical names are dropped). No ORDER BY is applied; sort explicitly when needed. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_normalize_option_chain` | `fin_normalize_option_chain('gold_source_options', 'cp', 'underlying_px', 'strike_px', 'expiry_dt', 'valuation_dt', 'zero_rate', 'iv', 'q')` | Project source option columns into canonical option fields and an `option_spec` struct for BSM functions. | Canonical option fields plus `option_spec`, then every other source column unchanged. No ORDER BY is applied. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_normalize_returns` | `fin_normalize_returns('gold_returns', 'd', 'asset', 'r')` | Project source return columns into canonical `date`, `asset_id`, and `return_decimal` fields. | Canonical columns first, then every other source column unchanged. No ORDER BY is applied. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_option_chain` | `fin_option_chain('gold_options', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol', 'dividend_yield')` | Project option input rows and append model-prefixed BSM columns such as `model_price`, `model_delta`, and `model_implied_volatility`. | Preserve other source columns, including internal-helper names. Existing `model_price`, `model_delta`, `model_gamma`, `model_vega`, `model_theta`, `model_rho`, and `model_implied_volatility` columns are replaced by fresh calculations, with case-insensitive name matching; the input table is unchanged. |
| `fin_portfolio_optimize` | `fin_portfolio_optimize([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]], 'max_sharpe', 0.0, true, 0.0, 1.0, 0.12, 0.2, 1.0)` | Portfolio optimizer placeholder returning one weight per asset. | Experimental equal-weight fallback; the objective and constraints are not solved. NULL, non-finite, or non-square inputs raise an error. |
| `fin_portfolio_optimize_table` | `fin_portfolio_optimize_table('gold_returns', 'asset', 'd', 'r')` | Table-input optimizer placeholder returning one weight per distinct non-NULL asset. | Experimental equal-weight fallback; return history is not used. All four column names are validated against the source. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_portfolio_return_table` | `fin_portfolio_return_table('gold_weighted_returns', 'asset', 'weight', 'expected_return')` | Compute portfolio return sum(weight * return) directly from table-shaped asset, weight, and return columns, optionally per date. | One row (or one row per date when the optional 5th `date_col` is given, ordered by date) with `portfolio_return`, `weight_sum`, and `asset_count`. Duplicate assets (per date) raise an error; NULL assets are skipped. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_portfolio_variance_table` | `fin_portfolio_variance_table('gold_weighted_returns', 'asset', 'weight', 'gold_covariance', 'asset_i', 'asset_j', 'covariance')` | Compute portfolio variance w'Cw and volatility from table-shaped weights and pairwise covariance rows. | One row with `portfolio_variance` and `portfolio_volatility`. Upper- or lower-triangle covariance storage is mirrored; missing off-diagonal pairs count as zero; a missing diagonal for a non-zero weight or duplicate weights/pairs raise an error; empty weights give NULL. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_predict_linear_to_grid` | `fin_predict_linear_to_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute', INTERVAL '3 minutes', INTERVAL '1 minute')` | Prometheus-style `predict_linear`: at each grid point g, least-squares fit value = a + b * t over observations with ts in (g - lookback, g] and predict at g + horizon. | DOUBLE `value`; NULL with fewer than two observations or no time spread in the window. `lookback` must be positive; `horizon` (default 0) is converted to seconds with 30-day months. Grid, NULL, `asset_col`, and `seq_col` rules as for `fin_resample_grid`. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_rate_to_grid` | `fin_rate_to_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')` | Per-second rate of change between consecutive grid samples: (value - previous) / seconds between grid points. | DOUBLE `value`; NULL for the first grid point. No counter-reset handling. Grid points are `start_ts + i * step` for every point not after `end_ts` (at most 10,000,000 points; month steps are anchored at `start_ts`). Each point samples the last observation at or before it via an ASOF join; rows with NULL timestamp or value are skipped, and duplicate timestamps keep the row with the largest `seq_col` (else the largest value). Optional named `asset_col := 'col'` builds one grid per asset (output keeps that column) and `seq_col := 'col'` breaks timestamp ties. Optional 7th/8th args: method (only `last`) and a non-negative staleness interval after which the sample is NULL. Invalid start/end/step/method/staleness raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_rebalance_trades` | `fin_rebalance_trades('gold_current_weights', 'gold_target_weights', 'gold_asset_prices', 100000.0)` | Trades that move current weights to target weights at a portfolio value (default 1.0). | Rows per asset with `current_weight`, `target_weight`, price, `notional_delta`, `quantity_delta`. Columns default to `asset`, `weight`, `price`; override with named `asset_col`, `weight_col`, `price_col` (output keeps those names). Duplicate assets in any input raise an error; a NULL portfolio value raises an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_resample_grid` | `fin_resample_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute', 'last', INTERVAL '10 minutes')` | Resample values onto a regular timestamp grid using the last observation at or before each grid timestamp. | Table (`[asset_col,] ts, value DOUBLE`) ordered by asset and ts. Grid points are `start_ts + i * step` for every point not after `end_ts` (at most 10,000,000 points; month steps are anchored at `start_ts`). Each point samples the last observation at or before it via an ASOF join; rows with NULL timestamp or value are skipped, and duplicate timestamps keep the row with the largest `seq_col` (else the largest value). Optional named `asset_col := 'col'` builds one grid per asset (output keeps that column) and `seq_col := 'col'` breaks timestamp ties. Optional 7th/8th args: method (only `last`) and a non-negative staleness interval after which the sample is NULL. Invalid start/end/step/method/staleness raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_resets_to_grid` | `fin_resets_to_grid('gold_prices', 'ts', 'close', TIMESTAMP '2026-01-02 09:30:00', TIMESTAMP '2026-01-02 09:34:00', INTERVAL '1 minute')` | Flag whether each grid sample is lower than the previous grid sample (1.0 reset, 0.0 otherwise). | DOUBLE `value`; NULL for the first grid point or when either sample is NULL. Grid points are `start_ts + i * step` for every point not after `end_ts` (at most 10,000,000 points; month steps are anchored at `start_ts`). Each point samples the last observation at or before it via an ASOF join; rows with NULL timestamp or value are skipped, and duplicate timestamps keep the row with the largest `seq_col` (else the largest value). Optional named `asset_col := 'col'` builds one grid per asset (output keeps that column) and `seq_col := 'col'` breaks timestamp ties. Optional 7th/8th args: method (only `last`) and a non-negative staleness interval after which the sample is NULL. Invalid start/end/step/method/staleness raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_schema_template` | `fin_schema_template('ohlcv')` | Return the expected columns for a named finance schema template (`ohlcv`, `returns`, `option_chain`, `rates_curve`, `portfolio`). | Table with `schema_kind`, `column_name`, `logical_type`, `required`, `description`. Unknown or NULL kinds raise an error. |
| `fin_tick_bars` | `fin_tick_bars('gold_prices', 'ts', 'close', 2)` | Aggregate trades into tick bars of `ceil(threshold)` rows (default threshold 100). | Rows are ordered by (`asset_col`, ts, `seq_col`, price, volume), so ties are deterministic; rows with NULL ts or price (or NULL volume for volume-based bars) are skipped. AFML reset-accumulator convention (Lopez de Prado 2018, ch. 2.3): the bar closes on the first row whose running total reaches the threshold (relative tolerance 1e-12) and the next bar restarts at zero, so overshoot does not carry over. Returns [asset_col,] `bar_id` (0-based per asset), `start_ts`, `end_ts`, `open`, `high`, `low`, `close`, `volume`, `vwap`, `ticks`; the last bar of each asset may be incomplete. `volume` and `vwap` are NULL unless named `volume_col := 'col'` is given. Named `asset_col`, `seq_col`, `volume_col`. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_validate_schema` | `fin_validate_schema('gold_prices', 'ohlcv')` | Validate a table's columns against a schema template. | One row per template column: `expected_type`, `required`, `present`, `actual_type`, `compatible` (any numeric for DOUBLE, DATE or TIMESTAMP variants for temporal columns), `status` (`ok`, `missing`, `missing_optional`, `type_mismatch`), and `valid`. Names match case-insensitively. Unknown kinds or missing tables raise an error. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |
| `fin_volume_bars` | `fin_volume_bars('gold_prices', 'ts', 'close', 'volume', 1000.0)` | Aggregate trades into volume bars that close once accumulated volume reaches the threshold. | Rows are ordered by (`asset_col`, ts, `seq_col`, price, volume), so ties are deterministic; rows with NULL ts or price (or NULL volume for volume-based bars) are skipped. AFML reset-accumulator convention (Lopez de Prado 2018, ch. 2.3): the bar closes on the first row whose running total reaches the threshold (relative tolerance 1e-12) and the next bar restarts at zero, so overshoot does not carry over. Returns [asset_col,] `bar_id` (0-based per asset), `start_ts`, `end_ts`, `open`, `high`, `low`, `close`, `volume`, `vwap`, `ticks`; the last bar of each asset may be incomplete. Volume must be finite and non-negative and the threshold positive, else an error. Named `asset_col`, `seq_col`. Every `table_name` argument accepts a table, view, or CTE name, or a parenthesized query such as `'(FROM read_parquet(''t.parquet''))'`. |

### General Helpers

| Function | Usage | Purpose | Returns / Notes |
|---|---|---|---|
| `fin_adf` | `fin_adf(x, max_lag := 1, regression := 'c')` | Compute adf for SQL finance workflows. | NULL placeholder. |
| `fin_autocorr` | `fin_autocorr(x, lag := 1)` | Compute autocorr for SQL finance workflows. | Experimental contemporaneous self-correlation; lag is ignored. |
| `fin_bipower_variation` | `fin_bipower_variation(log_r ORDER BY observation_key)` | Estimate annualized bipower variation from adjacent absolute log-return products. | Order-dependent aggregate; defaults to 252 periods and returns `NULL` with fewer than two non-`NULL` returns. |
| `fin_cagr` | `fin_cagr(r, annualization := 252)` | Compute cagr for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_changes` | `fin_changes(x, ts)` | Count how many times consecutive non-NULL values differ when ordered by `ts` (Prometheus `changes`). | BIGINT; 0 for empty or single-row groups. NULL x or ts rows are skipped; equal `ts` values are ordered by x. Buffers the group's values. |
| `fin_crosscorr` | `fin_crosscorr(x, y, lag := 0)` | Compute crosscorr for SQL finance workflows. | Experimental contemporaneous Pearson correlation; lag is ignored. |
| `fin_delta` | `fin_delta(x, ts)` | Last minus first non-NULL value when ordered by `ts`. | DOUBLE; NULL for empty groups. Equal `ts` values are ordered by x (first takes the smallest, last the largest). |
| `fin_dot` | `fin_dot([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])` | Compute dot for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_dv01` | `fin_dv01(0.05, 0.04, 5.0, 2, 100.0)` | Compute dv01 for SQL finance workflows. | DOUBLE unless noted by DuckDB overloads. |
| `fin_ema` | `fin_ema(x, period := 20 ORDER BY ts)` | Compute an exponential moving average with alpha `2 / (period + 1)`. | `DOUBLE`; seeds with the first non-NULL observation, then applies the exponential recurrence. Default period 20; period must be a positive integer at most 2147483647 and constant within each group. Inputs must be finite. Empty or all-NULL input yields `NULL`; period 1 returns the latest value. Constant-size state supports aggregate `ORDER BY`, `FILTER`, and SQL windows; specify ordering for reproducible results. |
| `fin_ema_halflife` | `fin_ema_halflife(x, ts, halflife)` | Compute ema halflife for SQL finance workflows. | Experimental arithmetic-mean alias; timestamps and half-life are ignored. |
| `fin_ewma_vol` | `fin_ewma_vol(r, 0.94, 252.0 ORDER BY ts)` | Compute annualized exponentially weighted volatility from ordered returns. | `DOUBLE`; square root of the EWMA variance model, with the same defaults, seed, and parameter validation as `fin_ewma_variance`. Scaled state can return finite volatility even when variance exceeds DOUBLE range. Empty input or an unrepresentable volatility yields `NULL`. |
| `fin_exp_decay_avg` | `fin_exp_decay_avg(x, ts, halflife)` | Return the arithmetic mean of supplied rows. | Experimental alias; timestamps and half-life are ignored and no decay is applied. |
| `fin_exp_decay_count` | `fin_exp_decay_count(ts, halflife)` | Count non-NULL timestamps. | Experimental alias; half-life is ignored and no decay is applied. |
| `fin_exp_decay_max` | `fin_exp_decay_max(x, ts, halflife)` | Return the maximum supplied value. | Experimental alias; timestamps and half-life are ignored and no decay is applied. |
| `fin_exp_decay_sum` | `fin_exp_decay_sum(x, ts, halflife)` | Sum supplied values. | Experimental alias; timestamps and half-life are ignored and no decay is applied. |
| `fin_expected_shortfall` | `fin_expected_shortfall(r, confidence := 0.95, method := 'historical')` | Compute the positive mean loss beyond historical VaR. | Alias of historical `fin_cvar(..., loss_positive := true)`. |
| `fin_first_non_null` | `fin_first_non_null(x, ts)` | First non-NULL value when ordered by `ts`. | Type of x; equal `ts` values are ordered by x. |
| `fin_garman_klass_vol` | `fin_garman_klass_vol(open, high, low, close, annualization := 252)` | Compute garman klass vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_half_life_mean_reversion` | `fin_half_life_mean_reversion(x)` | Compute half life mean reversion for SQL finance workflows. | NULL placeholder. |
| `fin_hurst` | `fin_hurst(x)` | Compute hurst for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_last_non_null` | `fin_last_non_null(x, ts)` | Last non-NULL value when ordered by `ts`. | Type of x; equal `ts` values are ordered by x. |
| `fin_linear_trend` | `fin_linear_trend(y, x := NULL)` | Fit an explicit-axis ordinary least-squares trend for grouped SQL finance workflows. | `STRUCT(slope, intercept, r2, stderr)`, where `stderr` is the slope standard error (requires at least three valid pairs). Slope and its error have units of y per x. Omitted or all-NULL `x` preserves the compatibility fallback `slope/r2/stderr := NULL, intercept := avg(y)`, with no implicit row ordering. Explicit axes exclude NULL and non-finite `(y, x)` pairs. Fewer than two valid pairs or constant x returns NULL trend fields. Constant y with varying x follows DuckDB's `r2 = 1` convention. Near-perfect fits may have small nonzero standard errors from rounding. See the source-build example in `examples/linear_trend.sql`. |
| `fin_ljung_box` | `fin_ljung_box(x, lags := 10)` | Compute ljung box for SQL finance workflows. | NULL placeholder. |
| `fin_log_nav` | `fin_log_nav(r, initial_nav := 1.0)` | Compute log nav for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_nav` | `fin_nav(r, initial_nav := 1.0)` | Compute nav for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_nearest_psd` | `fin_nearest_psd([[1.0, 2.0], [2.0, 1.0]])` | Compute nearest psd for SQL finance workflows. | LIST. |
| `fin_parametric_var` | `fin_parametric_var(mean, vol, confidence := 0.95, horizon := 1.0, distribution := 'normal')` | Compute parametric var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_parkinson_vol` | `fin_parkinson_vol(high, low, annualization := 252)` | Compute parkinson vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_pct_change` | `fin_pct_change(x, ts)` | Last / first - 1 over non-NULL values ordered by `ts`. | DOUBLE; NULL when the first value is 0 or the group is empty. Ties as for `fin_delta`. |
| `fin_quantile_spread` | `fin_quantile_spread(factor, forward_return, 5)` | Compute the mean forward-return spread between the top and bottom factor buckets. | `DOUBLE`; default 5 buckets, each extreme bucket has `ceil(n / buckets)` observations. Boundary ties share remaining bucket slots equally, so tied factors have no arbitrary row-order preference. NULL or non-finite pairs are ignored. `buckets` must be an integer greater than one and constant within each group. Uses selection instead of a full sort; empty input or an unrepresentable spread yields `NULL`. |
| `fin_rank_ic` | `fin_rank_ic(factor, forward_return)` | Compute rank ic for SQL finance workflows. | Experimental Pearson correlation on raw values; no ranking. |
| `fin_rate` | `fin_rate(x, ts, unit := 'second')` | Average rate of change: (last - first) / elapsed time between the first and last non-NULL observations ordered by `ts`, per `unit`. | DOUBLE; units `millisecond`, `second`, `minute`, `hour`, `day`, `week` (plural accepted); other units raise an error. NULL when elapsed time is 0. `ts` may be DATE, TIMESTAMP, or TIMESTAMPTZ. |
| `fin_resets` | `fin_resets(x, ts)` | Count how many times a non-NULL value is lower than its predecessor when ordered by `ts` (Prometheus `resets`). | BIGINT; 0 for empty or single-row groups. Ties as for `fin_changes`. |
| `fin_rogers_satchell_vol` | `fin_rogers_satchell_vol(open, high, low, close, annualization := 252)` | Compute rogers satchell vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_var` | `fin_var(r, confidence := 0.95, method := 'historical', loss_positive := true)` | Compute var for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_version` | `fin_version()` | Return the loaded finance extension version string. | VARCHAR in `finance <version>` form for releases. |
| `fin_vol_of_vol` | `fin_vol_of_vol(vol, annualization := 252)` | Compute vol of vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |
| `fin_yang_zhang_vol` | `fin_yang_zhang_vol(open, high, low, close, annualization := 252)` | Compute yang zhang vol for SQL finance workflows. | Aggregate or scalar SQL macro result. |

## Trend precision with large absolute levels

For `fin_linear_trend`, subtract a group-specific origin from both axes before
fitting when absolute levels are large relative to their variation. The executable
source-build recipe `examples/linear_trend_centered.sql` filters finite pairs,
computes origins with window functions, and fits each group in a separate step.
Groups with no finite pairs are absent from that recipe's output.

The fit uses DOUBLE arithmetic. In a 101-point synthetic series with slope 2,
alternating quarter-unit noise, and both axes offset by `1e15`, the uncentered
slope standard error was `0.0008786840531774002`. Centering produced
`0.000861770574046724`, compared with the exact-arithmetic reference
`0.000861770574038108`. The uncentered relative error was about 1.96% on
DuckDB v1.5.5 and v1.6.0-dev11514. This is one reproducible case, not an error bound.

Keep both origins with the fit. Its intercept describes shifted coordinates:
`y_predicted = y_origin + trend.intercept + trend.slope * (x_new - x_origin)`.
Centering cannot recover precision lost when converting inputs to DOUBLE, and
does not eliminate residual-variance cancellation for nearly perfect fits.
For timestamp axes, prefer elapsed time in the units needed by the analysis.

## Testing

The reference surface is exercised by `make test`, which builds the extension, runs smoke SQL, loads `test/sql/gold_dataset.sql`, and evaluates `test/sql/gold_tests.sql`. The gold dataset is intentionally small and deterministic so expected values are easy to audit.

For model and unit conventions, see
[Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}). For workflow-oriented
examples, see [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}).
