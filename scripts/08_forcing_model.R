# =============================================================================
# 08_forcing_model.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 8: Forward-model toolbox -- fit the migration<->forcing equation and
#          apply it to any forcing table (historical or future flow scenarios)
# =============================================================================
#
# Purpose: The settled, reusable forward model. Fits the RS 28-37 migration
#   equation for a chosen forcing metric, exposes the fitted equation as plain
#   coefficients, and provides predict_migration() to push ANY forcing table
#   through it -- the same function that will carry the UW future daily flows.
#
#   This is the clean go-forward tool. The model-selection and diagnostic
#   scaffolding that justified the structure (the m_ri/m_cross/m_A ladder,
#   variance-component and saturation reads, sqrt robustness, the metric
#   bake-off) lives, frozen, in 07 / 07b / explore -- the committed audit trail.
#   Nothing here re-litigates those choices; it just applies them.
#
# The model of record (settled in 07, see NOTE_multireach_lmm_procedure.md):
#   new_area_per_ft ~ forcing + interval_years
#                     + (forcing || river_segment)   # reach-varying slope, uncorrelated
#                     + (1 | interval)               # shared flood per interval
#   Fitted per reach, the equation is simply:
#     new_area_per_ft = reach_intercept
#                     + reach_slope * forcing        # reach's own sensitivity
#                     + baseline_per_year * interval_years
#   (The (1|interval) term is an in-sample nuisance for shared flood effects; it
#    is held at 0 when projecting new/future intervals -- see predict_migration.)
#
# Two forcing metrics, both retained as parallel lenses (see
# NOTE_projection_framing_and_implications.md); cum_excess is the model of record:
#   cum_excess  (cum_excess_k)  -- magnitude x duration above Q2; natural for a
#                                  DAILY series -> the primary/default metric
#   sum_peak    (sum_peak_k)    -- summed crest excess above Q2; the crest-driven
#                                  lens, kept at hand for extremes questions
#
# Inputs:
#   - data/multireach_interval_metrics.csv    (response, from 06)
#   - scripts/04c_interval_forcing_metrics.R  (forcing config + runner; both metrics)
# Outputs:
#   - data/forcing_model_coefficients_cum_excess.csv   (portable fitted equation)
#   - data/forcing_model_coefficients_sum_peak.csv
#   - plots/forcing_model_reach_fit.png                (per-reach fit sanity check)
#
# Style: Tidyverse & FP guidelines. Coefficients in feet; forcing scaled to
#   THOUSANDS of cfs-days so a slope reads "ft per 1000 cfs-days".
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(purrr)
library(ggplot2)
library(lme4)

source("scripts/04c_interval_forcing_metrics.R")  # config, run_interval_forcing_metrics


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

# Pendleton leveed reaches -- migration mechanically precluded, out of scope
# (docs/NOTE_confined_reach_exclusion.md). Single toggle: keep all to restore.
CONFINED_REACHES <- c(25L, 26L, 27L)

RESPONSE_CSV   <- "data/multireach_interval_metrics.csv"
PRIMARY_METRIC <- "cum_excess"

# The forcing metrics available to the model. `var` is the scaled panel column;
# `source` its raw (cfs / cfs-days) column from 04c; `label` for plots.
MODEL_METRICS <- list(
  cum_excess = list(var = "cum_excess_k", source = "cum_excess_thresh_cfs_days",
                    label = "Cumulative excess > Q2 (1000 cfs-days)"),
  sum_peak   = list(var = "sum_peak_k",   source = "sum_peak_excess_cfs",
                    label = "Summed crest excess > Q2 (1000 cfs-days)")
)


# =============================================================================
# 2. PANEL ASSEMBLY
# =============================================================================

assemble_panel <- function(response, forcing, confined_reaches = CONFINED_REACHES) {
  #' Join the per-reach response to per-interval forcing and add both scaled
  #' forcing columns + the factors the model needs. One row per reach x interval.
  #' @param response tibble from 06 (river_segment, year_t1/t2, interval_years,
  #'   new_area_per_ft, ...)
  #' @param forcing tibble from 04c (year_t1/t2 + forcing-metric columns)
  #' @return the model-ready panel
  response %>%
    filter(!river_segment %in% confined_reaches) %>%
    left_join(forcing, by = c("year_t1", "year_t2")) %>%
    mutate(
      river_segment = factor(river_segment),
      interval      = factor(paste0(year_t1, "-", year_t2)),
      cum_excess_k  = cum_excess_thresh_cfs_days / 1000,
      sum_peak_k    = sum_peak_excess_cfs / 1000
    )
}


# =============================================================================
# 3. FIT
# =============================================================================

fit_forcing_model <- function(panel, forcing_var, REML = TRUE) {
  #' Fit the model of record for one forcing metric. Structure is fixed (settled
  #' in 07); only the forcing column varies.
  #' @param panel model-ready panel (from assemble_panel)
  #' @param forcing_var name of the scaled forcing column (e.g. "cum_excess_k")
  #' @return an lmerMod
  fml <- stats::as.formula(sprintf(
    "new_area_per_ft ~ %s + interval_years + (%s || river_segment) + (1 | interval)",
    forcing_var, forcing_var))
  lme4::lmer(fml, data = panel, REML = REML)
}


# =============================================================================
# 4. THE FITTED EQUATION (expose the coefficients)
# =============================================================================

reach_effects <- function(model, forcing_var) {
  #' Per-reach intercept and slope = population fixed effect + that reach's
  #' (shrunken) random effect. Robust to the `||` split, which stores the reach
  #' intercept and reach slope as two separate river_segment RE terms.
  #' @return tibble(river_segment, reach_intercept, reach_slope)
  re  <- lme4::ranef(model)
  seg <- re[grep("^river_segment", names(re))]
  int_df <- seg[[which(vapply(seg, function(d) "(Intercept)" %in% colnames(d), logical(1)))]]
  slp_df <- seg[[which(vapply(seg, function(d) forcing_var  %in% colnames(d), logical(1)))]]
  fe <- lme4::fixef(model)
  tibble(
    river_segment   = rownames(int_df),
    reach_intercept = fe[["(Intercept)"]] + int_df[["(Intercept)"]],
    reach_slope     = fe[[forcing_var]]   + slp_df[[forcing_var]]
  )
}

model_equation <- function(model, forcing_var) {
  #' The complete fitted equation as plain numbers: population scalars + the
  #' per-reach intercept/slope table. This is everything predict_migration needs.
  fe <- lme4::fixef(model)
  list(
    forcing_var     = forcing_var,
    pop_intercept   = unname(fe[["(Intercept)"]]),
    pop_slope       = unname(fe[[forcing_var]]),
    baseline_per_yr = unname(fe[["interval_years"]]),
    reaches         = reach_effects(model, forcing_var)
  )
}

coef_table <- function(eq) {
  #' Flatten a fitted equation to a portable long-format CSV: population scalars
  #' plus one row per reach intercept and reach slope. Reconstructs the equation
  #' outside R.
  bind_rows(
    tibble(term = "population_intercept", river_segment = NA_character_, value = eq$pop_intercept),
    tibble(term = "population_slope",     river_segment = NA_character_, value = eq$pop_slope),
    tibble(term = "baseline_per_year",    river_segment = NA_character_, value = eq$baseline_per_yr),
    transmute(eq$reaches, term = "reach_intercept", river_segment, value = reach_intercept),
    transmute(eq$reaches, term = "reach_slope",     river_segment, value = reach_slope)
  ) %>% mutate(forcing_var = eq$forcing_var, .before = 1)
}


# =============================================================================
# 5. APPLY THE EQUATION -- the forward step
# =============================================================================

predict_migration <- function(model, newdata, forcing_var, interval_re = FALSE) {
  #' Push any forcing table through the fitted equation. This is the bridge to
  #' the future-flow scenarios: `newdata` can be the historical panel OR a table
  #' of projected intervals -- it just needs river_segment, the forcing column,
  #' and interval_years.
  #'
  #' Predicted new_area_per_ft = reach_intercept + reach_slope * forcing
  #'                             + baseline_per_year * interval_years
  #'
  #' @param interval_re FALSE (default): interval random effect held at 0 -- the
  #'   correct behavior for NEW/future intervals (their shared flood effect is
  #'   unknown). TRUE: add each interval's fitted RE back in, to reproduce the
  #'   in-sample fitted() for verification. Reaches not in the fit get NA.
  #' @return `newdata` with a pred_new_area_per_ft column
  eq  <- model_equation(model, forcing_var)  # reach keys are character
  out <- newdata %>%
    mutate(.rs_key = as.character(river_segment)) %>%
    left_join(eq$reaches, by = c(".rs_key" = "river_segment")) %>%
    mutate(pred_new_area_per_ft =
             reach_intercept + reach_slope * .data[[forcing_var]] +
             eq$baseline_per_yr * interval_years)
  if (interval_re) {
    ire <- lme4::ranef(model)$interval
    out <- out %>%
      mutate(.iv_key = as.character(interval)) %>%
      left_join(tibble(.iv_key = rownames(ire), .ire = ire[, 1]), by = ".iv_key") %>%
      mutate(pred_new_area_per_ft = pred_new_area_per_ft + tidyr::replace_na(.ire, 0)) %>%
      select(-.iv_key, -.ire)
  }
  select(out, -.rs_key)
}


# =============================================================================
# 6. REPORTING HELPERS
# =============================================================================

print_equation <- function(eq, label) {
  cat("\n=== Fitted equation:", label, "===\n")
  cat(sprintf("  new_area_per_ft = reach_intercept + reach_slope * %s + %.3f * interval_years\n",
              eq$forcing_var, eq$baseline_per_yr))
  cat(sprintf("  population intercept : %8.2f ft\n",                      eq$pop_intercept))
  cat(sprintf("  population slope     : %8.3f ft per 1000 cfs-days\n",    eq$pop_slope))
  cat(sprintf("  baseline reworking   : %8.3f ft per year\n",            eq$baseline_per_yr))
  cat("  per-reach intercept & slope:\n")
  eq$reaches %>%
    mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
    as.data.frame() %>% print(row.names = FALSE)
}

slope_summary <- function(models, metrics) {
  #' Headline: population forcing slope (+ SE, t) and baseline for each metric.
  imap_dfr(models, function(m, k) {
    v  <- metrics[[k]]$var
    co <- summary(m)$coefficients[v, ]
    tibble(metric = k, forcing_var = v,
           pop_slope       = round(co[["Estimate"]], 3),
           se              = round(co[["Std. Error"]], 3),
           t               = round(co[["t value"]], 2),
           baseline_per_yr = round(lme4::fixef(m)[["interval_years"]], 3))
  })
}

verify_equation <- function(model, panel, forcing_var) {
  #' The hand-built equation, with interval REs added back, must reproduce
  #' lme4's fitted() to numerical precision -- proves the coefficient extraction
  #' is exactly the model.
  pred <- predict_migration(model, panel, forcing_var, interval_re = TRUE)$pred_new_area_per_ft
  max_abs <- max(abs(pred - fitted(model)))
  r_insample <- cor(fitted(model), panel$new_area_per_ft)
  cat(sprintf("  %-13s max|manual - fitted()| = %.2e | in-sample cor(fitted, obs) = %.3f\n",
              forcing_var, max_abs, r_insample))
  invisible(max_abs)
}


# =============================================================================
# 7. RUN: fit both metrics, report the equation, save coefficients
# =============================================================================

response  <- read_csv(RESPONSE_CSV, show_col_types = FALSE)
intervals <- distinct(response, year_t1, year_t2)
forcing   <- run_interval_forcing_metrics(config, intervals)  # both metrics now
panel     <- assemble_panel(response, forcing, CONFINED_REACHES)

stopifnot(sum(is.na(panel$cum_excess_k)) == 0, sum(is.na(panel$sum_peak_k)) == 0)
cat("=== panel ===\n")
cat("rows:", nrow(panel),
    "| reaches:", nlevels(panel$river_segment),
    "| intervals:", nlevels(panel$interval), "\n")

# Fit both metrics; cum_excess is the model of record, sum_peak kept at hand.
models <- imap(MODEL_METRICS, function(m, k) fit_forcing_model(panel, m$var))

# Headline results, both metrics.
cat("\n=== Population forcing slope, both metrics ===\n")
slope_summary(models, MODEL_METRICS) %>% as.data.frame() %>% print(row.names = FALSE)

# Full fitted equation + portable coefficient CSV, per metric.
iwalk(models, function(m, k) {
  eq <- model_equation(m, MODEL_METRICS[[k]]$var)
  print_equation(eq, MODEL_METRICS[[k]]$label)
  out <- sprintf("data/forcing_model_coefficients_%s.csv", k)
  write_csv(coef_table(eq), out)
  cat("  -> wrote", out, "\n")
})

# Verification: equation extraction reproduces lme4's fit exactly.
cat("\n=== Verify: hand-built equation vs lme4 fitted() ===\n")
iwalk(models, function(m, k) verify_equation(m, panel, MODEL_METRICS[[k]]$var))


# =============================================================================
# 8. FIT SANITY CHECK (one lean plot; not a diagnostic battery)
# =============================================================================
# Per-reach: observed points, the reach's own fitted line (partial-pooled
# intercept + slope), and the shared population line. Confirms the equation
# tracks the data and shows the reach-to-reach spread in sensitivity. Primary
# metric only; interval_years and the interval RE held at 0 so lines compare.
prim     <- MODEL_METRICS[[PRIMARY_METRIC]]
eq_prim  <- model_equation(models[[PRIMARY_METRIC]], prim$var)
reach_ln <- eq_prim$reaches %>%
  mutate(river_segment = factor(river_segment, levels = levels(panel$river_segment)))

p_fit <- ggplot(panel, aes(.data[[prim$var]], new_area_per_ft)) +
  geom_abline(intercept = eq_prim$pop_intercept, slope = eq_prim$pop_slope,
              color = "#d95f0e", linewidth = 0.8) +
  geom_abline(data = reach_ln,
              aes(intercept = reach_intercept, slope = reach_slope),
              color = "#238b45", linewidth = 0.7) +
  geom_point(size = 1.3, alpha = 0.7, color = "#2c7fb8") +
  facet_wrap(~ river_segment) +
  labs(x = prim$label, y = "New area per ft (ft)",
       title = "Per-reach fit: reach equation (green) vs population (orange)",
       subtitle = sprintf("Model of record: %s. Points = observed intervals.", PRIMARY_METRIC)) +
  theme_minimal(base_size = 11)

ggsave("plots/forcing_model_reach_fit.png", p_fit, width = 10, height = 7, units = "in")
cat("\nWrote plots/forcing_model_reach_fit.png\n")
