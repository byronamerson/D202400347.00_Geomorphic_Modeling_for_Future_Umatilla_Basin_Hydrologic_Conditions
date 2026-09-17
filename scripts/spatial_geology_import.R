# =============================================================================
# spatial_geology_import.R
# USGS Surficial Geology Map Import (SIM 3527, GeMS shapefiles)
# =============================================================================
#
# Purpose: General-purpose reader for the USGS Umatilla River surficial
#   geology map (SIM 3527), exported from UmatillaMapping.gdb as GeMS-schema
#   shapefiles + companion CSVs. Reprojects every spatial layer to the DOGAMI
#   CMZ geodatabase's CRS so it shares a common frame with the rest of the
#   pipeline. Not specific to any downstream use (valley bottom, confinement
#   ratio, etc.) - just makes the dataset available for whatever comes next.
#
# Inputs:
#   - data_in/USGS_umatilla_surficial_geology/GeMS_shapefiles/
#       (native CRS: EPSG:26911, NAD83 UTM Zone 11N, meters)
#
# Output:
#   - In-memory named list for interactive exploration: geology
#       (geology$MapUnitPolys, geology$ContactsAndFaults, ...,
#        geology$DescriptionOfMapUnits, geology$DataSources, geology$Glossary)
#
# CRS note: target is EPSG:6557 (NAD83(2011) Oregon GIC Lambert, feet) -
#   confirmed to match Umatilla_Co_CMZ.gdb (Umatilla_River_CMZ /
#   Umatilla_River_AC / Umatilla_River_HMA all read as EPSG:6557).
#
# Style: Exploratory script with explicit, reusable objects (mirrors
#   spatial_gdb_inventory.R).
# =============================================================================

library(sf)
library(dplyr)
library(readr)
library(purrr)

# =============================================================================
# 0. CONFIGURATION
# =============================================================================

config <- list(
  geology_dir = "data_in/USGS_umatilla_surficial_geology/GeMS_shapefiles",
  target_crs  = 6557   # DOGAMI CMZ gdb CRS: NAD83(2011) Oregon GIC Lambert (ft)
)

# =============================================================================
# 1. READER
# =============================================================================

# Left-join a GeMS shapefile's full-attribute companion CSV onto its sf
# object by OBJECTID. Per GeMS_Shapefiles_readme.txt, shapefiles carry only a
# field subset (DBF limitations); the CSV has every field. No-op if no CSV
# exists for this layer.
# spatial (sf), dir_path (character scalar), layer_name (character scalar)
#   -> sf with any CSV-only columns added.
join_gems_attribute_csv <- function(spatial, dir_path, layer_name) {
  csv_path <- file.path(dir_path, paste0(layer_name, ".csv"))
  if (!file.exists(csv_path)) return(spatial)

  attrs <- read_csv(csv_path, show_col_types = FALSE)
  new_cols <- setdiff(names(attrs), names(spatial))
  if (length(new_cols) == 0L) return(spatial)

  spatial %>%
    left_join(attrs %>% select(OBJECTID, all_of(new_cols)), by = "OBJECTID")
}

# Read every shapefile in a GeMS shapefile export folder, reprojected to a
# common CRS, with each layer's full-attribute CSV joined back on; plus the
# CSV-only tables that have no shapefile counterpart (DescriptionOfMapUnits,
# DataSources, Glossary, GeoMaterialDict - schema/lookup tables, not features).
# dir_path (character scalar), target_crs (EPSG code) -> named list of sf
#   objects (spatial layers) and tibbles (lookup tables).
read_gems_shapefiles <- function(dir_path, target_crs) {
  stopifnot(dir.exists(dir_path))

  shp_paths <- list.files(dir_path, pattern = "\\.shp$", full.names = TRUE)
  shp_names <- tools::file_path_sans_ext(basename(shp_paths))

  spatial_layers <- map2(shp_paths, shp_names, function(path, layer_name) {
    st_read(path, quiet = TRUE) %>%
      st_transform(target_crs) %>%
      join_gems_attribute_csv(dir_path, layer_name)
  }) %>%
    set_names(shp_names)

  csv_paths  <- list.files(dir_path, pattern = "\\.csv$", full.names = TRUE)
  csv_names  <- tools::file_path_sans_ext(basename(csv_paths))
  table_only <- csv_names[!csv_names %in% shp_names]

  lookup_tables <- map(table_only, function(nm) {
    read_csv(file.path(dir_path, paste0(nm, ".csv")), show_col_types = FALSE)
  }) %>%
    set_names(table_only)

  c(spatial_layers, lookup_tables)
}

# =============================================================================
# 2. LOAD
# =============================================================================

geology <- read_gems_shapefiles(config$geology_dir, config$target_crs)

# ---- Verify --------------------------------------------------------------
cat("\n=== geology layers loaded ===\n")
cat(paste(names(geology), collapse = ", "), "\n\n")

cat("--- MapUnitPolys: units present ---\n")
geology$MapUnitPolys %>%
  st_drop_geometry() %>%
  count(MapUnit, sort = TRUE) %>%
  as.data.frame() %>%
  print()

cat("\nCRS check (MapUnitPolys):", st_crs(geology$MapUnitPolys)$input, "\n")
