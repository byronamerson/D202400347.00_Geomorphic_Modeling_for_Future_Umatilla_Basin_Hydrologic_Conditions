# HMA Interval Migration Metrics — Codex Brief
## Upper Umatilla River, RS 25–30

### Context

We have **20 dated HMA (Historical Migration Area) polygons** for the Umatilla
River (1952–2022). Each polygon is the active river corridor footprint at a
single photo date — NOT a cumulative envelope. We clip these to individual CMZ
segments (starting with RS 30, extending to RS 25–30) and compute polygon
overlay metrics for consecutive date pairs. The goal is a response variable (or
small family) to plot against **peak discharge** and related flood metrics in
the interval between photo dates.

**Specific stream power (ω = γQS/W) is off the table** — we lack a time series
of wetted width. Total stream power (Ω = γQS) remains available if we want it,
but the primary independent variable is simpler: peak Q (and cumulative excess Q
above bankfull) from the USGS gage record during each photo interval.

### The existing script (`rs30_interval_sandbox.R`)

Already implements the GIS symmetric-difference framework:

```
For each consecutive pair (t₁, t₂):
  overlap        = st_intersection(HMA_t1, HMA_t2)
  new_area       = st_difference(HMA_t2, HMA_t1)     # corridor expansion
  abandoned_area = st_difference(HMA_t1, HMA_t2)     # corridor contraction
  sym_change     = st_sym_difference(HMA_t1, HMA_t2) # total reworked area
```

Current output metrics per interval:
- `new_area_ft2`, `abandoned_area_ft2`, `symmetric_change_ft2`, `net_area_change_ft2`
- Annualized versions (`_per_year`)
- Length-normalized activity index: `symmetric_change_ft2_per_year_per_ft`

**Known issue:** `segment_length_ft` uses `Shape_Length` (polygon perimeter).
Should be replaced with reach centerline length or valley-axis length for correct
activity-index normalization (see Legg et al. 2014, §3.2).

---

### Candidate response metrics — ranked by relevance

#### Tier 1: Best candidates for flood-response plotting

1. **New area rate** (`new_area_ft2_per_year` or length-normalized)
   - The migration signal: area of floodplain newly incorporated into the
     corridor between dates. Most directly analogous to bank erosion.
   - Formula: `new_area = Area(HMA_t2 \ HMA_t1)`; rate = `new_area / Δt`
   - Length-normalized: `new_area / (centerline_length × Δt)` → average
     lateral expansion rate (ft/yr). This is the **WA Channel Migration
     Toolbox reach-average migration distance** (Legg et al. 2014, Tool 1).

2. **Channel activity index** (`symmetric_change_ft2_per_year_per_ft`)
   - Total reworked area (new + abandoned) per unit length per year.
   - Captures both expansion AND lateral shifting without net growth.
   - Formula: `(new_area + abandoned_area) / (centerline_length × Δt)`
   - Use when you want total geomorphic work, not just net expansion.

3. **Jaccard distance** (not yet implemented)
   - `d_J = 1 − [Area(A∩B) / Area(A∪B)]`
   - Dimensionless 0–1 instability index. 0 = identical footprints, 1 = no
     overlap. Captures positional change independent of area change.
   - All ingredients already computed (`overlap_ft2`, `area_t1`, `area_t2`).
   - **Not yet published as a named metric in fluvial geomorphology.** Novel.

#### Tier 2: Useful diagnostics / secondary axes

4. **Expansion ratio** = `new_area / abandoned_area`
   - >1 → net corridor expansion; <1 → net contraction; ≈1 → lateral shift.
   - Distinguishes widening from migration-without-widening.

5. **Net area change rate** = `(area_t2 − area_t1) / Δt`
   - Positive = corridor growth, negative = corridor narrowing.
   - Less informative than metrics 1–3 because cancellation hides work done.

6. **Overlap fraction** = `Area(A∩B) / min(Area(A), Area(B))`
   - Persistence metric. High overlap = stable corridor position.

#### Tier 3: Future extensions (not for first pass)

7. Centroid displacement of HMA polygon per interval (net translation vector)
8. Maximum corridor width change per DGO slice (Alber & Piégay 2011 framework)
9. Polygon-derived sinuosity change if centerlines are extracted

---

### Key methodological references (papers on hand)

**Richard et al. (2005a).** *Statistical analysis of lateral migration of the
Rio Grande.* Geomorphology 71:139–155.
- Digitized active channel polygons 1918–2001. Migration rates correlated with
  total stream power (QS) at R² > 0.50. Exponential equilibrium model explained
  78–90% of variance. A **mobility index** (ratio of total channel width to
  equilibrium width) predicts migration rates.
- **Most directly relevant precedent** for plotting polygon-derived migration
  against flood metrics.

**Richard et al. (2005b).** *Case study: Modeling lateral mobility of the Rio
Grande below Cochiti Dam.* J. Hydraulic Engineering 131(11):931–941.
- Companion paper to the above. Operational model application.

**Alber & Piégay (2011).** *Spatial disaggregation and aggregation procedures
for characterizing fluvial features at the network-scale.* Geomorphology
125:343–360.
- The DGO (Disaggregated Geographic Object) framework. Corridor polygons sliced
  perpendicular to centerline every 50–200 m. Per-slice width = polygon area /
  centerline length. Aggregated into homogeneous reaches via Hubert test.
- **Use this if you want spatially distributed metrics along the reach** rather
  than reach-average values.

**Roux et al. (2015).** *FluvialCorridor: A new ArcGIS toolbox package for
multiscale riverscape exploration.* Geomorphology 242:29–37.
- Operationalizes Alber & Piégay (2011). Four toolsets: extraction,
  disaggregation, metrics, aggregation. Python/ArcGIS.

**Rusnák et al. (2025).** *A channel shifting GIS toolbox for exploring
floodplain dynamics through channel erosion and deposition.* Geomorphology
475:109584.
- SCS Toolbox. Takes channel polygons as primary input. Auto-identifies
  erosion/deposition from polygon superposition. Computes lateral migration
  direction. Works standalone or linked to FluvialCorridor.

**Lea & Legleiter (2016).** *Refining measurements of lateral channel movement
from image time series.* Geomorphology 258:11–20.
- Spatially variable error framework. Migration vectors must exceed local error
  ellipses to be significant. Improved detection from 24% → 33% of measurements.
- **Relevant for uncertainty:** apply error thresholds before interpreting small
  interval changes, especially for 1-2 year intervals where digitization error
  dominates.

**Donovan et al. (2019).** *Accounting for uncertainty in remotely-sensed
measurements of river planform change.* Earth-Science Reviews 193:220–243.
- Level-of-detection (LoD) thresholds. Long-term rates underestimate short-term
  rates by 2–15% due to channel reversals. Kaplan-Meier and MLE for nondetect
  handling.
- **Key warning:** irregular intervals (1-year vs 10-year) produce
  systematically different annualized rates. Short intervals amplify digitization
  noise; long intervals smooth over reversals.

---

### Practical guidance for interval-vs-peak plotting

1. **Start with new_area_rate (length-normalized) vs. Qpeak in interval.** This
   is the simplest, most interpretable first plot. It directly answers: "did the
   corridor expand more in intervals with bigger floods?"

2. **Follow with channel_activity_index vs. Qpeak.** This captures total
   reworking including lateral shift. If the corridor moved laterally without
   growing, new_area_rate won't see it but the activity index will.

3. **Add Jaccard distance vs. Qpeak as a third panel.** Dimensionless, so
   directly comparable across segments of different size.

4. **For the independent variable:** use the maximum instantaneous peak in each
   interval as the primary x-axis. As a secondary exploration, try cumulative
   excess discharge above Q₂ (from the flood frequency analysis in
   `01_hydrology_acquisition.R`). Richard et al. (2005) found total stream power
   explained more variance than peak magnitude alone.

5. **Flag intervals < 3 years** as potentially below the level of detection.
   Lea & Legleiter (2016) and Donovan et al. (2019) both show that short
   intervals produce unreliable annualized rates.

6. **Fix the segment_length normalization** before scaling to RS 25–29. Use
   valley-axis or reach-centerline length, not polygon perimeter.

---

### What NOT to pursue right now

- Specific stream power (no wetted width time series)
- Centerline extraction and curvature-migration analysis (requires AC polygons
  per date, which we don't have — we have HMA envelopes)
- DGO-level disaggregation (save for later; reach-average is sufficient for
  the flood-response question)
- PIV / RivMAP raster approaches (our data are vector polygons, not masks)
