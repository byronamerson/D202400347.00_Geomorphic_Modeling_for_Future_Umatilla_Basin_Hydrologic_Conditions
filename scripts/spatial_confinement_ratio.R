# =============================================================================
# spatial_confinement_ratio.R
# Confinement Ratio (valley bottom width / channel width), RS 28-37
# =============================================================================
#
# Purpose: Compute two confinement-ratio variants per reach - the covariate
#   candidate for the unexplained ~6x reach-sensitivity spread in the m_B2
#   multi-reach migration-forcing model (NOTE_confinement_ratio_exploration.md,
#   NOTE_gradient_interaction_null_result.md). This script only builds the
#   input widths and the ratio itself as a CSV; testing it against m_B2's
#   per-reach BLUP slopes is deferred to a later session.
#
# Inputs:
#   - scripts/spatial_effective_valley_bottom.R (sourced; gives
#     contemporary_valley_bottom_closed, effective_valley_bottom, both already
#     reprojected to EPSG:6557)
#   - scripts/rs30_interval_sandbox.R (sourced; gives select_cmz_segment(),
#     clip_dated_hma_to_segment(), summarize_segment_hma_years(), and the
#     gdb/layer config - reused as written per NOTE_shared_module_refactor.md,
#     same pattern as 06_multireach_interval_metrics.R). hma/cmz are re-read
#     with curves linearized immediately after, for the same reason 06 does -
#     GEOS can't intersect curved geometry, and RS 30 (the sandbox's own
#     target) happens to be curve-free, which is why the sandbox works
#     unmodified but other reaches need the linearized read.
#   - data/reach_attributes.csv (length_ft per RS, from script 02) - the single
#     length denominator for every width in this script.
#
# Output:
#   - data/confinement_ratio.csv - one row per RS 28-37: raw areas, all three
#     widths, and both ratio variants.
#   - data/channel_area_by_rs_year.csv - one row per RS x dated HMA year: the
#     full per-year clipped active-channel area/width distribution behind the
#     median in confinement_ratio.csv. Added 2026-09-17 (continued) because
#     the median alone hid the answer to a direct question (RS 29's
#     unexpectedly narrow channel width, high ratio vs. RS 30) - keep the
#     distribution around instead of discarding it inside a helper.
#
# Reach scope: RS 28-37, the m_B2 modeled population (RS 25-27 excluded on
#   levee/mechanical-preclusion grounds - NOTE_confined_reach_exclusion.md).
#
# Key decisions (Byron, 2026-09-17 discussion):
#   - One length denominator for every width: reach_attr$length_ft, the same
#     column already used for new_area_per_ft elsewhere in this pipeline. No
#     transect-based width for either the valley-bottom or channel side -
#     area / length throughout, kept deliberately simple and trackable.
#   - Channel width denominator is NOT DOGAMI's avg_width_ft (single,
#     vintage-unstated) and NOT a new active-channel layer - it's the MEDIAN
#     clipped area, across all dated (non-composite) HMA years in that RS,
#     using the exact clip_dated_hma_to_segment()/summarize_segment_hma_years()
#     machinery already built for the interval-metrics pipeline. Median, not
#     mean, so one anomalous year (e.g. RS 30's flagged 2012 HMA question)
#     doesn't dominate a single reach's channel-width estimate.
#   - Two valley-bottom variants share the same per-RS boundary
#     (select_cmz_segment()) and the same length denominator - only the
#     valley-bottom polygon itself differs between them. Whether the DOGAMI
#     CMZ polygon's lateral extent could cap the "contemporary" (unconstrained)
#     variant's width was raised and explicitly set aside (Byron, 2026-09-17):
#     the valley-bottom geometry is USGS-mapped, independent of DOGAMI's
#     CMZ/EHA products entirely, so this is not the EHA-circularity concern
#     already put to bed in NOTE_confinement_ratio_exploration.md.
#   - confinement_ratio = valley_bottom_width / channel_width (Alber & Piegay
#     2011 convention - higher = less confined), matching the exploration
#     note. "confinement_ratio_constrained" is Byron's term for the effective
#     (m/a/lv-truncated) variant; the underlying geometry object keeps its
#     established name (effective_valley_bottom).
#
# Style: Tidyverse & FP guidelines.
# =============================================================================

library(sf)
library(dplyr)
library(purrr)
library(readr)
library(tibble)

source("scripts/spatial_effective_valley_bottom.R")
source("scripts/rs30_interval_sandbox.R")

# rs30_interval_sandbox.R reassigns `config` from scratch (its own gdb/layer
# config, not appended to the valley-bottom config built above) and reads
# hma/cmz with curves intact. Re-read both linearized, exactly as
# 06_multireach_interval_metrics.R already does, so st_intersection() below
# doesn't hit "Curved geometry types are not supported".
hma <- read_gdb_layer_linear(config$gdb_path, config$hma_layer)
cmz <- read_gdb_layer_linear(config$gdb_path, config$cmz_layer)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

modeled_reaches <- 28:37   # m_B2 population; see NOTE_confined_reach_exclusion.md

# =============================================================================
# 1. HELPERS
# =============================================================================

# Clip a valley-bottom polygon to one RS using the DOGAMI CMZ segment boundary
# as the per-reach cookie-cutter (the same boundary already used to bound HMA
# polygons per RS elsewhere in this pipeline).
# valley_bottom (sf, one row POLYGON/MULTIPOLYGON), cmz (sf, DOGAMI CMZ layer),
#   target_segment (integer RS number) -> numeric scalar, clipped area (ft2).
# Returns 0 if the reach has no overlap (should not happen for RS 28-37, but
# keeps the caller from erroring on an empty intersection).
compute_valley_bottom_area_by_rs <- function(valley_bottom, cmz, target_segment) {
  seg_cmz <- select_cmz_segment(cmz, target_segment)

  clipped <- valley_bottom %>%
    st_make_valid() %>%
    st_intersection(seg_cmz) %>%
    st_make_valid()

  if (nrow(clipped) == 0L) return(0)
  sum(as.numeric(st_area(clipped)))
}

# Per-RS, per-year clipped active-channel area - the full distribution behind
# the median channel-width denominator, for every modeled reach at once.
# Reuses the interval-metrics clipping helpers as written. Kept as its own,
# saved output (not just consumed and discarded inside a median helper) so a
# surprising ratio for one reach can be checked against its actual year-by-
# year spread rather than a single summary number.
# hma (sf, dated + composite polygons), cmz (sf), reaches (integer vector of
#   RS numbers), composite_note (character scalar identifying the
#   merged/composite polygon to exclude) -> tibble, one row per RS x HMA year
#   (river_segment, Year, n_clipped_polygons, total_clipped_area_ft2).
build_channel_area_by_year_table <- function(hma, cmz, reaches, composite_note) {
  map_dfr(reaches, function(seg) {
    seg_cmz <- select_cmz_segment(cmz, seg)
    seg_hma <- clip_dated_hma_to_segment(hma, seg_cmz, composite_note)

    summarize_segment_hma_years(seg_hma) %>%
      mutate(river_segment = seg) %>%
      select(river_segment, everything())
  })
}

# Build the confinement-ratio table for a set of reaches: three areas -> three
# widths (all divided by the same reach_attr$length_ft) -> two ratio variants.
# reaches (integer vector of RS numbers), contemporary_vb/effective_vb (sf,
#   one row each), cmz (sf), reach_attr (tibble with rs_num/length_ft),
#   channel_area_median (tibble with river_segment/channel_area_median_ft2,
#   from build_channel_area_by_year_table() + a median-by-reach summary) ->
#   tibble, one row per reach.
build_confinement_ratio_table <- function(reaches, contemporary_vb, effective_vb,
                                          cmz, reach_attr, channel_area_median) {
  map_dfr(reaches, function(seg) {
    seg_length_ft <- reach_attr$length_ft[reach_attr$rs_num == seg]
    stopifnot(length(seg_length_ft) == 1L)

    tibble(
      river_segment                       = seg,
      length_ft                           = seg_length_ft,
      contemporary_valley_bottom_area_ft2 = compute_valley_bottom_area_by_rs(contemporary_vb, cmz, seg),
      effective_valley_bottom_area_ft2    = compute_valley_bottom_area_by_rs(effective_vb, cmz, seg)
    )
  }) %>%
    left_join(channel_area_median, by = "river_segment") %>%
    mutate(
      contemporary_valley_bottom_width_ft = contemporary_valley_bottom_area_ft2 / length_ft,
      effective_valley_bottom_width_ft    = effective_valley_bottom_area_ft2 / length_ft,
      channel_width_ft                    = channel_area_median_ft2 / length_ft,
      confinement_ratio_contemporary      = contemporary_valley_bottom_width_ft / channel_width_ft,
      confinement_ratio_constrained       = effective_valley_bottom_width_ft / channel_width_ft
    )
}

# =============================================================================
# 2. BUILD
# =============================================================================

reach_attr <- read_csv("data/reach_attributes.csv", show_col_types = FALSE)

# Full per-RS, per-year channel-area distribution, saved on its own so the
# spread behind the median is always inspectable later, not just the median.
channel_area_by_year <- build_channel_area_by_year_table(
  hma            = hma,
  cmz            = cmz,
  reaches        = modeled_reaches,
  composite_note = config$composite_note
) %>%
  left_join(reach_attr %>% select(rs_num, length_ft), by = c("river_segment" = "rs_num")) %>%
  mutate(channel_width_ft = total_clipped_area_ft2 / length_ft)

write_csv(channel_area_by_year, "data/channel_area_by_rs_year.csv")

channel_area_median <- channel_area_by_year %>%
  group_by(river_segment) %>%
  summarise(channel_area_median_ft2 = median(total_clipped_area_ft2), .groups = "drop")

confinement_ratio <- build_confinement_ratio_table(
  reaches             = modeled_reaches,
  contemporary_vb     = contemporary_valley_bottom_closed,
  effective_vb        = effective_valley_bottom,
  cmz                 = cmz,
  reach_attr          = reach_attr,
  channel_area_median = channel_area_median
)

write_csv(confinement_ratio, "data/confinement_ratio.csv")

# ---- Verify --------------------------------------------------------------
cat("\n=== channel width range by RS (ft) - min / median / max across HMA years ===\n")
channel_area_by_year %>%
  group_by(river_segment) %>%
  summarise(
    n_years = n(),
    min_width_ft    = round(min(channel_width_ft), 1),
    median_width_ft = round(median(channel_width_ft), 1),
    max_width_ft    = round(max(channel_width_ft), 1),
    .groups = "drop"
  ) %>%
  as.data.frame() %>%
  print()

cat("\n=== confinement_ratio (RS 28-37) ===\n")
confinement_ratio %>%
  select(river_segment, length_ft, channel_width_ft,
         contemporary_valley_bottom_width_ft, confinement_ratio_contemporary,
         effective_valley_bottom_width_ft, confinement_ratio_constrained) %>%
  as.data.frame() %>%
  print()

cat("\nWrote data/confinement_ratio.csv\n")
cat("Wrote data/channel_area_by_rs_year.csv\n")
