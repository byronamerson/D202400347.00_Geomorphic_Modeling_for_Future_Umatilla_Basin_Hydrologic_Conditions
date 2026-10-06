# =============================================================================
# 03d_stream_power_context.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 1d: Stream Power Contextualization
# =============================================================================
#
# Purpose: Anchor Umatilla results in the broader geomorphic literature by
#          comparing computed unit stream power against published thresholds
#          for morphological response. This is not a statistical model — it's
#          a sanity check and interpretive framework.
#
# Specifically:
#   1. Compute omega at Q2 (already done in 02) and at observed flood peaks
#      associated with known avulsion events
#   2. Compare against published thresholds from Magilligan (1992),
#      Yochum et al. (2017), and Sholtes et al. (2018)
#   3. Compute longitudinal stream power gradient (does omega change abruptly
#      at avulsion-prone reaches?)
#   4. Report which reaches exceed which thresholds at Q2, Q10, Q50, Q100
#
# Inputs:
#   - data/reach_attributes.csv   (from 02)
#   - data/flood_frequency.csv    (from 01)
#   - data/gage_metadata.csv      (from 01)
#
# Outputs:
#   - data/phase1d_threshold_comparison.csv  — omega at multiple RIs per reach
#   - data/phase1d_omega_gradient.csv        — longitudinal omega gradient
#   - figures/phase1d_longitudinal_omega.png — omega profile with thresholds
#   - figures/phase1d_threshold_matrix.png   — heatmap: reaches × RI thresholds
#
# References:
#   Baker, V.R. & Costa, J.E. (1987). Flood power. In: Mayer & Nash (eds.),
#     Catastrophic Flooding, pp. 1-21. Allen & Unwin.
#   Magilligan, F.J. (1992). Thresholds and the spatial variability of flood
#     power during extreme floods. Geomorphology, 5(3-5), 373-390.
#   Miller, A.J. (1990). Flood hydrology and geomorphic effectiveness in the
#     central Appalachians. Earth Surface Processes and Landforms, 15, 119-134.
#   Nanson, G.C. & Hickin, E.J. (1986). A statistical analysis of bank
#     erosion and channel migration in western Canada. GSA Bulletin, 97, 497-504.
#   Sholtes, J.S. et al. (2018). Physical context for theoretical approaches
#     to sediment transport magnitude-frequency analysis in alluvial channels.
#     Water Resources Research, 54, 3007-3023.
#   Yochum, S.E. et al. (2017). Photographic guidance for selecting flow
#     resistance coefficients in high-gradient channels. USGS SIR 2017-5099.
#
# Style: Follows Tidyverse & Functional Programming Guidelines
# =============================================================================

library(tidyverse)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  # ---- Input files ----
  reach_attr_path  = "data/reach_attributes.csv",
  flood_freq_path  = "data/flood_frequency.csv",
  gage_meta_path   = "data/gage_metadata.csv",

  # ---- Output files ----
  output_dir       = "data/",
  figure_dir       = "plots/",
  threshold_csv    = "data/phase1d_threshold_comparison.csv",
  gradient_csv     = "data/phase1d_omega_gradient.csv",

  # ---- Physical constants (must match 02) ----
  gamma     = 9810,
  cfs_to_cms = 0.02832,
  ft_to_m   = 0.3048,

  # ---- Return intervals to compute omega at ----
  return_intervals = c(2, 5, 10, 50, 100),

  # ---- Published stream power thresholds (W/m²) ----
  # These bracket the range of morphological responses relevant to
  # the Umatilla. The thresholds come from field-calibrated studies.
  thresholds = tribble(
    ~threshold_wm2, ~response,                            ~source,
    230,            "Substantial widening (S<3%)",         "Yochum et al. 2017",
    300,            "Major morphological adjustment",      "Magilligan 1992; Miller 1990",
    480,            "Avulsions/braiding credible",         "Yochum et al. 2017",
    700,            "Numerous eroded banks very likely",   "Yochum et al. 2017"
  ),

  # ---- Plotting ----
  fig_width  = 12,
  fig_height = 7,
  fig_dpi    = 200
)

# =============================================================================
# 1. COMPUTE OMEGA AT MULTIPLE RETURN INTERVALS
# =============================================================================

compute_omega_multi_ri <- function(reach_tbl, flood_freq, gage_meta, cfg = config) {
  #' For each reach, compute unit stream power at multiple return intervals.
  #' Uses the same DA-scaling approach as 02 but at Q5, Q10, Q50, Q100
  #' in addition to Q2.
  #'
  #' omega = gamma * Q * S / w  (Baker & Costa, 1987)

  # Retrieve DA scaling exponent from saved model or re-estimate
  da_fit_path <- "data/da_scaling_fit.rds"
  if (file.exists(da_fit_path)) {
    da_fit <- read_rds(da_fit_path)
    alpha  <- coef(da_fit)[["log(drainage_area_sqmi)"]]
    message(sprintf("DA scaling alpha from saved model: %.3f", alpha))
  } else {
    # Re-estimate if model file not available
    q2_by_gage <- flood_freq %>%
      filter(return_period_yr == 2) %>%
      left_join(gage_meta %>% select(gage_id, drainage_area_sqmi), by = "gage_id")
    da_fit <- lm(log(q_cfs) ~ log(drainage_area_sqmi), data = q2_by_gage)
    alpha  <- coef(da_fit)[["log(drainage_area_sqmi)"]]
    message(sprintf("DA scaling alpha re-estimated: %.3f", alpha))
  }

  # Build lookup: gage_id × return_period → Q (cfs)
  q_lookup <- flood_freq %>%
    filter(return_period_yr %in% cfg$return_intervals) %>%
    select(gage_id, return_period_yr, q_cfs)

  # DA lookup
  da_lookup <- gage_meta %>%
    select(gage_id, da_gage_sqmi = drainage_area_sqmi)

  # For each reach × return interval, scale Q and compute omega
  reach_tbl %>%
    select(rs, rs_num, avg_width_ft, slope, assigned_gage,
           est_drainage_area_sqmi, confinement, has_avulsions) %>%
    crossing(return_period_yr = cfg$return_intervals) %>%
    left_join(q_lookup, by = c("assigned_gage" = "gage_id", "return_period_yr")) %>%
    left_join(da_lookup, by = c("assigned_gage" = "gage_id")) %>%
    mutate(
      # DA-scaled discharge at reach
      q_reach_cfs = q_cfs * (est_drainage_area_sqmi / da_gage_sqmi)^alpha,
      # Convert to SI and compute omega
      q_reach_cms = q_reach_cfs * cfg$cfs_to_cms,
      width_m     = avg_width_ft * cfg$ft_to_m,
      omega_wm2   = cfg$gamma * q_reach_cms * slope / width_m
    ) %>%
    select(rs, rs_num, return_period_yr, q_reach_cfs, omega_wm2,
           confinement, has_avulsions, slope, width_m) %>%
    arrange(rs_num, return_period_yr)
}

# =============================================================================
# 2. THRESHOLD EXCEEDANCE ANALYSIS
# =============================================================================

classify_threshold_exceedance <- function(omega_tbl, cfg = config) {
  #' For each reach × return interval, flag which published thresholds
  #' are exceeded. This gives a quick read on where the river has enough
  #' energy for different response modes.
  #'
  #' Interpretation (Magilligan 1992, Yochum et al. 2017):
  #'   omega > 300 W/m² at Q2 → chronic lateral adjustment expected
  #'   omega > 480 W/m² at Q10 → avulsions plausible during moderate floods
  #'   omega > 480 W/m² at Q2 → avulsions expected under bankfull conditions
  omega_tbl %>%
    crossing(cfg$thresholds) %>%
    mutate(exceeds = omega_wm2 > threshold_wm2) %>%
    select(rs, rs_num, return_period_yr, omega_wm2, threshold_wm2,
           response, source, exceeds, confinement, has_avulsions)
}

summarize_threshold_exceedance <- function(exceedance_tbl) {
  #' Summary: how many reaches exceed each threshold at each RI?
  exceedance_tbl %>%
    group_by(return_period_yr, threshold_wm2, response) %>%
    summarize(
      n_exceeds    = sum(exceeds),
      n_total      = n(),
      pct_exceeds  = 100 * n_exceeds / n_total,
      .groups = "drop"
    ) %>%
    arrange(return_period_yr, threshold_wm2)
}

# =============================================================================
# 3. LONGITUDINAL STREAM POWER GRADIENT
# =============================================================================

compute_omega_gradient <- function(omega_tbl) {
  #' Compute the longitudinal gradient of omega (W/m² per reach).
  #' Abrupt changes in omega may correspond to avulsion-prone locations
  #' where energy dissipation shifts from one process to another
  #' (Sholtes et al., 2018).
  omega_tbl %>%
    filter(return_period_yr == 2) %>%
    arrange(rs_num) %>%
    mutate(
      # Forward difference: change from this reach to the next upstream
      d_omega_upstream = lead(omega_wm2) - omega_wm2,
      # Normalized gradient (dimensionless)
      d_omega_pct      = d_omega_upstream / omega_wm2 * 100
    )
}

# =============================================================================
# 4. VISUALIZATION
# =============================================================================

plot_longitudinal_omega <- function(omega_tbl, cfg = config) {
  #' Longitudinal profile of unit stream power at multiple RIs.
  #' Annotate with literature thresholds (horizontal dashed lines).
  #' Highlight reaches with observed avulsions.
  #'
  #' Baker & Costa (1987): stream power as fundamental index of flood work.
  #' Magilligan (1992): ~300 W/m² threshold.
  #' Yochum et al. (2017): refined threshold suite.

  d <- omega_tbl %>%
    mutate(ri_label = paste0("Q", return_period_yr))

  ggplot(d, aes(x = rs_num, y = omega_wm2, color = ri_label)) +
    geom_line(linewidth = 0.8, alpha = 0.8) +
    geom_point(
      data = d %>% filter(has_avulsions),
      aes(shape = "Avulsion reach"), size = 2.5
    ) +
    # Literature thresholds
    geom_hline(
      data = cfg$thresholds,
      aes(yintercept = threshold_wm2, linetype = response),
      color = "grey40", linewidth = 0.4
    ) +
    scale_x_continuous(
      breaks = seq(1, 39, by = 2),
      labels = function(x) paste0("RS ", x)
    ) +
    scale_y_log10() +
    scale_linetype_manual(
      values = c(
        "Substantial widening (S<3%)"       = "dotted",
        "Major morphological adjustment"    = "dashed",
        "Avulsions/braiding credible"       = "longdash",
        "Numerous eroded banks very likely" = "solid"
      )
    ) +
    labs(
      x = "River Segment (downstream → upstream)",
      y = expression("Unit stream power ("*omega*", W/m"^2*")"),
      color = "Return interval",
      linetype = "Literature threshold",
      shape = NULL,
      title = "Phase 1d: Longitudinal Stream Power Profile",
      subtitle = "Umatilla River — omega at Q2 through Q100",
      caption = paste0(
        "Thresholds: Magilligan (1992), Miller (1990), Yochum et al. (2017)\n",
        "Stream power framework: Baker & Costa (1987)"
      )
    ) +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
      legend.position = "bottom",
      legend.box = "vertical",
      plot.caption = element_text(size = 8, color = "grey50")
    ) +
    guides(
      color    = guide_legend(nrow = 1),
      linetype = guide_legend(nrow = 2),
      shape    = guide_legend(nrow = 1)
    )
}

plot_threshold_heatmap <- function(exceedance_tbl) {
  #' Heatmap: reaches (rows) × return intervals (columns), colored by
  #' highest threshold exceeded. Gives a quick visual matrix of which
  #' reaches have enough energy for which response modes at which RIs.

  # Compute highest threshold exceeded per reach × RI
  highest <- exceedance_tbl %>%
    filter(exceeds) %>%
    group_by(rs_num, return_period_yr) %>%
    slice_max(threshold_wm2, n = 1) %>%
    ungroup() %>%
    mutate(response = factor(response, levels = c(
      "Substantial widening (S<3%)",
      "Major morphological adjustment",
      "Avulsions/braiding credible",
      "Numerous eroded banks very likely"
    )))

  ggplot(highest, aes(x = factor(return_period_yr), y = factor(rs_num))) +
    geom_tile(aes(fill = response), color = "white", linewidth = 0.3) +
    scale_fill_manual(
      values = c(
        "Substantial widening (S<3%)"       = "#fee08b",
        "Major morphological adjustment"    = "#fdae61",
        "Avulsions/braiding credible"       = "#f46d43",
        "Numerous eroded banks very likely" = "#d73027"
      ),
      drop = FALSE
    ) +
    scale_y_discrete(limits = rev(levels(factor(1:39)))) +
    labs(
      x = "Return interval (yr)",
      y = "River Segment",
      fill = "Highest threshold exceeded",
      title = "Phase 1d: Stream Power Threshold Exceedance Matrix",
      subtitle = "Umatilla River — which reaches exceed which thresholds?",
      caption = "Magilligan (1992), Yochum et al. (2017)"
    ) +
    theme_minimal(base_size = 10) +
    theme(
      legend.position = "bottom",
      plot.caption = element_text(size = 8, color = "grey50")
    )
}

# =============================================================================
# 5. PIPELINE
# =============================================================================

run_phase_1d <- function(cfg = config) {
  #' Execute Phase 1d stream power contextualization.

  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(cfg$figure_dir, recursive = TRUE, showWarnings = FALSE)

  # ---- Load data ----
  message("--- Loading inputs ---")
  reach_tbl  <- read_csv(cfg$reach_attr_path, show_col_types = FALSE) %>%
    mutate(assigned_gage = as.character(assigned_gage))
  flood_freq <- read_csv(cfg$flood_freq_path, show_col_types = FALSE) %>%
    mutate(gage_id = as.character(gage_id))
  gage_meta  <- read_csv(cfg$gage_meta_path, show_col_types = FALSE) %>%
    mutate(gage_id = as.character(gage_id))

  # ---- Compute omega at multiple RIs ----
  message("\n--- Computing omega at Q2, Q5, Q10, Q50, Q100 ---")
  omega_tbl <- compute_omega_multi_ri(reach_tbl, flood_freq, gage_meta, cfg)

  message("\n--- Omega summary at Q2 ---")
  omega_tbl %>%
    filter(return_period_yr == 2) %>%
    summarize(
      min   = min(omega_wm2, na.rm = TRUE),
      med   = median(omega_wm2, na.rm = TRUE),
      mean  = mean(omega_wm2, na.rm = TRUE),
      max   = max(omega_wm2, na.rm = TRUE)
    ) %>%
    print()

  # ---- Threshold exceedance ----
  message("\n--- Threshold exceedance analysis ---")
  message("  Magilligan (1992): 300 W/m² minimum for major adjustment")
  message("  Yochum et al. (2017): 230, 480, 700 W/m² from field surveys")
  exceedance <- classify_threshold_exceedance(omega_tbl, cfg)
  exceedance_summary <- summarize_threshold_exceedance(exceedance)
  print(exceedance_summary)

  # Save
  write_csv(omega_tbl, cfg$threshold_csv)
  message("Threshold comparison saved to: ", cfg$threshold_csv)

  # ---- Longitudinal gradient ----
  message("\n--- Longitudinal omega gradient ---")
  message("  (Sholtes et al. 2018: abrupt gradient changes → process transitions)")
  gradient <- compute_omega_gradient(omega_tbl)
  write_csv(gradient, cfg$gradient_csv)
  message("Gradient saved to: ", cfg$gradient_csv)

  # ---- Figures ----
  message("\n--- Generating figures ---")

  p_long <- plot_longitudinal_omega(omega_tbl, cfg)
  ggsave(file.path(cfg$figure_dir, "phase1d_longitudinal_omega.png"),
         p_long, width = cfg$fig_width, height = cfg$fig_height, dpi = cfg$fig_dpi)

  p_heat <- plot_threshold_heatmap(exceedance)
  ggsave(file.path(cfg$figure_dir, "phase1d_threshold_matrix.png"),
         p_heat, width = 8, height = 10, dpi = cfg$fig_dpi)

  message("\n--- Phase 1d complete ---")

  list(
    omega_tbl           = omega_tbl,
    exceedance          = exceedance,
    exceedance_summary  = exceedance_summary,
    gradient            = gradient
  )
}

# =============================================================================
# EXECUTE
# Run after 02_reach_attributes_and_scaling.R and 01 outputs exist.
# results_1d <- run_phase_1d()
# =============================================================================
