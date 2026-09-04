# Fire-Response Analytical Pathways — Upper Umatilla Basin

**Date:** August 2026
**Status:** Strategy document. Companion to `next_step_exploration_brief.md`; does not replace it.
**Trigger:** 2026 fires in the Upper Umatilla watershed, partially contained. See `MEMO_fire_delivered_wood_and_sediments` (7/24/2026).

---

## 0. Scope Boundary — Read First

**This project is not adding a fire, sediment, or hydrology analysis.**

The work stays what it already is: the relationship between channel migration and stream discharge on the upper Umatilla. Fire changes the **application and interpretation** of that relationship for the next few winters. It does not change the analysis.

- **In scope:** applying the existing migration–discharge framework to near-term post-fire conditions, and stating the implications for assets
- **Out of scope:** post-fire sediment yield modeling, debris-flow initiation, wood budgets, rainfall-intensity thresholds, atmospheric-river classification

Section 4 records the out-of-scope pathways deliberately, so they are recognized as declined rather than overlooked, and can be revisited under separate scope.

---

## 1. Why the Analysis Does Not Need to Change

The post-fire chain is longer than `discharge → migration`:

```
fire → higher Q per unit precipitation
     → sediment + wood supply pulse → bed aggradation
     → reduced conveyance           → higher stage at same Q
     → punctuated migration
```

Two entry points, and only one matters here:

- **Forcing side** — fire raises runoff per unit precipitation, but **the gages already integrate this.** Observed post-fire discharge needs no adjustment, and the Q₂ threshold stays where it is
- **Response side** — fire raises channel change per unit discharge, via sediment supply and loss of bank vegetation

**Therefore: the existing pipeline requires no modification.** Fire is a shift in the response function, not in the discharge metrics. The framework is already correctly specified for the question; what changes is the expected magnitude of response and how the results are framed.

This is the central justification for not reopening scope.

---

## 2. What the Existing Work Already Delivers

| Existing element | Near-term post-fire use |
|---|---|
| Documented migration rates per reach (DOGAMI EHA) | Identifies where fire-delivered material will produce the most change |
| Feb 2020 flood in calibration data | A characterized >Q₁₀₀ response on an *unburned* basin — the counterfactual |
| Net area change / expansion ratio | Aggradation drives corridor expansion; the one signal that worked is the right mechanism |
| Q₂ threshold + exceedance counts | "How many chances" a loaded channel gets per winter |
| CMZ / EHA / AHA hazard products | The asset-facing layer already exists |
| `02` DA scaling + gage assignment | Translates basin position to reach-specific discharge |

---

## 3. In-Scope Pathways

### P1 — Fire as a response-function shift *(framing, no new work)*

- Do not adjust the discharge record or the Q₂ threshold
- Express fire as expected exceedance of the pre-fire relationship
- Provides the defensible answer to "why aren't you modeling the sediment?" — because the gage record and the existing response function bracket the problem

### P8 — Feb 2020 as the calibrated analog *(top priority, data in hand)*

- Flood of record, ~24,900 cfs at Pendleton, above the regulation-corrected Q₁₀₀ of ~21,800 cfs
- Already in the calibration data with mapped channel response
- Also the high-leverage point in the current regression — the same observation drives both the statistical fragility and the fire application
- Product: per-reach summary of what a >Q₁₀₀ event did to an unburned basin
- Framing: this is the floor, not the expectation, for a comparable event on a burned basin
- Most communicable product available, and it requires no new data

### P9 — Asset exposure screen *(second priority, overlay only)*

- No new modeling. Rank, don't predict
- Layers: documented migration rate per reach × position relative to burned area × asset location
- Assets: Meacham Creek restoration footprints; mainstem spawning habitat upstream of Mission; Mission Creek
- **Infrastructure flags are extractable today** — `classify_confinement()` already parses `levee|railroad|road embankment|bridge` from DOGAMI bank notes
- Burn extent enters as a coarse spatial overlay, not a modeled sediment input
- Does not require a working regression. Ranking is the product

### P2 — Out-of-sample comparison *(deferred; gated on imagery, not analysis)*

- The existing relationship predicts channel change from observed discharge
- Post-2026 winters supply the test; residual = fire effect
- Requires only post-fire mapping, no new methods
- **Gated entirely on the imagery decision in Section 6** — if the baseline is lost, this pathway closes
- Report prediction intervals, not confidence intervals. At n = 13 they are wide: a large fire effect is detectable, a modest one is not

### P4 — Aggradation and avulsion *(implication to state, not work to do)*

- Aggradation reduces conveyance, raising stage at unchanged discharge — this is the mechanism that damages assets, not slow lateral migration
- DOGAMI's AHA inventory already supplies baseline avulsion susceptibility per reach
- `03c_avulsion_model.R` exists if this is ever funded
- **For now: state it as an expected implication in reporting. Do not build it**

---

## 4. Out of Scope — Recorded as Declined

These were considered and set aside. They constitute a different project.

- **P3 Sediment supply modeling** — Gartner et al. (2008) debris-flow volumes, connectivity indices, wood recruitment budgets
- **P5 Post-fire decay index** — repurposing the antecedent-index architecture for sediment exhaustion
- **P6 Event sequencing and supply exhaustion** — requires the daily record and cumulative-since-fire metrics
- **P7 Atmospheric-river and rain-on-snow classification** — requires SNOTEL integration and event typing
- **P10 Debris-flow initiation** — different process, different trigger (I₁₅ rainfall intensity), steep headwaters only

If CTUIR wants any of these, it is a scope conversation and a separate budget — most plausibly the post-fire watershed assessment already being pursued at ESA.

---

## 5. Two-Month Priority Plan

Realistic capacity: **8–10 working days.**

### Perishable — do first, regardless of any finding

- **Imagery scheduling decision.** Check NAIP/OSIP timing; select an alternative if it misses the window. Miss this and the first post-fire year is unrecoverable, closing P2 permanently — *~0.5 day*
- **Pull burn perimeters and available severity products** for the spatial overlay in P9 — *~0.5 day*
- **Pre-winter photo points** at Meacham restoration and mainstem above Mission. Cannot be collected retroactively — *~1–2 days field*

### The gate — ~1 day

- Phase 1 influence diagnostics on the net-area model (`explore/x01_influence_diagnostics.R`)
- Cheapest decisive test available: does the regression path survive the Feb 2020 leverage point

### If it survives

- Phase 2 peak-flow predictors — counts above Q₂/Q₅/Q₁₀, cumulative excess — *~2 days*
- Stop there. Report the relationship with honest caveats
- Do not start Phase 3 or 4 in this window

### If it does not survive

- Set the regression aside and go straight to P8 and P9

### Deliverables either way

- **P8 Feb 2020 per-reach case study** — *~2 days*
- **P9 asset exposure screen** — *~3 days*

Worth being clear-eyed: under the fire framing, P8 and P9 are the more useful client products regardless of the diagnostics outcome. The low-capacity path is not a compromise.

### Not in this window

- Finish `04a` / daily record; CESP; scale to RS 25–39; mid-century climate scenarios; anything in Section 4

### Free

- DOGAMI response. Waiting, not working. If Appleby replies it only affects whether 2011–2012 is trusted, and the Δt² weighting already handles that either way

---

## 6. Spatial Scope Note

- RS 25–30 covers the current analysis but not all the assets
- Meacham Creek, Mission Creek, and mainstem upstream of Mission sit outside it
- For P9, use DOGAMI's existing reach-scale rates across all 39 segments plus the McKay/tributary products — no new metric computation required
- Extending the *HMA interval analysis* upstream is Phase 3 and is out of this window

---

## 7. Limitations to State in Reporting

- No sediment or wood term in the model. Fire's primary effect is supply; the analysis represents discharge only
- The response function is pre-fire calibrated, and post-fire response may not be a simple scalar shift
- n = 13 at RS 30 gives wide prediction intervals
- Post-fire HMA mapping does not exist and is not funded; continuing DOGAMI's sequence is a new scope item
- Feb 2020 is a single event and a high-leverage observation — it anchors the analog framing and the statistical fragility simultaneously

---

## 8. Literature

**From the memo**

- Appleby, C.A., Anthony, L.H., & Noone, J.K. (2025). *Channel Migration Zone Maps for the Umatilla River and Lower McKay Creek.* DOGAMI Open-File Report O-25-10.
- Short, L.E., Gabet, E.J., & Hoffman, D.F. (2015). The role of large woody debris in modulating the dispersal of a post-fire sediment pulse. *Geomorphology* 246, 351–358.
- Wohl, E. & Scott, D.N. (2017). Wood and sediment storage and dynamics in river corridors. *ESPL* 42(1), 5–23.
- Gartner, J.E., et al. (2008). Empirical models to predict the volumes of debris flows generated by recently burned basins in the western US. *Geomorphology* 96(3–4), 339–354.
- Shakesby, R.A. & Doerr, S.H. (2006). Wildfire as a hydrological and geomorphological agent. *Earth-Science Reviews* 74, 269–307.
- Gershunov, A., et al. (2019). Precipitation regime change in Western North America: the role of atmospheric rivers. *Scientific Reports* 9(1).
- Praskievicz, S. (2016). Impacts of projected climate changes on streamflow and sediment transport for three snowmelt-dominated rivers in the interior Pacific Northwest. *River Research and Applications* 32(1), 4–17.

**Supporting the in-scope framing**

- Costa, J.E. & O'Connor, J.E. (1995). Geomorphically effective floods — magnitude plus duration.
- Benda, L., et al. (2003). Network dynamics hypothesis. Reeves, G.H., et al. (1995). Disturbance-driven habitat mosaics. — connects to CTUIR First Foods and Umatilla River Vision framing.
- Moody, J.A. & Martin, D.A. (2001, 2009). Post-fire sediment yield and recovery timescales — cite for the 1–5 year response window, not for modeling it.

---

*End of document. P8 and P9 are deliverable with data in hand. P1 and P4 are framing for reporting. P2 is gated on the imagery decision. Section 4 is declined scope, recorded deliberately.*
