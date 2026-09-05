# =============================================================================
# 07_mixed_forcing_model.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 7: RS 28-37 linear mixed-effects forcing model (Pendleton reaches 25-27
#          excluded -- leveed, migration precluded; see panel-assembly note below)
# =============================================================================
#
# Purpose: Fit the multi-reach forcing model. Response = length-normalized new
#   area (new_area_per_ft, interval total); forcing = cumulative excess above Q2
#   (shared Pendleton series, same for all reaches in an interval).
#
# Four variants; m_B2 is the model of record:
#   m_ri    : (1 | river_segment)                  -- simple, reach clustering
#   m_cross : (1 | river_segment) + (1 | interval) -- also interval clustering,
#             because forcing is SHARED across reaches within an interval (the
#             13 reaches in 2017-2020 all saw the same flood), so the effective
#             independent x-count is ~14 intervals, not 181 rows. The crossed
#             term gives an honest slope SE; the simple model over-credits n.
#   m_A     : m_cross + interval_years (fixed) -- Step A. Separates baseline
#             per-year reworking (interval_years) from flood forcing
#             (cum_excess_k), so the residual (1 | interval) carries genuine
#             flood-to-flood differences -- the clean saturation read.
#   m_B2    : m_A + reach-varying forcing slope, uncorrelated
#             (cum_excess_k || river_segment) -- Step B, THE MODEL OF RECORD.
#             Reaches differ ~6x in flood sensitivity. (The correlated variant
#             m_B pinned corr = 0.99 and failed to converge -- rejected.)
#
# Native scale is kept for interpretability (coefficients in feet); a sqrt
# robustness refit below confirms conclusions do not hinge on it. Exploratory
# checks that informed these choices (singleton sensitivity, the rejected m_B
# and log1p, the full transform-diagnostic table) live in
# scripts/07b_lmm_sensitivity_and_robustness.R.
#
# Inputs:
#   - data/multireach_interval_metrics.csv   (response, from 06)
#   - scripts/04c_interval_forcing_metrics.R (forcing: config + runner)
# Outputs:
#   - plots/lmm_residuals.png, plots/lmm_caterpillar.png, plots/lmm_reach_scatter.png
#
# Model note: cum_excess_k = cumulative excess above Q2 in THOUSANDS of cfs-days
#   (scaled so the predictor is near the response scale; slope reads per 1000
#   cfs-days). Style: Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(readr)
library(ggplot2)
library(lme4)

multireach <- read_csv("data/multireach_interval_metrics.csv", show_col_types = FALSE)


# ---- Forcing over the union of intervals (shared Pendleton series) -----------
source("scripts/04c_interval_forcing_metrics.R")
intervals <- distinct(multireach, year_t1, year_t2)
forcing   <- run_interval_forcing_metrics(config, intervals)


# ---- Assemble the panel -----------------------------------------------------
# Confined-reach exclusion: reaches 25-27 run through the city of Pendleton and
# are bounded by engineered levees, so channel migration is mechanically
# precluded -- a physically different process from the free / semi-confined
# reaches upstream, and out of scope for a migration-forcing model. (They also
# force impossible negative fitted intercepts on a zero-bounded response.)
# Filtered here at the single panel boundary, so every model below AND script
# 07b -- which sources this panel -- fits the migration-capable set (28-37).
# Rationale and sensitivity: docs/NOTE_confined_reach_exclusion.md
CONFINED_REACHES <- c(25L, 26L, 27L)

panel <- multireach %>%
  filter(!river_segment %in% CONFINED_REACHES) %>%
  left_join(forcing, by = c("year_t1", "year_t2")) %>%
  mutate(
    river_segment = factor(river_segment),
    interval      = factor(paste0(year_t1, "-", year_t2)),
    cum_excess_k  = cum_excess_thresh_cfs_days / 1000
  )

cat("=== panel ===\n")
cat("rows:", nrow(panel),
    "| reaches:", nlevels(panel$river_segment),
    "| intervals:", nlevels(panel$interval),
    "| missing cum_excess:", sum(is.na(panel$cum_excess_thresh_cfs_days)), "\n")


# ---- Fit both variants ------------------------------------------------------
m_ri <- lmer(
  new_area_per_ft ~ cum_excess_k + (1 | river_segment),
  data = panel, REML = TRUE
)

m_cross <- lmer(
  new_area_per_ft ~ cum_excess_k + (1 | river_segment) + (1 | interval),
  data = panel, REML = TRUE
)

# ---- Step A: add interval_years (baseline accrual vs flood saturation) -------
# interval_years is an interval-level covariate (constant within an interval): it
# explains the length-driven part of the between-interval variance, leaving
# (1 | interval) to carry the genuine flood-to-flood differences -- where
# saturation should now show. Additive/separable: a year of elapsed time does the
# same baseline reworking regardless of flood size, and vice versa.
# WATCH: the 1952-1974 singleton (RS 37 only, 22 yr) is a lone high-leverage
# point on the interval_years axis; if that slope looks fragile it's suspect #1.
m_A <- lmer(
  new_area_per_ft ~ cum_excess_k + interval_years +
    (1 | river_segment) + (1 | interval),
  data = panel, REML = TRUE
)

# ---- Step B / MODEL OF RECORD: reach-varying forcing slope (uncorrelated) ----
# Let each reach have its own sensitivity to forcing, not just its own baseline.
# Uncorrelated intercept + slope (||): the correlated form (cum_excess_k | ...)
# pinned the intercept-slope correlation at 0.99 and did not converge -- 13
# reaches can't identify that correlation. See 07b for the rejected m_B.
m_B2 <- lmer(
  new_area_per_ft ~ cum_excess_k + interval_years +
    (cum_excess_k || river_segment) + (1 | interval),
  data = panel, REML = TRUE
)


# ---- Compare fixed effect (slope) -------------------------------------------
# Same fixed effects + REML, so the estimate should barely move; the SE is the
# story -- how much does honest interval clustering widen it?
slope_row <- function(m, label) {
  s <- summary(m)$coefficients["cum_excess_k", ]
  tibble(model = label, slope = s[["Estimate"]], se = s[["Std. Error"]],
         t = s[["t value"]])
}
cat("\n=== cum_excess_k slope across variants (net of time in m_A) ===\n")
bind_rows(slope_row(m_ri, "reach-only"),
          slope_row(m_cross, "reach+interval"),
          slope_row(m_A, "+interval_years")) %>%
  as.data.frame() %>% print(digits = 3)

cat("\n=== m_A fixed effects (cum_excess_k + interval_years) ===\n")
print(round(summary(m_A)$coefficients, 3))


# ---- Compare variance components + ICC --------------------------------------
vc_tidy <- function(m, label) {
  as.data.frame(VarCorr(m)) %>%
    transmute(model = label, group = grp, sd = sdcor, variance = vcov)
}
cat("\n=== Variance components ===\n")
bind_rows(vc_tidy(m_ri, "reach-only"),
          vc_tidy(m_cross, "reach+interval"),
          vc_tidy(m_A, "+interval_years")) %>%
  as.data.frame() %>% print(digits = 4)

cat("\n=== Model comparison (same fixed effects; REML AIC/BIC comparable) ===\n")
print(AIC(m_ri, m_cross))
print(BIC(m_ri, m_cross))

cat("\n=== Does interval_years earn its place? ===\n")
# REML AIC/BIC are NOT comparable across different fixed effects, so refit with
# ML for an honest LRT of the interval_years term (m_cross nested in m_A).
m_cross_ml <- update(m_cross, REML = FALSE)
m_A_ml     <- update(m_A,     REML = FALSE)
print(anova(m_cross_ml, m_A_ml))


# ---- Model of record earns its place + scale robustness ---------------------
cat("\n=== Random slope earns its place? (m_A vs m_B2, REML LRT) ===\n")
print(anova(m_A, m_B2, refit = FALSE))

# m_B2 residuals are moderately right-skewed / heteroscedastic (typical of area
# data). We KEEP the native scale (coefficients in feet) and show a sqrt refit
# changes no conclusion. For airtight native-scale inference under
# heteroscedasticity, use cluster-robust SEs -- not a transform.
m_A_sqrt  <- update(m_A,  sqrt(new_area_per_ft) ~ .)
m_B2_sqrt <- update(m_B2, sqrt(new_area_per_ft) ~ .)

fe <- function(m, sc) {
  co <- summary(m)$coefficients[c("cum_excess_k", "interval_years"),
                                c("Estimate", "t value")]
  data.frame(scale = sc, term = rownames(co),
             est = round(co[, 1], 3), t = round(co[, 2], 2))
}
cat("\n=== Fixed effects, native vs sqrt (sign + significance robust) ===\n")
print(rbind(fe(m_B2, "identity"), fe(m_B2_sqrt, "sqrt")), row.names = FALSE)

reach_slope  <- function(m) {
  comp <- Filter(function(d) "cum_excess_k" %in% colnames(d), ranef(m))[[1]]
  setNames(fixef(m)[["cum_excess_k"]] + comp[, "cum_excess_k"], rownames(comp))
}
interval_eff <- function(m) setNames(ranef(m)$interval[, 1], rownames(ranef(m)$interval))

s_id <- reach_slope(m_B2);  s_sq <- reach_slope(m_B2_sqrt)[names(s_id)]
i_id <- interval_eff(m_B2); i_sq <- interval_eff(m_B2_sqrt)[names(i_id)]
cat("\n=== Rank agreement, native vs sqrt (Spearman) ===\n")
cat("  reach slopes    :", round(cor(s_id, s_sq, method = "spearman"), 3), "\n")
cat("  interval effects:", round(cor(i_id, i_sq, method = "spearman"), 3), "\n")
ri <- setNames(rank(i_id), names(i_id)); rs <- setNames(rank(i_sq), names(i_sq))
cat("  2017-2020 rank (1 = most below forcing): identity", ri["2017-2020"],
    "| sqrt", rs["2017-2020"], "\n")


# ---- Diagnostics: residuals (both models) -----------------------------------
resid_df <- bind_rows(
  tibble(model = "reach-only",
         fitted = fitted(m_ri),  resid = resid(m_ri),  std = resid(m_ri) / sigma(m_ri)),
  tibble(model = "reach+interval",
         fitted = fitted(m_cross), resid = resid(m_cross), std = resid(m_cross) / sigma(m_cross)),
  tibble(model = "m_B2 (record)",
         fitted = fitted(m_B2), resid = resid(m_B2), std = resid(m_B2) / sigma(m_B2))
)

p_resid <- ggplot(resid_df, aes(fitted, std)) +
  geom_hline(yintercept = 0, color = "grey60") +
  geom_point(alpha = 0.6, color = "#2c7fb8") +
  facet_wrap(~ model) +
  labs(x = "Fitted (ft)", y = "Std. residual",
       title = "LMM residuals vs fitted") +
  theme_minimal(base_size = 12)

p_qq <- ggplot(resid_df, aes(sample = std)) +
  stat_qq(alpha = 0.6, color = "#2c7fb8") + stat_qq_line(color = "#d95f0e") +
  facet_wrap(~ model) +
  labs(x = "Theoretical", y = "Std. residual", title = "LMM residual Q-Q") +
  theme_minimal(base_size = 12)

ggsave("plots/lmm_residuals.png",
       gridExtra::arrangeGrob(p_resid, p_qq, ncol = 1),
       width = 8, height = 8, units = "in")


# ---- Diagnostics: random-effect caterpillars --------------------------------
# Conditional modes +/- 2 SE. Reach intercepts compared across both models;
# interval intercepts from the crossed model reveal flood-interval effects (a
# below-forcing record flood shows as a negative interval effect = saturation).
tidy_ranef <- function(model, grp) {
  re <- ranef(model, condVar = TRUE)[[grp]]
  pv <- attr(re, "postVar")
  tibble(level = rownames(re), est = re[, 1], se = sqrt(pv[1, 1, ]))
}

cat_reach <- bind_rows(
  tidy_ranef(m_ri, "river_segment") %>% mutate(model = "reach-only"),
  tidy_ranef(m_cross, "river_segment") %>% mutate(model = "reach+interval")
) %>%
  mutate(level = factor(level, levels = as.character(37:28)))  # 25-27 excluded (Pendleton levees)

p_cat_reach <- ggplot(cat_reach, aes(est, level, color = model)) +
  geom_vline(xintercept = 0, linetype = 2, color = "grey60") +
  geom_pointrange(aes(xmin = est - 2 * se, xmax = est + 2 * se),
                  position = position_dodge(width = 0.6)) +
  scale_color_manual(values = c(`reach-only` = "#2c7fb8", `reach+interval` = "#d95f0e")) +
  labs(x = "Reach intercept (ft)", y = "River segment",
       title = "Reach random intercepts", color = NULL) +
  theme_minimal(base_size = 12)

# Interval effects from the model of record (m_B2): net of interval_years, so a
# negative value means "responded below forcing" with baseline time-accrual
# removed -- the clean saturation signal. 2017-2020 is NOT the standout (rank ~2
# of 15), so no special record-flood saturation.
cat_interval <- tidy_ranef(m_B2, "interval") %>%
  arrange(est) %>% mutate(level = factor(level, levels = level))

cat("\n=== m_B2 interval random effects (saturation read, net of interval_years) ===\n")
cat_interval %>% as.data.frame() %>% print(digits = 3)

p_cat_interval <- ggplot(cat_interval, aes(est, level)) +
  geom_vline(xintercept = 0, linetype = 2, color = "grey60") +
  geom_pointrange(aes(xmin = est - 2 * se, xmax = est + 2 * se), color = "#2c7fb8") +
  labs(x = "Interval intercept (ft)", y = "Interval",
       title = "Interval random intercepts (m_B2: net of interval_years)",
       subtitle = "Negative = responded below forcing, baseline time-accrual removed") +
  theme_minimal(base_size = 12)

ggsave("plots/lmm_caterpillar.png",
       gridExtra::arrangeGrob(p_cat_reach, p_cat_interval, ncol = 2),
       width = 11, height = 6, units = "in")


# ---- Diagnostics: per-reach scatter (slope heterogeneity + saturation) ------
# Three lines per reach, spanning the pooling spectrum:
#   grey   = that reach's own OLS (no pooling)
#   orange = shared population slope from fixef(m_B2) (complete pooling)
#   green  = LMM partial-pooling line: reach-specific intercept and slope, each
#            the fixed effect plus that reach's shrunken random effect. The green
#            line is pulled toward the orange consensus most where a reach's own
#            data are thin or noisy (watch reach 26 snap from flat to positive).
# interval_years and the interval RE are held at 0 for all three, matching the
# orange reference, so the lines are directly comparable.
reach_lines <- local({
  re   <- ranef(m_B2)
  cand <- re[grep("^river_segment", names(re))]         # the two reach RE terms
  b0d  <- cand[[which(vapply(cand, function(x) "(Intercept)" %in% colnames(x),
                             logical(1)))]]              # reach intercept component
  b0   <- setNames(b0d[["(Intercept)"]], rownames(b0d))
  sl   <- reach_slope(m_B2)                              # fixef slope + reach random slope
  tibble(river_segment = names(b0),
         intercept = fixef(m_B2)[["(Intercept)"]] + b0,
         slope     = sl[names(b0)]) %>%
    mutate(river_segment = factor(river_segment, levels = levels(panel$river_segment)))
})

p_scatter <- ggplot(panel, aes(cum_excess_k, new_area_per_ft)) +
  geom_abline(intercept = fixef(m_B2)[["(Intercept)"]],
              slope = fixef(m_B2)[["cum_excess_k"]],
              color = "#d95f0e", linewidth = 0.8) +
  geom_smooth(method = "lm", se = FALSE, color = "grey40", linewidth = 0.5, formula = y ~ x) +
  geom_abline(data = reach_lines, aes(intercept = intercept, slope = slope),
              color = "#238b45", linewidth = 0.7) +
  geom_point(size = 1.3, alpha = 0.7, color = "#2c7fb8") +
  facet_wrap(~ river_segment) +
  labs(x = "Cumulative excess > Q2 (1000 cfs-days)", y = "New area per ft (ft)",
       title = "Per-reach: reach OLS (grey) vs LMM partial-pool (green) vs population (orange)") +
  theme_minimal(base_size = 11)

ggsave("plots/lmm_reach_scatter.png", p_scatter, width = 10, height = 7, units = "in")

cat("\nWrote plots/lmm_residuals.png, plots/lmm_caterpillar.png, plots/lmm_reach_scatter.png\n")
