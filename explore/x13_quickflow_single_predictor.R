# =============================================================================
# x13_quickflow_single_predictor.R
# Umatilla River Discharge-Channel Migration Analysis
# Test: cumulative QUICKFLOW as the single forcing variable, vs cum_excess floors
# =============================================================================
#
# Byron's idea: instead of cum_excess above a fractional-Q2 floor, use cumulative
# quickflow (event water above the dynamic baseflow line) as the single flood
# forcing. More principled threshold (real baseflow, not a fixed Q2); includes
# moderate pulses. Reuses x12's per-interval flood_k. Adds cum_excess > 0.75*Q2
# (the current best, from x07) as the reference, and reports all on one scorecard.
#
# Reuses x12 (panel, pend_daily, intervals, m_q2, m_A, m_B). Run after nothing --
# it sources x12 itself.
# =============================================================================

source("explore/x12_separation_model_test.R")   # panel, pend_daily, intervals, m_q2/m_A/m_B, Q2
suppressPackageStartupMessages({library(tidyverse); library(lme4)})

CUT075 <- 0.75 * Q2

# add cum_excess > 0.75*Q2 per interval (the current best floor)
iv075 <- intervals %>%
  mutate(ce075_cfsd = map2_dbl(year_t1, year_t2, function(t1, t2) {
    w <- filter(pend_daily, water_year > t1, water_year <= t2)
    sum(pmax(0, w$total - CUT075))
  }))

panel2 <- panel %>%
  left_join(iv075, by = c("year_t1", "year_t2")) %>%
  mutate(ce075_k = ce075_cfsd / 1000)

# --- fit the two new single-predictor models ---
m_075 <- lmer(new_area_per_ft ~ ce075_k + interval_years + (ce075_k || river_segment) + (1|interval),
              data = panel2, REML = TRUE)
m_QF  <- lmer(new_area_per_ft ~ flood_k + interval_years + (flood_k || river_segment) + (1|interval),
              data = panel2, REML = TRUE)   # cumulative quickflow, single predictor


# --- scorecard across all candidates ---
sd_interval <- function(m) { v <- as.data.frame(VarCorr(m)); v$sdcor[v$grp == "interval"][1] }
r2m <- function(m) unname(suppressWarnings(MuMIn::r.squaredGLMM(m))[1, "R2m"])
aic_ml <- function(m) AIC(update(m, REML = FALSE))
fslope <- function(m, v) { co <- summary(m)$coefficients; sprintf("%.3f (t %.2f)", co[v,"Estimate"], co[v,"t value"]) }

cmp <- tibble(
  model = c("cum_excess > Q2", "cum_excess > 0.75Q2", "cum_excess > 0.25Q2",
            "QUICKFLOW (single)", "flood + baseflow"),
  forcing_slope = c(fslope(m_q2,"ceq2_k"), fslope(m_075,"ce075_k"), fslope(m_A,"ce025_k"),
                    fslope(m_QF,"flood_k"), fslope(m_B,"flood_k")),
  sd_interval = c(sd_interval(m_q2), sd_interval(m_075), sd_interval(m_A),
                  sd_interval(m_QF), sd_interval(m_B)),
  R2_marg = c(r2m(m_q2), r2m(m_075), r2m(m_A), r2m(m_QF), r2m(m_B)),
  aic_ml  = c(aic_ml(m_q2), aic_ml(m_075), aic_ml(m_A), aic_ml(m_QF), aic_ml(m_B))
)

cat("\n===============  SINGLE-PREDICTOR BAKE-OFF  ===============\n")
cat("Interval RE = variance the projection discards (lower better). AIC lower better.\n\n")
cmp %>% mutate(sd_interval = round(sd_interval, 2), R2_marg = round(R2_marg, 3),
               aic_ml = round(aic_ml, 1)) %>%
  arrange(aic_ml) %>% as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\nBest AIC: %s\n", cmp$model[which.min(cmp$aic_ml)]))
cat(sprintf("Lowest interval RE: %s\n", cmp$model[which.min(cmp$sd_interval)]))

# leaves m_075, m_QF, cmp in env
