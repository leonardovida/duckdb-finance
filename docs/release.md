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

The first release line starts at `0.1.0`.

## Release Flow

1. Make sure `main` is green.
2. Confirm `community-extension/description.yml` has the target
   `extension.version`.
3. Tag the current `main` commit:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

4. The release workflow validates the tag, builds release artifacts through
   DuckDB extension-ci-tools, renders a community extension manifest with
   `repo.ref` pinned to the tag commit, and creates the GitHub release. It
   expects the tagged commit to have already passed `main` CI.
5. Submit the rendered community manifest from the release assets to
   `duckdb/community-extensions` when publishing or updating the community
   catalog entry.

## Local Checks

Before tagging, run:

```sh
make ci DUCKDB_ROOT=/path/to/duckdb
python3 scripts/check_release_metadata.py --tag v0.1.0
```

The release workflow repeats the metadata check with the exact tag commit SHA
and writes a submission-ready manifest into the GitHub release assets.
