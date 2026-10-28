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

### Covariance from incomplete return histories

[`examples/pairwise_covariance.sql`](https://github.com/leonardovida/duckdb-finance/blob/main/examples/pairwise_covariance.sql) builds
long-form sample covariance rows from dated returns. It preserves the asset
labels, emits both directions and the diagonal, and reports `n_obs` for every
pair. Pairs with fewer than two shared finite observations have `NULL`
covariance. This recipe needs the 0.3.0 `fin_cov_matrix(date, asset, return)`
signature. Run it in a shell with that source build loaded:

```sql
.bail on
.read examples/pairwise_covariance.sql
```

The sample compares pairwise deletion with complete-case deletion. For AAA/CCC,
pairwise covariance is `0.0001` across three dates; complete-case covariance is
`-0.0001` across the two dates shared by AAA, BBB, and CCC. Require one row per
`(date, asset_id)` before joining returns, since duplicates multiply observations.
Use the same return interval and decimal units for all assets.

The second half selects an explicit portfolio universe and retains only dates
where every selected asset has a finite return. `covariance_gate` reports four
candidate dates, two complete dates, and two discarded dates. NULL/non-finite
returns are counted and exclude the whole date. Missing assets remain in the
universe and block the calculation. Duplicate selected asset/date keys, NULL
selected dates, duplicate weights, and NULL/non-finite weights also block it.
These are temporary example views and tables. Adapt their names and inputs to
your schema; run against a consistent input snapshot.

The `covariance_returns` and `covariance_weights` input views cast asset IDs to
`VARCHAR`, matching the matrix and portfolio-table APIs. All joins, duplicate
checks, and label ordering use those strings: integer IDs `2` and `10` appear
in matrix order `['10', '2']`. Preserve the same label representation in both
sources; string `'02'` is distinct from integer `2` (label `'2'`). Check that
your IDs remain unique after casting. The recipe blocks duplicate normalized
weights and selected `(date, asset_id)` keys rather than combining them.

The gate checks **every** ordered covariance pair for two observations and a
finite value, verifies the matrix labels against the selected assets, and calls
`fin_matrix_is_psd` with relative tolerance `1e-10`. This is a numerical tolerance,
not an economic accuracy claim. The example exposes the pairwise matrix's
failed PSD check without repairing it. The complete-case matrix passes, and
`complete_portfolio_risk` returns variance `0.0000245`, matching direct sample
variance of the weighted complete-date returns. No unchecked weights reach the
table function. The risk view exposes `coverage_ready` separately and sets its
final `ready` only when the computed variance is also finite and nonnegative.
Blocked coverage or unusable computed risk returns `ready = false` and NULL
risk; even finite weights can overflow the calculation.

`fin_portfolio_variance_table` mirrors triangular input and treats missing
off-diagonal pairs as zero, so its own checks cannot replace this coverage gate.
PSD is sufficient here for a variance calculation, but does not imply positive
definiteness or optimizer readiness: the two-date, three-asset sample is
singular. Complete-case deletion can discard substantial history and bias an
estimate when missingness is informative. Select the policy deliberately. Use
same-interval decimal returns throughout; covariance and portfolio variance
are in squared return units, with no automatic annualization.

Run the executable recipe and its analytic/negative cases with
`make covariance-example DUCKDB_ROOT=/path/to/duckdb`. Both `make check` and
the native CI gate run this target.

The checks also replace the inputs with a synthetic four-asset, eight-date
integer-ID panel. Its full-rank covariance is independently derived from four
orthogonal sign series, and portfolio variance is `89/437500`, matching the
sample variance of its weighted returns. This verifies label alignment and
coverage beyond the singular introductory panel; it does not establish that
an arbitrary complete-case estimate is suitable for optimization.

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
