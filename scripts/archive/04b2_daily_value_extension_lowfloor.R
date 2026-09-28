# =============================================================================
# 04b2_daily_value_extension_lowfloor.R
# Umatilla River Discharge-Channel Migration Analysis
# Phase 4b2: Piecewise daily extension DOWN TO 0.25*Q2 (adds a moderate band)
# =============================================================================
#
# Purpose: Lower the reconstructed Pendleton daily floor from 0.75*Q2 (4,156) to
#   0.25*Q2 (1,386), WITHOUT disturbing the settled >=0.75*Q2 flood reconstruction
#   the model of record rests on. Enables cum_excess forcing at a lower floor and
#   Byron's flow-parsing on the extended series. See Spec_Daily_Extension_LowFloor.
#
# Why piecewise (04b Section 6): a SINGLE transfer fit down into moderate flows
#   biases the >=Q2 predictions LOW, so we cannot just lower the one fit band. But
#   the Gibbon->Pendleton relationship stays clean far below bankfull (04b Section
#   4 ladder). Resolution -- TWO independent MOVE.1 (commonlog) transfers:
#     - HIGH band  (target_q >= 0.75*Q2): the EXISTING 04b fit, unchanged.
#     - MOD  band  (0.25*Q2 <= target_q < 0.75*Q2): a NEW dedicated fit.
#   Each sees only its own range, so neither is pulled by the other's curvature.
#   Reconstruction switches at the seam where the HIGH fit predicts 0.75*Q2.
#
# Guarantee: every day whose HIGH-fit prediction is >= 0.75*Q2 is reconstructed by
#   the unchanged HIGH fit -> the >=Q2 flood forcing is byte-identical to 04b.
#   (Verified in Section 5.) The MOD fit only ever fills BELOW 0.75*Q2.
#
# Reuses 04b: load_daily_extension_inputs, build_concurrent_daily,
#   fit_move1_transfer, assign_flow_events, assemble_extended_daily_record, config.
#
# Output: data/pendleton_daily_extended_lowfloor.rds  (04b's rds left untouched)
# Leaves in env: fit_hi, fit_mod, cv_mod, mod_resid, curv_p, predicted, extended,
#   verify (high-band preservation check)
# Plot: plots/04b2_transfer_fits.png
#
# Style: lingua.md + Tidyverse & FP guidelines. Self-running on source().
# =============================================================================

source("scripts/04b_daily_value_extension.R")   # functions + config (do not re-run 04b)
suppressPackageStartupMessages({library(tidyverse); library(smwrStats)})

Q2      <- cfg_num("q2_target_cfs")     # 5542
HI_FRAC <- 0.75                          # flood band floor  (unchanged)
LO_FRAC <- 0.25                          # new reconstruction floor
HI_CUT  <- HI_FRAC * Q2                   # 4156.5
LO_CUT  <- LO_FRAC * Q2                   # 1385.5
OUT_RDS <- "data/pendleton_daily_extended_lowfloor.rds"
CUR_RDS <- cfg("extended_record_rds")     # data/pendleton_daily_extended.rds (04b)

message(sprintf("04b2: HIGH band >= %.0f | MODERATE band [%.0f, %.0f) | floor 0.25*Q2",
                HI_CUT, LO_CUT, HI_CUT))


# =============================================================================
# 1. LOAD + CONCURRENT CALIBRATION SET (reuse 04b)
# =============================================================================

inputs     <- load_daily_extension_inputs(config)
concurrent <- build_concurrent_daily(inputs$target_daily, inputs$index_daily)


# =============================================================================
# 2. FIT: high band (existing) + moderate band (new)
# =============================================================================

fit_move1_band <- function(concurrent, lo, hi) {
  #' MOVE.1 (commonlog) fit on a BOUNDED target band [lo, hi). Bounding the top at
  #' `hi` keeps the moderate fit from being pulled by the floods -- the whole point.
  band <- filter(concurrent, target_q >= lo, target_q < hi)
  smwrStats::move.1(target_q ~ index_q, data = band, distribution = "commonlog")
}

fit_hi  <- fit_move1_transfer(concurrent, HI_CUT)          # 04b's flood fit, unchanged
fit_mod <- fit_move1_band(concurrent, LO_CUT, HI_CUT)      # new moderate fit

mod_band <- filter(concurrent, target_q >= LO_CUT, target_q < HI_CUT)


# =============================================================================
# 3. VALIDATE THE MODERATE FIT (04b's checks, applied to the moderate band)
# =============================================================================

# 3a. Curvature over the moderate band (is one log-linear fit adequate?)
curv    <- lm(log10(target_q) ~ log10(index_q) + I(log10(index_q)^2), data = mod_band)
curv_p  <- summary(curv)$coefficients["I(log10(index_q)^2)", "Pr(>|t|)"]

# 3b. Per-month residuals (seasonality: moderate flows spill into shoulder seasons)
mod_resid <- mod_band %>%
  mutate(pred = as.numeric(predict(fit_mod, newdata = data.frame(index_q = index_q),
                                   type = "response")),
         resid_log = log10(target_q) - log10(pred)) %>%
  group_by(month) %>%
  summarise(n = dplyr::n(), resid_mean_log = mean(resid_log),
            resid_sd_log = sd(resid_log), .groups = "drop") %>%
  arrange(month)

# 3c. Event-blocked leave-one-event-out CV of the moderate MOVE.1 fit
cv_moderate <- function(concurrent, lo, hi, max_gap_days = 1L) {
  band <- concurrent %>%
    filter(target_q >= lo, target_q < hi) %>%
    arrange(date) %>%
    mutate(event_id = assign_flow_events(date, max_gap_days))
  events <- unique(band$event_id)
  preds <- map_dfr(events, function(ev) {
    tr <- filter(band, event_id != ev); te <- filter(band, event_id == ev)
    m  <- smwrStats::move.1(target_q ~ index_q, data = tr, distribution = "commonlog")
    tibble(obs = te$target_q,
           pred = as.numeric(predict(m, newdata = data.frame(index_q = te$index_q),
                                     type = "response")))
  })
  tibble(n_days = nrow(band), n_events = length(events),
         cv_rmse_cfs = sqrt(mean((preds$obs - preds$pred)^2, na.rm = TRUE)),
         cv_rmse_log = sqrt(mean((log10(preds$obs) - log10(preds$pred))^2, na.rm = TRUE)),
         cv_bias_cfs = mean(preds$pred - preds$obs, na.rm = TRUE))
}
cv_mod <- cv_moderate(concurrent, LO_CUT, HI_CUT)


# =============================================================================
# 4. PIECEWISE RECONSTRUCTION (seam where the HIGH fit predicts 0.75*Q2)
# =============================================================================

observed_start <- min(inputs$target_daily$date)
ext_start      <- as.Date(cfg("extension_start"))
g_hi_min       <- min(filter(concurrent, target_q >= HI_CUT)$index_q)  # HIGH-fit Gibbon floor
g_mod_min      <- min(mod_band$index_q)                                # MOD-fit Gibbon floor

reconstruct_piecewise <- function(fit_hi, fit_mod, index_daily) {
  ext <- index_daily %>%
    filter(date >= ext_start, date < observed_start) %>%
    arrange(date)
  p_hi  <- predict(fit_hi,  newdata = data.frame(index_q = ext$daily_q_cfs),
                   type = "response", var.fit = TRUE)
  p_mod <- predict(fit_mod, newdata = data.frame(index_q = ext$daily_q_cfs),
                   type = "response", var.fit = TRUE)
  tibble(date = ext$date, gibbon = ext$daily_q_cfs,
         fit_hi = p_hi$fit, var_hi = p_hi$var.fit,
         fit_mod = p_mod$fit, var_mod = p_mod$var.fit) %>%
    mutate(
      band = case_when(
        fit_hi >= HI_CUT & gibbon >= g_hi_min                       ~ "high",
        fit_hi <  HI_CUT & fit_mod >= LO_CUT & gibbon >= g_mod_min   ~ "moderate",
        TRUE                                                        ~ "none"
      ),
      pendleton_est_cfs = if_else(band == "high", fit_hi,
                          if_else(band == "moderate", fit_mod, NA_real_)),
      est_var = if_else(band == "high", var_hi,
                if_else(band == "moderate", var_mod, NA_real_)),
      source  = if_else(band == "high", "estimated_gibbon_move1_high",
                if_else(band == "moderate", "estimated_gibbon_move1_mod", NA_character_))
    ) %>%
    filter(band != "none")
}

predicted <- reconstruct_piecewise(fit_hi, fit_mod, inputs$index_daily)

extended <- assemble_extended_daily_record(
  inputs$target_daily,
  predicted %>% transmute(date, pendleton_est_cfs, est_var, source)
)

saveRDS(extended, OUT_RDS)


# =============================================================================
# 5. PRESERVATION CHECK: >=0.75*Q2 days identical to 04b's record
# =============================================================================
# Every day the new record reconstructs with the HIGH fit must equal 04b's value
# on the same date. (04b's near-floor days that predict < 0.75*Q2 move to the MOD
# fit here -- expected; those are below the flood band and don't touch >=Q2 forcing.)

cur <- readRDS(CUR_RDS) %>% filter(is_estimated) %>% select(date, cur_q = daily_q_cfs)
verify <- predicted %>%
  filter(band == "high") %>%
  inner_join(cur, by = "date") %>%
  summarise(n_high = dplyr::n(),
            max_abs_diff = max(abs(pendleton_est_cfs - cur_q)),
            .groups = "drop")


# =============================================================================
# 6. REPORT
# =============================================================================

cat("\n===============  04b2 PIECEWISE LOW-FLOOR EXTENSION  ===============\n")
cat(sprintf("Moderate fit: MOVE.1 commonlog on [%.0f, %.0f), %d days.\n",
            LO_CUT, HI_CUT, nrow(mod_band)))
cat(sprintf("Gibbon floors: HIGH >= %.0f cfs | MOD >= %.0f cfs\n", g_hi_min, g_mod_min))

cat("\n-- moderate-fit validation --\n")
cat(sprintf("  curvature (quadratic log-log) p = %.3g %s\n", curv_p,
            if (curv_p < 0.01) "(<- watch: may want a sub-split)" else "(one linear fit ok)"))
cat("  event-blocked CV (moderate band):\n")
print(as.data.frame(round(cv_mod, 2)), row.names = FALSE)
cat("  per-month residuals (log10; drift = seasonal regime shift):\n")
print(as.data.frame(mod_resid %>% mutate(across(where(is.numeric), ~round(.x, 3)))),
      row.names = FALSE)

cat("\n-- reconstruction --\n")
print(predicted %>% count(band) %>% as.data.frame(), row.names = FALSE)
cat(sprintf("  reconstructed span: %s to %s\n",
            format(min(predicted$date)), format(max(predicted$date)))) 
cat(sprintf("  estimated days: %d (04b had %d)\n",
            sum(extended$is_estimated), nrow(cur)))

cat("\n-- flood-band preservation (>=0.75*Q2 days vs 04b) --\n")
cat(sprintf("  %d high-band days match 04b, max |diff| = %.2e cfs %s\n",
            verify$n_high, verify$max_abs_diff,
            if (verify$max_abs_diff < 1e-6) "(IDENTICAL)" else "(<- investigate)"))
cat(sprintf("  wrote %s\n", OUT_RDS))


# =============================================================================
# 7. VISUAL: the two-band transfer + the seam
# =============================================================================

seam_gibbon <- 10 ^ ((log10(HI_CUT) - coef(fit_hi)[1]) / coef(fit_hi)[2])  # HIGH fit -> 0.75*Q2
seam_jump <- as.numeric(predict(fit_hi,  newdata = data.frame(index_q = seam_gibbon), type = "response")) -
             as.numeric(predict(fit_mod, newdata = data.frame(index_q = seam_gibbon), type = "response"))
cat(sprintf("\n-- seam --\n  at Gibbon ~ %.0f cfs; discontinuity (high - mod) = %+.0f cfs (%.1f%% of 0.75*Q2)\n",
            seam_gibbon, seam_jump, 100 * seam_jump / HI_CUT))

grid <- tibble(index_q = 10 ^ seq(log10(min(concurrent$index_q)),
                                  log10(max(concurrent$index_q)), length.out = 200)) %>%
  mutate(
    hi  = as.numeric(predict(fit_hi,  newdata = data.frame(index_q = index_q), type = "response")),
    mod = as.numeric(predict(fit_mod, newdata = data.frame(index_q = index_q), type = "response"))
  )

p_fit <- ggplot(concurrent %>% filter(target_q >= 0.15 * Q2),
                aes(index_q, target_q)) +
  geom_point(aes(colour = target_q >= HI_CUT), size = 0.8, alpha = 0.5) +
  geom_line(data = grid, aes(index_q, hi),  colour = "#1f4e79", linewidth = 0.8) +
  geom_line(data = filter(grid, mod < HI_CUT, mod >= LO_CUT),
            aes(index_q, mod), colour = "#c1440e", linewidth = 0.8) +
  geom_hline(yintercept = c(LO_CUT, HI_CUT, Q2), linetype = c(3, 2, 1),
             colour = "grey55") +
  scale_x_log10() + scale_y_log10() +
  scale_colour_manual(values = c(`TRUE` = "#1f4e79", `FALSE` = "#c1440e"),
                      labels = c(`TRUE` = ">= 0.75*Q2 (high fit)",
                                 `FALSE` = "< 0.75*Q2 (moderate fit)"), name = NULL) +
  labs(title = "Piecewise Gibbon -> Pendleton transfer (log-log)",
       subtitle = sprintf("Lines: high fit (blue), moderate fit (orange). Dashed = 0.75*Q2 seam, solid = Q2, dotted = 0.25*Q2 floor. Seam at Gibbon ~ %.0f cfs.", seam_gibbon),
       x = "Gibbon daily Q (cfs)", y = "Pendleton daily Q (cfs)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

if (!dir.exists("plots")) dir.create("plots")
ggsave("plots/04b2_transfer_fits.png", p_fit, width = 8, height = 6, dpi = 130)
cat(sprintf("  wrote plots/04b2_transfer_fits.png\n"))

# =============================================================================
# 8. INTERACTIVE (single-hash = executable; double-hash = narration)
# =============================================================================
##
# cv_mod      # moderate-band CV skill
# mod_resid   # per-month residuals (seasonality)
# curv_p      # curvature p over the moderate band
# verify      # flood-band preservation
# dplyr::count(extended, source, is_estimated)
