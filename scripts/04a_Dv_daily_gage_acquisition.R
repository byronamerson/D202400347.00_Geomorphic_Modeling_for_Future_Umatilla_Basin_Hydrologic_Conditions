# =============================================================================
# 04a_Dv_daily_gage_acquisition.R
# Discharge-Channel Migration Analysis
# Phase 4a Dv: Daily Value Gage Acquisition
# =============================================================================
#
# Purpose: Discover the daily-value period of record for the target USGS gage
#          network, then pull the full available daily mean discharge record
#          for each gage into tidy project datasets.
#
# Scope:
#   - USGS daily values only
#   - Daily mean discharge only (parameter 00060, statistic 00003)
#   - The main gage network used in the Pendleton daily-extension workflow
#
# Not in scope:
#   - Flood-frequency analysis
#   - Water-year summaries
#   - Threshold exceedance metrics
#   - McKay regulation correction
#   - Modeling or validation
#
# Usage:   Edit the CONFIG section below, then either:
#            (a) source() and call run_dv_daily_gage_acquisition(config)
#            (b) step through interactively with the scaffolded functions,
#                running one section at a time for testing and inspection
#
# Output:  .csv files in config$output_dir:
#            dv_gage_daily_availability.csv
#            dv_gage_site_info.csv
#            dv_gage_daily_flows.csv
#            dv_gage_record_summary.csv
#
# Notes:
#   - PORTED to the modern USGS Water Data API (dataRetrieval >= 2.7.22). The
#     legacy NWIS services (whatNWISdata / readNWISsite / readNWISdv) are being
#     decommissioned by USGS and are avoided here. The three retrieval helpers
#     now call:
#       * read_waterdata_ts_meta()            -> daily-value availability
#       * read_waterdata_monitoring_location()-> site metadata
#       * read_waterdata_daily()              -> daily mean discharge
#   - The new API identifies sites as "USGS-<id>" (e.g. "USGS-14020000"). This
#     script keeps the bare id ("14020000") as the project join key and adds /
#     strips the "USGS-" prefix only at the API boundary.
#   - No API token is required. Paging is handled by dataRetrieval (50,000-row
#     request cap, automatic chunking).
#   - The daily table carries approval_status (Approved/Provisional) in place of
#     the legacy single-letter provisional code.
# =============================================================================

library(tidyverse)
library(dataRetrieval)
library(sf)

stopifnot(
  "dataRetrieval >= 2.7.22 is required for the Water Data API helpers" =
    utils::packageVersion("dataRetrieval") >= "2.7.22"
)


# =============================================================================
# CONFIG
# =============================================================================

config <- list(

  # ---- Gage network ----
  gages = tribble(
    ~gage_id,    ~gage_name,                                      ~position,
    "14020000",  "Umatilla R above Meacham Cr nr Gibbon",         "upstream",
    "14020850",  "Umatilla R at W Reservation Bndy nr Pendleton", "target",
    "14033500",  "Umatilla R near Umatilla",                      "downstream"
  ),

  # ---- Water Data API retrieval target ----
  parameter_cd = "00060",
  stat_cd = "00003",

  # ---- Retrieval window ----
  # Blank values request the full available record from the Water Data API.
  start_date = "",
  end_date   = "",

  # ---- Output ----
  output_dir = "data/"
)


# =============================================================================
# 1. REUSABLE HELPERS
# =============================================================================

# Add the Water Data API agency prefix to a bare USGS site id.
# gage_id (character) -> character monitoring_location_id ("USGS-<id>").
# Keep the bare id as the project join key; prefix only at the API boundary.
to_ml_id <- function(gage_id) {
  paste0("USGS-", gage_id)
}

# Strip the Water Data API agency prefix back to a bare USGS site id.
# ml_id (character monitoring_location_id) -> character bare gage id.
from_ml_id <- function(ml_id) {
  sub("^USGS-", "", ml_id)
}

# Build the Water Data API `time` argument from project start/end strings.
# start_date/end_date (character, "" for open) -> NA for full record, else c(start, end).
# The API takes NA (full record) or a length-2 c(start, end) bounded interval.
make_time_arg <- function(start_date, end_date) {
  start_blank <- is.na(start_date) || !nzchar(start_date)
  end_blank   <- is.na(end_date)   || !nzchar(end_date)
  if (start_blank && end_blank) {
    return(NA_character_)
  }
  c(
    if (start_blank) "1900-01-01" else start_date,
    if (end_blank) as.character(Sys.Date()) else end_date
  )
}

# Guarantee a set of columns exists on a data frame, adding any missing as NA.
# df (data frame), cols (character) -> df with all `cols` present.
# Defensive shim: the Water Data API omits columns that have no data, so
# downstream transmute() calls stay stable across sites and service versions.
ensure_cols <- function(df, cols) {
  missing <- setdiff(cols, names(df))
  if (length(missing)) {
    df[missing] <- NA
  }
  df
}

# Collapse a data-qualifier cell (which may be a list-column) to a scalar string.
# x (character vector, list element, or NA) -> single character or NA.
collapse_qualifier <- function(x) {
  x <- unlist(x, use.names = FALSE)
  x <- x[!is.na(x)]
  if (!length(x)) NA_character_ else paste(x, collapse = ";")
}

# Discover daily-value availability for the configured gage network.
# gages (tibble with gage_id, gage_name, position), parameter_cd, stat_cd
#   -> tibble with one row per daily time series matching the target.
# Key decisions:
#   - Query time-series metadata before retrieval so the project records the
#     reported period of record rather than inferring it later from rows.
#   - Filter to the daily computation period so the metadata table aligns with
#     the actual acquisition target.
discover_daily_value_availability <- function(gages, parameter_cd, stat_cd) {
  stopifnot(
    is.data.frame(gages),
    all(c("gage_id", "gage_name", "position") %in% names(gages)),
    is.character(parameter_cd),
    length(parameter_cd) == 1L,
    !is.na(parameter_cd),
    is.character(stat_cd),
    length(stat_cd) == 1L,
    !is.na(stat_cd)
  )

  ml_ids <- gages %>%
    distinct(gage_id) %>%
    pull(gage_id) %>%
    to_ml_id()

  # Query one site at a time and keep only the daily-mean series. The ts-meta
  # endpoint returns nothing for a comma-joined multi-site id, and its
  # statistic_id filter is unreliable, so filter by parameter server-side and
  # isolate the daily-mean series client-side. At each gage, 00060 has several
  # series (instantaneous "Points", annual "Water Year", daily "Daily"); the
  # daily mean is uniquely statistic_id 00003 + computation_period "Daily".
  ml_ids %>%
    map(~ read_waterdata_ts_meta(
      monitoring_location_id = .x,
      parameter_code = parameter_cd,
      skipGeometry = TRUE
    )) %>%
    bind_rows() %>%
    as_tibble() %>%
    ensure_cols(c(
      "monitoring_location_id", "parameter_code", "statistic_id",
      "computation_period_identifier", "begin", "end",
      "unit_of_measure", "time_series_id"
    )) %>%
    filter(
      statistic_id == stat_cd,
      str_to_lower(computation_period_identifier) == "daily"
    ) %>%
    transmute(
      gage_id = from_ml_id(monitoring_location_id),
      parameter_code,
      statistic_id,
      computation_period = computation_period_identifier,
      begin_date = begin,
      end_date = end,
      parameter_units = unit_of_measure,
      time_series_id
    ) %>%
    arrange(gage_id, begin_date)
}


# =============================================================================
# 2. PULL RAW SITE METADATA
# =============================================================================

# Pull site metadata for a single USGS gage from the Water Data API.
# gage_id (character USGS site number) -> one-row tibble with site identity
# and core hydrologic metadata used for documentation and QA.
# Key decisions:
#   - Retrieve the geometry so latitude/longitude can be preserved, then drop it
#     to keep the project table flat and CSV-friendly.
#   - Select down to the documentation fields so later steps do not depend on
#     the full Water Data API monitoring-location schema.
pull_site_metadata <- function(gage_id) {
  stopifnot(
    is.character(gage_id),
    length(gage_id) == 1L,
    !is.na(gage_id),
    nzchar(gage_id)
  )

  ml <- read_waterdata_monitoring_location(
    monitoring_location_id = to_ml_id(gage_id),
    skipGeometry = FALSE
  )

  coords <- sf::st_coordinates(ml)

  ml %>%
    sf::st_drop_geometry() %>%
    as_tibble() %>%
    ensure_cols(c(
      "monitoring_location_id", "monitoring_location_name", "site_type",
      "agency_code", "altitude", "vertical_datum", "hydrologic_unit_code",
      "drainage_area", "contributing_drainage_area",
      "time_zone_abbreviation", "uses_daylight_savings"
    )) %>%
    transmute(
      gage_id = from_ml_id(monitoring_location_id),
      station_name = monitoring_location_name,
      site_type = site_type,
      agency_code = agency_code,
      latitude_dd = coords[, "Y"],
      longitude_dd = coords[, "X"],
      altitude_ft = as.numeric(altitude),
      altitude_datum = vertical_datum,
      huc_cd = hydrologic_unit_code,
      drainage_area_sqmi = as.numeric(drainage_area),
      contributing_drainage_area_sqmi = as.numeric(contributing_drainage_area),
      time_zone = time_zone_abbreviation,
      honors_daylight_savings = uses_daylight_savings
    )
}


# =============================================================================
# 3. PULL DAILY VALUES
# =============================================================================

# Pull daily mean discharge for a single USGS gage from the Water Data API.
# gage_id, start_date, end_date, parameter_cd, stat_cd
#   -> tibble with gage_id, date, daily_q_cfs, approval_status, qualifier.
# Key decisions:
#   - Blank start_date and end_date request the full available record.
#   - Column names are standardized to project names rather than leaving the
#     Water Data API descriptors in place.
#   - Only one parameter/statistic target is retrieved so the output stays
#     narrow and predictable.
pull_daily_values_for_gage <- function(gage_id,
                                       start_date = "",
                                       end_date = "",
                                       parameter_cd = "00060",
                                       stat_cd = "00003") {
  stopifnot(
    is.character(gage_id),
    length(gage_id) == 1L,
    !is.na(gage_id),
    nzchar(gage_id)
  )

  read_waterdata_daily(
    monitoring_location_id = to_ml_id(gage_id),
    parameter_code = parameter_cd,
    statistic_id = stat_cd,
    time = make_time_arg(start_date, end_date),
    skipGeometry = TRUE,
    convertType = TRUE
  ) %>%
    as_tibble() %>%
    ensure_cols(c(
      "monitoring_location_id", "time", "value", "approval_status", "qualifier"
    )) %>%
    transmute(
      gage_id = from_ml_id(monitoring_location_id),
      date = as.Date(time),
      daily_q_cfs = as.numeric(value),
      approval_status = as.character(approval_status),
      qualifier = vapply(qualifier, collapse_qualifier, character(1))
    ) %>%
    arrange(date)
}


# =============================================================================
# 4. BUILD PROJECT TABLES
# =============================================================================

# Join gage labels onto the discovered daily-value availability table.
# availability_tbl (tibble from discover_daily_value_availability),
# gages (tibble with gage_id, gage_name, position)
#   -> tibble with availability fields plus project gage labels.
# Key decisions:
#   - Availability discovery and project-specific labeling are separate steps so
#     the Water Data API query stays generic and reusable.
#   - This helper only joins metadata already in memory; it performs no I/O.
attach_gage_labels_to_availability <- function(availability_tbl, gages) {
  stopifnot(
    is.data.frame(availability_tbl),
    "gage_id" %in% names(availability_tbl),
    is.data.frame(gages),
    all(c("gage_id", "gage_name", "position") %in% names(gages))
  )

  availability_tbl %>%
    left_join(
      gages %>% distinct(gage_id, gage_name, position),
      by = "gage_id"
    ) %>%
    relocate(gage_id, gage_name, position)
}


# Join gage labels onto the retrieved site metadata table.
# site_info_tbl (tibble from pull_site_metadata across gages),
# gages (tibble with gage_id, gage_name, position)
#   -> tibble with retained site fields plus project gage labels.
# Key decisions:
#   - Site retrieval and project labeling are separate so the site helper stays
#     focused on one gage and one external call.
#   - This helper should only add project context, not derive new hydrologic
#     variables.
attach_gage_labels_to_site_info <- function(site_info_tbl, gages) {
  stopifnot(
    is.data.frame(site_info_tbl),
    "gage_id" %in% names(site_info_tbl),
    is.data.frame(gages),
    all(c("gage_id", "gage_name", "position") %in% names(gages))
  )

  site_info_tbl %>%
    left_join(
      gages %>% distinct(gage_id, gage_name, position),
      by = "gage_id"
    ) %>%
    relocate(gage_id, gage_name, position)
}


# Join gage labels onto the retrieved daily-value table.
# daily_flows_tbl (tibble from pull_daily_values_for_gage across gages),
# gages (tibble with gage_id, gage_name, position)
#   -> tibble with standardized daily values plus project gage labels.
# Key decisions:
#   - Retrieval stays generic; project labels are attached in a separate pure
#     helper so the same pull function can be reused elsewhere.
#   - The output remains long and tidy, one row per gage-date observation.
attach_gage_labels_to_daily_flows <- function(daily_flows_tbl, gages) {
  stopifnot(
    is.data.frame(daily_flows_tbl),
    "gage_id" %in% names(daily_flows_tbl),
    is.data.frame(gages),
    all(c("gage_id", "gage_name", "position") %in% names(gages))
  )

  daily_flows_tbl %>%
    left_join(
      gages %>% distinct(gage_id, gage_name, position),
      by = "gage_id"
    ) %>%
    relocate(gage_id, gage_name, position)
}


# Build the named project result tables from already-retrieved inputs.
# availability_tbl, site_info_tbl, daily_flows_tbl, gages
#   -> named list of tidy tables ready for QA review or file writing.
# Key decisions:
#   - This function assembles project tables from in-memory objects only.
#   - It does not query the API and does not write files, which keeps it easy to
#     run during interactive development.
build_daily_value_results <- function(availability_tbl,
                                      site_info_tbl,
                                      daily_flows_tbl,
                                      gages) {
  stopifnot(
    is.data.frame(availability_tbl),
    is.data.frame(site_info_tbl),
    is.data.frame(daily_flows_tbl),
    is.data.frame(gages)
  )

  list(
    availability = availability_tbl,
    site_info = site_info_tbl,
    daily_flows = daily_flows_tbl
  )
}


# Summarize discovered and retrieved record spans for quick QA.
# availability_tbl, daily_flows_tbl -> tibble with one row per gage describing
# reported availability and the span actually retrieved.
# Key decisions:
#   - This summary is for auditability and gap-checking, not analysis.
#   - Reported availability and retrieved span are kept side by side so
#     mismatches are visible early.
build_daily_value_record_summary <- function(availability_tbl, daily_flows_tbl) {
  stopifnot(
    is.data.frame(availability_tbl),
    "gage_id" %in% names(availability_tbl),
    is.data.frame(daily_flows_tbl),
    all(c("gage_id", "date", "daily_q_cfs") %in% names(daily_flows_tbl))
  )

  reported <- availability_tbl %>%
    group_by(gage_id) %>%
    summarise(
      reported_begin = suppressWarnings(min(as.Date(begin_date), na.rm = TRUE)),
      reported_end = suppressWarnings(max(as.Date(end_date), na.rm = TRUE)),
      .groups = "drop"
    )

  retrieved <- daily_flows_tbl %>%
    group_by(gage_id) %>%
    summarise(
      retrieved_begin = suppressWarnings(min(date, na.rm = TRUE)),
      retrieved_end = suppressWarnings(max(date, na.rm = TRUE)),
      n_days = n(),
      n_missing_q = sum(is.na(daily_q_cfs)),
      .groups = "drop"
    )

  reported %>%
    full_join(retrieved, by = "gage_id") %>%
    arrange(gage_id)
}


# =============================================================================
# 5. WRITE OUTPUTS
# =============================================================================

# Write the daily-value acquisition outputs to stable CSV files.
# results (named list including record_summary), output_dir (directory path)
#   -> invisibly returns results after writing four project datasets.
# Key decisions:
#   - Writing lives at the boundary only; all upstream functions operate on
#     in-memory objects.
#   - Output filenames are stable and descriptive so later scripts can depend on
#     them without guessing.
write_daily_value_outputs <- function(results, output_dir) {
  stopifnot(
    is.list(results),
    all(c("availability", "site_info", "daily_flows", "record_summary") %in%
          names(results)),
    is.character(output_dir),
    length(output_dir) == 1L
  )

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  readr::write_csv(results$availability,
                   file.path(output_dir, "dv_gage_daily_availability.csv"))
  readr::write_csv(results$site_info,
                   file.path(output_dir, "dv_gage_site_info.csv"))
  readr::write_csv(results$daily_flows,
                   file.path(output_dir, "dv_gage_daily_flows.csv"))
  readr::write_csv(results$record_summary,
                   file.path(output_dir, "dv_gage_record_summary.csv"))

  invisible(results)
}


# =============================================================================
# 6. ORCHESTRATOR
# =============================================================================

# Run the full daily-value gage acquisition workflow as a convenience wrapper.
# config (list with gage network, API target, retrieval window, output_dir)
#   -> invisibly returns the built result tables after writing CSV outputs.
# Key decisions:
#   - This is an optional convenience for non-interactive runs; the same steps
#     are also runnable one at a time in the interactive section below.
#   - This is the only function in the script that chains retrieval, assembly,
#     summary building, and file writing in one call.
run_dv_daily_gage_acquisition <- function(config) {
  gages <- config$gages

  availability_raw <- discover_daily_value_availability(
    gages = gages,
    parameter_cd = config$parameter_cd,
    stat_cd = config$stat_cd
  )
  availability_tbl <- attach_gage_labels_to_availability(availability_raw, gages)

  site_info_raw <- gages$gage_id %>%
    map(pull_site_metadata) %>%
    bind_rows()
  site_info_tbl <- attach_gage_labels_to_site_info(site_info_raw, gages)

  daily_flows_raw <- gages$gage_id %>%
    map(
      ~ pull_daily_values_for_gage(
        gage_id = .x,
        start_date = config$start_date,
        end_date = config$end_date,
        parameter_cd = config$parameter_cd,
        stat_cd = config$stat_cd
      )
    ) %>%
    bind_rows()
  daily_flows_tbl <- attach_gage_labels_to_daily_flows(daily_flows_raw, gages)

  record_summary_tbl <- build_daily_value_record_summary(
    availability_tbl = availability_tbl,
    daily_flows_tbl = daily_flows_tbl
  )

  results <- build_daily_value_results(
    availability_tbl = availability_tbl,
    site_info_tbl = site_info_tbl,
    daily_flows_tbl = daily_flows_tbl,
    gages = gages
  )
  results$record_summary <- record_summary_tbl

  write_daily_value_outputs(results, config$output_dir)

  invisible(results)
}


## ============================================================================
## 7. INTERACTIVE STEPWISE RUN
## ============================================================================
##
## This section mirrors the orchestrator in explicit serial steps so each stage
## can be run, inspected, and debugged interactively without triggering the full
## chain at once.
##
## HASH CONVENTION: every executable line below is a SINGLE-hash comment; all
## narration (banners, step headers, this note) is DOUBLE-hash. Select any block
## and press Ctrl+Shift+C -- RStudio strips one hash per line, so the code goes
## live while the ## narration drops to a single # and stays commented. A
## multi-step selection therefore runs without errors. Toggle again to
## re-comment the code.
##
## ---- Step 0: unpack the config pieces used repeatedly ----
#
# gages <- config$gages
# parameter_cd <- config$parameter_cd
# stat_cd <- config$stat_cd
# start_date <- config$start_date
# end_date <- config$end_date
# output_dir <- config$output_dir
##
## ---- Step 1: discover daily-value availability (read_waterdata_ts_meta) ----
#
# availability_raw <- discover_daily_value_availability(
#   gages = gages,
#   parameter_cd = parameter_cd,
#   stat_cd = stat_cd
# )
#
# availability_raw
##
## ---- Step 2: attach project gage labels to the availability table ----
#
# availability_tbl <- attach_gage_labels_to_availability(
#   availability_tbl = availability_raw,
#   gages = gages
# )
#
# availability_tbl
##
## ---- Step 3: pull raw site metadata for each gage ----
#
# site_info_raw <- gages$gage_id %>%
#   map(pull_site_metadata) %>%
#   bind_rows()
#
# site_info_raw
##
## ---- Step 4: attach project gage labels to the site metadata ----
#
# site_info_tbl <- attach_gage_labels_to_site_info(
#   site_info_tbl = site_info_raw,
#   gages = gages
# )
#
# site_info_tbl
##
## ---- Step 5: pull raw daily values for each gage ----
#
# daily_flows_raw <- gages$gage_id %>%
#   map(
#     ~ pull_daily_values_for_gage(
#       gage_id = .x,
#       start_date = start_date,
#       end_date = end_date,
#       parameter_cd = parameter_cd,
#       stat_cd = stat_cd
#     )
#   ) %>%
#   bind_rows()
#
# daily_flows_raw
##
## ---- Step 6: attach project gage labels to the daily-value table ----
#
# daily_flows_tbl <- attach_gage_labels_to_daily_flows(
#   daily_flows_tbl = daily_flows_raw,
#   gages = gages
# )
#
# daily_flows_tbl
##
## ---- Step 7: build the record-summary QA table ----
#
# record_summary_tbl <- build_daily_value_record_summary(
#   availability_tbl = availability_tbl,
#   daily_flows_tbl = daily_flows_tbl
# )
#
# record_summary_tbl
##
## ---- Step 8: assemble the named project results list ----
#
# results <- build_daily_value_results(
#   availability_tbl = availability_tbl,
#   site_info_tbl = site_info_tbl,
#   daily_flows_tbl = daily_flows_tbl,
#   gages = gages
# )
#
# results$record_summary <- record_summary_tbl
#
# results
##
## ---- Step 9: write outputs only after the in-memory tables look right ----
#
# write_daily_value_outputs(
#   results = results,
#   output_dir = output_dir
# )
