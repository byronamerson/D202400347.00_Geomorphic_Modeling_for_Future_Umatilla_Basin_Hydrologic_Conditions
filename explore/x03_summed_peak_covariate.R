# =============================================================================
# x03_summed_peak_covariate.R   (EXPLORATORY -- not folded into 07)
# -----------------------------------------------------------------------------
# Hypothesis (Byron): a peak-based forcing metric that accounts for EVERY flood
# peak above Q2 in the interval -- not just the single largest crest -- may
# perform like cumulative excess once interval_years is in the model.
#
# New metric: sum_peak_excess = SUM over every above-Q2 flood event of
#   (that event's peak daily flow - Q2). One value per flood crest, weighted by
#   how high it crested. Contrast with the two metrics we already have:
#     cum_excess_k       -- integrates magnitude AND duration (area under hydrograph > Q2)
#     q_peak_daily_cfs   -- the single biggest crest only (all other floods discarded)
#   sum_peak_excess sits between: counts every flood by crest height, ignores duration.
#
# A "flood event" = one consecutive-day span above Q2 (same span logic that
# defines n_events / cum_excess), and its peak = max daily flow within the span.
#
# Fits on the live `panel` from 07 (RS 28-37). Source 07 first if not present.
# =============================================================================

library(lme4); library(dplyr); library(tidyr); library(purrr)
source("scripts/04c_interval_forcing_metrics.R")  # config, cfg, cfg_num, add_water_year

stopifnot(exists("panel"), all(c("year_t1", "year_t2") %in% names(panel)))

threshold <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")   # = Q2 = 5542
dw        <- add_water_year(readRDS(cfg("extended_record_rds")))     # daily, + water_year

# ---- Build the summed-peak metric per interval ------------------------------
# forcing window for t1->t2 is water years (t1+1)..t2 (matches 07 / the sandbox).
peak_metric_one <- function(t1, t2) {
  window <- filter(dw, water_year > t1, water_year <= t2)
  above  <- filter(window, daily_q_cfs >= threshold) %>% arrange(date)
  if (nrow(above) == 0L)
    return(tibble(sum_peak_excess = 0, n_peaks = 0L, max_peak = if (nrow(window)) max(window$daily_q_cfs) else NA_real_))
  span <- cumsum(c(TRUE, as.integer(diff(above$date)) > 1L))         # >1-day gap ends a flood
  per  <- tibble(q = above$daily_q_cfs, span) %>%
    group_by(span) %>% summarise(peak = max(q), .groups = "drop")
  tibble(sum_peak_excess = sum(per$peak - threshold),               # every crest, above Q2
         n_peaks         = nrow(per),
         max_peak        = max(per$peak))
}

peak_tbl <- distinct(panel, year_t1, year_t2) %>%
  mutate(m = pmap(list(year_t1, year_t2), peak_metric_one)) %>%
  unnest(m) %>%
  mutate(sum_peak_excess_k = sum_peak_excess / 1000)

panel2 <- panel %>%
  left_join(select(peak_tbl, year_t1, year_t2, sum_peak_excess_k, n_peaks, max_peak),
            by = c("year_t1", "year_t2")) %>%
  mutate(q_peak_k = q_peak_daily_cfs / 1000)

# sanity: n_peaks should equal the panel's n_events; max_peak should equal q_peak
cat("=== sanity (should match) ===\n")
cat("  n_peaks == n_events_thresh :", all(panel2$n_peaks == panel2$n_events_thresh), "\n")
cat("  max_peak == q_peak_daily   :", isTRUE(all.equal(panel2$max_peak, panel2$q_peak_daily_cfs)), "\n")


# ---- 1. Collinearity: is summed-peak more separable than single-max-peak? ----
iv <- distinct(panel2, interval, cum_excess_k, sum_peak_excess_k, q_peak_k, interval_years)
cat("\n=== Correlation among interval-level predictors (n =", nrow(iv), ") ===\n")
print(round(cor(iv[, c("cum_excess_k", "sum_peak_excess_k", "q_peak_k", "interval_years")]), 2))


# ---- 2. Three forcing metrics, each net of interval_years (ML, m_A structure) ----
# Same complexity (base + one forcing term), so AIC is directly comparable.
base     <- lmer(new_area_per_ft ~ interval_years +
                   (1 | river_segment) + (1 | interval), panel2, REML = FALSE)
m_cum    <- update(base, . ~ . + cum_excess_k)       # incumbent
m_maxpk  <- update(base, . ~ . + q_peak_k)           # single biggest crest (the earlier "peak alone")
m_sumpk  <- update(base, . ~ . + sum_peak_excess_k)  # every crest above Q2  <-- the new idea

compare_row <- function(m, term, label) {
  co <- summary(m)$coefficients
  tibble(model = label,
         forcing_slope    = round(co[term, "Estimate"], 3),
         forcing_t        = round(co[term, "t value"], 2),
         interval_years_t = round(co["interval_years", "t value"], 2),
         AIC              = round(AIC(m), 1))
}
cat("\n=== Forcing metric bake-off (all net of interval_years; lower AIC = better) ===\n")
cat("    base (interval_years only) AIC =", round(AIC(base), 1), "\n")
bind_rows(
  compare_row(m_cum,   "cum_excess_k",      "cum_excess (incumbent)"),
  compare_row(m_maxpk, "q_peak_k",          "max peak only"),
  compare_row(m_sumpk, "sum_peak_excess_k", "sum of every peak-excess")
) %>% as.data.frame() %>% print(row.names = FALSE)

cat("\n=== LRT: does each forcing metric beat interval_years-only? ===\n")
cat("  sum-of-peaks :\n"); print(anova(base, m_sumpk)[2, c("Chisq", "Df", "Pr(>Chisq)")])
cat("  cum_excess   :\n"); print(anova(base, m_cum)[2,  c("Chisq", "Df", "Pr(>Chisq)")])
cat("  max-peak     :\n"); print(anova(base, m_maxpk)[2, c("Chisq", "Df", "Pr(>Chisq)")])

# Read: if sum-of-peaks lands near cum_excess on AIC and its slope is significant,
# your hypothesis holds -- counting every crest recovers the forcing signal, and
# the earlier max-peak fit was poor mainly because it discarded all but one flood.
