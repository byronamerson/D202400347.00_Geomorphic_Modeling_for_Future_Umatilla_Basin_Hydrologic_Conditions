# =============================================================================
# x09_baseflow_method_comparison.R
# Umatilla River Discharge-Channel Migration Analysis
# EXPLORATORY: compare baseflow-separation methods on the COMPLETE records
#              (Pendleton observed 1996-present; Gibbon 1952-present)
# =============================================================================
#
# Goal (Byron): try each accepted baseflow-separation method on the two complete,
# continuous daily records and see how they perform --
#   (1) over the concurrent span (1996-present), Pendleton vs Gibbon, and
#   (2) on Gibbon over the full record of interest (1952-present).
# Gibbon needs NO gap-filling (continuous back to 1933), so it is the clean route:
# if Gibbon separates well and tracks Pendleton over the overlap, we have a path to
# carry the separation onto the sparse extended Pendleton record (next step).
#
# Three accepted methods, two families (all take a regular daily-flow vector):
#   - one-parameter recursive filter   FlowScreen::bf_oneparam(Q, k)
#   - Eckhardt two-parameter filter     FlowScreen::bf_eckhardt(Q, a, BFImax)
#   - IH/UK local-minimum (graphical)   lfstat::baseflow(Q, tp.factor, block.len)
# quickflow = flow - baseflow. BFI = sum(baseflow)/sum(flow).
#
# Parameters are standard literature defaults, flagged tunable. The recession
# constant (k, a) ideally comes from the gage's own recessions -- a refinement for
# next pass; here we use defaults and read the method SPREAD as the honest
# uncertainty. Methods agreeing => robust; diverging => the parameter/method choice
# matters and we tie it down.
#
# Input:  data/dv_gage_daily_flows.csv  (04a; observed daily, all gages, 0 gaps)
# Leaves in env: pend_sep, gib_sep (separated daily series), bfi_tbl, conc_cor
# Plots: plots/x09_baseflow_sample_year.png, plots/x09_bfi_by_month.png
#
# Style: lingua.md + Tidyverse & FP guidelines. Self-running on source().
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse); library(FlowScreen); library(lfstat)
})


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

PENDLETON <- "14020850"
GIBBON    <- "14020000"
GIBBON_START <- as.Date("1952-01-01")

# --- method parameters (standard defaults; tunable) ---
K_ONEPARAM <- 0.925     # one-param recession constant
A_ECK      <- 0.97      # Eckhardt recession constant (daily)
BFIMAX     <- 0.80      # Eckhardt BFImax (perennial stream)
IH_BLOCK   <- 5L        # IH block length (days)
IH_TP      <- 0.9       # IH turning-point factor


# =============================================================================
# 2. LOAD + CONTINUITY CHECK
# =============================================================================

daily <- read_csv("data/dv_gage_daily_flows.csv",
                  col_types = cols(.default = col_guess(), gage_id = col_character())) %>%
  filter(!is.na(daily_q_cfs), daily_q_cfs > 0) %>%
  select(gage_id, date, daily_q_cfs) %>%
  arrange(gage_id, date)

get_gage <- function(id, from = NULL) {
  d <- filter(daily, gage_id == id)
  if (!is.null(from)) d <- filter(d, date >= from)
  d <- arrange(d, date) %>%
    mutate(month = as.integer(format(date, "%m")),
           water_year = as.integer(format(date, "%Y")) +
             if_else(month >= 10L, 1L, 0L))
  gaps <- sum(as.integer(diff(d$date)) != 1L)
  message(sprintf("  %s: %d days, %s to %s, %d calendar gaps",
                  id, nrow(d), min(d$date), max(d$date), gaps))
  d
}

pend <- get_gage(PENDLETON)                 # 1996-present (all observed)
gib  <- get_gage(GIBBON, GIBBON_START)      # 1952-present


# =============================================================================
# 3. SEPARATE (three methods) -- pure over a continuous flow vector
# =============================================================================

add_separations <- function(g) {
  Q <- g$daily_q_cfs
  bf1 <- pmin(FlowScreen::bf_oneparam(Q, k = K_ONEPARAM),        Q)
  bfe <- pmin(FlowScreen::bf_eckhardt(Q, a = A_ECK, BFI = BFIMAX), Q)
  bfi <- pmin(lfstat::baseflow(Q, tp.factor = IH_TP, block.len = IH_BLOCK), Q)
  g %>% mutate(bf_oneparam = bf1, bf_eckhardt = bfe, bf_ih = bfi)
}

pend_sep <- add_separations(pend)
gib_sep  <- add_separations(gib)


# =============================================================================
# 4. BFI: overall + by season, per gage per method
# =============================================================================

bfi_long <- function(sep, gage_label, span_label) {
  sep %>%
    pivot_longer(starts_with("bf_"), names_prefix = "bf_",
                 names_to = "method", values_to = "bf") %>%
    filter(!is.na(bf)) %>%
    mutate(gage = gage_label, span = span_label)
}

# overall BFI (Gibbon reported for BOTH the full record and the concurrent overlap)
conc_start <- min(pend$date)
tbl <- bind_rows(
  bfi_long(pend_sep,                                   "Pendleton", "1996-present"),
  bfi_long(gib_sep,                                    "Gibbon",    "1952-present"),
  bfi_long(filter(gib_sep, date >= conc_start),        "Gibbon",    "1996-present (concurrent)")
)

bfi_tbl <- tbl %>%
  group_by(gage, span, method) %>%
  summarise(n_days = dplyr::n(),
            BFI = sum(bf) / sum(daily_q_cfs),
            mean_bf_cfs = mean(bf),
            mean_qf_cfs = mean(daily_q_cfs - bf), .groups = "drop") %>%
  arrange(gage, span, method)

bfi_by_month <- tbl %>%
  group_by(gage, span, method, month) %>%
  summarise(BFI = sum(bf) / sum(daily_q_cfs), .groups = "drop")


# =============================================================================
# 5. CONCURRENT TRANSFERABILITY: does Gibbon track Pendleton? (1996-present)
# =============================================================================
# If Gibbon quickflow/baseflow correlates with Pendleton's over the overlap, the
# separation can be carried from complete-Gibbon onto the sparse extended Pendleton.

conc <- inner_join(
  pend_sep %>% transmute(date, water_year,
                         across(starts_with("bf_"), ~ daily_q_cfs - .x,
                                .names = "qf_{.col}"),   # quickflow cols qf_bf_*
                         across(starts_with("bf_"), ~ .x, .names = "{.col}_p"),
                         Qp = daily_q_cfs),
  gib_sep %>% transmute(date,
                        across(starts_with("bf_"), ~ daily_q_cfs - .x,
                               .names = "qf_{.col}_g"),
                        across(starts_with("bf_"), ~ .x, .names = "{.col}_g"),
                        Qg = daily_q_cfs),
  by = "date"
)

methods <- c("oneparam", "eckhardt", "ih")
conc_cor <- map_dfr(methods, function(m) {
  qfp <- conc[[paste0("qf_bf_", m)]]        # Pendleton quickflow
  qfg <- conc[[paste0("qf_bf_", m, "_g")]]  # Gibbon quickflow
  bfp <- conc[[paste0("bf_", m, "_p")]]
  bfg <- conc[[paste0("bf_", m, "_g")]]
  tibble(method = m,
         r_quickflow_daily = cor(qfp, qfg, use = "complete.obs"),
         r_baseflow_daily  = cor(bfp, bfg, use = "complete.obs"))
})


# =============================================================================
# 6. REPORT
# =============================================================================

cat("\n===============  BASEFLOW METHOD COMPARISON  ===============\n")
cat(sprintf("params: one-param k=%.3f | Eckhardt a=%.2f BFImax=%.2f | IH block=%d tp=%.2f\n\n",
            K_ONEPARAM, A_ECK, BFIMAX, IH_BLOCK, IH_TP))

cat("Baseflow Index (fraction of total flow that is baseflow):\n")
bfi_tbl %>%
  mutate(BFI = round(BFI, 3), across(c(mean_bf_cfs, mean_qf_cfs), ~ round(.x))) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nMethod spread in BFI (max - min across methods), per gage/span:\n")
bfi_tbl %>% group_by(gage, span) %>%
  summarise(BFI_min = round(min(BFI), 3), BFI_max = round(max(BFI), 3),
            spread = round(max(BFI) - min(BFI), 3), .groups = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\nConcurrent (1996-present) Gibbon-vs-Pendleton daily correlation:\n")
cat("  (high => the separation transfers from complete-Gibbon to Pendleton)\n")
conc_cor %>% mutate(across(where(is.numeric), ~ round(.x, 3))) %>%
  as.data.frame() %>% print(row.names = FALSE)


# =============================================================================
# 7. VISUALS
# =============================================================================

# 7a. Sample wet year (WY2017): flow + the three baseflow lines, per gage
sample_wy <- 2017L
samp <- bind_rows(
  pend_sep %>% filter(water_year == sample_wy) %>% mutate(gage = "Pendleton"),
  gib_sep  %>% filter(water_year == sample_wy) %>% mutate(gage = "Gibbon")
) %>%
  select(gage, date, flow = daily_q_cfs, bf_oneparam, bf_eckhardt, bf_ih) %>%
  pivot_longer(starts_with("bf_"), names_prefix = "bf_",
               names_to = "method", values_to = "bf")

p_year <- ggplot(samp, aes(date)) +
  geom_area(aes(y = flow), fill = "grey85") +
  geom_line(aes(y = bf, colour = method), linewidth = 0.6) +
  facet_wrap(~ gage, scales = "free_y", ncol = 1) +
  scale_colour_manual(values = c(oneparam = "#1f4e79", eckhardt = "#c1440e",
                                 ih = "#238b45"), name = "baseflow method") +
  labs(title = sprintf("Baseflow separation, WY%d (grey = total flow)", sample_wy),
       subtitle = "How each method places the baseline under the same hydrograph.",
       x = NULL, y = "Q (cfs)") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

# 7b. Seasonal baseflow fraction (BFI by month), full records
p_month <- bfi_by_month %>%
  filter(span %in% c("1996-present", "1952-present")) %>%
  ggplot(aes(month, BFI, colour = method)) +
  geom_line(linewidth = 0.7) + geom_point(size = 1.4) +
  facet_wrap(~ gage) +
  scale_x_continuous(breaks = 1:12) +
  scale_colour_manual(values = c(oneparam = "#1f4e79", eckhardt = "#c1440e",
                                 ih = "#238b45"), name = "method") +
  labs(title = "Seasonal baseflow fraction (BFI by month)",
       subtitle = "Low in the winter storm season, high in summer recession.",
       x = "month", y = "BFI") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

if (!dir.exists("plots")) dir.create("plots")
ggsave("plots/x09_baseflow_sample_year.png", p_year, width = 9, height = 7, dpi = 130)
ggsave("plots/x09_bfi_by_month.png",        p_month, width = 9, height = 4.5, dpi = 130)
cat("\nWrote plots/x09_baseflow_sample_year.png, plots/x09_bfi_by_month.png\n")

# =============================================================================
# 8. INTERACTIVE (single-hash = executable; double-hash = narration)
# =============================================================================
##
# bfi_tbl     # BFI per gage/span/method
# conc_cor    # Gibbon-vs-Pendleton daily correlation (transferability)
# pend_sep / gib_sep  # the separated daily series
#
## Sensitivity: re-run with a different Eckhardt BFImax or recession constant to
## see how much BFI moves before trusting any single number.
