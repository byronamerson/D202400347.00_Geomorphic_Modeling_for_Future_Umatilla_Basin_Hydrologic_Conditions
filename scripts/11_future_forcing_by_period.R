# =============================================================================
# 11_future_forcing_by_period.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 11 (projection Step 2): future forcing by reporting period.
# =============================================================================
#
# Reduce a set of bias-corrected future flows to per-water-year cum_excess >
# 0.75xQ2, tagged by reporting period and member factors -- the forcing primitive
# the migration projection (Step 3) consumes. Carries the observed record on the
# SAME footing (one uniform per-year cum_excess pipeline) so future, observed and
# corrected-historical can be laid side by side for gut-checking (Byron: baseline
# is moot, view them together).
#
# PER-YEAR, not period-total, is the deliberate primitive: from per-year cum_excess
# we can form EITHER a period total OR a mean-annual rate at Step 3, so this step
# does NOT pre-commit the rate construction.
#
# NOTHING RUNS ON SOURCE. This file defines the chain; a runner script selects the
# product set, the track and the period table and calls run_future_forcing().
# Same shape as 10 / 10b / 10c.
#   - scripts/11b_future_forcing_era_k.R            statistical, 160 members
#   - scripts/11c_future_forcing_era_k_dynamical.R  dynamical, 12 members
#
# Reuse: 04c add_water_year + compute_all_interval_forcing at the config threshold;
#   a bias-correction manifest from 10 for the factor grid. (add_water_year /
#   annual helpers are duplicated from x15 pending the deferred R/ module --
#   NOTE_shared_module_refactor.md.)
# Inputs : data/Umatilla_Future_Flows_BC/<member>-<tag>.csv + the matching manifest
#          data/pendleton_daily_extended.rds (observed, via 04c config)
# Outputs: written by the runner; paths are arguments.
# Style  : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(readr)
library(purrr)
library(tidyr)

source("scripts/04c_interval_forcing_metrics.R")   # add_water_year, compute_all_interval_forcing, cfg, cfg_num
source("scripts/eras.R")                           # ERAS_STATISTICAL, ERAS_DYNAMICAL, as_period_table()


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

THRESHOLD <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")   # 0.75xQ2 = 4156 cfs
BC_DIR    <- "data/Umatilla_Future_Flows_BC"

# A water year is complete at 365 days (366 in a leap water year). Below that the
# year's cum_excess is a sum over a short record and is not comparable to a full
# year's; see drop_partial_water_years().
FULL_WATER_YEAR_DAYS <- 365L


# --- Reporting periods ---------------------------------------------------------
# NO TABLE IS DECLARED HERE. The blocks are the bias-correction eras, defined
# once in scripts/eras.R (Byron, 2026-09-29), and a runner passes the one for its
# track through as_period_table(), which supplies the `period` column name this
# step keys on and each block's nominal length in years.
#
# What changed and why it matters: this step used to carry its own statistical
# table opening with a 2030s decade, and 12 carried a third opening with a
# 2010-2039 normal. Nothing broke, because 12 re-bins from the per-year file --
# but water years 2006-2029 fell in no period and were silently dropped from this
# step's summary, and the summary's period labels did not name the same spans as
# the projection's. Both are gone: the eras cover 2006-2099 with no gap, and one
# block table now serves correction, forcing and projection alike.
#
# with_t_norm() lived here and in 12; as_period_table() in scripts/eras.R
# replaces both copies.


# =============================================================================
# 2. FORCING PRIMITIVE -- per-water-year cum_excess for one daily series
# =============================================================================

annual_intervals <- function(daily) {
  #' Each water year as its own one-year forcing window (year_t1 = wy-1,
  #' year_t2 = wy), matching compute_all_interval_forcing's (t1, t2] convention.
  wy <- sort(unique(add_water_year(daily)$water_year))
  tibble(year_t1 = wy - 1L, year_t2 = wy)
}

annual_cum_excess <- function(daily) {
  #' Per-water-year cum_excess above THRESHOLD for a daily series, with the
  #' record length that produced it.
  #' n_days is compute_interval_forcing()'s own n_window_days -- the count of
  #' DAILY RECORDS in the water year, not days above threshold. Taken from there
  #' rather than recounted here, so the two cannot disagree. It is what makes a
  #' partial year visible downstream; without it a 9-month year and a 12-month
  #' year are indistinguishable in the output.
  #' @param daily tibble(date, daily_q_cfs, is_estimated)
  #' @return tibble(water_year, cum_excess, n_days)
  compute_all_interval_forcing(daily, annual_intervals(daily), THRESHOLD) %>%
    transmute(water_year = year_t2,
              cum_excess = cum_excess_thresh_cfs_days,
              n_days     = n_window_days)
}

drop_partial_water_years <- function(annual, label) {
  #' Remove water years whose record is shorter than a full year, and say which.
  #' The dynamical members begin 2011-01-01, so their WY2011 holds Jan-Sep only
  #' and its cum_excess is a 9-month sum; left in, it would sit inside the
  #' 2011-2030 period and drag that period's mean annual forcing down. The
  #' statistical members begin 2006-01-01 and have the same defect at WY2006,
  #' which no reporting period has ever reached.
  #' @param annual tibble with water_year, n_days (one member or pooled)
  #' @param label character, named in the message
  #' @return annual, partial years removed
  partial <- filter(annual, n_days < FULL_WATER_YEAR_DAYS)
  if (nrow(partial) > 0) {
    message(sprintf("  %s: dropped %d partial member-year(s); water years %s",
                    label, nrow(partial),
                    paste(sort(unique(partial$water_year)), collapse = ", ")))
  }
  filter(annual, n_days >= FULL_WATER_YEAR_DAYS)
}

read_bc_member <- function(path) {
  #' One bias-corrected future member as a forcing-ready daily series (corrected
  #' modeled flow, not reconstruction -> is_estimated = FALSE). Reads q_corrected
  #' by name, so the era-K product set's extra `era` column is ignored.
  read_csv(path, show_col_types = FALSE) %>%
    transmute(date = as.Date(date), daily_q_cfs = q_corrected, is_estimated = FALSE)
}


# =============================================================================
# 3. PERIOD TAGGING  (table-driven; NA outside any period)
# =============================================================================

tag_period <- function(annual, periods) {
  #' Attach the period label from `periods` via a non-equi join. Water years
  #' outside every period get period = NA (kept in the annual file, dropped from
  #' the summary). Tolerating NA is correct HERE and is the documented difference
  #' from assign_era() in 10, where an unlabelled day would have no K.
  #' @param annual tibble with water_year
  #' @param periods tibble(period, y1, y2, t_norm)
  annual %>%
    left_join(periods, by = join_by(between(water_year, y1, y2))) %>%
    select(-y1, -y2)
}


# =============================================================================
# 4. THE UNIT OF WORK -- one product set x one track
# =============================================================================

read_track_manifest <- function(manifest_path, tag, bc_dir = BC_DIR) {
  #' The member factor grid for one product set, restricted to members whose
  #' corrected CSV is actually on disk. (I/O)
  #' @param manifest_path a bias-correction manifest written by 10
  #' @param tag product-set suffix, e.g. "BC-K-by-era" -- must match the CSVs the
  #'   manifest describes, or every path fails to exist
  #' @return tibble(member_id, gcm, scenario, downscaling, hydro, bc_path)
  manifest <- read_csv(manifest_path, show_col_types = FALSE) %>%
    mutate(bc_path = file.path(bc_dir, sprintf("%s-%s.csv", member_id, tag)))
  present <- filter(manifest, file.exists(bc_path))
  if (nrow(present) < nrow(manifest)) {
    message(sprintf("  %d of %d members in %s have no %s CSV on disk",
                    nrow(manifest) - nrow(present), nrow(manifest),
                    basename(manifest_path), tag))
  }
  transmute(present, member_id, gcm, scenario, downscaling, hydro, bc_path)
}

future_annual_forcing <- function(members, periods) {
  #' Per-water-year cum_excess for every member in one track. (I/O = the reads)
  #' @param members tibble from read_track_manifest()
  #' @param periods tibble(period, y1, y2, t_norm)
  #' @return tibble(member factors, water_year, cum_excess, n_days, source, period, t_norm)
  members %>%
    mutate(annual = map(bc_path, ~ annual_cum_excess(read_bc_member(.x)))) %>%
    select(-bc_path) %>%
    unnest(annual) %>%
    drop_partial_water_years("future members") %>%
    mutate(source = "future") %>%
    tag_period(periods)
}

fill_flood_free_years <- function(annual) {
  #' Enter water years that produced no forcing window as zeros. (pure)
  #' A water year in which no day cleared the 0.75xQ2 floor leaves no rows in
  #' data/pendleton_daily_extended.rds, so annual_intervals() builds no window
  #' for it and annual_cum_excess() returns nothing -- the year vanishes rather
  #' than reporting the zero it is. That silently conditions the historical
  #' baseline on years that had floods.
  #' Byron, 2026-09-29: a year with no exceedance is real and belongs in the
  #' data set. The reconstruction floor sits BELOW Q2, so an absent year is a
  #' measured zero, not a gap in coverage.
  #' Interior years only -- the span runs from the first water year with a
  #' record to the last, so nothing is invented beyond the record's own ends.
  #' @param annual tibble(water_year, cum_excess, n_days)
  #' @return annual + one zero row per absent water year, ordered
  span   <- seq(min(annual$water_year), max(annual$water_year))
  absent <- setdiff(span, annual$water_year)
  if (length(absent) > 0) {
    message(sprintf("  observed: %d flood-free water year(s) entered as zero; %s",
                    length(absent), paste(sort(absent), collapse = ", ")))
  }
  annual %>%
    bind_rows(tibble(water_year = as.integer(absent),
                     cum_excess = 0, n_days = 0L)) %>%
    arrange(water_year)
}

observed_annual_forcing <- function() {
  #' The observed record through the same per-year pipeline, tagged "historical".
  #' It is the anchor F_hist that 12 measures every period against, and it is the
  #' SAME on both tracks.
  #' NO completeness filter here, and n_days does not mean what it means for a
  #' member. `data/pendleton_daily_extended.rds` is a complete daily record only
  #' from WY1996; before that it holds ONLY the ~280 days 04b reconstructed above
  #' the 0.75xQ2 floor. That floor is the metric threshold, so a pre-1996 water
  #' year with eight rows is complete FOR cum_excess -- every day that could
  #' contribute is present. Design, settled 09-03/09-04; do not "repair" it by
  #' filtering on n_days.
  #' A year with NO above-floor day is the limiting case of the same design: it
  #' holds no rows, so it produced no window. fill_flood_free_years() enters it
  #' as the zero it is (Byron, 2026-09-29), which is why n_days = 0 appears on
  #' those rows and why F_hist is now a mean over the full span.
  #' @return tibble on the same columns as future_annual_forcing()
  readRDS(cfg("extended_record_rds")) %>%
    annual_cum_excess() %>%
    fill_flood_free_years() %>%
    mutate(member_id = "observed", gcm = NA_character_, scenario = "observed",
           downscaling = NA_character_, hydro = NA_character_,
           source = "observed", period = "historical", t_norm = NA_integer_)
}

summarise_periods <- function(annual_all) {
  #' Per member x period summary -- the Step 3 rate primitive.
  #' n_years is REALIZED (rows surviving the partial-year drop); t_norm is NOMINAL
  #' (the period table's length). They differ where a partial year was dropped,
  #' and both are carried so the difference is visible rather than inferred.
  #' @param annual_all per member x water-year forcing, period-tagged
  #' @return tibble(source, member factors, period, t_norm, n_years, ...)
  annual_all %>%
    filter(!is.na(period)) %>%
    group_by(source, member_id, gcm, scenario, downscaling, hydro, period, t_norm) %>%
    summarise(n_years                = dplyr::n(),
              mean_annual_cum_excess = mean(cum_excess),
              total_cum_excess       = sum(cum_excess),
              max_annual_cum_excess  = max(cum_excess),
              .groups = "drop")
}

run_future_forcing <- function(manifest_path, tag, periods,
                               out_annual, out_summary, bc_dir = BC_DIR) {
  #' Build one track's forcing tables from one product set. (the orchestrator)
  #' @param manifest_path bias-correction manifest for this track's product set
  #' @param tag product-set suffix naming the member CSVs
  #' @param periods tibble(period, y1, y2, t_norm) -- this track's reporting periods
  #' @param out_annual,out_summary output paths (track-suffixed by the caller, so
  #'   one track's run cannot overwrite the other's)
  #' @return list(annual, summary), invisibly
  stopifnot(file.exists(manifest_path),
            all(c("period", "y1", "y2", "t_norm") %in% names(periods)))

  members <- read_track_manifest(manifest_path, tag, bc_dir)
  stopifnot(nrow(members) > 0)
  message(sprintf("Computing annual cum_excess for %d members (%s) ...",
                  nrow(members), tag))

  annual_all <- bind_rows(future_annual_forcing(members, periods),
                          observed_annual_forcing())
  period_summary <- summarise_periods(annual_all)

  write_csv(annual_all,     out_annual)
  write_csv(period_summary, out_summary)
  message(sprintf("Wrote %s (%d rows) and %s (%d rows)",
                  out_annual, nrow(annual_all), out_summary, nrow(period_summary)))

  invisible(list(annual = annual_all, summary = period_summary))
}
