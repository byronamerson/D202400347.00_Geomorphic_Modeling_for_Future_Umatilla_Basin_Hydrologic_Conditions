# =============================================================================
# 07d_cesp_forcing_model.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 7d: cumulative effective stream power (CESP) as the forcing metric,
#           RS 28-37 -- a PARALLEL model to m_B2, not a replacement
# =============================================================================
#
# Purpose: refit the m_B2 structure with flood forcing expressed as cumulative
#   effective stream power per unit bed area (MJ/m2) instead of cumulative
#   excess discharge (1000 cfs-days), and score the two side by side. m_B2
#   remains the model of record unless CESP earns the swap.
#
# -----------------------------------------------------------------------------
# WHAT IS ACTUALLY NEW HERE -- read this before interpreting anything below
# -----------------------------------------------------------------------------
# Within a reach the gradient S_i and every unit constant are reach-constant, so
# m_B2's per-reach random slope absorbs them entirely:
#
#     cesp_it  is proportional to  cum_excess_it / w_it      (within reach i)
#
# The whole new information content is w_it, the time-varying active-channel
# width. This model is therefore a test of WIDTH NORMALIZATION, with specific
# stream power as the physical justification for that normalization -- not the
# addition of an independent stream-power signal. Say it that way in the report.
#
# Corollary: total stream power per unit channel length (Omega = gamma*Q*S, no
# width) is a pure per-reach rescale of cum_excess and cannot differ from m_B2
# at all, so that variant is deliberately NOT fit here. The related route of
# gradient-as-a-reach-covariate was already tested and was null -- see 07c and
# NOTE_gradient_interaction_null_result.md.
#
# -----------------------------------------------------------------------------
# METHOD
# -----------------------------------------------------------------------------
# Specific (unit) stream power    omega = gamma * Q * S / w        [W/m2]
# Integrated over an interval and restricted to above-threshold flow, this is
# cumulative effective stream power -- an established construct, not a bespoke
# one (Larsen, Fremier & Girvetz 2006, JAWRA: CESP applied to bank erosion on
# the Sacramento River). The integrated rather than peak form is the one the
# duration literature supports (Costa & O'Connor 1995; Magilligan et al. 2015:
# geomorphically effective floods combine high peak WITH long duration).
#
#     CESP_it = gamma * S_i * SUM_days (Q - Qc)+ * dt / w_it       [J/m2]
#
# w_it is constant within an interval, so it factors straight out of the daily
# sum and the already-validated cum_excess metric is reused unchanged:
#
#     CESP_it [J/m2] = K * S_i * cum_excess_it[cfs-days] / w_it[ft]
#     K = gamma * cfs_to_cms * seconds_per_day / ft_to_m  ~=  7.874e7
#
# So there is no daily recomputation and NO NEW THRESHOLD: the exceedance
# threshold is inherited unchanged from the 04c config (0.75*Q2 = bankfull,
# verified against Pendleton's own LP3 fit in x14). The only difference from
# m_B2's forcing is the division by width.
#
# -----------------------------------------------------------------------------
# KEY DECISIONS
# -----------------------------------------------------------------------------
# 1. WIDTH = START OF INTERVAL (w_t1), not the mean and not w_t2.
#    The active-channel polygons that produce the response also produce the
#    width, and an identity links them:
#        w_t2 = w_t1 + new_area_per_ft - abandoned_area_per_ft
#    new_area_per_ft IS the response. So w_t2 -- and any mean involving it --
#    carries the response inside the predictor's denominator with coefficient
#    one, biasing the forcing slope downward (larger response -> wider channel
#    -> smaller CESP). w_t1 is fixed before the interval's floods occur and is
#    the only exogenous choice. Decided with Byron 2026-09-17.
#    A w_mean refit is fitted below so the choice is testable rather than only
#    argued. Attenuation under w_mean CONFIRMS the endogeneity; it is not
#    evidence that w_mean is the better denominator.
#
# 2. WIDTH SOURCE is clipped active-channel area / length_ft, from
#    data/channel_area_by_rs_year.csv (built 2026-09-17 alongside the
#    confinement ratio). This is a channel-BELT width -- the HMA active-channel
#    envelope including bars -- not a wetted width at the flow. At and above
#    bankfull, which is where this forcing metric lives, the active channel is
#    approximately the conveying width, so the approximation holds there; below
#    bankfull it would not. Independent check: recent-year widths reproduce
#    DOGAMI's transect-based avg_width_ft closely (RS 28: 254-269 vs 256;
#    RS 29: 185.2 vs 185). DISCLOSE in the report -- this is a defensible index,
#    not a hydraulic computation.
#
# 3. GRADIENT S is the static per-reach valley gradient (reach_attributes.csv
#    'slope'), one value per reach; the CMZ workbook has no year dimension and
#    per-year sinuosity was withdrawn (see Spec_Next_Step_Exploration.md).
#    REQUIRES the 2026-09-17 slope units fix in script 02 -- guarded below,
#    because a stale file would silently produce CESP values 100x low.
#
# 4. TAU1 IS NOT COMPARABLE across the two models on their natural scales: the
#    slopes carry different units (ft per MJ/m2 vs ft per 1000 cfs-days).
#    Standardized refits exist below purely so the between-reach slope SD can
#    be compared. This is the one place 07d departs from 07c's procedure, where
#    the predictor was identical and raw tau1 shrinkage was the clean signal.
#
# 5. AIC/BIC need identical rows, so m_B2 is REFIT on the CESP panel rather
#    than reused from 07; row counts are asserted equal. The two models are NOT
#    nested and their predictors differ in units, so there is no valid LRT --
#    judge on AIC (ML), marginal R2, and the interval RE only.
#
# Inputs:
#   - scripts/07_mixed_forcing_model.R  (sourced: panel, m_B2, CONFINED_REACHES)
#   - data/channel_area_by_rs_year.csv  (per-year widths, spatial_confinement_ratio.R)
#   - data/reach_attributes.csv         (per-reach gradient, script 02)
# Outputs:
#   - data/cesp_panel.csv               (augmented panel, fully inspectable)
#   - plots/cesp_vs_cum_excess.png      (what the width normalization did)
#   - plots/cesp_reach_scatter.png      (per-reach response vs CESP)
#
# Model note: cesp_k = CESP in MJ/m2 (J/m2 / 1e6), scaled so the predictor sits
#   near the response scale -- the same convention as cum_excess_k in 07.
#   Style: Tidyverse & FP guidelines; contracts per docs/lingua.md.
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(lme4)

# Brings `panel` (RS 28-37, forcing joined), `m_B2`, and CONFINED_REACHES.
source("scripts/07_mixed_forcing_model.R")


# =============================================================================
# 0. CONFIG
# =============================================================================
# Unit constants are named rather than folded into a magic number so the
# derivation of K stays readable at the point of use.

config_cesp <- list(
  channel_width_path = "data/channel_area_by_rs_year.csv",
  reach_attr_path    = "data/reach_attributes.csv",
  panel_out_path     = "data/cesp_panel.csv",
  gamma_n_per_m3     = 9810,        # rho * g, specific weight of water (N/m3)
  cfs_to_cms         = 0.0283168,
  seconds_per_day    = 86400,
  ft_to_m            = 0.3048,
  joules_per_mj      = 1e6,
  # Plausible window for a non-zero Umatilla reach gradient (ft/ft). The
  # pre-fix bug lands at ~5e-5 and trips the low end.
  plausible_gradient = c(0.0005, 0.02)
)


# =============================================================================
# 1. INPUTS
# =============================================================================

read_channel_widths <- function(path) {
  #' Purpose: load the per-reach, per-photo-year active-channel width series
  #'   that supplies the CESP denominator.
  #' In:  path -- csv from spatial_confinement_ratio.R, one row per reach-year
  #'   carrying the clipped active-channel area and the width derived from it.
  #' Out: tibble(rs_num, year, channel_width_ft); width in feet, being clipped
  #'   active-channel area divided by the reach's length_ft.
  #' Decisions: keys are renamed to rs_num/year here so every join downstream
  #'   uses the same names as reach_attributes.csv and the interval panel.
  read_csv(path, show_col_types = FALSE) %>%
    transmute(
      rs_num           = as.integer(river_segment),
      year             = as.integer(Year),
      channel_width_ft = channel_width_ft
    )
}


read_reach_gradients <- function(path, cfg) {
  #' Purpose: load the static per-reach valley gradient used as S in CESP.
  #' In:  path -- data/reach_attributes.csv (script 02 output);
  #'      cfg  -- config list supplying the plausibility window.
  #' Out: tibble(rs_num, gradient), dimensionless ft/ft.
  #' Decisions: the magnitude is validated rather than trusted. A
  #'   reach_attributes.csv written before the 2026-09-17 units fix carries
  #'   gradients 100x too small, which would produce CESP values 100x low with
  #'   no other visible symptom -- model fit and ranking are invariant to a
  #'   global rescale, so nothing else in this script would catch it.
  gradients <- read_csv(path, show_col_types = FALSE) %>%
    transmute(rs_num = as.integer(rs_num), gradient = slope)

  observed <- median(gradients$gradient[gradients$gradient > 0], na.rm = TRUE)
  if (is.na(observed) ||
      observed < cfg$plausible_gradient[1] ||
      observed > cfg$plausible_gradient[2]) {
    stop("Reach gradients look wrong: median non-zero gradient = ",
         signif(observed, 3), " ft/ft, expected ",
         cfg$plausible_gradient[1], "-", cfg$plausible_gradient[2], ". ",
         "Re-run scripts/02_reach_attributes_and_scaling.R -- a value near 5e-5 ",
         "is the signature of the pre-2026-09-17 slope/100 units bug.")
  }
  gradients
}


# =============================================================================
# 2. PANEL ASSEMBLY
# =============================================================================

attach_interval_widths <- function(panel_tbl, widths) {
  #' Purpose: attach start-of-interval and end-of-interval channel widths to
  #'   every panel row, so CESP can be formed on w_t1 and the w_mean
  #'   sensitivity refit can run on the same rows.
  #' In:  panel_tbl -- RS 28-37 interval panel from 07 (river_segment a factor,
  #'        year_t1/year_t2 the bounding photo years);
  #'      widths    -- tibble(rs_num, year, channel_width_ft).
  #' Out: panel_tbl plus rs_num, width_start_ft, width_end_ft, width_mean_ft.
  #' Decisions: joined at the two endpoints rather than interpolated. There are
  #'   no photo years INSIDE an interval, so a "within-interval mean" would be
  #'   invented rather than measured -- w_mean here is only the two endpoints,
  #'   which is exactly why it cannot escape the endogeneity in decision 1.
  #'   Completeness is asserted: a missing width would silently drop the row
  #'   and break the equal-rows requirement for the AIC comparison.
  joined <- panel_tbl %>%
    mutate(rs_num = as.integer(as.character(river_segment))) %>%
    left_join(rename(widths, width_start_ft = channel_width_ft),
              by = c("rs_num", "year_t1" = "year")) %>%
    left_join(rename(widths, width_end_ft = channel_width_ft),
              by = c("rs_num", "year_t2" = "year")) %>%
    mutate(width_mean_ft = (width_start_ft + width_end_ft) / 2)

  incomplete <- filter(joined, is.na(width_start_ft) | is.na(width_end_ft))
  if (nrow(incomplete) > 0) {
    stop("No channel width for ", nrow(incomplete), " panel row(s): ",
         paste(sprintf("RS %d %d-%d", incomplete$rs_num,
                       incomplete$year_t1, incomplete$year_t2),
               collapse = ", "))
  }
  joined
}


compute_cesp <- function(panel_tbl, cfg) {
  #' Purpose: form cumulative effective stream power per unit bed area for each
  #'   reach-interval, under both the start-of-interval and the mean width.
  #' In:  panel_tbl -- panel carrying gradient, width_start_ft, width_mean_ft
  #'        and cum_excess_thresh_cfs_days (the 04c above-threshold volume);
  #'      cfg -- config list supplying the unit constants.
  #' Out: panel_tbl plus cesp_k (MJ/m2 on START width -- the model predictor)
  #'      and cesp_mean_k (MJ/m2 on MEAN width -- the sensitivity predictor).
  #' Decisions: because width is constant within an interval it factors out of
  #'   the daily integral, so the validated cum_excess metric is reused as-is.
  #'   No daily series is re-read and no second threshold is introduced -- the
  #'   only change from m_B2's forcing is the division by width.
  energy_constant <- cfg$gamma_n_per_m3 * cfg$cfs_to_cms *
    cfg$seconds_per_day / cfg$ft_to_m   # J/m2 per (ft/ft * cfs-day / ft)

  panel_tbl %>%
    mutate(
      cesp_j_per_m2      = energy_constant * gradient *
        cum_excess_thresh_cfs_days / width_start_ft,
      cesp_mean_j_per_m2 = energy_constant * gradient *
        cum_excess_thresh_cfs_days / width_mean_ft,
      cesp_k             = cesp_j_per_m2 / cfg$joules_per_mj,
      cesp_mean_k        = cesp_mean_j_per_m2 / cfg$joules_per_mj
    )
}


standardize <- function(x) {
  #' Purpose: z-score a predictor so between-reach slope SDs (tau1) from models
  #'   with differently-scaled predictors can be compared.
  #' In:  x -- numeric vector, no NAs (panel completeness is asserted upstream).
  #' Out: numeric vector, mean 0 and SD 1.
  #' Decisions: standardization is used ONLY for the tau1 comparison. Reported
  #'   coefficients come from the natural-scale fits so they stay in feet per
  #'   physical unit.
  as.numeric((x - mean(x)) / sd(x))
}


# =============================================================================
# 3. SCORECARD HELPERS
# =============================================================================
# Mirrors the single-predictor bake-off in explore/x13 so the numbers here are
# directly comparable to the forcing-metric selection already on the record.

sd_interval <- function(m) {
  #' Purpose: interval random-effect SD -- the variance the projection discards
  #'   and carries as its uncertainty band. Lower is better.
  #' In:  m -- a fitted lmer model with an `interval` grouping factor.
  #' Out: scalar SD, in feet.
  vc <- as.data.frame(VarCorr(m))
  vc$sdcor[vc$grp == "interval"][1]
}


sd_reach_slope <- function(m, term) {
  #' Purpose: tau1 -- the between-reach SD of the forcing slope, i.e. how much
  #'   reaches differ in flood sensitivity after the model has had its say.
  #' In:  m -- fitted lmer with an uncorrelated reach random slope on `term`;
  #'      term -- the forcing predictor's name, as it appears in the formula.
  #' Out: scalar SD, in response units per predictor unit.
  #' Decisions: matched on var1 rather than grp, because the `||` form splits
  #'   the reach effects across grp labels (river_segment, river_segment.1).
  vc  <- as.data.frame(VarCorr(m))
  idx <- which(!is.na(vc$var1) & vc$var1 == term)
  vc$sdcor[idx[1]]
}


r2_marginal <- function(m) {
  #' Purpose: marginal R2 -- variance explained by fixed effects alone
  #'   (Nakagawa/Johnson; handles the random slope).
  #' In:  m -- fitted lmer model.
  #' Out: scalar R2m.
  unname(suppressWarnings(MuMIn::r.squaredGLMM(m))[1, "R2m"])
}


aic_ml <- function(m) {
  #' Purpose: AIC on an ML refit, so models with different fixed effects or
  #'   differently-scaled predictors are comparable. REML AIC is not.
  #' In:  m -- fitted lmer model (REML or ML).
  #' Out: scalar AIC.
  AIC(update(m, REML = FALSE))
}


forcing_slope <- function(m, term) {
  #' Purpose: format the fixed forcing slope and its t value for the scorecard.
  #' In:  m -- fitted lmer model; term -- forcing predictor name.
  #' Out: character, "estimate (t value)".
  co <- summary(m)$coefficients
  sprintf("%.3f (t %.2f)", co[term, "Estimate"], co[term, "t value"])
}


# =============================================================================
# 4. BUILD
# =============================================================================
# Reads the two inputs, attaches widths and gradient to the 07 panel, forms
# CESP under both width choices, and writes the augmented panel out so every
# summary number below can be traced back to its rows.

widths    <- read_channel_widths(config_cesp$channel_width_path)
gradients <- read_reach_gradients(config_cesp$reach_attr_path, config_cesp)

panel_cesp <- panel %>%
  attach_interval_widths(widths) %>%
  left_join(gradients, by = "rs_num") %>%
  compute_cesp(config_cesp) %>%
  mutate(
    cum_excess_z = standardize(cum_excess_k),
    cesp_z       = standardize(cesp_k)
  )

stopifnot(
  nrow(panel_cesp) == nrow(panel),
  !any(is.na(panel_cesp$cesp_k)),
  !any(is.na(panel_cesp$gradient))
)

write_csv(panel_cesp, config_cesp$panel_out_path)

threshold_label <- if ("threshold_cfs" %in% names(panel_cesp)) {
  paste(unique(panel_cesp$threshold_cfs), collapse = ", ")
} else {
  "not carried in panel -- confirm against the 04c config"
}

cat("\n=== CESP panel ===\n")
cat("rows:", nrow(panel_cesp),
    "| reaches:", nlevels(panel_cesp$river_segment),
    "| intervals:", nlevels(panel_cesp$interval), "\n")
cat("exceedance threshold (cfs, inherited from 04c):", threshold_label, "\n")
cat("cesp_k (MJ/m2) range:",
    paste(round(range(panel_cesp$cesp_k), 2), collapse = " to "), "\n")
cat("wrote", config_cesp$panel_out_path, "\n")

# The new information, made visible: how much w_t1 actually moves within each
# reach. A reach whose width barely varies contributes nothing that m_B2's
# random slope did not already absorb.
cat("\n=== Start-of-interval width variation by reach (this IS the new signal) ===\n")
panel_cesp %>%
  group_by(river_segment) %>%
  summarize(gradient  = first(gradient),
            w_min_ft  = min(width_start_ft),
            w_max_ft  = max(width_start_ft),
            w_ratio   = max(width_start_ft) / min(width_start_ft),
            .groups   = "drop") %>%
  arrange(desc(w_ratio)) %>%
  as.data.frame() %>%
  print(digits = 3, row.names = FALSE)


# =============================================================================
# 5. FIT
# =============================================================================
# One structure, three forcings. m_B2_same is m_B2's formula refit on this
# panel so AIC is computed on identical rows.

m_CESP <- lmer(
  new_area_per_ft ~ cesp_k + interval_years +
    (cesp_k || river_segment) + (1 | interval),
  data = panel_cesp, REML = TRUE
)

m_B2_same <- lmer(
  new_area_per_ft ~ cum_excess_k + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel_cesp, REML = TRUE
)

# Sensitivity only -- see decision 1. Not a candidate model of record.
m_CESP_mean <- lmer(
  new_area_per_ft ~ cesp_mean_k + interval_years +
    (cesp_mean_k || river_segment) + (1 | interval),
  data = panel_cesp, REML = TRUE
)

# Standardized refits exist solely to make tau1 comparable (decision 4).
m_B2_z <- lmer(
  new_area_per_ft ~ cum_excess_z + interval_years +
    (cum_excess_z || river_segment) + (1 | interval),
  data = panel_cesp, REML = TRUE
)

m_CESP_z <- lmer(
  new_area_per_ft ~ cesp_z + interval_years +
    (cesp_z || river_segment) + (1 | interval),
  data = panel_cesp, REML = TRUE
)


# =============================================================================
# 6. COMPARE
# =============================================================================

scorecard <- tibble(
  model = c("m_B2       cum_excess  (1000 cfs-days)",
            "m_CESP     start width (MJ/m2)",
            "m_CESP_mean mean width (MJ/m2) [sensitivity]"),
  forcing_slope = c(forcing_slope(m_B2_same,   "cum_excess_k"),
                    forcing_slope(m_CESP,      "cesp_k"),
                    forcing_slope(m_CESP_mean, "cesp_mean_k")),
  sd_interval   = c(sd_interval(m_B2_same),
                    sd_interval(m_CESP),
                    sd_interval(m_CESP_mean)),
  R2_marg       = c(r2_marginal(m_B2_same),
                    r2_marginal(m_CESP),
                    r2_marginal(m_CESP_mean)),
  aic_ml        = c(aic_ml(m_B2_same),
                    aic_ml(m_CESP),
                    aic_ml(m_CESP_mean))
)

cat("\n===============  FORCING METRIC COMPARISON  ===============\n")
cat("Same structure, same rows, same threshold; only the forcing changes.\n")
cat("Not nested and different predictor units -- NO LRT. Lower AIC and lower\n")
cat("interval RE are better; slopes are NOT comparable across rows.\n\n")
scorecard %>%
  mutate(sd_interval = round(sd_interval, 2),
         R2_marg     = round(R2_marg, 3),
         aic_ml      = round(aic_ml, 1)) %>%
  as.data.frame() %>%
  print(row.names = FALSE)

cat("\n=== Between-reach forcing-slope SD (tau1), STANDARDIZED predictors ===\n")
cat("Comparable only on this scale -- natural-scale slopes carry different units.\n")
cat("A SHRINKAGE here is the success signal: it means width normalization\n")
cat("explains part of the ~6x sensitivity spread m_B2 treats as scatter.\n")
tau1_cum  <- sd_reach_slope(m_B2_z,   "cum_excess_z")
tau1_cesp <- sd_reach_slope(m_CESP_z, "cesp_z")
cat("  m_B2   (cum_excess_z):", round(tau1_cum,  4), "\n")
cat("  m_CESP (cesp_z)      :", round(tau1_cesp, 4), "\n")
cat("  change               :",
    sprintf("%+.1f%%", 100 * (tau1_cesp - tau1_cum) / tau1_cum), "\n")

cat("\n=== Endogeneity check (decision 1) ===\n")
cat("w_mean carries the response in the denominator, so its forcing slope\n")
cat("should be ATTENUATED relative to the w_t1 fit. Attenuation confirms the\n")
cat("endogeneity; it does not make w_mean the better denominator.\n")
cat("  start-width slope:", forcing_slope(m_CESP,      "cesp_k"),      "\n")
cat("  mean-width slope :", forcing_slope(m_CESP_mean, "cesp_mean_k"), "\n")


# =============================================================================
# 7. DIAGNOSTIC PLOTS
# =============================================================================

# What the width normalization actually did. If width were constant within a
# reach, CESP would be an exact per-reach rescale of cum_excess and every point
# would sit on the orange through-origin line. Departures from that line are the
# entire new signal -- so a reach with points tight to the line contributes
# nothing beyond what m_B2's random slope already had.
p_transform <- ggplot(panel_cesp, aes(cum_excess_k, cesp_k)) +
  geom_smooth(method = "lm", formula = y ~ x - 1, se = FALSE,
              color = "#d95f0e", linewidth = 0.6) +
  geom_point(aes(color = width_start_ft), size = 1.8) +
  scale_color_viridis_c(name = "w_t1 (ft)") +
  facet_wrap(~ river_segment, scales = "free_y") +
  labs(x = "Cumulative excess above threshold (1000 cfs-days)",
       y = "CESP (MJ/m2)",
       title = "What width normalization does to the forcing",
       subtitle = "Orange = constant-width expectation; departures are the new information") +
  theme_minimal(base_size = 11)

ggsave("plots/cesp_vs_cum_excess.png", p_transform,
       width = 10, height = 7, units = "in")

# Per-reach response vs CESP, with the population line for reference. Compare
# panel-by-panel against plots/lmm_reach_scatter.png from 07.
p_scatter <- ggplot(panel_cesp, aes(cesp_k, new_area_per_ft)) +
  geom_abline(intercept = fixef(m_CESP)[["(Intercept)"]],
              slope     = fixef(m_CESP)[["cesp_k"]],
              color = "#d95f0e", linewidth = 0.8) +
  geom_point(size = 1.3, alpha = 0.7, color = "#2c7fb8") +
  facet_wrap(~ river_segment) +
  labs(x = "CESP (MJ/m2)", y = "New area per ft (ft)",
       title = "Per-reach response vs cumulative effective stream power",
       subtitle = "Orange = population (fixed-effect) line") +
  theme_minimal(base_size = 11)

ggsave("plots/cesp_reach_scatter.png", p_scatter,
       width = 10, height = 7, units = "in")

cat("\nWrote plots/cesp_vs_cum_excess.png, plots/cesp_reach_scatter.png\n")

# Leaves in env: panel_cesp, m_CESP, m_B2_same, m_CESP_mean, m_B2_z, m_CESP_z,
# scorecard, tau1_cum, tau1_cesp.
