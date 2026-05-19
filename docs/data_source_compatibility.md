---
layout: default
title: Data Source Compatibility
description: How to adapt external market-data tables and files to DuckDB Finance canonical inputs.
permalink: /data-source-compatibility/
nav_order: 6
wide: true
---

# Data Source Compatibility

DuckDB Finance does not fetch vendor data or depend on a market-data session.
Instead, load or attach data with DuckDB first, then normalize source-specific
column names into canonical finance columns.

The normalization helpers accept table or view names plus source column names.
That makes them work with ordinary tables, MotherDuck tables, CSV scans, Parquet
scans, Iceberg-derived views, or any other relation DuckDB can query after you
wrap it in a view.

## Canonical Shapes

| Shape | Required Columns | Helper |
|---|---|---|
| Returns | `date`, `asset_id`, `return_decimal` | `fin_normalize_returns` |
| OHLCV | `ts`, `asset_id`, `open`, `high`, `low`, `close`, `volume` | `fin_normalize_ohlcv` |
| Options | `option_kind`, `underlying_price`, `strike_price`, `expiry_date`, `valuation_date`, `time_to_expiry_years`, `risk_free_rate`, `implied_volatility`, `dividend_yield`, `option_spec` | `fin_normalize_option_chain` |
| Portfolio weights | `asset_id`, `weight`, optional `expected_return` | `fin_portfolio_return_table` |
| Covariance rows | `asset_i`, `asset_j`, `covariance` | `fin_portfolio_variance_table` |

## File Or Vendor Views

Create a view over the source first. Keep source names visible in that view or
pass them directly into a normalization helper.

```sql
CREATE OR REPLACE VIEW raw_returns AS
SELECT *
FROM read_parquet('returns/*.parquet');

SELECT *
FROM fin_normalize_returns('raw_returns', 'trade_date', 'ticker', 'return_1d');
```

For option feeds with expiry dates, normalize once and reuse the generated
`option_spec` for pricing and Greeks:

```sql
CREATE OR REPLACE VIEW canonical_options AS
SELECT *
FROM fin_normalize_option_chain(
  'raw_options',
  'cp',
  'underlying_px',
  'strike_px',
  'expiry_dt',
  'valuation_dt',
  'zero_rate',
  'iv',
  'q'
);

SELECT
  option_kind,
  strike_price,
  expiry_date,
  fin_bsm_price(option_spec) AS model_price,
  (fin_bsm_greeks(option_spec)).delta AS model_delta
FROM canonical_options;
```

## Portfolio Tables

For real portfolios, prefer table-shaped functions over list literals:

```sql
SELECT *
FROM fin_portfolio_return_table('portfolio_inputs', 'asset_id', 'weight', 'expected_return');

SELECT *
FROM fin_portfolio_variance_table(
  'portfolio_inputs',
  'asset_id',
  'weight',
  'covariance_rows',
  'asset_i',
  'asset_j',
  'covariance'
);
```

Use list and matrix scalar functions for compact examples, small ad hoc
calculations, and unit tests. Use table-shaped functions for warehouse data,
joined source feeds, or anything with asset identifiers that need to survive
auditing.

## Naming Guidance

Prefer descriptive canonical names at ingestion boundaries:

- `asset_id` instead of `ticker`, `symbol`, or `secid`;
- `return_decimal` instead of `ret`, `r`, or percent-scaled values;
- `underlying_price` and `strike_price` instead of `spot` and `strike`;
- `time_to_expiry_years` instead of `ttm`;
- `risk_free_rate`, `implied_volatility`, and `dividend_yield` as annual decimal
  values.

Short names are fine inside small examples. Canonical names are better for
shared views, source adapters, and agent-generated SQL.
