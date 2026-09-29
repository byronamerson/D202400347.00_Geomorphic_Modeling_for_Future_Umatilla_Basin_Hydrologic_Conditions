# =============================================================================
# 11c_future_forcing_era_k_dynamical.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 11c: future forcing by period for the DYNAMICAL track, from the era-K
#            bias-corrected product set.
# =============================================================================
#
# Purpose: the dynamical counterpart of 11b. Twelve members (3 GCMs x 4 hydrology
#   configs, RCP8.5 only), corrected by 10c under ERAS_DYNAMICAL.
#
# Reporting periods differ from the statistical track by design (PERIODS_DYNAMICAL
#   in 11): 2011-2030 and 2031-2050, the same two 20-year blocks this track uses
#   for K. The record runs 2011-01-01 -> 2050-11-30, so the statistical table's
#   30-year normals do not fit it -- 2070-2099 would be empty and 2040-2069 would
#   hold 11 years. Under G6 this track owes the statistical one no comparability;
#   the side-by-side of the two forward models is itself the finding.
#
# Two properties of this record, both expected:
#   - WY2011 is Jan-Sep 2011 only (the record starts 2011-01-01), so it is dropped
#     as a partial year and the 2011-2030 period runs on 19 realized years against
#     a nominal t_norm of 20. Both numbers are carried in the summary.
#   - WY2051 is Oct-Nov 2050 only; it is dropped as partial and in any case falls
#     outside both periods.
#
# Inputs:
#   - scripts/11_future_forcing_by_period.R (the chain; 11 runs nothing on source)
#   - data/Umatilla_Future_Flows_BC/_bc-k-by-era-dynamical_manifest.csv
#   - data/Umatilla_Future_Flows_BC/<member_id>-BC-K-by-era.csv    (12 members)
#   - data/pendleton_daily_extended.rds                            (observed anchor)
#
# NB the member CSVs carry the SAME product tag as the statistical track -- both
#   tracks are one product set, written by two runs. It is the MANIFEST that
#   selects the track, which is why 10c wrote its own sidecar.
#
# Outputs:
#   - data/future_forcing_annual_bc-k-by-era-dynamical.csv
#   - data/future_forcing_period_summary_bc-k-by-era-dynamical.csv
# =============================================================================

source("scripts/11_future_forcing_by_period.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

PRODUCT_TAG <- "BC-K-by-era"
MANIFEST    <- file.path(BC_DIR, "_bc-k-by-era-dynamical_manifest.csv")
OUT_ANNUAL  <- "data/future_forcing_annual_bc-k-by-era-dynamical.csv"
OUT_SUMMARY <- "data/future_forcing_period_summary_bc-k-by-era-dynamical.csv"


# =============================================================================
# 2. RUN
# =============================================================================

out <- run_future_forcing(
  manifest_path = MANIFEST,
  tag           = PRODUCT_TAG,
  periods       = PERIODS_DYNAMICAL,
  out_annual    = OUT_ANNUAL,
  out_summary   = OUT_SUMMARY
)


# =============================================================================
# 3. WHAT THE RUN PRODUCED  (describe; do not conclude)
# =============================================================================

# Coverage: realized years per period against the table's nominal t_norm.
# 2011-2030 is expected at 19 of 20; 2031-2050 at 20 of 20.
out$summary %>%
  filter(source == "future") %>%
  summarise(members = n_distinct(member_id),
            n_years_min = min(n_years), n_years_max = max(n_years),
            .by = c(period, t_norm)) %>%
  arrange(period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# Mean annual cum_excess by GCM x period (cfs-days/yr). Split by GCM rather than
# scenario: this track is RCP8.5 only, so scenario carries no contrast here, and
# GCM is where the K spread clustered on 09-29.
out$summary %>%
  filter(source == "future") %>%
  summarise(members     = n_distinct(member_id),
            mean_annual = round(mean(mean_annual_cum_excess)),
            mean_yr_max = round(mean(max_annual_cum_excess)),
            .by = c(gcm, period)) %>%
  arrange(gcm, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# The observed anchor -- identical to 11b's by construction (same record, same
# pipeline). Printed so the two runs can be checked against each other.
out$summary %>%
  filter(source == "observed") %>%
  transmute(period, n_years, mean_annual_cum_excess = round(mean_annual_cum_excess)) %>%
  as.data.frame() %>% print(row.names = FALSE)
