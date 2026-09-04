# Daily Streamflow Extension Strategy: Pendleton Gage (14020850)

## Purpose

Extend the daily mean discharge record at the Pendleton gage backward from its start (~1996) to 1952, using the Gibbon and Umatilla gages as index stations. The extended record supports extraction of high-flow forcing metrics for a coupled channel-migration regression model.

## Context and Scope

### What this is for

The downstream analytical goal is a coupled regression model predicting channel change as a function of both peak discharge magnitude and flow duration above a geomorphic threshold. The specific metrics to extract from the extended daily record are:

- Peak daily Q per photo interval
- Total days above Q₂ (~5,500 cfs at Pendleton) per photo interval
- Cumulative daily discharge volume above Q₂ per photo interval
- Count of discrete exceedance events per photo interval
- Maximum continuous duration above Q₂ per photo interval

These metrics will be fit against measured channel migration (from HMA data available 1952–present) using an additive or interaction model structure (form TBD).

### What this is NOT

This is not a general-purpose daily hydrograph reconstruction. We do not need accurate estimates of summer baseflow, low-flow statistics, or the full flow-duration curve. We need the high-flow tail of the daily record — specifically, days where discharge exceeds approximately the 2-year flood — to be well-characterized.

### Why the high-flow focus simplifies the problem

Filtering to days above Q₂ eliminates or greatly reduces the standard statistical objections to daily record extension:

- **Seasonality:** Flows above Q₂ at Pendleton occur almost exclusively November–May. The seasonal mixture problem is gone.
- **Losing-stream behavior:** At bankfull and above, infiltration losses to the alluvial aquifer are negligible relative to total discharge. The documented pattern where Pendleton sometimes exceeds Umatilla discharge despite 5× smaller drainage area is primarily a baseflow and irrigation-season phenomenon.
- **Serial correlation:** We are extracting event-scale metrics (discrete flood events lasting days to weeks), not fitting a continuous daily time series. Autocorrelation within events is physical signal, not statistical nuisance.
- **Different behavior at different flow levels:** By restricting the transfer relationship to high flows, we avoid contaminating the regression with low-flow days that have a different interstation relationship.

---

## Gage Network

| Gage ID | Name | Position | DA (mi²) | Daily Record | Peaks | Regulation |
|---------|------|----------|----------|-------------|-------|------------|
| 14020000 | Umatilla R above Meacham Cr nr Gibbon | Upstream | 131 | ~1933–present | 92 yr (1933–2024) | Clean |
| 14020850 | Umatilla R at W Reservation Bndy nr Pendleton | **Target** | 441 | ~1996–present | 30 yr (1996–2025) | Clean |
| 14033500 | Umatilla R near Umatilla | Downstream | 2,290 | ~1904–present | 121 yr (1904–2024) | McKay Dam (all peaks coded 5/6) |

**Extension target period:** 1952–1996 (constrained by earliest available HMA aerial photo data, not gage record length).

**Index gage coverage for extension period:**
- Gibbon: full coverage 1952–1996 (clean, unregulated)
- Umatilla: full coverage 1952–1996, but requires McKay regulation correction

---

## McKay Regulation Correction on Daily Data

### Rationale

The Umatilla gage (14033500) is downstream of the McKay Creek confluence. McKay Dam (constructed 1923–1927) attenuates flood peaks from McKay Creek by up to 85% (documented in the 2020 event). To use Umatilla as a second index gage for daily extension, we need to correct its daily record to approximate natural (unregulated) conditions.

### Available data for correction

- **MCKO** (McKay Cr below dam, daily Q): ~1980–present
- **MYKO** (McKay Cr above reservoir, daily Q): ~1980–present  
- **MCK** (McKay Reservoir storage, daily AF): ~1980–present
- **USGS 14023500** (McKay Cr nr Pendleton, daily + peaks): ~1918–1991

### Approach

Extend the peak-event correction framework already built in `01d_regulation_correction.R` to operate on a daily time step:

1. **For the MCKO/MYKO overlap period (~1980–present):** On each day, compute the McKay deficit = (natural McKay inflow) − (observed dam release). Natural inflow is MYKO where available, or the mass-balance estimate (dS/dt + Q_out) where MYKO has gaps. Add the deficit to the observed Umatilla daily Q.

2. **For pre-1980 (no MYKO/MCKO data):** Use the statistical scaling relationship from `01d` — estimate McKay natural inflow from the drainage-area ratio and the Umatilla flow magnitude, then subtract the expected regulated release pattern. This is less precise but still corrects the first-order bias.

3. **Screening:** Only apply correction on days where Umatilla flow is elevated (above some baseflow screening threshold). During low flows, the McKay correction is dominated by irrigation-release patterns that are not relevant to high-flow extension.

### Implementation note

The daily correction should be developed and validated in `01d_regulation_correction.R` (or a companion script) before it feeds into the extension workflow. Cross-validate against the concurrent period where Pendleton observations exist.

---

## Extension Methods

### Primary: Conditional MOVE.1 on High-Flow Days

**Package:** `smwrStats::move.1()`, `smwrStats::jackknifeMove.1()`

**Concept:** Fit the MOVE.1 (Line of Organic Correlation) variance-preserving regression only on days where flows are in the high-flow regime. This focuses the transfer equation on the flow range that matters for channel migration metrics.

**Steps:**

1. Build a concurrent daily dataset (1996–2025) joining Pendleton, Gibbon, and McKay-corrected Umatilla.

2. Filter to high-flow days using a screening threshold. Options to test:
   - Days where Gibbon > Gibbon's Q₂ equivalent
   - Days where Pendleton > some fraction of Pendleton's Q₂ (e.g., 0.5 × Q₂)
   - Days in the November–May runoff season above a lower threshold (e.g., mean monthly flow for that month)
   
   The threshold choice affects sample size and regression quality — diagnose this before committing.

3. Fit MOVE.1 in log10-space:
   ```r
   library(smwrStats)
   
   mod_gibbon <- move.1(log10(pendleton_q) ~ log10(gibbon_q),
                        data = high_flow_concurrent,
                        distribution = "commonlog")
   
   mod_umatilla <- move.1(log10(pendleton_q) ~ log10(umatilla_corrected_q),
                          data = high_flow_concurrent,
                          distribution = "commonlog")
   ```

4. Jackknife cross-validation:
   ```r
   jk_gibbon <- jackknifeMove.1(log10(pendleton_q) ~ log10(gibbon_q),
                                data = high_flow_concurrent,
                                distribution = "commonlog")
   ```

5. For the extension period (1952–1996), apply the fitted models to predict Pendleton daily Q on days where the index gage exceeds the screening threshold. Days below the threshold are not reconstructed (they are below the geomorphic relevance threshold anyway).

### Two-Index Weighting

Where both index gages have coverage (both extend back to at least 1952), combine predictions using inverse-variance weighting:

```r
# Weights from jackknife RMSE
w_g <- 1 / rmse_gibbon^2
w_u <- 1 / rmse_umatilla^2

pendleton_est <- (w_g * est_gibbon + w_u * est_umatilla) / (w_g + w_u)
```

This parallels the inverse-variance weighting already used for MOVE.3 peak extension in `01c_move3_extension_and_weighting.R` (B17C Appendix 9).

If the McKay-corrected Umatilla daily record is only available from ~1980, then:
- **1980–1996:** Use two-index weighted estimate
- **1952–1980:** Use Gibbon-only estimate

### Alternative/Supplementary: MOVE.2 with Optimized Box-Cox

**Package:** `smwrStats::move.2()`, `smwrStats::optimBoxCox()`

If diagnostic plots show the log-space relationship between Gibbon and Pendleton is nonlinear (especially in the high-flow tail), MOVE.2 with an optimized Box-Cox transform may fit better:

```r
bc <- optimBoxCox(cbind(pendleton_q, gibbon_q), data = high_flow_concurrent)
mod2 <- move.2(pendleton_q ~ gibbon_q, data = high_flow_concurrent, distribution = bc)
```

Test this against MOVE.1 and select based on jackknife performance.

### Alternative/Supplementary: QPPQ Flow-Duration Curve Transfer

**Package:** `DVstats::QPPQ()`, `DVstats::estFDC()`

If a full daily reconstruction is needed (e.g., for Phase 2 climate-projection forcing), QPPQ transfers flows by mapping exceedance probabilities between index and target FDCs:

```r
library(DVstats)

fdc_gibbon    <- estFDC(gibbon_daily$daily_q_cfs)
fdc_pendleton <- estFDC(pendleton_daily$daily_q_cfs)

pendleton_est <- QPPQ(Q.in = gibbon_pre1996$daily_q_cfs,
                       FDC.in = fdc_gibbon,
                       FDC.out = fdc_pendleton)
```

**Monthly QPPQ** (build 12 separate FDC pairs) would handle seasonality. This is more relevant to Phase 2 than the current high-flow-focused analysis.

---

## Diagnostic and Validation Workflow

Before committing to a method, run these diagnostics on the concurrent period (1996–2025):

### Step 1: Characterize the high-flow transfer relationship

- Scatter plots: log10(Pendleton) vs. log10(Gibbon) and log10(Pendleton) vs. log10(corrected Umatilla), colored by month
- Compute correlation coefficients for high-flow days only (above various threshold candidates)
- Check for nonlinearity: do residuals from a log-space linear fit show curvature?
- Check for heteroscedasticity: does the scatter increase at the highest flows?

### Step 2: Evaluate threshold sensitivity

- How does the MOVE.1 slope and correlation change as you vary the screening threshold from (0.25 × Q₂) to (1.0 × Q₂)?
- How many days per year pass each threshold in the concurrent period vs. the extension period?
- Is there a natural breakpoint in the Gibbon→Pendleton relationship?

### Step 3: Validate event metrics

- For each water year in the concurrent period, extract the target metrics (days above Q₂, cumulative excess volume, event count, max duration) from:
  (a) observed Pendleton daily record
  (b) MOVE.1-predicted Pendleton daily record (using Gibbon as if Pendleton didn't exist)
  (c) two-index weighted prediction
- Compare (a) vs. (b) and (a) vs. (c) — this is the leave-one-out validation for the metrics that actually matter

### Step 4: Cross-check against annual metric MOVE.3

- Extract the annual metric series (e.g., annual days above Q₂) from the concurrent period at all three gages
- Extend Pendleton's annual metric series backward using MOVE.3 (as in `01c`)
- Compare the MOVE.3-extended annual metrics against the annual metrics extracted from the daily-extended record
- Agreement = convergence of evidence; disagreement = diagnostic signal

---

## Key R Packages and Functions

### Installed from code.usgs.gov

| Package | Key Functions for This Workflow |
|---------|-------------------------------|
| `smwrStats` | `move.1()`, `predict.move.1()`, `jackknifeMove.1()`, `move.2()`, `optimBoxCox()`, `seasonalPeak()`, `serial.test()` |
| `DVstats` | `QPPQ()`, `estFDC()`, `consistentFDC()`, `flowDurClasses()`, `hysep()`, `part()`, `dvStat()` |
| `smwrBase` | Date/time utilities, water year functions |
| `smwrGraphs` | USGS-style hydrologic plots |
| `smwrData` | Example datasets |
| `smwrQW` | Water quality (dependency, not directly used) |
| `dataRetrieval` | NWIS data access |
| `peakfq` | B17C flood frequency via `emafit()` |

### CRAN dependencies

`lubridate`, `robust`, `evd`, `tidyverse`

### Install order (from code.usgs.gov GitLab)

```r
remotes::install_gitlab("water/analysis-tools/smwrData", host = "code.usgs.gov")
remotes::install_gitlab("water/analysis-tools/smwrBase", host = "code.usgs.gov")
remotes::install_gitlab("water/analysis-tools/smwrGraphs", host = "code.usgs.gov")
remotes::install_gitlab("water/analysis-tools/smwrStats", host = "code.usgs.gov")
remotes::install_gitlab("water/analysis-tools/smwrQW", host = "code.usgs.gov")
remotes::install_gitlab("water/analysis-tools/DVstats", host = "code.usgs.gov")
```

---

## Relationship to Existing Pipeline

This work slots into the project pipeline as follows:

- **`01_hydrology_acquisition.R`** — already pulls daily and peak data for all three gages
- **`01b_mckay_creek_acquisition.R`** — already acquires McKay Creek daily records (MCKO, MYKO, MCK storage)
- **`01c_move3_extension_and_weighting.R`** — already implements MOVE.3 peak extension with inverse-variance weighting; the daily extension parallels this framework
- **`01d_regulation_correction.R`** — already implements McKay peak-event correction; needs to be extended to daily time step
- **NEW: `01e_daily_extension.R`** (or similar) — the new script implementing the daily extension workflow described here
- **`02_reach_attributes_and_scaling.R`** — downstream consumer of the extended metrics; currently uses DA scaling for reach-level discharge estimates

---

## Key References

- Hirsch, R.M., 1982, A comparison of four streamflow record extension techniques: Water Resources Research, v. 18, p. 1081–1088. (Introduces MOVE.1 and MOVE.2)
- Vogel, R.M., and Stedinger, J.R., 1985, Minimum variance streamflow record augmentation procedures: Water Resources Research, v. 21, no. 5, p. 715–723. (Introduces MOVE.3)
- England, J.F., Jr., et al., 2019, Guidelines for determining flood flow frequency — Bulletin 17C: USGS Techniques and Methods 4-B5. (MOVE.3 in Appendix 8, inverse-variance weighting in Appendix 9)
- HEC-SSP Tutorial: Daily Flow Record Extension with MOVE.1 — https://www.hec.usace.army.mil/confluence/sspdocs/ssptutorialsguides/daily-flow-record-extension/daily-flow-record-extension-with-move-1 (Demonstrates the danger of naive daily MOVE.1 for high-flow metrics; recommends annual-metric MOVE.3 as alternative)
- Fennessey, N.M., 1994, A hydro-climatological model of daily streamflow for the northeast United States: PhD dissertation, Tufts University. (Introduces QPPQ method)
- Archfield, S.A., et al., 2010, An objective and parsimonious approach for classifying natural flow regimes at a continental scale: River Research and Applications. (QPPQ operationalized)
- Granato, G.E., 2009, Computer programs for obtaining and analyzing daily mean streamflow data: USGS OFR 2008-1362. (SREF program implementing MOVE.1 and MOVE.3 for daily data)
