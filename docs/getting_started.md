---
layout: default
title: Getting Started
description: Run first pricing and risk queries with DuckDB Finance.
permalink: /getting-started/
nav_order: 2
---

# Getting Started

<p class="lead">Run a first set of SQL-native pricing and risk queries with an already loadable
<code>finance</code> extension.</p>

## Before You Start

This tutorial assumes DuckDB can already load `finance`.

Use DuckDB's standard community extension flow:

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

When developing the extension locally, use the source-build path from a
repository checkout:

```sh
git clone https://github.com/duckdb/duckdb.git /path/to/duckdb
git clone https://github.com/leonardovida/duckdb-finance.git /path/to/duckdb-finance
cd /path/to/duckdb-finance
make debug DUCKDB_ROOT=/path/to/duckdb
```

For source builds, the repository Makefile handles unsigned local extension
loading for validation:

```sh
make smoke DUCKDB_ROOT=/path/to/duckdb
```

See [Installation]({{ '/installation/' | relative_url }}) for the practical
install and build paths.

## First Queries

Returns and risk:

```sql
SELECT
  fin_simple_return(105, 100) AS simple_return,
  fin_total_return(r) AS total_return,
  fin_volatility(r) AS volatility,
  fin_sharpe(r) AS sharpe
FROM (VALUES (0.01), (-0.02), (0.03)) AS t(r);
```

Expected shape: one row with `simple_return` near `0.05`, `total_return` near
`0.019494`, volatility near `0.3995`, and a positive Sharpe ratio.

Options and implied volatility:

```sql
SELECT
  fin_bsm_price(spec) AS price,
  (fin_bsm_greeks(spec)).delta AS delta,
  fin_bsm_implied_vol('call', 10.450583572185565, 100, 100, 1, 0.05) AS implied_vol
FROM (
  SELECT fin_option_spec('call', 100, 100, 1, 0.05, 0.20) AS spec
);
```

Expected shape: one row with price near `10.450584`, delta near `0.636831`,
and implied volatility near `0.20`.

Fixed income and cash flows:

```sql
SELECT
  fin_bond_price(0.05, 0.04, 5, 2, 100) AS bond_price,
  fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic') AS npv,
  fin_irr([-100.0, 60.0, 60.0]) AS irr;
```

Portfolio math:

```sql
SELECT fin_portfolio_sharpe(
  [0.5, 0.5],
  [0.1, 0.2],
  [[0.04, 0.01], [0.01, 0.09]],
  0.02
) AS sharpe;
```

Table functions:

```sql
SELECT *
FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');

SELECT *
FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]]);
```

## What To Read Next

- [Installation]({{ '/installation/' | relative_url }}) for community extension
  installs and local source builds.
- [Function Reference]({{ '/function-reference/' | relative_url }}) for every
  registered `fin_*` function.
- [Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}) for
  model boundaries, units, and risk aggregation conventions.
- [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}) for complete
  desk-style workflows.
- [Function Cookbook]({{ '/function-cookbook/' | relative_url }}) for task-based
  examples.
- [Best Practices]({{ '/best-practices/' | relative_url }}) for units,
  validation, and aggregation guidance.
