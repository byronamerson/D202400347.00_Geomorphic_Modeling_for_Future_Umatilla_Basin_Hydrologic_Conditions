# =============================================================================
# 03c_avulsion_model.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1c: Avulsion Probability Model
# =============================================================================
#
# Purpose: Model how flood characteristics affect the probability of avulsion
#          events across 39 Umatilla River reaches. Avulsions represent an
#          episodic, threshold-driven reorganization process distinct from
#          continuous lateral migration (Phase 1a). Both are driven by
#          discharge but through different mechanisms at different timescales
#          (knowledge base Section 3.1 conceptual model).
#
# Model:
#   log(E[avulsion_count_i,t]) = log(interval_duration_t) + beta_0
#                                + beta_1 * Qpeak_t
#                                + beta_2 * N_floods_above_threshold_t
#                                + u_i
#
#   where:
#     - log(interval_duration) is an exposure offset (converts to rate model)
#     - u_i is a reach-level random intercept capturing geomorphic
#       predisposition independent of discharge
#     - Avulsion susceptibility categories from AHA notes serve as fixed-effect
#       covariates capturing what u_i would represent in a simpler model
#
# The negative binomial handles overdispersion from abundant zeros
# (25 of 39 reaches have no observed avulsions).
#
# Data situation:
#   ~14 reaches with observed avulsions, ~25 without
#   ~40-45 total avulsion events across ~70 years of record
#   Events bracketed by photo intervals (not exact dates)
#   Photo intervals range from 1-13 years (variable exposure)
#
# Approach:
#   1. Build a reach × photo-interval panel from avulsion period strings
#   2. Assign discharge metrics to each interval from gage records
#   3. Fit negative binomial GLM with offset for interval duration
#   4. Compare models with/without susceptibility categories as covariates
#   5. Test alternative: logistic regression on binary avulsion occurrence
#
# Inputs:
#   - data/reach_attributes.csv          (from 02)
#   - data/daily_flows.csv               (from 01)
#   - data/flood_frequency.csv           (from 01)
#   - data/gage_metadata.csv             (from 01)
#
# Outputs:
#   - data/phase1c_avulsion_panel.csv    — reach × interval panel with
#                                          avulsion counts and discharge metrics
#   - data/phase1c_model_comparison.csv  — model comparison table
#   - data/phase1c_best_fit.rds          — fitted model object
#   - figures/phase1c_avulsion_rate.png  — avulsion rate by discharge metric
#   - figures/phase1c_susceptibility.png — observed rates by susceptibility class
#
# References:
#   Costa, J.E. & O'Connor, J.E. (1995). Geomorphically effective floods.
#     In: Costa et al. (eds.), Natural and Anthropogenic Influences in Fluvial
#     Geomorphology. AGU Geophysical Monograph 89, pp. 45-56.
#   Magilligan, F.J. et al. (2015). The geomorphic function and characteristics
#     of large woody debris in low gradient rivers, coastal Maine, USA.
#     Geomorphology, 231, 234-247.
#   Yochum, S.E. et al. (2017). Photographic guidance for selecting flow
#     resistance coefficients in high-gradient channels. USGS SIR 2017-5099.
#     (~480 W/m² threshold for avulsions/braiding credible)
#   Burnham, K.P. & Anderson, D.R. (2002). Model Selection and Multimodel
#     Inference, 2nd ed. Springer.
#
# Style: Follows Tidyverse & Functional Programming Guidelines
# =============================================================================

library(tidyverse)
library(MASS)       # glm.nb for negative binomial

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  # ---- Input files ----
  reach_attr_path   = "data/reach_attributes.csv",
  daily_flows_path  = "data/daily_flows.csv",
  flood_freq_path   = "data/flood_frequency.csv",
  gage_meta_path    = "data/gage_metadata.csv",

  # ---- Output files ----
  output_dir        = "data/",
  figure_dir        = "figures/",
  panel_csv         = "data/phase1c_avulsion_panel.csv",
  model_comp_csv    = "data/phase1c_model_comparison.csv",
  best_fit_rds      = "data/phase1c_best_fit.rds",

  # ---- Photo interval dates ----
  # Aerial photo years used in DOGAMI CMZ study (O-25-10 Section 2.2).
  # USGS single-frame (1952-1981), NAIP/OSIP mosaics (1995-2024).
  photo_years = c(1952, 1964, 1974, 1981, 1995, 2000, 2005, 2009,
                  2011, 2012, 2014, 2016, 2017, 2022, 2024),

  # ---- Plotting ----
  fig_width  = 10,
  fig_height = 6,
  fig_dpi    = 200
)

# =============================================================================
# 1. BUILD AVULSION PANEL
# =============================================================================
# The avulsion data arrive as semicolon-delimited period strings per reach
# (e.g., "1981-1995; 2019-2020 (two avulsions)"). We need to expand these
# into a full reach × photo-interval panel.

build_photo_intervals <- function(photo_years) {
  #' Create a tibble of consecutive photo intervals.
  #' Each row is one interval with start year, end year, and duration.
  tibble(
    interval_start = photo_years[-length(photo_years)],
    interval_end   = photo_years[-1]
  ) %>%
    mutate(
      interval_id   = row_number(),
      duration_yr   = interval_end - interval_start,
      # Midpoint for assigning discharge metrics
      interval_mid  = (interval_start + interval_end) / 2
    )
}

parse_avulsion_events <- function(reach_tbl, intervals) {
  #' Parse avulsion period strings and assign events to photo intervals.
  #' Returns a tibble of (rs_num, interval_id, avulsion_count).

  reaches_with_avulsions <- reach_tbl %>%
    filter(has_avulsions) %>%
    select(rs_num, avulsion_periods)

  # For each reach with avulsions, parse the period string and match
  # to the closest photo interval
  events <- reaches_with_avulsions %>%
    mutate(
      parsed = map(avulsion_periods, function(text) {
        if (is.na(text) || text == "N/A") return(tibble())

        entries <- str_split(text, ";")[[1]] %>% str_trim()

        map_dfr(entries, function(entry) {
          # Extract year range (e.g., "1981-1995" or "2019-2020")
          years <- str_extract_all(entry, "\\d{4}")[[1]] %>% as.integer()
          if (length(years) < 2) return(tibble())

          # Count multiplier
          n <- if (str_detect(entry, regex("two|2x|\\(2\\)", ignore_case = TRUE))) {
            2L
          } else if (str_detect(entry, regex("three|3x|\\(3\\)", ignore_case = TRUE))) {
            3L
          } else {
            1L
          }

          tibble(period_start = years[1], period_end = years[2], n_events = n)
        })
      })
    ) %>%
    unnest(parsed) %>%
    select(rs_num, period_start, period_end, n_events)

  # Match each parsed event to the best-fitting photo interval
  events %>%
    mutate(
      interval_id = map2_int(period_start, period_end, function(s, e) {
        # Find interval that best matches the observed period
        diffs <- abs(intervals$interval_start - s) + abs(intervals$interval_end - e)
        which.min(diffs)
      })
    ) %>%
    group_by(rs_num, interval_id) %>%
    summarize(avulsion_count = sum(n_events), .groups = "drop")
}

build_avulsion_panel <- function(reach_tbl, cfg = config) {
  #' Build the full reach × interval panel.
  #' Every reach gets a row for every photo interval.
  #' Avulsion counts default to 0 where no events observed.

  intervals <- build_photo_intervals(cfg$photo_years)

  # Parse known avulsion events
  known_events <- parse_avulsion_events(reach_tbl, intervals)

  # Cross-join all reaches with all intervals
  panel <- reach_tbl %>%
    select(rs_num, rs, confinement, avulsion_susceptibility, omega_wm2,
           assigned_gage, sinuosity) %>%
    crossing(intervals) %>%
    # Left-join known events (fills NA for zero-event cells)
    left_join(known_events, by = c("rs_num", "interval_id")) %>%
    mutate(
      avulsion_count = replace_na(avulsion_count, 0L),
      has_avulsion   = avulsion_count > 0,
      log_duration   = log(duration_yr)   # offset for rate model
    )

  message(sprintf(
    "Avulsion panel: %d rows (%d reaches × %d intervals), %d total events",
    nrow(panel), n_distinct(panel$rs_num), n_distinct(panel$interval_id),
    sum(panel$avulsion_count)
  ))

  panel
}

# =============================================================================
# 2. DISCHARGE METRICS PER INTERVAL
# =============================================================================
# Extract flood characteristics for each photo interval from the daily
# flow record. These become predictors in the avulsion model.
#
# Costa & O'Connor (1995) and Magilligan et al. (2015) established that
# geomorphic effectiveness depends on the combination of peak magnitude
# and flow duration, not peak alone. We extract both peak and cumulative
# metrics to test which best predicts avulsion occurrence.

compute_interval_discharge_metrics <- function(daily_flows, gage_meta,
                                               flood_freq, intervals) {
  #' For each gage × photo interval, compute discharge summary metrics.
  #' Returns a tibble ready for joining to the avulsion panel.

  # Q2 thresholds (bankfull proxy) per gage
  q2_lookup <- flood_freq %>%
    filter(return_period_yr == 2) %>%
    select(gage_id, q2_cfs = q_cfs)

  daily_flows %>%
    # Assign each day to a photo interval
    mutate(year = as.integer(format(date, "%Y"))) %>%
    # Use crossing to find which interval each day falls into
    inner_join(
      intervals %>% select(interval_id, interval_start, interval_end),
      by = character(),   # cross join
      relationship = "many-to-many"
    ) %>%
    filter(year >= interval_start, year < interval_end) %>%
    # Join Q2 threshold for bankfull exceedance metrics
    left_join(q2_lookup, by = "gage_id") %>%
    # Compute metrics per gage × interval
    group_by(gage_id, interval_id) %>%
    summarize(
      # Peak discharge in interval
      q_peak_cfs          = max(daily_q_cfs, na.rm = TRUE),
      # Number of days above bankfull (Q2)
      n_days_above_q2     = sum(daily_q_cfs > q2_cfs, na.rm = TRUE),
      # Cumulative excess above Q2 (cfs-days) — geomorphic work proxy
      # per Costa & O'Connor (1995)
      cumul_excess_cfs_d  = sum(pmax(daily_q_cfs - q2_cfs, 0), na.rm = TRUE),
      # Number of distinct flood events above Q2
      # (count transitions from below to above threshold)
      n_flood_events_q2   = {
        above <- daily_q_cfs > q2_cfs
        above[is.na(above)] <- FALSE
        sum(diff(c(FALSE, above)) == 1)
      },
      # CV of daily flows (hydrologic variability)
      cv_daily_q          = sd(daily_q_cfs, na.rm = TRUE) /
                            mean(daily_q_cfs, na.rm = TRUE),
      n_days_record       = sum(!is.na(daily_q_cfs)),
      .groups = "drop"
    )
}

join_discharge_to_panel <- function(panel, discharge_metrics) {
  #' Join interval-specific discharge metrics to the avulsion panel.
  #' Each reach is assigned to a gage (from 02), so join on
  #' (assigned_gage = gage_id, interval_id).
  panel %>%
    left_join(
      discharge_metrics,
      by = c("assigned_gage" = "gage_id", "interval_id")
    )
}

# =============================================================================
# 3. MODEL FITTING
# =============================================================================

fit_avulsion_models <- function(panel) {
  #' Fit candidate negative binomial and logistic models.
  #' The NB models use log(duration) as an offset, converting to a rate model.
  #'
  #' Negative binomial is preferred over Poisson because the data are
  #' overdispersed (many zeros, occasional clusters of 2-3 events).

  # Filter to complete cases
  d <- panel %>%
    filter(!is.na(q_peak_cfs), !is.na(cumul_excess_cfs_d))

  # Scale predictors for numerical stability
  d <- d %>%
    mutate(
      q_peak_scaled     = q_peak_cfs / 1000,        # thousands of cfs
      cumul_excess_scaled = cumul_excess_cfs_d / 1e5, # hundred-thousands cfs-days
      n_events_scaled   = n_flood_events_q2
    )

  models <- list(
    # ---- Negative binomial with offset (primary approach) ----
    # M1: peak discharge only
    NB1_peak = tryCatch(
      glm.nb(avulsion_count ~ q_peak_scaled + offset(log_duration), data = d),
      error = function(e) { message("NB1 failed: ", e$message); NULL }
    ),

    # M2: peak + flood event count
    NB2_peak_events = tryCatch(
      glm.nb(avulsion_count ~ q_peak_scaled + n_events_scaled +
                offset(log_duration), data = d),
      error = function(e) { message("NB2 failed: ", e$message); NULL }
    ),

    # M3: peak + cumulative excess (Costa & O'Connor 1995 motivated)
    NB3_peak_cumul = tryCatch(
      glm.nb(avulsion_count ~ q_peak_scaled + cumul_excess_scaled +
                offset(log_duration), data = d),
      error = function(e) { message("NB3 failed: ", e$message); NULL }
    ),

    # M4: peak + susceptibility category (geomorphic predisposition)
    NB4_peak_suscept = tryCatch(
      glm.nb(avulsion_count ~ q_peak_scaled + avulsion_susceptibility +
                offset(log_duration), data = d),
      error = function(e) { message("NB4 failed: ", e$message); NULL }
    ),

    # M5: full model — peak + cumulative + susceptibility
    NB5_full = tryCatch(
      glm.nb(avulsion_count ~ q_peak_scaled + cumul_excess_scaled +
                avulsion_susceptibility + offset(log_duration), data = d),
      error = function(e) { message("NB5 failed: ", e$message); NULL }
    ),

    # ---- Logistic alternative (binary: any avulsion yes/no) ----
    LR1_peak = tryCatch(
      glm(has_avulsion ~ q_peak_scaled + log_duration, data = d,
          family = binomial),
      error = function(e) { message("LR1 failed: ", e$message); NULL }
    ),

    LR2_peak_suscept = tryCatch(
      glm(has_avulsion ~ q_peak_scaled + avulsion_susceptibility + log_duration,
          data = d, family = binomial),
      error = function(e) { message("LR2 failed: ", e$message); NULL }
    )
  )

  # Drop any that failed
  models <- compact(models)
  message(sprintf("Successfully fitted %d avulsion models", length(models)))
  models
}

compare_avulsion_models <- function(models) {
  #' Compare models via AIC (AICc where applicable).
  #' For mixed model families (NB vs logistic), report AIC within family.
  tibble(
    model   = names(models),
    family  = map_chr(models, ~ class(.x)[1]),
    k       = map_int(models, ~ length(coef(.x)) + 1),
    n       = map_int(models, ~ nobs(.x)),
    aic     = map_dbl(models, AIC),
    # Log-likelihood
    loglik  = map_dbl(models, logLik)
  ) %>%
    group_by(family) %>%
    mutate(
      delta_aic  = aic - min(aic),
      rel_lik    = exp(-0.5 * delta_aic),
      akaike_wt  = rel_lik / sum(rel_lik)
    ) %>%
    ungroup() %>%
    arrange(family, delta_aic) %>%
    select(-rel_lik)
}

# =============================================================================
# 4. VISUALIZATION
# =============================================================================

plot_avulsion_rate_by_discharge <- function(panel) {
  #' Scatterplot: avulsion rate (events/yr) vs peak discharge.
  #' Faceted by whether reach has historical avulsions.

  rates <- panel %>%
    filter(!is.na(q_peak_cfs)) %>%
    mutate(
      avulsion_rate = avulsion_count / duration_yr,
      has_historical = avulsion_susceptibility == "high_historical"
    )

  ggplot(rates, aes(x = q_peak_cfs / 1000, y = avulsion_rate)) +
    geom_point(aes(color = avulsion_susceptibility), alpha = 0.6, size = 2) +
    geom_smooth(method = "glm", method.args = list(family = "poisson"),
                se = TRUE, color = "steelblue", linewidth = 0.7) +
    facet_wrap(~ has_historical, labeller = labeller(
      has_historical = c("TRUE" = "Reaches with historical avulsions",
                         "FALSE" = "Reaches without")
    )) +
    labs(
      x = "Peak discharge in interval (thousands of cfs)",
      y = "Avulsion rate (events/yr)",
      color = "Susceptibility class",
      title = "Phase 1c: Avulsion Rate vs. Peak Discharge",
      subtitle = "Umatilla River — DOGAMI CMZ study (1952-2024)"
    ) +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")
}

plot_susceptibility_summary <- function(panel) {
  #' Bar chart: observed avulsion rates by susceptibility class.
  #' Provides sanity check that the classification scheme is informative.

  summary <- panel %>%
    group_by(avulsion_susceptibility) %>%
    summarize(
      total_events   = sum(avulsion_count),
      total_years    = sum(duration_yr),
      rate_per_yr    = total_events / total_years,
      n_reach_intervals = n(),
      .groups = "drop"
    ) %>%
    mutate(avulsion_susceptibility = fct_reorder(avulsion_susceptibility, rate_per_yr))

  ggplot(summary, aes(x = avulsion_susceptibility, y = rate_per_yr)) +
    geom_col(fill = "steelblue", alpha = 0.8) +
    geom_text(aes(label = sprintf("n=%d events", total_events)),
              hjust = -0.1, size = 3) +
    coord_flip() +
    labs(
      x = "Susceptibility class",
      y = "Observed avulsion rate (events / reach-year)",
      title = "Phase 1c: Avulsion Rates by Susceptibility Category",
      subtitle = "Classification from DOGAMI AHA notes"
    ) +
    theme_minimal(base_size = 11)
}

# =============================================================================
# 5. PIPELINE
# =============================================================================

run_phase_1c <- function(cfg = config) {
  #' Execute Phase 1c avulsion probability analysis.

  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$figure_dir, recursive = TRUE, showWarnings = FALSE)

  # ---- Load data ----
  message("--- Loading inputs ---")
  reach_tbl    <- read_csv(cfg$reach_attr_path, show_col_types = FALSE) %>%
    mutate(
      avulsion_susceptibility = factor(avulsion_susceptibility,
        levels = c("not_assessed", "low", "conducive_limited",
                   "conducive_throughout", "infrastructure_conditional",
                   "high_historical")
      )
    )
  daily_flows  <- read_csv(cfg$daily_flows_path, show_col_types = FALSE)
  flood_freq   <- read_csv(cfg$flood_freq_path, show_col_types = FALSE)
  gage_meta    <- read_csv(cfg$gage_meta_path, show_col_types = FALSE)

  # ---- Build panel ----
  message("\n--- Building avulsion panel ---")
  intervals <- build_photo_intervals(cfg$photo_years)
  panel     <- build_avulsion_panel(reach_tbl, cfg)

  # ---- Compute discharge metrics per interval ----
  message("\n--- Computing interval discharge metrics ---")
  message("  (Costa & O'Connor 1995: geomorphic effectiveness depends on")
  message("   peak magnitude AND flow duration, not peak alone)")
  discharge_metrics <- compute_interval_discharge_metrics(
    daily_flows, gage_meta, flood_freq, intervals
  )
  panel <- join_discharge_to_panel(panel, discharge_metrics)

  # Save panel
  write_csv(panel, cfg$panel_csv)
  message("Avulsion panel saved to: ", cfg$panel_csv)

  # ---- Fit models ----
  message("\n--- Fitting avulsion models ---")
  models <- fit_avulsion_models(panel)

  # ---- Compare ----
  message("\n--- Model comparison ---")
  comparison <- compare_avulsion_models(models)
  print(comparison)
  write_csv(comparison, cfg$model_comp_csv)
  message("Model comparison saved to: ", cfg$model_comp_csv)

  # ---- Select best NB model ----
  best_nb_name <- comparison %>%
    filter(family == "negbin") %>%
    slice_min(aic, n = 1) %>%
    pull(model)

  if (length(best_nb_name) > 0) {
    best_model <- models[[best_nb_name]]
    message(sprintf("\n--- Best NB model: %s ---", best_nb_name))
    print(summary(best_model))
    write_rds(best_model, cfg$best_fit_rds)
    message("Best model saved to: ", cfg$best_fit_rds)
  }

  # ---- Figures ----
  message("\n--- Generating figures ---")

  p_rate <- plot_avulsion_rate_by_discharge(panel)
  ggsave(file.path(cfg$figure_dir, "phase1c_avulsion_rate.png"),
         p_rate, width = cfg$fig_width, height = cfg$fig_height, dpi = cfg$fig_dpi)

  p_suscept <- plot_susceptibility_summary(panel)
  ggsave(file.path(cfg$figure_dir, "phase1c_susceptibility.png"),
         p_suscept, width = 8, height = 5, dpi = cfg$fig_dpi)

  message("\n--- Phase 1c complete ---")

  list(
    panel       = panel,
    models      = models,
    comparison  = comparison,
    best_model  = if (exists("best_model")) best_model else NULL
  )
}

# =============================================================================
# EXECUTE
# Run after 02_reach_attributes_and_scaling.R has produced reach_attributes.csv
# and 01_hydrology_acquisition.R has produced daily_flows.csv.
# results_1c <- run_phase_1c()
# =============================================================================
