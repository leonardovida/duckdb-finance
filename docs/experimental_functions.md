---
layout: default
title: Experimental Functions
description: Public functions that are documented and tested but not yet recommended for production use.
permalink: /experimental-functions/
nav_order: 7
wide: true
---

# Experimental Functions

These functions are still public so existing SQL examples and coverage can keep
tracking them, but they are not recommended for production workflows yet. Each
entry has an executable test and reference row, plus a reason for quarantine and
a safer replacement path.

Do not build new workflows around these names until their implementation is
promoted out of this page.

| Function | Why It Is Experimental | Prefer |
|---|---|---|
| `fin_bootstrap_curve` | Treats quoted rates as zero rates without bootstrapping instrument cash flows. | Bootstrap instrument-specific discount factors externally. |
| `fin_curve_bootstrap` | Alias of `fin_bootstrap_curve`; treats quoted rates as zero rates. | Bootstrap instrument-specific discount factors externally. |

Additional technical indicators retain simplified formulas. The WMA, DEMA,
TEMA, TRIMA, T3, KAMA, HMA, and regression-level aliases currently use arithmetic
means. ATR averages high minus low; it has no previous-close true-range or Wilder
smoothing. ADX/DI, CMO, MFI, TRIX, stochastic RSI, SAR, OBV, and Roll spread also
use simplified proxies.
These formulas need independent model validation before production use.

## Promotion Rule

A function can leave this page only when it has a non-placeholder
implementation, focused gold coverage for valid and invalid inputs, reference
documentation with units and return shape, and performance coverage through
`make perf`.
