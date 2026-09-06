# =============================================================================
# x04_drop2017_and_metric_table.R   (EXPLORATORY -- not folded into 07)
# -----------------------------------------------------------------------------
# Two things:
#   (1) Per-interval table of cum_excess vs sum-of-peaks, with their ratio
#       (= "crest-only fraction"; low ratio = duration-inflated interval) and
#       the mean migration response -- so we can SEE where the metrics disagree.
#   (2) Fragility check: refit the three forcing metrics with 2017-2020 dropped.
#       Does sum-of-peaks keep its ~4-AIC edge, or was it one-interval leverage?
#
# Key identity: sum_peak_excess_k <= cum_excess_k for every interval. Sum-of-peaks
# is cum_excess with the extra above-Q2 DURATION volume removed, so this whole
# comparison is really "does duration volume help or hurt?".
#
# Source 07 first (needs the live `panel`, RS 28-37).
# =============================================================================

library(lme4); library(dplyr); library(tidyr); library(purrr)
source("scripts/04c_interval_forcing_metrics.R")   # config, cfg, cfg_num, add_water_year

stopifnot(exists("panel"), all(c("year_t1", "year_t2") %in% names(panel)))

threshold <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")
dw        <- add_water_year(readRDS(cfg("extended_record_rds")))

peak_metric_one <- function(t1, t2) {
  above <- dw %>% filter(water_year > t1, water_year <= t2,
                         daily_q_cfs >= threshold) %>% arrange(date)
  if (nrow(above) == 0L) return(tibble(sum_peak_excess = 0))
  span <- cumsum(c(TRUE, as.integer(diff(above$date)) > 1L))
  per  <- tibble(q = above$daily_q_cfs, span) %>%
    group_by(span) %>% summarise(peak = max(q), .groups = "drop")
  tibble(sum_peak_excess = sum(per$peak - threshold))
}

peak_tbl <- distinct(panel, year_t1, year_t2) %>%
  mutate(sum_peak_excess = pmap_dbl(list(year_t1, year_t2),
                                    ~ peak_metric_one(..1, ..2)$sum_peak_excess),
         sum_peak_excess_k = sum_peak_excess / 1000)

panel2 <- panel %>%
  left_join(select(peak_tbl, year_t1, year_t2, sum_peak_excess_k),
            by = c("year_t1", "year_t2")) %>%
  mutate(q_peak_k = q_peak_daily_cfs / 1000)


# ---- (1) Per-interval metric table ------------------------------------------
tab <- panel2 %>%
  group_by(interval, interval_years) %>%
  summarise(cum_excess_k      = first(cum_excess_k),
            sum_peak_k        = first(sum_peak_excess_k),
            mean_new_area_ft  = round(mean(new_area_per_ft), 1),
            .groups = "drop") %>%
  mutate(crest_frac = round(sum_peak_k / cum_excess_k, 2)) %>%   # low = duration-inflated
  arrange(desc(cum_excess_k))
cat("=== Per-interval: cum_excess vs sum-of-peaks (crest_frac = sum_peak / cum_excess) ===\n")
as.data.frame(tab) %>% print(row.names = FALSE)


# ---- (2) Bake-off, full vs 2017-2020 dropped --------------------------------
bakeoff <- function(d, tag) {
  d <- droplevels(d)
  base    <- lmer(new_area_per_ft ~ interval_years +
                    (1 | river_segment) + (1 | interval), d, REML = FALSE)
  fits <- list(`cum_excess` = "cum_excess_k",
               `max_peak`   = "q_peak_k",
               `sum_peaks`  = "sum_peak_excess_k")
  cum_aic <- AIC(update(base, . ~ . + cum_excess_k))
  purrr::imap_dfr(fits, function(term, nm) {
    m  <- update(base, reformulate(c(".", term), response = "."))
    co <- summary(m)$coefficients
    tibble(dataset = tag, metric = nm,
           forcing_t = round(co[term, "t value"], 2),
           iv_t      = round(co["interval_years", "t value"], 2),
           AIC       = round(AIC(m), 1),
           AIC_vs_cum = round(AIC(m) - cum_aic, 1),          # <0 = beats cum_excess
           LRT_p     = signif(anova(base, m)[2, "Pr(>Chisq)"], 2))
  })
}

full <- bakeoff(panel2, "full (n=139)")
drop <- bakeoff(filter(panel2, interval != "2017-2020"), "drop 2017-2020")

cat("\n=== Metric bake-off: full vs 2017-2020 dropped ===\n")
cat("(AIC_vs_cum < 0 means the metric beats cum_excess within that dataset)\n\n")
bind_rows(full, drop) %>% as.data.frame() %>% print(row.names = FALSE)

# Read: if sum_peaks keeps AIC_vs_cum clearly negative with 2017-2020 gone, the
# crest-driven signal is real (not that one flood). If AIC_vs_cum collapses to
# ~0, the edge was leverage from de-weighting a single interval -> keep cum_excess.
