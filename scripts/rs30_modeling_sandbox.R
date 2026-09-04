# =============================================================================
# rs30_modeling_sandbox.R
# RS 30 Modeling Sandbox
# =============================================================================
#
# Purpose: Provide a focused workspace for exploratory RS 30 response-forcing
#          modeling after the interval geometry, hydrology joins, and first-pass
#          plots have already been assembled in rs30_interval_sandbox.R.
#
# Continuity note:
#   - This script is intentionally downstream of scripts/rs30_interval_sandbox.R.
#   - The interval sandbox remains the place where we:
#       * build RS 30 consecutive HMA intervals
#       * compute polygon-overlay response metrics
#       * join interval peak-flow forcing data
#       * assemble first-pass exploratory plots
#   - This modeling sandbox is where we:
#       * winnow candidate response/forcing relationships
#       * compare simple model forms and exclusion rules
#       * examine sensitivity to influential intervals and obvious outliers
#       * clarify which objects and outputs deserve promotion into reusable
#         helper functions later
#
# Development note:
#   - We are still exploring rather than locking an analysis API.
#   - Keep objects explicit, inspectable, and easy to rename or delete.
#   - Once the modeling workflow stabilizes, the next step will be to factor the
#     durable pieces into roxygen-documented helpers with narrower contracts.
#
# Current modeling focus:
#   - Response: symmetric_change_ft2_per_year
#   - Forcing: interval maximum annual peak flow at Pendleton
#   - Candidate base model: ordinary least squares linear regression
#   - Planned sensitivity checks: exclusion-rule variants and robust-regression
#     comparison if the outlier influence remains material
# =============================================================================

library(dplyr)
library(ggplot2)
library(broom)

# =============================================================================
# 1. LOAD RS 30 INTERVAL PRODUCTS
# =============================================================================

source("scripts/rs30_interval_sandbox.R")

# rs30_plot_data is created upstream in the interval sandbox and is the current
# exploratory modeling table: one row per consecutive RS 30 HMA interval with
# available synthetic Pendleton peak-flow forcing.


# =============================================================================
# 2. MODELING STAGING AREA
# =============================================================================

# Placeholder objects will accumulate here as we test serial model variants.
# Keep the exploratory phase simple and legible before extracting functions.

rs30_model_data <- rs30_plot_data %>%
  # Analyst exclusion carried forward across the exploratory modeling phase:
  # the 2011-2012 interval appears spurious after air-photo review. The current
  # plan is to follow up with the dataset authors about how the 2009-2012 HMA
  # sequence was constructed before considering reinstatement.
  filter(!(year_t1 == 2011 & year_t2 == 2012)) %>%
  mutate(
    interval_label = paste0(year_t1, "-", year_t2)
  )


# =============================================================================
# 3. SERIAL LINEAR MODEL VARIANTS
# =============================================================================

# First-pass model family:
#   symmetric change rate ~ interval maximum annual peak flow
#
# Variant logic:
#   - all_intervals: use the full consecutive interval series with available
#     synthetic Pendleton peaks
#   - drop_2011_2012: remove the most visually extreme short-interval point
#   - drop_2011_2012_2016_2017: remove both visually unusual high-response points

rs30_model_variants <- list(
  all_intervals = rs30_model_data,
  drop_2011_2012 = rs30_model_data,
  drop_2011_2012_2016_2017 = rs30_model_data %>%
    filter(interval_label != "2016-2017")
)

rs30_symmetric_change_models <- lapply(
  rs30_model_variants,
  function(model_tbl) {
    lm(
      symmetric_change_ft2_per_year ~ q_peak_max_cfs,
      data = model_tbl
    )
  }
)

rs30_symmetric_change_tidy <- bind_rows(
  lapply(
    names(rs30_symmetric_change_models),
    function(model_variant) {
      broom::tidy(rs30_symmetric_change_models[[model_variant]]) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_symmetric_change_glance <- bind_rows(
  lapply(
    names(rs30_symmetric_change_models),
    function(model_variant) {
      broom::glance(rs30_symmetric_change_models[[model_variant]]) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_symmetric_change_augment <- bind_rows(
  lapply(
    names(rs30_symmetric_change_models),
    function(model_variant) {
      broom::augment(
        rs30_symmetric_change_models[[model_variant]],
        data = rs30_model_variants[[model_variant]]
      ) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_symmetric_change_variant_plot_data <- bind_rows(
  lapply(
    names(rs30_model_variants),
    function(model_variant) {
      rs30_model_variants[[model_variant]] %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  mutate(
    model_variant = factor(
      model_variant,
      levels = c(
        "all_intervals",
        "drop_2011_2012",
        "drop_2011_2012_2016_2017"
      )
    )
  )

rs30_plot_symmetric_change_serial_lm <- ggplot(
  rs30_symmetric_change_variant_plot_data,
  aes(
    x = q_peak_max_cfs,
    y = symmetric_change_ft2_per_year,
    label = interval_label
  )
) +
  geom_point(size = 2.8, color = "#2c7fb8") +
  geom_text(
    nudge_y = 0.02 * max(rs30_symmetric_change_variant_plot_data$symmetric_change_ft2_per_year, na.rm = TRUE),
    check_overlap = TRUE,
    size = 3
  ) +
  geom_smooth(
    method = "lm",
    se = FALSE,
    color = "#d95f0e",
    linewidth = 0.8
  ) +
  facet_wrap(~ model_variant, scales = "free") +
  labs(
    x = "Pendleton interval maximum annual peak flow (cfs)",
    y = "Symmetric change rate (ft^2/year)",
    title = "RS 30: Serial linear fits of symmetric change vs interval peak flow",
    subtitle = "Compare full data and two exclusion-rule sensitivity variants"
  ) +
  theme_minimal(base_size = 11)

rs30_new_area_models <- lapply(
  rs30_model_variants,
  function(model_tbl) {
    lm(
      new_area_ft2_per_year ~ q_peak_max_cfs,
      data = model_tbl
    )
  }
)

rs30_new_area_tidy <- bind_rows(
  lapply(
    names(rs30_new_area_models),
    function(model_variant) {
      broom::tidy(rs30_new_area_models[[model_variant]]) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_new_area_glance <- bind_rows(
  lapply(
    names(rs30_new_area_models),
    function(model_variant) {
      broom::glance(rs30_new_area_models[[model_variant]]) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_new_area_augment <- bind_rows(
  lapply(
    names(rs30_new_area_models),
    function(model_variant) {
      broom::augment(
        rs30_new_area_models[[model_variant]],
        data = rs30_model_variants[[model_variant]]
      ) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_plot_new_area_serial_lm <- ggplot(
  rs30_symmetric_change_variant_plot_data,
  aes(
    x = q_peak_max_cfs,
    y = new_area_ft2_per_year,
    label = interval_label
  )
) +
  geom_point(size = 2.8, color = "#2c7fb8") +
  geom_text(
    nudge_y = 0.02 * max(rs30_symmetric_change_variant_plot_data$new_area_ft2_per_year, na.rm = TRUE),
    check_overlap = TRUE,
    size = 3
  ) +
  geom_smooth(
    method = "lm",
    se = FALSE,
    color = "#d95f0e",
    linewidth = 0.8
  ) +
  facet_wrap(~ model_variant, scales = "free") +
  labs(
    x = "Pendleton interval maximum annual peak flow (cfs)",
    y = "New area rate (ft^2/year)",
    title = "RS 30: Serial linear fits of new area vs interval peak flow",
    subtitle = "Compare full data and two exclusion-rule sensitivity variants"
  ) +
  theme_minimal(base_size = 11)

rs30_abandoned_area_models <- lapply(
  rs30_model_variants,
  function(model_tbl) {
    lm(
      abandoned_area_ft2_per_year ~ q_peak_max_cfs,
      data = model_tbl
    )
  }
)

rs30_abandoned_area_tidy <- bind_rows(
  lapply(
    names(rs30_abandoned_area_models),
    function(model_variant) {
      broom::tidy(rs30_abandoned_area_models[[model_variant]]) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_abandoned_area_glance <- bind_rows(
  lapply(
    names(rs30_abandoned_area_models),
    function(model_variant) {
      broom::glance(rs30_abandoned_area_models[[model_variant]]) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_abandoned_area_augment <- bind_rows(
  lapply(
    names(rs30_abandoned_area_models),
    function(model_variant) {
      broom::augment(
        rs30_abandoned_area_models[[model_variant]],
        data = rs30_model_variants[[model_variant]]
      ) %>%
        mutate(
          model_variant = model_variant
        )
    }
  )
) %>%
  select(model_variant, everything())

rs30_plot_abandoned_area_serial_lm <- ggplot(
  rs30_symmetric_change_variant_plot_data,
  aes(
    x = q_peak_max_cfs,
    y = abandoned_area_ft2_per_year,
    label = interval_label
  )
) +
  geom_point(size = 2.8, color = "#2c7fb8") +
  geom_text(
    nudge_y = 0.02 * max(rs30_symmetric_change_variant_plot_data$abandoned_area_ft2_per_year, na.rm = TRUE),
    check_overlap = TRUE,
    size = 3
  ) +
  geom_smooth(
    method = "lm",
    se = FALSE,
    color = "#d95f0e",
    linewidth = 0.8
  ) +
  facet_wrap(~ model_variant, scales = "free") +
  labs(
    x = "Pendleton interval maximum annual peak flow (cfs)",
    y = "Abandoned area rate (ft^2/year)",
    title = "RS 30: Serial linear fits of abandoned area vs interval peak flow",
    subtitle = "Compare full data and two exclusion-rule sensitivity variants"
  ) +
  theme_minimal(base_size = 11)


# =============================================================================
# 4. RESPONSE MATRIX: FIRST-PASS LINEAR SCAN
# =============================================================================

# Keep this first matrix deliberately simple:
#   one forcing variable, multiple existing response metrics, ordinary least
#   squares only. The goal is to see whether any already-computed response
#   variable carries a clearer signal before adding transforms or new metrics.
#
# Exclusion note:
#   - The 2011-2012 interval has already been removed upstream from
#     rs30_model_data by analyst judgment after visual review of the source air
#     photos.
#   - The mapped magnitude of change around the 2009-2012 HMA sequence does not
#     appear commensurate with the associated peak-flow story in the current
#     data products, so this interval is treated as spurious for this scan.

rs30_response_matrix_data <- rs30_model_data

rs30_response_specs <- tribble(
  ~response_col,                         ~response_label,                             ~response_definition,
  "new_area_ft2_per_year",               "New area rate (ft^2/year)",                "area newly occupied per year",
  "abandoned_area_ft2_per_year",         "Abandoned area rate (ft^2/year)",          "area no longer occupied per year",
  "symmetric_change_ft2_per_year",       "Symmetric change rate (ft^2/year)",        "total changed footprint per year",
  "net_area_change_ft2_per_year",        "Net area change rate (ft^2/year)",         "net gain minus loss per year",
  "symmetric_change_ft2_per_year_per_ft","Reach-averaged change rate ((ft^2/year)/ft)","total changed footprint per year per ft",
  "jaccard_change",                      "Jaccard change (unitless)",                "1 - overlap / union"
)

rs30_response_matrix_models <- lapply(
  seq_len(nrow(rs30_response_specs)),
  function(i) {
    response_col <- rs30_response_specs$response_col[[i]]
    response_label <- rs30_response_specs$response_label[[i]]
    response_definition <- rs30_response_specs$response_definition[[i]]

    model_formula <- stats::as.formula(
      paste(response_col, "~ q_peak_max_cfs")
    )

    model_fit <- lm(
      formula = model_formula,
      data = rs30_response_matrix_data
    )

    list(
      response_col = response_col,
      response_label = response_label,
      response_definition = response_definition,
      formula = model_formula,
      fit = model_fit
    )
  }
)

names(rs30_response_matrix_models) <- rs30_response_specs$response_col

rs30_response_matrix_tidy <- bind_rows(
  lapply(
    rs30_response_matrix_models,
    function(model_info) {
      broom::tidy(model_info$fit) %>%
        mutate(
          response_col = model_info$response_col,
          response_label = model_info$response_label,
          response_definition = model_info$response_definition
        )
    }
  )
) %>%
  select(response_col, response_label, response_definition, everything())

rs30_response_matrix_glance <- bind_rows(
  lapply(
    rs30_response_matrix_models,
    function(model_info) {
      broom::glance(model_info$fit) %>%
        mutate(
          response_col = model_info$response_col,
          response_label = model_info$response_label,
          response_definition = model_info$response_definition
        )
    }
  )
) %>%
  select(response_col, response_label, response_definition, everything()) %>%
  arrange(desc(r.squared))

rs30_response_matrix_facet_labels <- rs30_response_specs %>%
  left_join(
    rs30_response_matrix_glance %>%
      select(response_col, r.squared, p.value),
    by = "response_col"
  ) %>%
  mutate(
    facet_label = paste0(
      response_label,
      "\n(",
      response_definition,
      ")",
      "\nR^2 = ",
      format(round(r.squared, 3), nsmall = 3),
      " | p = ",
      format(round(p.value, 3), nsmall = 3)
    )
  )

rs30_response_matrix_plot_data <- bind_rows(
  lapply(
    seq_len(nrow(rs30_response_specs)),
    function(i) {
      response_col <- rs30_response_specs$response_col[[i]]
      response_label <- rs30_response_specs$response_label[[i]]

      rs30_response_matrix_data %>%
        transmute(
          interval_label,
          q_peak_max_cfs,
          response_col = response_col,
          response_label = response_label,
          response_value = .data[[response_col]]
        )
    }
  )
) %>%
  left_join(
    rs30_response_matrix_facet_labels,
    by = "response_col"
  ) %>%
  mutate(
    facet_label = factor(
      facet_label,
      levels = rs30_response_matrix_facet_labels$facet_label
    )
  )

rs30_plot_response_matrix_lm <- ggplot(
  rs30_response_matrix_plot_data,
  aes(
    x = q_peak_max_cfs,
    y = response_value
  )
) +
  geom_point(size = 2.6, color = "#2c7fb8") +
  geom_text(
    aes(label = interval_label),
    check_overlap = TRUE,
    size = 2.8,
    vjust = -0.4
  ) +
  geom_smooth(
    aes(
      x = q_peak_max_cfs,
      y = response_value,
      group = 1
    ),
    method = "lm",
    se = FALSE,
    color = "#d95f0e",
    linewidth = 0.8,
    inherit.aes = FALSE
  ) +
  facet_wrap(~ facet_label, scales = "free") +
  labs(
    x = "Pendleton interval maximum annual peak flow (cfs)",
    y = "Response value",
    title = "RS 30: First-pass linear model scan across response variables",
    subtitle = "Existing interval response metrics regressed on interval maximum annual peak flow"
  ) +
  theme_minimal(base_size = 9) +
  theme(
    strip.text = element_text(size = 8, lineheight = 1.05)
  )

ggsave("plots/channel_migration_metrics_vs_discharge.png",
       rs30_plot_response_matrix_lm,
       width = 8,
       height = 6,
       units = "in")
