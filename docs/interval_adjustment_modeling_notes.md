# Interval-Based Geomorphic Adjustment Modeling Notes

## Purpose

This note captures the current working interpretation of the DOGAMI
Umatilla dataset and outlines a practical path toward relating flood
magnitude to geomorphic adjustment. It is a design note, not a finished
analysis plan.

## Current Understanding

The core analytic problem is to build a predictive model that relates
flood magnitude to channel adjustment.

The original hope was to use active-channel geometry through time, but
the DOGAMI geodatabase does not provide a dated active-channel sequence.
Instead, it provides:

- one present-day active channel (`AC`) polygon for each stream
- a dated `HMA` sequence that represents historical occupation and
  migration footprint through time
- `CMZ`, `EHA`, `AHA`, and flagged-bank products derived from those
  spatial interpretations
- segment-based spreadsheet summaries with reach attributes and hazard
  metrics

This changes the framing of the analysis. The data do not strongly
support a time series of true active-channel width or position at each
mapped year. They do support interval-based analysis of historical
occupation change and planform reorganization.

## Key Analytic Frame

The main working idea is interval-based:

- take one mapped state at `t1`
- take the next mapped state at `t2`
- estimate geomorphic adjustment between those two states
- divide by elapsed time to create an annualized rate
- pair that response with flood metrics summarized over the same interval

This is the cleanest way to align the geomorphic response with the
hydrologic forcing.

The key observation is that the response variable should live on the
same time interval as the forcing variable. A single-date discharge
should not be linked to a multi-year spatial adjustment response.

## What The Spatial Data Support Best

The strongest response-variable family is polygon-based change between
dated `HMA` states.

Examples include:

- `new_area_ft2`: area newly occupied at `t2` relative to `t1`
- `abandoned_area_ft2`: area occupied at `t1` but not at `t2`
- `symmetric_change_ft2`: total changed footprint between `t1` and `t2`
- annualized versions of the above
- segment-length-normalized versions that behave like effective lateral
  adjustment widths

These metrics are attractive because they are directly supported by the
geometry and do not require assumptions about event-stage wetted width.

Distance-like migration metrics may still be useful, but they are more
inferential with the current data and should probably be treated as a
second wave of experimentation rather than the first.

## Candidate Response Families

### 1. Interval HMA Change Metrics

This is the leading candidate family for custom geomorphic response
metrics.

Possible dependent variables:

- `symmetric_change_ft2_per_year`
- `new_area_ft2_per_year`
- `abandoned_area_ft2_per_year`
- `symmetric_change_ft2_per_year / segment_length_ft`
- `new_area_ft2_per_year / segment_length_ft`

Interpretation:

- these capture planform reorganization and historical occupation change
- they are likely better described as geomorphic adjustment rates than as
  literal migration rates

### 2. DOGAMI Reach-Scale Erosion Metrics

The DOGAMI spreadsheets already contain strong derived response
variables, especially for the Umatilla River.

Examples:

- `Median EHA Rate (ft/yr)`
- `Maximum EHA Rate (ft/yr)`
- measured and modified erosion rates from the EHA table

Interpretation:

- these are likely the fastest response variables to model
- they are not built directly from time-step geometry, but they are
  ready-made descriptors of adjustment intensity

### 3. Avulsion Occurrence Or Avulsion Rate

The AHA spreadsheet and notes support a third response family.

Examples:

- binary avulsion occurrence by interval
- avulsion count by interval
- avulsion rate normalized by interval duration

Interpretation:

- this is especially relevant if the flood-response relationship is
  threshold-like rather than gradual

## What Seems Less Defensible Right Now

These should not be the primary analysis target at present:

- year-by-year active-channel width versus discharge
- unit stream power using width values that are not event-specific
- static `CMZ` extent as the main response variable

The reason is that the width term is not clearly tied to the discharge of
interest, and the available `AC` data are essentially a 2024 snapshot
rather than a dated sequence.

## Hydrology Framing

Flood magnitude remains the intended forcing-variable family.

Because the response is interval-based, the hydrologic predictors should
also be interval-based. Candidate interval predictors include:

- maximum annual peak flow in the interval
- mean annual peak flow in the interval
- count of flood peaks above a chosen threshold
- cumulative exceedance above a threshold
- return-interval-style summaries based on the largest event in the
  interval

This framing is more defensible than trying to pair a long interval of
geomorphic response with a single-date flow measurement.

## Candidate Modeling Strategies

Several modeling directions came up in discussion. The point at this
stage is not to commit to one, but to preserve the useful options.

### 1. Reach-Scale Regression On DOGAMI Erosion Metrics

This is the fastest path to a predictive model because the response
variables already exist in the spreadsheets.

Candidate response variables:

- `Median EHA Rate (ft/yr)`
- `Maximum EHA Rate (ft/yr)`
- measured or modified erosion rates from the EHA table

Candidate predictors:

- flood magnitude summaries
- slope
- sinuosity
- confinement
- bank or geology classes derived from notes where useful

Possible model forms:

- linear regression on raw or transformed rates
- robust regression if a few reaches dominate the fit
- GAM-style smooths if the relationship looks nonlinear

### 2. Interval Panel Model Using HMA Change Metrics

This is the most direct route to linking flood magnitude with observed
geomorphic adjustment through time.

Candidate response variables:

- `symmetric_change_ft2_per_year`
- `new_area_ft2_per_year`
- width-like normalized versions based on segment length

Candidate predictors:

- interval maximum annual peak flow
- counts of peaks above a threshold
- cumulative flood exceedance metrics
- static reach covariates such as slope or confinement

Possible model forms:

- interval-by-segment regression
- mixed models with segment as a repeated-measures grouping factor
- simple exploratory regressions first, with more structure only if the
  data justify it

### 3. Avulsion Occurrence Model

This remains attractive because avulsion is a threshold-style
geomorphic response and may connect to flood magnitude differently than
continuous lateral adjustment.

Candidate response variables:

- avulsion occurrence in an interval
- avulsion count in an interval
- avulsion rate with interval duration treated explicitly

Possible model forms:

- logistic regression for occurrence
- negative binomial or Poisson-rate models for counts
- susceptibility categories from the DOGAMI summaries as covariates

### 4. Stream Power As A Secondary, Not Primary, Predictor

Unit stream power is currently a weaker lead predictor than plain flood
magnitude because the width term is not event-specific in the available
data.

The current lean is:

- keep stream power in mind as interpretive context or a later secondary
  model
- do not make it the primary predictor until there is a stronger width
  basis tied to the discharge of interest

### 5. Model Family Hierarchy

The rough ranking that emerged in this chat was:

- first: interval `HMA` change versus interval flood metrics
- second: reach-scale erosion intensity versus flood magnitude
- third: avulsion occurrence versus interval flood metrics

This is not a final ranking, but it captures the current center of
gravity.

## Spatial Organizing Framework

The `CMZ` river segments remain the best spatial organizing framework.

Observed conditions:

- the Umatilla `CMZ` layer contains 39 unique `RIverSegment` values
- later dated `HMA` states intersect all 39 segments
- several early years are partial and should not be treated as full-river
  observations

This suggests a practical structure of:

- segment-by-interval observations for full-river work
- subreach experimentation first, followed by scaling up if the metrics
  behave well

## Candidate Reach Experiment

The next practical move is to identify one dynamic and interesting reach
as a test bed for metric generation.

The goal of the candidate reach is not to produce final inference. It is
to pressure-test metric definitions and see which ones capture
geomorphically meaningful change.

The candidate reach should ideally have:

- visually obvious planform change
- multiple usable `HMA` time steps
- enough spatial extent to show more than a single cutoff or local bank
  retreat
- a clean relation to the existing segment framework

For that candidate reach, the first experimental outputs should probably
be:

- maps of consecutive `HMA` states
- overlap and change polygons for `t1 -> t2`
- a small table of area-based interval metrics
- annualized versions of those metrics
- simple plots against interval flood summaries once hydrologic metrics
  are available

## Near-Term Direction

The current best path forward is:

1. Select one candidate reach that is visibly dynamic.
2. Generate polygon-based interval metrics for consecutive dated `HMA`
   states in that reach.
3. Compare a small family of response metrics rather than committing to a
   single definition too early.
4. Keep the language careful: these are likely geomorphic adjustment
   metrics first, and migration metrics only where the geometry supports
   that interpretation.
5. Use what the candidate reach reveals to decide whether the workflow
   should scale to all segments or remain focused on a smaller number of
   high-information reaches.

## Chat Highlights To Preserve

These points are worth keeping in view:

- The active-channel layers are present-day snapshots, not a dated active
  channel sequence.
- The `HMA` product solves one problem by being less sensitive to the
  exact discharge at the image date, but it changes the meaning of the
  response variable.
- The analysis target is now better framed as geomorphic adjustment or
  historical occupation change, not strictly wetted-channel migration.
- Response and forcing should be aligned on the same interval.
- Both area-based and distance-like metric families are conceptually
  interesting, but area-based metrics are more directly supported by the
  current geometry.
- The DOGAMI spreadsheets are valuable because they already contain
  reach-scale widths, slopes, sinuosity, erosion rates, avulsion notes,
  and qualitative constraints.
- The hydrology and regulation scripts in the repo define a substantial
  future workflow, but `data/` is currently empty, so those outputs are
  not yet materialized in this workspace.
- A dynamic candidate reach is the right next place to experiment before
  scaling any metric family to the whole river.

## Working Bottom Line

The most defensible current direction is to model flood magnitude against
interval-based geomorphic adjustment derived from dated `HMA` states,
using `CMZ` river segments as the spatial framework and polygon-based
change metrics as the first response family to test.

## Current Exploratory Progress

Work has now moved from discussion-only mode into exploratory scripting.

An exploratory script was added at
[scripts/rs30_interval_sandbox.R](C:/Users/bamerson/Documents/GitProjects/umatilla_geomorphic_futures/scripts/rs30_interval_sandbox.R).
Its role is to act as a rough working template for interval-based metric
generation before anything is turned into a more structured workflow.

The current sandbox does the following:

- reads `Umatilla_River_HMA` and `Umatilla_River_CMZ`
- isolates `RS 30` as the current candidate reach
- intersects dated `HMA` polygons with the segment
- builds the consecutive interval sequence present inside that segment
- computes a first bundle of area-based interval metrics

The current focus segment is `RS 30`.

Observed results so far:

- `RS 30` has a usable dated `HMA` sequence of
  `1952, 1964, 1974, 1981, 1995, 2000, 2005, 2009, 2011, 2012, 2014,
  2016, 2017, 2020, 2022`
- this yields `14` consecutive intervals for exploratory comparison
- each dated year clips to one polygon within the segment

The first-pass interval metrics currently in the sandbox are:

- `new_area_ft2`
- `abandoned_area_ft2`
- `symmetric_change_ft2`
- annualized versions of those metrics
- `symmetric_change_ft2_per_year_per_ft` as a segment-length-normalized
  width-like metric

### Symmetric Change

`Symmetric change` is currently an important working metric.

Definition:

- it is the total area that changed between `t1` and `t2`
- equivalently, it is `new area + abandoned area`
- in set terms, it is the part of `t1` and `t2` that does not overlap

Interpretation:

- it is best understood as a footprint-turnover or planform-reorganization
  metric
- it captures total geomorphic adjustment without assuming that all
  change is simple lateral migration
- this makes it especially attractive for `HMA`-based analysis, where the
  geometry reflects historical occupation and reorganization rather than
  a clean dated wetted-channel edge

### Where The Exploration Is Headed Next

The next likely extensions to the sandbox are:

- rank intervals by `symmetric_change_ft2_per_year`,
  `new_area_ft2_per_year`, and `abandoned_area_ft2_per_year`
- create quick visual comparisons for the highest-change intervals
- decide which response metric feels most geomorphically meaningful
  before wiring in interval flood summaries

The current stance is still exploratory and iterative. The script should
be expected to change several times before it becomes the basis for a
more structured metric-generation workflow.

## Session Progress Summary

This session moved the work from metric discussion into a first
hydrology-linked exploratory workflow for `RS 30`.

### What Was Reviewed

Several supporting documents were read or revisited to ground the work:

- `hma_interval_metrics_codex_brief.md`
- `codex_migration_pipeline_brief.md`
- `rapp_abbe_2003_codex_summary.md`
- `lingua.md`
- `contract-first-development.md`
- `r-dev-principles-llm-companion.md`
- `tidy-analysis-three-operations-agent-reference.md`

The practical effect of that reread was to tighten the comments and
contracts in the exploratory script so the code records decisions and
assumptions in plain language rather than forcing later readers to infer
method from implementation.

### GIS Tool Context

The `data_in/GIS_tools` directory was scanned for context.

Observed contents included:

- `SCS_TOOLBOX-main`
- `Fluvial-Corridor-Toolbox-ArcGIS-master`
- `gcd-master`

The SCS Toolbox Python scripts were then reviewed directly.

Working interpretation:

- `M1_centerline.py` contains ideas worth adapting later for replacing the
  current polygon-perimeter length denominator with a more defensible
  centerline-based reach length
- `M3_EAcalculation.py` reinforces the basic usefulness of polygon overlay,
  area-based change classes, and time-normalized rates
- `M2_segmentation.py` and `M4_FloodplainStat.py` look more like later-phase
  tools than first-pass needs for the current flood-response plots

### R Package Audit

The spatial package stack was checked and then re-checked after package
installation.

Packages now available for later R-native adaptation work include:

- `centerline`
- `nngeo`
- `exactextractr`
- `geos`
- `lwgeom`
- `sfnetworks`

This removed package availability as a near-term blocker.

### Hydrology Outputs And First Join

The hydrology scripts were run outside this note-writing step, and the
resulting outputs were located in `data/`.

Key files confirmed:

- `data/peak_flows.csv`
- `data/flood_frequency.csv`
- `data/gage_metadata.csv`

For `RS 30`, the first-pass gage choice settled on Pendleton
(`14020850`), with the explicit understanding that:

- `RS 30` is upstream of Pendleton and downstream of Gibbon
- Pendleton is the most practical first-pass forcing series for plotting
- earlier `RS 30` intervals that predate Pendleton coverage are allowed to
  remain `NA` rather than forcing a mixed-gage solution too early

### Water-Year Alignment Decision

A working temporal-alignment rule was agreed and implemented:

- HMA `Year` is treated as the same-labeled water year
- image dates are assumed to fall in the January-September part of that
  water year unless exact photo dates are recovered later
- for interval `t1 -> t2`, the first-pass forcing window is water years
  greater than `t1` and less than or equal to `t2`
- the primary forcing variable is the maximum annual peak flow in that
  window

This is explicit and provisional, not hidden. It is good enough for
first-pass plotting but should be revisited if photo dates are later
recovered.

### Script Development

The exploratory script at
`scripts/rs30_interval_sandbox.R` was extended substantially.

New or revised components include:

- stronger script-level context and method comments
- hydrology boundary helper to read annual peaks
- helper to build yearly and interval peak-flow tables aligned to HMA
  intervals
- joined exploratory objects:
  - `rs30_interval_yearly_peaks`
  - `rs30_interval_peak_summary`
  - `rs30_interval_metrics_with_peaks`
- first-pass plot objects for the original consecutive intervals:
  - `rs30_plot_new_area`
  - `rs30_plot_symmetric_change`
  - `rs30_plot_net_area_change`

### First Plotting Results

The first plots for consecutive intervals were produced and inspected.

Key observation:

- the original consecutive-interval plots showed more visually appealing
  regression structure than the later alternate partition variants
- the interval `2011-2012` appeared as a strong outlier, especially in the
  annualized response metrics

Working interpretation:

- this is likely tied to the combination of a very short interval and
  annualization
- it may reflect a real abrupt change, a mapping/date artifact, or both
- it should be treated as a flagged interval, not casually interpreted as a
  clean hydrology-response point

### Alternate Partition Experiments

To explore whether short intervals were overly shaping the plots, two
retrospective interval-construction variants were added and tested.

Shared rule:

- target lag = `5` years
- minimum acceptable lag = `4` years
- tie-break = choose the shorter interval when two candidates are equally
  close to the target lag

Variant 1:

- non-overlapping greedy backward partition from the present

Variant 2:

- maximally greedy backward overlapping windows

These were implemented in the script with helpers and their own plot sets.

Disjoint backward expected sequence for `RS 30`:

- `2017-2022`
- `2012-2017`
- `2005-2012`
- `2000-2005`
- `1995-2000`
- `1981-1995`
- `1974-1981`
- `1964-1974`
- `1952-1964`

Overlapping backward expected sequence for `RS 30`:

- `1952-1964`
- `1964-1974`
- `1974-1981`
- `1981-1995`
- `1995-2000`
- `2000-2005`
- `2005-2009`
- `2005-2011`
- `2005-2012`
- `2009-2014`
- `2011-2016`
- `2012-2017`
- `2016-2020`
- `2017-2022`

### What The Alternate Partitions Showed

Observed from the exploratory plots:

- the retrospective partitions largely suppressed the `2011-2012` short-
  interval blow-up
- they produced cleaner, more stable-looking point clouds
- however, the original consecutive-interval ordering still appeared more
  visually promising from a simple regression standpoint

Current lean:

- keep the original consecutive intervals as the primary exploratory design
- treat the backward partitions as sensitivity checks rather than
  replacements
- keep the overlapping windows explicitly labeled as dependent and
  exploratory, not as independent inferential samples

### Current Bottom Line

This session did not resolve the final interval design, but it did
substantially strengthen the exploratory workflow.

The project now has:

- a documented first-pass hydrology join for `RS 30`
- first-pass metric-versus-peak-flow plots
- explicit treatment of the short-interval problem
- two alternate interval-partitioning schemes for robustness checks
- a much better commented exploratory script that records decisions in
  plain language

The main unresolved issue carried forward is how to handle the
`2011-2012` interval and, more broadly, how much weight to give the raw
consecutive sequence versus the alternate partition variants.

### 2026-03-27 Continuation: RS 30 modeling reflection and hydrology pivot

This continuation records what changed after the original first-pass interval
plots and why the project is now pivoting toward richer forcing metrics.

#### What was added

- `scripts/01e_pendleton_synthetic_peaks.R`
  - builds a synthetic Pendleton (`14020850`) annual-peak series back to WY
    `1952` using the same manual MOVE.3-style extension logic already used in
    `01d`
  - uses the corrected `14033500` series from `01c` as the primary synthetic
    Pendleton record for geomorphic interval work
  - writes `data/pendleton_synthetic_peaks.csv`
- `scripts/rs30_interval_sandbox.R`
  - now points at `data/pendleton_synthetic_peaks.csv` for RS 30 interval
    forcing
  - now computes `jaccard_change` as a dimensionless interval change metric:
    `1 - overlap / union`
- `scripts/rs30_modeling_sandbox.R`
  - sources `rs30_interval_sandbox.R`
  - stages exploratory linear modeling objects with `broom`
  - includes serial exclusion-rule fits for:
    - `symmetric_change_ft2_per_year`
    - `new_area_ft2_per_year`
    - `abandoned_area_ft2_per_year`
  - includes a response-matrix scan across existing response metrics,
    including `jaccard_change`

#### Current substantive interpretation

- The synthetic Pendleton record solved the coverage problem for the photo
  interval series. RS 30 forcing can now span the HMA period rather than
  truncating at the observed Pendleton record start.
- The `2011-2012` interval is currently treated as spurious in the modeling
  sandbox and excluded from all exploratory modeling objects.
  - Reason: visual review of the air photos suggests the mapped magnitude of
    change in the `2009-2012` HMA sequence is not commensurate with the peak
    flow story implied by the current data products.
  - Planned follow-up: contact the DOGAMI / dataset authors to understand how
    the `2009-2012` HMA products were developed before deciding whether that
    interval should ever be reinstated.
- Peak-flow-only models remain weak.
  - Multiple response variables were tried, including area-based rates and the
    dimensionless `jaccard_change` metric.
  - None of the first-pass peak-only linear relationships looked strong enough
    to inspire confidence as a forecasting model by themselves.
- Even so, a few qualitative patterns remain physically suggestive.
  - In particular, the negative relationship between `abandoned_area` and peak
    flow feels geomorphically coherent: larger floods appear more likely to
    recruit or reoccupy corridor area than to abandon it, barring a large
    avulsion into a wholly new path.

#### Why the project is pivoting

The long-term objective is not just to explain past RS 30 interval behavior,
but to build a response model that can be paired with climate-scenario
hydrology to estimate how channel-change magnitude may shift in the future.

That objective now points away from continuing to shuffle response variables in
isolation and toward developing better interval-scale forcing metrics. The key
insight from this session is that peak annual maximum flow alone is probably
too weak a proxy for geomorphic work at this reach and interval scale.

#### Next major workflow

Build a parallel hydrology data-ingestion and munging workflow centered on
daily discharge, using `dataRetrieval`.

Current lean for that workflow:

- create a new hydrology-acquisition branch of the pipeline that pulls at least
  daily flow series for the relevant gages
- treat daily data as the base product and derive interval-scale forcing
  metrics from it later
- defer 15-minute ingestion for now because it is likely bulkier than needed
  for the first round of interval forcing development, even though it remains a
  viable later option
- prioritize interval-scale metrics that can also be computed from future
  climate-scenario hydrographs, especially:
  - duration above threshold
  - count of threshold exceedances
  - cumulative exceedance above threshold
  - other cumulative high-flow summaries

In other words: the exploratory RS 30 response-side work was useful, but the
next promising source of signal is richer hydrologic forcing derived from daily
records rather than more permutations of peak-only models.
