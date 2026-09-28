# =============================================================================
# check_interval_years.R
# Umatilla River Discharge-Channel Migration Analysis
# Question: does `interval_years` earn its place in the model of record?
# =============================================================================
#
# Why ask. The fit script reports interval_years at t = 1.22 -- below the
# threshold its own note tells the reader to use. That does not mean the effect
# is absent; it means the data cannot clearly distinguish baseline year-over-year
# reworking from zero. The term matters because the projection multiplies
# baseline_per_year x interval_years for every future interval.
#
# What is tested, in order:
#   1. Does dropping the term cost anything? Likelihood-ratio test on ML fits.
#   2. Does dropping it move the flood slope -- the number the story rests on?
#   3. Does it move the per-reach slopes, or just their overall level?
#   4. Is the 1952-1974 singleton (RS 37 only, 22 years, the lone high-leverage
#      point on the elapsed-time axis) the reason the term is weak?
#
# Decisions baked in:
#   - ML (REML = FALSE) for the likelihood comparison, because the two models
#     differ in their FIXED effects; REML likelihoods are not comparable across
#     different fixed-effect structures. REML fits are used for every reported
#     coefficient and variance, which is the standard split.
#   - Same random-effects structure in both, same data, same forcing column.
#     Only the one fixed term moves, so the comparison isolates it.
#   - Nothing is written to disk and nothing downstream is touched. This is a
#     check, not a product.
#
# Inputs : scripts/fit_forcing_model.R (sourced for `panel`, `model`,
#          `fit_forcing_model`, `reach_effects`, FORCING_VAR). Guarded, so in a
#          warm session nothing is refit and nothing is re-printed.
# Outputs: console only.
#
# Style: docs/lingua.md + Tidyverse & FP guidelines.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(lme4)
})

if (!exists("panel") || !exists("model") || !exists("fit_forcing_model")) {
  source("scripts/fit_forcing_model.R")
}


# =============================================================================
# 1. THE VARIANT FIT
# =============================================================================

fit_no_years <- function(panel, forcing_var = FORCING_VAR, REML = TRUE) {
  #' The model of record minus `interval_years`. Identical in every other
  #' respect -- same response, same forcing column, same `||` random structure --
  #' so a difference between this and `model` is attributable to the one term.
  #'
  #' @param panel model-ready panel
  #' @param forcing_var name of the scaled forcing column
  #' @param REML TRUE for reporting; FALSE for the likelihood-ratio test
  #' @return an lmerMod
  fml <- stats::as.formula(sprintf(
    "new_area_per_ft ~ %s + (%s || river_segment) + (1 | interval)",
    forcing_var, forcing_var))
  lme4::lmer(fml, data = panel, REML = REML)
}

# REML fits -- for reported coefficients, R2 and variance components.
m_full <- model
m_drop <- fit_no_years(panel)

# ML fits -- for the likelihood-ratio test only. Fixed effects differ, so REML
# likelihoods would not be comparable.
ml_full <- fit_forcing_model(panel, FORCING_VAR, REML = FALSE)
ml_drop <- fit_no_years(panel, FORCING_VAR, REML = FALSE)


# =============================================================================
# 2. REPORT
# =============================================================================

say <- function(...) cat(paste0("  ", strwrap(paste0(...), width = 74)), sep = "\n")

pct_change <- function(new, old) 100 * (new - old) / abs(old)

r2m <- function(m) unname(MuMIn::r.squaredGLMM(m)[1, "R2m"])
r2c <- function(m) unname(MuMIn::r.squaredGLMM(m)[1, "R2c"])

sd_of <- function(m, grp, v) {
  vc <- as.data.frame(lme4::VarCorr(m))
  vc$sdcor[vc$grp == grp & (is.na(vc$var1) | vc$var1 == v)][1]
}

# ---- Block 1: does the term pay for itself? --------------------------------

lrt <- anova(ml_drop, ml_full)

cat("\n=== 1. DOES `interval_years` PAY FOR ITSELF? ===\n")
cat(sprintf("  log-likelihood, with the term     %9.2f\n", as.numeric(logLik(ml_full))))
cat(sprintf("  log-likelihood, without it        %9.2f\n", as.numeric(logLik(ml_drop))))
cat(sprintf("  AIC change on dropping it         %+9.2f  (negative = simpler model preferred)\n",
            AIC(ml_drop) - AIC(ml_full)))
cat(sprintf("  likelihood-ratio chi-sq (1 df)    %9.2f   p = %.3f\n",
            lrt$Chisq[2], lrt$`Pr(>Chisq)`[2]))
say("These are ML fits, not REML, because the two models differ in their ",
    "FIXED effects and REML likelihoods cannot be compared across different ",
    "fixed structures. p above about 0.05 means dropping the term costs no ",
    "measurable fit. Read this together with block 2: a term can fail to pay ",
    "for itself statistically and still be worth keeping if removing it ",
    "distorts the coefficient the story rests on.")

# ---- Block 2: what moves in the reported fit -------------------------------

co_full <- summary(m_full)$coefficients
co_drop <- summary(m_drop)$coefficients

cmp <- data.frame(
  quantity = c("flood slope (ft per 1,000 cfs-days)",
               "  its SE",
               "  its t",
               "population intercept (ft)",
               "marginal R2",
               "conditional R2",
               "SD between intervals (ft)",
               "SD between reaches (ft)",
               "SD residual (ft)"),
  with_term = c(co_full[FORCING_VAR, "Estimate"],
                co_full[FORCING_VAR, "Std. Error"],
                co_full[FORCING_VAR, "t value"],
                co_full["(Intercept)", "Estimate"],
                r2m(m_full), r2c(m_full),
                sd_of(m_full, "interval", "(Intercept)"),
                sd_of(m_full, "river_segment.1", "(Intercept)"),
                sd_of(m_full, "Residual", NA)),
  without   = c(co_drop[FORCING_VAR, "Estimate"],
                co_drop[FORCING_VAR, "Std. Error"],
                co_drop[FORCING_VAR, "t value"],
                co_drop["(Intercept)", "Estimate"],
                r2m(m_drop), r2c(m_drop),
                sd_of(m_drop, "interval", "(Intercept)"),
                sd_of(m_drop, "river_segment.1", "(Intercept)"),
                sd_of(m_drop, "Residual", NA))
)
cmp$pct <- round(pct_change(cmp$without, cmp$with_term), 1)
cmp$with_term <- round(cmp$with_term, 3)
cmp$without   <- round(cmp$without, 3)

cat("\n=== 2. WHAT MOVES IN THE REPORTED (REML) FIT ===\n")
print(cmp, row.names = FALSE)
say("The flood slope is the number the whole story rests on -- if it barely ",
    "moves, the two models tell the same story about floods and the choice is ",
    "about parsimony rather than substance. Watch the between-interval SD ",
    "too: that term becomes the projection's uncertainty band, and elapsed ",
    "time and flood-interval identity are partly confounded because longer ",
    "intervals tend to contain more flood.")

# ---- Block 3: do the reach slopes move? ------------------------------------

sl_full <- reach_effects(m_full, FORCING_VAR)
sl_drop <- reach_effects(m_drop, FORCING_VAR)
sl <- sl_full %>%
  select(river_segment, slope_with = reach_slope) %>%
  left_join(select(sl_drop, river_segment, slope_without = reach_slope),
            by = "river_segment") %>%
  mutate(pct = round(pct_change(slope_without, slope_with), 1))

cat("\n=== 3. PER-REACH SLOPES ===\n")
cat(sprintf("  largest change on any reach: %.1f%% (RS %s)\n",
            max(abs(sl$pct)), sl$river_segment[which.max(abs(sl$pct))]))
cat(sprintf("  rank order across reaches, Spearman: %.3f\n",
            cor(sl$slope_with, sl$slope_without, method = "spearman")))
print(as.data.frame(sl), row.names = FALSE)
say("Compare this against the 33%% origin sensitivity already documented for ",
    "centering. If dropping the term moves reach slopes by less than that, it ",
    "is not the largest thing already known to be uncertain about them.")

# ---- Block 4: is the 1952-1974 singleton driving it? -----------------------

SINGLETON <- "1952-1974"

panel_nosing <- filter(panel, as.character(interval) != SINGLETON)
m_nosing     <- fit_forcing_model(panel_nosing, FORCING_VAR)
co_nosing    <- summary(m_nosing)$coefficients

cat("\n=== 4. THE 1952-1974 SINGLETON ===\n")
cat(sprintf("  rows dropped: %d of %d | reaches present in that interval: %s\n",
            nrow(panel) - nrow(panel_nosing), nrow(panel),
            paste(sort(unique(as.character(
              filter(panel, as.character(interval) == SINGLETON)$river_segment))),
              collapse = ", ")))
cat(sprintf("  interval_years, full panel     %.3f  (SE %.3f, t %.2f)\n",
            co_full["interval_years", "Estimate"],
            co_full["interval_years", "Std. Error"],
            co_full["interval_years", "t value"]))
cat(sprintf("  interval_years, singleton out  %.3f  (SE %.3f, t %.2f)\n",
            co_nosing["interval_years", "Estimate"],
            co_nosing["interval_years", "Std. Error"],
            co_nosing["interval_years", "t value"]))
cat(sprintf("  flood slope,    singleton out  %.3f  (was %.3f)\n",
            co_nosing[FORCING_VAR, "Estimate"], co_full[FORCING_VAR, "Estimate"]))
say("This interval is RS 37 only and 22 years long against a panel median of ",
    "3, so it sits alone at the far end of the elapsed-time axis and one ",
    "reach's behaviour there can set the term almost by itself. If t RISES ",
    "with it removed, the singleton was masking a real effect and the term is ",
    "better than it looked. If t FALLS toward zero, the term was largely that ",
    "one point. If little moves, the weakness is spread across the panel and ",
    "is a genuine limit of the data, not an outlier problem.")

cat("\n")


# =============================================================================
# 3. USAGE
# =============================================================================
# source("scripts/check_interval_years.R")
#
# Leaves m_full, m_drop, ml_full, ml_drop, m_nosing, sl in the environment for
# poking at. Writes nothing.
# =============================================================================
