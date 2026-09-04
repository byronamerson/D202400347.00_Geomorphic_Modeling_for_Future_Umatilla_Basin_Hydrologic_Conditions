# =============================================================================
# 04c_interval_forcing_metrics.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 4c: Per-interval forcing metrics (the flood predictors)
# =============================================================================
#
# Purpose: Reduce the extended daily discharge record to a small set of flood
#          summary numbers for each HMA photo interval, so channel change can be
#          regressed on them.
#
#          Vocabulary (used in the comments below):
#            - FORCING = the independent variable, the hydrologic driver. Here,
#              the discharge / flood numbers that potentially do the geomorphic
#              work. These are the predictors (the x's).
#            - RESPONSE = the dependent variable, the channel change (e.g.
#              net_area_change from the HMA polygons). Built elsewhere
#              (rs30_interval_sandbox.R); joined to these forcing metrics for the
#              regression.
#
#          For each interval t1 -> t2, the forcing window is water years
#          (t1 + 1) through t2 — the same alignment used for the interval-max
#          peak in rs30_interval_sandbox.R (the flood that did the work must fall
#          within the interval, not before it).
#
# Forcing metrics per interval (threshold = Q2 ~5,542 cfs unless changed):
#   - q_peak_daily_cfs           : max daily mean discharge in the window
#   - threshold_cfs              : the exceedance threshold actually used
#                                  (metric_fraction x Q2; = Q2 when fraction = 1.0)
#   - days_above_thresh          : number of days with daily Q >= threshold
#   - cum_excess_thresh_cfs_days : sum of max(0, dailyQ - threshold) over the
#                                  window, in cfs-days (magnitude x duration above
#                                  threshold = the "effective discharge" / work
#                                  proxy; x 86,400 for ft^3, or x 1.983 for acre-ft)
#   - n_events_thresh            : number of discrete flood events (strictly
#                                  consecutive runs of days >= threshold)
#   - max_duration_thresh_days   : longest strictly-consecutive run of days >=
#                                  threshold (one below-threshold day ends a run)
#   - any_estimated              : TRUE if the window contains any reconstructed
#                                  (pre-1995) day — the honest observed/estimated flag
#
# The span-based metrics (n_events_thresh, max_duration_thresh_days) and the
# total duration all derive from ONE definition of a flood "span": a strictly-
# consecutive run of above-threshold days (a single below-threshold day ends a
# run). Because sum(span lengths) == days_above_thresh by construction, total
# duration and the day tally are the same number, asserted below as a guard.
#
# Because the reconstruction floor (~4,156 cfs) is BELOW Q2, every day that could
# cross Q2 is present in the record, so all Q2-based metrics are COMPLETE across
# 1952-present (not sparse). Metric thresholds below ~0.75 x Q2 are not fully
# supported by the reconstructed record.
#
# Inputs:
#   data/pendleton_daily_extended.rds   — from 04b (date, daily_q_cfs, is_estimated, ...)
#   an intervals tibble with year_t1, year_t2 (e.g. distinct rows of rs30_plot_data)
#
# Output:
#   data/interval_forcing_metrics.csv   — one row per interval
#
# Style: lingua.md (boundary contracts, small pure functions, I/O at the
#   orchestrator boundary) and the Tidyverse & Functional Programming Guidelines.
# =============================================================================

library(tidyverse)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

config <- tribble(
  ~parameter,             ~value,
  "q2_target_cfs",        "5542",     # Pendleton Q2 (post-McKay-correction B17C)
  "metric_fraction",      "1.0",      # metric threshold = fraction x Q2 (1.0 = Q2)
  "extended_record_rds",  "data/pendleton_daily_extended.rds",
  "forcing_csv",          "data/interval_forcing_metrics.csv"
)

cfg <- function(param) config %>% filter(parameter == param) %>% pull(value)
cfg_num <- function(param) as.numeric(cfg(param))


# =============================================================================
# 2. HELPERS
# =============================================================================

add_water_year <- function(daily, date_col = "date") {
  #' Attach USGS water year (Oct 1 (T-1) .. Sep 30 (T)) to a daily record.
  #' @param daily tibble with a Date column; @param date_col its name
  #' @return `daily` with an integer water_year column added
  d <- daily[[date_col]]
  mutate(daily,
         water_year = as.integer(format(d, "%Y")) +
           if_else(as.integer(format(d, "%m")) >= 10L, 1L, 0L))
}

consecutive_run_lengths <- function(dates) {
  #' Lengths of every strictly-consecutive run of calendar days in a date set.
  #' A gap of more than one calendar day (a below-threshold or absent day) ends
  #' a run — correct even with the sparse pre-1995 record. This one definition of
  #' a flood "span" feeds every span-based metric, so the event count, the total
  #' duration, and the longest run stay mutually consistent by construction.
  #' @param dates Date vector of threshold-exceeding days
  #' @return integer vector of run lengths (empty if none); sum() == length(dates)
  if (length(dates) == 0L) return(integer(0))
  d <- sort(unique(dates))
  run_id <- cumsum(c(TRUE, as.integer(diff(d)) > 1L))  # a >1-day gap ends a run
  as.integer(tabulate(run_id))
}


# =============================================================================
# 3. FORCING METRICS
# =============================================================================

compute_interval_forcing <- function(window, threshold_cfs) {
  #' Reduce one interval's daily window to the flood-predictor (forcing) metrics.
  #' @param window daily rows for the interval (date, daily_q_cfs, is_estimated)
  #' @param threshold_cfs metric (exceedance) threshold in cfs
  #' @return one-row tibble of forcing metrics (see file header)
  above <- filter(window, daily_q_cfs >= threshold_cfs)
  spans <- consecutive_run_lengths(above$date)   # one canonical set of flood spans
  stopifnot(sum(spans) == nrow(above))           # every above-day is in exactly one span
  tibble(
    n_window_days              = nrow(window),
    q_peak_daily_cfs           = if (nrow(window)) max(window$daily_q_cfs) else NA_real_,
    threshold_cfs              = threshold_cfs,
    days_above_thresh          = nrow(above),
    cum_excess_thresh_cfs_days = sum(pmax(0, window$daily_q_cfs - threshold_cfs)),
    n_events_thresh            = length(spans),
    max_duration_thresh_days   = if (length(spans)) max(spans) else 0L,
    any_estimated              = any(window$is_estimated)
  )
}

compute_all_interval_forcing <- function(extended_daily, intervals, threshold_cfs) {
  #' Compute forcing metrics for every interval. The forcing window for
  #' t1 -> t2 is water years (t1 + 1) .. t2 (matches the peak alignment in
  #' rs30_interval_sandbox.R).
  #' @param extended_daily the extended daily record (from 04b)
  #' @param intervals tibble with year_t1, year_t2 (extra columns are preserved)
  #' @param threshold_cfs metric (exceedance) threshold in cfs
  #' @return `intervals` with the forcing-metric columns appended
  stopifnot(all(c("year_t1", "year_t2") %in% names(intervals)))
  dw <- add_water_year(extended_daily)
  intervals %>%
    mutate(.forcing = pmap(list(year_t1, year_t2), function(t1, t2) {
      window <- filter(dw, water_year > t1, water_year <= t2)
      compute_interval_forcing(window, threshold_cfs)
    })) %>%
    unnest(.forcing)
}


# =============================================================================
# 4. ORCHESTRATOR
# =============================================================================

run_interval_forcing_metrics <- function(config, intervals) {
  #' Read the extended daily record, compute per-interval forcing metrics at the
  #' configured threshold, write the CSV, and return the table.
  #' @param config config tribble; @param intervals tibble with year_t1, year_t2
  #' @return the intervals table with forcing-metric columns appended
  extended <- readRDS(cfg("extended_record_rds"))
  threshold <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")
  message("  Metric threshold: ", round(threshold), " cfs (",
          cfg("metric_fraction"), " x Q2)")

  forcing <- compute_all_interval_forcing(
    extended, intervals, threshold
  )

  readr::write_csv(forcing, cfg("forcing_csv"))
  message("  Wrote ", nrow(forcing), " intervals to ", cfg("forcing_csv"))
  forcing
}


# =============================================================================
# 5. INTERACTIVE STEPWISE RUN
# =============================================================================
##
## Single-hash lines are executable; double-hash is narration. NOTE the source
## order: source the sandbox FIRST (it builds rs30_plot_data and defines its own
## `config`), capture what you need, THEN source this script so its `config`
## (the forcing config) is the active one.
##
## ---- Step 1: get the intervals and the response (migration) from the sandbox --
#
# source("scripts/rs30_interval_sandbox.R")   # builds rs30_plot_data
# intervals <- dplyr::distinct(rs30_plot_data, year_t1, year_t2)
# migration <- rs30_plot_data                 # keep for the join below
##
## ---- Step 2: compute the forcing metrics ----
#
# source("scripts/04c_interval_forcing_metrics.R")   # forcing `config` now active
# forcing <- run_interval_forcing_metrics(config, intervals)
# forcing
##
## ---- Step 3: join forcing to response and take a first look ----
#
# dat <- dplyr::left_join(migration, forcing, by = c("year_t1", "year_t2"))
##
## First test: does cumulative excess above Q2 beat interval-max peak on
## net_area_change? (weight short intervals down by interval_years^2 as before)
#
# summary(lm(net_area_change_ft2_per_year ~ cum_excess_thresh_cfs_days,
#            data = dat, weights = interval_years^2))
# summary(lm(net_area_change_ft2_per_year ~ days_above_thresh,
#            data = dat, weights = interval_years^2))
