# =============================================================================
# x06_maintenance_band_covariation.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY: is the channel-maintenance band worth a flow-extension redo?
# =============================================================================
#
# The cheap check (before paying for a lower-floor daily extension).
#
# Question: does a "channel-maintenance" flow band (0.5*Q2 -> Q2) carry signal
#   that is DISTINCT from the flood band (> Q2), or are the two just collinear
#   (wet years have more of both)?
#     - Collinear  -> a 2nd fixed effect can't separate; lowering the cum_excess
#                     floor only rescales the predictor we already have. Skip the
#                     extension redo.
#     - Divergent  -> wet-but-not-flooding stretches light up the maintenance
#                     band while the flood band stays quiet. That's exactly the
#                     interval-level variance the hypothesis is about. Worth it.
#
# Why this is honest with the CURRENT data: it uses ONLY the OBSERVED Pendleton
#   daily record (WY1996-2025, complete daily, 0 gaps). The 0.5*Q2 band sits
#   below bankfull, where the reconstructed pre-1996 record is NOT supported --
#   but the observed gage record IS. So we measure the intrinsic co-variation of
#   the two bands on real sub-bankfull data. If they are collinear here, they are
#   collinear everywhere.
#
# Scale caveat: the migration model's interval RE lives at the DOGAMI photo
#   interval scale. We only have ~2-3 complete intervals post-1996 -- too few to
#   fit anything. Water year (n ~ 30) is the finest scale with enough points to
#   SEE the band relationship, and is a fair proxy for whether the bands are
#   intrinsically redundant. Interval-scale confirmation is downstream.
#
# Band partition (non-overlapping, by construction):
#   flood_cfsd = sum( max(0, q - Q2) )                 # excess above Q2
#   maint_cfsd = sum( max(0, min(q, Q2) - lower) )     # excess in [lower, Q2)
#   lower      = maint_lower_frac * Q2                 # 0.5*Q2 = 2,771 cfs
#   => flood + maint == sum( max(0, q - lower) )       # the lowered-floor
#      predictor is literally flood + maint (asserted below). So the two-predictor
#      model is the general case; lowering the floor is its equal-slope special
#      case.
#
# Input:  data/dv_gage_daily_flows.csv  (04a; observed daily, all 3 gages)
# Leaves in the global env: band_wy (per-WY tibble), band_cor, band_diverge
# Plot:   plots/x06_band_covariation.png
#
# Style: lingua.md + Tidyverse & Functional Programming Guidelines (small pure
#   functions, config tribble, I/O at the boundary). Self-running on source().
# =============================================================================

library(tidyverse)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

config <- tribble(
  ~parameter,          ~value,
  "q2_cfs",            "5542",                       # Pendleton Q2 (B17C, post-McKay)
  "maint_lower_frac",  "0.5",                        # maintenance-band floor = frac x Q2
  "pendleton_gage_id", "14020850",                   # observed daily target gage
  "daily_flows_csv",   "data/dv_gage_daily_flows.csv",
  "wy_first",          "1996",                       # first complete observed WY
  "wy_last",           "2025",                       # last full WY (2026 ends 09-02)
  "min_days_complete", "350",                        # WY completeness guard
  "plot_png",          "plots/x06_band_covariation.png"
)

cfg     <- function(p) config %>% filter(parameter == p) %>% pull(value)
cfg_num <- function(p) as.numeric(cfg(p))


# =============================================================================
# 2. HELPERS (pure)
# =============================================================================

add_water_year <- function(daily, date_col = "date") {
  #' Attach USGS water year (Oct 1 (T-1) .. Sep 30 (T)); matches 04c exactly.
  d <- daily[[date_col]]
  mutate(daily,
         water_year = as.integer(format(d, "%Y")) +
           if_else(as.integer(format(d, "%m")) >= 10L, 1L, 0L))
}

band_metrics_by_wy <- function(daily, q2, lower) {
  #' Per-water-year flood-band and maintenance-band forcing (cfs-days).
  #' @param daily tibble(date, daily_q_cfs) -- one gage, observed
  #' @param q2 flood threshold; @param lower maintenance-band floor (< q2)
  #' @return one row per water_year with the two bands + day tallies
  stopifnot(lower < q2)
  daily %>%
    add_water_year() %>%
    group_by(water_year) %>%
    summarise(
      n_days       = dplyr::n(),
      q_peak_cfs   = max(daily_q_cfs),
      flood_cfsd   = sum(pmax(0, daily_q_cfs - q2)),
      maint_cfsd   = sum(pmax(0, pmin(daily_q_cfs, q2) - lower)),
      floor_cfsd   = sum(pmax(0, daily_q_cfs - lower)),   # == flood + maint
      days_flood   = sum(daily_q_cfs >= q2),
      days_maint   = sum(daily_q_cfs >= lower & daily_q_cfs < q2),
      .groups = "drop"
    ) %>%
    mutate(
      flood_k = flood_cfsd / 1000,     # per 1,000 cfs-days (the model's _k units)
      maint_k = maint_cfsd / 1000,
      floor_k = floor_cfsd / 1000
    )
}

band_correlations <- function(band_wy) {
  #' Pearson (linear) and Spearman (rank, robust to skew) between the bands.
  with(band_wy, tibble(
    pearson  = cor(flood_k, maint_k, method = "pearson"),
    spearman = cor(flood_k, maint_k, method = "spearman"),
    n_years  = nrow(band_wy)
  ))
}

flag_divergent <- function(band_wy) {
  #' Surface the years that carry the hypothesis: maintenance flow present while
  #' the flood band is quiet (the predictor-blind years), ranked by how
  #' maintenance-heavy vs flood-light they are.
  band_wy %>%
    mutate(
      maint_share = maint_cfsd / pmax(floor_cfsd, 1),   # share of >lower excess in the band
      flood_blind = flood_cfsd == 0 & maint_cfsd > 0     # no Q2 exceedance at all
    ) %>%
    arrange(desc(maint_share)) %>%
    select(water_year, flood_k, maint_k, days_flood, days_maint,
           maint_share, flood_blind, q_peak_cfs)
}


# =============================================================================
# 3. RUN (self-executes on source)
# =============================================================================

q2    <- cfg_num("q2_cfs")
lower <- cfg_num("maint_lower_frac") * q2

message("x06: Q2 = ", q2, " cfs;  maintenance band = [",
        round(lower), ", ", q2, ") cfs  (", cfg("maint_lower_frac"), " x Q2)")

daily_pendleton <- read_csv(cfg("daily_flows_csv"), show_col_types = FALSE) %>%
  filter(gage_id == cfg("pendleton_gage_id")) %>%
  select(date, daily_q_cfs) %>%
  arrange(date)

band_wy_all <- band_metrics_by_wy(daily_pendleton, q2, lower)

# identity guard: the lowered-floor predictor IS the sum of the two bands
stopifnot(all(abs(band_wy_all$floor_cfsd -
                    (band_wy_all$flood_cfsd + band_wy_all$maint_cfsd)) < 1e-6))

# keep complete water years in the observed window
band_wy <- band_wy_all %>%
  filter(water_year >= cfg_num("wy_first"),
         water_year <= cfg_num("wy_last"),
         n_days     >= cfg_num("min_days_complete"))

band_cor     <- band_correlations(band_wy)
band_diverge <- flag_divergent(band_wy)

# ---- console summary ----
message("\n  Complete water years used: ", nrow(band_wy),
        " (", min(band_wy$water_year), "-", max(band_wy$water_year), ")")
message("  Correlation flood_k vs maint_k:  Pearson ", round(band_cor$pearson, 2),
        " | Spearman ", round(band_cor$spearman, 2))
message("  Water years with ZERO Q2 exceedance but maintenance-band flow: ",
        sum(band_diverge$flood_blind), " of ", nrow(band_wy))
message("  Median maintenance-band share of >0.5*Q2 excess: ",
        round(100 * median(band_diverge$maint_share)), "%")
message("\n  Most maintenance-heavy / flood-light years (top 6):")
print(head(band_diverge, 6))

# ---- plot: are the two bands independent across water years? ----
p_band <- ggplot(band_wy, aes(flood_k, maint_k)) +
  geom_smooth(method = "lm", se = FALSE, colour = "grey70",
              linewidth = 0.5, formula = y ~ x) +
  geom_point(aes(colour = days_flood == 0), size = 2.4) +
  geom_text(aes(label = water_year), size = 2.7, vjust = -0.8,
            check_overlap = TRUE) +
  scale_colour_manual(values = c(`TRUE` = "#c1440e", `FALSE` = "#1f4e79"),
                      labels = c(`TRUE` = "no Q2 exceedance",
                                 `FALSE` = "flood present"),
                      name = NULL) +
  labs(
    title = "Do the flood and channel-maintenance bands carry distinct signal?",
    subtitle = paste0("Observed Pendleton daily, WY", min(band_wy$water_year),
                      "-", max(band_wy$water_year),
                      ".  Points off the trend line = years the current >Q2 ",
                      "predictor misses."),
    x = "Flood band  > Q2   (1,000 cfs-days)",
    y = "Maintenance band  0.5*Q2 -> Q2   (1,000 cfs-days)"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

if (!dir.exists("plots")) dir.create("plots")
ggsave(cfg("plot_png"), p_band, width = 8, height = 6, dpi = 130)
message("\n  Wrote plot: ", cfg("plot_png"))

# =============================================================================
# 4. INTERACTIVE (single-hash = executable; double-hash = narration)
# =============================================================================
##
## After source(), inspect:
#
# band_wy       # per-WY bands (flood_k, maint_k, floor_k, day tallies)
# band_cor      # Pearson + Spearman between the two bands
# band_diverge  # years ranked by maintenance-heavy / flood-light
#
## Sensitivity: try a different band floor without editing the file --
#
# lower2 <- 0.25 * q2
# band_metrics_by_wy(daily_pendleton, q2, lower2) |>
#   dplyr::filter(water_year >= 1996, water_year <= 2025) |>
#   band_correlations()
