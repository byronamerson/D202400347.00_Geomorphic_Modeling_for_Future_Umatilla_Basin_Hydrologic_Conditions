# =============================================================================
# 01b_tributary_dam_acquisition.R
# Discharge-Channel Migration Analysis
# Tributary/Dam Data Acquisition for Regulation Analysis
# =============================================================================
#
# Purpose: Acquire tributary discharge records from USGS NWIS and USBR
#          Hydromet to support natural flow reconstruction at a regulated
#          mainstem gage. Retrieves below-dam release, above-reservoir
#          natural inflow, and reservoir storage data.
#
# Usage:   Edit the CONFIG section below for your tributary/dam system,
#          then either:
#            (a) source() and call run_tributary_acquisition(config)
#            (b) step through interactively — config and all functions are
#                available at top level for testing individual pieces.
#
# Output:  .csv files in config$output_dir:
#            {prefix}_daily_flows.csv       — composite below-dam record
#            {prefix}_peak_flows.csv        — USGS annual peaks w/ dam_period
#            {prefix}_site_info.csv         — USGS site metadata
#            {prefix}_above_reservoir_daily.csv — natural inflow (Hydromet)
#            {prefix}_reservoir_storage.csv — reservoir storage (Hydromet)
#            {prefix}_record_summary.csv   — record summary by source/period
#
# Style:   Follows Tidyverse & Functional Programming Guidelines
#          (Tidyverse_Functional_Programming_Guidelines_for_temperheic.md)
# =============================================================================

library(tidyverse)
library(dataRetrieval)   # USGS NWIS access
library(lubridate)       # date handling
library(httr)            # HTTP requests for USBR Hydromet

# =============================================================================
# CONFIG — edit these values for a different tributary/dam system
# =============================================================================

config <- list(
  
  # ---- USGS gage below dam ----
  usgs_gage_id   = "14023500",
  usgs_gage_name = "McKay Cr nr Pendleton",
  
  # ---- USBR Hydromet stations ----
  # Each entry: station code, parameter code, role in the analysis
  hydromet_stations = tribble(
    ~station_id, ~pcode, ~station_name,                          ~role,
    "MCKO",      "QD",   "McKay Cr nr Pendleton (USBR)",         "below_dam",
    "MYKO",      "QD",   "McKay Cr nr Pilot Rock (USBR)",        "above_reservoir",
    "MCK",       "AF",   "McKay Reservoir nr Pendleton (USBR)",  "reservoir_storage"
  ),
  
  # ---- Dam construction period ----
  # Used to classify records as pre_dam / construction / post_dam
  dam_start_year = 1923L,
  dam_end_year   = 1927L,
  
  # ---- Retrieval parameters ----
  usgs_start_date    = "1900-01-01",
  hydromet_start_date = "1980-01-01",
  
  # ---- Output ----
  output_dir    = "data/",
  output_prefix = "mckay"         # prefixed to all output filenames
)


# =============================================================================
# 1. USGS NWIS RETRIEVAL
# =============================================================================
# Generic functions that accept a gage_id argument — same pattern as 01.

pull_usgs_daily <- function(gage_id, start_date = "1900-01-01", end_date = "") {
  #' Retrieve daily mean discharge from NWIS for a single gage.
  #' Returns a tibble with date, daily_q_cfs, and qualifying codes.
  readNWISdv(
    siteNumbers = gage_id,
    parameterCd = "00060",
    startDate   = start_date,
    endDate     = end_date
  ) %>%
    renameNWISColumns() %>%
    as_tibble() %>%
    select(
      gage_id     = site_no,
      date        = Date,
      daily_q_cfs = Flow,
      q_code      = Flow_cd
    ) %>%
    mutate(source = "usgs_nwis")
}

pull_usgs_peaks <- function(gage_id, dam_start_year, dam_end_year) {
  #' Retrieve annual instantaneous peak discharge from NWIS.
  #' Annotates each peak with dam_period based on dam construction years.
  #'
  #' @param gage_id        USGS site number
  #' @param dam_start_year First year of dam construction
  #' @param dam_end_year   Year dam construction was completed
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
      ),
      dam_period = case_when(
        water_year <= dam_start_year ~ "pre_dam",
        water_year <= dam_end_year   ~ "construction",
        TRUE                         ~ "post_dam"
      ),
      source = "usgs_nwis"
    )
}

pull_usgs_site <- function(gage_id) {
  #' Pull site metadata including drainage area from NWIS.
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
# 2. USBR HYDROMET RETRIEVAL
# =============================================================================
# The PNW Hydromet daily data endpoint is:
#   https://www.usbr.gov/pn-bin/daily.pl
#
# Returns clean CSV with columns: DateTime, {station}_{pcode}
#
# Note: httr::GET() with duplicate parameter names (year, month, day for
# start and end) works because the CGI expects positional pairs. R's list
# keeps all entries; httr serializes them in order.

pull_hydromet_daily <- function(station, pcode,
                                start_date = "1980-01-01",
                                end_date   = format(Sys.Date(), "%Y-%m-%d")) {
  #' Pull daily data from USBR PNW Hydromet via /pn-bin/daily.pl.
  #' Returns a tidy tibble with date and value columns.
  #'
  #' @param station Hydromet CBTT station code (e.g., "MCKO", "MYKO", "MCK")
  #' @param pcode   Parameter code: "QD" = daily avg discharge (cfs),
  #'                "AF" = reservoir storage (acre-feet), "GD" = gage height (ft)
  #' @param start_date Start date as "YYYY-MM-DD"
  #' @param end_date   End date as "YYYY-MM-DD"
  sd <- as.Date(start_date)
  ed <- as.Date(end_date)
  
  resp <- GET(
    url = "https://www.usbr.gov/pn-bin/daily.pl",
    query = list(
      station = station,
      format  = "csv",
      year = year(sd),  month = month(sd),  day = day(sd),
      year = year(ed),  month = month(ed),  day = day(ed),
      pcode = pcode
    )
  )
  
  if (http_error(resp)) {
    warning("Hydromet daily.pl query failed for ", station, "/", pcode,
            ": HTTP ", status_code(resp))
    return(tibble(
      gage_id = character(), date = as.Date(character()),
      daily_q_cfs = numeric(), q_code = character(),
      source = character()
    ))
  }
  
  raw_text <- content(resp, as = "text", encoding = "UTF-8")
  
  # Parse CSV — column 1 is DateTime, column 2 is the value
  read_csv(I(raw_text), show_col_types = FALSE) %>%
    transmute(
      gage_id     = station,
      date        = as.Date(DateTime),
      daily_q_cfs = .[[2]],
      q_code      = NA_character_,
      source      = "usbr_hydromet"
    ) %>%
    filter(!is.na(date))
}

pull_hydromet_stations <- function(stations_tbl, start_date = "1980-01-01") {
  #' Pull all Hydromet stations defined in a config tibble.
  #' Returns a named list keyed by station_id (lowercased).
  #'
  #' @param stations_tbl  Tibble with columns: station_id, pcode, station_name, role
  #' @param start_date    Earliest date to request
  
  results <- pmap(stations_tbl, function(station_id, pcode, ...) {
    message("  Pulling ", station_id, " (", pcode, ")...")
    result <- tryCatch(
      pull_hydromet_daily(
        station    = station_id,
        pcode      = pcode,
        start_date = start_date
      ),
      error = function(e) {
        warning("Failed to pull ", station_id, ": ", e$message)
        tibble()
      }
    )
    message("    ", nrow(result), " records",
            if (nrow(result) > 0) {
              paste0(", ", min(result$date), " to ", max(result$date))
            } else {
              " (empty)"
            })
    result
  })
  
  set_names(results, tolower(stations_tbl$station_id))
}


# =============================================================================
# 3. COMPOSITE ASSEMBLY
# =============================================================================
# Stitch together USGS and Hydromet records into a single, continuous
# below-dam discharge record. Priority: USGS > Hydromet (identical during
# overlap, but USGS is the published/reviewed source).

assemble_composite_daily <- function(usgs_daily, hydromet_daily) {
  #' Combine USGS and Hydromet daily flow records.
  #' Where records overlap, USGS takes priority.
  bind_rows(usgs_daily, hydromet_daily) %>%
    arrange(date) %>%
    group_by(date) %>%
    slice_min(
      order_by = factor(source, levels = c("usgs_nwis", "usbr_hydromet")),
      n = 1, with_ties = FALSE
    ) %>%
    ungroup()
}

annotate_dam_period <- function(daily_tbl, dam_start_year, dam_end_year) {
  #' Add dam_period and water_year columns to daily flow tibble.
  #'
  #' @param daily_tbl       Tibble with a date column
  #' @param dam_start_year  First year of dam construction
  #' @param dam_end_year    Year dam construction was completed
  daily_tbl %>%
    mutate(
      water_year = if_else(
        month(date) >= 10,
        year(date) + 1L,
        year(date)
      ),
      dam_period = case_when(
        water_year <= dam_start_year ~ "pre_dam",
        water_year <= dam_end_year   ~ "construction",
        TRUE                         ~ "post_dam"
      )
    )
}

summarize_record <- function(daily_tbl) {
  #' Summarize an assembled daily record by source and dam period.
  daily_tbl %>%
    group_by(source, dam_period) %>%
    summarize(
      record_start   = min(date, na.rm = TRUE),
      record_end     = max(date, na.rm = TRUE),
      n_days         = n(),
      n_missing      = sum(is.na(daily_q_cfs)),
      pct_complete   = 100 * (1 - n_missing / n_days),
      mean_daily_cfs = mean(daily_q_cfs, na.rm = TRUE),
      max_daily_cfs  = max(daily_q_cfs, na.rm = TRUE),
      .groups = "drop"
    )
}


# =============================================================================
# 4. SAVE HELPERS
# =============================================================================

save_tributary_outputs <- function(composite_daily, peaks, site_info,
                                   above_reservoir_daily, reservoir_storage,
                                   record_summary, output_dir, prefix) {
  #' Write all pipeline outputs as .csv to output_dir.
  #' Per NOTE_data_format_standards.md: .csv for all tabular outputs.
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(composite_daily,      file.path(output_dir, paste0(prefix, "_daily_flows.csv")))
  write_csv(peaks,                file.path(output_dir, paste0(prefix, "_peak_flows.csv")))
  write_csv(site_info,            file.path(output_dir, paste0(prefix, "_site_info.csv")))
  write_csv(above_reservoir_daily, file.path(output_dir, paste0(prefix, "_above_reservoir_daily.csv")))
  write_csv(reservoir_storage,    file.path(output_dir, paste0(prefix, "_reservoir_storage.csv")))
  write_csv(record_summary,       file.path(output_dir, paste0(prefix, "_record_summary.csv")))
  
  message("--- All outputs saved as .csv to: ", output_dir, " ---")
}


# =============================================================================
# 5. EXECUTION PIPELINE
# =============================================================================

run_tributary_acquisition <- function(cfg = config) {
  #' Execute the full tributary/dam data acquisition pipeline.
  #' Pulls from USGS NWIS and USBR Hydromet, assembles composite record,
  #' annotates dam periods, summarizes, and saves to disk.
  #'
  #' @param cfg  Config list (defaults to the top-level `config` object).
  
  output_dir <- cfg$output_dir
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # ---- USGS NWIS ----
  message("\n=== Pulling USGS NWIS data for ", cfg$usgs_gage_id, " ===")
  usgs_daily <- pull_usgs_daily(cfg$usgs_gage_id,
                                start_date = cfg$usgs_start_date)
  usgs_peaks <- pull_usgs_peaks(cfg$usgs_gage_id,
                                dam_start_year = cfg$dam_start_year,
                                dam_end_year   = cfg$dam_end_year)
  usgs_site  <- pull_usgs_site(cfg$usgs_gage_id)
  
  message("  USGS daily: ", nrow(usgs_daily), " records, ",
          min(usgs_daily$date, na.rm = TRUE), " to ",
          max(usgs_daily$date, na.rm = TRUE))
  message("  USGS peaks: ", nrow(usgs_peaks), " annual peaks")
  
  # ---- USBR Hydromet ----
  message("\n=== Pulling USBR Hydromet stations ===")
  hydromet <- pull_hydromet_stations(cfg$hydromet_stations,
                                     start_date = cfg$hydromet_start_date)
  
  # Identify roles from config
  below_dam_id       <- cfg$hydromet_stations %>%
    filter(role == "below_dam") %>% pull(station_id) %>% tolower()
  above_reservoir_id <- cfg$hydromet_stations %>%
    filter(role == "above_reservoir") %>% pull(station_id) %>% tolower()
  storage_id         <- cfg$hydromet_stations %>%
    filter(role == "reservoir_storage") %>% pull(station_id) %>% tolower()
  
  # ---- Assemble composite below-dam daily record ----
  message("\n=== Assembling composite below-dam record ===")
  composite_daily <- assemble_composite_daily(usgs_daily,
                                              hydromet[[below_dam_id]]) %>%
    annotate_dam_period(cfg$dam_start_year, cfg$dam_end_year)
  
  message("  Composite record: ", nrow(composite_daily), " days, ",
          min(composite_daily$date), " to ", max(composite_daily$date))
  
  # ---- Annotate above-reservoir and storage records ----
  above_reservoir_daily <- hydromet[[above_reservoir_id]] %>%
    annotate_dam_period(cfg$dam_start_year, cfg$dam_end_year)
  
  reservoir_storage <- hydromet[[storage_id]] %>%
    rename(daily_af = daily_q_cfs) %>%
    mutate(
      water_year = if_else(month(date) >= 10, year(date) + 1L, year(date))
    )
  
  # ---- Summarize ----
  record_summary <- summarize_record(composite_daily)
  message("\n--- Below-Dam Record Summary ---")
  print(record_summary)
  
  message("\n--- Pre-dam peak flow summary ---")
  pre_dam_peaks <- usgs_peaks %>% filter(dam_period == "pre_dam")
  if (nrow(pre_dam_peaks) > 0) {
    message("  N peaks: ", nrow(pre_dam_peaks))
    message("  Range: ", min(pre_dam_peaks$peak_q_cfs, na.rm = TRUE),
            " to ", max(pre_dam_peaks$peak_q_cfs, na.rm = TRUE), " cfs")
    message("  Median: ", median(pre_dam_peaks$peak_q_cfs, na.rm = TRUE), " cfs")
  }
  
  message("\n--- Above-reservoir record ---")
  if (nrow(above_reservoir_daily) > 0) {
    message("  ", nrow(above_reservoir_daily), " days, ",
            min(above_reservoir_daily$date), " to ",
            max(above_reservoir_daily$date))
    message("  Max daily Q: ",
            max(above_reservoir_daily$daily_q_cfs, na.rm = TRUE), " cfs")
  }
  
  message("\n--- Reservoir storage record ---")
  if (nrow(reservoir_storage) > 0) {
    message("  ", nrow(reservoir_storage), " days, ",
            min(reservoir_storage$date), " to ", max(reservoir_storage$date))
    message("  Max storage: ",
            max(reservoir_storage$daily_af, na.rm = TRUE), " af")
  }
  
  # ---- Save outputs ----
  save_tributary_outputs(
    composite_daily       = composite_daily,
    peaks                 = usgs_peaks,
    site_info             = usgs_site,
    above_reservoir_daily = above_reservoir_daily,
    reservoir_storage     = reservoir_storage,
    record_summary        = record_summary,
    output_dir            = output_dir,
    prefix                = cfg$output_prefix
  )
  
  # Return all data for interactive use
  list(
    composite_daily       = composite_daily,
    peaks                 = usgs_peaks,
    site_info             = usgs_site,
    above_reservoir_daily = above_reservoir_daily,
    reservoir_storage     = reservoir_storage,
    record_summary        = record_summary
  )
}


# =============================================================================
# EXECUTE
# =============================================================================
# Full pipeline:
  trib_data <- run_tributary_acquisition(config)
#
# --- Interactive testing ---
# Config is already in your environment after source(). Test any function:
#   usgs_daily <- pull_usgs_daily(config$usgs_gage_id,
#                                  start_date = config$usgs_start_date)
#   usgs_peaks <- pull_usgs_peaks(config$usgs_gage_id,
#                                  dam_start_year = config$dam_start_year,
#                                  dam_end_year   = config$dam_end_year)
#   hydromet   <- pull_hydromet_stations(config$hydromet_stations,
#                                         start_date = config$hydromet_start_date)
#   composite  <- assemble_composite_daily(usgs_daily, hydromet$mcko) %>%
#     annotate_dam_period(config$dam_start_year, config$dam_end_year)
#   summary    <- summarize_record(composite)
# =============================================================================
