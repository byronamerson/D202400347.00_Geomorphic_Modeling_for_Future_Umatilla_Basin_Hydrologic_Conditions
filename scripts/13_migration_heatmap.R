# =============================================================================
# 13_migration_heatmap.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 12 companion: SPATIAL (reach x period) heat maps of projected migration
#          rate -- the "where does migration accelerate" view.
# =============================================================================
#
# Draws entirely from the projection summary outputs. Each cell is one ensemble-
# median rate; y = reach (upstream -> downstream), x = the period axis, fill =
# rate, one panel per RCP.
#
# TWO AXES, STATISTICAL TRACK ONLY. The dynamical track is reported on the
# calendar-era axis (12c) and was retired from the warming-level axis on
# 2026-10-05; neither of its summaries is mapped here.
#
#   era : calendar blocks 2006-2035 / 2036-2065 / 2066-2099   (from 12b)
#   gwl : warming levels 1.5 / 2 / 3 / 4 degC                 (from
#         gwl_migration_projection.R)
#
# Two views per axis: absolute annual rate (where the channel moves fastest) and
# delta vs historical (where climate change adds the most). The historical column
# is not in the summary CSVs, but it is recoverable: absolute = historical +
# delta per member, and historical is a per-reach constant, so (absolute median
# - delta median) is that reach's historical rate. No extra input is needed.
#
# THE HISTORICAL COLUMN IS NOT THE SAME NUMBER ON THE TWO AXES. The era figure
# annualizes the Observed point over 30 years (eras.R,
# OBS_WINDOW_YEARS_STATISTICAL); the warming-level figure over 20 years
# (GWL_TRACKS, settled 2026-10-05, because every published warming-level window
# is 20 years). Each figure is internally consistent; the two historical columns
# cannot be read against each other. The delta views are unaffected -- the
# divisor cancels in the change view.
#
# THE WARMING-LEVEL GRID IS RAGGED BY CONSTRUCTION, the era grid is not. RCP4.5
# never reaches 4 degC, so that tile is empty, and member counts fall away at the
# high levels (80 / 64 / 16 on RCP4.5; 80 / 80 / 80 / 56 on RCP8.5) against a
# uniform 80 everywhere on the era axis. Cells are drawn as-is: nothing is
# dropped and no member count is shown. This is deliberate for a first look.
#
# Inputs : data/migration_rate_summary_<suffix>.csv    (absolute band)
#          data/migration_dArate_summary_<suffix>.csv  (delta band)
# Outputs: plots/migration_heatmap_rate_<suffix>.png
#          plots/migration_heatmap_dArate_<suffix>.png
# Style  : Tidyverse & FP guidelines (docs/lingua.md, docs/r-principles.md).
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(purrr)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

# One entry per period axis. Period levels are stated, not derived from the
# incoming table: the axis order is an editorial choice about the figure, and a
# figure should not silently re-order itself because a run produced a different
# set of cells.
AXES <- list(
  list(
    suffix        = "bc-k-by-era",
    axis_name     = "climate era",
    period_levels = c("2006-2035", "2036-2065", "2066-2099"),
    obs_window_yr = 30L
  ),
  list(
    suffix        = "gwl-bc-k-by-era",
    axis_name     = "global warming level",
    period_levels = c("1.5 degC", "2 degC", "3 degC", "4 degC"),
    obs_window_yr = 20L
  )
)

# Figure canvas, in inches. Sized for a tech memo on letter landscape with 1 in
# margins: a 9 x 6.5 in text block, leaving ~0.5 in under the figure for a
# caption. Rendered at final size on purpose -- letting the word processor scale
# a larger render down also scales the type below its stated point size. Shared
# by both axes, so the two figures are interchangeable on the page; the cost is
# that the warming-level figure fits five columns in the same width the era
# figure uses for four, so its tiles are narrower.
FIG_WIDTH_IN  <- 9
FIG_HEIGHT_IN <- 6

rate_csv_path  <- function(suffix) sprintf("data/migration_rate_summary_%s.csv", suffix)
delta_csv_path <- function(suffix) sprintf("data/migration_dArate_summary_%s.csv", suffix)
out_rate_path  <- function(suffix) sprintf("plots/migration_heatmap_rate_%s.png", suffix)
out_delta_path <- function(suffix) sprintf("plots/migration_heatmap_dArate_%s.png", suffix)


# =============================================================================
# 2. HELPERS  (pure; each carries its boundary contract)
# =============================================================================

reach_historical_rate <- function(abs_band, delta_band) {
  #' Recover each reach's historical absolute rate as (absolute median - delta median).
  #' Absolute = historical + delta per member and historical is a per-reach constant,
  #' so the difference of medians equals that constant, identical across every
  #' scenario x period cell.
  #' @param abs_band,delta_band summary bands from the projection runner
  #'   (river_segment, scenario, period, median, ...).
  #' @return tibble(river_segment, hist_rate_ft_yr, spread) -- spread should be ~0;
  #'   it is a guard that the recovery held.
  abs_band %>%
    select(river_segment, scenario, period, ma = median) %>%
    inner_join(select(delta_band, river_segment, scenario, period, md = median),
               by = c("river_segment", "scenario", "period")) %>%
    mutate(h = ma - md) %>%
    group_by(river_segment) %>%
    summarise(hist_rate_ft_yr = mean(h), spread = max(h) - min(h), .groups = "drop")
}

build_heatmap_table <- function(band, hist_value, reach_levels, period_levels) {
  #' Assemble a tidy reach x scenario x period cell table, prepending the
  #' historical baseline column and ordering the reach/period axes for display.
  #' @param band summary band (river_segment, scenario, period, median).
  #' @param hist_value tibble(river_segment, value) for the historical column
  #'   (0 for the delta view; the reach historical rate for the absolute view).
  #' @param reach_levels,period_levels ordered factor levels for the axes.
  #' @return tibble(river_segment, scenario, reach <fct>, period <fct>, value).
  #' Decision: period is levelled against the stated axis, so a level present in
  #' the config but absent from `band` (RCP4.5 at 4 degC) draws as an empty tile
  #' rather than vanishing from the axis.
  hist_rows <- band %>%
    distinct(river_segment, scenario) %>%
    left_join(hist_value, by = "river_segment") %>%
    mutate(period = "historical")

  band %>%
    transmute(river_segment, scenario, period, value = median) %>%
    bind_rows(hist_rows) %>%
    mutate(reach  = factor(paste0("RS", river_segment), levels = reach_levels),
           period = factor(period, levels = c("historical", period_levels)))
}

plot_heatmap <- function(cells, fill_scale, dark_high, plot_title, plot_subtitle) {
  #' Reach x period heat map, one panel per RCP, each cell labeled with its value.
  #' @param cells table from build_heatmap_table().
  #' @param fill_scale a ggplot2 fill scale -- selects the colour ramp.
  #' @param dark_high TRUE if the ramp's HIGH end is dark (high-value cells then
  #'   need light label text); FALSE if the high end is light.
  #' @param plot_title,plot_subtitle labels.
  #' @return a ggplot object (caller handles ggsave -- I/O at the boundary).
  #' Decision: label text flips dark/light by cell brightness so numbers stay
  #' legible across the ramp; both RCP panels share one fill scale so they are
  #' directly comparable. drop = FALSE on the x scale keeps a level with no data
  #' visible as a gap.
  rng     <- range(cells$value, na.rm = TRUE)
  hi_text <- if (dark_high) "grey95" else "grey10"   # text on high-value cells
  lo_text <- if (dark_high) "grey10" else "grey95"   # text on low-value cells
  cells   <- mutate(cells,
                    label_col = ifelse((value - rng[1]) / diff(rng) > 0.55, hi_text, lo_text))

  ggplot(cells, aes(period, reach, fill = value)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = round(value, 1), color = label_col), size = 3.2) +
    facet_wrap(~ scenario) +
    scale_x_discrete(drop = FALSE) +
    fill_scale +
    scale_color_identity() +
    labs(x = NULL, y = NULL, title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(panel.grid   = element_blank(),
          axis.text.x  = element_text(angle = 30, hjust = 1),
          legend.position = "right")
}

# Colour ramp: ColorBrewer YlOrRd -- colour-blind safe, canonical risk/intensity
# ramp, high end dark, no extra package.
fill_ylorrd <- function(lab) scale_fill_distiller(palette = "YlOrRd", direction = 1, name = lab)


# =============================================================================
# 3. ORCHESTRATION  (read one axis' summaries, assemble grids, write heat maps)
# =============================================================================

render_axis_heatmaps <- function(axis) {
  #' Draw and write both heat maps for one period axis.
  #' @param axis one element of AXES: suffix, axis_name, period_levels,
  #'   obs_window_yr, plot_width_in.
  #' @return invisibly, the two output paths written.
  #' This is the I/O boundary -- every helper above works on in-memory tables.
  rate_csv  <- rate_csv_path(axis$suffix)
  delta_csv <- delta_csv_path(axis$suffix)
  stopifnot(file.exists(rate_csv), file.exists(delta_csv))

  abs_band   <- read_csv(rate_csv,  show_col_types = FALSE)
  delta_band <- read_csv(delta_csv, show_col_types = FALSE)

  # Axis ordering: RS28 (upstream) at top -> RS37 (downstream) at bottom.
  reach_levels <- paste0("RS", rev(sort(unique(abs_band$river_segment))))

  reach_hist <- reach_historical_rate(abs_band, delta_band)
  stopifnot(all(reach_hist$spread < 1e-6))   # historical rate must be constant per reach

  abs_cells <- build_heatmap_table(
    abs_band,
    hist_value    = transmute(reach_hist, river_segment, value = hist_rate_ft_yr),
    reach_levels  = reach_levels,
    period_levels = axis$period_levels)

  delta_cells <- build_heatmap_table(
    delta_band,
    hist_value    = distinct(delta_band, river_segment) %>% mutate(value = 0),
    reach_levels  = reach_levels,
    period_levels = axis$period_levels)

  out_rate  <- out_rate_path(axis$suffix)
  out_delta <- out_delta_path(axis$suffix)

  ggsave(out_rate, plot_heatmap(
    abs_cells, fill_ylorrd("ft/yr"), dark_high = TRUE,
    plot_title    = sprintf("Projected channel migration rate by reach and %s",
                            axis$axis_name),
    plot_subtitle = sprintf(paste("Statistical track; ensemble median absolute rate (ft/yr).",
                                  "Historical column annualized over %d yr.",
                                  "Rows: RS28 (upstream) -> RS37 (downstream)."),
                            axis$obs_window_yr)),
    width = FIG_WIDTH_IN, height = FIG_HEIGHT_IN, units = "in")

  ggsave(out_delta, plot_heatmap(
    delta_cells, fill_ylorrd("delta ft/yr"), dark_high = TRUE,
    plot_title    = sprintf("Projected change in channel migration rate by reach and %s",
                            axis$axis_name),
    plot_subtitle = paste("Statistical track; ensemble median change vs historical (ft/yr).",
                          "Rows: RS28 (upstream) -> RS37 (downstream).")),
    width = FIG_WIDTH_IN, height = FIG_HEIGHT_IN, units = "in")

  cat(sprintf("Wrote %s and %s\n", out_rate, out_delta))
  invisible(c(out_rate, out_delta))
}

walk(AXES, render_axis_heatmaps)
