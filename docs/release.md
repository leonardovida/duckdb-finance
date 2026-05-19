---
layout: default
title: Release
description: How DuckDB Finance is tagged and released.
permalink: /release/
nav_order: 11
---

# Release

DuckDB Finance releases are tag-driven. Development lands on `main`; when `main`
is ready, create a semantic version tag from that commit.

The next release line is the breaking `0.2.0` cleanup release.

## Maintainer Flow

1. Make sure `main` is green.
2. Confirm `community-extension/description.yml` has the target
   `extension.version`.
3. Confirm the local checkout is exactly on `origin/main`:

   ```sh
   git switch main
   git pull --ff-only origin main
   git status --short --branch
   ```

4. Run the local static and DuckDB-backed checks:

   ```sh
   make ci DUCKDB_ROOT=/path/to/duckdb
   ```

5. Validate the release metadata for the intended tag:

   ```sh
   python3 scripts/check_release_metadata.py --tag v0.2.0
   ```

6. Tag the current `main` commit:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

7. The release workflow validates the tag, builds release artifacts through
   DuckDB extension-ci-tools, renders a community extension manifest with
   `repo.ref` pinned to the tag commit, and creates the GitHub release. It
   expects the tagged commit to have already passed `main` CI.
8. Submit the rendered community manifest from the release assets to
   `duckdb/community-extensions` when publishing or updating the community
   catalog entry.

## Release Workflow

The workflow is intentionally split:

- `Validate release metadata` checks the semantic tag and renders the community
  manifest with the exact tag commit SHA.
- `Build release artifacts` uses DuckDB extension-ci-tools to build the
  platform artifacts.
- `Publish GitHub release` uploads uniquely named assets and updates an
  existing release when a tag is rerun.

Release matrix tests are skipped because the tagged commit must already be green
on `main`. This keeps release publication fast while preserving behavior
coverage in CI.

## Community Publication

Until `finance` is accepted into DuckDB Community Extensions, the release assets
include a submission-ready manifest but users still need the source-build path.

After upstream publication:

1. Confirm `extensions/finance/description.yml` exists in
   `duckdb/community-extensions`.
2. Run the manual smoke workflow with `require_published=true`.
3. Update installation docs from pending-publication wording to the published
   community install command.

The post-publication smoke workflow runs weekly. It skips while the upstream
catalog entry is absent, then verifies:

```sql
INSTALL finance FROM community;
LOAD finance;
```

and executes `examples/community_install_smoke.sql` against the downloaded DuckDB
CLI.

## Final Audit

After the GitHub release is created, confirm:

```sh
gh release view v0.2.0 --json tagName,targetCommitish,url,isDraft,isPrerelease,assets
git rev-parse HEAD
git rev-parse v0.2.0
git ls-remote --tags origin v0.2.0
```

The rendered community manifest asset should include:

- `extension.version` matching the tag without the `v` prefix;
- `repo.github: leonardovida/duckdb-finance`;
- `repo.ref` pinned to the exact release commit SHA;
- `license: MIT`.
