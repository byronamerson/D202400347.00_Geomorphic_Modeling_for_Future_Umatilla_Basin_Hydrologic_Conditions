# =============================================================================
# [DEPRECATED 2026-09-04] One-off diagnostic; finding captured, not in pipeline.
# -----------------------------------------------------------------------------
# Answered one question: is cum_excess an EXTREME or a CUMULATIVE forcing?
# Finding (see claude/NOTE_simple_forcing_model.md): cum_excess beats and largely
# ABSORBS interval-max peak (unique beyond-peak R^2 ~ 0.18) and its edge tracks
# flow CHARACTER (sustained vs flashy), NOT interval length. That is why the
# Phase-5 model (scripts/05_simple_forcing_model.R) uses cum_excess. This script
# uses the retired annualized/Delta-t^2 frame and is not part of the forward
# pipeline -- kept for reference only.
# =============================================================================

# =============================================================================
# 04f_forcing_regime_diagnostic.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 4f: Is cum_excess an EXTREME or a CUMULATIVE forcing? (regime diagnostic)
# =============================================================================
#
# Question (from the long-vs-short interval discussion):
#   Does cum_excess's edge over interval-max peak come from SHORT intervals
#   (where peak and cum_excess nearly coincide -> cum_excess is just tracking the
#   single big flood = EXTREME regime) or from LONG intervals (where they
#   diverge -> cum_excess carries accumulation info beyond the peak = CUMULATIVE
#   regime)?
#
# Strategy: decompose cum_excess into
#     (a) the part explained by peak          (peak-tracking)
#     (b) the residual, "beyond-peak" part    (accumulation from extra / moderate
#                                              events -- large in long, multi-event
#                                              intervals)
#   then ask (1) whether the beyond-peak part predicts channel change at all, and
#   (2) whether the peak/cum_excess divergence is concentrated in long intervals.
#
# Frame: validated (all 14 intervals, Delta-t^2 weights) -- matches 04d/04e.
# Response: net area change rate (the strongest-signal response). Swap RESPONSE_COL
# to re-run for new_area etc.
# =============================================================================

library(dplyr)
library(tidyr)
library(ggplot2)
library(broom)

RESPONSE_COL <- "net_area_change_ft2_per_year"
PEAK_COL     <- "q_peak_max_cfs"                 # interval-max annual peak (04d's peak)
CUM_COL      <- "cum_excess_thresh_cfs_days"
LONG_YRS     <- 3                                # project convention: >= 3 yr = adequate


# ---- 0. Assemble the validated modeling table --------------------------------
source("scripts/rs30_interval_sandbox.R")
rs30_grid_intervals <- distinct(rs30_plot_data, year_t1, year_t2)
source("scripts/04c_interval_forcing_metrics.R")
rs30_forcing_metrics <- run_interval_forcing_metrics(config, rs30_grid_intervals)

dx <- rs30_plot_data %>%
  left_join(rs30_forcing_metrics, by = c("year_t1", "year_t2")) %>%
  mutate(
    interval_weight = interval_years^2,
    resp   = .data[[RESPONSE_COL]],
    peak   = .data[[PEAK_COL]],
    cum    = .data[[CUM_COL]],
    z_peak = as.numeric(scale(peak)),
    z_cum  = as.numeric(scale(cum)),
    divergence   = z_cum - z_peak,
    length_class = if_else(interval_years >= LONG_YRS,
                           "long (>= 3 yr)", "short (< 3 yr)")
  )


# ---- 1. How coupled are peak and cum_excess, and does it break with length? --
# If peak and cum_excess are tightly correlated, cum_excess can't add much beyond
# the extreme. The divergence z_cum - z_peak is where cum_excess "sees" something
# peak doesn't; if that divergence grows with interval length, the extra info is
# a long-interval phenomenon.
cat("\n--- Coupling ---\n")
cat(sprintf("cor(peak, cum_excess) all intervals       : %.3f\n",
            cor(dx$peak, dx$cum)))
cat(sprintf("cor(peak, cum_excess) long  (>= 3 yr) only : %.3f\n",
            with(subset(dx, interval_years >= LONG_YRS), cor(peak, cum))))
cat(sprintf("cor(peak, cum_excess) short (<  3 yr) only : %.3f\n",
            with(subset(dx, interval_years <  LONG_YRS), cor(peak, cum))))
cat(sprintf("cor(divergence, interval_years)           : %.3f  (>0 => cum_excess exceeds peak in LONG intervals)\n",
            cor(dx$divergence, dx$interval_years)))


# ---- 2. Per-interval divergence table (sorted by length) ---------------------
# Eyeball WHERE peak and cum_excess part ways. Big positive divergence in the
# long rows = accumulation the single peak misses.
regime_table <- dx %>%
  arrange(desc(interval_years)) %>%
  transmute(
    interval_label,
    yrs = interval_years,
    n_events = n_events_thresh,
    peak = round(peak),
    cum_excess = round(cum),
    z_peak = round(z_peak, 2),
    z_cum  = round(z_cum, 2),
    divergence = round(divergence, 2),
    net_area_yr = round(resp)
  )
cat("\n--- Per-interval divergence (sorted long -> short) ---\n")
print(regime_table, n = Inf)


# ---- 3. Does cum_excess add over peak? (incremental R^2, weighted) -----------
m_peak <- lm(resp ~ peak,           data = dx, weights = interval_weight)
m_cum  <- lm(resp ~ cum,            data = dx, weights = interval_weight)
m_both <- lm(resp ~ z_peak + z_cum, data = dx, weights = interval_weight)

r2 <- function(m) summary(m)$r.squared
cat("\n--- Incremental value (weighted, n = 14) ---\n")
cat(sprintf("R^2  peak only              : %.3f\n", r2(m_peak)))
cat(sprintf("R^2  cum_excess only        : %.3f\n", r2(m_cum)))
cat(sprintf("R^2  peak + cum_excess      : %.3f\n", r2(m_both)))
cat(sprintf("  delta R^2 from adding cum_excess to peak : %+.3f\n", r2(m_both) - r2(m_peak)))
cat(sprintf("  delta R^2 from adding peak to cum_excess : %+.3f\n", r2(m_both) - r2(m_cum)))
cat("\nJoint model (standardized predictors -- compare |coef|; larger = more independent pull):\n")
print(broom::tidy(m_both))


# ---- 4. The decisive test: does the BEYOND-PEAK part of cum_excess predict? --
# resid_cum = the part of cum_excess NOT explained by peak (accumulation beyond
# the single big flood). If it predicts net area, cum_excess is genuinely
# cumulative; if not, cum_excess only helps by tracking peak (extreme regime).
# NOTE: residualize with the SAME Delta-t^2 weights as the fit, so this R^2 is the
# weighted semi-partial and should reconcile with the +0.176 delta-R^2 in Sec 3.
# (The earlier version residualized UNWEIGHTED, which broke that identity.)
dx <- dx %>%
  mutate(resid_cum = resid(lm(cum ~ peak, data = dx, weights = interval_weight)))

m_resid <- lm(resp ~ resid_cum, data = dx, weights = interval_weight)
cat("\n--- Beyond-peak accumulation vs response (weighted-consistent) ---\n")
cat(sprintf("R^2  net_area ~ (cum_excess beyond peak)  : %.3f,  p = %.3f\n",
            r2(m_resid), glance(m_resid)$p.value))
cat(sprintf("  (should reconcile with delta-R^2 = +0.176 from Sec 3)\n"))
cat(sprintf("weighted cor(beyond-peak accumulation, years) : %.3f  (>0 => beyond-peak accumulation lives in LONG intervals)\n",
            cov.wt(cbind(dx$resid_cum, dx$interval_years), wt = dx$interval_weight, cor = TRUE)$cor[1, 2]))


# ---- 5. Stratified restatement: which predictor wins in each length class ----
# Explicit split (avoids lm-inside-summarise data-masking issues). Low n per
# class -- read as a coarse cross-check of the continuous measures above.
strat <- bind_rows(lapply(split(dx, dx$length_class), function(d) {
  tibble(
    length_class = d$length_class[[1]],
    n            = nrow(d),
    r2_peak      = summary(lm(resp ~ peak, data = d, weights = interval_weight))$r.squared,
    r2_cum       = summary(lm(resp ~ cum,  data = d, weights = interval_weight))$r.squared
  )
}))
cat("\n--- Stratified R^2 (net_area ~ each forcing, within length class) ---\n")
print(strat)


# ---- 6. Visual: cum_excess vs peak, sized by interval length -----------------
# Tight diagonal cloud = coupled (extreme regime). Long-interval points lifting
# ABOVE the cloud = cum_excess seeing accumulation the peak misses.
p_regime <- ggplot(dx, aes(peak, cum)) +
  geom_smooth(method = "lm", se = FALSE, formula = y ~ x,
              color = "grey70", linewidth = 0.7) +
  geom_point(aes(size = interval_years, color = length_class)) +
  { if (requireNamespace("ggrepel", quietly = TRUE))
      ggrepel::geom_text_repel(aes(label = interval_label), size = 3, seed = 1,
                               min.segment.length = 0)
    else geom_text(aes(label = interval_label), size = 3, vjust = -0.7) } +
  scale_color_manual(values = c("long (>= 3 yr)" = "#d95f0e",
                                "short (< 3 yr)" = "#2c7fb8")) +
  scale_size_continuous(range = c(2, 7)) +
  labs(
    x = "Interval-max annual peak (cfs)",
    y = "Cumulative excess > Q2 (cfs-days)",
    size = "Interval (yr)", color = NULL,
    title = "Peak vs cumulative excess -- do they decouple in long intervals?",
    subtitle = "Points above the line: cum_excess sees accumulation the single peak misses"
  ) +
  theme_minimal(base_size = 12)
print(p_regime)
