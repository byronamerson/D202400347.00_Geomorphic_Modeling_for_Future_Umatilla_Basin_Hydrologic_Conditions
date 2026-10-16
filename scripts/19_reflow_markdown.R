# =============================================================================
# 19_reflow_markdown.R
# Umatilla River Discharge-Channel Migration Analysis
# Rewrap over-long prose lines in a markdown draft to the file's convention.
# =============================================================================
#
# Why: hand edits applied through single-line find-and-replace produce lines far
# past the file's ~80-character convention, because the replacement text is
# written as one line regardless of length. This restores the convention without
# touching content.
#
# What it does NOT do: it never joins lines. Each source line is wrapped
# independently, so a line already under the width is returned untouched and the
# diff stays confined to the lines that were too long. Refilling whole
# paragraphs would rewrite the entire file and make review impossible.
#
# Exempt from wrapping (content would break):
#   - table rows            |---|---|
#   - image and link lines  ![alt](path)
#   - headings              #, ##, ###
#   - fenced code and block quotes
#   - blank lines
#
# Inputs : path to a markdown file
# Outputs: the file, rewrapped; a .bak copy of the original beside it
# =============================================================================

WRAP_WIDTH <- 80


is_exempt_line <- function(line) {
  #' Is this line one that must be left exactly as written?
  #' @param line a single character string, one line of the file.
  #' @return TRUE if wrapping it would break markdown or a path.
  #' Decision: the test is on the line as it stands, not on document structure --
  #' a table row is recognizable on its own, which keeps this a pure predicate.
  trimmed <- trimws(line)

  nchar(trimmed) == 0L ||
    grepl("^[|]", trimmed) ||          # table row
    grepl("^#", trimmed) ||            # heading
    grepl("^>", trimmed) ||            # block quote
    grepl("^```", trimmed) ||          # code fence
    grepl("^[-*+] ", trimmed) ||       # list item (hanging indent not handled)
    grepl("\\]\\(", trimmed)           # inline link or image -- path may be long
}


wrap_one_line <- function(line, width) {
  #' Wrap a single line to the width, at spaces only.
  #' @param line a single character string.
  #' @param width target maximum characters.
  #' @return a character vector of one or more lines.
  #' A word longer than the width (a URL, say) is left over-long rather than
  #' broken, which is what strwrap does.
  if (is_exempt_line(line) || nchar(line) <= width) return(line)
  strwrap(line, width = width)
}


reflow_lines <- function(lines, width) {
  #' Wrap every eligible line in a document.
  #' @param lines character vector, the file's lines.
  #' @param width target maximum characters.
  #' @return character vector, possibly longer than the input.
  unlist(lapply(lines, wrap_one_line, width = width), use.names = FALSE)
}


count_words <- function(lines) {
  #' Total whitespace-separated tokens, for the before/after check.
  #' @param lines character vector.
  #' @return single integer.
  sum(lengths(strsplit(trimws(lines), "[[:space:]]+")))
}


reflow_markdown_file <- function(path, width = WRAP_WIDTH) {
  #' Rewrap a markdown file in place, after backing it up.
  #' @param path path to the markdown file.
  #' @param width target maximum characters.
  #' @return invisibly, a list of before/after line and word counts.
  #' This is the I/O boundary -- every helper above works on character vectors.
  #' Writes CRLF, the convention this draft already uses.
  stopifnot(file.exists(path))

  original <- readLines(path, warn = FALSE)
  wrapped  <- reflow_lines(original, width)

  file.copy(path, paste0(path, ".bak"), overwrite = TRUE)

  con <- file(path, open = "wb")
  writeLines(wrapped, con, sep = "\r\n")
  close(con)

  stats <- list(
    lines_before = length(original),
    lines_after  = length(wrapped),
    words_before = count_words(original),
    words_after  = count_words(wrapped),
    over_width   = sum(nchar(wrapped) > width & !vapply(wrapped, is_exempt_line, logical(1)))
  )

  cat(sprintf("Lines: %d -> %d\n", stats$lines_before, stats$lines_after))
  cat(sprintf("Words: %d -> %d\n", stats$words_before, stats$words_after))
  cat(sprintf("Non-exempt lines still over %d characters: %d\n",
              width, stats$over_width))
  cat(sprintf("Backup written to %s.bak\n", path))

  invisible(stats)
}


# =============================================================================
# RUN
# =============================================================================

DRAFT <- "docs/TM_Umatilla_Migration_DRAFT_2026-10-15.md"

reflow_markdown_file(DRAFT)
