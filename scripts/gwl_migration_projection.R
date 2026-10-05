# =============================================================================
# gwl_migration_projection.R
# Umatilla River Discharge-Channel Migration Analysis
# Global Warming Level (GWL) track, step 3: the frozen migration model applied
#          at warming levels -> per-reach rate vs degC, as CHANGE and as
#          ABSOLUTE annual rate.
# =============================================================================
#
# Sibling to gwl_windows.R (step 1) and gwl_forcing_by_level.R (step 2). This is
# the warming-level counterpart of 12_migration_projection.R, which stays on the
# calendar-era axis and is NOT modified by this file.
#
# -----------------------------------------------------------------------------
# WHY THIS IS A SEPARATE SCRIPT AND NOT AN ARGUMENT TO 12
# -----------------------------------------------------------------------------
# SESSION_LOG_2026-09-29d §7 records that 12 "should not need changing" on this
# axis. Read rather than assumed (2026-09-29), that is WRONG, and the reason is
# structural, not cosmetic:
#
#   12 does its own binning. run_migration_projection() takes the PER-YEAR
#   forcing table and calls bin_forcing_to_normals(), which joins
#   between(water_year, y1, y2) -- on the year ALONE. An era is a global
#   calendar block: 2036-2065 means the same years for every member, so keying
#   on the year is sufficient. A warming-level window is not global. CCSM4
#   reaches 2 degC over 2024-2043 and MIROC5 over 2039-2058, so the block
#   boundaries are a property of (gcm, scenario) and cannot be written as a
#   normals table at all.
#
# Everything DOWNSTREAM of that binning is axis-agnostic: it consumes one object
# (member_period_forcing) plus an ordered label table, and never asks what the
# labels mean. So this script does not copy 12 -- it sources it and reuses its
# pure helpers, supplying the two things that genuinely differ: forcing already
# binned by warming level (step 2's product), and a level-ordered label table
# where 12 passes an era-ordered one.
#
# 12 runs nothing on source, so sourcing it is safe and is the documented way
# its runners use it.
#
# -----------------------------------------------------------------------------
# WHAT IS REUSED FROM 12, UNMODIFIED
# -----------------------------------------------------------------------------
#   out_paths, select_reach_slopes, select_reach_floors, historical_anchor,
#   apply_frozen_slopes, reach_historical_rates, add_absolute_rate,
#   summarise_ensemble_band, build_trajectory, median_forcing_by_cell,
#   build_whisker_design, whisker_half_widths, attach_whiskers, build_interval,
#   plot_trajectory, plot_rate_trajectory, plot_ensemble_violin, plot_raincloud,
#   ensemble_phrase, and the SCENARIO_* / FIG_* / PI_* constants.
#
# The model is the same frozen m_B2, the arithmetic is the same, and the figures
# are the same four. Only the x-axis differs.
#
# -----------------------------------------------------------------------------
# DECISIONS
# -----------------------------------------------------------------------------
# 1. t_norm = 20 ON EVERY LEVEL. Warming-level windows are 20 years on both
#    tracks (step 2 asserts it), so unlike the statistical eras (30/30/34) there
#    is one block length here. It is READ from the step-2 table rather than
#    declared, so it cannot drift from the thing that produced it.
#
# 2. THE OBSERVED POINT'S DIVISOR IS 20 ON BOTH TRACKS, and it is NOT the same
#    question as (1). The Observed point belongs to no level; its divisor
#    annualizes the model's per-interval intercept for the historical record.
#    SETTLED (Byron, 2026-10-05): on this axis every window is 20 years, which
#    is the AR6 convention the windows are published under, so the historical
#    anchor is annualized on the same basis as the levels it is plotted beside.
#    Stated as a literal in GWL_TRACKS rather than taken from scripts/eras.R,
#    because the eras.R constants answer the ERA-axis question and the
#    statistical one is deliberately 30 there (the statistical eras run
#    30/30/34, so there is no single block length to read and 30 is the honest
#    divisor on that axis -- see the "The observed point" block in eras.R).
#
#    CONSEQUENCE, needs a caption or methods line: the same observed record now
#    plots at a different height on the era and warming-level absolute-rate
#    figures (RS30: 8.29 ft/yr at 30, 8.88 at 20, both at F_hist = 3,465). Each
#    figure is internally consistent; the two cannot be read against each other
#    by eye. The change-vs-historical view is immune either way -- the divisor
#    cancels.
#
# 3. THE HISTORICAL ANCHOR COMES FROM 11's ANNUAL TABLE, not from step 2. F_hist
#    is the observed record's mean annual cum_excess and is IDENTICAL on both
#    tracks and both axes; gwl_forcing_by_level.R deliberately does not rebuild
#    it. So this script reads the same annual CSV 12 does, purely for its
#    observed rows.
#
# 4. LEVELS ARE PLOTTED AS DISCRETE SLOTS, not as a continuous degC axis. G1
#    (Byron, 2026-09-28): the published windows as published, four levels, not a
#    curve. 12's figures already treat the block as an ordered factor, so the
#    slots read "Observed, 1.5 degC, 2 degC, ..." with no change to the plotting
#    code.
#
# 5. n IS CARRIED PER LEVEL in the subtitle, not once for the run. Membership
#    varies by level -- RCP4.5 reaches 3 degC in only 2 GCMs of 10 -- so a single
#    "160 members" phrase would describe no level correctly. level_n_phrase()
#    counts from the data.
#
# Inputs : data/gwl_forcing_by_level_<suffix>.csv        (gwl_forcing_by_level.R)
#          data/future_forcing_annual_bc-k-by-era*.csv   (11b / 11c; F_hist only)
#          data/forcing_model_coefficients_cum_excess.csv (m_B2 coefficients)
#          data/forcing_model_cum_excess.rds              (m_B2 fitted object)
# Outputs: four CSVs and four figures per track, under a gwl- suffix.
# Style  : Tidyverse & FP guidelines; docs/lingua.md, docs/r-principles.md --
#          pure contracted helpers, I/O at the orchestrator boundary.
# =============================================================================

source("scripts/12_migration_projection.R")   # helpers + constants; runs nothing


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

# One entry per forward-modeling track. Tracks are never pooled into one
# ensemble summary (G6, Byron 2026-09-28): separate inputs, separate outputs.
# obs_window_years is stated per track -- see decision 2 in the header.
#
# RETIRED 2026-10-05 (Byron): the dynamical track is off the warming-level axis
# entirely -- no CSVs, no figures, no report rows. Its 40-year corrected record
# leaves three of five member-level windows truncated at the leading or trailing
# end, which is a no-start for a framing that depends on the window straddling
# the crossing year. The dynamical track is reported on the CALENDAR-ERA axis
# only (10c / 11c / 12c), untouched. Row kept as a comment so the inputs stay on
# the record.
GWL_TRACKS <- tibble::tribble(
  ~track,        ~level_csv,                                          ~annual_csv,                                           ~suffix,                     ~obs_window_years,
  "statistical", "data/gwl_forcing_by_level_bc-k-by-era.csv",           "data/future_forcing_annual_bc-k-by-era.csv",           "gwl-bc-k-by-era",           20L
  # "dynamical", "data/gwl_forcing_by_level_bc-k-by-era-dynamical.csv", "data/future_forcing_annual_bc-k-by-era-dynamical.csv", "gwl-bc-k-by-era-dynamical", 20L
)


# =============================================================================
# 2. HELPERS  (pure; I/O is in section 3)
# =============================================================================

level_label <- function(warming_level) {
  #' Purpose : the display label for a warming level.
  #' In      : warming_level, numeric vector (1.5, 2, 3, 4).
  #' Out     : character vector ("1.5 degC", "2 degC", ...).
  #' Decision: one label rule in one place, because the label is the join key
  #'   between the forcing table, the whisker table and the plot's slot order --
  #'   three places 12 keys on a character `period`. Trailing zeros are dropped
  #'   so 2 does not read as "2.0 degC" beside "1.5 degC".
  paste0(format(warming_level, trim = TRUE, drop0trailing = TRUE), " degC")
}

as_member_period_forcing <- function(level_forcing) {
  #' Purpose : map step 2's level summary onto the object 12's chain consumes.
  #' In      : level_forcing, a gwl_forcing_by_level.R table.
  #' Out     : tibble(member_id, gcm, scenario, downscaling, hydro, period,
  #'   t_norm, F_period) -- bin_forcing_to_normals()'s contract, plus gcm.
  #' Decision: the mapping is a RENAME, not a recomputation. F_period is 12's
  #'   name for a member's mean annual cum_excess in a block, which is exactly
  #'   mean_annual_cum_excess; total_cum_excess is not used here because 12
  #'   rescales the annual mean itself (cum_excess_k = t_norm * f_annual / 1000).
  #' Decision: gcm is carried through. 12's era path has no use for it, but the
  #'   level axis does -- membership varies by level and is reported per GCM.
  stopifnot(all(c("member_id", "gcm", "scenario", "downscaling", "hydro",
                  "warming_level", "t_norm",
                  "mean_annual_cum_excess") %in% names(level_forcing)))
  level_forcing %>%
    transmute(member_id, gcm, scenario, downscaling, hydro,
              period   = level_label(warming_level),
              t_norm   = as.integer(t_norm),
              F_period = mean_annual_cum_excess)
}

level_block_table <- function(member_period_forcing) {
  #' Purpose : the ordered block table 12's trajectory and plot helpers expect
  #'   where the era path passes as_period_table(ERAS_*).
  #' In      : member_period_forcing, from as_member_period_forcing().
  #' Out     : tibble(period, t_norm), ordered coldest level first.
  #' Decision: DERIVED from the forcing, not declared. A level with no member on
  #'   this track must not appear as an empty slot on its figures. (This mattered
  #'   most for the dynamical track, retired from this axis 2026-10-05; it still
  #'   guards the statistical track, where RCP4.5 reaches 3 degC in only 2 GCMs.)
  #' Decision: no y1/y2. Those exist for bin_forcing_to_normals(), which this
  #'   path never calls; everything downstream uses `period` for ordering and
  #'   `t_norm` for the interval scale. Stated because the era table has them.
  member_period_forcing %>%
    distinct(period, t_norm) %>%
    arrange(as.numeric(sub(" .*$", "", period)))
}

level_n_phrase <- function(member_period_forcing, track_label) {
  #' Purpose : the per-level membership line for a figure subtitle.
  #' In      : member_period_forcing; track_label ("statistical"/"dynamical").
  #' Out     : single character, e.g.
  #'   "statistical members per level: 1.5 degC 80 (10 GCMs); 2 degC 64 (8 GCMs)".
  #' Decision: counted from the data, never written into a string -- the same
  #'   failure 12's ensemble_phrase() was built to avoid, and it bites harder
  #'   here because membership CHANGES along the plotted axis (decision 5).
  per <- member_period_forcing %>%
    group_by(period) %>%
    summarise(n_members = dplyr::n_distinct(member_id),
              n_gcms    = dplyr::n_distinct(gcm),
              .groups   = "drop") %>%
    arrange(as.numeric(sub(" .*$", "", period)))
  sprintf("%s members per level: %s", track_label,
          paste(sprintf("%s %d (%d GCMs)", per$period, per$n_members, per$n_gcms),
                collapse = "; "))
}


# =============================================================================
# 3. ORCHESTRATION  (read, apply the frozen model, write)
# =============================================================================

run_gwl_projection <- function(level_csv, annual_csv, obs_window_years,
                               suffix, track_label,
                               coef_csv = COEF_CSV, model_rds = MODEL_RDS) {
  #' Purpose : project migration at warming levels for ONE track -- four CSVs and
  #'   four figures, the same products 12 writes on the era axis.
  #' In      : level_csv, step 2's per member x level forcing summary;
  #'   annual_csv, an 11 per-year table (observed rows only, for F_hist);
  #'   obs_window_years, the Observed point's divisor (stated, see header 2);
  #'   suffix, the product tag; track_label, for subtitles.
  #' Out     : list(member_rate, delta_band, abs_band, whiskers, f_hist,
  #'   reach_hist, blocks), invisibly.
  #' Decision: the binning step is the ONLY thing this orchestrator does
  #'   differently from run_migration_projection(). Forcing arrives binned, so
  #'   bin_forcing_to_normals() is never called and the era path is untouched.
  stopifnot(file.exists(level_csv), file.exists(annual_csv),
            file.exists(coef_csv), file.exists(model_rds),
            length(obs_window_years) == 1L, is.finite(obs_window_years),
            obs_window_years > 0)
  out <- out_paths(suffix)

  level_forcing <- read_csv(level_csv,  show_col_types = FALSE)
  annual        <- read_csv(annual_csv, show_col_types = FALSE)
  coef          <- read_csv(coef_csv,   show_col_types = FALSE)

  member_period_forcing <- as_member_period_forcing(level_forcing)
  blocks                <- level_block_table(member_period_forcing)
  stopifnot(nrow(member_period_forcing) > 0, nrow(blocks) > 0)

  reach_slopes <- select_reach_slopes(coef)
  f_hist       <- historical_anchor(annual)
  anchor_yr    <- as.integer(obs_window_years)
  reach_floors <- select_reach_floors(coef, anchor_yr)
  stopifnot(is.finite(f_hist), nrow(reach_slopes) > 0, nrow(reach_floors) > 0)

  scenarios <- sort(unique(member_period_forcing$scenario))

  # delta view (change vs historical) and absolute view (historical rate + delta)
  d_rate     <- apply_frozen_slopes(member_period_forcing, reach_slopes, f_hist)
  reach_hist <- reach_historical_rates(reach_floors, reach_slopes, f_hist)
  abs_member <- add_absolute_rate(d_rate, reach_hist)

  delta_band <- summarise_ensemble_band(d_rate,     d_rate_ft_yr)
  abs_band   <- summarise_ensemble_band(abs_member, abs_rate_ft_yr)

  write_csv(d_rate,     out$member)
  write_csv(delta_band, out$summary)
  write_csv(abs_band,   out$summary_abs)

  # Model-error whiskers at each cell's MEDIAN forcing, from the live model.
  model         <- read_rds(model_rds)
  forcing_cells <- median_forcing_by_cell(member_period_forcing)
  reach_levels  <- levels(model.frame(model)$river_segment)
  whisk_design  <- build_whisker_design(forcing_cells, f_hist, reach_levels,
                                        anchor_yr, scenarios)
  whiskers      <- whisker_half_widths(model, whisk_design, PI_LEVEL, PI_SEED)
  write_csv(whiskers, out$whiskers)

  delta_traj <- build_trajectory(delta_band, blocks)
  abs_traj   <- build_trajectory(abs_band,   blocks, hist_rate = reach_hist)
  abs_traj_w <- attach_whiskers(abs_traj, whiskers)

  ens  <- ensemble_phrase(member_period_forcing, track_label)
  npl  <- level_n_phrase(member_period_forcing, track_label)

  ggsave(out$plot_delta, plot_trajectory(
    delta_traj,
    y_lab         = "Change in migration rate vs historical (ft/yr)",
    plot_title    = "Projected change in channel migration rate by warming level",
    plot_subtitle = sprintf("Median + 10-90%% ensemble band.  %s.  Reaches RS28-37.", npl)),
    width = FIG_W, height = FIG_H, units = "in")

  ggsave(out$plot_abs, plot_rate_trajectory(
    abs_traj_w, blocks,
    y_lab         = "Migration rate (ft/yr)",
    plot_title    = "Projected channel migration rate by warming level (modeled)",
    plot_subtitle = paste(
      "Points = modeled median migration rate.  Bars = the model's 80% prediction interval: the 8-in-10 range for an actual measured rate at that forcing",
      "(fitted-coefficient, reach, unmeasured-period, and mapping error combined).  Band = 10-90% spread across the climate futures (which-future uncertainty).",
      sprintf("Observed = modeled rate at the historical forcing, annualized over %d yr.  %s.  Reaches RS28-37.",
              anchor_yr, npl),
      sep = "\n")),
    width = FIG_W, height = FIG_H, units = "in")

  ggsave(out$plot_violin, plot_ensemble_violin(
    d_rate,
    value         = d_rate_ft_yr,
    y_lab         = "Change in migration rate vs historical (ft/yr)",
    plot_title    = "Projected change in migration rate by warming level -- full ensemble distribution",
    plot_subtitle = sprintf(paste("Violin = member spread per level, split by RCP;",
                                  "points = members, bar = median.  %s.  Reaches RS28-37."), npl)),
    width = FIG_W, height = FIG_H, units = "in")

  ggsave(out$plot_rain, plot_raincloud(
    abs_member, whiskers, blocks,
    y_lab         = "Migration rate (ft/yr)",
    plot_title    = "Projected channel migration rate by warming level -- full ensemble distribution (modeled)",
    plot_subtitle = paste(
      sprintf("Shaded area = spread across the modeled future-flow projections (which-future uncertainty); %s.", ens),
      "Dots = the individual projections; point = ensemble median; vertical line = 80% model prediction error. Reaches RS28-37.",
      sep = "\n")),
    width = FIG_W, height = FIG_H, units = "in")

  message(sprintf("Wrote 4 CSVs and 4 figures for the %s GWL track (%s)",
                  track_label, suffix))

  invisible(list(member_rate = abs_member, delta_band = delta_band,
                 abs_band = abs_band, whiskers = whiskers, f_hist = f_hist,
                 reach_hist = reach_hist, blocks = blocks,
                 forcing = member_period_forcing))
}


# =============================================================================
# 4. BUILD  (both tracks; the only thing that runs on source)
# =============================================================================

gwl_proj <- purrr::pmap(GWL_TRACKS, function(track, level_csv, annual_csv,
                                             suffix, obs_window_years) {
  run_gwl_projection(level_csv, annual_csv, obs_window_years, suffix, track)
}) %>% setNames(GWL_TRACKS$track)


# =============================================================================
# 5. REPORT  (describe; do not conclude)
# =============================================================================

cat("\n=== 1. Run settings ===\n")
purrr::imap(gwl_proj, function(r, track) {
  tibble::tibble(track          = track,
                 f_hist         = round(r$f_hist),
                 obs_divisor_yr = GWL_TRACKS$obs_window_years[GWL_TRACKS$track == track],
                 levels         = paste(r$blocks$period, collapse = ", "),
                 block_t_norm   = paste(unique(r$blocks$t_norm), collapse = ", "))
}) %>% bind_rows() %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n    F_hist is the observed record's mean annual cum_excess. obs_divisor_yr\n",
    "   annualizes the Observed point only; it cancels in the change-vs-\n",
    "   historical view. It is 20, matching the level windows (settled\n",
    "   2026-10-05); the era-axis figures use 30 on the statistical track, so\n",
    "   Observed sits higher there.\n", sep = "")

cat("\n=== 2. Change vs historical at RS30 (ft/yr), median [p10, p90] ===\n")
purrr::imap(gwl_proj, function(r, track) {
  r$delta_band %>%
    filter(river_segment == 30) %>%
    transmute(track = track, scenario, level = period,
              median = round(median, 2), p10 = round(p10, 2), p90 = round(p90, 2))
}) %>% bind_rows() %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n    One reach, shown because it is the project's reference reach. The full\n",
    "   ten-reach tables are on disk; the figures carry all of them.\n", sep = "")

cat("\n=== 3. 80% model-error half-width (ft/yr), across reaches ===\n")
purrr::imap(gwl_proj, function(r, track) {
  r$whiskers %>%
    group_by(track = track, period, interval_years) %>%
    summarise(reaches = dplyr::n_distinct(river_segment),
              min     = round(min(whisker_half), 2),
              median  = round(median(whisker_half), 2),
              max     = round(max(whisker_half), 2),
              .groups = "drop")
}) %>% bind_rows() %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n    interval_years is the divisor: every level divides by 20, so unlike the\n",
    "   era axis no block reads narrower purely from its length. The Observed row\n",
    "   divides by its own track's divisor.\n", sep = "")
