# =============================================================================
# x16_forcing_response_curvature.R
# Umatilla River Discharge-Channel Migration Analysis
# Does the OBSERVED forcing->migration relationship flatten at high forcing?
# =============================================================================
#
# Decides whether a concave forcing->migration form is DATA-SUPPORTED or would be a
# pure extrapolation-regularization judgment. Two reads on the model of record's
# in-sample behavior:
#   1. Conditional residuals vs forcing. If the linear forcing term is right, the
#      residuals have no trend with forcing. A downward trend at high forcing =
#      the linear slope is too steep there = concavity (in-sample over-prediction).
#   2. AIC of the same model structure with the forcing entered linear vs two
#      simple concave transforms (sqrt, log1p). ML fits (AIC needs ML, not REML).
#      Lower AIC for a concave form = the data prefer diminishing returns of
#      extreme forcing.
#
# Caveat carried into the reading: the observed record has FEW high-forcing
# intervals, so this test has limited power in the tail. If concavity is invisible
# in-sample, that itself says the projection's tail form is a judgment call, not
# something the data pin down.
#
# NB projection-only question. The model of record stays linear (settled); this
# only informs how we extrapolate the projection.
#
# Reuse: 08 (panel, models, fit_forcing_model). Style: Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(purrr)
library(ggplot2)
library(lme4)

source("scripts/08_forcing_model.R")   # panel, models, fit_forcing_model, MODEL_METRICS

FORCING_VAR <- "cum_excess_k"
m_lin       <- models[["cum_excess"]]


# =============================================================================
# 1. CONDITIONAL RESIDUALS vs FORCING  (the direct over-prediction signal)
# =============================================================================

resid_df <- panel %>%
  mutate(.resid = resid(m_lin))

p_resid <- ggplot(resid_df, aes(.data[[FORCING_VAR]], .resid)) +
  geom_hline(yintercept = 0, color = "grey50") +
  geom_point(alpha = 0.6, color = "#2c7fb8") +
  geom_smooth(method = "loess", se = TRUE, color = "#d95f0e") +
  labs(x = "cum_excess_k (1000 cfs-days)", y = "Residual (observed - fitted), ft",
       title = "Model-of-record residuals vs forcing",
       subtitle = "Flat = linear form OK; downward trend at high forcing = concavity") +
  theme_minimal(base_size = 11)

ggsave("plots/curvature_residuals.png", p_resid, width = 9, height = 6, units = "in")


# =============================================================================
# 2. LINEAR vs CONCAVE FORMS  (same structure, transformed forcing, ML for AIC)
# =============================================================================

panel_t <- panel %>%
  mutate(cum_excess_sqrt = sqrt(cum_excess_k),   # diminishing returns, unbounded
         cum_excess_log   = log1p(cum_excess_k))  # stronger flattening

FORMS <- c(linear = "cum_excess_k", sqrt = "cum_excess_sqrt", log1p = "cum_excess_log")

fits <- imap(FORMS, ~ fit_forcing_model(panel_t, .x, REML = FALSE))  # ML for AIC comparison

aic_tbl <- imap_dfr(fits, function(m, k) {
  v <- FORMS[[k]]
  co <- summary(m)$coefficients
  tibble(form        = k,
         forcing_var = v,
         AIC         = round(AIC(m), 1),
         dAIC        = NA_real_,               # filled below
         slope       = round(co[v, "Estimate"], 3),
         slope_t     = round(co[v, "t value"], 2))
}) %>%
  mutate(dAIC = round(AIC - min(AIC), 1)) %>%
  arrange(AIC)

cat("\n=== Forcing form comparison (ML; lower AIC preferred) ===\n")
as.data.frame(aic_tbl) %>% print(row.names = FALSE)


# =============================================================================
# 3. USAGE
# =============================================================================
# source("explore/x16_forcing_response_curvature.R")
#   -> prints the AIC table; writes plots/curvature_residuals.png
# Read: a clear negative residual trend + a concave form winning AIC by >~2 =>
#   concavity is real, use it for the projection tail. A flat residual cloud +
#   AIC within ~2 => in-sample data don't support concavity; the projection tail
#   form is a conservative judgment call (report with explicit uncertainty).
# =============================================================================
