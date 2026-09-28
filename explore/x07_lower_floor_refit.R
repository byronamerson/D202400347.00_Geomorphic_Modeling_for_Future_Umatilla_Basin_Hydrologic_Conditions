# =============================================================================
# x07_lower_floor_refit.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY: does lowering the cum_excess floor from Q2 to 0.75*Q2 shrink the
#              interval random effect? (the cheap gate on the 0.5*Q2 extension)
# =============================================================================
#
# Byron's "lower the floor" option, tested as far as TODAY's data allows.
#
# The model of record (m_B2, 08_forcing_model.R) floors cum_excess at Q2 (5,542).
# The daily extension is fully supported down to ~0.75*Q2 (4,156) across all
# 1952-present intervals -- so we can refit the SAME model with the floor lowered
# to 0.75*Q2, with NO extension work, and read directly whether the interval RE
# shrinks and the fixed-effects (marginal) R2 rises.
#
# This adds the [0.75*Q2, Q2) band -- the flood shoulder plus the ~6 flood-blind
# years that peak in 4,156-5,320 (per x06) -- to the flood term. It is a PARTIAL
# test: the fully sub-bankfull flood-blind years (peaks 3,160-3,960) are still
# invisible until a 0.5*Q2 extension. So:
#   - shrinks interval RE / lifts marginal R2, stable slope -> green light for the
#     0.5*Q2 extension (the sub-bankfull years should add more).
#   - does nothing -> caution before paying for the extension.
# Asymmetric by design: a positive result is decisive, a null is a caution.
#
# Everything else is held fixed (same response, reaches, intervals, structure,
# REML). Only the forcing floor changes.
#
# Leaves in env: m_q2, m_075, cmp (headline compare), vc_q2, vc_075,
#   forcing_cmp (per-interval forcing change), reach_slopes_cmp
# Plot: plots/x07_interval_re_compare.png
# =============================================================================

# Sourcing 08 defines the toolbox AND fits the Q2 model of record, leaving
# `response`, `intervals`, `forcing` (Q2), `panel` (Q2), `models` in the env.
# (It also rewrites its own gitignored coefficient CSVs/plot -- identical to the
# committed Q2 fit, harmless.)
source("scripts/08_forcing_model.R")

library(lme4)
suppressPackageStartupMessages(library(dplyr))

Q2  <- 5542
VAR <- "cum_excess_k"


# =============================================================================
# 1. RECOMPUTE FORCING AT THE 0.75*Q2 FLOOR, REBUILD PANEL, REFIT
# =============================================================================
# compute_all_interval_forcing() (from 04c) is pure and takes the threshold
# explicitly -> no global config mutation, no CSV clobber.

extended    <- readRDS("data/pendleton_daily_extended.rds")
forcing_075 <- compute_all_interval_forcing(extended, intervals, 0.75 * Q2)
panel_075   <- assemble_panel(response, forcing_075, CONFINED_REACHES)

stopifnot(
  nrow(panel_075) == nrow(panel),                 # same rows as the Q2 panel
  sum(is.na(panel_075$cum_excess_k)) == 0
)

m_q2  <- models$cum_excess                          # the model of record (Q2, REML)
m_075 <- fit_forcing_model(panel_075, VAR)          # same structure, 0.75*Q2 floor, REML


# =============================================================================
# 2. READ-OUTS (pure)
# =============================================================================

varcomp <- function(m) {
  #' Random-effect SDs (feet) + residual, by role. Robust to the `||` split,
  #' which stores the reach intercept and reach slope as two river_segment grps.
  v <- as.data.frame(lme4::VarCorr(m))
  pick <- function(keep) v$sdcor[keep][1]
  tibble(
    sd_interval     = pick(v$grp == "interval"),
    sd_reach_int    = pick(grepl("^river_segment", v$grp) & v$var1 == "(Intercept)"),
    sd_reach_slope  = pick(grepl("^river_segment", v$grp) & v$var1 == VAR),
    sd_residual     = pick(v$grp == "Residual")
  )
}

fixed_row <- function(m) {
  co <- summary(m)$coefficients
  r2 <- suppressWarnings(MuMIn::r.squaredGLMM(m))   # Nakagawa/Johnson (handles random slope)
  tibble(
    pop_slope = co[VAR, "Estimate"],
    slope_se  = co[VAR, "Std. Error"],
    slope_t   = co[VAR, "t value"],
    baseline  = lme4::fixef(m)[["interval_years"]],
    R2_marg   = unname(r2[1, "R2m"]),               # fixed effects only
    R2_cond   = unname(r2[1, "R2c"]),               # fixed + random
    singular  = lme4::isSingular(m),
    aic_ml    = AIC(update(m, REML = FALSE))        # ML AIC (REML LL not comparable across differing fixed design)
  )
}

reach_slopes <- function(m) {
  reach_effects(m, VAR) %>% arrange(reach_slope)
}


# =============================================================================
# 3. ASSEMBLE THE COMPARISON
# =============================================================================

vc_q2  <- varcomp(m_q2)
vc_075 <- varcomp(m_075)

cmp <- bind_rows(
  bind_cols(floor = "Q2 (5,542)",       vc_q2,  fixed_row(m_q2)),
  bind_cols(floor = "0.75*Q2 (4,156)",  vc_075, fixed_row(m_075))
)

# headline deltas
d_interval_var <- vc_075$sd_interval^2 - vc_q2$sd_interval^2
pct_interval   <- 100 * d_interval_var / vc_q2$sd_interval^2
d_r2m          <- cmp$R2_marg[2] - cmp$R2_marg[1]

reach_slopes_cmp <- full_join(
  reach_slopes(m_q2)  %>% rename(slope_q2  = reach_slope, int_q2  = reach_intercept),
  reach_slopes(m_075) %>% rename(slope_075 = reach_slope, int_075 = reach_intercept),
  by = "river_segment"
) %>% mutate(sign_flip = sign(slope_q2) != sign(slope_075))

# how did each interval's forcing change (which intervals gained the band)?
forcing_cmp <- forcing %>%
  transmute(year_t1, year_t2,
            cum_excess_k_q2 = cum_excess_thresh_cfs_days / 1000,
            any_est_q2 = any_estimated) %>%
  left_join(
    forcing_075 %>% transmute(year_t1, year_t2,
                              cum_excess_k_075 = cum_excess_thresh_cfs_days / 1000),
    by = c("year_t1", "year_t2")
  ) %>%
  mutate(delta_k = cum_excess_k_075 - cum_excess_k_q2,
         interval = paste0(year_t1, "-", year_t2)) %>%
  arrange(desc(delta_k)) %>%
  select(interval, cum_excess_k_q2, cum_excess_k_075, delta_k, any_est_q2)


# =============================================================================
# 4. REPORT
# =============================================================================

cat("\n================  LOWERED-FLOOR REFIT: Q2  vs  0.75*Q2  ================\n")
cat("Same response, reaches, intervals, structure, REML. Only the floor moved.\n\n")

cmp %>%
  mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\nInterval RE variance:  %.3f -> %.3f  (%+.1f%%)   [SD %.3f -> %.3f ft]\n",
            vc_q2$sd_interval^2, vc_075$sd_interval^2, pct_interval,
            vc_q2$sd_interval, vc_075$sd_interval))
cat(sprintf("Marginal R2 (fixed):   %.3f -> %.3f  (%+.3f)\n",
            cmp$R2_marg[1], cmp$R2_marg[2], d_r2m))
cat(sprintf("Population slope:      %.3f (t %.2f)  ->  %.3f (t %.2f)\n",
            cmp$pop_slope[1], cmp$slope_t[1], cmp$pop_slope[2], cmp$slope_t[2]))
cat(sprintf("Reach-slope sign flips: %d of %d   |  singular: %s -> %s\n",
            sum(reach_slopes_cmp$sign_flip), nrow(reach_slopes_cmp),
            cmp$singular[1], cmp$singular[2]))
cat(sprintf("AIC (ML):             %.1f  ->  %.1f  (%+.1f)\n",
            cmp$aic_ml[1], cmp$aic_ml[2], cmp$aic_ml[2] - cmp$aic_ml[1]))

cat("\nIntervals that gained the most forcing at the lower floor (top 6):\n")
forcing_cmp %>% head(6) %>%
  mutate(across(where(is.numeric), ~ round(.x, 2))) %>%
  as.data.frame() %>% print(row.names = FALSE)


# =============================================================================
# 5. VISUAL: interval random effects, Q2 vs 0.75*Q2 (does the spread narrow?)
# =============================================================================

ire_tbl <- function(m, lbl) {
  re <- lme4::ranef(m)$interval
  tibble(interval = rownames(re), ire = re[, 1], floor = lbl)
}

ire_all <- bind_rows(ire_tbl(m_q2, "Q2 (5,542)"),
                     ire_tbl(m_075, "0.75*Q2 (4,156)")) %>%
  mutate(floor = factor(floor, levels = c("Q2 (5,542)", "0.75*Q2 (4,156)")))

p_ire <- ggplot(ire_all, aes(reorder(interval, ire), ire)) +
  geom_hline(yintercept = 0, colour = "grey70", linewidth = 0.4) +
  geom_point(aes(colour = floor), size = 2.2) +
  coord_flip() +
  scale_colour_manual(values = c("Q2 (5,542)" = "#1f4e79",
                                 "0.75*Q2 (4,156)" = "#c1440e"), name = "floor") +
  labs(title = "Interval random effects: does lowering the floor shrink the spread?",
       subtitle = "Each point = one interval's shared-flood deviation (ft). Tighter around 0 = less interval-level variance the fixed effect misses.",
       x = "interval", y = "interval random effect (ft)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

if (!dir.exists("plots")) dir.create("plots")
ggsave("plots/x07_interval_re_compare.png", p_ire, width = 8, height = 6, dpi = 130)
cat("\nWrote plots/x07_interval_re_compare.png\n")

# =============================================================================
# 6. INTERACTIVE (single-hash = executable; double-hash = narration)
# =============================================================================
##
# cmp               # full side-by-side (variance components + fixed + R2 + AIC)
# forcing_cmp       # per-interval forcing change at the lower floor
# reach_slopes_cmp  # per-reach slopes Q2 vs 0.75*Q2, sign-flip flag
#
## Sensitivity: the model of record carried a benign convergence flag at Q2;
## check whether 0.75*Q2 converges clean --
# m_075@optinfo$conv$lme4$messages
