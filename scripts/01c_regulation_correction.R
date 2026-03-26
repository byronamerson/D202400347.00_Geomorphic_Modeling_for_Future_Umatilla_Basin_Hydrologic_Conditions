# =============================================================================
# 01c_regulation_correction.R
# Discharge-Channel Migration Analysis
# Phase 1c: Dam Regulation Correction for a Mainstem Gage
# =============================================================================
#
# Purpose: Reconstruct unregulated peak flows at a regulated mainstem gage
#          by estimating what a dammed tributary would have contributed
#          naturally (absent the dam) and adding the "regulation deficit"
#          back to observed peaks.
#
# Approach B — two sub-methods for the pre-inflow-gage period:
#
#   Method (i):  Statistical scaling — estimate natural tributary contribution
#                from pre-dam peak statistics scaled by concurrent mainstem
#                conditions (log-log regression with optional seasonal harmonic).
#
#   Method (ii): Mass-balance inversion — back-calculate reservoir inflow
#                from storage changes and observed releases:
#                Q_inflow = dS/dt + Q_release + losses
#
# Both methods are validated against the truth period (where above-reservoir
# inflow data exist), then the better-performing method is applied to the
# period without inflow data.
#
# Usage:   Edit the CONFIG section below, then either:
#            (a) source() and call run_regulation_correction(config)
#            (b) step through interactively.
#
# Output:  .csv files:
#            reconstructed_peaks.csv    — corrected peak series
#            cv_data.csv                — cross-validation data
#            cv_performance.csv         — performance metrics
#            correction_summary.csv     — summary by period/source
#          .rds file:
#            stat_fit.rds               — fitted lm model object (non-tabular)
#          .png diagnostic plots (4)
#
# Dependencies:
#   - peak_flows.csv              (from 01)
#   - {prefix}_daily_flows.csv    (from 01b — below-dam composite)
#   - {prefix}_above_reservoir_daily.csv  (from 01b — natural inflow)
#   - {prefix}_reservoir_storage.csv      (from 01b — storage AF)
#   - {prefix}_peak_flows.csv     (from 01b — USGS annual peaks)
#
# Style:   Follows Tidyverse & Functional Programming Guidelines
#          (Tidyverse_Functional_Programming_Guidelines_for_temperheic.md)
# =============================================================================

library(tidyverse)
library(lubridate)

# =============================================================================
# CONFIG — edit these values for a different dam/tributary system
# =============================================================================

config <- list(
  
  # ---- Mainstem gage to correct ----
  mainstem_gage_id = "14033500",
  
  # ---- Tributary file prefix (from 01b config$output_prefix) ----
  tributary_prefix = "mckay",
  
  # ---- Physical constants ----
  da_tributary_sqmi = 250,     # drainage area of tributary at dam
  da_mainstem_sqmi  = 2290,    # drainage area of mainstem gage
  
  # Pre-dam tributary peak statistics (unregulated annual peaks, cfs)
  # Used for context/QA — not directly in the correction algorithm.
  predam_peaks_cfs = c(910, 2000, 2200, 2680, 3250),
  
  # Dam construction year — peaks in water years <= this are pre-dam
  dam_end_year = 1927L,
  
  # ---- Event pairing ----
  # Days +/- around each mainstem peak to search for tributary peak/inflow
  peak_window_days = 14L,
  
  # ---- Method selection ----
  # NULL = auto-select by deficit-level NSE; or force:
  #   "statistical_scaling" or "mass_balance"
  preferred_method = NULL,
  
  # ---- Conversion constant ----
  af_to_cf = 43560,    # 1 acre-foot = 43560 ft^3
  
  # ---- Input / Output ----
  data_dir   = "data/",
  output_dir = "data/"
)


# =============================================================================
# 1. DATA LOADING
# =============================================================================

load_input_data <- function(data_dir, mainstem_gage_id, tributary_prefix) {
  #' Load pre-built datasets from 01 and 01b pipeline outputs.
  #'
  #' @param data_dir          Directory containing .csv files
  #' @param mainstem_gage_id  Gage ID to filter from peak_flows.csv
  #' @param tributary_prefix  Filename prefix from 01b (e.g., "mckay")
  #'
  #' Returns a named list with mainstem peaks and a joined tributary daily
  #' tibble containing below-dam release, above-reservoir inflow, and storage.
  
  peak_flows  <- read_csv(file.path(data_dir, "peak_flows.csv"),
                          show_col_types = FALSE)
  mcko_daily  <- read_csv(file.path(data_dir, paste0(tributary_prefix, "_daily_flows.csv")),
                          show_col_types = FALSE)
  myko_daily  <- read_csv(file.path(data_dir, paste0(tributary_prefix, "_above_reservoir_daily.csv")),
                          show_col_types = FALSE)
  mck_storage <- read_csv(file.path(data_dir, paste0(tributary_prefix, "_reservoir_storage.csv")),
                          show_col_types = FALSE)
  trib_peaks  <- read_csv(file.path(data_dir, paste0(tributary_prefix, "_peak_flows.csv")),
                          show_col_types = FALSE)
  
  # Join the three tributary daily records into one wide tibble keyed by date
  trib_joined <- mcko_daily %>%
    select(date, mcko_q_cfs = daily_q_cfs) %>%
    full_join(
      myko_daily %>% select(date, myko_q_cfs = daily_q_cfs),
      by = "date"
    ) %>%
    full_join(
      mck_storage %>% select(date, mck_storage_af = daily_af),
      by = "date"
    ) %>%
    arrange(date)
  
  message("  Tributary joined daily record: ", nrow(trib_joined), " days")
  message("    Below-dam coverage: ", sum(!is.na(trib_joined$mcko_q_cfs)), " days")
  message("    Above-reservoir coverage: ", sum(!is.na(trib_joined$myko_q_cfs)), " days")
  message("    Storage coverage: ", sum(!is.na(trib_joined$mck_storage_af)), " days")
  
  list(
    mainstem_peaks = peak_flows %>%
      filter(gage_id == mainstem_gage_id) %>%
      arrange(peak_date),
    trib_daily     = trib_joined,
    trib_peaks     = trib_peaks
  )
}


# =============================================================================
# 2. EVENT PAIRING — LINK MAINSTEM PEAKS TO TRIBUTARY RECORDS
# =============================================================================

extract_tributary_window <- function(peak_date, trib_daily, window_days) {
  #' For a single mainstem peak date, extract the tributary daily records
  #' in the surrounding window. Returns a tibble (possibly 0 rows).
  window_start <- peak_date - days(window_days)
  window_end   <- peak_date + days(window_days)
  
  trib_daily %>%
    filter(date >= window_start, date <= window_end)
}

safe_max <- function(x) {
  #' max() that returns NA instead of -Inf when all values are NA.
  x_clean <- x[!is.na(x)]
  if (length(x_clean) == 0) NA_real_ else max(x_clean)
}

compute_daily_massbalance_inflow <- function(window, af_to_cf) {
  #' Compute daily reservoir inflow from the mass-balance equation:
  #'   Q_in(t) = dS(t)/dt + Q_out(t)
  #'
  #' where dS/dt is the daily change in storage (AF/day -> cfs) and Q_out
  #' is the observed dam release. Evaporation/precip neglected during
  #' flood events (small relative to inflow).
  #'
  #' @param window   Tibble with date, mcko_q_cfs, mck_storage_af columns
  #' @param af_to_cf Conversion factor: acre-feet to cubic feet (43560)
  #'
  #' Returns a tibble with date and estimated inflow, or NULL if
  #' insufficient data.
  
  has_storage <- "mck_storage_af" %in% names(window) &&
    sum(!is.na(window$mck_storage_af)) >= 2
  has_release <- "mcko_q_cfs" %in% names(window) &&
    sum(!is.na(window$mcko_q_cfs)) >= 2
  
  if (!has_storage | !has_release) return(NULL)
  
  window %>%
    arrange(date) %>%
    mutate(
      ds_af_per_day = lead(mck_storage_af) - mck_storage_af,
      ds_cfs        = ds_af_per_day * af_to_cf / 86400,
      mb_inflow_cfs = ds_cfs + mcko_q_cfs
    ) %>%
    filter(!is.na(mb_inflow_cfs))
}

pair_peaks_with_tributary <- function(mainstem_peaks, trib_daily,
                                      window_days, af_to_cf) {
  #' For each mainstem peak, extract the peak above-reservoir inflow,
  #' peak below-dam release, storage change, and daily mass-balance
  #' inflow within the event window.
  #'
  #' @param mainstem_peaks  Peak flow tibble for the mainstem gage
  #' @param trib_daily      Joined tributary daily tibble (mcko, myko, mck)
  #' @param window_days     Days +/- around each peak date
  #' @param af_to_cf        Acre-feet to cubic-feet conversion constant
  #'
  #' Returns a tibble with one row per mainstem peak year, augmented with
  #' tributary event metrics (NA where data are unavailable).
  
  empty_event <- tibble(
    myko_peak_cfs      = NA_real_,
    mcko_peak_cfs      = NA_real_,
    mcko_at_peak_cfs   = NA_real_,
    storage_start_af   = NA_real_,
    storage_end_af     = NA_real_,
    delta_storage_af   = NA_real_,
    mb_inflow_peak_cfs = NA_real_,
    n_days_window      = 0L
  )
  
  local_window   <- window_days
  local_af_to_cf <- af_to_cf
  
  mainstem_peaks %>%
    mutate(
      trib_event = map(peak_date, ~ {
        window <- extract_tributary_window(.x, trib_daily,
                                           window_days = local_window)
        
        if (nrow(window) == 0) return(empty_event)
        
        myko_peak    <- safe_max(window$myko_q_cfs)
        mcko_peak    <- safe_max(window$mcko_q_cfs)
        mcko_at_date <- window %>%
          filter(date == .x) %>%
          pull(mcko_q_cfs) %>%
          first() %||% NA_real_
        
        storage_vals <- window$mck_storage_af[!is.na(window$mck_storage_af)]
        s_start <- if (length(storage_vals) > 0) first(storage_vals) else NA_real_
        s_end   <- if (length(storage_vals) > 0) last(storage_vals)  else NA_real_
        
        mb_series <- compute_daily_massbalance_inflow(window, local_af_to_cf)
        mb_peak   <- if (!is.null(mb_series) && nrow(mb_series) > 0)
          safe_max(mb_series$mb_inflow_cfs) else NA_real_
        
        tibble(
          myko_peak_cfs      = myko_peak,
          mcko_peak_cfs      = mcko_peak,
          mcko_at_peak_cfs   = mcko_at_date,
          storage_start_af   = s_start,
          storage_end_af     = s_end,
          delta_storage_af   = s_end - s_start,
          mb_inflow_peak_cfs = mb_peak,
          n_days_window      = nrow(window)
        )
      })
    ) %>%
    unnest(trib_event)
}


# =============================================================================
# 3. METHOD (i): STATISTICAL SCALING
# =============================================================================
# Estimate natural tributary peak contribution from mainstem peak magnitude
# using a regression trained on the truth period.
#
# Model: log10(inflow_peak) ~ log10(mainstem_peak) + peak_month_sin + peak_month_cos
#
# Retransformation uses Duan's (1983) smearing estimator.

fit_statistical_scaling_model <- function(paired_data) {
  #' Fit a log-log regression of above-reservoir peak inflow vs mainstem
  #' peak Q, with optional seasonal harmonic terms.
  #' Uses only years where above-reservoir data exist (the truth period).
  #' Returns a list with the fitted lm object, smearing factor, and metadata.
  
  training <- paired_data %>%
    filter(!is.na(myko_peak_cfs), myko_peak_cfs > 0, peak_q_cfs > 0) %>%
    mutate(
      peak_month     = month(peak_date),
      peak_month_rad = 2 * pi * peak_month / 12,
      peak_sin       = sin(peak_month_rad),
      peak_cos       = cos(peak_month_rad)
    )
  
  if (nrow(training) < 5) {
    warning("Fewer than 5 concurrent truth peak pairs — model unreliable")
  }
  
  if (nrow(training) >= 10) {
    mod_seasonal <- lm(
      log10(myko_peak_cfs) ~ log10(peak_q_cfs) + peak_sin + peak_cos,
      data = training
    )
    mod_simple <- lm(log10(myko_peak_cfs) ~ log10(peak_q_cfs), data = training)
    f_test <- anova(mod_simple, mod_seasonal)
    use_seasonal <- f_test$`Pr(>F)`[2] < 0.10
  } else {
    use_seasonal <- FALSE
  }
  
  if (use_seasonal) {
    mod <- mod_seasonal
    message("  Statistical model: seasonal terms INCLUDED (p = ",
            round(f_test$`Pr(>F)`[2], 4), ")")
  } else {
    mod <- lm(log10(myko_peak_cfs) ~ log10(peak_q_cfs), data = training)
    message("  Statistical model: simple log-log (no seasonal terms)")
  }
  
  residuals_log10 <- residuals(mod)
  smearing_factor <- mean(10^residuals_log10)
  
  message(sprintf("  Smearing factor: %.4f  (n = %d, R^2 = %.3f)",
                  smearing_factor, nrow(training), summary(mod)$r.squared))
  
  list(
    model           = mod,
    smearing_factor = smearing_factor,
    use_seasonal    = use_seasonal,
    training_n      = nrow(training),
    r_squared       = summary(mod)$r.squared
  )
}

predict_natural_tributary_statistical <- function(stat_fit, mainstem_peak_cfs,
                                                  peak_date = NULL) {
  #' Predict natural tributary peak inflow from the statistical model.
  #' Applies Duan's smearing correction for unbiased retransformation.
  
  newdata <- tibble(peak_q_cfs = mainstem_peak_cfs)
  
  if (stat_fit$use_seasonal && !is.null(peak_date)) {
    peak_month_rad <- 2 * pi * month(peak_date) / 12
    newdata <- newdata %>%
      mutate(peak_sin = sin(peak_month_rad),
             peak_cos = cos(peak_month_rad))
  } else if (stat_fit$use_seasonal && is.null(peak_date)) {
    warning("Seasonal model but no peak_date supplied — using annual average")
    newdata <- newdata %>% mutate(peak_sin = 0, peak_cos = 0)
  }
  
  log10_pred <- predict(stat_fit$model, newdata = newdata)
  as.numeric(10^log10_pred * stat_fit$smearing_factor)
}


# =============================================================================
# 4. METHOD (ii): MASS-BALANCE INVERSION
# =============================================================================
# Back-calculate daily reservoir inflow from storage changes and releases.
# The daily mass-balance inflow series is computed in
# compute_daily_massbalance_inflow() (Section 2) and the peak extracted
# during event pairing as mb_inflow_peak_cfs.
#
# Unlike a crude window-average approach, this reconstructs the full daily
# inflow hydrograph within each event window and takes the maximum.


# =============================================================================
# 5. CROSS-VALIDATION FRAMEWORK
# =============================================================================

run_cross_validation <- function(paired_data) {
  #' Run cross-validation on the truth period (years with above-reservoir data).
  #'
  #' Returns a list with cv_data (augmented truth-period tibble) and
  #' stat_fit (the fitted statistical model).
  
  truth_period <- paired_data %>%
    filter(!is.na(myko_peak_cfs), !is.na(mcko_peak_cfs),
           myko_peak_cfs > 0, peak_q_cfs > 0)
  
  message(sprintf("  Truth period: %d events with concurrent inflow + release",
                  nrow(truth_period)))
  
  stat_fit <- fit_statistical_scaling_model(truth_period)
  
  truth_period <- truth_period %>%
    mutate(
      deficit_observed_cfs  = myko_peak_cfs - mcko_peak_cfs,
      
      myko_pred_stat_cfs    = predict_natural_tributary_statistical(
        stat_fit, peak_q_cfs, peak_date
      ),
      deficit_pred_stat_cfs = myko_pred_stat_cfs - mcko_peak_cfs,
      
      myko_pred_mb_cfs      = mb_inflow_peak_cfs,
      deficit_pred_mb_cfs   = mb_inflow_peak_cfs - mcko_peak_cfs
    )
  
  n_neg_mb <- sum(truth_period$mb_inflow_peak_cfs < 0, na.rm = TRUE)
  n_na_mb  <- sum(is.na(truth_period$mb_inflow_peak_cfs))
  if (n_neg_mb > 0) {
    message(sprintf("  WARNING: %d events have negative mass-balance inflow", n_neg_mb))
  }
  if (n_na_mb > 0) {
    message(sprintf("  NOTE: %d truth events lack mass-balance estimates", n_na_mb))
  }
  
  list(cv_data = truth_period, stat_fit = stat_fit)
}

summarize_cv_performance <- function(cv_data) {
  #' Compute performance metrics for each method against observed deficits.
  #' Evaluates at both the deficit level and the inflow level (diagnostic).
  
  compute_metrics <- function(observed, predicted, method_name, level) {
    valid <- !is.na(observed) & !is.na(predicted)
    obs  <- observed[valid]
    pred <- predicted[valid]
    n    <- length(obs)
    
    if (n < 3) {
      return(tibble(method = method_name, level = level, n = n,
                    rmse = NA, bias = NA, nse = NA, r_squared = NA,
                    pct_bias = NA))
    }
    
    resid  <- pred - obs
    ss_res <- sum(resid^2)
    ss_tot <- sum((obs - mean(obs))^2)
    
    tibble(
      method    = method_name,
      level     = level,
      n         = n,
      rmse      = sqrt(mean(resid^2)),
      bias      = mean(resid),
      pct_bias  = 100 * mean(resid) / mean(obs),
      nse       = if (ss_tot > 0) 1 - ss_res / ss_tot else NA_real_,
      r_squared = cor(obs, pred)^2
    )
  }
  
  bind_rows(
    compute_metrics(cv_data$deficit_observed_cfs,
                    cv_data$deficit_pred_stat_cfs,
                    "statistical_scaling", "deficit"),
    compute_metrics(cv_data$deficit_observed_cfs,
                    cv_data$deficit_pred_mb_cfs,
                    "mass_balance", "deficit"),
    compute_metrics(cv_data$myko_peak_cfs,
                    cv_data$myko_pred_stat_cfs,
                    "statistical_scaling", "inflow"),
    compute_metrics(cv_data$myko_peak_cfs,
                    cv_data$myko_pred_mb_cfs,
                    "mass_balance", "inflow")
  )
}


# =============================================================================
# 6. QA CHECKS
# =============================================================================

qa_check_correction <- function(paired_data, cv_data) {
  #' Run QA checks on the paired data and cross-validation results.
  
  flags <- list()
  
  inverted <- cv_data %>% filter(myko_peak_cfs < mcko_peak_cfs)
  if (nrow(inverted) > 0) {
    message(sprintf("  QA: %d events where inflow < release (negative deficit):",
                    nrow(inverted)))
    message("       WY: ", paste(inverted$water_year, collapse = ", "))
    flags$inverted_deficit <- inverted
  }
  
  extreme <- cv_data %>% filter(deficit_observed_cfs > 3 * peak_q_cfs)
  if (nrow(extreme) > 0) {
    message(sprintf("  QA: %d events with deficit > 3x mainstem peak",
                    nrow(extreme)))
    flags$extreme_deficit <- extreme
  }
  
  neg_mb <- cv_data %>% filter(mb_inflow_peak_cfs < 0)
  if (nrow(neg_mb) > 0) {
    message(sprintf("  QA: %d events with negative MB inflow", nrow(neg_mb)))
    flags$negative_mb <- neg_mb
  }
  
  extrap <- paired_data %>%
    filter(is.na(myko_peak_cfs), peak_q_cfs > 0) %>%
    filter(peak_q_cfs > max(cv_data$peak_q_cfs, na.rm = TRUE) * 1.5 |
             peak_q_cfs < min(cv_data$peak_q_cfs, na.rm = TRUE) * 0.5)
  if (nrow(extrap) > 0) {
    message(sprintf("  QA: %d pre-truth peaks >50%% outside stat model training range",
                    nrow(extrap)))
    flags$extrapolation <- extrap
  }
  
  if (length(flags) == 0) message("  QA: All checks passed")
  flags
}


# =============================================================================
# 7. APPLY CORRECTION TO FULL RECORD
# =============================================================================

reconstruct_unregulated_peaks <- function(paired_data, stat_fit,
                                          cv_performance, dam_end_year,
                                          preferred_method = NULL) {
  #' Apply the regulation correction to all post-dam peaks.
  #'
  #' @param paired_data     Output of pair_peaks_with_tributary()
  #' @param stat_fit        Output of fit_statistical_scaling_model()
  #' @param cv_performance  Output of summarize_cv_performance()
  #' @param dam_end_year    Year dam construction completed
  #' @param preferred_method Override method selection. NULL = auto by NSE.
  
  if (is.null(preferred_method)) {
    preferred_method <- cv_performance %>%
      filter(level == "deficit", !is.na(nse)) %>%
      slice_max(nse, n = 1) %>%
      pull(method)
    message("Auto-selected method: ", preferred_method)
  }
  
  stat_predictions <- predict_natural_tributary_statistical(
    stat_fit,
    paired_data$peak_q_cfs,
    paired_data$peak_date
  )
  
  paired_data %>%
    mutate(
      period = case_when(
        water_year <= dam_end_year ~ "pre_dam",
        !is.na(myko_peak_cfs) & !is.na(mcko_peak_cfs) ~ "post_dam_with_truth",
        TRUE ~ "post_dam_no_truth"
      ),
      
      myko_est_stat_cfs = stat_predictions,
      myko_est_mb_cfs   = mb_inflow_peak_cfs,
      
      regulation_deficit_cfs = case_when(
        period == "pre_dam" ~ 0,
        
        period == "post_dam_with_truth" ~
          myko_peak_cfs - mcko_peak_cfs,
        
        period == "post_dam_no_truth" & preferred_method == "statistical_scaling" ~
          pmax(myko_est_stat_cfs - coalesce(mcko_peak_cfs, 0), 0),
        
        period == "post_dam_no_truth" & preferred_method == "mass_balance" &
          !is.na(myko_est_mb_cfs) ~
          pmax(myko_est_mb_cfs - coalesce(mcko_peak_cfs, 0), 0),
        
        # Fallback: if mass_balance selected but unavailable, use stat
        period == "post_dam_no_truth" & preferred_method == "mass_balance" &
          is.na(myko_est_mb_cfs) ~
          pmax(myko_est_stat_cfs - coalesce(mcko_peak_cfs, 0), 0),
        
        TRUE ~ NA_real_
      ),
      
      peak_q_unreg_cfs = peak_q_cfs + coalesce(regulation_deficit_cfs, 0),
      
      correction_source = case_when(
        period == "pre_dam"              ~ "none_predam",
        period == "post_dam_with_truth"  ~ "observed_truth",
        period == "post_dam_no_truth" & preferred_method == "mass_balance" &
          !is.na(myko_est_mb_cfs)        ~ "mass_balance",
        period == "post_dam_no_truth"    ~ "statistical_scaling",
        TRUE                             ~ "unknown"
      ),
      
      pct_correction = 100 * regulation_deficit_cfs / peak_q_unreg_cfs
    )
}


# =============================================================================
# 8. DIAGNOSTIC PLOTS
# =============================================================================

plot_cv_scatter <- function(cv_data) {
  #' Scatter plots of observed vs predicted regulation deficit for both methods.
  
  cv_long <- cv_data %>%
    select(water_year, peak_q_cfs, deficit_observed_cfs,
           statistical_scaling = deficit_pred_stat_cfs,
           mass_balance = deficit_pred_mb_cfs) %>%
    pivot_longer(
      cols = c(statistical_scaling, mass_balance),
      names_to = "method",
      values_to = "deficit_predicted_cfs"
    ) %>%
    filter(!is.na(deficit_predicted_cfs), !is.na(deficit_observed_cfs))
  
  ggplot(cv_long, aes(x = deficit_observed_cfs, y = deficit_predicted_cfs)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
    geom_point(aes(color = method), alpha = 0.7, size = 2.5) +
    geom_smooth(method = "lm", se = FALSE, linewidth = 0.5, color = "gray30") +
    facet_wrap(~method, scales = "free") +
    labs(
      title = "Cross-Validation: Observed vs Predicted Regulation Deficit",
      subtitle = "Truth period (above-reservoir inflow data available)",
      x = "Observed Deficit (inflow peak - release peak, cfs)",
      y = "Predicted Deficit (cfs)"
    ) +
    theme_minimal() +
    theme(legend.position = "none")
}

plot_cv_inflow <- function(cv_data) {
  #' Scatter plots of observed vs predicted natural inflow peak.
  
  cv_long <- cv_data %>%
    select(water_year, myko_peak_cfs,
           statistical_scaling = myko_pred_stat_cfs,
           mass_balance = myko_pred_mb_cfs) %>%
    pivot_longer(
      cols = c(statistical_scaling, mass_balance),
      names_to = "method",
      values_to = "myko_predicted_cfs"
    ) %>%
    filter(!is.na(myko_predicted_cfs), !is.na(myko_peak_cfs))
  
  ggplot(cv_long, aes(x = myko_peak_cfs, y = myko_predicted_cfs)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
    geom_point(aes(color = method), alpha = 0.7, size = 2.5) +
    facet_wrap(~method, scales = "free") +
    labs(
      title = "Cross-Validation: Observed vs Predicted Natural Inflow Peak",
      subtitle = "Above-reservoir truth vs statistical and mass-balance estimates",
      x = "Observed Inflow Peak (cfs)",
      y = "Predicted Natural Inflow (cfs)"
    ) +
    theme_minimal() +
    theme(legend.position = "none")
}

plot_reconstructed_peaks <- function(reconstructed, dam_end_year) {
  #' Time series of observed vs reconstructed peaks.
  
  ggplot(reconstructed, aes(x = water_year)) +
    geom_segment(
      aes(xend = water_year, y = peak_q_cfs, yend = peak_q_unreg_cfs),
      color = "gray70", linewidth = 0.3
    ) +
    geom_point(aes(y = peak_q_cfs, shape = "Observed (regulated)"),
               color = "steelblue", size = 1.8) +
    geom_point(aes(y = peak_q_unreg_cfs, shape = "Reconstructed (unregulated)",
                   color = correction_source), size = 1.8) +
    geom_vline(xintercept = dam_end_year, linetype = "dashed",
               color = "firebrick", linewidth = 0.5) +
    annotate("text", x = dam_end_year, y = Inf, label = "Dam\ncompleted",
             vjust = 1.5, hjust = -0.1, size = 3, color = "firebrick") +
    scale_shape_manual(values = c("Observed (regulated)" = 16,
                                  "Reconstructed (unregulated)" = 17)) +
    labs(
      title = "Mainstem Gage — Regulation Correction",
      subtitle = "Approach B: Natural flow reconstruction via tributary deficit",
      x = "Water Year",
      y = "Annual Peak Discharge (cfs)",
      shape = NULL, color = "Correction Source"
    ) +
    theme_minimal()
}

plot_deficit_timeseries <- function(reconstructed) {
  #' Time series of the regulation deficit, colored by source.
  
  reconstructed %>%
    filter(period != "pre_dam") %>%
    ggplot(aes(x = water_year, y = regulation_deficit_cfs,
               fill = correction_source)) +
    geom_col(alpha = 0.7, width = 0.8) +
    labs(
      title = "Regulation Deficit Over Time",
      subtitle = "How much peak flow the dam removed from each annual mainstem peak",
      x = "Water Year",
      y = "Regulation Deficit (cfs)",
      fill = "Source"
    ) +
    theme_minimal()
}


# =============================================================================
# 9. SAVE HELPERS
# =============================================================================

save_correction_outputs <- function(reconstructed, cv_data, cv_perf,
                                    stat_fit, correction_summary,
                                    output_dir) {
  #' Write all pipeline outputs.
  #' Per NOTE_data_format_standards.md:
  #'   .csv for tabular data
  #'   .rds only for stat_fit (fitted lm model object)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  write_csv(reconstructed,      file.path(output_dir, "reconstructed_peaks.csv"))
  write_csv(cv_data,            file.path(output_dir, "cv_data.csv"))
  write_csv(cv_perf,            file.path(output_dir, "cv_performance.csv"))
  write_csv(correction_summary, file.path(output_dir, "correction_summary.csv"))
  
  # stat_fit contains an lm model object — .rds justified
  write_rds(stat_fit, file.path(output_dir, "stat_fit.rds"))
  
  message("--- Correction outputs saved to: ", output_dir, " ---")
  message("    (.csv for tabular data, .rds for stat_fit model object only)")
}


# =============================================================================
# 10. EXECUTION PIPELINE
# =============================================================================

run_regulation_correction <- function(cfg = config) {
  #' Execute the full regulation correction pipeline.
  #'
  #' @param cfg  Config list (defaults to the top-level `config` object).
  
  output_dir <- cfg$output_dir
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # ---- Load data ----
  message("=== Loading input data ===")
  inputs <- load_input_data(cfg$data_dir, cfg$mainstem_gage_id,
                            cfg$tributary_prefix)
  
  # ---- Pair peaks with tributary data ----
  message("\n=== Pairing mainstem peaks with tributary event windows ===")
  message(sprintf("  Window: +/-%d days around each mainstem peak",
                  cfg$peak_window_days))
  
  paired <- pair_peaks_with_tributary(
    inputs$mainstem_peaks,
    inputs$trib_daily,
    window_days = cfg$peak_window_days,
    af_to_cf    = cfg$af_to_cf
  )
  
  n_with_myko <- sum(!is.na(paired$myko_peak_cfs))
  n_with_mb   <- sum(!is.na(paired$mb_inflow_peak_cfs))
  message(sprintf("  %d mainstem peaks total", nrow(paired)))
  message(sprintf("  %d have above-reservoir truth data", n_with_myko))
  message(sprintf("  %d have mass-balance estimates", n_with_mb))
  
  # ---- Cross-validation ----
  message("\n=== Cross-validation on truth period ===")
  cv_out   <- run_cross_validation(paired)
  cv_data  <- cv_out$cv_data
  stat_fit <- cv_out$stat_fit
  
  cv_perf <- summarize_cv_performance(cv_data)
  message("\n--- Cross-Validation Performance ---")
  print(cv_perf %>% filter(level == "deficit"))
  message("\n--- Inflow-Level Diagnostics ---")
  print(cv_perf %>% filter(level == "inflow"))
  
  # ---- QA checks ----
  message("\n=== QA Checks ===")
  qa_flags <- qa_check_correction(paired, cv_data)
  
  # ---- Reconstruct unregulated peaks ----
  message("\n=== Reconstructing unregulated peak series ===")
  reconstructed <- reconstruct_unregulated_peaks(
    paired, stat_fit, cv_perf,
    dam_end_year     = cfg$dam_end_year,
    preferred_method = cfg$preferred_method
  )
  
  n_corrected <- sum(reconstructed$regulation_deficit_cfs > 0, na.rm = TRUE)
  message(sprintf("  %d peaks corrected (deficit > 0)", n_corrected))
  
  # ---- Summary statistics ----
  message("\n--- Correction Summary by Period ---")
  correction_summary <- reconstructed %>%
    group_by(period, correction_source) %>%
    summarize(
      n_peaks             = n(),
      mean_obs_cfs        = round(mean(peak_q_cfs, na.rm = TRUE)),
      mean_unreg_cfs      = round(mean(peak_q_unreg_cfs, na.rm = TRUE)),
      mean_deficit_cfs    = round(mean(regulation_deficit_cfs, na.rm = TRUE)),
      max_deficit_cfs     = round(max(regulation_deficit_cfs, na.rm = TRUE)),
      mean_pct_correction = round(mean(pct_correction, na.rm = TRUE), 1),
      .groups = "drop"
    )
  print(correction_summary)
  
  # ---- Save outputs ----
  save_correction_outputs(
    reconstructed      = reconstructed,
    cv_data            = cv_data,
    cv_perf            = cv_perf,
    stat_fit           = stat_fit,
    correction_summary = correction_summary,
    output_dir         = output_dir
  )
  
  # ---- Diagnostic plots ----
  message("Generating diagnostic plots...")
  p_cv      <- plot_cv_scatter(cv_data)
  p_inflow  <- plot_cv_inflow(cv_data)
  p_peaks   <- plot_reconstructed_peaks(reconstructed, cfg$dam_end_year)
  p_deficit <- plot_deficit_timeseries(reconstructed)
  
  ggsave(file.path(output_dir, "regulation_cv_scatter.png"),
         p_cv, width = 10, height = 5, dpi = 150)
  ggsave(file.path(output_dir, "regulation_cv_inflow.png"),
         p_inflow, width = 10, height = 5, dpi = 150)
  ggsave(file.path(output_dir, "regulation_reconstructed_peaks.png"),
         p_peaks, width = 12, height = 6, dpi = 150)
  ggsave(file.path(output_dir, "regulation_deficit_timeseries.png"),
         p_deficit, width = 12, height = 5, dpi = 150)
  
  message("Diagnostic plots saved.")
  
  # Return for interactive use
  list(
    reconstructed      = reconstructed,
    cv_data            = cv_data,
    cv_performance     = cv_perf,
    stat_fit           = stat_fit,
    qa_flags           = qa_flags,
    correction_summary = correction_summary
  )
}


# =============================================================================
# EXECUTE
# =============================================================================
# Full pipeline:
  reg_results <- run_regulation_correction(config)
#
# --- Interactive testing ---
# Config is already in your environment after source(). Test any function:
#   inputs <- load_input_data(config$data_dir, config$mainstem_gage_id,
#                              config$tributary_prefix)
#   paired <- pair_peaks_with_tributary(inputs$mainstem_peaks, inputs$trib_daily,
#                                       window_days = config$peak_window_days,
#                                       af_to_cf = config$af_to_cf)
#   cv     <- run_cross_validation(paired)
#   perf   <- summarize_cv_performance(cv$cv_data)
#   recon  <- reconstruct_unregulated_peaks(paired, cv$stat_fit, perf,
#               dam_end_year = config$dam_end_year)
# =============================================================================
