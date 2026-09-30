# =============================================================================
# eras.R
# Umatilla River Discharge-Channel Migration Analysis
# The project's era blocks -- ONE definition, sourced by every stage that uses them.
# =============================================================================
#
# An era is a block of calendar years. The same blocks do three jobs:
#
#   1. Bias correction (10 / 10b / 10c). The PresRat K factor is computed and
#      applied within each era, so the correction multiplier STEPS at an era
#      boundary and is constant inside one.
#   2. Future forcing (11 / 11b / 11c). The per-member forcing summary.
#   3. Migration projection (12 / 12b / 12c). The reporting period -- the slots
#      along the x-axis of the migration-rate figures.
#
# They did not always agree. Until 2026-09-29 the three stages each carried their
# own statistical table (correction 2006-2035/2036-2065/2066-2099; forcing
# 2030s/2040-2069/2070-2099; projection 2010-2039/2040-2069/2070-2099), so two of
# the three reported periods straddled a K step and held two different
# corrections. The dynamical track happened to agree across all three.
#
# Byron, 2026-09-29: the bias-correction eras are the master temporal logic and
# the rest of the workflow inherits them, the dynamical track keeping its own
# breakdown. This file IS that single definition -- no other script should
# declare a block table.
#
# NOTHING RUNS ON SOURCE. Definitions only, so sourcing this starts no work.
# That is why sourcing it does not violate the no-source-chaining rule
# (docs/lingua.md, adopted 2026-09-17): the rule is about not triggering a run,
# and this file triggers nothing.
#
# KNOWN LIMIT, stated rather than papered over: warming-level windows are 20
# years, model-specific, and cut across these blocks however the blocks are
# drawn. Alignment holds for the calendar-era workflow; on the warming-level axis
# it cannot, and belongs in the methods text as a caveat (Byron, 2026-09-29: the
# multipliers sit close to unity, so the effect there is second-order).
# =============================================================================

library(dplyr)


# --- The blocks ---------------------------------------------------------------

# Statistical track (BCSD + MACA). Corrected record 2006-2099 = 94 years.
# Pierce et al. (2015) segments the future into 30-year blocks. 30 does not
# divide 94, so the tail carries the 4-year remainder at 34 rather than leaving a
# 4-year block whose mean change would rest on very few days.
ERAS_STATISTICAL <- tribble(
  ~era,         ~y1,    ~y2,
  "2006-2035",  2006L,  2035L,
  "2036-2065",  2036L,  2065L,
  "2066-2099",  2066L,  2099L
)

# Dynamical track. Corrected record 2011-01-01 -> 2050-11-30 = 40 years.
# Two 20-year blocks, NOT Pierce's 30: 30 would split 40 into 30 and 10, leaving
# the end of the record in a block a third the length of the other. 20 is already
# this project's block length (the warming-level windows are all 20 years), so it
# introduces no new unit. Deliberately NOT aligned with the statistical table --
# the two tracks are separate analytical tracks, never pooled into one ensemble
# summary, and K never crosses between them.
#
# Property, not a defect: the record ends 2050-11-30, so the second block holds
# 20 Januaries and 19 Decembers where the first holds 20 of each. K is a ratio
# against a control carrying the same truncation, so it largely cancels, but it
# is asymmetric between the two blocks. December is not the flood month here
# (measured 2026-09-28: 7% of dynamical above-bankfull days, against Feb-Apr
# carrying the bulk).
ERAS_DYNAMICAL <- tribble(
  ~era,         ~y1,    ~y2,
  "2011-2030",  2011L,  2030L,
  "2031-2050",  2031L,  2050L
)


# --- The observed point -------------------------------------------------------

# The migration figures carry an "Observed" slot: the model's own rendering of
# the historical flood record, one value per reach, and the height the future
# eras climb from. It belongs to no era, but the model's intercept is a
# per-INTERVAL offset, so reporting it as ft/yr means dividing by SOME number of
# years. That divisor is stated here rather than read off the era table, because
# the statistical eras are no longer all one length (30 / 30 / 34) and there is
# therefore no single length to read. 34 is the arithmetic remainder of 94/30,
# not a chosen block length, so 30 is the honest divisor. Byron, 2026-09-29.
#
# Consequence, already on record (SESSION_LOG_2026-09-29b): this divisor is
# track-specific, so the same observed record plots at a different height on the
# two tracks' absolute-rate figures (RS30: 9.07 ft/yr at 30, 9.66 at 20).
# Internally consistent within a figure; the two figures cannot be read against
# each other by eye. The change-vs-historical view is unaffected -- the divisor
# cancels in the difference.
OBS_WINDOW_YEARS_STATISTICAL <- 30L
OBS_WINDOW_YEARS_DYNAMICAL   <- 20L


# --- Shape conversion ---------------------------------------------------------

as_period_table <- function(eras) {
  #' The era table in the shape 11 and 12 consume. (pure)
  #' Those two key their outputs on a column called `period`, and need each
  #' block's length in years (`t_norm`) -- the model uses it to annualize its
  #' per-interval intercept and to place forcing on the model's interval scale.
  #' Length is NOMINAL, from the table; it is not the realized year count, which
  #' can be lower where a partial water year was dropped. Both are carried
  #' downstream so the difference stays visible rather than inferred.
  #' Replaces with_t_norm(), which was duplicated in 11 and 12.
  #' @param eras tibble(era, y1, y2) -- one of the tables above.
  #' @return tibble(period, y1, y2, t_norm)
  stopifnot(all(c("era", "y1", "y2") %in% names(eras)), nrow(eras) > 0)
  eras %>%
    rename(period = era) %>%
    mutate(t_norm = as.integer(y2 - y1 + 1L))
}
