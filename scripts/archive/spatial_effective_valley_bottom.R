# =============================================================================
# spatial_effective_valley_bottom.R
# Effective Valley Bottom (contemporary valley bottom, truncated by m/a/lv)
# =============================================================================
#
# Purpose: Truncate contemporary_valley_bottom_closed at the confining
#   features (m = roadbed/rail bed, a = artificial fill, lv = levees/levee
#   remnants) that can bound or redirect lateral migration (Byron,
#   2026-09-16/17). This is the "effective valley bottom" step deferred in
#   spatial_valley_bottom.R - input to the confinement-ratio work
#   (NOTE_confinement_ratio_exploration.md).
#
# Method (Byron, 2026-09-17): truncate-at-wall, not subtract-the-footprint.
#   Where a confining feature crosses the valley bottom, cut there and keep
#   only the channel-side piece. Implemented as: difference the confining-
#   feature dissolve out of contemporary_valley_bottom_closed (this both
#   removes the footprint AND, wherever a feature fully crosses the corridor,
#   splits it into separate polygon parts); keep only the part(s) touching
#   the active channel. Where more than one confining feature stands between
#   the channel and the valley wall, only the nearest one actually separates
#   the channel-side part from the rest, so it wins as "the wall" without
#   needing an explicit distance comparison.
#
# Inputs:
#   - scripts/spatial_valley_bottom.R (sourced; gives geology,
#     contemporary_valley_bottom, contemporary_valley_bottom_closed)
#   - data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb, layer
#     Umatilla_River_AC (active channel; first use of this gdb in the
#     spatial_valley_bottom* script family, so it's read directly here)
#
# Output:
#   - In-memory sf object for interactive exploration: effective_valley_bottom
#
# Confining units (Byron, 2026-09-16): m, a, lv. Byron's correction: these are
#   NOT negligible thin ribbons - m in particular is a substantial rail/road
#   bed with a real berm in many reaches, and lv/a play a similar role.
#
# Note on read_gdb_layer_linear(): duplicated from
#   06_multireach_interval_metrics.R rather than shared, matching the existing
#   pattern in this repo (see NOTE_shared_module_refactor.md - extracting
#   reused helpers into an R/ module is scoped but explicitly deferred).
#
# Style: Tidyverse & FP guidelines.
# =============================================================================

library(sf)
library(dplyr)

source("scripts/spatial_valley_bottom.R")

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config$confining_units          <- c("m", "a", "lv")
config$cmz_gdb_path              <- "data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb"
config$active_channel_layer      <- "Umatilla_River_AC"
config$effective_bridge_buffer_dist_ft <- config$bridge_buffer_dist_ft  # reuse; adjust if this step looks different

# =============================================================================
# 1. HELPERS
# =============================================================================

# Read a DOGAMI gdb layer with curves linearized. GEOS cannot process true
# curves (CurvePolygon/CompoundCurve); st_difference()/st_intersects() would
# throw "Curved geometry types are not supported" otherwise.
# gdb_path (character scalar), layer_name (character scalar) -> sf.
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

# Truncate a valley-bottom polygon at confining features: difference out the
# confining-feature footprint (which also splits the polygon wherever a
# feature fully crosses it), then keep only the resulting part(s) that touch
# the channel. See header note on why this makes the nearest feature "win"
# without an explicit distance comparison.
# valley_bottom (sf, POLYGON/MULTIPOLYGON), confining_features (sf),
#   channel (sf) -> sf, one row (channel-side parts unioned).
truncate_at_confining_features <- function(valley_bottom, confining_features, channel) {
  remainder <- valley_bottom %>%
    st_difference(st_union(confining_features)) %>%
    st_make_valid()

  parts <- remainder %>%
    st_geometry() %>%
    st_cast("POLYGON") %>%
    st_sf(geometry = .)

  touches_channel <- lengths(st_intersects(parts, channel)) > 0

  cat("\n=== truncate_at_confining_features ===\n")
  cat("n parts after differencing:", nrow(parts), "\n")
  cat("n parts kept (touch channel):", sum(touches_channel), "\n")

  parts[touches_channel, ] %>%
    st_union() %>%
    st_sf(geometry = .)
}

# =============================================================================
# 2. BUILD
# =============================================================================

confining_features <- geology$MapUnitPolys %>%
  dissolve_by_mapunit(config$confining_units)

active_channel <- read_gdb_layer_linear(config$cmz_gdb_path, config$active_channel_layer) %>%
  st_transform(config$target_crs)

effective_valley_bottom_raw <- contemporary_valley_bottom_closed %>%
  truncate_at_confining_features(confining_features, active_channel)

# Differencing/casting can leave the channel-side piece multipart or notched
# (e.g. where a confining feature partially crosses) - reuse the same
# bridge-closing step as contemporary_valley_bottom_closed.
effective_valley_bottom <- effective_valley_bottom_raw %>%
  close_valley_bottom_by_buffer(config$effective_bridge_buffer_dist_ft, config$bridge_buffer_nQuadSegs)

# ---- Verify --------------------------------------------------------------
summarize_valley_bottom_geometry(confining_features, "confining_features (m, a, lv - raw dissolve)")
summarize_valley_bottom_geometry(effective_valley_bottom_raw, "effective_valley_bottom_raw (truncated, before re-close)")
summarize_valley_bottom_geometry(effective_valley_bottom, "effective_valley_bottom")
