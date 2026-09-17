# =============================================================================
# spatial_effective_valley_bottom_plot.R
# Interactive review plot for the effective valley bottom
# =============================================================================
#
# Purpose: Quick zoomable/pannable check of effective_valley_bottom against
#   the confining features that cut it (QA, not a final figure). Separate
#   from spatial_effective_valley_bottom.R so building the geometry doesn't
#   always drag in plotly / render a widget.
#
# Inputs:
#   - scripts/spatial_effective_valley_bottom.R (sourced; produces
#     confining_features, effective_valley_bottom_raw, effective_valley_bottom)
#   - scripts/spatial_valley_bottom_plot.R (sourced; supplies plot_valley_bottom())
#
# Output:
#   - effective_valley_bottom_plot (ggplot object)
#   - printed to Viewer as an interactive plotly widget
# =============================================================================

library(ggplot2)
library(plotly)

source("scripts/spatial_effective_valley_bottom.R")
source("scripts/spatial_valley_bottom_plot.R")   # reuses plot_valley_bottom()

effective_valley_bottom_plot <- plot_valley_bottom(
  effective_valley_bottom,
  "Effective valley bottom (truncated at m/a/lv, re-closed)"
)
effective_valley_bottom_plot

# Overlay view: effective valley bottom (blue) vs. the confining features
# that cut it (red) - useful for eyeballing whether the truncation is
# cutting where you'd expect.
confining_simplified <- confining_features %>%
  st_simplify(dTolerance = 20, preserveTopology = TRUE)
effective_simplified <- effective_valley_bottom %>%
  st_simplify(dTolerance = 20, preserveTopology = TRUE)

overlay_plot <- ggplot() +
  geom_sf(data = effective_simplified, fill = "steelblue", color = NA, alpha = 0.6) +
  geom_sf(data = confining_simplified, fill = "firebrick", color = NA, alpha = 0.6) +
  coord_sf(datum = st_crs(effective_simplified)) +
  theme_minimal() +
  labs(title = "Effective valley bottom (blue) vs. confining features (red)")

ggplotly(overlay_plot)
