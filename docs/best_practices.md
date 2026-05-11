---
layout: default
title: Best Practices
description: Practical conventions for reliable DuckDB Finance SQL.
permalink: /best-practices/
nav_order: 8
---

# Best Practices

DuckDB Finance is most useful when finance assumptions stay visible in SQL. Use
these practices for research, CI fixtures, desk sanity checks, and agent-written
queries.

## Keep Units Explicit

Use decimal units:

- `0.01` means 1% return.
- `0.20` means 20% annualized volatility.
- `0.0005` means 5 basis points when a function expects a decimal rate.
- `5.0` means 5 basis points only when a parameter name or docs say `_bps`.

Name derived columns with units when they are not obvious:

```sql
WITH desk_risk(trade_id, dv01_usd, scenario_pnl_usd, volatility_annualized) AS (
  VALUES ('SPX_ATM_CALL', 125.0, -3400.0, 0.20)
)
SELECT
  trade_id,
  dv01_usd,
  scenario_pnl_usd,
  volatility_annualized
FROM desk_risk;
```

## Normalize Before Aggregating

Portfolio functions and SQL sums do not make incompatible risks compatible.
Normalize first, then aggregate:

```sql
WITH desk_risk(portfolio_id, quantity, pv_usd, dv01_usd_per_bp) AS (
  VALUES
    ('CORE', 2.0, 10.45, 0.64),
    ('CORE', 1.0, 2500.00, -42.00)
),
normalized AS (
  SELECT
    portfolio_id,
    quantity,
    pv_usd,
    dv01_usd_per_bp
  FROM desk_risk
)
SELECT
  portfolio_id,
  sum(pv_usd * quantity) AS pv_usd,
  sum(dv01_usd_per_bp * quantity) AS dv01_usd_per_bp
FROM normalized
GROUP BY portfolio_id;
```

Do not add equity delta, FX delta, credit spread sensitivity, and IR DV01 into a
single total unless you have mapped them to the same scenario or PnL unit.

## Treat Models As Local Models

The extension prices from caller-supplied inputs. It does not calibrate curves,
fetch market data, select calendars, or apply desk-specific risk conventions.

Before using outputs in a serious workflow, reconcile:

- option PV and Greeks against the desk model for representative strikes and
  maturities;
- day-count and calendar conversion before `ttm` reaches pricing functions;
- sign conventions for pay/receive, long/short, and premium direction;
- vol, rate, spread, and notional units;
- portfolio aggregation units and FX conversion.

## Prefer Small Reproducible Examples

For docs, tests, and agent-generated answers:

- Use `VALUES` blocks for tiny examples.
- Avoid proprietary market data.
- Include expected result shape or key numbers for tutorial snippets.
- Use deterministic dates rather than `current_date` unless testing relative
  behavior.
- Keep fixture data in `test/sql/gold_dataset.sql` when it is reused.

## Validate At Boundaries

Use validation helpers before pricing or aggregation:

```sql
WITH quotes(open, high, low, close) AS (
  VALUES (100.0, 102.0, 99.0, 101.0)
)
SELECT
  fin_validate_ohlc(open, high, low, close) AS valid_ohlc,
  fin_is_price(close) AS valid_close
FROM quotes;
```

For schema-sensitive workflows, document the expected input columns and fail
early when data is missing or in the wrong unit.

## Use Compatibility Helpers Deliberately

Compatibility helpers are useful when porting an existing workflow, but core
finance functions are usually clearer for new SQL. Prefer the core function
unless the compatibility shape carries useful structure across queries.

See [Compatibility]({{ '/compatibility/' | relative_url }}) for the supported
boundary.

## Verify Changes

Run local validation before handing off a change:

```sh
python3 scripts/check_docs_site.py
python3 scripts/check_function_docs.py
python3 scripts/check_gs_quant_surface.py
make check DUCKDB_ROOT=/path/to/duckdb
```

When the change only edits prose, the Python docs checks catch navigation,
function-reference, and compatibility-manifest drift. When SQL examples change,
run those examples against the local extension too.
