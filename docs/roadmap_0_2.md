---
layout: default
title: 0.2.0 Roadmap
description: Planned quality, documentation, and workflow priorities for the next release.
permalink: /roadmap-0-2/
nav_order: 12
---

# 0.2.0 Roadmap

`0.2.0` should make DuckDB Finance easier to trust from agents, notebooks, CI
fixtures, and desk-style SQL workflows. The release should prioritize
documented behavior, executable examples, and model boundaries over broad API
expansion.

## Release Goal

Ship a finance-first extension that a user or agent can install, inspect, and
apply without guessing:

- which function fits a task;
- what units and conventions the function expects;
- which examples are safe to run;
- which behaviors are approximations or explicitly scoped local models;
- how to validate a query before relying on the result.

## Non-Goals

`0.2.0` should not attempt to become a market data connector, calibration
service, trading system, portfolio book of record, or vendor-compatible clone.
The extension should stay local, deterministic, and explicit about inputs.

## Workstreams

### Community Package Availability

The extension is published through DuckDB Community Extensions. The remaining
release work is to keep the upstream catalog entry, install smoke, and docs in
sync with tagged releases.

Acceptance criteria:

- `finance` has an accepted entry under `duckdb/community-extensions`.
- The published package installs with `INSTALL finance FROM community;`.
- `.github/workflows/community-install-smoke.yml` runs the install smoke against
  the published catalog entry.
- Installation docs keep the community extension path first and the source build
  path scoped to development.

### Agent-Ready Function Selection

Agents need task-oriented routing before they need more functions.

Acceptance criteria:

- [Function Cookbook]({{ '/function-cookbook/' | relative_url }}) covers the
  top workflows with minimal runnable SQL.
- [Agent Guide]({{ '/agent-guide/' | relative_url }}) explains how to verify a
  selected function with docs, tests, and source.
- Function examples avoid hidden state, external data, and entitlement language.
- Common workflows link to the exact reference entries they depend on.

Candidate workflows:

- option price, Greeks, and implied-volatility checks;
- volatility and return diagnostics;
- fixed-income discount, duration, and curve-shift checks;
- portfolio weights, variance, and rebalance trades;
- OHLCV validation and technical indicators;
- market microstructure snapshots.

### Reference Quality

The function reference should stay complete, but `0.2.0` should improve the
highest-traffic entries first.

Acceptance criteria:

- Every function keeps usage, purpose, and return semantics.
- Options, rates, risk, portfolio, validation, and table-function sections name
  units and invalid-input behavior.
- Approximate or placeholder behavior is marked in plain language.
- Reference examples remain compact and executable after `LOAD finance`.

### Playbooks And Examples

Playbooks should demonstrate repeatable analysis, not isolated syntax.

Acceptance criteria:

- `examples/playbooks.sql` remains runnable from a repository checkout against a
  local source build.
- Each playbook has a short docs page explanation with expected result shape.
- Playbooks use synthetic data and avoid market-data implications.
- At least one playbook shows how to validate units before aggregating risk.

### Numerical Review

Before adding breadth, review correctness for core finance models.

Acceptance criteria:

- BSM, Black-76, Bachelier, implied-volatility, and Greeks tests include
  round-trip or sanity coverage.
- Rate, day-count, duration, convexity, DV01, IRR, and XIRR examples state
  conventions.
- Return and risk metrics document sample/population assumptions where relevant.
- Edge cases cover zero denominators, invalid dimensions, negative time,
  impossible prices, and NULL inputs.

### Performance And CI

The CI shape should stay fast without hiding behavior regressions.

Acceptance criteria:

- Static docs/test/perf coverage checks run on every PR.
- DuckDB-backed tests run for source, SQL, build, workflow, and release-sensitive
  changes.
- Docs-only PRs stay fast and explain skipped DuckDB builds.
- Release builds keep platform artifact coverage while relying on green `main`
  CI for expensive behavior tests.

### Release Hygiene

Each release should be reproducible from `main`.

Acceptance criteria:

- `docs/release.md` remains the maintainer runbook.
- Tag validation checks semantic version, exact commit SHA, and rendered
  community manifest.
- GitHub release assets include platform artifacts and a submission-ready
  community manifest.
- The release notes link to the tag commit, workflow run, and full diff.

## Suggested Milestones

| Milestone | Focus | Exit Criteria |
|---|---|---|
| `0.2.0-alpha.1` | Upstream publication and install smoke | Community install works in CI or the upstream blocker is documented. |
| `0.2.0-alpha.2` | Agent routing and cookbook polish | Top workflows have runnable examples and reference links. |
| `0.2.0-beta.1` | Numerical and edge-case review | Core options, rates, risk, and portfolio behaviors have focused tests. |
| `0.2.0` | Stable docs and release polish | Main CI, docs, Pages, install smoke, and release metadata are green. |

## Definition Of Done

Before tagging `0.2.0`:

```sh
make check DUCKDB_ROOT=/path/to/duckdb
python3 scripts/check_release_metadata.py --tag v0.2.0
```

Also confirm:

- published community install smoke is green;
- docs site builds and publishes;
- release assets are produced for DuckDB's supported extension targets;
- every user-facing behavior change has tests and docs;
- known approximations are documented rather than hidden.
