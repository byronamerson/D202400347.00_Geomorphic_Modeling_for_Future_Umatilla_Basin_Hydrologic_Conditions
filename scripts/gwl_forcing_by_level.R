# =============================================================================
# gwl_forcing_by_level.R
# Umatilla River Discharge-Channel Migration Analysis
# Global Warming Level (GWL) track, step 2: forcing summarised by warming level.
# =============================================================================
#
# Sibling to gwl_windows.R, which produced the grouping key. This step applies
# it: take each member's per-water-year cum_excess from 11, keep the years that
# fall inside that member's GCM x scenario window at each warming level, and
# reduce to one row per member x level -- the same summary shape 11 hands to 12,
# keyed by warming_level instead of period.
#
#   era track : group years by calendar period   (11 -> 12)
#   GWL track : group years by warming level     (this file -> 12)
#
# 12 is NOT modified. It takes its block table and divisor as arguments and
# selects no track of its own, so a level-keyed table of the same shape is all
# it needs.
#
# Inputs : data/gwl_windows.csv                              (gwl_windows.R)
#          data/future_forcing_annual_bc-k-by-era.csv        (11b, statistical)
#          data/future_forcing_annual_bc-k-by-era-dynamical.csv (11c, dynamical)
# Output : data/gwl_forcing_by_level_<suffix>.csv, one per track
# Style  : Tidyverse & FP guidelines; docs/lingua.md.
#
# -----------------------------------------------------------------------------
# DECISIONS, so they are not re-derived
# -----------------------------------------------------------------------------
#
# 1. PARTIAL WINDOWS COUNT (Byron, 2026-09-29; PICKUP_2026-09-28 §5b, settled).
#    Five member-GCM x level combinations have windows reaching outside the
#    corrected record: two statistical (CCSM4, CanESM2 at RCP8.5 1.5 degC,
#    16/20) and three dynamical (CCSM4 1.5 degC 11/20; GFDL-ESM2M 9/20 and
#    MIROC5 12/20 at 2 degC). Missing years are filled at the mean of the years
#    present IN THAT WINDOW, then totalled to the nominal 20. n_years carries
#    the realized count so the fill is visible, never inferred.
#
#    Byron accepted the bias rather than correcting it. Direction, for the
#    caption: the window straddles the crossing year, so a window truncated at
#    the FRONT keeps the warm half and one truncated at the BACK keeps the cool
#    half. On the dynamical track these sort by level -- 1.5 degC warm-biased,
#    2 degC cool-biased -- which compresses the gap between them.
#
# 2. THE FILL IS ARITHMETIC, NOT A REPAIR. Filling k missing years at the mean m
#    of the n present gives n*m + (n_window - n)*m = n_window * m. The fill
#    cannot move the mean, so total_cum_excess below is mean * WINDOW_YEARS by
#    construction. Stated because the equality is easy to doubt: it holds for
#    any n, and the years themselves are NOT interchangeable -- only their sum.
#
#    This is the ONE deliberate departure from summarise_periods() in 11, whose
#    total_cum_excess is a straight sum over realized years. The two differ only
#    on the five short windows above.
#
# 3. PUBLISHED YEARS ARE READ AS WATER-YEAR LABELS. gwl_windows.csv carries
#    CALENDAR years -- the source works on annual-mean global temperature. 11's
#    table is keyed by water year. Window [2025, 2044] is therefore taken as
#    WY2025..WY2044, i.e. 1 Oct 2024 through 30 Sep 2044: the whole window shifts
#    three months earlier in real time, identically at every level. The crossing
#    year comes out of a 20-year running mean, so a quarter-year shift on a
#    20-year window is below the resolution of the thing being windowed, and any
#    offset rule would be a correction we could not source.
#
# 4. LEVELS ARE NOT INDEPENDENT SAMPLES, and this step does nothing about it.
#    Adjacent windows within a GCM overlap wherever the model warms from one
#    level to the next in under 20 years -- commonly 6-10 shared years between
#    1.5 and 2 degC. AR6 practice reports each level on its own with n carried
#    and does not test level against level; that constraint lives in the
#    reporting, not in the data. A year in two windows is correctly counted in
#    both. (The larger dependence is that 16 statistical members share each
#    GCM x scenario trajectory, which is true of the era track as well.)
#
# 5. THE OBSERVED ANCHOR IS NOT REBUILT HERE. 11 writes the observed record as
#    period = "historical" in its own summary, identical on both tracks, and 12
#    reads it from there. Whether the statistical Observed point keeps its
#    30-year divisor or takes 20 on a warming-level figure is a step-3 question
#    and is deliberately not answered in this file.
#
# NOTHING RUNS ON SOURCE except section 5, which builds both tracks -- the same
# shape as gwl_windows.R. Neither track reads member CSVs; both read the per-year
# tables 11 already wrote.
# =============================================================================

library(dplyr)
library(readr)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

WINDOWS_CSV  <- file.path("data", "gwl_windows.csv")

# The nominal warming-level window length. Every published window is 20 years;
# asserted rather than assumed, because the IPCC-WG1/Atlas tables use the same
# column names for a CENTRAL year and would pass through silently.
WINDOW_YEARS <- 20L

# The levels each track is permitted to report at (G6, Byron 2026-09-28). The
# dynamical record ends 2050-11-30, so no dynamical member has a usable window
# at 3 or 4 degC; CCSM4's 3 degC window (2049-2068) overlaps the record by two
# water years, which the coverage rule would otherwise fill to a nominal 20 and
# report as a level. THIS IS A HARD LIMIT, NOT A COVERAGE THRESHOLD -- it is not
# a floor on n_years, and settling it did not reopen §5b. The dynamical track
# reports 1.5 and 2 degC; that is the scope of the record.
LEVELS_BY_TRACK <- list(
  statistical = c(1.5, 2.0, 3.0, 4.0),
  dynamical   = c(1.5, 2.0)
)

# One entry per forward-modeling track. The tracks are never pooled into one
# ensemble summary (Byron, 2026-09-28) -- separate inputs, separate outputs, no
# shared row anywhere in this file.
TRACKS <- tibble::tribble(
  ~track,         ~annual_csv,                                           ~out_csv,
  "statistical",  "data/future_forcing_annual_bc-k-by-era.csv",           "data/gwl_forcing_by_level_bc-k-by-era.csv",
  "dynamical",    "data/future_forcing_annual_bc-k-by-era-dynamical.csv", "data/gwl_forcing_by_level_bc-k-by-era-dynamical.csv"
)


# =============================================================================
# 2. READ
# =============================================================================

read_windows <- function(path, window_years = WINDOW_YEARS) {
  #' Purpose: the warming-level windows, verified to be the length we summarise
  #'          to.
  #' In     : path to gwl_windows.csv.
  #' Out    : tibble(gcm, scenario, warming_level, start_year, end_year).
  #' Decision: n_years is recomputed from the span rather than trusted, and the
  #'          assertion is the guard PICKUP_2026-09-28 §6 records as missing. A
  #'          table of centred years would satisfy the column names and fail
  #'          here, which is the point.
  w <- read_csv(path, show_col_types = FALSE)
  stopifnot(all(c("gcm", "scenario", "warming_level",
                  "start_year", "end_year") %in% names(w)))
  span <- w$end_year - w$start_year + 1L
  if (!all(span == window_years)) {
    stop(sprintf("gwl_windows.csv: %d window(s) are not %d years (span %s)",
                 sum(span != window_years), window_years,
                 paste(sort(unique(span[span != window_years])), collapse = ", ")))
  }
  select(w, gcm, scenario, warming_level, start_year, end_year)
}

read_future_annual <- function(path) {
  #' Purpose: one track's per-water-year forcing, future members only.
  #' In     : path to an 11 annual table.
  #' Out    : tibble(member_id, gcm, scenario, downscaling, hydro, water_year,
  #'          cum_excess, n_days).
  #' Decision: `period` and `t_norm` are dropped. They are the ERA grouping and
  #'          carry no meaning on this axis; leaving them would let a level-keyed
  #'          row be read against a calendar block. The observed rows are dropped
  #'          with source != "future" -- see decision 5 in the header.
  read_csv(path, show_col_types = FALSE) %>%
    filter(source == "future") %>%
    select(member_id, gcm, scenario, downscaling, hydro,
           water_year, cum_excess, n_days)
}


# =============================================================================
# 3. THE FILTER
# =============================================================================

limit_levels <- function(windows, track) {
  #' Purpose: drop the warming levels a track's record cannot support.
  #' In     : windows, from read_windows(); track, a name in LEVELS_BY_TRACK.
  #' Out    : windows, restricted to that track's permitted levels.
  #' Decision: applied to the WINDOWS, before any member-year is joined, so an
  #'          unsupported level produces no row anywhere rather than a row that
  #'          a later filter has to remember to remove. See LEVELS_BY_TRACK.
  keep <- LEVELS_BY_TRACK[[track]]
  if (is.null(keep)) stop(sprintf("no permitted levels declared for track '%s'", track))
  filter(windows, warming_level %in% keep)
}

tag_warming_level <- function(annual, windows) {
  #' Purpose: keep the member-years that fall inside their own GCM x scenario
  #'          window at each warming level.
  #' In     : annual, per member x water year; windows, from read_windows().
  #' Out    : annual + warming_level, member-years in no window removed.
  #' Decision: the join keys on gcm AND scenario as well as the year span. A
  #'          warming level is a property of (GCM, scenario, years) only, so
  #'          every member sharing a GCM x scenario inherits the same windows --
  #'          but joining on the year alone would hand every member every GCM's
  #'          windows.
  #' Decision: inner_join, not left. A member-year outside every window belongs
  #'          to no level and is not part of this axis; keeping it as NA would
  #'          only invite a downstream filter to forget it.
  #' Note    : this join MULTIPLIES rows where a GCM's windows overlap, and that
  #'          is correct -- the year belongs to both levels. See header §4.
  annual %>%
    inner_join(windows,
               by = join_by(gcm, scenario,
                            between(water_year, start_year, end_year))) %>%
    select(-start_year, -end_year)
}

summarise_levels <- function(tagged, window_years = WINDOW_YEARS) {
  #' Purpose: one row per member x warming level -- the step-3 rate primitive,
  #'          on the same columns summarise_periods() produces in 11.
  #' In     : tagged, from tag_warming_level(); window_years, the nominal length.
  #' Out    : tibble(member factors, warming_level, t_norm, n_years,
  #'          mean_annual_cum_excess, total_cum_excess, max_annual_cum_excess,
  #'          is_partial).
  #' Decision: n_years is REALIZED (member-years actually in the window) and
  #'          t_norm is NOMINAL (window_years). They differ exactly where the
  #'          record does not cover the window, and both are carried so the
  #'          difference is visible rather than inferred.
  #' Decision: total_cum_excess is the FILLED total, mean * window_years, per
  #'          header §1-2 -- NOT the straight sum 11 writes. On a full window the
  #'          two are the same number.
  tagged %>%
    group_by(member_id, gcm, scenario, downscaling, hydro, warming_level) %>%
    summarise(n_years                = dplyr::n(),
              mean_annual_cum_excess = mean(cum_excess),
              max_annual_cum_excess  = max(cum_excess),
              .groups = "drop") %>%
    mutate(t_norm           = window_years,
           total_cum_excess = mean_annual_cum_excess * window_years,
           is_partial       = n_years < window_years) %>%
    select(member_id, gcm, scenario, downscaling, hydro, warming_level,
           t_norm, n_years, is_partial,
           mean_annual_cum_excess, total_cum_excess, max_annual_cum_excess) %>%
    arrange(scenario, warming_level, gcm, member_id)
}


# =============================================================================
# 4. THE UNIT OF WORK -- one track
# =============================================================================

run_gwl_forcing <- function(annual_csv, out_csv, windows, track_label) {
  #' Purpose: build and write one track's warming-level forcing summary.
  #' In     : annual_csv, an 11 per-year table; out_csv, where to write;
  #'          windows, from read_windows(); track_label, named in messages.
  #' Out    : the summary, invisibly. (I/O at this boundary only.)
  stopifnot(file.exists(annual_csv))
  annual  <- read_future_annual(annual_csv)
  allowed <- limit_levels(windows, track_label)
  tagged  <- tag_warming_level(annual, allowed)

  if (nrow(tagged) == 0L) {
    stop(sprintf("%s: no member-year fell in any warming-level window", track_label))
  }

  out <- summarise_levels(tagged)
  write_csv(out, out_csv)

  message(sprintf("%s: levels %s; %d member-years -> %d member x level rows (%d partial); wrote %s",
                  track_label,
                  paste(LEVELS_BY_TRACK[[track_label]], collapse = "/"),
                  nrow(tagged), nrow(out), sum(out$is_partial), out_csv))
  invisible(out)
}


# =============================================================================
# 5. BUILD  (both tracks; the only thing that runs on source)
# =============================================================================

windows <- read_windows(WINDOWS_CSV)

gwl_forcing <- purrr::pmap(TRACKS, function(track, annual_csv, out_csv) {
  run_gwl_forcing(annual_csv, out_csv, windows, track)
}) %>% setNames(TRACKS$track)


# =============================================================================
# 6. REPORT
# =============================================================================

cat("\n=== 1. Members and GCMs behind each warming level ===\n")
purrr::imap(gwl_forcing, function(d, track) {
  d %>%
    group_by(track = track, scenario, warming_level) %>%
    summarise(n_members = dplyr::n(),
              n_gcms    = dplyr::n_distinct(gcm),
              .groups   = "drop")
}) %>%
  bind_rows() %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n    The n a figure at each level must carry. Tracks are reported side by\n",
    "   side and never pooled. The dynamical track cannot reach 3 or 4 degC --\n",
    "   its record ends in 2050 -- and that is a scoping fact, not a gap.\n", sep = "")

cat("\n=== 2. Partial windows ===\n")
bind_rows(gwl_forcing, .id = "track") %>%
  filter(is_partial) %>%
  distinct(track, scenario, warming_level, gcm, n_years, t_norm) %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n    Windows the corrected record does not fully cover. Missing years were\n",
    "   filled at the mean of the years present, so the total is on the nominal\n",
    "   ", WINDOW_YEARS, "-year scale. Expected: CCSM4 and CanESM2 at RCP8.5 1.5 degC on the\n",
    "   statistical track; CCSM4 at 1.5 degC and GFDL-ESM2M / MIROC5 at 2 degC on\n",
    "   the dynamical track. Anything else here is unexplained -- stop and look.\n", sep = "")

cat("\n=== 3. Level means, pooled within track x scenario ===\n")
bind_rows(gwl_forcing, .id = "track") %>%
  group_by(track, scenario, warming_level) %>%
  summarise(members            = dplyr::n(),
            mean_annual        = round(mean(mean_annual_cum_excess)),
            min_member         = round(min(mean_annual_cum_excess)),
            max_member         = round(max(mean_annual_cum_excess)),
            .groups            = "drop") %>%
  as.data.frame() %>% print(row.names = FALSE)

cat("\n    Mean annual cum_excess (cfs-days/yr) across members at each level. The\n",
    "   spread is the ensemble's, not an uncertainty estimate. F_hist for\n",
    "   comparison is 3,465 cfs-days/yr over WY1952-2026.\n", sep = "")
