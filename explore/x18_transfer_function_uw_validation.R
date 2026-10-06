# =============================================================================
# x18_transfer_function_uw_validation.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY -- does a monthly series predict the cum_excess that its own
#                daily series produced?
# =============================================================================
#
# THE QUESTION
#   explore/x16_monthly_transfer_function.R fitted
#   sqrt(cum_excess) ~ max_month + February on the observed Pendleton record
#   and got a leave-one-out R2 of 0.71. Thirty water years is enough to show
#   the relationship exists. It is not enough to show that the function
#   reproduces a PERIOD MEAN, which is the only number the migration
#   projection consumes -- one scalar per member per reporting period.
#
#   The UW ensemble can answer that. Each bias-corrected member is a complete
#   daily series, so for every member BOTH sides are computable from the same
#   data: the real cum_excess from the dailies, and the transfer-function
#   estimate from the monthly means of those same dailies. Eighty members of
#   roughly 93 water years each, against the observed record's single
#   realization of 30.
#
#   This is the test that decides whether the CTUIR monthly future-flows
#   product could be pushed through the transfer function and fed to the
#   forward model. If the function cannot reproduce a period mean here, where
#   both sides are known, it cannot be trusted where only one side is.
#
# SCOPE  (Byron, 2026-10-06)
#   RCP4.5, statistical members only: BCSD and MACA downscaling, 10 global
#   climate models, 4 hydrologic model set-ups = 80 members.
#
#   The dynamically-downscaled members are excluded. They are reported on
#   their own period breakdown, their forcings were trained to a different
#   historical meteorological dataset, and they are never pooled with the
#   statistical members into one ensemble summary. Including them here would
#   mix two populations in a single diagnostic.
#
# WHAT THIS DOES NOT TEST
#   Every fit here is within-member: a member's own years fit a function that
#   is then scored on that member's own years. So this does NOT test whether
#   coefficients fitted on the OBSERVED gage record transfer to a modelled
#   series -- which is what using the function on CTUIR data would require.
#   Section 6 reports how tightly the 80 members' coefficients cluster, which
#   bears on that question without settling it.
#
#   It also does not test whether the relationship holds as the climate warms
#   and winter precipitation shifts from snow to rain. Fits use all of a
#   member's years rather than projecting an early block onto a late one.
#
# WHY LEAVE-ONE-OUT
#   A function fitted on a member's 93 years and then scored on those same 93
#   years flatters itself -- it has already seen every answer. Leave-one-out
#   holds back one water year, fits on the remaining 92, and predicts the held
#   back year. Every prediction is then out of sample, with no time split and
#   no years spent on a holdout block.
#
# Inputs : data/Umatilla_Future_Flows_BC/_bc-k-by-era_manifest.csv
#          data/Umatilla_Future_Flows_BC/<member_id>-BC-K-by-era.csv  (80 read)
# Outputs: console and returned objects. NOTHING IS WRITTEN TO DISK.
# Style  : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)

# 11 defines the future-forcing chain and runs nothing when sourced. It
# supplies the TRUTH side already in use by the projection --
# read_bc_member(), annual_cum_excess(), drop_partial_water_years(),
# tag_period(), THRESHOLD, BC_DIR -- and in turn the era definitions. The
# estimate side is the only new machinery in this file.
source("scripts/11_future_forcing_by_period.R")


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

PRODUCT_TAG <- "BC-K-by-era"
MANIFEST    <- file.path(BC_DIR, "_bc-k-by-era_manifest.csv")

# The manifest's own scenario label, read from the file (2026-10-06), not
# assumed. The CTUIR workbook and the UW manifest do not spell this the same
# way, and the run_transfer_validation() guard below fails loudly rather than
# silently testing zero members if a redelivery changes it.
SCENARIO_KEEP <- "RCP45"

# The form settled in x16. Stated here rather than buried inside the fitting
# function so that changing the model is a configuration edit, not a code edit.
TRANSFER_FORM <- sqrt_cum_excess ~ max_month + feb


# =============================================================================
# 2. THE ESTIMATE SIDE -- monthly means and the transfer function
# =============================================================================

monthly_predictors <- function(daily) {
  #' The two transfer-function predictors, per water year, from a daily series.
  #' PURPOSE: reduce a daily series to exactly what a monthly product delivers,
  #'   so that the estimate side sees no more information than the CTUIR
  #'   workbook would give us.
  #' INPUT : daily  tibble(date, daily_q_cfs, ...)
  #' OUTPUT: tibble(water_year, max_month, feb)
  #'   max_month  the largest of the 12 calendar-monthly mean flows (cfs)
  #'   feb        that water year's February mean flow (cfs)
  #' DECISIONS: calendar months, not water-year months -- CTUIR delivers
  #'   calendar months and the x16 fit used them. A water year missing
  #'   February returns NA there; such years are partial and are removed by
  #'   the completeness filter in member_water_year_table(), so the NA never
  #'   reaches a fit.
  daily %>%
    add_water_year() %>%
    mutate(month = as.integer(format(date, "%m"))) %>%
    summarise(mean_q = mean(daily_q_cfs), .by = c(water_year, month)) %>%
    summarise(
      max_month = max(mean_q),
      feb       = if (any(month == 2L)) mean_q[month == 2L] else NA_real_,
      .by = water_year
    )
}

add_loo_prediction <- function(wy, form = TRANSFER_FORM) {
  #' Attach a leave-one-out transfer-function estimate to one member's years.
  #' PURPOSE: an out-of-sample cum_excess estimate for every water year,
  #'   without spending years on a holdout block.
  #' INPUT : wy    tibble(water_year, cum_excess, max_month, feb) for ONE member
  #'         form  the fitted form, on the square-root scale (see DECISIONS)
  #' OUTPUT: wy with a `pred` column -- estimated cum_excess (cfs-days)
  #' DECISIONS: fitted on sqrt(cum_excess) and back-transformed with Duan
  #'   smearing. cum_excess is non-negative and zero-inflated, so a plain
  #'   linear fit predicts negative values. The square-root scale stabilises
  #'   variance, and smearing keeps the back-transformed MEAN approximately
  #'   unbiased. Mean-unbiasedness is the property that matters here: the
  #'   forward model consumes a period mean, not individual years.
  #'   Predictions are clipped at zero, which is physically required and costs
  #'   nothing. The form itself is inherited from x16 and is not re-selected.
  fit_data <- mutate(wy, sqrt_cum_excess = sqrt(cum_excess))

  predict_held_out_year <- function(i) {
    fit <- lm(form, data = fit_data[-i, ])
    p   <- predict(fit, newdata = fit_data[i, , drop = FALSE])
    mean(pmax(0, p + residuals(fit))^2)   # Duan smearing on the back-transform
  }

  mutate(wy, pred = map_dbl(seq_len(nrow(wy)), predict_held_out_year))
}

transfer_coefficients <- function(wy, form = TRANSFER_FORM) {
  #' The full-record fitted coefficients for one member.
  #' PURPOSE: section 6 asks whether the monthly-to-event relationship is a
  #'   property of the river (coefficients cluster across members) or of the
  #'   particular series (they scatter). That is a question about the fitted
  #'   surface, not about prediction skill, so it uses the full-record fit
  #'   rather than the leave-one-out fits.
  #' INPUT : wy  tibble(cum_excess, max_month, feb) for ONE member
  #' OUTPUT: tibble(term, estimate) -- one row per coefficient
  fit <- lm(form, data = mutate(wy, sqrt_cum_excess = sqrt(cum_excess)))
  tibble(term = names(coef(fit)), estimate = unname(coef(fit)))
}


# =============================================================================
# 3. ONE MEMBER -- both sides from the same daily series
# =============================================================================

member_water_year_table <- function(path) {
  #' Truth and predictors, per water year, for one bias-corrected member. (I/O)
  #' PURPOSE: the unit of work. Both sides come from ONE read of ONE daily
  #'   series, which is what makes this a self-contained test.
  #' INPUT : path  a corrected member CSV
  #' OUTPUT: tibble(water_year, cum_excess, n_days, max_month, feb)
  #'   cum_excess      the TRUTH -- the same per-water-year primitive the
  #'                   migration projection calls, at the same threshold
  #'   max_month, feb  the ESTIMATE side's only inputs
  #' DECISIONS: incomplete water years are removed here, by the same rule and
  #'   the same helper the forcing chain uses. A member's corrected record
  #'   opens 2006-01-01, so its WY2006 holds January to September only: that
  #'   year's cum_excess is a nine-month sum and its max_month is a maximum
  #'   over nine candidates rather than twelve. Both sides are wrong in that
  #'   year, in different directions, so the year is dropped rather than
  #'   reconciled. Every member should lose exactly WY2006 and keep 93 years;
  #'   the coverage check in section 6 reports whether that held.
  daily <- read_bc_member(path)

  annual_cum_excess(daily) %>%
    left_join(monthly_predictors(daily), by = "water_year") %>%
    drop_partial_water_years(basename(path))
}


# =============================================================================
# 4. THE COMPARISON THAT MATTERS -- period means, not years
# =============================================================================

summarise_member_periods <- function(wy_pred, periods) {
  #' Truth and estimate collapsed to the period means the forward model uses.
  #' PURPOSE: year-level scatter is expected and largely irrelevant. The
  #'   forward model takes one scalar per member per reporting period. That is
  #'   the scale at which the transfer function either works or does not.
  #' INPUT : wy_pred  tibble(water_year, cum_excess, pred, ...) for ONE member
  #'         periods  tibble(period, y1, y2, t_norm)
  #' OUTPUT: tibble(period, n_years, mean_truth, mean_est, ratio, diff)
  #'   ratio  mean_est / mean_truth -- the proportional miss
  #'   diff   mean_est - mean_truth (cfs-days/yr) -- carried alongside because
  #'          a period whose truth is near zero makes the ratio meaningless
  #'          while the difference stays readable
  wy_pred %>%
    tag_period(periods) %>%
    filter(!is.na(period)) %>%
    summarise(
      n_years    = dplyr::n(),
      mean_truth = mean(cum_excess),
      mean_est   = mean(pred),
      .by = period
    ) %>%
    mutate(ratio = mean_est / mean_truth,
           diff  = mean_est - mean_truth)
}


# =============================================================================
# 5. ORCHESTRATOR
# =============================================================================

run_transfer_validation <- function(manifest_path = MANIFEST,
                                    tag           = PRODUCT_TAG,
                                    scenario_keep = SCENARIO_KEEP,
                                    periods = as_period_table(ERAS_STATISTICAL)) {
  #' Run the within-member transfer-function validation on one scenario.
  #' PURPOSE: the feasibility test for the monthly-to-forcing pathway.
  #'   Returns its tables; writes nothing.
  #' INPUT : manifest_path  a bias-correction manifest
  #'         tag            product-set suffix naming the member CSVs
  #'         scenario_keep  the manifest's scenario label to restrict to
  #'         periods        reporting periods, from the project era table
  #' OUTPUT: list(annual, periods, coefficients), invisibly
  #'   annual        per member and water year: truth, estimate, predictors
  #'   periods       per member and period: the period-mean comparison
  #'   coefficients  per member: the full-record fitted coefficients
  stopifnot(file.exists(manifest_path))

  members_all <- read_track_manifest(manifest_path, tag)
  members     <- filter(members_all, scenario == scenario_keep)

  # Fail loudly on a label mismatch rather than silently testing zero members.
  if (nrow(members) == 0L) {
    stop(sprintf("No members with scenario == '%s'. Manifest has: %s",
                 scenario_keep,
                 paste(sort(unique(members_all$scenario)), collapse = ", ")))
  }

  message(sprintf("Transfer-function validation: %d members (%s, %s) ...",
                  nrow(members), scenario_keep, tag))

  # One nested table per member, carried through all three products so that
  # each member's fit is built from that member's years and no other's.
  fitted <- members %>%
    mutate(wy = map(bc_path, member_water_year_table)) %>%
    mutate(wy = map(wy, add_loo_prediction)) %>%
    select(-bc_path)

  invisible(list(
    annual = unnest(fitted, wy),
    periods = fitted %>%
      mutate(wy = map(wy, ~ summarise_member_periods(.x, periods))) %>%
      unnest(wy),
    coefficients = fitted %>%
      mutate(wy = map(wy, transfer_coefficients)) %>%
      unnest(wy)
  ))
}


# =============================================================================
# 6. RUN AND DESCRIBE  (describe; do not conclude)
# =============================================================================

out <- run_transfer_validation()

# Coverage first. Every member should carry 93 water years, having lost only
# the partial WY2006. A different count means a different partial year.
out$annual %>%
  summarise(water_years = dplyr::n(), .by = member_id) %>%
  summarise(members = dplyr::n(),
            wy_min  = min(water_years),
            wy_max  = max(water_years)) %>%
  as.data.frame() %>% print(row.names = FALSE)

# THE RESULT. Across members, how far each period-mean estimate sits from the
# period-mean truth: the median and range of the ratio, and the share of
# members landing within 10 and 25 percent.
out$periods %>%
  summarise(members      = dplyr::n(),
            truth_mean   = round(mean(mean_truth)),
            est_mean     = round(mean(mean_est)),
            ratio_median = round(median(ratio), 3),
            ratio_min    = round(min(ratio), 3),
            ratio_max    = round(max(ratio), 3),
            within_10pct = round(mean(abs(ratio - 1) <= 0.10), 2),
            within_25pct = round(mean(abs(ratio - 1) <= 0.25), 2),
            .by = period) %>%
  arrange(period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# Is the miss a consistent bias or is it scatter? Split by downscaling method:
# BCSD and MACA are different meteorological forcings and may behave
# differently, BCSD being disaggregated from monthly output and MACA from
# daily.
out$periods %>%
  summarise(ratio_median = round(median(ratio), 3),
            diff_median  = round(median(diff)),
            .by = c(downscaling, period)) %>%
  arrange(downscaling, period) %>%
  as.data.frame() %>% print(row.names = FALSE)

# Coefficient spread across the 80 members. Tight clustering would mean the
# monthly-to-event relationship is a property of the river, and a fit made on
# the observed gage record could reasonably be pointed at the CTUIR monthly
# flows. Wide scatter would mean it is a property of the particular series,
# and it could not.
out$coefficients %>%
  summarise(median = round(median(estimate), 4),
            q10    = round(quantile(estimate, 0.10), 4),
            q90    = round(quantile(estimate, 0.90), 4),
            .by = term) %>%
  as.data.frame() %>% print(row.names = FALSE)


# =============================================================================
# 7. LOOK AT IT
# =============================================================================

# One point per member and period. On the 1:1 line the transfer function
# reproduces that period's mean forcing exactly.
ggplot(out$periods, aes(mean_truth, mean_est, colour = downscaling)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
  geom_point(size = 1.8, alpha = 0.7) +
  facet_wrap(~ period) +
  labs(title = "Period-mean cum_excess: monthly estimate vs. daily truth",
       subtitle = sprintf(
         "UW statistical members, %s, within-member leave-one-out fit, %d members",
         SCENARIO_KEEP, n_distinct(out$periods$member_id)),
       x = "Truth, from the daily series (cfs-days/yr)",
       y = "Estimate, from the monthly means (cfs-days/yr)",
       colour = NULL) +
  theme_minimal()
