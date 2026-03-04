# =============================================================================
# 01c_move3_extension_and_weighting.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1c: MOVE.3 Record Extension & Inverse-Variance Weighting for
#           USGS 14020850 (Pendleton)
# =============================================================================
#
# Purpose: Address inflated flood quantiles at USGS 14020850 (Pendleton,
#          30 yr record) caused by capturing the large 2020 flood. Uses
#          MOVE.3 record extension (B17C Appendix 8) with two index gages,
#          then combines the two extended-record frequency curves via
#          inverse-variance weighting (B17C Appendix 9).
#
# Index Gages:
#   - 14033500 (Umatilla R near Umatilla): CORRECTED for McKay Dam
#     regulation via 01d. Using the corrected series removes the regulation
#     signal that would otherwise distort the inter-gage log-space
#     correlation. The corrected peaks represent the natural flow regime
#     at the downstream gage.
#   - 14020000 (Umatilla R above Meacham Cr, nr Gibbon): unregulated,
#     used as-is.
#
# Why corrected 14033500?
#   McKay Dam attenuates peaks at 14033500. When these attenuated peaks
#   are correlated with 14020850 (which is upstream of McKay Creek
#   confluence and unaffected by regulation), the regulation signal adds
#   noise to the MOVE.3 regression — the index gage's peaks are
#   systematically low relative to what the natural hydrologic
#   relationship would predict. Using the corrected series yields a
#   tighter, more physically defensible regression.
#
# Inputs (from 01, 01d):
#   data/peak_flows.csv                  — all three Umatilla gages (from 01)
#   data/reconstructed_peaks.csv         — corrected 14033500 peaks (from 01d)
#
# Outputs:
#   data/move3_extended_record.csv       — extended peak series for 14020850
#   data/move3_diagnostics.csv           — MOVE.3 regression diagnostics
#   data/move3_comparison.csv            — frequency comparison table
#
# Dependencies:
#   peakfq::emafit() (peakfq v8.0.0)
#
# Style: Follows Tidyverse & Functional Programming Guidelines
#        (Tidyverse_Functional_Programming_Guidelines_for_temperheic.md)
# =============================================================================

library(tidyverse)
library(peakfq)

# =============================================================================
# 1. CONFIGURATION
# =============================================================================

config <- tribble(
  ~parameter,              ~value,
  "target_gage_id",        "14020850",
  "index_corrected_id",    "14033500",
  "index_unregulated_id",  "14020000",
  "max_extension",         "26",
  "extension_method",      "most_recent",
  "regional_skew",         "-0.07",
  "regional_skew_se",      "0.424",
  "ema_eps",               "0.90",
  "ema_weight_opt",        "HWN",
  "ema_lo_thresh",         "0"
)

# AEPs for flood frequency (return periods 2, 5, 10, 25, 50, 100 yr)
AEPs <- c(0.5, 0.2, 0.1, 0.04, 0.02, 0.01)

# Helper to pull typed values from config
cfg <- function(param) {
  config %>% filter(parameter == param) %>% pull(value)
}
cfg_num <- function(param) as.numeric(cfg(param))


# =============================================================================
# 2. DATA LOADING
# =============================================================================

load_move3_inputs <- function(data_dir = "data/") {
  #' Load peak flow data for the target gage and both index gages.
  #'
  #' Target (14020850): read from peak_flows.csv (observed record).
  #' Index 14033500:     read from reconstructed_peaks.csv (corrected by 01d).
  #' Index 14020000:     read from peak_flows.csv (unregulated, as-is).
  #'
  #' @param data_dir Path to data directory
  #' @return Named list with target_peaks, index_corrected, index_unregulated
  
  peak_flows <- read_csv(
    file.path(data_dir, "peak_flows.csv"),
    col_types = cols(.default = col_guess(), gage_id = col_character())
  )
  
  corrected_peaks <- read_csv(
    file.path(data_dir, "reconstructed_peaks.csv"),
    col_types = cols(.default = col_guess())
  )
  
  target_id    <- cfg("target_gage_id")
  corrected_id <- cfg("index_corrected_id")
  unreg_id     <- cfg("index_unregulated_id")
  
  target_peaks <- peak_flows %>%
    filter(gage_id == target_id) %>%
    select(water_year, peak_q_cfs) %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)
  
  # Use the unregulated (corrected) peak series from 01d for 14033500.
  # The column is peak_q_unreg_cfs — the reconstructed natural peak.
  index_corrected <- corrected_peaks %>%
    select(water_year, peak_q_cfs = peak_q_unreg_cfs) %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)
  
  index_unregulated <- peak_flows %>%
    filter(gage_id == unreg_id) %>%
    select(water_year, peak_q_cfs) %>%
    filter(!is.na(peak_q_cfs), peak_q_cfs > 0)
  
  message("  Target (", target_id, "): ", nrow(target_peaks), " peaks, ",
          min(target_peaks$water_year), "–", max(target_peaks$water_year))
  message("  Index corrected (", corrected_id, "): ", nrow(index_corrected),
          " peaks, ", min(index_corrected$water_year), "–",
          max(index_corrected$water_year))
  message("  Index unregulated (", unreg_id, "): ", nrow(index_unregulated),
          " peaks, ", min(index_unregulated$water_year), "–",
          max(index_unregulated$water_year))
  
  list(
    target_peaks      = target_peaks,
    index_corrected   = index_corrected,
    index_unregulated = index_unregulated
  )
}


# =============================================================================
# 3. CONCURRENT PERIOD DIAGNOSTICS
# =============================================================================

summarize_concurrent <- function(target_peaks, index_peaks, index_label) {
  #' Compute log-space correlation and concurrent record summary between
  
  #' a target and index gage.
  #'
  #' @param target_peaks tibble with water_year, peak_q_cfs
  #' @param index_peaks  tibble with water_year, peak_q_cfs
  #' @param index_label  character label for reporting
  #' @return tibble with one row of concurrent period diagnostics
  
  concurrent <- inner_join(
    target_peaks %>% select(water_year, target_q = peak_q_cfs),
    index_peaks  %>% select(water_year, index_q  = peak_q_cfs),
    by = "water_year"
  )
  
  n <- nrow(concurrent)
  r <- cor(log10(concurrent$target_q), log10(concurrent$index_q))
  
  message("  ", index_label, ": ", n, " concurrent years, r(log) = ",
          round(r, 4))
  
  tibble(
    index_label    = index_label,
    n_concurrent   = n,
    year_min       = min(concurrent$water_year),
    year_max       = max(concurrent$water_year),
    r_log          = r
  )
}


# =============================================================================
# 4. MOVE.3 RECORD EXTENSION (Bulletin 17C, Appendix 8)
# =============================================================================

move3_extend <- function(target_peaks, index_peaks, max_extension,
                         method = "most_recent") {
  #' Extend a short peak flow record using MOVE.3 (Bulletin 17C App. 8).
  #'
  #' Uses the variance-preserving Matalas-Jacobs estimator:
  #'   Y_hat = y_bar + (sy/sx) * (X - x_bar)
  #' (NOT the OLS slope r*sy/sx, which would shrink variance.)
  #'
  #' @param target_peaks  tibble with water_year, peak_q_cfs (short record)
  #' @param index_peaks   tibble with water_year, peak_q_cfs (long record)
  #' @param max_extension max years to extend (B17C recommends <= n1)
  #' @param method        "most_recent" or "match_skew"
  #'
  #' @return list with:
  #'   extended_record — combined observed + estimated peaks
  #'   diagnostics     — regression stats, correlation, Matalas-Jacobs adjustments
  
  # ---- Concurrent period ----
  combined <- inner_join(
    target_peaks %>% select(water_year, target_q = peak_q_cfs),
    index_peaks  %>% select(water_year, index_q  = peak_q_cfs),
    by = "water_year"
  ) %>%
    mutate(
      log_target = log10(target_q),
      log_index  = log10(index_q)
    )
  
  n1    <- nrow(combined)
  x_bar <- mean(combined$log_index)
  y_bar <- mean(combined$log_target)
  sx    <- sd(combined$log_index)
  sy    <- sd(combined$log_target)
  r     <- cor(combined$log_index, combined$log_target)
  
  # ---- Non-concurrent years at index site ----
  non_concurrent <- index_peaks %>%
    filter(
      !water_year %in% combined$water_year,
      !is.na(peak_q_cfs), peak_q_cfs > 0
    ) %>%
    select(water_year, index_q = peak_q_cfs) %>%
    mutate(log_index = log10(index_q)) %>%
    arrange(desc(water_year))
  
  ne <- min(max_extension, nrow(non_concurrent))
  
  extension_years <- switch(
    method,
    most_recent = non_concurrent %>% slice_head(n = ne),
    {
      warning("method '", method, "' not implemented, using most_recent")
      non_concurrent %>% slice_head(n = ne)
    }
  )
  
  # ---- MOVE.3 variance-preserving regression ----
  b_move <- sy / sx
  
  extension_years <- extension_years %>%
    mutate(
      log_target_est = y_bar + b_move * (log_index - x_bar),
      target_q_est   = 10^log_target_est
    )
  
  # ---- Matalas-Jacobs moment adjustment ----
  n_total <- n1 + ne
  
  all_index <- bind_rows(
    combined        %>% select(water_year, log_index),
    extension_years %>% select(water_year, log_index)
  )
  x_bar_full <- mean(all_index$log_index)
  
  y_bar_adj <- y_bar + b_move * (x_bar_full - x_bar)
  sy2_adj   <- sy^2 * (1 + (ne / n_total) * (1 - r^2) *
                         (1 + (ne * (x_bar_full - x_bar)^2) /
                            ((n_total - 1) * sx^2)))
  
  message("    n1=", n1, " ne=", ne, " n_total=", n_total,
          " r=", round(r, 4), " b_move=", round(b_move, 4))
  message("    adj_mean=", round(y_bar_adj, 4),
          " adj_sd=", round(sqrt(sy2_adj), 4),
          " (orig_sd=", round(sy, 4), ")")
  
  # ---- Build extended record ----
  observed <- combined %>%
    transmute(water_year, peak_q_cfs = target_q, source = "observed")
  
  estimated <- extension_years %>%
    transmute(water_year, peak_q_cfs = target_q_est, source = "estimated")
  
  extended_record <- bind_rows(observed, estimated) %>%
    arrange(water_year)
  
  list(
    extended_record = extended_record,
    diagnostics = tibble(
      n_concurrent    = n1,
      n_extended      = ne,
      n_total         = n_total,
      r_log           = r,
      target_mean_log = y_bar,
      target_sd_log   = sy,
      adj_mean_log    = y_bar_adj,
      adj_sd_log      = sqrt(sy2_adj),
      index_mean_conc = x_bar,
      index_mean_full = x_bar_full,
      b_move          = b_move,
      extension_yr_min = min(extension_years$water_year),
      extension_yr_max = max(extension_years$water_year)
    )
  )
}


# =============================================================================
# 5. FLOOD FREQUENCY ON EXTENDED RECORDS (EMA / B17C)
# =============================================================================

run_emafit_on_record <- function(peak_record, label, target_gage_id,
                                 regional_skew, regional_skew_se,
                                 eps, weight_opt, lo_thresh, aeps) {
  #' Fit LP3 via EMA (B17C) to a peak flow record and return tidy quantiles.
  #'
  #' @param peak_record    tibble with water_year, peak_q_cfs
  #' @param label          character label for this method/run
  #' @param target_gage_id gage ID string
  #' @param regional_skew  regional skew coefficient
  #' @param regional_skew_se SE of regional skew
  #' @param eps            confidence interval coverage
  #' @param weight_opt     skew weighting option for emafit
  #' @param lo_thresh      low outlier threshold (0 triggers MGBT)
  #' @param aeps           numeric vector of annual exceedance probabilities
  #' @return tibble of quantile estimates with method label
  
  QT <- peak_record %>%
    transmute(
      ql    = peak_q_cfs,
      qu    = peak_q_cfs,
      tl    = 1,
      tu    = 1e20,
      dtype = 0L,
      peak_WY = water_year
    ) %>%
    as.data.frame()
  
  result <- emafit(
    QT        = QT,
    LOthresh  = lo_thresh,
    rG        = regional_skew,
    rGmse     = regional_skew_se^2,
    eps       = eps,
    weightOpt = weight_opt,
    AEPs      = aeps,
    site_no   = target_gage_id,
    quietly   = TRUE
  )
  
  lp3_summary <- result[[1]]
  freq <- result[[2]] %>%
    as_tibble() %>%
    mutate(
      return_period_yr = 1 / EXC_Prob,
      method           = label,
      record_length    = lp3_summary$RecordLength,
      weighted_skew    = lp3_summary$Skew
    )
  
  message("    ", label, ": n=", lp3_summary$RecordLength,
          " skew=", round(lp3_summary$Skew, 3))
  
  freq
}


# =============================================================================
# 6. INVERSE-VARIANCE WEIGHTED COMBINATION (B17C Appendix 9)
# =============================================================================

combine_frequency_curves <- function(ff_list) {
  #' Combine two or more frequency curves using inverse-variance weighting.
  #'
  #' @param ff_list list of tibbles from run_emafit_on_record(), each with
  #'                return_period_yr, Estimate, Variance columns
  #' @return tibble with weighted estimates
  
  bind_rows(ff_list) %>%
    group_by(return_period_yr, EXC_Prob) %>%
    summarize(
      Estimate = weighted.mean(Estimate, w = 1 / Variance),
      Variance = 1 / sum(1 / Variance),
      Conf_Low = NA_real_,
      Conf_Up  = NA_real_,
      .groups  = "drop"
    ) %>%
    mutate(
      method        = "Weighted MOVE.3 (both index)",
      record_length = NA_integer_,
      weighted_skew = NA_real_
    )
}


# =============================================================================
# 7. COMPARISON TABLE
# =============================================================================

build_comparison_table <- function(ff_original, ff_ext_corrected,
                                   ff_ext_unregulated, ff_weighted) {
  #' Build a tidy comparison of all frequency methods at key return periods.
  #'
  #' @return tibble with method, return_period_yr, estimate_cfs columns
  
  rps <- c(2, 5, 10, 25, 50, 100)
  
  all_methods <- bind_rows(
    ff_original, ff_ext_corrected, ff_ext_unregulated, ff_weighted
  ) %>%
    filter(return_period_yr %in% rps) %>%
    select(method, return_period_yr, estimate_cfs = Estimate,
           variance = Variance, record_length, weighted_skew)
  
  # Add percent change from original
  orig <- all_methods %>%
    filter(method == unique(ff_original$method)) %>%
    select(return_period_yr, orig_est = estimate_cfs)
  
  all_methods %>%
    left_join(orig, by = "return_period_yr") %>%
    mutate(
      pct_change = round(100 * (estimate_cfs - orig_est) / orig_est, 1)
    ) %>%
    select(-orig_est)
}


# =============================================================================
# 8. OUTPUT
# =============================================================================

save_move3_outputs <- function(extended_record, diagnostics, comparison,
                               output_dir = "data/") {
  #' Save MOVE.3 results as CSV files.
  #'
  #' @param extended_record tibble of extended peaks (observed + estimated)
  #' @param diagnostics     tibble of MOVE.3 regression diagnostics
  #' @param comparison      tibble of frequency comparison across methods
  
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(extended_record,
            file.path(output_dir, "move3_extended_record.csv"))
  write_csv(diagnostics,
            file.path(output_dir, "move3_diagnostics.csv"))
  write_csv(comparison,
            file.path(output_dir, "move3_comparison.csv"))
  
  message("  Saved: move3_extended_record.csv, move3_diagnostics.csv, ",
          "move3_comparison.csv")
}


# =============================================================================
# 9. DIAGNOSTIC PLOTS
# =============================================================================

plot_move3_regression <- function(target_peaks, index_peaks, index_label,
                                  extended_record) {
  #' Scatter plot of log(target) vs log(index) with MOVE.3 regression line
  #' and estimated extension points highlighted.
  #'
  #' @return ggplot object
  
  concurrent <- inner_join(
    target_peaks %>% select(water_year, target_q = peak_q_cfs),
    index_peaks  %>% select(water_year, index_q  = peak_q_cfs),
    by = "water_year"
  )
  
  estimated_yrs <- extended_record %>%
    filter(source == "estimated") %>%
    pull(water_year)
  
  est_points <- index_peaks %>%
    filter(water_year %in% estimated_yrs) %>%
    inner_join(
      extended_record %>% filter(source == "estimated") %>%
        select(water_year, est_target_q = peak_q_cfs),
      by = "water_year"
    )
  
  ggplot() +
    geom_point(
      data = concurrent,
      aes(x = log10(index_q), y = log10(target_q)),
      color = "steelblue", size = 2, alpha = 0.7
    ) +
    geom_point(
      data = est_points,
      aes(x = log10(peak_q_cfs), y = log10(est_target_q)),
      color = "tomato", shape = 17, size = 2, alpha = 0.7
    ) +
    geom_smooth(
      data = concurrent,
      aes(x = log10(index_q), y = log10(target_q)),
      method = "lm", formula = y ~ x, se = FALSE,
      color = "grey40", linetype = "dashed", linewidth = 0.5
    ) +
    labs(
      title = paste("MOVE.3 Regression — Index:", index_label),
      subtitle = paste("Blue = concurrent observed, Red = MOVE.3 estimates"),
      x = paste("log10(Q) at", index_label),
      y = "log10(Q) at 14020850"
    ) +
    theme_minimal()
}

plot_frequency_comparison <- function(comparison) {
  #' Bar chart comparing flood quantiles across methods.
  #'
  #' @return ggplot object
  
  comparison %>%
    mutate(
      return_period_yr = factor(return_period_yr),
      method = fct_inorder(method)
    ) %>%
    ggplot(aes(x = return_period_yr, y = estimate_cfs, fill = method)) +
    geom_col(position = "dodge", alpha = 0.8) +
    scale_fill_brewer(palette = "Set2") +
    scale_y_continuous(labels = scales::comma) +
    labs(
      title = "Flood Frequency Comparison — USGS 14020850 (Pendleton)",
      x = "Return Period (years)",
      y = "Peak Discharge (cfs)",
      fill = "Method"
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")
}


# =============================================================================
# 10. PIPELINE RUNNER
# =============================================================================

run_move3_extension <- function(data_dir = "data/", output_dir = "data/") {
  #' Execute the full MOVE.3 record extension pipeline.
  #'
  #' 1. Load target and index peak data
  #' 2. Report concurrent period diagnostics
  #' 3. Run MOVE.3 with each index gage
  #' 4. Fit EMA on original and both extended records
  #' 5. Combine via inverse-variance weighting
  #' 6. Build comparison table
  #' 7. Save outputs and diagnostic plots
  #'
  #' @param data_dir   directory containing input CSVs
  #' @param output_dir directory for output CSVs and plots
  #' @return list with extended_record, diagnostics, comparison, ff results
  
  message("\n=== 01c: MOVE.3 Record Extension for ", cfg("target_gage_id"), " ===")
  
  # ---- Load data ----
  message("\n--- Loading input data ---")
  inputs <- load_move3_inputs(data_dir)
  
  # ---- Concurrent period diagnostics ----
  message("\n--- Concurrent period diagnostics ---")
  diag_corrected <- summarize_concurrent(
    inputs$target_peaks, inputs$index_corrected,
    paste0(cfg("index_corrected_id"), " (corrected)")
  )
  diag_unregulated <- summarize_concurrent(
    inputs$target_peaks, inputs$index_unregulated,
    paste0(cfg("index_unregulated_id"), " (Gibbon)")
  )
  
  # ---- MOVE.3 extensions ----
  max_ext <- cfg_num("max_extension")
  ext_method <- cfg("extension_method")
  
  message("\n--- MOVE.3 using corrected ", cfg("index_corrected_id"),
          " as index ---")
  ext_corrected <- move3_extend(
    inputs$target_peaks, inputs$index_corrected,
    max_extension = max_ext, method = ext_method
  )
  
  message("\n--- MOVE.3 using ", cfg("index_unregulated_id"),
          " (Gibbon) as index ---")
  ext_unregulated <- move3_extend(
    inputs$target_peaks, inputs$index_unregulated,
    max_extension = max_ext, method = ext_method
  )
  
  # ---- EMA flood frequency ----
  message("\n--- Fitting EMA (B17C) ---")
  ema_args <- list(
    target_gage_id   = cfg("target_gage_id"),
    regional_skew    = cfg_num("regional_skew"),
    regional_skew_se = cfg_num("regional_skew_se"),
    eps              = cfg_num("ema_eps"),
    weight_opt       = cfg("ema_weight_opt"),
    lo_thresh        = cfg_num("ema_lo_thresh"),
    aeps             = AEPs
  )
  
  n_orig <- nrow(inputs$target_peaks)
  
  ff_original <- do.call(run_emafit_on_record, c(
    list(
      peak_record = inputs$target_peaks,
      label       = paste0("Original (", n_orig, " yr)")
    ),
    ema_args
  ))
  
  ff_ext_corrected <- do.call(run_emafit_on_record, c(
    list(
      peak_record = ext_corrected$extended_record,
      label       = paste0("MOVE.3 via ", cfg("index_corrected_id"),
                           " (corrected)")
    ),
    ema_args
  ))
  
  ff_ext_unregulated <- do.call(run_emafit_on_record, c(
    list(
      peak_record = ext_unregulated$extended_record,
      label       = paste0("MOVE.3 via ", cfg("index_unregulated_id"),
                           " (Gibbon)")
    ),
    ema_args
  ))
  
  # ---- Inverse-variance weighted combination ----
  message("\n--- Inverse-variance weighting (B17C App. 9) ---")
  ff_weighted <- combine_frequency_curves(
    list(ff_ext_corrected, ff_ext_unregulated)
  )
  
  # ---- Comparison table ----
  comparison <- build_comparison_table(
    ff_original, ff_ext_corrected, ff_ext_unregulated, ff_weighted
  )
  
  message("\n--- Frequency Comparison ---")
  comparison %>%
    select(method, return_period_yr, estimate_cfs, pct_change) %>%
    pivot_wider(
      names_from  = return_period_yr,
      values_from = c(estimate_cfs, pct_change),
      names_glue  = "{.value}_Q{return_period_yr}"
    ) %>%
    print()
  
  # ---- Assemble diagnostics ----
  diagnostics <- bind_rows(
    ext_corrected$diagnostics %>%
      mutate(index_gage = paste0(cfg("index_corrected_id"), " (corrected)")),
    ext_unregulated$diagnostics %>%
      mutate(index_gage = paste0(cfg("index_unregulated_id"), " (Gibbon)"))
  )
  
  # The weighted combination is the preferred extended record for
  # downstream use (RS 9–29 flood frequency)
  # Build the final record: observed peaks from 14020850 + the weighted
  # frequency curve for quantile estimation. For the actual extended
  # peak series, we use the corrected-index extension (primary) since
  # the inverse-variance weighting operates on the frequency estimates,
  # not on individual peak values.
  extended_record <- ext_corrected$extended_record %>%
    mutate(
      gage_id    = cfg("target_gage_id"),
      index_gage = paste0(cfg("index_corrected_id"), " (corrected)")
    ) %>%
    bind_rows(
      ext_unregulated$extended_record %>%
        filter(source == "estimated") %>%
        mutate(
          gage_id    = cfg("target_gage_id"),
          index_gage = paste0(cfg("index_unregulated_id"), " (Gibbon)")
        )
    ) %>%
    arrange(index_gage, water_year)
  
  # ---- Save outputs ----
  message("\n--- Saving outputs ---")
  save_move3_outputs(extended_record, diagnostics, comparison, output_dir)
  
  # ---- Diagnostic plots ----
  message("--- Generating diagnostic plots ---")
  
  p_reg_corrected <- plot_move3_regression(
    inputs$target_peaks, inputs$index_corrected,
    paste0(cfg("index_corrected_id"), " (corrected)"),
    ext_corrected$extended_record
  )
  p_reg_unregulated <- plot_move3_regression(
    inputs$target_peaks, inputs$index_unregulated,
    paste0(cfg("index_unregulated_id"), " (Gibbon)"),
    ext_unregulated$extended_record
  )
  p_comparison <- plot_frequency_comparison(comparison)
  
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  ggsave(file.path(output_dir, "move3_regression_corrected.png"),
         p_reg_corrected, width = 8, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "move3_regression_gibbon.png"),
         p_reg_unregulated, width = 8, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "move3_frequency_comparison.png"),
         p_comparison, width = 10, height = 6, dpi = 150)
  message("  Diagnostic plots saved.")
  
  # ---- Return ----
  list(
    extended_record    = extended_record,
    diagnostics        = diagnostics,
    comparison         = comparison,
    ff_original        = ff_original,
    ff_ext_corrected   = ff_ext_corrected,
    ff_ext_unregulated = ff_ext_unregulated,
    ff_weighted        = ff_weighted,
    concurrent_diag    = bind_rows(diag_corrected, diag_unregulated)
  )
}

# =============================================================================
# EXECUTE
# =============================================================================
move3_results <- run_move3_extension(data_dir = "data/", output_dir = "data/")
