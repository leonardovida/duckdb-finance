# AGENTS.md

This repository is an out-of-tree DuckDB extension named `finance`.
Work as a careful senior engineer: keep changes scoped, preserve existing user
work, and verify behavior with DuckDB after edits.

## Repository Layout

- `src/scalar.cpp`: native scalar functions for distributions, rates, options,
  cash flows, portfolio math, validation, and calendars.
- `src/aggregate.cpp`: native aggregate implementations that need custom state.
- `src/macros.cpp`: SQL macro registrations for finance-native analytics.
- `src/table_functions.cpp`: table functions and bind-replace SQL generators.
- `include/finance/finance_extension.hpp`: extension registration declarations.
- `test/sql/smoke_queries.sql`: broad smoke coverage.
- `test/sql/gold_dataset.sql`: deterministic gold fixture tables.
- `test/sql/gold_tests.sql`: assertion-based behavior coverage.
- `docs/function_reference.md`: source-derived user-facing function reference.

## Build And Test

The extension builds against a DuckDB checkout. Use `DUCKDB_ROOT` when the
checkout is not adjacent to this repository.

Use the repository `Makefile`:

```sh
make debug
make smoke
make gold
make test
make check
```

`make test` runs both smoke and gold SQL through:

```sh
make test DUCKDB_ROOT=/path/to/duckdb
```

`make check` runs documentation coverage first, then the full DuckDB-backed test
suite.

Known local warning: the DuckDB debug build may print non-fatal CMake/vcpkg or
Apple Silicon sanitizer warnings. Treat DuckDB SQL errors, assertion conversion
failures, crashes, and nonzero exits as failures.

## Development Rules

- Prefer source-derived changes over broad rewrites. Match the style already in
  the file you are editing.
- Use `rg` / `rg --files` for search.
- Use `apply_patch` for manual edits.
- Do not run destructive git commands or clean untracked files unless explicitly
  requested.
- Do not rely on `duckdb_functions()` for local introspection; this local DuckDB
  debug build has been observed to crash on that path.
- When adding or changing a `fin_*` function, add focused coverage in
  `test/sql/gold_tests.sql` and keep the fixture small in
  `test/sql/gold_dataset.sql`.
- If a function is a placeholder or pragmatic v1 alias, document that explicitly
  and test the placeholder behavior so future implementations can change behind
  a stable name.
- Avoid nested aggregate macros in `src/macros.cpp`. DuckDB rejects macro shapes
  such as `fsum(... first(x) ...)` or aggregate macros calling aggregate macros
  inside another aggregate expression. Inline formulas or split tests when
  necessary.

## Documentation

Update `docs/function_reference.md` when the callable surface changes. At a
minimum, every registered `fin_*` function should have a usage row, purpose, and
return/notes entry. Keep examples executable with the local DuckDB extension
where practical.

## Verification Checklist

Before handing off a code or documentation change:

```sh
make check
```

For function-surface changes, also check that every registered function is
documented and exercised by the gold tests.
