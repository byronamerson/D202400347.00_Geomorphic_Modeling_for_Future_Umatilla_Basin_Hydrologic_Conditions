# =============================================================================
# 09b_bias_correction_diagnostic.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 9b: Transfer cross-check + raw-flow sanity -- hand-rolled QM vs qmap
#           QUANT vs qmap RQUANT, and a four-member raw-flow sweep, before
#           committing to an implementation.
# =============================================================================
#
# Purpose (two jobs):
#   (A) three empirical quantile-mapping transfers, fitted on the SAME
#       above-bankfull pool and laid side by side, so we can see how much the
#       implementation choice actually moves the correction.
#       1. hand-rolled  -- scripts/09 build_qmap()/apply_qmap(): paired empirical
#                          quantiles (type 8), tail-densified grid, multiplicative
#                          ("ratio") extrapolation above the largest observed flow.
#       2. qmap QUANT    -- fitQmapQUANT/doQmapQUANT: plain empirical quantile map
#                          (Gudmundsson). Type-7 quantiles, Boe (2007) additive
#                          constant extrapolation. The direct analog of the
#                          hand-roll -- a correctness check: these should nearly
#                          coincide.
#       3. qmap RQUANT   -- fitQmapRQUANT/doQmapRQUANT: ROBUST version. Smooths
#                          the quantile-quantile relation with local linear
#                          regression + bootstrap, and (type "linear2")
#                          extrapolates beyond the largest observed flow along the
#                          local slope. The candidate upgrade for our THIN flood
#                          tail (~few events pin the top).
#
#   (B) a raw-flow sanity sweep across all four Livneh members vs the observed
#       reference -- to answer the question the first VIC_P1 run raised: does the
#       raw hindcast even contain the floods our metric depends on, is any deficit
#       VIC-specific or systemic, and is it peak-damping or a volume shortfall?
#
#   The change-preserving futures method (MBC::QDM) is a separate, later step;
#   it is not exercised here (the hindcast has no future window to preserve).
#
# What to look for:
#   - hand-rolled vs QUANT should overlie almost exactly through the interior;
#     divergence at the very top is the tail rule (ratio vs additive).
#   - RQUANT vs the other two in the flood tail = how much sparse-sample noise is
#     being smoothed. A material departure => the tail is thin enough that the
#     robust fit is worth adopting.
#   - The distribution table shows whether each corrected series lands on the obs
#     ruler; the days>=Q2/yr row exposes the conditional-map frequency question.
#   - The member sweep: mean_daily matching obs but the exceedance rates / max
#     falling short = peak-damping; mean_daily itself low = a volume shortfall.
#
# Inputs : scripts/09_bias_correction.R (engine + readers), qmap
# Outputs: plots/bias_correction_transfer_comparison.png   (gitignored)
#          returns comparison / sweep tibbles for inspection
# Style  : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)
library(qmap)

source("scripts/09_bias_correction.R")  # constants, readers, build_qmap/apply_qmap


# =============================================================================
# 1. FIT THE THREE TRANSFERS  (same above-bankfull pool)
# =============================================================================

fit_transfers <- function(member = "VIC_P1",
                          reference = c("extended", "native"),
                          fit_floor = BANKFULL_CFS,
                          tail = "ratio") {
  #' Fit all three transfers on one Livneh member vs one observed reference,
  #' each on the identical >= fit_floor pool so the comparison is apples to
  #' apples. qmap's wet.day handling is precip-specific and is turned OFF.
  #' @return a list bundling the fitted transfers + the source series + pools
  reference <- match.arg(reference)
  livneh <- read_umamc_streamflow(livneh_path(member))
  obs <- switch(reference,
    extended = read_extended_reference(),
    native   = read_native_gauge_reference()
  )

  m <- livneh$q_cfs[is.finite(livneh$q_cfs) & livneh$q_cfs >= fit_floor]
  o <- obs$q_cfs[is.finite(obs$q_cfs)       & obs$q_cfs   >= fit_floor]

  list(
    handroll  = build_qmap(livneh$q_cfs, obs$q_cfs, fit_floor = fit_floor, tail = tail),
    quant     = fitQmapQUANT(o, m, qstep = 0.01, nboot = 1,  wet.day = FALSE),
    rquant    = fitQmapRQUANT(o, m, qstep = 0.01, nlls = 10, nboot = 10, wet.day = FALSE),
    livneh    = livneh,
    obs       = obs,
    fit_floor = fit_floor,
    model_max = max(m),
    member    = member,
    reference = reference
  )
}


# =============================================================================
# 2. APPLY  (pass-through below the floor; map at/above it)
# =============================================================================

apply_pkg_transfer <- function(x, fobj, do_fun, floor, ...) {
  #' Apply a qmap doQmap*() transfer only to in-support (>= floor) values,
  #' leaving lower flows untouched -- matching the hand-roll's semantics.
  out <- x
  idx <- which(is.finite(x) & x >= floor)
  out[idx] <- do_fun(x[idx], fobj, ...)
  out
}

apply_all_transfers <- function(fits) {
  #' Push the Livneh series through all three transfers.
  #' @return the Livneh tibble with q_raw + one corrected column per method
  fits$livneh %>%
    transmute(
      date,
      q_raw   = q_cfs,
      q_hand  = apply_qmap(fits$handroll, q_cfs),
      q_quant = apply_pkg_transfer(q_cfs, fits$quant,  doQmapQUANT,  fits$fit_floor, type = "linear"),
      q_rquant = apply_pkg_transfer(q_cfs, fits$rquant, doQmapRQUANT, fits$fit_floor, type = "linear2")
    )
}


# =============================================================================
# 3. TRANSFER CURVES  (the direct side-by-side view)
# =============================================================================

transfer_curves <- function(fits, n = 300) {
  #' Sample each transfer on a common model-flow grid (bankfull -> model max):
  #' corrected flow as a function of raw model flow. This is the cleanest
  #' side-by-side -- what each method would do to any given input flow.
  grid <- seq(fits$fit_floor, fits$model_max, length.out = n)
  bind_rows(
    tibble(method = "hand-rolled (ratio tail)", model_q = grid,
           corrected = apply_qmap(fits$handroll, grid)),
    tibble(method = "qmap QUANT (linear)",      model_q = grid,
           corrected = doQmapQUANT(grid, fits$quant, type = "linear")),
    tibble(method = "qmap RQUANT (linear2)",    model_q = grid,
           corrected = doQmapRQUANT(grid, fits$rquant, type = "linear2"))
  )
}


# =============================================================================
# 4. DISTRIBUTION COMPARISON TABLE
# =============================================================================

compare_distributions <- function(fits,
                                  probs = c(0.5, 0.9, 0.95, 0.99, 0.995, 0.999)) {
  #' High-flow (>= bankfull) quantiles and above-Q2 exceedance rate for the raw
  #' Livneh, each corrected series, and the observed reference. A working
  #' transfer pulls its column onto `obs`; the days>=Q2/yr row surfaces any
  #' frequency bias the conditional (above-threshold) map leaves in place.
  corrected <- apply_all_transfers(fits)
  hi  <- function(x) x[is.finite(x) & x >= BANKFULL_CFS]
  yrs <- function(d) as.numeric(diff(range(d))) / 365.25

  series <- list(
    raw    = list(q = corrected$q_raw,    d = corrected$date),
    hand   = list(q = corrected$q_hand,   d = corrected$date),
    quant  = list(q = corrected$q_quant,  d = corrected$date),
    rquant = list(q = corrected$q_rquant, d = corrected$date),
    obs    = list(q = fits$obs$q_cfs,     d = fits$obs$date)
  )

  col_of <- function(s) c(
    sum(s$q >= Q2_CFS, na.rm = TRUE) / yrs(s$d),          # days>=Q2 /yr
    quantile(hi(s$q), probs, type = 8, names = FALSE)      # high-flow quantiles
  )

  tibble(quantity = c("days>=Q2 /yr", sprintf("q%.1f%% (cfs)", probs * 100))) %>%
    bind_cols(map_dfc(series, col_of))
}


# =============================================================================
# 4b. RAW SANITY STATS & MEMBER SWEEP  (is the flood signal even in the flows?)
# =============================================================================

raw_sanity_stats <- function(q, date) {
  #' Coarse water-balance + high-flow stats for one daily series. mean_daily is
  #' the volume / water-balance check (matches obs => volume OK); the exceedance
  #' rates, upper quantiles, and max are the flood-representation check (falling
  #' short => peak-damping). Separating the two tells 'peaks flattened' from
  #' 'whole series runs low'.
  #' @param q,date daily flow (cfs) and dates
  #' @return one-row tibble of stats
  ok <- is.finite(q); q <- q[ok]; date <- date[ok]
  yrs <- as.numeric(diff(range(date))) / 365.25
  tibble(
    n_years          = round(yrs, 1),
    mean_daily_cfs   = round(mean(q), 1),
    days_bankfull_yr = round(sum(q >= BANKFULL_CFS) / yrs, 3),
    days_q2_yr       = round(sum(q >= Q2_CFS) / yrs, 3),
    q99_cfs          = round(quantile(q, 0.99,  type = 8, names = FALSE)),
    q999_cfs         = round(quantile(q, 0.999, type = 8, names = FALSE)),
    max_daily_cfs    = round(max(q))
  )
}

sweep_members <- function(reference = c("extended", "native"),
                          members = LIVNEH_MEMBERS) {
  #' Raw sanity stats for every Livneh hindcast member plus the observed
  #' reference (restricted to the Livneh span for a fair comparison), stacked
  #' into one at-a-glance table. Answers: is the flood deficit VIC-specific or
  #' systemic, and is it peak-damping or a volume shortfall?
  #' @return tibble, one row per member + one obs row
  reference <- match.arg(reference)
  series <- set_names(members) %>% map(~ read_umamc_streamflow(livneh_path(.x)))
  model_tbl <- imap_dfr(series, ~ raw_sanity_stats(.x$q_cfs, .x$date) %>%
                          mutate(series = .y, .before = 1))

  span <- range(series[[1]]$date)          # 1950-2011; obs restricted to match
  obs <- switch(reference,
    extended = read_extended_reference(),
    native   = read_native_gauge_reference()
  ) %>% filter(date >= span[1], date <= span[2])

  obs_tbl <- raw_sanity_stats(obs$q_cfs, obs$date) %>%
    mutate(series = paste0("OBS (", reference, ")"), .before = 1)

  bind_rows(model_tbl, obs_tbl)
}


# =============================================================================
# 5. PLOT  (boundary)
# =============================================================================

plot_transfer_comparison <- function(fits,
                                     out = "plots/bias_correction_transfer_comparison.png") {
  #' Overlay the three transfer curves with the 1:1 line and the Q2 marker; the
  #' empirical hand-roll knots are shown as points for reference.
  curves <- transfer_curves(fits)
  knots  <- fits$handroll$transfer %>% filter(model_q >= fits$fit_floor)

  p <- ggplot(curves, aes(model_q, corrected, colour = method)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey60") +
    geom_vline(xintercept = Q2_CFS, linetype = "dotted", colour = "grey50") +
    geom_point(data = knots, aes(model_q, obs_q), inherit.aes = FALSE,
               colour = "grey40", size = 0.7, alpha = 0.6) +
    geom_line(linewidth = 0.8) +
    labs(
      x = "Raw Livneh daily flow (cfs)",
      y = "Bias-corrected flow (cfs)",
      colour = NULL,
      title = sprintf("Bias-correction transfers: %s vs %s reference",
                      fits$member, fits$reference),
      subtitle = sprintf("Fitted on days >= bankfull (%.0f cfs); dotted = Q2 (%.0f); dashed = 1:1",
                         fits$fit_floor, Q2_CFS)
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

  if (!dir.exists("plots")) dir.create("plots", recursive = TRUE)
  ggsave(out, p, width = 8, height = 6, dpi = 150)
  message("  Wrote ", out)
  invisible(p)
}


# =============================================================================
# 6. USAGE  (run interactively; nothing executes on source())
# =============================================================================
# fits <- fit_transfers("VIC_P1", reference = "extended")
# compare_distributions(fits)          # numbers: each method vs obs
# plot_transfer_comparison(fits)       # curves side by side -> plots/
#
# # raw flood-representation across all four members (+ obs), at a glance:
# sweep_members(reference = "extended")
#
# # sensitivity: native gauge reference, or the full-CDF (frequency) variant
# fits_nat  <- fit_transfers("VIC_P1", reference = "native")
# fits_full <- fit_transfers("VIC_P1", reference = "extended", fit_floor = 0)
# =============================================================================
