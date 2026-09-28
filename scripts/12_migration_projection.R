# =============================================================================
# 12_migration_projection.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 12 (projection Step 3): apply the frozen model of record to future forcing
#          -> per-reach migration rate by 30-year climate normal, as CHANGE and
#             as ABSOLUTE annual rate.
# =============================================================================
#
# Fit once, apply per period. The migration model is FIXED (m_B2, 08, on the
# historical record); here we only APPLY its reach coefficients to each period's
# forcing. Two views come out of the same construction:
#
#   d rate (change vs historical):
#     d_rate = reach_slope * (F_period - F_hist) / 1000                 [ft/yr]
#     -- the per-interval intercept + baseline cancel in the delta.
#
#   Absolute annual rate (m_B2 prediction, annualized over a 30-yr normal):
#     rate  = floor_reach + reach_slope * F_period / 1000               [ft/yr]
#     floor_reach = baseline_per_year + reach_intercept / T_NORM
#     -- baseline_per_year is the shared flood-independent background rate;
#        reach_intercept is a per-INTERVAL offset, so it is annualized over the
#        normal length (T_NORM = 30). The absolute rate is the delta trajectory
#        shifted up per reach by that reach's historical rate, so the two plots
#        stay exactly consistent (floor + reach_slope*F_hist cancels in the delta).
#     Convention settled with Byron 2026-09-08 (reach-specific floor).
#
#     F_period = member's mean annual cum_excess > 0.75xQ2 (cfs-days) in the period
#     F_hist   = observed record's mean annual cum_excess (the historical anchor)
#     /1000    = cfs-days -> the model's "per 1000 cfs-days" slope units
#
# Grain: three 30-year climate normals (2010-2039, 2040-2069, 2070-2099) + the
# observed baseline. Trajectory anchored on the 160 full-century members
# (BCSD+MACA); the 12 dynamical/WRF members stop ~2069 (composition would drift).
# Ensemble handling: RCP = two reported cases; the other axes pool into a
# median + 10/90 band.
#
# Inputs : data/future_forcing_annual_by_period.csv        (per-year forcing, from 11)
#          data/forcing_model_coefficients_cum_excess.csv  (m_B2 coefficients, from 08)
#          data/forcing_model_cum_excess.rds               (m_B2 fitted object, from 08)
# Outputs: data/migration_dArate_by_member.csv    (reach x member x period, delta)
#          data/migration_dArate_summary.csv      (reach x scenario x period, delta band)
#          data/migration_rate_summary.csv        (reach x scenario x period, absolute band)
#          plots/migration_trajectory.png         (delta vs historical)
#          plots/migration_rate_trajectory.png    (absolute annual rate + model-error whiskers)
# Style  : Tidyverse & FP guidelines (docs/lingua.md, docs/r-principles.md) --
#          pure contracted helpers, I/O at the orchestrator boundary.
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(ggplot2)
library(ggdist)     # stat_slab()/stat_dots() for the raincloud figure
library(merTools)   # predictInterval() for the model-error whiskers


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

ANNUAL_CSV      <- "data/future_forcing_annual_by_period.csv"
COEF_CSV        <- "data/forcing_model_coefficients_cum_excess.csv"
OUT_MEMBER      <- "data/migration_dArate_by_member.csv"
OUT_SUMMARY     <- "data/migration_dArate_summary.csv"
OUT_SUMMARY_ABS <- "data/migration_rate_summary.csv"
OUT_PLOT        <- "plots/migration_trajectory.png"
OUT_PLOT_ABS    <- "plots/migration_rate_trajectory.png"
OUT_PLOT_VIOLIN <- "plots/migration_dArate_violin.png"
OUT_PLOT_RAINCLOUD <- "plots/migration_rate_raincloud.png"  # abs-rate raincloud (12c, folded in)

# Three 30-year climate normals (the settled grain). Config-driven: change the
# table, nothing else. Windows are contiguous and share no boundary year, so the
# inclusive between()-join below tags each water year to exactly one normal.
NORMALS <- tribble(
  ~period,       ~y1,    ~y2,
  "2010-2039",   2010L,  2039L,
  "2040-2069",   2040L,  2069L,
  "2070-2099",   2070L,  2099L
)

# Trajectory ensemble = the statistical downscalings (full-century, constant set).
# Dynamical members stop ~2069, so including them would change ensemble
# composition between the near/mid and late normals.
TRAJECTORY_DOWNSCALINGS <- c("BCSD", "MACA")

# Normal length (years). Annualizes the per-interval reach_intercept for the
# absolute-rate floor; the projection periods ARE 30-yr normals, so this is the
# correct divisor, not an arbitrary one.
T_NORM <- 30L

# --- Model-error whiskers (absolute-rate figure only) ---------------------------
# The client-facing absolute-rate figure carries a second uncertainty channel: the
# forward MODEL's own prediction error at each plotted (median) point, as an 80%
# error bar. It needs the LIVE fitted model (predictInterval), which the coefficient
# CSV cannot supply -- 08 now also saves the merMod as .rds. See
# NOTE_model_error_whiskers_plan.md and explore/x17 (widths sanity check).
MODEL_RDS <- "data/forcing_model_cum_excess.rds"
PI_LEVEL  <- 0.80                # 80% bar -> matches the 10-90 ensemble footing
PI_SEED   <- 20260908L           # predictInterval draws are seeded (reproducible)

# Colorblind-safe scenario colors: ColorBrewer BrBG dark ends (CVD-safe).
# RCP4.5 = teal-green (cooler), RCP8.5 = rusty brown (warmer).
SCENARIO_COLORS <- c(RCP45 = "#01665E", RCP85 = "#8C510A")
OBSERVED_LABEL  <- "Observed"     # discrete x-slot label for the historical anchor


# =============================================================================
# 2. HELPERS  (pure; each carries its boundary contract. I/O is in section 3.)
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

select_reach_floors <- function(coef, t_norm) {
  #' Per-reach baseline annual rate (the absolute-rate floor): the shared
  #' flood-independent background rate plus the reach's per-interval intercept
  #' annualized over the normal length.
  #' @param coef model-coefficient table.
  #' @param t_norm normal length in years (reach_intercept is per-interval).
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
  #' record flood, so it is an honest (conservative) anchor.
  #' @param annual per member x water-year forcing table (from 11), with a
  #'   `source` column tagging "observed" rows.
  #' @return single numeric (cfs-days/yr).
  annual %>%
    filter(source == "observed") %>%
    summarise(F = mean(cum_excess)) %>%
    pull(F)
}

bin_forcing_to_normals <- function(annual, normals, downscalings) {
  #' Re-bin per-water-year future forcing to each 30-year normal and reduce to a
  #' per member x period mean annual cum_excess (F_period).
  #' @param annual per member x water-year forcing (from 11).
  #' @param normals tibble(period, y1, y2) defining the 30-yr windows.
  #' @param downscalings character vector of downscalings to keep (constant-set
  #'   trajectory ensemble).
  #' @return tibble(member_id, scenario, downscaling, hydro, period, F_period).
  #' Decision: step 12 owns the binning, so drop any stale `period` carried in
  #' from 11 (its old bins) before the join -- otherwise dplyr disambiguates the
  #' two `period` columns to period.x/period.y and downstream code breaks.
  annual %>%
    filter(source == "future", downscaling %in% downscalings) %>%
    select(-any_of("period")) %>%
    left_join(normals, by = join_by(between(water_year, y1, y2))) %>%
    filter(!is.na(period)) %>%
    group_by(member_id, scenario, downscaling, hydro, period) %>%
    summarise(F_period = mean(cum_excess), .groups = "drop")
}

apply_frozen_slopes <- function(member_period_forcing, reach_slopes, f_hist) {
  #' Apply the frozen reach slopes to each member x period forcing -> delta migration
  #' rate. Every reach is paired with every member x period (a cross join), then
  #' the fit-once slope is applied per period. The intercept + baseline cancel in
  #' the delta, so only the reach slope and the forcing change enter.
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
  #'   tibble(river_segment, hist_rate_ft_yr) for the absolute view (historical =
  #'   each reach's modeled rate at F_hist, with no ensemble spread).
  #' @return band + one historical row per reach x scenario, `period` a factor
  #'   ordered historical -> latest normal.
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
  # band pinches to the line there and fans out over the future normals.
  anchor <- anchor %>%
    transmute(river_segment, scenario, period = "historical",
              members = NA_integer_, median = value, p10 = value, p90 = value)

  band %>%
    bind_rows(anchor) %>%
    mutate(period = factor(period, levels = period_levels))
}

plot_trajectory <- function(traj, y_lab, plot_title, plot_subtitle, y_by = 10) {
  #' Migration-rate trajectory by climate normal, one panel per reach, RCP as
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
    facet_wrap(~ river_segment, nrow = 2,                          # 2x5 landscape -> fits a standard 4:3 slide
               labeller = as_labeller(\(x) paste0("RS", x))) +     # fixed scales -> comparable; strips read "RS30"
    scale_color_manual(values = c(RCP45 = "#01665E", RCP85 = "#8C510A"),
                       aesthetics = c("color", "fill")) +
    scale_y_continuous(breaks = seq(y_bot, y_top, by = y_by)) +
    coord_cartesian(ylim = c(y_bot, y_top)) +                      # clip-safe: limits enclose all data
    labs(x = NULL, y = y_lab, color = NULL, fill = NULL,
         title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "top")
}


plot_ensemble_violin <- function(member_rate, value, y_lab, plot_title, plot_subtitle,
                                 y_by = 10) {
  #' Full ensemble DISTRIBUTION per reach x period -- the "grid, not a crowd" view
  #' that the median+band trajectory summarises. Two violins per period (one per
  #' RCP), the member cloud overlaid as points, and the median marked; faceted by
  #' reach. Shows skew and tails the ribbon hides.
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
    scale_color_manual(values = c(RCP45 = "#01665E", RCP85 = "#8C510A"),
                       aesthetics = c("color", "fill")) +
    scale_y_continuous(breaks = seq(y_bot, y_top, by = y_by)) +
    coord_cartesian(ylim = c(y_bot, y_top)) +                      # display-clip only; violins use full data
    labs(x = NULL, y = y_lab, color = NULL, fill = NULL,
         title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "top")
}


build_interval <- function(member_rate, whiskers, period_levels) {
  #' Purpose : One row per reach x scenario x period -- the ensemble median and
  #'   its 80% model-prediction-error bounds -- the raincloud's interval channel.
  #' Inputs  : member_rate (abs_rate_ft_yr per member x reach x period); whiskers
  #'   (whisker_half_widths() output, model-error half-widths in ft/yr);
  #'   period_levels (character, for factor ordering of period).
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
  #'   (half-violin density, stat_slab). Two RCP lanes per period, dodged.
  #' Inputs  : member_rate (abs_rate_ft_yr per member x reach x period, with
  #'   scenario + period); whiskers (whisker_half_widths() output); normals
  #'   (tibble(period, ...) giving period order); labels; y_by tick interval;
  #'   dodge_w/slab_scale/dots_scale layout knobs.
  #' Output  : a ggplot (caller does ggsave -- I/O at the boundary).
  #' Decisions: interval is plain geom_linerange + point on PRECOMPUTED model
  #'   error, NOT a ggdist interval stat (those summarise the members -- a
  #'   different, which-future quantity). slab normalize = "groups" == equal max
  #'   width per cell (the settled scale = "width" convention). dots
  #'   overflow = "compress" keeps ~80 dots inside the narrow facet.
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
    # interval: ensemble median + 80% model prediction error (thin, capless),
    # dodged onto each RCP lane's spine. inherit.aes = FALSE: cell has no
    # abs_rate_ft_yr, so map its aesthetics explicitly.
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
    scale_fill_manual(values = SCENARIO_COLORS,
                      labels = c(RCP45 = "RCP4.5", RCP85 = "RCP8.5"), name = NULL) +
    scale_color_manual(values = SCENARIO_COLORS,
                       labels = c(RCP45 = "RCP4.5", RCP85 = "RCP8.5"), name = NULL,
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


# --- Model-error whiskers: helpers (pure) ---------------------------------------

median_forcing_by_cell <- function(member_period_forcing) {
  #' Median annual cum_excess per scenario x period across trajectory members.
  #' Forcing is period-level (reach-independent), so the plotted median rate
  #' corresponds to this median forcing -- the anchor for the median point's OWN
  #' model-error width (option a: the point's error, not a per-member composite).
  #' @param member_period_forcing tibble from bin_forcing_to_normals().
  #' @return tibble(scenario, period, f_annual_median) in cfs-days/yr.
  member_period_forcing %>%
    group_by(scenario, period) %>%
    summarise(f_annual_median = median(F_period), .groups = "drop")
}

build_whisker_design <- function(forcing_cells, f_hist, reach_levels, t_norm) {
  #' One predictInterval design row per reach x {future cell, observed anchor}.
  #' Forcing is placed on the model's interval-total scale (cum_excess_k =
  #' t_norm * annual / 1000, interval_years = t_norm), and every `interval` label
  #' is a fresh, never-fitted level so predictInterval(new.levels="draw") injects
  #' the period variance. The observed anchor is a modeled point too, so it also
  #' draws an interval effect; emitted per scenario (identical value) to key onto
  #' the per-scenario trajectory rows.
  #' @param forcing_cells tibble(scenario, period, f_annual_median).
  #' @param f_hist observed-record mean annual forcing (scalar).
  #' @param reach_levels model's river_segment factor levels (character).
  #' @param t_norm normal length (yr).
  #' @return tibble(river_segment<fct>, interval<fct>, cum_excess_k, interval_years,
  #'   scenario, period).
  future_cells <- forcing_cells %>%
    transmute(scenario, period, f_annual = f_annual_median)
  obs_cells <- tibble(scenario = names(SCENARIO_COLORS),
                      period = "historical", f_annual = f_hist)
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
  #' @return tibble(river_segment<int>, scenario, period, whisker_half<ft/yr>).
  pi <- merTools::predictInterval(
    merMod = model, newdata = as.data.frame(design), which = "full",
    level = level, n.sims = 1000, stat = "median",
    type = "linear.prediction", include.resid.var = TRUE,
    new.levels = "draw", seed = seed)
  design %>%
    mutate(whisker_half = ((pi$upr - pi$lwr) / 2) / interval_years) %>%
    transmute(river_segment = as.integer(as.character(river_segment)),
              scenario, period, whisker_half)
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
    left_join(mutate(whiskers, .pkey = as.character(period)) %>% select(-period),
              by = c("river_segment", "scenario", ".pkey")) %>%
    select(-.pkey) %>%
    mutate(ymin = median - whisker_half, ymax = median + whisker_half)
}

plot_rate_trajectory <- function(traj, normals, y_lab, plot_title, plot_subtitle,
                                 y_by = 10) {
  #' Absolute migration-rate trajectory as a DISCRETE series of period solutions
  #' (Byron 2026-09-08): a categorical x of labeled slots (Observed + the three
  #' normals), each point centered in its slot, slots separated by light vertical
  #' dividers, and a DASHED connector that reads as a trend aid, not a fitted
  #' curve. Two channels: the 10-90 ensemble band (which-future) as a translucent
  #' ribbon, and the 80% model-error whisker (how well-pinned each point is) as an
  #' error bar. RCP as CVD-safe BrBG color.
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
    geom_line(linewidth = 0.7, linetype = "dashed", position = dodge) +  # trend aid, not a curve
    geom_errorbar(aes(ymin = ymin, ymax = ymax), width = 0.18,
                  linewidth = 0.5, position = dodge) +
    geom_point(size = 1.7, position = dodge) +
    facet_wrap(~ river_segment, nrow = 2,
               labeller = as_labeller(\(x) paste0("RS", x))) +
    scale_color_manual(values = SCENARIO_COLORS, aesthetics = c("color", "fill")) +
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
# 3. ORCHESTRATION  (validate + read inputs, apply the model, write outputs)
# =============================================================================

# Validation at the boundary -- helpers below trust their inputs.
stopifnot(file.exists(ANNUAL_CSV), file.exists(COEF_CSV), file.exists(MODEL_RDS))

annual       <- read_csv(ANNUAL_CSV, show_col_types = FALSE)
coef         <- read_csv(COEF_CSV,   show_col_types = FALSE)
reach_slopes <- select_reach_slopes(coef)
reach_floors <- select_reach_floors(coef, T_NORM)
f_hist       <- historical_anchor(annual)
stopifnot(is.finite(f_hist), nrow(reach_slopes) > 0, nrow(reach_floors) > 0)

member_period_forcing <- bin_forcing_to_normals(annual, NORMALS, TRAJECTORY_DOWNSCALINGS)

# delta view (change vs historical) and absolute view (historical rate + delta).
d_rate       <- apply_frozen_slopes(member_period_forcing, reach_slopes, f_hist)
reach_hist   <- reach_historical_rates(reach_floors, reach_slopes, f_hist)
abs_member   <- add_absolute_rate(d_rate, reach_hist)

delta_band <- summarise_ensemble_band(d_rate,     d_rate_ft_yr)
abs_band   <- summarise_ensemble_band(abs_member, abs_rate_ft_yr)

write_csv(d_rate,     OUT_MEMBER)
write_csv(delta_band, OUT_SUMMARY)
write_csv(abs_band,   OUT_SUMMARY_ABS)

cat("\n=== delta migration rate (ft/yr) vs historical, ensemble median [p10, p90] ===\n")
cat(sprintf("(historical anchor F_hist = %s cfs-days/yr; %d statistical members)\n",
            format(round(f_hist), big.mark = ","),
            n_distinct(member_period_forcing$member_id)))
delta_band %>%
  mutate(across(c(median, p10, p90), ~ round(.x, 2))) %>%
  arrange(river_segment, scenario, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n=== Absolute migration rate (ft/yr), historical baseline per reach ===\n")
reach_hist %>%
  mutate(hist_rate_ft_yr = round(hist_rate_ft_yr, 2)) %>%
  arrange(river_segment) %>%
  as.data.frame() %>% print(row.names = FALSE)

delta_traj <- build_trajectory(delta_band, NORMALS)
abs_traj   <- build_trajectory(abs_band,   NORMALS, hist_rate = reach_hist)

# Model-error whiskers for the absolute-rate figure: 80% prediction-error half-
# width at each cell's MEDIAN forcing (the plotted point's own error), from the
# live fitted model. See NOTE_model_error_whiskers_plan.md and explore/x17.
model         <- read_rds(MODEL_RDS)
forcing_cells <- median_forcing_by_cell(member_period_forcing)
reach_levels  <- levels(model.frame(model)$river_segment)
whisk_design  <- build_whisker_design(forcing_cells, f_hist, reach_levels, T_NORM)
whiskers      <- whisker_half_widths(model, whisk_design, PI_LEVEL, PI_SEED)
abs_traj_w    <- attach_whiskers(abs_traj, whiskers)

ggsave(OUT_PLOT, plot_trajectory(
  delta_traj,
  y_lab        = "Change in migration rate vs historical (ft/yr)",
  plot_title   = "Projected change in channel migration rate by climate normal",
  plot_subtitle = "Median + 10-90% ensemble band, 160 statistical members. Reaches RS28-37."),
  width = 13, height = 7.5, units = "in")

ggsave(OUT_PLOT_ABS, plot_rate_trajectory(
  abs_traj_w, NORMALS,
  y_lab        = "Migration rate (ft/yr)",
  plot_title   = "Projected channel migration rate by climate normal (modeled)",
  plot_subtitle = paste(
    "Points = modeled median migration rate.  Bars = the model's 80% prediction interval: the 8-in-10 range for an actual measured rate at that forcing",
    "(fitted-coefficient, reach, unmeasured-period, and mapping error combined).  Band = 10-90% spread across the 160 climate futures (which-future uncertainty).",
    "Observed = modeled rate at the historical forcing.  RCP4.5 / RCP8.5 shown separately.  Reaches RS28-37.",
    sep = "\n")),
  width = 13, height = 7.5, units = "in")

ggsave(OUT_PLOT_VIOLIN, plot_ensemble_violin(
  d_rate,
  value        = d_rate_ft_yr,
  y_lab        = "Change in migration rate vs historical (ft/yr)",
  plot_title   = "Projected change in channel migration rate -- full ensemble distribution",
  plot_subtitle = "Violin = member spread per climate normal, split by RCP (80 each); points = members, bar = median. Reaches RS28-37."),
  width = 13, height = 7.5, units = "in")

# Raincloud view of the absolute rate (10 x 7.5 per the ten-reach facet
# convention in claude/plotting_conventions.md).
ggsave(OUT_PLOT_RAINCLOUD, plot_raincloud(
  abs_member, whiskers, NORMALS,
  y_lab        = "Migration rate (ft/yr)",
  plot_title   = "Projected channel migration rate -- full ensemble distribution (modeled)",
  plot_subtitle = paste(
    "Shaded area = spread across ~80 modeled future-flow projections per RCP (which-future uncertainty).",
    "Dots = the individual projections; Point  = ensemble median; vertical line = 80% model prediction error. Reaches RS28-37.",
    sep = "\n")),
  width = 13, height = 7.5, units = "in")

cat("\nWrote ", OUT_PLOT, ", ", OUT_PLOT_ABS, ", ", OUT_PLOT_VIOLIN, ", and ",
    OUT_PLOT_RAINCLOUD, "\n", sep = "")
