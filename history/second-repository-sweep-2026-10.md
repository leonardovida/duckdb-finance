# Second repository sweep — 2026-10-01

This sweep starts from released v0.2.21, commit
`4e39d6e6eb1c6151da1c7647ddb2db1068f703bf`, on branch
`codex/second-repository-sweep`. It revisits native scalar and aggregate
implementations, SQL macros, table generators, registration, tests, CI, and
documentation. The public surface remains 383 function names.

The changes repair further numerical failures and two named-model substitutes.
They do not establish that the entire repository is free of bugs or that every
function implements its advertised financial model. The experimental catalog
and remaining priorities below describe material limitations.

## Implemented improvements

| Function | Problem and resulting behavior |
|---|---|
| `fin_ema` | Previously returned `avg(x)` and ignored period. Now uses alpha `2/(period+1)`, seeds from the first non-NULL observation, and preserves the default period 20. Native aggregate overloads support ordering, filtering, and SQL windows. State is constant size; repeated constant inputs use a closed-form block update. |
| `fin_iv_percentile` | Previously returned min-max IV rank. Now computes the fraction of prior observations strictly below the latest IV, excluding that latest observation from the denominator. Ties contribute zero. Empty/singleton histories return NULL. Exact percentile requires retained history; use a bounded window for a rolling calculation. |
| `fin_iv_rank` | Retains the separate min-max calculation. Both IV aggregates reject non-finite or negative volatility observations instead of allowing NaN/infinity to contaminate state. |
| `fin_weighted_quantile` | Overflowing total weights and interpolation of opposite finite extremes could produce errors or infinity. Normalized compensated weights and stable interpolation repair those cases. Endpoint quantiles scan extrema instead of sorting. Constant samples skip sorting; equal values use increasing-weight order for deterministic interpolation knots. Constant method arguments are parsed once per chunk, and cumulative comparisons avoid a division per visited observation. |
| `fin_outlier_count` | Naive sums and squared deviations could overflow and incorrectly report no outliers. Normalized, compensated sample moments repair extreme-scale inputs. Independent accumulation lanes retain compensation; eligible flat chunks use bulk appends and validate constant thresholds once. Constant samples explicitly return zero, preventing rounding from inventing variance. |
| `fin_quantile_spread` | Full sorting dominated runtime; tied factors could assign different forward returns to buckets depending on row order. Selection finds the two bucket boundaries. Remaining slots at a boundary are shared equally across tied observations. Scaled compensated means avoid overflowing sums; an unrepresentable final spread returns NULL. |
| `fin_ewma_variance`, `fin_ewma_vol` | Squaring large returns could overflow while requested volatility remained finite. Scaled variance and zero-seeded affine tails preserve finite volatility and stable ordered merges. Dynamic rescaling and exponent-aware merges preserve late contributions after long decay histories. Unrepresentable outputs return NULL. Defaults remain lambda 0.94 and annualization 252. |
| `fin_sortino` | Overflowing or underflowing squared returns and cancellation in the return sum could corrupt a finite ratio. Compensated sums, separate return/downside scales, and exponent-aware final division repair those cases. Eligible ordinary flat chunks use compensated block updates; other inputs retain the general path. Defaults remain MAR 0 and annualization 252. |

These are intentional result changes. EMA and IV percentile no longer return
their old substitutes; quantile spread has deterministic proportional tie
handling; invalid IV and Sortino inputs are controlled errors. Consumers relying
on the old behavior should review those cases. Function reference rows document
units, defaults, seed and tie conventions, NULLs, validation, and ordering.

## Model status and usability

EMA and IV percentile leave the experimental catalog after focused numerical,
domain, ordering, window, and performance verification. Fifteen additional
partial implementations enter it: SMA, WMA, DEMA, TEMA, TRIMA, T3, KAMA, HMA,
regression level/intercept, TSF, and the four exponential-decay aggregates.
They currently ignore smoothing or decay parameters. The catalog now contains
58 entries, with reasons and alternatives. SMA computes a mean correctly over
an explicitly supplied SQL window, but its nominal period does not select that
window.

The usability checker now detects parameterized arithmetic-mean and decay
substitutes and protects specific documentation contracts for the repaired
aggregates. This makes these limitations visible rather than implying that a
callable name proves model accuracy. Additional simplified technical indicators
remain described on the experimental-functions page.

## Verification

- Full `make check` passes against DuckDB v1.5.5 on Linux, including the debug
  build's AddressSanitizer and UndefinedBehaviorSanitizer checks.
- The combined gold corpus now has 218 statements, with 68 added assertions.
  Coverage includes extrema, subnormal weights/returns, cancellation, long
  decays, NULLs, ties, filtering, named/default arguments, and rolling windows.
- New `scripts/verify_aggregate_numerics.py` checks 618 outputs against 80-digit
  Decimal references at one and four DuckDB threads. References use geometric
  weights and sorted/grouped definitions independently of native affine states
  and selection. Twenty-one invalid-input cases must fail with controlled errors.
- Numerical verification runs in both `make check` and `make ci-duckdb`.
  All 15 Python runner/benchmark/usability tests pass. Workflow lint and
  `git diff --check` pass.
- The optimized release build also passes the smoke/gold suites and all 618
  numerical reference comparisons and 21 invalid-input checks. All 24 release
  benchmark cases complete, including the newly implemented EMA and percentile.
- `make perf` completes the 218-statement corpus with per-statement profiles;
  all generated profiles and all 24 release operator profiles parse as JSON.

## Measured performance

These measurements compare the same GNU 14.2 `-O3` release build configuration
and DuckDB v1.5.5 executable against the saved v0.2.21 extension. The Linux
workspace exposes five AMD EPYC 9V74 CPU cores. Each query uses four DuckDB
threads, two warmups, and nine measured repetitions in one process. Builds and
other tests were stopped during benchmarking. Loading and data setup are
excluded; explicit ordering and SQL execution are included. Medians below are
milliseconds, with the CLI's millisecond timing resolution. These are local
observations, not universal speed guarantees.

| Query | Rows | Before (ms) | After (ms) | Interpretation |
|---|---:|---:|---:|---|
| Weighted quantile endpoints | 1,000,000 | 227 | 32 | 7.09× faster; removes sorting. |
| Quantile spread | 1,000,000 | 101 | 21 | 4.81× faster; selection replaces sorting. |
| Interior weighted quantile | 1,000,000 | 110 | 113 | Roughly unchanged. |
| Interior weighted quantile | 4,000,000 | 507 | 480 | Modest improvement in this run. |
| Outlier count | 1,000,000 | 6 | 10 | 4 ms added for scaled compensated moments. |
| Outlier count | 4,000,000 | 35 | 51 | 16 ms added; a measurable accuracy cost. |
| Default Sortino | 1,000,000 | 1 | 2 | At the timing resolution; larger input confirms overhead. |
| Default Sortino | 4,000,000 | 3 | 5 | 2 ms added for compensated/scaled state. |
| Ordered RSI/EWMA/drawdown | 1,000,000 | 196 | 198 | Roughly unchanged. |
| Ordered EWMA | 4,000,000 | 258 | 253 | Roughly unchanged; includes ordering. |

The accurate implementations therefore do not improve every function's
throughput. Bulk outlier appends and block Sortino accumulation reduce their
new overhead, while preserving the numerical checks. Further work should target
those paths without dropping the accuracy guarantees covered by the fixtures.

The full 24-case release run measures ordered EMA at 75 ms and exact IV
percentile at 56 ms for one million observations. Their prior substitutes
computed different models, so comparing their timings as speedups would be
misleading. Exact percentile also trades additional memory for correct results.

Raw comparisons are checked in as
[`second-sweep-before.json`](benchmarks/second-sweep-before.json),
[`second-sweep-after.json`](benchmarks/second-sweep-after.json),
[`second-sweep-followup-before.json`](benchmarks/second-sweep-followup-before.json),
and [`second-sweep-followup-after.json`](benchmarks/second-sweep-followup-after.json).
The complete release run is
[`second-sweep-full.json`](benchmarks/second-sweep-full.json). Operator profiles
are local validation artifacts; paths in those JSON files refer to this
workspace, not bundled profile files.

## Remaining priorities

| Priority | Evidence and next acceptance criteria |
|---|---|
| P1: named models | Optimizer/HRP functions still return equal weights; frontier uses constant equal-weight risk; bootstrap treats instrument quotes as zero rates; GARCH uses fixed parameters; Fama-MacBeth omits full second-stage inference. Promote each only after independent model fixtures and supported objective/instrument conventions. |
| P1: lagged/ranked/time-dependent analytics | Autocorrelation and cross-correlation ignore lag; rank correlations use raw Pearson values; half-life EMA and exponential-decay functions ignore timestamps. Further technical indicators use proxies. Define order, lookback, ties, and missing-data rules before implementing each model. |
| P1: financial conventions | Money-rounding mode and some metadata remain nominal; calendars are weekday based; regular bonds omit settlement/stub schedules. Implement supported choices or reject unsupported ones explicitly. |
| P1: broader numerical oracles | Weighted moments still return NULL when accumulated weights or moments overflow. Distribution continued fractions/series have fixed iteration budgets and need independent extreme-tail and large-degree grids. Scalar and portfolio functions need broader convention/domain coverage beyond name checks. |
| P2: aggregate memory and windows | Exact IV percentile now retains observations; weighted quantiles, outliers, and drawdown also retain histories. Whole-history percentile windows can do substantial repeated work. Profile large/skewed groups and consider a dedicated exact window algorithm before any explicit approximate alternative. |
| P2: remaining hot paths | Interior weighted quantiles still sort. Option-chain output can invert a price produced from a known volatility. Profile fused analytics and exact weighted selection while preserving mathematical and failure contracts. |
| P2: compatibility and performance governance | This pass runs locally on Linux/v1.5.5. Validate the supported platform/version matrix before release and retain representative benchmark artifacts in CI. Statement references and sanitizer success do not prove model accuracy or universal throughput. |
