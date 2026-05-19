---
layout: default
title: Experimental Functions
description: Public functions that are documented and tested but not yet recommended for production use.
permalink: /experimental-functions/
nav_order: 7
wide: true
---

# Experimental Functions

These functions are still public so existing SQL examples and coverage can keep
tracking them, but they are not recommended for production workflows yet. Each
entry has an executable test and reference row, plus a reason for quarantine and
a safer replacement path.

Do not build new workflows around these names until their implementation is
promoted out of this page.

| Function | Why It Is Experimental | Prefer |
|---|---|---|
| `fin_adf` | Returns `NULL` until an Augmented Dickey-Fuller implementation is added. | Use explicit SQL regression diagnostics or keep this out of production workflows. |
| `fin_anova_oneway` | Returns `NULL` until one-way ANOVA statistic and p-value support is added. | Use grouped DuckDB aggregates for means, variances, and counts. |
| `fin_apo` | Returns a constant placeholder instead of exponential moving-average spread. | Compute fast and slow moving averages explicitly in SQL. |
| `fin_aroon` | Returns fixed placeholder values instead of lookback high/low positions. | Compute high/low lookback positions explicitly in SQL. |
| `fin_aroonosc` | Returns a constant placeholder instead of Aroon oscillator. | Compute Aroon up/down explicitly and subtract them. |
| `fin_black_litterman_returns` | Returns input market weights until full Black-Litterman posterior support is added. | Keep Black-Litterman calculations in reviewed SQL or an external model. |
| `fin_corr_matrix` | Returns a one-cell placeholder rather than a grouped correlation matrix. | Use pairwise DuckDB `corr()` grouped by asset pairs. |
| `fin_cov_matrix` | Returns a one-cell variance placeholder rather than a grouped covariance matrix. | Use pairwise DuckDB `covar_samp()` grouped by asset pairs. |
| `fin_cramers_v` | Returns `NULL` until categorical association support is added. | Build a contingency table and compute the statistic explicitly. |
| `fin_half_life_mean_reversion` | Returns `NULL` until lagged-regression half-life support is added. | Estimate lagged regression manually and compute `-ln(2) / slope`. |
| `fin_hurst` | Returns a fixed neutral value until a rescaled-range or variance-scaling implementation is added. | Use explicit log-log variance scaling in SQL. |
| `fin_ks_test` | Returns `NULL` until Kolmogorov-Smirnov statistic support is added. | Compare empirical distributions with explicit SQL quantiles. |
| `fin_linear_trend` | Returns `NULL` trend fields except intercept. | Use DuckDB `regr_slope`, `regr_intercept`, and `regr_r2` directly. |
| `fin_linearreg_slope` | Returns `NULL` until rolling/windowed regression slope support is added. | Use DuckDB `regr_slope` over the desired window. |
| `fin_ljung_box` | Returns `NULL` until autocorrelation test statistic support is added. | Compute lagged autocorrelations explicitly in SQL. |
| `fin_macd` | Returns zero MACD fields instead of exponential moving-average signals. | Compute fast, slow, and signal EMAs explicitly before using the result. |
| `fin_mann_whitney_u` | Returns `NULL` until rank-sum statistic support is added. | Rank observations with DuckDB window functions and aggregate manually. |
| `fin_max_sharpe_weights` | Returns equal weights until constrained optimizer support is added. | Use `fin_portfolio_optimize` for diagnostic table output or an external optimizer. |
| `fin_min_variance_weights` | Returns equal weights until closed-form or constrained optimizer support is added. | Use `fin_portfolio_optimize` for diagnostic table output or an external optimizer. |
| `fin_mutual_information` | Returns `NULL` until binned mutual-information support is added. | Bin inputs explicitly and aggregate probabilities in SQL. |
| `fin_newey_west_tstat` | Returns `NULL` until HAC standard-error support is added. | Compute regression and HAC errors in reviewed SQL or an external stats package. |
| `fin_ols` | Returns `NULL` model fields except intercept. | Use DuckDB `regr_*` aggregates for single-factor regressions. |
| `fin_ols_no_intercept` | Delegates to the placeholder OLS result. | Use explicit SQL linear algebra or DuckDB `regr_*` aggregates where applicable. |
| `fin_ppo` | Returns a constant placeholder instead of percentage price oscillator. | Compute fast and slow moving averages explicitly in SQL. |
| `fin_risk_parity_weights` | Returns equal weights until risk-budget optimizer support is added. | Use `fin_hrp_weights` for a deterministic table output or an external optimizer. |
| `fin_stability` | Returns a constant placeholder instead of log-equity trend stability. | Compute NAV and regression `r2` explicitly in SQL. |
| `fin_theils_u` | Returns `NULL` until categorical association support is added. | Build the contingency table and entropy terms explicitly. |
| `fin_ttest_1samp` | Returns a statistic and degrees of freedom but not a p-value. | Use the statistic as a diagnostic only or compute p-values externally. |
| `fin_ttest_2samp` | Returns a statistic and degrees of freedom but not a p-value. | Use the statistic as a diagnostic only or compute p-values externally. |
| `fin_welch_ttest` | Delegates to two-sample t-test output that does not include a p-value. | Use the statistic as a diagnostic only or compute p-values externally. |

## Promotion Rule

A function can leave this page only when it has a non-placeholder
implementation, focused gold coverage for valid and invalid inputs, reference
documentation with units and return shape, and performance coverage through
`make perf`.
