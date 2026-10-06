# =============================================================================
# spatial_sandbox.R
# Umatilla River Spatial Sandbox
# =============================================================================
#
# Purpose: Provide a rough-and-ready workspace for exploring the DOGAMI
#          Umatilla River channel migration geodatabase before folding ideas
#          into the more rigorous project scripts.
#
# Specifically:
#   1. Read the two core DOGAMI feature classes used in downstream analysis:
#      Umatilla_River_HMA and Umatilla_River_CMZ
#   2. Expose lightweight summaries that help us understand the temporal and
#      segment structure of those layers
#   3. Keep the loading logic in one place so ad hoc inspection can build from
#      the same starting point each time
#
# Inputs:
#   - data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb
#
# Outputs:
#   - In-memory sf objects and summary tables for interactive exploration
#
# Style: Exploratory script with explicit, reusable objects
# =============================================================================

library(sf)
library(dplyr)
library(xml2)
library(tibble)
library(grDevices)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  gdb_path = "data_in/DOGAMI_Umatilla_CMZ/Umatilla_Co_CMZ.gdb",
  hma_layer = "Umatilla_River_HMA",
  cmz_layer = "Umatilla_River_CMZ"
)

# =============================================================================
# 1. READ CORE DOGAMI LAYERS
# =============================================================================

# Read the digitized wetted-channel polygons that form the time series of
# channel position through time.
hma <- st_read(
  dsn = config$gdb_path,
  layer = config$hma_layer,
  quiet = TRUE
)

# Read the segmented channel migration zone polygons that divide the river
# corridor into 39 analysis segments.
cmz <- st_read(
  dsn = config$gdb_path,
  layer = config$cmz_layer,
  quiet = TRUE
)

# =============================================================================
# 2. LIGHTWEIGHT EXPLORATORY SUMMARIES
# =============================================================================

# Purpose: Summarize the temporal coverage of the HMA polygons so we can see
# which aerial-photo years are represented and how many polygons occur in each.
# Inputs: `hma`, an sf object with a Year field
# Returns: A tibble with one row per year and the number of polygons in that year
# Key decisions: Keep geometry dropped here because this summary is for temporal
# inspection rather than spatial operations.
hma_years <- hma %>%
  st_drop_geometry() %>%
  count(Year, name = "n_polygons") %>%
  arrange(Year)

# Purpose: Summarize the CMZ segmentation so we can see which river segments are
# present and whether any segment identifiers repeat.
# Inputs: `cmz`, an sf object with a RIverSegment field
# Returns: A tibble with one row per segment identifier and its polygon count
# Key decisions: Preserve the original field name from DOGAMI even though the
# capitalization is unusual, so the sandbox mirrors source data exactly.
cmz_segments <- cmz %>%
  st_drop_geometry() %>%
  count(RIverSegment, name = "n_polygons") %>%
  arrange(RIverSegment)

# =============================================================================
# 3. QUICK REFERENCE OBJECTS
# =============================================================================

hma_fields <- names(st_drop_geometry(hma))
cmz_fields <- names(st_drop_geometry(cmz))

hma_crs <- st_crs(hma)
cmz_crs <- st_crs(cmz)

# =============================================================================
# 4. GOOGLE EARTH EXPORTS
# =============================================================================

# Purpose: Export HMA and CMZ polygons to Google Earth KML with readable
# placemark names and intentional styling.
# Inputs: `hma` and `cmz`, loaded from the DOGAMI geodatabase.
# Returns: KML files written to `data_out/google_earth/`.
# Key decisions:
#   - Write KML directly with xml2 so we control names and styles rather than
#     accepting GDAL defaults.
#   - Keep the workflow dataset-specific: HMA gets year-based labels and a
#     year ramp; CMZ gets unique segment-based labels and a simpler style.
#   - Reproject to WGS84 (EPSG:4326) before serializing coordinates because
#     Google Earth expects lon/lat coordinates.
#   - Exclude HMA row 21 because it is the merged polygon that should not
#     appear in the export.

google_earth_dir <- "data_out/google_earth"

dir.create(google_earth_dir, recursive = TRUE, showWarnings = FALSE)

# Purpose: Create stable placemark labels within groups, using the bare group
# value when it appears once and letter suffixes when it repeats.
# Inputs:
#   - values: vector used as the visible base label, such as Year or segment ID
# Returns:
#   - character vector such as "1952", "1964_a", "1964_b"
# Key decisions:
#   - Suffix repeated values with lowercase letters because that reads cleanly
#     in the Google Earth layer tree.
#   - Preserve the original group value in the label so the source meaning stays
#     visible to the user.
make_unique_labels_by_group <- function(values) {
  value_text <- as.character(values)

  tibble(value_text = value_text) %>%
    group_by(value_text) %>%
    mutate(
      group_size = n(),
      group_index = row_number(),
      suffix = letters[group_index],
      placemark_name = if_else(
        group_size == 1L,
        value_text,
        paste0(value_text, "_", suffix)
      )
    ) %>%
    ungroup() %>%
    pull(placemark_name)
}

# Purpose: Convert a standard R colour plus alpha to KML colour format.
# Inputs:
#   - colour: named colour or #RRGGBB value
#   - alpha: numeric opacity between 0 and 1
# Returns:
#   - character scalar in aabbggrr format for KML
# Key decisions:
#   - Convert through col2rgb so named colours and hex colours both work.
#   - KML uses alpha-blue-green-red byte order rather than RGB order.
hex_to_kml_colour <- function(colour, alpha = 1) {
  rgb_values <- grDevices::col2rgb(colour)
  red <- sprintf("%02x", rgb_values[1, 1])
  green <- sprintf("%02x", rgb_values[2, 1])
  blue <- sprintf("%02x", rgb_values[3, 1])
  alpha_hex <- sprintf("%02x", round(alpha * 255))

  paste0(alpha_hex, blue, green, red)
}

# Purpose: Build a style table for HMA so each year shares a consistent colour.
# Inputs:
#   - years: vector of HMA years after filtering
# Returns:
#   - tibble with one row per year and columns for style_id, line_colour,
#     fill_colour, line_width, fill_alpha
# Key decisions:
#   - Use one style per year rather than per polygon so repeated polygons from
#     the same year read as one temporal class.
#   - Use semi-transparent fills and darker outlines so overlapping channel
#     traces remain visible in Google Earth.
make_hma_style_table <- function(years) {
  unique_years <- sort(unique(years))
  n_years <- length(unique_years)

  if (n_years == 0L) {
    return(
      tibble(
        Year = numeric(),
        style_id = character(),
        line_colour = character(),
        fill_colour = character(),
        line_width = numeric(),
        fill_alpha = numeric()
      )
    )
  }

  fill_palette_values <- grDevices::hcl.colors(
    n = n_years,
    palette = "YlOrRd",
    rev = FALSE
  )
  line_palette_values <- grDevices::hcl.colors(
    n = n_years + 2L,
    palette = "YlOrRd",
    rev = FALSE
  )[seq_len(n_years) + 2L]

  tibble(
    Year = unique_years,
    style_id = paste0("hma_year_", unique_years),
    line_colour = line_palette_values,
    fill_colour = fill_palette_values,
    line_width = 2.5,
    fill_alpha = 0.22
  )
}

# Purpose: Build a simple style table for CMZ so polygons are readable in
# Google Earth without implying temporal meaning that does not exist there.
# Inputs: none
# Returns: one-row tibble with a shared style definition for CMZ polygons
# Key decisions:
#   - Keep CMZ styling calm and uniform for now.
#   - Prioritize unique names over elaborate colour encoding.
make_cmz_style_table <- function() {
  tibble(
    style_id = "cmz_default",
    line_colour = "#2c7fb8",
    fill_colour = "#7fcdbb",
    line_width = 2,
    fill_alpha = 0.20
  )
}

# Purpose: Prepare HMA polygons for Google Earth export.
# Inputs: `hma`, the source sf object
# Returns: sf object in EPSG:4326 with placemark_name and style_id columns
# Key decisions:
#   - Drop row 21 before any downstream naming or styling so it never appears
#     in the export.
#   - Derive visible names from Year, with suffixes for repeated years.
#   - Join a year-based style ID onto each feature so the writer can remain
#     generic.
make_hma_export_data <- function(hma) {
  hma_filtered <- hma %>%
    slice(-21)

  hma_style_table <- make_hma_style_table(hma_filtered$Year)

  hma_filtered %>%
    st_transform(4326) %>%
    st_cast("MULTIPOLYGON") %>%
    arrange(Year, Shape_Area) %>%
    mutate(
      placemark_name = make_unique_labels_by_group(Year)
    ) %>%
    left_join(
      hma_style_table %>% select(Year, style_id),
      by = "Year"
    )
}

# Purpose: Prepare CMZ polygons for Google Earth export.
# Inputs: `cmz`, the source sf object
# Returns: sf object in EPSG:4326 with placemark_name and style_id columns
# Key decisions:
#   - Use RIverSegment as the visible base label because it matches the source
#     segmentation concept.
#   - Prefix the segment identifier so the Google Earth layer tree reads more
#     clearly than a bare code alone.
#   - Add suffixes if segment IDs repeat so every placemark name is unique.
make_cmz_export_data <- function(cmz) {
  cmz %>%
    st_transform(4326) %>%
    st_cast("MULTIPOLYGON") %>%
    arrange(RIverSegment) %>%
    mutate(
      placemark_name = make_unique_labels_by_group(
        paste0("Segment_", RIverSegment)
      ),
      style_id = "cmz_default"
    )
}

# Purpose: Add KML <Style> nodes to a Document from a style table.
# Inputs:
#   - doc: xml2 node for the KML Document
#   - style_table: tibble with style_id, line_colour, fill_colour, line_width,
#     fill_alpha
# Returns: doc is modified in place
# Key decisions:
#   - Emit styles once at the document level and reference them from placemarks
#     with styleUrl so the KML stays compact and readable.
append_style_nodes <- function(doc, style_table) {
  for (i in seq_len(nrow(style_table))) {
    style_row <- style_table[i, ]

    style_node <- xml_add_child(doc, "Style", id = style_row$style_id)
    line_style <- xml_add_child(style_node, "LineStyle")
    poly_style <- xml_add_child(style_node, "PolyStyle")

    xml_add_child(
      line_style,
      "color",
      hex_to_kml_colour(style_row$line_colour, alpha = 1)
    )
    xml_add_child(line_style, "width", as.character(style_row$line_width))

    xml_add_child(
      poly_style,
      "color",
      hex_to_kml_colour(style_row$fill_colour, alpha = style_row$fill_alpha)
    )
    xml_add_child(poly_style, "outline", "1")
  }

  invisible(doc)
}

# Purpose: Convert a matrix of lon/lat coordinates to KML coordinate text.
# Inputs: matrix with X and Y columns
# Returns: single character string "lon,lat,0 lon,lat,0 ..."
# Key decisions:
#   - Use altitude 0 because these are plan-view polygons for Google Earth.
coords_to_kml <- function(coords) {
  paste(
    apply(coords[, 1:2, drop = FALSE], 1, function(row) {
      paste(row[1], row[2], 0, sep = ",")
    }),
    collapse = " "
  )
}

# Purpose: Serialize one polygon or multipolygon geometry into a Placemark.
# Inputs:
#   - geometry: one sf geometry object
#   - placemark_node: xml2 Placemark node
# Returns: placemark_node modified in place
# Key decisions:
#   - Handle polygons and multipolygons explicitly because both appear in common
#     sf workflows and Google Earth expects nested boundary rings in KML.
append_polygon_geometry <- function(geometry, placemark_node) {
  process_polygon <- function(polygon_geometry, parent_node) {
    polygon_node <- xml_add_child(parent_node, "Polygon")

    outer_boundary <- xml_add_child(polygon_node, "outerBoundaryIs")
    outer_ring <- xml_add_child(outer_boundary, "LinearRing")
    xml_add_child(
      outer_ring,
      "coordinates",
      coords_to_kml(polygon_geometry[[1]])
    )

    if (length(polygon_geometry) > 1) {
      for (ring_index in 2:length(polygon_geometry)) {
        inner_boundary <- xml_add_child(polygon_node, "innerBoundaryIs")
        inner_ring <- xml_add_child(inner_boundary, "LinearRing")
        xml_add_child(
          inner_ring,
          "coordinates",
          coords_to_kml(polygon_geometry[[ring_index]])
        )
      }
    }
  }

  geometry_type <- as.character(st_geometry_type(geometry))

  if (geometry_type == "POLYGON") {
    process_polygon(geometry, placemark_node)
  } else if (geometry_type == "MULTIPOLYGON") {
    multi_geometry <- xml_add_child(placemark_node, "MultiGeometry")
    for (polygon_index in seq_along(geometry)) {
      process_polygon(geometry[[polygon_index]], multi_geometry)
    }
  } else {
    stop("Only POLYGON and MULTIPOLYGON geometries are supported in this writer.")
  }

  invisible(placemark_node)
}

# Purpose: Write a styled polygon sf object to KML for Google Earth.
# Inputs:
#   - sf_object: prepared sf object with placemark_name and style_id columns
#   - style_table: table of styles referenced by style_id
#   - output_path: path to the KML file to write
#   - document_name: visible name shown in Google Earth
# Returns: writes a KML file to disk
# Key decisions:
#   - The writer assumes naming and styling were prepared upstream, keeping the
#     I/O boundary simple and the dataset-specific logic outside the writer.
write_polygon_kml <- function(sf_object, style_table, output_path, document_name) {
  kml <- read_xml('<kml xmlns="http://www.opengis.net/kml/2.2"></kml>')
  doc <- xml_add_child(kml, "Document")

  xml_add_child(doc, "name", document_name)

  bbox <- st_bbox(sf_object)
  centroid <- st_coordinates(st_centroid(st_as_sfc(bbox)))
  diagonal_distance <- sqrt(
    (bbox["xmax"] - bbox["xmin"])^2 + (bbox["ymax"] - bbox["ymin"])^2
  )
  view_range <- diagonal_distance * 111000 * 1.1

  look_at <- xml_add_child(doc, "LookAt")
  xml_add_child(look_at, "longitude", as.character(centroid[1, "X"]))
  xml_add_child(look_at, "latitude", as.character(centroid[1, "Y"]))
  xml_add_child(look_at, "altitude", "0")
  xml_add_child(look_at, "range", as.character(view_range))
  xml_add_child(look_at, "tilt", "0")
  xml_add_child(look_at, "heading", "0")

  append_style_nodes(doc, style_table)

  for (i in seq_len(nrow(sf_object))) {
    feature <- sf_object[i, ]
    placemark <- xml_add_child(doc, "Placemark")

    xml_add_child(placemark, "name", feature$placemark_name)
    xml_add_child(placemark, "styleUrl", paste0("#", feature$style_id))

    append_polygon_geometry(st_geometry(feature)[[1]], placemark)
  }

  write_xml(kml, output_path)
}

hma_for_google_earth <- make_hma_export_data(hma)
cmz_for_google_earth <- make_cmz_export_data(cmz)

hma_style_table <- make_hma_style_table(hma_for_google_earth$Year)
cmz_style_table <- make_cmz_style_table()

hma_kml_path <- file.path(google_earth_dir, "Umatilla_River_HMA.kml")
cmz_kml_path <- file.path(google_earth_dir, "Umatilla_River_CMZ.kml")

write_polygon_kml(
  sf_object = hma_for_google_earth,
  style_table = hma_style_table,
  output_path = hma_kml_path,
  document_name = "Umatilla_River_HMA"
)

write_polygon_kml(
  sf_object = cmz_for_google_earth,
  style_table = cmz_style_table,
  output_path = cmz_kml_path,
  document_name = "Umatilla_River_CMZ"
)
