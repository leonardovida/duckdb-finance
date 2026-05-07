---
layout: default
title: GS Quant-Inspired SQL Mapping
description: Local DuckDB Finance mappings for GS Quant-style pricing and risk workflows.
permalink: /gs-quant-mapping/
nav_order: 5
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
