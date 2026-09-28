# =============================================================================
# 01e_daily_extension.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1e: Daily Mean Discharge Record Extension for USGS 14020850 (Pendleton)
# =============================================================================
#
# Purpose: Extend the Pendleton daily mean discharge record backward from its
#          observed start (~1995-10) to 1952, so that high-flow forcing metrics
#          (days above Q2, cumulative excess volume, event count, max duration)
#          can be computed per HMA photo interval over the full 1952-present
#          analysis window. This is NOT a general daily-hydrograph
#          reconstruction: only the high-flow tail matters.
#
# Method: Conditional MOVE.1 (Line of Organic Correlation, variance-preserving)
#         fitted on high-flow days in log10 space, Gibbon (14020000) -> Pendleton
#         (14020850). MOVE.1 preserves the marginal variance of the extended
#         record (unlike OLS, which shrinks toward the mean and would truncate
#         the high-flow tail the whole analysis depends on).
#         Reference: Hirsch (1982), WRR 18(4):1081-1088.
#
# Key design decisions (established in session 2026-09-03; see project record):
#   - GIBBON-ONLY START, with a validation gate. Gibbon is unregulated and has
#     complete daily coverage across 1952-1996. The downstream Umatilla gage
#     (14033500) as a second index would require building a daily McKay
#     regulation correction and only helps 1980-1996, so it is held in reserve.
#     Escalate to two-index only if the concurrent-period diagnostics show the
#     Gibbon->Pendleton transfer is too weak.
#   - TWO INDEPENDENT THRESHOLDS, set by different logic:
#       * Screening/reconstruction threshold (STATISTICAL): how low we can
#         transfer reliably. Lowered toward the bankfull band (~Q1.5) to gain
#         calibration data and buffer the Q2 boundary, but bounded above the
#         flow level where losing-stream/irrigation dynamics distort the
#         inter-gage relationship. The exact floor is chosen empirically by the
#         threshold-sensitivity ladder (Section 4), not by gut.
#       * Metric threshold (GEOMORPHIC): Q2 (~5,542 cfs), what does the
#         geomorphic work. Applied when computing forcing metrics downstream.
#         Kept independent of the screening threshold.
#   - Days below the screening threshold are not reconstructed; they contribute
#     zero to every high-flow metric, so this is zero-weighting, not data loss.
#   - Serial correlation on daily data inflates uncertainty, not the central
#     estimate. Reconstructed metrics are reported as estimates and validated by
#     the annual-metric MOVE.3 cross-check (Section 9). Report reconstructed vs
#     observed intervals distinctly; do not overstate precision on the former.
#
# Inputs (from 04a):
#   data/dv_gage_daily_flows.csv   — daily mean Q, all three gages
#                                    (gage_id, date, daily_q_cfs, ...)
#
# Outputs:
#   data/pendleton_daily_extended.rds  — tidy tibble of extended daily flows at
#     14020850, 1952-present, with observed-vs-estimated flag, source index,
#     prediction, and jackknife-based uncertainty. (Written once modeling
#     sections are implemented.)
#
# Dependencies:
#   smwrStats::move.1(), predict.move.1(), jackknifeMove.1()  (USGS, code.usgs.gov)
#   (Read the move.1 docs before implementing Section 5 — verify whether the
#    log10 transform belongs in the formula or in `distribution="commonlog"`,
#    not both. lingua.md Section 1.)
#
# Status: SUPERSEDED 2026-09-03 — preserved as the MOVE.1 exploration record.
#   The threshold-sensitivity ladder plus a quadratic curvature test (Section 4
#   diagnostics, run this session) showed the log10 Gibbon->Pendleton transfer
#   is significantly nonlinear across the whole high-flow range (quadratic term
#   p = 3e-4; slope drifts ~0.55 in the tail to ~0.89 at moderate flow). A single
#   MOVE.1 line is therefore misspecified. The active extension moved to
#   MOVE.2 + optimBoxCox in 04b_daily_value_extension.R, which carries the same
#   (method-agnostic) diagnostic Sections 1-4 forward. This file is kept
#   unchanged to document the process and the MOVE.1 finding.
#
# Style: Follows lingua.md (boundary contracts, small pure functions, I/O at the
#   orchestrator boundary) and the Tidyverse & Functional Programming Guidelines.
# =============================================================================

library(tidyverse)
# library(smwrStats)   # enable when Section 5 (MOVE.1 fit) is implemented


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

config <- tribble(
  ~parameter,             ~value,
  "target_gage_id",       "14020850",   # Pendleton (target of the extension)
  "index_gage_id",        "14020000",   # Gibbon (primary index, unregulated)
  "secondary_index_id",   "14033500",   # Umatilla (reserved; two-index fallback)
  "q2_target_cfs",        "5542",       # Pendleton Q2, post-McKay-correction B17C
                                        #   (Project_Context_Primer diagnostic)
  "extension_start",      "1952-01-01", # earliest HMA photo year
  "daily_flows_csv",      "data/dv_gage_daily_flows.csv",
  "extended_record_rds",  "data/pendleton_daily_extended.rds"
)

# Fractions of Q2 scanned by the threshold-sensitivity ladder (Section 4).
# The screening floor is chosen from where the transfer stays stable, expected
# around the bankfull band (~0.5-0.7 x Q2).
THRESHOLD_FRACTIONS <- c(1.00, 0.75, 0.50, 0.35, 0.25)

# Helpers to pull typed scalars from the config tribble.
cfg <- function(param) {
  config %>% filter(parameter == param) %>% pull(value)
}
cfg_num <- function(param) as.numeric(cfg(param))


# =============================================================================
# 2. DATA LOADING
# =============================================================================

add_water_year <- function(daily, date_col = "date") {
  #' Attach USGS water year and month to a daily record.
  #'
  #' Water year T runs Oct 1 (year T-1) through Sep 30 (year T). Month is kept
  #' for the seasonal residual checks in Section 3.
  #'
  #' @param daily tibble with a Date column
  #' @param date_col name of the Date column
  #' @return `daily` with integer `water_year` and `month` columns added
  d <- daily[[date_col]]
  daily %>%
    mutate(
      month = as.integer(format(d, "%m")),
      water_year = as.integer(format(d, "%Y")) + if_else(month >= 10L, 1L, 0L)
    )
}

load_daily_extension_inputs <- function(config) {
  #' Load the daily mean discharge records for the target and index gages.
  #'
  #' Reads the tidy long daily table written by 04a and splits it into the
  #' target (Pendleton) and primary index (Gibbon) series. Positive, non-missing
  #' discharge only, since the transfer is fit in log space.
  #'
  #' @param config the config tribble (target_gage_id, index_gage_id, path)
  #' @return named list: target_daily, index_daily (each gage_id, date,
  #'   daily_q_cfs, water_year, month)
  daily <- read_csv(
    cfg("daily_flows_csv"),
    col_types = cols(.default = col_guess(), gage_id = col_character())
  ) %>%
    filter(!is.na(daily_q_cfs), daily_q_cfs > 0) %>%
    select(gage_id, date, daily_q_cfs) %>%
    add_water_year()

  target_id <- cfg("target_gage_id")
  index_id  <- cfg("index_gage_id")

  target_daily <- filter(daily, gage_id == target_id)
  index_daily  <- filter(daily, gage_id == index_id)

  message("  Target (", target_id, "): ", nrow(target_daily), " days, ",
          min(target_daily$date), " to ", max(target_daily$date))
  message("  Index  (", index_id, "): ", nrow(index_daily), " days, ",
          min(index_daily$date), " to ", max(index_daily$date))

  list(target_daily = target_daily, index_daily = index_daily)
}

build_concurrent_daily <- function(target_daily, index_daily) {
  #' Join target and index daily series on shared dates (the concurrent period).
  #'
  #' The inner join yields exactly the overlap window (~1995-10 onward) where
  #' both gages observe, which is the calibration set for the transfer.
  #'
  #' @param target_daily,index_daily tibbles (gage_id, date, daily_q_cfs, ...)
  #' @return tibble: date, water_year, month, target_q, index_q (one row/day)
  concurrent <- inner_join(
    target_daily %>% select(date, water_year, month, target_q = daily_q_cfs),
    index_daily  %>% select(date, index_q = daily_q_cfs),
    by = "date"
  )
  message("  Concurrent daily record: ", nrow(concurrent), " days, ",
          min(concurrent$date), " to ", max(concurrent$date))
  concurrent
}


# =============================================================================
# 3. CONCURRENT HIGH-FLOW CHARACTERIZATION  (diagnostic Step 1)
# =============================================================================

count_high_flow_events <- function(dates, max_gap_days = 1L) {
  #' Count independent high-flow events among a set of flagged high-flow days.
  #'
  #' Consecutive (or near-consecutive) high-flow days belong to one event. This
  #' is the serial-correlation lens: the number of EVENTS is the effective
  #' sample size for the transfer, always << the number of days.
  #'
  #' @param dates Date vector of days already filtered to high flow
  #' @param max_gap_days gaps up to this many days are treated as one event
  #' @return integer count of independent events
  if (length(dates) == 0L) return(0L)
  d <- sort(unique(dates))
  gaps <- as.integer(diff(d))
  1L + sum(gaps > max_gap_days)
}

characterize_transfer_at_threshold <- function(concurrent, target_threshold_cfs) {
  #' Summarize the log-space Gibbon->Pendleton transfer for high-flow days.
  #'
  #' High-flow days are those where observed target (Pendleton) flow meets the
  #' threshold. The Line-of-Organic-Correlation slope IS the MOVE.1 slope
  #' (sign(r) * sd(log10 target) / sd(log10 index)); computing it directly here
  #' previews the transfer before the formal smwrStats fit + jackknife (Sec 5-6).
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param target_threshold_cfs high-flow cutoff on the target series (cfs)
  #' @return one-row tibble: threshold_cfs, n_days, n_events, r_log, loc_slope,
  #'   loc_intercept, index_q_min (the index flow at the lowest retained day —
  #'   the basis for translating this cutoff to a Gibbon screening threshold)
  hi <- concurrent %>% filter(target_q >= target_threshold_cfs)
  lx <- log10(hi$index_q)
  ly <- log10(hi$target_q)
  r  <- if (nrow(hi) > 2) cor(lx, ly) else NA_real_
  loc_slope <- if (nrow(hi) > 2) sign(r) * sd(ly) / sd(lx) else NA_real_
  loc_intercept <- if (nrow(hi) > 2) mean(ly) - loc_slope * mean(lx) else NA_real_

  tibble(
    threshold_cfs = target_threshold_cfs,
    n_days        = nrow(hi),
    n_events      = count_high_flow_events(hi$date),
    r_log         = r,
    loc_slope     = loc_slope,
    loc_intercept = loc_intercept,
    index_q_min   = if (nrow(hi) > 0) min(hi$index_q) else NA_real_
  )
}

describe_transfer_residuals <- function(concurrent, target_threshold_cfs) {
  #' Per-month residual/scatter diagnostics for the chosen high-flow threshold.
  #'
  #' Detects the two things that would break a single MOVE.1 line: seasonal
  #' regime mixing (residual structure differing by month) and heteroscedasticity
  #' at the high-flow end. Residuals are taken about the LOC line in log space.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param target_threshold_cfs high-flow cutoff on the target series (cfs)
  #' @return tibble by month: n_days, resid_mean, resid_sd (log10 units)
  fit <- characterize_transfer_at_threshold(concurrent, target_threshold_cfs)
  concurrent %>%
    filter(target_q >= target_threshold_cfs) %>%
    mutate(
      resid_log = log10(target_q) -
        (fit$loc_intercept + fit$loc_slope * log10(index_q))
    ) %>%
    group_by(month) %>%
    summarise(
      n_days    = n(),
      resid_mean = mean(resid_log),
      resid_sd   = sd(resid_log),
      .groups = "drop"
    ) %>%
    arrange(month)
}


# =============================================================================
# 4. THRESHOLD-SENSITIVITY LADDER  (diagnostic Step 2 — sets the screening floor)
# =============================================================================

scan_threshold_sensitivity <- function(concurrent, q2_target_cfs, fractions) {
  #' Scan the transfer relationship across a ladder of high-flow thresholds.
  #'
  #' As the threshold drops from Q2 toward bankfull and below, a stable slope,
  #' correlation, and residual spread mean we are still in the single clean
  #' rainfall-runoff regime — lowering is free data. When they start to drift or
  #' fan out, the low-flow (losing-stream/irrigation) regime is leaking in: set
  #' the screening floor just above that breakpoint.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param q2_target_cfs Pendleton Q2 (cfs)
  #' @param fractions numeric vector of Q2 fractions to test
  #' @return tibble, one row per threshold: fraction, threshold_cfs, n_days,
  #'   n_events, r_log, loc_slope, loc_intercept, index_q_min
  fractions %>%
    map_dfr(function(frac) {
      characterize_transfer_at_threshold(concurrent, frac * q2_target_cfs) %>%
        mutate(fraction = frac, .before = 1)
    }) %>%
    arrange(desc(fraction))
}


# =============================================================================
# 5. MOVE.1 TRANSFER FIT   (smwrStats — TO IMPLEMENT after reading move.1 docs)
# =============================================================================

fit_move1_transfer <- function(concurrent, screening_threshold_cfs) {
  #' Fit the variance-preserving MOVE.1 transfer Gibbon -> Pendleton.
  #'
  #' Fit on high-flow days only (index or target above the screening threshold
  #' chosen in Section 4), in log10 space, via smwrStats::move.1. The LOC slope
  #' preserves the marginal variance of the reconstructed series.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param screening_threshold_cfs the data-chosen high-flow floor (cfs)
  #' @return a fitted move.1 object (transfer equation + variance structure)
  #'
  #' TODO: read ?smwrStats::move.1 first — resolve whether log10 goes in the
  #' formula OR distribution="commonlog", not both (lingua.md Sec 1).
  stop("not implemented — pending move.1 documentation review")
}

jackknife_move1_transfer <- function(concurrent, screening_threshold_cfs) {
  #' Leave-one-out jackknife of the MOVE.1 transfer for a prediction RMSE.
  #'
  #' The RMSE feeds (a) the reconstruction uncertainty and (b) inverse-variance
  #' weighting if the second index is ever activated. Note: on daily data this
  #' RMSE is optimistic because days are serially correlated — treat n_events,
  #' not n_days, as the effective sample size when interpreting it.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param screening_threshold_cfs the data-chosen high-flow floor (cfs)
  #' @return list: rmse_log and the jackknife object
  stop("not implemented — pending move.1 documentation review")
}


# =============================================================================
# 6. BACKWARD PREDICTION  (TO IMPLEMENT)
# =============================================================================

predict_pendleton_daily <- function(move1_fit, index_daily, screening_threshold_cfs,
                                     extension_start) {
  #' Reconstruct pre-observation Pendleton daily flow from Gibbon.
  #'
  #' Apply the fitted transfer to index (Gibbon) days from `extension_start`
  #' up to the observed record, but only on days where Gibbon exceeds the
  #' screening threshold (translated to the Gibbon scale). Days below are left
  #' unreconstructed — they contribute nothing to any high-flow metric.
  #'
  #' @param move1_fit fitted transfer from fit_move1_transfer
  #' @param index_daily Gibbon daily series
  #' @param screening_threshold_cfs high-flow floor (cfs)
  #' @param extension_start earliest date to reconstruct (Date or string)
  #' @return tibble: date, pendleton_est_cfs, source = "estimated_gibbon"
  stop("not implemented")
}

assemble_extended_daily_record <- function(target_daily, predicted, jackknife) {
  #' Splice observed and reconstructed Pendleton daily into one tidy record.
  #'
  #' Observed days (post-1995) carry source = "observed"; reconstructed days
  #' carry source = "estimated_gibbon" and the jackknife-based uncertainty.
  #' The observed/estimated flag is the honest boundary for all downstream use.
  #'
  #' @param target_daily observed Pendleton daily
  #' @param predicted reconstructed daily from predict_pendleton_daily
  #' @param jackknife uncertainty from jackknife_move1_transfer
  #' @return tibble: date, daily_q_cfs, source, is_estimated, uncertainty_log
  stop("not implemented")
}


# =============================================================================
# 7. ANNUAL-METRIC MOVE.3 CROSS-CHECK  (diagnostic Step 4 — TO IMPLEMENT)
# =============================================================================

crosscheck_annual_metric_move3 <- function(concurrent, extended_record) {
  #' Independent validation: extend an annual high-flow metric via MOVE.3 and
  #' compare against the same metric derived from the daily reconstruction.
  #'
  #' MOVE.3 on a near-iid annual series (e.g., annual days above Q2) sidesteps
  #' the daily serial-correlation problem, so agreement is convergence of
  #' evidence and disagreement flags where the daily extension strains. This is
  #' the empirical answer to the "naive daily MOVE.1" objection.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param extended_record output of assemble_extended_daily_record
  #' @return tibble comparing daily-derived vs MOVE.3-extended annual metrics
  stop("not implemented")
}


# =============================================================================
# 8. WRITE OUTPUTS  (TO IMPLEMENT)
# =============================================================================

write_extension_outputs <- function(extended_record, output_rds) {
  #' Persist the extended daily record as .rds at the project boundary.
  #'
  #' @param extended_record output of assemble_extended_daily_record
  #' @param output_rds destination path
  #' @return invisibly, extended_record
  stop("not implemented")
}


# =============================================================================
# 9. ORCHESTRATORS
# =============================================================================

run_extension_diagnostics <- function(config) {
  #' Run the implemented diagnostic half: load -> concurrent join -> high-flow
  #' characterization -> threshold-sensitivity ladder. Runnable now; its purpose
  #' is to set the screening floor before any MOVE.1 fitting.
  #'
  #' @param config the config tribble
  #' @return named list: inputs, concurrent, threshold_scan
  message("Loading daily records ...")
  inputs <- load_daily_extension_inputs(config)

  message("Building concurrent daily record ...")
  concurrent <- build_concurrent_daily(inputs$target_daily, inputs$index_daily)

  message("Scanning threshold sensitivity ...")
  threshold_scan <- scan_threshold_sensitivity(
    concurrent, cfg_num("q2_target_cfs"), THRESHOLD_FRACTIONS
  )
  print(threshold_scan)

  list(inputs = inputs, concurrent = concurrent, threshold_scan = threshold_scan)
}

run_daily_extension <- function(config, screening_threshold_cfs) {
  #' Full narrative orchestrator (end-state). Fit the transfer on high-flow days,
  #' jackknife it, reconstruct pre-1996 Pendleton, splice with the observed
  #' record, cross-check against MOVE.3, and write the extended record.
  #'
  #' Not runnable end-to-end until Sections 5-8 are implemented; the screening
  #' threshold is supplied from the Section 4 diagnostic review.
  #'
  #' @param config the config tribble
  #' @param screening_threshold_cfs floor chosen from run_extension_diagnostics
  #' @return invisibly, the extended record
  inputs     <- load_daily_extension_inputs(config)
  concurrent <- build_concurrent_daily(inputs$target_daily, inputs$index_daily)

  move1_fit  <- fit_move1_transfer(concurrent, screening_threshold_cfs)
  jackknife  <- jackknife_move1_transfer(concurrent, screening_threshold_cfs)

  predicted  <- predict_pendleton_daily(
    move1_fit, inputs$index_daily, screening_threshold_cfs, cfg("extension_start")
  )
  extended   <- assemble_extended_daily_record(inputs$target_daily, predicted, jackknife)

  crosscheck_annual_metric_move3(concurrent, extended)
  write_extension_outputs(extended, cfg("extended_record_rds"))

  invisible(extended)
}


# =============================================================================
# 10. INTERACTIVE STEPWISE RUN
# =============================================================================
##
## Diagnostic half is runnable now. Single-hash lines are executable; double-hash
## is narration (Ctrl+Shift+C strips one hash — code goes live, ## stays a
## comment). Work through these before implementing the MOVE.1 fit.
##
## ---- Step 1: load and join the concurrent record ----
#
# inputs <- load_daily_extension_inputs(config)
# concurrent <- build_concurrent_daily(inputs$target_daily, inputs$index_daily)
##
## ---- Step 2: threshold-sensitivity ladder (this sets the screening floor) ----
#
# threshold_scan <- scan_threshold_sensitivity(
#   concurrent, cfg_num("q2_target_cfs"), THRESHOLD_FRACTIONS
# )
# threshold_scan
##
## ---- Step 3: residual/seasonality check at a candidate threshold ----
##            (rerun at a few fractions; look for month structure or fanning)
#
# describe_transfer_residuals(concurrent, 0.5 * cfg_num("q2_target_cfs"))
##
## ---- Or run the whole diagnostic half at once ----
#
# diag <- run_extension_diagnostics(config)
