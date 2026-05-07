# DuckDB Finance

`finance` is an out-of-tree DuckDB extension for SQL-native quant finance
workflows. It is aimed at quant developers, desk strategists, risk engineers,
and finance users who want deterministic analytics close to their data.

It provides functions with the `fin_` prefix for returns, risk metrics,
volatility, option pricing and Greeks, fixed income, cash flows, portfolio math,
technical indicators, market microstructure, time-series table functions, schema
helpers, finance-oriented validation, and GS Quant-inspired pricing/risk
descriptors.

This repository builds against the local DuckDB checkout at:

```sh
/Users/leov/workspace/motherduck/duckdb
```

## Build And Test

```sh
make debug
make smoke
make test
make check
```

`make smoke` and `make test` both build the extension, load the produced binary
with DuckDB's `-unsigned` flag, and run `test/sql/smoke_queries.sql`.
`make check` also verifies that every registered `fin_*` function is documented
in `docs/function_reference.md`.

Manual load:

```sql
LOAD '/Users/leov/workspace/motherduck/duckdb/build/debug/extension/finance/finance.duckdb_extension';
SELECT fin_version();
```

## Implementation Layout

- `src/scalar.cpp`: native scalar math, option models, fixed income, cash-flow,
  portfolio, matrix, validation, and calendar/session functions.
- `src/aggregate.cpp`: native aggregates that need custom state, including
  Sortino, EWMA variance/volatility, RSI, drawdown metrics, outlier counts,
  quantile spread, IV rank, and IV percentile.
- `src/macros.cpp`: SQL macro wrappers for aggregate-style analytics and
  compatibility aliases.
- `src/table_functions.cpp`: DuckDB table functions and bind-replace SQL table
  functions for option chains, curve bootstrapping, grids, bars, optimizers,
  factor reports, calendars, and rebalance trades.
- `test/sql/smoke_queries.sql`: executable DuckDB smoke coverage.
- `test/sql/gold_dataset.sql` and `test/sql/gold_tests.sql`: deterministic
  behavior coverage for the function surface.
- `docs/function_reference.md`: comprehensive function reference with usage,
  purpose, return notes, and examples.
- `docs/gs_quant_mapping.md`: GS Quant-inspired SQL mapping, model semantics,
  usage examples, and the Goldman-style golden dataset layout.
- `docs/quant_developer_guide.md`: model boundaries, units, sign conventions,
  risk aggregation guidance, and reconciliation notes for quant developers.
- `docs/playbooks.md` and `examples/playbooks.sql`: workflow-oriented examples
  for option desks, scenario PnL, rates, portfolios, factors, and microstructure.
- `examples/hot_path_benchmark.sql`: local CLI benchmark for option, bond,
  binomial-tree, and cash-flow hot paths.

## Examples

```sql
SELECT fin_simple_return(105, 100);
SELECT fin_total_return(r), fin_volatility(r), fin_sharpe(r)
FROM (VALUES (0.01), (-0.02), (0.03)) AS t(r);

SELECT fin_max_drawdown(r), fin_ulcer_index(r), fin_outlier_count(r, 'zscore', 3.0)
FROM (VALUES (0.01), (-0.02), (0.03), (0.015)) AS t(r);
```

```sql
SELECT fin_bsm_price('call', 100, 100, 1, 0.05, 0.2);
SELECT (fin_bsm_greeks('call', 100, 100, 1, 0.05, 0.2)).delta;
SELECT fin_bsm_implied_vol('call', 10.45058357, 100, 100, 1, 0.05);
```

```sql
SELECT fin_bond_price(0.05, 0.04, 5, 2, 100);
SELECT fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.1, 'periodic');
```

```sql
SELECT fin_portfolio_sharpe(
  [0.5, 0.5],
  [0.1, 0.2],
  [[0.04, 0.01], [0.01, 0.09]],
  0.02
);
```

```sql
SELECT *
FROM fin_option_chain('option_inputs', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol');

SELECT *
FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');

SELECT *
FROM fin_efficient_frontier([0.1, 0.2], [[0.04, 0.01], [0.01, 0.09]]);
```

```sql
WITH option AS (
  SELECT fin_gsq_eq_option('call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20) AS inst
)
SELECT
  fin_gsq_eq_option_price(inst),
  fin_gsq_eq_delta(inst),
  fin_gsq_eq_vega(inst)
FROM option;

SELECT
  portfolio_id,
  fin_gsq_portfolio_value(value, quantity),
  fin_gsq_portfolio_risk(risk, quantity)
FROM gsq_goldman_portfolio_cases
GROUP BY portfolio_id;
```

## Playbooks

The playbooks are practical SQL workflows that can be run after loading the
extension:

```sh
make debug
{
  printf "LOAD '/Users/leov/workspace/motherduck/duckdb/build/debug/extension/finance/finance.duckdb_extension';\n"
  cat examples/playbooks.sql
} | /Users/leov/workspace/motherduck/duckdb/build/debug/duckdb -unsigned
```

The examples assume finance-native units: decimal returns and rates, annualized
decimal vols, year-fraction option expiries, notional-scaled GSQ-style prices
and Greeks, and portfolio risk columns normalized before aggregation.

## Performance

The scalar hot paths are optimized for vectorized DuckDB execution and reusable
per-row model state. To run the local benchmark:

```sh
make debug
/Users/leov/workspace/motherduck/duckdb/build/debug/duckdb -unsigned
```

```sql
LOAD '/Users/leov/workspace/motherduck/duckdb/build/debug/extension/finance/finance.duckdb_extension';
.read examples/hot_path_benchmark.sql
```

## Documentation

GitHub Pages source lives in `docs/` and is configured for:

- <https://leonardovida.github.io/duckdb-finance/>

- [Function reference](docs/function_reference.md): usage and behavior notes for
  the `fin_*` function surface.
- [GS Quant-inspired SQL mapping](docs/gs_quant_mapping.md): local SQL
  equivalents for GS Quant-style pricing contexts, instruments, measures,
  scenarios, portfolios, and golden fixtures.
- [Quant developer guide](docs/quant_developer_guide.md): assumptions, units,
  model boundaries, risk conventions, and reconciliation guidance.
- [Finance SQL playbooks](docs/playbooks.md): complete runnable workflows and
  their intended use cases.
- [Extension overview](docs/index.md): API areas, stability notes, and build
  context.

## Notes

The extension intentionally uses standard DuckDB types (`DOUBLE`, `DATE`,
`TIMESTAMP`, `VARCHAR`, `STRUCT`, and `LIST`) rather than custom SQL logical
types. Some broad catalog entries are pragmatic v1 implementations or aliases;
the stable native core is concentrated in pricing, Greeks, rates, cash flows,
portfolio vector/matrix helpers, validation, and table-function plumbing.
