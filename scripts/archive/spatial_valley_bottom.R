# =============================================================================
# spatial_valley_bottom.R
# Contemporary Valley Bottom (dissolve of USGS surficial geology units)
# =============================================================================
#
# Purpose: Build a single, hole-free "contemporary valley bottom" polygon from
#   the USGS surficial geology map (SIM 3527), as input to the confinement-
#   ratio work (NOTE_confinement_ratio_exploration.md). This is the "natural"
#   footprint only - it does not yet account for m/a/lv (rail bed, artificial
#   fill, levees) as potential bounding/truncating features. That "effective
#   valley bottom" step is deferred (undecided how m/a/lv should be applied).
#
# Inputs:
#   - scripts/spatial_geology_import.R (sourced; defines read_gems_shapefiles()
#     and produces `geology`, re-read from disk each time this is sourced -
#     not dependent on anything already in memory)
#
# Output:
#   - In-memory sf objects for interactive exploration:
#       contemporary_valley_bottom         - raw dissolve, holes closed, but
#                                             still multipart wherever a
#                                             linear feature (m/a/lv/etc.)
#                                             fully splits the corridor.
#                                             Kept as-is (not overwritten) -
#                                             useful on its own for seeing how
#                                             those features break up the
#                                             floodplain.
#       contemporary_valley_bottom_closed  - the above, morphologically
#                                             closed (bridged) into one
#                                             contiguous polygon. See "Bridge
#                                             handling" below.
#
# Unit selection (Byron, 2026-09-17): w, ch, vb0, vb1, vb2, vb3, pc.
#   vb4 excluded (too high in elevation; not expected in RS 28-39). Terraces
#   (tr) excluded - contemporary valley bottom only, not the Pleistocene-
#   Holocene former valley floor.
#
# Hole handling: dissolving only the units above leaves gaps wherever the
#   geologist coded a strip of ground within the valley bottom as a different
#   unit (m, a, lv, or anything else) rather than one of the units above -
#   e.g. a rail bed or levee running through the corridor becomes a hole in
#   the unioned polygon. Byron wants a complete polygon, not one full of
#   holes, so all holes are closed here (nngeo::st_remove_holes(), the same
#   package already used elsewhere in this project). This is a blunt
#   instrument - it can't tell "a road crosses the valley bottom" apart from
#   "there's a real non-valley inclusion in the middle of it" - flag if that
#   distinction turns out to matter; max_area lets us only close small ones.
#
# Bridge handling (2026-09-17): st_remove_holes() only closes fully interior
#   rings - it doesn't reconnect the corridor where a linear feature runs
#   all the way across it, splitting contemporary_valley_bottom into separate
#   MULTIPOLYGON parts. contemporary_valley_bottom_closed fixes that with a
#   morphological "close": buffer outward by bridge_buffer_dist_ft, then back
#   inward by the same distance. The outward pass bridges any gap narrower
#   than 2x that distance (swallowing the linear feature) and fills interior
#   holes up to the same width; the inward pass brings the boundary back
#   close to its original position. This never touches m/a/lv data - that
#   dissolve stays available separately for later in the analysis.
#
# Style: Tidyverse & FP guidelines.
# =============================================================================

library(sf)
library(dplyr)
library(nngeo)

source("scripts/spatial_geology_import.R")

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config$valley_bottom_units   <- c("w", "ch", "vb0", "vb1", "vb2", "vb3", "pc")
config$hole_fill_max_area_ft2 <- 0   # 0 = close every hole (nngeo default)

config$bridge_buffer_dist_ft   <- 100 # bridges gaps/holes narrower than 2x this
config$bridge_buffer_nQuadSegs <- 8   # low vertex density - this is a bridging
                                       # tool, not a precision buffer

# =============================================================================
# 1. HELPERS
# =============================================================================

# Filter a map-unit polygon layer to a set of unit codes and union them into
# a single (multi)polygon. Drops attributes - the result is a footprint, not
# a feature table.
# map_unit_polys (sf), units (character vector of MapUnit codes) -> sf with
#   one row (POLYGON/MULTIPOLYGON geometry only).
dissolve_by_mapunit <- function(map_unit_polys, units) {
  map_unit_polys %>%
    filter(MapUnit %in% units) %>%
    st_union() %>%
    st_sf(geometry = .)
}

# Close interior holes in a dissolved polygon up to max_area (0 = all holes).
# See header note: this is what turns the raw dissolve (full of gaps where
# m/a/lv/etc. cut through the valley bottom) into one complete polygon.
# dissolved (sf, POLYGON/MULTIPOLYGON), max_area (numeric) -> sf, holes closed.
close_valley_bottom_gaps <- function(dissolved, max_area) {
  st_remove_holes(dissolved, max_area = max_area)
}

# Morphological "close": buffer out then back in by the same distance. Bridges
# gaps/slivers narrower than 2x dist (e.g. a linear feature splitting the
# corridor into separate MULTIPOLYGON parts) and fills holes up to that width,
# without reference to m/a/lv or any other layer. See "Bridge handling" above.
# x (sf, POLYGON/MULTIPOLYGON), dist (numeric, ft), nQuadSegs (integer)
#   -> sf, bridged/closed.
close_valley_bottom_by_buffer <- function(x, dist, nQuadSegs) {
  x %>%
    st_buffer(dist, nQuadSegs = nQuadSegs) %>%
    st_buffer(-dist, nQuadSegs = nQuadSegs)
}

# Print part/hole/area diagnostics for a valley-bottom polygon. Shared by
# contemporary_valley_bottom and contemporary_valley_bottom_closed so both get
# the same checks.
# x (sf, POLYGON/MULTIPOLYGON), label (character scalar) -> x, invisibly.
summarize_valley_bottom_geometry <- function(x, label) {
  parts <- x %>% st_geometry() %>% st_cast("POLYGON")

  n_parts <- length(parts)
  n_holes <- sum(lengths(parts) - 1L)   # each POLYGON sfg = 1 exterior ring + holes

  cat("\n===", label, "===\n")
  cat("geometry type:", st_geometry_type(x, by_geometry = FALSE), "\n")
  cat("n polygon parts:", n_parts, "\n")
  cat("n interior holes remaining:", n_holes, "\n")
  cat("total area (ft2):", format(sum(st_area(x)), big.mark = ","), "\n")
  cat("CRS:", st_crs(x)$input, "\n")

  invisible(x)
}

# =============================================================================
# 2. BUILD
# =============================================================================

contemporary_valley_bottom <- geology$MapUnitPolys %>%
  dissolve_by_mapunit(config$valley_bottom_units) %>%
  close_valley_bottom_gaps(config$hole_fill_max_area_ft2)

# Separate object - contemporary_valley_bottom is left as-is (see header note).
contemporary_valley_bottom_closed <- contemporary_valley_bottom %>%
  close_valley_bottom_by_buffer(config$bridge_buffer_dist_ft, config$bridge_buffer_nQuadSegs)

# ---- Verify --------------------------------------------------------------
summarize_valley_bottom_geometry(contemporary_valley_bottom, "contemporary_valley_bottom")
summarize_valley_bottom_geometry(contemporary_valley_bottom_closed, "contemporary_valley_bottom_closed")
