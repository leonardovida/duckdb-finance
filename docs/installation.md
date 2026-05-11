---
layout: default
title: Installation
description: Install DuckDB Finance after publication or build it from source today.
permalink: /installation/
nav_order: 3
---

# Installation

`finance` is not yet published in DuckDB Community Extensions. Today, use the
source-build path below. The community install commands are the intended public
path after upstream publication.

## Published Community Extension

After `finance` is accepted into
[`duckdb/community-extensions`](https://github.com/duckdb/community-extensions),
users install and load the signed package with:

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

Community extensions are built and signed by DuckDB's community extension CI and
served from DuckDB's community extension endpoint. They can be disabled in
locked-down environments with DuckDB's `allow_community_extensions` setting.

## Current Source Build

Source builds are the current maintainer and contributor path. Clone DuckDB and
this repository in any layout, then point `DUCKDB_ROOT` at the DuckDB checkout:

```sh
git clone https://github.com/duckdb/duckdb.git /path/to/duckdb
git clone https://github.com/leonardovida/duckdb-finance.git /path/to/duckdb-finance
cd /path/to/duckdb-finance
make debug DUCKDB_ROOT=/path/to/duckdb
```

Run the validation suite through the repository Makefile. These targets start
DuckDB with unsigned local extensions enabled and load the built extension from
the DuckDB build tree:

```sh
make check DUCKDB_ROOT=/path/to/duckdb
```

For a faster load-and-query smoke run:

```sh
make smoke DUCKDB_ROOT=/path/to/duckdb
```

## Publication Checklist

Publishing requires a pull request to `duckdb/community-extensions` with a
descriptor at `extensions/finance/description.yml`.

This repository keeps a ready-to-copy descriptor in
[`community-extension/description.yml`](https://github.com/leonardovida/duckdb-finance/blob/main/community-extension/description.yml).
Before submitting it upstream, set `repo.ref` to the exact commit SHA that
should be built and distributed. Do not submit `main`, a tag that may move, or
any other symbolic ref.

The descriptor should include:

- Extension metadata: name, description, semantic version, language, build
  system, licence, maintainers, and any excluded platforms or required
  toolchains.
- Repository metadata: public GitHub repository and build ref.
- Documentation metadata: a small `hello_world` SQL snippet and an extended
  description for DuckDB's generated community-extension page.
