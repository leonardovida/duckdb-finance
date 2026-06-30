# DuckDB Finance

[![CI](https://github.com/leonardovida/duckdb-finance/actions/workflows/ci.yml/badge.svg)](https://github.com/leonardovida/duckdb-finance/actions/workflows/ci.yml)

`finance` brings quant finance analytics into DuckDB. It gives you SQL-native
pricing, risk, returns, portfolio math, market microstructure helpers, and
validation checks without sending data to a pricing service or hiding model
assumptions behind an SDK session.

It is built for quant developers, desk strategists, risk engineers, and finance
users who want deterministic local analytics close to the data. `finance` is
available from DuckDB Community Extensions and can be installed with DuckDB's
standard community extension flow:

```sql
INSTALL finance FROM community;
LOAD finance;
```

```sql
-- After loading finance:

SELECT
  fin_bsm_price(spec) AS price,
  (fin_bsm_greeks(spec)).delta AS delta,
  fin_bsm_implied_vol('call', 10.450583572185565, 100, 100, 1, 0.05) AS iv
FROM (
  SELECT fin_option_spec('call', 100, 100, 1, 0.05, 0.20) AS spec
);
```

## Why It Exists

Finance workflows often start in SQL but detour into notebooks, services, or
vendor libraries for basic analytics. DuckDB Finance keeps that work inside
DuckDB:

- Price options, bonds, swaps, forwards, cash flows, and scenario shocks.
- Calculate returns, volatility, drawdowns, Sharpe, Sortino, beta, VaR-style
  metrics, and data-quality checks.
- Aggregate portfolios with explicit caller-owned units and assumptions.
- Build table-function workflows for calendars, option chains, efficient
  frontiers, factor reports, bars, and grids.
- Keep analytics local, deterministic, and explicit when moving finance
  workflows into SQL.

All public functions live in the `fin_` namespace and use ordinary DuckDB types:
`DOUBLE`, `DATE`, `TIMESTAMP`, `VARCHAR`, `STRUCT`, `LIST`, and table results.

## 60 Seconds: How To Price And Risk An Option

Prerequisite: DuckDB with the `finance` extension loaded. Install it from DuckDB
Community Extensions or use a source build for local development.

1. Install and load the extension.

   ```sql
   INSTALL finance FROM community;
   LOAD finance;
   SELECT fin_version();
   ```

2. Price a call option and return its first-order Greeks.

   ```sql
   SELECT
     fin_bsm_price(spec) AS price,
     (fin_bsm_greeks(spec)).delta AS delta,
     (fin_bsm_greeks(spec)).vega AS vega
   FROM (
     SELECT fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS spec
   );
   ```

Expected result: scalar price and risk columns you can join, aggregate, test,
or write into a DuckDB table like any other SQL result.

## What Is Included

| Area | Examples |
|---|---|
| Returns and risk | Simple/log returns, annualization, volatility, Sharpe, Sortino, EWMA volatility, drawdowns, outliers, quantile spread, capture ratios, VaR/CVaR-style helpers, and data-quality reports. |
| Options and volatility | Black-Scholes-Merton, Black-76, Bachelier, binomial trees, digital, Asian geometric, barrier, SABR/SVI helpers, Greeks, higher-order Greeks, and implied-volatility solvers. |
| Fixed income and cash flows | Discount factors, forward rates, PV/FV, NPV/IRR/XIRR/MIRR, annuities, bond price/YTM/duration/convexity/DV01, curve interpolation, and curve bootstrapping. |
| Portfolio analytics | Portfolio return, variance, volatility, Sharpe, table-shaped portfolio return/variance helpers, optimizer table functions, HRP fallback weights, efficient-frontier points, and rebalance trades. |
| Technical analysis and microstructure | OHLC/OHLCV helpers, indicators, VWAP/TWAP, spreads, microprice, imbalance, impact proxies, and tick/volume/dollar/imbalance bars. |
| Validation and schemas | Checks for prices, returns, OHLC rows, conventions, calendars, sessions, expected schemas, and source-normalized returns/OHLCV/options. |

See the [Function Reference](docs/function_reference.md) for the complete
registered surface and [Data Source Compatibility](docs/data_source_compatibility.md)
for adapting CSV, Parquet, MotherDuck, or vendor-shaped tables into canonical
finance columns.

## Status And Boundaries

This repository is early-stage OSS and should be treated as pre-1.0. The native
core is covered by deterministic DuckDB SQL tests, function-reference coverage,
golden fixtures, and performance coverage checks, but users should pin a commit
for production research workflows.

The extension is local and deterministic:

- It does not call market-data vendors or remote pricing services.
- Some broad catalog entries are pragmatic v1 aliases or approximations. Those
  entries are documented and tested so stronger implementations can replace them
  behind stable names.

## Install

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

Community extensions are built and signed by DuckDB's community extension CI.
Locked-down environments can disable community extensions with DuckDB's
`allow_community_extensions` option.

For development, build from source:

```sh
git clone https://github.com/duckdb/duckdb.git /path/to/duckdb
git clone https://github.com/leonardovida/duckdb-finance.git /path/to/duckdb-finance
cd /path/to/duckdb-finance
make debug DUCKDB_ROOT=/path/to/duckdb
```

The Makefile also supports an adjacent `../duckdb` checkout by default.

## More Examples

Run the finance playbooks from this repository checkout after loading the
extension:

```sql
INSTALL finance FROM community;
LOAD finance;
.read examples/playbooks.sql
```

For source builds, use `make smoke DUCKDB_ROOT=/path/to/duckdb` or run the same
SQL file from a DuckDB shell that has loaded the local unsigned extension.

Useful starting points:

- [Getting Started](docs/getting_started.md): first pricing and risk queries.
- [Agent Guide](docs/agent_guide.md): routing guide for agents writing SQL or
  changing the extension.
- [Function Cookbook](docs/function_cookbook.md): task-based examples for
  choosing functions.
- [Finance SQL Playbooks](docs/playbooks.md): runnable desk-style workflows.
- [Best Practices](docs/best_practices.md): units, validation, aggregation, and
  reconciliation guidance.
- [Quant Developer Guide](docs/quant_developer_guide.md): units, model
  boundaries, risk conventions, and reconciliation guidance.

## Develop And Verify

Run the full local check:

```sh
make check DUCKDB_ROOT=/path/to/duckdb
```

For CI-style validation without the verbose smoke suite:

```sh
make ci DUCKDB_ROOT=/path/to/duckdb
```

For full-surface profiling:

```sh
make perf DUCKDB_ROOT=/path/to/duckdb
```

## Documentation

GitHub Pages source lives in `docs/` and is published at:

- <https://leonardovida.github.io/duckdb-finance/>

Main docs:

- [Agent Guide](docs/agent_guide.md)
- [Installation](docs/installation.md)
- [Function Cookbook](docs/function_cookbook.md)
- [Function Reference](docs/function_reference.md)
- [Best Practices](docs/best_practices.md)
- [Finance SQL Playbooks](docs/playbooks.md)
- [Performance Testing](docs/performance_testing.md)
- [Release](docs/release.md)
- [Development Guide](docs/development.md)
- [Contributing](CONTRIBUTING.md)

## Design Principles

- Keep inputs explicit and caller-owned.
- Use normal DuckDB types rather than hidden external objects.
- Prefer deterministic local formulas over network-dependent behavior.
- Make units and model assumptions visible in SQL and docs.
- Cover edge cases with executable DuckDB tests.
- Keep golden datasets small, synthetic, and auditable.

## License

MIT. See [LICENSE](LICENSE).
