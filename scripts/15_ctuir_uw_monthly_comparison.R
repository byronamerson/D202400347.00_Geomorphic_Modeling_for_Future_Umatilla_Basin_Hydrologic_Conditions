# =============================================================================
# 15_ctuir_uw_monthly_comparison.R
#
# Job 1 of the CTUIR analytical jobs (NOTE_ctuir_analytical_roles.md §1):
# a hydrologic-model-structure check on the monthly change signal.
#
# Claim supported: two structurally different hydrologic models, given the same
# downscaled climate over this basin, route it to similar seasonal outcomes --
# evidence that hydrologic model structure is not the dominant uncertainty here.
# NOT independent corroboration: both products sit downstream of MACA
# downscaling (NOTE_ctuir_swat_monthly_flows.md §6). SWAT vs VIC is the only
# thing that differs, and the hydrology is what the agreement tests.
#
# This comparison does NOT validate the forcing metric and cannot. A monthly
# mean is set by the bulk of the flow distribution; cum_excess sums only days
# above 4,156 cfs, in the extreme tail. Two models can agree month-for-month on
# mean flow and differ completely in days above bankfull. See the dry-month
# limitation on compute_change_ratio().
#
# Inputs  : data_in/CTUIR_future_flows_modeling/Umatilla_Future_Flows_Results.xlsx
#           data_in/Umatilla_Future_Flows/<member>-UMAMC-streamflow-1.0.csv (raw)
# Outputs : returned in memory; nothing written
# =============================================================================

library(dplyr)
library(purrr)
library(readr)
library(readxl)
library(ggplot2)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

CTUIR_XLSX    <- "data_in/CTUIR_future_flows_modeling/Umatilla_Future_Flows_Results.xlsx"
CTUIR_SHEET   <- "data"
RAW_DIR       <- "data_in/Umatilla_Future_Flows"
MISSING_VALUE <- -9999                 # UMAMC files flag gaps with -9999

CTUIR_NODE    <- "West Boundary"       # USGS 14020850, the forcing node for RS25-37
SCENARIO      <- "RCP85"
FUTURE_ERA    <- "2080"

# Windows stated literally rather than derived, so the figure cannot silently
# re-scope if a future delivery changes era extents. Both verified against the
# workbook on 2026-10-06: hindcast 1971-1990 (20 yr) and the 2080 era 2070-2090
# (21 yr) for every model and scenario.
HINDCAST_YEARS <- 1971:1990
FUTURE_YEARS   <- 2070:2090

# All four CTUIR models. Two have a UW counterpart; two do not, and are carried
# so the figure shows the full CTUIR spread -- NorESM1-M in particular, which is
# the wet-responding outlier and has no independent realization available to us.
#
# uw_file is NA where no counterpart exists. One UW member per GCM (MACA/VIC_P1)
# holds the chain constant, following the 09-25 cross-validation design.
# MACA is the right downscaling because CTUIR's own provenance is MACA, leaving
# SWAT vs VIC as the only difference.
#
# GFDL: the workbook says only "GFDL". MACA carries both GFDL-ESM2G and
# GFDL-ESM2M; the UW ensemble carries only ESM2M. The pairing is therefore
# probable, not certain, and is labelled as such on the figure.
MODELS <- tibble::tribble(
  ~ctuir_model, ~panel_label,                ~uw_file,
  "CANESM",     "CanESM2",                   "CanESM2_RCP85_MACA_VIC_P1-UMAMC-streamflow-1.0.csv",
  "GFDL",       "GFDL (variant unspecified)", "GFDL-ESM2M_RCP85_MACA_VIC_P1-UMAMC-streamflow-1.0.csv",
  "BNUESM",     "BNU-ESM (CTUIR only)",      NA_character_,
  "NORESM",     "NorESM1-M (CTUIR only)",    NA_character_
)

MONTH_LABELS <- month.abb


# =============================================================================
# 2. READERS  (boundary: all file I/O lives here)
# =============================================================================

read_umamc_streamflow <- function(path) {
  #' Read one UMAMC daily-streamflow file (raw RMJOC-II output).
  #' The provenance header is comment-marked with '#'; the first non-comment
  #' line is the column header. The DYNAMICAL variant ships an UNNAMED first
  #' column, so read the two columns BY POSITION, not by name -- col 1 is date
  #' and col 2 is streamflow in every variant. Convention taken unchanged from
  #' scripts/09_bias_correction.R.
  #' @param path path to a *-UMAMC-streamflow-1.0.csv file
  #' @return tibble(date <Date>, q_cfs <dbl>); -9999 gaps become NA
  raw <- read_csv(path, comment = "#", show_col_types = FALSE,
                  col_types = cols(.default = col_character()))
  tibble(date  = as.Date(raw[[1]]),
         q_cfs = na_if(as.double(raw[[2]]), MISSING_VALUE))
}

read_ctuir_monthly <- function(path, sheet) {
  #' Read the CTUIR SWAT monthly-flow workbook into a tidy long table.
  #' The 'data' sheet holds year-by-year monthly values, not a 12-month
  #' climatology, and is sorted by flow rather than by time.
  #' Two format decisions: columns A:G are read and the unlabeled 8th column
  #' (FLOW_OUTcms x 35.3147, i.e. cfs) is left behind rather than read and
  #' dropped; and model is upper-cased because the hindcast rows spell it
  #' "CanESM" where every future row spells it "CANESM".
  #' @param path path to Umatilla_Future_Flows_Results.xlsx
  #' @param sheet sheet name holding the year-by-year record
  #' @return tibble(node, model, scenario, era, year, month, flow_cms)
  #'   -- one row per node x model x scenario-era x year x month
  read_xlsx(path, sheet = sheet, range = cell_cols("A:G")) %>%
    transmute(
      node     = SUB,
      model    = toupper(model),
      scenario = `C scenario`,
      era      = `time era`,
      year     = as.integer(YEAR),
      month    = as.integer(MON),
      flow_cms = as.double(FLOW_OUTcms)
    )
}


# =============================================================================
# 3. REDUCTION TO MONTHLY CLIMATOLOGY  (pure)
# =============================================================================

summarize_monthly_climatology <- function(monthly, years) {
  #' Collapse a year-by-month record to a twelve-month climatology.
  #' Two stages, deliberately: mean within each year-month, then mean across
  #' years. Equal weight per year, which matches how the CTUIR workbook is
  #' built and keeps a long month from outweighing a short one.
  #' @param monthly tibble with columns year, month, value
  #' @param years integer vector; the window to average over
  #' @return tibble(month <int>, value <dbl>) -- 12 rows, one per calendar month
  monthly %>%
    filter(year %in% years) %>%
    summarize(value = mean(value, na.rm = TRUE), .by = c(year, month)) %>%
    summarize(value = mean(value), .by = month)
}

daily_to_monthly <- function(daily) {
  #' Reduce a daily streamflow series to year-by-month mean flow.
  #' Calendar months and calendar years, not water years -- the comparison is a
  #' month-of-year climatology, where a water-year offset would only relabel.
  #' @param daily tibble(date <Date>, q_cfs <dbl>)
  #' @return tibble(year <int>, month <int>, value <dbl>) in cfs
  daily %>%
    transmute(year  = as.integer(format(date, "%Y")),
              month = as.integer(format(date, "%m")),
              value = q_cfs) %>%
    summarize(value = mean(value, na.rm = TRUE), .by = c(year, month))
}

compute_change_ratio <- function(hindcast, future) {
  #' Monthly change ratio: future climatology divided by that same model's own
  #' hindcast climatology, month by month.
  #' Within-model by construction. Differencing against observations or a pooled
  #' baseline would import each model's bias into the change signal, which is
  #' the one thing this comparison must not do. Units cancel, so the CTUIR cms
  #' side and the UW cfs side are directly comparable with no conversion.
  #'
  #' Limitation, dry months: where the monthly distribution is strongly skewed
  #' -- late summer especially -- the ratio reports a change in event frequency
  #' dressed as a change in mean flow. UW CanESM2 August runs at 3.64 because
  #' nine of 21 future Augusts carry event days reaching 1,000+ cfs, while the
  #' dry baseflow floor between them is unchanged or lower (verified across all
  #' 160 statistical members, 2026-10-06: floor ratio median 0.916, range
  #' 0.373-1.87). Nov-May, where the flood season and cum_excess live, is
  #' unaffected.
  #' @param hindcast tibble(month, value) -- 12 rows
  #' @param future tibble(month, value) -- 12 rows
  #' @return tibble(month <int>, ratio <dbl>) -- 12 rows
  hindcast %>%
    rename(hindcast = value) %>%
    left_join(rename(future, future = value), by = "month") %>%
    transmute(month, ratio = future / hindcast)
}


# =============================================================================
# 4. PER-MODEL ASSEMBLY  (pure)
# =============================================================================

ctuir_change_ratio <- function(ctuir_long, ctuir_model) {
  #' One CTUIR model's change ratio at the forcing node, RCP8.5 2080 era
  #' against that model's own hindcast.
  #' @param ctuir_long tidy CTUIR table from read_ctuir_monthly()
  #' @param ctuir_model upper-cased CTUIR model name (e.g. "CANESM")
  #' @return tibble(month, ratio, source = "CTUIR SWAT")
  at_node <- ctuir_long %>%
    filter(node == CTUIR_NODE, model == ctuir_model) %>%
    rename(value = flow_cms)

  hindcast <- at_node %>%
    filter(era == "hindcast") %>%
    summarize_monthly_climatology(HINDCAST_YEARS)

  future <- at_node %>%
    filter(scenario == SCENARIO, era == FUTURE_ERA) %>%
    summarize_monthly_climatology(FUTURE_YEARS)

  compute_change_ratio(hindcast, future) %>%
    mutate(source = "CTUIR SWAT")
}

uw_change_ratio <- function(path) {
  #' One UW member's change ratio at Pendleton, 2070-2090 against the 1971-1990
  #' slice of the same continuous series.
  #' RAW members, not bias-corrected: the corrected products begin in 2006 and
  #' cannot supply a 1971-1990 hindcast. Within-model ratios make absolute bias
  #' cancel, and the CTUIR side is uncorrected SWAT, so raw-vs-raw is
  #' like-for-like. The raw statistical members run 1950-2099 unbroken, so both
  #' windows come from one file with no historical/future splice.
  #' @param path path to the member's UMAMC file
  #' @return tibble(month, ratio, source = "UW VIC")
  monthly <- daily_to_monthly(read_umamc_streamflow(path))

  compute_change_ratio(
    summarize_monthly_climatology(monthly, HINDCAST_YEARS),
    summarize_monthly_climatology(monthly, FUTURE_YEARS)
  ) %>%
    mutate(source = "UW VIC")
}

assemble_one_panel <- function(ctuir_model, panel_label, uw_file, ctuir_long) {
  #' Every curve belonging to one figure panel: the CTUIR curve always, plus
  #' the UW curve where a counterpart member exists.
  #' @return tibble(panel_label, source, month, ratio) -- 12 or 24 rows
  curves <- ctuir_change_ratio(ctuir_long, ctuir_model)

  if (!is.na(uw_file)) {
    curves <- bind_rows(curves, uw_change_ratio(file.path(RAW_DIR, uw_file)))
  }

  curves %>%
    mutate(panel_label = panel_label) %>%
    select(panel_label, source, month, ratio)
}


# =============================================================================
# 5. FIGURE
# =============================================================================

plot_change_ratio_curves <- function(ratios, panel_order) {
  #' Twelve-month change-ratio curves, CTUIR overlaid on UW where a counterpart
  #' exists, one panel per CTUIR model.
  #' A line at 1.0 marks no change, so agreement is read as curve shape against
  #' a fixed reference rather than against the other curve alone. Panel order is
  #' stated by the caller so the two paired models lead.
  #'
  #' Full twelve months on purpose: the whole-year redistribution is part of
  #' what the CTUIR record is being asked about, and truncating to the flood
  #' season would hide the summer behaviour rather than caveat it. The dry-month
  #' ratios are real but weakly informative -- see compute_change_ratio().
  #' @param ratios tibble(panel_label, source, month, ratio)
  #' @param panel_order character vector of panel labels, in display order
  #' @return a ggplot object
  ratios %>%
    mutate(month = factor(month, levels = 1:12, labels = MONTH_LABELS),
           panel_label = factor(panel_label, levels = panel_order)) %>%
    ggplot(aes(x = month, y = ratio, colour = source, group = source)) +
    geom_hline(yintercept = 1, linewidth = 0.3, colour = "grey50") +
    geom_line(linewidth = 0.7) +
    geom_point(size = 1.5) +
    facet_wrap(~ panel_label, nrow = 1) +
    labs(
      x = NULL,
      y = "Change ratio (2070-2090 / 1971-1990)",
      colour = NULL,
      title = "Monthly change signal under RCP8.5: CTUIR SWAT vs UW routed flow",
      subtitle = "Umatilla R. at the West Reservation Boundary / Pendleton; each model against its own hindcast"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")
}


# =============================================================================
# 6. ORCHESTRATOR
# =============================================================================

run_monthly_comparison <- function() {
  #' Build the change-ratio curves for all four CTUIR models plus the two UW
  #' counterparts, and the comparison figure. All file reading happens here and
  #' in the readers it calls.
  #' @return list(ratios = tibble, figure = ggplot)
  stopifnot(file.exists(CTUIR_XLSX))
  uw_paths <- file.path(RAW_DIR, na.omit(MODELS$uw_file))
  stopifnot(all(file.exists(uw_paths)))

  ctuir_long <- read_ctuir_monthly(CTUIR_XLSX, CTUIR_SHEET)

  ratios <- MODELS %>%
    pmap(assemble_one_panel, ctuir_long = ctuir_long) %>%
    list_rbind()

  list(ratios = ratios,
       figure = plot_change_ratio_curves(ratios, MODELS$panel_label))
}

out <- run_monthly_comparison()
print(out$figure)