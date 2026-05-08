# DuckDB Finance

[![CI](https://github.com/leonardovida/duckdb-finance/actions/workflows/ci.yml/badge.svg)](https://github.com/leonardovida/duckdb-finance/actions/workflows/ci.yml)

`finance` is a DuckDB extension for SQL-native quant finance analytics. It puts
common pricing, risk, return, portfolio, market microstructure, and validation
tools directly inside DuckDB so research and risk workflows can stay close to
the data.

The extension is designed for quant developers, desk strategists, risk
engineers, and finance users who want deterministic local analytics with
explicit assumptions instead of hidden service calls.

## What You Get

- Return and risk analytics: simple/log returns, annualization, volatility,
  Sharpe, Sortino, EWMA volatility, drawdowns, outlier counts, quantile spread,
  capture ratios, VaR/CVaR-style helpers, and data-quality reports.
- Option models: Black-Scholes-Merton, Black-76, Bachelier, binomial trees,
  digital, Asian geometric, barrier, SABR/SVI helpers, Greeks, higher-order
  Greeks, and implied-volatility solvers.
- Fixed income and cash flows: discount factors, forward rates, PV/FV,
  NPV/IRR/XIRR/MIRR, annuities, bond price/YTM/duration/convexity/DV01, curve
  interpolation, and curve bootstrapping.
- Portfolio analytics: vector and matrix helpers, portfolio return, variance,
  volatility, Sharpe, equal/inverse-vol weights, optimizer table functions, HRP
  fallback weights, efficient-frontier points, and rebalance trades.
- GS Quant-inspired local workflows: SQL descriptors for pricing contexts,
  instruments, measures, scenarios, and portfolios, backed by deterministic
  local helpers and golden fixtures.
- Technical analysis and microstructure: OHLC/OHLCV helpers, indicators,
  candlestick aliases, VWAP/TWAP, spreads, microprice, imbalance, impact
  proxies, and tick/volume/dollar/imbalance bars.
- Validation and schema helpers: finance-oriented checks for prices, returns,
  OHLC rows, conventions, calendars, sessions, and expected schemas.

All public functions live in the `fin_` namespace.

## Status

This repository is early-stage OSS. The native core is covered by deterministic
DuckDB SQL tests and documentation coverage checks, but the API should still be
treated as pre-1.0. Some broad catalog entries are pragmatic v1 aliases or
approximations; those are documented so stronger implementations can replace
them behind stable names.

The extension does not call Goldman Sachs, GS Quant, market-data vendors, or any
remote pricing service. GSQ-style names are local SQL analogues for familiar
pricing-and-risk workflows.

## Install

After `finance` is accepted into the DuckDB Community Extensions repository,
install and load it from DuckDB:

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

Community extensions are built and signed by DuckDB's community extension CI and
served from the community extension endpoint. If you need to disable community
extensions in a locked-down environment, set DuckDB's
`allow_community_extensions` option according to the DuckDB extension security
docs.

Until the community package is published, build from source for local
development.

## Build From Source

Clone DuckDB and this repository, then point `DUCKDB_ROOT` at the DuckDB
checkout:

```sh
git clone https://github.com/duckdb/duckdb.git /path/to/duckdb
git clone https://github.com/leonardovida/duckdb-finance.git /path/to/duckdb-finance
cd /path/to/duckdb-finance
```

Build the debug extension:

```sh
make debug DUCKDB_ROOT=/path/to/duckdb
```

The Makefile also supports an adjacent `../duckdb` checkout by default for
contributors who prefer that layout.

## Load A Local Build

Start DuckDB with unsigned local extensions enabled:

```sh
DUCKDB_ROOT=/path/to/duckdb
$DUCKDB_ROOT/build/debug/duckdb -unsigned
```

Load the built extension:

```sql
LOAD '/path/to/duckdb/build/debug/extension/finance/finance.duckdb_extension';
SELECT fin_version();
```

## Quick Start

Returns and portfolio analytics:

```sql
SELECT
  fin_simple_return(105.0, 100.0) AS simple_return,
  fin_log_return(105.0, 100.0) AS log_return;

SELECT
  fin_total_return(r) AS total_return,
  fin_volatility(r) AS volatility,
  fin_sharpe(r) AS sharpe,
  fin_max_drawdown(r) AS max_drawdown
FROM (VALUES (0.01), (-0.02), (0.03), (0.015)) AS t(r);

SELECT fin_portfolio_sharpe(
  [0.5, 0.5],
  [0.1, 0.2],
  [[0.04, 0.01], [0.01, 0.09]],
  0.02
) AS sharpe;
```

Options:

```sql
SELECT
  fin_bsm_price('call', 100.0, 100.0, 1.0, 0.05, 0.20) AS price,
  (fin_bsm_greeks('call', 100.0, 100.0, 1.0, 0.05, 0.20)).delta AS delta,
  fin_bsm_implied_vol('call', 10.450583572185565, 100.0, 100.0, 1.0, 0.05) AS iv;
```

Fixed income and cash flows:

```sql
SELECT
  fin_bond_price(0.05, 0.04, 5.0, 2.0, 100.0) AS bond_price,
  fin_npv([-100.0, 60.0, 60.0], [0.0, 1.0, 2.0], 0.10, 'periodic') AS npv;
```

GSQ-style local descriptors:

```sql
WITH option AS (
  SELECT fin_gsq_eq_option(
    'call', 'SPX', 100.0, 100.0, 1.0, 0.05, 0.20, 0.0, 10.0, 'USD'
  ) AS inst
)
SELECT
  fin_gsq_eq_option_price(inst) AS pv,
  fin_gsq_eq_delta(inst) AS delta,
  fin_gsq_eq_vega(inst) AS vega
FROM option;
```

Table functions:

```sql
CREATE OR REPLACE TEMP TABLE option_inputs AS
SELECT * FROM (VALUES
  ('call', 100.0, 100.0, 1.0, 0.05, 0.20),
  ('put', 100.0, 100.0, 1.0, 0.05, 0.20)
) AS t(kind, spot, strike, ttm, rate, vol);

SELECT *
FROM fin_option_chain('option_inputs', 'kind', 'spot', 'strike', 'ttm', 'rate', 'vol');
```

## Playbooks

The playbooks are practical SQL workflows that can be run after loading the
extension:

```sql
INSTALL finance FROM community;
LOAD finance;
.read examples/playbooks.sql
```

The examples assume finance-native units: decimal returns and rates, annualized
decimal vols, year-fraction option expiries, notional-scaled GSQ-style prices
and Greeks, and portfolio risk columns normalized before aggregation.

## Performance

The scalar hot paths are optimized for vectorized DuckDB execution and reusable
per-row model state. To profile the complete registered function surface through
the gold-test corpus:

```sh
make perf
```

To run the heavier local hot-path benchmark:

```sql
LOAD finance;
.read examples/hot_path_benchmark.sql
```

## Documentation

GitHub Pages source lives in `docs/` and is configured for:

- <https://leonardovida.github.io/duckdb-finance/>

- [Getting started](docs/getting_started.md): local build, load, and first
  pricing queries.
- [Installation](docs/installation.md): community extension installation,
  source builds, and publication checklist.
- [Function reference](docs/function_reference.md): usage and behavior notes for
  the `fin_*` function surface.
- [Performance testing](docs/performance_testing.md): full-surface profiling
  and focused hot-path benchmark workflow.
- [GS Quant-inspired SQL mapping](docs/gs_quant_mapping.md): local SQL
  equivalents for GS Quant-style pricing contexts, instruments, measures,
  scenarios, portfolios, and golden fixtures.
- [Quant developer guide](docs/quant_developer_guide.md): assumptions, units,
  model boundaries, risk conventions, and reconciliation guidance.
- [Finance SQL playbooks](docs/playbooks.md): complete runnable workflows and
  their intended use cases.
- [Extension overview](docs/index.md): API areas, stability notes, and build
  context.
- [Development guide](docs/development.md): build, test, extension layout, and
  contribution workflow.

Runnable examples live in `examples/`.

## Tests

Run the full local check:

```sh
make check
```

This runs documentation coverage, builds the extension, loads it in DuckDB, and
executes both smoke and deterministic gold tests.

Focused commands:

```sh
make smoke
make gold
make test
```

## Performance

The hot scalar paths are implemented in native C++ and written for DuckDB's
vectorized execution model. The option and portfolio paths avoid unnecessary
allocation where practical and reuse per-row model state for related values.

Run the focused hot-path benchmark after loading the extension:

```sql
LOAD finance;
.read examples/hot_path_benchmark.sql
```

## Design Principles

- Keep inputs explicit and caller-owned.
- Use normal DuckDB types rather than hidden external objects.
- Prefer deterministic local formulas over network-dependent behavior.
- Make units and model assumptions visible in SQL and docs.
- Cover edge cases with executable DuckDB tests.
- Keep golden datasets small, synthetic, and auditable.

## Repository Layout

```text
src/                         Native extension implementation
include/finance/             Extension registration headers
test/sql/                    Smoke tests, fixtures, and gold assertions
docs/                        User and developer documentation
examples/                    Runnable SQL playbooks and benchmarks
scripts/check_function_docs.py
community-extension/         Community extension metadata
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/development.md](docs/development.md) before opening a pull request.

The minimum bar for behavior changes is:

1. focused DuckDB SQL tests,
2. updated function documentation,
3. `make check` passing locally or a clear explanation of the blocker.

## License

MIT. See [LICENSE](LICENSE).
