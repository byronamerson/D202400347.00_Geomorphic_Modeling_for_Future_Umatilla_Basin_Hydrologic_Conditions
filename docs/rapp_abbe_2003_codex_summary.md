# Rapp & Abbe (2003) CMZ Framework — Codex Reference Summary
## "A Framework for Delineating Channel Migration Zones"
## WA Dept of Ecology Publication #03-06-027

This is the foundational document for CMZ delineation in the Pacific Northwest.
DOGAMI's Oregon program (which produced our Umatilla River HMA data) follows
this framework directly. Understanding this document frames what the HMA polygons
represent and how migration rates feed into the CMZ delineation.

---

## 1. THE CMZ EQUATION

The Channel Migration Zone is the spatial sum of four components:

```
CMZ = HMZ + AHZ + EHA − DMA
```

| Component | Full Name | What It Is |
|-----------|-----------|------------|
| **HMZ** | Historical Migration Zone | Union of all historical channel positions from the aerial photo record |
| **AHZ** | Avulsion Hazard Zone | Areas outside the HMZ at risk of channel occupation via avulsion |
| **EHA** | Erosion Hazard Area | Areas outside HMZ+AHZ susceptible to bank erosion, projected forward |
| **DMA** | Disconnected Migration Area | Areas where man-made structures prevent channel migration (subtracted) |

**The HMZ is what our HMA polygons represent.** The HMA polygon for any given
date is the active channel footprint at that photo date. The union of all dated HMA
polygons = the HMZ. Our interval metrics (new_area, abandoned_area, etc.) quantify
how the HMZ grew between successive photo dates.

---

## 2. METHODS FOR MEASURING HISTORICAL CHANNEL CHANGE (§4.1)

Rapp & Abbe specify two preferred methods for quantifying planform change within
the HMZ. Both are GIS-based.

### 2.1 Transect Method (§4.1.2)

Two types of transects are used simultaneously:

- **Floodplain transects:** Perpendicular to the valley-bottom centerline. Measure
  valley width, channel sinuosity, active channel width, and locations of historical
  and secondary channels.

- **Active channel transects:** Perpendicular to the centerline of the primary
  low-flow channel, at regular increments scaled to channel size. Measure width and
  area of the primary channel, side channels, unvegetated bars, and isolated water
  bodies.

**Both transect types remain stationary across all photo dates.** Erosion rates are
calculated as the change in channel-edge position at each transect divided by the time
interval. The end product is a map of the HMZ plus erosion rate estimates.

**Limitations:** Transect spacing must match channel scale. Resolution may miss
changes between transects. Predates GIS polygon analysis and does not capture full
areal extent of change.

### 2.2 Polygon Analysis (§4.1.3) — The method we are using

Rapp & Abbe state: **"Assuming GIS is available, polygon-based analysis is preferred
over transect measurements because changes are measured areally rather than linearly."**

Three calculations are performed for each record of channel position:

```
1. Total area of the active channel at date t
2. Area of channel at date t that is OUTSIDE the area at date (t-1)
3. Area of channel at date t that is OUTSIDE ALL past channel locations
```

These directly correspond to our existing R metrics:

| Rapp & Abbe calculation | Our R metric |
|-------------------------|-------------|
| Total area at t | `area_t2_ft2` |
| Area outside previous record | `new_area_ft2` (= st_difference(HMA_t2, HMA_t1)) |
| Area outside all past locations | Cumulative new area (not yet implemented) |

**Floodplain turnover rate** (defined in §4.1.3): The time it takes for a channel to
occupy its entire valley bottom. Calculated from the polygon overlay record.
Used as input to the Erosion Hazard Area projection (§4.3).

```
Turnover Rate = Total Valley Bottom Area / (Area Reworked per Year)
```

This connects directly to our **channel activity index**:
`activity_index = symmetric_change_ft2 / (centerline_length × Δt)`,
which is the numerator of the turnover rate calculation, length-normalized.

---

## 3. EROSION HAZARD AREA EQUATIONS (§4.3)

The EHA projects erosion forward in time beyond the HMZ. It has two sub-components:
the Erosion Setback (ES) and the Geotechnical Setback (GS).

### 3.1 Erosion Setback Coefficient (CE)

```
CE = ER × (TE / TR)
```

Where:
- **ER** = bank erosion rate (ft/yr or m/yr), measured from historical photo overlay
- **TE** = average time the channel erodes at one location before moving on (years)
- **TR** = average time for the channel to reoccupy the same location (years)

**TR is estimated as:**

```
TR = (Tr1 + 2 × Tr2) / 2
```

Where:
- **Tr1** = time for a meander to migrate one wavelength downstream (years)
- **Tr2** = time for the channel to migrate across the valley bottom (one direction) (years)
- **2 × Tr2** = time for the channel to cross the valley and return (years)

### 3.2 Erosion Setback Distance (ES)

```
ES = T × CE
```

Where:
- **T** = design life of the CMZ (years; typically 100 or 500 years)
- **CE** = erosion setback coefficient from above

### 3.3 Worked Example from the Document

Given:
- Channel crosses valley bottom every 150 years (Tr2 = 150)
- Meanders move one wavelength every 100 years (Tr1 = 100)
- Bank erodes at 1.1 m/yr for 10 years before channel moves on (ER = 1.1, TE = 10)
- Design life T = 500 years

```
TR = (100 + 2 × 150) / 2 = 200 years

CE = 1.1 m/yr × (10 yr / 200 yr) = 0.055 m/yr

ES = 500 yr × 0.055 m/yr = 27.5 m ≈ 28 m
```

### 3.4 Geotechnical Setback (GS)

For banks prone to mass wasting (terraces, high alluvial banks):

```
GS = H / tan(90° − Sh)
```

Where:
- **H** = bank height (ft or m)
- **Sh** = estimated stable slope angle (degrees from horizontal)

The GS extends beyond the ES boundary to account for mass wasting once the toe is
undercut. Not needed for low floodplain banks; essential for glacial outwash or high
alluvial terrace banks.

**The full EHA is:** `EHA = ES + GS`

---

## 4. WHAT THE HMZ / HMA DATA PRODUCTS REPRESENT

Key definitions from the glossary and Chapter 2:

- **Active channel:** "The portion of a channel that is largely unvegetated, at
  least for some portion of the year, and inundated at times of high discharge."
  This is what each dated HMA polygon captures.

- **Historical Migration Zone (HMZ):** "The area the channel has occupied over the
  course of the historical record, delineated by the outermost extent of channel
  locations plotted over that time." = the union of all dated HMA polygons.

- **Channel confinement categories:**
  - Confined: valley width < 2 × bankfull width
  - Moderately confined: valley width = 2–4 × bankfull width
  - Unconfined: valley width > 4 × bankfull width
  - CMZs occur in unconfined and moderately confined channels, typically < 4% gradient

- **Bankfull stage** is defined geomorphically, NOT by the 1.5-yr flood recurrence.
  "Because the bankfull channel reflects on-going geomorphic processes, rivers do
  not have a common recurrence interval or bankfull stage" (Williams 1978).

- **Meander belt:** "The historical width of the strip of floodplain previously
  occupied by the channel." Rapp & Abbe explicitly state this is NOT used for CMZ
  delineation because meander belts themselves migrate and channels can avulse
  outside them.

---

## 5. VERTICAL CHANNEL DYNAMICS AND AVULSION (§4.2)

Rapp & Abbe emphasize that planimetric (2D) analysis alone is insufficient — vertical
channel change (aggradation/incision) drives avulsion hazards.

**Key guidance for vertical variability:**
- In forested systems, log jams cause 2+ meters of aggradation
- Vertical fluctuations ≥ 1 rootwad diameter or 2–3 basal diameters of mature trees
- Channelized or wood-cleared streams are more likely to incise, not aggrade
- The Simon & Hupp (1986) channel evolution model applies: incision → widening →
  secondary aggradation → new equilibrium

**For our Umatilla analysis:** The upper Umatilla (RS 25–30) is a relatively confined
gravel-bed river with agricultural floodplain. Vertical dynamics from LWD are less
dominant than in west-side WA rivers, but incision/aggradation cycles may still matter.
The planimetric polygon analysis is the appropriate primary method for this system.

---

## 6. LIMITATIONS OF PLANIMETRIC ANALYSIS (§4.1, directly quoted concerns)

Rapp & Abbe flag these limitations of the polygon overlay approach we are using:

1. **Registration errors** compound with inconsistent feature delineation → spurious
   erosion rate measurements. (Our data comes from DOGAMI's professional GIS
   production, which mitigates this.)

2. **Planimetric analysis only documents geographic changes** — on-the-ground
   processes are inferred. It does not explicitly account for bank material, soils,
   vegetation, sediment, discharge, or structures.

3. **No measurement of vertical channel change.**

4. **Difficult on smaller streams** where features are hard to resolve.

5. **Period of record must be long enough** — "at least 50 years" recommended to
   capture climatic variability. (Our record: 1952–2022 = 70 years. ✓)

6. **Short intervals amplify noise.** Very short intervals (1–2 years between photos)
   may not show meaningful migration and are dominated by digitization uncertainty.

---

## 7. HOW THIS CONNECTS TO OUR PIPELINE

### What we have:
- 20 dated HMA polygons (1952–2022) = the building blocks of the HMZ
- CMZ segment polygons (39 segments, working with RS 25–30)
- Peak flow records from USGS gages
- The `rs30_interval_sandbox.R` script implementing polygon overlay metrics

### What our metrics measure in Rapp & Abbe terms:
- `new_area_ft2` = "area of channel outside the area of previous record" (§4.1.3 calc #2)
- `abandoned_area_ft2` = area no longer in the corridor (corridor contraction)
- `symmetric_change_ft2` = total reworked area (a proxy for corridor dynamism)
- `new_area / (length × Δt)` = the **erosion rate ER** that feeds into the ES equation

### What we could compute later:
- **Floodplain turnover rate** = total valley bottom area ÷ average annual reworking rate
  This is Rapp & Abbe's key parameter for projecting the EHA forward.
- **Cumulative new area outside ALL past locations** = Rapp & Abbe's calc #3 from §4.1.3.
  Tracks how much truly new floodplain the corridor occupies over the full record.
- **Erosion Setback (ES)** projection using the CE equation and measured ER values
- **Confinement ratio** per segment = valley width / bankfull width

### The flood-response plotting question in Rapp & Abbe context:
Rapp & Abbe do NOT directly correlate migration rates with peak flows — their
framework treats the historical record as an integrated whole and projects forward with
a single ER value. Our analysis goes further by **decomposing the historical record into
intervals and testing whether migration metrics vary systematically with flood magnitude
in each interval.** This is closer to Richard et al. (2005) on the Rio Grande, who showed
R² > 0.50 between polygon-derived migration rates and total stream power. If we find
a significant relationship, it strengthens the physical basis for the ER values and could
support flow-conditional ES projections.

---

## 8. EQUATION REFERENCE CARD

```
# CMZ master equation
CMZ = HMZ + AHZ + EHA − DMA

# Erosion setback coefficient
CE = ER × (TE / TR)

# Reoccupation time
TR = (Tr1 + 2 × Tr2) / 2

# Erosion setback distance
ES = T × CE

# Geotechnical setback
GS = H / tan(90° − Sh)

# Full erosion hazard area
EHA = ES + GS

# Our interval metrics (what feeds ER)
new_area_rate = st_area(st_difference(HMA_t2, HMA_t1)) / (centerline_length × Δt)
activity_index = st_area(st_sym_difference(HMA_t1, HMA_t2)) / (centerline_length × Δt)
```

---

## 9. REFERENCE

Rapp, C.F. and Abbe, T.B. (2003). A Framework for Delineating Channel Migration
Zones. Washington Department of Ecology, Shorelands and Environmental Assistance
Program. Publication #03-06-027. 135 pp.
