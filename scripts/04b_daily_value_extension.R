# =============================================================================
# 04b_daily_value_extension.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 4b: Daily Mean Discharge Record Extension for USGS 14020850 (Pendleton)
# =============================================================================
#
# Purpose: Extend the Pendleton daily mean discharge record backward from its
#          observed start (~1995-10) to 1952, so high-flow forcing metrics
#          (days above Q2, cumulative excess volume, event count, max duration)
#          can be computed per HMA photo interval over the full analysis window.
#          Only the high-flow tail matters; this is not a general hydrograph
#          reconstruction.
#
# Method: Variance-preserving record extension from Gibbon (14020000) ->
#         Pendleton (14020850), fit on high-flow days.
#         SELECTED: MOVE.1 (commonlog LOC; smwrStats::move.1), fit band 0.75 x Q2.
#         Although the diagnostics showed the log10 transfer is significantly
#         nonlinear (quadratic term p = 3e-4), MOVE.2 + optimBoxCox was TESTED and
#         REJECTED by event-blocked CV — 3-4x worse RMSE, large bias, numerically
#         unstable. The curvature is real but practically second order; MOVE.1
#         generalizes better out of sample (Hirsch 1982). A common-test-set band
#         comparison further showed that adding moderate-flow data biases the
#         >= Q2 predictions (bias +112 cfs at Q2-only to -960 cfs at 0.25 x Q2),
#         so the fit band is kept high at 0.75 x Q2 (30 events; ~1,090 cfs Gibbon
#         reconstruction floor). The MOVE.2 fit + both comparisons are retained in
#         Sections 5-6 as the record. See 01e for the curvature diagnostics.
#
# API notes (verified against installed smwrStats docs, lingua.md Sec 1):
#   - move.1 / move.2 take RAW variables in the formula; the transform is chosen
#     by `distribution`. distribution="commonlog" applies log10 to BOTH sides
#     internally, so DO NOT log the variables in the formula (that double-logs).
#   - Box-Cox: optimBoxCox(<data frame of both columns>) -> object passed as
#     move.2(..., distribution = bc). predict(..., type="response") back-transforms.
#   - predict.move.1 has var.fit=TRUE (built-in prediction variance); predict.move.2
#     does NOT — if MOVE.2 is adopted, reconstruction uncertainty comes from
#     event-blocked resampling, not from the model object.
#   - Cross-validation and any resampling are blocked BY EVENT, not by day:
#     daily high flows are serially correlated, so the event is the unit of
#     independent information (n_events << n_days).
#
# Key design decisions (session 2026-09-03; see project record):
#   - GIBBON-ONLY start with a validation gate; downstream Umatilla (14033500)
#     as a second index held in reserve (needs a daily McKay correction).
#   - TWO INDEPENDENT THRESHOLDS: screening/reconstruction threshold is
#     STATISTICAL (how low we can transfer reliably; the diagnostics showed the
#     relationship stays clean with strong correlation down past 0.25 x Q2, so
#     the floor is set for sample size, targeting the bankfull band); the metric
#     threshold is GEOMORPHIC (Q2 ~5,542 cfs), applied downstream.
#   - Days below the screening threshold are not reconstructed — they contribute
#     zero to every high-flow metric.
#
# Inputs (from 04a):
#   data/dv_gage_daily_flows.csv   — daily mean Q, all three gages
#
# Outputs:
#   data/pendleton_daily_extended.rds  — extended daily flows at 14020850,
#     1952-present, with observed/estimated flag, source, prediction, uncertainty.
#     (Written once the modeling sections are completed.)
#
# Relationship to other scripts:
#   - 01e_daily_extension.R — the MOVE.1 exploration record this supersedes.
#     Its diagnostic Sections 1-4 are method-agnostic and are carried here.
#   - 04a_Dv_daily_gage_acquisition.R — supplies the daily records.
#
# Status: 2026-09-03. Method + band SELECTED (MOVE.1, 0.75 x Q2 — see Method).
#   Sections 1-7 and 9 implemented and runnable: diagnostics, fits, method and
#   band comparisons, backward reconstruction, record assembly, and the .rds
#   writer. run_daily_extension(config) produces the extended record. Section 8
#   (MOVE.3 annual-metric cross-check) remains a contracted stub — the last
#   validation step, run after the record and interval metrics exist.
#
# Style: lingua.md (boundary contracts, small pure functions, I/O at the
#   orchestrator boundary) and the Tidyverse & Functional Programming Guidelines.
# =============================================================================

library(tidyverse)
library(smwrStats)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

config <- tribble(
  ~parameter,             ~value,
  "target_gage_id",       "14020850",   # Pendleton (target of the extension)
  "index_gage_id",        "14020000",   # Gibbon (primary index, unregulated)
  "secondary_index_id",   "14033500",   # Umatilla (reserved; two-index fallback)
  "q2_target_cfs",        "5542",       # Pendleton Q2, post-McKay-correction B17C
  "extension_start",      "1952-01-01", # earliest HMA photo year
  "daily_flows_csv",      "data/dv_gage_daily_flows.csv",
  "extended_record_rds",  "data/pendleton_daily_extended.rds"
)

# Fractions of Q2 scanned by the threshold-sensitivity ladder (Section 4).
THRESHOLD_FRACTIONS <- c(1.00, 0.75, 0.50, 0.35, 0.25)

cfg <- function(param) config %>% filter(parameter == param) %>% pull(value)
cfg_num <- function(param) as.numeric(cfg(param))


# =============================================================================
# 2. DATA LOADING
# =============================================================================

add_water_year <- function(daily, date_col = "date") {
  #' Attach USGS water year and month to a daily record.
  #' Water year T runs Oct 1 (T-1) through Sep 30 (T).
  #' @param daily tibble with a Date column; @param date_col its name
  #' @return `daily` with integer water_year and month added
  d <- daily[[date_col]]
  daily %>%
    mutate(
      month = as.integer(format(d, "%m")),
      water_year = as.integer(format(d, "%Y")) + if_else(month >= 10L, 1L, 0L)
    )
}

load_daily_extension_inputs <- function(config) {
  #' Load daily mean discharge for the target and primary index gages.
  #' Positive, non-missing discharge only (the transfer is fit in log space).
  #' @param config config tribble (gage ids, path)
  #' @return list: target_daily, index_daily (gage_id, date, daily_q_cfs, wy, month)
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
  #' Inner-join target and index on shared dates (the concurrent calibration set).
  #' @param target_daily,index_daily tibbles (date, daily_q_cfs, ...)
  #' @return tibble: date, water_year, month, target_q, index_q
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

assign_flow_events <- function(dates, max_gap_days = 1L) {
  #' Assign an event id to each high-flow day; consecutive (or near-consecutive)
  #' days share an event. The event is the unit of independent information under
  #' serial correlation — used both for effective-sample counts and to block the
  #' cross-validation in Section 6.
  #' @param dates Date vector (any order); @param max_gap_days gaps up to this
  #'   many days stay within one event
  #' @return integer event id per element, aligned to the input order
  if (length(dates) == 0L) return(integer(0))
  ord <- order(dates)
  d <- dates[ord]
  new_event <- c(TRUE, as.integer(diff(d)) > max_gap_days)
  ev_sorted <- cumsum(new_event)
  ev <- integer(length(dates))
  ev[ord] <- ev_sorted
  ev
}

count_high_flow_events <- function(dates, max_gap_days = 1L) {
  #' Count independent high-flow events among flagged high-flow days.
  #' @param dates Date vector of high-flow days; @param max_gap_days event gap
  #' @return integer event count
  if (length(dates) == 0L) return(0L)
  length(unique(assign_flow_events(dates, max_gap_days)))
}

characterize_transfer_at_threshold <- function(concurrent, target_threshold_cfs) {
  #' Summarize the log-space Gibbon->Pendleton transfer for high-flow days.
  #' The Line-of-Organic-Correlation slope IS the MOVE.1 slope; computing it
  #' directly previews the transfer. NOTE: over a restricted (high-only) range
  #' this LOC slope is a confounded curvature measure — use the quadratic test in
  #' the interactive section for curvature, not these slope values.
  #' @param concurrent tibble from build_concurrent_daily
  #' @param target_threshold_cfs high-flow cutoff on the target series (cfs)
  #' @return one-row tibble: threshold_cfs, n_days, n_events, r_log, loc_slope,
  #'   loc_intercept, index_q_min
  hi <- concurrent %>% filter(target_q >= target_threshold_cfs)
  lx <- log10(hi$index_q); ly <- log10(hi$target_q)
  r  <- if (nrow(hi) > 2) cor(lx, ly) else NA_real_
  loc_slope <- if (nrow(hi) > 2) sign(r) * sd(ly) / sd(lx) else NA_real_
  loc_intercept <- if (nrow(hi) > 2) mean(ly) - loc_slope * mean(lx) else NA_real_
  tibble(
    threshold_cfs = target_threshold_cfs,
    n_days = nrow(hi), n_events = count_high_flow_events(hi$date),
    r_log = r, loc_slope = loc_slope, loc_intercept = loc_intercept,
    index_q_min = if (nrow(hi) > 0) min(hi$index_q) else NA_real_
  )
}

describe_transfer_residuals <- function(concurrent, target_threshold_cfs) {
  #' Per-month residual diagnostics about the LOC line, to catch seasonal regime
  #' mixing or high-end heteroscedasticity that would break a single fit.
  #' @param concurrent tibble from build_concurrent_daily
  #' @param target_threshold_cfs high-flow cutoff on the target series (cfs)
  #' @return tibble by month: n_days, resid_mean, resid_sd (log10 units)
  fit <- characterize_transfer_at_threshold(concurrent, target_threshold_cfs)
  concurrent %>%
    filter(target_q >= target_threshold_cfs) %>%
    mutate(resid_log = log10(target_q) -
             (fit$loc_intercept + fit$loc_slope * log10(index_q))) %>%
    group_by(month) %>%
    summarise(n_days = n(), resid_mean = mean(resid_log),
              resid_sd = sd(resid_log), .groups = "drop") %>%
    arrange(month)
}


# =============================================================================
# 4. THRESHOLD-SENSITIVITY LADDER  (diagnostic Step 2 — sets the screening floor)
# =============================================================================

scan_threshold_sensitivity <- function(concurrent, q2_target_cfs, fractions) {
  #' Scan the transfer across a ladder of high-flow thresholds. Stable
  #' correlation and residual spread as the threshold drops mean the regime stays
  #' clean and lowering is free data; drift signals low-flow leak-in.
  #' @param concurrent tibble from build_concurrent_daily
  #' @param q2_target_cfs Pendleton Q2 (cfs); @param fractions Q2 fractions
  #' @return tibble, one row per threshold (see characterize_transfer_at_threshold)
  fractions %>%
    map_dfr(~ characterize_transfer_at_threshold(concurrent, .x * q2_target_cfs) %>%
              mutate(fraction = .x, .before = 1)) %>%
    arrange(desc(fraction))
}


# =============================================================================
# 5. TRANSFER FITS: MOVE.2 (primary) and MOVE.1 (comparator)
# =============================================================================

fit_move1_transfer <- function(concurrent, screening_threshold_cfs) {
  #' Fit the log-linear MOVE.1 comparator, Gibbon -> Pendleton, on high-flow days.
  #' Raw variables in the formula; distribution="commonlog" applies log10 to both
  #' internally (verified: NOT logged in the formula).
  #' @param concurrent tibble from build_concurrent_daily
  #' @param screening_threshold_cfs high-flow floor on the target series (cfs)
  #' @return a fitted move.1 object
  hi <- filter(concurrent, target_q >= screening_threshold_cfs)
  move.1(target_q ~ index_q, data = hi, distribution = "commonlog")
}

fit_move2_boxcox_transfer <- function(concurrent, screening_threshold_cfs) {
  #' Fit the MOVE.2 primary with an optimized Box-Cox transform on high-flow days.
  #' optimBoxCox jointly transforms BOTH variables toward bivariate normality,
  #' straightening the log-log curvature the diagnostics found; move.2 then fits
  #' the LOC in the transformed space and predict() back-transforms.
  #' @param concurrent tibble from build_concurrent_daily
  #' @param screening_threshold_cfs high-flow floor on the target series (cfs)
  #' @return list: fit (move.2 object), boxcox (optimBoxCox object)
  hi <- filter(concurrent, target_q >= screening_threshold_cfs)
  bc <- optimBoxCox(as.data.frame(hi[, c("target_q", "index_q")]))
  fit <- move.2(target_q ~ index_q, data = hi, distribution = bc)
  list(fit = fit, boxcox = bc)
}


# =============================================================================
# 6. EVENT-BLOCKED METHOD COMPARISON  (does MOVE.2 earn its extra flexibility?)
# =============================================================================

compare_transfer_methods_cv <- function(concurrent, screening_threshold_cfs,
                                         max_gap_days = 1L) {
  #' Leave-one-event-out cross-validation of MOVE.1 vs MOVE.2 on high-flow days.
  #'
  #' Blocks by EVENT, not day: each held-out event is predicted from a model fit
  #' on all other events, so serial correlation does not leak train into test.
  #' The winner is the method with lower out-of-sample error; MOVE.2 must beat
  #' MOVE.1 to justify the Box-Cox parameters.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param screening_threshold_cfs high-flow floor on the target series (cfs)
  #' @param max_gap_days event-blocking gap (days)
  #' @return list: summary (one row per method: cv_rmse_cfs, cv_rmse_log,
  #'   cv_bias_cfs, full_R) and predictions (per held-out day, both methods)
  hi <- concurrent %>%
    filter(target_q >= screening_threshold_cfs) %>%
    arrange(date) %>%
    mutate(event_id = assign_flow_events(date, max_gap_days))

  events <- unique(hi$event_id)
  message("  CV on ", nrow(hi), " days / ", length(events), " events ...")

  preds <- map_dfr(events, function(ev) {
    train <- filter(hi, event_id != ev)
    test  <- filter(hi, event_id == ev)
    m1 <- move.1(target_q ~ index_q, data = train, distribution = "commonlog")
    bc <- optimBoxCox(as.data.frame(train[, c("target_q", "index_q")]))
    m2 <- move.2(target_q ~ index_q, data = train, distribution = bc)
    nd <- data.frame(index_q = test$index_q)
    tibble(
      date = test$date, obs = test$target_q,
      pred_move1 = as.numeric(predict(m1, newdata = nd, type = "response")),
      pred_move2 = as.numeric(predict(m2, newdata = nd, type = "response"))
    )
  })

  rmse     <- function(o, p) sqrt(mean((o - p)^2, na.rm = TRUE))
  rmse_log <- function(o, p) sqrt(mean((log10(o) - log10(p))^2, na.rm = TRUE))
  bias     <- function(o, p) mean(p - o, na.rm = TRUE)

  full1 <- fit_move1_transfer(concurrent, screening_threshold_cfs)
  full2 <- fit_move2_boxcox_transfer(concurrent, screening_threshold_cfs)$fit

  summary <- tibble(
    method      = c("move1_commonlog", "move2_boxcox"),
    cv_rmse_cfs = c(rmse(preds$obs, preds$pred_move1),
                    rmse(preds$obs, preds$pred_move2)),
    cv_rmse_log = c(rmse_log(preds$obs, preds$pred_move1),
                    rmse_log(preds$obs, preds$pred_move2)),
    cv_bias_cfs = c(bias(preds$obs, preds$pred_move1),
                    bias(preds$obs, preds$pred_move2)),
    full_R      = c(full1$R, full2$R),
    n_days      = nrow(hi),
    n_events    = length(events)
  )
  print(summary)
  list(summary = summary, predictions = preds)
}


compare_fit_bands_common_test <- function(concurrent, q2_target_cfs, fractions,
                                          test_fraction = 1.0, max_gap_days = 1L) {
  #' Compare candidate MOVE.1 fit bands on a COMMON high-flow test set.
  #'
  #' Every candidate band trains MOVE.1 on days >= fraction*Q2, but ALL bands are
  #' scored on the same test days (>= test_fraction*Q2, default Q2). The test set
  #' and its events are defined once; for each test event the whole event window
  #' (+/- max_gap_days) is excluded from every band's training data, so the
  #' holdout is clean and the target flows are held fixed while only the training
  #' support changes. This answers "which fit band best predicts the >= Q2 flows
  #' we reconstruct" — the per-band CV cannot, because it scores each band on its
  #' own range.
  #'
  #' @param concurrent tibble from build_concurrent_daily
  #' @param q2_target_cfs Pendleton Q2 (cfs)
  #' @param fractions candidate training-band fractions of Q2
  #' @param test_fraction common test set = days >= this * Q2 (default 1.0 = Q2)
  #' @param max_gap_days event-blocking gap (days)
  #' @return tibble by band: fraction, train_events, test_days, rmse_cfs,
  #'   rmse_log, bias_cfs (all on the common >= test_fraction*Q2 test set)
  test_cut <- test_fraction * q2_target_cfs
  test_days <- concurrent %>%
    filter(target_q >= test_cut) %>%
    arrange(date) %>%
    mutate(event_id = assign_flow_events(date, max_gap_days))
  test_events <- test_days %>%
    group_by(event_id) %>%
    summarise(d1 = min(date), d2 = max(date), .groups = "drop")

  map_dfr(fractions, function(frac) {
    band <- filter(concurrent, target_q >= frac * q2_target_cfs)
    preds <- map_dfr(seq_len(nrow(test_events)), function(i) {
      d1 <- test_events$d1[i]; d2 <- test_events$d2[i]
      # hold out the whole event window from this band's training data
      train <- filter(band, date < d1 - max_gap_days | date > d2 + max_gap_days)
      test  <- filter(test_days, event_id == test_events$event_id[i])
      m1 <- move.1(target_q ~ index_q, data = train, distribution = "commonlog")
      tibble(
        obs  = test$target_q,
        pred = as.numeric(predict(m1, newdata = data.frame(index_q = test$index_q),
                                  type = "response"))
      )
    })
    tibble(
      fraction     = frac,
      train_events = count_high_flow_events(band$date, max_gap_days),
      test_days    = nrow(test_days),
      rmse_cfs     = sqrt(mean((preds$obs - preds$pred)^2, na.rm = TRUE)),
      rmse_log     = sqrt(mean((log10(preds$obs) - log10(preds$pred))^2, na.rm = TRUE)),
      bias_cfs     = mean(preds$pred - preds$obs, na.rm = TRUE)
    )
  }) %>%
    arrange(desc(fraction))
}


# =============================================================================
# 7. BACKWARD PREDICTION  (TO IMPLEMENT after method + band chosen)
# =============================================================================

predict_pendleton_daily <- function(fit, index_daily, gibbon_floor_cfs,
                                    extension_start, observed_start) {
  #' Reconstruct pre-observation Pendleton daily flow from Gibbon.
  #'
  #' Applies the fitted MOVE.1 transfer to Gibbon days from extension_start up to
  #' the start of the observed record, only where Gibbon >= gibbon_floor_cfs (the
  #' fit band's lower support edge) so the transfer is interpolated within its
  #' calibrated Gibbon range, never extrapolated below it. Days below the floor
  #' are left unreconstructed — they fall below the geomorphic-relevance
  #' threshold and contribute nothing to the high-flow metrics.
  #'
  #' @param fit fitted move.1 object (target_q ~ index_q)
  #' @param index_daily Gibbon daily (date, daily_q_cfs)
  #' @param gibbon_floor_cfs Gibbon screening floor (cfs)
  #' @param extension_start earliest date to reconstruct (Date or string)
  #' @param observed_start first date of the observed target record (exclusive upper bound)
  #' @return tibble: date, pendleton_est_cfs, est_var, source
  ext <- index_daily %>%
    filter(date >= as.Date(extension_start), date < as.Date(observed_start),
           daily_q_cfs >= gibbon_floor_cfs) %>%
    arrange(date)

  # var.fit gives the MOVE.1 prediction variance (verify its scale on first run).
  pr <- predict(fit, newdata = data.frame(index_q = ext$daily_q_cfs),
                type = "response", var.fit = TRUE)

  tibble(
    date = ext$date,
    pendleton_est_cfs = pr$fit,
    est_var = pr$var.fit,
    source = "estimated_gibbon_move1"
  )
}

assemble_extended_daily_record <- function(target_daily, predicted) {
  #' Splice observed and reconstructed Pendleton daily into one tidy record.
  #'
  #' Observed days (post-1995) carry source="observed"; reconstructed days carry
  #' the MOVE.1 source and prediction sd. The is_estimated flag is the honest
  #' boundary for all downstream use. Estimated dates all precede the observed
  #' record, so there is no overlap to reconcile.
  #'
  #' @param target_daily observed Pendleton daily (date, daily_q_cfs)
  #' @param predicted tibble from predict_pendleton_daily
  #' @return tibble: date, daily_q_cfs, source, is_estimated, est_sd (date-sorted)
  observed <- target_daily %>%
    transmute(date, daily_q_cfs, source = "observed",
              is_estimated = FALSE, est_sd = NA_real_)
  estimated <- predicted %>%
    transmute(date, daily_q_cfs = pendleton_est_cfs, source,
              is_estimated = TRUE, est_sd = sqrt(est_var))
  bind_rows(estimated, observed) %>% arrange(date)
}


# =============================================================================
# 8. ANNUAL-METRIC MOVE.3 CROSS-CHECK  (TO IMPLEMENT)
# =============================================================================

crosscheck_annual_metric_move3 <- function(concurrent, extended_record) {
  #' Validate the daily reconstruction against an independent MOVE.3 extension of
  #' an annual high-flow metric (near-iid, so it sidesteps daily serial
  #' correlation). Agreement is convergence of evidence.
  #' @return tibble comparing daily-derived vs MOVE.3-extended annual metrics
  stop("not implemented")
}


# =============================================================================
# 9. WRITE OUTPUTS  (TO IMPLEMENT)
# =============================================================================

write_extension_outputs <- function(extended_record, output_rds) {
  #' Persist the extended daily record as .rds at the project boundary.
  #' @param extended_record output of assemble_extended_daily_record
  #' @param output_rds destination path
  #' @return invisibly, extended_record
  saveRDS(extended_record, output_rds)
  message("  Wrote ", nrow(extended_record), " daily rows to ", output_rds)
  invisible(extended_record)
}


# =============================================================================
# 10. ORCHESTRATORS
# =============================================================================

run_extension_diagnostics <- function(config) {
  #' Runnable now: load -> concurrent join -> threshold-sensitivity ladder.
  #' Sets the screening floor before any fitting.
  #' @return list: inputs, concurrent, threshold_scan
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

run_method_comparison <- function(config, screening_fraction = 0.5) {
  #' Runnable now: fit MOVE.1 and MOVE.2 at a candidate screening threshold and
  #' event-blocked-cross-validate them. Decides which method the reconstruction
  #' uses. Rerun at a few fractions to check the choice is stable.
  #' @param config config tribble
  #' @param screening_fraction fraction of Q2 for the fit band
  #' @return the compare_transfer_methods_cv result
  inputs <- load_daily_extension_inputs(config)
  concurrent <- build_concurrent_daily(inputs$target_daily, inputs$index_daily)
  compare_transfer_methods_cv(
    concurrent, screening_fraction * cfg_num("q2_target_cfs")
  )
}

run_daily_extension <- function(config, method = "move1_commonlog",
                                screening_fraction = 0.75) {
  #' Full narrative orchestrator: fit the selected transfer on the high-flow
  #' band, reconstruct pre-1996 Pendleton from Gibbon, splice with the observed
  #' record, and write the extended .rds. The MOVE.3 annual-metric cross-check
  #' (Section 8) is run separately once interval metrics exist.
  #'
  #' Defaults encode the selected method and band (MOVE.1, 0.75 x Q2). The
  #' reconstruction screens Gibbon at the fit band's lower support edge, so the
  #' transfer is only ever interpolated within its calibrated range.
  #'
  #' @param config config tribble
  #' @param method "move1_commonlog" (selected) or "move2_boxcox"
  #' @param screening_fraction fraction of Q2 defining the fit band
  #' @return invisibly, the extended daily record
  inputs <- load_daily_extension_inputs(config)
  concurrent <- build_concurrent_daily(inputs$target_daily, inputs$index_daily)

  band_cut <- screening_fraction * cfg_num("q2_target_cfs")
  gibbon_floor <- min(filter(concurrent, target_q >= band_cut)$index_q)
  observed_start <- min(inputs$target_daily$date)
  message("  Fit band: target_q >= ", round(band_cut), " cfs; Gibbon floor: ",
          round(gibbon_floor), " cfs")

  fit <- if (method == "move2_boxcox") {
    fit_move2_boxcox_transfer(concurrent, band_cut)$fit
  } else {
    fit_move1_transfer(concurrent, band_cut)
  }

  predicted <- predict_pendleton_daily(fit, inputs$index_daily, gibbon_floor,
                                       cfg("extension_start"), observed_start)
  extended <- assemble_extended_daily_record(inputs$target_daily, predicted)
  write_extension_outputs(extended, cfg("extended_record_rds"))
  message("  Reconstructed ", sum(extended$is_estimated), " estimated days (",
          format(min(predicted$date)), " to ", format(max(predicted$date)),
          "), retained ", sum(!extended$is_estimated), " observed days.")
  invisible(extended)
}


# =============================================================================
# 11. INTERACTIVE STEPWISE RUN
# =============================================================================
##
## Single-hash lines are executable; double-hash is narration (Ctrl+Shift+C
## strips one hash — code goes live, ## stays a comment).
##
## ---- Step 1: diagnostics — set the screening floor ----
#
# diag <- run_extension_diagnostics(config)
##
## ---- Step 2: confirm curvature directly (unconfounded by restricted range) ----
#
# hi <- subset(diag$concurrent, target_q >= 0.5 * cfg_num("q2_target_cfs"))
# summary(lm(log10(target_q) ~ log10(index_q) + I(log10(index_q)^2), data = hi))
##
## ---- Step 3: does MOVE.2 beat MOVE.1? (event-blocked CV at a few bands) ----
#
# cmp_050 <- run_method_comparison(config, screening_fraction = 0.50)
# cmp_035 <- run_method_comparison(config, screening_fraction = 0.35)
# cmp_075 <- run_method_comparison(config, screening_fraction = 0.75)
##
## OUTCOME: MOVE.1 beat MOVE.2 (Box-Cox unstable, 3-4x worse CV RMSE, biased).
##
## ---- Step 4: band selection on a COMMON >= Q2 test set ----
##            (showed high bands predict the >= Q2 flows best; adding moderate
##             data biases them low. Selected: MOVE.1, 0.75 x Q2.)
#
# compare_fit_bands_common_test(diag$concurrent, cfg_num("q2_target_cfs"),
#                               c(1.0, 0.75, 0.5, 0.35, 0.25))
##
## ---- Step 5: build the extended daily record (MOVE.1, 0.75 x Q2 defaults) ----
#
# ext <- run_daily_extension(config)
# dplyr::count(ext, source, is_estimated)
# subset(ext, is_estimated) |> (\(d) c(n = nrow(d), max_cfs = max(d$daily_q_cfs)))()
