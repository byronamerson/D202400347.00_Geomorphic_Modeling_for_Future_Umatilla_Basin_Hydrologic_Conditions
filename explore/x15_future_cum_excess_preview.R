# =============================================================================
# x15_future_cum_excess_preview.R
# Umatilla River Discharge-Channel Migration Analysis
# Sneak preview: do the bias-corrected FUTURE flows carry more extreme cumulative
# flood forcing (cum_excess > 0.75xQ2) than the observed record?
# =============================================================================
#
# Sets the stakes for the tail-extrapolation decision (Agenda B result). Computes
# per-water-year cum_excess above bankfull for the observed extended record and for
# every bias-corrected future member, then compares the distributions -- how far
# past the observed range do future flood-years reach?
#
# PREVIEW ONLY. Annual (per-water-year) cum_excess, NOT the multi-year interval
# forcing the projection uses (Step 2). Pools all 172 members / scenarios /
# downscalings -- a first look, not the scenario- or period-resolved projection.
#
# Reuse: 04c add_water_year + compute_all_interval_forcing at the config threshold.
# Style: Tidyverse & FP guidelines.
# =============================================================================

library(dplyr)
library(readr)
library(purrr)
library(tidyr)
library(ggplot2)

source("scripts/04c_interval_forcing_metrics.R")   # add_water_year, compute_all_interval_forcing, cfg

THRESHOLD <- cfg_num("metric_fraction") * cfg_num("q2_target_cfs")   # 0.75xQ2 = 4156 cfs
BC_DIR    <- "data/Umatilla_Future_Flows_BC"


# =============================================================================
# 1. PER-WATER-YEAR cum_excess FOR ONE DAILY SERIES
# =============================================================================

annual_intervals <- function(daily) {
  #' Each water year as its own one-year forcing window (year_t1 = wy-1, year_t2 = wy),
  #' matching compute_all_interval_forcing's (t1, t2] convention.
  wy <- sort(unique(add_water_year(daily)$water_year))
  tibble(year_t1 = wy - 1L, year_t2 = wy)
}

annual_cum_excess <- function(daily) {
  #' Per-water-year cum_excess above THRESHOLD for a daily series.
  #' @param daily tibble(date, daily_q_cfs, is_estimated)
  #' @return tibble(water_year, cum_excess)
  compute_all_interval_forcing(daily, annual_intervals(daily), THRESHOLD) %>%
    transmute(water_year = year_t2, cum_excess = cum_excess_thresh_cfs_days)
}


# =============================================================================
# 2. READERS
# =============================================================================

read_bc_member <- function(path) {
  #' One bias-corrected future member as a forcing-ready daily series (corrected
  #' flow is real modeled data, not reconstruction -> is_estimated = FALSE).
  read_csv(path, show_col_types = FALSE) %>%
    transmute(date = as.Date(date), daily_q_cfs = q_corrected, is_estimated = FALSE)
}


# =============================================================================
# 3. BUILD: observed + all future members
# =============================================================================

observed_annual <- readRDS(cfg("extended_record_rds")) %>%
  annual_cum_excess() %>%
  mutate(source = "observed")

bc_files <- list.files(BC_DIR, pattern = "-BC\\.csv$", full.names = TRUE)
message(sprintf("Reading %d bias-corrected future members ...", length(bc_files)))

future_annual <- map_dfr(bc_files, function(p) {
  read_bc_member(p) %>%
    annual_cum_excess() %>%
    mutate(member = sub("-BC$", "", tools::file_path_sans_ext(basename(p))))
}) %>%
  mutate(source = "future")


# =============================================================================
# 4. COMPARE THE DISTRIBUTIONS
# =============================================================================

obs_max <- max(observed_annual$cum_excess)

qtab <- function(x, label) {
  tibble(source = label, n = length(x),
         q50 = round(quantile(x, 0.50)), q90 = round(quantile(x, 0.90)),
         q99 = round(quantile(x, 0.99)), max = round(max(x)))
}

cat("\n=== Annual cum_excess > 0.75xQ2 (cfs-days) ===\n")
bind_rows(
  qtab(observed_annual$cum_excess, "observed"),
  qtab(future_annual$cum_excess,   "future (all members)")
) %>% as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\nObserved max annual cum_excess: %s cfs-days\n", format(round(obs_max), big.mark = ",")))
cat(sprintf("Future member-years exceeding that: %.1f%% (%d of %d)\n",
            100 * mean(future_annual$cum_excess > obs_max),
            sum(future_annual$cum_excess > obs_max), nrow(future_annual)))
cat(sprintf("Future max annual cum_excess: %s cfs-days (%.1fx the observed max)\n",
            format(round(max(future_annual$cum_excess)), big.mark = ","),
            max(future_annual$cum_excess) / obs_max))


# =============================================================================
# 5. PLOT: ECDF of annual cum_excess, observed vs future, obs-max marked
# =============================================================================

p_preview <- bind_rows(observed_annual, select(future_annual, water_year, cum_excess, source)) %>%
  ggplot(aes(cum_excess, color = source)) +
  stat_ecdf(linewidth = 0.9) +
  geom_vline(xintercept = obs_max, linetype = 2, color = "grey40") +
  annotate("text", x = obs_max, y = 0.05, label = " observed max", hjust = 0, size = 3, color = "grey40") +
  scale_color_manual(values = c(observed = "#2c7fb8", future = "#d95f0e")) +
  labs(x = "Annual cum_excess > 0.75xQ2 (cfs-days)", y = "Cumulative fraction of years",
       color = NULL,
       title = "Future vs observed annual flood forcing (preview)",
       subtitle = "All 172 bias-corrected members pooled; dashed = observed max annual") +
  theme_minimal(base_size = 11)

ggsave("plots/future_cum_excess_preview.png", p_preview, width = 9, height = 6, units = "in")
cat("\nWrote plots/future_cum_excess_preview.png\n")
