# Projected Channel Migration, Umatilla River RS28–RS37

**Technical Memorandum — DRAFT**
Project D202400347.00 | Draft of 2026-10-13

> Draft status: Introduction, Methods and Discussion drafted this revision.
> Results carried forward from the 2026-10-06 draft. Summary not written
> (it is written last). Figure appendix not yet built: the change-in-rate
> plots and heat maps remain inline in Results pending that pass.
> Figure axis labels and font sizes pending revision (latex2exp pass).

---

## 1. Introduction

The February 2020 flood showed how quickly the Umatilla River restructures its
channel and floodplain, and how exposed the features that sustain First Foods
are to extreme hydrology that departs from the historical record.
Such departure is a signature of hydrologic non-stationarity. Stationarity is the
assumption that a river fluctuates within an unchanging envelope of variability, so
flood magnitude and frequency follow a fixed underlying distribution that a long
enough gage record will eventually pin down (Milly et al. 2008). Under
non-stationarity that envelope is itself moving. The climate conditions generating
the flows are changing, so a longer record describes the past more precisely without
describing the future any better. Projections for the upper basin indicate greater
flow variability, a shift from snow toward rain, higher winter flows, and
atmospheric river events increasing in frequency and intensity through late
century. However, the concern is not larger floods alone. Rather, extreme floods combined with
increased variability yield a widening separation between the large floods that 
restructure the fluvial system, which recur on a decadal scale, and 
the moderate floods that maintain it. Both flood styles perform the geomorphic work behind 
the floodplain processes that support First Foods, as the CTUIR River Vision describes.
This analysis treats that full range of channel-forming flow as one quantity and asks a
narrower question of it: how much faster does the channel migrate under the projected
future climate?

Evaluating what this means for channel migration takes three pieces, and two of them
already exist for this basin.
The Oregon Department of Geology and Mineral Industries (DOGAMI) has mapped
channel migration zones (CMZs) for the Umatilla River and lower McKay Creek
under the Washington State CMZ protocol (Appleby et al. 2025; Olson et al. 2014),
delineating the area the channel can
be expected to occupy. A CMZ bounds where migration can occur; it reports no
rate, and it is drawn from the historical record rather than a projected one.

Downscaled streamflow projections for the upper basin extend through 2099 under
two emissions scenarios, describing the changed flow regime (Chegwidden et al.
2017). They stop short of
geomorphic consequence: they describe how the hydrology changes, not what the
channel does in response. What neither supplies is the third piece: a relationship that
converts a flow regime into a migration rate.

This memorandum builds that third piece. We fit the historical relationship between flood
hydrology and measured channel migration across ten reaches, then drive that
relationship with the projected flows to estimate migration rates through 2099.
The result is a reach-scale index of relative migration risk, suitable for
ranking reaches against one another and for comparing time periods and warming
levels. It is not a forecast of where the channel will be in a given year. Other
drivers of channel change are shifting at the same time; Section 4 returns to them.

Reaches are identified by DOGAMI's river station (RS) numbering, so results can
be read directly against the published CMZ mapping. The analysis covers RS28
through RS37, the reaches upstream of Pendleton, which is the scope of this
project.

---

## 2. Methods

The analysis links three datasets that were not developed to work together: mapped
historical channel positions, the Pendleton streamflow record, and downscaled
future flow projections. The chain progresses in three steps. We quantify historical
migration from the mapping, fit a model relating it to flood hydrology over the
same intervals, then apply that model to projected flows. Each analytical step required
preparatory work on its inputs, described below.

**Quantifying historical migration.** DOGAMI digitized Umatilla River planform
position from aerial photography at fourteen dates between 1952 and 2022, as
the historical migration area (HMA) component of its CMZ mapping (Appleby et al.
2025), which follows the channel migration zone framework of Rapp and Abbe
(2003). For each
reach and each photo interval, we measured the area newly occupied by the
active channel and normalized it by reach centerline length, yielding new
channel area per foot of reach, the approach implemented in the Washington
Channel Migration Toolbox (Legg et al. 2014). Annualized, this is the migration rate reported
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
stabilizes the per-reach slopes given fourteen intervals apiece. The reach
slope is that reach's flood sensitivity, in feet of new channel area per foot
of reach per 1,000 cfs-days. A crossed random effect on photo interval accounts
for the shared hydrology: all ten reaches experience the same flood in a given
interval, so their residuals are not independent. Interval length enters as a
fixed effect, separating background reworking that accrues with elapsed time
from flood-driven reworking. Fitted slopes span roughly a sixfold range across
the ten reaches (Figure 1).

![Fitted forcing–migration relationship by reach](../plots/forcing_model_reach_fit.png)

**Figure 1.** Fitted relationship between flood forcing and channel migration, by reach.

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
are not interchangeable with the statistical members.

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
or 4 °C above pre-industrial. Crossing years are taken from published values.
Models disagree
about when a given warming level arrives, so a fixed calendar window pools
different climate states together; a warming level removes that timing
disagreement and isolates the hydrologic and geomorphic response. One caveat
follows from the mismatch: the warming-level windows are model-specific and cut
across the eras within which the bias-correction multipliers are defined.

**Applying the model.** Reach coefficients are frozen at their fitted values
and applied to each period's mean annual cumulative excess discharge, producing
a migration rate for every reach, period and ensemble member. Rates are
reported on a 30-year basis, for the reason given in Appendix A.

---

## 3. Results

**Historically, migration rates vary fourfold between reaches.** Over the
70-year record, reach-average rates range from 2.7 ft/yr at RS29 to 8.3 ft/yr
at RS30, with most reaches between 4.5 and 6.7 ft/yr. This spread reflects
reach setting, not flow: all ten reaches see the same hydrology (Table 1).

**Projected rates rise by a factor of roughly three by late century, and the
increase is nearly uniform across reaches.** Under RCP8.5, late-century
(2066–2099) median rates reach 2.3 to 3.1 times their historical values, with
eight of the ten reaches falling between 2.8 and 3.1. Reach ranking is
essentially unchanged: RS30 remains the fastest-migrating reach and RS29 the
slowest, with only RS31 and RS37 trading places. The projected hydrology
scales the existing pattern of migration rather than rearranging it (Figures 2–4).

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

**Table 1.** Historical and projected median migration rates by reach, calendar-era axis (ft/yr).

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
eight of the ten runs fall inside it. The vertical bars are a separate quantity:
how far an actual measured rate would be expected to fall either side of the
projection. They reflect the scatter remaining in the fitted historical
flow-to-migration relationship.

![Projected migration rate trajectory, calendar-era axis](../plots/migration_rate_trajectory_bc-k-by-era.png)

**Figure 2.** Projected migration rate trajectory by reach, statistical ensemble, calendar-era axis.

![Change in migration rate vs historical, calendar-era axis](../plots/migration_trajectory_bc-k-by-era.png)

**Figure 3.** Change in migration rate vs historical (ft/yr) by reach, statistical ensemble, calendar-era axis.

![Projected median migration rate by reach and period, calendar-era axis](../plots/migration_heatmap_rate_bc-k-by-era.png)

**Figure 4.** Projected median migration rate by reach and period, calendar-era axis.

### 3.1 Dynamically downscaled projections

A second, smaller ensemble carries the projections through 2050: 12 members
under RCP8.5, downscaled dynamically rather than statistically, summarized over
2011–2030 and 2031–2050. Median rates for the first window range from 3.2 ft/yr
at RS29 to 11.3 ft/yr at RS30. Medians hold nearly constant into the second
window, moving less than two percent at every reach, while the upper tail of
the ensemble climbs: at RS30 the 10th-to-90th percentile band widens from
7.9–14.7 ft/yr to 10.7–21.9 ft/yr. Through mid-century this smaller set of runs
holds the typical rate near where it begins while its highest runs climb. The
increase appears as a widening range rather than a rising middle (Figures 5 and
6). These projections exist on the calendar-period axis only.

![Dynamical ensemble migration rate trajectory](../plots/migration_rate_trajectory_bc-k-by-era-dynamical.png)

**Figure 5.** Migration rate trajectory by reach, dynamical ensemble, RCP8.5, 12 members.

![Change in migration rate vs historical, dynamical ensemble](../plots/migration_trajectory_bc-k-by-era-dynamical.png)

**Figure 6.** Change in migration rate vs historical (ft/yr) by reach, dynamical ensemble, RCP8.5, 12 members.

### 3.2 The same projections on a warming-level axis

**The two framings answer different questions.** Results so far pool ensemble
members by calendar period. Members reach different amounts of warming by any
given date, so a period average mixes two kinds of disagreement: how the river
responds to warming, and when that warming arrives. Pooling the same members by
global warming level instead removes the second. At a given warming level the
members describe the same climate state, and the remaining spread is response.
The era framing answers what to expect around a date, which is what planning
horizons require; the warming-level framing answers how this river responds to
a given amount of warming, which is the physical result. Neither replaces the
other.

The reframing shows that much of the late-century scenario gap above is timing.
At 2 °C, RS30 reads 14.8 ft/yr under RCP4.5 and 16.3 under RCP8.5, about 10
percent apart, and that agreement holds across all ten reaches. The two
scenarios reach 2 °C at different dates, not different rivers.

**Migration rate rises steadily with warming level.** At RS30, median rates are
11.3 ft/yr at 1.5 °C, 16.3 at 2 °C, 18.2 at 3 °C, and 22.8 at 4 °C (Table 2,
Figures 7–9).

**Table 2.** Projected median migration rates by reach and global warming level (ft/yr).

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

**Figure 7.** Projected migration rate by reach and warming level, statistical ensemble.

![Change in migration rate vs historical, warming-level axis](../plots/migration_trajectory_gwl-bc-k-by-era.png)

**Figure 8.** Change in migration rate vs historical (ft/yr) by reach and warming level, statistical ensemble.

![Projected median migration rate by reach and warming level](../plots/migration_heatmap_rate_gwl-bc-k-by-era.png)

**Figure 9.** Projected median migration rate by reach and warming level.

---

## 4. Discussion

**Geomorphic work and the River Vision.** The River Vision's geomorphology
touchstone (Jones et al. 2008) describes a functional Umatilla River as one whose channel network
is maintained and reshaped by its own hydrology, with peak flows periodically
reworking channel pattern. That reworking sustains habitat diversity and hyporheic
exchange — the two-way movement of river water through floodplain gravels — which
riverine First Foods depend on. Channel migration is that reworking,
measured. The Vision lists three critical data needs this analysis addresses:
the discharge that constitutes a channel-forming event, how often such events
occur, and what flow conditions to expect under climate change. For the reaches
upstream of Pendleton, the answer to all three points the same way. Flows above
bankfull, about 4,160 cfs at Pendleton, drive measurable channel migration;
those flows become more frequent and deliver more volume through the century;
and median migration rates roughly triple by late century under the
high-emissions pathway. Every projection in the ensemble produces an increase,
at every reach.

**A shifting continuum, not a single trend.** More geomorphic work does not
mean more of the same work. As precipitation shifts from snow toward rain,
runoff responds faster and arrives in sharper pulses, which alters the balance
between the moderate floods that maintain channel and floodplain structure and
the large floods that restructure it. This analysis cannot resolve that
balance. Its forcing metric sums all flow above bankfull and does not
distinguish the two classes of event, though the daily records needed to
separate them already exist, and the question merits a focused analysis. Upland
processes shift on the same ground and the same schedule. Fire degrades soil
stability and hydrologic function, two of the Upland Vision touchstones
(Endress et al. 2019), so
less precipitation infiltrates and more runs off overland, entraining sediment
as it goes. Wood and sediment delivered to the channel network aggrade the bed,
reduce conveyance, and punctuate migration at locations the historical record
does not identify. None of these processes acts independently, and none is
stationary. We fit the migration relationship to a historical record and
project it forward on the assumption that it holds, but a given discharge will
not necessarily perform the same geomorphic work on a burned, sediment-loaded
basin that it performed on the record we fit. This memorandum addresses one leg
of that continuum, the leg existing data measure most directly.

---

## 5. Limitations

*To be drafted.* Extrapolation beyond the fitted forcing range; silence on
sediment supply and riparian vegetation; fragility of between-reach ratios
(per-reach slopes shift by up to 33 percent under an alternative centering;
rank order is stable, Spearman 0.99). Comparison against DOGAMI's published
reach erosion rates: magnitudes agree (across-reach mean 7.6 ft/yr ours versus
8.5 ft/yr DOGAMI) but per-reach ranking does not (Spearman 0.18), explained by
the methodological difference between fixed-transect bank retreat over the
whole record and polygon corridor expansion per photo interval. Note this
comparison rests on the 5-year photo-interval basis, not the 30-year basis of
Tables 1 and 2.

Additional limitations from the Section 4 framing, to be integrated:

- The model represents discharge only. It includes no sediment supply, no wood
  supply, and no riparian vegetation term.
- The response function is calibrated on a pre-fire record. Post-fire response
  is not necessarily a scalar shift of it.
- The forcing metric does not separate maintenance-scale from
  disturbance-scale floods, so changes in the balance between them are
  described in direction only, not quantified.
- Upland processes, fire and mass wasting among them, are named as co-occurring
  drivers and are not modeled.

## 6. Supporting analysis and future work

*To be drafted. Three short paragraphs, at most one figure.* CTUIR SWAT
monthly flow corroboration; the monthly-to-forcing pathway named as tested and
closed; stream force named as a closed pathway, set aside because the candidate
formulations collapse variables already represented in the model and introduce
covariance with the forcing term.

## 7. References

Appleby, C.A., Anthony, L.H., and Noone, J.K., 2025, *Channel Migration Zone Maps
for the Umatilla River and Lower McKay Creek, Umatilla County, Oregon*: Oregon
Department of Geology and Mineral Industries Open-File Report O-25-10.

Cannon, A.J., 2024, *MBC: Multivariate Bias Correction of Climate Model Outputs*,
R package version 0.10-7.

Cannon, A.J., Sobie, S.R., and Murdock, T.Q., 2015, Bias correction of GCM
precipitation by quantile mapping: How well do methods preserve changes in
quantiles and extremes?: *Journal of Climate*, v. 28, no. 17, p. 6938–6959,
https://doi.org/10.1175/JCLI-D-14-00754.1.

Chegwidden, O.S., Nijssen, B., Rupp, D.E., and Mote, P.W., 2017, *Hydrologic
Response of the Columbia River System to Climate Change* [Data set]: Zenodo,
https://doi.org/10.5281/zenodo.854763.

Costa, J.E., and O'Connor, J.E., 1995, Geomorphically effective floods, *in*
Costa, J.E., Miller, A.J., Potter, K.W., and Wilcock, P.R., eds., *Natural and
Anthropogenic Influences in Fluvial Geomorphology*: American Geophysical Union
Geophysical Monograph 89, Washington, D.C.

Donovan, M., Belmont, P., Notebaert, B., and others, 2019, Accounting for
uncertainty in remotely-sensed measurements of river planform change:
*Earth-Science Reviews*, v. 193, p. 220–243.

Endress, B.A., Quaempts, E.J., and Steinmetz, S., 2019, *First Foods Upland
Vision*: Confederated Tribes of the Umatilla Indian Reservation, Department of
Natural Resources, April 2019.

England, J.F., Jr., Cohn, T.A., Faber, B.A., Stedinger, J.R., Thomas, W.O., Jr.,
Veilleux, A.G., Kiang, J.E., and Mason, R.R., Jr., 2018, *Guidelines for
determining flood flow frequency — Bulletin 17C*: U.S. Geological Survey
Techniques and Methods, book 4, chap. B5, 148 p.,
https://doi.org/10.3133/tm4B5.

Hirsch, R.M., 1982, A comparison of four streamflow record extension techniques:
*Water Resources Research*, v. 18, no. 4, p. 1081–1088.

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

Olson, P.L., Legg, N.T., Abbe, T.B., Reinhart, M.A., and Radloff, J.K., 2014,
*A Methodology for Delineating Planning-Level Channel Migration Zones*:
Washington State Department of Ecology.

Pierce, D.W., Cayan, D.R., Maurer, E.P., Abatzoglou, J.T., and Hegewisch, K.C.,
2015, Improved bias correction techniques for hydrological simulations of
climate change: *Journal of Hydrometeorology*, v. 16, no. 6, p. 2421–2442,
https://doi.org/10.1175/JHM-D-14-0236.1.

Rapp, C.F., and Abbe, T.B., 2003, *A Framework for Delineating Channel Migration
Zones*: Washington State Department of Ecology.

Vogel, R.M., and Stedinger, J.R., 1985, Minimum variance streamflow record
augmentation procedures: *Water Resources Research*, v. 21, no. 5, p. 715–723.

## 8. Appendix A — Methods detail

*To be drafted.* Includes the interval-length basis: the fitted model carries a
per-reach, per-interval intercept that is annualized by the interval length, so
a short interval annualizes high and a long one low. This reflects channel
reoccupation, the river reworking ground it has already touched. Long intervals
also understate rates measured over short ones, because reversals cancel within
the interval (Donovan et al. 2019). All rates in
Tables 1 and 2 are on a 30-year basis.

Software: the analysis applies published implementations of established methods
rather than reimplementing them — `smwrStats` for MOVE.1 record extension
(Hirsch 1982), PeakFQ for the Bulletin 17C flood-frequency analysis (England et
al. 2018), and `MBC` for quantile delta mapping (Cannon et al. 2015; Cannon
2024).

## 9. Appendix B — Additional figures

*To be built.* The change-in-rate figures (3, 6, 8) and the heat maps (4, 9)
move here, presented as alternative renderings of the same results rather than
as new findings.
