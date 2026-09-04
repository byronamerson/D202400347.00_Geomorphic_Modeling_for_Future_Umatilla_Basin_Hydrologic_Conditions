# x01_influence_diagnostics.R
# Question: does the net-area vs peak-flow relationship survive the Feb 2020
# leverage point, and do the structural fixes change the answer?
#
# Run section by section. Results stay in x01_* globals for inspection.

library(dplyr)
library(purrr)
library(broom)
library(ggplot2)

# ---- 1. data ----

source("scripts/rs30_interval_sandbox.R")

x01_data <- rs30_plot_data %>%
  filter(!is.na(q_peak_max_cfs)) %>%
  mutate(
    interval_label  = paste0(year_t1, "-", year_t2),
    interval_years  = year_t2 - year_t1,
    # dimensionless and un-annualized: the dt cancels, so this is immune to the
    # short-interval amplification that makes 2016-2017 an outlier
    expansion_ratio = net_area_change_ft2_per_year / symmetric_change_ft2_per_year
  )

# 2011-2012 held out to match the existing sandbox; reinstated at low weight in section 6
x01_main <- filter(x01_data, interval_label != "2011-2012")

x01_responses <- c(
  "new_area_ft2_per_year",
  "abandoned_area_ft2_per_year",
  "symmetric_change_ft2_per_year",
  "net_area_change_ft2_per_year",
  "jaccard_change",
  "expansion_ratio"
)

x01_fit <- function(resp, dat, pred = "q_peak_max_cfs") {
  lm(reformulate(pred, resp), data = dat)
}

x01_models <- set_names(x01_responses) %>% map(x01_fit, dat = x01_main)

x01_scan <- imap_dfr(x01_models, ~ glance(.x) %>%
  transmute(response = .y, r_squared = r.squared, p_value = p.value, n = nobs))

print(arrange(x01_scan, p_value))

# ---- 2. influence matrix ----

# thresholds at n = 13, p = 2: cooksd 4/n = 0.308, hat 2p/n = 0.308, dffits 2*sqrt(p/n) = 0.784
x01_n <- nrow(x01_main)

x01_influence <- imap_dfr(x01_models, function(fit, resp) {
  augment(fit, data = x01_main) %>%
    transmute(
      response   = resp,
      interval_label,
      q_peak_max_cfs,
      hat        = .hat,
      cooksd     = .cooksd,
      std_resid  = .std.resid,
      dffits     = dffits(fit),
      flagged    = cooksd > 4 / x01_n | hat > 4 / x01_n | abs(dffits) > 2 * sqrt(2 / x01_n)
    )
})

print(x01_influence %>% filter(flagged) %>% arrange(response, desc(cooksd)))

# ---- 3. leave-one-out trajectory ----

x01_loo <- function(resp, dat) {
  map_dfr(seq_len(nrow(dat)), function(i) {
    fit <- x01_fit(resp, dat[-i, ])
    glance(fit) %>%
      transmute(
        response  = resp,
        dropped   = dat$interval_label[i],
        r_squared = r.squared,
        p_value   = p.value,
        slope     = coef(fit)[[2]]
      )
  })
}

x01_loo_net <- x01_loo("net_area_change_ft2_per_year", x01_main)

print(arrange(x01_loo_net, desc(p_value)))

# decision rule set in advance: p > 0.10 on any single drop => suggestive, not established
x01_loo_verdict <- if (max(x01_loo_net$p_value) > 0.10) {
  "SUGGESTIVE - mechanism-supported, not statistically established"
} else {
  "HOLDS - p < 0.10 across all single-interval drops"
}
print(x01_loo_verdict)

# ---- 4. permutation test ----

# replaces t-test asymptotics, which are the weakest part of the claim at n = 13
x01_permute <- function(resp, dat, n_perm = 10000, seed = 1) {
  obs <- summary(x01_fit(resp, dat))$r.squared
  set.seed(seed)
  null <- replicate(n_perm, {
    shuffled <- dat
    shuffled[[resp]] <- sample(shuffled[[resp]])
    summary(x01_fit(resp, shuffled))$r.squared
  })
  tibble(response = resp, r2_obs = obs, p_perm = mean(null >= obs))
}

x01_perm <- map_dfr(c("net_area_change_ft2_per_year", "expansion_ratio"),
                    x01_permute, dat = x01_main)
print(x01_perm)

# ---- 5. bootstrap slope CI ----

# case resampling, not residual resampling, because leverage is the concern
set.seed(1)
x01_boot_slope <- replicate(2000, {
  d <- x01_main[sample(nrow(x01_main), replace = TRUE), ]
  tryCatch(coef(x01_fit("net_area_change_ft2_per_year", d))[[2]], error = function(e) NA_real_)
})

x01_boot_ci <- quantile(x01_boot_slope, c(0.025, 0.5, 0.975), na.rm = TRUE)
print(x01_boot_ci)
# CI spanning zero means the slope is not resolvable at this sample size
print(paste("excludes zero:", !(x01_boot_ci[1] < 0 & x01_boot_ci[3] > 0)))

# ---- 6. structural variants ----

# log10(Q) compresses the high end, reducing Feb 2020 leverage.
# dt^2 weights: annualized rate has variance ~ sigma^2 / dt^2 if area error is
# roughly constant, so short intervals are down-weighted rather than deleted
# (Donovan et al. 2019). That also lets 2011-2012 back in at low weight.
x01_variants <- list(
  ols         = lm(net_area_change_ft2_per_year ~ q_peak_max_cfs, x01_main),
  log_q       = lm(net_area_change_ft2_per_year ~ log10(q_peak_max_cfs), x01_main),
  wls_dt2     = lm(net_area_change_ft2_per_year ~ q_peak_max_cfs, x01_main, weights = interval_years^2),
  wls_dt2_all = lm(net_area_change_ft2_per_year ~ q_peak_max_cfs, x01_data, weights = interval_years^2),
  ratio_ols   = lm(expansion_ratio ~ q_peak_max_cfs, x01_main),
  ratio_log_q = lm(expansion_ratio ~ log10(q_peak_max_cfs), x01_main)
)

x01_variant_scan <- imap_dfr(x01_variants, ~ glance(.x) %>%
  transmute(variant = .y, r_squared = r.squared, p_value = p.value, n = nobs))

print(x01_variant_scan)

# max leverage per variant: did the transform actually reduce it?
x01_variant_leverage <- imap_dfr(x01_variants, ~ tibble(
  variant  = .y,
  max_hat  = max(hatvalues(.x)),
  max_cook = max(cooks.distance(.x))
))

print(x01_variant_leverage)

# ---- 7. plots ----

x01_plot_leverage <- ggplot(
  filter(x01_influence, response == "net_area_change_ft2_per_year"),
  aes(x = hat, y = std_resid, size = cooksd, label = interval_label)
) +
  geom_point(alpha = 0.7, color = "#2c7fb8") +
  geom_text(size = 3, vjust = -1.2, check_overlap = TRUE) +
  geom_vline(xintercept = 4 / x01_n, linetype = "dashed", color = "grey50") +
  geom_hline(yintercept = c(-2, 0, 2), linetype = c("dotted", "solid", "dotted"), color = "grey50") +
  labs(
    x = "Leverage (hat)", y = "Studentized residual", size = "Cook's D",
    title = "RS 30 net area change: influence structure",
    subtitle = "Dashed line = 2p/n leverage threshold"
  ) +
  theme_minimal(base_size = 11)

x01_plot_loo <- ggplot(x01_loo_net, aes(x = reorder(dropped, p_value), y = p_value)) +
  geom_col(fill = "#2c7fb8") +
  geom_hline(yintercept = c(0.05, 0.10), linetype = "dashed", color = c("#d95f0e", "grey40")) +
  coord_flip() +
  labs(
    x = NULL, y = "p-value with this interval dropped",
    title = "Leave-one-out sensitivity of the net-area fit",
    subtitle = "Orange = 0.05, grey = 0.10 decision threshold"
  ) +
  theme_minimal(base_size = 11)

print(x01_plot_leverage)
print(x01_plot_loo)
