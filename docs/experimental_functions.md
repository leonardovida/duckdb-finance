---
layout: default
title: Experimental Functions
description: Public functions that are documented and tested but not yet recommended for production use.
permalink: /experimental-functions/
nav_order: 7
wide: true
---

# Experimental Functions

This page lists public functions that are documented and tested but not yet
recommended for production workflows. Each entry has an executable test and
reference row, plus a reason for quarantine and a safer replacement path.

No functions are experimental in this release. Every registered `fin_*`
function computes the model its name and reference row describe.

## Promotion Rule

A function can leave this page only when it has a non-placeholder
implementation, focused gold coverage for valid and invalid inputs, reference
documentation with units and return shape, and performance coverage through
`make perf`.
