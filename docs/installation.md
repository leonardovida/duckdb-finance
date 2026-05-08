---
layout: default
title: Installation
description: Install DuckDB Finance from community extensions or build it from source.
permalink: /installation/
nav_order: 3
---

# Installation

## Community Extension

The intended distribution path is DuckDB's Community Extensions repository. Once
the extension is published there, users install and load it with:

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

This is the user-facing install path. It does not require cloning DuckDB,
building an unsigned binary, or knowing the maintainer's local filesystem
layout.

Community extensions are built and signed by DuckDB's community extension CI and
served from DuckDB's community extension endpoint. They can be disabled in
locked-down environments with DuckDB's `allow_community_extensions` setting.

## Publication Checklist

Publishing requires a pull request to
[`duckdb/community-extensions`](https://github.com/duckdb/community-extensions)
with a descriptor at `extensions/finance/description.yml`.

This repository keeps a ready-to-copy descriptor in
[`community-extension/description.yml`](https://github.com/leonardovida/duckdb-finance/blob/main/community-extension/description.yml).
Before submitting it upstream, set `repo.ref` to the exact commit SHA that
should be built and distributed.

The descriptor should include:

- Extension metadata: name, description, semantic version, language, build
  system, license, maintainers, and any excluded platforms or required
  toolchains.
- Repository metadata: public GitHub repository and build ref.
- Documentation metadata: a small `hello_world` SQL snippet and an extended
  description for DuckDB's generated community-extension page.

## Build From Source

Source builds are for maintainers and contributors. Clone DuckDB and this
repository in any layout, then point `DUCKDB_ROOT` at the DuckDB checkout:

```sh
git clone https://github.com/duckdb/duckdb.git /path/to/duckdb
git clone https://github.com/leonardovida/duckdb-finance.git /path/to/duckdb-finance
cd /path/to/duckdb-finance
make debug DUCKDB_ROOT=/path/to/duckdb
```

Load the local unsigned build from DuckDB:

```sh
/path/to/duckdb/build/debug/duckdb -unsigned
```

```sql
LOAD '/path/to/duckdb/build/debug/extension/finance/finance.duckdb_extension';
SELECT fin_version();
```

Run the validation suite:

```sh
make check DUCKDB_ROOT=/path/to/duckdb
```
