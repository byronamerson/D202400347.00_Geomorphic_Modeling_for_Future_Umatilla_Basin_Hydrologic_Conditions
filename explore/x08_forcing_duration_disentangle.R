# =============================================================================
# x08_forcing_duration_disentangle.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY: is the lowered-floor forcing carrying wet/dry hydrology beyond
#              interval length, or is it interval length in disguise?
# =============================================================================
#
# In x07, lowering the cum_excess floor to 0.75*Q2 shrank the interval RE 16% and
# fit better -- but the time-baseline collapsed (3.55 -> 1.37 ft/yr), and the
# intervals that gained the most forcing were the LONGEST ones. Two readings:
#   (b) real: sustained moderate flow does the "background" reworking, correctly
#       reattributed from a bare time term to a flow predictor.
#   (a) artifact: cum_excess at the low floor just tracks interval LENGTH, so it
#       is redundant with interval_years and the split between them is arbitrary
#       (and unsafe to extrapolate into the projection).
#
# The model already estimates the forcing effect NET of interval_years (its slope
# stays significant, t 3.42) -- so forcing is not a PURE time proxy. The open
# question is COLLINEARITY: are forcing and interval_years so correlated that the
# split is unstable? This script measures exactly that, at both floors.
#
# The picture: interval length (x) vs forcing (y), one point per interval.
#   - tight line  -> forcing ~ length; the baseline drop is an artifact (reading a)
#   - vertical spread at a given length (dry-long low, wet-long high)
#                 -> forcing carries hydrology beyond time (reading b) -> safe to lower
#
# Uses objects left by x07 (forcing, forcing_075, panel). Run x07 first.
# Leaves in env: iv (interval-level table), dur_cor (correlations + VIF)
# Plot: plots/x08_forcing_vs_duration.png
# =============================================================================

suppressPackageStartupMessages({library(dplyr); library(tidyr); library(ggplot2)})

stopifnot(exists("forcing"), exists("forcing_075"), exists("panel"))  # from x07/08


# =============================================================================
# 1. INTERVAL-LEVEL TABLE: length + forcing at each floor
# =============================================================================
# interval_years is per-interval; take the modeled intervals from the panel.

iv <- panel %>%
  distinct(interval, year_t1, year_t2, interval_years) %>%
  left_join(forcing %>% transmute(year_t1, year_t2,
                                  ce_q2   = cum_excess_thresh_cfs_days / 1000,
                                  any_est = any_estimated),
            by = c("year_t1", "year_t2")) %>%
  left_join(forcing_075 %>% transmute(year_t1, year_t2,
                                      ce_075 = cum_excess_thresh_cfs_days / 1000),
            by = c("year_t1", "year_t2")) %>%
  mutate(
    per_yr_q2  = ce_q2  / interval_years,   # forcing intensity (flow above thresh per year)
    per_yr_075 = ce_075 / interval_years
  ) %>%
  arrange(desc(interval_years))


# =============================================================================
# 2. THE NUMBERS: correlation of forcing with length, and its consequence
# =============================================================================

vif2 <- function(r) 1 / (1 - r^2)   # 2-predictor VIF from the predictor-predictor r

dur_cor <- tibble(
  floor        = c("Q2 (5,542)", "0.75*Q2 (4,156)"),
  pearson_len  = c(cor(iv$ce_q2, iv$interval_years),
                   cor(iv$ce_075, iv$interval_years)),
  spearman_len = c(cor(iv$ce_q2, iv$interval_years, method = "spearman"),
                   cor(iv$ce_075, iv$interval_years, method = "spearman")),
  R2_on_length = c(cor(iv$ce_q2, iv$interval_years)^2,
                   cor(iv$ce_075, iv$interval_years)^2)
) %>%
  mutate(
    vif       = vif2(pearson_len),            # inflation of the forcing/time split
    indep_pct = 100 * (1 - R2_on_length),     # % of forcing variation NOT explained by length
    # does flow-INTENSITY vary across intervals, or is it flat (= pure length)?
    intensity_cv = c(sd(iv$per_yr_q2)  / mean(iv$per_yr_q2),
                     sd(iv$per_yr_075) / mean(iv$per_yr_075))
  )


# =============================================================================
# 3. REPORT
# =============================================================================

cat("\n=========  FORCING vs INTERVAL LENGTH  (disentangling x07)  =========\n")
cat("One row per floor. 'indep_pct' = share of forcing variation NOT tied to length.\n",
    "'intensity_cv' = spread of forcing-per-year across intervals (flat = pure length).\n\n")
dur_cor %>% mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nInterval table (longest first):\n")
iv %>%
  transmute(interval, yrs = interval_years, ce_q2 = round(ce_q2, 1),
            ce_075 = round(ce_075, 1), per_yr_075 = round(per_yr_075, 2), any_est) %>%
  as.data.frame() %>% print(row.names = FALSE)

verdict <- if (dur_cor$R2_on_length[2] > 0.7) {
  "READ (a) leans in: at 0.75*Q2 the forcing is MOSTLY length -> split is shaky."
} else if (dur_cor$R2_on_length[2] < 0.5) {
  "READ (b) leans in: forcing keeps large wet/dry variation beyond length -> real."
} else {
  "MIXED: forcing shares substantial variance with length but keeps some independent."
}
cat("\n", verdict, "\n", sep = "")


# =============================================================================
# 4. THE PICTURE: length vs forcing, both floors
# =============================================================================

plot_df <- iv %>%
  select(interval, interval_years, any_est, ce_q2, ce_075) %>%
  pivot_longer(c(ce_q2, ce_075), names_to = "floor", values_to = "forcing") %>%
  mutate(floor = factor(floor, levels = c("ce_q2", "ce_075"),
                        labels = c("floor = Q2 (5,542)", "floor = 0.75*Q2 (4,156)")))

p_dur <- ggplot(plot_df, aes(interval_years, forcing)) +
  geom_smooth(method = "lm", se = FALSE, colour = "grey65",
              linewidth = 0.5, formula = y ~ x) +
  geom_point(aes(colour = any_est), size = 2.4) +
  geom_text(aes(label = interval), size = 2.5, vjust = -0.7, check_overlap = TRUE) +
  facet_wrap(~ floor, scales = "free_y") +
  scale_colour_manual(values = c(`TRUE` = "#c1440e", `FALSE` = "#1f4e79"),
                      labels = c(`TRUE` = "contains reconstructed days",
                                 `FALSE` = "observed only"), name = NULL) +
  labs(
    title = "Is the forcing carrying hydrology, or just interval length?",
    subtitle = "Vertical spread at a given length = wet/dry contrast beyond time (real). A tight line = length in disguise.",
    x = "interval length (years)", y = "cum_excess (1,000 cfs-days)"
  ) +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

if (!dir.exists("plots")) dir.create("plots")
ggsave("plots/x08_forcing_vs_duration.png", p_dur, width = 10, height = 5.2, dpi = 130)
cat("\nWrote plots/x08_forcing_vs_duration.png\n")

# =============================================================================
# 5. INTERACTIVE (single-hash = executable; double-hash = narration)
# =============================================================================
##
# iv       # interval length + forcing at each floor + per-year intensity
# dur_cor  # correlation w/ length, VIF, independent %, intensity spread
#
## Stability probe: does the baseline/slope split survive dropping the long
## reconstructed leverage interval (1952-1974)? If it swings hard, collinearity
## is driving the split.
# panel_075_drop <- dplyr::filter(panel_075, interval != "1952-1974")
# summary(fit_forcing_model(panel_075_drop, "cum_excess_k"))$coefficients
