# =============================================================================
# 01c_move3_extension_and_weighting.R
# Discharge-Channel Migration Analysis
# MOVE.3 Record Extension & Inverse-Variance Weighting
# =============================================================================
#
# Purpose: Extend a short-record target gage using MOVE.3 (B17C Appendix 8)
#          with one or more long-record index gages, refit B17C flood
#          frequency on extended records, and combine via inverse-variance
#          weighting (B17C Appendix 9).
#
# Usage:   Edit the CONFIG section below for your gage network, then either:
#            (a) source() and call run_move3_pipeline(config)
#            (b) step through interactively — config and all functions are
#                available at top level for testing individual pieces.
#
# Output:  .csv files in config$output_dir:
#            move3_extended_peaks.csv        — extended peak records (all index gages)
#            move3_diagnostics.csv           — MOVE.3 regression diagnostics
#            move3_flood_frequency.csv       — frequency curves for all methods
#            move3_weighted_flood_frequency.csv — final inverse-variance weighted result
#            move3_comparison.csv            — side-by-side Q estimates, all methods
#
# Dependencies:
#   - data/peak_flows.csv  (from 01_hydrology_acquisition.R)
#   - data/regional_skew.csv (from 01_hydrology_acquisition.R)
#   - peakfq::emafit()
#
# Style:   Follows Tidyverse & Functional Programming Guidelines
#          (Tidyverse_Functional_Programming_Guidelines_for_temperheic.md)
# =============================================================================

library(tidyverse)
library(peakfq)          # B17C flood frequency (EMA/MGBT)

# =============================================================================
# CONFIG — edit these values for a different gage network
# =============================================================================

config <- list(
  
  # ---- Target gage (short record to extend) ----
  target_gage_id = "14020850",
  
  # ---- Index gages (long records used for extension) ----
  # Named vector: name = gage_id. Names appear in output labels.
  index_gage_ids = c(
    "Umatilla" = "14033500",
    "Gibbon"   = "14020000"
  ),
  
  # ---- MOVE.3 settings ----
  max_extension    = 26L,            # max years to extend (B17C recommends <= n1)
  extension_method = "most_recent",  # "most_recent" or "match_skew"
  
  # ---- Flood frequency (B17C) settings ----
  # Regional skew — looked up from data/regional_skew.csv at runtime,
  # or override here with fixed values (set to NULL to use the CSV lookup).
  regional_skew_override = NULL,     # e.g., -0.07
  skew_se_override       = NULL,     # e.g., 0.424
  
  # AEPs to compute
  aeps = c(0.5, 0.2, 0.1, 0.04, 0.02, 0.01),
  
  # EMA configuration
  ema_confidence = 0.90,
  ema_weight_opt = "HWN",
  
  # ---- Input / Output ----
  data_dir   = "data/",
  output_dir = "data/"
)


# =============================================================================
# 1. DATA LOADING
# =============================================================================

load_move3_inputs <- function(data_dir, target_gage_id, index_gage_ids) {
  #' Load peak flows and regional skew from 01 pipeline outputs.
  #' Returns a list with target_peaks, index_peaks (named list), and skew_tbl.
  
  all_peaks <- read_csv(file.path(data_dir, "peak_flows.csv"),
                        show_col_types = FALSE)
  skew_tbl  <- read_csv(file.path(data_dir, "regional_skew.csv"),
                        show_col_types = FALSE)
  
  target_peaks <- all_peaks %>% filter(gage_id == target_gage_id)
  
  index_peaks <- index_gage_ids %>%
    imap(~ all_peaks %>% filter(gage_id == .x))
  
  list(
    all_peaks    = all_peaks,
    target_peaks = target_peaks,
    index_peaks  = index_peaks,
    skew_tbl     = skew_tbl
  )
}


# =============================================================================
# 2. CONCURRENT RECORD DIAGNOSTICS
# =============================================================================

compute_concurrent_diagnostics <- function(all_peaks, target_gage_id,
                                           index_gage_ids) {
  #' Compute concurrent-period statistics: record overlap and log-space
  #' Pearson correlations between the target and each index gage.
  #'
  #' @param all_peaks       Combined peak flow tibble (all gages)
  #' @param target_gage_id  Target gage ID string
  #' @param index_gage_ids  Named character vector of index gage IDs
  #'
  #' @return Tibble with one row per index gage: correlation, concurrent years
  
  all_gage_ids <- c(target_gage_id, unname(index_gage_ids))
  
  concurrent <- all_peaks %>%
    filter(gage_id %in% all_gage_ids) %>%
    select(gage_id, water_year, peak_q_cfs) %>%
    pivot_wider(
      names_from  = "gage_id",
      values_from = "peak_q_cfs",
      id_cols     = "water_year"
    ) %>%
    drop_na()
  
  message("Concurrent years (all gages): ", nrow(concurrent),
          " (", min(concurrent$water_year), "-", max(concurrent$water_year), ")")
  
  # Pairwise correlations with target
  index_gage_ids %>%
    imap_dfr(function(gid, label) {
      pair <- all_peaks %>%
        filter(gage_id %in% c(target_gage_id, gid)) %>%
        select(gage_id, water_year, peak_q_cfs) %>%
        pivot_wider(names_from = "gage_id", values_from = "peak_q_cfs") %>%
        drop_na()
      
      r_log <- cor(log10(pair[[target_gage_id]]), log10(pair[[gid]]))
      
      message("  r(target vs ", label, " [", gid, "]): ",
              round(r_log, 4), " (n=", nrow(pair), ")")
      
      tibble(
        index_label    = label,
        index_gage_id  = gid,
        r_log          = r_log,
        n_concurrent   = nrow(pair),
        year_start     = min(pair$water_year),
        year_end       = max(pair$water_year)
      )
    })
}


# =============================================================================
# 3. MOVE.3 RECORD EXTENSION (B17C Appendix 8)
# =============================================================================

move3_extend <- function(target_peaks, index_peaks, max_extension = 26,
                         method = "most_recent") {
  #' Extend a short peak flow record using MOVE.3 (Bulletin 17C App. 8).
  #'
  #' @param target_peaks  tibble with water_year, peak_q_cfs (short record)
  #' @param index_peaks   tibble with water_year, peak_q_cfs (long record)
  #' @param max_extension max years to extend (B17C recommends <= n1)
  #' @param method        "most_recent" or "match_skew"
  #'
  #' @return list with:
  #'   extended_record - combined observed + estimated peaks
  #'   diagnostics     - regression stats, correlation, etc.
  
  # Step 1: Identify concurrent period
  combined <- inner_join(
    target_peaks %>% select(water_year, target_q = peak_q_cfs),
    index_peaks  %>% select(water_year, index_q  = peak_q_cfs),
    by = "water_year"
  )
  
  n1 <- nrow(combined)
  message("  Concurrent years: ", n1)
  
  # Log-transform
  combined <- combined %>%
    mutate(log_target = log10(target_q),
           log_index  = log10(index_q))
  
  # Step 2: Concurrent period statistics
  x_bar <- mean(combined$log_index)
  y_bar <- mean(combined$log_target)
  sx    <- sd(combined$log_index)
  sy    <- sd(combined$log_target)
  r     <- cor(combined$log_index, combined$log_target)
  
  message("  Log-space: target mean=", round(y_bar, 4),
          " SD=", round(sy, 4),
          " | index mean=", round(x_bar, 4),
          " SD=", round(sx, 4),
          " | r=", round(r, 4))
  
  # Step 3: Identify non-concurrent years at index site
  non_concurrent <- index_peaks %>%
    filter(!water_year %in% combined$water_year,
           !is.na(peak_q_cfs), peak_q_cfs > 0) %>%
    select(water_year, index_q = peak_q_cfs) %>%
    mutate(log_index = log10(index_q)) %>%
    arrange(desc(water_year))
  
  message("  Non-concurrent years available: ", nrow(non_concurrent))
  
  # Cap extension length
  ne <- min(max_extension, nrow(non_concurrent))
  message("  Extension length (ne): ", ne)
  
  if (method == "most_recent") {
    extension_years <- non_concurrent %>% slice_head(n = ne)
  } else {
    warning("match_skew not yet implemented, using most_recent")
    extension_years <- non_concurrent %>% slice_head(n = ne)
  }
  
  # Step 4: MOVE.3 variance-preserving Matalas-Jacobs estimator
  #   Y_hat = y_bar + (sy/sx) * (X - x_bar)
  b_move <- sy / sx
  
  extension_years <- extension_years %>%
    mutate(
      log_target_est = y_bar + b_move * (log_index - x_bar),
      target_q_est   = 10^log_target_est
    )
  
  # Step 5: Matalas-Jacobs adjustment for extended record statistics
  n_total <- n1 + ne
  
  all_index <- bind_rows(
    combined %>% select(water_year, log_index),
    extension_years %>% select(water_year, log_index)
  )
  x_bar_full <- mean(all_index$log_index)
  
  y_bar_adj <- y_bar + b_move * (x_bar_full - x_bar)
  sy2_adj <- sy^2 * (1 + (ne / n_total) * (1 - r^2) *
                       (1 + (ne * (x_bar_full - x_bar)^2) /
                          ((n_total - 1) * sx^2)))
  
  message("  Matalas-Jacobs: adj_mean=", round(y_bar_adj, 4),
          " adj_SD=", round(sqrt(sy2_adj), 4),
          " (orig_SD=", round(sy, 4), ")")
  
  # Step 6: Build extended record
  observed <- combined %>%
    transmute(water_year, peak_q_cfs = target_q, source = "observed")
  
  estimated <- extension_years %>%
    transmute(water_year, peak_q_cfs = target_q_est, source = "estimated")
  
  extended_record <- bind_rows(observed, estimated) %>%
    arrange(water_year)
  
  message("  Extended record: ", nrow(extended_record), " years (",
          n1, " observed + ", ne, " estimated)")
  
  list(
    extended_record = extended_record,
    diagnostics = tibble(
      n_concurrent    = n1,
      n_extended      = ne,
      n_total         = n_total,
      r_log           = r,
      target_mean     = y_bar,
      target_sd       = sy,
      adj_mean        = y_bar_adj,
      adj_sd          = sqrt(sy2_adj),
      index_mean_conc = x_bar,
      index_mean_full = x_bar_full,
      b_move          = b_move
    )
  )
}


# =============================================================================
# 4. FLOOD FREQUENCY ON EXTENDED RECORDS
# =============================================================================

build_emafit_input_from_extended <- function(extended_record) {
  #' Convert an extended peak record into the QT dataframe for emafit().
  #' All peaks treated as exact systematic observations (no censoring).
  extended_record %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0) %>%
    transmute(
      ql    = peak_q_cfs,
      qu    = peak_q_cfs,
      tl    = 1,
      tu    = 1e20,
      dtype = 0L,
      peak_WY = water_year
    ) %>%
    as.data.frame()
}

run_emafit_on_extended <- function(extended_record, label, target_gage_id,
                                   gen_skew, skew_se,
                                   aeps       = c(0.5, 0.2, 0.1, 0.04,
                                                  0.02, 0.01),
                                   confidence = 0.90,
                                   weight_opt = "HWN") {
  #' Run emafit on an extended (or original) peak record and return a
  #' tidy frequency curve tibble.
  #'
  #' @param extended_record  Tibble with water_year, peak_q_cfs, source
  #' @param label            Method label for output (e.g., "MOVE.3 via Umatilla")
  #' @param target_gage_id   Gage ID string (for emafit site_no)
  #' @param gen_skew         Regional generalized skew
  #' @param skew_se          Standard error of regional skew
  #' @param aeps             Annual exceedance probabilities
  #' @param confidence       Confidence interval coverage
  #' @param weight_opt       Skew weighting algorithm
  
  QT <- build_emafit_input_from_extended(extended_record)
  
  skew_mse <- skew_se^2
  
  result <- emafit(
    QT        = QT,
    LOthresh  = 0,
    rG        = gen_skew,
    rGmse     = skew_mse,
    eps       = confidence,
    weightOpt = weight_opt,
    AEPs      = aeps,
    site_no   = target_gage_id,
    quietly   = TRUE
  )
  
  freq <- result[[2]] %>%
    mutate(return_period_yr = 1 / EXC_Prob)
  
  message("  ", label, ": record_length=", result[[1]]$RecordLength,
          " weighted_skew=", round(result[[1]]$Skew, 3))
  
  freq %>%
    mutate(
      method  = label,
      gage_id = target_gage_id
    )
}


# =============================================================================
# 5. INVERSE-VARIANCE WEIGHTED COMBINATION (B17C Appendix 9)
# =============================================================================

combine_inverse_variance <- function(ff_list, method_label = "Weighted MOVE.3") {
  #' Combine flood frequency estimates from multiple MOVE.3 extensions
  #' using inverse-variance weighting (B17C Appendix 9).
  #'
  #' @param ff_list      List of frequency curve tibbles (one per index gage)
  #' @param method_label Label for the combined result
  #'
  #' @return Tibble with weighted frequency estimates
  
  bind_rows(ff_list) %>%
    group_by(return_period_yr) %>%
    summarize(
      Estimate = weighted.mean(Estimate, w = 1 / Variance),
      Variance = 1 / sum(1 / Variance),
      .groups  = "drop"
    ) %>%
    mutate(method = method_label)
}


# =============================================================================
# 6. COMPARISON TABLE
# =============================================================================

build_comparison_table <- function(ff_original, ff_extended_list, ff_weighted,
                                   display_rps = c(2, 5, 10, 25, 50, 100)) {
  #' Build a side-by-side comparison table of all methods, including
  #' percent change from the original.
  #'
  #' @return List with: all_ff, wide_table, pct_change
  
  all_methods <- bind_rows(
    ff_original,
    bind_rows(ff_extended_list),
    ff_weighted
  ) %>%
    filter(return_period_yr %in% display_rps)
  
  wide_table <- all_methods %>%
    select(method, return_period_yr, Estimate) %>%
    pivot_wider(names_from = return_period_yr, values_from = Estimate,
                names_prefix = "Q")
  
  # Percent change from original
  orig_label <- unique(ff_original$method)
  orig_row   <- wide_table %>% filter(method == orig_label)
  
  pct_change <- wide_table %>%
    mutate(across(starts_with("Q"),
                  ~ round(100 * (. - orig_row[[cur_column()]]) /
                            orig_row[[cur_column()]], 1)))
  
  list(
    all_ff     = all_methods,
    wide_table = wide_table,
    pct_change = pct_change
  )
}


# =============================================================================
# 7. SAVE HELPERS
# =============================================================================

save_move3_outputs <- function(extended_peaks, diagnostics, all_ff,
                               weighted_ff, comparison, output_dir) {
  #' Write all MOVE.3 pipeline outputs as .csv.
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(extended_peaks, file.path(output_dir, "move3_extended_peaks.csv"))
  write_csv(diagnostics,    file.path(output_dir, "move3_diagnostics.csv"))
  write_csv(all_ff,         file.path(output_dir, "move3_flood_frequency.csv"))
  write_csv(weighted_ff,    file.path(output_dir, "move3_weighted_flood_frequency.csv"))
  write_csv(comparison$wide_table, file.path(output_dir, "move3_comparison.csv"))
  
  message("--- All MOVE.3 outputs saved as .csv to: ", output_dir, " ---")
}


# =============================================================================
# 8. EXECUTION PIPELINE
# =============================================================================

run_move3_pipeline <- function(cfg = config) {
  #' Execute the full MOVE.3 extension and weighting pipeline:
  #'   1. Load peak flows and skew from 01 outputs
  #'   2. Compute concurrent diagnostics
  #'   3. Run MOVE.3 extension with each index gage
  #'   4. Refit emafit on original and each extended record
  #'   5. Combine via inverse-variance weighting
  #'   6. Build comparison table and save outputs
  #'
  #' @param cfg  Config list (defaults to the top-level `config` object).
  
  # ---- Load data ----
  message("\n=== Loading peak flows and skew data ===")
  inputs <- load_move3_inputs(cfg$data_dir, cfg$target_gage_id,
                              cfg$index_gage_ids)
  
  # ---- Resolve skew values ----
  if (!is.null(cfg$regional_skew_override)) {
    gen_skew <- cfg$regional_skew_override
    skew_se  <- cfg$skew_se_override
    message("Using skew overrides: gen_skew=", gen_skew, " skew_se=", skew_se)
  } else {
    skew_row <- inputs$skew_tbl %>% filter(gage_id == cfg$target_gage_id)
    gen_skew <- skew_row$gen_skew
    skew_se  <- skew_row$skew_se
    message("Skew from regional_skew.csv: gen_skew=", gen_skew,
            " skew_se=", skew_se)
  }
  
  # ---- Concurrent diagnostics ----
  message("\n=== Concurrent Record Diagnostics ===")
  diag_concurrent <- compute_concurrent_diagnostics(
    inputs$all_peaks, cfg$target_gage_id, cfg$index_gage_ids
  )
  
  # ---- MOVE.3 extension with each index gage ----
  message("\n=== Running MOVE.3 Extensions ===")
  extensions <- cfg$index_gage_ids %>%
    imap(function(gid, label) {
      message("\n--- MOVE.3 using ", label, " (", gid, ") as index ---")
      move3_extend(
        target_peaks  = inputs$target_peaks,
        index_peaks   = inputs$index_peaks[[label]],
        max_extension = cfg$max_extension,
        method        = cfg$extension_method
      )
    })
  
  # Combine extended records and diagnostics across index gages
  all_extended_peaks <- extensions %>%
    imap_dfr(~ .x$extended_record %>% mutate(index_gage = .y))
  
  all_diagnostics <- extensions %>%
    imap_dfr(~ .x$diagnostics %>% mutate(index_gage = .y))
  
  # ---- Flood frequency on original record ----
  message("\n=== Flood Frequency — Original Record ===")
  n_target <- nrow(inputs$target_peaks %>%
                     filter(!is.na(peak_q_cfs), peak_q_cfs > 0))
  ff_original <- run_emafit_on_extended(
    inputs$target_peaks %>%
      transmute(water_year, peak_q_cfs, source = "observed"),
    label          = paste0("Original (", n_target, " yr)"),
    target_gage_id = cfg$target_gage_id,
    gen_skew       = gen_skew,
    skew_se        = skew_se,
    aeps           = cfg$aeps,
    confidence     = cfg$ema_confidence,
    weight_opt     = cfg$ema_weight_opt
  )
  
  # ---- Flood frequency on each extended record ----
  message("\n=== Flood Frequency — Extended Records ===")
  ff_extended_list <- extensions %>%
    imap(function(ext, label) {
      run_emafit_on_extended(
        ext$extended_record,
        label          = paste0("MOVE.3 via ", label),
        target_gage_id = cfg$target_gage_id,
        gen_skew       = gen_skew,
        skew_se        = skew_se,
        aeps           = cfg$aeps,
        confidence     = cfg$ema_confidence,
        weight_opt     = cfg$ema_weight_opt
      )
    })
  
  # ---- Inverse-variance weighted combination ----
  message("\n=== Inverse-Variance Weighted Combination ===")
  ff_weighted <- combine_inverse_variance(ff_extended_list)
  
  # ---- Comparison table ----
  comparison <- build_comparison_table(ff_original, ff_extended_list, ff_weighted)
  
  message("\n--- Flood Frequency Comparison ---")
  print(comparison$wide_table)
  message("\n--- % Change from Original ---")
  print(comparison$pct_change)
  
  # ---- Save ----
  save_move3_outputs(
    extended_peaks = all_extended_peaks,
    diagnostics    = all_diagnostics,
    all_ff         = comparison$all_ff,
    weighted_ff    = ff_weighted,
    comparison     = comparison,
    output_dir     = cfg$output_dir
  )
  
  # Return for interactive use
  list(
    inputs          = inputs,
    extensions      = extensions,
    ff_original     = ff_original,
    ff_extended     = ff_extended_list,
    ff_weighted     = ff_weighted,
    comparison      = comparison,
    diagnostics     = all_diagnostics,
    diag_concurrent = diag_concurrent
  )
}


# =============================================================================
# EXECUTE
# =============================================================================
# Full pipeline:
  move3_results <- run_move3_pipeline(config)
#
# --- Interactive testing ---
# Config is already in your environment after source(). Test any function:
#   inputs  <- load_move3_inputs(config$data_dir, config$target_gage_id,
#                                 config$index_gage_ids)
#   diag    <- compute_concurrent_diagnostics(inputs$all_peaks,
#                config$target_gage_id, config$index_gage_ids)
#   ext     <- move3_extend(inputs$target_peaks,
#                           inputs$index_peaks[["Umatilla"]],
#                           max_extension = config$max_extension)
#   ff      <- run_emafit_on_extended(ext$extended_record,
#                label = "test", target_gage_id = config$target_gage_id,
#                gen_skew = -0.07, skew_se = 0.424, aeps = config$aeps)
#   weighted <- combine_inverse_variance(list(ff1, ff2))
# =============================================================================
