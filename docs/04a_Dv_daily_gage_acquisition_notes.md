# 04a Dv Daily Gage Acquisition Notes

## Purpose

This note summarizes the work completed in the session that started the
`04x_Dv_` daily-values script series, with the immediate focus on
`scripts/04a_Dv_daily_gage_acquisition.R`.

The goal of the script is to support the Pendleton daily-extension workflow by:

- documenting the daily-value period of record for the target USGS gage network
- pulling the full available daily mean discharge record for each target gage
- organizing those data into tidy project tables for later daily-extension work

## Key decisions made in this session

### 1. The `01` series is reference material, not a template to copy blindly

We reviewed the existing `01` scripts, especially:

- `scripts/01_hydrology_acquisition.R`
- `scripts/01b_mckay_creek_acquisition.R`
- `scripts/01c_regulation_correction.R`

The decision was to stay flexible. The `01` scripts provide useful patterns,
but the `04x_Dv_` series should follow the work being done in the daily-values
workflow rather than forcing the new scripts into the old structure.

### 2. Package docs were read before implementation

Before drafting or implementing the new script, the relevant package docs were
re-read, including:

- `dataRetrieval::readNWISdv()`
- `dataRetrieval::readNWISsite()`
- `dataRetrieval::renameNWISColumns()`
- `dataRetrieval::whatNWISdata()`
- `readr::write_csv()`

This was done explicitly to comply with the repo guidance in `docs/lingua.md`
and `docs/r-principles.md`: do not guess package APIs.

### 3. `04a` should stay narrow in scope

The first `04x_Dv_` script should do only the daily-value acquisition job.

In scope:

- discover USGS daily-value availability
- pull daily mean discharge for the target gages
- pull site metadata needed for documentation and QA
- build tidy output tables

Out of scope for `04a`:

- flood-frequency analysis
- threshold metrics
- water-year summaries
- McKay regulation correction
- modeling

### 4. The script should support both orchestrated and interactive use

The final orchestrator is still acceptable, but the script should not force a
single all-at-once workflow.

The decision was to support two modes clearly:

- an orchestrator for convenience
- a serial, stepwise interactive section where each stage can be run one at a
  time and inspected before proceeding

### 5. Each helper should be standalone

The script was intentionally shaped so helper functions:

- take explicit inputs
- do not depend on hidden global objects
- do not reach into `config` unless they are themselves orchestrator-level code
- keep I/O at the boundary where practical

This was done to stay aligned with:

- `docs/lingua.md`
- `docs/r-principles.md`
- `docs/skills/r-dev/SKILL.md`

## Files and docs reviewed in the session

### Project docs

- `docs/daily_extension_strategy.md`
- `docs/hma_interval_metrics_codex_brief.md`
- `docs/interval_adjustment_modeling_notes.md`
- `docs/codex_migration_pipeline_brief.md`
- `docs/lingua.md`
- `docs/r-principles.md`
- `docs/contract-first-development.md`
- `docs/skills/r-dev/SKILL.md`

### Existing scripts reviewed

- `scripts/01_hydrology_acquisition.R`
- `scripts/01b_mckay_creek_acquisition.R`
- `scripts/01c_regulation_correction.R`

## Work completed in `scripts/04a_Dv_daily_gage_acquisition.R`

### Scaffold drafted

The script was created with:

- a file header that defines purpose, scope, non-goals, outputs, and usage
- a `config` block for the three main gages
- boundary contracts for each function
- an orchestrator scaffold
- an interactive stepwise run section

### Interactive section improved

The scaffold was revised so the interactive section is more copy-run-ready.
It now includes:

- a simple unpacking step for `config` pieces
- numbered step blocks
- stable intermediate object names
- explicit inspection points before moving on
- a clearly separated final write step

### Functions implemented so far

The following functions were implemented:

#### `discover_daily_value_availability()`

Purpose:

- query NWIS metadata for the configured gage set
- retain only daily-value records relevant to this workflow

Current behavior:

- validates boundary inputs
- calls `whatNWISdata()` for each gage
- filters to daily values for the requested parameter and statistic
- returns a tidy availability table

#### `pull_site_metadata()`

Purpose:

- retrieve the site metadata for one USGS gage

Current behavior:

- validates boundary inputs
- calls `readNWISsite()`
- returns a selected, standardized subset of site fields

#### `attach_gage_labels_to_availability()`

Purpose:

- join project gage labels onto the availability table

Current behavior:

- validates inputs
- performs a pure in-memory join using `gage_id`

#### `attach_gage_labels_to_site_info()`

Purpose:

- join project gage labels onto the site metadata table

Current behavior:

- validates inputs
- performs a pure in-memory join using `gage_id`

## Functions still scaffolded only

The following functions still exist as contracts/placeholders:

- `pull_daily_values_for_gage()`
- `attach_gage_labels_to_daily_flows()`
- `build_daily_value_results()`
- `build_daily_value_record_summary()`
- `write_daily_value_outputs()`
- `run_dv_daily_gage_acquisition()`

## Current assumptions and caveats

- The current `04a` target gage list is the three main project gages:
  - `14020000`
  - `14020850`
  - `14033500`
- No R code was executed for testing during this session.
- The implemented functions were written against the reviewed package docs, but
  they have not yet been run in the live session.
- The next session should verify the `whatNWISdata()` call behavior first,
  because that function uses `...` and is more flexible than the simpler NWIS
  wrappers.

## Recommended next steps for the next session

The most natural next steps are:

1. Inspect and, if needed, lightly refine the current implementations of:
   - `discover_daily_value_availability()`
   - `pull_site_metadata()`
2. Implement `pull_daily_values_for_gage()`
3. Implement the remaining pure helpers:
   - `attach_gage_labels_to_daily_flows()`
   - `build_daily_value_record_summary()`
4. Implement `build_daily_value_results()`
5. Leave `write_daily_value_outputs()` and the orchestrator for last

## Primary file produced in this session

- `scripts/04a_Dv_daily_gage_acquisition.R`
