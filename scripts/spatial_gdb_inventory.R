# =============================================================================
# spatial_gdb_inventory.R
# DOGAMI Umatilla CMZ Geodatabase Inventory
# =============================================================================
#
# Purpose: Build a rough-and-ready tabular inventory of every layer and field
#          in the DOGAMI Umatilla County channel migration geodatabase.
#
# Specifically:
#   1. Enumerate all layers in Umatilla_Co_CMZ.gdb
#   2. Record field names, positions, and column classes for each layer
#   3. Expose per-layer header summaries for both all non-geometry fields and
#      the smaller set of user-facing fields after dropping Shape metrics
#
# Inputs:
#   - data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb
#
# Outputs:
#   - In-memory tibbles for interactive exploration:
#       * layer_catalog
#       * field_catalog
#       * attribute_catalog
#       * user_field_catalog
#       * attribute_headers_by_layer
#       * user_headers_by_layer
#
# Style: Exploratory script with explicit, reusable objects
# =============================================================================

library(sf)
library(dplyr)
library(tibble)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  gdb_path = "data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb"
)

# =============================================================================
# 1. TABULAR HELPERS
# =============================================================================

# Build a compact tibble from sf::st_layers() for all layers in a datasource.
# layer_info (sf_layers) -> tibble with one row per layer and summary metadata.
# Flatten geometry type vectors to readable strings and preserve layer order.
make_layer_catalog <- function(layer_info) {
  tibble(
    layer_name = layer_info$name,
    geometry_type = vapply(
      layer_info$geomtype,
      function(geometry_value) paste(geometry_value, collapse = ", "),
      character(1)
    ),
    feature_count = layer_info$features,
    field_count = layer_info$fields
  )
}

# Extract one row per field from an sf object that was already read from disk.
# layer_data (sf), layer_name (character scalar) -> tibble with one row per field.
# Record geometry and Shape metrics explicitly so downstream summaries can filter them.
make_field_catalog <- function(layer_data, layer_name) {
  field_names <- names(layer_data)
  geometry_field <- attr(layer_data, "sf_column")

  tibble(
    layer_name = layer_name,
    field_position = seq_along(field_names),
    field_name = field_names,
    field_class = vapply(layer_data, function(column) class(column)[1], character(1))
  ) %>%
    mutate(
      is_geometry = field_name == geometry_field,
      is_shape_metric = field_name %in% c(
        "Shape_Length",
        "SHAPE_Length",
        "Shape_Area",
        "SHAPE_Area"
      ),
      is_user_field = !is_geometry & !is_shape_metric
    )
}

# Collapse a field catalog into one row per layer with header summaries.
# field_catalog (tibble), count_name/name_prefix (character scalars) -> tibble by layer.
# Keep both list-columns and comma-delimited text so the output works in scripts and viewers.
make_layer_header_summary <- function(field_catalog, count_name, name_prefix) {
  if (nrow(field_catalog) == 0L) {
    empty_summary <- tibble(
      layer_name = character(),
      n_fields = integer(),
      header_names = list(),
      header_names_csv = character()
    )

    names(empty_summary) <- c(
      "layer_name",
      count_name,
      paste0(name_prefix, "_names"),
      paste0(name_prefix, "_names_csv")
    )

    return(empty_summary)
  }

  header_summary <- field_catalog %>%
    group_by(layer_name) %>%
    summarise(
      n_fields = n(),
      header_names = list(field_name),
      header_names_csv = paste(field_name, collapse = ", "),
      .groups = "drop"
    )

  names(header_summary) <- c(
    "layer_name",
    count_name,
    paste0(name_prefix, "_names"),
    paste0(name_prefix, "_names_csv")
  )

  header_summary
}

# Read every layer from the geodatabase and assemble tabular inventory objects.
# gdb_path (character scalar path) -> named list of tibbles describing layers and fields.
# Keep all datasource reads here so helper functions stay focused on tabular transforms.
summarize_gdb_schema <- function(gdb_path) {
  stopifnot(file.exists(gdb_path))

  layer_info <- st_layers(gdb_path)
  layer_catalog <- make_layer_catalog(layer_info)

  layer_objects <- stats::setNames(
    lapply(
      layer_catalog$layer_name,
      function(layer_name) {
        st_read(
          dsn = gdb_path,
          layer = layer_name,
          quiet = TRUE
        )
      }
    ),
    layer_catalog$layer_name
  )

  field_catalog <- bind_rows(
    lapply(
      names(layer_objects),
      function(layer_name) {
        make_field_catalog(
          layer_data = layer_objects[[layer_name]],
          layer_name = layer_name
        )
      }
    )
  )

  attribute_catalog <- field_catalog %>%
    filter(!is_geometry)

  user_field_catalog <- field_catalog %>%
    filter(is_user_field)

  attribute_headers_by_layer <- layer_catalog %>%
    left_join(
      make_layer_header_summary(
        field_catalog = attribute_catalog,
        count_name = "n_attribute_fields",
        name_prefix = "attribute"
      ),
      by = "layer_name"
    ) %>%
    mutate(
      n_attribute_fields = dplyr::coalesce(n_attribute_fields, 0L),
      attribute_names = lapply(attribute_names, function(x) if (is.null(x)) character() else x),
      attribute_names_csv = dplyr::coalesce(attribute_names_csv, "")
    )

  user_headers_by_layer <- layer_catalog %>%
    left_join(
      make_layer_header_summary(
        field_catalog = user_field_catalog,
        count_name = "n_user_fields",
        name_prefix = "user_field"
      ),
      by = "layer_name"
    ) %>%
    mutate(
      n_user_fields = dplyr::coalesce(n_user_fields, 0L),
      user_field_names = lapply(user_field_names, function(x) if (is.null(x)) character() else x),
      user_field_names_csv = dplyr::coalesce(user_field_names_csv, "")
    )

  list(
    layer_catalog = layer_catalog,
    field_catalog = field_catalog,
    attribute_catalog = attribute_catalog,
    user_field_catalog = user_field_catalog,
    attribute_headers_by_layer = attribute_headers_by_layer,
    user_headers_by_layer = user_headers_by_layer
  )
}

# =============================================================================
# 2. GEODATABASE INVENTORY
# =============================================================================

gdb_inventory <- summarize_gdb_schema(config$gdb_path)

layer_catalog <- gdb_inventory$layer_catalog
field_catalog <- gdb_inventory$field_catalog
attribute_catalog <- gdb_inventory$attribute_catalog
user_field_catalog <- gdb_inventory$user_field_catalog
attribute_headers_by_layer <- gdb_inventory$attribute_headers_by_layer
user_headers_by_layer <- gdb_inventory$user_headers_by_layer

