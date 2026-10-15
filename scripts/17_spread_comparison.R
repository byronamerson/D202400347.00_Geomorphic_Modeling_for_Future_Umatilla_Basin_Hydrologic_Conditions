# =============================================================================
# 17_spread_comparison.R
# Umatilla River Discharge-Channel Migration Analysis
# How much of the ensemble spread on the calendar-era axis is disagreement
# about TIMING rather than about RESPONSE?
# =============================================================================
#
# THE QUESTION
#
# On the era axis, the members pooled into a period are at different amounts of
# warming, because models reach a given warming level at different dates. The
# p10-p90 band therefore mixes two disagreements: how this river responds to a
# given amount of warming, and when that amount arrives. Pooling the same
# members by warming level removes the second: every member in a 2 degC window
# is at 2 degC by construction. Comparing band width at matched climate states
# bounds how much of the era-axis spread is the timing argument.
#
# WHAT THIS IS NOT
#
# Not a variance decomposition. The pairings below are descriptive comparisons
# of band width at comparable climate states, not a partition of variance among
# scenario, GCM, downscaling method and hydrologic model.
#
# CONSTRAINTS THAT BOUND THE CLAIM (state these wherever the numbers appear)
#
#   - Window length differs: era blocks are 30 years, warming-level windows 20.
#   - Member counts differ by level (e.g. 56 at 4 degC against 80 on the era
#     axis), so the two bands are not estimated from the same sample.
#   - The pairings are approximate. RCP8.5 late century against 4 degC and
#     mid-century against 2 degC are matched on the median rates reported in
#     the memorandum, not on a fitted correspondence.
#
# INPUTS  data/migration_rate_summary_bc-k-by-era.csv
#         data/migration_rate_summary_gwl-bc-k-by-era.csv
#         Both: river_segment, scenario, period, members, median, p10, p90.
#
# OUTPUT  Printed to console only. Nothing is written to disk; this feeds two
#         sentences in Section 3.3 of the technical memorandum.
# =============================================================================

library(dplyr)
library(readr)

ERA_CSV <- "data/migration_rate_summary_bc-k-by-era.csv"
GWL_CSV <- "data/migration_rate_summary_gwl-bc-k-by-era.csv"

# RCP8.5 only: the pairings are defined for the high-emissions pathway, where
# the scenario reaches the upper warming levels at all.
PAIRINGS <- tibble::tribble(
  ~pairing,        ~era_period,  ~gwl_period,
  "mid-century",   "2036-2065",  "2 degC",
  "late century",  "2066-2099",  "4 degC"
)

# --- helpers -----------------------------------------------------------------

add_spread_ratio <- function(summary_tbl) {
  # Purpose: attach the per-row spread measure used throughout this comparison.
  # In:  a rate summary table with p10 and p90 columns (ft/yr).
  # Out: the same table with spread_ratio = p90 / p10, dimensionless.
  # Decision: a RATIO rather than a width in ft/yr, because the rates
  # themselves roughly triple across the century. A width would grow with the
  # mean and say nothing about relative uncertainty.
  mutate(summary_tbl, spread_ratio = p90 / p10)
}

select_scenario_periods <- function(summary_tbl, scenario_id, periods) {
  # Purpose: keep one scenario and an ordered set of periods.
  # In:  rate summary table; scenario label as written in the file ("RCP85");
  #      character vector of period labels to retain.
  # Out: filtered table, one row per reach and period.
  filter(summary_tbl, scenario == scenario_id, period %in% periods)
}

join_matched_states <- function(era_tbl, gwl_tbl, pairings) {
  # Purpose: put each era period beside the warming level it approximately
  #          corresponds to, reach by reach.
  # In:  era and warming-level tables carrying spread_ratio; the pairing table.
  # Out: one row per reach and pairing, with both spread ratios and their
  #      quotient. ratio_of_ratios > 1 means the era band is wider, which is
  #      the signature of timing disagreement inflating the era axis.
  era_tbl |>
    select(river_segment, era_period = period,
           era_median = median, era_spread = spread_ratio) |>
    inner_join(pairings, by = "era_period") |>
    inner_join(
      gwl_tbl |>
        select(river_segment, gwl_period = period,
               gwl_median = median, gwl_spread = spread_ratio),
      by = c("river_segment", "gwl_period")
    ) |>
    mutate(ratio_of_ratios = era_spread / gwl_spread)
}

summarize_across_reaches <- function(matched_tbl) {
  # Purpose: collapse the ten reaches to the numbers the memorandum reports.
  # In:  the matched table from join_matched_states().
  # Out: one row per pairing: median and range of each spread ratio across
  #      reaches, and the median of their quotient.
  matched_tbl |>
    group_by(pairing, era_period, gwl_period) |>
    summarise(
      n_reaches      = n(),
      era_spread_med = median(era_spread),
      era_spread_min = min(era_spread),
      era_spread_max = max(era_spread),
      gwl_spread_med = median(gwl_spread),
      gwl_spread_min = min(gwl_spread),
      gwl_spread_max = max(gwl_spread),
      quotient_med   = median(ratio_of_ratios),
      .groups = "drop"
    )
}

# --- run ---------------------------------------------------------------------

era <- read_csv(ERA_CSV, show_col_types = FALSE) |>
  add_spread_ratio() |>
  select_scenario_periods("RCP85", PAIRINGS$era_period)

gwl <- read_csv(GWL_CSV, show_col_types = FALSE) |>
  add_spread_ratio() |>
  select_scenario_periods("RCP85", PAIRINGS$gwl_period)

matched <- join_matched_states(era, gwl, PAIRINGS)
overall <- summarize_across_reaches(matched)

cat("\n-- Per reach: p90/p10 on each axis, RCP8.5 --\n")
matched |>
  mutate(across(c(era_median, gwl_median), \(x) round(x, 1)),
         across(c(era_spread, gwl_spread, ratio_of_ratios), \(x) round(x, 2))) |>
  arrange(pairing, river_segment) |>
  print(n = Inf)

cat("\n-- Across the ten reaches --\n")
overall |>
  mutate(across(where(is.numeric), \(x) round(x, 2))) |>
  print(width = Inf)

cat("\nQuotient > 1 means the calendar-era band is wider than the band at the",
    "\nmatched warming level, the share attributable to timing disagreement.\n")
