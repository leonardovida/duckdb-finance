---
layout: default
title: Performance Testing
description: Profiling and benchmark coverage for DuckDB Finance functions.
permalink: /performance-testing/
nav_order: 5
---

# Performance Testing

The extension keeps two layers of performance coverage:

1. `make perf` profiles the complete gold-test corpus with DuckDB JSON
   profiling enabled and preserves a separate profile for each statement. Because `scripts/check_function_tests.py` and
   `scripts/check_function_perf_tests.py` both verify that every registered
   `fin_*` function is referenced by `test/sql/gold_tests.sql`, this gives every
   function coverage in the profiled SQL corpus. These are static reference
   checks; constant folding and macro expansion can remove individual calls
   from a runtime plan. They do not prove numerical accuracy or throughput.
2. `examples/hot_path_benchmark.sql` contains heavier benchmark queries for the
   highest-volume model families, including option pricing and Greeks, binomial
   pricing, bond analytics, cash-flow solvers, curve helpers, portfolio math,
   returns/risk aggregates, and date/calendar helpers.

Run the full function-surface profile:

```sh
make perf DUCKDB_ROOT=/path/to/duckdb
```

By default the profile is written to:

```text
/tmp/duckdb-finance-profile.json.d/statement-NNNN.json
```

The directory also contains `statements.json`, mapping SQL statements to their
profile files. Statements for which DuckDB emits no profile have a `null` profile
entry. The final available query profile is also copied to
`/tmp/duckdb-finance-profile.json` for compatibility with existing consumers.
Use the individual files when comparing queries; the final profile alone does
not represent the whole suite.

Use `PERF_OUTPUT` to write somewhere else:

```sh
make perf DUCKDB_ROOT=/path/to/duckdb PERF_OUTPUT=/tmp/finance-profile.json
```

Run the focused hot-path benchmark from a checkout of this repository after
installing and loading the published extension:

```sql
INSTALL finance FROM community;
LOAD finance;
.read examples/hot_path_benchmark.sql
```

When developing from source, use the same source-built DuckDB and local
extension flow as the Makefile targets above. The `.read` path is relative to
the repository checkout where the DuckDB shell is running.

## Repeatable Release Benchmarks

Use `make benchmark` to build an optimized extension and run twenty-four
representative workloads. It defaults to one million observations, four DuckDB
threads, one warmup, and five measured repetitions per query. Solver and tree
workloads use smaller subsets. Setup and loading are excluded from query timings.
Results include the exact SQL, every timing, medians, and numerical outputs in
`/tmp/duckdb-finance-benchmark.json`.

```sh
make benchmark BENCH_SCALE=0.25 BENCH_REPEATS=5 BENCH_OUTPUT=/tmp/finance-bench.json
```

For controlled before/after comparisons use `scripts/benchmark_functions.py`
with the same DuckDB CLI and separately compiled extension builds. Pass
`--baseline` with the earlier JSON file to check numerical outputs and calculate
speedups. Query text, scale, and thread count must match. `--case` selects one
workload; it can be repeated. Warmups, repetitions, threads, and scale have
explicit overrides. Selecting a case creates only its required fixture tables.
`--profile-dir` collects an additional untimed JSON operator profile for each
selected case and checks that profiling preserves its result. The CLI's
millisecond timing resolution limits conclusions
about very short queries; increase workload size for those cases.

Avoid concurrent builds or other benchmarks during timing. Use release builds
for throughput decisions and sanitizer builds for detecting memory and
undefined-behavior errors. Whole-query timings include DuckDB planning and
execution; sorting or SQL macro expansion may dominate the native function.

## Defaults and Numerical Behavior

| Family | Default | When to override |
|---|---|---|
| BSM/Black-76 IV | Starting volatility 0.2; absolute price tolerance `1e-8`; safeguarded solver. | Supply a quote-specific guess or a tolerance appropriate to price units. |
| Bachelier IV | Automatic price/time-scaled guess; absolute price tolerance `1e-8`; safeguarded solver. | Explicit guesses use forward-price units, which differ from decimal lognormal volatility. |
| IRR/XIRR | Guess 0.1, normalized cash flows, analytic derivative, bracket fallback. | Supply a guess to select a root when cash flows have multiple sign changes. |
| Regular bonds | Frequency 2, face 100; duration defaults to Macaulay years. | Match the coupon schedule; select `modified` for yield sensitivity. |
| Binomial | 200 steps, European exercise, CRR, dividend yield 0. | Specify American exercise when relevant and test step convergence for the instrument. |
| Curves | Linear interpolation and flat endpoint extrapolation. | Supply a model-specific curve externally for other interpolation/extrapolation rules. |
| Weekday offsets | Offset 1; `(date, offset)` uses weekdays automatically. | Explicit offsets accept `BIGINT`; the calendar overload remains weekday based. Exchange holidays require an external calendar. |
| Returns/risk | Decimal simple returns; annualization 252. | Use the actual observation frequency and explicitly select log returns when applicable. |
| Weighted statistics | Population variance (`ddof=0`); linear weighted quantile. | Use the required weight interpretation and explicit degrees of freedom. |
| Robust statistics | Exact 5th/95th percentile bounds; historical CVaR confidence 0.95. | Choose bounds/confidence for the application. Cutoffs use selection rather than full sorting; summation is scaled and compensated. |
| Ordered indicators | EMA period 20, seeded with the first observation; RSI period 14; EWMA lambda 0.94 and annualization 252. | Always define observation order; adjust periods and decay to sampling frequency. |
| IV percentile | Fraction of prior observations strictly below the latest IV, excluding that latest observation from the denominator. | Use an explicitly bounded SQL window for rolling history; ties do not count as below. |
| Quantile spread | Five buckets; boundary ties share slots equally. | Choose bucket count for the sample size. Selection avoids sorting the full sample. |

EMA and IV percentile now implement their named calculations; quantile spread
now handles boundary ties without arbitrary row-order preference. These results
can differ from earlier versions. The Bachelier
starting guess is now automatic; explicit guesses remain supported. Curve
inputs must have finite, strictly increasing knots and finite values. Invalid
scalar inputs and failed solves return `NULL`; aggregate validation errors
remain errors. Performance paths retain exact models rather than silently
substituting approximations. Experimental functions still require independent
model validation.

## CI Coverage

`make check` runs:

- `scripts/verify_aggregate_numerics.py`, which checks grouped and windowed
  aggregates against 80-digit Decimal references at one and four threads, and
  verifies controlled rejection of invalid inputs. `make ci-duckdb` also runs it.

- `scripts/check_function_docs.py`, which verifies every registered function has
  a Function Reference entry.
- `scripts/check_function_tests.py`, which verifies every registered function is
  referenced by the gold behavior tests.
- `scripts/check_function_perf_tests.py`, which verifies the profiled corpus
  used by `make perf` covers every registered function.
- `scripts/check_function_surface.py`, which writes and validates the
  machine-readable source/docs/gold/perf inventory for every registered
  function.
- The DuckDB-backed smoke and gold SQL suites.

The GitHub Pages workflow publishes the `docs/` site from `main`, so this page
and the generated function reference are deployed with the rest of the
documentation website.
