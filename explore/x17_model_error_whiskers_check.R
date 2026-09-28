# =============================================================================
# x17_model_error_whiskers_check.R
# Umatilla River Discharge-Channel Migration Analysis
# DIAGNOSTIC (no plot): model-prediction-error whisker widths + sanity cross-check
# =============================================================================
#
# Purpose: Before adding model-error whiskers to the absolute-rate trajectory
#   (scripts/12), confirm that merTools::predictInterval yields plausible
#   per-reach widths -- specifically that the ANNUALIZED width, expressed as a
#   ~1 SD, lands near the empirical hindcast anchor (~0.8 ft/yr; ~25 ft/interval
#   ~= sqrt(sigma_interval^2 + sigma_resid^2) ~= sqrt(17^2 + 18^2)). Prints
#   widths only; builds no plot layer. See NOTE_model_error_whiskers_plan.md.
#
# Method decisions (settled with Byron 2026-09-08; merTools docs read first):
#   - level = 0.80          -> matches the 10-90 ensemble band's probability footing.
#   - new.levels = "draw"   -> the future period is an UNOBSERVED `interval` level,
#       so its effect is sampled from VarCorr; the ~17 ft interval-scale variance
#       enters the width. (Default "zero" DROPS it -> falsely tight.)
#   - include.resid.var = TRUE -> the ~18 ft residual/mapping floor belongs in a
#       PREDICTION interval.
#   - fix.intercept.variance / ignore.fixed.terms LEFT OFF: the merTools vignette
#       forbids them when predicting groups not in the fit (our future `interval`);
#       for an unseen group the fixed-intercept variance is genuine, not spurious.
#       Accept a mildly conservative bar.
#   - Forcing on the model's own scale: over a 30-yr normal the interval-total
#       cum_excess = T_NORM * (mean annual forcing); cum_excess_k = that / 1000,
#       interval_years = T_NORM. Model is linear + cumulative-additive, so
#       "apply the 30-yr total once" reproduces "apply each year and sum".
#   - Cross-check like-for-like: predictInterval returns an 80% HALF-WIDTH
#       (~1.28 SD); the ~0.8 ft/yr anchor is ~1 SD. Compare SD to SD:
#       sd = half_width / qnorm(0.5 + level/2).
#
# Inputs : the LIVE fitted model of record, obtained by sourcing 08 (which only
#            writes a coefficient CSV, not the model object; sourcing also
#            regenerates 08's usual coefficient CSVs + fit plot -- harmless);
#          data/future_forcing_annual_by_period.csv  (per-year forcing, from 11).
# Output : console only -- kept reaches, median forcing per cell, widths table,
#            and the SD cross-check against the empirical anchor.
# Style  : lingua / r-principles -- pure helpers with boundary contracts, I/O at
#            the orchestrator boundary, seeded randomness.
# =============================================================================

library(dplyr)
library(readr)
library(tidyr)
library(merTools)

# Live fitted model of record. 08 runs its full orchestration on source and
# leaves the lmerMod object in `models[["cum_excess"]]` -- the object we need
# (the coefficient CSV alone cannot feed predictInterval).
source("scripts/08_forcing_model.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

SEED         <- 20260908L         # predictInterval draws are seeded for reproducibility
PI_LEVEL     <- 0.80              # matches the 10-90 ensemble band
T_NORM       <- 30L               # 30-yr climate normal; annualizes the interval prediction
ANNUAL_CSV   <- "data/future_forcing_annual_by_period.csv"
DOWNSCALINGS <- c("BCSD", "MACA") # constant-set trajectory ensemble (as in scripts/12)

# Three 30-year climate normals (the settled grain; mirrors scripts/12).
NORMALS <- tribble(
  ~period,       ~y1,    ~y2,
  "2010-2039",   2010L,  2039L,
  "2040-2069",   2040L,  2069L,
  "2070-2099",   2070L,  2099L
)


# =============================================================================
# 2. HELPERS  (pure; each carries its boundary contract. I/O is in section 3.)
# =============================================================================

median_forcing_by_cell <- function(annual, normals, downscalings) {
  #' Median annual cum_excess per scenario x period across trajectory members.
  #' Forcing is period-level (reach-independent), so scripts/12's plotted median
  #' point corresponds to this median forcing -- the right anchor for a per-reach
  #' model-error width. Mirrors bin_forcing_to_normals() in 12, then medians.
  #' @param annual per member x water-year forcing (from 11); `source` tags
  #'   observed vs future, `downscaling`/`scenario` the ensemble axes.
  #' @param normals tibble(period, y1, y2) -- the 30-yr windows.
  #' @param downscalings downscalings to keep (constant-set ensemble).
  #' @return tibble(scenario, period, f_annual_median) in cfs-days/yr.
  annual %>%
    filter(source == "future", downscaling %in% downscalings) %>%
    select(-any_of("period")) %>%                                  # drop 11's stale bins
    left_join(normals, by = join_by(between(water_year, y1, y2))) %>%
    filter(!is.na(period)) %>%
    group_by(member_id, scenario, period) %>%
    summarise(f_member = mean(cum_excess), .groups = "drop") %>%
    group_by(scenario, period) %>%
    summarise(f_annual_median = median(f_member), .groups = "drop")
}

historical_forcing <- function(annual) {
  #' Observed-record mean annual cum_excess -- the historical anchor forcing
  #' F_hist (matches historical_anchor() in 12).
  #' @param annual per member x water-year forcing (from 11).
  #' @return single numeric (cfs-days/yr).
  annual %>%
    filter(source == "observed") %>%
    summarise(f = mean(cum_excess)) %>%
    pull(f)
}

select_representative_reaches <- function(reaches, n_pick = 3L) {
  #' Pick reaches spanning the flood-sensitivity range (min, median, max
  #' reach_slope), so the widths table shows how the whisker tracks slope -- the
  #' leverage that makes model error grow with forcing.
  #' @param reaches tibble(river_segment, reach_intercept, reach_slope) from
  #'   model_equation()$reaches; river_segment is a character key.
  #' @param n_pick number of reaches to return (min/median/max => 3).
  #' @return tibble(river_segment) subset, character key.
  ranked <- arrange(reaches, reach_slope)
  idx    <- unique(c(1L, ceiling(nrow(ranked) / 2), nrow(ranked)))[seq_len(n_pick)]
  ranked %>%
    slice(idx) %>%
    transmute(river_segment = as.character(river_segment))
}

build_design <- function(reaches_keep, forcing_cells, f_hist, panel_levels, t_norm) {
  #' One predictInterval design row per kept reach x {future cell, historical
  #' anchor}. Forcing is placed on the model's interval-total scale, and every
  #' `interval` label is a fresh, never-fitted level so new.levels="draw" injects
  #' the period variance -- the historical anchor is also a modeled (not in-sample)
  #' point, so it too draws an interval effect.
  #' @param reaches_keep tibble(river_segment) character key.
  #' @param forcing_cells tibble(scenario, period, f_annual_median).
  #' @param f_hist historical anchor forcing (scalar).
  #' @param panel_levels model's river_segment factor levels (for matching).
  #' @param t_norm normal length (yr).
  #' @return tibble(river_segment<fct>, interval<fct, new level>, cum_excess_k,
  #'   interval_years, scenario, period, f_annual, tag).
  future_cells <- forcing_cells %>%
    transmute(scenario, period, f_annual = f_annual_median, tag = "future")
  hist_cell <- tibble(scenario = "historical", period = "historical",
                      f_annual = f_hist, tag = "historical")

  bind_rows(future_cells, hist_cell) %>%
    crossing(reaches_keep) %>%
    mutate(
      cum_excess_k   = t_norm * f_annual / 1000,           # interval-total, scaled to 1000s
      interval_years = t_norm,
      river_segment  = factor(river_segment, levels = panel_levels),
      interval       = factor(paste0("future_", period))   # never in the fit -> drawn
    )
}

add_point_estimate <- function(design, reaches, baseline_per_yr) {
  #' Deterministic model prediction per design row (reach_intercept +
  #' reach_slope*forcing + baseline*years), as a CENTERING check: predictInterval's
  #' `fit` should land here, confirming the forcing scaling is right. Reported as
  #' an annual rate for readability.
  #' @param design tibble from build_design().
  #' @param reaches tibble(river_segment, reach_intercept, reach_slope), character key.
  #' @param baseline_per_yr population baseline rate (ft/yr), scalar.
  #' @return design + det_new_area (interval total) + det_rate_ft_yr (annual).
  reach_coef <- reaches %>%
    transmute(.rs = as.character(river_segment), reach_intercept, reach_slope)
  design %>%
    mutate(.rs = as.character(river_segment)) %>%
    left_join(reach_coef, by = ".rs") %>%
    mutate(
      det_new_area   = reach_intercept + reach_slope * cum_excess_k +
                         baseline_per_yr * interval_years,
      det_rate_ft_yr = det_new_area / interval_years
    ) %>%
    select(-.rs)
}

whisker_widths <- function(model, design, level, seed) {
  #' predictInterval half-widths on the design rows, annualized to ft/yr, plus
  #' the ~1 SD backed out for the empirical cross-check. We keep only the
  #' symmetric HALF-WIDTH -- the plotted point comes from 12's deterministic
  #' prediction, not predictInterval's `fit`.
  #' @param model the lmerMod model of record (cum_excess).
  #' @param design tibble from add_point_estimate() (carries interval_years, factors).
  #' @param level prediction-interval width (0.80).
  #' @param seed integer seed for the draws.
  #' @return design + pi_fit/pi_lwr/pi_upr (interval total) + pi_fit_ft_yr +
  #'   half_ft_yr + sd_ft_yr (annual).
  pi <- predictInterval(
    merMod            = model,
    newdata           = design,
    which             = "full",
    level             = level,
    n.sims            = 1000,
    stat              = "median",
    type              = "linear.prediction",
    include.resid.var = TRUE,
    new.levels        = "draw",          # future/hist interval unseen -> draw its effect
    seed              = seed
  )
  z <- qnorm(0.5 + level / 2)            # 80% half-width -> SD divisor (~1.2816)
  design %>%
    mutate(
      pi_fit       = pi$fit,
      pi_lwr       = pi$lwr,
      pi_upr       = pi$upr,
      pi_fit_ft_yr = pi_fit / interval_years,
      half_ft_yr   = ((pi_upr - pi_lwr) / 2) / interval_years,
      sd_ft_yr     = half_ft_yr / z
    )
}


# =============================================================================
# 3. ORCHESTRATION  (read input, build design, simulate, report)
# =============================================================================

stopifnot(exists("models"), exists("panel"), file.exists(ANNUAL_CSV))

model  <- models[["cum_excess"]]
fv     <- MODEL_METRICS[["cum_excess"]]$var
eq     <- model_equation(model, fv)
annual <- read_csv(ANNUAL_CSV, show_col_types = FALSE)

reaches_keep  <- select_representative_reaches(eq$reaches, n_pick = 3L)
forcing_cells <- median_forcing_by_cell(annual, NORMALS, DOWNSCALINGS)
f_hist        <- historical_forcing(annual)

design <- build_design(reaches_keep, forcing_cells, f_hist,
                       panel_levels = levels(panel$river_segment), t_norm = T_NORM) %>%
  add_point_estimate(eq$reaches, eq$baseline_per_yr)

widths <- whisker_widths(model, design, level = PI_LEVEL, seed = SEED)

# ---- report ----
cat("\n=== Representative reaches (min / median / max flood slope) ===\n")
eq$reaches %>%
  semi_join(reaches_keep, by = "river_segment") %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\nHistorical anchor F_hist = %s cfs-days/yr\n",
            format(round(f_hist), big.mark = ",")))

cat("\n=== Median annual forcing per scenario x period (cfs-days/yr) ===\n")
forcing_cells %>%
  mutate(f_annual_median = round(f_annual_median)) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n=== Whisker widths (ft/yr): centering + width + backed-out SD ===\n")
cat("(det_rate = deterministic 12-style point; pi_fit should match it.\n")
cat(" half = 80% half-width; sd = half / 1.2816 for the empirical compare.)\n\n")
widths %>%
  transmute(river_segment = as.integer(as.character(river_segment)),
            scenario, period,
            f_annual       = round(f_annual),
            det_rate_ft_yr = round(det_rate_ft_yr, 2),
            pi_fit_ft_yr   = round(pi_fit_ft_yr, 2),
            half_ft_yr     = round(half_ft_yr, 3),
            sd_ft_yr       = round(sd_ft_yr, 3)) %>%
  arrange(river_segment, scenario, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n=== Cross-check vs empirical anchor (~0.8 ft/yr, a ~1 SD quantity) ===\n")
cat(sprintf("  backed-out SD range  : %.2f - %.2f ft/yr\n",
            min(widths$sd_ft_yr), max(widths$sd_ft_yr)))
cat(sprintf("  80%% half-width range : %.2f - %.2f ft/yr\n",
            min(widths$half_ft_yr), max(widths$half_ft_yr)))
cat("  Read: SD near ~0.8 -> trust the simulation. Far tighter -> the\n")
cat("  near-singular fit is talking; fall back on the empirical number.\n")
