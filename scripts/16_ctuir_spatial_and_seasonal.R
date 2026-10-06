# =============================================================================
# 16_ctuir_spatial_and_seasonal.R
#
# Jobs 2 and 3 of the CTUIR analytical jobs (NOTE_ctuir_analytical_roles.md
# §2, §3). Both are within-model, within-node ratios of the CTUIR SWAT record
# alone -- no UW data, no daily series, no fitting, no bias correction.
#
# Job 2 -- spatial uniformity of the change signal. The forward model applies
#   one change signal across a corridor forced by two different gages
#   (NOTE_gage_reach_forcing_mapping.md). The UW ensemble has one control point
#   and cannot test whether the projected CHANGE is the same at both forcing
#   points. CTUIR has three nodes, so this is the only place in the project
#   where the question can be asked.
#
# Job 3 -- seasonal reallocation. The forward model reports a change in
#   migration rate and is silent on the flow season having moved. Monthly
#   resolution is the right instrument for a seasonal-timing claim: averaging
#   destroys event structure but does not touch the seasonal centroid.
#
# Neither job enters the model of record. Job 2 supports a structural
# assumption already in it; Job 3 qualifies how its output should be read.
#
# Inputs  : data_in/CTUIR_future_flows_modeling/Umatilla_Future_Flows_Results.xlsx
#           (via read_ctuir_monthly() in scripts/15_ctuir_uw_monthly_comparison.R)
# Outputs : returned in memory; nothing written
#
# NOTE ON SOURCING: script 15 runs its own comparison and prints a figure when
# sourced. That is a few seconds of cost for reusing one reader rather than
# duplicating it. If that becomes annoying, the fix is to lift the reader into
# a shared file, not to copy it.
# =============================================================================

source("scripts/15_ctuir_uw_monthly_comparison.R")

library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

# Nodes in upstream-to-downstream order, stated literally so a figure cannot
# silently re-order itself if a delivery changes. Gibbon is Meacham Creek
# (176 mi2), West Boundary the mainstem forcing node (441 mi2), Yoakum further
# downstream.
#
# CAVEAT that must travel with any Job 2 text: Gibbon is NESTED INSIDE West
# Boundary's drainage -- Meacham Cr. is tributary to the Umatilla above the
# West Reservation Boundary. These are not independent basins. The defensible
# claim is within-basin uniformity of the change signal across a 2.5x
# drainage-area range, which is what the corridor forcing structure needs.
NODES <- c("Gibbon", "West Boundary", "Yoakum")

# Scenario-era cells in increasing-forcing order. The hindcast is the common
# denominator for every ratio and is not itself a period here.
#
# The scenario strings are taken from the workbook's 'C scenario' column.
# "baseline C" is confirmed for the hindcast rows (2026-10-06); the two RCP
# labels are confirmed for RCP85 and assumed symmetric for RCP45. The cell
# census below prints the distinct values, so a mismatch surfaces on the first
# run rather than silently dropping rows.
HINDCAST_SCENARIO <- "baseline C"

PERIODS <- tibble::tribble(
  ~scenario, ~era,   ~period_label,
  "RCP45",   "2040", "RCP4.5 2040",
  "RCP45",   "2080", "RCP4.5 2080",
  "RCP85",   "2040", "RCP8.5 2040",
  "RCP85",   "2080", "RCP8.5 2080"
)

# The four CTUIR GCMs, upper-cased as read_ctuir_monthly() returns them.
#
# UNCONDITIONAL CONSTRAINT (NOTE_ctuir_analytical_roles.md §4): the CTUIR
# multi-model mean is pulled by NorESM1-M under RCP8.5 and must never be quoted
# bare. Every pooled quantity below is a MEDIAN across GCMs, and the per-model
# values are returned alongside so the spread is visible rather than hidden.
CTUIR_MODELS  <- c("CANESM", "GFDL", "BNUESM", "NORESM")
ROBUSTNESS_EXCLUDE <- "NORESM"   # §2: the Job 2 finding is re-run without it

# Seasonal groupings for Job 3, as published in the note.
DJF_MONTHS <- c(12L, 1L, 2L)
AMJ_MONTHS <- c(4L, 5L, 6L)

FIG_WIDTH_IN  <- 9     # letter landscape text block, settled 2026-10-06
FIG_HEIGHT_IN <- 6


# =============================================================================
# 2. CELL CENSUS  (the window check that replaced stated year literals)
# =============================================================================

census_ctuir_cells <- function(ctuir_long) {
  #' Report the year span and row count of every node x model x scenario x era
  #' cell in the workbook.
  #' WHY THIS EXISTS: this script defines its averaging windows by the workbook's
  #' own 'era' label rather than by stated year literals. That removes the
  #' per-cell window lookup the unequal 2040-era lengths would otherwise force
  #' (2030-2050 for most cells, 2030-2051 for RCP4.5 GFDL and NorESM), and the
  #' inequality is harmless because every quantity here is a within-model mean.
  #' The cost is that a redelivery with different era extents would be picked up
  #' silently. This census reports the extents instead of enforcing them, so a
  #' change shows up in the console.
  #' @param ctuir_long tidy table from read_ctuir_monthly()
  #' @return tibble(node, model, scenario, era, y1, y2, n_years, n_rows)
  ctuir_long %>%
    summarize(y1      = min(year),
              y2      = max(year),
              n_years = n_distinct(year),
              n_rows  = n(),
              .by     = c(node, model, scenario, era)) %>%
    arrange(node, model, scenario, era)
}


# =============================================================================
# 3. CLIMATOLOGY AND CHANGE RATIOS  (pure)
# =============================================================================

climatology_by_cell <- function(ctuir_long) {
  #' Twelve-month climatology for every node x model x scenario x era cell.
  #' Reuses summarize_monthly_climatology()'s two-stage logic -- mean within
  #' year-month, then mean across years -- applied per cell, so a cell with an
  #' extra year is still weighted one-year-one-vote.
  #' @param ctuir_long tidy table from read_ctuir_monthly()
  #' @return tibble(node, model, scenario, era, month, value) -- 12 rows per cell
  ctuir_long %>%
    summarize(value = mean(flow_cms, na.rm = TRUE),
              .by   = c(node, model, scenario, era, year, month)) %>%
    summarize(value = mean(value),
              .by   = c(node, model, scenario, era, month))
}

attach_hindcast <- function(clim, hindcast_scenario) {
  #' Pair every future cell with its OWN model's hindcast at the SAME node.
  #' Within-model and within-node by construction: differencing against another
  #' model, another node, or a pooled baseline would import absolute SWAT bias
  #' into the change signal, which is the one thing these jobs must not do.
  #' @param clim climatology table from climatology_by_cell()
  #' @param hindcast_scenario the 'C scenario' value marking hindcast rows
  #' @return tibble(node, model, scenario, era, month, value, hindcast)
  baseline <- clim %>%
    filter(era == "hindcast") %>%
    select(node, model, month, hindcast = value)

  clim %>%
    filter(era != "hindcast", scenario != hindcast_scenario) %>%
    left_join(baseline, by = c("node", "model", "month"))
}

change_ratio_by_cell <- function(clim, hindcast_scenario) {
  #' Monthly change ratio, future cell over its own hindcast, for every cell.
  #' Units cancel, so no cms-to-cfs conversion is needed anywhere.
  #' @return tibble(node, model, scenario, era, month, ratio)
  attach_hindcast(clim, hindcast_scenario) %>%
    transmute(node, model, scenario, era, month, ratio = value / hindcast)
}

median_across_models <- function(ratios, exclude = character(0)) {
  #' Collapse per-model change ratios to a GCM median, optionally dropping
  #' named models.
  #' MEDIAN, not mean: the CTUIR multi-model mean is pulled by NorESM1-M under
  #' RCP8.5 (48 of 54 above-bankfull months) and must never be quoted bare.
  #' The `exclude` argument makes the note's NorESM robustness check a
  #' reproducible call rather than an ad hoc re-run.
  #' @param ratios tibble from change_ratio_by_cell()
  #' @param exclude character vector of model names to drop
  #' @return tibble(node, scenario, era, month, ratio_median, ratio_min,
  #'   ratio_max, n_models)
  ratios %>%
    filter(!model %in% exclude) %>%
    summarize(ratio_median = median(ratio),
              ratio_min    = min(ratio),
              ratio_max    = max(ratio),
              n_models     = n_distinct(model),
              .by          = c(node, scenario, era, month))
}

compare_nodes_to_reference <- function(node_medians, reference_node) {
  #' Ratio of each node's change signal to the reference node's, month by month.
  #' This is the Job 2 statistic: a value near 1.0 means the two forcing points
  #' project the same change, which is what applying a single change signal
  #' across the corridor assumes.
  #' @param node_medians tibble from median_across_models()
  #' @param reference_node node name used as the denominator
  #' @return tibble(node, scenario, era, month, vs_reference)
  reference <- node_medians %>%
    filter(node == reference_node) %>%
    select(scenario, era, month, reference = ratio_median)

  node_medians %>%
    filter(node != reference_node) %>%
    left_join(reference, by = c("scenario", "era", "month")) %>%
    transmute(node, scenario, era, month, vs_reference = ratio_median / reference)
}


# =============================================================================
# 4. SEASONAL SHARES  (pure)
# =============================================================================

monthly_share_by_cell <- function(clim) {
  #' Each month's share of the annual total, per cell.
  #' Shares are taken over the sum of the twelve monthly MEANS, so month length
  #' is not weighted -- February carries the same denominator weight as January.
  #' That biases every share slightly, but identically in every cell, so the
  #' hindcast-to-future comparison the job rests on is unaffected. A
  #' volume-weighted share would move the absolute numbers by a few percent and
  #' the reallocation not at all.
  #' @param clim climatology table from climatology_by_cell()
  #' @return tibble(node, model, scenario, era, month, share)
  clim %>%
    mutate(share = value / sum(value),
           .by   = c(node, model, scenario, era)) %>%
    select(node, model, scenario, era, month, share)
}

summarize_season_shares <- function(shares, djf_months, amj_months) {
  #' Collapse monthly shares to the three Job 3 statistics per cell: the
  #' wettest month, winter's share of the annual total, and spring's.
  #' The wettest month is the headline -- it moves April to March to February
  #' with increasing forcing -- and the two seasonal shares quantify the same
  #' shift as a redistribution of volume.
  #' @param shares tibble from monthly_share_by_cell()
  #' @param djf_months,amj_months integer month numbers defining each season
  #' @return tibble(node, model, scenario, era, peak_month, djf_share, amj_share)
  shares %>%
    summarize(peak_month = month[which.max(share)],
              djf_share  = sum(share[month %in% djf_months]),
              amj_share  = sum(share[month %in% amj_months]),
              .by        = c(node, model, scenario, era))
}

median_season_shares <- function(season_shares) {
  #' GCM-median seasonal shares, with the per-model range retained.
  #' The note's published Job 3 table was GCM-POOLED; this returns the median
  #' for consistency with Job 2 and with the never-quote-the-mean constraint, so
  #' values may differ slightly from the published figures. The per-model table
  #' is returned alongside, which is where NorESM should be inspected.
  #' @param season_shares tibble from summarize_season_shares()
  #' @return tibble(node, scenario, era, djf_median, djf_min, djf_max,
  #'   amj_median, amj_min, amj_max, peak_months, n_models)
  season_shares %>%
    summarize(djf_median  = median(djf_share),
              djf_min     = min(djf_share),
              djf_max     = max(djf_share),
              amj_median  = median(amj_share),
              amj_min     = min(amj_share),
              amj_max     = max(amj_share),
              peak_months = paste(sort(unique(peak_month)), collapse = ", "),
              n_models    = n_distinct(model),
              .by         = c(node, scenario, era))
}


# =============================================================================
# 5. LABELLING
# =============================================================================

label_periods <- function(x, periods, hindcast_label = "Hindcast") {
  #' Attach the display label for each scenario-era cell and order it by
  #' increasing forcing. Hindcast rows, where present, lead.
  #' Levels are stated by the caller rather than read off the data, so the
  #' figure cannot re-order itself if a run produces a different set of cells.
  #' @param x any table carrying scenario and era columns
  #' @param periods the PERIODS tribble
  #' @param hindcast_label label used for era == "hindcast" rows
  #' @return x with a period_label factor column added
  levels_in_order <- c(hindcast_label, periods$period_label)

  x %>%
    left_join(periods, by = c("scenario", "era")) %>%
    mutate(period_label = factor(if_else(era == "hindcast",
                                         hindcast_label, period_label),
                                 levels = levels_in_order))
}


# =============================================================================
# 6. FIGURES
# =============================================================================

plot_node_change_ratios <- function(node_medians, periods, node_order) {
  #' Job 2: monthly change-ratio curves, one line per node, faceted by
  #' scenario-era.
  #' Nodes are overlaid rather than faceted because the claim is about the gap
  #' BETWEEN them -- curves that sit on top of each other in Jan-Mar are the
  #' finding. A line at 1.0 marks no change.
  #' @return a ggplot object
  node_medians %>%
    label_periods(periods) %>%
    mutate(month = factor(month, levels = 1:12, labels = MONTH_LABELS),
           node  = factor(node, levels = node_order)) %>%
    ggplot(aes(x = month, y = ratio_median, colour = node, group = node)) +
    geom_hline(yintercept = 1, linewidth = 0.3, colour = "grey50") +
    geom_line(linewidth = 0.7) +
    geom_point(size = 1.4) +
    facet_wrap(~ period_label, nrow = 1) +
    labs(
      x = NULL,
      y = "Change ratio (future / hindcast)",
      colour = NULL,
      title = "Spatial uniformity of the monthly change signal across three CTUIR nodes",
      subtitle = "GCM median of within-model, within-node ratios; Gibbon is nested inside West Boundary's drainage"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")
}

plot_monthly_shares <- function(shares, periods, node_order) {
  #' Job 3: each month's share of the annual total, one line per scenario-era,
  #' faceted by node.
  #' Curves rather than the stacked bar the note suggested: the finding is that
  #' the PEAK MOVES, and a peak sliding left across overlaid curves reads
  #' directly, where twelve stacked segments do not. The stacked bar remains the
  #' better choice if the emphasis shifts to seasonal volume blocks.
  #' @return a ggplot object
  shares %>%
    summarize(share = median(share), .by = c(node, scenario, era, month)) %>%
    label_periods(periods) %>%
    mutate(month = factor(month, levels = 1:12, labels = MONTH_LABELS),
           node  = factor(node, levels = node_order)) %>%
    ggplot(aes(x = month, y = share, colour = period_label, group = period_label)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 1.4) +
    facet_wrap(~ node, nrow = 1) +
    labs(
      x = NULL,
      y = "Share of annual total",
      colour = NULL,
      title = "Seasonal reallocation of flow under increasing forcing",
      subtitle = "GCM median monthly share; the wettest month moves April to March to February"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")
}


# =============================================================================
# 7. ORCHESTRATOR
# =============================================================================

run_spatial_and_seasonal <- function() {
  #' Build Jobs 2 and 3 from the CTUIR workbook alone. All file reading happens
  #' in read_ctuir_monthly(), sourced from script 15.
  #' @return list of tables and figures; see names() on the result
  stopifnot(file.exists(CTUIR_XLSX))

  ctuir_long <- read_ctuir_monthly(CTUIR_XLSX, CTUIR_SHEET)
  census     <- census_ctuir_cells(ctuir_long)

  clim <- climatology_by_cell(ctuir_long)

  # --- Job 2: is the change signal the same at both forcing points? ----------
  ratios_by_model <- change_ratio_by_cell(clim, HINDCAST_SCENARIO)
  node_medians    <- median_across_models(ratios_by_model)
  node_medians_no_noresm <- median_across_models(ratios_by_model,
                                                 exclude = ROBUSTNESS_EXCLUDE)
  node_contrast <- compare_nodes_to_reference(node_medians, "West Boundary")

  # --- Job 3: where in the year does the water arrive? ----------------------
  shares        <- monthly_share_by_cell(clim)
  season_by_model <- summarize_season_shares(shares, DJF_MONTHS, AMJ_MONTHS)
  season_medians  <- median_season_shares(season_by_model)

  list(
    census                 = census,
    ratios_by_model        = ratios_by_model,
    node_medians           = node_medians,
    node_medians_no_noresm = node_medians_no_noresm,
    node_contrast          = node_contrast,
    shares                 = shares,
    season_by_model        = season_by_model,
    season_medians         = season_medians,
    figure_job2 = plot_node_change_ratios(node_medians, PERIODS, NODES),
    figure_job3 = plot_monthly_shares(shares, PERIODS, NODES)
  )
}

out <- run_spatial_and_seasonal()
print(out$census, n = Inf)
print(out$figure_job2)
print(out$figure_job3)
