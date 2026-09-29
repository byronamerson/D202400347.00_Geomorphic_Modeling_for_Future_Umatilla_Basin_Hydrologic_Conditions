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
# Periods: the three 30-year climate normals, unchanged. t_norm = 30 throughout,
#   so this run reproduces the pre-era-K construction exactly except for the
#   corrected flows underneath it -- which is what makes the two product sets
#   comparable.
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
  annual_csv  = ANNUAL_CSV,
  normals     = NORMALS_STATISTICAL,
  suffix      = SUFFIX,
  track_label = TRACK_LABEL
)


# =============================================================================
# 3. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

cat(sprintf("\nF_hist = %s cfs-days/yr; t_norm = %d yr\n",
            format(round(out$f_hist), big.mark = ","),
            anchor_t_norm(NORMALS_STATISTICAL)))

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
