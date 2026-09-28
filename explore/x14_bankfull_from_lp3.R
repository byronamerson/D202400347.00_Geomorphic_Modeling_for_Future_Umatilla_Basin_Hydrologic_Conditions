# =============================================================================
# x14_bankfull_from_lp3.R
# Umatilla River Discharge-Channel Migration Analysis
# Where does 0.75*Q2 sit vs bankfull? Recover Q1.5 from the existing LP3 fit.
# =============================================================================
#
# The B17C flood-frequency table (data/flood_frequency.csv) bottoms out at the
# 2-year. Bankfull is usually taken as ~Q1.5. To locate it we recover the fitted
# LP3 curve's parameters (log-mean M, log-sd S, skew G) from the tabulated
# quantiles via the Wilson-Hilferty frequency factor (the same one B17 uses),
# confirm the recovery reproduces the tabulated points, then evaluate BELOW the
# 2-year at T = 1.5 and 1.25. This is the *existing* observation-based fit, just
# read at return periods it wasn't printed for -- no new frequency analysis.
#
# Then: what return period does 0.75*Q2 (4,156 cfs) actually correspond to? If it
# lands near T=1.5, calling it "bankfull" is fair; if higher, it sits above bankfull.
#
# Caveat: Pendleton's fit rests on 30 years, so sub-2-year extrapolation carries
# real uncertainty. Cross-checked against peakfq_results.rds if it holds the params.
# =============================================================================

suppressPackageStartupMessages(library(tidyverse))

Q2_CFS   <- 5541.8
FLOOR_75 <- 0.75 * Q2_CFS   # 4,156

ff <- read_csv("data/flood_frequency.csv", show_col_types = FALSE) %>%
  filter(gage_id == "14020850") %>%
  arrange(return_period_yr)

Tr <- ff$return_period_yr
Q  <- ff$q_cfs
y  <- log10(Q)
z  <- qnorm(1 - 1 / Tr)      # standard normal deviate for each return period

# Wilson-Hilferty Pearson-III frequency factor (-> z as G -> 0)
Kwh <- function(z, G) {
  if (abs(G) < 1e-8) return(z)
  (2 / G) * ((1 + G * z / 6 - G^2 / 36)^3 - 1)
}

# recover LP3 params (M, S, G) by least squares on log10(Q) vs the tabulated curve
obj <- function(p) {
  M <- p[1]; S <- p[2]; G <- p[3]
  sum((y - (M + vapply(z, Kwh, numeric(1), G = G) * S))^2)
}
fit <- optim(c(mean(y), sd(y), -0.1), obj, method = "Nelder-Mead",
             control = list(reltol = 1e-12, maxit = 5000))
M <- fit$par[1]; S <- fit$par[2]; G <- fit$par[3]

# quantile from the recovered curve
qT <- function(t) 10^(M + Kwh(qnorm(1 - 1 / t), G) * S)

# return period of a given discharge (invert)
rp_of <- function(q) {
  f <- function(t) qT(t) - q
  uniroot(f, c(1.001, 500))$root
}

# ---- fit check: recovered vs tabulated ----
check <- ff %>% mutate(q_fit = vapply(return_period_yr, qT, numeric(1)),
                       pct_err = 100 * (q_fit - q_cfs) / q_cfs)

cat("\n===========  LP3 fit recovery (Pendleton 14020850)  ===========\n")
cat(sprintf("Recovered LP3: log-mean %.4f, log-sd %.4f, skew %.3f\n", M, S, G))
cat("Fit check (recovered vs tabulated B17C):\n")
check %>% transmute(return_period_yr, tabulated = round(q_cfs),
                    recovered = round(q_fit), pct_err = round(pct_err, 2)) %>%
  as.data.frame() %>% print(row.names = FALSE)

# ---- the answer: sub-2-year quantiles ----
sub <- tibble(return_period_yr = c(1.1, 1.25, 1.5, 2)) %>%
  mutate(q_cfs = vapply(return_period_yr, qT, numeric(1)),
         frac_of_Q2 = q_cfs / Q2_CFS)

cat("\nSub-2-year discharges from the same LP3 fit:\n")
sub %>% mutate(q_cfs = round(q_cfs), frac_of_Q2 = round(frac_of_Q2, 3)) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat(sprintf("\n0.75*Q2 = %.0f cfs corresponds to a  T = %.2f-year  flood.\n",
            FLOOR_75, rp_of(FLOOR_75)))
cat(sprintf("Bankfull proxy Q1.5 = %.0f cfs = %.2f*Q2.  0.75*Q2 is %s bankfull.\n",
            qT(1.5), qT(1.5) / Q2_CFS,
            if (FLOOR_75 > qT(1.5)) "ABOVE" else "at/below"))

# ---- cross-check against the stored PeakFQ object, if it carries the params ----
cat("\n--- peakfq_results.rds structure (cross-check) ---\n")
pf <- tryCatch(readRDS("data/peakfq_results.rds"), error = function(e) NULL)
if (!is.null(pf)) str(pf, max.level = 2) else cat("could not read peakfq_results.rds\n")
