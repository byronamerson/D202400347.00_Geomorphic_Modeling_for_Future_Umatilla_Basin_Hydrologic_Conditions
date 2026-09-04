# Next-Step Exploration Brief — Curve Fitting, Forcing Metrics, Stream Power

**Date:** August 2026 (revised)
**Status:** Specification. Phase 1 script written; Phases 2–5 not implemented.
**Companion:** `fire_response_analytical_pathways.md` (application/scope), `Spec_HMA_Migration_Metrics.md`, `Spec_Daily_Extension_01e.md`
**Conventions:** `docs/lingua.md`, `docs/r-principles.md`

---

## 0. Scripting Strategy — Two Tiers

`lingua.md` requires contracts on *every non-trivial or reusable function*. An exploration script with no functions has no boundaries to contract. Contract-first at exploration stage is what produced `04a` — ten contracted functions, six empty, never executed.

| Tier | Location | Rules |
|---|---|---|
| **Exploration** | `explore/` | Flat top-to-bottom. No contracts. Disposable. 40–90 lines |
| **Pipeline** | `scripts/` | Full contracts, pure helpers, I/O at boundary |

Exploration conventions:

- One file per question, named for the question: `x01_influence_diagnostics.R`
- No functions unless reused 3+ times
- Section markers `# ---- 2. leverage ----` for RStudio outline nav and run-by-section
- **Leave results in named global objects.** Do not wrap in lists — named objects are inspectable from outside the session
- Print and plot inline; write files only once an answer settles
- One-line comments stating *why*. No headers, no `@param`
- Promote to `scripts/` with full contracts only when a step earns re-running

---

## 1. Existing Objects and Columns

From `rs30_interval_sandbox.R` → `rs30_modeling_sandbox.R`:

- `rs30_plot_data` — modeling table, one row per consecutive RS 30 HMA interval
- `rs30_model_data` — above, with 2011–2012 filtered and `interval_label` added

Columns in use: `year_t1`, `year_t2`, `q_peak_max_cfs`, `new_area_ft2_per_year`, `abandoned_area_ft2_per_year`, `symmetric_change_ft2_per_year`, `net_area_change_ft2_per_year`, `symmetric_change_ft2_per_year_per_ft`, `jaccard_change`, `interval_label`

**Known defect:** in `rs30_modeling_sandbox.R`, `rs30_model_variants$all_intervals` and `$drop_2011_2012` are both assigned `rs30_model_data`, which already has 2011–2012 removed at line 65. Two of the three variants are the same model. Rename or rebuild.

---

## 2. Baseline Result Being Refined

First-pass scan, n = 13, forcing = interval maximum annual peak at Pendleton:

| Response | R² | p |
|---|---|---|
| `net_area_change_ft2_per_year` | 0.336 | **0.038** |
| `jaccard_change` | 0.183 | 0.144 |
| `new_area_ft2_per_year` | 0.175 | 0.155 |
| `abandoned_area_ft2_per_year` | 0.116 | 0.256 |
| `symmetric_change_ft2_per_year` | 0.014 | 0.700 |
| `symmetric_change_ft2_per_year_per_ft` | 0.014 | 0.700 |

Three structural facts:

- **Net area works because its components oppose.** New area trends positive, abandoned negative; the difference stacks both effects while cancelling shared noise
- **Symmetric change cancels the signal by construction** — it is the sum of those same opposing components. Demote it from primary response status
- **Panels 5 and 6 are the same model.** The segment-length divisor is a constant at single-reach scale, so R² and p are identical by necessity. The perimeter-vs-centerline bug therefore has *not* contaminated any single-reach result

Two threats to the p = 0.038:

- **Leverage.** Predictor is clumped — eight intervals in 4,500–9,000 cfs, then a gap, then five from 12,700 to 24,900. The 2017–2020 point at ~24,900 cfs is the Feb 2020 flood of record, exceeds the corrected Q₁₀₀ of ~21,800, and lands on the fitted line
- **Multiplicity.** Six responses scanned; Bonferroni threshold is 0.0083. The opposing-components mechanism partially justifies net area as quasi-pre-specified, but it was found post hoc and must be reported that way

---

## 3. Phase 1 — Curve-Fit Refinement (no new data)

**Script:** `explore/x01_influence_diagnostics.R` — written.

- Influence matrix across all six responses. Thresholds at n = 13, p = 2: Cook's D 4/n = 0.308, hat 2p/n = 0.308, DFFITS 2√(p/n) = 0.784
- Leave-one-out refit trajectory: slope, R², p with each interval dropped
- **Decision rule, set in advance:** if dropping any single interval pushes p above 0.10, report as *suggestive, mechanism-supported, not established*
- Permutation test on R² — replaces t-test asymptotics at n = 13
- Case-resample bootstrap CI on the slope. Expect it wide; the width is the result
- `log10(q_peak_max_cfs)` as predictor — compresses the high end, reduces Feb 2020 leverage
- **Δt² weighting replaces exclusion.** If polygon area error has roughly constant variance σ²_A, an annualized rate has variance σ²_A/Δt². Weights ∝ `interval_years^2` down-weight short intervals continuously, treat 2016–2017 and 2011–2012 consistently, and let 2011–2012 re-enter at low weight regardless of DOGAMI's answer (Donovan et al. 2019)
- New response: **`expansion_ratio = net / symmetric`** — dimensionless, bounded [−1, +1], **un-annualized** and therefore structurally immune to the Δt amplification that produces the short-interval outliers. Isolates the direction of adjustment while dividing out reworking magnitude

**Revised response priority:**

1. `expansion_ratio`
2. `net_area_change_ft2_per_year`
3. `new_area_ft2_per_year`
4. `abandoned_area_ft2_per_year`
5. `symmetric_change_ft2_per_year` — demoted

Symmetric change is still correct for "how much was reworked." That is simply not what peak discharge predicts here.

---

## 4. Phase 2 — Expand Peak-Flow Predictors (no new data)

**Script:** `explore/x02_peak_forcing_metrics.R`

From `data/pendleton_synthetic_peaks.csv` (annual maxima, 1952–present):

- `q_peak_mean`, `q_peak_2nd` per interval
- `n_wy_above_q2` / `q5` / `q10`, and per-year rates
- `cum_excess_peak` = Σ max(0, Q_peak,wy − Q₂), and annualized

Constraints:

- **Express as rates.** Irregular Δt makes raw counts and sums scale with interval length. `jaccard_change` already has this problem uncorrected
- **Screen collinearity first** — `car::vif()`. Peak magnitude, exceedance count, and cumulative excess are three views of the same flood
- **Compare by LOO-CV RMSE and AICc**, not in-sample R²

---

## 5. Phase 3 — Scale to RS 25–30

**Script:** `explore/x03_multireach_metrics.R`

- Replace the polygon-perimeter denominator with a centerline length via `centerline::cnt_path()`. **This is the centerline tool's only job in this project** — a one-time static extraction, rough precision adequate
- Loop interval metrics over RS 25–30
- Join corrected static slope per reach
- Mixed model with reach random intercept (`lme4::lmer`), then random slopes on Q
- ~78 reach-intervals instead of 13

---

## 6. Phase 4 — Daily Record and CESP

**Scripts:** finish `scripts/04a` (contracted) → `explore/x04_cesp_metrics.R`

- `04a` has four helpers implemented, six as empty contracts, never executed. Write the remainder against `read_waterdata_daily()` — legacy NWIS services are being decommissioned
- Per interval: days above Q₂, max continuous duration, independent event count, cumulative excess volume, RB flashiness
- **Event independence:** successive peaks separated by more than `5 + ln(A)` days; at 441 mi² that is ~11 days (Lang et al. 1999)
- Antecedent index `A(t1) = Σ λ^k Q_annual(t1−k)`. **Fix λ at 2–3 physically motivated values; do not tune it** at n = 13
- Watch: for consecutive intervals, the antecedent window of interval *i* is essentially interval *i−1*, creating an implicit lag-1 structure. Screen that correlation before interpreting

### Cumulative Effective Stream Power

The threshold-integrated energy metric is an established construct, **not a bespoke formulation**:

- **Larsen, Fremier & Girvetz (2006)**, *JAWRA* — CESP applied to bank erosion, Sacramento River. Already in this project's literature anchors
- **Mahalder et al. (2024)**, *TRR* — CESP for bridge-pier scour in cohesive sediments
- Shear-stress analogue: cumulative excess shear stress, `Σ(τ − τc)Δt` (Hanson & Simon 2001)

```
E_it [J/m] ≈ 2.400×10⁷ · S_i · Σ_d Q_id[cfs]      # 9810 × 0.02832 × 86400
```

Threshold-restricted forms are the usable ones:

```
E_above  = 2.400×10⁷ · S_i · Σ_{Q>Qc}  Q_id
E_excess = 2.400×10⁷ · S_i · Σ_{Q>Qc} (Q_id − Qc)
```

**The all-flows version is a trap** — `Σ Q` over all days is total runoff volume, dominated by baseflow. The literature settled this by building the threshold into the metric's name.

Two project-specific adaptations to disclose: normalizing **per unit channel length (J/m)** rather than per unit bed area (published CESP divides by width — this is the adaptation to the missing width series, and it matches the length-normalized response); and integrating over **multi-year photo intervals** rather than single events.

`E` is available energy, not work done — most dissipates as heat and turbulence. Report as an index. Annualize for irregular Δt.

---

## 7. Stream Power — Corrected Understanding

| Quantity | Formula | Units | Needs width? |
|---|---|---|---|
| Total, per unit channel length | `Ω = ρgQS` | W/m | **No** |
| Specific (unit) | `ω = Ω/w` | W/m² | Yes |

The earlier "off the table" call applies only to `ω`. `Ω` needs discharge and slope alone, and it is the expression that matches the length-normalized response — both are per-unit-channel-length quantities.

```
Ω [W/m] ≈ 277.8 · Q[cfs] · S
```

**Already implemented.** `compute_unit_stream_power()` in `02_reach_attributes_and_scaling.R` computes `omega_total = gamma * q2_cms * slope` alongside `omega_wm2`. Re-purpose, don't build.

### Blocking constraint

At a single reach `S` is constant, so `Ω` is a **linear rescaling of Q** and an OLS fit at RS 30 returns numerically identical R² and p. Same trap as the reach-averaged-change-rate panel. **`Ω` requires Phase 3 first.**

### Static slope still does real work

`Ω_it = 277.8 · Q_it · S_i` and `E_it = 9810 · S_i · Σ(Q_it Δt)` are static-reach-gradient × time-varying-discharge — a legitimate interaction, not a fudge. Two panel formulations:

- `Ω` or CESP as predictor directly — varies in both dimensions across RS 25–30
- **Random-slopes mixed model** — let the discharge coefficient vary by reach, then test whether reach slope predicts that variation. Cleaner attribution: asks directly whether steeper reaches are more discharge-sensitive rather than assuming the `Q·S` product form

### BUG — slope units, fix before any stream power work

`import_summary_table()` does `slope = slope_pct / 100`. **The Summary Table values are already dimensionless ft/ft despite the "Slope (%)" header.**

Proof: length-weighted across 39 reaches the column implies a **1,770 ft drop over 82.6 miles**, matching the Umatilla's actual fall. Read as percent it implies 17.7 ft, which is impossible.

- Every slope in the pipeline is **100× too small**; `omega_wm2` and `omega_total` inherit it
- R², p, and AICc ranking in `03a` are unaffected — constant multiplier
- **Broken:** all comparison to absolute literature thresholds, which is exactly what `plot_omega_vs_rate()` does with the Magilligan 300 and Yochum 230/480/700 W/m² reference lines
- Corrected, RS 30 (S = 0.0056, w = 541 ft): ω ≈ **52 W/m²** at Q₂, **206 W/m²** at Q₁₀₀ — just under Yochum's 230 threshold. A substantive result, and a reason to question transferring Front Range thresholds to a wide unconfined alluvial reach

### Slope and sinuosity are static, and stay static

- Single value per reach, Summary Table columns 6 and 7. No year dimension anywhere in the workbook
- RS 25–30: slope 0.0040–0.0068; sinuosity 1.00–1.18
- **Per-year sinuosity is not achievable — withdrawn.** HMA polygons are corridor footprints, not digitized channel traces. A medial axis extracted from one approximates the valley axis and is nearly straight by construction; year-over-year variation would be envelope digitization noise, not channel sinuosity
- Consequently time-varying slope via `S_channel = S_valley / sinuosity` is also unavailable
- Geomorphic note: sinuosity ~1.0–1.18 with RS 30 the widest reach at 541 ft and ~9 avulsions indicates a wandering/anabranching gravel-bed system. Nanson & Hickin meander-migration framing may be the wrong template; avulsion dynamics the right one

---

## 8. Sequencing

| Phase | Blocked by | Answers |
|---|---|---|
| 1 | Nothing | Does net area survive the Feb 2020 leverage point |
| 2 | Nothing | Frequency or magnitude |
| 3 | Centerline denominator; slope fix | Does gradient predict discharge sensitivity |
| 4 | `04a` six stub helpers | Does duration beat magnitude |
| 5 | Phases 1–4 | Scenario projection |

Phases 1–2 are unblocked. DOGAMI's response affects only whether 2011–2012 is trusted, and Δt² weighting removes that dependency.

---

## 9. Package Reference

| Purpose | Functions |
|---|---|
| Influence | `influence.measures()`, `cooks.distance()`, `hatvalues()`, `dffits()`, `rstudent()` |
| Tidy | `broom::augment()`, `glance()`, `tidy()` |
| Plots, VIF | `car::influencePlot()`, `car::vif()` |
| Robust | `MASS::rlm()`, `robustbase::lmrob()` |
| Small-sample selection | `MuMIn::AICc()` |
| Bounded response | `betareg::betareg()` |
| Mixed models | `lme4::lmer()`, `nlme::lme()` |
| Event separation | `DVstats::hysep()`, `part()` |
| Daily data | `dataRetrieval::read_waterdata_daily()` |
| Centerline | `centerline::cnt_skeleton()`, `cnt_path()` |

---

## 10. Literature

**Diagnostics and small-sample inference**

- Cook (1977), *Technometrics* 19(1), 15–18.
- Belsley, Kuh & Welsch (1980). *Regression Diagnostics.* Wiley.
- Benjamini & Hochberg (1995), *JRSS-B* 57(1), 289–300 — preferable to Bonferroni for the six-response scan.

**Interval measurement error**

- Donovan et al. (2019) — short- vs. long-interval rate bias, 2–15%; basis for Δt² weighting.

**Magnitude, duration, stream power**

- Wolman & Miller (1960), *Journal of Geology* 68(1), 54–74.
- Bagnold (1966), USGS PP 422-I — origin of `Ω = ρgQS`.
- Bull (1979), *GSA Bulletin* 90(5), 453–464 — threshold of critical power.
- Costa & O'Connor (1995) — magnitude *and* duration jointly.
- Magilligan (1992), *Geomorphology* 5, 373–390 — ~300 W/m².
- Yochum et al. (2017), *Geomorphology* 292, 178–192 — 230/480/700 W/m²; confinement co-predictor.
- Larsen, Fremier & Girvetz (2006), *JAWRA* — **Cumulative Effective Stream Power**.
- Mahalder et al. (2024), *TRR* — CESP, contemporary application.
- Hanson & Simon (2001) — excess shear stress erosion equation.

**Hydraulic geometry and migration**

- Leopold & Maddock (1953), USGS PP 252.
- Castro & Jackson (2001), *JAWRA* 37(5), 1249–1262 — PNW bankfull hydraulic geometry.
- Nanson & Hickin (1986), *GSA Bulletin* 97(4), 497–504.
- Dunne et al. (2024), *Science Advances* — discharge variability drives lateral migration.

**Flood frequency**

- England et al. (2019). *Bulletin 17C.* USGS TM 4-B5.
- Lang, Ouarda & Bobée (1999), *Journal of Hydrology* 225, 103–117 — partial-duration independence.

---

*End of brief. Phase 1 script is `explore/x01_influence_diagnostics.R`.*
