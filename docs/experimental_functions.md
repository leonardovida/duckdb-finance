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
| `fin_apo` | Returns a constant placeholder instead of exponential moving-average spread. | Compute fast and slow moving averages explicitly in SQL. |
| `fin_aroon` | Returns fixed placeholder values instead of lookback high/low positions. | Compute high/low lookback positions explicitly in SQL. |
| `fin_aroonosc` | Returns a constant placeholder instead of Aroon oscillator. | Compute Aroon up/down explicitly and subtract them. |
| `fin_linearreg_slope` | Returns `NULL` until rolling/windowed regression slope support is added. | Use DuckDB `regr_slope` over the desired window. |
| `fin_macd` | Returns zero MACD fields instead of exponential moving-average signals. | Compute fast, slow, and signal EMAs explicitly before using the result. |
| `fin_ppo` | Returns a constant placeholder instead of percentage price oscillator. | Compute fast and slow moving averages explicitly in SQL. |
| `fin_bootstrap_curve` | Treats quoted rates as zero rates without bootstrapping instrument cash flows. | Bootstrap instrument-specific discount factors externally. |
| `fin_curve_bootstrap` | Alias of `fin_bootstrap_curve`; treats quoted rates as zero rates. | Bootstrap instrument-specific discount factors externally. |
| `fin_sma` | Averages supplied rows and ignores period. | Use `avg` with an explicit SQL window for the lookback. |
| `fin_wma` | Uses an arithmetic mean without chronological weights. | Assign linearly increasing weights explicitly. |
| `fin_dema` | Uses an arithmetic mean instead of DEMA. | Compute two ordered EMA stages in separate SQL subqueries. |
| `fin_tema` | Uses an arithmetic mean instead of TEMA. | Compute three ordered EMA stages in separate SQL subqueries. |
| `fin_trima` | Uses an arithmetic mean without triangular weights. | Assign triangular weights explicitly. |
| `fin_t3` | Uses an arithmetic mean and ignores period and volume factor. | Use an independently validated T3 model. |
| `fin_kama` | Uses an arithmetic mean without adaptive smoothing. | Use an independently validated KAMA model. |
| `fin_hma` | Uses an arithmetic mean instead of HMA. | Compute the staged weighted moving averages explicitly. |
| `fin_linearreg` | Returns an arithmetic mean instead of an endpoint regression estimate. | Use `regr_slope` and `regr_intercept` with a chronological axis. |
| `fin_linearreg_intercept` | Returns an arithmetic mean instead of an intercept. | Use `regr_intercept` with a chronological axis. |
| `fin_tsf` | Returns an arithmetic mean instead of a forecast. | Estimate slope and intercept before forecasting. |

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
