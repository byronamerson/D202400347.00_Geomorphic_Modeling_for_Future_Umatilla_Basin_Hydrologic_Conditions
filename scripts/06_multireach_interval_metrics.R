# =============================================================================
# 06_multireach_interval_metrics.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 6: Multi-reach interval response metrics (RS 25-37) for the mixed model
# =============================================================================
#
# Purpose: Generate the per-reach response table for the RS 25-37 linear mixed
#   model. Reuses the RS-generic interval helpers from rs30_interval_sandbox.R
#   as written; the only new code is (a) a curve-linearizing reader and (b) a
#   wrapper that composes the helpers for an arbitrary segment, then a loop
#   over RS 25-37.
#
# Inputs:
#   - scripts/rs30_interval_sandbox.R   (helpers + config; also reads hma, cmz)
#   - data/reach_attributes.csv         (length_ft per reach, from script 02)
#
# Output:
#   - data/multireach_interval_metrics.csv  (one row per reach x interval)
#
# Reaches: RS 25-37 — all downstream of the Meacham Creek confluence (RS 37/38
#   boundary), so all share the extended Pendleton forcing (see
#   NOTE_gage_reach_forcing_mapping.md).
#
# Response: new_area_per_ft = new_area_ft2 / stationing length. Length-normalized
#   so a shared slope is comparable across reaches of different length; totals
#   (not annualized) per the Phase-5 forcing model. See NOTE_simple_forcing_model.md.
#
# Style: Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(readr)
library(purrr)
library(sf)

# Helpers + config (target_segment = 30, ignored here — the wrapper takes the
# segment as an argument). Sourcing also reads hma/cmz and builds the RS 30
# products; we re-read the layers linearized below for the multi-reach loop.
source("scripts/rs30_interval_sandbox.R")

reach_attr <- read_csv("data/reach_attributes.csv", show_col_types = FALSE)


# ---- New helper: read a gdb layer with curves linearized --------------------
# The DOGAMI gdb stores some segments as true curves (CurvePolygon /
# CompoundCurve). GEOS cannot process curves — st_intersection() / st_area()
# throw "Curved geometry types are not supported" (RS 30 is curve-free, which is
# why the RS 30 pipeline works, but other reaches are not). GDAL's
# CONVERT_TO_LINEAR densifies curves to plain (multi)polygons on read. This is a
# read-boundary fix; the sandbox's read_gdb_layer() is unchanged.
read_gdb_layer_linear <- function(gdb_path, layer_name) {
  tmp <- tempfile(fileext = ".gpkg")
  gdal_utils(
    util        = "vectortranslate",
    source      = gdb_path,
    destination = tmp,
    options     = c("-f", "GPKG", "-nlt", "CONVERT_TO_LINEAR", layer_name)
  )
  st_read(tmp, quiet = TRUE)
}

# Overwrite the sandbox's curved hma/cmz with linearized versions for the loop.
hma <- read_gdb_layer_linear(config$gdb_path, config$hma_layer)
cmz <- read_gdb_layer_linear(config$gdb_path, config$cmz_layer)


# ---- New helper: interval metrics for an arbitrary segment -------------------
# Composes the sandbox helpers (used as written) for one RS. Returns one row per
# HMA interval tagged with river_segment.
build_reach_interval_metrics <- function(hma, cmz, target_segment,
                                         segment_length_ft, composite_note) {
  seg_cmz       <- select_cmz_segment(cmz, target_segment)
  seg_hma       <- clip_dated_hma_to_segment(hma, seg_cmz, composite_note)
  seg_years     <- summarize_segment_hma_years(seg_hma)
  seg_intervals <- make_consecutive_intervals(seg_years)

  products <- build_interval_products(seg_hma, seg_intervals, segment_length_ft)

  products$interval_metrics %>%
    mutate(river_segment = target_segment) %>%
    select(river_segment, everything())
}


# ---- Loop RS 25-37 and assemble the response table --------------------------
# Length-normalize new area by stationing length. One row per reach x interval.
reaches <- 25:37

multireach_metrics <- map_dfr(reaches, function(seg) {
  seg_len <- reach_attr$length_ft[reach_attr$rs_num == seg]
  build_reach_interval_metrics(hma, cmz, seg, seg_len, config$composite_note) %>%
    mutate(
      length_ft       = seg_len,
      new_area_per_ft = new_area_ft2 / seg_len
    )
})

multireach_out <- multireach_metrics %>%
  transmute(
    river_segment, year_t1, year_t2, interval_years, length_ft,
    new_area_ft2, new_area_per_ft,
    net_area_change_ft2, abandoned_area_ft2, symmetric_change_ft2, jaccard_change
  )

write_csv(multireach_out, "data/multireach_interval_metrics.csv")


# ---- Verify --------------------------------------------------------------
cat("\n=== multireach_interval_metrics ===\n")
cat("reaches:", n_distinct(multireach_out$river_segment),
    "| rows:", nrow(multireach_out), "\n\n")

cat("--- intervals per reach ---\n")
multireach_out %>% count(river_segment, name = "n_intervals") %>%
  as.data.frame() %>% print()

cat("\n--- new_area_per_ft (ft) range by reach ---\n")
multireach_out %>%
  group_by(river_segment) %>%
  summarise(
    min  = round(min(new_area_per_ft), 2),
    med  = round(median(new_area_per_ft), 2),
    max  = round(max(new_area_per_ft), 2),
    .groups = "drop"
  ) %>%
  as.data.frame() %>% print()

cat("\nWrote data/multireach_interval_metrics.csv\n")
