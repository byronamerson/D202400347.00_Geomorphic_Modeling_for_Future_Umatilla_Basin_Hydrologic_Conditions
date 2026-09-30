# =============================================================================
# 12b_migration_projection_era_k.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 12b: migration projection for the STATISTICAL track (BCSD + MACA), from
#            the era-K forcing table.
# =============================================================================
#
# Purpose: apply the frozen forward model to the 160 statistical members' forcing
#   as rebuilt by 11b on the era-K corrected flows.
#
# Blocks: the bias-correction eras (2006-2035 / 2036-2065 / 2066-2099) from
#   scripts/eras.R, NOT the 30-year climate normals this runner used before
#   2026-09-29. The blocks are therefore 30/30/34 years and the Observed point's
#   divisor is stated as OBS_WINDOW_YEARS_STATISTICAL rather than read off the
#   table. Block length does not enter the plotted rate; it does divide the
#   model-error whisker.
#
# Inputs:
#   - scripts/12_migration_projection.R (the chain; 12 runs nothing on source)
#   - data/future_forcing_annual_bc-k-by-era.csv      (from 11b)
#   - data/forcing_model_coefficients_cum_excess.csv  (frozen model of record)
#   - data/forcing_model_cum_excess.rds               (same model, live, for the PI)
#
# Outputs: data/migration_*_bc-k-by-era.csv, plots/migration_*_bc-k-by-era.png
# =============================================================================

source("scripts/12_migration_projection.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

ANNUAL_CSV  <- "data/future_forcing_annual_bc-k-by-era.csv"
SUFFIX      <- "bc-k-by-era"
TRACK_LABEL <- "statistical"


# =============================================================================
# 2. RUN
# =============================================================================

out <- run_migration_projection(
  annual_csv       = ANNUAL_CSV,
  normals          = as_period_table(ERAS_STATISTICAL),
  obs_window_years = OBS_WINDOW_YEARS_STATISTICAL,
  suffix           = SUFFIX,
  track_label      = TRACK_LABEL
)


# =============================================================================
# 3. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

cat(sprintf("\nF_hist = %s cfs-days/yr; Observed point annualized over %d yr\n",
            format(round(out$f_hist), big.mark = ","),
            OBS_WINDOW_YEARS_STATISTICAL))

# Per-reach historical anchor rate (ft/yr) -- the floor the future rates climb from.
out$reach_hist %>%
  mutate(hist_rate_ft_yr = round(hist_rate_ft_yr, 2)) %>%
  arrange(river_segment) %>%
  as.data.frame() %>% print(row.names = FALSE)

# Change vs historical: ensemble median [p10, p90] per reach x scenario x period.
out$delta_band %>%
  mutate(across(c(median, p10, p90), ~ round(.x, 2))) %>%
  arrange(river_segment, scenario, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# 80% model-error half-width (ft/yr), spread across reaches within each block.
# interval_years is the divisor: a longer block divides the same interval-scale
# prediction error by more years, so 2066-2099 reads narrower for that reason
# alone. Full table at out$whiskers and on disk.
cat("\n80% model-error half-width (ft/yr), across reaches:\n")
out$whiskers %>%
  group_by(period, interval_years) %>%
  summarise(reaches = n_distinct(river_segment),
            min     = round(min(whisker_half), 2),
            median  = round(median(whisker_half), 2),
            max     = round(max(whisker_half), 2),
            .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)
