# =============================================================================
# spatial_valley_bottom_plot.R
# Interactive review plot for the contemporary valley bottom
# =============================================================================
#
# Purpose: Quick zoomable/pannable check of contemporary_valley_bottom and
#   contemporary_valley_bottom_closed (QA, not a final figure - no styling
#   conventions from plotting_conventions.md apply here). Separate from
#   spatial_valley_bottom.R so building the geometry doesn't always drag in
#   plotly / render a widget.
#
# Inputs:
#   - scripts/spatial_valley_bottom.R (sourced; produces
#     contemporary_valley_bottom and contemporary_valley_bottom_closed)
#
# Output:
#   - valley_bottom_plot, valley_bottom_closed_plot (ggplot objects)
#   - each printed to Viewer as its own interactive plotly widget
# =============================================================================

library(ggplot2)
library(plotly)

source("scripts/spatial_valley_bottom.R")

# Display-only simplification - ggplotly chokes on the full vertex count from
# ~2,400 source polygons unioned together. Does not touch the analysis
# objects themselves, only this script's copies of them.
# dTolerance is in the layer's units (ft here); raise it if still slow,
# lower it (or drop the simplify step) if the outline looks too blocky.
# x (sf, POLYGON/MULTIPOLYGON), title (character scalar) -> plotly widget.
plot_valley_bottom <- function(x, title) {
  simplified <- x %>% st_simplify(dTolerance = 20, preserveTopology = TRUE)

  p <- ggplot(simplified) +
    geom_sf(fill = "steelblue", color = NA, alpha = 0.6) +
    coord_sf(datum = st_crs(simplified)) +
    theme_minimal() +
    labs(title = title)

  ggplotly(p)
}

valley_bottom_plot <- plot_valley_bottom(
  contemporary_valley_bottom,
  "Contemporary valley bottom (dissolve, holes closed, simplified for display)"
)
valley_bottom_plot

valley_bottom_closed_plot <- plot_valley_bottom(
  contemporary_valley_bottom_closed,
  "Contemporary valley bottom, bridged/closed (simplified for display)"
)
valley_bottom_closed_plot
