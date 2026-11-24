# AGENTS.md

This repository is an out-of-tree DuckDB extension named `finance`. It
registers 383 SQL functions, all named `fin_*`, and targets DuckDB v2.0.0.
Work as a careful senior engineer: keep changes scoped, preserve existing user
work, and verify behavior with DuckDB after edits.

If you only need to write SQL against the extension, read
`docs/agent_guide.md` instead of this file.

## Find Things Fast

Look a function up before reading source. `docs/function_reference.md` is
about 190 KB; search it, do not read it whole.

```sh
rg '"name": "fin_sharpe"' docs/function_catalog.jsonl   # kind, parameters, contract, example, source file
rg '^\| `fin_sharpe` ' docs/function_reference.md       # the reference row (one row per function)
rg -A3 '^-- fin_sharpe\b' docs/function_examples.sql    # the runnable example
rg -n 'fin_sharpe\(' test/sql/gold_tests.sql            # behavior tests
rg -n '"fin_sharpe"' src                                # registration site
```

## Repository Layout

Each `src/*.cpp` translation unit includes the `.inc` files in the matching
subdirectory; edit the `.inc` file that owns a function family.

| Path | Contents |
|---|---|
| `src/finance_extension.cpp` | Extension entry point and the `FinanceRegisterFunction` helpers. |
| `src/scalar.cpp`, `src/scalar/*.inc` | Native scalar functions: distributions, rates, options, cash flows, market data, portfolio optimizers, validation, calendars. `register.inc` registers them; `common.inc` holds shared helpers. |
| `src/aggregate.cpp`, `src/aggregate/*.inc` | Native aggregates with custom state and window-frame support. `register*.inc` registers them. |
| `src/macros.cpp`, `src/macros/*.inc` | SQL macro registrations, one `{"fin_name", "(params) AS expression"}` entry each. |
| `src/table_functions.cpp`, `src/table_functions/*.inc` | Table functions and bind-replace SQL generators. |
| `src/portfolio_qp.inc` | Quadratic-programming solver for the optimizers. |
| `include/finance/finance_extension.hpp` | Extension registration declarations. |
| `test/sql/gold_dataset.sql` | Deterministic gold fixture tables. |
| `test/sql/gold_tests.sql` | Assertion-based behavior coverage. Every function must appear here. |
| `test/sql/smoke_queries.sql` | Broad smoke coverage. |
| `test/sql/smoke.test` | sqllogictest records, mainly expected errors. |
| `docs/function_reference.md` | User-facing function reference: one table row per function. |
| `docs/function_examples.sql` | One runnable example per function, plus native parameter names. |
| `docs/agent_guide.md`, `docs/llms.txt` | Entry points for agents that use the extension. |
| `scripts/` | Static checks, generators, and SQL runners used by the Makefile. |
| `history/` | Reports from earlier sweeps; not current documentation. |

Generated files. Do not edit them by hand; rerun the generator:

| File | Generator | Inputs |
|---|---|---|
| `src/function_metadata.inc` | `python3 scripts/generate_function_metadata.py` | Reference purpose cells, examples, parameter names |
| `docs/function_catalog.jsonl` | `python3 scripts/generate_function_catalog.py` | Reference rows, examples, macro parameter lists, registration sites |

## Build And Test

The extension builds against a DuckDB v2.0.0 checkout. The Makefile expects it
at `../duckdb`; set `DUCKDB_ROOT` when it is somewhere else.

```sh
git clone --depth 1 --branch v2.0.0 https://github.com/duckdb/duckdb.git ../duckdb
```

| Command | What it does | Needs a DuckDB build |
|---|---|---|
| `make ci-static` | Docs, coverage, metadata, catalog, and script unit checks. Runs in seconds. | No |
| `make debug` | Builds DuckDB and the extension with sanitizers. The first build takes a long time; `GEN=ninja` speeds it up. | Builds it |
| `make query SQL="SELECT fin_version()"` | Runs one statement against the built extension. | Yes |
| `make smoke` | Loads the extension and runs `test/sql/smoke_queries.sql`. | Yes |
| `make gold` | Runs the gold fixtures and assertions. | Yes |
| `make sqllogictest` | Runs `test/sql/*.test` through the CLI. | Yes |
| `make function-examples` | Runs every example and checks `duckdb_functions()` metadata. | Yes |
| `make test` | Smoke, sqllogictest, gold, function examples, covariance example. | Yes |
| `make check` | `ci-static` checks, then `make test`, then the aggregate numerics check. | Yes |

Every target accepts `DUCKDB_ROOT=/path/to/duckdb`.

Gold tests call the `assert_true`, `assert_eq`, `assert_near`, and
`assert_not_null` macros defined at the top of `test/sql/gold_tests.sql`. Each
takes the test name first. A passing assertion returns 1; a failing one raises
a conversion error that contains the test name. Treat DuckDB SQL errors,
assertion conversion failures, crashes, and nonzero exits as failures.

Known local warning: the DuckDB debug build may print non-fatal CMake/vcpkg or
Apple Silicon sanitizer warnings.

## Development Rules

- Prefer source-derived changes over broad rewrites. Match the style already in
  the file you are editing.
- Use `rg` / `rg --files` for search.
- Use `apply_patch` for manual edits.
- Do not run destructive git commands or clean untracked files unless explicitly
  requested.
- Register native functions through `FinanceRegisterFunction` so they get
  documented parameter names (DuckDB 2.0 binds `name := value` natively) and
  are marked fallible (DuckDB 2.0 turns an error thrown by a non-fallible
  function into an internal error).
- Change argument types in a scalar `resolve_types` callback, not in `bind`:
  DuckDB 2.0 casts scalar arguments before calling `bind`.
- Write SQL lambdas as `lambda x: ...`; DuckDB 2.0 rejects `x -> ...` by default.
- Scalar functions return `NULL` for a numeric domain failure and raise an
  error that starts with the function name for an unknown configuration
  string. Keep new functions consistent with their siblings.
- Avoid nested aggregate macros in `src/macros.cpp`. DuckDB rejects macro shapes
  such as `fsum(... first(x) ...)` or aggregate macros calling aggregate macros
  inside another aggregate expression. Inline formulas or split tests when
  necessary.
- If a function is a placeholder or pragmatic v1 alias, document that explicitly
  and test the placeholder behavior so future implementations can change behind
  a stable name.

## Adding Or Changing A Function

Do every step; `make ci-static` fails when one is missing.

1. Implement it in the `.inc` file of its family and register it under a
   `fin_*` name.
2. Add focused coverage in `test/sql/gold_tests.sql`: valid input, `NULL`,
   invalid input, and a window case for aggregates. Keep fixtures small in
   `test/sql/gold_dataset.sql`.
3. Add or update its row in `docs/function_reference.md`: usage, purpose, and
   return/notes (type, units, defaults, `NULL` and error behavior).
4. Add or update exactly one self-contained example in
   `docs/function_examples.sql` (inline `VALUES`, `range()`, literals, or CTEs;
   no fixture tables or files). Native functions list their parameter names in
   the example header.
5. Regenerate both generated files (see the table above). The purpose cell and
   the example become the `duckdb_functions()` description and example.
6. Update `docs/agent_guide.md` and `docs/llms.txt` when the function count or
   a convention they state changes.
7. Run `make check`.

## Verification Checklist

Before handing off a code or documentation change:

```sh
make check
```

For a documentation-only change, `make ci-static` is the minimum. For
function-surface changes, also check that every registered function is
documented and exercised by the gold tests.
