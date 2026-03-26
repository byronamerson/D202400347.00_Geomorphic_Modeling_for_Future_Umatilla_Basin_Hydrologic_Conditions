# Notes: O-25-10_report_Dec23

## Document Control
- Source PDF: `docs/O-25-10_report_Dec23.pdf`
- Derived folder: `docs/derived/O-25-10_report_Dec23`
- Page count: 79
- Sparse extracted pages: none detected

## Structural Map
- 
  - CHANNEL MIGRATION ZONE MAPS FOR UMATILLA RIVER AND LOWER MCKAY CREEK, UMATILLA COUNTY, OREGON
  - Table of Contents
  - List of Figures
  - Geographic Information System (GIS) Data
  - Spreadsheets
  - UNITS OF MEASUREMENT
  - Executive Summary
  - 1.0   INTRODUCTION
    - 1.1   Purpose and Study Area
    - 1.2   Overview of the Hazards of Channel Migration
    - 1.3   Umatilla County
    - 1.4   Umatilla River and Lower McKay Creek
      - 1.4.1   Geology
      - 1.4.2   Hydrology
        - 1.4.2.1   Recent Flooding
        - 1.4.2.2   Climate Change
      - 1.4.3   Geomorphology
        - 1.4.3.1   Upper Umatilla River
        - 1.4.3.2   Middle Umatilla River
        - 1.4.3.3   Lower Umatilla River
        - 1.4.3.4   Lower McKay Creek
      - 1.4.4   Historical Changes
  - 2.0   METHODS
    - 2.1   Overview
    - 2.2   Data Sources
      - 2.2.1   Topographic Data
      - 2.2.2   Aerial Imagery
      - 2.2.3   Geology
      - 2.2.4   Infrastructure
      - 2.2.5   Local Geomorphic and Channel Migration History
      - 2.2.6   Flood History
    - 2.3   Channel Migration Zone Mapping
      - 2.3.1   Active Channel (AC)
      - 2.3.2   Historical Migration Area (HMA)
      - 2.3.3   Modern Valley Bottom (MVB)
      - 2.3.4   River Segments (RS)
      - 2.3.5   Erosion Hazard Area (EHA)
      - 2.3.6   Avulsion Hazard Area (AHA)
      - 2.3.7   Flagged
      - 2.3.8   Channel Migration Zone (CMZ)
  - 3.0   RESULTS
    - 3.1   Umatilla River
      - 3.1.1   Upper Umatilla River
      - 3.1.2   Middle Umatilla River
      - 3.1.3   Lower Umatilla River
    - 3.2   Lower McKay Creek
  - 4.0   DISCUSSION AND RECOMMENDATIONS
    - 4.1   Umatilla River
    - 4.2   Lower McKay Creek
    - 4.3   Comparison to Other Studies
    - 4.4   Applications for Data and Maps
    - 4.5   Limitations of Data and Maps
    - 4.6   Recommendations and Future Studies
  - 5.0   ACKNOWLEDGMENTS
  - 6.0   REFERENCES

## Keyword Index
- `CMZ`: 93 hits on pages 4, 7, 8, 9, 10, 28, 29, 30, 32, 33, 40, 41, 42, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 65, 66, 67, 68, 69, 74
- `EHA`: 38 hits on pages 4, 7, 8, 10, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 38, 40, 41, 42, 65, 67
- `avulsion`: 37 hits on pages 8, 9, 10, 18, 28, 38, 39, 41, 42, 43, 59, 65, 66, 68, 77
- `HMA`: 34 hits on pages 3, 4, 7, 8, 12, 13, 18, 28, 29, 30, 31, 32, 33, 34, 36, 37, 38, 40, 41, 42, 59, 65, 73
- `AHA`: 25 hits on pages 4, 7, 8, 28, 29, 30, 32, 38, 39, 40, 41, 42, 43, 65, 66, 69, 73
- `flagged`: 25 hits on pages 4, 8, 28, 29, 30, 32, 39, 40, 41, 42, 43, 44, 59, 65, 68
- `study area`: 19 hits on pages 3, 4, 9, 11, 12, 18, 20, 30, 31, 32, 41, 63, 67, 68, 69
- `aerial imagery`: 14 hits on pages 4, 19, 22, 23, 25, 30, 32, 33, 38, 43, 59
- `methods`: 9 hits on pages 2, 3, 28, 30, 63, 68, 69
- `river segment`: 4 hits on pages 8, 28, 33, 41
- `active channel`: 3 hits on pages 8, 28, 32

## Derived Artifacts
- `pdf_info.json` stores basic metadata and page count.
- `toc.json` stores the table of contents structure returned by `pdftools`.
- `pages.csv` stores one row per page with raw and cleaned text.
- `keyword_hits.csv` stores page-cited keyword hits.
- `page_text.md` stores readable extracted text for every page.

## Working Notes
- Section `2.1` provides the study's core definitions for `AC`, `HMA`, `EHA`,
  `AHA`, `Flagged`, `MVB`, and `RS`.
- `HMA` is defined as the combined areas occupied by current and past active
  channels visible in the historical record, including the active channel
  itself.
- `RS` is defined as a section of river with relatively similar hydrologic and
  geomorphic characteristics; in this study, RS are typically about
  `8,000-14,000 ft` long.
- The report states that the `CMZ` is intended to represent the area where the
  stream is most likely to move laterally over the next `30` and `100` years.
- In the detailed mapping workflow, the final `CMZ` is created by merging the
  low-hazard `EHA` and the `AHA`, because the low-hazard `EHA` already
  encompasses the inner erosion-hazard components.

### Time-Step Analysis Notes
- Historical imagery used for `HMA` delineation is listed as:
  `1952`, `1964 (partial)`, `1965 (partial)`, `1974 (partial)`,
  `1976 (partial)`, `1977 (partial)`, `1981`, `1995`, `2000`, `2005`,
  `2009`, `2011`, `2012`, `2014`, `2016`, `2017`, `2022`, and `2024`.
- The methods section gives year-level image timing only. It does not, in the
  extracted text reviewed so far, provide month or exact acquisition dates for
  those historical images.
- Several early years are explicitly labeled `partial`, which will matter for
  any future segment-by-segment incremental migration calculation between
  consecutive time steps.
- The `2024 AC` was delineated from the most recent aerial imagery, with lidar
  slope maps and REMs used where banks were obscured by vegetation or where
  recent channel movement post-dated lidar collection.
- After mapping the `AC`, DOGAMI digitized a stream centerline and generated
  stream stations every `100 ft` along the middle of the active channel.
- Average `AC` width was measured from cross-sectional transects clipped to the
  `AC` boundary.
- `HMA` polygons were mapped from historical aerial photographs at `1:4,000`
  scale or finer, and lidar DEMs plus REMs were used to verify channel
  position where imagery interpretation was uncertain.
- `RS` were defined using changes in slope, valley width, channel confinement,
  channel pattern, discharge at major tributaries, infrastructure, geology,
  land use, and `HMA` width.

### Implications For Planned Segment-By-Time-Step Analysis
- A `segment x image year` analysis frame is consistent with DOGAMI's own
  workflow because `RS` are the organizing unit for width, sinuosity, erosion
  rates, and spreadsheet summaries.
- The `HMA` layer should be treated as a time-indexed footprint of wetted or
  active-channel occupation derived from the available imagery, but any
  time-step comparison will need to account for years with only `partial`
  coverage.
- A future mean wetted-width metric by `segment x time step` is conceptually
  aligned with DOGAMI's `AC` width workflow, even if our implementation uses
  historical `HMA` polygons rather than only the `2024 AC`.
- If we want to correlate wetted width with discharge on the image date, the
  report may not be sufficient on its own because it currently provides year
  coverage but not exact acquisition dates. Those may need to come from source
  imagery metadata or external imagery catalogs.

### Chapter 2 Reconciliation Summary
- The `Umatilla_River_HMA` layer does not map cleanly one-to-one onto the
  imagery year list written in the report.
- The `HMA` attribute table contains polygons for
  `1952, 1964, 1965, 1974, 1976, 1977, 1981, 1995, 2000, 2005, 2009, 2011,
  2012, 2014, 2016, 2017, 2020, 2022`, plus one polygon with `Year = NA`.
- The report's imagery list includes `2024`, but `2024` is not present as a
  `Year` value in the `HMA` layer.
- The report explicitly states that the `2024 AC` was digitized from the most
  recent imagery, which supports the interpretation that `2024` primarily lives
  in the `AC` layer rather than as a separate dated `HMA` polygon.
- The single `2020` polygon in `HMA` is not described in the report's imagery
  year list, but it is consistent with the report's repeated emphasis on the
  geomorphic importance of the February `2020` flood and with the report's more
  general references to imagery availability through the `2020s`.
- The `Year = NA` polygon has the note:
  `Merged 1952-2022 historical and 2024 active channel. Small gaps filled in.`
- That note strongly suggests the `NA` polygon is a merged composite product,
  not an individual time-step polygon.
- Working interpretation: for time-step analysis, the likely usable dated HMA
  sequence is `1952` through `2022`, including `2020`; the `NA` polygon should
  be treated as a derived composite and excluded from incremental time-step
  calculations unless a later use case specifically calls for the merged HMA
  envelope.
- Working interpretation: `2024` should currently be treated as the `AC` date,
  not as a normal `HMA$Year` level, unless additional metadata show that DOGAMI
  intended it to function as the terminal HMA state as well.

### Chapter 3 Segment Analysis Readiness
- `CMZ` segment IDs are analysis-ready as an organizing frame: the geodatabase
  contains `39` unique `RIverSegment` values for the Umatilla River.
- The report organizes the Umatilla River by three larger spatial groupings:
  lower river `RS 1-14`, middle river `RS 15-27`, and upper river `RS 28-39`.
- The existing project interpretation in
  `scripts/02_reach_attributes_and_scaling.R` states that RS numbering runs
  downstream to upstream, with `RS 1` at the mouth and `RS 39` upstream. That
  interpretation is consistent with the report's lower/middle/upper grouping.
- Every dated `HMA` polygon intersects at least one `CMZ` segment, and every
  `CMZ` segment intersects at least one dated `HMA` polygon.
- Later dated `HMA` polygons (`1981`, `1995`, `2000`, `2005`, `2009`, `2011`,
  `2012`, `2014`, `2016`, `2017`, `2020`, `2022`) intersect all `39` segments,
  which means the full segment framework is available for later-period analyses.
- Several early dated `HMA` polygons are spatially partial and only intersect a
  subset of segments. Examples:
  `1964` appears in multiple polygons covering different segment groups,
  `1965` intersects about `RS 12-22`, `1974` intersects about `RS 24-39`,
  and `1976` intersects about `RS 17-24`.
- This confirms that segment-by-time-step analysis is feasible, but it also
  confirms that early years should not be treated as if they provide full-river
  coverage.
- The segment framework is therefore ready for analysis, but any future table of
  observations should distinguish between:
  1. years with full `RS 1-39` coverage
  2. years with only partial segment coverage
- The workbook structure reinforces this framing: all four tabs in
  `Umatilla_River_CMZ_Summary.xlsx` cover the full `RS 1-39` sequence and serve
  as segment-level summary products rather than time-step products.
- Working interpretation: the most robust first prototype analysis will likely
  focus on a user-chosen subset of segments within the later years that have
  full coverage, then selectively extend backward into partial early years once
  the handling rules are explicit.

### Chapter 4 Measurement Design
- The natural analysis unit is a `segment x time step` observation, where a
  time step is a pair of dated channel states that can be compared within the
  same `RIverSegment`.
- The report already uses both areal and width-normalized migration language,
  which suggests that our own future metrics should include at least one
  area-based measure and one width-based measure.
- The report's EHA workflow also uses `channel widths/year` as a normalized
  erosion-rate unit, which makes width-normalized migration metrics especially
  attractive for later comparison to DOGAMI-derived values.

#### Candidate Incremental Migration Metrics
- `Newly occupied area`: area present in time `t2` but not in time `t1` within a
  segment. This aligns well with the report's own summary language about the
  channel occupying `new acres` over multi-year periods.
- `Abandoned area`: area present in time `t1` but not in time `t2` within a
  segment. This complements newly occupied area and helps distinguish sweeping
  lateral translation from simple expansion.
- `Symmetric change area`: the union of newly occupied and abandoned area. This
  is a compact measure of total planform change between two time steps.
- `Net area change`: area at `t2` minus area at `t1` within a segment. This is
  easy to compute but is not sufficient on its own because opposing gains and
  losses can cancel.
- `Migration rate by elapsed years`: any of the above area measures divided by
  the number of years between image dates. This is the most obvious way to make
  irregular time intervals comparable.

#### Candidate Width Metrics
- `Mean wetted width`: wetted or active-channel area within a segment divided by
  a segment length measure. This is likely the most stable first-pass width
  metric if polygon geometry is the primary input.
- `Transect-based mean width`: reproduce DOGAMI's logic more directly by
  intersecting regularly spaced transects with the polygon at each time step and
  averaging widths within a segment.
- `Width change`: difference in mean wetted width between `t1` and `t2`.
- `Relative width change`: width change divided by baseline width at `t1`.

#### Candidate Normalized Migration Metrics
- `Area change per segment length`: incremental changed area divided by segment
- length. This gives a width-like quantity that is easy to interpret.
- `Area change relative to baseline wetted area`: symmetric or newly occupied
  area divided by area at `t1`. This is useful for comparing narrow and wide
  segments.
- `Width-normalized migration`: change area per segment length, divided by mean
  wetted width. This would make the metric more comparable across differently
  sized segments.

#### Recommended First Prototype Metrics
- `new_area_ft2`
- `abandoned_area_ft2`
- `symmetric_change_ft2`
- `elapsed_years`
- `new_area_ft2_per_year`
- `symmetric_change_ft2_per_year`
- `mean_wetted_width_ft_t1`
- `mean_wetted_width_ft_t2`
- `delta_mean_wetted_width_ft`

#### Recommended First Prototype Logic
- Use later full-coverage years first so that segment availability is not the
  main complication in the prototype.
- Use consecutive dated observations as the default comparison pairs, but keep
  the pairing logic explicit because the intervals are irregular.
- Exclude the composite `Year = NA` polygon from time-step metrics.
- Treat `2024 AC` as a possible terminal comparison state only after we decide
  whether mixing `HMA` and `AC` products is methodologically acceptable.
- Record whether each time step is based on full or partial segment coverage so
  downstream analysis does not silently mix those cases.

#### Design Risks And Caveats
- `Partial` imagery years may make some segment-year observations structurally
  incomparable to full-coverage years.
- Year-only image timing means any later hydrology linkage will initially be
  coarse unless image acquisition dates can be recovered.
- Polygon differencing can confound true lateral migration with widening,
  narrowing, and avulsion. That is not necessarily a flaw, but it means the
  chosen metric must be described carefully.
- Segment length must be defined consistently. Options include the report's
  stream-station length, CMZ-derived longitudinal length, or a centerline-based
  measure generated in our own workflow.

#### Working Recommendation
- For a first exploratory analysis, the best metric family is probably:
  `segment-level polygon differencing + mean wetted width by time step`.
- In practical terms, that means:
  1. clip each dated `HMA` polygon to each segment
  2. compute area at each `segment x year`
  3. compute pairwise differences between consecutive time steps
  4. convert area to an implied mean width using a consistent segment length
  5. compare those values later to flood magnitude and stream power
- This keeps the first prototype interpretable, aligned with the report, and
  simple enough to revise once the behavior of the data is clearer.

### Chapter 5 Hydrology Linkage Readiness
- The repo already has a defined hydrology workflow in
  `scripts/01_hydrology_acquisition.R`.
- That script is designed to produce:
  `gage_metadata.csv`, `daily_flows.csv`, `peak_flows.csv`,
  `flood_frequency.csv`, `site_info.csv`, and `regional_skew.csv` in `data/`.
- The current `data/` directory does not yet contain those materialized outputs,
  so the hydrology linkage architecture exists in code but not yet as ready-made
  project tables.
- The reach-level hydraulic and stream-power workflow is already defined in
  `scripts/02_reach_attributes_and_scaling.R` and
  `scripts/03d_stream_power_context.R`.
- The current project logic links hydrology to river segments through three
  mainstem USGS gages:
  `14020000` (upstream), `14020850` (mid), and `14033500` (downstream).
- Existing stream-power calculations are reach- or segment-based, not
  time-step-based. They use segment slope, average width, gage assignment, and
  drainage-area scaling to estimate discharge and unit stream power.
- The existing workflow already computes or plans to compute:
  `Q2`, `Q5`, `Q10`, `Q50`, `Q100`, and associated `omega` values by reach.
- This means the repo is already structurally prepared for a static
  segment-level hydrology linkage, even before we build a time-step migration
  table.

#### Two Distinct Future Linkage Paths
- `Static segment context`: attach each segment's existing slope, average width,
  gage assignment, flood-frequency estimates, and reference stream power values.
  This is the easiest path and is mostly a matter of running the existing
  scripts or adapting their outputs.
- `Dynamic time-step linkage`: attach hydrologic information to each
  `segment x time step` migration observation. This is harder and depends on the
  precision of image dates and on what hydrologic summary we decide is most
  defensible.

#### What Appears Ready Now
- Segment-level gage assignment logic
- Segment-level slope and average width concepts
- Flood-frequency architecture for the mainstem gages
- Stream-power formulas and threshold framing

#### What Is Not Yet Ready
- Materialized hydrology tables in `data/`
- Exact image acquisition dates needed for same-day or same-week discharge joins
- A defined rule for how to summarize hydrology over irregular image intervals
- A time-step-specific width measure derived from the historical polygons

#### Candidate Hydrology Linkage Designs For Later
- `Image-date discharge`: if exact acquisition dates can be recovered, join each
  image year to daily discharge at the appropriate gage and use that to relate
  wetted width to flow state.
- `Seasonal discharge proxy`: if month or season but not exact date can be
  recovered, use monthly mean or seasonal flow summaries.
- `Interval forcing metrics`: for migration between `t1` and `t2`, summarize the
  hydrologic forcing during the interval using metrics such as annual peak flow,
  maximum stream power, number of threshold exceedances, or cumulative high-flow
  days.
- `Event-focused linkage`: if specific major floods like `2020` are known to
  dominate adjustment, explicitly tag intervals that include those events.

#### Working Recommendation
- For the first prototype, plan on two hydrology layers:
  1. a static segment context table with existing reach-scale hydrology and
     stream power
  2. a future dynamic table keyed to time steps once image-date precision is
  improved
- That separation lets the migration prototype proceed without waiting on exact
  acquisition dates, while still preserving a path toward more defensible
  time-step hydrology linkage later.

## Decision Agenda

### 1. Time-State Definition
- Should `2024 AC` be treated as the terminal channel state in time-step
  analysis, or should the dated `HMA` sequence stop at `2022`?
- Should the composite `Year = NA` polygon be ignored entirely for analysis, or
  retained for some later envelope-style comparison?

### 2. Coverage Rules
- How should `partial` imagery years be handled?
- Should partial years be excluded from the first prototype, included only for
  intersected segments, or used only qualitatively?

### 3. Segment Focus
- Which subset of segments should be used for the first prototype?
- Should the first prototype stay within one larger river grouping
  (`RS 1-14`, `RS 15-27`, or `RS 28-39`) or intentionally span contrasting
  settings?

### 4. Segment Length Definition
- Which segment length should be used to convert polygon area to mean wetted
  width?
- Candidate options include report stream-station length, workbook segment
  length, or a new centerline-based measure generated in our workflow.

### 5. Migration Metric Family
- Which first-pass metric should lead the exploratory analysis?
- Candidates include newly occupied area, abandoned area, symmetric change area,
  and width-based changes.
- Should the first prototype emphasize areal change, width change, or both in
  parallel?

### 6. Time-Step Pairing Rule
- Should the prototype use only consecutive dated states?
- Should longer interval comparisons also be included for sensitivity checks?

### 7. Hydrology Linkage Strategy
- Should the first linkage use static segment context only?
- Should interval-based forcing summaries be the first dynamic linkage?
- Is recovering exact image dates important enough to prioritize before any
  hydrology-migration analysis begins?

### 8. Prototype Scope
- Should the first prototype aim only to build a clean `segment x time step`
  table, or should it also produce first exploratory plots and correlations?
- What is the minimum useful prototype output for shared review?

## Open Questions
- Can the exact acquisition date or at least month be recovered for each image
  year used to digitize `HMA` polygons?
- How should `partial` imagery years be handled when computing incremental
  migration between consecutive time steps?
- Should `2024 AC` be paired with the historical `HMA` sequence as the terminal
  wetted-channel state in future time-step analyses, or should it be handled as
  a separate product type?
- Which segment subset should be the first prototype focus for the time-step
  migration analysis?
- Which segment length definition should be used for converting area to mean
  wetted width in the prototype workflow?
- Should the first migration-hydrology linkage use static segment context,
  interval-based forcing summaries, or attempt image-date discharge immediately?
