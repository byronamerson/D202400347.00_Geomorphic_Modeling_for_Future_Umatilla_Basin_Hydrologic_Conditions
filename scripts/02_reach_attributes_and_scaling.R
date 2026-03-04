# =============================================================================
# 02_reach_attributes_and_scaling.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1: Build tidy reach-attribute table; assign discharge via DA scaling
# =============================================================================
#
# Purpose: Import CMZ summary spreadsheets into a single tidy reach-attribute
#          tibble, assign discharge to each reach via drainage area scaling,
#          and compute unit stream power at reference discharge (Q2).
#
# Inputs:
#   - Umatilla_River__CMZ_Summary.xlsx (Summary Table, EHA Table, AHA Table)
#   - data/gage_metadata.csv           (from 01_hydrology_acquisition.R)
#   - data/flood_frequency.csv         (from 01_hydrology_acquisition.R)
#
# Outputs:
#   - data/reach_attributes.csv  — one row per RS with all geomorphic,
#     hydraulic, and stream power fields (portable, human-readable)
#   - data/da_scaling_fit.rds    — lm object for DA scaling (non-tabular,
#     retained as .rds per data format standards)
#
# References:
#   Baker, V.R. & Costa, J.E. (1987). Flood power. In: Mayer & Nash (eds.),
#     Catastrophic Flooding, pp. 1-21. Allen & Unwin.
#   Magilligan, F.J. (1992). Thresholds and the spatial variability of flood
#     power during extreme floods. Geomorphology, 5(3-5), 373-390.
#   Nanson, G.C. & Hickin, E.J. (1986). A statistical analysis of bank
#     erosion and channel migration in western Canada. GSA Bulletin, 97, 497-504.
#   Thomas, B.E. et al. (1997). Methods for estimating flood frequency in
#     Washington. USGS Water-Resources Investigations Report 97-4277.
#   Wood, M.S. et al. (2016). Estimating peak-flow frequency statistics for
#     selected gaged and ungaged sites in naturally flowing streams and rivers
#     in Idaho. USGS SIR 2016-5083.
#   Yochum, S.E. et al. (2017). Photographic guidance for selecting flow
#     resistance coefficients in high-gradient channels. USGS SIR 2017-5099.
#   Sholtes, J.S. et al. (2018). Physical context for theoretical approaches
#     to sediment transport magnitude-frequency analysis in alluvial channels.
#     Water Resources Research, 54, 3007-3023.
#
# Style: Follows Tidyverse & Functional Programming Guidelines
#        (Tidyverse_Functional_Programming_Guidelines_for_temperheic.md)
# =============================================================================

library(tidyverse)
library(readxl)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================
# All file paths, gage assignments, and physical constants in one place.
# Edit this block when running on a different machine or with updated data.

config <- list(
  # ---- Input files ----
  xlsx_path       = "Umatilla_River__CMZ_Summary.xlsx",
  gage_meta_path  = "data/gage_metadata.csv",
  flood_freq_path = "data/flood_frequency.csv",

  # ---- Output files ----
  output_dir      = "data/",
  reach_attr_csv  = "data/reach_attributes.csv",
  da_fit_rds      = "data/da_scaling_fit.rds",

  # ---- Physical constants ----
  gamma           = 9810,       # specific weight of water (N/m³)
  cfs_to_cms      = 0.02832,    # conversion factor
  ft_to_m         = 0.3048,

  # ---- DA scaling default ----
  # Typical PNW exponent for flood peaks: 0.8-1.0
  # (Thomas et al., 1997, USGS WRI 97-4277; Wood et al., 2016, SIR 2016-5083)
  alpha_default   = 0.9,

  # ---- Gage-to-reach breakpoints ----
  # RS numbering runs downstream (RS 1 = mouth) to upstream (RS 39).
  # Breakpoints reflect major tributary confluences and gage locations.
  # These should be refined with GIS drainage area accumulation.
  gage_breaks = tribble(
    ~rs_min, ~rs_max, ~gage_id,
    30,      39,      "14020000",   # upstream of Pendleton (Gibbon)
    9,       29,      "14020850",   # Pendleton corridor (Reservation Bndy)
    1,       8,       "14033500"    # lower river near Umatilla
  ),

  # ---- Approximate stream stations for each gage (ft from mouth) ----
  # Used for DA interpolation. Replace with GIS-derived values when available.
  gage_stations = tribble(
    ~gage_id,     ~approx_station_ft,
    "14020000",   420000,   # near RS 39
    "14020850",   210000,   # near RS 20
    "14033500",    10000    # near RS 1
  )
)

# =============================================================================
# 1. IMPORT CMZ SUMMARY DATA
# =============================================================================
# Each import function reads one sheet and returns a tidy tibble.
# Atomic functions keep Excel-parsing logic isolated from analysis logic.

import_summary_table <- function(xlsx_path) {
  #' Import the Summary Table sheet from the CMZ spreadsheet.
  #' Extracts per-reach geometry: width, slope, sinuosity, erosion rates, length.
  #'
  #' Width source: DOGAMI 2024 active channel digitization from aerial imagery
  #'   at 1:4,000 scale (O-25-10 Section 2.3.1). Transects generated every
  #'   100 ft along stream centerline, clipped to AC boundary, averaged per RS.
  #' Slope source: from longitudinal profile or LiDAR (reported in Summary Table).
  #' Erosion rates: time-averaged median and maximum (ft/yr) over full photo
  #'   record (1952-2024), measured along bankline transects (O-25-10 Fig 2-5).
  read_xlsx(xlsx_path, sheet = "Summary Table", skip = 1) %>%
    select(
      rs              = 1,   # River Segment (RS 1, RS 2, ...)
      ds_station_ft   = 2,   # downstream stream station
      us_station_ft   = 3,   # upstream stream station
      length_ft       = 4,
      avg_width_ft    = 5,
      slope_pct       = 6,
      sinuosity       = 7,
      median_rate_ftyr = 8,  # median EHA erosion rate (ft/yr)
      max_rate_ftyr   = 9,   # maximum EHA erosion rate (ft/yr)
      channel_notes   = 10,  # qualitative channel description
      bank_notes      = 11   # bank/geology description
    ) %>%
    filter(str_detect(rs, "^RS\\s*\\d+$")) %>%
    mutate(
      rs_num = parse_number(rs),
      # Convert slope from percent to dimensionless (m/m)
      slope  = slope_pct / 100,
      # Dimensionless erosion rates (channel widths per year)
      # Following Nanson & Hickin (1986) convention for cross-system comparison
      median_rate_cw = median_rate_ftyr / avg_width_ft,
      max_rate_cw    = max_rate_ftyr / avg_width_ft
    ) %>%
    arrange(rs_num)
}

import_eha_table <- function(xlsx_path) {
  #' Import the EHA Table sheet.
  #' Extracts measured vs. modified erosion rates and buffer distances.
  #' Modified rates account for infrastructure constraints per DOGAMI methodology:
  #'   reaches where levees suppress observed rates get group-median substitution
  #'   from adjacent unmodified reaches (O-25-10 Section 2.3.5).
  read_xlsx(xlsx_path, sheet = "EHA Table", skip = 3) %>%
    select(
      rs                    = 1,
      avg_ac_width_ft       = 2,
      high_30yr_buffer_ft   = 3,
      median_rate_ftyr_eha  = 4,
      median_rate_cw_eha    = 5,
      med_30yr_buffer_ft    = 6,
      low_100yr_buffer_ft   = 7,
      measured_rate_ftyr    = 8,
      measured_rate_cw      = 9,
      modified_rate_ftyr    = 10,
      modified_rate_cw      = 11,
      modification_type     = 12
    ) %>%
    filter(str_detect(rs, "^RS\\s*\\d+$")) %>%
    mutate(rs_num = parse_number(rs)) %>%
    arrange(rs_num)
}

import_aha_table <- function(xlsx_path) {
  #' Import the AHA (Avulsion Hazard Area) Table.
  #' Parses avulsion observation intervals and counts per reach.
  #' Avulsion events are bracketed by photo interval dates (not exact dates).
  #' Photo years: 1952, 1964, 1974, 1981, 1995, 2000, 2005, 2009, 2011,
  #'   2012, 2014, 2016, 2017, 2022, 2024 (USGS single-frame + NAIP/OSIP).
  read_xlsx(xlsx_path, sheet = "AHA Table", skip = 1) %>%
    select(
      rs               = 1,
      avulsion_periods = 2,   # semicolon-delimited observation intervals
      avulsion_notes   = 3
    ) %>%
    filter(str_detect(rs, "^RS\\s*\\d+$")) %>%
    mutate(
      rs_num         = parse_number(rs),
      has_avulsions  = !is.na(avulsion_periods) & avulsion_periods != "N/A",
      avulsion_count = if_else(
        has_avulsions,
        map_int(avulsion_periods, count_avulsions_from_text),
        0L
      )
    ) %>%
    arrange(rs_num)
}

count_avulsions_from_text <- function(text) {
  #' Parse an avulsion period string to count total events.
  #' Handles entries like "2019-2020 (two avulsions)" by counting the
  #' multiplier, and standard semicolon-separated entries as 1 each.
  if (is.na(text) || text == "N/A") return(0L)

  entries <- str_split(text, ";")[[1]] %>% str_trim()

  counts <- map_int(entries, function(entry) {
    if (str_detect(entry, regex("two|2x|\\(2\\)", ignore_case = TRUE))) {
      2L
    } else if (str_detect(entry, regex("three|3x|\\(3\\)", ignore_case = TRUE))) {
      3L
    } else {
      1L
    }
  })

  sum(counts)
}

# =============================================================================
# 2. MERGE INTO UNIFIED REACH TABLE
# =============================================================================

build_reach_table <- function(xlsx_path) {
  #' Import all three sheets and merge into a single tidy reach table.
  #' One row per river segment with geometry, erosion rates, and avulsions.

  summary_tbl <- import_summary_table(xlsx_path)
  eha_tbl     <- import_eha_table(xlsx_path)
  aha_tbl     <- import_aha_table(xlsx_path)

  summary_tbl %>%
    left_join(
      eha_tbl %>% select(rs_num, measured_rate_ftyr, measured_rate_cw,
                         modified_rate_ftyr, modified_rate_cw,
                         modification_type),
      by = "rs_num"
    ) %>%
    left_join(
      aha_tbl %>% select(rs_num, avulsion_periods, has_avulsions,
                         avulsion_count, avulsion_notes),
      by = "rs_num"
    )
}

# =============================================================================
# 3. REACH CLASSIFICATION
# =============================================================================
# Derive categorical covariates from the qualitative notes in the CMZ summary.
# These are needed as predictors in Phase 1a (spatial regression) and
# Phase 1c (avulsion probability model).
#
# Classification scheme follows knowledge base Section 2.3 categories.
# Confinement affects stream power dissipation and lateral adjustment capacity.
# Avulsion susceptibility captures geomorphic predisposition independent of
# discharge — critical for separating lateral migration from avulsion mechanisms
# (see knowledge base Section 3.1 conceptual model).

classify_confinement <- function(bank_notes) {
  #' Classify valley confinement from bank/geology notes.
  #' Returns: "confined", "partly_confined", or "unconfined".
  case_when(
    str_detect(bank_notes, regex("confine.*narrow|narrow.*valley|bedrock.*confine",
                                 ignore_case = TRUE)) ~ "confined",
    str_detect(bank_notes, regex("levee|railroad|road.*embankment|bridge",
                                 ignore_case = TRUE)) ~ "partly_confined",
    str_detect(bank_notes, regex("erodible.*alluvium|wide.*valley|unconfined",
                                 ignore_case = TRUE)) ~ "unconfined",
    TRUE ~ "unclassified"
  )
}

classify_avulsion_susceptibility <- function(avulsion_notes, has_avulsions) {
  #' Classify avulsion susceptibility from AHA notes and observed record.
  #' Categories follow the knowledge base Section 2.3 classification scheme.
  case_when(
    has_avulsions ~ "high_historical",
    str_detect(avulsion_notes, regex("conducive.*throughout|entire",
                                     ignore_case = TRUE)) ~ "conducive_throughout",
    str_detect(avulsion_notes, regex("conducive|favorable",
                                     ignore_case = TRUE)) ~ "conducive_limited",
    str_detect(avulsion_notes, regex("levee.*fail|canal.*fail|infrastructure",
                                     ignore_case = TRUE)) ~ "infrastructure_conditional",
    str_detect(avulsion_notes, regex("low potential|not conducive",
                                     ignore_case = TRUE)) ~ "low",
    TRUE ~ "not_assessed"
  )
}

add_reach_classifications <- function(reach_tbl) {
  #' Add derived categorical covariates to the reach table.
  reach_tbl %>%
    mutate(
      confinement = classify_confinement(bank_notes),
      avulsion_susceptibility = classify_avulsion_susceptibility(
        avulsion_notes, has_avulsions
      )
    )
}

# =============================================================================
# 4. DRAINAGE AREA SCALING
# =============================================================================
# Assign discharge to each reach by interpolating between the three gages
# based on contributing drainage area. Uses a simple power-law scaling:
#   Q_reach = Q_gage * (DA_reach / DA_gage)^alpha
#
# The exponent alpha is calibrated from the three gage pairs. For most
# PNW rivers, alpha ~ 0.8-1.0 for flood peaks (Thomas et al., 1997,
# USGS WRI 97-4277). Regional regressions in Wood et al. (2016, SIR
# 2016-5083) show similar exponents for Idaho/eastern Oregon basins.

estimate_da_exponent <- function(flood_freq_tbl, gage_meta_tbl, cfg = config) {
  #' Estimate the drainage-area scaling exponent (alpha) from Q2 values
  #' at the three gages. Uses log-log regression: log(Q2) ~ log(DA).
  #' Saves the lm object as .rds (non-tabular, justified per data format
  #' standards) and returns the alpha value.

  q2_by_gage <- flood_freq_tbl %>%
    filter(return_period_yr == 2) %>%
    left_join(gage_meta_tbl %>% select(gage_id, drainage_area_sqmi),
              by = "gage_id")

  if (nrow(q2_by_gage) < 2) {
    warning("Fewer than 2 gages with Q2 — using default alpha = ",
            cfg$alpha_default)
    return(cfg$alpha_default)
  }

  # Log-log regression: log(Q) = log(c) + alpha * log(DA)
  fit <- lm(log(q_cfs) ~ log(drainage_area_sqmi), data = q2_by_gage)

  alpha <- coef(fit)[["log(drainage_area_sqmi)"]]
  r2    <- summary(fit)$r.squared

  message(sprintf(
    "DA scaling exponent: alpha = %.3f (R² = %.3f, n = %d gages)",
    alpha, r2, nrow(q2_by_gage)
  ))

  # Save the model object (non-tabular → .rds is justified)
  dir.create(dirname(cfg$da_fit_rds), recursive = TRUE, showWarnings = FALSE)
  write_rds(fit, cfg$da_fit_rds)
  message("DA scaling model saved to: ", cfg$da_fit_rds)

  alpha
}

assign_gage_to_reach <- function(reach_tbl, cfg = config) {
  #' Assign each reach to its nearest (most representative) gage.
  #' Uses the gage_breaks lookup in config.
  #'
  #' NOTE: These breakpoints are approximate and should be refined based
  #' on tributary confluence locations and drainage area accumulation.
  #' The report's RS numbering runs downstream-to-upstream (RS 1 = mouth).
  gage_lookup <- cfg$gage_breaks

  reach_tbl %>%
    mutate(
      assigned_gage = map_chr(rs_num, function(rs) {
        match_row <- gage_lookup %>%
          filter(rs >= rs_min, rs <= rs_max)
        if (nrow(match_row) == 0) return(NA_character_)
        match_row$gage_id[1]
      })
    )
}

estimate_reach_drainage_area <- function(reach_tbl, gage_meta_tbl, cfg = config) {
  #' Estimate contributing drainage area at each reach by linear
  #' interpolation between upstream and downstream gage DA values,
  #' using stream station (longitudinal position) as the interpolant.
  #'
  #' This is a first approximation — a more precise approach would use
  #' GIS-derived drainage area at each reach from a DEM.
  #'
  #' ACTION: If GIS-derived DA values per reach become available,
  #' replace this function with a direct lookup.

  # Build interpolation table: station → DA
  interp_tbl <- cfg$gage_stations %>%
    left_join(gage_meta_tbl %>% select(gage_id, drainage_area_sqmi),
              by = "gage_id") %>%
    arrange(approx_station_ft)

  reach_tbl %>%
    mutate(
      mid_station_ft = (ds_station_ft + us_station_ft) / 2,
      est_drainage_area_sqmi = approx(
        x    = interp_tbl$approx_station_ft,
        y    = interp_tbl$drainage_area_sqmi,
        xout = mid_station_ft,
        rule  = 2  # extrapolate using nearest value at endpoints
      )$y
    )
}

compute_reach_discharge <- function(reach_tbl, flood_freq_tbl,
                                    gage_meta_tbl, alpha) {
  #' Compute reference discharge (Q2) at each reach using DA scaling.
  #' Q_reach = Q_gage * (DA_reach / DA_gage)^alpha

  q2_lookup <- flood_freq_tbl %>%
    filter(return_period_yr == 2) %>%
    select(gage_id, q2_gage_cfs = q_cfs)

  da_lookup <- gage_meta_tbl %>%
    select(gage_id, da_gage_sqmi = drainage_area_sqmi)

  reach_tbl %>%
    left_join(q2_lookup, by = c("assigned_gage" = "gage_id")) %>%
    left_join(da_lookup, by = c("assigned_gage" = "gage_id")) %>%
    mutate(
      q2_reach_cfs = q2_gage_cfs * (est_drainage_area_sqmi / da_gage_sqmi)^alpha
    ) %>%
    select(-q2_gage_cfs, -da_gage_sqmi)
}

# =============================================================================
# 5. UNIT STREAM POWER
# =============================================================================
# Unit stream power (omega, W/m²) is the primary explanatory variable for
# Phase 1a. It integrates discharge magnitude, channel slope, and geometry
# into a single hydraulic forcing metric.
#
# omega = gamma * Q * S / w
#
# where gamma = specific weight of water (9810 N/m³), Q = discharge (m³/s),
# S = channel slope (m/m), w = channel width (m).
#
# Key thresholds from the literature (used in Phase 1d contextualization):
#   ~230 W/m²  — substantial widening credible, slopes <3%
#                (Yochum et al., 2017, USGS SIR 2017-5099)
#   ~300 W/m²  — minimum for major morphological adjustment
#                (Magilligan, 1992, Geomorphology; Miller, 1990)
#   ~480 W/m²  — avulsions and braiding credible
#                (Yochum et al., 2017)
#   ~700 W/m²  — numerous eroded banks very likely
#                (Yochum et al., 2017)
#
# Baker & Costa (1987) established stream power as the fundamental index
# of geomorphic work of floods. Nanson & Hickin (1986) demonstrated the
# empirical link between stream power and lateral migration rates.
# Sholtes et al. (2018) refined the magnitude-frequency context for
# threshold-based interpretations in alluvial channels.

compute_unit_stream_power <- function(reach_tbl, cfg = config) {
  #' Compute unit stream power (omega, W/m²) at Q2 for each reach.
  #' All inputs converted to SI: Q in m³/s, w in m, S dimensionless.
  reach_tbl %>%
    mutate(
      q2_cms       = q2_reach_cfs * cfg$cfs_to_cms,
      width_m      = avg_width_ft * cfg$ft_to_m,
      # Unit stream power (W/m²)
      omega_wm2    = cfg$gamma * q2_cms * slope / width_m,
      # Total stream power (W/m) for reference
      omega_total  = cfg$gamma * q2_cms * slope
    )
}

# =============================================================================
# 6. PIPELINE: BUILD COMPLETE REACH TABLE
# =============================================================================

build_complete_reach_table <- function(cfg = config) {
  #' Master pipeline: import, classify, scale, compute, and save.
  #' Reads inputs from paths in config; writes .csv output.

  # ---- Load upstream outputs ----
  gage_meta  <- read_csv(cfg$gage_meta_path,  show_col_types = FALSE)
  flood_freq <- read_csv(cfg$flood_freq_path, show_col_types = FALSE)

  message("--- Importing CMZ summary data ---")
  reach_tbl <- build_reach_table(cfg$xlsx_path)

  message("--- Classifying reaches ---")
  reach_tbl <- reach_tbl %>%
    add_reach_classifications()

  message("--- Assigning gages and estimating drainage areas ---")
  reach_tbl <- reach_tbl %>%
    assign_gage_to_reach(cfg) %>%
    estimate_reach_drainage_area(gage_meta, cfg)

  message("--- Estimating DA scaling exponent ---")
  alpha <- estimate_da_exponent(flood_freq, gage_meta, cfg)

  message("--- Computing reach discharge (Q2) ---")
  reach_tbl <- reach_tbl %>%
    compute_reach_discharge(flood_freq, gage_meta, alpha)

  message("--- Computing unit stream power ---")
  reach_tbl <- reach_tbl %>%
    compute_unit_stream_power(cfg)

  # ---- Diagnostic summary ----
  message("\n--- Reach Table Summary ---")
  reach_tbl %>%
    select(rs, avg_width_ft, slope, sinuosity, median_rate_cw,
           confinement, q2_reach_cfs, omega_wm2) %>%
    print(n = 39)

  message("\n--- Stream Power Summary by Confinement ---")
  reach_tbl %>%
    group_by(confinement) %>%
    summarize(
      n         = n(),
      omega_med = median(omega_wm2, na.rm = TRUE),
      omega_max = max(omega_wm2, na.rm = TRUE),
      rate_med  = median(median_rate_cw, na.rm = TRUE),
      .groups   = "drop"
    ) %>%
    print()

  # ---- Save as .csv (portable, human-readable) ----
  dir.create(dirname(cfg$reach_attr_csv), recursive = TRUE, showWarnings = FALSE)
  write_csv(reach_tbl, cfg$reach_attr_csv)
  message("--- Reach table saved to: ", cfg$reach_attr_csv, " ---")

  reach_tbl
}

# =============================================================================
# EXECUTE
# Run after 01_hydrology_acquisition.R has been executed and .csv outputs exist.
# reach_tbl <- build_complete_reach_table()
# =============================================================================
