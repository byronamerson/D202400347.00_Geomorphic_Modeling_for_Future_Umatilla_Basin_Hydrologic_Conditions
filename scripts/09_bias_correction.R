# =============================================================================
# 09_bias_correction.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 9: Bias-correction engine (empirical quantile mapping) for the UW /
#          RMJOC-II future daily flows at Pendleton (UMAMC).
# =============================================================================
#
# Purpose: the "flat" correction machinery -- a transparent, hand-rolled
#   empirical quantile-mapping (QM) transfer that maps modeled daily flow onto
#   the observed gauge's ruler in the high-flow range. No black-box QM package:
#   the transfer is just paired empirical quantiles, so the method can be
#   followed and critiqued end to end.
#
#   This is the HISTORICAL / hindcast case of the PresRat core (Pierce et al.
#   2015). In the historical period EDCDFm reduces to plain QM -- there is no
#   model-future-vs-model-historical change to preserve yet -- so what we build
#   and exercise here is plain QM. The ratio-change (EDCDFm/PresRat) extension
#   for the GCM *futures* bolts onto build_qmap()/apply_qmap() later and is NOT
#   in this file. (The tested field implementation of that extension is
#   MBC::QDM, ratio=TRUE -- see the diagnostic notes.)
#
# Decisions baked in (see claude/NOTE_bias_correction_decisions.md for rationale
# and the watch-points to revisit if downstream results look spurious):
#   - Fit floor = BANKFULL = 0.75 x Q2 (~4,157 cfs). Build the transfer on the
#     high-flow band, not just >= Q2 (~doubles the anchoring events). QM is
#     quantile-local, so pooling bankfull-to-Q2 days cannot drag the top of the
#     map the way it dragged the single-slope MOVE.1 extension.
#   - Reference distribution: EXTENDED record (primary; carries reconstructed
#     pre-1996 floods incl. 1964) with the NATIVE gauge as a sensitivity run.
#     build_qmap() takes the reference as an argument, so running both is free.
#     NB the extended record is a HIGH-FLOW reconstruction: its pre-1996 low-flow
#     days are not filled, so it over-reads mean/volume -- use the native gauge
#     for any volume/water-balance comparison.
#   - Metric threshold Q2 (5,542) is applied DOWNSTREAM (04c), not here.
#
# OPEN CHOICE the diagnostic settled toward FULL-CDF (frequency vs magnitude):
#   `fit_floor = BANKFULL` builds a CONDITIONAL (above-threshold) map -- it
#   corrects the *magnitude* distribution of high flows but leaves the model's
#   *frequency* of exceeding a level unchanged. `fit_floor = 0` builds a
#   FULL-CDF map, which also corrects exceedance frequency and any volume offset.
#   The hindcast sweep showed both a modest volume offset and a large flood-
#   frequency deficit, so full-CDF is the working choice; still switchable.
#
# Scope of THIS file: the engine + a minimal self-check on the Livneh hindcast.
#   The full diagnostic battery (FDCs, above-Q2 exceedance stats over matched
#   periods, per-hydro-model comparison) and the forcing-pipeline hookup follow
#   as separate steps. Nothing is written to disk yet -- correct_livneh()
#   returns objects for inspection until the mode + reference are settled.
#
# Inputs:
#   - data_in/Umatilla_Future_Flows/historical_livneh_{PRMS_P1,VIC_P1,VIC_P2,VIC_P3}-UMAMC-streamflow-1.0.csv
#   - data/pendleton_daily_extended.rds   (extended reference; from 04b)
#   - data/dv_gage_daily_flows.csv        (native gauge reference; from 04a)
#
# Style: Tidyverse & FP guidelines. Flows in cfs throughout.
# NB: qmap (loaded in 09b) pulls in MASS, which masks dplyr::select. This file
#   therefore avoids select() (uses transmute) so it is robust to load order.
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(purrr)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

Q2_CFS            <- 5542                       # Pendleton Q2 (mirrors 04c/04b config; B17C, post-McKay)
BANKFULL_FRACTION <- 0.75                        # fit floor as a fraction of Q2 (04b daily-extension band)
BANKFULL_CFS      <- BANKFULL_FRACTION * Q2_CFS  # ~4,157 cfs
MISSING_VALUE     <- -9999                        # UMAMC files flag gaps with -9999

FUTURE_FLOWS_DIR    <- "data_in/Umatilla_Future_Flows"
EXTENDED_RECORD_RDS <- "data/pendleton_daily_extended.rds"
NATIVE_GAUGE_CSV    <- "data/dv_gage_daily_flows.csv"
PENDLETON_GAGE_ID   <- 14020850

# Livneh hindcast members (obs-weather-driven -> day-for-day comparable to the
# gauge). Two structurally distinct hydrologic models: PRMS and VIC (P1-P3 are
# VIC parameter perturbations).
LIVNEH_MEMBERS <- c("PRMS_P1", "VIC_P1", "VIC_P2", "VIC_P3")

# Probability grid for the transfer curve: even coverage plus a densified tail
# (0.95 -> 0.9999) so the flood end of the map is well resolved.
QMAP_PROBS <- sort(unique(c(
  seq(0.02, 0.98, by = 0.02),
  1 - 10^(-seq(1.3, 4, by = 0.1))
)))


# =============================================================================
# 2. READERS  (boundary: all file I/O lives here)
# =============================================================================

read_umamc_streamflow <- function(path) {
  #' Read one UMAMC daily-streamflow file (raw RMJOC-II output).
  #' The ~30-line provenance header is comment-marked with '#'; the first
  #' non-comment line is the column header. NB the DYNAMICAL downscaling variant
  #' ships an UNNAMED first column (header ",streamflow") while BCSD/MACA use
  #' "date,streamflow" -- so read the two columns by POSITION, not by name
  #' (col 1 = date, col 2 = streamflow in every variant). Gaps are -9999 -> NA.
  #' @param path path to a *-UMAMC-streamflow-1.0.csv file
  #' @return tibble(date <Date>, q_cfs <dbl>)
  raw <- read_csv(path, comment = "#", show_col_types = FALSE,
                  col_types = cols(.default = col_character()))
  tibble(date  = as.Date(raw[[1]]),
         q_cfs = na_if(as.double(raw[[2]]), MISSING_VALUE))
}

livneh_path <- function(member) {
  #' Path to a Livneh hindcast member's UMAMC file.
  #' @param member one of LIVNEH_MEMBERS
  file.path(FUTURE_FLOWS_DIR,
            sprintf("historical_livneh_%s-UMAMC-streamflow-1.0.csv", member))
}

read_extended_reference <- function() {
  #' Observed reference (PRIMARY for FLOODS): the extended Pendleton daily record
  #' from 04b (real gauge 1996-present spliced onto the MOVE.1 reconstruction back
  #' to 1952 -- it carries the reconstructed pre-1996 floods incl. 1964). NB it is
  #' a high-flow reconstruction, so its mean/volume is not a clean reference.
  #' @return tibble(date <Date>, q_cfs <dbl>)
  readRDS(EXTENDED_RECORD_RDS) %>%
    transmute(date = as.Date(date), q_cfs = daily_q_cfs)
}

read_native_gauge_reference <- function() {
  #' Observed reference (SENSITIVITY; and the clean VOLUME reference): the native
  #' Pendleton gauge only (14020850, continuous real daily ~1996-present, no
  #' reconstruction; misses 1964).
  #' @return tibble(date <Date>, q_cfs <dbl>)
  read_csv(NATIVE_GAUGE_CSV, show_col_types = FALSE) %>%
    filter(gage_id == PENDLETON_GAGE_ID) %>%
    transmute(date = as.Date(date), q_cfs = daily_q_cfs)
}


# =============================================================================
# 3. QUANTILE-MAP ENGINE  (pure)
# =============================================================================

build_qmap <- function(model_q, obs_q, fit_floor = BANKFULL_CFS,
                       tail = c("ratio", "additive", "clamp")) {
  #' Build an empirical quantile-mapping transfer from a modeled flow sample to
  #' an observed flow sample.
  #'
  #' The transfer is the classic QM curve: at a shared set of probabilities, pair
  #' the model's quantile with the observed quantile. Applying it maps a model
  #' value to the observed value at the same non-exceedance probability. Built on
  #' quantiles (type 8, Hyndman-Fan) rather than raw sorted pairs so tied flow
  #' values and unequal sample sizes are handled cleanly.
  #'
  #' @param model_q,obs_q numeric daily-flow vectors (cfs); NAs dropped
  #' @param fit_floor keep only days >= this flow when building the map. The
  #'   default (BANKFULL_CFS) gives a CONDITIONAL high-flow map; set 0 for a
  #'   FULL-CDF map (also corrects exceedance frequency + volume -- see header).
  #' @param tail extrapolation rule for model values ABOVE the top transfer
  #'   knot: "ratio" (preserve the top-knot multiplicative factor -- default,
  #'   consistent with the ratio-based PresRat direction), "additive" (preserve
  #'   the top-knot offset), or "clamp" (cap at the top observed knot).
  #' @return an object of class "qmap"
  tail <- match.arg(tail)
  m <- model_q[is.finite(model_q) & model_q >= fit_floor]
  o <- obs_q[is.finite(obs_q)   & obs_q   >= fit_floor]
  stopifnot(length(m) >= 10, length(o) >= 10)

  transfer <- tibble(
    prob    = QMAP_PROBS,
    model_q = quantile(m, QMAP_PROBS, type = 8, names = FALSE),
    obs_q   = quantile(o, QMAP_PROBS, type = 8, names = FALSE)
  )

  structure(
    list(transfer   = transfer,
         fit_floor  = fit_floor,
         tail       = tail,
         n_model    = length(m),
         n_obs      = length(o),
         model_max  = max(m),
         obs_max    = max(o)),
    class = "qmap"
  )
}

apply_qmap <- function(qmap, x) {
  #' Push flow values through a fitted quantile-map transfer.
  #' Values below the fit floor are outside the transfer's support and are passed
  #' through unchanged (they never enter the > Q2 forcing metric). Values above
  #' the top transfer knot use the qmap's tail rule.
  #' @param qmap a "qmap" from build_qmap()
  #' @param x numeric flow vector (cfs)
  #' @return numeric vector, x with in-support values corrected
  tr <- qmap$transfer
  out <- x
  idx <- which(is.finite(x) & x >= qmap$fit_floor)
  xi  <- x[idx]

  # Interior: interpolate the monotone model_q -> obs_q transfer curve. A
  # saturated model tail can produce tied model_q knots; average obs_q within
  # ties so approx() sees strictly increasing x (removes the benign warning).
  tr_u <- aggregate(obs_q ~ model_q, data = tr, FUN = mean)
  xc <- approx(tr_u$model_q, tr_u$obs_q, xout = xi, rule = 2)$y

  # Beyond the top knot: replace the clamped value with the chosen tail rule.
  top_m <- tr$model_q[nrow(tr)]
  top_o <- tr$obs_q[nrow(tr)]
  above <- xi > top_m
  if (any(above)) {
    xc[above] <- switch(qmap$tail,
      clamp    = top_o,
      additive = top_o + (xi[above] - top_m),
      ratio    = top_o * (xi[above] / top_m)
    )
  }

  out[idx] <- xc
  out
}


# =============================================================================
# 4. ORCHESTRATION  (boundary)
# =============================================================================

correct_livneh <- function(member = "VIC_P1",
                           reference = c("extended", "native"),
                           fit_floor = BANKFULL_CFS,
                           tail = "ratio") {
  #' Bias-correct one Livneh hindcast member against an observed reference.
  #' @param member one of LIVNEH_MEMBERS
  #' @param reference "extended" (primary) or "native" (sensitivity)
  #' @param fit_floor,tail passed to build_qmap()
  #' @return tibble(date, q_raw, q_corrected) plus the qmap as an attribute
  reference <- match.arg(reference)
  livneh <- read_umamc_streamflow(livneh_path(member))
  obs <- switch(reference,
    extended = read_extended_reference(),
    native   = read_native_gauge_reference()
  )

  qmap <- build_qmap(livneh$q_cfs, obs$q_cfs, fit_floor = fit_floor, tail = tail)

  # transmute (not mutate + select) so this is robust to MASS masking select.
  result <- livneh %>%
    transmute(date, q_raw = q_cfs, q_corrected = apply_qmap(qmap, q_cfs))

  attr(result, "qmap") <- qmap
  attr(result, "member") <- member
  attr(result, "reference") <- reference
  result
}


# =============================================================================
# 5. MINIMAL SELF-CHECK  (does the corrected series land on the obs ruler?)
# =============================================================================

high_flow_summary <- function(corrected, reference = c("extended", "native"),
                              probs = c(0.5, 0.9, 0.95, 0.99, 0.995, 0.999)) {
  #' Quick sanity table: high-flow (>= bankfull) quantiles of the raw and
  #' corrected Livneh series against the observed reference, plus exceedance
  #' rates above Q2 (per water year, to normalize for differing record lengths).
  #' A working transfer should pull the `corrected` column onto the `obs` column;
  #' the Q2 exceedance-rate row exposes any frequency bias the conditional map
  #' leaves behind.
  #' @param corrected output of correct_livneh()
  #' @param reference which observed reference to compare against
  #' @return tibble(quantity, raw, corrected, obs)
  reference <- match.arg(reference)
  obs <- switch(reference,
    extended = read_extended_reference(),
    native   = read_native_gauge_reference()
  )

  hi <- function(x) x[is.finite(x) & x >= BANKFULL_CFS]
  yrs <- function(d) as.numeric(diff(range(d))) / 365.25
  rate_gt_q2 <- function(x, d) sum(x >= Q2_CFS, na.rm = TRUE) / yrs(d)

  q_rows <- tibble(
    quantity  = sprintf("q%.1f%% (cfs)", probs * 100),
    raw       = quantile(hi(corrected$q_raw),       probs, type = 8, names = FALSE),
    corrected = quantile(hi(corrected$q_corrected), probs, type = 8, names = FALSE),
    obs       = quantile(hi(obs$q_cfs),             probs, type = 8, names = FALSE)
  )

  count_rows <- tibble(
    quantity  = c("days>=bankfull /yr", "days>=Q2 /yr"),
    raw       = c(sum(corrected$q_raw       >= BANKFULL_CFS, na.rm = TRUE) / yrs(corrected$date),
                  rate_gt_q2(corrected$q_raw,       corrected$date)),
    corrected = c(sum(corrected$q_corrected >= BANKFULL_CFS, na.rm = TRUE) / yrs(corrected$date),
                  rate_gt_q2(corrected$q_corrected, corrected$date)),
    obs       = c(sum(obs$q_cfs >= BANKFULL_CFS, na.rm = TRUE) / yrs(obs$date),
                  rate_gt_q2(obs$q_cfs, obs$date))
  )

  bind_rows(count_rows, q_rows)
}


# =============================================================================
# 6. USAGE  (run interactively; nothing executes on source())
# =============================================================================
# corr <- correct_livneh("VIC_P1", reference = "extended")   # primary reference
# high_flow_summary(corr, reference = "extended")            # sanity table
# attr(corr, "qmap")$transfer                                # inspect the curve
#
# # sensitivity: same member against the native gauge only
# corr_nat <- correct_livneh("VIC_P1", reference = "native")
#
# # frequency vs magnitude: full-CDF map (also corrects exceedance frequency)
# corr_full <- correct_livneh("VIC_P1", reference = "extended", fit_floor = 0)
# =============================================================================
