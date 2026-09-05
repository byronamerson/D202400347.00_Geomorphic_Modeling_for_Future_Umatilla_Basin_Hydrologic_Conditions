# =============================================================================
# [DEPRECATED 2026-09-04] Superseded by scripts/05_simple_forcing_model.R
# -----------------------------------------------------------------------------
# This script models ANNUALIZED (per-year) change with Delta-t^2 weighting -- a
# frame we retired in favor of the simpler total-vs-total model in 05 (response
# and forcing both as interval totals => no annualizing, no weighting, no
# interval_years term). Kept for reference only.
# The crossover FINDING here still stands and is recorded in the note:
#   cum_excess  -> expansion metrics (net / new area)
#   total duration (days_above) -> abandonment / Jaccard
# See claude/NOTE_simple_forcing_model.md.
# =============================================================================

# =============================================================================
# 04e_migration_forcing_grid.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 4e: Response x Forcing grid -- migration metrics vs the new forcing vars
# =============================================================================
#
# Purpose: Generalize the rs30_modeling_sandbox.R Section 4 response-matrix scan
#          (six migration metrics, one forcing variable) from the old single
#          forcing variable (interval-max annual peak) to a full RESPONSE x
#          FORCING grid against the two primary flood quantities the forcing
#          work (04c/04d) established:
#
#            cum_excess_thresh_cfs_days  cumulative excess above Q2
#                                        (magnitude x duration = work proxy)
#            days_above_thresh           total duration above Q2 (total days > Q2)
#
# Frame: VALIDATED (matches 04d), NOT the sandbox exploratory frame:
#          - ALL 14 intervals (no 2011-2012 exclusion)
#          - interval_years^2 weights (Delta-t^2; down-weight noisy short-interval
#            annualized rates)
#
# Built-in cross-check: the (net_area_change x cum_excess) cell reproduces the
# established 04d result, R^2 ~ 0.39, p ~ 0.017 on n = 14.  [CONFIRMED 2026-09-04]
#
# Depends on (RUN ORDER MATTERS -- both scripts define an object `config`):
#   scripts/rs30_interval_sandbox.R        -> rs30_plot_data (response + interval)
#   scripts/04c_interval_forcing_metrics.R -> forcing `config` + orchestrator
#   data/pendleton_daily_extended.rds (04b)
#
# Outputs (objects, for inspection):
#   rs30_grid_wide    scannable table: response rows (fixed order) x forcing cols,
#                     each cell = slope sign/value, R^2, p
#   rs30_grid_glance  long form: one row per cell, numeric R^2/adj/p/n
#   rs30_grid_tidy    coefficients per cell (intercept + slope)
#   rs30_grid_plots   list of 12 full-size ggplots (one per cell)
# Plots are printed to the plot pane, NOT written to a dense facet grid (which
# is unreadable at 6 x 2). ggsave any cell you want from rs30_grid_plots.
# =============================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(broom)


# ---- 0. Assemble the validated modeling table (response + forcing) -----------
# Mirror 04d's source order: source the interval sandbox FIRST (it builds
# rs30_plot_data and defines its own `config`), capture the intervals, THEN
# source 04c so its forcing `config` is the active one at metric-compute time.

source("scripts/rs30_interval_sandbox.R")   # builds rs30_plot_data
rs30_grid_intervals <- distinct(rs30_plot_data, year_t1, year_t2)

source("scripts/04c_interval_forcing_metrics.R")   # forcing `config` now active
rs30_forcing_metrics <- run_interval_forcing_metrics(config, rs30_grid_intervals)

# ALL 14 intervals (validated frame -- no 2011-2012 exclusion). interval_weight
# carries the Delta-t^2 weight into every weighted fit.
rs30_grid_data <- rs30_plot_data %>%
  left_join(rs30_forcing_metrics, by = c("year_t1", "year_t2")) %>%
  mutate(interval_weight = interval_years^2)


# ---- 1. Response and forcing specs -------------------------------------------
# Six existing interval response metrics (same set as the sandbox scan).
# NOTE: for a SINGLE reach the reach-avg rate is symmetric change / (constant
# length), so its R^2/p (and slope SIGN) are identical to symmetric change here.
# The two only diverge once length varies across reaches (RS 25-29).
rs30_response_specs <- tribble(
  ~response_col,                          ~response_label,
  "new_area_ft2_per_year",                "New area rate (ft^2/yr)",
  "abandoned_area_ft2_per_year",          "Abandoned area rate (ft^2/yr)",
  "symmetric_change_ft2_per_year",        "Symmetric change rate (ft^2/yr)",
  "net_area_change_ft2_per_year",         "Net area change rate (ft^2/yr)",
  "symmetric_change_ft2_per_year_per_ft", "Reach-avg change rate ((ft^2/yr)/ft)",
  "jaccard_change",                       "Jaccard change (unitless)"
)

# The two primary flood quantities.
rs30_forcing_specs <- tribble(
  ~forcing_col,                  ~forcing_label,
  "cum_excess_thresh_cfs_days",  "Cumulative excess > Q2 (cfs-days)",
  "days_above_thresh",           "Total duration > Q2 (days)"
)


# ---- 2. Fit the response x forcing grid (weighted OLS, n = 14) ---------------
# Every cell: a Delta-t^2 weighted simple linear regression on the full 14
# intervals. 6 responses x 2 forcings = 12 fits.
rs30_grid_specs <- crossing(rs30_response_specs, rs30_forcing_specs)

rs30_grid_models <- lapply(
  seq_len(nrow(rs30_grid_specs)),
  function(i) {
    response_col   <- rs30_grid_specs$response_col[[i]]
    response_label <- rs30_grid_specs$response_label[[i]]
    forcing_col    <- rs30_grid_specs$forcing_col[[i]]
    forcing_label  <- rs30_grid_specs$forcing_label[[i]]

    model_fit <- lm(
      reformulate(forcing_col, response_col),
      data    = rs30_grid_data,
      weights = interval_weight
    )

    list(
      response_col   = response_col,
      response_label = response_label,
      forcing_col    = forcing_col,
      forcing_label  = forcing_label,
      fit            = model_fit
    )
  }
)

rs30_grid_glance <- bind_rows(
  lapply(rs30_grid_models, function(m) {
    broom::glance(m$fit) %>%
      mutate(response_label = m$response_label,
             forcing_label  = m$forcing_label)
  })
) %>%
  select(forcing_label, response_label, r.squared, adj.r.squared, p.value, nobs)

rs30_grid_tidy <- bind_rows(
  lapply(rs30_grid_models, function(m) {
    broom::tidy(m$fit) %>%
      mutate(response_label = m$response_label,
             forcing_label  = m$forcing_label)
  })
) %>%
  select(forcing_label, response_label, everything())


# ---- 2b. Scannable wide summary (slope sign + R^2 + p) ------------------------
# ONE fixed response order (anchored on cum_excess R^2, descending) applied to
# BOTH forcing columns, so each response reads straight across. Each cell now
# carries the SLOPE of the forcing term (its sign is the direction of the
# relationship) alongside R^2 and p.
rs30_grid_slopes <- rs30_grid_tidy %>%
  filter(term != "(Intercept)") %>%
  transmute(forcing_label, response_label, slope = estimate)

rs30_grid_cells <- rs30_grid_glance %>%
  left_join(rs30_grid_slopes, by = c("forcing_label", "response_label")) %>%
  mutate(cell = sprintf("b=%+.2e  R2=%.3f  p=%.3f", slope, r.squared, p.value))

response_order <- rs30_grid_glance %>%
  filter(forcing_label == "Cumulative excess > Q2 (cfs-days)") %>%
  arrange(desc(r.squared)) %>%
  pull(response_label)

rs30_grid_wide <- rs30_grid_cells %>%
  select(response_label, forcing_label, cell) %>%
  pivot_wider(names_from = forcing_label, values_from = cell) %>%
  rename(
    cum_excess     = `Cumulative excess > Q2 (cfs-days)`,
    total_duration = `Total duration > Q2 (days)`
  ) %>%
  mutate(response_label = factor(response_label, levels = response_order)) %>%
  arrange(response_label)

print(rs30_grid_wide, width = Inf)


# ---- 3. Individual per-cell plots (dumped to the plot pane) ------------------
# One clean, full-size plot per response x forcing cell. Points labeled by
# interval (ggrepel if available, else nudged geom_text). The lm smooth is
# weighted to match the fitted line. R^2/p live in the subtitle.

make_cell_plot <- function(m) {
  g <- broom::glance(m$fit)
  d <- rs30_grid_data %>%
    transmute(interval_label,
              interval_weight,
              x = .data[[m$forcing_col]],
              y = .data[[m$response_col]])

  label_layer <- if (requireNamespace("ggrepel", quietly = TRUE)) {
    ggrepel::geom_text_repel(aes(label = interval_label), size = 3.2,
                             max.overlaps = Inf, seed = 1,
                             min.segment.length = 0)
  } else {
    geom_text(aes(label = interval_label), size = 3.2, vjust = -0.6,
              check_overlap = TRUE)
  }

  ggplot(d, aes(x, y)) +
    geom_smooth(aes(weight = interval_weight), method = "lm", se = FALSE,
                formula = y ~ x, color = "#d95f0e", linewidth = 0.9) +
    geom_point(size = 3, color = "#2c7fb8") +
    label_layer +
    labs(
      x = m$forcing_label,
      y = m$response_label,
      title = paste0("RS 30:  ", m$response_label, "  vs  ", m$forcing_label),
      subtitle = sprintf("Delta-t^2 weighted, n = 14    |    R^2 = %.3f,  p = %.3f",
                         g$r.squared, g$p.value)
    ) +
    theme_minimal(base_size = 12)
}

rs30_grid_plots <- lapply(rs30_grid_models, make_cell_plot)
names(rs30_grid_plots) <- paste(
  rs30_grid_specs$forcing_col, "~", rs30_grid_specs$response_col
)

# Print all 12 to the plot pane -- page through with the pane's back/forward
# arrows. To view or save a single cell, e.g.:
#   rs30_grid_plots[["cum_excess_thresh_cfs_days ~ net_area_change_ft2_per_year"]]
#   ggsave("plots/net_area_vs_cum_excess.png", .Last.value, width = 7, height = 5)
for (p in rs30_grid_plots) print(p)
