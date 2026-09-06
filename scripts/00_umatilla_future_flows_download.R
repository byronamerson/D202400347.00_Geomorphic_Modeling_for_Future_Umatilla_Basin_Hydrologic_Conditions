# =============================================================================
# 00_umatilla_future_flows_download.R
# Geomorphic Modeling for Future Umatilla Basin Hydrologic Conditions
# Phase 0: Raw acquisition of RMJOC-II projected streamflow (UMAMC node)
# =============================================================================
#
# Purpose: Download the University of Washington (RMJOC-II) projected daily
#          streamflow files for the Umatilla River UMAMC routing node
#          (at/near Pendleton) into the project's data_in directory, as-is.
#          No parsing, reshaping, or consolidation -- just a faithful mirror
#          of the posted files for ingestion later in the analysis workflow.
#
# Scope:
#   - Mirrors https://data.cig.uw.edu/picea/RMJOCII/pub/UMAMC/streamflow/
#   - All files matching the target pattern (default: *.csv, ~178 files)
#   - Skips files already present (resume-friendly); optional overwrite
#   - Writes a download manifest for provenance / QA
#
# Not in scope:
#   - Reading, validating, or combining the CSVs
#   - Any transformation into .xlsx or other consolidated products
#
# Usage:   Edit the CONFIG section below, then either:
#            (a) source() and call run_future_flows_download(config)
#            (b) step through interactively with the functions below
#
# Output:  config$output_dir (default data_in/Umatilla_Future_Flows/):
#            <the mirrored *.csv files>
#            _download_manifest.csv   (one row per file: url, bytes, status)
#
# Notes:
#   - The source is an Apache auto-index. We scrape the live index for the
#     actual posted file list rather than generating names from the factor
#     grid, because not every GCM x scenario x downscaling x hydro x partition
#     combination exists (e.g. DYNAMICAL is RCP85-only; PRMS is P1-only).
#   - Base R libcurl is used for both the index read and the downloads: no
#     scraping library required, and the link extraction is a single, readable
#     regex you can inspect and adjust.
#   - options(timeout=) is raised because ~1 MB files over a slow link can
#     exceed R's 60 s default.
# =============================================================================

library(tidyverse)


# =============================================================================
# CONFIG
# =============================================================================

config <- list(

  # ---- Source ----
  base_url = "https://data.cig.uw.edu/picea/RMJOCII/pub/UMAMC/streamflow/",

  # Which posted files to mirror. Default grabs every .csv. To pull a subset
  # later, tighten this regex (e.g. "_VIC_.*\\.csv$" for VIC only).
  file_pattern = "\\.csv$",

  # ---- Destination ----
  output_dir = here::here("data_in", "Umatilla_Future_Flows"),

  # ---- Behavior ----
  overwrite     = FALSE,  # FALSE = skip files already downloaded (resume)
  pause_sec     = 0.2,    # brief courtesy pause between requests
  timeout_sec   = 600,    # per-file download timeout
  write_manifest = TRUE
)


# =============================================================================
# FUNCTIONS
# =============================================================================

# ---- Discover the posted files -------------------------------------------------
# Reads the Apache directory index and returns a tibble of file name + full URL
# for every link matching `pattern`. Apache sort links (?C=N;O=D) and the parent
# directory link are excluded by the pattern and the anchor filter.
list_remote_files <- function(base_url, pattern = "\\.csv$") {

  html <- paste(readLines(url(base_url, method = "libcurl"), warn = FALSE),
                collapse = "\n")

  # Pull the target of every <a href="...">
  hrefs <- str_match_all(html, 'href="([^"]+)"')[[1]][, 2]

  files <- hrefs |>
    unique() |>
    # keep only the ones that look like the files we want
    keep(~ str_detect(.x, pattern)) |>
    # drop absolute paths / parent links; we only want plain file names here
    keep(~ !str_detect(.x, "^(/|\\?|https?://)"))

  tibble(
    file = files,
    url  = paste0(str_remove(base_url, "/$"), "/", files)
  )
}

# ---- Download a single file ----------------------------------------------------
# Returns a one-row manifest tibble describing the outcome.
download_one <- function(file, url, dest_dir, overwrite = FALSE) {

  dest <- file.path(dest_dir, file)

  if (file.exists(dest) && !overwrite) {
    return(tibble(
      file, url, dest,
      status = "skipped_exists",
      bytes  = file.info(dest)$size,
      time   = Sys.time()
    ))
  }

  result <- tryCatch({
    download.file(url, destfile = dest, mode = "wb",
                  method = "libcurl", quiet = TRUE)
    "downloaded"
  }, error = function(e) paste0("error: ", conditionMessage(e)))

  tibble(
    file, url, dest,
    status = result,
    bytes  = if (file.exists(dest)) file.info(dest)$size else NA_real_,
    time   = Sys.time()
  )
}

# ---- Orchestrator --------------------------------------------------------------
run_future_flows_download <- function(config) {

  dir.create(config$output_dir, showWarnings = FALSE, recursive = TRUE)

  old_timeout <- getOption("timeout")
  options(timeout = config$timeout_sec)
  on.exit(options(timeout = old_timeout), add = TRUE)

  message("Reading index: ", config$base_url)
  remote <- list_remote_files(config$base_url, config$file_pattern)
  message("Found ", nrow(remote), " matching file(s).")

  if (nrow(remote) == 0) {
    warning("No files matched. Check base_url / file_pattern.")
    return(invisible(tibble()))
  }

  manifest <- vector("list", nrow(remote))
  for (i in seq_len(nrow(remote))) {
    message(sprintf("[%3d/%3d] %s", i, nrow(remote), remote$file[i]))
    manifest[[i]] <- download_one(
      remote$file[i], remote$url[i],
      dest_dir  = config$output_dir,
      overwrite = config$overwrite
    )
    if (config$pause_sec > 0) Sys.sleep(config$pause_sec)
  }
  manifest <- bind_rows(manifest)

  # ---- Summary ----
  message("\n--- Summary ---")
  manifest |>
    count(status) |>
    pwalk(function(status, n) message(sprintf("  %-16s %d", status, n)))

  errors <- manifest |> filter(str_starts(status, "error"))
  if (nrow(errors) > 0) {
    message("\n", nrow(errors), " file(s) failed -- re-run to retry ",
            "(successful files are skipped):")
    walk(errors$file, ~ message("  ", .x))
  }

  if (isTRUE(config$write_manifest)) {
    manifest_path <- file.path(config$output_dir, "_download_manifest.csv")
    write_csv(manifest, manifest_path)
    message("\nManifest written: ", manifest_path)
  }

  invisible(manifest)
}


# =============================================================================
# RUN
# =============================================================================
# Uncomment to run on source(), or call run_future_flows_download(config)
# interactively after sourcing.

manifest <- run_future_flows_download(config)
