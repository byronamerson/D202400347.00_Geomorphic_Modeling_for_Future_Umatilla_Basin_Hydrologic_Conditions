# Quantifying channel migration from polygon-based historical mapping

**The dominant method for converting Historical Migration Area (HMA) polygons to migration rates is the area-divided-by-length approach**: the area of the polygon swept between two successive channel positions is divided by reach length to yield average lateral migration distance, then divided by the time interval for a rate. This core technique underpins the Washington State CMZ framework (Rapp & Abbe 2003; Legg et al. 2014), DOGAMI's Oregon program, and the French "bande active" school (Alber & Piégay 2011, 2017). Transect-based methods applied to the boundaries of migration polygons provide spatial variability along the reach. The field has matured significantly since 2015, with dedicated GIS toolboxes (FluvialCorridor, SCS Toolbox, WA Channel Migration Toolbox) now operationalizing polygon-based workflows. Notably, overlap-based stability indices (Jaccard/IoU) applied to channel polygons appear to be a genuine methodological gap — implicit in symmetric-difference analyses but not yet formalized in the fluvial literature.

---

## 1. Washington State CMZ framework: the foundational polygon-to-rate methodology

### 1.1 Rapp & Abbe (2003) — CMZ component framework

**Description:** The seminal CMZ delineation methodology defining the Historical Migration Zone (HMZ) as the union of all historical channel positions. Migration rates are projected forward as erosion setbacks.

**CMZ equation:**
```
CMZ = HMZ + AHZ + EHA − DMA
```
Where HMZ = Historical Migration Zone (cumulative channel envelope), AHZ = Avulsion Hazard Zone, EHA = Erosion Hazard Area (= Erosion Setback + Geotechnical Setback), DMA = Disconnected Migration Area.

**Erosion Setback formula:**
```
ES = (dx/dt) × Design Life
GS = Bank Height / tan(Stable Slope Angle)
```

**Two quantitative methods specified:**
- **Transect method** (§4.1.2): Fixed transects perpendicular to the channel/floodplain; migration rate = lateral displacement of channel edge ÷ time interval at each transect.
- **Polygon analysis** (§4.1.3): GIS overlay of sequential channel polygons to identify erosion and accretion areas, referenced to Jacobson & Pugh (1997).

**Data inputs:** Georeferenced historical aerial photos, GLO survey maps (~1870s), USGS topographic maps, LiDAR DEMs, field surveys.

**Limitations:** Assumes past behavior predicts future behavior. Requires specified design life (typically 100 years). Intensive/costly (~$1000s/mile). Does not account for climate change.

**Citation:** Rapp, C.F. and Abbe, T.B. (2003). *A Framework for Delineating Channel Migration Zones.* Washington Department of Ecology Publication #03-06-027.

---

### 1.2 Washington Channel Migration Toolbox (Legg et al. 2014) — The key polygon-to-rate implementation

**Description:** Four ArcGIS tools operationalizing the Rapp & Abbe framework. **This is the most directly relevant published tool for converting polygon-based mapping to migration rates.**

**Tool 1 — Reach-average migration (the core polygon method):**
```
Reach-Average Migration Distance = Migration Polygon Area / Reach Length
Reach-Average Migration Rate = Migration Distance / Δt (years)
```
Migration polygons are formed between consecutive channel centerlines. The area swept is divided by valley/reach length for an average lateral migration distance — this is the fundamental polygon-to-rate conversion.

**Tool 2 — Transect generation:** Creates evenly-spaced perpendicular transects from a user-defined centerline. The toolbox recommends using a **generalized HMZ centerline** rather than the valley centerline, because valley-perpendicular transects intersect migration polygons at oblique angles and systematically overestimate migration.

**Tool 3 — Transect migration:** Each transect intersects migration polygons; the width of intersection = migration distance at that transect.
```
Annual Migration Rate at Transect = Total Migration Distance / Number of Years
```

**Tool 4 — Transect channel width:** Intersects transects with channel outline polygons for width over time.

**Data inputs:** Channel centerlines (polylines) and channel outline polygons for each date, reach boundary lines, valley or generalized centerline.

**Limitations:** Centerline type (wetted vs. active channel) affects results. Transect angle affects measurement accuracy on highly sinuous channels. ArcGIS 10.x only.

**Citation:** Legg, N.T., Heimburg, C., Collins, B.D., and Olson, P.L. (2014). *The Channel Migration Toolbox: ArcGIS Tools for Measuring Stream Channel Migration.* Washington Department of Ecology Publication 14-06-032.

---

### 1.3 King County DNRP refinements

**Description:** Follows the Rapp & Abbe framework with three acceptable migration measurement methods: (1) transect method, (2) meander bend method (point-to-point displacement of analogous features), and (3) other functionally equivalent methods.

**Key refinement:** Migration rates must be calculated **separately** for armored banks, unarmored banks, and actively migrating banks. King County uses higher percentiles (75th or 90th) rather than the mean for conservative hazard delineation.

**Citation:** King County (2014). *Appendix A to Revised King County Channel Migration Public Rule.* King County Department of Natural Resources and Parks.

---

### 1.4 Planning-level CMZ (Olson et al. 2014)

**Description:** A lower-cost alternative that uses landform interpretation (LiDAR-derived Relative Elevation Models, geologic maps) rather than migration rate measurement. **Does not produce quantitative migration rates** — instead defines the CMZ as the Modern Valley Bottom plus Erosion Hazard Area via geomorphic mapping.

**Limitations:** Cannot be assigned a numerical design life. More conservative (wider) than rate-based methods.

**Citation:** Olson, P.L., Legg, N.T., Abbe, T.B., Reinhart, M.A., and Radloff, J.K. (2014). *A Methodology for Delineating Planning-Level Channel Migration Zones.* Washington Department of Ecology Publication 14-06-025.

---

## 2. DOGAMI's Oregon CMZ program follows Washington with tiered hazard zones

**Description:** Oregon's Department of Geology and Mineral Industries explicitly follows Rapp & Abbe (2003), mapping the Historical Migration Area (HMA) as the union of all historical active channel positions, then calculating local erosion rates from sequential channel positions using transect measurements.

**Key difference from Washington:** DOGAMI produces **tiered erosion hazard zones** — 30-year high, 30-year medium, and 100-year low hazard — plus flagged stream banks as a distinct mapped unit.

**Erosion Setback formula (same as Washington):**
```
Erosion Setback = Measured Erosion Rate × Design Life (30 or 100 years)
```

**Example measured rates:** Zigzag River: **8.9–40.4 ft/yr** maximum; Johnson Creek: **0.9–3.5 ft/yr** maximum.

**Citations:**
- English, J.T. and Coe, D.E. (2011). *Channel migration hazard maps, Coos County, Oregon.* DOGAMI Open-File Report O-11-09.
- DOGAMI (2024). *Channel migration zone maps for Eastern Lane County.* OFR O-24-02.
- Roberts, J.T. and Anthony, L.H. (2015). *Statewide Subbasin-Level Channel Migration Screening for Oregon.* DOGAMI IMS-56.

---

## 3. Colorado's Fluvial Hazard Zone approach explicitly rejects rate-based methods

**Description:** After the 2013 Front Range floods, Colorado developed the **Fluvial Hazard Zone (FHZ)** program through the Colorado Water Conservation Board (CWCB). The FHZ protocol defines two map units: the **Active Stream Corridor (ASC)** and the **Fluvial Hazard Buffer (FHB)**.

**Critical distinction: Colorado's FHZ does NOT use migration rate measurements.** The protocol explicitly states: *"Simply measuring, modeling, or calculating erosion as bank retreat is insufficient in capturing all fluvial geomorphic hazards."* The mapping is qualitative geomorphic interpretation by qualified professionals, using LiDAR DEMs, Relative Elevation Models, aerial photography, and field observations.

**FHZ = Active Stream Corridor + Fluvial Hazard Buffer**

Some supplementary analyses include historical bankline delineation (e.g., six aerial photo dates spanning 85 years), but these are descriptive rather than rate-based.

**Limitations:** Planning-level only. Does not predict magnitude, frequency, or rate. Voluntary at the state level.

**Citation:** Blazewicz, M., Jagt, K., Sholtes, J., and Sturm, C. (2020). *Colorado Fluvial Hazard Zone Delineation Protocol v1.0.* Colorado Water Conservation Board.

---

## 4. NCHRP Report 533 and HEC-20: circle-fit and overlay methods for bridge design

### 4.1 NCHRP 533 — Best-fit circle / centroid comparison

**Description:** An empirical photogrammetric method for predicting meander bend migration. Circles are fit to the outer banklines of meander bends, and changes in circle radius and centroid position are tracked over time. A database of **141 sites, 1,503 bends on 89 U.S. rivers** underpins the statistical relationships.

**Key metrics:**
```
Migration Distance = displacement of best-fit circle centroid between dates
Migration Rate = Migration Distance / Δt (ft/yr or channel widths/yr)
ΔRc = change in radius of curvature between dates
```

**Migration modes classified:** Extension (outward growth), Translation (downstream movement), Expansion (both), Rotation (angular displacement of bend axis).

**Three levels of application:** Manual overlay, computer-assisted (CAD), and GIS-based extensions (Data Logger + Channel Migration Predictor).

**Limitations:** Applies primarily to single-thread meandering rivers. Cannot model avulsions or catastrophic changes. Best-fit circles are less suited for compound bends.

**Citation:** Lagasse, P.F., Spitz, W.J., Zevenbergen, L.W., and Zachmann, D.W. (2004). *Handbook for Predicting Stream Meander Migration.* NCHRP Report 533. Transportation Research Board.

### 4.2 FHWA HEC-20 — Three-level stream stability analysis

**Description:** Multi-level analysis procedure for stream stability at highway crossings. Level 1 is qualitative geomorphic assessment; Level 2 includes basic engineering analyses; Level 3 involves mathematical/physical modeling. Chapter 6 covers lateral stability and references both map/photo overlay comparison and the NCHRP 533 circle-fit method.

**Basic migration rate formula:**
```
Rate = ΔPosition / ΔTime
```

**Citation:** Lagasse, P.F., Zevenbergen, L.W., Spitz, W.J., and Arneson, L.A. (2012). *Stream Stability at Highway Structures.* HEC-20, Fourth Edition. FHWA-HIF-12-004.

---

## 5. Active River Corridor and European "freedom space" polygon methods

### 5.1 Erodible corridor concept (Piégay et al. 2005)

**Description:** A review of techniques for delimiting the erodible river corridor using three approaches: (1) empirical rules-of-thumb (equilibrium meander amplitude from discharge-geometry relationships), (2) historical overlay (union of all historical channel positions), and (3) simulation modelling. The corridor envelope polygon — the spatial union of all digitized active channel positions — is the central data product.

**Key metrics:** Corridor width measured perpendicular to valley axis; corridor width relative to current channel width; equilibrium meander amplitude predicted from empirical hydraulic geometry.

**Citation:** Piégay, H., Darby, S.E., Mosselman, E., and Surian, N. (2005). A review of techniques available for delimiting the erodible river corridor. *River Research and Applications*, 21(7), 773–789.

### 5.2 Freedom space for rivers (Biron et al. 2014)

**Description:** Combines a **mobility space** (from historical channel overlay + projected future migration) and a **flooding space** (from LiDAR-based hydrogeomorphic mapping) into three hierarchical freedom space levels. Level 1 (Lmin) averages **~1.7× current channel width**.

**Key metrics:**
- Mobility space (M): polygon from union of all historical channel positions, projected forward (50-year horizon)
- Flooding space (I): hydrogeomorphic flood envelope from LiDAR
- Freedom space width expressed as multiples of channel width per reach segment

**Citations:**
- Biron, P.M., Buffin-Bélanger, T., Larocque, M., et al. (2014). Freedom space for rivers: A sustainable management approach. *Environmental Management*, 54(5), 1056–1073.
- Buffin-Bélanger, T., Biron, P.M., Larocque, M., et al. (2015). Freedom space for rivers: An economically viable concept in a changing climate. *Geomorphology*, 251, 137–148.

### 5.3 Extended freedom space mapping (Massé et al. 2020)

**Description:** Tested across 167 km in Quebec. Key finding: **flood processes occur within ~2.6 channel widths** on average, while **erosion processes span ~20.6 channel widths** — erosion zones are dramatically larger than flooding zones.

**Citation:** Massé, S., Demers, S., Besnard, C., et al. (2020). Development of a mapping approach encompassing most fluvial processes. *River Research and Applications*, 36, 947–959.

### 5.4 Spatial disaggregation framework (Alber & Piégay 2011) — The core polygon-to-metric method

**Description:** The foundational GIS methodology for converting corridor polygons into quantitative longitudinal metrics. Corridor polygons are subdivided into equal-length **Disaggregated Geographic Objects (DGOs)** perpendicular to the centerline (every 50–200 m), creating transverse "slices." Per-slice metrics are calculated and then aggregated into statistically homogeneous reaches using the Hubert test.

**Key metrics derived from each polygon slice:**
```
Active channel width = polygon area within DGO / centerline length within DGO
Confinement ratio = channel width / valley bottom width
Sinuosity = channel centerline length / valley axis length per segment
Corridor envelope width = width of union polygon of all temporal channel positions
```

**Citation:** Alber, A. and Piégay, H. (2011). Spatial disaggregation and aggregation procedures for characterizing fluvial features at the network-scale. *Geomorphology*, 125(3), 343–360.

### 5.5 FluvialCorridor GIS toolbox (Roux et al. 2015)

**Description:** ArcGIS toolbox implementing the Alber & Piégay framework with four toolsets: spatial components extraction, disaggregation, metrics computation, and statistical aggregation. Automates centerline extraction from polygons, polygon slicing into DGOs, and computation of width, sinuosity, confinement, and contact-length metrics.

**Citation:** Roux, C., Alber, A., Bertrand, M., Vaudor, L., and Piégay, H. (2015). "FluvialCorridor": A new ArcGIS toolbox package for multiscale riverscape exploration. *Geomorphology*, 242, 29–37.

### 5.6 Regional-scale migration rate analysis (Alber & Piégay 2017)

**Description:** Characterized and modeled migration rates across **99 reaches in the French Rhône Basin (111,300 km²)** from diachronic channel polygon overlay. Explored correlations between migration rate and watershed area, channel slope, stream power, and active channel width.

**Key metrics:**
```
Absolute lateral migration rate (m/yr) from overlay of diachronic channel polygons
Normalized migration rate = migration rate / channel width (dimensionless, per year)
Migration polygon area = area between successive channel positions
```

**Citation:** Alber, A. and Piégay, H. (2017). Characterizing and modelling river channel migration rates at a regional scale. *Journal of Environmental Management*, 202, 479–493.

### 5.7 Standalone Channel Shifting Toolbox (Rusnák et al. 2025)

**Description:** A new ArcGIS toolbox that takes vectorized channel polygons as primary input and automatically identifies erosion/deposition areas from polygon superposition, computes lateral migration direction, and generates floodplain statistics from LiDAR. Works standalone or linked to FluvialCorridor. Tested on sinuous, meandering, and braided-wandering rivers.

**Key metrics:** Erosion area, deposition area, direction of lateral movement, channel width change per DGO, floodplain age (time since last channel occupancy).

**Citation:** Rusnák, M., Opravil, Š., Dunesme, S., Afzali, H., Rey, L., Parmentier, H., and Piégay, H. (2025). A channel shifting GIS toolbox for exploring floodplain dynamics through channel erosion and deposition. *Geomorphology*, 475, 109584.

### 5.8 Monte Carlo uncertainty for polygon-based surficial metrics (Jautzy et al. 2022)

**Description:** Goes "beyond linear metrics" to assess significance of planform changes through surficial (area-based) metrics. Uses Monte Carlo simulations to propagate spatially variable geometric errors into uncertainty estimates for measured erosion/deposition areas. Tested on the lower Bruche River (France); **uncertainties ranged 15.8%–52.9%** of measured change.

**Key metrics:**
```
Eroded surface area (m²) = area at t₂ not at t₁
Deposited surface area (m²) = area at t₁ not at t₂
Significance assessed via MC-derived confidence intervals
```

**Citation:** Jautzy, T., Dépret, T., Piégay, H., et al. (2022). Measuring river planform changes from remotely sensed data — a Monte Carlo approach. *Earth Surface Dynamics*.

### 5.9 Active channel width / bande active metrics (Liébault & Piégay 2002)

**Description:** The French "bande active" concept measures historical changes in active channel width from time series of aerial photographs. **Normalized width (W*)** is the residual from a regional scaling law: W = a × Ad^0.44. Positive W* = transport-limited (sediment surplus); negative W* = supply-limited.

**Key metrics:**
```
Width ratio = W(later date) / W(earlier date)
Corridor envelope width = width of union of all historical bande active polygons
Normalized width W* = residual from regional W–Ad power law
```

**Citation:** Liébault, F. and Piégay, H. (2002). Causes of 20th century channel narrowing in mountain and piedmont rivers of southeastern France. *Earth Surface Processes and Landforms*, 27(4), 425–444.

---

## 6. DSAS and transect-based methods: primarily line-based but with polygon adaptations

### 6.1 USGS DSAS applied to river banklines

**Description:** The Digital Shoreline Analysis System casts perpendicular transects from a user-defined baseline and computes movement statistics where transects intersect sequential bank-line positions. Extensively applied to large rivers (Brahmaputra, Ganga, Yamuna) but fundamentally a **line-based tool** — no published study applies DSAS directly to channel envelope polygons.

**Key metrics:**
```
EPR (End Point Rate) = (d_newest − d_oldest) / (t_newest − t_oldest)  [m/yr]
NSM (Net Shoreline Movement) = d_newest − d_oldest  [m]
SCE (Shoreline Change Envelope) = max distance between any two positions
LRR (Linear Regression Rate) = slope of least-squares regression through all positions vs. time
WLR (Weighted Linear Regression Rate) = LRR weighted by positional uncertainty
```

**Data inputs:** Digitized bank-line positions (polylines) for multiple dates; user-defined baseline.

**Limitations:** Requires well-defined linear bank lines. EPR uses only two dates. LRR assumes linear trend. Not directly applicable to polygon data without conversion to boundary polylines.

**Citation:** Thieler, E.R., Himmelstoss, E.A., Zichichi, J.L., and Ergul, A. (2009). *Digital Shoreline Analysis System (DSAS) version 4.0.* USGS Open-File Report 2008-1278.

### 6.2 The Washington Toolbox bridges the gap between DSAS-style transects and polygon data

The WA Channel Migration Toolbox (Legg et al. 2014, described in §1.2 above) is the closest analogue to applying DSAS-style transects to polygon-based data. It generates transects that intersect "migration polygons" formed between sequential centerlines, measuring the width of intersection as migration distance — effectively a transect-based approach applied to polygonal migration areas rather than to individual banklines.

### 6.3 PIV-based riverbank migration (Chadwick et al. 2023)

**Description:** Applies Particle Image Velocimetry (PIV) to time series of binary channel masks. Uses an **Eulerian grid-based framework** — no centerline or bankline definition needed. Cross-correlates sub-images to track channel bank motion.

**Key metrics:**
```
PIV displacement vectors (Δx, Δy) at each grid cell
Optimal timestep: Δt ≈ Tc/8, where Tc = time for bank to migrate one channel width
Migration rate = |displacement vector| / Δt
```

**Limitations:** Requires wide channels (>8 Landsat pixels, i.e., >240 m). Cannot detect cutoff or avulsion.

**Citation:** Chadwick, A.J., Steele, S.E., Silvestre, J., and Lamb, M.P. (2023). Remote sensing of riverbank migration using particle image velocimetry. *Journal of Geophysical Research: Earth Surface*, 128, e2023JF007177.

### 6.4 RivMAP toolbox (Schwenk et al. 2017)

**Description:** MATLAB toolbox quantifying planform changes from annual binary channel masks (Landsat-derived). Computes pixel-by-pixel erosion/accretion maps, centerline migration rates via nearest-neighbor or DTW matching, and channel width along perpendicular transects.

**Key metrics:** Erosion pixels = mask(t₁) AND NOT mask(t₂); Accretion pixels = NOT mask(t₁) AND mask(t₂). Compatible with raster polygon (binary mask) inputs.

**Citation:** Schwenk, J., Khandelwal, A., Fratkin, M., Kumar, V., and Foufoula-Georgiou, E. (2017). High spatiotemporal resolution of river planform dynamics from Landsat: The RivMAP toolbox. *Earth and Space Science*, 4(2), 46–75.

---

## 7. Polygon-area-based metrics: six approaches from the literature

### 7.1 Incremental area change / eroded-area polygon method

**Description:** The polygon between two consecutive centerlines is computed via GIS overlay; its area divided by average stream length yields average lateral migration distance. Used extensively on the Sacramento River.

**Formula:**
```
Average lateral migration = Migration Polygon Area / (Polygon Perimeter / 2)
Migration Rate = Average lateral migration / Δt
Area reworked per unit channel length = ΔA / L  [m²/m/yr]
```

**Citations:**
- Larsen, E.W. and Greco, S.E. (2002). Modeling channel management impacts on river migration. *Environmental Management*, 30(2), 209–224.
- Micheli, E.R. and Larsen, E.W. (2011). River channel cutoff dynamics, Sacramento River. *River Research and Applications*, 27(3), 328–344.

### 7.2 Normalized area change (ΔA per unit reach length)

**Description:** The WA Toolbox (Tool 1) variant: area of the migration polygon divided by the valley/reach length yields average lateral migration distance. This is the simplest polygon-to-rate metric.

**Formula:**
```
Length-Averaged Migration = Polygon Area / Reach Length  [m]
Length-Averaged Migration Rate = Length-Averaged Migration / Δt  [m/yr]
```

**Citation:** Legg, N.T., Heimburg, C., Collins, B.D., and Olson, P.L. (2014). Publication 14-06-032, Washington Department of Ecology.

### 7.3 Polygon centroid shift

**Description:** Centroid of the active channel polygon (or best-fit meander circle) is computed at each time step; displacement vector between centroids indicates net direction and magnitude of channel shift.

**Formula:**
```
Centroid Displacement = √[(x₂ − x₁)² + (y₂ − y₁)²]
Centroid Migration Rate = Displacement / Δt
Direction = arctan[(y₂ − y₁) / (x₂ − x₁)]
```

**Limitations:** Captures only net translation; misses expansion, rotation, or asymmetric migration. Sensitive to planform changes (cutoffs shift centroid abruptly).

**Citation:** Lagasse, P.F. et al. (2004). NCHRP Report 533 (uses centroid of best-fit circles on meander bends).

### 7.4 Polygon overlap indices (Jaccard / IoU) — An apparent methodological gap

**Description:** Set-theoretic overlap between channel polygons at t₁ and t₂ as a dimensionless stability metric.

**Formulas:**
```
Jaccard Index:  J(A,B) = |A ∩ B| / |A ∪ B|
    J = 1: identical positions (perfect stability)
    J → 0: complete relocation (maximum instability)
Jaccard Distance:  d_J = 1 − J = |A △ B| / |A ∪ B|
Overlap Coefficient:  OC = |A ∩ B| / min(|A|, |B|)
```

**Status:** No published fluvial geomorphology study was found that explicitly names or applies the Jaccard index to channel polygon overlap. The concept is implicit in symmetric-difference analyses (Rusnák et al. 2025; RivMAP) but has **not been formally named or benchmarked** in the fluvial context. This represents a genuine methodological contribution opportunity.

### 7.5 GIS symmetric difference for erosion-deposition mapping

**Description:** Standard GIS overlay operations applied to channel polygons at two dates:

```
Intersection (A ∩ B) = stable channel area (occupied at both dates)
A − B = channel abandonment/erosion (areas at t₁ not at t₂)
B − A = channel establishment/deposition (new areas at t₂)
Symmetric Difference (A △ B) = total changed area
Union (A ∪ B) = total area occupied at either date (the HMA)
```

**Metrics:**
```
Eroded Area = Area(A) − Area(A ∩ B)
Deposited Area = Area(B) − Area(A ∩ B)
Net Change = Deposited − Eroded
Gross Change = Eroded + Deposited
```

**Citations:** Rusnák et al. (2025), Schwenk et al. (2017), Jautzy et al. (2022) — all cited above.

### 7.6 Active channel width-to-valley-width ratio over time

**Description:** The ratio of active channel width to valley-bottom width as a temporal metric, extracted from polygon geometry per DGO slice.

**Formula:**
```
Confinement Ratio = Valley Width / Channel Width
Channel Activity Ratio = Active Channel Width / Valley Width
```

**Citation:** Roux, C. et al. (2015). *Geomorphology*, 242, 29–37 (FluvialCorridor toolbox).

---

## 8. Planform change metrics adaptable to HMA polygon data

### 8.1 Migration rate directly from polygon overlay

**Description:** Overlay channel polygons from two dates; the erosion polygon (area at t₂ not at t₁) divided by the eroding bank length and time interval yields a direct migration rate. This avoids centerline extraction entirely.

**Formula:**
```
Migration Rate = Erosion Polygon Area / (Eroding Bank Length × Δt)  [m/yr]
```

**Citations:** Micheli, E.R. and Kirchner, J.W. (2002). *Earth Surface Processes and Landforms*, 27, 627–639. Also Nardi and Rinaldi (2015) and Gaeuman et al. (2003).

### 8.2 Sinuosity from polygon-derived centerlines

**Metric:** P = L_channel / L_valley, where centerline is extracted via medial axis or Voronoi skeleton from the polygon boundary. Track sinuosity change between dates. Maximum migration rates occur around **P ≈ 1.6–1.9**.

### 8.3 Braiding index from polygon data

**Metrics:**
```
Brice BI = 2 × (total bar length) / reach length
Channel-count BI = ΣL_all_channels / ΣL_main_channel
Active channel width = channel polygon area / main centerline length
```

### 8.4 Channel belt width from HMA polygons

**Description:** The HMA polygon itself IS the channel belt. Its width, measured perpendicular to the valley axis at regular intervals, is the cumulative mobility envelope. Rate of belt width growth = indicator of channel mobility.

**Key relationship:** Belt width scales with meander wavelength and channel width. For braided rivers, belt width varies systematically with discharge, slope, and grain size.

**Citation:** Limaye, A.B. (2020). How do braided rivers grow channel belts? *Journal of Geophysical Research: Earth Surface*, 125, e2020JF005570.

### 8.5 Channel activity index

**Formula:**
```
Activity = (Erosion Area + Deposition Area) / (Reach Length × Δt)  [m²/m/yr or m/yr]
```
Fraction of the channel belt reworked per unit time and length.

---

## 9. Uncertainty quantification frameworks for polygon-based measurements

### 9.1 Donovan et al. (2019) — Level of detection thresholds

**Description:** Comprehensive framework using Level of Detection (LoD) thresholds, spatially variable error estimation, and nondetect handling (Kaplan-Meier, Maximum Likelihood Estimation). Key finding: **long-term migration rates systematically underestimate short-term rates by 2–15%** at 50-year intervals due to channel reversals.

**Citation:** Donovan, M., Belmont, P., Notebaert, B., et al. (2019). Accounting for uncertainty in remotely-sensed measurements of river planform change. *Earth-Science Reviews*, 193, 220–243.

### 9.2 Lea & Legleiter (2016) — Spatially variable error ellipses

**Description:** Leave-one-out cross-validation of GCPs generates error ellipses at each measurement location. Migration vectors must exceed local error ellipses to be statistically significant. Improved detection of significant migration from **24% (RMSE method) to 33% (spatially variable method)**.

**Citation:** Lea, D.M. and Legleiter, C.J. (2016). Refining measurements of lateral channel movement from image time series. *Geomorphology*, 258, 11–20.

---

## 10. Empirical relationships between migration rates and hydraulic variables

### 10.1 Curvature–migration relationship (Hickin & Nanson 1984)

**The foundational empirical relationship:** Peak migration rates occur at **Rc/W ≈ 2.5–3.0** (radius of curvature to width ratio), based on 189 bends on 21 rivers in Western Canada.

**Core model:**
```
M = Ω / (Yb × Hb) × f(Rc/W)
```
Where M = lateral migration rate, **Ω = specific stream power (γQS/W)**, Yb = bank material resistance coefficient, Hb = outer bank height, f(Rc/W) = curvature function peaking at Rc/W ≈ 2.5.

**Stream power explains ~52% of migration rate variance.**

**Citations:**
- Hickin, E.J. and Nanson, G.C. (1984). Lateral migration rates of river bends. *Journal of Hydraulic Engineering*, ASCE, 110(11), 1557–1567.
- Nanson, G.C. and Hickin, E.J. (1986). A statistical analysis of bank erosion and channel migration in western Canada. *GSA Bulletin*, 97(4), 497–504.

**Note:** Sylvester et al. (2019, *Geology*) have argued the decline at low Rc/W may be a statistical artifact of averaging; the relationship may actually be quasi-linear.

### 10.2 Erodibility coefficient framework (Micheli & Kirchner 2002; Constantine et al. 2009)

**Formula:**
```
M = E × Δu = E × (u_b − U_s)
```
Where E = bank erodibility coefficient, u_b = near-bank velocity, U_s = cross-section average velocity.

**Key findings:** Wet meadow banks erode **~6× slower** than dry meadow banks. Riparian forest reduces migration rates significantly compared to agricultural land. Constantine et al. (2009) showed that the jet-test erodibility coefficient (k) from the excess shear stress equation (ε = k(τ − τc)) explains much of the variability in E.

**Citations:**
- Micheli, E.R. and Kirchner, J.W. (2002). *Earth Surface Processes and Landforms*, 27, 627–639.
- Constantine, C.R., Dunne, T., and Hanson, G.J. (2009). *Geomorphology*, 106(3-4), 242–257.

### 10.3 Cumulative effective stream power (Larsen et al. 2006) — The strongest polygon–hydrology link

**Description:** The most robust published empirical relationship linking hydrological forcing to polygon-derived erosion. Bank erosion area (from polygon overlay) is correlated with cumulative stream power above a threshold discharge.

**Formula:**
```
Πi = Σ(γQiS) for all days where Qi > Q_threshold
Π_scaled = Πi / Π_mean  (dimensionless annual flow scaling factor)
```
For the Sacramento River: Q_threshold ≈ 425 m³/s (~2-year recurrence). **r² = 0.74, p = 0.02** for observed erosion rate vs. cumulative effective stream power.

**Citation:** Larsen, E.W., Fremier, A.K., and Greco, S.E. (2006). Cumulative effective stream power and bank erosion on the Sacramento River. *Journal of the American Water Resources Association*, 42(4), 1077–1097.

### 10.4 Stream power–migration statistical analysis (Richard et al. 2005)

**Description:** Analysis of the Rio Grande below Cochiti Dam (1918–2001) using digitized active channel polygons. Migration rates correlated with total stream power (QS) at **R² > 0.50**, improving to **R² > 0.60** with channel width as a second variable. An exponential equilibrium model explained **78–90%** of variance in migration rates.

**Key finding:** A **mobility index** (ratio of total channel width to equilibrium width) predicts migration rates.

**Citations:**
- Richard, G.A., Julien, P.Y., and Baird, D.C. (2005). Statistical analysis of lateral migration of the Rio Grande. *Geomorphology*, 71(1-2), 139–155.
- Richard, G.A., Julien, P.Y., and Baird, D.C. (2005). Case study: Modeling lateral mobility of the Rio Grande. *Journal of Hydraulic Engineering*, 131(11), 931–941.

### 10.5 Sediment supply as a driver (Constantine et al. 2014)

**Finding:** Rivers with higher suspended sediment concentrations experience higher annual migration rates (Amazon Basin, 20 reaches, Landsat 1985–2013). Cutoff rates scale exponentially with migration rates.

**Citation:** Constantine, J.A., Dunne, T., Ahmed, J., Legleiter, C.J., and Lazarus, E.D. (2014). Sediment supply as a driver of river meandering. *Nature Geoscience*, 7(12), 899–903.

### 10.6 Curvature–migration convolution (Güneralp & Rhoads 2008, 2009)

**Description:** Digital signal processing framework analyzing the spatial convolution function relating planform curvature to migration rate. Migration at any point is a weighted sum of upstream curvature:
```
ζ[τ] = Σ_j (w[j] × C*[τ − j])
```
Where ζ = migration rate at point τ, C* = curvature, w[j] = weighting function (exponential decay or damped oscillatory).

**Limitations:** Requires centerline data; focused on single-thread meandering channels.

**Citations:**
- Güneralp, İ. and Rhoads, B.L. (2008). Continuous characterization of the planform geometry and curvature of meandering rivers. *Geographical Analysis*, 40(1), 1–25.
- Güneralp, İ. and Rhoads, B.L. (2009). Empirical analysis of the planform curvature-migration relation. *Water Resources Research*, 45, W09424.

---

## Summary comparison of all polygon-compatible methods

| Method | Core metric | Formula | Polygon-native? | Key citation |
|--------|------------|---------|-----------------|-------------|
| WA Toolbox reach-average | Area ÷ length ÷ time | M = A_polygon / (L × Δt) | **Yes** | Legg et al. 2014 |
| WA Toolbox transect | Width of polygon at transect | M = w_transect / Δt | **Yes** | Legg et al. 2014 |
| Eroded-area polygon | Area ÷ bank length ÷ time | M = A_erosion / (L_bank × Δt) | **Yes** | Larsen & Greco 2002 |
| GIS symmetric difference | Erosion/deposition areas | A△B decomposition | **Yes** | Rusnák et al. 2025 |
| FluvialCorridor DGO slicing | Width per longitudinal slice | W = A_slice / L_centerline | **Yes** | Roux et al. 2015 |
| SCS Toolbox | Erosion area + direction | Automated polygon overlay | **Yes** | Rusnák et al. 2025 |
| Monte Carlo surficial | Area change with uncertainty | MC-propagated ΔA | **Yes** | Jautzy et al. 2022 |
| Centroid shift | Centroid displacement | d = √(Δx² + Δy²) | **Yes** | Lagasse et al. 2004 |
| Jaccard/IoU overlap | Stability index | J = \|A∩B\| / \|A∪B\| | **Yes** | *Not yet published for rivers* |
| PIV on binary masks | Displacement vectors | Cross-correlation | **Yes** (raster) | Chadwick et al. 2023 |
| RivMAP pixel comparison | Erosion/accretion pixels | Binary mask difference | **Yes** (raster) | Schwenk et al. 2017 |
| DSAS (EPR, LRR) | Rate at transects | d/Δt regression | No (line-based) | Thieler et al. 2009 |
| NCHRP 533 circle-fit | Centroid + radius change | Best-fit circle tracking | Partially | Lagasse et al. 2004 |
| Hickin–Nanson curvature | M vs. Rc/W | M = f(Ω, Yb, Hb, Rc/W) | Adaptable | Hickin & Nanson 1984 |
| Cum. effective stream power | Erosion vs. Σ(γQS) | Πi = Σ(γQiS) for Q > Qt | Via polygon erosion areas | Larsen et al. 2006 |

---

## Conclusion: the polygon-based toolkit is maturing rapidly

The literature reveals a clear methodological trajectory from qualitative overlay comparison toward rigorous, uncertainty-quantified polygon-based analytics. **Three operational GIS toolboxes** now exist for polygon-native channel change analysis: the Washington Channel Migration Toolbox (Legg et al. 2014), FluvialCorridor (Roux et al. 2015), and the Standalone Channel Shifting Toolbox (Rusnák et al. 2025). The simplest and most widely used polygon-to-rate conversion remains **area ÷ length ÷ time**, but the Alber & Piégay (2011) DGO disaggregation framework enables spatially distributed metrics along the reach without requiring transect generation.

Two genuine gaps emerge. First, **formal overlap indices** (Jaccard, IoU) applied to channel polygons as stability metrics are conceptually sound but absent from the published fluvial literature. Second, the Monte Carlo uncertainty frameworks (Jautzy et al. 2022; Donovan et al. 2019) have been demonstrated but are not yet integrated into standard CMZ practice. The strongest empirical bridge between polygon-derived migration and hydraulic forcing is **cumulative effective stream power** (Larsen et al. 2006), which explains 74% of migration variance on the Sacramento River using exactly the kind of polygon-overlay erosion measurements that HMA data products provide. Colorado's explicit rejection of rate-based methods in favor of geomorphic interpretation represents a philosophically distinct approach — one that prioritizes capturing all fluvial hazards over precise rate quantification, but at the cost of losing predictive temporal horizons.