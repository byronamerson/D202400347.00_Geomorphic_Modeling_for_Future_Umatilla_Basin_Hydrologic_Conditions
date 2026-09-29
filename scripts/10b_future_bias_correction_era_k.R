# =============================================================================
# 10b_future_bias_correction_era_k.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 10b: Re-correct the STATISTICAL future members (BCSD + MACA) with the
#            PresRat K-factor computed per era rather than once for 2006-2099.
# =============================================================================
#
# Purpose: produce a second, parallel set of bias-corrected future flows that
#   differs from the current set in exactly one respect -- the granularity of
#   the K-factor -- so the two can be compared without re-running either.
#
#   The open question this serves (PICKUP_2026-09-28 s.2, "still open"): one
#   window gives one K per member spanning 94 years, where Pierce et al. (2015)
#   computes K per month AND per 30-year future period. Whether one K across a
#   warming century is adequate is untested. This script builds the material to
#   test it.
#
# What is NOT changed here. The QDM correction itself is untouched: same engine
#   (MBC::QDM, ratio = TRUE), same o.c, same 2005/2006 split, same unbounded
#   realized windows, one pass over the whole projection block. jitter.factor is
#   0, so QDM is deterministic -- re-running it reproduces mhat.p exactly, and
#   the only difference between the two product sets is which K scaled which
#   days. Re-running rather than rescaling the existing files is deliberate: it
#   reuses the audited chain in 10 instead of introducing separate arithmetic
#   that would depend on the old manifest staying in sync with the files on disk.
#
# Scope: STATISTICAL TRACK ONLY. The dynamical members are a separate bias-
#   correction track (PICKUP_2026-09-28 G6) whose projection stops 2050-11-30,
#   so ERAS_STATISTICAL does not fit them -- its 2066-2099 block would hold zero
#   days and its 2036-2065 block would be truncated. Their era table is not
#   settled; they are excluded here rather than defaulted into.
#
# Method of record for the era boundaries: Pierce et al. (2015) segments the
#   future into 30-year periods. 2006-2099 is 94 years, so the tail block
#   carries the remainder at 34 years -- see ERAS_STATISTICAL in 10.
#
# Inputs:
#   - scripts/10_future_bias_correction.R  (the whole correction chain; 10 runs
#     nothing on source)
#   - data_in/Umatilla_Future_Flows/*-UMAMC-streamflow-1.0.csv  (raw members)
#   - data/dv_gage_daily_flows.csv                              (o.c, from 04a)
#
# Outputs (alongside the existing "-BC" set, not replacing it):
#   - data/Umatilla_Future_Flows_BC/<member_id>-BC-K-by-era.csv
#   - data/Umatilla_Future_Flows_BC/_bc-k-by-era_manifest.csv
#   - data/Umatilla_Future_Flows_BC/_bc-k-by-era_kfactors.csv  (member x era)
#
# Runtime: ~1.1 s/member, so ~3 minutes for 160 members.
# =============================================================================

source("scripts/10_future_bias_correction.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

# Named positively rather than as "not DYNAMICAL": a downscaling value that
# appeared later would silently join a negative filter, and this script's whole
# premise is that the era table fits the track it is applied to.
STATISTICAL_DOWNSCALING <- c("BCSD", "MACA")

PRODUCT_TAG <- "BC-K-by-era"


# =============================================================================
# 2. MEMBER SELECTION
# =============================================================================

select_track <- function(members, downscaling_values) {
  #' The members belonging to one bias-correction track. (pure)
  #' Separated from the run so the selection can be inspected before a 3-minute
  #' job commits to it.
  #' @param members tibble from list_future_members()
  #' @param downscaling_values character vector of `downscaling` values to keep
  #' @return the filtered members tibble
  filter(members, downscaling %in% downscaling_values)
}


# =============================================================================
# 3. RUN
# =============================================================================

members     <- list_future_members()
statistical <- select_track(members, STATISTICAL_DOWNSCALING)
obs_q       <- read_native_gauge_reference()$q_cfs

message(sprintf("Era-K re-run: %d statistical members, %d eras (%s)",
                nrow(statistical), nrow(ERAS_STATISTICAL),
                paste(ERAS_STATISTICAL$era, collapse = ", ")))

manifest <- run_bias_correction(
  members = statistical,
  obs_q   = obs_q,
  eras    = ERAS_STATISTICAL,
  tag     = PRODUCT_TAG,
  overwrite = TRUE   # this tag has no prior products; explicit so a re-run of
                     # this script refreshes rather than silently resumes.
)


# =============================================================================
# 4. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

count(manifest, status)

# K spread by era, across the 160 members. Read against the single-K values in
# _bc_manifest.csv; the comparison itself is a separate question.
read_csv(file.path(BC_OUT_DIR, sprintf("_%s_kfactors.csv", tolower(PRODUCT_TAG))),
         show_col_types = FALSE) %>%
  summarise(n = n(), k_min = min(k), k_med = median(k), k_max = max(k),
            .by = era)
