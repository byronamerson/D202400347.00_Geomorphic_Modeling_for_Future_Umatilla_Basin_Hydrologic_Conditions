# =============================================================================
# 12_migration_projection.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 12 (projection Step 3): apply the frozen model of record to future forcing
#          -> per-reach migration rate by reporting period, as CHANGE and as
#             ABSOLUTE annual rate.
# =============================================================================
#
# Fit once, apply per period. The migration model is FIXED (m_B2, on the historical
# record); here we only APPLY its reach coefficients to each period's forcing. Two
# views come out of the same construction:
#
#   d rate (change vs historical):
#     d_rate = reach_slope * (F_period - F_hist) / 1000                 [ft/yr]
#     -- the per-interval intercept + baseline cancel in the delta.
#
#   Absolute annual rate (m_B2 prediction, annualized over the period):
#     rate  = floor_reach + reach_slope * F_period / 1000               [ft/yr]
#     floor_reach = baseline_per_year + reach_intercept / t_norm
#     -- baseline_per_year is the shared flood-independent background rate;
#        reach_intercept is a per-INTERVAL offset, so it is annualized over the
#        period length. The absolute rate is the delta trajectory shifted up per
#        reach by that reach's historical rate, so the two plots stay exactly
#        consistent (floor + reach_slope*F_hist cancels in the delta).
#     Convention settled with Byron 2026-09-08 (reach-specific floor).
#
#     F_period = member's mean annual cum_excess > 0.75xQ2 (cfs-days) in the period
#     F_hist   = observed record's mean annual cum_excess (the historical anchor)
#     /1000    = cfs-days -> the model's "per 1000 cfs-days" slope units
#
# t_norm IS A PROPERTY OF THE PERIOD TABLE (Byron, 2026-09-29), not a script
#   constant. It was `T_NORM <- 30L`, correct only while every reporting period was
#   a 30-year normal. It is now carried per period from the table, so a track with
#   20-year periods annualizes the intercept over 20. CONSEQUENCE, accepted: the
#   observed anchor is a modeled point too, so it sits HIGHER on a track with
#   shorter periods (RS30: 2.56 ft/yr at t_norm 30, 3.15 at 20). Internally
#   consistent within a track; the two tracks' absolute-rate figures cannot be read
#   against each other by eye. The delta view is unaffected -- the floor cancels.
#
# NOTHING RUNS ON SOURCE. This file defines the chain; a runner selects the track,
# its forcing table and its period table. Same shape as 10 / 11.
#   - scripts/12b_migration_projection_era_k.R            statistical, 160 members
#   - scripts/12c_migration_projection_era_k_dynamical.R  dynamical, 12 members
#
# Track selection happens UPSTREAM now: 11b / 11c each write their own forcing
#   table from their own bias-correction manifest, so the old
#   TRAJECTORY_DOWNSCALINGS filter is gone. A forcing table holds one track.
#
# Inputs : a per-year forcing table from 11b / 11c
#          data/forcing_model_coefficients_cum_excess.csv  (m_B2 coefficients)
#          data/forcing_model_cum_excess.rds               (m_B2 fitted object)
# Outputs: per-track, suffixed -- see out_paths().
# Style  : Tidyverse & FP guidelines (docs/lingua.md, docs/r-principles.md) --
#          pure contracted helpers, I/O at the orchestrator boundary.
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)
library(ggdist)     # stat_slab()/stat_dots() for the raincloud figure
library(merTools)   # predictInterval() for the model-error whiskers

source("scripts/eras.R")   # ERAS_STATISTICAL, ERAS_DYNAMICAL, OBS_WINDOW_YEARS_*,
                           # as_period_table()


# =============================================================================
# 1. CONFIGURATION  (track-invariant only; per-track settings are arguments)
# =============================================================================

COEF_CSV  <- "data/forcing_model_coefficients_cum_excess.csv"
MODEL_RDS <- "data/forcing_model_cum_excess.rds"

# --- Model-error whiskers (absolute-rate figure only) ---------------------------
# The client-facing absolute-rate figure carries a second uncertainty channel: the
# forward MODEL's own prediction error at each plotted (median) point, as an 80%
# error bar. It needs the LIVE fitted model (predictInterval), which the coefficient
# CSV cannot supply. See NOTE_model_error_whiskers_plan.md and explore/x17.
PI_LEVEL <- 0.80                # 80% bar -> matches the 10-90 ensemble footing
PI_SEED  <- 20260908L           # predictInterval draws are seeded (reproducible)

# Colorblind-safe scenario colors: ColorBrewer BrBG dark ends (CVD-safe).
# RCP4.5 = teal-green (cooler), RCP8.5 = rusty brown (warmer). The dynamical track
# is RCP8.5 only, so its figures use one lane -- unused values drop out.
SCENARIO_COLORS <- c(RCP45 = "#01665E", RCP85 = "#8C510A")
SCENARIO_LABELS <- c(RCP45 = "RCP4.5", RCP85 = "RCP8.5")
OBSERVED_LABEL  <- "Observed"     # discrete x-slot label for the historical anchor

# Ten-reach facet figures: 10 x 7.5 in, a standard 4:3 slide -- explicitly NOT the
# 13.3 widescreen (plotting_conventions.md, settled 2026-09-08).
FIG_W <- 10
FIG_H <- 7.5

# --- Reporting periods ---------------------------------------------------------
# NO TABLE IS DECLARED HERE. This step still owns its own binning -- it re-bins
# from the per-year forcing file rather than trusting the labels carried in it --
# but the blocks it bins to are now the bias-correction eras, defined once in
# scripts/eras.R and passed in by a runner through as_period_table().
#
# Why (Byron, 2026-09-29): the correction applies one multiplier per era and
# steps at an era boundary. While this step reported on 30-year normals that did
# not line up with those eras, two of the three reported periods straddled a step
# and so held two different corrections. On the shared blocks each reported
# period carries exactly one.
#
# Consequence to expect, arithmetic not hydrology: the statistical blocks are
# 30/30/34 years rather than three 30s. Block length does NOT enter the plotted
# rate -- the per-reach floor is built once from the observed-point divisor and
# added to every block alike -- but it DOES divide the model-error whisker, so
# the 2066-2099 bars run roughly 12% narrower than the other two purely from the
# longer window. Narrower there means "spread over more years", not "better
# pinned down"; say so in the caption if the figure is read closely.
#
# with_t_norm() lived here and in 11; as_period_table() replaces both copies.

out_paths <- function(suffix) {
  #' The eight output paths for one track. (pure)
  #' One naming rule in one place, so a track cannot half-overwrite another's
  #' products through a mistyped path in a runner.
  #' @param suffix product/track tag, e.g. "bc-k-by-era-dynamical"
  #' @return named list of paths
  list(
    member      = sprintf("data/migration_dArate_by_member_%s.csv", suffix),
    summary     = sprintf("data/migration_dArate_summary_%s.csv", suffix),
    summary_abs = sprintf("data/migration_rate_summary_%s.csv", suffix),
    whiskers    = sprintf("data/migration_whisker_half_widths_%s.csv", suffix),
    plot_delta  = sprintf("plots/migration_trajectory_%s.png", suffix),
    plot_abs    = sprintf("plots/migration_rate_trajectory_%s.png", suffix),
    plot_violin = sprintf("plots/migration_dArate_violin_%s.png", suffix),
    plot_rain   = sprintf("plots/migration_rate_raincloud_%s.png", suffix)
  )
}


# =============================================================================
# 2. HELPERS  (pure; each carries its boundary contract. I/O is in section 4.)
# =============================================================================

coef_value <- function(coef, term_name) {
  #' Pull a population-level (reach-independent) coefficient value.
  #' @param coef the model-coefficient table (forcing_var, term, river_segment, value).
  #' @param term_name e.g. "baseline_per_year", "population_slope".
  #' @return single numeric.
  coef %>% filter(term == term_name) %>% pull(value)
}

select_reach_slopes <- function(coef) {
  #' Per-reach flood slope (ft per 1000 cfs-days) from the model of record.
  #' @return tibble(river_segment <int>, reach_slope <dbl>).
  coef %>%
    filter(term == "reach_slope") %>%
    transmute(river_segment = as.integer(river_segment), reach_slope = value)
}

# anchor_t_norm() is GONE. It derived the observed point's divisor from the period
# table and errored on a mixed-length table rather than picking one -- correct
# while every block in use was the same length. The statistical eras are 30/30/34,
# so there is no single length to derive and the divisor is now STATED, per track,
# as OBS_WINDOW_YEARS_STATISTICAL / _DYNAMICAL in scripts/eras.R and passed to
# run_migration_projection() as obs_window_years. The guard's job is done by the
# argument being explicit; its reasoning moved to eras.R with the constants.

select_reach_floors <- function(coef, t_norm) {
  #' Per-reach baseline annual rate (the absolute-rate floor): the shared
  #' flood-independent background rate plus the reach's per-interval intercept
  #' annualized over the period length.
  #' @param coef model-coefficient table.
  #' @param t_norm period length in years (reach_intercept is per-interval).
  #' @return tibble(river_segment <int>, floor_reach <dbl>) in ft/yr.
  baseline <- coef_value(coef, "baseline_per_year")
  coef %>%
    filter(term == "reach_intercept") %>%
    transmute(river_segment = as.integer(river_segment),
              floor_reach   = baseline + value / t_norm)
}

historical_anchor <- function(annual) {
  #' Observed-record mean annual cum_excess -- the historical forcing baseline
  #' F_hist against which every period's change is measured. Carries the 2020
  #' record flood, so it is an honest (conservative) anchor, and carries
  #' flood-free water years as zeros (11's fill_flood_free_years(), Byron
  #' 2026-09-29) -- the mean is over the record's full span, not over its
  #' flood years only.
  #' @param annual per member x water-year forcing table (from 11), with a
  #'   `source` column tagging "observed" rows.
  #' @return single numeric (cfs-days/yr).
  annual %>%
    filter(source == "observed") %>%
    summarise(F = mean(cum_excess)) %>%
    pull(F)
}

bin_forcing_to_normals <- function(annual, normals) {
  #' Re-bin per-water-year future forcing to each reporting period and reduce to a
  #' per member x period mean annual cum_excess (F_period).
  #' The forcing table holds ONE track (11b / 11c wrote it from one manifest), so
  #' no downscaling filter is applied here -- that selection moved upstream.
  #' @param annual per member x water-year forcing (from 11b / 11c).
  #' @param normals tibble(period, y1, y2, t_norm).
  #' @return tibble(member_id, scenario, downscaling, hydro, period, t_norm, F_period).
  #' Decision: step 12 owns the binning, so drop any `period` / `t_norm` carried in
  #' from 11 (its own bins) before the join -- otherwise dplyr disambiguates the
  #' duplicated columns to .x/.y and downstream code breaks.
  annual %>%
    filter(source == "future") %>%
    select(-any_of(c("period", "t_norm"))) %>%
    left_join(normals, by = join_by(between(water_year, y1, y2))) %>%
    filter(!is.na(period)) %>%
    group_by(member_id, scenario, downscaling, hydro, period, t_norm) %>%
    summarise(F_period = mean(cum_excess), .groups = "drop")
}

apply_frozen_slopes <- function(member_period_forcing, reach_slopes, f_hist) {
  #' Apply the frozen reach slopes to each member x period forcing -> delta migration
  #' rate. Every reach is paired with every member x period (a cross join), then
  #' the fit-once slope is applied per period. The intercept + baseline cancel in
  #' the delta, so only the reach slope and the forcing change enter -- and the
  #' delta view is therefore indifferent to t_norm.
  #' @param member_period_forcing tibble from bin_forcing_to_normals().
  #' @param reach_slopes tibble(river_segment, reach_slope) from select_reach_slopes().
  #' @param f_hist historical anchor forcing (scalar, from historical_anchor()).
  #' @return tibble(... , river_segment, reach_slope, d_rate_ft_yr).
  member_period_forcing %>%
    cross_join(reach_slopes) %>%
    mutate(d_rate_ft_yr = reach_slope * (F_period - f_hist) / 1000)
}

reach_historical_rates <- function(reach_floors, reach_slopes, f_hist) {
  #' Absolute annual migration rate each reach would show at the historical
  #' forcing baseline -- the anchor the future rates climb from.
  #' @param reach_floors tibble(river_segment, floor_reach) from select_reach_floors().
  #' @param reach_slopes tibble(river_segment, reach_slope) from select_reach_slopes().
  #' @param f_hist historical anchor forcing (scalar).
  #' @return tibble(river_segment, hist_rate_ft_yr).
  reach_floors %>%
    left_join(reach_slopes, by = "river_segment") %>%
    transmute(river_segment, hist_rate_ft_yr = floor_reach + reach_slope * f_hist / 1000)
}

add_absolute_rate <- function(d_rate, reach_hist_rates) {
  #' Lift the delta rate to an absolute annual rate by adding each reach's historical
  #' rate (the floor cancels out of the delta, so absolute = historical + delta).
  #' @param d_rate tibble from apply_frozen_slopes().
  #' @param reach_hist_rates tibble from reach_historical_rates().
  #' @return d_rate + column abs_rate_ft_yr.
  d_rate %>%
    left_join(reach_hist_rates, by = "river_segment") %>%
    mutate(abs_rate_ft_yr = hist_rate_ft_yr + d_rate_ft_yr)
}

summarise_ensemble_band <- function(member_rate, value) {
  #' Pool the model-uncertainty axes into a per reach x scenario x period band.
  #' @param member_rate per member x reach x period rate table.
  #' @param value <data-masking> the rate column to summarise (d_rate_ft_yr or
  #'   abs_rate_ft_yr).
  #' @return tibble(river_segment, scenario, period, members, median, p10, p90).
  #' Note: quantile() rides its default type = 7 (linear interpolation) -- the
  #' plain, trackable choice; no reason here to depart from it.
  member_rate %>%
    group_by(river_segment, scenario, period) %>%
    summarise(members = dplyr::n(),
              median  = median({{ value }}),
              p10     = quantile({{ value }}, 0.10),
              p90     = quantile({{ value }}, 0.90),
              .groups = "drop")
}

build_trajectory <- function(band, normals, hist_rate = NULL) {
  #' Prepend the historical anchor so each scenario's climb starts at baseline,
  #' and order periods for plotting.
  #' @param band tibble from summarise_ensemble_band().
  #' @param normals tibble(period, ...) supplying the ordered period labels.
  #' @param hist_rate NULL for the delta view (historical = 0), or a
  #'   tibble(river_segment, hist_rate_ft_yr) for the absolute view.
  #' @return band + one historical row per reach x scenario, `period` a factor
  #'   ordered historical -> latest period.
  period_levels <- c("historical", normals$period)

  anchor <- distinct(band, river_segment, scenario)
  anchor <- if (is.null(hist_rate)) {
    mutate(anchor, value = 0)
  } else {
    anchor %>%
      left_join(hist_rate, by = "river_segment") %>%
      rename(value = hist_rate_ft_yr)
  }
  # Historical is a single modeled point (or zero) -- no member spread, so the
  # band pinches to the line there and fans out over the future periods.
  anchor <- anchor %>%
    transmute(river_segment, scenario, period = "historical",
              members = NA_integer_, median = value, p10 = value, p90 = value)

  band %>%
    bind_rows(anchor) %>%
    mutate(period = factor(period, levels = period_levels))
}

plot_trajectory <- function(traj, y_lab, plot_title, plot_subtitle, y_by = 10) {
  #' Migration-rate trajectory by reporting period, one panel per reach, RCP as
  #' color, 10-90% ensemble band as ribbon. (Delta view; the absolute view uses
  #' plot_rate_trajectory() below.)
  #' @param traj tibble from build_trajectory().
  #' @param y_lab,plot_title,plot_subtitle labels (differ for delta vs absolute view).
  #' @param y_by tick interval (ft/yr) for the shared y-axis.
  #' @return a ggplot object (caller handles ggsave -- I/O at the boundary).
  #' Decision: SHARED fixed y-axis (not free_y) so panel heights are comparable
  #' reach-to-reach -- the whole point is to read relative range. Limits are taken
  #' from the data (widest band drives the ceiling) and rounded out to the tick
  #' interval so nothing clips.
  y_top <- ceiling(max(traj$p90, na.rm = TRUE) / y_by) * y_by
  y_bot <- min(0, floor(min(traj$p10, na.rm = TRUE) / y_by) * y_by)

  ggplot(traj, aes(period, median, color = scenario, fill = scenario, group = scenario)) +
    geom_ribbon(aes(ymin = p10, ymax = p90), alpha = 0.18, color = NA) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.6) +
    facet_wrap(~ river_segment, nrow = 2,                          # 2x5 landscape
               labeller = as_labeller(\(x) paste0("RS", x))) +     # strips read "RS30"
    scale_color_manual(values = SCENARIO_COLORS, labels = SCENARIO_LABELS,
                       aesthetics = c("color", "fill")) +
    scale_y_continuous(breaks = seq(y_bot, y_top, by = y_by)) +
    coord_cartesian(ylim = c(y_bot, y_top)) +                      # clip-safe
    labs(x = NULL, y = y_lab, color = NULL, fill = NULL,
         title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "top")
}

plot_ensemble_violin <- function(member_rate, value, y_lab, plot_title, plot_subtitle,
                                 y_by = 10) {
  #' Full ensemble DISTRIBUTION per reach x period -- the "grid, not a crowd" view
  #' that the median+band trajectory summarises. Violins per period x RCP, the
  #' member cloud overlaid as points, and the median marked; faceted by reach.
  #' @param member_rate per member x reach x period rate table (future periods only).
  #' @param value <data-masking> rate column to show (d_rate_ft_yr or abs_rate_ft_yr).
  #' @param y_lab,plot_title,plot_subtitle labels.
  #' @param y_by tick interval (ft/yr) for the shared y-axis.
  #' @return a ggplot object (caller handles ggsave -- I/O at the boundary).
  #' Decision: violins scaled to equal width so shape reads even where a tail is
  #' long; shared fixed y-axis (2x5, RS strips) per the project plot convention.
  vals  <- dplyr::pull(member_rate, {{ value }})
  y_top <- ceiling(max(vals, na.rm = TRUE) / y_by) * y_by
  y_bot <- min(0, floor(min(vals, na.rm = TRUE) / y_by) * y_by)
  dodge <- position_dodge(width = 0.8)

  ggplot(member_rate, aes(period, {{ value }}, fill = scenario, color = scenario)) +
    geom_violin(position = dodge, alpha = 0.22, linewidth = 0.3,
                scale = "width", width = 0.8) +
    geom_point(position = position_jitterdodge(jitter.width = 0.12, dodge.width = 0.8),
               size = 0.35, alpha = 0.30, stroke = 0) +
    stat_summary(fun = median, fun.min = median, fun.max = median, geom = "crossbar",
                 position = dodge, width = 0.55, linewidth = 0.35, color = "grey15") +
    facet_wrap(~ river_segment, nrow = 2,
               labeller = as_labeller(\(x) paste0("RS", x))) +
    scale_color_manual(values = SCENARIO_COLORS, labels = SCENARIO_LABELS,
                       aesthetics = c("color", "fill")) +
    scale_y_continuous(breaks = seq(y_bot, y_top, by = y_by)) +
    coord_cartesian(ylim = c(y_bot, y_top)) +                      # display-clip only
    labs(x = NULL, y = y_lab, color = NULL, fill = NULL,
         title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "top")
}


# --- Model-error whiskers: helpers (pure) ---------------------------------------

median_forcing_by_cell <- function(member_period_forcing) {
  #' Median annual cum_excess per scenario x period across members, with the
  #' period's t_norm carried. Forcing is period-level (reach-independent), so the
  #' plotted median rate corresponds to this median forcing -- the anchor for the
  #' median point's OWN model-error width (option a: the point's error, not a
  #' per-member composite).
  #' @param member_period_forcing tibble from bin_forcing_to_normals().
  #' @return tibble(scenario, period, t_norm, f_annual_median) in cfs-days/yr.
  member_period_forcing %>%
    group_by(scenario, period, t_norm) %>%
    summarise(f_annual_median = median(F_period), .groups = "drop")
}

build_whisker_design <- function(forcing_cells, f_hist, reach_levels, anchor_yr,
                                 scenarios) {
  #' One predictInterval design row per reach x {future cell, observed anchor}.
  #' Forcing is placed on the model's interval-total scale (cum_excess_k =
  #' t_norm * annual / 1000, interval_years = t_norm) using EACH PERIOD'S OWN
  #' t_norm, and every `interval` label is a fresh, never-fitted level so
  #' predictInterval(new.levels="draw") injects the period variance. The observed
  #' anchor is a modeled point too, so it also draws an interval effect; it is
  #' emitted per scenario (identical value) to key onto the per-scenario
  #' trajectory rows, and takes the track's anchor t_norm.
  #' @param forcing_cells tibble(scenario, period, t_norm, f_annual_median).
  #' @param f_hist observed-record mean annual forcing (scalar).
  #' @param reach_levels model's river_segment factor levels (character).
  #' @param anchor_yr window length for the observed point (the track's
  #'   OBS_WINDOW_YEARS_* constant, in scripts/eras.R).
  #' @param scenarios scenarios present on this track.
  #' @return tibble(river_segment<fct>, interval<fct>, cum_excess_k, interval_years,
  #'   scenario, period).
  future_cells <- forcing_cells %>%
    transmute(scenario, period, t_norm, f_annual = f_annual_median)
  obs_cells <- tibble(scenario = scenarios, period = "historical",
                      t_norm = anchor_yr, f_annual = f_hist)
  bind_rows(future_cells, obs_cells) %>%
    tidyr::crossing(river_segment = reach_levels) %>%
    mutate(
      cum_excess_k   = t_norm * f_annual / 1000,   # interval-total, scaled to 1000s
      interval_years = t_norm,
      river_segment  = factor(river_segment, levels = reach_levels),
      interval       = factor(paste0("future_", period))   # never in the fit -> drawn
    )
}

whisker_half_widths <- function(model, design, level, seed) {
  #' 80% model-error half-widths per design row, annualized to ft/yr. Symmetric
  #' (linear-Gaussian PI), so we keep only the half-width -- the plotted point
  #' stays 12's deterministic median rate; predictInterval supplies "how wide,"
  #' not "where." merTools config settled 2026-09-08 (whiskers plan note):
  #' new.levels="draw" (future/observed interval unseen -> draw its effect),
  #' include.resid.var=TRUE (mapping/residual floor belongs in a PI),
  #' fix.intercept.variance left off (forbidden for out-of-sample groups).
  #' @param model the lmerMod model of record (cum_excess).
  #' @param design tibble from build_whisker_design().
  #' @param level PI width (0.80); seed integer seed for the draws.
  #' @return tibble(river_segment<int>, scenario, period, interval_years,
  #'   whisker_half<ft/yr>). interval_years is the divisor that annualized the
  #'   half-width, carried because the blocks are no longer one length: a longer
  #'   block yields a narrower bar for that reason alone.
  pi <- merTools::predictInterval(
    merMod = model, newdata = as.data.frame(design), which = "full",
    level = level, n.sims = 1000, stat = "median",
    type = "linear.prediction", include.resid.var = TRUE,
    new.levels = "draw", seed = seed)
  design %>%
    mutate(whisker_half = ((pi$upr - pi$lwr) / 2) / interval_years) %>%
    transmute(river_segment = as.integer(as.character(river_segment)),
              scenario, period, interval_years, whisker_half)
}

attach_whiskers <- function(traj, whiskers) {
  #' Add ymin/ymax (median +/- model-error half-width) to the absolute-rate
  #' trajectory; observed rows carry a whisker too (a modeled point). Joined on a
  #' character period key so traj's factor `period` matches whiskers' character key.
  #' @param traj tibble from build_trajectory().
  #' @param whiskers tibble from whisker_half_widths().
  #' @return traj + whisker_half, ymin, ymax.
  traj %>%
    mutate(.pkey = as.character(period)) %>%
    left_join(mutate(whiskers, .pkey = as.character(period)) %>%
                select(-period, -interval_years),
              by = c("river_segment", "scenario", ".pkey")) %>%
    select(-.pkey) %>%
    mutate(ymin = median - whisker_half, ymax = median + whisker_half)
}

build_interval <- function(member_rate, whiskers, period_levels) {
  #' Purpose : One row per reach x scenario x period -- the ensemble median and
  #'   its 80% model-prediction-error bounds -- the raincloud's interval channel.
  #' Inputs  : member_rate (abs_rate_ft_yr per member x reach x period); whiskers
  #'   (whisker_half_widths() output); period_levels (for factor ordering).
  #' Output  : tibble(river_segment, scenario, period<fct>, med, ymin, ymax).
  #' Decision: median(members) == rate at median forcing (rate is linear in
  #'   forcing), so the interval anchors exactly on the ensemble median.
  member_rate %>%
    group_by(river_segment, scenario, period) %>%
    summarise(med = median(abs_rate_ft_yr), .groups = "drop") %>%
    mutate(.rs = as.character(river_segment)) %>%
    inner_join(whiskers %>%
                 mutate(.rs = as.character(river_segment)) %>%
                 select(.rs, scenario, period, whisker_half),
               by = c(".rs", "scenario", "period")) %>%
    mutate(period = factor(period, levels = period_levels),
           ymin   = med - whisker_half,
           ymax   = med + whisker_half) %>%
    select(-.rs)
}

plot_raincloud <- function(member_rate, whiskers, normals, y_lab, plot_title,
                           plot_subtitle, y_by = 10,
                           dodge_w = 0.75, slab_scale = 0.55, dots_scale = 0.6) {
  #' Purpose : Absolute-rate ensemble distribution per reach x period as a
  #'   raincloud -- the "grid, not a crowd" companion to plot_rate_trajectory(),
  #'   with the model-error interval moved OFF the data so nothing is occluded.
  #'   Per reach x period x RCP lane, left to right: rain (individual projections,
  #'   stat_dots) -> interval (median + 80% model prediction error) -> cloud
  #'   (half-violin density, stat_slab).
  #' Inputs  : member_rate; whiskers; normals (period order); labels; layout knobs.
  #' Output  : a ggplot (caller does ggsave -- I/O at the boundary).
  #' Decisions: interval is plain geom_linerange + point on PRECOMPUTED model
  #'   error, NOT a ggdist interval stat (those summarise the members -- a
  #'   different, which-future quantity). slab normalize = "groups" == equal max
  #'   width per cell. dots overflow = "compress" keeps the dots inside the facet.
  period_levels <- normals$period
  member_rate   <- mutate(member_rate, period = factor(period, levels = period_levels))
  cell          <- build_interval(member_rate, whiskers, period_levels)
  dodge         <- position_dodge(width = dodge_w)

  vals  <- member_rate$abs_rate_ft_yr
  y_top <- ceiling(max(c(vals, cell$ymax), na.rm = TRUE) / y_by) * y_by
  y_bot <- min(0, floor(min(c(vals, cell$ymin), na.rm = TRUE) / y_by) * y_by)

  ggplot(member_rate, aes(period, abs_rate_ft_yr, fill = scenario, color = scenario)) +
    # cloud: half-violin density, opening right; equal max width per cell
    stat_slab(side = "right", scale = slab_scale, normalize = "groups",
              position = dodge, alpha = 0.35, linewidth = 0.25) +
    # rain: one dot per projection, piling left; compressed to stay in the facet
    stat_dots(side = "left", scale = dots_scale, position = dodge,
              binwidth = NA, overflow = "compress",
              color = NA, alpha = 0.55) +
    # interval: ensemble median + 80% model prediction error (thin, capless).
    # inherit.aes = FALSE: cell has no abs_rate_ft_yr, so map explicitly.
    geom_linerange(data = cell, inherit.aes = FALSE,
                   aes(x = period, ymin = ymin, ymax = ymax,
                       color = scenario, group = scenario),
                   position = dodge, linewidth = 0.55) +
    geom_point(data = cell, inherit.aes = FALSE,
               aes(x = period, y = med, fill = scenario, group = scenario),
               position = dodge, shape = 21, color = "grey20",
               size = 1.6, stroke = 0.3) +
    facet_wrap(~ river_segment, nrow = 2,
               labeller = as_labeller(\(x) paste0("RS", x))) +
    scale_fill_manual(values = SCENARIO_COLORS, labels = SCENARIO_LABELS, name = NULL) +
    scale_color_manual(values = SCENARIO_COLORS, labels = SCENARIO_LABELS, name = NULL,
                       guide = "none") +
    scale_y_continuous(breaks = seq(y_bot, y_top, by = y_by)) +
    coord_cartesian(ylim = c(y_bot, y_top)) +
    labs(x = NULL, y = y_lab, title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1),
          legend.position = "top",
          panel.grid.minor = element_blank(),
          plot.title = element_text(size = 12),
          plot.subtitle = element_text(size = 8, lineheight = 1.15))
}

plot_rate_trajectory <- function(traj, normals, y_lab, plot_title, plot_subtitle,
                                 y_by = 10) {
  #' Absolute migration-rate trajectory as a DISCRETE series of period solutions
  #' (Byron 2026-09-08): a categorical x of labeled slots (Observed + the periods),
  #' each point centered in its slot, slots separated by light vertical dividers,
  #' and a DASHED connector that reads as a trend aid, not a fitted curve. Two
  #' channels: the 10-90 ensemble band (which-future) as a translucent ribbon, and
  #' the 80% model-error whisker (how well-pinned each point is) as an error bar.
  #' @param traj tibble from attach_whiskers() (median, ymin, ymax, p10, p90).
  #' @param normals tibble(period, ...) supplying future slot order.
  #' @param y_lab,plot_title,plot_subtitle labels.
  #' @param y_by tick interval (ft/yr) for the shared y-axis.
  #' @return a ggplot object (caller handles ggsave -- I/O at the boundary).
  slot_levels <- c(OBSERVED_LABEL, normals$period)
  d <- traj %>%
    mutate(slot = factor(ifelse(period == "historical", OBSERVED_LABEL,
                                as.character(period)), levels = slot_levels))
  # Shared fixed y-axis: whiskers (ymax) and band (p90) both drive the ceiling.
  y_top <- ceiling(max(c(d$p90, d$ymax), na.rm = TRUE) / y_by) * y_by
  y_bot <- min(0, floor(min(c(d$p10, d$ymin), na.rm = TRUE) / y_by) * y_by)
  dodge <- position_dodge(width = 0.5)
  ggplot(d, aes(slot, median, color = scenario, fill = scenario, group = scenario)) +
    geom_vline(xintercept = seq(0.5, length(slot_levels) + 0.5, by = 1),
               color = "grey85", linewidth = 0.3) +               # slot dividers
    geom_ribbon(aes(ymin = p10, ymax = p90), alpha = 0.15, color = NA) +
    geom_line(linewidth = 0.7, linetype = "dashed", position = dodge) +  # trend aid
    geom_errorbar(aes(ymin = ymin, ymax = ymax), width = 0.18,
                  linewidth = 0.5, position = dodge) +
    geom_point(size = 1.7, position = dodge) +
    facet_wrap(~ river_segment, nrow = 2,
               labeller = as_labeller(\(x) paste0("RS", x))) +
    scale_color_manual(values = SCENARIO_COLORS, labels = SCENARIO_LABELS,
                       aesthetics = c("color", "fill")) +
    scale_y_continuous(breaks = seq(y_bot, y_top, by = y_by)) +
    coord_cartesian(ylim = c(y_bot, y_top)) +
    labs(x = NULL, y = y_lab, color = NULL, fill = NULL,
         title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1),
          legend.position = "top", panel.grid.major.x = element_blank(),
          plot.title = element_text(size = 12),
          plot.subtitle = element_text(size = 8, lineheight = 1.15))
}


# =============================================================================
# 3. SUBTITLE TEXT  (built from the run, not hardcoded to one track)
# =============================================================================

ensemble_phrase <- function(member_period_forcing, track_label) {
  #' "160 statistical members" / "12 dynamical members, RCP8.5 only" -- counted
  #' from the data rather than written into a string, which is how the old
  #' hardcoded "160 statistical members" survived into runs it did not describe.
  #' @return single character
  n   <- n_distinct(member_period_forcing$member_id)
  rcp <- sort(unique(member_period_forcing$scenario))
  sprintf("%d %s members (%s)", n, track_label,
          paste(SCENARIO_LABELS[rcp], collapse = " / "))
}


# =============================================================================
# 4. ORCHESTRATION  (validate + read inputs, apply the model, write outputs)
# =============================================================================

run_migration_projection <- function(annual_csv, normals, obs_window_years,
                                     suffix, track_label,
                                     coef_csv = COEF_CSV, model_rds = MODEL_RDS) {
  #' Project migration for ONE track: read its forcing table, apply the frozen
  #' model, write four CSVs and four figures.
  #' @param annual_csv per-year forcing table from 11b / 11c (one track).
  #' @param normals tibble(period, y1, y2, t_norm) -- this track's reporting
  #'   blocks, from as_period_table() on one of the era tables in scripts/eras.R.
  #' @param obs_window_years years to annualize the OBSERVED point over -- the
  #'   track's OBS_WINDOW_YEARS_* constant. Stated, not derived from `normals`,
  #'   because the statistical blocks are 30/30/34 and there is no single length
  #'   to derive. Required, so a track cannot inherit the wrong one by default.
  #' @param suffix product/track tag for the output names.
  #' @param track_label "statistical" / "dynamical", for figure subtitles.
  #' @return list(member_rate, delta_band, abs_band, whiskers), invisibly.
  stopifnot(file.exists(annual_csv), file.exists(coef_csv), file.exists(model_rds),
            all(c("period", "y1", "y2", "t_norm") %in% names(normals)),
            length(obs_window_years) == 1L, is.finite(obs_window_years),
            obs_window_years > 0)
  out <- out_paths(suffix)

  annual       <- read_csv(annual_csv, show_col_types = FALSE)
  coef         <- read_csv(coef_csv,   show_col_types = FALSE)
  reach_slopes <- select_reach_slopes(coef)
  f_hist       <- historical_anchor(annual)
  anchor_yr    <- as.integer(obs_window_years)
  reach_floors <- select_reach_floors(coef, anchor_yr)
  stopifnot(is.finite(f_hist), nrow(reach_slopes) > 0, nrow(reach_floors) > 0)

  member_period_forcing <- bin_forcing_to_normals(annual, normals)
  stopifnot(nrow(member_period_forcing) > 0)
  scenarios <- sort(unique(member_period_forcing$scenario))

  # delta view (change vs historical) and absolute view (historical rate + delta).
  d_rate     <- apply_frozen_slopes(member_period_forcing, reach_slopes, f_hist)
  reach_hist <- reach_historical_rates(reach_floors, reach_slopes, f_hist)
  abs_member <- add_absolute_rate(d_rate, reach_hist)

  delta_band <- summarise_ensemble_band(d_rate,     d_rate_ft_yr)
  abs_band   <- summarise_ensemble_band(abs_member, abs_rate_ft_yr)

  write_csv(d_rate,     out$member)
  write_csv(delta_band, out$summary)
  write_csv(abs_band,   out$summary_abs)

  # Model-error whiskers: 80% prediction-error half-width at each cell's MEDIAN
  # forcing (the plotted point's own error), from the live fitted model.
  model         <- read_rds(model_rds)
  forcing_cells <- median_forcing_by_cell(member_period_forcing)
  reach_levels  <- levels(model.frame(model)$river_segment)
  whisk_design  <- build_whisker_design(forcing_cells, f_hist, reach_levels,
                                        anchor_yr, scenarios)
  whiskers      <- whisker_half_widths(model, whisk_design, PI_LEVEL, PI_SEED)
  write_csv(whiskers, out$whiskers)

  delta_traj <- build_trajectory(delta_band, normals)
  abs_traj   <- build_trajectory(abs_band,   normals, hist_rate = reach_hist)
  abs_traj_w <- attach_whiskers(abs_traj, whiskers)

  ens <- ensemble_phrase(member_period_forcing, track_label)

  ggsave(out$plot_delta, plot_trajectory(
    delta_traj,
    y_lab         = "Change in migration rate vs historical (ft/yr)",
    plot_title    = "Projected change in channel migration rate by period",
    plot_subtitle = sprintf("Median + 10-90%% ensemble band, %s. Reaches RS28-37.", ens)),
    width = FIG_W, height = FIG_H, units = "in")

  ggsave(out$plot_abs, plot_rate_trajectory(
    abs_traj_w, normals,
    y_lab         = "Migration rate (ft/yr)",
    plot_title    = "Projected channel migration rate by period (modeled)",
    plot_subtitle = paste(
      "Points = modeled median migration rate.  Bars = the model's 80% prediction interval: the 8-in-10 range for an actual measured rate at that forcing",
      "(fitted-coefficient, reach, unmeasured-period, and mapping error combined).  Band = 10-90% spread across the climate futures (which-future uncertainty).",
      sprintf("Observed = modeled rate at the historical forcing.  %s.  Reaches RS28-37.", ens),
      sep = "\n")),
    width = FIG_W, height = FIG_H, units = "in")

  ggsave(out$plot_violin, plot_ensemble_violin(
    d_rate,
    value         = d_rate_ft_yr,
    y_lab         = "Change in migration rate vs historical (ft/yr)",
    plot_title    = "Projected change in channel migration rate -- full ensemble distribution",
    plot_subtitle = sprintf(paste("Violin = member spread per period, split by RCP;",
                                  "points = members, bar = median.  %s.  Reaches RS28-37."), ens)),
    width = FIG_W, height = FIG_H, units = "in")

  ggsave(out$plot_rain, plot_raincloud(
    abs_member, whiskers, normals,
    y_lab         = "Migration rate (ft/yr)",
    plot_title    = "Projected channel migration rate -- full ensemble distribution (modeled)",
    plot_subtitle = paste(
      sprintf("Shaded area = spread across the modeled future-flow projections (which-future uncertainty); %s.", ens),
      "Dots = the individual projections; point = ensemble median; vertical line = 80% model prediction error. Reaches RS28-37.",
      sep = "\n")),
    width = FIG_W, height = FIG_H, units = "in")

  message(sprintf("Wrote 4 CSVs and 4 figures for the %s track (%s)",
                  track_label, suffix))

  invisible(list(member_rate = abs_member, delta_band = delta_band,
                 abs_band = abs_band, whiskers = whiskers,
                 f_hist = f_hist, reach_hist = reach_hist))
}
