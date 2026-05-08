---
layout: default
title: Getting Started
description: Install, load, and run the DuckDB Finance extension.
permalink: /getting-started/
nav_order: 2
---

# Getting Started

<p class="lead">Install <code>finance</code> like a DuckDB community extension, load it, and run
SQL-native pricing and risk queries directly in DuckDB.</p>

## Install And Load

After `finance` is published in the DuckDB Community Extensions repository, use
DuckDB's standard community extension flow:

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

Community extensions are built and signed by DuckDB's community extension CI, so
normal users should not need a local DuckDB source checkout or an unsigned local
extension binary.

Until the community package is published, build from source using the
[Development Guide]({{ '/development/' | relative_url }}).

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

Options and implied volatility:

```sql
SELECT
  fin_bsm_price('call', 100, 100, 1, 0.05, 0.20) AS price,
  (fin_bsm_greeks('call', 100, 100, 1, 0.05, 0.20)).delta AS delta,
  fin_bsm_implied_vol('call', 10.450583572185565, 100, 100, 1, 0.05) AS implied_vol;
```

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

GS Quant-inspired descriptors:

```sql
WITH option AS (
  SELECT fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20) AS inst
)
SELECT
  fin_gsq_eq_option_price(inst) AS price,
  fin_gsq_eq_delta(inst) AS delta,
  fin_gsq_eq_vega(inst) AS vega
FROM option;
```

## What To Read Next

- [Installation]({{ '/installation/' | relative_url }}) for the community
  extension publication path and local source builds.
- [Function Reference]({{ '/function-reference/' | relative_url }}) for every
  registered `fin_*` function.
- [Quant Developer Guide]({{ '/quant-developer-guide/' | relative_url }}) for
  model boundaries, units, and risk aggregation conventions.
- [Finance SQL Playbooks]({{ '/playbooks/' | relative_url }}) for complete
  desk-style workflows.
