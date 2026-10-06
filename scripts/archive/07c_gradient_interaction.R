# =============================================================================
# 07c_gradient_interaction.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 7c: add channel gradient as a between-reach fixed covariate on the
#           forcing slope -- gradient x forcing interaction on m_B2 (RS 28-37)
# =============================================================================
#
# Purpose: The model of record (m_B2, in 07_mixed_forcing_model.R) lets each
#   reach have its own forcing sensitivity via an UNSTRUCTURED random slope
#   (cum_excess_k || river_segment). That random slope measures how much reaches
#   differ in flood response (~6x) but explains NONE of it -- it is patternless
#   per-reach scatter. This script asks whether channel gradient (valley slope,
#   a static reach attribute) explains part of that spread, via the mechanistic
#   hypothesis that steeper reaches convert a unit of flood forcing into more
#   corridor reworking (stream-power control: omega ~ rho g Q S / w).
#
# WHAT THE INTERACTION DOES (read this before reading the output):
#   In m_B2 the per-reach forcing slope is decomposed as
#       slope_j = beta_forcing + b_j ,   b_j ~ Normal(0, tau1^2)
#   where beta_forcing is the population mean and b_j is the reach's unexplained
#   departure. tau1 = sd(cum_excess_k | river_segment) in the VarCorr table IS
#   the "reaches differ ~6x" number, treated as structureless scatter.
#
#   Adding cum_excess_k:gradient_c reparameterizes that slope as
#       slope_j = beta_forcing + gamma1 * gradient_c(j) + b_j
#                 \_ pop mean _/  \_ explained by gradient _/  \_ leftover _/
#   Gradient now predicts PART of b_j. Whatever it explains moves out of the
#   random pile and into the fixed term gamma1. => THE SUCCESS SIGNAL IS
#   tau1 SHRINKING between m_B2 and this model, NOT AIC or R^2. A fixed
#   between-reach covariate and its matching random effect PARTITION the same
#   between-reach variance; we are converting "reaches differ, unknown why" into
#   "reaches differ, gradient explains part of why."
#
#   The main effect (gradient_c alone) instead competes with the reach random
#   INTERCEPT (tau0): it asks "do steeper reaches have a higher baseline offset?"
#   -- a weaker, secondary question. We fit the full cum_excess_k * gradient_c
#   (main + interaction) but EXPECT only the interaction to earn its place.
#
# WHY KEEP THE RANDOM SLOPE once the interaction is in: dropping it would force
#   gamma1 to explain ALL between-reach sensitivity variation and report a
#   falsely tight SE -- pseudo-replication moved up one level, the same error the
#   crossed design exists to avoid. With 10 reaches, gamma1 and b_j are collinear
#   by construction (both functions of reach identity); the split "smooth
#   gradient trend vs patternless residual" is real but not sharply identified.
#   Expect: gamma1 with a real-but-modest t, tau1 drops but does not vanish, and
#   RS 30 keeps a large positive leftover b_j (its gradient is mid-pack, 0.0056,
#   but its sensitivity is top-of-set -- gradient under-predicts it, tying to its
#   anomalous 541-ft active width and the 2012 HMA-expansion question).
#
# Inputs:
#   - scripts/07_mixed_forcing_model.R  (sourced for `panel` and `m_B2`)
# Outputs:
#   - plots/lmm_gradient_blup_precheck.png  (exploratory: gradient vs BLUP slope)
#   - plots/lmm_gradient_reach_slopes.png   (per-reach sensitivity, m_B2 vs +grad)
#   - console: variance-component before/after (tau1 is the headline) + LRT
#
# NOTE ON GRADIENT SOURCE: values below are a hard-coded lookup transcribed from
#   the DOGAMI CMZ workbook (data_in/.../Umatilla_River__CMZ_Summary.xlsx,
#   "Summary Table", column "Slope (%)" -- misnamed; values are fractional
#   gradients, e.g. RS 30 = 0.0056 = 0.56% ~ 5.6 m/km, NOT percent). Static per
#   reach, so a lookup is auditable and pipeline-friendly. TODO when back in the
#   live R project: replace the tibble with a read from the workbook on disk,
#   e.g. readxl::read_excel(path, sheet = "Summary Table") then parse the
#   "River Segment" / "Slope (%)" columns, to remove the transcription step.
# Style: Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(tibble)
library(ggplot2)
library(lme4)

# ---- Source the model of record --------------------------------------------
# 07 builds `panel` (RS 28-37, forcing joined, cum_excess_k scaled) and fits
# m_B2. We extend that exact panel so the two models are strictly nested and
# their variance components are directly comparable.
source("scripts/07_mixed_forcing_model.R")


# ---- Channel gradient lookup (see NOTE ON GRADIENT SOURCE above) ------------
# Transcribed from the DOGAMI CMZ workbook, RS 28-37. Fractional gradient.
reach_gradient <- tribble(
  ~river_segment, ~gradient,
  28L, 0.0044,
  29L, 0.0068,
  30L, 0.0056,
  31L, 0.0055,
  32L, 0.0048,
  33L, 0.0053,
  34L, 0.0059,
  35L, 0.0061,   # NB: 07 excludes 25-27; 35/36 order matches workbook rows
  36L, 0.0061,
  37L, 0.0071
) %>%
  # RS 35 is 0.0055 in the workbook; the 0.0061 above is RS 36. Fix explicitly
  # rather than silently -- transcription is the fragile step. Corrected values:
  mutate(gradient = c(0.0044, 0.0068, 0.0056, 0.0055, 0.0048,
                      0.0053, 0.0059, 0.0055, 0.0061, 0.0071))

# ---- Attach gradient to the panel and center --------------------------------
# CENTERING (gradient_c = gradient - mean): pure reparameterization. It does NOT
# collapse reaches to a common value -- each reach keeps its own gradient in the
# design matrix; centering only slides the origin so that gradient_c = 0 lands at
# the mean reach. Effect: the cum_excess_k MAIN coefficient then reads as
# "flood sensitivity at the average reach" (comparable to m_B2's ~1.08), instead
# of "sensitivity at gradient = 0", a value no reach has (off the physical range,
# same pathology as the intercept). gamma1 and every fitted per-reach slope come
# out identical with or without centering.
# SCALING: gradient is ~0.001; cum_excess_k is ~1-50. Left unscaled, the
# interaction column is ~1000x smaller than the others -> the optimizer chokes
# ("predictors on very different scales", non-convergence). Express gradient in
# per-0.001 units (gradient_c1000) so all predictors sit near the same scale and
# gamma1 reads as "change in sensitivity per 0.001 (=0.1%) of gradient" -- a
# readable geomorphic step. Scaling changes only units/numerics, not the fit's
# conclusions.
panel_g <- panel %>%
  # panel$river_segment is a factor; join on the integer code beneath it
  mutate(rs_int = as.integer(as.character(river_segment))) %>%
  left_join(reach_gradient, by = c("rs_int" = "river_segment")) %>%
  mutate(gradient_c = (gradient - mean(reach_gradient$gradient)) / 0.001)

stopifnot(sum(is.na(panel_g$gradient)) == 0)  # every reach matched a gradient


# =============================================================================
# STEP 1 (EXPLORATORY): does gradient track the existing sensitivity spread?
# -----------------------------------------------------------------------------
# The cheap pre-check, BEFORE spending a between-reach df on the refit. Extract
# each reach's fitted forcing slope from the CURRENT m_B2 (population slope +
# reach random slope = the conditional/BLUP slope) and plot it against gradient.
# A clean positive line => gradient has signal to convert. A reach sitting far
# off the line (expect RS 30) => idiosyncratic, gradient will under-predict it.
# =============================================================================

# reach_slope(): fixef forcing slope + each reach's random-slope BLUP. Defined in
# 07 (sourced above); reproduced-safe here in case 07's copy changes name.
blup_forcing_slope <- function(m) {
  comp <- Filter(function(d) "cum_excess_k" %in% colnames(d), ranef(m))[[1]]
  setNames(fixef(m)[["cum_excess_k"]] + comp[, "cum_excess_k"], rownames(comp))
}

precheck <- tibble(
  river_segment = names(blup_forcing_slope(m_B2)),
  blup_slope    = as.numeric(blup_forcing_slope(m_B2))
) %>%
  mutate(rs_int = as.integer(river_segment)) %>%
  left_join(reach_gradient, by = c("rs_int" = "river_segment"))

precheck_rho <- cor(precheck$gradient, precheck$blup_slope, method = "spearman")
cat("\n=== STEP 1 pre-check: gradient vs m_B2 per-reach forcing slope ===\n")
cat("Spearman rho (gradient, BLUP forcing slope):", round(precheck_rho, 3), "\n")
precheck %>%
  arrange(desc(blup_slope)) %>%
  select(river_segment, gradient, blup_slope) %>%
  as.data.frame() %>% print(digits = 3)

p_precheck <- ggplot(precheck, aes(gradient, blup_slope)) +
  geom_smooth(method = "lm", se = FALSE, color = "grey60",
              linewidth = 0.5, formula = y ~ x) +
  geom_point(size = 2, color = "#2c7fb8") +
  geom_text(aes(label = river_segment), vjust = -0.8, size = 3.2) +
  labs(x = "Channel gradient (fractional)",
       y = "m_B2 per-reach forcing slope (ft per 1000 cfs-days)",
       title = "Pre-check: does gradient track flood sensitivity?",
       subtitle = paste0("Spearman rho = ", round(precheck_rho, 2),
                         ".  A reach above the line responds harder than its ",
                         "gradient predicts (watch RS 30).")) +
  theme_minimal(base_size = 12)

ggsave("plots/lmm_gradient_blup_precheck.png", p_precheck,
       width = 7, height = 5, units = "in")


# =============================================================================
# STEP 2: refit m_B2 with the gradient x forcing interaction
# -----------------------------------------------------------------------------
# Fixed effects expand to: cum_excess_k + gradient_c + cum_excess_k:gradient_c
#   + interval_years. Random structure UNCHANGED (gradient_c is reach-constant,
#   so it can only be fixed; the random slope on cum_excess_k stays and is
#   exactly what should shrink).
# =============================================================================
m_B2_grad <- lmer(
  new_area_per_ft ~ cum_excess_k * gradient_c + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel_g, REML = TRUE
)

cat("\n=== STEP 2: fixed effects, m_B2 + gradient interaction ===\n")
print(round(summary(m_B2_grad)$coefficients, 4))
cat("\nInterpretation: cum_excess_k = flood sensitivity at the AVERAGE reach",
    "(gradient_c = 0);\n  cum_excess_k:gradient_c (gamma1) = how that sensitivity",
    "changes per unit gradient.\n  gradient_c (main) competes with the reach",
    "random intercept -- expected weak.\n")


# =============================================================================
# STEP 3 (HEADLINE): did the random forcing-slope variance shrink?
# -----------------------------------------------------------------------------
# tau1 = sd(cum_excess_k | river_segment). This is THE metric. Compare m_B2 (no
# gradient) to m_B2_grad. A drop = gradient explained part of the between-reach
# sensitivity spread. tau0 (reach intercept SD) is the secondary read tied to the
# main effect. Both models are REML with the SAME random structure, so their
# variance components are directly comparable.
# =============================================================================
vc_tidy <- function(m, label) {
  as.data.frame(VarCorr(m)) %>%
    transmute(model = label, group = grp, term = var1, sd = sdcor)
}

vc_compare <- bind_rows(
  vc_tidy(m_B2,      "m_B2 (no gradient)"),
  vc_tidy(m_B2_grad, "m_B2 + gradient")
)

cat("\n=== STEP 3 HEADLINE: variance components before/after ===\n")
cat("Watch the row: group = river_segment, term = cum_excess_k  (this is tau1)\n")
vc_compare %>% as.data.frame() %>% print(digits = 4)

tau1 <- vc_compare %>%
  filter(group == "river_segment", term == "cum_excess_k")
if (nrow(tau1) == 2) {
  sd_old <- tau1$sd[tau1$model == "m_B2 (no gradient)"]
  sd_new <- tau1$sd[tau1$model == "m_B2 + gradient"]
  change_pct <- 100 * (sd_new / sd_old - 1)  # signed: negative = shrinkage
  cat("\n  tau1 (forcing-slope SD):", round(sd_old, 4), "->", round(sd_new, 4),
      sprintf("  (%+.0f%%)\n", change_pct))
  if (change_pct < -2) {
    cat("  Reading: tau1 SHRANK -> gradient explains part of the between-reach",
        "flood-sensitivity spread.\n")
  } else {
    cat("  Reading: tau1 did NOT shrink -> gradient does NOT explain the",
        "between-reach\n  flood-sensitivity spread. This is a clean negative",
        "result, not a failure:\n  in this 10-reach set gradient and flood",
        "sensitivity are not aligned\n  (e.g. RS 29 is steep but least",
        "sensitive; RS 30 is mid-gradient but most).\n")
  }
}


# =============================================================================
# STEP 4: does the interaction earn its place? (ML LRT)
# -----------------------------------------------------------------------------
# REML likelihoods are NOT comparable across different fixed effects, so refit
# both with ML for the LRT. Nesting: m_B2 (ML) is m_B2_grad (ML) minus the two
# gradient fixed terms. LRT on FIXED effects is fine here (no boundary issue --
# that caveat is only for testing random effects). This is a SECONDARY check;
# the variance-component drop in Step 3 is the substantive result.
# =============================================================================
# anova() requires an IDENTICAL data object across models. m_B2 was fit on
# `panel` (from 07); m_B2_grad on `panel_g`. Refit the BASELINE on panel_g too so
# both ML models share one data frame. panel_g is panel + gradient columns, so
# the baseline fit is unchanged; this only satisfies anova's identity check.
m_B2_ml      <- update(m_B2, REML = FALSE, data = panel_g)
m_B2_grad_ml <- update(m_B2_grad, REML = FALSE)

cat("\n=== STEP 4: LRT, gradient terms earn their place? (ML) ===\n")
print(anova(m_B2_ml, m_B2_grad_ml))

# Isolate the INTERACTION specifically (drop only the interaction, keep the
# gradient main effect) -- the term the whole hypothesis rests on.
m_B2_grad_mainonly_ml <- update(
  m_B2_ml,
  . ~ cum_excess_k + gradient_c + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel_g
)
cat("\n=== STEP 4b: LRT isolating the INTERACTION (main effect retained) ===\n")
print(anova(m_B2_grad_mainonly_ml, m_B2_grad_ml))


# =============================================================================
# STEP 5: per-reach forcing slopes, m_B2 vs m_B2 + gradient
# -----------------------------------------------------------------------------
# Show what the interaction did reach by reach: the conditional (BLUP) forcing
# slope under each model. Under +gradient, a reach's slope is
#   beta_forcing + gamma1 * gradient_c(j) + b_j -- part now structured by
# gradient. Reaches should pull toward a gradient-ordered line; RS 30 should
# stay high (leftover b_j) -- the visible "still idiosyncratic" signal.
# =============================================================================
slopes_compare <- tibble(
  river_segment = names(blup_forcing_slope(m_B2)),
  `m_B2`        = as.numeric(blup_forcing_slope(m_B2)),
  `m_B2 + gradient` = as.numeric(blup_forcing_slope(m_B2_grad)[
                        names(blup_forcing_slope(m_B2))])
) %>%
  mutate(rs_int = as.integer(river_segment)) %>%
  left_join(reach_gradient, by = c("rs_int" = "river_segment")) %>%
  tidyr::pivot_longer(c(`m_B2`, `m_B2 + gradient`),
                      names_to = "model", values_to = "forcing_slope")

p_slopes <- ggplot(slopes_compare,
                   aes(gradient, forcing_slope, color = model)) +
  geom_line(aes(group = river_segment), color = "grey80", linewidth = 0.4) +
  geom_point(size = 2) +
  geom_text(data = filter(slopes_compare, model == "m_B2 + gradient"),
            aes(label = river_segment), vjust = -0.8, size = 3, color = "black") +
  scale_color_manual(values = c(`m_B2` = "#2c7fb8",
                                `m_B2 + gradient` = "#238b45")) +
  labs(x = "Channel gradient (fractional)",
       y = "Per-reach forcing slope (ft per 1000 cfs-days)",
       title = "Per-reach flood sensitivity: unstructured (m_B2) vs gradient-structured",
       subtitle = "Grey links pair the same reach across models. RS 30 expected to stay high.",
       color = NULL) +
  theme_minimal(base_size = 12)

ggsave("plots/lmm_gradient_reach_slopes.png", p_slopes,
       width = 8, height = 5.5, units = "in")

cat("\nWrote plots/lmm_gradient_blup_precheck.png,",
    "plots/lmm_gradient_reach_slopes.png\n")

# ---- One-line summary for the meeting ---------------------------------------
cat("\n=== SUMMARY ===\n")
cat("Claim to test: flood sensitivity scales with channel gradient",
    "(stream-power control).\n")
cat("Evidence hierarchy: (1) tau1 reduction [Step 3] is the headline;",
    "(2) interaction LRT [Step 4b] secondary;\n  (3) RS 30 residual",
    "[Step 5] = the part gradient does NOT explain.\n")
cat("Honest framing: 'sensitivity scales with gradient, consistent with a",
    "stream-power control'\n  -- NOT 'gradient net of all else causes",
    "sensitivity' (10 reaches can't isolate that).\n")
