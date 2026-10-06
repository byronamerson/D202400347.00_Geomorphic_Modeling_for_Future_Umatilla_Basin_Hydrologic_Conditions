# =============================================================================
# 04d_forcing_model_validation.R Umatilla River Discharge-Channel Migration
# Analysis Phase 4d: Validation of the cumulative-excess forcing model
# =============================================================================
#
# Purpose: Join the per-interval forcing metrics (04c) to the migration response
# (rs30_interval_sandbox) and run the battery of tests that established
# cumulative excess above Q2 as the primary forcing variable: model comparison,
# single-flood leverage, full leave-one-out robustness, a permutation test, and
# a reconstruction extrapolation check.
#
# This is a VALIDATION / DIAGNOSTIC script, not a function library. It runs
# top-to-bottom and prints results for inspection. Each section says what the
# test checks and the result obtained on 2026-09-03 (n = 14 intervals, RS 30),
# so a later reader (or a re-run) can tell at a glance whether things still
# agree. Comments are intent + expected-result, not formal function contracts.
#
# Depends on (RUN ORDER MATTERS — see Section 0):
# scripts/rs30_interval_sandbox.R          -> rs30_plot_data (response + peak)
# scripts/04c_interval_forcing_metrics.R   -> forcing metrics (+ its own
# `config`) data/pendleton_daily_extended.rds  (04b) -> the reconstructed daily
# record data/dv_gage_daily_flows.csv       (04a) -> Gibbon daily, for the
# extrap check
# =============================================================================

library(tidyverse)
library(broom)


# ---- 0. Assemble the modeling table -----------------------------------------
# SOURCE ORDER MATTERS: rs30_interval_sandbox.R and 04c BOTH define an object
# called `config`. Source the sandbox first (it builds rs30_plot_data with its
# own config at source time), capture what we need, THEN source 04c so its
# forcing `config` is the one active when we call run_interval_forcing_metrics().

source("scripts/rs30_interval_sandbox.R")   # builds rs30_plot_data (response + interval-max peak)
intervals <- dplyr::distinct(rs30_plot_data, year_t1, year_t2)
migration <- rs30_plot_data

source("scripts/04c_interval_forcing_metrics.R")   # forcing `config` now active
forcing <- run_interval_forcing_metrics(config, intervals)
forcing

# One row per HMA interval: migration response + forcing predictors side by side.
dat <- dplyr::left_join(migration, forcing, by = c("year_t1", "year_t2"))


# ---- 1. Model comparison: which forcing variable predicts expansion? --------
# All fits are Delta-t^2 weighted (annualized rates from short intervals are
# noisy; the weight down-weights them — see 04c and the annualization argument).
# Response is net area change (corridor expansion) per year.
#
# CHECKS: does integrated flow (magnitude x duration above Q2) beat (a) a plain
# day-count and (b) peak magnitude alone, on the SAME weighted n = 14 sample?
# EXPECTED (2026-09-03): cum_excess_thresh_cfs_days -> R2 ~ 0.39, p ~ 0.017   BEST;
# slope positive days_above_thresh          -> R2 ~ 0.02, p ~ 0.65    useless (a
# count throws away magnitude) q_peak_max_cfs         -> R2 ~ 0.22, p ~ 0.088
# weaker than cum_excess
summary(
  lm(
    net_area_change_ft2_per_year ~ cum_excess_thresh_cfs_days,
    data = dat,
    weights = interval_years^2
  )
)
summary(
  lm(
    net_area_change_ft2_per_year ~ days_above_thresh,
    data = dat,
    weights = interval_years^2
  )
)
summary(
  lm(
    net_area_change_ft2_per_year ~ q_peak_max_cfs,
    data = dat,
    weights = interval_years^2
  )
)


# ---- 2. Single-flood leverage: drop the 2020 flood of record ----------------
# In x01 the PEAK relationship rested entirely on the 2017-2020 interval (Feb
# 2020, the flood of record): removing it took peak to p ~ 0.15
# (non-significant).
#
# CHECKS: does cum_excess still hold once that one interval is removed?
# EXPECTED: cum_excess SURVIVES -> R2 ~ 0.33, p ~ 0.041. The signal is not
# hostage to a single flood (unlike peak).
summary(
  lm(
    net_area_change_ft2_per_year ~ cum_excess_thresh_cfs_days,
    data = subset(dat, !(year_t1 == 2017 & year_t2 == 2020)),
    weights = interval_years^2
  )
)


# ---- 3. Full leave-one-out: is ANY single interval load-bearing? ------------
# Refit dropping each interval in turn; the worst-case (maximum) p-value is the
# test statistic. Pre-set decision rule (from x01): if the max p across all
# single drops exceeds 0.10 the relationship is only "suggestive"; if it stays
# below 0.10 it "holds".
#
# CHECKS: robustness of cum_excess vs peak to removal of any one interval.
# EXPECTED: cum_excess_maxp ~ 0.064  (< 0.10 -> HOLDS across all drops)
# peak_maxp       ~ 0.44   (fails the rule) Most load-bearing drop for
# cum_excess = 1964-1974 -> p ~ 0.064: the RECONSTRUCTED Dec 1964 flood is the
# single biggest support (more than Feb 2020). The daily extension supplied the
# key point.
loo_one <- function(pred)
  map_dfr(seq_len(nrow(dat)), function(i) {
    d <- dat[-i, ]
    f <- lm(
      reformulate(pred, "net_area_change_ft2_per_year"),
      data = d,
      weights = interval_years^2
    )
    glance(f) |> transmute(
      pred,
      dropped = paste0(dat$year_t1[i], "-", dat$year_t2[i]),
      r_squared = r.squared,
      p_value = p.value
    )
  })
loo_cum  <- loo_one("cum_excess_thresh_cfs_days")
loo_peak <- loo_one("q_peak_max_cfs")
c(
  cum_excess_maxp = max(loo_cum$p_value),
  peak_maxp = max(loo_peak$p_value)
)  # worst single drop
dplyr::arrange(loo_cum, desc(p_value)) # which drop hurts cum_excess most


# ---- 4. Permutation test: is the fit better than chance? --------------------
# Shuffle the response 10,000 times and refit; the permutation p is the fraction
# of shuffles whose R2 meets or exceeds the observed R2. This replaces t-test
# asymptotics, which are the weakest part of the claim at n = 14.
#
# CHECKS: that the cum_excess R2 is not a small-sample asymptotic artifact.
# EXPECTED: permutation p ~ 0.029, consistent with the parametric p ~ 0.017.
set.seed(1)
obs  <- summary(
  lm(
    net_area_change_ft2_per_year ~ cum_excess_thresh_cfs_days,
    dat,
    weights = interval_years^2
  )
)$r.squared
null <- replicate(10000, {
  d <- dat
  d$net_area_change_ft2_per_year <- sample(d$net_area_change_ft2_per_year)  # break the x-y link
  summary(
    lm(
      net_area_change_ft2_per_year ~ cum_excess_thresh_cfs_days,
      d,
      weights = interval_years^2
    )
  )$r.squared
})
mean(null >= obs)   # permutation p


# ---- 5. Reconstruction extrapolation check ----------------------------------
# The result leans hardest on the reconstructed 1964-1974 interval (Section 3),
# so it matters whether that reconstruction was INTERPOLATION (Gibbon input
# inside the MOVE.1 calibration range -> trustworthy) or EXTRAPOLATION (Gibbon
# input above the calibrated maximum -> carries the log-log curvature bias, less
# trustworthy). Compare each reconstructed day's Gibbon input against the
# largest Gibbon daily seen in the calibration (observed, post-1995) period.
#
# CHECKS: did any reconstructed day use a Gibbon value above the calibration
# max? EXPECTED: n_extrapolated = 0. gib_recon_max ~ 4,500 vs gib_cal_max ~
# 9,330 — every reconstructed day (1964 included) is well within range: pure
# interpolation, so no extrapolation bias on the load-bearing point.
gib <- readr::read_csv("data/dv_gage_daily_flows.csv", show_col_types = FALSE) |>
  dplyr::filter(gage_id == "14020000") |>                 # Gibbon (index gage)
  dplyr::transmute(date = as.Date(date), gibbon_q = daily_q_cfs)

ext <- readRDS("data/pendleton_daily_extended.rds")
recon_dates <- subset(ext, is_estimated)$date             # the 280 reconstructed days
obs_start   <- min(subset(ext, !is_estimated)$date)       # first observed day = calibration start
gib_cal_max <- max(gib$gibbon_q[gib$date >= obs_start])   # max Gibbon in the calibration period
gib_recon   <- gib$gibbon_q[gib$date %in% recon_dates]    # Gibbon inputs used in the reconstruction
c(
  gib_cal_max = gib_cal_max,
  gib_recon_max = max(gib_recon),
  n_extrapolated = sum(gib_recon > gib_cal_max)
)
