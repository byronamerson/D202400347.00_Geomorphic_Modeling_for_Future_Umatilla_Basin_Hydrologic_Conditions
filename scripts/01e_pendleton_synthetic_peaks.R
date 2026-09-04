# =============================================================================
# 01e_pendleton_synthetic_peaks.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1e: Synthetic Pendleton Annual Peaks for Geomorphic Interval Analysis
# =============================================================================
#
# Purpose: Build a Pendleton annual-peak series that spans the HMA photo record
#          back to WY 1952 so the geomorphology-vs-peak plots can use one
#          consistent forcing series across the full interval set.
#
# Inputs (from 01, 01c):
#   data/peak_flows.csv
#   data/reconstructed_peaks.csv
#
# Outputs:
#   data/pendleton_synthetic_peaks.csv
#   data/pendleton_synthetic_move3_diagnostics.csv
#
# Decision note:
#   - This script deliberately extends the Pendleton record beyond the
#     Bulletin 17C-style 26-year extension convention used in 01d.
#   - If hydrologic statisticians would like a written confession: yes, this is
#     a knowingly non-standard extension back to WY 1952, done on purpose for
#     exploratory geomorphic forcing alignment rather than standards-compliant
#     flood-frequency analysis. Decorum has been set aside knowingly.
#   - We keep 01d as the flood-frequency workflow and use 01e only to create a
#     pragmatic synthetic annual-peak record for the photo-interval analyses.
#   - The corrected 14033500 extension is treated as the primary synthetic
#     Pendleton series because 01d already established it as the preferred
#     index-gage relationship for annual-peak extension.
# =============================================================================

library(tidyverse)

# =============================================================================
# 1. CONFIGURATION
# =============================================================================

config <- tribble(
  ~parameter,               ~value,
  "target_gage_id",         "14020850",
  "index_corrected_id",     "14033500",
  "index_unregulated_id",   "14020000",
  "target_start_year",      "1952",
  "primary_index_label",    "14033500 (corrected)"
)

cfg <- function(param) {
  config %>%
    filter(parameter == param) %>%
    pull(value)
}

cfg_num <- function(param) as.numeric(cfg(param))


# =============================================================================
# 2. DATA LOADING
# =============================================================================

load_move3_inputs <- function(data_dir = "data/") {
  peak_flows <- read_csv(
    file.path(data_dir, "peak_flows.csv"),
    col_types = cols(.default = col_guess(), gage_id = col_character())
  )

  corrected_peaks <- read_csv(
    file.path(data_dir, "reconstructed_peaks.csv"),
    col_types = cols(.default = col_guess())
  )

  target_id <- cfg("target_gage_id")
  corrected_id <- cfg("index_corrected_id")
  unreg_id <- cfg("index_unregulated_id")

  target_peaks <- peak_flows %>%
    filter(gage_id == target_id) %>%
    select(water_year, peak_q_cfs) %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)

  index_corrected <- corrected_peaks %>%
    select(water_year, peak_q_cfs = peak_q_unreg_cfs) %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)

  index_unregulated <- peak_flows %>%
    filter(gage_id == unreg_id) %>%
    select(water_year, peak_q_cfs) %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)

  list(
    target_peaks = target_peaks,
    index_corrected = index_corrected,
    index_unregulated = index_unregulated
  )
}


# =============================================================================
# 3. DIAGNOSTICS
# =============================================================================

summarize_concurrent <- function(target_peaks, index_peaks, index_label) {
  concurrent <- inner_join(
    target_peaks %>% select(water_year, target_q = peak_q_cfs),
    index_peaks %>% select(water_year, index_q = peak_q_cfs),
    by = "water_year"
  )

  tibble(
    index_label = index_label,
    n_concurrent = nrow(concurrent),
    year_min = min(concurrent$water_year),
    year_max = max(concurrent$water_year),
    r_log = cor(log10(concurrent$target_q), log10(concurrent$index_q))
  )
}


# =============================================================================
# 4. MOVE.3 EXTENSION TO THE PHOTO RECORD
# =============================================================================

move3_extend_to_year <- function(target_peaks, index_peaks, target_start_year) {
  combined <- inner_join(
    target_peaks %>% select(water_year, target_q = peak_q_cfs),
    index_peaks %>% select(water_year, index_q = peak_q_cfs),
    by = "water_year"
  ) %>%
    mutate(
      log_target = log10(target_q),
      log_index = log10(index_q)
    )

  x_bar <- mean(combined$log_index)
  y_bar <- mean(combined$log_target)
  sx <- sd(combined$log_index)
  sy <- sd(combined$log_target)
  r <- cor(combined$log_index, combined$log_target)

  extension_years <- index_peaks %>%
    filter(
      !water_year %in% combined$water_year,
      water_year >= target_start_year,
      water_year < min(target_peaks$water_year),
      !is.na(peak_q_cfs),
      peak_q_cfs > 0
    ) %>%
    select(water_year, index_q = peak_q_cfs) %>%
    mutate(
      log_index = log10(index_q)
    ) %>%
    arrange(water_year)

  if (nrow(extension_years) == 0) {
    stop("No index-site years available for the requested synthetic extension window.")
  }

  b_move <- sy / sx

  estimated <- extension_years %>%
    mutate(
      log_target_est = y_bar + b_move * (log_index - x_bar),
      peak_q_cfs = 10^log_target_est,
      source = "estimated"
    ) %>%
    select(water_year, peak_q_cfs, source)

  observed <- target_peaks %>%
    mutate(source = "observed")

  extended_record <- bind_rows(estimated, observed) %>%
    arrange(water_year)

  diagnostics <- tibble(
    n_concurrent = nrow(combined),
    n_extended = nrow(estimated),
    extension_yr_min = min(estimated$water_year),
    extension_yr_max = max(estimated$water_year),
    r_log = r,
    b_move = b_move,
    target_mean_log = y_bar,
    target_sd_log = sy,
    index_mean_log = x_bar,
    index_sd_log = sx
  )

  list(
    extended_record = extended_record,
    diagnostics = diagnostics
  )
}


# =============================================================================
# 5. OUTPUT ASSEMBLY
# =============================================================================

build_primary_synthetic_record <- function(ext_corrected, ext_unregulated) {
  corrected_label <- cfg("primary_index_label")

  corrected_record <- ext_corrected$extended_record %>%
    mutate(
      gage_id = cfg("target_gage_id"),
      move3_index_gage = corrected_label
    )

  candidate_diagnostics <- bind_rows(
    ext_corrected$diagnostics %>%
      mutate(index_label = corrected_label),
    ext_unregulated$diagnostics %>%
      mutate(index_label = paste0(cfg("index_unregulated_id"), " (Gibbon)"))
  ) %>%
    select(index_label, everything())

  list(
    synthetic_record = corrected_record,
    diagnostics = candidate_diagnostics
  )
}

save_synthetic_outputs <- function(synthetic_record, diagnostics, output_dir = "data/") {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  write_csv(
    synthetic_record,
    file.path(output_dir, "pendleton_synthetic_peaks.csv")
  )

  write_csv(
    diagnostics,
    file.path(output_dir, "pendleton_synthetic_move3_diagnostics.csv")
  )
}


# =============================================================================
# 6. PIPELINE RUNNER
# =============================================================================

run_pendleton_synthetic_peaks <- function(data_dir = "data/", output_dir = "data/") {
  message("\n=== 01e: Synthetic Pendleton annual peaks for geomorphic plots ===")

  inputs <- load_move3_inputs(data_dir)
  target_start_year <- cfg_num("target_start_year")

  concurrent_diag <- bind_rows(
    summarize_concurrent(
      inputs$target_peaks,
      inputs$index_corrected,
      paste0(cfg("index_corrected_id"), " (corrected)")
    ),
    summarize_concurrent(
      inputs$target_peaks,
      inputs$index_unregulated,
      paste0(cfg("index_unregulated_id"), " (Gibbon)")
    )
  )

  message("\n--- MOVE.3 extension using corrected ", cfg("index_corrected_id"), " ---")
  ext_corrected <- move3_extend_to_year(
    target_peaks = inputs$target_peaks,
    index_peaks = inputs$index_corrected,
    target_start_year = target_start_year
  )

  message("\n--- MOVE.3 extension using ", cfg("index_unregulated_id"), " (Gibbon) ---")
  ext_unregulated <- move3_extend_to_year(
    target_peaks = inputs$target_peaks,
    index_peaks = inputs$index_unregulated,
    target_start_year = target_start_year
  )

  outputs <- build_primary_synthetic_record(ext_corrected, ext_unregulated)

  diagnostics <- outputs$diagnostics %>%
    left_join(concurrent_diag, by = c("index_label"))

  save_synthetic_outputs(
    synthetic_record = outputs$synthetic_record,
    diagnostics = diagnostics,
    output_dir = output_dir
  )

  list(
    synthetic_record = outputs$synthetic_record,
    diagnostics = diagnostics,
    corrected_extension = ext_corrected,
    gibbon_extension = ext_unregulated
  )
}


# =============================================================================
# EXECUTE
# =============================================================================

pendleton_synthetic_outputs <- run_pendleton_synthetic_peaks()
