# =============================================================================
# 09d_forward_prediction_check.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 9d: Forward-prediction sanity check (Agenda B) -- does the FIXED model of
#           record, applied in projection mode (interval RE = 0), give sensible
#           migration predictions from observed AND hindcast-corrected forcing?
# =============================================================================
#
# The honest projection-mode test. 09c RE-FIT the model on each flow source, which
# entangled "how the slopes estimate" with "how good the forcing is." This does the
# opposite -- and the thing the projection actually does: hold the model of record
# FIXED (08's cum_excess fit, all observed intervals) and PUSH each forcing source
# through predict_migration() with the interval RE zeroed -- exactly the future mode.
#
# Two questions:
#   1. Interval-RE-zeroing cost. On OBSERVED forcing, how far do the fixed-model
#      predictions (interval RE = 0) fall from observed migration? That gap is the
#      shared-flood variance we deliberately drop for future intervals -- the
#      ceiling on projection skill (Agenda C).
#   2. Corrected-forcing fidelity. Do the bias-corrected Livneh members, pushed
#      through the SAME fixed model, land near the observed-forcing predictions?
#      Close => the corrected flows carry the right forcing into the right
#      intervals, so the projection is trustworthy as a distributional index.
#
# NB this is NOT a refit: every source uses the identical per-reach slopes from the
# model of record. Only the forcing (the x's) changes between sources.
#
# Reuse: sources 09c (which sources 09 + 08). Uses its common-interval setup and
#   forcing builders (livneh_forcing, extended_forcing_common), plus 08's model of
#   record, predict_migration and assemble_panel. Only the predict-don't-refit
#   step is new. Threshold flows from the 04c config = 0.75xQ2 (bankfull).
# Outputs: a per-source skill table + a predicted-vs-observed plot.
# Style : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)

source("scripts/09c_forcing_validation.R")   # 09 + 08 + the common-interval forcing machinery


# =============================================================================
# 1. CONFIGURATION -- the fixed model of record
# =============================================================================
# The deployed equation: 08's cum_excess fit over ALL observed intervals. We do not
# refit it here; we apply its per-reach slopes to each forcing source.
FIXED_MODEL <- models[["cum_excess"]]
FORCING_VAR <- "cum_excess_k"


# =============================================================================
# 2. PREDICT FROM ONE FORCING SOURCE  (fixed model, projection mode)
# =============================================================================

predict_from_forcing <- function(forcing_tbl, response_tbl = response_common) {
  #' Push one forcing table through the FIXED model with the interval RE held at 0
  #' -- the projection configuration. Same response, reaches, and structure as the
  #' fit; only the forcing columns differ by source.
  #' @param forcing_tbl per-interval forcing (04c output) for one flow source
  #' @param response_tbl the observed migration response over the common intervals
  #' @return the panel with a pred_new_area_per_ft column (predicted migration)
  panel <- assemble_panel(response_tbl, forcing_tbl, CONFINED_REACHES)
  predict_migration(FIXED_MODEL, panel, FORCING_VAR, interval_re = FALSE)
}


# =============================================================================
# 3. SKILL vs OBSERVED MIGRATION
# =============================================================================

prediction_skill <- function(pred, source_label) {
  #' Predicted vs observed migration across reach x interval: correlation, RMSE and
  #' bias, all in new_area_per_ft units (ft). Bias = mean(pred - obs).
  #' @param pred a predict_from_forcing() result
  #' @param source_label flow-source name for the row
  #' @return one-row tibble
  d <- filter(pred, !is.na(pred_new_area_per_ft), !is.na(new_area_per_ft))
  tibble(
    source = source_label,
    n      = nrow(d),
    cor    = round(cor(d$pred_new_area_per_ft, d$new_area_per_ft), 3),
    rmse   = round(sqrt(mean((d$pred_new_area_per_ft - d$new_area_per_ft)^2)), 2),
    bias   = round(mean(d$pred_new_area_per_ft - d$new_area_per_ft), 2)
  )
}


# =============================================================================
# 4. BUILD PREDICTIONS: observed reference + every corrected member
# =============================================================================

build_forward_check <- function(members = LIVNEH_MEMBERS, reference = "native") {
  #' Fixed-model predictions from each flow source on the common intervals: the
  #' observed extended record (the yardstick / interval-RE ceiling) plus each
  #' bias-corrected Livneh member (the corrected-forcing fidelity test).
  #' @return list(preds = named list of prediction tibbles, skill = one row/source)
  sources <- c(
    list(observed = extended_forcing_common()),
    set_names(members) %>% map(~ livneh_forcing(.x, reference = reference))
  )
  preds <- imap(sources, ~ mutate(predict_from_forcing(.x), source = .y))
  skill <- imap_dfr(preds, prediction_skill)
  list(preds = preds, skill = skill)
}


# =============================================================================
# 5. REPORT PLOT -- predicted vs observed, faceted by flow source
# =============================================================================

plot_forward_check <- function(check) {
  #' 1:1 scatter of predicted vs observed migration, one facet per flow source.
  #' The observed facet shows the interval-RE-zeroing ceiling; member facets show
  #' whether corrected forcing reproduces it.
  bind_rows(check$preds) %>%
    ggplot(aes(new_area_per_ft, pred_new_area_per_ft, color = source)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, color = "grey50") +
    geom_point(size = 1.3, alpha = 0.7) +
    facet_wrap(~ source) +
    labs(x = "Observed new area per ft (ft)",
         y = "Predicted (fixed model, interval RE = 0)",
         title = "Agenda B: model of record in projection mode",
         subtitle = "1:1 dashed. Observed facet = interval-RE ceiling; members = corrected-forcing fidelity") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "none")
}


# =============================================================================
# 6. USAGE  (run interactively; sourcing runs 08's model of record once)
# =============================================================================
# check <- build_forward_check()      # observed + 4 corrected members, common intervals
# check$skill                          # the headline: skill vs observed migration
# ggsave("plots/forward_prediction_check.png", plot_forward_check(check),
#        width = 10, height = 7, units = "in")
# =============================================================================
