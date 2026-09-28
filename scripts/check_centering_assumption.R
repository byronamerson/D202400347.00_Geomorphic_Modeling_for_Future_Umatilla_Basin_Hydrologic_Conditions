# =============================================================================
# check_centering_assumption.R
# Umatilla River Discharge-Channel Migration Analysis
# One question: does WHERE we measure forcing from change the model?
# =============================================================================
#
# THE QUESTION
#
#   The model of record gives every reach its own straight line, with its own
#   intercept and its own fit slope, and tells lme4 NOT to estimate a
#   relationship between those two -- the `||` in:
#
#       (cum_excess_k || river_segment)
#
#   "No relationship between intercept and slope" only means something once you
#   say WHERE the intercept is measured. An intercept is the height of the line
#   at forcing = 0, and forcing = 0 means a photo interval in which the river
#   never once went above bankfull -- the far edge of the data.
#
#   Slide the x-axis so 0 sits at the AVERAGE flood instead, and the lines are
#   identical but their heights are measured somewhere else. Across a fan of
#   lines with different steepness, heights measured at the edge and heights
#   measured at the middle relate to steepness differently. So "assume no
#   relationship" is a different claim in the two cases, and `||` is quietly
#   making whichever claim the units happen to put at zero.
#
#   That is what this script tests, and the only thing it tests.
#
# WHAT IS DONE
#
#   Refit the identical model with forcing CENTERED: cum_excess_k - its mean.
#
#   Centering ONLY, not scaling. `scale()` centers AND divides by the standard
#   deviation, which changes the units and makes the slopes incomparable. Here
#   the units stay ft per 1,000 cfs-days, so every slope below can be compared
#   directly against the uncentered fit. This is the simplification that makes
#   the answer readable: one thing changes, nothing else.
#
# WHAT TO EXPECT BEFORE LOOKING (stated first so the result cannot be
# rationalised afterwards)
#
#   - The population fit SLOPE should be essentially unchanged. Sliding the
#     x-axis does not tilt a line. If it moves, something is wrong.
#   - The INTERCEPT will change, by definition: it now reports the value at an
#     average flood rather than at no flood. That is arithmetic, not a finding.
#   - log-likelihood, the between-interval SD, and the per-reach fit slopes are
#     the actual test. Under a harmless assumption they barely move. If they
#     move, `||` is doing real work and the x-origin is a modelling choice that
#     has to be made on purpose.
#
# HOW TO DECIDE (proposed, not a law -- judge the numbers yourself)
#
#   Changes under roughly 5% are noise for this project's purposes: a
#   between-interval SD that shifts by less than about 1 ft does not change the
#   uncertainty band delivered with the projection, and reach slopes that keep
#   their rank order do not change the story about which reaches respond most.
#   Bigger than that, and it needs a decision rather than a shrug.
#
# Inputs : scripts/fit_forcing_model.R (sourced for `panel`, `model`,
#          `fit_forcing_model`, `reach_effects`). Guarded, so in a warm session
#          nothing is refit and nothing is re-printed.
# Outputs: console only. This is a check, not a product.
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
# 1. REFIT, CENTERED
# =============================================================================

CENTERED_VAR <- "cum_excess_c"

centre_forcing <- function(panel, from = FORCING_VAR, to = CENTERED_VAR) {
  #' Add a centered copy of the forcing column: the same numbers with their mean
  #' subtracted, so 0 falls at an average flood instead of at no flood.
  #'
  #' Key decision: subtraction only, never scale(). Dividing by the standard
  #' deviation would change the units and make the two fits' slopes
  #' incomparable, which is what muddied this question on 2026-09-17.
  #'
  #' @param panel the model-ready panel
  #' @return `panel` with the centered column added
  mutate(panel, !!to := .data[[from]] - mean(.data[[from]]))
}

panel_c <- centre_forcing(panel)
model_c <- fit_forcing_model(panel_c, CENTERED_VAR)

forcing_mean <- mean(panel[[FORCING_VAR]])


# =============================================================================
# 2. REPORT
# =============================================================================

say <- function(...) cat(paste0("  ", strwrap(paste0(...), width = 74)), sep = "\n")

pct_change <- function(new, old) 100 * (new - old) / abs(old)

cat("\n=== WHAT CHANGED: the sanity checks ===\n")
cat(sprintf("  forcing was shifted left by its own mean: %.2f (1,000 cfs-days)\n",
            forcing_mean))
cat(sprintf("  population fit slope   uncentered %7.3f   centered %7.3f\n",
            fixef(model)[[FORCING_VAR]], fixef(model_c)[[CENTERED_VAR]]))
cat(sprintf("  intercept              uncentered %7.2f   centered %7.2f\n",
            fixef(model)[["(Intercept)"]], fixef(model_c)[["(Intercept)"]]))
say("The slope should be the same to about three decimals -- sliding the ",
    "x-axis does not tilt a line, so a difference here would mean a coding ",
    "error, not a finding. The intercept SHOULD differ: uncentered it is the ",
    "predicted change in an interval with no flood at all; centered it is the ",
    "predicted change in an average-flood interval. That is arithmetic.")

cat("\n=== THE TEST: does the model itself move? ===\n")
ll_u  <- as.numeric(logLik(model))
ll_c  <- as.numeric(logLik(model_c))
vc_u  <- as.data.frame(VarCorr(model))
vc_c  <- as.data.frame(VarCorr(model_c))
sd_iv_u <- vc_u$sdcor[vc_u$grp == "interval"]
sd_iv_c <- vc_c$sdcor[vc_c$grp == "interval"]
r2_u <- MuMIn::r.squaredGLMM(model)[1, "R2m"]
r2_c <- MuMIn::r.squaredGLMM(model_c)[1, "R2m"]

cat(sprintf("  log-likelihood         uncentered %8.2f   centered %8.2f   diff %+.2f\n",
            ll_u, ll_c, ll_c - ll_u))
cat(sprintf("  between-interval SD    uncentered %8.2f   centered %8.2f   %+.1f%%\n",
            sd_iv_u, sd_iv_c, pct_change(sd_iv_c, sd_iv_u)))
cat(sprintf("  marginal R2            uncentered %8.3f   centered %8.3f   %+.1f%%\n",
            r2_u, r2_c, pct_change(r2_c, r2_u)))
say("If `||` were a harmless re-labelling, these three would be identical. ",
    "The log-likelihood is how well the model fits; two fits of the same data ",
    "with the same number of parameters should score the same unless the ",
    "models genuinely differ. The between-interval SD is the projection's ",
    "uncertainty band. Marginal R2 is what a competing model has to beat.")

cat("\n=== THE TEST: do the reach sensitivities move? ===\n")
sl <- reach_effects(model, FORCING_VAR) %>%
  rename(slope_uncentered = reach_slope) %>%
  select(river_segment, slope_uncentered) %>%
  left_join(
    reach_effects(model_c, CENTERED_VAR) %>%
      rename(slope_centered = reach_slope) %>%
      select(river_segment, slope_centered),
    by = "river_segment"
  ) %>%
  mutate(diff = slope_centered - slope_uncentered,
         pct  = 100 * diff / slope_uncentered)

cat(sprintf("  largest change in any reach's slope : %+.3f ft per 1,000 cfs-days (%+.1f%%)\n",
            sl$diff[which.max(abs(sl$diff))], sl$pct[which.max(abs(sl$diff))]))
cat(sprintf("  reach with that change              : RS %s\n",
            sl$river_segment[which.max(abs(sl$diff))]))
cat(sprintf("  do reaches keep their rank order?   : Spearman %.3f\n",
            cor(sl$slope_uncentered, sl$slope_centered, method = "spearman")))
say("Each reach's fit slope is how much new channel area it produces per ",
    "1,000 cfs-days of flood -- the number the projection applies reach by ",
    "reach. Spearman near 1.000 means the reaches keep their order, so the ",
    "story about which reaches are most flood-responsive is unchanged even if ",
    "the numbers shift a little. A Spearman well below 1 would mean the ",
    "x-origin is deciding which reaches look sensitive, which would have to ",
    "be settled before the projection is trusted.")

cat("\n  per-reach detail:\n")
sl %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>%
  print(row.names = FALSE)
