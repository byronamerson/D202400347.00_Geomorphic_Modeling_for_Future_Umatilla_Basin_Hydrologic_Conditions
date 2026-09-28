

# Umatilla Geomorphic Futures — 09/09/26 Meeting Reference

------------------------------------------------------------------------

## The big picture

We joined **two large public datasets** — mapping of decades of channel migration (how the river has actually moved) and century-long climate-driven streamflow projections (how flood energy may change) — with **a statistical model we built** that links flood forcing to channel change. Run the future flows through that model and you get a **reach-by-reach picture of how channel migration may change through 2100.** We didn't generate the big datasets or the core hydrologic methods; our contribution is the connective analysis.

------------------------------------------------------------------------

## 1. Where the "future flows" come from — the climate chain

We didn't model climate ourselves. We used an established chain of models, and attached our migration relationship to the end of it:

**Global climate model → downscaling → hydrology model → routing → daily streamflow at Pendleton → bias correction → our migration model**

- **Global Climate Models (GCMs)** — planet-scale physics simulations run to 2100. Ten different models are used, because their disagreement *is* the uncertainty. Each is run under two emissions futures: **RCP4.5** (emissions taper — teal) and **RCP8.5** (emissions keep climbing — tan).
- **Downscaling** — GCMs see the world in \~60–100-mile blocks; downscaling translates that to local terrain and weather.
- **Hydrology model (VIC, PRMS)** — turns downscaled rain/snow/temperature into streamflow (snowpack, melt, runoff), then routes it to a single point: the Pendleton gage.
- Every combination of {climate model × emissions × downscaling × hydrology model} is one plausible future — that's the **\~160 futures** the projection spans.
- **Bias correction** — the model chain gets the *pattern* right but sits on a slightly wrong ruler, so we statistically re-map each series onto the observed gage record, using a method that preserves the climate *change* signal rather than washing it out.

> *"These are physics-based global climate models, downscaled to the basin and turned into daily river flow, then calibrated back to our own gage. We run about 160 versions of the future so the answer is a range, not a single guess."*

**Source — future flows:** RMJOC-II Columbia River climate-change datasets, produced by the University of Washington Climate Impacts Group with the Bureau of Reclamation, U.S. Army Corps of Engineers, and Bonneville Power Administration. [cig.uw.edu/datasets/columbia-river-climate-change](https://cig.uw.edu/datasets/columbia-river-climate-change/)

------------------------------------------------------------------------

## 2. How we modeled channel migration

**Why "new area" is the yardstick.** We measure the channel in **new area per foot of channel** — fresh floodplain the river carved into over each interval, divided by reach length so reaches are comparable (it reads as the average width of channel reworked, in feet). We chose it over *net* change because net change (new minus abandoned) cancels itself out over long intervals and mixes two processes; new area isolates the one thing floods do — rework corridor — and it's the quantity that matters for habitat turnover.

**Why a mixed model, not ordinary regression.** All ten reaches in a given interval saw the *same* flood, so the measurements aren't independent — plain regression (OLS) would fake precision it hasn't earned. A **linear mixed model** respects that structure and, critically, gives every reach its own flood sensitivity **without letting a thin or noisy reach run away with a wild slope.**

**Reading the per-reach figure** (three fits, same data). The figure fits the *same* points three ways so you can see why the mixed model is the right call:

- **Grey — each reach fit alone (OLS).** Fit only to that reach's own points, ignoring the rest of the river. It chases the scatter: on a thin or noisy reach it swings to a slope the data don't really support (RS29's grey line goes nearly flat; RS36's is dragged steep by one big point).
- **Orange — all reaches pooled into one line.** The opposite mistake: it forces a single slope on the whole river and treats every point as independent. But the ten reaches in a given interval all saw the *same* flood, so they are **not** independent — pooling them this way is **pseudo-replication** (counting the same flood ten times as if it were ten separate facts), and the one line ends up fitting no reach well: too shallow for responsive reaches like RS30, too steep for quiet ones like RS29.
- **Green — the mixed model (partial pooling).** The middle path, and the one we keep. Each reach gets its own line, but pulled toward the population where its own data are thin. Strong, consistent reaches (RS30, RS36) keep their steep green slope; weak reaches (RS29) are pulled back toward the average. Each reach is estimated partly on its own history and partly on the whole river — "borrowing strength" — so no reach's slope hangs on a single leverage point.

The green fit is what we carry forward; it's what makes the reach sensitivities stable enough to project one reach at a time.

> *"We measure how much new channel area the river creates, and we fit each reach partly on its own history and partly on the whole river's behavior — so no single reach's estimate hangs on one noisy data point."*

**Source — channel migration mapping:** Oregon Department of Geology and Mineral Industries (DOGAMI), Channel Migration mapping program. [oregon.gov/dogami/flood/Pages/channelmigration.aspx](https://www.oregon.gov/dogami/flood/Pages/channelmigration.aspx)

------------------------------------------------------------------------

## 3. The resulting forward model — and what it tells us

**The model, side by side.**

In words:

```         
new area per ft  =  intercept
                 +  (baseline rate    × interval length)
                 +  (flood sensitivity × flood forcing)
                 +  reach adjustment
                 +  period adjustment
                 +  noise
```

In numbers (the average reach — adjustments set to zero):

```         
new area per ft [ft]  =  11.5
                      +  1.37 × (interval years)
                      +  1.08 × (flood forcing, in 1,000 cfs-days above bankfull)
                      +  (reach offset)  +  (period offset)  +  noise
```

**What goes in (the inputs):**

- **New area per ft** — fresh channel area reworked per foot of channel length over an interval (ft). The response we predict.
- **Flood forcing** (`cum_excess`) — *cumulative flow above bankfull*: how far flow rose above the bankfull threshold (\~4,156 cfs, the \~1.5-year flood), summed over every day it stayed up. Magnitude **and** duration in one number. Its unit is 1,000 cfs-days (a flood 5,000 cfs over bankfull for 10 days = 50 units) — but the *shape* of the relationship, not the unit, is the point.

**The terms in the equation (modeling view):**

| Term | Role in the model | Value (average reach) | What it is |
|------------------|------------------|------------------|------------------|
| **Intercept** | constant offset | 11.5 ft | positions the line; literally the prediction at 0 years **and** 0 forcing — outside the physical range, so **not** a physical baseline |
| **Baseline migration** | slope on interval length | 1.37 ft / yr | steady time-accruing reworking; **one shared rate — the same for every reach** |
| **Flood sensitivity** | slope on flood forcing | 1.08 ft per 1,000 cfs-days | flood-driven reworking; this is a **population average — reaches range \~0.38 to \~1.65** |
| **Reach adjustment** | random effects | — | each reach's own intercept offset + own flood slope (partial-pooled) |
| **Period adjustment** | random intercept | spread ≈ 15 ft | per-interval offset for unmeasured drivers (antecedent wetness, sediment, vegetation); **zeroed for the future → feeds the uncertainty whiskers** |
| **Residual** | noise | spread ≈ 18 ft | mapping/digitizing judgment + fine randomness |

**Baseline migration is not the intercept.** Baseline migration is a *rate that grows with interval length* — 1.37 ft/yr, so \~14 ft over a 10-year gap and \~41 ft over a 30-year gap. The intercept is a *fixed 11.5-ft offset* that doesn't scale with anything; read literally it's the prediction for a zero-length, zero-flood interval, which can't happen — so treat it as a math anchor that positions the line, not as "the baseline."

**These are the marginal (population) numbers.** The 11.5 / 1.37 / 1.08 are the model's **fixed effects** — the average across all reaches. Nuance worth having in your pocket: the **flood sensitivity (1.08)** is a genuine average of reach-specific slopes (0.38–1.65), and it's that *per-reach* slope the projection actually uses; the intercept also varies by reach; the **baseline rate (1.37) does not vary by reach at all** — it's a single shared value.

**How it runs forward:** climate pushes only the **flood** term (Δ migration ≈ reach slope × change in forcing); the baseline and the bankfull threshold are held fixed; the period effect is zeroed. That's why the projection is a **range**, reach by reach.

**What the model tells us about the river — plain language:**

1.  **Migration runs on two processes that add together.** Steady baseline migration (ordinary high flows, every year) and episodic flood-driven migration (floods above bankfull). Both are real and statistically solid.
2.  **Which one dominates depends on the decade.** In a quiet stretch the baseline does most of the work; in a decade with a major flood, the flood dominates. *(A calm 5-year gap ≈ 7 ft of baseline work; a 3-year span with a big flood on a responsive reach can be 80+ ft of flood work.)*
3.  **Reaches are not interchangeable.** They differ several-fold in flood sensitivity — some barely respond, some rework hard. **This is the actionable result:** it tells you *where* added flood energy bites.
4.  **The relationship is genuinely straight.** Within our observed range, a curved/"saturating" form fits *worse* — no evidence the biggest floods max out the corridor. So bigger future floods keep doing proportionally more work.
5.  **Flood flow explains a real but minority slice of the reach-by-reach numbers** (\~40%), because much of the variation is which-reach, which-period, and unavoidable mapping error. Measured at the period scale, flow and time together explain \~**80%** of period-to-period migration — the flood signal is solid; it just isn't the *only* thing moving the channel.

------------------------------------------------------------------------

## 4. How we express uncertainty — the band vs. the whiskers

The projection figure carries **two different uncertainties**, and it's worth keeping them apart:

- **The shaded band = which future.** The 10–90% spread across the \~160 climate futures. It **fans out** over time, because the futures diverge as the century goes on.
- **The whiskers (bars) = how well-pinned any single estimate is** — the model's *own* prediction error at a given forcing. Built by simulation.

**How the whiskers were built (simulation).** Any one predicted point carries wobble from four sources: (1) **fitted-coefficient error** — the intercept and slopes are estimates with their own uncertainty; (2) **reach error** — the reach's adjustment is estimated too; (3) **unmeasured-period error** — a future decade will have its own "period stuff" the flow record can't see (spread ≈ 15 ft); (4) **mapping error** — the digitizing/measurement floor (spread ≈ 18 ft). We **replay the model \~1,000+ times**; each replay pulls a random value for each of those four from its fitted distribution and adds them up, producing a cloud of plausible outcomes. The **10th–90th percentiles** of that cloud are the **80% prediction interval**; divide by 30 years → ft/yr → the whisker.

**Plain reading:** *if you went out and measured migration at that forcing, there's an 8-in-10 chance the real rate falls inside the bar.*

**Confidence vs. prediction.** Including only sources 1–2 would answer *"where is the average line?"* (a confidence interval). Adding 3–4 answers *"where could a real measurement land?"* (a **prediction interval**) — the honest, wider one, and what the bars show.

**Why the bars are \~the same height everywhere while the band fans out.** The two biggest sources (period ≈ 15, mapping ≈ 18) are *fixed-size* — they don't grow with forcing — so the whisker stays about constant per reach. Only the coefficient piece widens slightly at extreme forcing. The band fans because the *futures* spread; the whisker doesn't, because the *model's* precision is roughly steady.

> *"The shaded band is which climate future you land in — it fans out with time. The little bars are how tightly the model pins any single estimate: we replayed the model a thousand times, each with the fitted uncertainties shuffled in, and took the middle 80% of the outcomes. Read a bar as: eight times out of ten, a real measured rate would fall inside it."*

------------------------------------------------------------------------

## 5. Built on public infrastructure

The analysis is a bridge on top of several large, publicly available, multi-agency efforts:

| What we used | Whose effort | Role |
|------------------------|------------------------|------------------------|
| **Channel migration mapping** (historical channel footprints) | [**DOGAMI**](https://www.oregon.gov/dogami/flood/Pages/channelmigration.aspx) (Oregon Dept. of Geology & Mineral Industries) | Our response — "what the channel has done" |
| **Future daily streamflow** (\~160 futures to 2100) | [**UW Climate Impacts Group, via RMJOC-II**](https://cig.uw.edu/datasets/columbia-river-climate-change/) (**Bureau of Reclamation + U.S. Army Corps + Bonneville Power**) | Our forcing input — "what the water may do" |
| **Observed gage record** (Pendleton, 14020850) | **USGS** | Bias-correction reference; historical forcing |
| **Flood-frequency & record-extension methods** (Bulletin 17C / PeakFQ; MOVE.3) | **USGS** | Set bankfull; reconstruct the historical flood record |

> *"This study builds on remarkable public infrastructure — state channel mapping from DOGAMI, federal climate-flow projections from Reclamation, the Army Corps, and the UW Climate Impacts Group, and streamgaging and flood-frequency methods from USGS. What we added is the connective analysis that turns those into a reach-by-reach picture of future channel migration."*

------------------------------------------------------------------------

## 6. Two key points

- **This is a risk index, not a calibrated forecast.** The wide uncertainties are deliberate and honest — the channel, sediment supply, and vegetation will all keep changing too. It's a defensible read of *how things may change and where the risk concentrates*, not a prediction of a specific number.
- **The biggest future floods are beyond anything in our record.** The far-right, high-emissions estimates are an extrapolation — flagged as the least-certain part of the plot, and the reason the tail is carried as uncertainty rather than trusted as a point value.
