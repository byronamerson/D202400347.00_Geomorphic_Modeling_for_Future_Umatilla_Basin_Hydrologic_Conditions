# =============================================================================
# 09c_forcing_validation.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 9c: End-to-end validation -- do the bias-corrected Livneh flows, pushed
#           through the SAME forcing pipeline, reproduce the migration<->forcing
#           relationship the observed record established?
# =============================================================================
#
# Why this is the real test. The 09b marginal tables (corrected flow vs obs
# distribution) match largely BY CONSTRUCTION -- quantile mapping forces each
# member's marginal onto the reference. That confirms the machinery, not the
# predictive value. Here we test the thing QM does NOT force: whether the
# corrected flows put the right flood forcing in the right DOGAMI intervals, so
# that the fitted migration model comes out the same as the model of record.
#
# Design (isolates flow source):
#   - Hold the interval set fixed to what the Livneh hindcast covers -- water
#     years ending <= 2011 (Livneh ends 2011-12-31). That drops the 2011-2022
#     intervals incl. the 2017-2020 record flood. Refit BOTH the extended
#     reference and every member on THIS common set, so the only thing that
#     varies between fits is the flow the forcing was computed from.
#   - Same forcing pipeline for all sources: 04c compute_all_interval_forcing()
#     at Q2 = 5,542, identical span logic. Same response, same model structure
#     (08 fit_forcing_model). Only the daily flow differs.
#   - Reference for the correction: NATIVE gauge, full-CDF (fit_floor = 0) --
#     the config settled in 09b. Switchable.
#
# Member-agnostic on purpose: all four Livneh members are carried, not one, so
# the spread across them IS the response range for the future-flow analysis
# (per Byron -- the corrections are good in general and several members give a
# defensible envelope, not a single point estimate).
#
# Read the result as: does each member's pop_slope + baseline + per-reach slopes
# land near the extended reference (refit on the same intervals)? Close => the
# corrected flows carry the migration signal end to end. The event *timing*
# these depend on is Livneh's own weather-driven sequence (incl. the 1964 storm)
# -- not imposed by QM -- so this comparison is genuinely independent.
#
# Inputs : scripts/09_bias_correction.R (correct_livneh + engine)
#          scripts/08_forcing_model.R   (sources 04c; forcing pipeline + model
#                                         of record; runs on source())
# Outputs: returns fitted models + comparison tibbles for inspection.
# Style  : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(readr)

# --- session guard -----------------------------------------------------------
# qmap (loaded in this session for 09b) attaches MASS, whose select() masks
# dplyr::select(). The downstream 04c/08 pipelines use bare select() (e.g.
# flood_spans, predict_migration), so shadow it in the global environment before
# sourcing them. Harmless when MASS is not loaded (assigns dplyr::select to
# itself). This is a session-contamination workaround, not a change to 04c/08.
select <- dplyr::select

source("scripts/09_bias_correction.R")   # correct_livneh + QM engine (no qmap pkg needed)
source("scripts/08_forcing_model.R")     # sources 04c; exposes response, intervals, config,
                                         # assemble_panel, fit_forcing_model, reach_effects, etc.


# =============================================================================
# 1. COMMON INTERVAL SET  (what the Livneh hindcast covers)
# =============================================================================

LIVNEH_END_WY    <- 2011                                   # Livneh ends 2011-12-31
common_intervals <- filter(intervals, year_t2 <= LIVNEH_END_WY)
response_common  <- semi_join(response, common_intervals, by = c("year_t1", "year_t2"))
metric_threshold <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")   # Q2 = 5,542


# =============================================================================
# 2. FORCING FROM A FLOW SOURCE  (same 04c pipeline for all)
# =============================================================================

livneh_forcing <- function(member, reference = "native", fit_floor = 0) {
  #' Correct one member (full-CDF vs the chosen reference), then run the SAME
  #' 04c forcing pipeline over the common intervals. Corrected Livneh is real
  #' data, not reconstruction, so is_estimated = FALSE.
  correct_livneh(member, reference = reference, fit_floor = fit_floor) %>%
    transmute(date, daily_q_cfs = q_corrected, is_estimated = FALSE) %>%
    compute_all_interval_forcing(common_intervals, metric_threshold)
}

extended_forcing_common <- function() {
  #' Forcing from the extended record over the SAME common intervals -- the
  #' model-of-record flow source, restricted so the comparison isolates flow.
  readRDS(cfg("extended_record_rds")) %>%
    compute_all_interval_forcing(common_intervals, metric_threshold)
}


# =============================================================================
# 3. FIT THE FORCING MODEL FOR ONE FLOW SOURCE
# =============================================================================

fit_source <- function(forcing_tbl, forcing_var = "cum_excess_k") {
  #' Assemble the panel (same response, same reaches, same structure) and fit the
  #' model of record for one forcing table.
  panel <- assemble_panel(response_common, forcing_tbl, CONFINED_REACHES)
  fit_forcing_model(panel, forcing_var)
}


# =============================================================================
# 4. BUILD ALL FITS  (extended reference + every member = the response range)
# =============================================================================

build_validation_fits <- function(members = LIVNEH_MEMBERS,
                                   reference = "native",
                                   forcing_var = "cum_excess_k") {
  #' One fit per flow source on the common intervals: the extended reference plus
  #' each corrected Livneh member. Returns a named list of lmerMods.
  ext <- list(extended = fit_source(extended_forcing_common(), forcing_var))
  mem <- set_names(members) %>%
    map(~ fit_source(livneh_forcing(.x, reference = reference), forcing_var))
  c(ext, mem)
}


# =============================================================================
# 5. COMPARISON REPORTERS
# =============================================================================

compare_population <- function(fits, forcing_var = "cum_excess_k") {
  #' Population forcing slope (+SE, t), baseline reworking, intercept, in-sample
  #' fit, and n -- one row per flow source. The extended row is the yardstick; a
  #' corrected member that reproduces its slope + baseline is validated end to end.
  imap_dfr(fits, function(m, k) {
    co <- summary(m)$coefficients
    tibble(
      source        = k,
      n             = nobs(m),
      pop_slope     = round(co[forcing_var, "Estimate"], 3),
      slope_se      = round(co[forcing_var, "Std. Error"], 3),
      slope_t       = round(co[forcing_var, "t value"], 2),
      baseline_yr   = round(lme4::fixef(m)[["interval_years"]], 3),
      pop_intercept = round(lme4::fixef(m)[["(Intercept)"]], 2),
      cor_fit_obs   = round(cor(fitted(m), fitted(m) + resid(m)), 3)
    )
  })
}

compare_reach_slopes <- function(fits, forcing_var = "cum_excess_k") {
  #' Per-reach forcing slope for each flow source, side by side -- tests whether
  #' the spatial pattern of sensitivity (the reach-level risk map) is reproduced.
  imap_dfr(fits, ~ reach_effects(.x, forcing_var) %>%
             transmute(river_segment,
                       reach_slope = round(reach_slope, 3),
                       source = .y)) %>%
    pivot_wider(names_from = source, values_from = reach_slope)
}


# =============================================================================
# 6. USAGE  (run interactively; sourcing runs 08's model of record once)
# =============================================================================
# fits <- build_validation_fits()     # extended + 4 members, native ref, cum_excess
# compare_population(fits)            # the headline: slopes vs the extended yardstick
# compare_reach_slopes(fits)         # the spatial risk pattern, member by member
#
# # variants:
# build_validation_fits(reference = "extended")     # correct to extended instead
# build_validation_fits(forcing_var = "sum_peak_k") # the crest-driven metric
# =============================================================================
