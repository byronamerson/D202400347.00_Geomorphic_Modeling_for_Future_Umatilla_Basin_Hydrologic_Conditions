# =============================================================================
# 07b_lmm_sensitivity_and_robustness.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 7 (companion): exploratory checks behind the 07 model choices
# =============================================================================
#
# A lab-notebook of the "throwaway" checks that informed the settled model in
# scripts/07_mixed_forcing_model.R. Kept for reproducibility / audit. None of
# these are needed to run the settled analysis; 07 stands on its own.
#
# Contents:
#   1. interval_years leverage: drop the 1952-1974 singleton
#   2. Random slope, correlated form (m_B) -- REJECTED (corr 0.99, no converge)
#   3. Random slope, uncorrelated form (m_B2) -- the derivation kept in 07
#   4. Response-scale transform diagnostic (identity vs sqrt vs log1p)
#
# The sqrt robustness comparison is NOT here -- it lives in 07 as part of the
# settled record. Depends on m_A, m_B2, panel from 07; sources it if not already
# in the session.
# =============================================================================

library(lme4)
if (!exists("m_A") || !exists("panel")) source("scripts/07_mixed_forcing_model.R")


# ---- 1. interval_years leverage: drop the 1952-1974 singleton (RS 37, 22 yr) -
# That interval exists for one reach only (missing 1964 photo) and is far longer
# than any other -> a lone high-leverage point on the interval_years axis.
m_A_nosgl <- update(m_A, data = droplevels(subset(panel, interval != "1952-1974")))
round(rbind(
  interval_years_full  = summary(m_A)$coefficients["interval_years", ],
  interval_years_nosgl = summary(m_A_nosgl)$coefficients["interval_years", ],
  cum_excess_k_full    = summary(m_A)$coefficients["cum_excess_k", ],
  cum_excess_k_nosgl   = summary(m_A_nosgl)$coefficients["cum_excess_k", ]
), 3)
# Result: cum_excess_k unchanged (bulletproof); interval_years 3.35 -> 2.45
# (still significant). Baseline accrual is real; its magnitude is leverage-soft.


# ---- 2. Random slope, CORRELATED form (m_B) -- REJECTED ----------------------
# Full (cum_excess_k | river_segment): intercept var + slope var + their corr.
m_B <- lmer(
  new_area_per_ft ~ cum_excess_k + interval_years +
    (cum_excess_k | river_segment) + (1 | interval),
  data = panel, REML = TRUE
)
cat("singular fit? ", isSingular(m_B), "\n\n")
print(VarCorr(m_B), comp = "Std.Dev.")
cat("\n-- earns its place? (REML LRT, same fixed effects) --\n")
print(anova(m_A, m_B, refit = FALSE))
cat("\n-- per-reach realized forcing slopes (sorted) --\n")
print(round(sort(coef(m_B)$river_segment[, "cum_excess_k"]), 2))
# Result: not singular, BUT a convergence warning and intercept-slope corr pinned
# at 0.99 -> over-parameterized for 13 reaches. Rejected in favor of m_B2.


# ---- 3. Random slope, UNCORRELATED form (m_B2) -- kept in 07 -----------------
# Refit here alongside the correlation-cost test (m_B2 nested in m_B), which is
# the piece unique to this script; the m_A-vs-m_B2 test also lives in 07.
m_B2 <- lmer(
  new_area_per_ft ~ cum_excess_k + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel, REML = TRUE
)
cat("singular fit? ", isSingular(m_B2), "\n\n")
print(VarCorr(m_B2), comp = "Std.Dev.")
cat("\n-- uncorrelated slope vs m_A (does slope variance earn its place?) --\n")
print(anova(m_A, m_B2, refit = FALSE))
cat("\n-- does the dropped correlation cost anything? (m_B2 nested in m_B) --\n")
print(anova(m_B2, m_B, refit = FALSE))
cat("\n-- per-reach slopes, uncorrelated model (sorted) --\n")
print(round(sort(coef(m_B2)$river_segment[, "cum_excess_k"]), 2))
# Result: m_B2 converges clean; slope variance decisive (p ~ 5e-5). Dropping the
# correlation is statistically detectable (p ~ 0.003) but the corr was the
# untrustworthy 0.99 boundary estimate and changes no conclusion -> keep m_B2.


# ---- 4. Response-scale transform diagnostic (identity vs sqrt vs log1p) ------
# How skewed / heteroscedastic are the residuals, and does a transform fix it?
skew <- function(x) mean((x - mean(x))^3) / sd(x)^3
diag_fit <- function(m, label) {
  r <- resid(m); f <- fitted(m)
  data.frame(
    scale      = label,
    resid_skew = round(skew(r), 2),                             # ~0 = symmetric
    hetero_rho = round(cor(abs(r), f, method = "spearman"), 2), # >0 = spread grows w/ fit
    conv_warn  = length(m@optinfo$conv$lme4$messages) > 0
  )
}
m_id   <- m_B2
m_sqrt <- update(m_B2, sqrt(new_area_per_ft)  ~ .)
m_log  <- update(m_B2, log1p(new_area_per_ft) ~ .)
do.call(rbind, list(
  diag_fit(m_id,   "identity"),
  diag_fit(m_sqrt, "sqrt"),
  diag_fit(m_log,  "log1p")
))
# Result: identity moderately off (skew 1.18, hetero 0.42); sqrt cleans both
# (0.43 / 0.18); log1p overcorrects (signs flip) AND goes singular. -> keep
# identity for interpretability, use sqrt only as a robustness check -- that
# robustness comparison is now in 07 (part of the settled record).
