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

## Quack Server

DuckDB 2.0 can serve a database to other DuckDB processes over the
[Quack remote protocol](https://duckdb.org/docs/2.0/quack/overview.html).
`finance` works on a Quack server without extra configuration, but DuckDB does
not autoload community extensions, so the server process must load `finance`
before clients call `fin_*` functions.

Install the extension once on the server host:

```sh
duckdb -c "INSTALL finance FROM community"
```

Start the server with `finance` loaded. Pass the database file before `-serve`,
which reads its next argument as the protocol. The server prints the
`auth_token` that clients use:

```sh
duckdb -cmd "LOAD finance" my_database.duckdb -serve
```

From an existing session, load the extension before serving:

```sql
LOAD finance;
CALL quack_serve(token := 'my_token');
```

A server started from the CLI can also load the extension from its
`~/.duckdbrc` file by adding `LOAD finance;`.

Clients do not need `finance` installed when the query runs on the server:

```sql
ATTACH 'quack:localhost' AS remote (TOKEN 'my_token');
CONNECT remote;

SELECT fin_bsm_price(fin_option_spec('call', 100.0, 100.0, 1.0, 0.05, 0.20));
SELECT * FROM fin_calendar('weekday', DATE '2026-05-04', DATE '2026-05-08');
```

Where each query runs determines where `finance` must be loaded:

| Client query | Runs on | Client needs `finance` |
| --- | --- | --- |
| Any query after `CONNECT remote` | Server | No |
| `quack_query('quack:localhost', 'SELECT fin_...', token := 'my_token')` | Server | No |
| `fin_*` over attached tables only, such as `SELECT fin_volatility(r) FROM remote.returns` | Server | No |
| Server views that call `fin_*`, read through `ATTACH` | Server | No |
| `fin_*` over client-local tables or literals, or a join between local and attached tables | Client | Yes |

Table functions that take table names as strings, such as
`fin_normalize_ohlcv` and `fin_option_chain`, resolve those names on the server
after `CONNECT`.

After `CONNECT`, `LOAD` statements also run on the server, and the default
Quack authorization accepts every query from a client that holds the token.
Such a client can load any extension already installed on the server host.
Preload the extensions the server needs and restrict who receives the token.
The Quack server listens on `localhost` by default. Follow DuckDB's
[Quack security guidance](https://duckdb.org/docs/2.0/quack/security.html) and
place a TLS-terminating reverse proxy in front of the server for remote access.

`scripts/quack_server_smoke.py` runs these scenarios against a DuckDB 2.0 CLI
with a client that does not have `finance` installed.

## Source Build

Clone DuckDB and this repository in any layout, then point `DUCKDB_ROOT` at the
DuckDB checkout:

```sh
git clone --branch v2.0.0 https://github.com/duckdb/duckdb.git /path/to/duckdb
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
