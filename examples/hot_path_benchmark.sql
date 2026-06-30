-- Hot-path benchmark for DuckDB Finance.
-- Run from this repository checkout after loading the extension. The standard
-- community extension load path is:
--   INSTALL finance FROM community;
--   LOAD finance;
--   .read examples/hot_path_benchmark.sql

.timer on

PRAGMA threads=4;

CREATE OR REPLACE TEMP TABLE bench_options AS
SELECT
  CASE WHEN i % 2 = 0 THEN 'call' ELSE 'put' END AS kind,
  80.0 + (i % 80)::DOUBLE AS spot,
  85.0 + (i % 70)::DOUBLE AS strike,
  0.05 + (i % 720)::DOUBLE / 365.0 AS ttm,
  0.01 + (i % 500)::DOUBLE / 100000.0 AS rate,
  0.10 + (i % 80)::DOUBLE / 1000.0 AS vol,
  (i % 50)::DOUBLE / 10000.0 AS dividend_yield
FROM range(1000000) AS r(i);

SELECT
  'bsm_price_delta_vega_1m' AS benchmark,
  fsum(fin_bsm_price(kind, spot, strike, ttm, rate, vol, dividend_yield)) AS price_sum,
  fsum(fin_bsm_delta(kind, spot, strike, ttm, rate, vol, dividend_yield)) AS delta_sum,
  fsum(fin_bsm_vega(kind, spot, strike, ttm, rate, vol, dividend_yield)) AS vega_sum
FROM bench_options;

SELECT
  'bsm_struct_greeks_1m' AS benchmark,
  fsum(greeks.delta) AS delta_sum,
  fsum(greeks.gamma) AS gamma_sum,
  fsum(greeks.vega) AS vega_sum
FROM (
  SELECT fin_bsm_greeks(kind, spot, strike, ttm, rate, vol, dividend_yield) AS greeks
  FROM bench_options
) g;

SELECT
  'binomial_50k_100_steps' AS benchmark,
  fsum(fin_binomial_price(kind, spot, strike, ttm, rate, vol, dividend_yield, 100, 'american', 'crr')) AS price_sum
FROM (
  SELECT * FROM bench_options LIMIT 50000
) b;

CREATE OR REPLACE TEMP TABLE bench_bonds AS
SELECT
  0.01 + (i % 500)::DOUBLE / 10000.0 AS coupon_rate,
  0.015 + (i % 500)::DOUBLE / 10000.0 AS ytm,
  1.0 + (i % 30)::DOUBLE AS maturity_years,
  2 AS frequency,
  100.0 AS face
FROM range(1000000) AS r(i);

SELECT
  'bond_price_duration_convexity_1m' AS benchmark,
  fsum(fin_bond_price(coupon_rate, ytm, maturity_years, frequency, face)) AS price_sum,
  fsum(fin_bond_duration(coupon_rate, ytm, maturity_years, frequency, face)) AS duration_sum,
  fsum(fin_bond_convexity(coupon_rate, ytm, maturity_years, frequency, face)) AS convexity_sum
FROM bench_bonds;

SELECT
  'cashflow_npv_500k' AS benchmark,
  fsum(fin_npv(0.08, cashflows)) AS npv_sum,
  fsum(fin_irr(cashflows)) AS irr_sum
FROM (
  SELECT [-100.0 + i * 0.0, 25.0, 30.0, 35.0, 40.0, 45.0]::DOUBLE[] AS cashflows
  FROM range(500000) AS r(i)
) c;

SELECT
  'cashflow_xirr_200k' AS benchmark,
  fsum(fin_xirr(cashflows, dates)) AS xirr_sum
FROM (
  SELECT
    [-100.0 + i * 0.0, 18.0, 24.0, 30.0, 36.0, 42.0]::DOUBLE[] AS cashflows,
    [DATE '2026-01-01', DATE '2026-04-01', DATE '2026-07-01', DATE '2026-10-01', DATE '2027-01-01', DATE '2027-04-01']::DATE[] AS dates
  FROM range(200000) AS r(i)
) x;

SELECT
  'curve_swap_1m' AS benchmark,
  fsum(fin_curve_zero_rate(maturities, rates, target)) AS zero_sum,
  fsum(fin_curve_discount_factor(maturities, rates, target)) AS df_sum,
  fsum(fin_swap_rate(maturities, discounts)) AS swap_sum
FROM (
  SELECT
    [0.25 + i * 0.0, 0.5, 1.0, 2.0, 5.0, 10.0]::DOUBLE[] AS maturities,
    [0.035, 0.037, 0.040, 0.043, 0.047, 0.050]::DOUBLE[] AS rates,
    [0.9913, 0.9817, 0.9608, 0.9176, 0.7900, 0.6065]::DOUBLE[] AS discounts,
    0.25 + (i % 40)::DOUBLE / 4.0 AS target
  FROM range(1000000) AS r(i)
) c;

SELECT
  'portfolio_return_var_sharpe_1m' AS benchmark,
  fsum(fin_portfolio_expected_return(weights, mu)) AS expected_sum,
  fsum(fin_portfolio_variance(weights, cov)) AS variance_sum,
  fsum(fin_portfolio_vol(weights, cov)) AS vol_sum,
  fsum(fin_portfolio_sharpe(weights, mu, cov, 0.02)) AS sharpe_sum
FROM (
  SELECT
    [0.25 + i * 0.0, 0.25, 0.25, 0.25]::DOUBLE[] AS weights,
    [0.08, 0.10, 0.12, 0.09]::DOUBLE[] AS mu,
    [[0.04, 0.01, 0.00, 0.00], [0.01, 0.05, 0.01, 0.00], [0.00, 0.01, 0.06, 0.01], [0.00, 0.00, 0.01, 0.03]]::DOUBLE[][] AS cov
  FROM range(1000000) AS r(i)
) p;

CREATE OR REPLACE TEMP TABLE bench_returns AS
SELECT
  (i % 100)::DOUBLE / 10000.0 - 0.004 AS r,
  (i % 120)::DOUBLE / 10000.0 - 0.005 AS benchmark_r
FROM range(1000000) AS r(i);

SELECT
  'returns_risk_aggregates_1m' AS benchmark,
  fin_volatility(r, 252) AS volatility,
  fin_sharpe(r, 0.0, 252) AS sharpe,
  fin_tracking_error(r, benchmark_r, 252) AS tracking_error,
  fin_information_ratio(r, benchmark_r, 252) AS information_ratio
FROM bench_returns;

CREATE OR REPLACE TEMP TABLE bench_dates AS
SELECT
  DATE '2026-01-01' + CAST(i % 365 AS INTEGER) AS start_date,
  DATE '2026-01-01' + CAST((i % 365) + 30 AS INTEGER) AS end_date
FROM range(1000000) AS r(i);

SELECT
  'date_calendar_1m' AS benchmark,
  fsum(fin_business_days_between(start_date, end_date, 'weekday')) AS business_days,
  fsum(fin_yearfrac(start_date, end_date, 'ACT/365F')) AS yearfrac_sum
FROM bench_dates;
