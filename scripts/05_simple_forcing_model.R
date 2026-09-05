# =============================================================================
# 05_simple_forcing_model.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 5 (FINALIZED): total NEW AREA vs total cumulative excess, RS 30
# =============================================================================
#
# THE MODEL (deliberately the simplest thing that works):
#
#     total new area over the interval  ~  total cumulative excess over the interval
#     lm(new_area_ft2 ~ cum_excess_thresh_cfs_days)          # equal weights
#
# This script is the FINALIZED single-reach workflow AND the reusable per-reach
# template for the RS 25-37 linear mixed-effects model. It runs top-to-bottom:
#   1. Base fit (all intervals)
#   2. Influence screen  -- Cook's D, leverage, studentized residual (FLAG only)
#   3. Outlier policy     -- exclude a flagged point ONLY with a documented reason
#   4. Sensitivity        -- primary (excluded) vs all-intervals fit, side by side
#   5. Robust cross-check -- Huber rlm, the no-hard-delete view of the same data
#   6. Validation battery -- single-flood leverage / LOO / permutation / extrap
#   7. Outputs            -- scatter, influence plot, compact results CSVs
#
# THE OUTLIER RULE (the whole policy, briefly):
#   Flag high-influence points with standard diagnostics, but DELETE one only if
#   it also has an independent, documented reason to be spurious. Report the fit
#   with AND without, always. The two extremes are NOT symmetric: a big-area /
#   ~zero-forcing point is mechanism-violating (flood work with no flood -> data
#   artifact, excludable); a big-forcing / small-area point can be a real
#   resistant-reach response (keep it). So we exclude on reason, never on residual
#   distance from the line -- trimming to the line inflates R^2 and pre-bakes any
#   downstream model.
#
# Why NEW AREA (not net change): net = new - abandoned is a signed directional
#   residual that cancels over long intervals and mixes flood-driven erosion with
#   non-flood abandonment. New area = a flood-clean AMOUNT of erosion, same
#   currency as cum_excess (an amount of forcing). Full rationale:
#   NOTE_simple_forcing_model.md.
#
# Depends on: rs30_interval_sandbox.R (response totals) + 04c (forcing totals).
#   Extrapolation check also reads data/dv_gage_daily_flows.csv (04a) and
#   data/pendleton_daily_extended.rds (04b).
# =============================================================================

library(dplyr)
library(broom)
library(ggplot2)
library(purrr)


# ---- 0. Assemble the table (response totals + forcing totals) ----------------
# Source order matters: the sandbox and 04c both define `config`. Source the
# sandbox first (captures response), then 04c so its forcing `config` is active.
source("scripts/rs30_interval_sandbox.R")
intervals <- distinct(rs30_plot_data, year_t1, year_t2)
source("scripts/04c_interval_forcing_metrics.R")
forcing <- run_interval_forcing_metrics(config, intervals)

dat <- rs30_plot_data %>%
  left_join(forcing, by = c("year_t1", "year_t2"))

n_all <- nrow(dat)
p_par <- 2L   # intercept + slope


# ---- 1. Base fit: all intervals ---------------------------------------------
m_all <- lm(new_area_ft2 ~ cum_excess_thresh_cfs_days, data = dat)
cat("\n=== Base fit: new_area ~ cum_excess (ALL intervals, n =", n_all, ") ===\n")
print(summary(m_all))


# ---- 2. Influence screen (FLAG, never auto-drop) ----------------------------
# Conventional cutoffs used only to FLAG points for review:
#   Cook's D > 4/n ; |studentized resid| > 2 ; leverage (hat) > 2*p/n
influence <- dat %>%
  transmute(
    interval_label, year_t1, year_t2,
    cum_excess = round(cum_excess_thresh_cfs_days),
    new_area   = round(new_area_ft2),
    cooksD     = cooks.distance(m_all),
    leverage   = hatvalues(m_all),
    std_resid  = rstudent(m_all)
  ) %>%
  mutate(
    flag_cook  = cooksD    > 4 / n_all,
    flag_lev   = leverage  > 2 * p_par / n_all,
    flag_resid = abs(std_resid) > 2,
    flagged    = flag_cook | flag_lev | flag_resid
  ) %>%
  arrange(desc(cooksD))
cat("\n--- Influence screen (flags for review; exclusion still needs a reason) ---\n")
print(influence, n = Inf)


# ---- 3. Outlier policy: documented exclusions -------------------------------
# One row per excluded interval, each with an independent, written reason.
# Expect this table to grow per-RS as we scale to the mixed model.
exclusions <- tibble::tribble(
  ~year_t1, ~year_t2, ~reason,
  2011,     2012,     "Zero forcing paired with ~1.3M ft2 new area (mechanism-violating). DOGAMI-confirmed HMA mapping artifact: averages out in their risk-over-time framing but distorts a per-interval flood->change model."
)
cat("\n--- Documented exclusions ---\n")
print(exclusions)

dat_primary <- dat %>% anti_join(exclusions, by = c("year_t1", "year_t2"))
n_pri <- nrow(dat_primary)

m_primary <- lm(new_area_ft2 ~ cum_excess_thresh_cfs_days, data = dat_primary)
cat("\n=== PRIMARY fit: new_area ~ cum_excess (2011-2012 excluded, n =", n_pri, ") ===\n")
print(summary(m_primary))


# ---- 4. Sensitivity: primary vs all-intervals, side by side -----------------
fit_row <- function(f, label) {
  g <- glance(f); co <- summary(f)$coefficients
  tibble(
    fit       = label,
    n         = stats::nobs(f),
    r_squared = g$r.squared,
    p_value   = g$p.value,
    slope     = co["cum_excess_thresh_cfs_days", "Estimate"],
    intercept = co["(Intercept)", "Estimate"],
    intercept_p = co["(Intercept)", "Pr(>|t|)"]
  )
}
sensitivity <- bind_rows(
  fit_row(m_primary, "primary (2011-2012 excluded)"),
  fit_row(m_all,     "all intervals")
)
cat("\n--- Sensitivity: exclusion effect on the fit ---\n")
print(as.data.frame(sensitivity))

# Same simple form for the other area totals (documents why new_area is the one).
area_totals <- c("new_area_ft2", "net_area_change_ft2", "symmetric_change_ft2", "abandoned_area_ft2")
area_contrast <- bind_rows(lapply(area_totals, function(y) {
  f <- lm(reformulate("cum_excess_thresh_cfs_days", y), data = dat_primary)
  glance(f) %>% transmute(response = y, r_squared = r.squared, p_value = p.value,
                          slope = coef(f)[["cum_excess_thresh_cfs_days"]])
})) %>% arrange(desc(r_squared))
cat("\n--- All area totals ~ cum_excess (primary data, for contrast) ---\n")
print(as.data.frame(area_contrast))


# ---- 5. Robust cross-check (Huber): the no-hard-delete view ------------------
# rlm down-weights BOTH extremes automatically. Two things to see: (a) run on ALL
# intervals, what weight does it put on 2011-2012 (should be ~0 -> it "excludes"
# the artifact on its own); (b) does the robust slope agree with our OLS primary
# slope (agreement = our documented deletion matches what robust does anyway).
robust_ok <- requireNamespace("MASS", quietly = TRUE)
if (robust_ok) {
  rob_all <- MASS::rlm(new_area_ft2 ~ cum_excess_thresh_cfs_days, data = dat,
                       psi = MASS::psi.huber, maxit = 100)
  w_2011  <- rob_all$w[which(dat$year_t1 == 2011 & dat$year_t2 == 2012)]
  rob_pri <- MASS::rlm(new_area_ft2 ~ cum_excess_thresh_cfs_days, data = dat_primary,
                       psi = MASS::psi.huber, maxit = 100)
  robust <- tibble(
    robust_all_slope        = coef(rob_all)[["cum_excess_thresh_cfs_days"]],
    robust_weight_2011_2012 = as.numeric(w_2011),
    robust_primary_slope    = coef(rob_pri)[["cum_excess_thresh_cfs_days"]],
    ols_primary_slope       = coef(m_primary)[["cum_excess_thresh_cfs_days"]]
  )
  cat("\n--- Robust (Huber) cross-check ---\n"); print(as.data.frame(robust))
} else {
  robust <- tibble(robust_all_slope = NA, robust_weight_2011_2012 = NA,
                   robust_primary_slope = NA, ols_primary_slope = coef(m_primary)[[2]])
  cat("\n[robust cross-check skipped: MASS not installed]\n")
}


# ---- 6. Validation battery (ported from 04d; on the PRIMARY fit) ------------
# 6a. Single-flood leverage: drop the 2017-2020 record flood (the high-leverage
#     point). Does new_area ~ cum_excess survive without it?
m_drop2020 <- lm(new_area_ft2 ~ cum_excess_thresh_cfs_days,
                 data = subset(dat_primary, !(year_t1 == 2017 & year_t2 == 2020)))
val_drop2020 <- glance(m_drop2020)
cat("\n--- 6a. Drop 2017-2020 record flood -> R2 =", round(val_drop2020$r.squared, 3),
    " p =", round(val_drop2020$p.value, 3), "(n =", stats::nobs(m_drop2020), ") ---\n")

# 6b. Full leave-one-out: worst-case (max) p across single drops. Rule: max p
#     < 0.10 -> "holds"; otherwise "suggestive".
loo <- map_dfr(seq_len(n_pri), function(i) {
  f <- lm(new_area_ft2 ~ cum_excess_thresh_cfs_days, data = dat_primary[-i, ])
  glance(f) %>% transmute(
    dropped   = paste0(dat_primary$year_t1[i], "-", dat_primary$year_t2[i]),
    r_squared = r.squared, p_value = p.value
  )
}) %>% arrange(desc(p_value))
loo_maxp        <- max(loo$p_value)
most_loadbearing <- loo$dropped[which.max(loo$p_value)]
cat("\n--- 6b. LOO worst single drop: p =", round(loo_maxp, 3),
    "(most load-bearing =", most_loadbearing, ") ---\n")
print(head(loo, 3))

# 6c. Permutation test: shuffle the response 10,000x; permutation p = fraction of
#     shuffles whose R2 >= observed. Replaces t-test asymptotics at small n.
set.seed(1)
obs_r2 <- glance(m_primary)$r.squared
null_r2 <- replicate(10000, {
  d <- dat_primary
  d$new_area_ft2 <- sample(d$new_area_ft2)
  glance(lm(new_area_ft2 ~ cum_excess_thresh_cfs_days, d))$r.squared
})
perm_p <- mean(null_r2 >= obs_r2)
cat("\n--- 6c. Permutation p =", round(perm_p, 4), " (parametric p =",
    round(obs_r2 <- glance(m_primary)$p.value, 4), ") ---\n")

# 6d. Reconstruction extrapolation check (unchanged from 04d): were any
#     reconstructed daily values driven by Gibbon inputs above the calibration
#     max? EXPECTED n_extrapolated = 0.
gib <- readr::read_csv("data/dv_gage_daily_flows.csv", show_col_types = FALSE) %>%
  filter(gage_id == "14020000") %>%
  transmute(date = as.Date(date), gibbon_q = daily_q_cfs)
ext         <- readRDS("data/pendleton_daily_extended.rds")
recon_dates <- subset(ext, is_estimated)$date
obs_start   <- min(subset(ext, !is_estimated)$date)
gib_cal_max <- max(gib$gibbon_q[gib$date >= obs_start])
gib_recon   <- gib$gibbon_q[gib$date %in% recon_dates]
extrap <- c(gib_cal_max = gib_cal_max, gib_recon_max = max(gib_recon),
            n_extrapolated = sum(gib_recon > gib_cal_max))
cat("\n--- 6d. Extrapolation check ---\n"); print(extrap)


# ---- 7. Outputs -------------------------------------------------------------
dat$excluded <- with(dat, year_t1 == 2011 & year_t2 == 2012)

# 7a. Scatter: primary fit line; excluded point marked; record flood annotated.
p_simple <- ggplot() +
  geom_smooth(data = dat_primary, aes(cum_excess_thresh_cfs_days, new_area_ft2),
              method = "lm", formula = y ~ x, se = TRUE,
              color = "#d95f0e", fill = "#f6d9bf", linewidth = 0.9) +
  geom_point(data = subset(dat, !excluded),
             aes(cum_excess_thresh_cfs_days, new_area_ft2), size = 3, color = "#2c7fb8") +
  geom_point(data = subset(dat, excluded),
             aes(cum_excess_thresh_cfs_days, new_area_ft2),
             shape = 4, size = 4, stroke = 1.3, color = "#b2182b") +
  { if (requireNamespace("ggrepel", quietly = TRUE))
      ggrepel::geom_text_repel(data = dat, aes(cum_excess_thresh_cfs_days, new_area_ft2,
                               label = interval_label), size = 3, seed = 1, min.segment.length = 0)
    else geom_text(data = dat, aes(cum_excess_thresh_cfs_days, new_area_ft2,
                   label = interval_label), size = 3, vjust = -0.7) } +
  labs(
    x = "Cumulative excess > Q2 over interval (cfs-days)",
    y = "New area over interval (ft^2)",
    title = "RS 30: total new channel area vs total flood forcing",
    subtitle = sprintf("Primary fit (2011-2012 excluded, red X), equal weights, n = %d  |  R^2 = %.3f, p = %.3f",
                       n_pri, glance(m_primary)$r.squared, glance(m_primary)$p.value)
  ) +
  theme_minimal(base_size = 12)
ggsave("plots/simple_new_area_vs_cum_excess.png", p_simple, width = 8, height = 5.5, units = "in")
print(p_simple)

# 7b. Influence plot: leverage vs studentized residual, bubble = Cook's D.
p_infl <- ggplot(influence, aes(leverage, std_resid)) +
  geom_hline(yintercept = c(-2, 2), linetype = 2, color = "grey60") +
  geom_vline(xintercept = 2 * p_par / n_all, linetype = 2, color = "grey60") +
  geom_point(aes(size = cooksD, color = flagged), alpha = 0.7) +
  scale_color_manual(values = c(`FALSE` = "#2c7fb8", `TRUE` = "#b2182b")) +
  { if (requireNamespace("ggrepel", quietly = TRUE))
      ggrepel::geom_text_repel(aes(label = interval_label), size = 3, seed = 1, min.segment.length = 0)
    else geom_text(aes(label = interval_label), size = 3, vjust = -0.7) } +
  labs(
    x = "Leverage (hat)", y = "Studentized residual",
    size = "Cook's D", color = "Flagged",
    title = "RS 30 influence screen",
    subtitle = sprintf("Dashed: leverage = 2p/n = %.2f, |resid| = 2. Flag != delete (delete needs a reason).",
                       2 * p_par / n_all)
  ) +
  theme_minimal(base_size = 12)
ggsave("plots/rs30_influence.png", p_infl, width = 8, height = 5.5, units = "in")
print(p_infl)

# 7c. Compact results dump (for review / logging).
results <- tibble::tibble(
  metric = c(
    "fit_all_n", "fit_all_r2", "fit_all_p", "fit_all_slope", "fit_all_intercept", "fit_all_intercept_p",
    "fit_primary_n", "fit_primary_r2", "fit_primary_p", "fit_primary_slope", "fit_primary_intercept", "fit_primary_intercept_p",
    "robust_all_slope", "robust_weight_2011_2012", "robust_primary_slope",
    "val_drop2020_r2", "val_drop2020_p", "val_loo_maxp", "val_loo_most_loadbearing",
    "val_perm_p", "val_gib_cal_max", "val_gib_recon_max", "val_n_extrapolated"
  ),
  value = c(
    n_all, glance(m_all)$r.squared, glance(m_all)$p.value,
    coef(m_all)[[2]], coef(m_all)[[1]], summary(m_all)$coefficients["(Intercept)", "Pr(>|t|)"],
    n_pri, glance(m_primary)$r.squared, glance(m_primary)$p.value,
    coef(m_primary)[[2]], coef(m_primary)[[1]], summary(m_primary)$coefficients["(Intercept)", "Pr(>|t|)"],
    robust$robust_all_slope, robust$robust_weight_2011_2012, robust$robust_primary_slope,
    val_drop2020$r.squared, val_drop2020$p.value, loo_maxp, most_loadbearing,
    perm_p, extrap[["gib_cal_max"]], extrap[["gib_recon_max"]], extrap[["n_extrapolated"]]
  ) %>% as.character()
)
readr::write_csv(results, "data/rs30_single_model_results.csv")
readr::write_csv(influence, "data/rs30_influence_screen.csv")
cat("\n=== Wrote data/rs30_single_model_results.csv and data/rs30_influence_screen.csv ===\n")
cat("=== Wrote plots/simple_new_area_vs_cum_excess.png and plots/rs30_influence.png ===\n")
