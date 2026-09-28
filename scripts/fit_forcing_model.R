# =============================================================================
# fit_forcing_model.R
# Umatilla River Discharge-Channel Migration Analysis
# Fit the cumulative flow forcing model; report it in plain language; export it
# =============================================================================
#
# Purpose: The live tool for the CUMULATIVE FLOW FORCING MODEL -- the model of
#   record. It does three things and nothing else: fit the model, report what
#   the fit says in language a non-statistician can act on, and export the
#   fitted equation for the projection scripts to read.
#
#   Replaces the run-every-time parts of 07_mixed_forcing_model.R (which chose
#   the model structure -- now settled and recorded) and 08_forcing_model.R
#   (same fit, plus a parallel sum_peak fit nothing downstream consumed).
#
# -----------------------------------------------------------------------------
# THE MODEL, in symbols and in words
# -----------------------------------------------------------------------------
#
#   new_area_per_ft ~ cum_excess_k + interval_years
#                     + (cum_excess_k || river_segment)
#                     + (1 | interval)
#
#   In words: every reach gets its own straight line relating flood forcing to
#   channel change. A straight line is two numbers -- an INTERCEPT (where the
#   line sits) and a FIT SLOPE (how steeply it rises, i.e. how much new channel
#   area that reach produces per unit of flood). Reaches differ in both.
#
#   `||` (double pipe) means: give each reach its own intercept AND its own fit
#   slope, but do NOT estimate a relationship between the two -- assume there
#   isn't one. (A single pipe `|` would estimate that relationship; it was tried
#   and failed to converge -- ten reaches cannot pin it down. See 07.)
#
#   `(1 | interval)` gives each photo interval its own adjustment, because all
#   reaches share one Pendleton flow series: in a given interval they all saw
#   the same flood, so their errors are not independent.
#
#   VOCABULARY: "slope" in this script ALWAYS means the fit slope of that line,
#   in ft of new area per 1000 cfs-days. Bed gradient is not in this model. It
#   was tested twice (07c interaction, 07f stream power) and contributed
#   nothing, and is deliberately absent.
#
#   Written out per reach, the fitted equation is simply:
#
#     new_area_per_ft = reach_intercept
#                     + reach_slope * cum_excess_k     (that reach's sensitivity)
#                     + baseline_per_year * interval_years
#
#   The (1 | interval) term is an in-sample nuisance for the shared flood; it is
#   held at 0 when projecting future intervals -- see predict_migration().
#
# -----------------------------------------------------------------------------
# OPEN ASSUMPTION -- parked deliberately, not settled
# -----------------------------------------------------------------------------
#   The `||` "no relationship" assumption is imposed at forcing = 0, i.e. an
#   interval in which the river never went above bankfull -- the far edge of the
#   data. Where you put zero on the x-axis changes what that assumption claims.
#   Refitting with forcing measured from its own mean gave a different
#   log-likelihood (-626.91 vs -629.00, 2026-09-17), which proves this is a real
#   modelling choice and not a re-expression of the same model. To be tested by
#   refitting centered and comparing the per-reach slopes and the between-
#   interval SD. Nothing in this script depends on the outcome.
#
# -----------------------------------------------------------------------------
# Inputs   data/multireach_interval_metrics.csv  (response, from 06)
#          data/interval_forcing_metrics.csv     (forcing, from 04c -- READ, not
#                                                 re-run; no source-chaining)
# Outputs  data/forcing_model_coefficients_cum_excess.csv  (portable equation)
#          data/forcing_model_cum_excess.rds               (fitted object, for 12)
#          plots/forcing_model_reach_fit.png               (per-reach fit check)
#
# Style: docs/lingua.md + Tidyverse & FP guidelines. Coefficients in feet;
#   forcing in THOUSANDS of cfs-days so a fit slope reads "ft per 1000 cfs-days".
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
  library(lme4)
})


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

RESPONSE_CSV <- "data/multireach_interval_metrics.csv"
FORCING_CSV  <- "data/interval_forcing_metrics.csv"
COEF_CSV     <- "data/forcing_model_coefficients_cum_excess.csv"
MODEL_RDS    <- "data/forcing_model_cum_excess.rds"
FIT_PLOT     <- "plots/forcing_model_reach_fit.png"

# Pendleton leveed reaches -- migration mechanically precluded, out of scope.
# Single toggle: empty this vector to restore them.
# (docs/NOTE_confined_reach_exclusion.md)
CONFINED_REACHES <- c(25L, 26L, 27L)

# The forcing metric. `var` is the scaled panel column the model fits on;
# `source` its raw column in the forcing CSV. The crest-driven alternative
# (sum_peak_excess_cfs) is still computed by 04c and sits unused in the forcing
# CSV; point these two lines at it to fit that lens instead.
FORCING_VAR    <- "cum_excess_k"
FORCING_SOURCE <- "cum_excess_thresh_cfs_days"


# =============================================================================
# 2. PANEL ASSEMBLY
# =============================================================================

assemble_panel <- function(response, forcing,
                           confined_reaches = CONFINED_REACHES,
                           forcing_source   = FORCING_SOURCE,
                           forcing_var      = FORCING_VAR) {
  #' Join the per-reach response to the per-interval forcing and add the model's
  #' factors. One row per reach x interval.
  #'
  #' Key decisions: confined reaches are dropped here, at the single panel
  #' boundary, so every downstream use gets the migration-capable set. Forcing is
  #' divided by 1000 so the fitted slope reads "ft per 1000 cfs-days" rather than
  #' a number with four leading zeros.
  #'
  #' @param response tibble from 06 (river_segment, year_t1/t2, interval_years,
  #'   new_area_per_ft, ...)
  #' @param forcing tibble from 04c (year_t1/t2 + forcing-metric columns)
  #' @return the model-ready panel
  panel <- response %>%
    filter(!river_segment %in% confined_reaches) %>%
    left_join(forcing, by = c("year_t1", "year_t2")) %>%
    mutate(
      river_segment = factor(river_segment),
      interval      = factor(paste0(year_t1, "-", year_t2)),
      !!forcing_var := .data[[forcing_source]] / 1000
    )

  # Validate at the boundary: a missing forcing value means the saved forcing
  # table does not cover every interval in the response -- re-run 04c.
  missing <- panel %>% filter(is.na(.data[[forcing_var]])) %>% distinct(interval)
  if (nrow(missing) > 0) {
    stop("No forcing for interval(s): ", paste(missing$interval, collapse = ", "),
         "\n  Re-run scripts/04c_interval_forcing_metrics.R.")
  }
  panel
}


# =============================================================================
# 3. FIT
# =============================================================================

fit_forcing_model <- function(panel, forcing_var = FORCING_VAR, REML = TRUE) {
  #' Fit the model of record. The structure is fixed (settled in 07, see
  #' NOTE_multireach_lmm_procedure.md); only the forcing column varies, which is
  #' what lets an alternative forcing metric be swapped in at the config block.
  #'
  #' @param panel model-ready panel (from assemble_panel)
  #' @param forcing_var name of the scaled forcing column (e.g. "cum_excess_k")
  #' @param REML TRUE for reporting the fit; FALSE only if likelihood-ratio
  #'   testing different FIXED effects, which needs ML
  #' @return an lmerMod
  fml <- stats::as.formula(sprintf(
    "new_area_per_ft ~ %s + interval_years + (%s || river_segment) + (1 | interval)",
    forcing_var, forcing_var))
  lme4::lmer(fml, data = panel, REML = REML)
}


# =============================================================================
# 4. THE FITTED EQUATION -- expose it as plain numbers
# =============================================================================

reach_effects <- function(model, forcing_var = FORCING_VAR) {
  #' Per-reach intercept and fit slope = the population fixed effect plus that
  #' reach's own (shrunken) random effect.
  #'
  #' Key decision: written to be robust to the `||` split, which stores the reach
  #' intercept and the reach slope as two SEPARATE river_segment terms rather
  #' than one two-column term. Found by column name, not by position.
  #'
  #' @return tibble(river_segment, reach_intercept, reach_slope)
  re  <- lme4::ranef(model)
  seg <- re[grep("^river_segment", names(re))]
  int_df <- seg[[which(vapply(seg, function(d) "(Intercept)" %in% colnames(d), logical(1)))]]
  slp_df <- seg[[which(vapply(seg, function(d) forcing_var  %in% colnames(d), logical(1)))]]
  fe <- lme4::fixef(model)
  tibble(
    river_segment   = rownames(int_df),
    reach_intercept = fe[["(Intercept)"]] + int_df[["(Intercept)"]],
    reach_slope     = fe[[forcing_var]]   + slp_df[[forcing_var]]
  )
}

model_equation <- function(model, forcing_var = FORCING_VAR) {
  #' The complete fitted equation as plain numbers: the population scalars plus
  #' the per-reach intercept/slope table. This is everything needed to compute a
  #' prediction outside lme4, and everything predict_migration() uses.
  #' @return list(forcing_var, pop_intercept, pop_slope, baseline_per_yr, reaches)
  fe <- lme4::fixef(model)
  list(
    forcing_var     = forcing_var,
    pop_intercept   = unname(fe[["(Intercept)"]]),
    pop_slope       = unname(fe[[forcing_var]]),
    baseline_per_yr = unname(fe[["interval_years"]]),
    reaches         = reach_effects(model, forcing_var)
  )
}

coef_table <- function(eq) {
  #' Flatten a fitted equation to a portable long-format table: the population
  #' scalars plus one row per reach intercept and reach slope. This is what the
  #' projection scripts read, so the equation can be reconstructed without R.
  bind_rows(
    tibble(term = "population_intercept", river_segment = NA_character_, value = eq$pop_intercept),
    tibble(term = "population_slope",     river_segment = NA_character_, value = eq$pop_slope),
    tibble(term = "baseline_per_year",    river_segment = NA_character_, value = eq$baseline_per_yr),
    transmute(eq$reaches, term = "reach_intercept", river_segment, value = reach_intercept),
    transmute(eq$reaches, term = "reach_slope",     river_segment, value = reach_slope)
  ) %>% mutate(forcing_var = eq$forcing_var, .before = 1)
}


# =============================================================================
# 5. APPLY THE EQUATION -- the forward step
# =============================================================================

predict_migration <- function(model, newdata, forcing_var = FORCING_VAR,
                              interval_re = FALSE) {
  #' Push any forcing table through the fitted equation. This is the bridge to
  #' the future-flow scenarios: `newdata` can be the historical panel OR a table
  #' of projected intervals; it just needs river_segment, the forcing column,
  #' and interval_years.
  #'
  #'   predicted new_area_per_ft = reach_intercept
  #'                             + reach_slope * forcing
  #'                             + baseline_per_year * interval_years
  #'
  #' Key decision: @param interval_re FALSE (default) holds the interval random
  #'   effect at 0 -- the correct behaviour for a NEW or FUTURE interval, whose
  #'   shared flood effect is unknown. TRUE adds each interval's fitted effect
  #'   back in, which is only for reproducing the in-sample fitted() as a check.
  #'   Reaches absent from the fit get NA rather than a silent population value.
  #' @return `newdata` with a pred_new_area_per_ft column added
  eq  <- model_equation(model, forcing_var)   # reach keys are character
  out <- newdata %>%
    mutate(.rs_key = as.character(river_segment)) %>%
    left_join(eq$reaches, by = c(".rs_key" = "river_segment")) %>%
    mutate(pred_new_area_per_ft =
             reach_intercept + reach_slope * .data[[forcing_var]] +
             eq$baseline_per_yr * interval_years)
  if (interval_re) {
    ire <- lme4::ranef(model)$interval
    out <- out %>%
      mutate(.iv_key = as.character(interval)) %>%
      left_join(tibble(.iv_key = rownames(ire), .ire = ire[, 1]), by = ".iv_key") %>%
      mutate(pred_new_area_per_ft = pred_new_area_per_ft + tidyr::replace_na(.ire, 0)) %>%
      select(-.iv_key, -.ire)
  }
  select(out, -.rs_key)
}


# =============================================================================
# 6. REPORT -- every number that reaches the screen, with how to read it
# =============================================================================
# Rule for this section (docs/lingua.md, applied to console output): nothing is
# printed without a plain-language note saying what it is and what to do with
# it. A number no one can act on is not a diagnostic, it is noise.

say <- function(...) {
  #' Print an indented, wrapped plain-language note beneath a results block.
  cat(paste0("  ", strwrap(paste0(...), width = 74)), sep = "\n")
}

report_data <- function(panel, forcing_csv = FORCING_CSV) {
  #' Block 1: what went into the fit. Catches a broken join or a stale forcing
  #' table before any number below is believed.
  thresholds <- unique(panel$threshold_cfs)
  stopifnot(length(thresholds) == 1)   # one threshold, or the panel is mixed
  reaches <- sort(as.integer(levels(panel$river_segment)))
  cat("\n=== 1. DATA ===\n")
  cat(sprintf("  %d reach-intervals | %d reaches (%d-%d) | %d photo intervals\n",
              nrow(panel), nlevels(panel$river_segment),
              min(reaches), max(reaches), nlevels(panel$interval)))
  cat(sprintf("  Flood threshold: %s cfs -- only flow ABOVE this counts as forcing\n",
              format(round(thresholds), big.mark = ",")))
  cat(sprintf("  Forcing table built: %s (%s)\n",
              format(file.mtime(forcing_csv), "%Y-%m-%d"), forcing_csv))
  say("If the forcing table date is older than the last change to the daily ",
      "flow record, re-run 04c before trusting anything below.")
  invisible(NULL)
}

report_flood_effect <- function(model, forcing_var = FORCING_VAR) {
  #' Block 2: the headline. Does flooding drive channel change, and by how much?
  rows <- c(forcing_var, "interval_years")
  co   <- summary(model)$coefficients[rows, , drop = FALSE]
  tbl  <- data.frame(
    driver   = c("flood: per 1,000 cfs-days above threshold", "time: per year elapsed"),
    estimate = round(co[, "Estimate"], 3),
    SE       = round(co[, "Std. Error"], 3),
    t        = round(co[, "t value"], 2)
  )
  cat("\n=== 2. THE FLOOD EFFECT ===\n")
  print(tbl, row.names = FALSE)
  say("ESTIMATE is feet of new channel area per foot of reach length, for one ",
      "unit of that driver -- averaged over all reaches. SE is how uncertain ",
      "that estimate is, in the same units. t is estimate divided by SE, i.e. ",
      "the signal-to-noise ratio: above roughly 2 the effect is solidly ",
      "distinguishable from zero; below 2, treat it as unproven. The two ",
      "drivers are additive: a reach accrues change with elapsed time whether ",
      "or not a flood comes, and floods add to that.")
  invisible(tbl)
}

report_explained_variation <- function(model) {
  #' Block 3: how much of the story the model actually tells. This is the
  #' currency the acceptance rule is written in (NOTE_model_priorities...).
  r2 <- MuMIn::r.squaredGLMM(model)   # REML fit is fine here; R2 is not likelihood-based
  cat("\n=== 3. HOW MUCH THE MODEL EXPLAINS ===\n")
  cat(sprintf("  flood size + years elapsed only    (marginal R2)     %.3f\n",  r2[1, "R2m"]))
  cat(sprintf("  + which reach, + which flood       (conditional R2)  %.3f\n",  r2[1, "R2c"]))
  say("R2 is the share of the variation in channel change the model accounts ",
      "for, on a 0-to-1 scale. MARGINAL counts only what could be known about ",
      "a FUTURE interval -- flood size and elapsed time -- so it is the honest ",
      "number for the projection, and the number a competing model has to ",
      "beat. CONDITIONAL also credits the model for knowing which reach and ",
      "which particular flood, which is hindsight. The gap between the two is ",
      "how much of the story is reach character and flood character rather ",
      "than flood size.")
  invisible(r2)
}

report_unexplained_variation <- function(model, forcing_var = FORCING_VAR) {
  #' Block 4: what the model does NOT explain, and how it splits. The
  #' between-interval piece is the one that becomes the projection's error band.
  #'
  #' Key decision: only components measured in FEET share this budget. The
  #' reach-slope SD is in ft per 1,000 cfs-days -- different units, so it is
  #' reported in block 5 instead of being added to a percentage here.
  vc  <- as.data.frame(lme4::VarCorr(model))
  vc  <- vc[is.na(vc$var1) | vc$var1 == "(Intercept)", ]
  lab <- ifelse(grepl("^river_segment", vc$grp), "between reaches (baseline level)",
         ifelse(vc$grp == "interval",            "between flood intervals",
                                                 "leftover, unexplained"))
  tbl <- data.frame(source = lab,
                    SD_ft  = round(vc$sdcor, 2),
                    share  = paste0(round(100 * vc$vcov / sum(vc$vcov)), "%"))
  tbl <- tbl[order(-vc$vcov), ]
  cat("\n=== 4. WHERE THE UNEXPLAINED SCATTER SITS ===\n")
  print(tbl, row.names = FALSE)
  say("The model never explains everything; this is what is left over and how ",
      "it divides. SD is a typical departure in feet. BETWEEN REACHES = some ",
      "reaches simply rework more than others at any flood size. BETWEEN ",
      "FLOOD INTERVALS = some floods did more work than their size predicts. ",
      "LEFTOVER = reach-and-interval-specific noise. Watch the between-flood ",
      "row: the projection has no way to know a future flood's personality, ",
      "so it sets that term to zero and carries this SD as the uncertainty ",
      "band on every projected interval. Shrinking it is what narrows the ",
      "range you deliver.")
  invisible(tbl)
}

report_reach_sensitivity <- function(model, eq, forcing_var = FORCING_VAR) {
  #' Block 5: how differently reaches respond to the same flood. Summary only --
  #' the full ten-row table goes to the coefficient CSV and the plot, because a
  #' ten-row table on screen is a wall, not a diagnostic.
  sl  <- eq$reaches
  hi  <- sl[which.max(sl$reach_slope), ]
  lo  <- sl[which.min(sl$reach_slope), ]
  vc  <- as.data.frame(lme4::VarCorr(model))
  sd_slope <- vc$sdcor[!is.na(vc$var1) & vc$var1 == forcing_var]
  cat("\n=== 5. REACH-TO-REACH SENSITIVITY (fit slope) ===\n")
  cat(sprintf("  most responsive   RS %-3s %6.3f ft per 1,000 cfs-days\n",
              hi$river_segment, hi$reach_slope))
  cat(sprintf("  least responsive  RS %-3s %6.3f\n", lo$river_segment, lo$reach_slope))
  cat(sprintf("  population average       %6.3f  | spread across reaches (SD) %.3f\n",
              eq$pop_slope, sd_slope))
  cat(sprintf("  every reach responds positively to flooding: %s\n",
              all(sl$reach_slope > 0)))
  say("Each reach gets its own fit slope: how much new channel area it ",
      "produces per 1,000 cfs-days of flood. These are partially pooled -- a ",
      "reach with few or noisy intervals is pulled toward the population ",
      "average, so no single reach's quirk runs away with the model. A ",
      "negative slope anywhere would mean 'floods shrink this reach', which is ",
      "a red flag to investigate rather than a finding. Full table in the ",
      "coefficient CSV; picture in the fit plot.")
  invisible(sl)
}

report_equation_check <- function(model, panel, forcing_var = FORCING_VAR) {
  #' Block 6: the guard on the export. The projection scripts read the
  #' coefficient CSV, not the fitted object, so the hand-assembled equation must
  #' reproduce lme4's own fitted values exactly or the two diverge silently.
  pred    <- predict_migration(model, panel, forcing_var,
                               interval_re = TRUE)$pred_new_area_per_ft
  max_abs <- max(abs(pred - fitted(model)))
  cat("\n=== 6. EQUATION CHECK ===\n")
  cat(sprintf("  largest disagreement, our equation vs lme4's own fit: %.1e ft\n", max_abs))
  cat(sprintf("  in-sample correlation, fitted vs observed:            %.3f\n",
              cor(fitted(model), panel$new_area_per_ft)))
  say("The first number should be essentially zero (about 1e-10 or smaller). ",
      "It confirms the exported coefficient CSV IS the model -- the projection ",
      "reads those coefficients rather than the fitted object, so if this ever ",
      "grows, the projection has quietly stopped matching the model. The ",
      "second number is how closely the fit tracks the observed data in ",
      "sample; it flatters the model because it includes the hindsight terms, ",
      "so use the marginal R2 in block 3 for judging the model, not this.")
  invisible(max_abs)
}


# =============================================================================
# 7. RUN
# =============================================================================

response <- read_csv(RESPONSE_CSV, show_col_types = FALSE)
forcing  <- read_csv(FORCING_CSV,  show_col_types = FALSE)

panel <- assemble_panel(response, forcing)
model <- fit_forcing_model(panel)
eq    <- model_equation(model)

report_data(panel)
report_flood_effect(model)
report_explained_variation(model)
report_unexplained_variation(model)
report_reach_sensitivity(model, eq)
report_equation_check(model, panel)

write_csv(coef_table(eq), COEF_CSV)
write_rds(model, MODEL_RDS)   # 12 needs the live merMod for merTools::predictInterval
cat("\n=== WROTE ===\n")
cat("  ", COEF_CSV,  " (the equation, for the projection)\n", sep = "")
cat("  ", MODEL_RDS, " (fitted object, for model-error whiskers in 12)\n", sep = "")


# =============================================================================
# 8. FIT PLOT -- one picture, not a diagnostic battery
# =============================================================================
# Per reach: the observed intervals, that reach's own fitted line (green), and
# the shared population line (orange). Shows both that the equation tracks the
# data and how much reaches differ in sensitivity. interval_years and the
# interval effect are held at 0 so the lines are directly comparable.

reach_lines <- eq$reaches %>%
  mutate(river_segment = factor(river_segment, levels = levels(panel$river_segment)))

p_fit <- ggplot(panel, aes(.data[[FORCING_VAR]], new_area_per_ft)) +
  geom_abline(intercept = eq$pop_intercept, slope = eq$pop_slope,
              color = "#d95f0e", linewidth = 0.8) +
  geom_abline(data = reach_lines,
              aes(intercept = reach_intercept, slope = reach_slope),
              color = "#238b45", linewidth = 0.7) +
  geom_point(size = 1.3, alpha = 0.7, color = "#2c7fb8") +
  facet_wrap(~ river_segment) +
  labs(x = sprintf("Cumulative flood excess above %s cfs (1,000 cfs-days)",
                   format(round(unique(panel$threshold_cfs)), big.mark = ",")),
       y = "New area per ft of reach (ft)",
       title = "Per-reach fit: that reach's line (green) vs the population line (orange)",
       subtitle = "Points = observed photo intervals. Green above orange = more flood-responsive than average.") +
  theme_minimal(base_size = 11)

ggsave(FIT_PLOT, p_fit, width = 10, height = 7, units = "in")
cat("  ", FIT_PLOT, " (per-reach fit)\n", sep = "")
