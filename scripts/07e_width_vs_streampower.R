# =============================================================================
# 07e_width_vs_streampower.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 7e: is CESP a stream-power effect, or a channel-width effect wearing a
#           stream-power label?  RS 28-37
# =============================================================================
#
# Purpose: 07d found CESP (cumulative effective stream power on start-of-
#   interval width) beats cum_excess on AIC (-7.6) and on the interval random
#   effect (15.33 -> 12.08). This script asks whether that gain requires the
#   stream-power PRODUCT form at all, or whether it is reproduced by simply
#   letting narrow channels rework more -- flood volume and inverse width as
#   two ordinary main effects.
#
# -----------------------------------------------------------------------------
# THE TWO STORIES
# -----------------------------------------------------------------------------
# A. STREAM POWER. Energy per unit bed area is what does the work, so flood
#    volume and width must enter as a RATIO. Narrow channel concentrates the
#    same flood's energy; wide channel spreads it.
#
# B. WIDTH (incl. mean reversion). Narrow channels simply rework more, for
#    reasons that need no energy argument -- and specifically, a reach that is
#    anomalously narrow at t1 is more likely to widen over the following
#    interval, which produces new area directly. Under this story flood volume
#    and width are two SEPARATE main effects and their product adds nothing.
#
# Both stories predict "narrow reaches rework more", so a positive CESP result
# does not by itself distinguish them. Only the functional form does.
#
# -----------------------------------------------------------------------------
# THE TEST -- three nested models, one shared random structure
# -----------------------------------------------------------------------------
#   m_B2_same : cum_excess_k                          (07d's baseline)
#   m_ADD     : cum_excess_k + inv_width_k            (story B)
#   m_ENC     : cum_excess_k + inv_width_k + cesp_k   (encompassing)
#
# All three carry the identical random part from the model of record,
# (cum_excess_k || river_segment) + (1 | interval), so they are strictly nested
# and the likelihood-ratio tests below are valid -- unlike the 07d comparison,
# which was between non-nested models and could only be scored on AIC.
#
#   LRT 1  m_B2_same vs m_ADD : does channel width matter AT ALL?
#   LRT 2  m_ADD     vs m_ENC : does the stream-power product form add anything
#                               once width is already in as a plain main effect?
#
# LRT 2 is the decisive one:
#   significant  -> the ratio form carries information the two main effects
#                   cannot. The energy framing is earned; report CESP as CESP.
#   null         -> what 07d found is a width effect. Real result, wrong label.
#                   Report it as "narrow reaches rework more" and drop the
#                   stream-power language from the claim.
#
# NOTE on what cesp_k is doing in m_ENC. Within a reach,
# cesp_k = K * S_i * cum_excess / width, and S_i is constant, so cesp_k IS the
# cum_excess x inv_width interaction up to a per-reach scale factor. m_ENC is
# therefore the standard main-effects-plus-interaction encompassing model, with
# the interaction written in its physical units instead of as a bare product.
#
# -----------------------------------------------------------------------------
# KEY DECISIONS
# -----------------------------------------------------------------------------
# 1. inv_width_k = 1000 / width_start_ft, so LARGER MEANS NARROWER and a
#    positive coefficient reads "narrower channels rework more" -- the
#    direction story B predicts. Scaled by 1000 to sit near the other
#    predictors rather than at ~0.003.
#
# 2. Start-of-interval width throughout, for the reason settled in 07d: the
#    end width contains the new area that IS the response, to the extent the
#    reach widened rather than merely migrated. Byron's objection to the
#    original framing was correct -- pure lateral migration cancels (new area
#    ~= abandoned area) and contaminates nothing. But every reach in this panel
#    shows net widening over the record (w_max/w_min 1.46 to 2.82), so the
#    condition for contamination is met empirically here even though it is not
#    automatic. The migration-vs-widening diagnostic below settles how strongly.
#
# 3. The random part is HELD FIXED across the three models, with the reach
#    random slope on cum_excess_k (not on cesp_k). This is what buys nesting.
#    m_CESP from 07d, whose random slope is on cesp_k, is carried in the
#    scorecard for continuity but is NOT part of either LRT.
#
# 4. Convergence is checked properly rather than noted and ignored: 07d threw
#    four max|grad| warnings and this script adds more terms. Per
#    ?lme4::convergence, allFit across all optimizers is lme4's own gold
#    standard -- if the optimizers agree to within much less than the
#    differences being interpreted, the warnings are false positives. The
#    stricter-tolerance and scaled-predictor remedies (their steps 2 and 3)
#    are run first because they are nearly free.
#
# Inputs:
#   - scripts/07d_cesp_forcing_model.R  (sourced: panel_cesp, m_CESP, m_B2_same;
#     which in turn sources 07 for panel and m_B2)
# Outputs:
#   - data/width_vs_streampower_scorecard.csv
#   - plots/width_vs_streampower_partial.png
#
# Requires optimx and dfoptim for the full optimizer set (installed 2026-09-17).
# Style: Tidyverse & FP guidelines; contracts per docs/lingua.md.
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(lme4)

source("scripts/07d_cesp_forcing_model.R")   # panel_cesp, m_CESP, m_B2_same

# Set FALSE to skip the optimizer sweep (it refits every model ~7 times).
RUN_ALLFIT <- TRUE


# =============================================================================
# 1. PREDICTOR
# =============================================================================

add_inverse_width <- function(panel_tbl, scale_ft = 1000) {
  #' Purpose: add the inverse start-of-interval channel width, the predictor
  #'   that lets "narrow channels rework more" compete with CESP on its own
  #'   terms rather than only inside a ratio.
  #' In:  panel_tbl -- the 07d CESP panel, carrying width_start_ft;
  #'      scale_ft  -- numerator, purely for readable coefficient magnitudes.
  #' Out: panel_tbl plus inv_width_k (1000/ft), LARGER = NARROWER.
  #' Decisions: the reciprocal rather than the width itself, so that this term
  #'   and cesp_k share the same functional dependence on width. If width
  #'   entered linearly, LRT 2 would partly be testing the reciprocal shape
  #'   rather than the ratio structure, which is not the question.
  panel_tbl %>%
    mutate(inv_width_k = scale_ft / width_start_ft)
}

panel_wsp <- panel_cesp %>%
  add_inverse_width() %>%
  # Length-normalized abandoned area, for the widening-vs-migration diagnostic
  # below. Script 06 normalizes new area but leaves abandoned area in ft2;
  # both share the same length_ft denominator, so this puts the two on the
  # same footing as new_area_per_ft.
  mutate(abandoned_area_per_ft = abandoned_area_ft2 / length_ft)


# =============================================================================
# 2. IS IT WIDENING OR MIGRATION?  (Byron's objection, measured)
# =============================================================================
# The endogeneity concern in 07d requires new area to systematically EXCEED
# abandoned area. If the reaches mostly migrate, the two track each other and
# the concern is weak; if they widen, it is live. Measured, not assumed.

migration_check <- panel_wsp %>%
  summarize(
    r_new_vs_abandoned = cor(new_area_per_ft, abandoned_area_per_ft,
                             method = "spearman", use = "complete.obs"),
    mean_new           = mean(new_area_per_ft, na.rm = TRUE),
    mean_abandoned     = mean(abandoned_area_per_ft, na.rm = TRUE),
    frac_net_widening  = mean(new_area_per_ft > abandoned_area_per_ft,
                              na.rm = TRUE)
  )

cat("\n=== Widening vs migration (does the 07d endogeneity concern apply?) ===\n")
cat("Tight 1:1 new-vs-abandoned = migration dominates, concern weak.\n")
cat("New systematically exceeding abandoned = net widening, concern live.\n")
as.data.frame(migration_check) %>% print(digits = 3, row.names = FALSE)


# =============================================================================
# 3. COLLINEARITY -- read before trusting any single coefficient
# =============================================================================
# cesp_k is a ratio built from cum_excess_k and inv_width_k, so it is
# correlated with both by construction. Strong correlation does not invalidate
# the LRTs (which compare model fits, not individual coefficients) but it does
# mean the three fixed effects in m_ENC should not be interpreted separately.

cat("\n=== Predictor correlations (Spearman) ===\n")
panel_wsp %>%
  select(cum_excess_k, inv_width_k, cesp_k) %>%
  cor(method = "spearman") %>%
  round(3) %>%
  print()


# =============================================================================
# 4. FIT -- three nested models, identical random structure
# =============================================================================

m_ADD <- lmer(
  new_area_per_ft ~ cum_excess_k + inv_width_k + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel_wsp, REML = TRUE
)

m_ENC <- lmer(
  new_area_per_ft ~ cum_excess_k + inv_width_k + cesp_k + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel_wsp, REML = TRUE
)

# m_B2_same comes from 07d and already has this exact random structure, but it
# was fitted on panel_cesp. panel_wsp only adds a column, so the rows are
# identical -- asserted rather than assumed.
stopifnot(nrow(panel_wsp) == nrow(panel_cesp))
m_BASE <- lmer(
  new_area_per_ft ~ cum_excess_k + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel_wsp, REML = TRUE
)


# =============================================================================
# 5. THE TWO LIKELIHOOD-RATIO TESTS
# =============================================================================
# Refit with ML: REML likelihoods are not comparable across different fixed
# effects. Same reason 07 refits before its interval_years LRT.

m_BASE_ml <- update(m_BASE, REML = FALSE)
m_ADD_ml  <- update(m_ADD,  REML = FALSE)
m_ENC_ml  <- update(m_ENC,  REML = FALSE)

cat("\n=== LRT 1: does channel width matter at all? ===\n")
cat("m_BASE (cum_excess) vs m_ADD (+ inverse width)\n")
print(anova(m_BASE_ml, m_ADD_ml))

cat("\n=== LRT 2 (DECISIVE): does the stream-power ratio add anything ===\n")
cat("    beyond flood volume and width as separate main effects?\n")
cat("m_ADD vs m_ENC (+ cesp_k)\n")
print(anova(m_ADD_ml, m_ENC_ml))

cat("\n--- how to read LRT 2 ---\n")
cat("significant -> the ratio carries information the main effects cannot;\n")
cat("               the stream-power framing is earned.\n")
cat("null        -> 07d found a WIDTH effect. Real, but report it as\n")
cat("               'narrower reaches rework more', not as stream power.\n")


# =============================================================================
# 6. SCORECARD
# =============================================================================
# Helper definitions are inherited from 07d (sd_interval, r2_marginal, aic_ml,
# forcing_slope) so the numbers stay directly comparable to that table.

scorecard_wsp <- tibble(
  model = c("m_BASE  cum_excess only",
            "m_ADD   cum_excess + inv_width",
            "m_ENC   cum_excess + inv_width + cesp",
            "m_CESP  cesp only (07d, non-nested)"),
  sd_interval = c(sd_interval(m_BASE), sd_interval(m_ADD),
                  sd_interval(m_ENC),  sd_interval(m_CESP)),
  R2_marg     = c(r2_marginal(m_BASE), r2_marginal(m_ADD),
                  r2_marginal(m_ENC),  r2_marginal(m_CESP)),
  aic_ml      = c(aic_ml(m_BASE), aic_ml(m_ADD),
                  aic_ml(m_ENC),  aic_ml(m_CESP))
)

cat("\n===============  WIDTH vs STREAM POWER SCORECARD  ===============\n")
scorecard_wsp %>%
  mutate(sd_interval = round(sd_interval, 2),
         R2_marg     = round(R2_marg, 3),
         aic_ml      = round(aic_ml, 1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

write_csv(scorecard_wsp, "data/width_vs_streampower_scorecard.csv")

cat("\n=== m_ADD fixed effects ===\n")
cat("Positive inv_width_k = narrower channels rework more (story B's direction).\n")
print(round(summary(m_ADD)$coefficients, 3))

cat("\n=== m_ENC fixed effects (collinear -- read the LRT, not these) ===\n")
print(round(summary(m_ENC)$coefficients, 3))


# =============================================================================
# 7. CONVERGENCE
# =============================================================================
# ?lme4::convergence, in its recommended order. The warnings may well be false
# positives, but with a positive finding riding on ~7 AIC units that has to be
# demonstrated rather than assumed.

cat("\n=== Convergence step 1: stricter stopping tolerances ===\n")
strict_tol <- lmerControl(optCtrl = list(xtol_abs = 1e-8, ftol_abs = 1e-8))
m_ENC_tight <- update(m_ENC, control = strict_tol)
cat("logLik, default tol:", round(as.numeric(logLik(m_ENC)), 4), "\n")
cat("logLik, strict  tol:", round(as.numeric(logLik(m_ENC_tight)), 4), "\n")
cat("max|grad| default  :",
    signif(max(abs(m_ENC@optinfo$derivs$gradient)), 3), "\n")
cat("max|grad| strict   :",
    signif(max(abs(m_ENC_tight@optinfo$derivs$gradient)), 3), "\n")

cat("\n=== Convergence step 2: scaled predictors ===\n")
# Predictors here span 1.6 (inv_width_k) to 212 (cesp_k). Disparate scales are
# a standard cause of these warnings and scaling is a pure reparameterization:
# the fit is identical, only the coefficients move.
panel_scaled <- panel_wsp %>%
  mutate(across(c(cum_excess_k, inv_width_k, cesp_k, interval_years),
                ~ as.numeric(scale(.x))))
m_ENC_scaled <- update(m_ENC, data = panel_scaled)
cat("logLik, scaled     :", round(as.numeric(logLik(m_ENC_scaled)), 4),
    " (should match the unscaled fit)\n")
cat("max|grad| scaled   :",
    signif(max(abs(m_ENC_scaled@optinfo$derivs$gradient)), 3), "\n")


summarize_allfit <- function(model, model_name, model_data) {
  #' Purpose: refit one model with every available optimizer and report how far
  #'   the answers spread, which is how ?lme4::convergence says to decide
  #'   whether a max|grad| warning is a false positive.
  #' In:  model      -- a fitted merMod;
  #'      model_name -- label for the output row;
  #'      model_data -- the data frame the model was fitted to, passed
  #'        explicitly because allFit works by calling update() and the help
  #'        page warns it is fragile about where variables live.
  #' Out: one-row tibble: optimizers attempted, how many succeeded, the spread
  #'   in log-likelihood, and the spread in the interval random-effect SD.
  #' Decisions: the interval RE is tracked alongside logLik because it is the
  #'   quantity the projection actually consumes -- a fit can be stable in
  #'   likelihood while its variance components wander.
  af <- suppressWarnings(suppressMessages(
    lme4::allFit(model, data = model_data, verbose = FALSE)
  ))
  ss <- summary(af)

  lliks <- ss$llik[ss$which.OK]
  # sdcor columns are named by grouping factor; the interval intercept SD is
  # the one the projection carries as its uncertainty band.
  sd_col <- grep("^interval", colnames(ss$sdcor), value = TRUE)[1]
  sds    <- if (!is.na(sd_col)) ss$sdcor[ss$which.OK, sd_col] else NA_real_

  tibble(
    model            = model_name,
    n_optimizers     = length(ss$which.OK),
    n_converged      = sum(ss$which.OK),
    llik_spread      = max(lliks) - min(lliks),
    interval_sd_min  = min(sds, na.rm = TRUE),
    interval_sd_max  = max(sds, na.rm = TRUE)
  )
}

if (RUN_ALLFIT) {
  cat("\n=== Convergence step 3: allFit across all optimizers ===\n")
  cat("lme4's gold standard. If llik_spread is far smaller than the AIC gaps\n")
  cat("being interpreted (~7 units), the warnings are false positives.\n")
  cat("Running -- this refits each model about seven times.\n\n")

  allfit_report <- bind_rows(
    summarize_allfit(m_BASE, "m_BASE", panel_wsp),
    summarize_allfit(m_ADD,  "m_ADD",  panel_wsp),
    summarize_allfit(m_ENC,  "m_ENC",  panel_wsp),
    summarize_allfit(m_CESP, "m_CESP", panel_wsp)
  )

  allfit_report %>%
    mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
    as.data.frame() %>%
    print(row.names = FALSE)
} else {
  cat("\n(allFit skipped -- set RUN_ALLFIT <- TRUE to run it)\n")
  allfit_report <- NULL
}


# =============================================================================
# 8. PARTIAL-EFFECT PLOT
# =============================================================================
# Response against inverse width, with flood forcing held at its mean by using
# m_ADD's partial residuals. If story B is the whole story, this is the picture
# that carries the finding -- and it is a much easier one to present than a
# stream-power argument.

partial_df <- panel_wsp %>%
  mutate(
    partial_resid = resid(m_ADD) +
      fixef(m_ADD)[["inv_width_k"]] * inv_width_k
  )

p_partial <- ggplot(partial_df, aes(inv_width_k, partial_resid)) +
  geom_smooth(method = "lm", formula = y ~ x, color = "#d95f0e",
              fill = "grey85", linewidth = 0.8) +
  geom_point(aes(color = river_segment), size = 1.8, alpha = 0.8) +
  labs(
    x = "Inverse start-of-interval width (1000 / ft)  -- right = narrower",
    y = "New area per ft, flood forcing removed (ft)",
    title = "Do narrower reaches rework more, independent of flood size?",
    subtitle = "Partial effect of inverse width from m_ADD",
    color = "River segment"
  ) +
  theme_minimal(base_size = 12)

ggsave("plots/width_vs_streampower_partial.png", p_partial,
       width = 9, height = 6, units = "in")

cat("\nWrote data/width_vs_streampower_scorecard.csv",
    "and plots/width_vs_streampower_partial.png\n")

# Leaves in env: panel_wsp, m_BASE, m_ADD, m_ENC, m_ENC_tight, m_ENC_scaled,
# scorecard_wsp, migration_check, allfit_report.
