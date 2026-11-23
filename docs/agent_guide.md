---
layout: default
title: Agent Guide
description: Lookup commands, conventions, pitfalls, and checklists for agents that write DuckDB Finance SQL or change the extension.
permalink: /agent-guide/
nav_order: 3
---

# Agent Guide

This page is for automated agents. It is self-contained: read it top to bottom
once, then use the lookup commands instead of loading whole pages. The
[Function Reference]({{ '/function-reference/' | relative_url }}) is about
190 KB; do not read it in full.

A plain-text index of the documentation is published at
[`llms.txt`]({{ '/llms.txt' | relative_url }}).

## Facts

- The extension is called `finance`. Load it with
  `INSTALL finance FROM community; LOAD finance;`.
- It registers 383 functions, all named `fin_*`. It targets DuckDB v2.0.0.
- Functions are local and deterministic. Nothing fetches market data, curves,
  or calendars from a network.
- Check the loaded version with `SELECT fin_version();`.

## Look Up A Function

Pick the route that matches what you have access to. Each returns the same
facts: signature, purpose, return shape, and one runnable example.

**A DuckDB session with the extension loaded.** Ask the catalog:

```sql
-- One function: parameters, description, runnable example
SELECT function_type, parameters, description, examples
FROM duckdb_functions()
WHERE function_name = 'fin_bsm_price';

-- Search by keyword
SELECT DISTINCT function_name, function_type, description
FROM duckdb_functions()
WHERE function_name LIKE 'fin\_%' ESCAPE '\' AND description ILIKE '%drawdown%'
ORDER BY function_name;
```

**A repository checkout.** Query the catalog file. It has one JSON object per
line with `name`, `kind`, `category`, `usage`, `parameters`, `purpose`,
`returns`, `example`, and `source`:

```sh
rg '"name": "fin_bsm_price"' docs/function_catalog.jsonl
rg -i 'drawdown' docs/function_catalog.jsonl | jq -r '[.name, .kind, .purpose] | @tsv'
jq -r 'select(.category == "Options And Volatility Models") | .name' docs/function_catalog.jsonl
```

For the prose reference, each function is exactly one table row that starts
with its name, so one anchored search returns the full contract:

```sh
rg '^\| `fin_bsm_price` ' docs/function_reference.md
rg -A3 '^-- fin_bsm_price\b' docs/function_examples.sql
rg -n 'fin_bsm_price\(' test/sql/gold_tests.sql
```

**Only the website.** Fetch
[`function_catalog.jsonl`]({{ '/function_catalog.jsonl' | relative_url }}) and
filter it, or open the Function Reference and search for the row.

Read the source (`source` in the catalog names the registering file) only when
the reference row does not answer an edge-case question.

## Function Kinds

The catalog `kind` field and `duckdb_functions().function_type` tell you how a
function is called.

| Kind | Count | Call shape | Notes |
|---|---|---|---|
| `scalar` | 128 | `SELECT fin_bsm_price('call', 100, 100, 1, 0.05, 0.2)` | Native C++. One value per row. Optional trailing arguments are overloads. |
| `aggregate` | 111 | `SELECT fin_sharpe(r, 0.0, 252) FROM t` | Native C++. Also valid with `OVER (...)`. Optional trailing arguments are overloads. |
| `macro` | 115 | `SELECT fin_cagr(r, annualization := 12) FROM t` | SQL macro, scalar or aggregate. Has real default values. Only the aggregate macros listed in the reference run over a window frame. |
| `table` | 29 | `SELECT * FROM fin_calendar('NYSE', DATE '2026-01-01', DATE '2026-01-31')` | Used in `FROM`. Several take a table or view name and column names as strings. |

## Conventions That Apply Everywhere

| Topic | Rule |
|---|---|
| Rates, returns, volatility, dividend yield | Decimals. `0.05` is 5%, `0.20` is 20% vol. |
| Basis points | Only where the name says `bps` (`fin_bps`, `fin_from_bps`, `fin_spread_bps`). |
| Time to expiry `ttm` | Year fraction. The caller converts dates with `fin_yearfrac`. |
| Annualization | Observations per year, default 252. Pass 12 for monthly data, 52 for weekly. |
| Risk-free rate, MAR, thresholds in risk aggregates | Annual decimal, converted to a per-period rate as `(1 + rate)^(1/annualization) - 1`. |
| Currency | A label. No FX conversion happens unless you call an FX function. |
| Notional | Pricing functions return per-unit values. Multiply by quantity yourself. |
| Integer parameters | `BIGINT`; `INTEGER` columns bind. |
| Date parameters | `DATE`, `TIMESTAMP`, or `TIMESTAMPTZ`; the time of day is dropped. |
| Option kind | `'call'` or `'put'`. |
| Vectors and matrices | `DOUBLE[]` and `DOUBLE[][]`, for example `[[0.04, 0.01], [0.01, 0.09]]`. |

## Errors And NULLs

| Situation | Result |
|---|---|
| `NULL` argument to a scalar | `NULL` for that row. |
| Numeric domain failure in a scalar (non-positive volatility, rate at or below -100%, solver finds no root) | `NULL` for that row. The query continues. |
| Unknown configuration string (day count, compounding, option kind, method, calendar) | Error that starts with the function name, such as `fin_yearfrac: unknown day-count convention 'ACT/999'`. |
| Invalid constant parameter of an aggregate (confidence outside (0, 1), non-positive annualization, period out of range) | Error that starts with the function name. |
| NaN or infinite observation inside an aggregate group | `NULL` for that group. `fin_outlier_count` ignores such rows instead. |
| Too few observations (for example Sharpe of one row, an indicator before its warm-up) | `NULL`. |
| Order-dependent aggregate without an order, merged in parallel | Error `rows reached the aggregate in an undefined order`. |

To make bad inputs fail a pipeline, validate first with `fin_is_price`,
`fin_validate_ohlc`, `fin_validate_return`, or a `WHERE ... IS NULL` check on
the result.

## Pitfalls

1. **Percent instead of decimal.** `fin_bsm_price('call', 100, 100, 1, 5, 20)`
   prices with a 500% rate and 2000% vol. Write `0.05, 0.20`.
2. **Missing order.** Drawdowns, technical indicators, EWMA, GARCH, IV rank,
   Yang-Zhang, and bipower variation depend on row order. Write
   `fin_max_drawdown(r ORDER BY ts)` or use a window with `ORDER BY`. Add a
   tiebreaker when `ts` has duplicates.
3. **Expecting a series from a grouped call.** `fin_rsi(close, 14 ORDER BY ts)`
   returns the value at the last row. For one value per row use
   `OVER (PARTITION BY symbol ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`.
4. **Expecting the period to choose the window.** In a sliding frame the
   indicator is computed from the frame rows only, so recursive indicators
   (EMA, RSI, MACD, ATR, ADX) restart at the frame start. Use the running
   frame above for the standard series.
5. **Skipping a middle argument by name.** Native functions resolve optional
   arguments as overloads, so a named call must supply a prefix of the
   parameter list: `fin_volatility(r, 252, ddof := 0)` binds,
   `fin_volatility(r, ddof := 0)` does not. SQL macros have true defaults and
   accept any subset.
6. **Passing a relation where a name is expected.** Table functions such as
   `fin_normalize_returns`, `fin_tick_bars`, `fin_bootstrap_curve`, and
   `fin_portfolio_return_table` take the table or view name and its column
   names as strings: `fin_tick_bars('trades', 'ts', 'price', 100)`.
   Wrap a file scan or subquery in a view first.
7. **Windowing a multi-aggregate macro.** Macros that combine several
   aggregates (for example `fin_calmar`) cannot run with `OVER`. Use a native
   aggregate, or a correlated subquery over the frame rows.
8. **Struct results.** Functions such as `fin_bsm_greeks`, `fin_macd`, and
   `fin_bbands` return a `STRUCT`. Read a field with
   `(fin_bsm_greeks(spec)).delta`, or expand with `SELECT unnest(...)`.
9. **Summing incompatible risks.** Delta, DV01, and vega in different units or
   currencies do not add. Normalize to one unit before `sum`.
10. **Old lambda syntax.** DuckDB 2.0 rejects `x -> x + 1` by default. Write
    `lambda x: x + 1` in `list_transform` and similar calls around `fin_*`
    results.

## Choose A Function

| Task | Use |
|---|---|
| Return between two prices | `fin_simple_return`, `fin_log_return` |
| Compound a return series | `fin_total_return`, `fin_cagr` |
| Risk-adjusted performance | `fin_sharpe`, `fin_sortino`, `fin_calmar`, `fin_omega_ratio` |
| Volatility | `fin_volatility`, `fin_ewma_vol`, `fin_parkinson_vol`, `fin_yang_zhang_vol` |
| Drawdown | `fin_max_drawdown`, `fin_avg_drawdown`, `fin_ulcer_index` |
| Tail risk | `fin_var`, `fin_cvar` |
| Benchmark-relative | `fin_beta`, `fin_alpha`, `fin_tracking_error`, `fin_information_ratio` |
| Option price and Greeks | `fin_option_spec` with `fin_bsm_price`, `fin_bsm_greeks`; `fin_black76_price` for futures; `fin_bachelier_price` for normal vol; `fin_binomial_price` for American exercise |
| Implied volatility | `fin_bsm_implied_vol`, `fin_black76_implied_vol`, `fin_bachelier_implied_vol` |
| Discounting and cash flows | `fin_discount_factor`, `fin_npv`, `fin_irr`, `fin_xirr` |
| Bonds | `fin_bond_price`, `fin_bond_ytm`, `fin_bond_duration`, `fin_bond_convexity`, `fin_dv01` |
| Curve | `fin_bootstrap_curve`, `fin_interpolate_curve`, `fin_curve_zero_rate`, `fin_curve_discount_factor` |
| Day counts and calendars | `fin_yearfrac`, `fin_is_business_day`, `fin_next_business_day`, `fin_prev_business_day`, `fin_business_days_between`, `fin_calendar` |
| Portfolio math on lists | `fin_portfolio_return`, `fin_portfolio_vol`, `fin_portfolio_sharpe` |
| Portfolio weights | `fin_min_variance_weights`, `fin_max_sharpe_weights`, `fin_risk_parity_weights`, `fin_inverse_vol_weights`, `fin_efficient_frontier` |
| Technical indicators | `fin_sma`, `fin_ema`, `fin_rsi`, `fin_macd`, `fin_bbands`, `fin_atr`, `fin_adx` |
| Microstructure | `fin_mid`, `fin_spread_bps`, `fin_microprice`, `fin_vwap`, `fin_twap` |
| Bars from ticks | `fin_tick_bars`, `fin_volume_bars`, `fin_dollar_bars`, `fin_imbalance_bars` |
| Vendor-shaped input | `fin_normalize_returns`, `fin_normalize_ohlcv`, `fin_normalize_option_chain` |
| Input validation | `fin_is_price`, `fin_validate_ohlc`, `fin_validate_return` |

Confirm the exact signature with a lookup before writing the call. The
[Function Cookbook]({{ '/function-cookbook/' | relative_url }}) has a runnable
query for each row group.

## Answer Checklist For SQL Tasks

1. Look the function up. Do not write a signature from memory.
2. Write a query that runs after `LOAD finance` with inline `VALUES` when the
   user gave no table.
3. State the units you assumed: decimal rates, year-fraction `ttm`,
   annualization, per-unit notional.
4. Run it when a DuckDB session is available. Without one, copy the shape of
   the catalog `example`.
5. Do not invent market data, curves, holidays, or risk conventions. Ask, or
   put the assumption in the SQL as a named column.

Worked example:

```sql
SELECT
  fin_bsm_price(spec) AS price,
  (fin_bsm_greeks(spec)).delta AS delta,
  (fin_bsm_greeks(spec)).vega AS vega
FROM (SELECT fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS spec);
```

Assumptions: spot 100, strike 100, one year to expiry, 5% continuously
compounded rate, 20% annual volatility, no dividends, result per unit of
underlying. Expected: price near 10.4506, delta near 0.6368.

## Changing The Extension

Repository rules live in `AGENTS.md` at the repository root; read it before
editing. The short version:

| To change | Edit | Then |
|---|---|---|
| A native scalar | `src/scalar/*.inc`, registration in `src/scalar/register.inc` | Add gold tests |
| A native aggregate | `src/aggregate/*.inc`, registration in `src/aggregate/register*.inc` | Add gold tests, including a window case |
| A SQL macro | `src/macros/*.inc` | Add gold tests |
| A table function | `src/table_functions/*.inc` | Add gold tests |
| A function's documented contract | Its row in `docs/function_reference.md` and its block in `docs/function_examples.sql` | Regenerate the two generated files below |

Generated files, never edited by hand:

```sh
python3 scripts/generate_function_metadata.py   # src/function_metadata.inc
python3 scripts/generate_function_catalog.py    # docs/function_catalog.jsonl
```

Verify:

```sh
make ci-static                          # seconds, no DuckDB build needed
make check DUCKDB_ROOT=/path/to/duckdb  # full suite against a DuckDB v2.0.0 checkout
```

See the [Development Guide]({{ '/development/' | relative_url }}) for the build
and the test layout.
