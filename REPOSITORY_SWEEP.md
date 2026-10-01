# Repository sweep — 2026-10-01

The sweep found and repaired numerical, NULL-handling, aggregation, and test
infrastructure defects. It also found a larger accuracy limitation: several
public functions implement simplified proxies rather than their named models.
Passing tests cannot establish that the entire catalog is production accurate
or free of bugs. The remaining work below is necessary before making that claim.

The follow-up performance pass is documented in `PERFORMANCE_IMPROVEMENTS.md`.
It implements the geometric bond-risk calculations, analytic IRR derivatives,
selection-based robust cutoffs, and bounded RSI state proposed here, and adds
release benchmarks and clearer defaults.

## Scope and evidence

Reviewed the native scalar, aggregate, SQL macro, and table-function families,
registration surface, fixtures, validation scripts, build configuration,
workflows, examples, and public documentation. The source-derived checks cover
383 public function names. Coverage of a name does not prove every overload,
parameter combination, or financial convention.

The starting revision was `260c9b9`. Baseline and patched runtime checks used
DuckDB `v1.5.5` on Linux with the debug build's AddressSanitizer and
UndefinedBehaviorSanitizer instrumentation. Changes preserve public function
names; one private vector helper supports the repaired risk decomposition.

## Repairs implemented

| Area | Defect and resulting behavior |
|---|---|
| Native NULL inputs | Vector scaling, matrix operations, business-day offsets, and Black-76/Bachelier Greeks now check all argument validity before reading values. NULL inputs return NULL instead of consuming unspecified native data. |
| Non-finite output | Vector arithmetic and option analytics reject non-finite results. Struct-valued Greeks follow the scalar functions' finite-output contract. |
| Implied volatility | Solvers honor the supplied guess, recognize zero-volatility intrinsic prices, reject impossible prices/zero-time inversion, and return NULL when convergence fails. Bachelier bracketing supports normal volatility above the previous arbitrary cap. |
| BSM accuracy and speed | Put delta uses the opposite normal tail to preserve small negative deltas. IV price and vega share one pricing kernel per iteration. |
| Bond pricing | Replaced the coupon-period loop with a constant-time geometric sum using `log1p`/`expm1`; retained zero-yield and zero-coupon branches. Validated period counts before integer conversion. |
| Bond yield | Removed the silent high-yield bracket cutoff. A one-year zero-coupon bond with face 100 and price 0.01 now solves near 9999 rather than returning 128. Nonconverged yields return NULL. |
| Bond risk | Duration validates its kind and numerical inputs. Convexity avoids integer overflow in period and frequency products. |
| IRR/XIRR | Normalize cash flows before solving. For example, `[-1e-20, 2e-20]` now produces IRR 1 rather than accepting the initial guess 0.1. Wide date differences use 64-bit arithmetic. |
| Annuities and rate domains | Small-rate annuities use stable exponential differences; invalid payment timing, periodic discount bases, MIRR rates, and non-finite discount factors/times return NULL. |
| Dates | Year fractions reject infinite dates, use wide differences, and count complete ACT/ACT years directly. Weekday offsets skip full weeks and reject out-of-range results. |
| Drawdown | Track NAV relative to its running peak. Long growth histories no longer overflow absolute wealth and lose subsequent drawdowns. |
| Weighted moments | Avoid unnecessary intermediate products in updates/merges; initialize the first observation directly. Overflowing accumulated moments return NULL instead of a fabricated zero variance. |
| Degrees of freedom | Stable variance/stddev now use `count(x) - ddof` for finite non-negative ddof values, including values above one; exhausted denominators return NULL. |
| Return compounding | Empty, invalid, and non-finite inputs return NULL. A simple return of -1 produces total loss without evaluating `ln(0)`; returns below -1 are rejected. |
| Missing observations | Downside/upside deviation, semivariance, and hit/win/loss rates skip NULL observations. Beta, alpha, capture ratios, and VWAP consistently use complete pairs. |
| Risk contributions | Component volatility risk includes each asset's weight. Contributions sum to portfolio volatility and normalized contributions sum to one for the tested valid portfolios. The existing marginal-risk function remains `Sigma * w`; its variance-gradient convention is documented. |
| CI | DuckDB-backed checks now run for relevant pull requests, pushes to main, and merge-queue changes, with pinned defaults. Previously this workflow required manual dispatch. |
| SQL runner/profiling | Added dollar-quoted SQL handling, escaped SQL paths, and fail-fast extension loading. `make perf` retains per-statement JSON profiles and a statement manifest instead of overwriting one file for the entire suite. |
| Model status | Added 15 functions to the experimental catalog, bringing its total to 45. Reasons and usable alternatives are documented. These entries are warnings in the catalog, not runtime access restrictions. |

These repairs intentionally change results for invalid inputs, failed solves,
missing observations, non-default ddof, and incorrect risk decompositions.
Consumers relying on the previous results should review those cases.

## Validation

- Passed full `make check`: workflow YAML, documentation/site coverage, public function
  surface, gold/performance SQL references, usability, release metadata, Python
  runner tests, smoke SQL, and assertion-based gold SQL.
- Added 102 focused SQL assertions, including extreme magnitudes, empty and
  all-NULL groups, invalid domains, nonconvergence, and vectorized NULL inputs.
- Added deterministic property checks across 400 option parameter cases and
  2,870 calendar start/offset combinations, checking both forward and backward
  offsets against independently enumerated weekdays.
- Checked bond pricing against explicit discounted cash-flow sums, option
  parity/Greek finite differences/IV round trips, and portfolio decomposition
  identities. Round trips complement independently calculated references; they
  alone do not establish financial accuracy.
- Exercised 5,000-row mixed NULL vectors, 30,000-row weighted aggregation with
  large weights, and drawdown histories that overflow absolute NAV.
- Passed eight Python SQL-runner unit tests, workflow `actionlint`, and
  `git diff --check`.
- Executed `make perf`: 162 SQL statements, retaining and parsing 127 valid JSON
  query profiles. Setup statements do not all produce query profiles.

GitHub-hosted jobs and release/platform builds were not run during this sweep.
No deployed artifact or version change is included.

## Measured performance

Three timed repetitions per query, setup excluded, on the same DuckDB CLI and
machine. The baseline extension was compiled from the starting revision with
the same compiler, debug flags, sanitizer instrumentation, and DuckDB libraries.
Times below are medians; they are synthetic debug measurements, not production
latency guarantees.

| Workload | Baseline | Patched | Speedup |
|---|---:|---:|---:|
| 200,000 regular bond prices, 200 coupon periods | 562 ms | 358 ms | 1.57x |
| 1,000 weekday offsets, 1,000 business days each | 135 ms | 29 ms | 4.66x |
| 5,000 BSM implied-volatility inversions | 56 ms | 51 ms | 1.10x |

Reproduce after loading the corresponding baseline or patched extension. Run
each timed SELECT three times in a fresh process for each build:

```sql
CREATE TEMP TABLE bonds AS
SELECT .05 + (i % 100)::DOUBLE * .0001 AS coupon,
       .04 + (i % 100)::DOUBLE * .0001 AS ytm
FROM range(200000) t(i);
CREATE TEMP TABLE dates AS
SELECT DATE '2026-01-01' + (i % 365)::INTEGER AS d FROM range(1000) t(i);
CREATE TEMP TABLE options AS
SELECT 90 + (i % 21)::DOUBLE AS s,
       .1 + (i % 40)::DOUBLE / 100 AS v FROM range(5000) t(i);
CREATE TEMP TABLE quotes AS
SELECT *, fin_bsm_price('call', s, 100, 1, .05, v) AS p FROM options;
.timer on
SELECT fsum(fin_bond_price(coupon, ytm, 100, 2, 100)) FROM bonds;
SELECT sum(date_diff('day', d, fin_next_business_day(d, 'weekday', 1000))) FROM dates;
SELECT fsum(fin_bsm_implied_vol('call', p, s, 100, 1, .05)) FROM quotes;
```

## Remaining priorities

| Priority | Evidence and recommended improvement | Acceptance criteria |
|---|---|---|
| P1: named model accuracy | Optimizer/HRP return equal weights; frontier uses constant equal-weight risk; bootstrap treats quotes as zero rates; GARCH fit returns fixed parameters; Fama-MacBeth lacks second-stage inference. Implement each model or explicitly constrain its contract. See `config/experimental_functions.json` and `docs/experimental_functions.md`. | Independent reference datasets, invariants and failure-domain tests; documented supported instruments/objectives/conventions before promotion. |
| P1: time series and ranking | Autocorrelation/cross-correlation ignore lag; rank correlation/IC use raw Pearson correlation; EMA ignores exponential weighting; IV percentile uses min-max rank. Further technical indicators and decay functions use simplified proxies. | Explicit ordering/window semantics and independently calculated lagged, ranked, and recurrence-based expected values, including ties and missing observations. |
| P1: convention contracts | Several parameters remain nominal: money-rounding mode and some model/method metadata do not change computation. Calendars are weekday based; exchange holidays and settlement schedules need a defined contract. Regular coupon bonds do not model settlement or stubs. | Inventory every parameter/overload, implement supported behavior, and reject unsupported selections rather than silently substituting another model. |
| P1: stronger accuracy coverage | Name/reference checks and many smoke assertions only establish callability. The 383-name catalog is much broader than the independent numerical reference suite. | Versioned independent oracle fixtures for every promoted model; boundaries, NULL selection vectors, financial identities, and error bounds across parameter grids. |
| P2: aggregate memory | Drawdown, weighted quantiles, and outlier counting retain observations. RSI is now bounded by its seed period; robust means/CVaR use selection instead of full sorting. Large groups still need memory profiling. | Profile large/skewed groups; design exact mergeable states where possible and bounded-memory approximation only as an explicit separate contract. Preserve weighted-quantile/tie semantics when changing selection strategies. |
| P2: additional numerical speed | Bond risk uses logarithmic-time moments and IRR/XIRR use analytic derivatives. Option-chain analytics can still repeat kernels or invert a price generated from a known volatility. | Release profiles identify remaining hotspots; fused analytics and distribution-inverse refinements must preserve independent reference accuracy and failure behavior. |
| P2: performance governance | Gold-suite profiles include setup and constant-folded expressions; a SQL reference does not prove the native function executed. Debug timings do not establish release throughput. | Representative release workloads with warmups/repetitions, operator profiles, output checks, peak memory, and agreed regression budgets. Retain baselines in CI artifacts. |
| P2: compatibility | Local validation used one DuckDB version and Linux debug configuration. | Build/load/test the supported DuckDB and OS/architecture matrix, including release artifacts and community installation. |

The highest-value next step is model accuracy and contract coverage. Faster
execution of a proxy does not make that proxy a correct implementation of its
advertised financial model. Use the experimental catalog when selecting
functions for production and promote functions only after independent validation.
