# =============================================================================
# 01_hydrology_acquisition.R
# Discharge-Channel Migration Analysis
# Phase 1: Acquire and organize USGS discharge records
# =============================================================================
#
# Purpose: Pull daily and peak flow data from USGS gages, run Bulletin 17C
#          flood frequency analysis via peakfq::emafit() (EMA with MGBT),
#          and build a tidy hydrologic record ready for downstream analysis.
#
# Flood Frequency Method:
#   Bulletin 17C (England et al., 2019) via peakfq::emafit()
#   - Expected Moments Algorithm (EMA) for LP3 fitting
#   - Multiple Grubbs-Beck Test (MGBT) for low outlier screening
#   - Weighted skew using regional values (looked up via read_skew_map_pt)
#   - PSF specification files generated for documentation/reproducibility
#
# Usage:   Edit the CONFIG section below for your gage network, then either:
#            (a) source() and call run_hydrology_acquisition(config)
#            (b) step through interactively — config and all functions are
#                available at top level for testing individual pieces.
#
# Output:  .csv files (gage_metadata, daily_flows, peak_flows, flood_frequency,
#          site_info, regional_skew) in config$output_dir.
#          .rds for peakfq_results (non-tabular nested list).
#          PSF files in config$output_dir/psf/ for audit trail.
#
# Style:   Follows Tidyverse & Functional Programming Guidelines
#          (Tidyverse_Functional_Programming_Guidelines_for_temperheic.md)
# =============================================================================

library(tidyverse)
library(dataRetrieval)   # USGS data access
library(lubridate)       # date handling
library(peakfq)          # B17C flood frequency (EMA/MGBT)

# =============================================================================
# CONFIG — edit these values for a different river system
# =============================================================================

config <- list(
  
  # ---- Gage network ----
  # One row per gage. position is a label used for reach assignment in 02.
  # drainage_area_sqmi: verified against NWIS site descriptions at runtime.
  gages = tribble(
    ~gage_id,    ~gage_name,                                      ~position,      ~drainage_area_sqmi,
    "14020000",  "Umatilla R above Meacham Cr nr Gibbon",         "upstream",     131,
    "14020850",  "Umatilla R at W Reservation Bndy nr Pendleton", "mid",          441,
    "14033500",  "Umatilla R near Umatilla",                      "downstream",   2290
  ),
  
  # ---- Retrieval parameters ----
  daily_start_date = "1950-01-01",
  daily_end_date   = "",               # "" = through present
  
  # ---- Flood frequency (B17C) settings ----
  # Annual exceedance probabilities to compute
  aeps = c(0.5, 0.2, 0.1, 0.04, 0.02, 0.01, 0.005, 0.002),
  
  # EMA configuration
  ema_confidence = 0.90,               # confidence interval coverage
  ema_weight_opt = "HWN",              # skew weighting algorithm
  
  # Regulation-flagged gages — emit a warning during analysis.
  # Set to character(0) if no gages are regulated.
  regulated_gage_ids = "14033500",
  
  # ---- Output ----
  output_dir = "data/"
)


# =============================================================================
# 1. ATOMIC DATA RETRIEVAL FUNCTIONS
# =============================================================================
# Each function does one thing: pull a specific data type for a single gage.
# They return tidy tibbles with consistent column naming.

pull_daily_flow <- function(gage_id, start_date = "1950-01-01", end_date = "") {
  #' Retrieve daily mean discharge from NWIS for a single gage.
  #' Returns a tibble with date, daily_q_cfs, and qualifying codes.
  readNWISdv(
    siteNumbers  = gage_id,
    parameterCd  = "00060",
    startDate    = start_date,
    endDate      = end_date
  ) %>%
    renameNWISColumns() %>%
    as_tibble() %>%
    select(
      gage_id     = site_no,
      date        = Date,
      daily_q_cfs = Flow,
      q_code      = Flow_cd
    )
}

pull_peak_flow <- function(gage_id) {
  #' Retrieve annual instantaneous peak discharge from NWIS for a single gage.
  #' Returns a tibble with water year, peak date, peak_q_cfs, and qualification.
  readNWISpeak(siteNumbers = gage_id) %>%
    as_tibble() %>%
    select(
      gage_id    = site_no,
      peak_date  = peak_dt,
      peak_q_cfs = peak_va,
      peak_code  = peak_cd,
      gage_ht_ft = gage_ht
    ) %>%
    mutate(
      water_year = if_else(
        month(peak_date) >= 10,
        year(peak_date) + 1L,
        year(peak_date)
      )
    )
}

pull_site_info <- function(gage_id) {
  #' Pull site metadata including drainage area from NWIS.
  #' Used to verify/update drainage_area_sqmi in gage config.
  readNWISsite(siteNumbers = gage_id) %>%
    as_tibble() %>%
    select(
      gage_id            = site_no,
      station_name       = station_nm,
      drainage_area      = drain_area_va,
      contrib_drain_area = contrib_drain_area_va,
      latitude           = dec_lat_va,
      longitude          = dec_long_va,
      datum              = alt_va
    )
}


# =============================================================================
# 2. BATCH RETRIEVAL VIA PURRR
# =============================================================================
# Map retrieval functions across all gages. Uses safely() to handle any
# individual gage failures without crashing the whole pull.

pull_all_gage_data <- function(gage_ids, start_date = "1950-01-01",
                               end_date = "") {
  #' Master retrieval function: pulls daily, peak, and site info for all gages.
  #' Returns a named list of three combined tibbles.
  
  message("--- Pulling site info ---")
  site_info <- gage_ids %>%
    map(safely(pull_site_info)) %>%
    set_names(gage_ids) %>%
    { list(
      data   = map(., "result") %>% compact() %>% bind_rows(),
      errors = map(., "error") %>% discard(is.null)
    )}
  
  if (length(site_info$errors) > 0) {
    warning("Site info pull failed for: ",
            paste(names(site_info$errors), collapse = ", "))
  }
  
  message("--- Pulling daily flows (this may take a minute) ---")
  daily_flows <- gage_ids %>%
    map(safely(~ pull_daily_flow(.x, start_date = start_date,
                                 end_date = end_date))) %>%
    set_names(gage_ids) %>%
    { list(
      data   = map(., "result") %>% compact() %>% bind_rows(),
      errors = map(., "error") %>% discard(is.null)
    )}
  
  message("--- Pulling peak flows ---")
  peak_flows <- gage_ids %>%
    map(safely(pull_peak_flow)) %>%
    set_names(gage_ids) %>%
    { list(
      data   = map(., "result") %>% compact() %>% bind_rows(),
      errors = map(., "error") %>% discard(is.null)
    )}
  
  list(
    site_info   = site_info$data,
    daily_flows = daily_flows$data,
    peak_flows  = peak_flows$data,
    errors      = list(
      site  = site_info$errors,
      daily = daily_flows$errors,
      peak  = peak_flows$errors
    )
  )
}


# =============================================================================
# 3. FLOOD FREQUENCY ANALYSIS (BULLETIN 17C VIA PEAKFQ)
# =============================================================================
# Compute flood quantiles at each gage using the Expected Moments Algorithm
# (EMA) with Multiple Grubbs-Beck Test (MGBT) for low outlier screening,
# following USGS Bulletin 17C (England et al., 2019).
#
# Regional skew is looked up automatically from the B17C generalized skew
# map (SIR 2016-5083) via peakfq::read_skew_map_pt() using gage coordinates.

build_emafit_input <- function(peak_tbl) {
  #' Convert a peak flow tibble (from pull_peak_flow) into the QT dataframe
  #' that emafit() expects.
  #'
  #' For standard systematic peaks (no censoring, no historic information):
  #'   ql = qu = peak_va  (exact observation)
  #'   tl = 1             (gage can detect flows >= 1 cfs)
  #'   tu = 1e20          (no upper perception limit)
  #'   dtype = 0          (not a historic peak)
  #'
  #' Peak qualification codes that modify flow intervals:
  #'   Code 1: max daily average (not instantaneous) -> right-censor: qu = 1e20
  #'   Code 4: discharge less than indicated -> left-censor: ql = 0, qu = peak_va
  #'   Code 8: discharge greater than indicated -> right-censor: qu = 1e20
  #'   Codes 2, 5, 6: estimates or regulated — treated as exact for now
  #'
  #' Returns the QT dataframe ready for emafit().
  
  peak_tbl %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0) %>%
    mutate(
      ql = case_when(
        peak_code == "4" ~ 0,           # less than indicated
        TRUE             ~ peak_q_cfs   # exact or estimated
      ),
      qu = case_when(
        peak_code == "1" ~ 1e20,        # max daily avg, true peak unknown above
        peak_code == "8" ~ 1e20,        # greater than indicated
        TRUE             ~ peak_q_cfs   # exact or estimated
      ),
      tl    = 1,                        # lower perception threshold (cfs)
      tu    = 1e20,                     # upper perception threshold
      dtype = 0L                        # systematic record (no historic peaks)
    ) %>%
    select(ql, qu, tl, tu, dtype, peak_WY = water_year) %>%
    as.data.frame()
}

lookup_regional_skew <- function(site_info_tbl) {
  #' Look up regional skew and SE for each gage from the B17C generalized
  #' skew map (SIR 2016-5083) using peakfq::read_skew_map_pt().
  #'
  #' Returns a tibble with gage_id, gen_skew, skew_se, and source citation.
  
  site_info_tbl %>%
    select(gage_id, latitude, longitude) %>%
    mutate(
      skew_info = map2(latitude, longitude, ~ {
        read_skew_map_pt(.x, .y)
      })
    ) %>%
    unnest(skew_info) %>%
    select(
      gage_id,
      gen_skew    = GenSkew,
      skew_se     = SkewSE,
      skew_source = MapSkewSourceText
    )
}

run_emafit_single <- function(peak_tbl, gen_skew, skew_se,
                              aeps       = c(0.5, 0.2, 0.1, 0.04, 0.02, 0.01,
                                             0.005, 0.002),
                              confidence = 0.90,
                              weight_opt = "HWN") {
  #' Run emafit for a single gage's peak record.
  #'
  #' @param peak_tbl   Tibble of peaks from pull_peak_flow() for one gage.
  #' @param gen_skew   Regional generalized skew coefficient.
  #' @param skew_se    Standard error of regional skew.
  #' @param aeps       Annual exceedance probabilities to estimate.
  #' @param confidence Confidence interval coverage (0-1).
  #' @param weight_opt Skew weighting algorithm ("HWN", "INV", or "ERL").
  #'
  #' @return Named list with elements: lp3 (moments), qnt (frequency curve),
  #'         emp (EMA data representation), mgb (MGBT p-values).
  
  QT <- build_emafit_input(peak_tbl)
  
  if (nrow(QT) < 10) {
    warning("Fewer than 10 peaks for gage ",
            unique(peak_tbl$gage_id), " — results unreliable")
  }
  
  # emafit expects MSE (variance), not SE — square the SE
  skew_mse <- skew_se^2
  
  gage_id <- unique(peak_tbl$gage_id)
  
  result <- emafit(
    QT        = QT,
    LOthresh  = 0,             # triggers MGBT (values <= 1e-99 -> MGBT)
    rG        = gen_skew,      # regional skew
    rGmse     = skew_mse,      # MSE of regional skew
    eps       = confidence,    # confidence interval coverage
    weightOpt = weight_opt,    # skew weighting algorithm
    AEPs      = aeps,
    site_no   = gage_id,
    quietly   = TRUE
  )
  
  # Name the list elements consistently
  list(
    lp3 = result[[1]] %>% mutate(gage_id = gage_id),
    qnt = result[[2]] %>% mutate(gage_id = gage_id,
                                 return_period_yr = 1 / EXC_Prob),
    emp = result[[3]] %>% mutate(gage_id = gage_id),
    mgb = result[[4]] %>% mutate(gage_id = gage_id)
  )
}

run_emafit_all_gages <- function(peak_flows_tbl, skew_tbl,
                                 aeps       = c(0.5, 0.2, 0.1, 0.04, 0.02,
                                                0.01, 0.005, 0.002),
                                 confidence = 0.90,
                                 weight_opt = "HWN") {
  #' Run B17C flood frequency analysis for all gages via emafit().
  #' Uses purrr::map with safely() for resilient iteration.
  #'
  #' @param peak_flows_tbl  Combined peak flow tibble (all gages).
  #' @param skew_tbl        Regional skew lookup table from lookup_regional_skew().
  #' @param aeps            Annual exceedance probabilities to estimate.
  #' @param confidence      Confidence interval coverage.
  #' @param weight_opt      Skew weighting algorithm.
  #'
  #' @return Named list with combined tibbles: lp3, qnt, emp, mgb.
  
  gage_ids <- unique(peak_flows_tbl$gage_id)
  
  results <- gage_ids %>%
    set_names() %>%
    map(safely(function(gid) {
      peaks <- peak_flows_tbl %>% filter(gage_id == gid)
      skew  <- skew_tbl %>% filter(gage_id == gid)
      
      run_emafit_single(
        peak_tbl   = peaks,
        gen_skew   = skew$gen_skew,
        skew_se    = skew$skew_se,
        aeps       = aeps,
        confidence = confidence,
        weight_opt = weight_opt
      )
    }))
  
  # Separate successes and errors
  errors <- results %>% map("error") %>% discard(is.null)
  if (length(errors) > 0) {
    warning("emafit failed for: ", paste(names(errors), collapse = ", "))
    walk(errors, ~ message("  Error: ", .x$message))
  }
  
  ok <- results %>% map("result") %>% compact()
  
  # Combine across gages into tidy tibbles
  list(
    lp3 = ok %>% map("lp3") %>% bind_rows(),
    qnt = ok %>% map("qnt") %>% bind_rows(),
    emp = ok %>% map("emp") %>% bind_rows(),
    mgb = ok %>% map("mgb") %>% bind_rows()
  )
}


# =============================================================================
# 3b. PSF FILE GENERATION (DOCUMENTATION / REPRODUCIBILITY)
# =============================================================================
# Generate PeakFQ specification files for each gage so the analysis can be
# reproduced in the Shiny app or standalone PeakFQ. These are written to
# disk alongside the other outputs.

write_psf_file <- function(gage_id, peak_tbl, gen_skew, skew_se,
                           output_dir = "data/psf/") {
  #' Write a PSF specification file for a single gage.
  #'
  #' Uses NWIS RDB format for input data, weighted skew, and MGBT.
  #' The PSF file can be passed to peakfq::peakfq() or loaded in the
  #' PeakFQ Shiny app for interactive review.
  
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  rdb_file <- file.path(output_dir, paste0(gage_id, "_peaks.rdb"))
  
  peaks_clean <- peak_tbl %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)
  
  beg_year <- min(peaks_clean$water_year, na.rm = TRUE)
  end_year <- max(peaks_clean$water_year, na.rm = TRUE)
  
  psf_lines <- c(
    paste0("I NWIS ", rdb_file),
    paste0("O File ", file.path(output_dir, paste0(gage_id, "_output.txt"))),
    "O Plot Style Graphics",
    "O Plot Format PNG",
    "O ConfInterval 0.9",
    "O EMA YES",
    paste0("Station ", gage_id, ".00"),
    paste0("     PCPT_Thresh ", beg_year, " ", end_year, " 0 1E+20  DEFAULT"),
    "     SkewOpt Weighted",
    paste0("     GenSkew ", format(gen_skew, digits = 6)),
    paste0("     SkewSE ", format(skew_se, digits = 4)),
    "     LOType MGBT"
  )
  
  psf_file <- file.path(output_dir, paste0(gage_id, ".psf"))
  writeLines(psf_lines, psf_file)
  message("  PSF written: ", psf_file)
  
  invisible(psf_file)
}

write_all_psf_files <- function(peak_flows_tbl, skew_tbl,
                                output_dir = "data/psf/") {
  #' Generate PSF specification files for all gages.
  
  gage_ids <- unique(peak_flows_tbl$gage_id)
  
  gage_ids %>%
    walk(function(gid) {
      peaks <- peak_flows_tbl %>% filter(gage_id == gid)
      skew  <- skew_tbl %>% filter(gage_id == gid)
      write_psf_file(gid, peaks, skew$gen_skew, skew$skew_se, output_dir)
    })
  
  message("--- All PSF files written to: ", output_dir, " ---")
}


# =============================================================================
# 4. DAILY FLOW SUMMARY METRICS
# =============================================================================

summarize_daily_flows <- function(daily_flows_tbl) {
  #' Compute per-gage summary statistics from the daily flow record.
  daily_flows_tbl %>%
    group_by(gage_id) %>%
    summarize(
      record_start     = min(date, na.rm = TRUE),
      record_end       = max(date, na.rm = TRUE),
      n_days           = n(),
      n_missing        = sum(is.na(daily_q_cfs)),
      pct_complete     = 100 * (1 - n_missing / n_days),
      mean_daily_cfs   = mean(daily_q_cfs, na.rm = TRUE),
      median_daily_cfs = median(daily_q_cfs, na.rm = TRUE),
      sd_daily_cfs     = sd(daily_q_cfs, na.rm = TRUE),
      max_daily_cfs    = max(daily_q_cfs, na.rm = TRUE),
      .groups = "drop"
    )
}


# =============================================================================
# 5. WATER YEAR ANNOTATION
# =============================================================================

annotate_water_year <- function(daily_flows_tbl) {
  #' Add water_year column to daily flow tibble.
  #' Water year starts Oct 1 (e.g., WY 2020 = Oct 2019 through Sep 2020).
  daily_flows_tbl %>%
    mutate(
      water_year = if_else(
        month(date) >= 10,
        year(date) + 1L,
        year(date)
      )
    )
}


# =============================================================================
# 6. SAVE HELPERS
# =============================================================================

save_hydro_outputs <- function(gage_metadata, daily_flows, peak_flows,
                               flood_freq, site_info, skew_tbl,
                               pfq_results, output_dir) {
  #' Write all pipeline outputs to output_dir.
  #' Per NOTE_data_format_standards.md:
  #'   .csv for all tabular outputs
  #'   .rds only for peakfq_results (non-tabular nested list with EMA internals)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(gage_metadata, file.path(output_dir, "gage_metadata.csv"))
  write_csv(daily_flows,   file.path(output_dir, "daily_flows.csv"))
  write_csv(peak_flows,    file.path(output_dir, "peak_flows.csv"))
  write_csv(flood_freq,    file.path(output_dir, "flood_frequency.csv"))
  write_csv(site_info,     file.path(output_dir, "site_info.csv"))
  write_csv(skew_tbl,      file.path(output_dir, "regional_skew.csv"))
  
  # peakfq_results is a nested list (lp3, qnt, emp, mgb tibbles) — .rds justified
  write_rds(pfq_results,   file.path(output_dir, "peakfq_results.rds"))
  
  message("--- All outputs saved to: ", output_dir, " ---")
  message("    (.csv for tabular data, .rds for peakfq_results only)")
}


# =============================================================================
# 7. EXECUTION PIPELINE
# =============================================================================

run_hydrology_acquisition <- function(cfg = config) {
  #' Execute the full hydrology acquisition pipeline:
  #'   1. Pull daily, peak, and site data from NWIS
  #'   2. Verify drainage areas
  #'   3. Look up regional skew from B17C generalized skew map
  #'   4. Run emafit() flood frequency for each gage
  #'   5. Generate PSF files for reproducibility
  #'   6. Save all outputs
  #'
  #' @param cfg  Config list (defaults to the top-level `config` object).
  
  output_dir <- cfg$output_dir
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # ---- Pull all gage data ----
  gage_ids <- cfg$gages$gage_id
  raw_data <- pull_all_gage_data(
    gage_ids,
    start_date = cfg$daily_start_date,
    end_date   = cfg$daily_end_date
  )
  
  # ---- QA: Verify drainage areas against NWIS metadata ----
  message("\n--- Drainage Area Verification ---")
  if (nrow(raw_data$site_info) > 0) {
    da_check <- cfg$gages %>%
      left_join(
        raw_data$site_info %>% select(gage_id, nwis_da = drainage_area),
        by = "gage_id"
      ) %>%
      mutate(da_match = near(drainage_area_sqmi, nwis_da, tol = 5))
    
    print(da_check %>% select(gage_id, position, drainage_area_sqmi,
                              nwis_da, da_match))
    
    gage_metadata_verified <- da_check %>%
      mutate(drainage_area_sqmi = coalesce(nwis_da, drainage_area_sqmi)) %>%
      select(gage_id, gage_name, position, drainage_area_sqmi)
  } else {
    message("No site info retrieved — using config drainage areas.")
    message("ACTION REQUIRED: Verify drainage areas manually from NWIS.")
    gage_metadata_verified <- cfg$gages
  }
  
  # ---- Annotate daily flows with water year ----
  daily_flows <- raw_data$daily_flows %>%
    annotate_water_year()
  
  # ---- Look up regional skew for each gage ----
  message("\n--- Regional Skew Lookup (B17C Generalized Skew Map) ---")
  skew_tbl <- lookup_regional_skew(raw_data$site_info)
  print(skew_tbl)
  
  # ---- Run B17C flood frequency via emafit ----
  message("\n--- Running Bulletin 17C Flood Frequency (emafit) ---")
  pfq_results <- run_emafit_all_gages(
    raw_data$peak_flows,
    skew_tbl,
    aeps       = cfg$aeps,
    confidence = cfg$ema_confidence,
    weight_opt = cfg$ema_weight_opt
  )
  
  # ---- Print key results ----
  message("\n--- LP3 Moments Summary ---")
  pfq_results$lp3 %>%
    select(gage_id, BegYear, EndYear, RecordLength, SkewOption,
           Mean, StandDev, Skew, PILF_Method, PILFs) %>%
    print()
  
  message("\n--- Flood Frequency Estimates ---")
  pfq_results$qnt %>%
    filter(return_period_yr %in% c(2, 5, 10, 25, 50, 100)) %>%
    select(gage_id, return_period_yr, Estimate, Conf_Low, Conf_Up) %>%
    pivot_wider(
      names_from  = return_period_yr,
      values_from = c(Estimate, Conf_Low, Conf_Up),
      names_glue  = "{.value}_Q{return_period_yr}"
    ) %>%
    print()
  
  # ---- Regulation warning for flagged gages ----
  reg_ids <- intersect(cfg$regulated_gage_ids,
                       unique(raw_data$peak_flows$gage_id))
  if (length(reg_ids) > 0) {
    for (rid in reg_ids) {
      n_reg <- raw_data$peak_flows %>%
        filter(gage_id == rid, peak_code %in% c("5", "6")) %>%
        nrow()
      if (n_reg > 0) {
        message("\n*** WARNING: Gage ", rid, " has ", n_reg,
                " peaks coded as regulation-affected (codes 5/6). ***")
        message("*** B17C results should be interpreted with caution. ***\n")
      }
    }
  }
  
  # ---- Generate PSF files for reproducibility ----
  message("--- Generating PSF specification files ---")
  write_all_psf_files(raw_data$peak_flows, skew_tbl,
                      output_dir = file.path(output_dir, "psf"))
  
  # ---- Summarize daily flow records ----
  daily_summary <- summarize_daily_flows(daily_flows)
  message("\n--- Daily Flow Record Summary ---")
  print(daily_summary)
  
  # ---- Build backward-compatible flood_freq tibble ----
  # This matches the format expected by 02_reach_attributes_and_scaling.R:
  #   gage_id, return_period_yr, q_cfs, n_years_record, distribution
  flood_freq <- pfq_results$qnt %>%
    transmute(
      gage_id,
      return_period_yr,
      q_cfs          = Estimate,
      q_cfs_low      = Conf_Low,
      q_cfs_high     = Conf_Up,
      variance_log   = Variance,
      n_years_record = pfq_results$lp3$RecordLength[
        match(gage_id, pfq_results$lp3$gage_id)
      ],
      distribution   = "LP3-EMA-B17C"
    )
  
  # ---- Save outputs ----
  save_hydro_outputs(
    gage_metadata = gage_metadata_verified,
    daily_flows   = daily_flows,
    peak_flows    = raw_data$peak_flows,
    flood_freq    = flood_freq,
    site_info     = raw_data$site_info,
    skew_tbl      = skew_tbl,
    pfq_results   = pfq_results,
    output_dir    = output_dir
  )
  
  # Return for interactive use
  list(
    gage_metadata  = gage_metadata_verified,
    daily_flows    = daily_flows,
    peak_flows     = raw_data$peak_flows,
    flood_freq     = flood_freq,
    pfq_results    = pfq_results,
    skew_tbl       = skew_tbl,
    site_info      = raw_data$site_info,
    daily_summary  = daily_summary
  )
}


# =============================================================================
# EXECUTE
# =============================================================================
# Full pipeline:
  hydro_data <- run_hydrology_acquisition(config)
#
# --- Interactive testing ---
# Config is already in your environment after source(). Test any function:
#   raw      <- pull_all_gage_data(config$gages$gage_id,
#                                  start_date = config$daily_start_date)
#   peaks    <- raw$peak_flows
#   skew_tbl <- lookup_regional_skew(raw$site_info)
#   pfq      <- run_emafit_all_gages(peaks, skew_tbl, aeps = config$aeps)
#   QT       <- build_emafit_input(peaks %>% filter(gage_id == "14020000"))
#   daily    <- raw$daily_flows %>% annotate_water_year()
# =============================================================================
