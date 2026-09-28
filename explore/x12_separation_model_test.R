# =============================================================================
# x12_separation_model_test.R
# Umatilla River Discharge-Channel Migration Analysis
# STEP 3: build per-interval flood (quickflow) + baseflow forcing via the Gibbon
#         fraction map, and test the two-predictor model of migration.
# =============================================================================
#
# The decisive test of the separation detour. Using the validated fraction map
# (x11: Pendleton baseflow = Pendleton total x Gibbon's daily baseflow fraction,
# annual r 0.96, ~0 bias), we split the extended Pendleton total on the active
# days (>= 0.25*Q2) into:
#   flood_k (quickflow) = total x (1 - Gibbon BFI)   -- event pulses, peaks included
#   base_k  (baseflow)  = total x Gibbon BFI          -- sustained "maintenance" flow
# summed per DOGAMI interval (window WY t1+1 .. t2, as in 04c).
#
# Three models on the SAME panel (RS 28-37, confined reaches dropped):
#   m_q2   : cum_excess > Q2            (the model of record, single predictor)
#   m_A    : cum_excess > 0.25*Q2       (lowered-floor single predictor -- x07 idea,
#                                        now on the real 0.25*Q2 extension)
#   m_B    : flood_k + base_k           (the SEPARATION, two predictors)
# Scorecard (same as x07): interval RE (the variance the projection discards),
# marginal/conditional R2, AIC. Plus an LRT: does baseflow earn its place next to
# flood? And the two slopes -- does sustained flow drive migration, or just floods?
#
# Reuses x09 (gib_sep) and 08 (response, assemble helpers, CONFINED_REACHES).
# Leaves in env: interval_forcing, panel, m_q2, m_A, m_B, cmp, lrt_bf
# =============================================================================

source("explore/x09_baseflow_method_comparison.R")   # gib_sep (Gibbon IH separation)
source("scripts/08_forcing_model.R")                  # response, assemble_panel, CONFINED_REACHES, models, 04c fns
suppressPackageStartupMessages({library(tidyverse); library(lme4)})

Q2    <- 5542
FLOOR <- 0.25 * Q2
EXT   <- "data/pendleton_daily_extended_lowfloor.rds"


# =============================================================================
# 1. DAILY PENDLETON SEPARATION via the Gibbon fraction map (active days)
# =============================================================================

gib_bfi <- gib_sep %>%
  filter(!is.na(bf_ih), daily_q_cfs > 0) %>%
  transmute(date, gib_bfi = pmin(bf_ih / daily_q_cfs, 1))   # Gibbon daily baseflow fraction

pend_daily <- readRDS(EXT) %>%                               # extended total (obs + reconstructed)
  select(date, total = daily_q_cfs, is_estimated) %>%
  filter(total >= FLOOR) %>%                                # active days only
  inner_join(gib_bfi, by = "date") %>%
  add_water_year() %>%                                      # from 04c
  mutate(base = total * gib_bfi,           # sustained
         flood = total - base)             # event pulses (quickflow)


# =============================================================================
# 2. PER-INTERVAL FORCING (flood, baseflow, and cum_excess at both floors)
# =============================================================================

intervals <- distinct(response, year_t1, year_t2)

interval_forcing <- intervals %>%
  mutate(.f = pmap(list(year_t1, year_t2), function(t1, t2) {
    w <- filter(pend_daily, water_year > t1, water_year <= t2)
    tibble(
      flood_cfsd      = sum(w$flood),
      base_cfsd       = sum(w$base),
      ce_q2_cfsd      = sum(pmax(0, w$total - Q2)),      # model of record predictor
      ce_025_cfsd     = sum(pmax(0, w$total - FLOOR)),   # lowered-floor predictor
      n_active_days   = nrow(w),
      any_estimated   = any(w$is_estimated)
    )
  })) %>%
  unnest(.f)


# =============================================================================
# 3. PANEL (same rows as the model of record)
# =============================================================================

panel <- response %>%
  filter(!river_segment %in% CONFINED_REACHES) %>%
  left_join(interval_forcing, by = c("year_t1", "year_t2")) %>%
  mutate(
    river_segment = factor(river_segment),
    interval      = factor(paste0(year_t1, "-", year_t2)),
    flood_k = flood_cfsd  / 1000,
    base_k  = base_cfsd   / 1000,
    ceq2_k  = ce_q2_cfsd  / 1000,
    ce025_k = ce_025_cfsd / 1000
  )

stopifnot(sum(is.na(panel$flood_k)) == 0, sum(is.na(panel$base_k)) == 0)
cat(sprintf("panel: %d rows | %d reaches | %d intervals\n",
            nrow(panel), nlevels(panel$river_segment), nlevels(panel$interval)))


# =============================================================================
# 4. FIT THE THREE MODELS
# =============================================================================

m_q2 <- lmer(new_area_per_ft ~ ceq2_k  + interval_years + (ceq2_k  || river_segment) + (1|interval),
             data = panel, REML = TRUE)
m_A  <- lmer(new_area_per_ft ~ ce025_k + interval_years + (ce025_k || river_segment) + (1|interval),
             data = panel, REML = TRUE)
m_B  <- lmer(new_area_per_ft ~ flood_k + base_k + interval_years + (flood_k || river_segment) + (1|interval),
             data = panel, REML = TRUE)


# =============================================================================
# 5. SCORECARD
# =============================================================================

sd_interval <- function(m) { v <- as.data.frame(VarCorr(m)); v$sdcor[v$grp == "interval"][1] }
r2 <- function(m) { r <- suppressWarnings(MuMIn::r.squaredGLMM(m)); c(R2m = unname(r[1,"R2m"]), R2c = unname(r[1,"R2c"])) }
aic_ml <- function(m) AIC(update(m, REML = FALSE))

cmp <- tibble(
  model = c("m_q2  (cum_excess > Q2)", "m_A   (cum_excess > 0.25Q2)", "m_B   (flood + baseflow)"),
  sd_interval = c(sd_interval(m_q2), sd_interval(m_A), sd_interval(m_B)),
  R2_marg = c(r2(m_q2)["R2m"], r2(m_A)["R2m"], r2(m_B)["R2m"]),
  R2_cond = c(r2(m_q2)["R2c"], r2(m_A)["R2c"], r2(m_B)["R2c"]),
  aic_ml  = c(aic_ml(m_q2), aic_ml(m_A), aic_ml(m_B)),
  singular = c(isSingular(m_q2), isSingular(m_A), isSingular(m_B))
)

# does baseflow earn its place next to flood? (LRT, ML)
m_B_ml     <- update(m_B, REML = FALSE)
m_flood_ml <- update(m_B_ml, . ~ . - base_k)
lrt_bf <- anova(m_flood_ml, m_B_ml)

# the two slopes in m_B (the physical result)
fe   <- summary(m_B)$coefficients
slopes_B <- as.data.frame(fe[c("flood_k", "base_k", "interval_years"), , drop = FALSE])


# =============================================================================
# 6. REPORT
# =============================================================================

cat("\n===============  SEPARATION MODEL TEST  ===============\n")
cat("Interval RE = variance the projection discards (lower is better).\n\n")

cmp %>% mutate(sd_interval = round(sd_interval, 2),
               across(c(R2_marg, R2_cond), ~ round(.x, 3)),
               aic_ml = round(aic_ml, 1)) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nm_B slopes (does sustained flow drive migration, or just floods?):\n")
slopes_B %>% mutate(across(everything(), ~ round(.x, 3))) %>%
  as.data.frame() %>% print()

cat(sprintf("\nDoes baseflow earn its place next to flood?  LRT chisq=%.2f, df=%d, p=%.4f  -> %s\n",
            lrt_bf$Chisq[2], lrt_bf$Df[2], lrt_bf$`Pr(>Chisq)`[2],
            if (lrt_bf$`Pr(>Chisq)`[2] < 0.05) "YES" else "no"))

cat(sprintf("\nInterval RE:  Q2 %.2f  ->  0.25Q2 %.2f  ->  flood+base %.2f  (ft)\n",
            sd_interval(m_q2), sd_interval(m_A), sd_interval(m_B)))
cat(sprintf("Best AIC (ML): %s\n", cmp$model[which.min(cmp$aic_ml)]))

# =============================================================================
# 7. INTERACTIVE
# =============================================================================
##
# cmp        # three-model scorecard
# slopes_B   # flood vs baseflow slopes
# lrt_bf     # baseflow likelihood-ratio test
# interval_forcing  # per-interval flood/baseflow/cum_excess
