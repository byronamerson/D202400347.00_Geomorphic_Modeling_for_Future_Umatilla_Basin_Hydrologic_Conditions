# =============================================================================
# 10_future_bias_correction.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 10: Change-preserving bias correction of the UW / RMJOC-II GCM FUTURE
#           daily flows at Pendleton (UMAMC), 2006-2099.
# =============================================================================
#
# Purpose: map each GCM member's modeled daily flow onto the observed gauge's
#   ruler while PRESERVING that member's own future-vs-historical change at every
#   quantile -- remove the model's distributional bias WITHOUT damping the
#   climate-change signal, which is the deliverable.
#
#   This is the FUTURES case of the PresRat core (Pierce et al. 2015). Unlike the
#   historical hindcast (09, where EDCDFm reduces to plain QM), the futures carry
#   a model-future-vs-model-historical change that must be kept. Field
#   implementation = Cannon's Quantile Delta Mapping, MBC::QDM(ratio = TRUE).
#   Engine choice: MBC::QDM direct (Byron, NOTE_bias_correction_decisions UPDATE c).
#
# ARCHITECTURE (functional decomposition -- see Tidyverse/FP guidelines):
#   The unit of work is a PURE transform, correct_series(), that takes an already-
#   read daily series + the reference vector and returns the corrected tibble --
#   no file I/O, testable with synthetic data, identical whether called once or
#   172 times. File reads/writes live in thin edge wrappers (correct_future_file,
#   run_bias_correction). The 172-file job is then a declarative map over the
#   members tibble; the augmented tibble IS the manifest (split-apply-combine).
#   Fault tolerance via safely(), not tryCatch in a loop.
#
#   DELIBERATE departure from the nest-everything pattern: the batch is side-
#   effecting (172 CSV writes + resume), so it is a map-with-side-effects that
#   returns a manifest, NOT a tibble holding all 172 daily series (~6M rows) in
#   memory. The correction MATH stays pure; only orchestration holds side effects.
#
# Method (locked -- see claude/NOTE_bias_correction_decisions.md UPDATE c):
#   corrected_future(t) = Q_obs(tau_t) * [ m.p(t) / Q_mc(tau_t) ]
#     tau_t = the future value's non-exceedance prob within the future window.
#   o.c = native Pendleton gauge, FULL daily CDF (complete, carries 2020 flood).
#   m.c = each member's historical control window 1951-2005 (free-running GCM
#         climate -> distributional frame, not day-for-day). BRANCH A: full
#         control period, chosen over the 1996-2005 gauge overlap for tail
#         robustness (m.c sets BOTH the bias and the change-ratio denominator).
#   m.p = that member's future window 2006-2099, corrected in ONE block.
#   ratio = TRUE (flow is a ratio variable, like precip -> multiplicative change).
#
# Trackable assumptions / watch-points (revisit if downstream looks spurious):
#   - LOW tail: MBC::QDM's trace / ratio.max guards act only on near-zero values
#     (ratio.max.trace defaults to 10*trace). Pendleton flows are never near zero,
#     so these are inert here; low-flow corrections do not enter the >Q2 metric
#     regardless.
#   - UPPER tail: future floods can exceed anything in o.c / m.c. QDM extrapolates
#     the largest values by the top-quantile ratio (mhat.p ~ max(o.c) * m.p/max(m.c)),
#     i.e. a multiplicative tail. This is the fragile spot the hindcast flagged
#     (~+/-15% at q99.9, member-dependent); carry it in the projection envelope.
#   - K-FACTOR (PresRat mean-change conservation) is NOT part of MBC::QDM and is
#     deferred (off). If adopted it is a separate post-correction step.
#   - Metric threshold Q2 (5,542) is applied DOWNSTREAM (04c), not here; this
#     script corrects the full daily distribution.
#
# Reporting granularity (downstream, not here): corrected daily series are sliced
#   into century periods (2020s/2050s/2080s) at the forcing step; the correction
#   is one pass over the full 2006-2099 and is untouched by that slicing.
#
# Inputs:
#   - data_in/Umatilla_Future_Flows/*-UMAMC-streamflow-1.0.csv  (172 GCM members;
#     historical_livneh_* excluded -- those are 09's hindcast)
#   - data/dv_gage_daily_flows.csv   (native gauge reference, o.c; from 04a)
#
# Outputs (CSV per data-format standard; gitignored derived data):
#   - data/Umatilla_Future_Flows_BC/<member_id>-BC.csv  (date, q_raw, q_corrected)
#   - data/Umatilla_Future_Flows_BC/_bc_manifest.csv    (factor grid + status)
#
# Reuse: source("scripts/09_bias_correction.R") for readers + config (09 runs
#   nothing on source). NB the shared single-job functions still physically live
#   in 09; extracting them into R/ modules is scoped separately
#   (NOTE_shared_module_refactor.md). Style: Tidyverse & FP guidelines; cfs
#   throughout. MBC pulls in MASS (masks dplyr::select) -> avoid select().
# =============================================================================

source("scripts/09_bias_correction.R")   # readers, Q2_CFS, MISSING_VALUE, dirs

library(dplyr)
library(readr)
library(purrr)
library(MBC)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

CALIB_WINDOW  <- c(1951L, 2005L)   # m.c: GCM historical control (Branch A)
FUTURE_WINDOW <- c(2006L, 2099L)   # m.p: RCP future, corrected in one block

BC_OUT_DIR    <- "data/Umatilla_Future_Flows_BC"

# QDM knobs (trackable). ratio = TRUE for flow. trace / jitter are near-zero
# guards, inert for Pendleton flows; exposed here so they are visible.
QDM_RATIO  <- TRUE
QDM_TRACE  <- 0.01   # cfs; below the smallest daily flow -> inert divide guard
QDM_JITTER <- 0      # bump slightly only if MBC warns about ties


# =============================================================================
# 2. READERS / MEMBER DISCOVERY  (I/O boundary)
#    (read_umamc_streamflow, read_native_gauge_reference come from 09)
# =============================================================================

parse_umamc_filename <- function(path) {
  #' Parse the RMJOC-II factor grid from a UMAMC filename. (pure)
  #' Pattern: [GCM]_[SCENARIO]_[DOWNSCALING]_[HYDRO]_P[#]-UMAMC-streamflow-1.0.csv
  #' Split from the RIGHT so GCM names containing '_' or '-' stay intact.
  #' @param path path to a *-UMAMC-streamflow-1.0.csv file
  #' @return one-row tibble of factors + path + member_id
  stem  <- sub("-UMAMC-streamflow-1\\.0\\.csv$", "", basename(path))
  parts <- strsplit(stem, "_", fixed = TRUE)[[1]]
  n <- length(parts)
  stopifnot(n >= 5)
  tibble(
    member_id   = stem,
    gcm         = paste(parts[seq_len(n - 4)], collapse = "_"),
    scenario    = parts[n - 3],
    downscaling = parts[n - 2],
    hydro       = parts[n - 1],
    hydro_param = parts[n],
    path        = path
  )
}

list_future_members <- function(dir = FUTURE_FLOWS_DIR) {
  #' Discover the GCM future members (livneh hindcast excluded). (I/O)
  #' @return tibble, one row per member (172 expected)
  files <- list.files(dir, pattern = "-UMAMC-streamflow-1\\.0\\.csv$",
                      full.names = TRUE)
  files <- files[!grepl("^historical_livneh_", basename(files))]
  members <- map_dfr(files, parse_umamc_filename)
  message(sprintf("Found %d future members (%d GCMs; scenarios: %s; downscaling: %s)",
                  nrow(members), n_distinct(members$gcm),
                  paste(sort(unique(members$scenario)),    collapse = ", "),
                  paste(sort(unique(members$downscaling)), collapse = ", ")))
  members
}


# =============================================================================
# 3. PURE CORE  (no I/O; testable with synthetic data; the unit of work)
# =============================================================================

slice_years <- function(series, window) {
  #' Subset a daily series to a calendar-year range [window[1], window[2]]. (pure)
  #' @param series tibble with a `date` <Date> column
  #' @param window length-2 integer c(first_year, last_year), inclusive
  series %>%
    filter(between(as.integer(format(date, "%Y")), window[1], window[2]))
}

qdm_future <- function(o_c, m_c, m_p,
                       ratio = QDM_RATIO, trace = QDM_TRACE,
                       jitter.factor = QDM_JITTER) {
  #' Cannon (2015) Quantile Delta Mapping via MBC::QDM. (pure)
  #' Maps m.p onto the o.c ruler while preserving the m.p-vs-m.c change per
  #' quantile. o_c, m_c may carry NAs (dropped here); m_p MUST be finite and
  #' ordered by the caller (MBC::QDM returns mhat.p positionally).
  #' @param o_c observed calibration -- native gauge, full daily CDF (cfs)
  #' @param m_c model historical control window, 1951-2005 (cfs)
  #' @param m_p model future window, 2006-2099 (cfs); finite, ordered by date
  #' @return list(mhat_p, mhat_c): corrected future + (diagnostic) historical
  oc <- o_c[is.finite(o_c)]
  mc <- m_c[is.finite(m_c)]
  stopifnot(length(oc) >= 30, length(mc) >= 30, all(is.finite(m_p)))
  fit <- MBC::QDM(o.c = oc, m.c = mc, m.p = m_p,
                  ratio = ratio, trace = trace, jitter.factor = jitter.factor)
  list(mhat_p = fit$mhat.p, mhat_c = fit$mhat.c)
}

correct_series <- function(series, obs_q,
                           calib_window  = CALIB_WINDOW,
                           future_window = FUTURE_WINDOW) {
  #' THE UNIT OF WORK (pure). Bias-correct one member's future window from an
  #' already-read daily series and an injected reference vector. No file I/O.
  #' @param series tibble(date, q_cfs) -- one member's full daily record
  #' @param obs_q  native gauge flow vector (o.c)
  #' @return tibble(date, q_raw, q_corrected) for the future window;
  #'   mhat_c (corrected historical) + mc (raw historical) attached as attrs
  mc     <- slice_years(series, calib_window)$q_cfs
  mp_tbl <- slice_years(series, future_window) %>%
    filter(is.finite(q_cfs)) %>%
    arrange(date)

  fit <- qdm_future(obs_q, mc, mp_tbl$q_cfs)

  result <- mp_tbl %>%
    transmute(date, q_raw = q_cfs, q_corrected = fit$mhat_p)
  attr(result, "mhat_c") <- fit$mhat_c
  attr(result, "mc")     <- mc[is.finite(mc)]
  result
}


# =============================================================================
# 4. I/O WRAPPER  (thin: read a file, delegate to the pure core)
# =============================================================================

correct_future_file <- function(path, obs_q, ...) {
  #' Read one member file and bias-correct it. (I/O = the read; math delegated)
  #' @param path  one member's UMAMC file
  #' @param obs_q native gauge reference vector (o.c), injected
  #' @param ...   passed to correct_series() (calib_window / future_window)
  #' @return correct_series() output
  read_umamc_streamflow(path) %>%
    correct_series(obs_q, ...)
}


# =============================================================================
# 5. ORCHESTRATION  (side effects isolated; the 172-file job as a map)
# =============================================================================

run_bias_correction <- function(members = list_future_members(),
                                obs_q   = read_native_gauge_reference()$q_cfs,
                                out_dir = BC_OUT_DIR, overwrite = FALSE) {
  #' Correct every future member -> one CSV each, with skip-existing resume and a
  #' factor-grid manifest. Declarative map over the members tibble; the augmented
  #' tibble IS the manifest. safely() keeps one bad member from aborting the run.
  #' @return the manifest tibble (invisibly)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # side-effecting worker: correct one member, write its CSV, return a status.
  correct_write <- function(path, out_path) {
    if (!overwrite && file.exists(out_path)) return("skipped")
    write_csv(correct_future_file(path, obs_q), out_path)
    "ok"
  }
  attempt <- safely(correct_write)

  manifest <- members %>%
    mutate(
      out_path = file.path(out_dir, sprintf("%s-BC.csv", member_id)),
      .result  = map2(path, out_path, attempt),
      status   = map_chr(.result, \(r) if (is.null(r$error)) r$result
                                       else paste0("ERROR: ", conditionMessage(r$error)))
    ) %>%
    mutate(.result = NULL)   # drop the list-col without select() (MASS masks it)

  write_csv(manifest, file.path(out_dir, "_bc_manifest.csv"))
  message(sprintf("Done: %s",
                  paste(names(table(manifest$status)), table(manifest$status),
                        sep = "=", collapse = "  ")))
  invisible(manifest)
}


# =============================================================================
# 6. SELF-CHECKS  (pure; reference injected -> no hidden reads)
# =============================================================================

qdm_change_preservation <- function(corr, probs = c(0.90, 0.95, 0.99, 0.995)) {
  #' QDM's defining property: the model's own future/historical change ratio must
  #' survive correction. raw = q(m.p)/q(m.c); corrected = q(mhat.p)/q(mhat.c).
  #' The two columns should match closely.
  mc     <- attr(corr, "mc")
  mhat_c <- attr(corr, "mhat_c")
  q <- function(x, p) quantile(x[is.finite(x)], p, type = 8, names = FALSE)
  tibble(
    prob             = probs,
    raw_change       = q(corr$q_raw, probs)       / q(mc, probs),
    corrected_change = q(corr$q_corrected, probs) / q(mhat_c, probs)
  )
}

qdm_bias_check <- function(corr, obs_q, probs = c(0.5, 0.9, 0.95, 0.99, 0.995)) {
  #' The plain-QM half of QDM: the corrected HISTORICAL window (mhat.c) should
  #' land on the gauge ruler (o.c). obs_q injected (no hidden read).
  mc     <- attr(corr, "mc")
  mhat_c <- attr(corr, "mhat_c")
  q <- function(x, p) quantile(x[is.finite(x)], p, type = 8, names = FALSE)
  tibble(prob      = probs,
         model_raw = q(mc, probs),
         corrected = q(mhat_c, probs),
         obs       = q(obs_q, probs))
}

future_shift_summary <- function(corr, probs = c(0.95, 0.99, 0.995, 0.999)) {
  #' The projected shift on the gauge ruler: corrected future vs corrected
  #' historical high-flow quantiles, plus days>=Q2 per year (the frequency lens).
  mhat_c     <- attr(corr, "mhat_c")
  q <- function(x, p) quantile(x[is.finite(x)], p, type = 8, names = FALSE)
  yrs <- function(d) as.numeric(diff(range(d))) / 365.25
  hist_years <- diff(CALIB_WINDOW) + 1
  bind_rows(
    tibble(quantity         = "days>=Q2 /yr",
           corrected_hist   = sum(mhat_c >= Q2_CFS, na.rm = TRUE) / hist_years,
           corrected_future = sum(corr$q_corrected >= Q2_CFS, na.rm = TRUE) /
             yrs(corr$date)),
    tibble(quantity         = sprintf("q%.1f%% (cfs)", probs * 100),
           corrected_hist   = q(mhat_c, probs),
           corrected_future = q(corr$q_corrected, probs))
  )
}


# =============================================================================
# 7. USAGE  (run interactively; nothing executes on source())
# =============================================================================
# members <- list_future_members()                 # 172 rows expected
# obs_q   <- read_native_gauge_reference()$q_cfs
#
# # single member -- same unit of work the batch maps, called once
# corr <- correct_future_file(members$path[1], obs_q)
# qdm_change_preservation(corr)      # raw vs corrected change -> should match
# qdm_bias_check(corr, obs_q)        # corrected historical -> should land on obs
# future_shift_summary(corr)         # projected shift (frequency + magnitude)
#
# # full ensemble (resumable; writes per-member CSV + _bc_manifest.csv)
# manifest <- run_bias_correction(members, obs_q)
# =============================================================================
