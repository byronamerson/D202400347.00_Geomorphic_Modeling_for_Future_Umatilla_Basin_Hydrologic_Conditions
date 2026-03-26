# =============================================================================
# rs30_interval_sandbox.R
# RS 30 Interval Adjustment Sandbox
# =============================================================================
#
# Purpose: Explore interval-based geomorphic adjustment metrics for Umatilla
#          River segment 30 using consecutive dated HMA states.
#
# Specifically:
#   1. Read the Umatilla River HMA and CMZ layers
#   2. Isolate CMZ segment 30 as a candidate exploratory reach
#   3. Intersect dated HMA polygons with RS 30 and identify the usable year
#      sequence for consecutive interval comparisons
#   4. Compute a first bundle of polygon-based interval metrics that can serve
#      as response-variable candidates in later flood-response modeling
#
# Inputs:
#   - data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb
#
# Outputs:
#   - In-memory sf objects and tibbles for interactive exploration:
#       * rs30_cmz
#       * rs30_hma
#       * rs30_hma_years
#       * rs30_interval_pairs
#       * rs30_interval_metrics
#       * rs30_interval_geometries
#       * rs30_interval_yearly_peaks
#       * rs30_interval_peak_summary
#       * rs30_interval_metrics_with_peaks
#
# Key decisions:
#   - Treat dated HMA polygons as year-stamped channel-state observations, then
#     compare consecutive states as intervals. This follows the interval-based
#     response framing developed in docs/interval_adjustment_modeling_notes.md:
#     forcing and response should live on the same interval.
#   - Use polygon-overlay metrics as the first response family because that is
#     the method most directly supported by the HMA data and is consistent with
#     Rapp & Abbe (2003), who prefer polygon analysis over transects when GIS
#     is available.
#   - Treat HMA Year as the same-labeled water year for first-pass hydrologic
#     alignment. Working assumption from project discussion: imagery dates are
#     assumed to fall in January-September unless exact photo dates are later
#     recovered. This is explicit and provisional, not hidden.
#   - Use Pendleton gage 14020850 as the first-pass forcing series for RS 30.
#     Early HMA intervals outside that gage's record are allowed to remain NA
#     rather than forcing a mixed-gage solution before the first plots.
#
# References:
#   - Rapp, C.F. and Abbe, T.B. (2003). A Framework for Delineating Channel
#     Migration Zones. WA Dept of Ecology Publication 03-06-027.
#   - docs/rapp_abbe_2003_codex_summary.md
#   - docs/interval_adjustment_modeling_notes.md
#   - docs/hma_interval_metrics_codex_brief.md
#
# Style: Exploratory script with explicit, reusable objects and recorded
# methodological assumptions so later reviewers do not need to infer intent.
# =============================================================================

library(sf)
library(dplyr)
library(tibble)
library(ggplot2)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  gdb_path = "data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb",
  hma_layer = "Umatilla_River_HMA",
  cmz_layer = "Umatilla_River_CMZ",
  target_segment = 30L,
  composite_note = "Merged 1952-2022 historical and 2024 active channel. Small gaps filled in.",
  peak_flows_csv = "data/peak_flows.csv",
  plot_gage_id = "14020850",
  plot_gage_label = "Pendleton"
)

# =============================================================================
# 1. REUSABLE HELPERS
# =============================================================================

# Read a single simple-features layer from the DOGAMI geodatabase.
# gdb_path/layer_name (character scalars) -> sf object.
# Keep all geodatabase I/O at the boundary so later helpers remain pure.
read_gdb_layer <- function(gdb_path, layer_name) {
  st_read(
    dsn = gdb_path,
    layer = layer_name,
    quiet = TRUE
  )
}

# Extract one CMZ segment polygon by its DOGAMI segment identifier.
# cmz (sf), target_segment (integer scalar) -> single-segment sf object.
# Preserve the original RIverSegment field name because it is the source identifier.
select_cmz_segment <- function(cmz, target_segment) {
  cmz %>%
    filter(RIverSegment == target_segment)
}

# Keep only dated HMA polygons that intersect the target segment.
# hma/candidate_segment (sf) -> sf object of dated HMA polygons clipped to the segment.
# Exclude the merged composite polygon because it is not a true time-step observation.
clip_dated_hma_to_segment <- function(hma, candidate_segment, composite_note) {
  hma %>%
    filter(!is.na(Year)) %>%
    filter(is.na(Note) | Note != composite_note) %>%
    st_intersection(candidate_segment) %>%
    mutate(
      clipped_area_ft2 = as.numeric(st_area(.))
    ) %>%
    filter(clipped_area_ft2 > 0)
}

# Summarize the available HMA years within the target segment.
# rs_hma (sf) -> tibble with one row per year and clipped polygon count/area.
# Keep area summaries so partial-coverage years are visible during interpretation.
summarize_segment_hma_years <- function(rs_hma) {
  rs_hma %>%
    st_drop_geometry() %>%
    group_by(Year) %>%
    summarise(
      n_clipped_polygons = n(),
      total_clipped_area_ft2 = sum(clipped_area_ft2),
      .groups = "drop"
    ) %>%
    arrange(Year)
}

# Build consecutive year pairs from the dated HMA sequence in the target segment.
# year_tbl (tibble with Year column) -> tibble with one row per HMA interval.
# Use the observed year sequence directly rather than imposing regular spacing because
# the image record is irregular by design; preserving that irregularity is part of
# the data-generating process rather than a nuisance to smooth away.
make_consecutive_intervals <- function(year_tbl) {
  years <- year_tbl$Year

  tibble(
    year_t1 = years[-length(years)],
    year_t2 = years[-1]
  ) %>%
    mutate(
      interval_years = year_t2 - year_t1
    )
}

# Union all clipped HMA geometry for one year within the target segment.
# rs_hma (sf), target_year (integer scalar) -> sfc geometry scalar.
# Union by year so interval comparisons are year-state comparisons rather than polygon-by-polygon comparisons.
make_year_geometry <- function(rs_hma, target_year) {
  rs_hma %>%
    filter(Year == target_year) %>%
    summarise() %>%
    st_geometry() %>%
    .[[1]]
}

# Compute first-pass interval metrics from two yearly geometries.
# geom_t1/geom_t2 (sfc geometry scalars), interval_years/segment_length_ft -> tibble with one row.
# Area-based change is treated as the primary response family because it is most directly supported by HMA.
compute_interval_metrics <- function(geom_t1, geom_t2, interval_years, segment_length_ft) {
  area_t1 <- as.numeric(st_area(geom_t1))
  area_t2 <- as.numeric(st_area(geom_t2))

  overlap_geom <- st_intersection(geom_t1, geom_t2)
  new_geom <- st_difference(geom_t2, geom_t1)
  abandoned_geom <- st_difference(geom_t1, geom_t2)
  symmetric_change_geom <- st_sym_difference(geom_t1, geom_t2)

  overlap_ft2 <- as.numeric(st_area(overlap_geom))
  new_area_ft2 <- as.numeric(st_area(new_geom))
  abandoned_area_ft2 <- as.numeric(st_area(abandoned_geom))
  symmetric_change_ft2 <- as.numeric(st_area(symmetric_change_geom))
  net_area_change_ft2 <- area_t2 - area_t1

  tibble(
    area_t1_ft2 = area_t1,
    area_t2_ft2 = area_t2,
    overlap_ft2 = overlap_ft2,
    new_area_ft2 = new_area_ft2,
    abandoned_area_ft2 = abandoned_area_ft2,
    symmetric_change_ft2 = symmetric_change_ft2,
    net_area_change_ft2 = net_area_change_ft2,
    new_area_ft2_per_year = new_area_ft2 / interval_years,
    abandoned_area_ft2_per_year = abandoned_area_ft2 / interval_years,
    symmetric_change_ft2_per_year = symmetric_change_ft2 / interval_years,
    net_area_change_ft2_per_year = net_area_change_ft2 / interval_years,
    symmetric_change_ft2_per_year_per_ft = symmetric_change_ft2 / interval_years / segment_length_ft
  )
}

# Build yearly geometries and interval metrics for a target segment.
# rs_hma/interval_tbl/segment_length_ft -> list(yearly_geometries, interval_metrics).
# Grain change: yearly_geometries stores one geometry per HMA year; interval_metrics
# stores one row per HMA interval. Keep both because exploratory map checks are part
# of the method-development loop and should not require recomputation.
build_interval_products <- function(rs_hma, interval_tbl, segment_length_ft) {
  yearly_geometries <- stats::setNames(
    lapply(
      unique(rs_hma$Year),
      function(target_year) make_year_geometry(rs_hma, target_year)
    ),
    unique(rs_hma$Year)
  )

  interval_metrics <- bind_rows(
    lapply(
      seq_len(nrow(interval_tbl)),
      function(i) {
        year_t1 <- interval_tbl$year_t1[[i]]
        year_t2 <- interval_tbl$year_t2[[i]]

        compute_interval_metrics(
          geom_t1 = yearly_geometries[[as.character(year_t1)]],
          geom_t2 = yearly_geometries[[as.character(year_t2)]],
          interval_years = interval_tbl$interval_years[[i]],
          segment_length_ft = segment_length_ft
        ) %>%
          mutate(
            year_t1 = year_t1,
            year_t2 = year_t2,
            interval_years = interval_tbl$interval_years[[i]]
          ) %>%
          select(year_t1, year_t2, interval_years, everything())
      }
    )
  )

  list(
    yearly_geometries = yearly_geometries,
    interval_metrics = interval_metrics
  )
}

# Read the exported annual-peak table from the hydrology acquisition pipeline.
# peak_flows_csv (character scalar path) -> tibble with one row per gage x water year annual peak.
# Keep hydrology file I/O at the boundary so interval-join helpers remain pure and reusable.
read_peak_flows_table <- function(peak_flows_csv) {
  readr::read_csv(
    peak_flows_csv,
    show_col_types = FALSE
  )
}

# Build yearly and interval peak-flow tables aligned to HMA intervals using water years.
# interval_tbl/peak_flows_tbl (tibbles), gage_id (character scalar) ->
#   list(yearly_peaks, interval_summary).
# Grain change:
#   - yearly_peaks: one row = one water year inside one HMA interval
#   - interval_summary: one row = one HMA interval
# Key decisions:
#   - Working assumption from project discussion: HMA Year is treated as the
#     same-labeled water year because imagery is assumed to fall in January-
#     September unless exact photo dates are available.
#   - For interval t1 -> t2, the forcing window is WY (t1 + 1) through WY t2.
#     The maximum annual peak in that window is treated as the first-pass flood
#     most likely to have done the geomorphic work reflected in the later HMA
#     polygon. This is a practical exploratory alignment rule, not a claim that
#     exact photo dates are known.
# References:
#   - docs/interval_adjustment_modeling_notes.md: forcing and response should be
#     aligned on the same interval.
#   - docs/hma_interval_metrics_codex_brief.md: start with interval maximum peak
#     flow as the primary x-axis and treat short intervals cautiously.
#   - Rapp & Abbe (2003): polygon-overlay interpretation and warning that short
#     intervals amplify noise.
build_interval_peak_tables <- function(interval_tbl, peak_flows_tbl, gage_id) {
  gage_peaks <- peak_flows_tbl %>%
    filter(gage_id == !!gage_id) %>%
    arrange(water_year, peak_date)

  yearly_peaks <- bind_rows(
    lapply(
      seq_len(nrow(interval_tbl)),
      function(i) {
        year_t1 <- interval_tbl$year_t1[[i]]
        year_t2 <- interval_tbl$year_t2[[i]]
        interval_years <- interval_tbl$interval_years[[i]]

        gage_peaks %>%
          filter(
            water_year > year_t1,
            water_year <= year_t2
          ) %>%
          mutate(
            year_t1 = year_t1,
            year_t2 = year_t2,
            interval_years = interval_years
          ) %>%
          select(year_t1, year_t2, interval_years, everything())
      }
    )
  )

  interval_summary <- yearly_peaks %>%
    group_by(year_t1, year_t2, interval_years) %>%
    summarise(
      n_water_years = n(),
      q_peak_max_cfs = max(peak_q_cfs, na.rm = TRUE),
      q_peak_max_date = peak_date[which.max(peak_q_cfs)],
      .groups = "drop"
    ) %>%
    arrange(year_t1, year_t2)

  list(
    yearly_peaks = yearly_peaks,
    interval_summary = interval_summary
  )
}

# Build a first-pass exploratory scatter plot for one RS 30 response metric.
# plot_tbl (one row per HMA interval), response_col/response_label (character scalars) -> ggplot object.
# Keep the plotting helper narrow: it assumes q_peak_max_cfs already exists and only handles the
# first exploratory panel design. Short intervals are flagged visually because Rapp & Abbe (2003)
# and later migration-measurement references caution that 1-2 year intervals may be noisy.
make_interval_peak_plot <- function(plot_tbl, response_col, response_label) {
  ggplot(
    plot_tbl,
    aes(
      x = q_peak_max_cfs,
      y = .data[[response_col]],
      label = interval_label,
      color = short_interval_flag
    )
  ) +
    geom_point(size = 2.8) +
    geom_text(
      nudge_y = 0.02 * max(plot_tbl[[response_col]], na.rm = TRUE),
      check_overlap = TRUE,
      show.legend = FALSE
    ) +
    scale_color_manual(
      values = c("interval >= 3 years" = "#2c7fb8", "interval < 3 years" = "#d95f0e")
    ) +
    labs(
      x = paste0(config$plot_gage_label, " interval maximum annual peak flow (cfs)"),
      y = response_label,
      color = NULL,
      title = paste0("RS 30: ", response_label, " vs interval peak flow"),
      subtitle = "Points labeled by HMA interval; short intervals flagged for caution"
    ) +
    theme_minimal(base_size = 11)
}

# Build one backward interval for a terminal HMA year using a target-lag rule.
# years/t2_index (sorted HMA years and terminal-year position), target_lag/min_lag (numeric scalars) ->
#   tibble with one row describing the selected interval.
# Key decisions:
#   - Prefer lags >= min_lag so 1-2 year intervals are avoided when possible.
#   - Among acceptable lags, choose the interval closest to target_lag.
#   - If two candidates are equally close, choose the shorter interval.
#   - If no candidate meets min_lag, fall back to the longest available backward interval.
select_backward_interval <- function(years, t2_index, target_lag = 5L, min_lag = 4L) {
  stopifnot(length(years) >= 2L)
  stopifnot(t2_index >= 2L, t2_index <= length(years))

  t2 <- years[[t2_index]]
  candidates <- tibble(
    t1_index = seq_len(t2_index - 1L),
    year_t1 = years[seq_len(t2_index - 1L)]
  ) %>%
    mutate(
      year_t2 = t2,
      interval_years = year_t2 - year_t1
    )

  preferred <- candidates %>%
    filter(interval_years >= min_lag)

  if (nrow(preferred) == 0L) {
    selected <- candidates %>%
      arrange(desc(interval_years)) %>%
      slice(1)
  } else {
    selected <- preferred %>%
      mutate(distance_to_target = abs(interval_years - target_lag)) %>%
      arrange(distance_to_target, interval_years) %>%
      slice(1) %>%
      select(-distance_to_target)
  }

  selected
}

# Build a non-overlapping greedy backward partition of the observed HMA years.
# years (sorted HMA years) -> tibble with one row per disjoint backward interval.
# Grain: one row = one disjoint retrospective HMA interval.
# This is the preferred alternate interval design because it reduces short-interval
# inflation without introducing overlap dependence among constructed windows.
build_backward_partition_disjoint <- function(years, target_lag = 5L, min_lag = 4L) {
  stopifnot(length(years) >= 2L)

  terminal_index <- length(years)
  intervals <- list()

  while (terminal_index >= 2L) {
    selected <- select_backward_interval(
      years = years,
      t2_index = terminal_index,
      target_lag = target_lag,
      min_lag = min_lag
    )

    intervals[[length(intervals) + 1L]] <- selected
    terminal_index <- selected$t1_index[[1]]
  }

  bind_rows(intervals) %>%
    select(year_t1, year_t2, interval_years) %>%
    arrange(year_t1, year_t2)
}

# Build a maximally greedy backward set of overlapping retrospective intervals.
# years (sorted HMA years) -> tibble with one row per terminal HMA year except the earliest.
# Grain: one row = one overlapping retrospective HMA interval.
# This is a sensitivity design only. Years can be reused across windows, so resulting
# intervals are serially dependent and should not be treated as independent evidence.
build_backward_partition_overlapping <- function(years, target_lag = 5L, min_lag = 4L) {
  stopifnot(length(years) >= 2L)

  bind_rows(
    lapply(
      2:length(years),
      function(t2_index) {
        select_backward_interval(
          years = years,
          t2_index = t2_index,
          target_lag = target_lag,
          min_lag = min_lag
        )
      }
    )
  ) %>%
    select(year_t1, year_t2, interval_years) %>%
    arrange(year_t1, year_t2)
}

# Build metrics, peak-flow joins, and a plotting table for one interval variant.
# rs_hma/interval_tbl/segment_length_ft/peak_flows_tbl/gage_id -> list(metrics, yearly_peaks, peak_summary, metrics_with_peaks, plot_data).
# Grain:
#   - metrics: one row = one HMA interval in the supplied interval table
#   - yearly_peaks: one row = one water year inside one supplied interval
#   - peak_summary and metrics_with_peaks: one row = one supplied interval
# This helper keeps the alternate partition variants comparable by running them through
# the same metric and hydrology-join machinery used for the original consecutive intervals.
build_interval_variant_outputs <- function(rs_hma, interval_tbl, segment_length_ft, peak_flows_tbl, gage_id) {
  interval_products <- build_interval_products(
    rs_hma = rs_hma,
    interval_tbl = interval_tbl,
    segment_length_ft = segment_length_ft
  )

  peak_tables <- build_interval_peak_tables(
    interval_tbl = interval_tbl,
    peak_flows_tbl = peak_flows_tbl,
    gage_id = gage_id
  )

  metrics_with_peaks <- interval_products$interval_metrics %>%
    left_join(
      peak_tables$interval_summary,
      by = c("year_t1", "year_t2", "interval_years")
    )

  plot_data <- metrics_with_peaks %>%
    filter(!is.na(q_peak_max_cfs)) %>%
    mutate(
      interval_label = paste0(year_t1, "-", year_t2),
      short_interval_flag = if_else(
        interval_years < 3,
        "interval < 3 years",
        "interval >= 3 years"
      )
    )

  list(
    metrics = interval_products$interval_metrics,
    yearly_peaks = peak_tables$yearly_peaks,
    peak_summary = peak_tables$interval_summary,
    metrics_with_peaks = metrics_with_peaks,
    plot_data = plot_data
  )
}

# =============================================================================
# 2. READ CORE LAYERS
# =============================================================================

hma <- read_gdb_layer(config$gdb_path, config$hma_layer)
cmz <- read_gdb_layer(config$gdb_path, config$cmz_layer)

# =============================================================================
# 3. ISOLATE RS 30
# =============================================================================

rs30_cmz <- select_cmz_segment(
  cmz = cmz,
  target_segment = config$target_segment
)

rs30_length_ft <- rs30_cmz %>%
  st_drop_geometry() %>%
  summarise(segment_length_ft = sum(Shape_Length)) %>%
  pull(segment_length_ft)

rs30_hma <- clip_dated_hma_to_segment(
  hma = hma,
  candidate_segment = rs30_cmz,
  composite_note = config$composite_note
)

rs30_hma_years <- summarize_segment_hma_years(rs30_hma)

# =============================================================================
# 4. BUILD CONSECUTIVE INTERVALS
# =============================================================================

rs30_interval_pairs <- make_consecutive_intervals(rs30_hma_years)

rs30_interval_products <- build_interval_products(
  rs_hma = rs30_hma,
  interval_tbl = rs30_interval_pairs,
  segment_length_ft = rs30_length_ft
)

rs30_interval_geometries <- rs30_interval_products$yearly_geometries
rs30_interval_metrics <- rs30_interval_products$interval_metrics

# =============================================================================
# 5. JOIN RS 30 INTERVALS TO PENDLETON ANNUAL PEAKS
# =============================================================================
#
# Grain summary after this section:
#   - rs30_interval_yearly_peaks: one row = one Pendleton annual peak inside one
#     RS 30 HMA interval
#   - rs30_interval_peak_summary: one row = one RS 30 HMA interval with the
#     interval maximum annual peak
#   - rs30_interval_metrics_with_peaks: one row = one RS 30 HMA interval with
#     geomorphic metrics and joined first-pass forcing metrics
#
# Decision note:
#   - We allow early intervals to remain NA where Pendleton does not provide
#     coverage. That keeps the first exploratory plots honest and avoids hiding
#     a mixed-gage assumption inside the join.

peak_flows_tbl <- read_peak_flows_table(config$peak_flows_csv)

rs30_peak_tables <- build_interval_peak_tables(
  interval_tbl = rs30_interval_pairs,
  peak_flows_tbl = peak_flows_tbl,
  gage_id = config$plot_gage_id
)

rs30_interval_yearly_peaks <- rs30_peak_tables$yearly_peaks
rs30_interval_peak_summary <- rs30_peak_tables$interval_summary

rs30_interval_metrics_with_peaks <- rs30_interval_metrics %>%
  left_join(
    rs30_interval_peak_summary,
    by = c("year_t1", "year_t2", "interval_years")
  )

# =============================================================================
# 6. FIRST-PASS RS 30 PLOTS
# =============================================================================
#
# Grain after filtering:
#   - rs30_plot_data: one row = one RS 30 HMA interval with available Pendleton
#     first-pass forcing data
#
# Decision note:
#   - First plots use only intervals with non-missing Pendleton peaks.
#   - Early RS 30 intervals remain excluded here rather than borrowing a second
#     gage or reconstructed series before we have seen the basic pattern.

rs30_plot_data <- rs30_interval_metrics_with_peaks %>%
  filter(!is.na(q_peak_max_cfs)) %>%
  mutate(
    interval_label = paste0(year_t1, "-", year_t2),
    short_interval_flag = if_else(
      interval_years < 3,
      "interval < 3 years",
      "interval >= 3 years"
    )
  )

rs30_plot_new_area <- make_interval_peak_plot(
  plot_tbl = rs30_plot_data,
  response_col = "new_area_ft2_per_year",
  response_label = "New area rate (ft^2/year)"
)

rs30_plot_symmetric_change <- make_interval_peak_plot(
  plot_tbl = rs30_plot_data,
  response_col = "symmetric_change_ft2_per_year",
  response_label = "Symmetric change rate (ft^2/year)"
)

rs30_plot_net_area_change <- make_interval_peak_plot(
  plot_tbl = rs30_plot_data,
  response_col = "net_area_change_ft2_per_year",
  response_label = "Net area change rate (ft^2/year)"
)

# =============================================================================
# 7. BACKWARD PARTITION VARIANTS
# =============================================================================
#
# Variant summary:
#   - rs30_intervals_backward_disjoint: non-overlapping retrospective intervals
#   - rs30_intervals_backward_overlapping: overlapping retrospective intervals
#
# Shared rule:
#   - target lag = 5 years
#   - minimum acceptable lag = 4 years
#   - tie-break = choose the shorter interval when two candidates are equally
#     close to the target lag

rs30_year_vector <- rs30_hma_years$Year

rs30_intervals_backward_disjoint <- build_backward_partition_disjoint(
  years = rs30_year_vector,
  target_lag = 5L,
  min_lag = 4L
)

rs30_intervals_backward_overlapping <- build_backward_partition_overlapping(
  years = rs30_year_vector,
  target_lag = 5L,
  min_lag = 4L
)

rs30_backward_disjoint_outputs <- build_interval_variant_outputs(
  rs_hma = rs30_hma,
  interval_tbl = rs30_intervals_backward_disjoint,
  segment_length_ft = rs30_length_ft,
  peak_flows_tbl = peak_flows_tbl,
  gage_id = config$plot_gage_id
)

rs30_backward_disjoint_plot_data <- rs30_backward_disjoint_outputs$plot_data

rs30_backward_disjoint_plot_new_area <- make_interval_peak_plot(
  plot_tbl = rs30_backward_disjoint_plot_data,
  response_col = "new_area_ft2_per_year",
  response_label = "New area rate (ft^2/year)"
)

rs30_backward_disjoint_plot_symmetric_change <- make_interval_peak_plot(
  plot_tbl = rs30_backward_disjoint_plot_data,
  response_col = "symmetric_change_ft2_per_year",
  response_label = "Symmetric change rate (ft^2/year)"
)

rs30_backward_disjoint_plot_net_area_change <- make_interval_peak_plot(
  plot_tbl = rs30_backward_disjoint_plot_data,
  response_col = "net_area_change_ft2_per_year",
  response_label = "Net area change rate (ft^2/year)"
)

rs30_backward_overlapping_outputs <- build_interval_variant_outputs(
  rs_hma = rs30_hma,
  interval_tbl = rs30_intervals_backward_overlapping,
  segment_length_ft = rs30_length_ft,
  peak_flows_tbl = peak_flows_tbl,
  gage_id = config$plot_gage_id
)

rs30_backward_overlapping_plot_data <- rs30_backward_overlapping_outputs$plot_data

rs30_backward_overlapping_plot_new_area <- make_interval_peak_plot(
  plot_tbl = rs30_backward_overlapping_plot_data,
  response_col = "new_area_ft2_per_year",
  response_label = "New area rate (ft^2/year)"
)

rs30_backward_overlapping_plot_symmetric_change <- make_interval_peak_plot(
  plot_tbl = rs30_backward_overlapping_plot_data,
  response_col = "symmetric_change_ft2_per_year",
  response_label = "Symmetric change rate (ft^2/year)"
)

rs30_backward_overlapping_plot_net_area_change <- make_interval_peak_plot(
  plot_tbl = rs30_backward_overlapping_plot_data,
  response_col = "net_area_change_ft2_per_year",
  response_label = "Net area change rate (ft^2/year)"
)

