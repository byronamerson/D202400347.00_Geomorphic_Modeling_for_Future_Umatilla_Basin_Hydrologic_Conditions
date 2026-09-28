# =============================================================================
# x10_separation_collinearity.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY: are baseflow vs quickflow forcing LESS collinear than the bands?
# =============================================================================
#
# The payoff test. x06 showed the flood band (>Q2) and the maintenance band
# (0.5*Q2 -> Q2) were collinear per water year: Pearson 0.60, Spearman 0.82. The
# hypothesis is that a physical SUSTAINED-vs-EVENT split (baseflow vs quickflow)
# separates the two drivers more cleanly than a flow-LEVEL split (bands).
#
# Test (same shape as x06): per complete water year on the OBSERVED Pendleton
# record (WY1996-2025), sum baseflow and quickflow into two annual forcing totals,
# and correlate them across years. Compare to the bands' 0.60 / 0.82. Run it for
# each separation method (IH and Eckhardt headline; one-param kept for contrast).
#
#   quickflow_total = sum(flow - baseflow)   # the event / flood driver
#   baseflow_total  = sum(baseflow)          # the sustained / maintenance driver
#
# Also reported: how much each piece is just "annual wetness" (its correlation
# with total flow) -- because both grow in wet years, some collinearity is
# inescapable; the question is whether it beats the bands.
#
# Reuses x09 (pend_sep, method params). Run after x09.
# Leaves in env: wy_forcing, sep_cor
# Plot: plots/x10_quickflow_vs_baseflow.png
#
# Style: lingua.md + Tidyverse & FP guidelines. Self-running on source().
# =============================================================================

source("explore/x09_baseflow_method_comparison.R")   # pend_sep + params
suppressPackageStartupMessages(library(tidyverse))

# x06 benchmark: flood band vs maintenance band, per water year, observed Pendleton
BANDS_PEARSON  <- 0.60
BANDS_SPEARMAN <- 0.82

METHODS <- c(ih = "bf_ih", eckhardt = "bf_eckhardt", oneparam = "bf_oneparam")


# =============================================================================
# 1. PER-WATER-YEAR FORCING (baseflow total, quickflow total), per method
# =============================================================================
# Complete water years only, matching x06 (WY1996-2025, >= 350 days).

sep_totals <- function(sep, bf_col) {
  sep %>%
    group_by(water_year) %>%
    summarise(n_days = dplyr::n(),
              total_k = sum(daily_q_cfs) / 1000,
              bf_k    = sum(.data[[bf_col]]) / 1000,
              qf_k    = sum(daily_q_cfs - .data[[bf_col]]) / 1000,
              .groups = "drop") %>%
    filter(water_year >= 1996, water_year <= 2025, n_days >= 350)
}

# wide per-WY table (one bf/qf pair per method) for the plot + inspection
wy_forcing <- reduce(names(METHODS), function(acc, m) {
  t <- sep_totals(pend_sep, METHODS[[m]]) %>%
    select(water_year, total_k,
           !!paste0("bf_", m) := bf_k, !!paste0("qf_", m) := qf_k)
  if (is.null(acc)) t else left_join(acc, select(t, -total_k), by = "water_year")
}, .init = NULL)


# =============================================================================
# 2. COLLINEARITY, PER METHOD  (vs the bands' benchmark)
# =============================================================================

sep_cor <- map_dfr(names(METHODS), function(m) {
  d  <- sep_totals(pend_sep, METHODS[[m]])
  cc <- complete.cases(d[c("qf_k", "bf_k", "total_k")])   # IH: drop the leading-NA WY
  d  <- d[cc, ]
  tibble(
    method         = m,
    n_years        = nrow(d),
    pearson_qf_bf  = cor(d$qf_k, d$bf_k),
    spearman_qf_bf = cor(d$qf_k, d$bf_k, method = "spearman"),
    vif            = 1 / (1 - cor(d$qf_k, d$bf_k)^2),
    r_qf_total     = cor(d$qf_k, d$total_k),   # how much quickflow is just wetness
    r_bf_total     = cor(d$bf_k, d$total_k)    # how much baseflow  is just wetness
  )
})


# =============================================================================
# 3. REPORT
# =============================================================================

cat("\n=========  SUSTAINED-vs-EVENT SPLIT: does it beat the bands?  =========\n")
cat(sprintf("Benchmark (x06 flood vs maintenance bands): Pearson %.2f | Spearman %.2f\n",
            BANDS_PEARSON, BANDS_SPEARMAN))
cat("Per water year, WY1996-2025, observed Pendleton.\n\n")

sep_cor %>%
  mutate(
    beats_bands = if_else(pearson_qf_bf < BANDS_PEARSON, "yes", "no"),
    across(where(is.numeric), ~ round(.x, 3))
  ) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nRead: pearson_qf_bf < 0.60 => baseflow/quickflow separate more cleanly than\n",
    "the bands. r_*_total near 1 => that piece is mostly just annual wetness.\n", sep = "")


# =============================================================================
# 4. PLOT: quickflow vs baseflow per water year, by method
# =============================================================================

plot_df <- map_dfr(names(METHODS), function(m) {
  sep_totals(pend_sep, METHODS[[m]]) %>%
    transmute(water_year, method = m, bf_k, qf_k)
}) %>%
  mutate(method = factor(method, levels = c("ih", "eckhardt", "oneparam")))

p_sep <- ggplot(plot_df, aes(bf_k, qf_k)) +
  geom_smooth(method = "lm", se = FALSE, colour = "grey70",
              linewidth = 0.5, formula = y ~ x) +
  geom_point(size = 2, colour = "#1f4e79") +
  geom_text(aes(label = water_year), size = 2.4, vjust = -0.7, check_overlap = TRUE) +
  facet_wrap(~ method, scales = "free") +
  labs(title = "Quickflow vs baseflow forcing per water year",
       subtitle = "Off the trend line = years where event water and sustained water diverge. Tight line = collinear (like the bands).",
       x = "baseflow total (1,000 cfs-days)",
       y = "quickflow total (1,000 cfs-days)") +
  theme_minimal(base_size = 11)

if (!dir.exists("plots")) dir.create("plots")
ggsave("plots/x10_quickflow_vs_baseflow.png", p_sep, width = 11, height = 4.5, dpi = 130)
cat("\nWrote plots/x10_quickflow_vs_baseflow.png\n")

# =============================================================================
# 5. INTERACTIVE
# =============================================================================
##
# sep_cor      # collinearity per method vs the bands
# wy_forcing   # per-WY baseflow/quickflow totals, all methods
