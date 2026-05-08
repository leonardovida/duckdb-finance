# Security Policy

## Supported Versions

This repository is currently pre-1.0. Security fixes are expected to land on the
default branch.

## Reporting A Vulnerability

Please report security issues privately through GitHub security advisories for
this repository when available. If advisories are unavailable, open a minimal
issue that states you have a security concern without including exploit details,
credentials, proprietary data, or private market data.

## Scope

Relevant issues include crashes triggered by malformed SQL inputs, memory safety
bugs in native extension code, unsafe file or network behavior, and accidental
exposure of secrets through tests or examples.

The extension is designed to run locally inside DuckDB. It should not require
credentials, remote sessions, or market-data entitlements to execute tests.
