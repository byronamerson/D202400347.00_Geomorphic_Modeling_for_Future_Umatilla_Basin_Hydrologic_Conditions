# =============================================================================
# 13_migration_heatmap.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 12 companion: SPATIAL (reach x period) heat map of projected migration
#          rate -- the "where does migration accelerate" view.
# =============================================================================
#
# Draws entirely from script 12's summary outputs. Each cell is one ensemble-
# median rate; y = reach (upstream -> downstream), x = climate normal (historical
# baseline + three 30-yr normals), fill = rate, one panel per RCP.
#
# Two views: absolute annual rate (where the channel moves fastest) and Δ vs
# historical (where climate change adds the most). The historical column is not
# in the summary CSVs, but it is recoverable: absolute = historical + Δ per
# member and historical is a per-reach constant, so (absolute median − Δ median)
# is that reach's historical rate -- no extra input from 12 needed.
#
# Inputs : data/migration_rate_summary.csv    (absolute band, from 12)
#          data/migration_dArate_summary.csv  (Δ band, from 12)
# Outputs: plots/migration_heatmap_rate.png   (absolute)
#          plots/migration_heatmap_dArate.png (Δ vs historical)
# Style  : Tidyverse & FP guidelines (docs/lingua.md, docs/r-principles.md).
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

RATE_CSV  <- "data/migration_rate_summary.csv"
DELTA_CSV <- "data/migration_dArate_summary.csv"
OUT_RATE  <- "plots/migration_heatmap_rate.png"
OUT_DELTA <- "plots/migration_heatmap_dArate.png"
OUT_RATE_ALT <- "plots/migration_heatmap_rate_rocket.png"   # palette comparison

# Climate normals, ordered; "historical" is prepended as the baseline column.
NORMAL_PERIODS <- c("2010-2039", "2040-2069", "2070-2099")


# =============================================================================
# 2. HELPERS  (pure; each carries its boundary contract)
# =============================================================================

reach_historical_rate <- function(abs_band, delta_band) {
  #' Recover each reach's historical absolute rate as (absolute median − Δ median).
  #' Absolute = historical + Δ per member and historical is a per-reach constant,
  #' so the difference of medians equals that constant, identical across every
  #' scenario x period cell.
  #' @param abs_band,delta_band summary bands from 12 (river_segment, scenario,
  #'   period, median, ...).
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
  #'   (0 for the Δ view; the reach historical rate for the absolute view).
  #' @param reach_levels,period_levels ordered factor levels for the axes.
  #' @return tibble(river_segment, scenario, reach <fct>, period <fct>, value).
  hist_rows <- band %>%
    distinct(river_segment, scenario) %>%
    left_join(hist_value, by = "river_segment") %>%
    mutate(period = "historical")

  band %>%
    transmute(river_segment, scenario, period, value = median) %>%
    bind_rows(hist_rows) %>%
    mutate(reach  = factor(paste0("RS", river_segment), levels = reach_levels),
           period = factor(period, levels = period_levels))
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
  #' directly comparable.
  rng     <- range(cells$value, na.rm = TRUE)
  hi_text <- if (dark_high) "grey95" else "grey10"   # text on high-value cells
  lo_text <- if (dark_high) "grey10" else "grey95"   # text on low-value cells
  cells   <- mutate(cells,
                    label_col = ifelse((value - rng[1]) / diff(rng) > 0.55, hi_text, lo_text))

  ggplot(cells, aes(period, reach, fill = value)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = round(value, 1), color = label_col), size = 3) +
    facet_wrap(~ scenario) +
    fill_scale +
    scale_color_identity() +
    labs(x = NULL, y = NULL, title = plot_title, subtitle = plot_subtitle) +
    theme_minimal(base_size = 10) +
    theme(panel.grid   = element_blank(),
          axis.text.x  = element_text(angle = 30, hjust = 1),
          legend.position = "right")
}


# =============================================================================
# 3. ORCHESTRATION  (read 12's summaries, assemble grids, write heat maps)
# =============================================================================

stopifnot(file.exists(RATE_CSV), file.exists(DELTA_CSV))
abs_band   <- read_csv(RATE_CSV,  show_col_types = FALSE)
delta_band <- read_csv(DELTA_CSV, show_col_types = FALSE)

# Axis ordering: RS28 (upstream) at top -> RS37 (downstream) at bottom. Flip the
# rev() if the station numbering runs the other way.
reaches       <- sort(unique(abs_band$river_segment))
reach_levels  <- paste0("RS", rev(reaches))
period_levels <- c("historical", NORMAL_PERIODS)

reach_hist <- reach_historical_rate(abs_band, delta_band)
stopifnot(all(reach_hist$spread < 1e-6))   # historical rate must be constant per reach

abs_cells <- build_heatmap_table(
  abs_band,
  hist_value    = transmute(reach_hist, river_segment, value = hist_rate_ft_yr),
  reach_levels  = reach_levels,
  period_levels = period_levels)

delta_cells <- build_heatmap_table(
  delta_band,
  hist_value    = distinct(delta_band, river_segment) %>% mutate(value = 0),
  reach_levels  = reach_levels,
  period_levels = period_levels)

# Colour ramps (both colour-blind safe, warm = more change, high end dark).
# Default: ColorBrewer YlOrRd -- canonical risk/intensity ramp, no extra package.
# Comparison: viridis rocket, reversed so the high end is dark -- perceptually uniform.
fill_ylorrd <- function(lab) scale_fill_distiller(palette = "YlOrRd", direction = 1, name = lab)
fill_rocket <- function(lab) scale_fill_viridis_c(option = "rocket", direction = -1, name = lab)

ggsave(OUT_RATE, plot_heatmap(
  abs_cells, fill_ylorrd("ft/yr"), dark_high = TRUE,
  plot_title    = "Projected channel migration rate by reach and climate normal",
  plot_subtitle = "Ensemble median absolute rate (ft/yr). Rows: RS28 (upstream) -> RS37 (downstream)."),
  width = 13, height = 6.5, units = "in")

ggsave(OUT_DELTA, plot_heatmap(
  delta_cells, fill_ylorrd("Δ ft/yr"), dark_high = TRUE,
  plot_title    = "Projected change in channel migration rate by reach and climate normal",
  plot_subtitle = "Ensemble median Δ vs historical (ft/yr). Rows: RS28 (upstream) -> RS37 (downstream)."),
  width = 13, height = 6.5, units = "in")

# Same absolute map in the rocket ramp, for a side-by-side palette comparison.
ggsave(OUT_RATE_ALT, plot_heatmap(
  abs_cells, fill_rocket("ft/yr"), dark_high = TRUE,
  plot_title    = "Projected channel migration rate",
  plot_subtitle = "Same data as migration_heatmap_rate.png; viridis rocket ramp."),
  width = 13, height = 6.5, units = "in")

cat("\nWrote ", OUT_RATE, ", ", OUT_DELTA, ", and ", OUT_RATE_ALT, "\n", sep = "")
