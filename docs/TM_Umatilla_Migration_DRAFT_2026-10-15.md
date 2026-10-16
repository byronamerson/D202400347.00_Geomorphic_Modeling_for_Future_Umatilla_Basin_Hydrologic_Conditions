# Projected Channel Migration, Umatilla River RS28–RS37

**Technical Memorandum — DRAFT**
Project D202400347.00 | Draft of 2026-10-15

> Draft status: Results restructured this revision. The calendar-era and
> warming-level framings now run in sequence, followed by a comparison of what
> each conveys. The dynamical track is reported as findings in text; its plots,
> the change-in-rate plots and the heat maps are in Appendix B. Discussion,
> Limitations and Section 6 drafted this revision. Summary written
> this revision. Figure axis labels and font sizes pending revision (latex2exp
> pass).

---

## 0. Summary and High-Level Messages

This memorandum estimates how fast the Umatilla River upstream of Pendleton will
rework its channel and floodplain under projected future hydrology. We measured
historical channel migration from seventy years of aerial photography, fit the
relationship between that migration and the flood volume delivered over each
photo interval, and drove the fitted relationship with downscaled streamflow
projections through 2099. The result is a reach-scale estimate of migration rate
for two emissions scenarios, three calendar eras and four global warming levels.

**Migration rates increase. The direction is certain; the magnitude is not.**
Under the high-emissions pathway, median rates at late century are roughly three
times their historical values. At late century every one of the eighty ensemble
members produces
an increase, at every reach: the result does not depend on which
climate model, downscaling method or hydrologic model a run happens to use. How
large the increase is remains open. Across those runs the middle eighty percent
spans a factor of about two and a half.

**That remaining uncertainty is about the river's response to warming, not about
when warming arrives.** Grouping the same runs by amount of warming rather than
by date does not narrow the range. What the models disagree about is how much
flow a given amount of warming delivers to this basin. Better information about
the timing of warming would not sharpen the answer, which argues for designing
against a range of outcomes rather than waiting for the range to close.

**Emissions pathway matters little before mid-century and considerably after.**
The two scenarios differ by about nine percent at 2036-2065 and by thirty-six
percent at 2066-2099. Decisions on near-term horizons are largely insensitive to
which pathway the world follows; decisions with a design life reaching past
mid-century are not.

**The flood season moves earlier, which a rate alone does not show.** An
independent hydrologic model of this basin, developed by CTUIR's Department of
Natural Resources, puts the wettest month of the year in April under hindcast
conditions and in February by late century. Winter's share of annual volume
rises
by roughly half and spring's falls by about a third. Snowmelt-driven spring
peaks
and rain-driven winter peaks are not interchangeable inputs to a migrating
channel, so the character of the geomorphic work changes along with its amount.

**This is one of the few analyses to estimate channel migration under future
climate scenarios from available information.** The method builds a relationship
between flood hydrology and measured migration, then applies it as a forward
model. It uses only data already in hand, including published channel migration
mapping, the gage record, and publicly released streamflow projections, with no
new field data collection, and it is transferable to other basins where those
three ingredients exist. The approach carries real limitations, set out in
Section 5, and the projections should be read as a relative index of migration
risk rather than as a forecast of channel position.

**Two independent checks support the projection chain.** The CTUIR model
reproduces the monthly change signal of the projections used here at the gage
that forces every reach in this study, and its three nodes show the flood-season
change signal to be spatially uniform within three percent across a 2.5-fold
range in drainage area, which is the assumption the forward model makes in
applying one change signal across the study corridor.

**Flood volume, not peak discharge, is what the historical record resolves.**
The
forcing variable is cumulative excess discharge: the volume by which daily flow
exceeds the bankfull threshold of 4,156 cfs, summed over the interval. It
outperformed peak discharge and a simple count of above-threshold days. Channel
migration in this river responds to how much water is delivered above the
threshold of motion and for how long, not to the height of the hydrograph peak.

**The fitted relationship rests on a pre-fire record.** The 2026 fire season
burned substantial ground in the contributing area above the gages that force
every reach here. Where fire increases hillslope delivery of sediment and wood,
a
given discharge may perform more geomorphic work than the fitted relationship
predicts, which would make these estimates conservative in the affected reaches.

**What the results support now.** These estimates are usable for reading
relative
migration risk across the study corridor, for setting design life and setback
distances for restoration projects and infrastructure, and for sequencing work
where the projected rate increase and the exposure of a valued asset coincide.
Section 6 identifies the applied tools, including forecasting, screening and
early warning keyed to conditions already on the ground, that the same
flow-to-migration relationship could support and that do not yet exist.

---

## 1. Introduction

The February 2020 flood showed how quickly the Umatilla River restructures its
channel and floodplain, and how exposed the features that sustain First Foods
are to extreme hydrology that departs from the historical record.
Such departure is a signature of hydrologic non-stationarity. Stationarity is
the
assumption that a river fluctuates within an unchanging envelope of
variability, so
flood magnitude and frequency follow a fixed underlying distribution that a long
enough gage record will eventually pin down (Milly et al. 2008). Under
non-stationarity that envelope is itself moving. The climate conditions
generating
the flows are changing, so a longer record describes the past more precisely
without
describing the future any better. Projections for the upper basin indicate
greater
flow variability, a shift from snow toward rain, and higher winter flows through
late century, with the rain-on-snow zone migrating upslope into terrain that now
accumulates snow (Clifton et al. 2017). The concern is not larger floods alone:
extreme floods combined with
increased variability yield a widening separation between the large floods that
restructure the fluvial system, which recur on a decadal scale, and
the moderate floods that maintain it. Both flood styles perform the geomorphic
work behind
the floodplain processes that support First Foods, as the CTUIR River Vision
describes.
This analysis treats that full range of channel-forming flow as one quantity
and asks a
narrower question of it: how much faster does the channel migrate under the
projected
future climate?

Evaluating what this means for channel migration takes three pieces, and two of
them
already exist for this basin.
The Oregon Department of Geology and Mineral Industries (DOGAMI) has mapped
channel migration zones (CMZs) for the Umatilla River and lower McKay Creek
under the Washington State CMZ protocol (Appleby et al. 2025; Olson et al.
2014),
delineating the area the channel can
be expected to occupy. A CMZ bounds where migration can occur; it reports no
rate, and it is drawn from the historical record rather than a projected one.

Downscaled streamflow projections for the upper basin extend through 2099 under
two emissions scenarios, describing the changed flow regime (Chegwidden et al.
2017). They stop short of
geomorphic consequence: they describe how the hydrology changes, not what the
channel does in response. What neither supplies is the third piece: a
relationship that
converts a flow regime into a migration rate.

This memorandum builds that third piece. We fit the historical relationship
between flood
hydrology and measured channel migration across ten reaches, then drive that
relationship with the projected flows to estimate migration rates through 2099.
The result is a reach-scale index of relative migration risk, suitable for
ranking reaches against one another and for comparing time periods and warming
levels. It is not a forecast of where the channel will be in a given year. Other
drivers of channel change are shifting at the same time; Section 4 returns to
them.

Reaches are identified by DOGAMI's river station (RS) numbering, so results can
be read directly against the published CMZ mapping. The analysis covers RS28
through RS37, the reaches upstream of Pendleton, which is the scope of this
project.

---

## 2. Methods

The analysis links three datasets that were not developed to work together:
mapped
historical channel positions, the Pendleton streamflow record, and downscaled
future flow projections. The chain progresses in three steps. We quantify
historical
migration from the mapping, fit a model relating it to flood hydrology over the
same intervals, then apply that model to projected flows. Each analytical step
required
preparatory work on its inputs, described below.

**Quantifying historical migration.** DOGAMI digitized Umatilla River planform
position from aerial photography at fifteen dates between 1952 and 2022, as
the historical migration area (HMA) component of its CMZ mapping (Appleby et al.
2025), which follows the channel migration zone framework of Rapp and Abbe
(2003). For each
reach and each photo interval, we measured the area newly occupied by the
active channel and normalized it by reach centerline length, yielding new
channel area per foot of reach, the approach implemented in the Washington
Channel Migration Toolbox (Legg et al. 2014). Annualized, this is the migration
rate reported
throughout. The metric describes areal reworking of the active corridor rather
than centerline displacement, and it is signed positive: abandoned area is not
netted against it. Reaches RS25 through RS27, which run through the city of
Pendleton between engineered levees, are excluded because migration there is
mechanically precluded and belongs to a different process.

**Flood forcing.** Daily mean discharge comes from USGS 14020850, Umatilla
River at Pendleton. The channel mapping begins in 1952 and the gage record
begins in late 1995, so most photo intervals have no observed daily record at
Pendleton. We extended the record to 1952 by MOVE.1 (maintenance of variance
extension), a record-extension technique that preserves the variance of the
reconstructed series rather than regressing toward the mean (Hirsch 1982),
applied with the USGS `smwrStats` implementation and fitted on high
flows against the Gibbon gage (USGS 14020000). Only flows above the
reconstruction floor were estimated; the method targets the flood tail, not a
general hydrograph. For each photo interval we computed cumulative excess
discharge above bankfull: the summed volume, in cfs-days, by which daily
discharge exceeded the bankfull threshold of 4,156 cfs, taken as 0.75 times the
two-year flood. The two-year flood was estimated by log-Pearson Type III
flood-frequency analysis following Bulletin 17C (England et al. 2018), with the
annual peak record extended by MOVE.3 as that guidance recommends (Vogel and
Stedinger 1985). The metric integrates flood magnitude over flood duration,
following the geomorphic-effectiveness literature (Costa and O'Connor 1995;
Magilligan et al. 2015). It outperformed peak discharge and a simple count of
above-threshold days on the same intervals. The metric sums all flow above
bankfull and does not distinguish moderate events from large ones.

**The fitted relationship.** We fit a linear mixed-effects model of migration
rate on cumulative excess discharge, with reach-specific intercepts and slopes.
Mixed-effects means the model estimates reach-level coefficients as draws from
a common distribution rather than fitting ten unconstrained regressions, which
stabilizes the per-reach slopes given thirteen or fourteen intervals apiece.
The reach
slope is that reach's flood sensitivity, in feet of new channel area per foot
of reach per 1,000 cfs-days. A crossed random effect on photo interval accounts
for the shared hydrology: all ten reaches experience the same flood in a given
interval, so their residuals are not independent. Interval length enters as a
fixed effect, separating background reworking that accrues with elapsed time
from flood-driven reworking. The fitted coefficients, and the variation the
model partitions among reaches, photo intervals and residual, are reported in
Section 3.1.

**Projected streamflow.** Future flows come from the Columbia River basin
hydrologic projections of Chegwidden et al. (2017), routed to the Umatilla
River at Pendleton. An ensemble member is one path through four methodological
choices: emissions scenario, global climate model (GCM), downscaling method,
and hydrologic model. Downscaling translates GCM output at roughly 150 km
resolution to the approximately 6 km grid on which the hydrologic models run.
The primary ensemble uses statistical downscaling and comprises 80 members per
emissions scenario, RCP4.5 and RCP8.5, at a daily timestep from 2006 through
2099. A second set of twelve dynamically downscaled members under RCP8.5,
extending only to 2050, is reported as a separate track because its
meteorological forcings were trained against a different historical dataset and
are not interchangeable with the statistical members. One external check on
this ensemble is available. CTUIR's Department of Natural Resources built a
SWAT model of the upper basin, an independent hydrologic model of this river,
and two GCMs are common to both products; at the West Reservation Boundary node
its simulated monthly change signal reproduces the change signal in the
projections used here (O'Daniel and Rogers-Pachico n.d.).

**Bias correction, and the claims it supports.** The projections were supplied
as raw routed streamflow. The providers bias-corrected their output at 190
sites against reference flows by the preservation-of-ratio method (Pierce et al.
2015), and the Umatilla River at Pendleton is not among
them, so correction fell to this analysis. Uncorrected, the routed flows
under-produce floods at Pendleton, exceeding bankfull about one day per year
where the gage record gives several. We corrected each member by quantile delta
mapping (QDM; Cannon et al. 2015, applied with the `MBC` package), which maps
the modeled flow distribution onto the observed
distribution while preserving each member's own projected change in that
distribution. The correction multiplier is computed and applied within each
reporting era. Change preservation is the reason QDM is used rather than
conventional quantile mapping: a fixed transfer function distorts the projected
change signal most severely in the upper tail, which is where this metric
lives. Hindcast testing bounded the claim. The corrected series reproduce the
frequency and magnitude distribution of above-bankfull flow, but they do not
reproduce the timing of individual floods, because GCM calendar dates are not
observational dates. We therefore treat the corrected flows as distributionally
faithful synthetic hydrographs and report results as multi-decadal summaries,
never as dated events.

**Reporting axes.** Results are presented on two groupings of the same
corrected flows. The calendar-era axis uses 2006–2035, 2036–2065 and 2066–2099
for the statistical ensemble, following the 30-year blocking convention of
Pierce et al. (2015), and two twenty-year blocks for the dynamical
track. The global warming level (GWL) axis instead pools each GCM over the
twenty-year window where its global mean temperature first crosses 1.5, 2, 3
or 4 °C above pre-industrial. Crossing years are taken as published in the
Intergovernmental Panel on Climate Change Sixth Assessment, Working Group I,
Chapter 11 tables (Hauser et al. 2022), computed from the same multi-model
climate archive these projections draw on. Reporting results by warming level
rather than by date is the more recent of the two conventions, adopted broadly
through that assessment; it complements the calendar-era view rather than
replacing it.
Models disagree
about when a given warming level arrives, so a fixed calendar window pools
different climate states together; a warming level removes that timing
disagreement and isolates the hydrologic and geomorphic response. One caveat
follows from the mismatch: the warming-level windows are model-specific and cut
across the eras within which the bias-correction multipliers are defined.

**Applying the model.** Reach coefficients are frozen at their fitted values
and applied to each period's mean annual cumulative excess discharge, producing
a migration rate for every reach, period and ensemble member. Rates are
reported on a 30-year basis, for the reason given in Appendix A. The forward
model applies one projected change signal across the whole study corridor.
CTUIR's SWAT runs support that structure: in the flood season their simulated
change ratios agree within 3 percent between a 176 mi² snowmelt tributary and
the 441 mi² mainstem node, a 2.5-fold range in drainage area within the same
basin (O'Daniel and Rogers-Pachico n.d.).

---

## 3. Results

### 3.1 The fitted relationship

The model relates channel migration over a photo interval to the flood forcing
delivered during that interval and to the interval's length. Migration,
*A*~new~, is the new channel area created between successive photo dates (area
within the corridor at the later date but not the earlier one), in feet of new
area per foot of reach. Forcing, *K*, is the interval's cumulative excess
discharge in thousands of cfs-days. Interval length, *T*, is the elapsed time
between photo dates, in years. Each reach *i* carries its own intercept *a*~i~
and slope *b*~i~; the elapsed-time coefficient *c* is shared across reaches.

> A_new,i = a_i + b_i K + c T

In words: the new area a reach creates over an interval is its own intercept,
plus an amount proportional to the flood forcing it received, plus a small
allowance for how long the interval ran. The reach intercepts and slopes are
estimated with the ten reaches constrained toward a common average rather than
fitted independently. The fit uses 139 reach-interval observations across ten
reaches.

Of the three terms, *b* (the flood term) is the one the record pins down. Its
mean across reaches is 1.081 ft per 1,000 cfs-days, standard error 0.316.
Reaches depart from
that mean with a standard deviation of 0.445, roughly forty percent of the
mean, and the fitted per-reach slopes *b*~i~ run from 0.378 at RS29 to 1.654 at
RS30
(Figure 1). That spread is the reach sensitivity the projections propagate.

*c* (the elapsed-time coefficient), 1.371 ft per year, and *a* (the population
intercept), 11.52 ft, are both uncertain enough that the record cannot
distinguish them from zero; each estimate is only 1.2 to 1.5 times its own
standard error. Interval
length is also confounded with position in the record, since the long intervals
are early and the short ones recent, so anything changing systematically across
seventy years loads onto this term. It enters the absolute rates in Section 3.2
as a constant offset shared by every reach, period and ensemble member, and
cancels entirely in the change-relative-to-historical view.

The model separates several sources of variation, and the largest of them is
the flood of the moment. Each photo interval carries its own adjustment with a
standard deviation of 15.3 ft, about the same size as the 17.8 ft the model
cannot explain at all, and larger than the 11.6 ft by which reaches differ from
each other in baseline. Reaches responding to the same flood do not supply
independent observations of it, which is why photo interval enters as a random
effect.

![Fitted forcing–migration relationship by reach](../plots/forcing_model_reach_fit.png)

**Figure 1.** Fitted relationship between flood forcing and channel migration,
by reach. Points are the observed photo intervals; the green line is each
reach's own fitted slope and the orange line the population slope, with the
interval-length effect held at zero so the two are comparable. The vertical
axis is new channel area per foot of reach length over the interval, not an
annual rate.

### 3.2 Calendar-era framing

**Historically, migration rates vary threefold between reaches.** Over the
70-year record, reach-average rates range from 2.7 ft/yr at RS29 to 8.3 ft/yr
at RS30, with most reaches between 4.5 and 6.7 ft/yr. This spread reflects
reach setting, not flow: all ten reaches see the same hydrology (Table 1).

**Projected rates rise by a factor of roughly three by late century, and the
increase is nearly uniform across reaches.** Under RCP8.5, late-century
(2066–2099) median rates reach 2.3 to 3.1 times their historical values, with
eight of the ten reaches falling between 2.8 and 3.1. Reach ranking is
essentially unchanged: RS30 remains the fastest-migrating reach and RS29 the
slowest, with only RS31 and RS37 trading places. The projected hydrology
scales the existing pattern of migration rather than rearranging it (Table 1,
Figure 2).

**The increase is back-loaded.** Near-term (2006–2035) medians sit only
slightly above historical values, with RS30 moving from 8.3 to 9.8 ft/yr.
Rates roughly double by mid-century (RS30, 16.7 ft/yr) and approach tripling
by late century (RS30, 23.6 ft/yr).

**Emissions scenario separates the projections only after mid-century.** At
2036–2065 the two scenarios differ by about 9 percent (RS30: 15.3 ft/yr under
RCP4.5, 16.7 under RCP8.5). By 2066–2099 they differ by 36 percent (17.3
versus 23.6 ft/yr). Scenario choice has little effect on the first half of the
century.

**The increase is certain in direction and uncertain in size.** Each projection
used here is one run of a climate model, and 80 runs are used. At late century
every one of them gives a higher migration rate than today, at every reach. How
much higher is the open question: across those runs the middle 80 percent span
roughly a factor of two and a half. At RS30 under the high-emissions pathway,
the runs cluster around 23.6 ft/yr but range from about 15 to 38. That range is
wider than the gap between the two emissions pathways, and the ranges for the
two pathways overlap through their middles. Which climate future arrives
matters more to the result than which emissions pathway the world follows.
Grouping the runs by amount of warming rather than by date leaves this range
unchanged (Section 3.4), so a firmer arrival date would not narrow it.

**Table 1.** Historical and projected median migration rates by reach,
calendar-era axis (ft/yr).

| Reach | Historical | RCP4.5 2006–35 | RCP4.5 2036–65 | RCP4.5 2066–99 | RCP8.5 2006–35 | RCP8.5 2036–65 | RCP8.5 2066–99 |
|---|---|---|---|---|---|---|---|
| RS28 | 4.0 | 5.1 | 6.8 | 7.6 | 4.6 | 7.3 | 10.1 |
| RS29 | 2.7 | 3.3 | 4.3 | 4.7 | 3.0 | 4.6 | 6.2 |
| RS30 | 8.3 | 11.1 | 15.3 | 17.3 | 9.8 | 16.7 | 23.6 |
| RS31 | 6.5 | 8.6 | 11.8 | 13.4 | 7.6 | 12.9 | 18.2 |
| RS32 | 4.8 | 6.4 | 8.8 | 9.9 | 5.6 | 9.5 | 13.4 |
| RS33 | 5.2 | 7.0 | 9.6 | 10.9 | 6.2 | 10.5 | 14.8 |
| RS34 | 5.9 | 7.9 | 10.9 | 12.3 | 7.0 | 11.8 | 16.8 |
| RS35 | 4.6 | 6.0 | 8.2 | 9.3 | 5.3 | 8.9 | 12.6 |
| RS36 | 6.7 | 9.2 | 13.1 | 14.8 | 8.0 | 14.2 | 20.5 |
| RS37 | 6.4 | 8.7 | 12.3 | 13.9 | 7.6 | 13.3 | 19.1 |

Ensemble medians, 80 members. Historical values are the fitted model evaluated
at observed forcing over the 70-year record.

Figure 2 plots the same rates period by period and adds two kinds of spread the
table does not report. The shaded band is the disagreement among climate runs:
it spans the central 80 percent of the eighty members. The vertical bars are a
separate quantity:
how far an actual measured rate would be expected to fall either side of the
projection, at the same 80 percent level. They reflect the scatter remaining in
the fitted historical
flow-to-migration relationship. The points are not a fitted trend through time:
each one is the median of the ensemble's distribution in that period, and the
lines only connect them in sequence. A regression does sit behind the figure,
but it is the forward model that produces each point, not the line joining
them. The same results plotted as change from
historical, and as a reach-by-period heat map, are in Appendix B (Figures B1
and B2).

![Projected migration rate trajectory, calendar-era axis](../plots/migration_rate_trajectory_bc-k-by-era.png)

**Figure 2.** Projected migration rate trajectory by reach, statistical
ensemble, calendar-era axis. Points are ensemble medians, the bars the model's
80 percent prediction interval, and the band the 10–90 percent spread across
members. The Observed anchor is the fitted model evaluated at historical
forcing, annualized over 30 years.

### 3.3 Warming-level framing

**Migration rate rises with warming level.** Grouping the same runs by
amount of warming rather than by date, median rates at RS30 are
11.3 ft/yr at 1.5 °C, 16.3 at 2 °C, 18.2 at 3 °C, and 22.8 at 4 °C, the step
between 2 and 3 °C being the smallest. The
reach-to-reach pattern of Section 3.2 persists at every level: RS30 is fastest
and RS29 slowest, and the ratios between reaches hold (Table 2, Figure 3).
Figure 3 reads as Figure 2 does: each point is the median of the ensemble's
distribution at that level, connected in sequence rather than fitted through.
The
change-from-historical and heat-map versions of this figure are in Appendix B
(Figures B3 and B4).

**Table 2.** Projected median migration rates by reach and global warming level
(ft/yr).

| Reach | 4.5 / 1.5 °C | 4.5 / 2 °C | 4.5 / 3 °C | 8.5 / 1.5 °C | 8.5 / 2 °C | 8.5 / 3 °C | 8.5 / 4 °C |
|---|---|---|---|---|---|---|---|
| RS28 | 5.8 | 6.5 | 6.6 | 5.2 | 7.1 | 7.9 | 9.7 |
| RS29 | 3.6 | 4.0 | 4.1 | 3.2 | 4.4 | 4.8 | 5.9 |
| RS30 | 13.0 | 14.8 | 15.0 | 11.3 | 16.3 | 18.2 | 22.8 |
| RS31 | 10.0 | 11.3 | 11.5 | 8.7 | 12.5 | 14.0 | 17.5 |
| RS32 | 7.2 | 8.2 | 8.3 | 6.3 | 9.1 | 10.2 | 12.7 |
| RS33 | 8.0 | 9.1 | 9.2 | 6.9 | 10.0 | 11.2 | 14.1 |
| RS34 | 9.1 | 10.3 | 10.4 | 7.8 | 11.4 | 12.8 | 16.0 |
| RS35 | 6.8 | 7.8 | 7.8 | 5.9 | 8.5 | 9.6 | 11.9 |
| RS36 | 10.5 | 12.1 | 12.3 | 9.0 | 13.5 | 15.2 | 19.3 |
| RS37 | 10.0 | 11.4 | 11.6 | 8.6 | 12.7 | 14.3 | 18.1 |

Member counts vary by level: 80 at 1.5 °C, 64 at 2 °C and 16 at 3 °C under
RCP4.5; 80 at 1.5–3 °C and 56 at 4 °C under RCP8.5. The RCP4.5 3 °C column
rests on 16 members and should be read with that in mind.

![Projected migration rate trajectory, warming-level axis](../plots/migration_rate_trajectory_gwl-bc-k-by-era.png)

**Figure 3.** Projected migration rate by reach and warming level, statistical
ensemble.

### 3.4 What the two framings convey

**The two framings answer different questions.** Grouping runs by calendar
period answers what to expect around a date, which is what planning horizons
require. Grouping the same runs by amount of warming answers how the channel
responds to a given amount of warming, which is the physical result. The two
agree where they overlap: under RCP8.5 at RS30 the mid-century median of
16.7 ft/yr sits close to the 2 °C value of 16.3, and the late-century median of
23.6 ft/yr close to the 4 °C value of 22.8.

**Around 2 °C the two emissions pathways differ mainly in when they arrive.**
On the
calendar axis they are 36 percent apart at RS30 by late century. At 2 °C of
warming they are about 10 percent apart, and that holds across all
ten reaches. The agreement is specific to that level: at 1.5 °C the ordering
reverses, with RCP4.5 running 11 to 15 percent higher, and at 3 °C the gap
widens to 19 to 24 percent on an RCP4.5 column of only sixteen members. The
pathways reach 2 °C at different dates, and the migration
rate at 2 °C is much the same either way.

**Fixing the amount of warming does not narrow the range across runs.** Runs
reach a given amount of warming in different decades, so if much of the range
reported in Section 3.2 came from disagreement about dates, grouping by warming
level would shrink it. It does not. Under RCP8.5 at late century the range
across runs spans a factor of about 2.5 on either grouping, and at mid-century
about 2.2, at every reach. What the runs disagree about is how much flow a
given amount of warming brings to this river, and no regrouping removes that.

### 3.5 Dynamically downscaled projections

**Through mid-century the dynamical track shows a widening range rather than a
rising middle.** This second, smaller ensemble runs twelve members under RCP8.5
to 2050, summarized over 2011–2030 and 2031–2050. Median rates for the first
window range from 3.2 ft/yr at RS29 to 11.3 ft/yr at RS30, within the range the
statistical ensemble gives for the same years. Medians then hold nearly
constant into the second window, moving less than two percent at every reach,
while both tails climb and the band widens: at RS30 the 10th-to-90th percentile
band runs 7.9–14.7 ft/yr in the first window and 10.7–21.9 ft/yr in the second,
the lower bound up 35 percent and the upper up 49 percent. The statistical
ensemble raises the middle over its own era blocks, 2006–2035 and 2036–2065, so
the two tracks agree that the high end rises
and differ on whether the typical year does. These projections exist on the
calendar-period axis only, and their figures are in Appendix B (Figures B5 and
B6).

---

## 4. Discussion

**Geomorphic work and the River Vision.** The River Vision's geomorphology
touchstone (Jones et al. 2008) describes a functional Umatilla River as one
whose channel network
is maintained and reshaped by its own hydrology, with peak flows periodically
reworking channel pattern. That reworking sustains habitat diversity and
hyporheic
exchange, the bidirectional movement of river water through floodplain gravels,
which
riverine First Foods depend on, and whose extent follows valley-bottom width,
gradient and substrate (Dwire and Mellmann-Brown 2017). Channel migration is
such reworking,
measured. The River Vision lists three critical data needs this analysis
addresses:
the discharge that constitutes a channel-forming event, how often such events
occur, and what flow conditions to expect under climate change. For the reaches
upstream of Pendleton, the answer to all three points the same way. Flows above
bankfull, 4,156 cfs at Pendleton, drive measurable channel migration;
those flows become more frequent and deliver more volume through the century;
and median migration rates roughly triple by late century under the
high-emissions pathway. At late century every projection in the ensemble
produces an increase,
at every reach.

**Valley confinement governs which species the change most affects.** Spring
Chinook
spawn in unconfined alluvial valleys that buffer redds from scour, and in
coarser substrate; bull trout build shallower redds in finer gravel and are more
exposed (Isaak et al. 2017). This analysis does not resolve how migration rate
varies with valley confinement across these ten reaches, so the consequence for
either species is not established here.

**The flood season moves earlier.** A separate line of evidence speaks to
timing, which this analysis cannot address. CTUIR's Department of Natural
Resources ran its SWAT model of the upper basin under the same two emissions
scenarios, producing monthly flows at three nodes, one of which is the Umatilla
at the West Reservation Boundary, the gage that forces every reach in this
study. Those runs put the wettest month of the year in April under hindcast
conditions and in February by late century under the high-emissions pathway.
Winter's share of annual volume rises from 32 to 46 percent and spring's falls
from 42 to 26 at that node. Every scenario, era and node moves in the same
direction, and the separation holds
for all four of their climate models, with no overlap between hindcast and
late-century values at any node. Snowmelt-driven spring peaks and
rain-driven winter peaks are not interchangeable inputs to a migrating channel.
They differ in rate of rise, duration, antecedent soil moisture, and in the
state
of riparian vegetation at the time of inundation. This is non-stationarity in a
second dimension: the envelope of flood magnitude is moving, and the season
delivering those floods is moving with it. A rate projection alone does not
show that.

**A shifting continuum, not a single trend.** More geomorphic work does not
mean more of the same work. As precipitation shifts from snow toward rain,
runoff responds faster and arrives in sharper pulses, which alters the balance
between the moderate floods that maintain channel and floodplain structure and
the large floods that restructure it. Projections for Blue Mountains streams
put winter high-flow days, those in the top 5 percent of flows, at roughly
double by 2080, a mean of 4.6 days rising to 8.6 (Isaak et al. 2017). This
analysis cannot resolve that
balance. Its forcing metric sums all flow above bankfull and does not
distinguish the two classes of event, though the daily records needed to
separate them already exist, and the question merits a focused analysis. Upland
processes shift on the same ground and the same schedule. Fire degrades soil
stability and hydrologic function, two of the Upland Vision touchstones
(Endress et al. 2019), so less precipitation infiltrates and more runs off
overland, entraining sediment as it goes. Increased fire frequency and area
burned are near certainties for the Blue Mountains, with more sediment removed
from hillslopes and delivered episodically to channels (Isaak et al. 2017).
Wood and sediment delivered to the
channel network aggrade the bed, reduce conveyance, and punctuate migration at
locations the historical record does not identify. We fit the migration
relationship to a historical record and project it forward on the assumption
that it holds, but a given discharge will not necessarily perform the same
geomorphic work on a burned, sediment-loaded basin that it performed on the
record we fit.

**The conditions this analysis projects are now arriving.** Three recent events
put that picture in the present tense. The February 2020 flood restructured
channel and floodplain across the study corridor. The 2026 fire season ranked
among the largest on record in Oregon by total area burned, and the largest
fire in this basin, the Hagen Fire, started from lightning on July 16 and
burned 61,380 acres in the Umatilla National Forest, running along the North
Fork of the Umatilla River and east of Gibbon (InciWeb 2026). That ground lies
in the contributing area above the gages that force every reach in this study.
As of October 2026 an El Niño of record intensity is strengthening toward a
winter peak, and the storm track it organizes will be unusually loaded with
moisture (Swain 2026). Whether landfalling atmospheric rivers reach this far
north and inland is uncertain, and the potential is real enough to plan
against. Intense rain falling on recently burned ground produces overland flow,
debris flows and shallow landsliding, and that material enters the channel
network as sediment and wood. That chain is the link between the Upland
Vision's soil stability and hydrologic function touchstones and the River
Vision's geomorphology touchstone, and it is the conceptual model this
memorandum offers. Hydrologic non-stationarity moves fire, hillslope delivery
and channel adjustment together; the relationships among them are themselves
non-stationary; and the First Foods that depend on floodplain process sit
downstream of all three. The analysis reported here quantifies one leg of that
model, the leg existing data measure most directly.

---

## 5. Limitations

**The model represents discharge and nothing else.** It includes no sediment
supply, no wood supply, and no riparian vegetation term. Each of these governs
how a channel responds to a given flood, and each is omitted because the
historical record supporting this analysis does not resolve them. The fitted
relationship absorbs their historical average effect into the reach
coefficients, which is defensible only while those effects stay near their
historical average.

**The fitted relationship rests on a pre-fire record.** Post-fire response is
not necessarily the same relationship scaled up. Where fire alters hillslope
delivery, the same discharge may perform more geomorphic work than the fitted
relationship predicts, and the departure would be episodic rather than steady.

**The forcing metric does not separate event classes.** Flow above bankfull is
summed without regard to whether it arrives as a maintenance-scale or a
restructuring flood, so Section 4 describes the changing balance between them
in direction only.

**Projected forcing extends beyond the fitted range.** The relationship was
fitted on photo intervals of one to fourteen years and is applied to
thirty-year blocks, so every projected period carries more cumulative excess
discharge than any interval in the fit. On an annual basis the comparison is
closer: the
late-century high-emissions median, about 12,700 cfs-days per year, falls
inside the observed range of zero to 19,500, the upper bound being the interval
containing the February 2020 flood. The upper tenth of that ensemble exceeds
it. Rates at the high end are extrapolations of a linear
relationship rather than interpolations within observed conditions.

**Between-reach ratios are less stable than the ranking.** Per-reach slopes
shift by up to 33 percent under an alternative centering of the forcing
variable, while rank order is essentially unaffected (Spearman 0.99). Read the
ordering of reaches as the firm result and the ratios between them as
approximate.

**Comparison with DOGAMI's published erosion rates agrees in magnitude but not
in reach ranking.** Across-reach means are close, 7.6 ft/yr measured from the
photo record here against 8.5
ft/yr published, while per-reach ranking does not correspond (Spearman 0.18).
The two methods differ: DOGAMI measures bank retreat at fixed transects,
while this analysis measures the corridor area created between mapped
channel polygons and converts it to a rate. Two different approaches to
measuring the same process give similar magnitudes. The measured rate sits
above the historical column of Table 1, which reports the fitted model rather
than the measurement.

**Results are multi-decadal summaries.** The corrected flows reproduce the
distribution of above-bankfull flow but not the dates of individual floods, so
no result here applies to a named year.

---

## 6. Supporting analysis and future work

**The open questions point toward applied tools, not larger models.** The
results establish that migration rates rise, that the reach ordering holds, and
that the size of the increase stays uncertain whichever way the runs are
grouped. What they do not supply is a way to act on that within a season or a
project life. Methods for forecasting, screening and early warning, built on
the same flow-to-migration relationship and keyed to conditions already on the
ground such as burned area and snowpack, would help protect the investments the
Tribes have made in river restoration, fish habitat and community
infrastructure. Developing them is the direction this work recommends, and
their form is an open question rather than a settled design.

**CTUIR's Future Flows modeling supports this analysis at two points.** Their
SWAT model of the upper basin is an independent hydrologic model of this river,
and two climate models are common to both products, so the agreement between
them tests the projection chain rather than restating it (Section 2). Their
three nodes allow the spatial uniformity of the change signal to be tested,
which the single-node UW ensemble cannot do (Section 2). Placing that
dataset inside the forward model, which would require fitting it to the daily
record, is future work and was not undertaken here.

**Two pathways were tested and closed.** Converting CTUIR's monthly flows into
the daily forcing metric was attempted and did not produce a defensible
transfer: monthly means do not retain the event structure the metric integrates
over. Stream force was examined as an alternative forcing variable, following
the Fluvial Danger Zone approach named in the project scope, and was set aside
because the candidate formulations collapse variables already represented in
the model and introduce covariance with the forcing term.

---

## 7. References

Appleby, C.A., Anthony, L.H., and Noone, J.K., 2025, *Channel Migration Zone
Maps
for the Umatilla River and Lower McKay Creek, Umatilla County, Oregon*: Oregon
Department of Geology and Mineral Industries Open-File Report O-25-10.

Bates, D., Mächler, M., Bolker, B., and Walker, S., 2015, Fitting linear
mixed-effects models using lme4: *Journal of Statistical Software*, v. 67,
no. 1, p. 1–48, https://doi.org/10.18637/jss.v067.i01.

Cannon, A.J., 2024, *MBC: Multivariate Bias Correction of Climate Model
Outputs*,
R package version 0.10-7.

Cannon, A.J., Sobie, S.R., and Murdock, T.Q., 2015, Bias correction of GCM
precipitation by quantile mapping: How well do methods preserve changes in
quantiles and extremes?: *Journal of Climate*, v. 28, no. 17, p. 6938–6959,
https://doi.org/10.1175/JCLI-D-14-00754.1.

Chegwidden, O.S., Nijssen, B., Rupp, D.E., and Mote, P.W., 2017, *Hydrologic
Response of the Columbia River System to Climate Change* [Data set]: Zenodo,
https://doi.org/10.5281/zenodo.854763.

Clifton, C.F., Day, K.T., Dello, K., Grant, G.E., Halofsky, J.E., Isaak, D.J.,
Luce, C.H., Safeeq, M., Staab, B.P., and Stevenson, J., 2017, Climate change and
hydrology in the Blue Mountains, *in* Halofsky, J.E., and Peterson, D.L., eds.,
*Climate Change Vulnerability and Adaptation in the Blue Mountains*: Portland,
Oreg., U.S. Department of Agriculture, Forest Service, Pacific Northwest
Research Station, General Technical Report PNW-GTR-939, chap. 3.

Costa, J.E., and O'Connor, J.E., 1995, Geomorphically effective floods, *in*
Costa, J.E., Miller, A.J., Potter, K.W., and Wilcock, P.R., eds., *Natural and
Anthropogenic Influences in Fluvial Geomorphology*: American Geophysical Union
Geophysical Monograph 89, Washington, D.C.

Donovan, M., Belmont, P., Notebaert, B., and others, 2019, Accounting for
uncertainty in remotely-sensed measurements of river planform change:
*Earth-Science Reviews*, v. 193, p. 220–243.

Dwire, K.A., and Mellmann-Brown, S., 2017, Climate change and special habitats
in the Blue Mountains—Riparian areas, wetlands, and groundwater-dependent
ecosystems, *in* Halofsky, J.E., and Peterson, D.L., eds., *Climate Change
Vulnerability and Adaptation in the Blue Mountains*: Portland, Oreg., U.S.
Department of Agriculture, Forest Service, Pacific Northwest Research Station,
General Technical Report PNW-GTR-939, chap. 7.

Endress, B.A., Quaempts, E.J., and Steinmetz, S., 2019, *First Foods Upland
Vision*: Confederated Tribes of the Umatilla Indian Reservation, Department of
Natural Resources, April 2019.

England, J.F., Jr., Cohn, T.A., Faber, B.A., Stedinger, J.R., Thomas, W.O., Jr.,
Veilleux, A.G., Kiang, J.E., and Mason, R.R., Jr., 2018, *Guidelines for
determining flood flow frequency — Bulletin 17C*: U.S. Geological Survey
Techniques and Methods, book 4, chap. B5, 148 p.,
https://doi.org/10.3133/tm4B5.

Hauser, M., Engelbrecht, F., and Fischer, E.M., 2022, *Transient global warming
levels for CMIP5 and CMIP6* [Software]: Zenodo,
https://doi.org/10.5281/zenodo.3591806, repository main branch as updated
November 7, 2025, accessed September 28, 2026.

Hirsch, R.M., 1982, A comparison of four streamflow record extension techniques:
*Water Resources Research*, v. 18, no. 4, p. 1081–1088.

InciWeb, 2026, Hagen Fire incident information: U.S. Forest Service, Umatilla
National Forest, final incident update September 27, 2026,
https://inciweb.wildfire.gov/incident-information/orumf-hagen-fire.

Isaak, D.J., Ramsey, K., Chatel, J.C., Konnoff, D.L., Gecy, R.A., and Horan, D.,
2017, Climate change, fish, and aquatic habitat in the Blue Mountains, *in*
Halofsky, J.E., and Peterson, D.L., eds., *Climate Change Vulnerability and
Adaptation in the Blue Mountains*: Portland, Oreg., U.S. Department of
Agriculture, Forest Service, Pacific Northwest Research Station, General
Technical Report PNW-GTR-939, chap. 5.

Jones, K.L., Poole, G.C., Quaempts, E.J., O'Daniel, S., and Beechie, T., 2008,
*The Umatilla River Vision*: Confederated Tribes of the Umatilla Indian
Reservation, Department of Natural Resources, October 1, 2008, revised May 2011.

Legg, N.T., Heimburg, C., Collins, B.D., and Olson, P.L., 2014, *The Channel
Migration Toolbox*: Washington State Department of Ecology Publication
14-06-032.

Magilligan, F.J., Buraas, E.M., and Renshaw, C.E., 2015, The efficacy of stream
power and flow duration on geomorphic responses to catastrophic flooding:
*Geomorphology*, v. 228, p. 175–188.

Milly, P.C.D., Betancourt, J., Falkenmark, M., Hirsch, R.M., Kundzewicz, Z.W.,
Lettenmaier, D.P., and Stouffer, R.J., 2008, Stationarity is dead: Whither water
management?: *Science*, v. 319, no. 5863, p. 573–574.

O'Daniel, S., and Rogers-Pachico, B., n.d., *Future Flows* [presentation]:
Confederated Tribes of the Umatilla Indian Reservation, Department of Natural
Resources, GIS Program.

Olson, P.L., Legg, N.T., Abbe, T.B., Reinhart, M.A., and Radloff, J.K., 2014,
*A Methodology for Delineating Planning-Level Channel Migration Zones*:
Washington State Department of Ecology.

Pierce, D.W., Cayan, D.R., Maurer, E.P., Abatzoglou, J.T., and Hegewisch, K.C.,
2015, Improved bias correction techniques for hydrological simulations of
climate change: *Journal of Hydrometeorology*, v. 16, no. 6, p. 2421–2442,
https://doi.org/10.1175/JHM-D-14-0236.1.

R Core Team, 2025, *R: A language and environment for statistical computing*:
Vienna, Austria, R Foundation for Statistical Computing,
https://www.R-project.org/.

Rapp, C.F., and Abbe, T.B., 2003, *A Framework for Delineating Channel Migration
Zones*: Washington State Department of Ecology.

Swain, D.L., 2026, El Niño, already near or at record intensity, will further
strengthen to historic level and likely bring major California and Southwest
U.S. winter impacts: Weather West, October 12, 2026,
https://weatherwest.com/archives/44119.

Vogel, R.M., and Stedinger, J.R., 1985, Minimum variance streamflow record
augmentation procedures: *Water Resources Research*, v. 21, no. 5, p. 715–723.

## 8. Appendix A — Methods detail

**A.1 Gage record and index gages.** The analysis gage is Umatilla River at
West Reservation Boundary near Pendleton (USGS 14020850), drainage area
441 mi², with daily discharge and annual peaks from 1996. It lies upstream of
the McKay Creek confluence and is unregulated. Two index gages extend it:
Umatilla River above Meacham Creek near Gibbon (USGS 14020000), unregulated and
used as recorded, and Umatilla River near Umatilla (USGS 14033500), which lies
below McKay Dam. Peaks at the downstream gage are attenuated by storage, so its
record was first corrected to natural conditions by mass-balance inversion of
reservoir storage change and release, cross-validated against the period with
above-reservoir inflow gaging.

**A.2 Flood frequency and the bankfull threshold.** Flood quantiles at
Pendleton are fitted to the thirty-year at-site peak
record (1996-2025) by expected moments analysis under Bulletin 17C (England et
al. 2018), run in PeakFQ. The two-year flood is
5,542 cfs; the bankfull threshold is 0.75 Q₂, or 4,156 cfs. A longer record was
built as a check: peaks were extended against
both index gages by the Maintenance of Variance Extension type 3 procedure
(MOVE.3; Vogel and Stedinger 1985) under Bulletin
17C appendix 8, and the two frequency curves combined by inverse-variance
weighting under appendix 9, giving 55 years of
record and a two-year flood of 5,468 cfs. Extension lowers the estimate by 1.3
percent at Q₂ and by 9.7 percent at Q₁₀₀. The
2020 flood carries the leverage of a thirty-year sample in the tail, where
observations constrain the curve sparsely, and
much less at Q₂, where they do not. The analysis uses the at-site estimate, so
the threshold rests on measured peaks.

**A.3 Daily record extension.** The daily record at Pendleton begins in 1996 and
does not span the photo record, so it was extended back to 1952 by the
Maintenance of Variance Extension type 1 procedure (MOVE.1; Hirsch 1982) against
the Gibbon gage. The extension estimates only flows above a reconstruction
floor; it targets the flood tail and does not reconstruct a general hydrograph.

**A.4 Flood forcing metric.** For each photo interval, cumulative excess
discharge is the summed volume by which daily discharge exceeded bankfull, in
cfs-days. The metric integrates flood magnitude over flood duration, following
the geomorphic-effectiveness literature (Costa and O'Connor 1995; Magilligan et
al. 2015).

**A.5 Migration record.** Channel positions come from the historical migration
area polygons of the DOGAMI channel migration zone mapping (Appleby et al. 2025;
Rapp and Abbe 2003). Area reworked per reach per interval is normalized by reach
stationing length (Legg et al. 2014). Fifteen photo dates between 1952 and 2022
give fourteen intervals; RS37 lacks the 1964 coverage, so its earliest interval
spans 1952–1974. Reaches 25 through 27 are leveed through Pendleton and are
excluded. The fitted model has a per-reach, per-interval intercept that is
annualized by the interval length, so a short interval annualizes high and a
long one low. This reflects channel reoccupation, the river reworking ground it
has already touched. Long intervals also understate rates measured over short
ones, because reversals cancel within the interval (Donovan et al. 2019). Rates
reported on the calendar-era axis are annualized over 30 years, and on the
warming-level axis over 20.

**A.6 Projected flows and bias correction.** Future daily flows are the Columbia
River basin hydrologic projections of Chegwidden et al. (2017), routed to
Pendleton: 80 statistically downscaled members per emissions scenario under
RCP4.5 and RCP8.5 through 2099, and twelve dynamically downscaled members under
RCP8.5 through 2050, reported as a separate track. Correction is by quantile
delta mapping (Cannon et al. 2015), fitted on the bankfull-and-above band
against the extended observed record and applied within each reporting era. The
transfer was exercised in the historical period first, where quantile delta
mapping reduces to plain quantile mapping, to test that the corrected series
reproduce observed above-bankfull frequency and magnitude.

**A.7 Reporting axes.** Calendar eras follow the 30-year blocking convention of
Pierce et al. (2015). Warming-level windows are the IPCC AR6 Working Group I
Chapter 11 tables as republished by Hauser et al. (2022):
for each climate model and scenario, the 20-year window centered on the first
year a 20-year running mean of global mean temperature exceeds the level
relative to 1861–1900. Windows are used as published, with no interpolation
between levels and no extension past the last one.

**Software.** The analysis was carried out in the R statistical computing
environment (version 4.6.1; R Core Team 2025), using published implementations
of established
methods rather than reimplementing them: PeakFQ for the Bulletin 17C
flood-frequency analysis (England et al. 2018), `smwrStats` for MOVE.1 record
extension (Hirsch 1982), `MBC` for quantile delta mapping (Cannon et al. 2015;
Cannon 2024), and `lme4` for the mixed-effects fit (Bates et al. 2015).

## 9. Appendix B — Additional figures

These figures present the same results as Section 3 in two further framings:
change in migration rate relative to historical, anchored at zero, and
reach-by-period heat maps. The dynamical track's figures follow.

![Change in migration rate vs historical, calendar-era axis](../plots/migration_trajectory_bc-k-by-era.png)

**Figure B1.** Change in migration rate vs historical (ft/yr) by reach,
statistical ensemble, calendar-era axis.

![Projected median migration rate by reach and period, calendar-era axis](../plots/migration_heatmap_rate_bc-k-by-era.png)

**Figure B2.** Projected median migration rate by reach and period, statistical
ensemble, calendar-era axis.

![Change in migration rate vs historical, warming-level axis](../plots/migration_trajectory_gwl-bc-k-by-era.png)

**Figure B3.** Change in migration rate vs historical (ft/yr) by reach and
warming level, statistical ensemble.

![Projected median migration rate by reach and warming level](../plots/migration_heatmap_rate_gwl-bc-k-by-era.png)

**Figure B4.** Projected median migration rate by reach and warming level,
statistical ensemble.

![Dynamical ensemble migration rate trajectory](../plots/migration_rate_trajectory_bc-k-by-era-dynamical.png)

**Figure B5.** Migration rate trajectory by reach, dynamical ensemble, RCP8.5,
12 members. This track's periods are 20 years, so its Observed anchor is
annualized over 20 rather than 30 and sits higher than the one in Figure 2;
absolute rates on the two tracks are not comparable by eye. The
change-from-historical view in Figure B6 is unaffected.

![Change in migration rate vs historical, dynamical ensemble](../plots/migration_trajectory_bc-k-by-era-dynamical.png)

**Figure B6.** Change in migration rate vs historical (ft/yr) by reach,
dynamical ensemble, RCP8.5, 12 members.
