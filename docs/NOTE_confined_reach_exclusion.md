# NOTE — Exclusion of the Pendleton leveed reaches (25–27)

**Date:** 2026-09-05
**Scope:** Multi-reach migration-forcing model (`scripts/07_mixed_forcing_model.R`,
and `scripts/07b_lmm_sensitivity_and_robustness.R`, which sources 07's panel).
**Decision:** Drop river segments **25, 26, 27** from the migration-forcing model.
Modeled reach set is now **28–37** (10 reaches).

## Why

Reaches 25–27 pass through the **city of Pendleton** and are bounded by
**engineered levees**. Channel migration in those reaches is *mechanically
precluded* by the infrastructure — the banks cannot move regardless of flow.
That makes them a **different data-generating process** from the free and
semi-confined reaches upstream (28+), which are far less confined or
unconfined. A model that pools them assumes every reach responds to flood
forcing through the same migration mechanism; the leveed reaches violate that
assumption at the physical level.

This is exclusion on **mechanistic grounds**, not because the reaches fit
poorly. The poor fit is a *symptom*:

- **Impossible fitted intercepts.** The response `new_area_per_ft` is one-sided
  (area *gained*; loss is tracked separately in `abandoned_area` /
  `net_area_change`), so it is bounded at 0. Reaches 25–27 produced **negative
  fitted intercepts** — physically impossible for an area-gain metric, and a
  clear sign the linear model was being asked to describe a process that
  doesn't occur there.
- **Contiguity + single cause.** The three squirrely reaches are a
  *geographically contiguous* block sharing *one* physical constraint (the
  Pendleton levee system), not a scattered trio selected after the fact.

## Consequence

- **Scope of inference narrows, honestly**, to migration-capable reaches of the
  Umatilla — the population the forcing relationship was ever about.
- Panel goes from 13 → 10 reaches (~181 → ~139 rows).
- The confined reaches remain in the data artifact
  (`data/multireach_interval_metrics.csv`); they are excluded only at the
  **model boundary**, so (a) the data layer stays complete and (b) the
  exclusion is a toggle for sensitivity, not a data deletion.

## Implementation

Single filter at the panel-assembly boundary in
`scripts/07_mixed_forcing_model.R`:

```r
CONFINED_REACHES <- c(25L, 26L, 27L)
panel <- multireach %>% filter(!river_segment %in% CONFINED_REACHES) %>% ...
```

Because every model in 07 fits `panel`, and 07b `source()`s 07 to obtain
`panel`, this one edit cascades to all downstream models, caterpillars, and the
per-reach scatter. Script 06 (`reaches <- 25:37`) is left unchanged — it still
computes metrics for all reaches; the confined-reach rows simply are not modeled.

## Sensitivity (to record from the refit)

Forcing slope (`cum_excess_k`) and the reach/interval variance components,
full 13-reach set vs. reduced 10-reach set — to be filled in from the refit so
the effect of the exclusion is on the record:

| Quantity | Full (25–37) | Reduced (28–37) |
|---|--:|--:|
| `cum_excess_k` slope (m_B2) | 1.255 | **1.461** (+16%) |
| `cum_excess_k` slope (m_A) | 1.256 | 1.461 |
| among-reach SD (m_A) | 19.07 | **16.57** |
| among-interval SD (m_A) | 14.50 | 16.64 |
| residual SD (m_A) | 18.80 | 19.42 |
| `interval_years` slope (m_A) | 3.35 | 3.62 |

**Read:** the forcing slope rose ~16% (the leveed reaches were diluting it toward
flat), and it stayed significant (m_A t = 3.31, m_B2 t = 2.99). Among-reach SD
*fell* (19.1 → 16.6): the reaches are more homogeneous once the confined outliers
are gone — corroborating that 25–27 were a different population. The impossible
negative per-reach intercepts are gone (population intercept now +9.4, physical).
Structure unchanged: `interval_years` still earns its place (LRT p = 4e-4) and the
random reach slope still does (m_A vs m_B2, p = 3e-3), so m_B2 stays the model of
record. One benign flag: m_B2 reports a borderline convergence warning
(max|grad| = 0.0022 vs tol 0.002) on the thinner 10-reach set — check with an
optimizer restart / `allFit`; estimates expected stable.
