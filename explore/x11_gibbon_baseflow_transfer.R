# =============================================================================
# x11_gibbon_baseflow_transfer.R
# Umatilla River Discharge-Channel Migration Analysis
# STEPS 1-2: separate Gibbon (IH), calibrate Gibbon->Pendleton baseflow transfer,
#            validate against REAL Pendleton baseflow over the 1996-present overlap
# =============================================================================
#
# The plan: Gibbon is continuous 1952-present, so its IH baseflow needs no gap-fill.
# If Gibbon's baseflow can be mapped onto Pendleton, we get Pendleton's baseflow
# baseline back to 1952 WITHOUT filling the sparse extended record (Gibbon supplies
# the baseline the sparse Pendleton record was missing). This script does steps 1-2
# and stops at the validation gate: does the transfer reproduce the real Pendleton
# baseflow where we can check it (the overlap)? Quickflow / interval forcing is step 3.
#
# Two candidate transfers (let the overlap decide):
#   (a) DIRECT level:   Pendleton_bf = MOVE.1(Gibbon_bf)   [log-log, project idiom]
#   (b) FRACTION:       Pendleton_bf = Pendleton_Q * (Gibbon_bf / Gibbon_Q)
# NOTE (a) is the one usable HISTORICALLY: it builds Pendleton baseflow from the
# COMPLETE Gibbon record. (b) needs the complete Pendleton TOTAL, which pre-1996 is
# sparse (only >=0.25*Q2 days) -- so (b) is shown for comparison only. If (a)
# validates, it is what we carry to 1952.
#
# Reuses x09 (pend_sep, gib_sep -- both carry bf_ih). Run after x09.
# Leaves in env: fit_bf (the transfer), conc (overlap w/ predictions),
#   val_daily, val_annual
# Plots: plots/x11_baseflow_overlay.png, plots/x11_annual_baseflow_1to1.png
#
# Style: lingua.md + Tidyverse & FP guidelines. Self-running on source().
# =============================================================================

source("explore/x09_baseflow_method_comparison.R")   # pend_sep, gib_sep (bf_ih)
suppressPackageStartupMessages({library(tidyverse); library(smwrStats)})


# =============================================================================
# 1. CONCURRENT OVERLAP: Gibbon baseflow + REAL Pendleton baseflow (IH)
# =============================================================================

conc <- inner_join(
  pend_sep %>% transmute(date, month, water_year,
                         pend_bf = bf_ih, pend_Q = daily_q_cfs),
  gib_sep  %>% transmute(date, gib_bf = bf_ih, gib_Q = daily_q_cfs),
  by = "date"
) %>%
  filter(!is.na(pend_bf), !is.na(gib_bf), pend_bf > 0, gib_bf > 0, gib_Q > 0)

message("  overlap days (both IH baseflow defined): ", nrow(conc))


# =============================================================================
# 2. CALIBRATE BOTH TRANSFERS AND PREDICT PENDLETON BASEFLOW ON THE OVERLAP
# =============================================================================

# (a) direct level transfer, MOVE.1 log-log (variance-preserving, project idiom)
fit_bf <- move.1(pend_bf ~ gib_bf, data = conc, distribution = "commonlog")

conc <- conc %>%
  mutate(
    pend_bf_direct   = as.numeric(predict(fit_bf,
                        newdata = data.frame(gib_bf = gib_bf), type = "response")),
    pend_bf_fraction = pend_Q * (gib_bf / gib_Q)   # borrow Gibbon's daily BF fraction
  )


# =============================================================================
# 3. VALIDATE against the REAL Pendleton baseflow
# =============================================================================

# 3a. daily
metrics <- function(obs, hat) {
  tibble(r = cor(obs, hat), rmse_cfs = sqrt(mean((obs - hat)^2)),
         bias_cfs = mean(hat - obs), bias_pct = 100 * mean(hat - obs) / mean(obs))
}
val_daily <- bind_rows(
  bind_cols(transfer = "direct",   metrics(conc$pend_bf, conc$pend_bf_direct)),
  bind_cols(transfer = "fraction", metrics(conc$pend_bf, conc$pend_bf_fraction))
)

# 3b. annual baseflow total (the scale we will actually sum forcing on)
annual <- conc %>%
  group_by(water_year) %>%
  filter(dplyr::n() >= 350) %>%
  summarise(real_k     = sum(pend_bf) / 1000,
            direct_k   = sum(pend_bf_direct) / 1000,
            fraction_k = sum(pend_bf_fraction) / 1000, .groups = "drop")

val_annual <- bind_rows(
  bind_cols(transfer = "direct",
            metrics(annual$real_k, annual$direct_k), n_years = nrow(annual)),
  bind_cols(transfer = "fraction",
            metrics(annual$real_k, annual$fraction_k), n_years = nrow(annual))
)


# =============================================================================
# 4. REPORT
# =============================================================================

cat("\n===========  GIBBON -> PENDLETON BASEFLOW TRANSFER (overlap validation)  ===========\n")
cat("Does Gibbon's baseflow reproduce the REAL Pendleton baseflow (IH) on 1996-present?\n\n")

cat("Daily baseflow:\n")
val_daily %>% mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nAnnual baseflow total (the forcing scale):\n")
val_annual %>% mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nTransfer (a) equation, log-log:  log10(Pend_bf) = ",
    sprintf("%.3f + %.3f * log10(Gib_bf)\n", coef(fit_bf)[1], coef(fit_bf)[2]), sep = "")
cat("Reminder: (a) DIRECT is the one usable back to 1952 (built from complete Gibbon);\n",
    "(b) FRACTION needs the complete Pendleton total, which is sparse pre-1996.\n", sep = "")


# =============================================================================
# 5. VISUALS
# =============================================================================

# 5a. overlay: real vs transferred Pendleton baseflow, two sample years
samp_years <- c(2011L, 2017L)
overlay <- conc %>%
  filter(water_year %in% samp_years) %>%
  select(date, water_year, real = pend_bf, direct = pend_bf_direct,
         fraction = pend_bf_fraction, total = pend_Q) %>%
  pivot_longer(c(real, direct, fraction), names_to = "series", values_to = "bf")

p_overlay <- ggplot(overlay, aes(date)) +
  geom_area(aes(y = total), fill = "grey88") +
  geom_line(aes(y = bf, colour = series, linewidth = series)) +
  facet_wrap(~ water_year, scales = "free", ncol = 1) +
  scale_colour_manual(values = c(real = "black", direct = "#c1440e",
                                 fraction = "#1f4e79"),
                      labels = c(real = "real Pendleton baseflow",
                                 direct = "(a) transferred from Gibbon",
                                 fraction = "(b) Gibbon fraction"), name = NULL) +
  scale_linewidth_manual(values = c(real = 0.9, direct = 0.6, fraction = 0.6),
                         guide = "none") +
  labs(title = "Does Gibbon reproduce Pendleton's baseflow? (grey = Pendleton total flow)",
       subtitle = "Black = truth. If the coloured line tracks it, Gibbon stands in for Pendleton.",
       x = NULL, y = "Q (cfs)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

# 5b. annual baseflow total: transferred vs real, 1:1
annual_long <- annual %>%
  pivot_longer(c(direct_k, fraction_k), names_to = "transfer", values_to = "hat_k") %>%
  mutate(transfer = str_remove(transfer, "_k$"))

p_annual <- ggplot(annual_long, aes(real_k, hat_k, colour = transfer)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = 2) +
  geom_point(size = 2) +
  scale_colour_manual(values = c(direct = "#c1440e", fraction = "#1f4e79")) +
  labs(title = "Annual baseflow total: transferred-from-Gibbon vs real Pendleton",
       subtitle = "Dashed = 1:1. On the line = the transfer reproduces the real annual baseflow.",
       x = "real Pendleton baseflow total (1,000 cfs-days)",
       y = "transferred (1,000 cfs-days)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

if (!dir.exists("plots")) dir.create("plots")
ggsave("plots/x11_baseflow_overlay.png",      p_overlay, width = 9,  height = 7,   dpi = 130)
ggsave("plots/x11_annual_baseflow_1to1.png",  p_annual,  width = 6.5, height = 5.5, dpi = 130)
cat("\nWrote plots/x11_baseflow_overlay.png, plots/x11_annual_baseflow_1to1.png\n")

# =============================================================================
# 6. INTERACTIVE
# =============================================================================
##
# val_daily / val_annual   # transfer skill, daily and at the annual-total scale
# fit_bf                   # the Gibbon->Pendleton baseflow equation
# conc                     # overlap with both predictions
