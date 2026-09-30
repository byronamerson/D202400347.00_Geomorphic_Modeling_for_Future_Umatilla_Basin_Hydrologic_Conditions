# =============================================================================
# 11b_future_forcing_era_k.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 11b: future forcing by period for the STATISTICAL track (BCSD + MACA),
#            from the era-K bias-corrected product set.
# =============================================================================
#
# Purpose: rebuild Step 2's forcing tables on the product set that 10b wrote
#   (K computed and applied per era), for the 160 statistical members only.
#
# Why a separate script per track (G6): the two tracks are separate analytical
#   tracks with different reporting periods and different member sets, and their
#   outputs are never pooled into one ensemble summary. Keeping them in two files
#   makes that separation visible in the file tree, and keeps one track's outputs
#   from overwriting the other's.
#
# What is NOT changed here: the forcing metric (cum_excess > 0.75xQ2), the
#   per-water-year primitive, and the observed anchor. The only difference from
#   the 09-08 run is which corrected flows are read.
#
# Inputs:
#   - scripts/11_future_forcing_by_period.R (the chain; 11 runs nothing on source)
#   - data/Umatilla_Future_Flows_BC/_bc-k-by-era_manifest.csv
#   - data/Umatilla_Future_Flows_BC/<member_id>-BC-K-by-era.csv   (160 members)
#   - data/pendleton_daily_extended.rds                           (observed anchor)
#
# Outputs (alongside the pre-era-K files, not replacing them):
#   - data/future_forcing_annual_bc-k-by-era.csv
#   - data/future_forcing_period_summary_bc-k-by-era.csv
# =============================================================================

source("scripts/11_future_forcing_by_period.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

PRODUCT_TAG   <- "BC-K-by-era"
MANIFEST      <- file.path(BC_DIR, "_bc-k-by-era_manifest.csv")
OUT_ANNUAL    <- "data/future_forcing_annual_bc-k-by-era.csv"
OUT_SUMMARY   <- "data/future_forcing_period_summary_bc-k-by-era.csv"


# =============================================================================
# 2. RUN
# =============================================================================

out <- run_future_forcing(
  manifest_path = MANIFEST,
  tag           = PRODUCT_TAG,
  periods       = as_period_table(ERAS_STATISTICAL),
  out_annual    = OUT_ANNUAL,
  out_summary   = OUT_SUMMARY
)


# =============================================================================
# 3. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

# Coverage: members and realized years per period, against the table's nominal
# t_norm. A period short of its nominal length means a dropped partial year.
out$summary %>%
  filter(source == "future") %>%
  summarise(members = n_distinct(member_id),
            n_years_min = min(n_years), n_years_max = max(n_years),
            .by = c(period, t_norm)) %>%
  arrange(period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# Ensemble mean annual cum_excess by scenario x period (cfs-days/yr): the mean
# across members of each member's period-mean annual value.
out$summary %>%
  filter(source == "future") %>%
  summarise(members     = n_distinct(member_id),
            mean_annual = round(mean(mean_annual_cum_excess)),
            mean_yr_max = round(mean(max_annual_cum_excess)),
            .by = c(scenario, period)) %>%
  arrange(scenario, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# The observed anchor, on the same footing.
out$summary %>%
  filter(source == "observed") %>%
  transmute(period, n_years, mean_annual_cum_excess = round(mean_annual_cum_excess)) %>%
  as.data.frame() %>% print(row.names = FALSE)
