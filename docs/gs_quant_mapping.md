---
layout: default
title: GS Quant-Inspired SQL Mapping
description: Local DuckDB Finance mappings for GS Quant-style pricing and risk workflows.
permalink: /gs-quant-mapping/
nav_order: 7
---

# GS Quant-Inspired SQL Mapping

This document describes the local DuckDB Finance surface inspired by Goldman
Sachs GS Quant pricing-and-risk workflows. It is written for quant developers
and finance users who care about model assumptions, units, reproducibility, and
clear boundaries between local analytics and official pricing infrastructure.
The implementation is intentionally local and deterministic: it does not call
Goldman Sachs APIs, does not require a `GsSession`, and does not attempt to
reproduce entitled Marquee market data.

The goal is to port the parts of the GS Quant model that fit a SQL extension:
instrument descriptors, risk-measure descriptors, pricing-context metadata,
scenario transformations, and portfolio aggregation.

For cross-cutting conventions, see the
[Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}).

## Source Shape

GS Quant organizes pricing and risk around these concepts:

| GS Quant concept | DuckDB Finance mapping | Notes |
|---|---|---|
| `Instrument` / `Priceable` objects | `fin_gsq_*` instrument descriptor structs | SQL structs preserve the instrument family, core economic fields, currency, and notional. |
| `PricingContext` and `HistoricalPricingContext` | `fin_gsq_pricing_context`, `fin_gsq_historical_pricing_context` | Contexts are metadata descriptors. They do not dispatch remote jobs. |
| Risk measures such as `DollarPrice`, `EqDelta`, `IRDelta`, `IRVega` | `fin_gsq_measure_*` descriptor structs | Measure descriptors are used for local dispatch where supported. |
| `MarketDataShockBasedScenario`, `CurveScenario`, `RollFwd`, `IndexCurveShift` | `fin_gsq_market_data_*`, `fin_gsq_curve_scenario`, `fin_gsq_roll_fwd`, `fin_gsq_index_curve_shift` | Scenarios are deterministic transforms on local scalar inputs. |
| `Portfolio` and portfolio risk aggregation | `fin_gsq_portfolio_item`, `fin_gsq_portfolio_value`, `fin_gsq_portfolio_risk` | Aggregates operate on rows already priced or risked locally. |

## Portable Timeseries Functions

GS Quant's local `gs_quant.timeseries` helpers are represented by `fin_*`
SQL names grouped along the same module boundaries. The source-name
compatibility layer covers the 87 `@plot_function` entries in these portable
modules: `algebra`, `analysis`, `datetime`, `econometrics`, `statistics`, and
`technicals`.

| GS Quant module | SQL representation |
|---|---|
| `timeseries.algebra` | Arithmetic, filtering, boolean, and weighted aggregation helpers such as `fin_add`, `fin_filter`, `fin_if`, and `fin_weighted_sum`. |
| `timeseries.analysis` | First/last, diff, compare, lag, smoothing, repeat, and consecutive helpers such as `fin_first`, `fin_last_value`, and `fin_smooth_outliers`. |
| `timeseries.datetime` | Date-part, alignment, interpolation, range, bucket, and countdown helpers such as `fin_day`, `fin_weekday`, `fin_date_range`, and `fin_day_countdown`. |
| `timeseries.econometrics` | Return, price-index, annualization, volatility, correlation, beta, and drawdown helpers such as `fin_returns`, `fin_prices`, `fin_correlation`, and `fin_max_drawdown`. |
| `timeseries.statistics` | Min/max/range, mean/median/mode, sum/product, standard deviation, covariance, percentile, winsorization, and generated-series helpers such as `fin_mean`, `fin_cov`, and `fin_generate_series`. |
| `timeseries.technicals` | Moving average, Bollinger bands, RSI, MACD, exponential volatility, seasonal adjustment, and trend helpers such as `fin_moving_average`, `fin_bollinger_bands`, and `fin_trend`. |

Some pandas-native series operations have v1 SQL placeholders or aggregate
aliases where DuckDB needs a table-function implementation for full index-aware
behavior. Those placeholders are documented and tested behind stable names.
Python-reserved GS Quant helper names with trailing underscores, such as
`abs_`, `filter_`, `and_`, `min_`, and `sum_`, are exposed both as clean SQL
names and exact trailing-underscore aliases.

The standalone `gs_quant.datetime` helpers are represented by scalar SQL names
as well: business-day helpers map to the local calendar functions, day-count
helpers map to `fin_yearfrac`, and point/time formatting helpers map to
`fin_relative_date_add`, `fin_point_sort_order`, `fin_to_zulu_string`, and
`fin_time_difference_as_string`.

`gs_quant.timeseries.measures_portfolios` is represented as local aggregate
portfolio analytics. Instead of retrieving Marquee reports by portfolio id, the
SQL functions accept already-loaded return, benchmark, risk, factor, PnL, or AUM
series and compute the corresponding local measure, for example
`fin_portfolio_sharpe_ratio`, `fin_portfolio_tracking_error`,
`fin_portfolio_factor_exposure`, and `fin_aum`.

The unprefixed report-measure names from `gs_quant.timeseries.measures_reports`
are represented the same way, for example `fin_factor_exposure`, `fin_pnl`,
`fin_drawdown_length`, `fin_modigliani_ratio`, and `fin_r_squared`.

Smaller market-data modules that primarily wrap Marquee datasets are represented
as local-data aliases. `timeseries.backtesting.basket_series` maps to
`fin_basket_series`, `timeseries.tca.covariance` maps to `fin_covariance`,
FX-vol measures map to names such as `fin_implied_volatility_fxvol`,
`fin_forward_point`, `fin_fwd_points`, `fin_vol_swap_strike`, and
`fin_spot_carry`, inflation measures map to `fin_inflation_swap_rate` and
`fin_inflation_swap_term`, and the xccy swap spread measure maps to
`fin_crosscurrency_swap_rate`.

Rates measures in `timeseries.measures_rates` are represented with the same
local-data convention. Native primitives continue to handle `fin_swap_rate`,
`fin_forward_rate`, and `fin_discount_factor`; remote dataset wrappers such as
`fin_swaption_vol`, `fin_swaption_premium`, `fin_basis_swap_spread`,
`fin_ois_xccy`, `fin_usd_ois`, and `fin_policy_rate_expectation` accept local
rate, spread, premium, annuity, or volatility series and return last-value
compatibility measures.

Vendor and model-data wrappers follow the same local-series pattern:
`fin_cognitive_credit_fundamentals`, `fin_fci`, the FactSet/GIR family, and
risk-model functions such as `fin_factor_zscore`, `fin_factor_covariance`,
`fin_factor_correlation`, and `fin_factor_returns_percentile` keep the GS Quant
function names while leaving data acquisition to the caller.

The remaining decorated functions in `timeseries.measures` are represented as
general local-measure aliases. This includes credit volatility/spread helpers,
equity index implied/realized correlation and volatility helpers, commodity and
energy curves, corporate fundamentals, ESG/rating/fair-value wrappers, thematic
model exposure/beta, retail-interest, and S3 concentration measures. These
functions preserve GS Quant names but do not fetch Marquee datasets.

## Instrument Families

The SQL descriptors cover a focused cross-asset set:

| Family | Constructor | Local pricing helper |
|---|---|---|
| Equity option | `fin_gsq_eq_option` | `fin_gsq_eq_option_price`, `fin_gsq_eq_delta`, `fin_gsq_eq_gamma`, `fin_gsq_eq_vega`, `fin_gsq_calc_eq_option` |
| FX forward | `fin_gsq_fx_forward` | `fin_gsq_fx_forward_value` |
| FX option | `fin_gsq_fx_option` | `fin_gsq_fx_option_price` |
| FX binary option | `fin_gsq_fx_binary` | `fin_gsq_fx_binary_price` |
| Interest-rate swap | `fin_gsq_ir_swap` | `fin_gsq_ir_swap_price` |
| Interest-rate swaption | `fin_gsq_ir_swaption` | `fin_gsq_ir_swaption_price` |
| Interest-rate cap/floor period | `fin_gsq_ir_cap_floor` | `fin_gsq_ir_cap_floor_price` |
| Inflation swap | `fin_gsq_inflation_swap` | `fin_gsq_inflation_swap_price` |
| Credit index | `fin_gsq_cd_index` | Descriptor only |
| Credit index option | `fin_gsq_cd_index_option` | `fin_gsq_cd_index_option_price` |

## Pricing Model Semantics

The helpers are small, explicit model equivalents:

| Helper | Model semantics |
|---|---|
| `fin_gsq_eq_option_price` | Black-Scholes-Merton with continuous dividend yield. |
| `fin_gsq_fx_forward_value` | Domestic-discounted FX forward value using domestic and foreign rates. |
| `fin_gsq_fx_option_price` | Garman-Kohlhagen form, implemented through BSM with foreign rate as dividend yield. |
| `fin_gsq_fx_binary_price` | Cash-or-nothing digital option with domestic discounting. |
| `fin_gsq_ir_swap_price` | Notional x annuity x fixed/par spread, signed by pay/receive direction. |
| `fin_gsq_ir_swaption_price` | Black-76 option on the forward swap rate. |
| `fin_gsq_ir_cap_floor_price` | Black-76 caplet/floorlet-style period value. |
| `fin_gsq_inflation_swap_price` | Notional x annuity x inflation/fixed spread. |
| `fin_gsq_cd_index_option_price` | Black-76 option on forward credit spread scaled by risky annuity. |

These are not a substitute for Goldman Sachs' entitled pricing services. They
are designed for reproducible local tests, strategy research, prototyping, and
SQL-native analytics where the market data and model assumptions are provided by
the caller.

## Quant Conventions

The GSQ-style layer follows finance-first conventions rather than application
framework conventions:

| Topic | Convention |
|---|---|
| PV | Price helpers return PV-like values scaled by notional where the descriptor has notional. |
| Greeks | Equity Greeks are notional-scaled. The underlying model determines the exact risk unit. |
| Rates and spreads | Inputs are decimal rates or spreads. Scenario shifts that end in `_bps` are in basis points. |
| Time | `ttm` is a year fraction supplied by the caller. Relative-date resolution is outside the SQL layer. |
| Pay/receive | Swap PV is signed from the fixed-leg perspective defined by `pay_receive`. |
| Scenarios | Scenario functions transform scalar marks. They do not rebuild dependency graphs, curves, or vol surfaces. |
| Portfolios | Aggregators sum supplied values. They do not infer netting sets, risk buckets, currencies, or hedging units. |

For desk or production use, pin these conventions in tests and reconcile them
against the official model stack before presenting numbers as official risk.

## Golden Dataset

`test/sql/gold_dataset.sql` contains GS Quant-inspired fixture tables prefixed
with `gsq_goldman_`. They act as the golden dataset for this surface.

| Table | Purpose |
|---|---|
| `gsq_goldman_eq_option_cases` | Equity option descriptor, price, delta, gamma, and vega cases. |
| `gsq_goldman_fx_forward_cases` | FX forward present-value cases. |
| `gsq_goldman_fx_option_cases` | FX vanilla option cases. |
| `gsq_goldman_fx_binary_cases` | FX digital option cases. |
| `gsq_goldman_ir_swap_cases` | Receive/pay fixed-rate swap PV cases. |
| `gsq_goldman_ir_swaption_cases` | Swaption Black-76 cases. |
| `gsq_goldman_ir_cap_floor_cases` | Caplet/floorlet Black-76 cases. |
| `gsq_goldman_inflation_swap_cases` | Inflation swap spread PV cases. |
| `gsq_goldman_cd_index_option_cases` | Credit index option spread-option cases. |
| `gsq_goldman_shock_cases` | Absolute, proportional, override, and standard-deviation shock transforms. |
| `gsq_goldman_curve_scenario_cases` | Curve parallel and slope scenario cases. |
| `gsq_goldman_portfolio_cases` | Portfolio line items with trade names similar to GS Quant examples. |
| `gsq_goldman_portfolio_expected` | Expected aggregate portfolio value and risk. |

The expected values are hard-coded constants. `test/sql/gold_tests.sql` prices
or transforms the fixtures through the public functions and compares against
those constants with explicit tolerances.

## Usage Examples

For end-to-end workflows, see [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}) and the
runnable companion file at
[examples/playbooks.sql]({{ site.github_url }}/blob/main/examples/playbooks.sql).

Create and price an equity option descriptor:

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

Dispatch from a measure descriptor:

```sql
SELECT fin_gsq_calc_eq_option(
  fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20),
  fin_gsq_measure_eq_delta('USD')
);
```

Apply a market-data shock:

```sql
SELECT fin_gsq_apply_shock(
  0.20,
  fin_gsq_market_data_shock('Absolute', 0.0001)
);
```

Aggregate a portfolio:

```sql
SELECT
  portfolio_id,
  fin_gsq_portfolio_value(value, quantity) AS portfolio_value,
  fin_gsq_portfolio_risk(risk, quantity) AS portfolio_risk
FROM gsq_goldman_portfolio_cases
GROUP BY portfolio_id;
```

## Verification

Run the complete extension verification:

```sh
make check
```

For only the deterministic golden dataset:

```sh
make gold
```

<!-- BEGIN GENERATED GS QUANT SURFACE SUMMARY -->
## Full Source-Surface Audit

The checked GS Quant AST surface contains 1641 public top-level functions. The generated manifest at [`gs_quant_surface.csv`](gs_quant_surface.csv) maps every source path and function to a DuckDB Finance canonical analogue, a `gs_*` source lookup alias, coverage status, category, and notes.

| Category | Native mappings | Generated descriptors |
|---|---:|---:|
| `api_query` | 0 | 49 |
| `backtests` | 0 | 14 |
| `content` | 0 | 21 |
| `datetime` | 12 | 0 |
| `json_encoding` | 0 | 73 |
| `risk` | 0 | 33 |
| `support` | 0 | 58 |
| `test_support` | 0 | 1037 |
| `timeseries` | 296 | 48 |

Generated descriptors are explicit local payload analogues for helpers whose Python implementation depends on GS Quant SDK runtime objects, authenticated Marquee calls, pandas index behavior, or test scaffolding. They keep the source surface discoverable and tested, accept caller-supplied local payloads, and preserve the rule that DuckDB Finance remains local and deterministic.
<!-- END GENERATED GS QUANT SURFACE SUMMARY -->
