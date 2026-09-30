# =============================================================================
# 12c_migration_projection_era_k_dynamical.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 12c: migration projection for the DYNAMICAL track, from the era-K
#            forcing table.
# =============================================================================
#
# Purpose: the dynamical counterpart of 12b. Twelve members, RCP8.5 only, over the
#   two 20-year periods this track uses throughout (2011-2030, 2031-2050).
#
# Two consequences of the shorter period, both accepted 2026-09-29:
#   - t_norm = 20, so the per-interval reach intercept is annualized over 20 years
#     rather than 30. The absolute-rate floor is therefore HIGHER than on the
#     statistical track -- at RS30, 3.15 ft/yr against 2.56. The observed anchor is
#     a modeled point, so it rises by the same amount. Internally consistent; the
#     two tracks' absolute-rate figures are NOT comparable by eye. The delta
#     figures are, since the floor cancels there.
#   - 2011-2030 runs on 19 realized water years against a nominal 20 (WY2011 is
#     Jan-Sep only). t_norm takes the nominal value from the table; the cost at
#     RS30 is 0.09 ft/yr.
#
# The figures carry one RCP lane, not two. That is the track, not a defect.
#
# Inputs:
#   - scripts/12_migration_projection.R (the chain; 12 runs nothing on source)
#   - data/future_forcing_annual_bc-k-by-era-dynamical.csv   (from 11c)
#   - data/forcing_model_coefficients_cum_excess.csv         (frozen model of record)
#   - data/forcing_model_cum_excess.rds                      (same model, live)
#
# NB the forward model itself is UNCHANGED between tracks -- same frozen
#   coefficients, same observed anchor. What differs is the forcing and the period
#   table. Under G6 the side-by-side of the two is the finding.
#
# Outputs: data/migration_*_bc-k-by-era-dynamical.csv,
#          plots/migration_*_bc-k-by-era-dynamical.png
# =============================================================================

source("scripts/12_migration_projection.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

ANNUAL_CSV  <- "data/future_forcing_annual_bc-k-by-era-dynamical.csv"
SUFFIX      <- "bc-k-by-era-dynamical"
TRACK_LABEL <- "dynamical"


# =============================================================================
# 2. RUN
# =============================================================================

out <- run_migration_projection(
  annual_csv       = ANNUAL_CSV,
  normals          = as_period_table(ERAS_DYNAMICAL),
  obs_window_years = OBS_WINDOW_YEARS_DYNAMICAL,
  suffix           = SUFFIX,
  track_label      = TRACK_LABEL
)


# =============================================================================
# 3. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

cat(sprintf("\nF_hist = %s cfs-days/yr; Observed point annualized over %d yr\n",
            format(round(out$f_hist), big.mark = ","),
            OBS_WINDOW_YEARS_DYNAMICAL))

# Per-reach historical anchor rate (ft/yr) at THIS track's t_norm. Read against
# 12b's table: the difference is the intercept annualized over 20 rather than 30.
out$reach_hist %>%
  mutate(hist_rate_ft_yr = round(hist_rate_ft_yr, 2)) %>%
  arrange(river_segment) %>%
  as.data.frame() %>% print(row.names = FALSE)

# Change vs historical: ensemble median [p10, p90] per reach x period.
out$delta_band %>%
  mutate(across(c(median, p10, p90), ~ round(.x, 2))) %>%
  arrange(river_segment, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# 80% model-error half-width (ft/yr), spread across reaches within each block.
# interval_years is the divisor. These bars run wider than 12b's: the half-width
# is dominated by the interval random effect and the residual, neither of which
# shrinks with a shorter window, while the divisor does. Full table on disk.
cat("\n80% model-error half-width (ft/yr), across reaches:\n")
out$whiskers %>%
  group_by(period, interval_years) %>%
  summarise(reaches = n_distinct(river_segment),
            min     = round(min(whisker_half), 2),
            median  = round(median(whisker_half), 2),
            max     = round(max(whisker_half), 2),
            .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)
