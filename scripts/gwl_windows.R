# =============================================================================
# gwl_windows.R
# Umatilla River Discharge-Channel Migration Analysis
# Global Warming Level (GWL) track, step 1: the warming-level windows for our
# future-flow ensemble.
# =============================================================================
#
# The GWL track runs PARALLEL to the calendar-era track (scripts 11-13), which is
# unchanged. Both consume the same per-water-year forcing table; they differ only
# in how years are grouped before the migration model sees them:
#
#   era track : group years by calendar period   (PERIODS in 11)
#   GWL track : group years by warming level     (this file)
#
# This script produces the grouping key for the second: for each GCM x scenario,
# the 20-year window during which that model sits at +1.5, +2, +3 or +4 degC of
# global warming. A later step filters the annual forcing table to those windows.
#
# A warming level is a property of (GCM, scenario, span of years) ONLY. It does
# not depend on downscaling, hydrologic model, or parameter set, so every ensemble
# member sharing a GCM x scenario inherits the same windows.
#
# Windows are taken as published -- no interpolation between them and no
# extension past the last one. A model that never reaches a level simply has no
# window at that level and contributes nothing there; the report states how many
# models stand behind each level so a figure can carry that n.
#
# Source: mathause/cmip_warming_levels (Hauser, Engelbrecht & Fischer,
#   doi:10.5281/zenodo.3591806) -- the republished IPCC AR6 WGI Chapter 11
#   warming-level tables. Method: area-weighted global mean tas, annual mean,
#   minus the 1861-1900 baseline, 20-year centred running mean, first exceedance
#   gives the central year; window = [central - 10, central + 9].
#
# Inputs : data/cmip_warming_levels/warming_levels/cmip5_all_ens/csv/
#            cmip5_warming_levels_all_ens_1861_1900.csv   (cloned repo)
#          data/Umatilla_Future_Flows_BC/_bc_manifest.csv (our GCM list)
# Output : data/gwl_windows.csv
# Style  : Tidyverse & FP guidelines; docs/lingua.md.
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

CROSSING_TABLE <- file.path("data", "cmip_warming_levels", "warming_levels",
                            "cmip5_all_ens", "csv",
                            "cmip5_warming_levels_all_ens_1861_1900.csv")
MANIFEST       <- file.path("data", "Umatilla_Future_Flows_BC", "_bc_manifest.csv")
OUT_WINDOWS    <- file.path("data", "gwl_windows.csv")

# Baseline: 1861-1900, not the more common 1850-1900. The 1850-1900 table
# EXCLUDES any model whose historical run starts after 1850, which drops three of
# our ten (GFDL-ESM2M, HadGEM2-CC, HadGEM2-ES). The 1861-1900 table applies one
# baseline to all models. Cost, measured across our GCMs and both scenarios:
# crossing years move by a mean of +0.4 yr, range -1 to +2.

# Ensemble members, per RMJOC-II Part I Table 7: "All GCM data is from ensemble
# member r1i1p1 from each GCM dataset, except CCSM4 which is from ensemble member
# r6i1p1." Matching matters: CCSM4's two runs differ by up to 3 years at a given
# level (2 degC under RCP8.5 is 2021 for r1i1p1, 2024 for r6i1p1).
MEMBER_DEFAULT <- "r1i1p1"
MEMBER_BY_GCM  <- c(CCSM4 = "r6i1p1")

# Scenarios stay separate (Byron, 2026-09-28): RCP4.5 and RCP8.5 encode different
# assumptions about the future, and pooling them hides that.
SCENARIOS <- c(rcp45 = "RCP45", rcp85 = "RCP85")   # table spelling -> our spelling

# Reporting levels: the four IPCC AR6 standard warming levels. The published
# table also carries 0.61, 1.0 and 1.2 degC, which are not AR6 reporting levels
# and are excluded so no figure is built on a rung the literature does not use.
REPORTING_LEVELS <- c(1.5, 2.0, 3.0, 4.0)


# =============================================================================
# 2. READ
# =============================================================================

read_crossing_table <- function(path) {
  #' Purpose: load the published CMIP5 warming-level crossing table.
  #' In      : path to a cmip_warming_levels CSV. The file carries provenance
  #'           comment lines (#) above the header and pads fields with spaces.
  #' Out     : tibble(model, ensemble, exp, warming_level, start_year, end_year)
  #' Decision: comment = "#" and trim_ws are demanded by the file's format, not
  #'           style -- without them the header is read as data.
  read_csv(path, comment = "#", trim_ws = TRUE, show_col_types = FALSE) %>%
    rename_with(trimws) %>%
    mutate(across(where(is.character), trimws))
}

ensemble_gcms <- function(manifest_path) {
  #' Purpose: the GCMs actually present in our bias-corrected ensemble.
  #' In      : path to 10's _bc_manifest.csv.
  #' Out     : sorted character vector of GCM names.
  #' Decision: read rather than hardcode, so these windows cannot drift out of
  #'           step with the ensemble they group.
  read_csv(manifest_path, show_col_types = FALSE) %>%
    pull(gcm) %>% unique() %>% sort()
}

member_for_gcm <- function(gcm) {
  #' Purpose: the CMIP5 ensemble member RMJOC-II used for a given GCM.
  #' In      : gcm, character vector of model names.
  #' Out     : character vector of member ids, same length.
  #' Decision: see MEMBER_BY_GCM above -- RMJOC-II Part I, Table 7.
  coalesce(unname(MEMBER_BY_GCM[gcm]), MEMBER_DEFAULT)
}


# =============================================================================
# 3. THE WINDOWS
# =============================================================================

select_gwl_windows <- function(crossings, gcms, levels) {
  #' Purpose: reduce the published table to the warming-level windows for the
  #'          exact model runs our flows came from, at the reporting levels.
  #' In      : crossings, the published table; gcms, our GCM names; levels, the
  #'           warming levels to report at.
  #' Out     : tibble(gcm, scenario, warming_level, start_year, end_year,
  #'           n_years), one row per GCM x scenario x level that was reached.
  #' Decision: absence is meaningful. A GCM that never reaches a level has no row
  #'           there and contributes nothing to it -- that is the honest
  #'           behaviour, and the reason the report counts models per level.
  crossings %>%
    filter(model %in% gcms,
           exp %in% names(SCENARIOS),
           ensemble == member_for_gcm(model),
           warming_level %in% levels) %>%
    transmute(gcm      = model,
              scenario = unname(SCENARIOS[exp]),
              warming_level,
              start_year,
              end_year,
              n_years  = end_year - start_year + 1L) %>%
    arrange(scenario, warming_level, gcm)
}


# =============================================================================
# 4. BUILD  (I/O at the boundary)
# =============================================================================

gcms    <- ensemble_gcms(MANIFEST)
windows <- select_gwl_windows(read_crossing_table(CROSSING_TABLE),
                              gcms, REPORTING_LEVELS)

write_csv(windows, OUT_WINDOWS)


# =============================================================================
# 5. REPORT
# =============================================================================

cat("\n=== 1. Models reaching each warming level ===\n")
windows %>%
  count(scenario, warming_level, name = "n_gcms") %>%
  mutate(of = length(gcms)) %>%
  pivot_wider(id_cols = scenario, names_from = warming_level,
              values_from = n_gcms, names_prefix = "deg_") %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n    How many of the ", length(gcms), " ensemble GCMs reach each level, by\n",
    "   scenario. A blank or low count is not an error -- models that never reach\n",
    "   a level contribute nothing there. These are the n values a figure at each\n",
    "   level must carry.\n", sep = "")

cat("\n=== 2. The windows ===\n")
windows %>%
  mutate(window = paste0(start_year, "-", end_year)) %>%
  pivot_wider(id_cols = c(scenario, gcm), names_from = warming_level,
              values_from = window, names_prefix = "deg_") %>%
  arrange(scenario, gcm) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n    The 20 years of each member's record that represent that GCM at that\n",
    "   warming level. A later step filters the annual forcing table to these\n",
    "   spans; every member sharing a GCM and scenario uses the same window.\n",
    "   NA means that model does not reach that level before 2100.\n", sep = "")
