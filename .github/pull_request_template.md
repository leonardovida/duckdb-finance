## Summary

- 

## Type

- [ ] Function behavior
- [ ] Tests or fixtures
- [ ] Documentation or examples
- [ ] CI, release, or repository maintenance

## Checklist

- [ ] The change is scoped to one coherent behavior or documentation improvement.
- [ ] New or changed `fin_*` behavior has focused coverage in `test/sql/gold_tests.sql`.
- [ ] Fixtures in `test/sql/gold_dataset.sql` are synthetic, deterministic, and small.
- [ ] `docs/function_reference.md` is updated for callable-surface changes.
- [ ] Cookbook, playbook, or example docs are updated when a common workflow changes.
- [ ] Performance coverage is added or explicitly unnecessary.
- [ ] `make check DUCKDB_ROOT=/path/to/duckdb` passes, or the environment blocker is explained.

## Verification

```text

```
