# =============================================================================
# x02_peak_covariate_check.R   (EXPLORATORY -- not folded into 07)
# -----------------------------------------------------------------------------
# Question: does daily PEAK flow add anything to the forcing model beyond
# cumulative excess and elapsed time?
#   cum_excess_k    = integrated work (volume of above-Q2 flow)   -- already in
#   q_peak_daily_cfs = competence (can the flow mobilize bank at all) -- NEW
#
# n_events is deliberately NOT tested: it is the count of the same exceedance
# spans that generate cum_excess and contain the peak, so it carries no
# information independent of what is already in the model.
#
# Caveats we are watching:
#   - peak and cum_excess are interval-level -> ~15 effective points, not 139.
#   - they are correlated; we can test their JOINT contribution cleanly, but the
#     peak-vs-volume split will be weakly identified (see VIF below).
#
# Fits on the live `panel` from 07 (RS 28-37). Source 07 first if not present.
# =============================================================================

library(lme4)
library(dplyr)

stopifnot(exists("panel"), "q_peak_daily_cfs" %in% names(panel))

panel <- panel %>% mutate(q_peak_k = q_peak_daily_cfs / 1000)  # per-1000 cfs, matches cum_excess_k


# ---- 1. How entangled are peak and volume? (interval level) -----------------
iv <- distinct(panel, interval, cum_excess_k, q_peak_k, interval_years)
preds <- c("cum_excess_k", "q_peak_k", "interval_years")

cat("=== Correlation among interval-level predictors (n =", nrow(iv), "intervals) ===\n")
print(round(cor(iv[, preds]), 2))

vif1 <- function(p, d) 1 / (1 - summary(
  lm(reformulate(setdiff(preds, p), p), d))$r.squared)
cat("\n=== VIF (interval level; >~5 = poorly separable) ===\n")
print(round(vapply(preds, vif1, numeric(1), d = iv), 2))


# ---- 2. Does peak earn its place? m_A structure (random intercepts) ---------
# ML fits so the fixed-effect LRT is valid.
base_A <- lmer(new_area_per_ft ~ cum_excess_k + interval_years +
                 (1 | river_segment) + (1 | interval),
               panel, REML = FALSE)
peak_A <- update(base_A, . ~ . + q_peak_k)

cat("\n=== m_A + peak: fixed effects (ML) ===\n")
print(round(summary(peak_A)$coefficients, 3))
cat("\n=== LRT: peak added to m_A ===\n")
print(anova(base_A, peak_A))


# ---- 3. Same test in the model of record (m_B2 structure) -------------------
base_B2 <- lmer(new_area_per_ft ~ cum_excess_k + interval_years +
                  (cum_excess_k || river_segment) + (1 | interval),
                panel, REML = FALSE)
peak_B2 <- update(base_B2, . ~ . + q_peak_k)

cat("\n=== m_B2 + peak: fixed effects (ML) ===\n")
print(round(summary(peak_B2)$coefficients, 3))
cat("\n=== LRT: peak added to m_B2 (record structure) ===\n")
print(anova(base_B2, peak_B2))

# Read: a big drop in the cum_excess_k t-value when peak enters (vs its ~3.0 in
# 07) is the collinearity showing up -- the two share credit. Look at the JOINT
# picture (both terms + the LRT) before reading either coefficient alone.
