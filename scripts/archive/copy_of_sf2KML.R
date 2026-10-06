# copied from https://github.com/pygmyperch/melfuR/blob/master/R/sf2KML.R

#' Convert Simple Features to KML
#'
#' @description
#' Convert Simple Features (\pkg{sf}) objects to Keyhole Markup Language (KML)
#' format for visualisation in Google Earth. Supports common geometry types
#' including points, lines, and polygons.
#'
#' @param sf_object An \code{sf} object containing the spatial data to be
#'   converted to KML.
#' @param colour Character string specifying the colour for point markers.
#'   Must be one of \code{"green"}, \code{"blue"}, \code{"red"},
#'   \code{"purple"}, \code{"lightblue"}, \code{"pink"}, or \code{"white"}.
#'   Default is \code{"yellow"}.
#' @param outputPath Character string specifying the path where the KML file
#'   will be saved. If \code{NULL}, the file will be saved in the current
#'   working directory with a name based on \code{sf_object}.
#' @param line_colour Colour for lines and polygon outlines. Can be a named
#'   colour (e.g., \code{"red"}) or a hex colour code (e.g., \code{"#FF0000"}).
#'   Default is \code{"#00ffff"} (cyan).
#' @param fill_colour Colour for polygon fills. Can be a named colour or a hex
#'   colour code. Default is \code{"#00ff00"} (green).
#' @param fill_opacity Numeric value between 0 and 1 specifying the opacity of
#'   polygon fills. Default is \code{0.5} (50\% opacity).
#'
#' @return
#' Invisibly returns \code{NULL}. The function is called for its side effect of
#' writing a KML file to the specified or default path.
#'
#' @details
#' The following geometry types are supported:
#'
#' \itemize{
#'   \item \code{POINT}: rendered as pushpins, with colour specified by the
#'     \code{colour} argument.
#'   \item \code{LINESTRING} and \code{MULTILINESTRING}: rendered as lines,
#'     with colour specified by \code{line_colour}.
#'   \item \code{POLYGON} and \code{MULTIPOLYGON}: rendered as filled polygons
#'     with outline colour specified by \code{line_colour} and fill colour
#'     and opacity controlled by \code{fill_colour} and \code{fill_opacity}.
#' }
#' @examples
#' if (requireNamespace("sf", quietly = TRUE)) {
#'   library(sf)
#'
#'   # Example points: Flinders University locations
#'   Flinders_University <- data.frame(
#'     ID = c("MELFU", "Tavern", "Animal House",
#'            "Aquaculture compound", "Lake", "$1,360 car park"),
#'     X = c(138.570071, 138.571627, 138.569855,
#'           138.569586, 138.572218, 138.569437),
#'     Y = c(-35.026967, -35.026029, -35.028127,
#'           -35.027034, -35.026907, -35.029019)
#'   )
#'
#'   # Convert the data frame to an sf object (points)
#'   Flinders_sf_points <- st_as_sf(
#'     Flinders_University,
#'     coords = c("X", "Y"),
#'     crs    = 4326
#'   )
#'
#'   # Create a KML file with points
#'   sf2KML(
#'     Flinders_sf_points,
#'     colour     = "red",
#'     outputPath = "Flinders_points.kml"
#'   )
#'
#'   # Create a line connecting all points
#'   Flinders_line <- st_cast(st_combine(Flinders_sf_points), "LINESTRING")
#'   Flinders_sf_line <- st_sf(
#'     geometry = Flinders_line,
#'     ID       = "Flinders_path"
#'   )
#'
#'   sf2KML(
#'     Flinders_sf_line,
#'     outputPath  = "Flinders_line.kml",
#'     line_colour = "blue"
#'   )
#'
#'   # Create a polygon (convex hull of all points)
#'   Flinders_polygon <- st_convex_hull(st_combine(Flinders_sf_points))
#'   Flinders_sf_polygon <- st_sf(
#'     geometry = Flinders_polygon,
#'     ID       = "Flinders_area"
#'   )
#'
#'   sf2KML(
#'     Flinders_sf_polygon,
#'     outputPath   = "Flinders_polygon.kml",
#'     line_colour  = "red",
#'     fill_colour  = "yellow",
#'     fill_opacity = 0.3
#'   )
#'
#'   # Combine all geometries into one sf object
#'   Flinders_sf_all <- rbind(
#'     Flinders_sf_points,
#'     Flinders_sf_line,
#'     Flinders_sf_polygon
#'   )
#'
#'   sf2KML(
#'     Flinders_sf_all,
#'     colour      = "green",
#'     outputPath  = "Flinders_all.kml",
#'     line_colour = "purple",
#'     fill_colour = "#00FFFF",
#'     fill_opacity = 0.5
#'   )
#' }
#' @importFrom sf st_bbox st_centroid st_as_sfc st_coordinates st_geometry st_geometry_type
#' @importFrom xml2 read_xml xml_add_child write_xml
#' @export
sf2KML <- function(sf_object, colour = NULL, outputPath = NULL, line_colour = "#00ffff", fill_colour = "#00ff00", fill_opacity = 0.5) {
  library(sf)
  library(xml2)
  
  sf_object_name <- deparse(substitute(sf_object))
  if (is.null(outputPath)) {
    outputPath <- paste0(sf_object_name, ".kml")
  } else {
    if (!grepl("/", outputPath)) {
      outputPath <- paste0(getwd(), "/", outputPath)
    }
  }
  
  baseUrl <- "http://maps.google.com/mapfiles/kml/pushpin/"
  validColours <- list(
    green = "grn", blue = "blue", red = "red", purple = "purple",
    lightblue = "ltblu", pink = "pink", white = "wht"
  )
  
  iconUrl <- paste0(baseUrl, ifelse(colour %in% names(validColours), validColours[[colour]], "ylw"), "-pushpin.png")
  
  # function to convert hex to ABGR
  hex_to_abgr <- function(color, opacity = 1) {
    # Check if the input is a named color and convert to hex
    if (grepl("^#", color) == FALSE) {
      # Convert named color to RGB
      rgb_vals <- col2rgb(color)
      # Convert to hex
      color <- rgb(rgb_vals[1], rgb_vals[2], rgb_vals[3], maxColorValue = 255)
    }
    
    # Remove the leading '#' if present
    hex_color <- gsub("#", "", color)
    
    # Extract the RGB components
    red <- substr(hex_color, 1, 2)
    green <- substr(hex_color, 3, 4)
    blue <- substr(hex_color, 5, 6)
    
    # Convert opacity to a 2-digit hex value
    alpha <- sprintf("%02X", round(opacity * 255))
    
    # Combine into ABGR format
    abgr_color <- paste0("0x", alpha, blue, green, red)
    
    return(abgr_color)
  }
  
  # Convert colors to ABGR format
  line_colour_abgr <- hex_to_abgr(line_colour, 1)  # Full opacity for lines
  fill_colour_abgr <- hex_to_abgr(fill_colour, fill_opacity)
  
  kml <- read_xml('<kml xmlns="http://www.opengis.net/kml/2.2"></kml>')
  doc <- xml_add_child(kml, "Document")
  
  # Calculate the bounding box
  bbox <- st_bbox(sf_object)
  centroid <- st_coordinates(st_centroid(st_as_sfc(bbox)))
  centroid_x <- centroid[1, "X"]
  centroid_y <- centroid[1, "Y"]
  
  # Calculate the diagonal distance of the bounding box
  diagonal_distance <- sqrt((bbox["xmax"] - bbox["xmin"])^2 + (bbox["ymax"] - bbox["ymin"])^2)
  view_range <- diagonal_distance * 111000 * 1.1  # Convert to meters and add 10% for padding
  
  lookAt <- xml_add_child(doc, "LookAt")
  xml_add_child(lookAt, "longitude", as.character(centroid_x))
  xml_add_child(lookAt, "latitude", as.character(centroid_y))
  xml_add_child(lookAt, "altitude", "0")
  xml_add_child(lookAt, "range", as.character(view_range))
  xml_add_child(lookAt, "tilt", "0")
  xml_add_child(lookAt, "heading", "0")
  
  # Style for points
  pointStyleNode <- xml_add_child(doc, 'Style', id = 'pointStyle')
  iconStyleNode <- xml_add_child(pointStyleNode, 'IconStyle')
  iconNode <- xml_add_child(iconStyleNode, 'Icon')
  xml_add_child(iconNode, 'href', iconUrl)
  
  # Style for lines
  lineStyleNode <- xml_add_child(doc, 'Style', id = 'lineStyle')
  lineStyle <- xml_add_child(lineStyleNode, 'LineStyle')
  xml_add_child(lineStyle, 'color', line_colour_abgr)
  xml_add_child(lineStyle, 'width', '3')
  
  # Style for polygons
  polygonStyleNode <- xml_add_child(doc, 'Style', id = 'polygonStyle')
  lineStyle <- xml_add_child(polygonStyleNode, 'LineStyle')
  xml_add_child(lineStyle, 'color', line_colour_abgr)
  xml_add_child(lineStyle, 'width', '3')
  polyStyle <- xml_add_child(polygonStyleNode, 'PolyStyle')
  xml_add_child(polyStyle, 'color', fill_colour_abgr)
  
  # Function to convert coordinates to KML format
  coords_to_kml <- function(coords) {
    paste(apply(coords, 1, function(row) paste(row[1], row[2], 0, sep=",")), collapse=" ")
  }
  
  # Function to process a single linestring
  process_linestring <- function(ls, placemark) {
    lineString <- xml_add_child(placemark, 'LineString')
    coords <- if(inherits(ls, "matrix")) ls else st_coordinates(ls)
    coords <- coords[, 1:2]
    xml_add_child(lineString, 'coordinates', coords_to_kml(coords))
  }
  
  # Function to process a single polygon
  process_polygon <- function(poly, parent) {
    polygon <- xml_add_child(parent, 'Polygon')
    outer <- poly[[1]]
    outerBoundary <- xml_add_child(polygon, 'outerBoundaryIs')
    linearRing <- xml_add_child(outerBoundary, 'LinearRing')
    xml_add_child(linearRing, 'coordinates', coords_to_kml(outer))
    
    if (length(poly) > 1) {
      for (i in 2:length(poly)) {
        inner <- poly[[i]]
        innerBoundary <- xml_add_child(polygon, 'innerBoundaryIs')
        linearRing <- xml_add_child(innerBoundary, 'LinearRing')
        xml_add_child(linearRing, 'coordinates', coords_to_kml(inner))
      }
    }
  }
  
  # Add placemarks for each feature
  for (i in 1:nrow(sf_object)) {
    feature <- sf_object[i, ]
    geom <- st_geometry(feature)[[1]]
    geom_type <- st_geometry_type(geom)
    ID <- as.character(feature$ID)
    
    placemark <- xml_add_child(doc, 'Placemark')
    xml_add_child(placemark, 'name', ID)
    
    if (geom_type == "POINT") {
      xml_add_child(placemark, 'styleUrl', '#pointStyle')
      point <- xml_add_child(placemark, 'Point')
      coords <- st_coordinates(geom)
      xml_add_child(point, 'coordinates', sprintf('%f,%f,0', coords[1, "X"], coords[1, "Y"]))
    } else if (geom_type %in% c("LINESTRING", "MULTILINESTRING")) {
      xml_add_child(placemark, 'styleUrl', '#lineStyle')
      if (geom_type == "LINESTRING") {
        process_linestring(geom, placemark)
      } else {
        for (ls in st_geometry(geom)) {
          process_linestring(ls, placemark)
        }
      }
    } else if (geom_type == "POLYGON") {
      xml_add_child(placemark, 'styleUrl', '#polygonStyle')
      process_polygon(geom, placemark)
    } else if (geom_type == "MULTIPOLYGON") {
      xml_add_child(placemark, 'styleUrl', '#polygonStyle')
      multiGeometry <- xml_add_child(placemark, 'MultiGeometry')
      for (poly in geom) {
        process_polygon(poly, multiGeometry)
      }
    }
  }
  
  # Save the KML file
  write_xml(kml, outputPath)
}
