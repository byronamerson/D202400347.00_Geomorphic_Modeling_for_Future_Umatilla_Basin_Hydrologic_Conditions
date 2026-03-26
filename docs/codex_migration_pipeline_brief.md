# Codex Task Brief: R-Native Channel Migration Metrics Pipeline
## Upper Umatilla River, RS 25–30 — Exploratory Phase

---

## 0. IMMEDIATE GOAL

Produce preliminary scatter plots of HMA-derived migration metrics (y-axis)
against peak discharge in the photo interval (x-axis) for upper Umatilla River
segments 25–30. We are in **exploratory mode** — get plots on screen first,
refine later. Fancy stuff like Jaccard indices and left/right directionality
comes in a later pass.

---

## 1. PACKAGE AUDIT

### 1.1 Packages almost certainly already installed

These are core to the existing project codebase and R scripts on hand:

```r
library(sf)            # All spatial overlay operations (intersection, difference, sym_difference, union, buffer)
library(dplyr)         # Data wrangling
library(tibble)        # Tidy data frames
library(ggplot2)       # Plotting
library(tidyverse)     # Meta-package (already in 01_hydrology_acquisition.R)
library(dataRetrieval) # USGS gage data (already in 01_hydrology_acquisition.R)
library(lubridate)     # Date handling (already in 01_hydrology_acquisition.R)
```

### 1.2 Packages that may need installation

Check availability and install as needed:

```r
# Centerline extraction from polygons (CRAN, Dec 2025)
# Replaces SCS Toolbox M1 — Voronoi skeleton via GEOS
# install.packages("centerline")
library(centerline)

# Hole removal from polygons (CRAN)
# Replaces the hollow-filling loops in M1/M2/M3
# install.packages("nngeo")
library(nngeo)    # nngeo::st_remove_holes()

# Fast zonal stats for raster-polygon operations (CRAN)
# Replaces M4's ZonalStatisticsAsTable if we get to HACH later
# install.packages("exactextractr")
library(exactextractr)

# Low-level GEOS bindings — dependency of centerline, may already be present
# install.packages("geos")
library(geos)

# lwgeom for advanced geometry operations (snap, split, etc.)
# install.packages("lwgeom")
library(lwgeom)
```

### 1.3 Packages NOT needed (noted for avoidance)

- `rgdal`, `rgeos`, `sp` — all retired; sf/terra/geos replace them
- `raster` — use `terra` instead
- `arcpy` / `reticulate` bridge — we are going R-native, no Python dependency
- `cmgo` — GitHub-only, uses legacy `spatstat.geom` + `sp`; the `centerline`
  package is the modern CRAN equivalent for our needs

### 1.4 First-step audit script

Run this to check what's present and what needs installing:

```r
required_packages <- c(
 "sf", "dplyr", "tibble", "ggplot2", "tidyverse",
 "dataRetrieval", "lubridate",
 "centerline", "nngeo", "exactextractr", "geos", "lwgeom", "terra"
)

installed <- installed.packages()[, "Package"]
missing <- setdiff(required_packages, installed)

if (length(missing) > 0) {
 message("Packages to install: ", paste(missing, collapse = ", "))
 install.packages(missing)
} else {
 message("All required packages are installed.")
}
```

---

## 2. SCS TOOLBOX → R CROSSWALK

The SCS Toolbox (Rusnák et al. 2025) has four Python/arcpy modules. Below is
what each does and how to achieve the same result in R. The original Python
scripts are on the local drive for reference if needed.

### 2.1 M1: Centerline Extraction

**What it does:** Takes channel polygons (one per date), fills interior holes,
densifies vertices, builds Voronoi tessellation clipped to polygon, converts
Voronoi edges to lines, filters out boundary-touching and perpendicular stubs
(keeps lines where angle difference from nearest bank is 50°–130°), dissolves
and cleans short fragments (<4 vertices), extends endpoints to polygon boundary.
Two modes: (a) individual centerlines per date, (b) single "segmentation
centerline" from the union of all polygons.

**R equivalent:**

```r
library(centerline)
library(sf)
library(nngeo)

# Step 1: Fill holes in polygon
poly_clean <- nngeo::st_remove_holes(hma_polygon)

# Step 2: Extract skeleton
skeleton <- cnt_skeleton(poly_clean, keep = 1)
# keep = 1 preserves original vertex density
# keep < 1 simplifies (fewer skeleton branches)
# keep > 1 densifies (smoother but larger output)

# Step 3: Extract centerline path
# If you know upstream/downstream points:
cl <- cnt_path(skeleton, start_point, end_point)
# If you don't:
cl <- cnt_path_guess(poly_clean)
# cnt_path_guess connects the two most distant boundary points
```

**For the segmentation centerline (union of all dates):**

```r
hma_union <- st_union(all_hma_polygons) |> st_remove_holes()
union_skeleton <- cnt_skeleton(hma_union, keep = 1)
seg_centerline <- cnt_path(union_skeleton, upstream_pt, downstream_pt)
```

**Key difference from arcpy:** The `centerline` package uses GEOS
`geos_voronoi_edges()` instead of arcpy `CreateThiessenPolygons`. Same
underlying algorithm (Voronoi of boundary vertices), different implementation.
The angle-based filtering that M1 does manually is handled internally by the
skeleton-to-path extraction in `cnt_path()`.

### 2.2 M2: DGO Segmentation

**What it does:** Takes the segmentation centerline from M1, generates equally
spaced points along it, splits the centerline at those points, creates Thiessen
polygons from segment midpoints, clips to the union channel polygon. Output:
transverse polygon "slices" (DGOs) with sequential ID and known interval length.

**R equivalent:**

```r
# Parameters
interval_m <- 200  # DGO length in meters (or feet, match your CRS units)

# Step 1: Generate equally spaced points along centerline
sample_pts <- st_line_sample(seg_centerline, density = 1 / interval_m)
sample_pts <- st_cast(sample_pts, "POINT")

# Step 2: Voronoi tessellation from points
voronoi_raw <- st_voronoi(st_union(sample_pts))
voronoi_polys <- st_collection_extract(voronoi_raw, "POLYGON")
voronoi_sf <- st_sf(geometry = voronoi_polys)

# Step 3: Clip to union channel polygon
dgos <- st_intersection(voronoi_sf, hma_union)

# Step 4: Add sequential ID
dgos$ID_SEQ <- seq_len(nrow(dgos))
dgos$interval_length <- interval_m
```

**Note:** This is the Alber & Piégay (2011) DGO framework. Each slice has a
known length, so `polygon_area / interval_length = local corridor width`. This
also gives you the correct denominator for length-normalizing migration metrics.

### 2.3 M3: Erosion/Accretion Calculation

**What it does (simplified):** For each consecutive date pair:
1. Unions both channel polygons, fills holes
2. Computes erosion (area in older not in younger) and deposition (area in
   younger not in older) polygons
3. Classifies islands (holes within channel polygons)
4. Labels each fragment: erosion, deposition, stable, hollow, island_erosion,
   island_deposition
5. Creates left/right orientation mask by single-sided buffering of both
   centerlines, intersects EA polygons with mask → directional labels like
   erosion_LEFT, deposition_RIGHT
6. If DGO segments provided, intersects EA polygons with DGOs and computes:
   - `EA_rate_A` = area / time_span (area-based rate)
   - `EA_rate_m` = (area / time_span) / DGO_interval (linear migration rate)

**R equivalent of the core overlay (what the existing sandbox script already does):**

```r
# This is already implemented in compute_interval_metrics()
overlap        <- st_intersection(hma_t1, hma_t2)   # stable
new_area       <- st_difference(hma_t2, hma_t1)     # erosion (corridor expansion)
abandoned_area <- st_difference(hma_t1, hma_t2)     # deposition (corridor contraction)
sym_change     <- st_sym_difference(hma_t1, hma_t2) # total reworked
```

**R equivalent of the left/right orientation mask (future enhancement):**

```r
# Requires a centerline for the date pair (from M1 step above)
# sf::st_buffer with singleSide = TRUE
# Positive dist = left of line direction; negative = right
# Line direction must be consistent (e.g., always upstream → downstream)

# Make a large single-sided buffer that covers the full corridor
buffer_dist <- 5000  # feet or meters, larger than max corridor width

left_mask  <- st_buffer(centerline, dist = buffer_dist, singleSide = TRUE)
right_mask <- st_buffer(centerline, dist = -buffer_dist, singleSide = TRUE)

# Classify erosion polygons by side
erosion_left  <- st_intersection(new_area, left_mask)
erosion_right <- st_intersection(new_area, right_mask)
depo_left     <- st_intersection(abandoned_area, left_mask)
depo_right    <- st_intersection(abandoned_area, right_mask)
```

**Important:** `singleSide = TRUE` only works with projected CRS (GEOS engine).
The Umatilla data is already projected, so this is fine. Also, line direction
matters — ensure centerlines always run upstream to downstream (or vice versa,
consistently) so "left" and "right" are geomorphically meaningful.

**NOT implementing left/right in this first pass.** The directional labeling is
a refinement for later. For the exploratory plots, the undirected metrics from
the existing sandbox script are sufficient.

### 2.4 M4: Floodplain Statistics (FAM, HACH, CHM)

**What it does:**
- Floodplain Age Map (FAM): unions all dated polygons, tags each fragment with
  the most recent year of channel occupation
- Height Above Channel (HACH): extracts DEM elevations along a flow path,
  interpolates a water-surface trend raster (TopoToRaster), subtracts from DEM
- Canopy Height Model (CHM): DSM minus DEM
- Zonal statistics per DGO segment

**R equivalent (deferred — not needed for exploratory plotting):**

```r
# FAM — straightforward sf overlay
all_union <- st_union(all_dated_polygons) # or use reduce(st_union)
# Then overlay individual date polygons and tag with max year

# HACH — terra raster operations
# library(terra)
# water_surface <- terra::interpIDW(flow_pts_with_elev, dem_raster)
# hach <- dem_raster - water_surface

# Zonal stats
# library(exactextractr)
# exact_extract(hach_raster, dgo_polygons, fun = c("mean", "min", "max", "stdev"))
```

---

## 3. THE EXISTING R SCRIPT: rs30_interval_sandbox.R

### 3.1 What it already does

The script reads HMA and CMZ layers from the DOGAMI geodatabase, isolates RS 30,
clips dated HMA polygons to the segment, builds consecutive date-pair intervals,
and computes polygon overlay metrics for each interval.

**Current metric outputs per interval:**

| Metric | Description |
|--------|-------------|
| `area_t1_ft2` / `area_t2_ft2` | HMA polygon area at each date |
| `overlap_ft2` | Area occupied at both dates (stable corridor) |
| `new_area_ft2` | Area at t2 not at t1 (corridor expansion / erosion into floodplain) |
| `abandoned_area_ft2` | Area at t1 not at t2 (corridor contraction) |
| `symmetric_change_ft2` | Total reworked area (new + abandoned) |
| `net_area_change_ft2` | area_t2 - area_t1 |
| `*_per_year` variants | Annualized versions of above |
| `symmetric_change_ft2_per_year_per_ft` | Channel activity index (but see normalization issue below) |

### 3.2 Known issue: segment length normalization

The script uses `Shape_Length` from the CMZ polygon (perimeter) as the
denominator for the activity index. This is wrong — it should be the **reach
centerline length** or **valley-axis length**.

**Fix options (in order of ease):**
1. Use the `Shape_Length` of the **stream centerline** if available in the
   geodatabase (check for a centerline layer)
2. Extract centerline from the union HMA polygon using `centerline::cnt_path()`
   and measure its length with `st_length()`
3. Use the valley-axis length if a valley centerline exists

For the exploratory pass, option 1 or 2 is fine. The absolute values of
length-normalized metrics will change, but the relative ranking across intervals
won't.

### 3.3 What needs to be added for plotting

The script produces `rs30_interval_metrics` — a tibble with one row per interval.
To plot against peak flows, we need to:

1. **Join interval metrics to peak flow data.** Each interval (year_t1, year_t2)
   needs the maximum peak discharge from the USGS gage record during that
   period. The hydrology scripts (`01_hydrology_acquisition.R`) pull peak flows
   from three gages. For the upper river (RS 25–30), use:
   - USGS 14020850 (Umatilla R at W Reservation Boundary nr Pendleton) — mid gage
   - Or USGS 14020000 (above Meacham Cr nr Gibbon) — upstream gage
   The mid gage (14020850) is probably the best match for RS 25–30 but check
   drainage area relative to the segment locations.

2. **Extract interval peak Q.** For each (year_t1, year_t2) pair, find:
   ```r
   # Pseudocode
   interval_peaks <- peak_flows %>%
     filter(peak_date >= as.Date(paste0(year_t1, "-01-01")),
            peak_date <= as.Date(paste0(year_t2, "-12-31"))) %>%
     summarise(
       q_peak_max = max(peak_q_cfs),
       n_peaks = n()
     )
   ```

3. **Make scatter plots.** Three panels for the first pass:
   - `new_area_ft2_per_year` vs `q_peak_max` — corridor expansion rate vs peak Q
   - `symmetric_change_ft2_per_year` vs `q_peak_max` — total reworking vs peak Q
   - `net_area_change_ft2_per_year` vs `q_peak_max` — net change vs peak Q

   Label each point with the interval (e.g., "1974–1976"). Use `ggplot2` with
   `geom_point()` + `geom_text()` or `ggrepel::geom_text_repel()`.

### 3.4 Extending to RS 25–29

The script is structured for easy generalization. The `select_cmz_segment()`
helper takes a `target_segment` argument. To extend:

```r
target_segments <- 25:30

all_segment_metrics <- map_dfr(target_segments, function(seg_id) {
  rs_cmz <- select_cmz_segment(cmz, seg_id)
  rs_length <- rs_cmz %>% st_drop_geometry() %>%
    summarise(len = sum(Shape_Length)) %>% pull(len)
  rs_hma <- clip_dated_hma_to_segment(hma, rs_cmz, config$composite_note)
  rs_years <- summarize_segment_hma_years(rs_hma)
  rs_intervals <- make_consecutive_intervals(rs_years)
  products <- build_interval_products(rs_hma, rs_intervals, rs_length)
  products$interval_metrics %>% mutate(segment = seg_id)
})
```

Then join to peak flows and facet plots by segment.

---

## 4. PRIORITY METRICS FOR FIRST EXPLORATORY PLOTS

From the previous methods review, ranked by immediate utility:

### Tier 1 — Plot these first

1. **New area rate (length-normalized):** `new_area_ft2 / (centerline_length * Δt)`
   This is the WA Channel Migration Toolbox's "reach-average migration distance"
   (Legg et al. 2014). Most directly interpretable as "how much new floodplain
   did the corridor eat in this interval?"

2. **Channel activity index:** `symmetric_change_ft2 / (centerline_length * Δt)`
   Total reworked area per unit length per year. Captures both expansion AND
   lateral shift. If the corridor translated without growing, new_area_rate
   misses it but this catches it.

### Tier 2 — Add if time permits

3. **Expansion ratio:** `new_area / abandoned_area`
   Dimensionless. >1 = net corridor growth; <1 = net contraction; ≈1 = lateral
   shift without size change.

4. **Net area change rate:** `(area_t2 - area_t1) / Δt`
   Positive = corridor growing, negative = shrinking. Less informative than
   Tier 1 due to cancellation.

### Tier 3 — Later refinement pass

5. Jaccard distance = `1 - overlap / (area_t1 + area_t2 - overlap)`
6. Left/right directional erosion rates (requires centerline extraction)
7. DGO-level disaggregation (spatially distributed metrics along reach)

---

## 5. PEAK FLOW DATA STRUCTURE

The hydrology script (`01_hydrology_acquisition.R`) produces:

- `peak_flows_tbl`: tibble with columns `gage_id`, `peak_date`, `peak_q_cfs`
- `flood_freq_tbl`: tibble with `gage_id`, `return_period_yr`, `q_cfs`

For interval matching, we need the **Q₂ estimate** (bankfull proxy) from the
flood frequency analysis to also compute cumulative excess discharge if we want
it later. But for the first pass, just extract max peak Q per interval.

**Gage assignment for upper river:**
- RS 28–30+: USGS 14020850 (mid gage, DA = 441 mi²) is the best spatial match
- RS 25–27: also 14020850, or possibly 14020000 (upstream, DA = 131 mi²) if
  these segments are above the Meacham Creek confluence

Check segment positions against gage locations to assign correctly. This matters
because the upstream gage misses Meacham Creek tributary inflows.

---

## 6. SUGGESTED IMPLEMENTATION ORDER

1. **Package audit** — run the audit script from §1.4
2. **Fix segment length** — check geodatabase for a centerline layer, or
   extract one from the union HMA polygon using `centerline::cnt_path_guess()`
3. **Pull peak flows** — run the data retrieval portion of
   `01_hydrology_acquisition.R` (or load saved .rds if already run) to get
   `peak_flows_tbl`
4. **Build interval-peak join** — for each (year_t1, year_t2), extract max
   peak Q from the appropriate gage
5. **Extend to RS 25–30** — generalize the sandbox script across segments
6. **Plot** — `ggplot2` scatter panels: metric vs Qpeak, faceted or colored
   by segment
7. **Iterate** — adjust, add secondary metrics, refine

---

## 7. DATA PATHS

```
# DOGAMI geodatabase (primary spatial data source)
data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb
  Layers:
    - Umatilla_River_HMA   (20 dated polygons: 1952–2022)
    - Umatilla_River_CMZ   (39 segment polygons)
    - [check for centerline layer — may exist as intermediary]

# Hydrology outputs (from 01_hydrology_acquisition.R)
# Saved as .rds files — check data_out/ or equivalent output directory
# Contains: daily_flows_tbl, peak_flows_tbl, flood_freq_tbl

# SCS Toolbox Python scripts (reference only, not for execution)
# On local drive — M1_centerline.py, M2_segmentation.py,
# M3_EAcalculation.py, M4_FloodplainStat.py
```

---

## 8. KEY REFERENCE: EXISTING SANDBOX SCRIPT STRUCTURE

The `rs30_interval_sandbox.R` script follows this pattern:

```
read_gdb_layer()              → sf objects (hma, cmz)
select_cmz_segment()          → single segment polygon
clip_dated_hma_to_segment()   → dated HMA polygons within segment
summarize_segment_hma_years() → tibble of available years
make_consecutive_intervals()  → tibble of (year_t1, year_t2, interval_years)
make_year_geometry()           → union geometry for one year within segment
compute_interval_metrics()    → tibble of overlay metrics for one interval
build_interval_products()     → list(yearly_geometries, interval_metrics)
```

All helpers are pure functions (sf in, tibble/geometry out). The
`compute_interval_metrics()` function is the core — it takes two geometries and
returns area-based metrics. Extend it or compose around it; don't need to
rewrite it.

---

## 9. WHAT NOT TO DO IN THIS PASS

- Don't extract per-date centerlines (save for left/right directionality later)
- Don't build DGO segments (reach-average is sufficient for flood-response plots)
- Don't compute specific stream power (no wetted width time series)
- Don't worry about uncertainty quantification (Donovan et al. 2019 / Lea &
  Legleiter 2016 frameworks are for later)
- Don't try to run the SCS Python scripts — we're going R-native
- Don't install cmgo — it uses retired sp/spatstat dependencies
