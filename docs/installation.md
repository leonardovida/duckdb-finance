---
layout: default
title: Installation
description: Install DuckDB Finance from DuckDB Community Extensions or build it from source.
permalink: /installation/
nav_order: 3
---

# Installation

`finance` is published in DuckDB Community Extensions. Most users should install
the signed community package. Source builds remain the maintainer and contributor
path when changing or testing this repository.

## Community Extension

Install and load the signed community package with:

```sql
INSTALL finance FROM community;
LOAD finance;
SELECT fin_version();
```

Community extensions are built and signed by DuckDB's community extension CI and
served from DuckDB's community extension endpoint. They can be disabled in
locked-down environments with DuckDB's `allow_community_extensions` setting.

## Source Build

Clone DuckDB and this repository in any layout, then point `DUCKDB_ROOT` at the
DuckDB checkout:

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

## Community Extension Metadata

The upstream DuckDB community catalog entry is generated from a descriptor at
`extensions/finance/description.yml`.

This repository keeps the source descriptor in
[`community-extension/description.yml`](https://github.com/leonardovida/duckdb-finance/blob/main/community-extension/description.yml).
For community catalog updates, set `repo.ref` to the exact commit SHA that
should be built and distributed. Do not submit `main`, a tag that may move, or
any other symbolic ref.

The descriptor should include:

- Extension metadata: name, description, semantic version, language, build
  system, licence, maintainers, and any excluded platforms or required
  toolchains.
- Repository metadata: public GitHub repository and build ref.
- Documentation metadata: a small `hello_world` SQL snippet and an extended
  description for DuckDB's generated community-extension page.
