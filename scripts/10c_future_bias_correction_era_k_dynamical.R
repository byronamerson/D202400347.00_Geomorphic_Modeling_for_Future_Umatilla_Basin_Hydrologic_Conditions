# =============================================================================
# 10c_future_bias_correction_era_k_dynamical.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 10c: Re-correct the DYNAMICAL future members with the PresRat K-factor
#            computed per era rather than once for 2011-2050.
# =============================================================================
#
# Purpose: the dynamical counterpart to 10b. Same change, same reason -- one K
#   across a whole projection is untested granularity -- applied to the twelve
#   dynamically-downscaled members with an era table that fits their record.
#
# Why this is its own script and not a second call inside 10b. The dynamical
#   members are a SEPARATE ANALYTICAL TRACK (PICKUP_2026-09-28 G6), not a subset
#   of the ensemble that happens to be shorter. The provider states in print that
#   these forcings were "trained to a different historical meteorological forcing
#   dataset," which makes direct comparison problematic; the two tracks are never
#   pooled into one ensemble summary. The forward model is run on each set
#   separately, and the side-by-side results are themselves the finding -- how
#   the differing assumptions play out over the next ~40 years. Keeping the runs
#   in separate scripts keeps that separation visible in the file tree rather
#   than buried in a filter argument.
#
# Era table: ERAS_DYNAMICAL in 10 -- two 20-year blocks, 2011-2030 and
#   2031-2050. Not Pierce's 30-year blocks, which would split this 40-year
#   record into 30 and 10; 20 is already the project's block length under G1.
#   The bounds are deliberately NOT aligned with ERAS_STATISTICAL, because K
#   never crosses tracks and alignment would buy nothing.
#
# What is NOT changed here: the QDM correction itself. Same engine, same o.c,
#   same 2005/2006 split, same realized windows (control 1966-01-01 to
#   2005-11-30, projection 2011-01-01 to 2050-11-30, 14,579 days each).
#   jitter.factor is 0, so QDM is deterministic and the only difference from the
#   existing "-BC" products is which K scaled which days.
#
# Inputs:
#   - scripts/10_future_bias_correction.R  (the whole correction chain)
#   - data_in/Umatilla_Future_Flows/*_DYNAMICAL_*-UMAMC-streamflow-1.0.csv
#   - data/dv_gage_daily_flows.csv                              (o.c, from 04a)
#
# Outputs (alongside the existing "-BC" set, not replacing it):
#   - data/Umatilla_Future_Flows_BC/<member_id>-BC-K-by-era.csv  (12 members;
#     same product tag as 10b, since this is the same K-by-era correction of the
#     same ensemble -- member filenames are unique, so the two runs coexist)
#   - data/Umatilla_Future_Flows_BC/_bc-k-by-era-dynamical_manifest.csv
#   - data/Umatilla_Future_Flows_BC/_bc-k-by-era-dynamical_kfactors.csv
#     The sidecars carry their OWN tag because run_bias_correction() writes them
#     rather than appending: sharing 10b's sidecar tag would replace its 160
#     statistical rows with these 12. The two tracks' sidecars are joined by the
#     reader, which also keeps G6's separation explicit at the file level.
#   Run order does not matter -- neither script can clobber the other's outputs.
#
# Runtime: ~1 s/member, so well under a minute for 12.
# =============================================================================

source("scripts/10_future_bias_correction.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

DYNAMICAL_DOWNSCALING <- "DYNAMICAL"

# Same product tag as 10b -- these are the same K-by-era correction of the same
# ensemble, built in two runs because the era table differs by track, and the
# member CSVs are uniquely named so they coexist. The SIDECARS get their own tag
# because run_bias_correction() writes them rather than appending; see header.
PRODUCT_TAG <- "BC-K-by-era"
SIDECAR_TAG <- "BC-K-by-era-dynamical"


# =============================================================================
# 2. MEMBER SELECTION
# =============================================================================

select_track <- function(members, downscaling_values) {
  #' The members belonging to one bias-correction track. (pure)
  #' Separated from the run so the selection can be inspected before the job
  #' commits to it.
  #' DUPLICATED from 10b rather than sourced: 10b executes its 160-member run on
  #' source, so sourcing it here to borrow one helper would re-run the whole
  #' statistical job. The right fix is to lift shared helpers into a utilities
  #' module (NOTE_shared_module_refactor.md); until then the duplication is
  #' deliberate and is recorded here so it is not mistaken for drift.
  #' @param members tibble from list_future_members()
  #' @param downscaling_values character vector of `downscaling` values to keep
  #' @return the filtered members tibble
  filter(members, downscaling %in% downscaling_values)
}


# =============================================================================
# 3. RUN
# =============================================================================

members    <- list_future_members()
dynamical  <- select_track(members, DYNAMICAL_DOWNSCALING)
obs_q      <- read_native_gauge_reference()$q_cfs

message(sprintf("Era-K re-run (dynamical): %d members, %d eras (%s)",
                nrow(dynamical), nrow(ERAS_DYNAMICAL),
                paste(ERAS_DYNAMICAL$era, collapse = ", ")))

manifest <- run_bias_correction(
  members = dynamical,
  obs_q   = obs_q,
  eras    = ERAS_DYNAMICAL,
  tag     = PRODUCT_TAG,
  sidecar_tag = SIDECAR_TAG,
  overwrite = TRUE
)


# =============================================================================
# 4. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

count(manifest, status)

read_csv(file.path(BC_OUT_DIR, sprintf("_%s_kfactors.csv", tolower(SIDECAR_TAG))),
         show_col_types = FALSE) %>%
  summarise(n = n(), k_min = min(k), k_med = median(k), k_max = max(k),
            .by = era)