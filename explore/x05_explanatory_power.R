# =============================================================================
# x05_explanatory_power.R   (EXPLORATORY -- not folded into 07)
# -----------------------------------------------------------------------------
# What is the explanatory power of the forcing variables?
#   (1) Nakagawa marginal R2 (fixed effects only) vs conditional R2 (+ random).
#   (2) Forcing's INCREMENTAL marginal R2 -- what cum_excess adds over time alone.
#   (3) Variance shares: forcing+time / interval RE / reach RE / residual(measurement).
#   (4) The SAME question at the interval scale where forcing actually varies
#       (~15 interval means) -- this is the fair denominator for an interval-level
#       driver, and shows why the 139-row R2 understates the signal.
#
# Uses the m_A structure (random intercepts) for an exact Nakagawa partition;
# m_B2's random slope shifts these numbers negligibly.
#
# Source 07 first (needs the live `panel`).
# =============================================================================

library(lme4); library(dplyr)
stopifnot(exists("panel"))

fit <- function(f) lmer(f, panel, REML = TRUE)
m_full <- fit(new_area_per_ft ~ cum_excess_k + interval_years + (1 | river_segment) + (1 | interval))
m_time <- fit(new_area_per_ft ~ interval_years +                (1 | river_segment) + (1 | interval))
m_forc <- fit(new_area_per_ft ~ cum_excess_k +                  (1 | river_segment) + (1 | interval))

# Nakagawa R2, computed by hand (no package): variance of the fixed-effect
# predictions over the total implied variance.
r2 <- function(m) {
  vf   <- var(predict(m, re.form = NA))               # fixed-effect (forcing+time) variance
  vc   <- as.data.frame(VarCorr(m))
  vint <- sum(vc$vcov[vc$grp == "interval"])
  vrch <- sum(vc$vcov[vc$grp == "river_segment"])
  vres <- attr(VarCorr(m), "sc")^2                    # residual = measurement + fine noise
  tot  <- vf + vint + vrch + vres
  c(marginal = vf / tot, conditional = (vf + vint + vrch) / tot,
    v_fixed = vf, v_interval = vint, v_reach = vrch, v_resid = vres)
}

cat("=== Nakagawa R2 ===\n")
print(round(rbind(`forcing+time` = r2(m_full),
                  `time only`    = r2(m_time),
                  `forcing only` = r2(m_forc))[, c("marginal", "conditional")], 3))

cat("\nForcing's INCREMENTAL marginal R2 (forcing+time minus time-only):",
    round(r2(m_full)["marginal"] - r2(m_time)["marginal"], 3), "\n")

v <- r2(m_full)[c("v_fixed", "v_interval", "v_reach", "v_resid")]
cat("\n=== Variance shares, full model (%) ===\n")
print(round(100 * v / sum(v), 1))

# ---- Same question at the interval scale (where forcing varies) -------------
iv <- panel %>% group_by(interval) %>%
  summarise(new_area       = mean(new_area_per_ft),
            cum_excess_k    = first(cum_excess_k),
            interval_years  = first(interval_years), .groups = "drop")
cat("\n=== Interval-scale OLS R2 (n =", nrow(iv), "interval means) ===\n")
cat("  forcing + time :", round(summary(lm(new_area ~ cum_excess_k + interval_years, iv))$r.squared, 3), "\n")
cat("  forcing only   :", round(summary(lm(new_area ~ cum_excess_k,                  iv))$r.squared, 3), "\n")
cat("  time only      :", round(summary(lm(new_area ~ interval_years,                iv))$r.squared, 3), "\n")

# Read: marginal R2 (139 rows) is the honest "forcing+time" share at the noisy
# per-observation scale; the interval-scale R2 is what forcing explains where it
# actually operates. The gap between them IS the scale/measurement dilution.
