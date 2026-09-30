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
#   m.c = each member's historical control, everything it holds through 2005
#         (free-running GCM climate -> distributional frame, not day-for-day).
#         BRANCH A: full control period, chosen over the 1996-2005 gauge overlap
#         for tail robustness (m.c sets BOTH the bias and the change-ratio
#         denominator). Realized span is per-member and recorded in the
#         manifest: statistical 1950-2005, dynamical 1966-2005.
#   m.p = everything that member holds after 2005, corrected in ONE block:
#         statistical 2006-2099, dynamical 2011-2050.
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
#   - K-FACTOR (PresRat mean-change conservation) is not part of MBC::QDM, so it
#     is a separate post-correction step here (kfactor_by_era / apply_kfactor,
#     APPLY_K). Computed for every member-era and written to _bc_kfactors.csv
#     whether applied or not. Measured 2026-09-28 across all 172 under a SINGLE
#     era: median 0.995, range 0.937-1.017, 6 members beyond 5% of unity -- all
#     RCP8.5, five of them PRMS_P1, all K<1 (i.e. correction had inflated the
#     mean change). Within an era K is a UNIFORM multiplier, so its effect on
#     the downstream >=Q2 day counts is roughly 2.5x its own departure from 1;
#     it is not a cosmetic step for a threshold-based metric.
#   - K GRANULARITY is now an injected argument (`eras`), not a consequence of
#     the correction window: Pierce computes K per month AND per 30-year future
#     period, and the two tracks here have different projection spans, so each
#     track supplies its own era table. A single-row era table spanning the whole
#     projection reproduces the 2026-09-28 one-K-per-member behaviour exactly,
#     which makes the single-block case the degenerate case rather than a
#     separate code path.
#   - SINGLE BLOCK: m.p is corrected in one pass. Pierce segments the future into
#     30-year periods and ISIMIP3b into overlapping 36-year ones, both for
#     within-segment stationarity. QDM preserves a transient trend by
#     construction where PresRat does not, so segmenting is not required -- but
#     it is untested here.
#   - Metric threshold Q2 (5,542) is applied DOWNSTREAM (04c), not here; this
#     script corrects the full daily distribution.
#
# Reporting granularity (downstream, not here): corrected daily series are sliced
#   into century periods at the forcing step (PERIODS in 11). Those reporting
#   periods are NOT the same thing as the `eras` used for K here: PERIODS may
#   leave years untagged, whereas an era table must cover every projection day
#   or K is undefined for the gap. The QDM correction itself is still one pass
#   over the full projection block and is untouched by either slicing.
#
# Inputs:
#   - data_in/Umatilla_Future_Flows/*-UMAMC-streamflow-1.0.csv  (172 GCM members;
#     historical_livneh_* excluded -- those are 09's hindcast)
#   - data/dv_gage_daily_flows.csv   (native gauge reference, o.c; from 04a)
#
# Outputs (CSV per data-format standard; gitignored derived data). The `tag`
#   argument of run_bias_correction() names the product set; "BC" below is its
#   default. A variant run writes a parallel set under its own tag -- e.g.
#   tag = "BC-K-by-era" gives <member_id>-BC-K-by-era.csv plus
#   _bc-k-by-era_manifest.csv and _bc-k-by-era_kfactors.csv -- so the sets sit
#   side by side and stay comparable.
#   - data/Umatilla_Future_Flows_BC/<member_id>-BC.csv  (date, era, q_raw,
#     q_corrected). `era` travels with the series so the K that scaled any given
#     day is recoverable from the file itself.
#   - data/Umatilla_Future_Flows_BC/_bc_manifest.csv    (factor grid + status +
#     the REALIZED windows mc_start/mc_end/mc_n, mp_start/mp_end/mp_n, and the
#     K SUMMARY n_eras/k_min/k_max/k_applied. One row per member, unchanged in
#     shape -- 11 and gwl_windows.R join on it. The realized-window columns
#     exist because a window that silently did not fit a member was previously
#     undetectable from the output.)
#   - data/Umatilla_Future_Flows_BC/_bc_kfactors.csv    (LONG: one row per
#     member x era -- member_id, era, era_start, era_end, n_days, k. The per-era
#     values live here rather than in the manifest so the manifest stays one row
#     per member.)
#
# Reuse: source("scripts/09_bias_correction.R") for readers + config (09 runs
#   nothing on source). NB the shared single-job functions still physically live
#   in 09; extracting them into R/ modules is scoped separately
#   (NOTE_shared_module_refactor.md). Style: Tidyverse & FP guidelines; cfs
#   throughout. MBC pulls in MASS (masks dplyr::select) -> avoid select().
# =============================================================================

source("scripts/09_bias_correction.R")   # readers, Q2_CFS, MISSING_VALUE, dirs
source("scripts/eras.R")                 # ERAS_STATISTICAL, ERAS_DYNAMICAL

library(dplyr)
library(readr)
library(purrr)
library(MBC)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

SPLIT_YEAR <- 2005L   # last control year; everything after it is the projection.
                      # Deliberately NOT a pair of windows: with no outer bounds
                      # each member contributes the record it actually holds
                      # (statistical 1950-2099; dynamical 1966-2005 + 2011-2050),
                      # so a short record is never silently truncated by a window
                      # fitted to a longer one. The 2005/2006 split is unchanged.
APPLY_K    <- TRUE    # PresRat mean-change conservation (Pierce et al. 2015 s.3b)

# K-factor eras. Defined ONCE in scripts/eras.R and sourced above, because the
# same blocks are now the reporting periods in 11 and 12 as well (Byron,
# 2026-09-29: the correction eras are the master temporal logic). A second copy
# here is how the three stages drifted apart in the first place.
#
# ERAS_STATISTICAL is the default argument to correct_series() and
# run_bias_correction(), the 160-member case; ERAS_DYNAMICAL is passed
# explicitly by the dynamical runner. Both tables, and the reasoning behind each
# set of bounds, live in scripts/eras.R.

BC_OUT_DIR <- "data/Umatilla_Future_Flows_BC"

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

slice_period <- function(series, split_year, side = c("control", "future")) {
  #' The usable daily record on one side of the control/projection split. (pure)
  #' Unbounded on the outside by design -- see SPLIT_YEAR.
  #' @param series tibble(date, q_cfs), one member's full daily record
  #' @param split_year last calendar year belonging to the control block
  #' @param side "control" (year <= split_year) or "future" (year > split_year)
  #' @return tibble(date, q_cfs), finite values only, ordered by date
  side    <- match.arg(side)
  years   <- as.integer(format(series$date, "%Y"))
  in_side <- if (side == "control") years <= split_year else years > split_year
  series[in_side & is.finite(series$q_cfs), ] %>% arrange(date)
}

qdm_future <- function(o_c, m_c, m_p,
                       ratio = QDM_RATIO, trace = QDM_TRACE,
                       jitter.factor = QDM_JITTER) {
  #' Cannon (2015) Quantile Delta Mapping via MBC::QDM. (pure)
  #' Maps m.p onto the o.c ruler while preserving the m.p-vs-m.c change per
  #' quantile. o_c, m_c may carry NAs (dropped here); m_p MUST be finite and
  #' ordered by the caller (MBC::QDM returns mhat.p positionally).
  #' @param o_c observed calibration -- native gauge, full daily CDF (cfs)
  #' @param m_c model historical control block, through SPLIT_YEAR (cfs)
  #' @param m_p model projection block, after SPLIT_YEAR (cfs); finite, by date
  #' @return list(mhat_p, mhat_c): corrected future + (diagnostic) historical
  oc <- o_c[is.finite(o_c)]
  mc <- m_c[is.finite(m_c)]
  stopifnot(length(oc) >= 30, length(mc) >= 30, all(is.finite(m_p)))
  fit <- MBC::QDM(o.c = oc, m.c = mc, m.p = m_p,
                  ratio = ratio, trace = trace, jitter.factor = jitter.factor)
  list(mhat_p = fit$mhat.p, mhat_c = fit$mhat.c)
}

kfactor <- function(m_c, m_p, o_c, mhat_p) {
  #' PresRat mean-change conservation factor (Pierce et al. 2015 s.3b):
  #' K = <x> / <x_hat>, the GCM's change in mean flow divided by the change in
  #' mean flow that survived bias correction. K = 1 means quantile mapping
  #' already preserved the model's mean change; K < 1 means the correction
  #' inflated it. Reported per member whether or not it is applied.
  #' @param m_c,m_p model control and projection daily flows (cfs), finite
  #' @param o_c observed control daily flows (cfs); non-finite dropped here
  #' @param mhat_p bias-corrected projection daily flows (cfs), finite
  #' @return length-1 numeric
  model_change     <- mean(m_p)    / mean(m_c)
  corrected_change <- mean(mhat_p) / mean(o_c[is.finite(o_c)])
  model_change / corrected_change
}

assign_era <- function(dates, eras) {
  #' Label each date with the era whose calendar-year block contains it. (pure)
  #' Same non-equi join as tag_period() in 11, but with no tolerance for a gap:
  #' an unlabelled day would have no K, so an incomplete era table is an error
  #' here rather than an NA to be dropped downstream.
  #' @param dates Date vector
  #' @param eras tibble(era, y1, y2) -- calendar-year blocks, must cover `dates`
  #' @return character vector of era labels, parallel to `dates`
  labelled <- tibble(year = as.integer(format(dates, "%Y"))) %>%
    left_join(eras, by = join_by(between(year, y1, y2)))
  if (anyNA(labelled$era)) {
    stop(sprintf("era table leaves %d year(s) uncovered: %s",
                 n_distinct(labelled$year[is.na(labelled$era)]),
                 paste(sort(unique(labelled$year[is.na(labelled$era)])),
                       collapse = ", ")))
  }
  labelled$era
}

kfactor_by_era <- function(control_q, future, mhat_p, o_c, eras) {
  #' One K per era, from the single-era kfactor(). (pure)
  #' The control is the SAME for every era -- K asks how much of this member's
  #' change from its own control survived correction, so only the projection
  #' side is subset. Split-apply-combine over the era labels.
  #' @param control_q model control daily flows (cfs), finite
  #' @param future tibble(date, q_cfs) -- the projection block, ordered by date
  #' @param mhat_p bias-corrected projection daily flows (cfs), parallel to `future`
  #' @param o_c observed control daily flows (cfs)
  #' @param eras tibble(era, y1, y2)
  #' @return tibble(era, era_start, era_end, n_days, k), one row per era present
  tibble(date   = future$date,
         era    = assign_era(future$date, eras),
         m_p    = future$q_cfs,
         mhat_p = mhat_p) %>%
    summarise(era_start = min(date), era_end = max(date), n_days = n(),
              k = kfactor(control_q, m_p, o_c, mhat_p),
              .by = era) %>%
    arrange(era_start)
}

apply_kfactor <- function(corr) {
  #' Scale a corrected series by its era's K. (pure)
  #' Within an era K is a uniform multiplier: because it slides every day against
  #' a FIXED threshold, downstream exceedance counts move by more than K itself
  #' wherever the flow distribution is dense at that threshold.
  #' @param corr correct_series() output, carrying attr "k" (a per-era tibble)
  #' @return corr with q_corrected scaled; attributes preserved
  k <- attr(corr, "k")
  # Positional lookup rather than a join: left_join() would drop the "mhat_c",
  # "control" and "k" attributes the self-checks read back off this object.
  corr$q_corrected <- corr$q_corrected * k$k[match(corr$era, k$era)]
  corr
}

correct_series <- function(series, obs_q, eras = ERAS_STATISTICAL,
                           split_year = SPLIT_YEAR) {
  #' THE UNIT OF WORK (pure). Bias-correct one member's projection from an
  #' already-read daily series and an injected reference vector. No file I/O.
  #' K is computed here but NOT applied -- applying it is apply_kfactor()'s job.
  #' The QDM correction is one pass over the whole projection block regardless
  #' of `eras`; eras partition only the K step.
  #' @param series tibble(date, q_cfs) -- one member's full daily record
  #' @param obs_q  native gauge flow vector (o.c)
  #' @param eras tibble(era, y1, y2) -- K blocks; must cover the projection
  #' @param split_year last calendar year of the control block
  #' @return tibble(date, era, q_raw, q_corrected) for the projection; attrs
  #'   "mhat_c" (corrected control), "control" (raw control tibble), "k"
  #'   (per-era tibble from kfactor_by_era)
  control <- slice_period(series, split_year, "control")
  future  <- slice_period(series, split_year, "future")

  fit <- qdm_future(obs_q, control$q_cfs, future$q_cfs)

  result <- future %>%
    transmute(date, era = assign_era(date, eras),
              q_raw = q_cfs, q_corrected = fit$mhat_p)
  attr(result, "mhat_c")  <- fit$mhat_c
  attr(result, "control") <- control
  attr(result, "k")       <- kfactor_by_era(control$q_cfs, future,
                                            fit$mhat_p, obs_q, eras)
  result
}

describe_correction <- function(corr, k_applied) {
  #' One-row record of the window the correction ACTUALLY used. (pure)
  #' Exists because a realized window that differs from the intended one was
  #' previously invisible: the dynamical members ran on a 40-year control
  #' under a config that documented 55, and nothing reported it.
  #' K is summarised here, not enumerated: the per-era table rides along in the
  #' `k_table` list-column so the batch can write it out long, and the manifest
  #' itself stays one row per member (11 and gwl_windows.R join on it).
  #' @param corr correct_series() output
  #' @param k_applied was apply_kfactor() used on this member?
  #' @return one-row tibble for the manifest, with a k_table list-column
  control <- attr(corr, "control")
  k       <- attr(corr, "k")
  tibble(
    mc_start = min(control$date), mc_end = max(control$date), mc_n = nrow(control),
    mp_start = min(corr$date),    mp_end  = max(corr$date),   mp_n = nrow(corr),
    n_eras = nrow(k), k_min = min(k$k), k_max = max(k$k),
    k_applied = k_applied, status = "ok", k_table = list(k)
  )
}


# =============================================================================
# 4. I/O WRAPPER  (thin: read a file, delegate to the pure core)
# =============================================================================

correct_future_file <- function(path, obs_q, ...) {
  #' Read one member file and bias-correct it. (I/O = the read; math delegated)
  #' @param path  one member's UMAMC file
  #' @param obs_q native gauge reference vector (o.c), injected
  #' @param ...   passed to correct_series() (eras, split_year)
  #' @return correct_series() output
  read_umamc_streamflow(path) %>%
    correct_series(obs_q, ...)
}


# =============================================================================
# 5. ORCHESTRATION  (side effects isolated; the 172-file job as a map)
# =============================================================================

result_or_error <- function(r) {
  #' Unwrap one safely() result into a manifest row. (pure)
  #' @param r a safely() list(result, error)
  if (is.null(r$error)) r$result
  else tibble(status = paste0("ERROR: ", conditionMessage(r$error)))
}

run_bias_correction <- function(members = list_future_members(),
                                obs_q   = read_native_gauge_reference()$q_cfs,
                                eras    = ERAS_STATISTICAL,
                                out_dir = BC_OUT_DIR, tag = "BC",
                                sidecar_tag = tag, overwrite = FALSE,
                                split_year = SPLIT_YEAR, apply_k = APPLY_K) {
  #' Correct every future member -> one CSV each, with skip-existing resume, a
  #' factor-grid manifest and a long per-era K table. Declarative map over the
  #' members tibble; the augmented tibble IS the manifest. safely() keeps one bad
  #' member from aborting the run.
  #' `eras` defaults to the statistical table because that is the 160-member
  #' case; the dynamical track passes its own, paired with a filtered `members`.
  #' `tag` names the product set: it suffixes each member CSV and, by default,
  #' the two sidecars. Default "BC" reproduces the existing filenames exactly,
  #' so a variant run (a different era table, say) lands beside the current
  #' products instead of overwriting them, and the two can be compared without
  #' re-running either.
  #' `sidecar_tag` splits off the manifest and K-table names for the case where
  #' ONE product set is built by MORE THAN ONE run -- the tracks, which share a
  #' tag but need different era tables. Member CSVs are uniquely named per
  #' member so they coexist under one tag; the sidecars are single files and
  #' this function WRITES them, it does not append, so a second run under the
  #' same sidecar_tag would silently replace the first run's rows.
  #' @param members tibble from list_future_members(), optionally filtered to one track
  #' @param obs_q native gauge flow vector (o.c)
  #' @param eras tibble(era, y1, y2) -- K blocks covering this subset's projection
  #' @param tag product-set suffix, e.g. "BC" or "BC-K-by-era"
  #' @param sidecar_tag suffix for the manifest and K table; defaults to `tag`
  #' @return the manifest tibble (invisibly), without the k_table list-column
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # side-effecting worker: correct one member, write its CSV, return its row.
  correct_write <- function(path, out_path) {
    if (!overwrite && file.exists(out_path)) return(tibble(status = "skipped"))
    corr <- correct_future_file(path, obs_q, eras = eras, split_year = split_year)
    if (apply_k) corr <- apply_kfactor(corr)
    write_csv(corr, out_path)
    describe_correction(corr, apply_k)
  }

  out_paths   <- file.path(out_dir, sprintf("%s-%s.csv", members$member_id, tag))
  diagnostics <- map2(members$path, out_paths, safely(correct_write)) %>%
    map(result_or_error) %>%
    list_rbind()

  manifest <- bind_cols(mutate(members, out_path = out_paths), diagnostics)

  # The per-era K values, unnested to long form. Only "ok" rows carry a k_table;
  # a resume run in which every member was skipped produces no k_table column at
  # all, and leaves the existing sidecar alone rather than truncating it.
  if ("k_table" %in% names(manifest)) {
    kfactors <- manifest %>%
      filter(status == "ok") %>%
      mutate(k_table = map2(k_table, member_id,
                            ~ mutate(.x, member_id = .y, .before = 1))) %>%
      pull(k_table) %>%
      list_rbind()
    write_csv(kfactors,
              file.path(out_dir,
                        sprintf("_%s_kfactors.csv", tolower(sidecar_tag))))
  }
  # k_table is a list-column and cannot be written to CSV; the manifest keeps
  # only the n_eras / k_min / k_max summary of it.
  manifest <- mutate(manifest, k_table = NULL)
  write_csv(manifest,
            file.path(out_dir,
                      sprintf("_%s_manifest.csv", tolower(sidecar_tag))))
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
  mc     <- attr(corr, "control")$q_cfs
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
  mc     <- attr(corr, "control")$q_cfs
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
  # From the realized control, not a constant: the dynamical members' control is
  # 40 years, and a hard-coded 55 understated their historical days>=Q2 per year.
  hist_years <- yrs(attr(corr, "control")$date)
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
# # single member -- same unit of work the batch maps, called once.
# # NB list.files() sorts case-insensitively under this locale, so confirm which
# # member a path actually is before reasoning from its numbers.
# corr <- correct_future_file(members$path[1], obs_q, eras = ERAS_STATISTICAL)
# attr(corr, "k")                    # per-era K (computed, not applied)
# qdm_change_preservation(corr)      # raw vs corrected change -> should match
# qdm_bias_check(corr, obs_q)        # corrected historical -> should land on obs
# future_shift_summary(corr)         # projected shift (frequency + magnitude)
# corr_k <- apply_kfactor(corr)      # the K-scaled series, for comparison
#
# # The batch runs ONCE PER TRACK, because the era table differs between them.
# # overwrite = TRUE re-runs members that already have output; the previous
# # (one-K, 1951-start) products are archived in data/_pre_kfactor_20260928/.
# statistical <- filter(members, downscaling != "DYNAMICAL")
# manifest <- run_bias_correction(statistical, obs_q, ERAS_STATISTICAL,
#                                 overwrite = TRUE)
# count(manifest, status)
# reframe(), not summarise(): range() returns two values per group.
# manifest %>% reframe(across(c(mc_n, mp_n, n_eras), range), .by = downscaling)
# read_csv(file.path(BC_OUT_DIR, "_bc_kfactors.csv")) %>%
#   summarise(across(k, range), .by = era)
# =============================================================================