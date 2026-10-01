# Performance and defaults — 2026-10-01

This pass builds on the previous repository sweep. It improves the native
algorithms and common-call usability while retaining the existing financial
models and established defaults. The baseline includes the earlier correctness
repairs; the speedups below are additional gains.

## Implemented changes

| Area | Improvement |
|---|---|
| European binomial pricing | Evaluate the terminal binomial distribution in O(steps), replacing O(steps²) backward induction. Expand relative probabilities from their mode and normalize to avoid underflow at the endpoints. |
| American binomial pricing | Retain backward induction for early exercise, hoist discounted probabilities outside the node loop, and use the European path for non-dividend CRR calls with non-negative rates. JR retains its own exercise behavior. |
| Bond duration and convexity | Compute positive geometric moments by block doubling in O(log coupon periods), avoiding unstable closed-form cancellation near zero yield. Billion-period zero-coupon inputs now complete without a billion-iteration loop. |
| IRR | Compute NPV and its analytic rate derivative in one pass instead of three NPV evaluations per Newton iteration. Retain cashflow normalization, explicit guesses, and the existing bracket fallback. |
| XIRR | Validate and normalize amounts and date offsets once per solve. Cache year fractions, evaluate discounts with one `log1p` per iteration, and compute the analytic derivative alongside NPV. |
| BSM IV | Cache time, discount factors, and log moneyness across iterations; update only volatility-dependent kernel fields. |
| Black-76/Bachelier IV | Replace pure bisection with safeguarded Newton steps and bisection fallback. Cache time, discount, and moneyness terms outside the loop. |
| Bachelier default guess | Derive the starting guess from price, discount, and time scale. The default adapts to small rate units and large currency units; callers can still supply a guess. Absolute price tolerance stays `1e-8`. |
| Matrix–vector multiplication | Read DuckDB's flattened list storage directly instead of copying the matrix and vector into temporary containers per row. Preserve dimensional and NULL checks; non-finite outputs return NULL. |
| Scalar list allocation | Avoid allocating per-row output-list containers for scalar sums/dots and avoid unused containers for constant results. |
| Robust means and historical CVaR | Select exact percentile cutoffs without fully sorting the observations. Use scaled, compensated summation to handle large finite values and reduce sensitivity to the new traversal order. |
| Weighted mean | Skip second-moment calculations when only the mean is requested. |
| RSI | Retain at most `period + 1` seed prices, then store an affine Wilder recurrence instead of every observation. Merge long tails in constant time after replaying their short seed prefixes. |
| Drawdown merge | Copy a populated state into an empty destination while preserving ownership, avoiding revalidation and recomputation of the entire history. Exact history replay is still required for non-empty destination states. |
| Curves | Use binary lookup for curves with more than eight knots and validate constant curves once per input chunk. Reject non-finite values, non-finite targets, duplicates, and unordered knots; interpolate without subtracting extreme opposite-sign values. The curve-spec validator reports these same numerical constraints. |
| Convention parsing | Fast paths handle canonical compounding and day-count strings while preserving alias and whitespace normalization. |
| Weekday usability | Add `(date, BIGINT offset)` overloads for next/previous business day. Omitted offsets remain 1, and weekday behavior needs no calendar argument. Guard the entire finite date range before offset arithmetic. Existing calendar overloads remain available. |
| Benchmark tooling | Add `make benchmark` and a reusable runner with warmups, repetitions, result comparison, selected workloads, and optional untimed JSON operator profiles. Selected workloads create only their dependent fixture tables. |

## Release measurements

Both extensions used GNU C++ 14.2.0, `-O3`, the same DuckDB `v1.5.5` CLI/libraries,
and the same Linux machine. The baseline native sources were preserved before
this pass and compiled separately. Each query had one warmup and seven measured
repetitions; the table reports median whole-query milliseconds. Loading and
fixture setup were excluded. No builds ran during timing.

Most workloads use one million observations. IV/IRR workloads use 50,000 solves;
binomial pricing uses 2,000 options at the default 200 steps. The runner checks
that the before/after numerical outputs agree within its documented comparison
tolerance. Independent correctness tests provide stronger model-specific checks.

| Workload | Before (ms) | After (ms) | Ratio |
|---|---:|---:|---:|
| Separate BSM price/delta/vega | 48 | 63 | 0.76x |
| Combined BSM analytics | 40 | 38 | 1.05x |
| BSM IV | 19 | 15 | 1.27x |
| Black-76 IV | 70 | 14 | 5.00x |
| Bachelier IV | 53 | 12 | 4.42x |
| European binomial, default steps | 41 | 5 | 8.20x |
| Bond duration/convexity, 600 periods | 482 | 70 | 6.89x |
| IRR | 16 | 15 | 1.07x |
| XIRR | 84 | 40 | 2.10x |
| Matrix–vector multiplication | 98 | 97 | 1.01x |
| Portfolio volatility/components | 204 | 182 | 1.12x |
| Exact robust means/CVaR | 273 | 54 | 5.06x |
| Weighted mean | 3 | 3 | 1.00x |
| Ordered RSI/EWMA/drawdown | 187 | 186 | 1.01x |
| Weekday offsets | 12 | 13 | 0.92x |
| Constant curve, 128 knots | 30 | 9 | 3.33x |

The separate BSM and weekday rows prompted a larger follow-up, using four
million observations, two warmups, and nine repetitions. Separate BSM calls
measured 222 → 219 ms, weighted mean 12 → 12 ms, and weekday offsets 42 → 39 ms.
The apparent slowdowns did not reproduce at that scale. Small differences in
unchanged or very short workloads remain inconclusive; the large algorithmic
gains are the strongest evidence. These are measured workloads, not universal
latency guarantees.

Raw timings, SQL, results, and source fingerprints are retained in
`benchmarks/performance-before.json`, `benchmarks/performance-after.json`, and
the corresponding `performance-followup-*.json` files. The timed snapshots
precede the final curve-validator alignment; that usability change was verified
in both sanitizer and release suites. Sixteen additional
untimed operator profiles were executed, parsed, and checked against the timed
results. DuckDB's buffer-memory metrics exclude native C++ vector allocations
and should not be used alone to assess aggregate memory consumption.

## Defaults and usage

- BSM and Black-76 IV keep a 20% starting volatility and `1e-8` absolute price
  tolerance. Bachelier now chooses a price-scaled starting guess automatically.
  Its volatility is in forward-price units rather than annualized decimal units.
- IRR/XIRR keep a 10% guess, which callers can override when selecting among
  multiple roots. Faster derivatives do not change the financial definition.
- Regular bonds keep semiannual frequency and face 100. Duration defaults to
  Macaulay years; explicitly request `modified` for yield sensitivity.
- Binomial pricing keeps European exercise, CRR, 200 steps, and zero dividend
  yield. American exercise and additional steps remain explicit choices.
- Curves keep linear interpolation and flat endpoint extrapolation. Invalid
  knot ordering now returns NULL instead of silently using an unsuitable lookup.
- RSI keeps period 14 and its existing behavior on short histories. Ordered
  functions still require aggregate `ORDER BY` or a window order.
- `fin_next_business_day(date, 5)` and `fin_prev_business_day(date, 5)` now work
  directly. They use weekdays; exchange holiday calendars are still unsupported.

The full default/convention table is in `docs/performance_testing.md`. Use
combined BSM analytics when requesting several outputs to share a pricing kernel.

## Validation and reproduction

- Full `make check` under AddressSanitizer/UndefinedBehaviorSanitizer and the
  complete release gold corpus.
- 54 additional SQL assertions, including 200 bond cashflow references, 30
  binomial cases with all eight-step paths enumerated, 200 known IRR/XIRR roots
  across cashflow scales, and 300 Black-76/Bachelier parameter cases.
- Independent recursive and closed-form Wilder references, moving windows over
  4,096 prices, and 45 direct RSI partition/merge checks against a full-history
  reference. Direct checks also verify the retained seed-size bound.
- Robust statistics checked against DuckDB sorted quantiles and filtered means,
  including grouped data and extreme finite magnitudes; curve lookup checked
  against known linear values across 5,000 targets.
- Thirteen Python runner/benchmark tests, workflow `actionlint`, and
  `git diff --check`.

Run `make benchmark` for release measurements. Use `BENCH_SCALE`,
`BENCH_REPEATS`, and `BENCH_OUTPUT` to adjust workload size, repetitions, and the
saved result. The runner's `--baseline` compares a preserved prior build;
`--profile-dir` saves additional untimed operator profiles. Use identical CLI,
scale, thread count, and SQL when comparing builds.

## Remaining opportunities

The largest remaining costs require separate contracts or more targeted
profiles: weighted quantiles and quantile spreads still sort; drawdown and
outlier counting still retain observations; sorting ordered aggregates can
dominate their native kernels. Specialized exact window implementations and
additional fused analytics could reduce those costs. Distribution inverses and
shared constant matrices deserve dedicated workload measurements before further
changes. Approximate quantiles, architecture-specific SIMD, or relaxed floating
point rules should be explicit options with independent error and compatibility
checks, rather than changes to established defaults.

The experimental-model catalog remains an accuracy limitation. Faster execution
does not validate those models; their remaining issues are documented in
`docs/experimental_functions.md` and the original sweep report.
