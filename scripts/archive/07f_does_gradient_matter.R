# =============================================================================
# 07f_does_gradient_matter.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 7f: is the 07e result specific stream power, or just flood per width?
# =============================================================================
#
# Purpose: 07e showed the RATIO form (flood volume divided by channel width)
#   carries real signal that neither flood volume nor width carries alone
#   (LRT chi2 15.5, p = 8.3e-05). But cesp_k also contains reach gradient:
#
#       cesp_k = constant x gradient x flood volume / width
#
#   Gradient is one fixed number per reach and spans only 0.0044-0.0071 across
#   the ten reaches (1.6x), while width spans 119-612 ft (5x) and varies
#   through time. So gradient may be contributing nothing. 07c already found
#   it useless as a reach-level predictor of flood sensitivity.
#
#   This decides what the finding is called in the report:
#     gradient earns its place -> specific stream power
#     gradient is dead weight  -> flood volume per unit width, which is a
#                                 simpler and more honest label
#
# THE COMPARISON. qw_k is cesp_k with every reach assigned the PANEL-MEAN
#   gradient instead of its own. Same units, same scale, same everything --
#   the only difference is whether gradient varies by reach. So any difference
#   in fit is gradient's entire contribution, isolated.
#
#   m_CESP vs m_QW is the headline: identical structure, identical parameter
#   count, so AIC is directly comparable and no LRT is needed or valid.
#
# ALSO: everything is fitted on SCALED predictors. 07e found the unscaled
#   parameterization ill-conditioned -- scaling dropped max|grad| from 0.066 to
#   0.0005 and found a better optimum (logLik -615.62 -> -615.29). Scaling is a
#   pure reparameterization, so it changes no test result, only the numerical
#   behaviour and the coefficient units. This doubles as the insurance re-run
#   of 07e's LRT 2.
#
# Inputs:  scripts/07e_width_vs_streampower.R (sourced: panel_wsp, helpers)
# Outputs: data/gradient_contribution_scorecard.csv
#
# Style: Tidyverse & FP guidelines; contracts per docs/lingua.md.
# =============================================================================

library(dplyr)
library(readr)
library(lme4)

source("scripts/07e_width_vs_streampower.R")   # panel_wsp + 07d helpers


# =============================================================================
# 1. THE GRADIENT-FREE COUNTERPART
# =============================================================================

add_flat_gradient_forcing <- function(panel_tbl) {
  #' Purpose: build qw_k -- the same forcing as cesp_k but with reach gradient
  #'   held constant, so the two differ ONLY in whether gradient varies.
  #' In:  panel_tbl -- the 07e panel, carrying cesp_k and gradient.
  #' Out: panel_tbl plus qw_k, in the same MJ/m2-equivalent units as cesp_k.
  #' Decisions: built by rescaling cesp_k rather than recomputing from the
  #'   constants, which guarantees the two series are identical in every
  #'   respect except the gradient term -- no chance of a stray unit or
  #'   rounding difference masquerading as a gradient effect. The mean is taken
  #'   over the ten REACHES, not over panel rows, so reaches with more
  #'   intervals do not pull it.
  mean_gradient <- panel_tbl %>%
    distinct(river_segment, gradient) %>%
    pull(gradient) %>%
    mean()

  panel_tbl %>%
    mutate(qw_k = cesp_k * mean_gradient / gradient)
}

panel_grad <- panel_wsp %>%
  add_flat_gradient_forcing() %>%
  mutate(across(c(cum_excess_k, inv_width_k, cesp_k, qw_k, interval_years),
                ~ as.numeric(scale(.x)),
                .names = "{.col}_s"))

cat("\n=== How different are the two forcings? ===\n")
cat("If gradient does nothing, these are nearly the same variable.\n")
cat("Spearman correlation, cesp_k vs qw_k:",
    round(cor(panel_grad$cesp_k, panel_grad$qw_k, method = "spearman"), 4), "\n")
cat("Reach gradients span:",
    paste(round(range(panel_grad$gradient), 4), collapse = " to "),
    sprintf("(%.2fx)", max(panel_grad$gradient) / min(panel_grad$gradient)), "\n")


# =============================================================================
# 2. HEADLINE -- same structure, same df, AIC directly comparable
# =============================================================================

m_CESP_s <- lmer(
  new_area_per_ft ~ cesp_k_s + interval_years_s +
    (cesp_k_s || river_segment) + (1 | interval),
  data = panel_grad, REML = TRUE
)

m_QW_s <- lmer(
  new_area_per_ft ~ qw_k_s + interval_years_s +
    (qw_k_s || river_segment) + (1 | interval),
  data = panel_grad, REML = TRUE
)

headline <- tibble(
  model = c("m_CESP  gradient x flood / width  (specific stream power)",
            "m_QW    flood / width              (gradient held flat)"),
  forcing_slope = c(forcing_slope(m_CESP_s, "cesp_k_s"),
                    forcing_slope(m_QW_s,   "qw_k_s")),
  sd_interval   = c(sd_interval(m_CESP_s), sd_interval(m_QW_s)),
  R2_marg       = c(r2_marginal(m_CESP_s), r2_marginal(m_QW_s)),
  aic_ml        = c(aic_ml(m_CESP_s), aic_ml(m_QW_s))
)

cat("\n===============  DOES GRADIENT EARN ITS PLACE?  ===============\n")
cat("Identical structure and parameter count -- AIC is directly comparable.\n\n")
headline %>%
  mutate(sd_interval = round(sd_interval, 2),
         R2_marg     = round(R2_marg, 3),
         aic_ml      = round(aic_ml, 1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

delta_aic <- headline$aic_ml[1] - headline$aic_ml[2]
cat(sprintf("\nAIC(CESP) - AIC(QW) = %+.1f\n", delta_aic))
cat("Within about 2 units either way -> gradient contributes nothing;\n")
cat("  call the finding 'flood volume per unit width' and drop gradient.\n")
cat("CESP lower by more than ~4 -> gradient earns its place;\n")
cat("  'specific stream power' is the right label.\n")

write_csv(headline, "data/gradient_contribution_scorecard.csv")


# =============================================================================
# 3. SUPPORTING -- 07e's LRT 2, re-run scaled, for both forcings
# =============================================================================
# Same nested trio as 07e (random slope on cum_excess_k throughout, which is
# what buys nesting), now on the better-conditioned scaled predictors. Doubles
# as the insurance re-run of 07e's decisive test.

m_ADD_s <- lmer(
  new_area_per_ft ~ cum_excess_k_s + inv_width_k_s + interval_years_s +
    (cum_excess_k_s || river_segment) + (1 | interval),
  data = panel_grad, REML = FALSE
)

m_ENC_cesp_s <- update(m_ADD_s, . ~ . + cesp_k_s)
m_ENC_qw_s   <- update(m_ADD_s, . ~ . + qw_k_s)

cat("\n=== LRT: ratio form beyond flood volume + width (scaled refit) ===\n")
cat("-- with gradient (cesp) --\n")
print(anova(m_ADD_s, m_ENC_cesp_s))
cat("\n-- without gradient (qw) --\n")
print(anova(m_ADD_s, m_ENC_qw_s))
cat("\nBoth strongly significant and similar -> the RATIO is doing the work,\n")
cat("not the gradient. 07e's finding survives either way.\n")

# Leaves in env: panel_grad, m_CESP_s, m_QW_s, m_ADD_s, m_ENC_cesp_s,
# m_ENC_qw_s, headline, delta_aic.
