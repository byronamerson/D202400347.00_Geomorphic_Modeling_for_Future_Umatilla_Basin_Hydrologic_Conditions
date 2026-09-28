# =============================================================================
# 14_reach_sensitivity_teaching_figure.R
# Umatilla River Discharge-Channel Migration Analysis
# Client-facing teaching figure: three ways to fit reach flood-sensitivity
# =============================================================================
#
# Purpose: A communications figure (NOT a pipeline step) that makes the
#   linear-mixed-model "partial pooling" logic legible to a non-statistical
#   audience. For each reach RS28-RS37 it overlays three fits of the SAME data:
#     grey   = that reach's own OLS (complete no-pooling) -- overfits thin reaches
#     orange = one shared population line (complete pooling) -- ignores reach diffs
#     green  = the mixed-model partial-pool line -- each reach, borrowing strength
#
#   This is the bankfull (0.75xQ2, model of record) sibling of 07's p_scatter,
#   which is the FROZEN Q2 audit version -- deliberately NOT relabelled. Lines and
#   points come from the fit script's bankfull machinery; nothing is refit here.
#
# Source of truth: scripts/fit_forcing_model.R -> panel (observed points),
#   model + model_equation() (orange population + green
#   partial-pool lines). interval_years and the interval RE are held at 0 so the
#   three lines are directly comparable (matches the fit script's p_fit).
#
# Output: plots/reach_flood_sensitivity_teaching.png (10 x 7.5 in, 2x5 facets)
#
# Style: plotting_conventions.md + the fit script's p_fit palette.
# =============================================================================

library(dplyr)
library(ggplot2)

# fit_forcing_model.R is the bankfull toolbox: sourcing it (cold) builds `panel`,
# fits `model`, and exposes model_equation() / FORCING_VAR. Guarded so a warm
# session is not re-run; delete the guard to force a rebuild.
if (!exists("panel") || !exists("model") || !exists("model_equation")) {
  source("scripts/fit_forcing_model.R")
}

# ---- Pull the bankfull equation (no refit) ---------------------------------
eq <- model_equation(model, FORCING_VAR)


# green: partial-pool reach lines (reach-specific intercept + slope)
reach_ln <- eq$reaches %>%
  mutate(river_segment = factor(river_segment, levels = levels(panel$river_segment)))

# orange: the single shared population line (one row, drawn in every facet)
pop_ln <- tibble(intercept = eq$pop_intercept, slope = eq$pop_slope)

# ---- Plain-language legend labels (the key upgrade for a lay audience) ------
lab_ols  <- "Each reach fit alone (OLS) — overfits thin / noisy reaches"
lab_pool <- "All reaches, one pooled line — ignores that reaches differ"
lab_lmm  <- "Mixed model (partial pooling) — each reach, borrowing strength"
fit_levels <- c(lab_ols, lab_pool, lab_lmm)
fit_cols   <- setNames(c("grey55", "#d95f0e", "#238b45"), fit_levels)

# ---- Shared fixed y-axis, rounded out to a common tick interval ------------
y_tick <- 50
y_max  <- ceiling(max(panel$new_area_per_ft) / y_tick) * y_tick  # 200
y_brk  <- seq(0, y_max, y_tick)

# ---- Plot ------------------------------------------------------------------
p_teach <- ggplot(panel, aes(.data[[FORCING_VAR]], new_area_per_ft)) +
  # grey: per-reach OLS -- each facet's own points, no pooling
  geom_smooth(aes(color = lab_ols), method = "lm", se = FALSE,
              linewidth = 0.5, formula = y ~ x, key_glyph = "path") +
  # orange: shared population (complete-pooling) line
  geom_abline(data = pop_ln,
              aes(intercept = intercept, slope = slope, color = lab_pool),
              linewidth = 0.8, key_glyph = "path") +
  # green: LMM partial-pool line, per reach
  geom_abline(data = reach_ln,
              aes(intercept = reach_intercept, slope = reach_slope, color = lab_lmm),
              linewidth = 0.7, key_glyph = "path") +
  geom_point(size = 1.3, alpha = 0.7, color = "#2c7fb8") +
  facet_wrap(~ river_segment, nrow = 2,
             labeller = as_labeller(function(x) paste0("RS", x))) +
  scale_color_manual(values = fit_cols, breaks = fit_levels, name = NULL) +
  scale_y_continuous(breaks = y_brk) +
  coord_cartesian(ylim = c(0, y_max)) +  # clip display, keep all points for the OLS fit
  labs(
    x = "Cumulative flow above bankfull → (more flood forcing over the interval)",
    y = "New area per ft (ft)",
    title = "Estimating each reach's flood sensitivity: three ways to fit the same data",
    subtitle = "Umatilla River reaches RS28–RS37 · channel change vs. flood forcing, one point per survey interval",
    caption = paste0(
      "Forcing = cumulative excess discharge greater than bankfull flow (1,000 cfs-days). ",
      "Lines shown with the per-interval baseline held at zero so the three fits are directly comparable."
    )
  ) +
  guides(color = guide_legend(ncol = 1, override.aes = list(linewidth = 1.1))) +
  theme_minimal(base_size = 11) +
  theme(
    legend.position = "bottom",
    legend.text     = element_text(size = 9),
    plot.caption    = element_text(size = 8, color = "grey40", hjust = 0),
    plot.title      = element_text(face = "bold")
  )

ggsave("plots/reach_flood_sensitivity_teaching.png", p_teach,
       width = 13, height = 7.5, units = "in", dpi = 150)
cat("\nWrote plots/reach_flood_sensitivity_teaching.png\n")
