# NOTE — Valley bottom / effective valley bottom geometry (confinement-ratio numerator)

**Date:** 2026-09-17
**Scope:** Confinement-ratio covariate work (`scripts/spatial_geology_import.R`,
`scripts/spatial_valley_bottom.R`, `scripts/spatial_effective_valley_bottom.R`,
`scripts/spatial_confinement_ratio.R`, and their matching `_plot.R` QA scripts). Feeds
`NOTE_confinement_ratio_exploration.md` (Project notes).
**Decision:** Build the valley-bottom numerator from the USGS surficial geology map (SIM 3527),
not DOGAMI's EHA/erosion-rate products (rejected earlier — see `NOTE_confinement_ratio_exploration.md`
for the circularity concern). Keep the natural and the confining-feature-truncated versions as
separate, both-retained objects; truncate at confining features by cutting and keeping the
channel-side fragment, not by subtracting their footprint.

## Data

USGS surficial geology, `data_in/USGS_umatilla_surficial_geology/GeMS_shapefiles/` (GeMS schema:
shapefiles carry a DBF-limited field subset, full attributes in companion CSVs joined by
`OBJECTID`). Native CRS EPSG:26911; reprojected to **EPSG:6557** (NAD83(2011) Oregon GIC
Lambert, ft) to match the DOGAMI CMZ geodatabase (`Umatilla_River_CMZ`/`_AC`/`_HMA`, all
EPSG:6557). Map covers the full CMZ study area, so all of RS 28–37 is in scope.

## Unit selection

- **Contemporary valley bottom** (the natural footprint): `w, ch, vb0, vb1, vb2, vb3, pc`.
  `vb4` excluded (too high in elevation, not expected in RS 28–39). Terraces (`tr`) excluded —
  contemporary valley bottom only, not the Pleistocene-Holocene former valley floor.
- **Confining features** (roads/rail/levees that can bound or redirect lateral migration):
  `m` (roadbed/rail bed — a substantial berm in many reaches, not a negligible thin ribbon),
  `a` (artificial fill), `lv` (levees/levee remnants). Field narrative behind this: Union
  Pacific rail south of the river through RS 28/29, levees north of it (built post-1964 flood,
  no river contact since ~1960s); river has broken through/cut up the levees around RS 30;
  rail crosses the river at RS 32 and again at RS 34; Cayuse road + rail bound the river to the
  south from RS 34 to the Meacham Creek confluence (RS 37/38).

## Why two valley-bottom objects, not one

Dissolving only the valley-bottom units leaves gaps wherever a confining feature runs through
the corridor (coded as a different unit), and produces a multipart, holey polygon. Two objects
are built, and the first is never overwritten by the second:

- `contemporary_valley_bottom` — the raw dissolve, with only interior holes closed
  (`nngeo::st_remove_holes()`, `max_area = 0`). Still multipart wherever a confining feature
  fully crosses the corridor. Kept on its own — it's the clearest way to see how those features
  break up the floodplain, independent of any confinement analysis.
- `contemporary_valley_bottom_closed` — the same polygon, morphologically **closed**:
  `st_buffer(x, d) %>% st_buffer(-d)`. The outward pass bridges any gap narrower than `2d` and
  fills holes up to that width (swallowing the confining feature); the inward pass returns the
  boundary close to its original position. `d` = `config$bridge_buffer_dist_ft`, tuned
  interactively by visual QA in `ggplotly` — 40 ft and 100 ft still left visible openings; **500
  ft** closed the corridor into one contiguous polygon. This is a pragmatic, tuned parameter,
  not derived from measured feature widths — if it starts rounding off real valley-bottom edges
  (rather than just bridging crossings), it should be revisited, possibly per-reach rather than
  as one global constant.

## Effective valley bottom: truncate-at-wall, not subtract-the-footprint

Two ways to use the confining-feature dissolve were considered:

- **Subtract the footprint** — remove only the roadbed/levee ground itself from the valley
  bottom. Simple, but doesn't shrink the corridor beyond the feature; a levee sitting mid-valley
  would just punch a footprint-shaped hole, not narrow the effective width.
- **Truncate at the wall** (chosen) — treat the confining feature as an effective valley wall:
  where it crosses the corridor, cut there and keep only the channel side.

Implementation (`truncate_at_confining_features()`, `scripts/spatial_effective_valley_bottom.R`):

```r
remainder <- valley_bottom %>%
  st_difference(st_union(confining_features)) %>%
  st_make_valid()

parts <- remainder %>% st_geometry() %>% st_cast("POLYGON") %>% st_sf(geometry = .)
touches_channel <- lengths(st_intersects(parts, channel)) > 0
effective <- parts[touches_channel, ] %>% st_union() %>% st_sf(geometry = .)
```

Differencing the confining-feature footprint out of the valley bottom both removes that ground
and, wherever the feature fully crosses the corridor, splits the remainder into separate
polygon parts. Keeping only the part(s) that intersect the active channel (`Umatilla_River_AC`,
read directly from the DOGAMI gdb — first use of that layer in this script family) selects the
channel-side piece. **This makes the nearest confining feature "win" as the wall without any
explicit distance comparison**: where multiple features stand between the channel and the true
valley wall, only the one immediately adjacent to the channel actually separates the
channel-touching fragment from the rest; anything farther out is carried along with the
discarded far-side fragment.

Differencing/casting can leave the channel-side fragment multipart or notched at partial
crossings, so `effective_valley_bottom` re-applies the same buffer-closing step used for
`contemporary_valley_bottom_closed` (currently reusing the same 500 ft distance —
`config$effective_bridge_buffer_dist_ft` is a separate config value in case this step needs its
own tuning).

## Result (visual, not yet quantified)

Byron's review of the `ggplotly` output: **RS 27 and 28 come out very constrained** once
truncated at the confining features — "that'll affect things for sure." Consistent with the
field narrative above (rail south of the river, post-1964 levees) and with RS 25–27 already
being excluded from the `m_B2` migration model on levee/mechanical-preclusion grounds
(`NOTE_confined_reach_exclusion.md`). RS 27 is outside the modeled RS 28–37 scope so was never
quantified numerically (it's already excluded from `m_B2` entirely); RS 28 was — see below.

## Width conversion and channel-width denominator — decided (2026-09-17, continued)

Both open items above are resolved, discussed before coding per `lingua.md`:

- **Width conversion: area ÷ `length_ft`, for every width in this workflow** — not a
  transect-based measurement. Same `reach_attributes.csv` `length_ft` column already used for
  `new_area_per_ft` elsewhere, kept as the single length denominator so the valley-bottom and
  channel widths are on a consistent, simple, trackable basis (Byron's standing preference:
  simplest effective method with basic assumptions over analytical complexity).
- **Channel-width denominator: median clipped active-channel area across dated HMA years ÷
  `length_ft`** — not DOGAMI's `avg_width_ft` (a single, vintage-unstated value) and not a new
  active-channel layer. Reuses `clip_dated_hma_to_segment()` / `summarize_segment_hma_years()`
  as already built for the interval-metrics pipeline (composite/merged polygon excluded, same
  as everywhere else); median rather than mean so one anomalous year doesn't set a reach's
  channel width single-handedly. (See the trending-reach caveat below — this choice has a real
  limitation for RS 30.)
- **Per-RS clipping for both valley-bottom variants: `select_cmz_segment()`** — the same DOGAMI
  CMZ per-RS boundary already used to bound HMA polygons per reach. Whether the CMZ polygon's
  lateral extent could cap the *contemporary* (unconstrained) variant's true width was raised
  and explicitly set aside (Byron): the valley-bottom geometry is USGS-mapped and independent
  of DOGAMI's CMZ/EHA products, so this is not the EHA-circularity concern already put to bed
  above — not worth chasing further.
- Implemented in `scripts/spatial_confinement_ratio.R` (sources this script family plus
  `rs30_interval_sandbox.R` for the HMA-clipping helpers, per the existing reuse pattern in
  `06_multireach_interval_metrics.R`). Writes `data/confinement_ratio.csv`, one row per RS
  28–37: both raw areas, all three widths, and both ratio variants
  (`confinement_ratio_contemporary`, `confinement_ratio_constrained`).

## Result (quantified, 2026-09-17 continued further) — script run, RS 29 checked, RS 30 flagged

`scripts/spatial_confinement_ratio.R` ran successfully (after a stale-commit snag — see below)
and produced `data/confinement_ratio.csv` (RS 28–37) plus a new diagnostic output,
`data/channel_area_by_rs_year.csv`.

**Debugging note, for the record:** the first attempt to re-run the script after adding the
per-year diagnostic threw `unused arguments (hma = hma, composite_note = config$composite_note)`.
Root cause: a `device_commit_files` write to Byron's repo silently only partially applied — the
helper functions updated on disk, but the BUILD section's call site stayed on the old signature,
producing an internally inconsistent file. Re-committing with `force = true` and then reading
the file straight back off Byron's machine (not trusting the write confirmation alone) confirmed
the fix. **Practice going forward: verify any remote commit that changes a function signature or
call site by reading the file back from the device, not just checking the write result.**

Byron flagged `confinement_ratio_contemporary` for RS 29 (20.1) as surprisingly high vs. RS 30
(8.4), given RS 30 has the largest raw HMA/valley-bottom area of the ten reaches. Checked with
the mean-vs-median channel width by RS from the new per-year diagnostic:

- **RS 29 is genuinely the narrowest channel of the ten reaches, by both mean (168 ft) and
  median (153 ft)** — not a median-specific artifact. The high ratio reflects a real
  wide-valley/narrow-channel combination, not a calculation error. (RS 30's raw valley-bottom
  area is larger in absolute terms, but its channel is proportionally just as wide, so its ratio
  comes out modest — the mechanics check out.)
- **RS 30 shows a strong secular widening trend, not a stable width to summarize with one
  number**: 256–296 ft in the 1950s–60s to 610–619 ft in 2020–2022, more than doubling over the
  71-year record. Mean (434 ft) and median (438 ft) nearly coincide there, but only because the
  trend is roughly linear — not because the value is stable. A whole-record median treats a
  channel that has been steadily widening as if it had one representative width throughout. RS
  28 and 36 show a gentler version of the same pattern; most other reaches (29, 31–35, 37) look
  like noise around a stable value rather than a trend.

## Open items

- Decide whether the whole-record median channel width is acceptable as-is for trending reaches
  (RS 30 especially, RS 28/36 to a lesser degree), or whether those reaches need a
  differently-computed channel width (e.g. a recent-years window) before the LMM precheck.
- Precheck `confinement_ratio_contemporary` and `confinement_ratio_constrained` against `m_B2`'s
  per-reach BLUP slope, mirroring `07c_gradient_interaction.R`'s structure — deferred to a later
  session per Byron's scoping (this session is CSV-only, no LMM work).
- `confining_features` (the raw `m, a, lv` dissolve) is intentionally left as a standalone,
  reusable object — not consumed or modified by the truncation step — for any later use (e.g.
  further m/a/lv-vs-channel overlay work).
