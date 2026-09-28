# =============================================================================
# x16_monthly_transfer_function.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY -- can monthly mean flows predict annual cum_excess?
# =============================================================================
#
# QUESTION
#   The CTUIR future-flows product is monthly mean flow. Our forcing metric,
#   cum_excess above 0.75xQ2, lives at the event scale and is not recoverable
#   from a monthly series by construction. But it may be PREDICTABLE from one:
#   a February averaging 3,000 cfs almost certainly contained large events.
#
#   This script fits and cross-validates that relationship on the observed
#   record, where both sides are known. It is the cheap, decisive feasibility
#   test for a monthly -> cum_excess transfer function.
#
# WHY THIS MATTERS
#   The forward model (12, apply_frozen_slopes) consumes ONE scalar per member
#   per period: F_period = mean annual cum_excess. It does not care how that
#   scalar was produced. If monthly means predict cum_excess adequately, the
#   CTUIR product can feed the projection directly, with no synthetic daily
#   series and no method-of-fragments donor-year machinery.
#
# THE RECORD CONSTRAINT -- READ THIS BEFORE INTERPRETING ANYTHING
#   data/pendleton_daily_extended.rds is 11,575 rows spanning 1952-2026, but
#   the pre-1996 portion is RECONSTRUCTED HIGH-FLOW DAYS ONLY (a handful per
#   year). Monthly means cannot be computed from it.
#   The complete daily record is WY1996-2025: n = 30 water years.
#   Parsimony here is not a preference, it is forced by n.
#
# Inputs : data/pendleton_daily_extended.rds (04b)
#          scripts/04c_interval_forcing_metrics.R (threshold config only)
# Outputs: console; optional data/x16_wy_monthly_vs_cum_excess.csv
# Style  : Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(ggplot2)

source("scripts/04c_interval_forcing_metrics.R")   # cfg_num, add_water_year

THRESHOLD <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")   # 4156 cfs
MIN_DAYS  <- 360L   # water years with fewer complete days are dropped


# =============================================================================
# 1. BUILD THE WATER-YEAR TABLE: 12 monthly means + that year's cum_excess
# =============================================================================

daily <- readRDS("data/pendleton_daily_extended.rds") %>%
  filter(source == "observed") %>%          # drop the sparse reconstructed days
  add_water_year() %>%
  mutate(month = as.integer(format(date, "%m")))

complete_wy <- daily %>%
  count(water_year) %>%
  filter(n >= MIN_DAYS) %>%
  pull(water_year)

message(sprintf("Complete water years: %d (%d-%d)",
                length(complete_wy), min(complete_wy), max(complete_wy)))

daily <- filter(daily, water_year %in% complete_wy)

# Response: the same primitive 04c/11 compute, evaluated per water year.
cum_excess_wy <- daily %>%
  group_by(water_year) %>%
  summarise(cum_excess = sum(pmax(0, daily_q_cfs - THRESHOLD)), .groups = "drop")

# Predictors: the 12 monthly means -- exactly what CTUIR delivers.
monthly_wy <- daily %>%
  group_by(water_year, month) %>%
  summarise(mean_q = mean(daily_q_cfs), .groups = "drop") %>%
  pivot_wider(names_from = month, values_from = mean_q, names_prefix = "m")

wy <- monthly_wy %>%
  left_join(cum_excess_wy, by = "water_year") %>%
  mutate(
    max_month = pmax(m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12),
    djf       = (m12 + m1 + m2) / 3,
    ndjfma    = (m11 + m12 + m1 + m2 + m3 + m4) / 6
  )

message(sprintf("Water years with cum_excess == 0: %d of %d",
                sum(wy$cum_excess == 0), nrow(wy)))


# =============================================================================
# 2. PREDICTOR SCREEN
# =============================================================================

screen <- wy %>%
  select(-water_year, -cum_excess) %>%
  imap_dfr(~ tibble(predictor = .y,
                    pearson   = cor(.x, wy$cum_excess),
                    spearman  = cor(.x, wy$cum_excess, method = "spearman"))) %>%
  arrange(desc(abs(pearson)))

print(screen, n = Inf)


# =============================================================================
# 3. LEAVE-ONE-OUT CROSS-VALIDATION
# =============================================================================
#
# cum_excess is non-negative and zero-inflated (see the count above), so a
# raw linear fit predicts negative values. Two fixes, both cheap:
#   - clip predictions at zero (physically required, costs nothing)
#   - fit on sqrt scale and back-transform with a smearing correction, which
#     stabilises variance AND keeps the back-transformed MEAN approximately
#     unbiased. Mean-unbiasedness is what matters: the forward model consumes
#     a period MEAN, not individual years.

loo_predict <- function(data, formula, sqrt_scale = FALSE) {
  #' Leave-one-out predictions, clipped at zero.
  #' @return numeric vector aligned to rows of `data`
  map_dbl(seq_len(nrow(data)), function(i) {
    train <- data[-i, ]
    test  <- data[i, , drop = FALSE]
    if (sqrt_scale) {
      fit   <- lm(update(formula, sqrt(.) ~ .), data = train)
      resid <- residuals(fit)
      p     <- predict(fit, newdata = test)
      mean(pmax(0, p + resid)^2)          # Duan smearing on the back-transform
    } else {
      max(0, predict(lm(formula, data = train), newdata = test))
    }
  })
}

candidates <- list(
  "max_month"             = list(f = cum_excess ~ max_month,      s = FALSE),
  "max_month + m2"        = list(f = cum_excess ~ max_month + m2, s = FALSE),
  "sqrt: max_month"       = list(f = cum_excess ~ max_month,      s = TRUE),
  "sqrt: max_month + m2"  = list(f = cum_excess ~ max_month + m2, s = TRUE)
)

results <- imap_dfr(candidates, function(spec, name) {
  p  <- loo_predict(wy, spec$f, spec$s)
  y  <- wy$cum_excess
  tibble(model    = name,
         loo_r2   = 1 - sum((y - p)^2) / sum((y - mean(y))^2),
         loo_mae  = mean(abs(y - p)),
         mean_obs = mean(y),
         mean_pred = mean(p))
})

print(results)


# =============================================================================
# 4. THE TARGET THAT ACTUALLY MATTERS -- PERIOD MEAN, NOT YEAR
# =============================================================================
#
# The projection needs mean annual cum_excess over a 20-30 yr window. Year-level
# scatter is largely irrelevant if it averages out. With n = 30 we can only test
# 10-year blocks, and those are dominated by one or two flood years -- so treat
# this as indicative, NOT as validation. The real test is the UW ensemble
# (see section 6).

best <- candidates[["sqrt: max_month + m2"]]
wy$pred <- loo_predict(wy, best$f, best$s)

wy %>%
  mutate(block = cut(water_year, breaks = c(1995, 2005, 2015, 2025),
                     labels = c("1996-2005", "2006-2015", "2016-2025"))) %>%
  group_by(block) %>%
  summarise(obs = mean(cum_excess), pred = mean(pred), n = n(), .groups = "drop") %>%
  print()


# =============================================================================
# 5. LOOK AT IT
# =============================================================================

ggplot(wy, aes(max_month, cum_excess)) +
  geom_point(size = 2) +
  geom_text(aes(label = water_year), hjust = -0.15, size = 2.6) +
  labs(title = "Annual cum_excess vs. maximum monthly mean flow",
       subtitle = sprintf("Pendleton 14020850, WY%d-%d, threshold %.0f cfs",
                          min(wy$water_year), max(wy$water_year), THRESHOLD),
       x = "Maximum monthly mean flow (cfs)",
       y = "cum_excess (cfs-days)") +
  theme_minimal()

ggplot(wy, aes(pred, cum_excess)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
  geom_point(size = 2) +
  labs(title = "Leave-one-out predicted vs. observed cum_excess",
       subtitle = "sqrt(cum_excess) ~ max_month + m2, smearing back-transform",
       x = "LOO predicted (cfs-days)", y = "Observed (cfs-days)") +
  theme_minimal()


# =============================================================================
# 6. NEXT STEP IF THIS LOOKS USABLE -- the UW check
# =============================================================================
#
# n = 30 cannot validate skill at the 30-year period-mean scale. The UW
# ensemble can: 160 bias-corrected members x ~150 yr of DAILY flow, from which
# both sides are computable.
#
#   for each member:
#     truth     <- annual_cum_excess(daily)              # 11's primitive
#     estimate  <- transfer_fn(monthly means of the same daily series)
#     compare period means, 2040-2069 and 2070-2099
#
# That tests the transfer function under exactly the conditions it would be
# used in -- a warmer, rain-shifted future -- and measures the stationarity
# assumption (that the monthly -> event relationship holds under a changed
# climate) rather than leaving it as a caveat.
#
# Only if that passes does CTUIR data get pushed through the function.

# write_csv(wy, "data/x16_wy_monthly_vs_cum_excess.csv")
