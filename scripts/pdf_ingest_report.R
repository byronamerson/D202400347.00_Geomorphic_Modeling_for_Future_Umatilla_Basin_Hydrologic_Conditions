# =============================================================================
# pdf_ingest_report.R
# PDF Ingestion Utility For DOGAMI-Style Reports
# =============================================================================
#
# Purpose: Read a report PDF once, extract durable text artifacts, index key
#          terms, and generate a first-pass markdown notes file that can be
#          refined by hand.
#
# Specifically:
#   1. Collect basic PDF metadata and table of contents when available
#   2. Extract text for every page in the PDF
#   3. Normalize page text enough for search and readable storage
#   4. Index domain terms such as HMA, CMZ, EHA, AHA, flagged, and river segment
#   5. Write machine-derived artifacts into a report-specific daughter folder
#   6. Generate or refresh a human-facing notes file
#
# Inputs:
#   - docs/O-25-10_report_Dec23.pdf
#
# Outputs:
#   - docs/derived/O-25-10_report_Dec23/pdf_info.json
#   - docs/derived/O-25-10_report_Dec23/toc.json
#   - docs/derived/O-25-10_report_Dec23/pages.csv
#   - docs/derived/O-25-10_report_Dec23/keyword_hits.csv
#   - docs/derived/O-25-10_report_Dec23/page_text.md
#   - docs/O-25-10_report_Dec23_notes.md
#
# Style: Utility script for rough-and-ready report ingestion
# =============================================================================

library(pdftools)
library(pdfsearch)
library(dplyr)
library(purrr)
library(readr)
library(stringr)
library(tibble)
library(jsonlite)
library(fs)
library(glue)

config <- list(
  pdf_path = "docs/O-25-10_report_Dec23.pdf",
  slug = "O-25-10_report_Dec23",
  notes_path = "docs/O-25-10_report_Dec23_notes.md",
  derived_dir = "docs/derived/O-25-10_report_Dec23",
  keywords = c(
    "HMA",
    "CMZ",
    "EHA",
    "AHA",
    "flagged",
    "river segment",
    "study area",
    "methods",
    "aerial imagery",
    "active channel",
    "avulsion"
  )
)

#' Ingest a report PDF into reusable text artifacts and a first-pass notes file.
#'
#' @param cfg A named list containing the source PDF path, report slug, notes
#'   path, derived output directory, and keyword vector.
#'
#' @return A named list containing metadata, table of contents, page text,
#'   keyword hits, and output paths written to disk.
#'
#' @details
#' This is the top-level orchestrator for rough-and-ready PDF ingestion.
#' It reads the report once, preserves page-level provenance, and writes
#' machine-derived artifacts into a report-specific daughter folder under
#' `docs/derived/`. It also generates a human-facing markdown notes file that
#' summarizes the structure of the report and points back to the derived files.
#'
#' The workflow assumes text is extractable with `pdftools`. It does not attempt
#' figure or table ingestion beyond preserving any text that appears on those
#' pages. If extraction quality is poor on some pages, those issues are surfaced
#' in the page text artifacts and can be handled later.
ingest_pdf_report <- function(cfg) {
  validate_pdf_ingest_config(cfg)

  ensure_output_dirs(cfg)

  pdf_meta <- collect_pdf_metadata(cfg$pdf_path)
  page_tbl <- extract_pdf_pages(cfg$pdf_path)
  keyword_hits <- search_keywords_in_pdf(cfg$pdf_path, cfg$keywords)

  page_tbl <- annotate_keyword_presence(page_tbl)
  notes_md <- build_notes_markdown(cfg, pdf_meta, page_tbl, keyword_hits)
  page_text_md <- build_page_text_markdown(cfg, page_tbl)

  output_paths <- write_ingest_outputs(
    cfg = cfg,
    pdf_meta = pdf_meta,
    page_tbl = page_tbl,
    keyword_hits = keyword_hits,
    page_text_md = page_text_md,
    notes_md = notes_md
  )

  list(
    pdf_meta = pdf_meta,
    page_tbl = page_tbl,
    keyword_hits = keyword_hits,
    output_paths = output_paths
  )
}

#' Validate the configuration for PDF ingestion.
#'
#' @param cfg A named list used by `ingest_pdf_report()`.
#'
#' @return Invisible `TRUE`. Throws an error if required fields are missing or
#'   invalid.
#'
#' @details
#' Validation happens once at the boundary so internal helpers can assume they
#' receive a complete, coherent config. This helper only checks the pieces that
#' must be correct for the pipeline to run: source PDF existence, required paths,
#' and a non-empty keyword vector.
validate_pdf_ingest_config <- function(cfg) {
  required_names <- c("pdf_path", "slug", "notes_path", "derived_dir", "keywords")

  missing_names <- setdiff(required_names, names(cfg))
  if (length(missing_names) > 0) {
    stop("Config is missing required fields: ", paste(missing_names, collapse = ", "))
  }

  if (!file.exists(cfg$pdf_path)) {
    stop("PDF file does not exist: ", cfg$pdf_path)
  }

  if (!is.character(cfg$slug) || length(cfg$slug) != 1L || cfg$slug == "") {
    stop("`slug` must be a single non-empty string.")
  }

  if (!is.character(cfg$notes_path) || length(cfg$notes_path) != 1L) {
    stop("`notes_path` must be a single string.")
  }

  if (!is.character(cfg$derived_dir) || length(cfg$derived_dir) != 1L) {
    stop("`derived_dir` must be a single string.")
  }

  if (!is.character(cfg$keywords) || length(cfg$keywords) < 1L) {
    stop("`keywords` must be a non-empty character vector.")
  }

  invisible(TRUE)
}

ensure_output_dirs <- function(cfg) {
  dir_create(path_dir(cfg$notes_path))
  dir_create(cfg$derived_dir)

  invisible(TRUE)
}

#' Collect basic metadata and table-of-contents information from a PDF.
#'
#' @param pdf_path Path to the source PDF.
#'
#' @return A named list with `info`, `toc`, and `page_sizes`.
#'
#' @details
#' This function gathers the structural metadata that helps us understand the
#' shape of the report before interpreting its content. The TOC is preserved as
#' returned by `pdftools`; we do not try to over-interpret it here because TOC
#' structures vary across PDFs.
collect_pdf_metadata <- function(pdf_path) {
  list(
    info = pdftools::pdf_info(pdf_path),
    toc = pdftools::pdf_toc(pdf_path),
    page_sizes = pdftools::pdf_pagesize(pdf_path)
  )
}

#' Extract and lightly normalize text for every page in a PDF.
#'
#' @param pdf_path Path to the source PDF.
#'
#' @return A tibble with one row per page and columns for raw text, cleaned text,
#'   and a few simple page-level diagnostics.
#'
#' @details
#' `pdftools::pdf_text()` returns one string per page. This helper preserves that
#' one-page-per-row structure so every later summary can point back to a page
#' number. Text cleaning is intentionally light: collapse repeated blank lines,
#' trim whitespace, and normalize line-break hyphenation where it is likely to
#' improve searchability.
extract_pdf_pages <- function(pdf_path) {
  raw_pages <- pdftools::pdf_text(pdf_path)

  tibble(
    page = seq_along(raw_pages),
    text_raw = raw_pages
  ) %>%
    mutate(
      text_clean = map_chr(text_raw, clean_page_text),
      n_chars = str_length(text_clean),
      n_lines = str_count(text_clean, "\n") + 1L,
      is_sparse = n_chars < 100
    )
}

# Purpose: Clean one page of extracted PDF text without destroying page meaning.
# Inputs: `text`, a single page string returned by `pdf_text()`
# Returns: A cleaned page string suitable for search and markdown storage
# Key decisions: Keep cleaning conservative because over-normalizing PDF text can
# erase clues about headings, lists, or awkward layout that matter later.
clean_page_text <- function(text) {
  text %>%
    str_replace_all("-\\n(?=\\p{Ll})", "") %>%
    str_replace_all("[ \t]+", " ") %>%
    str_replace_all("\\n{3,}", "\n\n") %>%
    str_trim()
}

#' Search a PDF for domain keywords and return page-cited hits.
#'
#' @param pdf_path Path to the source PDF.
#' @param keywords Character vector of search terms.
#'
#' @return A tibble of keyword hits with the matched keyword, page number, and
#'   surrounding text returned by `pdfsearch`.
#'
#' @details
#' This helper uses `pdfsearch::keyword_search()` as a targeted indexing layer.
#' It helps us locate definitions, methods, and section anchors without requiring
#' a blind linear reread of the entire report.
search_keywords_in_pdf <- function(pdf_path, keywords) {
  hits <- pdfsearch::keyword_search(
    x = pdf_path,
    keyword = keywords,
    path = TRUE,
    surround_lines = 1,
    ignore_case = TRUE,
    token_results = FALSE,
    split_pdf = FALSE,
    remove_hyphen = TRUE,
    convert_sentence = TRUE
  )

  as_tibble(hits)
}

# Purpose: Add simple keyword-presence flags to the page table so we can quickly
# inspect which pages mention core report concepts.
# Inputs: `page_tbl`, a page-level tibble
# Returns: The input page tibble plus logical indicator columns
# Key decisions: Convert only a small fixed set of keywords into columns. The
# long-form hit table remains the main detailed search artifact.
annotate_keyword_presence <- function(page_tbl) {
  page_tbl %>%
    mutate(
      has_hma = str_detect(text_clean, regex("\\bHMA\\b", ignore_case = TRUE)),
      has_cmz = str_detect(text_clean, regex("\\bCMZ\\b", ignore_case = TRUE)),
      has_eha = str_detect(text_clean, regex("\\bEHA\\b", ignore_case = TRUE)),
      has_aha = str_detect(text_clean, regex("\\bAHA\\b", ignore_case = TRUE)),
      has_flagged = str_detect(text_clean, regex("\\bflagged\\b", ignore_case = TRUE)),
      has_segment = str_detect(text_clean, regex("river segment", ignore_case = TRUE)),
      has_methods = str_detect(text_clean, regex("\\bmethods\\b", ignore_case = TRUE))
    )
}

#' Build a markdown file containing extracted text for every page.
#'
#' @param cfg Configuration list for the current report.
#' @param page_tbl Tibble returned by `extract_pdf_pages()`.
#'
#' @return A single markdown string containing one section per page.
#'
#' @details
#' This markdown artifact is the durable “full slurp” of the report. It is not a
#' polished summary; it is a readable storage format for page-level extracted
#' text that can be searched, diffed, and revisited without reopening the PDF.
build_page_text_markdown <- function(cfg, page_tbl) {
  header_lines <- c(
    paste0("# Extracted Page Text: ", cfg$slug),
    "",
    paste0("- Source PDF: `", cfg$pdf_path, "`"),
    paste0("- Page count: ", nrow(page_tbl)),
    ""
  )

  page_sections <- page_tbl %>%
    transmute(
      section = map2_chr(
        page,
        text_clean,
        ~ paste0("## Page ", .x, "\n\n", .y, "\n")
      )
    ) %>%
    pull(section)

  c(header_lines, page_sections) %>%
    paste(collapse = "\n")
}

#' Build the first-pass markdown notes file for a PDF report.
#'
#' @param cfg Configuration list for the current report.
#' @param pdf_meta Named list returned by `collect_pdf_metadata()`.
#' @param page_tbl Tibble returned by `extract_pdf_pages()`.
#' @param keyword_hits Tibble returned by `search_keywords_in_pdf()`.
#'
#' @return A markdown string intended for the top-level notes file.
#'
#' @details
#' The notes file is the human-facing briefing layer above the derived artifacts.
#' It should summarize document structure, point to likely definition and methods
#' pages, and give the reader a compact index into the full page-text daughter
#' files.
build_notes_markdown <- function(cfg, pdf_meta, page_tbl, keyword_hits) {
  keyword_cols <- names(keyword_hits)
  page_col <- keyword_cols[str_detect(keyword_cols, "page")]
  if (length(page_col) == 0) {
    stop("Could not identify a page column in keyword search results.")
  }

  keyword_summary <- keyword_hits %>%
    count(keyword, sort = TRUE, name = "n_hits")

  candidate_pages <- keyword_hits %>%
    group_by(keyword) %>%
    summarise(
      pages = paste(sort(unique(.data[[page_col[[1L]]]])), collapse = ", "),
      .groups = "drop"
    )

  toc_md <- format_toc_markdown(pdf_meta$toc)
  keyword_summary_md <- format_keyword_summary_markdown(keyword_summary, candidate_pages)

  sparse_pages <- page_tbl %>%
    filter(is_sparse) %>%
    pull(page)

  sparse_pages_line <- if (length(sparse_pages) == 0) {
    "- Sparse extracted pages: none detected"
  } else {
    paste0("- Sparse extracted pages: ", paste(sparse_pages, collapse = ", "))
  }

  c(
    paste0("# Notes: ", cfg$slug),
    "",
    "## Document Control",
    paste0("- Source PDF: `", cfg$pdf_path, "`"),
    paste0("- Derived folder: `", cfg$derived_dir, "`"),
    paste0("- Page count: ", pdf_meta$info$pages),
    sparse_pages_line,
    "",
    "## Structural Map",
    toc_md,
    "",
    "## Keyword Index",
    keyword_summary_md,
    "",
    "## Derived Artifacts",
    "- `pdf_info.json` stores basic metadata and page count.",
    "- `toc.json` stores the table of contents structure returned by `pdftools`.",
    "- `pages.csv` stores one row per page with raw and cleaned text.",
    "- `keyword_hits.csv` stores page-cited keyword hits.",
    "- `page_text.md` stores readable extracted text for every page.",
    "",
    "## Working Notes",
    "- ",
    "",
    "## Open Questions",
    "- "
  ) %>%
    paste(collapse = "\n")
}

# Purpose: Render the PDF table of contents into a compact markdown list.
# Inputs: `toc`, the nested object returned by `pdftools::pdf_toc()`
# Returns: A markdown string
# Key decisions: Keep TOC formatting shallow and readable rather than trying to
# reproduce every nesting nuance of the PDF outline.
format_toc_markdown <- function(toc) {
  toc_lines <- flatten_toc_entries(toc)

  if (length(toc_lines) == 0) {
    return("- No table of contents metadata detected")
  }

  paste(toc_lines, collapse = "\n")
}

# Purpose: Flatten nested PDF TOC entries into a simple markdown bullet list.
# Inputs: `toc`, a nested list from `pdftools::pdf_toc()`
# Returns: A character vector of markdown bullet lines
# Key decisions: Represent nesting with indentation because the main goal is
# navigational usefulness, not full fidelity to the original PDF outline.
flatten_toc_entries <- function(toc, level = 0L) {
  if (is.null(toc) || length(toc) == 0) {
    return(character(0))
  }

  entries <- toc
  if (!is.null(toc$title) || !is.null(toc$page)) {
    entries <- list(toc)
  }

  map_chr_or_flatten <- map(entries, function(entry) {
    title <- entry$title %||% "Untitled TOC Entry"
    page <- entry$page %||% NA_integer_
    indent <- str_dup("  ", level)
    line <- paste0(indent, "- ", title, if (!is.na(page)) paste0(" (p. ", page, ")"))

    children <- entry$children %||% list()
    c(line, flatten_toc_entries(children, level + 1L))
  })

  unlist(map_chr_or_flatten, use.names = FALSE)
}

# Purpose: Render keyword counts and candidate pages into markdown.
# Inputs: `keyword_summary`, a tibble of hit counts; `candidate_pages`, a tibble
# of page lists by keyword
# Returns: A markdown string
# Key decisions: Surface pages directly because page-cited navigation is more
# useful than just raw hit counts.
format_keyword_summary_markdown <- function(keyword_summary, candidate_pages) {
  if (nrow(keyword_summary) == 0) {
    return("- No keyword hits found")
  }

  keyword_summary %>%
    left_join(candidate_pages, by = "keyword") %>%
    transmute(line = glue("- `{keyword}`: {n_hits} hits on pages {pages}")) %>%
    pull(line) %>%
    paste(collapse = "\n")
}

#' Write all machine-derived artifacts and the top-level notes file.
#'
#' @param cfg Configuration list for the current report.
#' @param pdf_meta Named list returned by `collect_pdf_metadata()`.
#' @param page_tbl Tibble returned by `extract_pdf_pages()`.
#' @param keyword_hits Tibble returned by `search_keywords_in_pdf()`.
#' @param page_text_md Markdown string returned by `build_page_text_markdown()`.
#' @param notes_md Markdown string returned by `build_notes_markdown()`.
#'
#' @return A named list of paths written to disk.
#'
#' @details
#' This function owns file I/O for the ingestion pipeline. Internal helpers build
#' objects in memory; this boundary helper is the single place where those
#' objects are persisted to the repository.
write_ingest_outputs <- function(cfg, pdf_meta, page_tbl, keyword_hits, page_text_md, notes_md) {
  info_path <- path(cfg$derived_dir, "pdf_info.json")
  toc_path <- path(cfg$derived_dir, "toc.json")
  pages_path <- path(cfg$derived_dir, "pages.csv")
  hits_path <- path(cfg$derived_dir, "keyword_hits.csv")
  page_text_path <- path(cfg$derived_dir, "page_text.md")
  notes_path <- cfg$notes_path

  jsonlite::write_json(pdf_meta$info, info_path, pretty = TRUE, auto_unbox = TRUE)
  jsonlite::write_json(pdf_meta$toc, toc_path, pretty = TRUE, auto_unbox = TRUE)
  readr::write_csv(page_tbl, pages_path)
  readr::write_csv(keyword_hits, hits_path)
  writeLines(page_text_md, page_text_path, useBytes = TRUE)
  writeLines(notes_md, notes_path, useBytes = TRUE)

  list(
    info_path = info_path,
    toc_path = toc_path,
    pages_path = pages_path,
    hits_path = hits_path,
    page_text_path = page_text_path,
    notes_path = notes_path
  )
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

# Uncomment to run interactively.
# report <- ingest_pdf_report(config)
