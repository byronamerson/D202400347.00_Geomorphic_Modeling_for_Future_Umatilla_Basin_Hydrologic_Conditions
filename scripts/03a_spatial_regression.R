# =============================================================================
# 03a_spatial_regression.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1a: Spatial Analysis of Erosion Rates (Cross-Sectional Regression)
# =============================================================================
#
# Purpose: Test whether reach-scale unit stream power explains the spatial
#          pattern of erosion intensity across 39 river segments. This is the
#          foundational relationship for Phase 2 climate projections — if
#          omega predicts spatial rate variation, we can recompute omega under
#          future Q scenarios and project how rates shift.
#
# Model:
#   Median_rate_cw_i = f(omega_i, covariates_i) + epsilon_i
#
#   where rate is dimensionless (channel widths/yr) following the convention
#   of Nanson & Hickin (1986) for cross-system comparison. Stream power is
#   computed at Q2 (bankfull proxy) per Baker & Costa (1987).
#
# Candidate models (fit and compared via AICc):
#   M1: rate ~ omega                          (stream power only)
#   M2: rate ~ omega + confinement            (+ valley setting)
#   M3: rate ~ omega + confinement + sinuosity (+ planform)
#   M4: rate ~ log(omega)                     (power-law form)
#   M5: rate ~ log(omega) + confinement       (power-law + valley)
#   M6: rate ~ log(omega) + confinement + sinuosity + avulsion_susceptibility
#                                              (full model)
#
# Inputs:
#   - data/reach_attributes.csv  (from 02_reach_attributes_and_scaling.R)
#
# Outputs:
#   - data/phase1a_model_comparison.csv  — AICc table for candidate models
#   - data/phase1a_best_fit.rds          — fitted lm object (non-tabular)
#   - data/phase1a_diagnostics.csv       — residuals, leverage, influence
#   - figures/phase1a_omega_vs_rate.png   — primary scatterplot
#   - figures/phase1a_diagnostics.png     — residual diagnostic panel
#   - figures/phase1a_partial_effects.png — partial regression plots
#
# References:
#   Baker, V.R. & Costa, J.E. (1987). Flood power. In: Mayer & Nash (eds.),
#     Catastrophic Flooding, pp. 1-21. Allen & Unwin.
#   Burnham, K.P. & Anderson, D.R. (2002). Model Selection and Multimodel
#     Inference, 2nd ed. Springer.
#   Magilligan, F.J. (1992). Thresholds and the spatial variability of flood
#     power during extreme floods. Geomorphology, 5(3-5), 373-390.
#   Nanson, G.C. & Hickin, E.J. (1986). A statistical analysis of bank
#     erosion and channel migration in western Canada. GSA Bulletin, 97, 497-504.
#   Shields, F.D. et al. (2000). Large woody debris effects on planform and
#     rate of stream channel migration. Physical Geography, 21, 523-540.
#   Yochum, S.E. et al. (2017). Photographic guidance for selecting flow
#     resistance coefficients in high-gradient channels. USGS SIR 2017-5099.
#
# Style: Follows Tidyverse & Functional Programming Guidelines
# =============================================================================

library(tidyverse)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  reach_attr_path       = "data/reach_attributes.csv",
  output_dir            = "data/",
  figure_dir            = "plots/",
  model_comparison_csv  = "data/phase1a_model_comparison.csv",
  best_fit_rds          = "data/phase1a_best_fit.rds",
  diagnostics_csv       = "data/phase1a_diagnostics.csv",

  # ---- Plotting ----
  fig_width  = 10,
  fig_height = 6,
  fig_dpi    = 200,

  # ---- Literature thresholds for annotation (W/m²) ----
  # Magilligan (1992): ~300 W/m² minimum for major morphological adjustment
  # Yochum et al. (2017, SIR 2017-5099): thresholds from photographic surveys
  omega_thresholds = tribble(
    ~threshold_wm2, ~label,                          ~source,
    230,            "Widening credible (S<3%)",       "Yochum et al. 2017",
    300,            "Major adjustment minimum",       "Magilligan 1992",
    480,            "Avulsions/braiding credible",    "Yochum et al. 2017",
    700,            "Numerous eroded banks likely",   "Yochum et al. 2017"
  )
)

# =============================================================================
# 1. LOAD AND PREPARE DATA
# =============================================================================

load_reach_data <- function(cfg = config) {
  #' Read the reach attribute table and prepare factors for regression.
  #' Confinement and avulsion susceptibility are ordered factors to give
  #' meaningful coefficient interpretation.
  read_csv(cfg$reach_attr_path, show_col_types = FALSE) %>%
    mutate(
      # Ensure gage_id is character (CSV stores USGS site numbers as numeric)
      assigned_gage = as.character(assigned_gage),
      # Convert to ordered factors for regression
      confinement = factor(confinement,
        levels = c("unconfined", "partly_confined", "confined", "unclassified")
      ),
      avulsion_susceptibility = factor(avulsion_susceptibility,
        levels = c("not_assessed", "low", "conducive_limited",
                   "conducive_throughout", "infrastructure_conditional",
                   "high_historical")
      ),
      # Log-transformed stream power for power-law models
      log_omega = log(omega_wm2),
      # Flag reaches with zero or NA erosion rate (confined/stable reaches)
      has_erosion = !is.na(median_rate_cw) & median_rate_cw > 0
    )
}

# =============================================================================
# 2. MODEL FITTING
# =============================================================================

fit_candidate_models <- function(reach_tbl) {
  #' Fit the suite of candidate OLS models.
  #' Returns a named list of lm objects.
  #'
  #' Linear vs log-omega forms test whether the relationship is better
  #' described as additive (rate increases proportionally with omega) or
  #' multiplicative (rate responds to proportional changes in omega).
  #' Nanson & Hickin (1986) found power-law forms fit their Canadian dataset;
  #' Baker & Costa (1987) argued for nonlinear thresholds.

  # Filter to reaches with valid data for regression
  d <- reach_tbl %>%
    filter(
      !is.na(omega_wm2), omega_wm2 > 0,
      !is.na(median_rate_cw)
    )

  models <- list(
    # Linear forms
    M1_omega          = lm(median_rate_cw ~ omega_wm2, data = d),
    M2_omega_conf     = lm(median_rate_cw ~ omega_wm2 + confinement, data = d),
    M3_omega_conf_sin = lm(median_rate_cw ~ omega_wm2 + confinement + sinuosity,
                           data = d),

    # Log-transformed forms (power-law in original scale)
    M4_log_omega          = lm(median_rate_cw ~ log_omega, data = d),
    M5_log_omega_conf     = lm(median_rate_cw ~ log_omega + confinement, data = d),
    M6_full               = lm(median_rate_cw ~ log_omega + confinement +
                                sinuosity + avulsion_susceptibility, data = d)
  )

  message(sprintf("Fitted %d candidate models on %d reaches", length(models), nrow(d)))
  models
}

# =============================================================================
# 3. MODEL COMPARISON
# =============================================================================

compute_aicc <- function(model) {
  #' Compute AICc (corrected AIC for small samples) per
  #' Burnham & Anderson (2002). Essential when n/k ratio is modest
  #' (here n ~ 39, k ranges 2-10).
  n  <- nobs(model)
  k  <- length(coef(model)) + 1  # +1 for sigma²
  aic <- AIC(model)
  # AICc = AIC + 2k(k+1) / (n - k - 1)
  aic + (2 * k * (k + 1)) / (n - k - 1)
}

compare_models <- function(models) {
  #' Build a comparison table: AICc, delta-AICc, Akaike weights, R², adj-R².
  tibble(
    model     = names(models),
    k         = map_int(models, ~ length(coef(.x)) + 1),
    n         = map_int(models, nobs),
    r2        = map_dbl(models, ~ summary(.x)$r.squared),
    adj_r2    = map_dbl(models, ~ summary(.x)$adj.r.squared),
    rmse      = map_dbl(models, ~ sqrt(mean(residuals(.x)^2))),
    aicc      = map_dbl(models, compute_aicc)
  ) %>%
    mutate(
      delta_aicc   = aicc - min(aicc),
      # Akaike weights (Burnham & Anderson, 2002)
      rel_lik      = exp(-0.5 * delta_aicc),
      akaike_wt    = rel_lik / sum(rel_lik)
    ) %>%
    arrange(delta_aicc) %>%
    select(-rel_lik)
}

# =============================================================================
# 4. DIAGNOSTICS
# =============================================================================

extract_diagnostics <- function(model, reach_tbl) {
  #' Extract regression diagnostics for the best model.
  #' Returns a tibble with fitted values, residuals, leverage, Cook's D.

  d <- reach_tbl %>%
    filter(!is.na(omega_wm2), omega_wm2 > 0, !is.na(median_rate_cw))

  aug <- broom::augment(model) %>%
    bind_cols(d %>% select(rs, rs_num, confinement, avulsion_susceptibility))

  aug
}

# =============================================================================
# 5. VISUALIZATION
# =============================================================================

plot_omega_vs_rate <- function(reach_tbl, best_model, cfg = config) {
  #' Primary scatterplot: unit stream power vs dimensionless erosion rate.
  #' Color by confinement class, overlay regression line from best model.
  #' Annotate with literature thresholds (Magilligan 1992, Yochum et al. 2017).

  d <- reach_tbl %>%
    filter(!is.na(omega_wm2), omega_wm2 > 0, !is.na(median_rate_cw))

  # Determine if best model uses log(omega) or omega
  uses_log <- any(str_detect(names(coef(best_model)), "log_omega"))

  p <- ggplot(d, aes(x = omega_wm2, y = median_rate_cw)) +
    geom_point(aes(color = confinement, shape = confinement), size = 3, alpha = 0.8) +
    # Literature thresholds as vertical reference lines
    # Magilligan (1992): 300 W/m²; Yochum et al. (2017): 230, 480, 700 W/m²
    geom_vline(
      data = cfg$omega_thresholds,
      aes(xintercept = threshold_wm2),
      linetype = "dashed", color = "grey50", linewidth = 0.4
    ) +
    geom_text(
      data = cfg$omega_thresholds,
      aes(x = threshold_wm2, y = Inf, label = label),
      hjust = -0.05, vjust = 1.5, size = 2.5, color = "grey40", angle = 90
    ) +
    labs(
      x = expression("Unit stream power at Q"[2]*" ("*omega*", W/m"^2*")"),
      y = "Median erosion rate (channel widths/yr)",
      color = "Confinement",
      shape = "Confinement",
      title = "Phase 1a: Stream Power vs. Lateral Erosion Rate",
      subtitle = "39 Umatilla River reaches — DOGAMI CMZ study (1952-2024)",
      caption = paste0(
        "Stream power: Baker & Costa (1987); ",
        "thresholds: Magilligan (1992), Yochum et al. (2017)"
      )
    ) +
    theme_minimal(base_size = 11) +
    theme(
      legend.position = "bottom",
      plot.caption = element_text(size = 8, color = "grey50")
    )

  # Add trend line appropriate to model form
  if (uses_log) {
    p <- p + scale_x_log10() +
      geom_smooth(method = "lm", formula = y ~ x, se = TRUE,
                  color = "steelblue", linewidth = 0.8, alpha = 0.2)
  } else {
    p <- p +
      geom_smooth(method = "lm", formula = y ~ x, se = TRUE,
                  color = "steelblue", linewidth = 0.8, alpha = 0.2)
  }

  p
}

plot_diagnostics <- function(best_model) {
  #' Standard 4-panel residual diagnostic plot.

  d <- broom::augment(best_model)

  p1 <- ggplot(d, aes(x = .fitted, y = .resid)) +
    geom_point(alpha = 0.6) +
    geom_hline(yintercept = 0, linetype = "dashed") +
    geom_smooth(se = FALSE, color = "red", linewidth = 0.5) +
    labs(x = "Fitted values", y = "Residuals", title = "Residuals vs Fitted") +
    theme_minimal(base_size = 10)

  p2 <- ggplot(d, aes(sample = .std.resid)) +
    stat_qq(alpha = 0.6) +
    stat_qq_line(color = "red") +
    labs(title = "Normal Q-Q") +
    theme_minimal(base_size = 10)

  p3 <- ggplot(d, aes(x = .fitted, y = sqrt(abs(.std.resid)))) +
    geom_point(alpha = 0.6) +
    geom_smooth(se = FALSE, color = "red", linewidth = 0.5) +
    labs(x = "Fitted values", y = expression(sqrt("|Standardized residuals|")),
         title = "Scale-Location") +
    theme_minimal(base_size = 10)

  p4 <- ggplot(d, aes(x = .hat, y = .std.resid)) +
    geom_point(alpha = 0.6) +
    labs(x = "Leverage", y = "Standardized residuals",
         title = "Residuals vs Leverage") +
    theme_minimal(base_size = 10)

  # Combine with patchwork if available, otherwise use cowplot/gridExtra
  if (requireNamespace("patchwork", quietly = TRUE)) {
    (p1 + p2) / (p3 + p4) +
      patchwork::plot_annotation(
        title = "Phase 1a: Regression Diagnostics",
        theme = theme(plot.title = element_text(hjust = 0.5))
      )
  } else {
    message("Install 'patchwork' for combined diagnostic plot; saving individually.")
    list(residuals = p1, qq = p2, scale_location = p3, leverage = p4)
  }
}

# =============================================================================
# 6. PIPELINE
# =============================================================================

run_phase_1a <- function(cfg = config) {
  #' Execute Phase 1a spatial regression analysis.

  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$figure_dir, recursive = TRUE, showWarnings = FALSE)

  # ---- Load data ----
  message("--- Loading reach attributes ---")
  reach_tbl <- load_reach_data(cfg)
  message(sprintf("  %d reaches loaded, %d with valid omega and rate",
                  nrow(reach_tbl),
                  sum(!is.na(reach_tbl$omega_wm2) & !is.na(reach_tbl$median_rate_cw))))

  # ---- Fit candidate models ----
  message("\n--- Fitting candidate models ---")
  models <- fit_candidate_models(reach_tbl)

  # ---- Compare models ----
  message("\n--- Model comparison (AICc, Burnham & Anderson 2002) ---")
  comparison <- compare_models(models)
  print(comparison)
  write_csv(comparison, cfg$model_comparison_csv)
  message("Model comparison saved to: ", cfg$model_comparison_csv)

  # ---- Select best model ----
  best_name  <- comparison$model[1]
  best_model <- models[[best_name]]
  message(sprintf("\n--- Best model: %s (adj-R² = %.3f, delta-AICc = 0) ---",
                  best_name, comparison$adj_r2[1]))
  message("\nCoefficients:")
  print(summary(best_model))

  # Save best model object (.rds — non-tabular lm, justified)
  write_rds(best_model, cfg$best_fit_rds)
  message("Best model saved to: ", cfg$best_fit_rds)

  # ---- Extract diagnostics ----
  diag_tbl <- extract_diagnostics(best_model, reach_tbl)
  write_csv(diag_tbl, cfg$diagnostics_csv)
  message("Diagnostics saved to: ", cfg$diagnostics_csv)

  # ---- Figures ----
  message("\n--- Generating figures ---")

  p_main <- plot_omega_vs_rate(reach_tbl, best_model, cfg)
  ggsave(file.path(cfg$figure_dir, "phase1a_omega_vs_rate.png"),
         p_main, width = cfg$fig_width, height = cfg$fig_height, dpi = cfg$fig_dpi)

  p_diag <- plot_diagnostics(best_model)
  if (inherits(p_diag, "gg") || inherits(p_diag, "patchwork")) {
    ggsave(file.path(cfg$figure_dir, "phase1a_diagnostics.png"),
           p_diag, width = 10, height = 8, dpi = cfg$fig_dpi)
  }

  message("\n--- Phase 1a complete ---")

  list(
    reach_tbl   = reach_tbl,
    models      = models,
    comparison  = comparison,
    best_model  = best_model,
    diagnostics = diag_tbl
  )
}

# =============================================================================
# EXECUTE
# Run after 02_reach_attributes_and_scaling.R has produced reach_attributes.csv.
# results_1a <- run_phase_1a()
# =============================================================================
