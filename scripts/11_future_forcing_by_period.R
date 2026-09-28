# =============================================================================
# 11_future_forcing_by_period.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 11 (projection Step 2): future forcing by century period.
# =============================================================================
#
# Reduce the bias-corrected future flows to per-water-year cum_excess > 0.75xQ2,
# tagged by century period and member factors -- the forcing primitive the
# migration projection (Step 3) consumes. Carries the observed record on the SAME
# footing (one uniform per-year cum_excess pipeline) so future, observed, and
# corrected-historical can be laid side by side for gut-checking (Byron: baseline
# is moot, view them together).
#
# PER-YEAR, not period-total, is the deliberate primitive: from per-year cum_excess
# we can form EITHER a period total OR a mean-annual rate at Step 3, so this step
# does NOT pre-commit the rate construction (still open -- the per-interval intercept
# + interval-scale-forcing question).
#
# Periods (confirmed 2026-09-07): a near-term decade + two climate-normal windows.
# Config-driven (PERIODS tibble) -- change the table, nothing else.
#
# Reuse: 04c add_water_year + compute_all_interval_forcing at the config threshold;
#   the _bc_manifest.csv factor grid from 10. (add_water_year / annual helpers are
#   duplicated from x15 pending the deferred R/ module -- NOTE_shared_module_refactor.)
# Inputs : data/Umatilla_Future_Flows_BC/<member>-BC.csv + _bc_manifest.csv (from 10)
#          data/pendleton_daily_extended.rds (observed, via 04c config)
# Outputs: data/future_forcing_annual_by_period.csv  (per member x water-year)
#          data/future_forcing_period_summary.csv    (per member x period)
# Style  : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(readr)
library(purrr)
library(tidyr)

source("scripts/04c_interval_forcing_metrics.R")   # add_water_year, compute_all_interval_forcing, cfg, cfg_num


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

THRESHOLD   <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")   # 0.75xQ2 = 4156 cfs
BC_DIR      <- "data/Umatilla_Future_Flows_BC"
MANIFEST    <- file.path(BC_DIR, "_bc_manifest.csv")
OUT_ANNUAL  <- "data/future_forcing_annual_by_period.csv"
OUT_SUMMARY <- "data/future_forcing_period_summary.csv"

# Century periods: near-term decade (skips the partial 2020s) + two 30-yr normals.
PERIODS <- tribble(
  ~period,       ~y1,    ~y2,
  "2030s",       2030L,  2039L,
  "2040-2069",   2040L,  2069L,
  "2070-2099",   2070L,  2099L
)


# =============================================================================
# 2. FORCING PRIMITIVE -- per-water-year cum_excess for one daily series
# =============================================================================

annual_intervals <- function(daily) {
  #' Each water year as its own one-year forcing window (year_t1 = wy-1, year_t2 = wy),
  #' matching compute_all_interval_forcing's (t1, t2] convention.
  wy <- sort(unique(add_water_year(daily)$water_year))
  tibble(year_t1 = wy - 1L, year_t2 = wy)
}

annual_cum_excess <- function(daily) {
  #' Per-water-year cum_excess above THRESHOLD for a daily series.
  #' @param daily tibble(date, daily_q_cfs, is_estimated)
  #' @return tibble(water_year, cum_excess)
  compute_all_interval_forcing(daily, annual_intervals(daily), THRESHOLD) %>%
    transmute(water_year = year_t2, cum_excess = cum_excess_thresh_cfs_days)
}

read_bc_member <- function(path) {
  #' One bias-corrected future member as a forcing-ready daily series (corrected
  #' modeled flow, not reconstruction -> is_estimated = FALSE).
  read_csv(path, show_col_types = FALSE) %>%
    transmute(date = as.Date(date), daily_q_cfs = q_corrected, is_estimated = FALSE)
}


# =============================================================================
# 3. PERIOD TAGGING  (config-driven; NA outside any period)
# =============================================================================

tag_period <- function(annual) {
  #' Attach the period label from PERIODS via a non-equi join. Water years outside
  #' every period get period = NA (kept in the annual file, dropped from summaries).
  annual %>%
    left_join(PERIODS, by = join_by(between(water_year, y1, y2))) %>%
    select(-y1, -y2)
}


# =============================================================================
# 4. BUILD: future members (per year) + observed on the same footing
# =============================================================================

# Future members: the corrected CSVs with a valid file, joined to their factor grid.
manifest <- read_csv(MANIFEST, show_col_types = FALSE) %>%
  mutate(bc_path = file.path(BC_DIR, sprintf("%s-BC.csv", member_id))) %>%
  filter(file.exists(bc_path))

message(sprintf("Computing annual cum_excess for %d future members ...", nrow(manifest)))

future_annual <- manifest %>%
  transmute(member_id, gcm, scenario, downscaling, hydro, bc_path) %>%
  mutate(annual = map(bc_path, ~ annual_cum_excess(read_bc_member(.x)))) %>%
  select(-bc_path) %>%
  unnest(annual) %>%
  mutate(source = "future") %>%
  tag_period()

# Observed record: same per-year pipeline, tagged "historical" (its own baseline row).
observed_annual <- readRDS(cfg("extended_record_rds")) %>%
  annual_cum_excess() %>%
  mutate(member_id = "observed", gcm = NA_character_, scenario = "observed",
         downscaling = NA_character_, hydro = NA_character_,
         source = "observed", period = "historical")

annual_all <- bind_rows(future_annual, observed_annual)


# =============================================================================
# 5. PERIOD SUMMARY  (per member x period -- the Step 3 rate primitive)
# =============================================================================

period_summary <- annual_all %>%
  filter(!is.na(period)) %>%
  group_by(source, member_id, gcm, scenario, downscaling, hydro, period) %>%
  summarise(n_years                = dplyr::n(),
            mean_annual_cum_excess = mean(cum_excess),
            total_cum_excess       = sum(cum_excess),
            max_annual_cum_excess  = max(cum_excess),
            .groups = "drop")


# =============================================================================
# 6. WRITE + HEADLINE
# =============================================================================

write_csv(annual_all,     OUT_ANNUAL)
write_csv(period_summary, OUT_SUMMARY)
message("Wrote ", OUT_ANNUAL, " (", nrow(annual_all), " rows) and ",
        OUT_SUMMARY, " (", nrow(period_summary), " rows)")

cat("\n=== Ensemble mean annual cum_excess > 0.75xQ2 by scenario x period (cfs-days) ===\n")
cat("    (mean across members of each member's period-mean annual cum_excess)\n")
period_summary %>%
  group_by(scenario, period) %>%
  summarise(members       = n_distinct(member_id),
            mean_annual   = round(mean(mean_annual_cum_excess)),
            mean_yr_max   = round(mean(max_annual_cum_excess)),   # avg of members' period-max year
            .groups = "drop") %>%
  arrange(scenario, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\nObserved historical mean annual cum_excess: %s cfs-days\n",
            format(round(period_summary$mean_annual_cum_excess[period_summary$source == "observed"]),
                   big.mark = ",")))
