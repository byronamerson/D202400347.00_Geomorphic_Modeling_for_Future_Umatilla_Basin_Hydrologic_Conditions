# R Development Principles

*The authoritative reference for how R code is written in this project.
Read this before writing any function. Read it again when a function
feels complicated. These principles take precedence over cleverness,
brevity, or convention. Above all human readable code takes precedence
over expediency.*

---

## 0. The One Rule

> *Decompose a big problem into smaller pieces, then solve each piece
> with a function or combination of functions. Each function taken by
> itself is simple and straightforward to understand; complexity is
> handled by composing functions in various ways.*
>
> — Hadley Wickham, *Advanced R* (2nd ed.), Chapter 9

Everything else in this document is a consequence of that rule.

---

## 1. Read the Docs — Every Time

**Before writing a function that uses a package, read that package's
documentation.** Do not rely on training data, memory, or educated
guesses about argument names, return types, or behaviour.

Package APIs change. Argument names differ between similar functions.
A function you think you know may have a better alternative in a
newer version.

```r
# Before using any of these, read their help pages:
?purrr::map2          # not mapply
?purrr::list_rbind    # not do.call(rbind, ...)
?purrr::map_lgl       # not vapply(..., logical(1))
?tidyr::pivot_longer  # not reshape or melt
?dplyr::bind_rows     # alternative to list_rbind for data frames
```

The same applies to newly installed or unfamiliar packages. Browse
their vignettes and help index before incorporating them. A function
that does what you need almost certainly exists — find it before
building it.

---

## 2. Functions Are Pure Where Possible

A **pure function** has two properties:
1. The output depends only on the inputs.
2. It has no side effects (no writing to disk, no modifying global state,
   no printing, no randomness unless seeded).

Pure functions can be tested in complete isolation. You can call them
from anywhere, pass them to `purrr::map()`, memoise them, and reason
about them without understanding the surrounding context.

```r
# ❌ Impure — captures `raw` from parent environment invisibly
parse_block <- function(start, end) {
  data_lines <- raw[seq(start + 2L, end)]  # raw is a free variable
  # ...
}

# ✅ Pure — all inputs are explicit arguments
parse_block <- function(raw, start, end) {
  data_lines <- raw[seq(start + 2L, end)]
  # ...
}
```

**The rule:** If a helper function needs a value, it takes that value
as an explicit argument. It does not reach into the parent scope.

### I/O lives at the boundary only

File reading, writing, and system calls happen exactly once, in the
outermost orchestrator function. Every internal helper works on
in-memory objects (character vectors, data frames, numeric vectors).
This makes every helper testable without touching the filesystem.

```r
# ✅ The orchestrator owns I/O; helpers own logic
read_data <- function(path, ...) {
  raw   <- readLines(path, warn = FALSE)   # I/O: happens once, here
  times <- locate_time_headers(raw)        # pure
  blocks <- extract_blocks(raw, times)     # pure
  # ... etc
}
```

---

## 3. One Function, One Job

A function that does two things should be two functions.

Signs a function is doing too many things:
- It needs a long comment at the top explaining its multiple phases
- Its name contains "and" (`parse_and_validate`, `read_and_clean`)
- It is longer than can be read on one screen without scrolling
- Testing it requires setting up complex state to exercise one behaviour

```r
# ❌ One function, many jobs
read_data <- function(path) {
  # reads file, finds headers, parses times, extracts blocks,
  # parses rows, splits variables, converts to long format,
  # validates names, builds tibble
}

# ✅ Each job is its own named function
locate_headers    <- function(raw)               # find header lines
parse_timestamp   <- function(header_line)       # extract numeric value
extract_block     <- function(raw, start, end)   # slice one block
parse_rows        <- function(lines)             # text -> list of vectors
is_sentinel       <- function(row)               # all-zero check
split_groups      <- function(row_list)          # split into groups
rows_to_matrix    <- function(row_list)          # list -> matrix
matrix_to_long    <- function(mat, t, name)      # matrix -> data frame
```

The orchestrator then reads like a description of what happens:

```r
read_data <- function(path, var_names) {
  raw         <- readLines(path, warn = FALSE)
  header_idx  <- locate_headers(raw)
  timestamps  <- map_dbl(raw[header_idx], parse_timestamp)
  block_ends  <- c(header_idx[-1L] - 1L, length(raw))
  all_blocks  <- map2(header_idx, block_ends, ~ extract_and_parse(raw, .x, .y))
  # ... assemble result
}
```

---

## 4. Name Functions After What They Do

Function names are verb-noun pairs that describe the transformation:

| Pattern | Example |
|---------|---------|
| `verb_noun` | `locate_headers`, `parse_timestamp`, `split_groups` |
| `is_*` / `has_*` | `is_sentinel`, `has_time_blocks` |
| `make_*` | `make_interpolator` (function factory) |
| `pkg_*` | exported public functions only (substitute your package prefix) |

Internal (non-exported) helpers do **not** use the package prefix.
Only functions that appear in `NAMESPACE` and are callable by users
get the prefix.

**If you cannot name a function clearly, it is doing too much.**
A function named `process_data` or `handle_block` is a warning sign.

---

## 5. No Deep Nesting

Nesting functions inside functions, or `mapply` inside `mapply`, is
the "Dagwood sandwich problem" — arguments spread over long distances,
logic folded inside logic, hard to read inside-out and right-to-left.

The fix is always the same: name the inner function and move it out.

```r
# ❌ Nested anonymous functions — hard to read, impossible to test
records <- mapply(
  function(block, t) {
    var_dfs <- mapply(
      function(mat, vname) {
        row_idx <- rep(seq_len(nrow(mat)), times = ncol(mat))
        col_idx <- rep(seq_len(ncol(mat)), each  = nrow(mat))
        data.frame(time = t, row = row_idx, ...)
      },
      mat = block, vname = var_names, SIMPLIFY = FALSE
    )
    do.call(rbind, var_dfs)
  },
  block = all_blocks, t = timestamps, SIMPLIFY = FALSE
)

# ✅ Named helpers + map2 + list_rbind
matrix_to_long <- function(mat, time, variable) {
  data.frame(
    time     = time,
    row      = rep(seq_len(nrow(mat)), times = ncol(mat)),
    col      = rep(seq_len(ncol(mat)), each  = nrow(mat)),
    variable = variable,
    value    = as.vector(mat),
    stringsAsFactors = FALSE
  )
}

block_to_long <- function(block, time, var_names) {
  map2(block, var_names, ~ matrix_to_long(.x, time, .y)) %>%
    list_rbind()
}

result <- map2(all_blocks, timestamps, ~ block_to_long(.x, .y, var_names)) %>%
  list_rbind()
```

**Maximum nesting depth:** One level of anonymous function inside a
`map()` call is acceptable for short, obvious lambdas. Two levels is
a signal to name the inner function. Three levels is never acceptable.

---

## 6. Pipes Over Nesting, Named Objects Over Pipes

Wickham describes three composition styles in *Advanced R* §6.3:

| Style | When to use |
|-------|-------------|
| `f(g(h(x)))` nesting | Short sequences only (2 steps max) |
| `y <- f(x); g(y)` named intermediate | When the intermediate object has meaning and a good name |
| `x %>% f() %>% g()` pipe | Sequential transformations where each step is a clear verb |

**Prefer pipes for sequential transformations.** Prefer named
intermediates when the intermediate result is scientifically meaningful
or will be referenced more than once. Never nest more than 2 calls deep.

```r
# ❌ Nested — reads inside-out
result <- as_tibble(do.call(rbind, lapply(blocks, parse_block)))

# ✅ Piped — reads left to right, each step is clear
result <- blocks %>%
  map(parse_block) %>%
  list_rbind() %>%
  as_tibble()
```

---

## 7. Use purrr, Not the apply Family

The `apply` family (`lapply`, `vapply`, `mapply`, `sapply`) has
inconsistent argument order, inconsistent return types, and the
`SIMPLIFY` footgun. `purrr` functions have a uniform interface:
`.x` is always the data, `.f` is always the function, the suffix
tells you the return type.

| Base R | purrr replacement | Notes |
|--------|-------------------|-------|
| `lapply(x, f)` | `map(x, f)` | Returns list |
| `vapply(x, f, logical(1))` | `map_lgl(x, f)` | Returns logical vector |
| `vapply(x, f, double(1))` | `map_dbl(x, f)` | Returns numeric vector |
| `mapply(f, x, y, SIMPLIFY=FALSE)` | `map2(x, y, f)` | Two-input parallel map |
| `do.call(rbind, list_of_dfs)` | `list_rbind(list_of_dfs)` | Row-bind data frames |
| `do.call(rbind, list_of_matrices)` | stays as `do.call` | No purrr equiv for matrices |

**Exception:** `do.call(rbind, row_list)` for stacking numeric vectors
into a matrix has no purrr equivalent — keep it as-is with a comment
explaining why.

---

## 8. Short Lambda Rule

Anonymous functions inside `map()` are fine for short, obvious
transformations. The threshold for naming is:

- More than one line → give it a name
- Uses `{}` braces → give it a name
- Called more than once → give it a name
- You needed a comment to explain it → give it a name

```r
# ✅ Fine as a lambda — one expression, self-evident
map_dbl(header_lines, ~ as.numeric(sub(".*TIME\\s*=\\s*(\\S+).*", "\\1", .x)))

# ❌ Too complex for a lambda — name it
map(data_lines, ~ {
  vals <- as.numeric(strsplit(trimws(.x), "\\s+")[[1L]])
  vals[!is.na(vals)]
})

# ✅ Named instead
strip_and_parse <- function(line) {
  as.numeric(strsplit(trimws(line), "\\s+")[[1L]])
}
map(data_lines, strip_and_parse)
```

---

## 9. Comments Explain Why, Names Explain What

If a comment is needed to explain *what* a line does, the line should
be a named function instead. Comments explain *why* a decision was
made, cite a source, or flag a non-obvious constraint.

```r
# ❌ Comment restates the code
is_sentinel <- vapply(rows, function(r) all(r == 0), logical(1L))  # find all-zero rows

# ✅ The function name explains what; the comment explains why
is_sentinel <- function(row) all(row == 0)

# The file format writes an all-zero row between variable groups.
# These are format artifacts, not physical data — they are discarded.
sentinels <- map_lgl(rows, is_sentinel)
```

---

## 10. File Layout

**Exported functions** live in their own files: `R/read.R`,
`R/plot.R`, `R/run.R`, etc.

**Internal helpers** for a given exported function are co-located in
the same file, below the exported function they serve. They are not
exported and do not carry the package prefix.

```
R/read.R
  pkg_read_data()       <- exported, public API
  locate_headers()      <- internal helper
  parse_timestamp()     <- internal helper
  extract_block()       <- internal helper
  parse_rows()          <- internal helper
  is_sentinel()         <- internal helper
  split_groups()        <- internal helper
  matrix_to_long()      <- internal helper
```

**Migration rule:** If a helper becomes useful to a second exported
function, move it to `R/utils-parse.R` (or the appropriate utils file)
at that point — not before. No premature abstraction.

---

## 11. Validate at the Boundary

Input validation (`stopifnot`, `stop()`, `match.arg()`) belongs at
the top of the exported function, before any computation begins.
Internal helpers assume their inputs are already valid — they do not
re-check.

```r
pkg_read_data <- function(path, var_names = c("pressure", "temperature")) {
  # Validation at the boundary — once, at the top
  stopifnot(file.exists(path))
  stopifnot(is.character(var_names), length(var_names) >= 1L)

  # Everything below this line can assume path exists and var_names is valid
  raw <- readLines(path, warn = FALSE)
  # ...
}
```

Shared validation logic that applies across multiple functions belongs
in a named `validate_*` helper (e.g., `validate_standard_df(df)`) that
can be called from any function accepting the standard data schema.

---

## 12. Testing

Testing follows standard R package practices using **testthat 3e**.

### Setup

Use testthat and usethis to scaffold infrastructure:

```r
usethis::use_testthat()
usethis::use_test("read")
```

### File Naming

Test files mirror source files by name:

`R/read.R` → `tests/testthat/test-read.R`

### Running Tests

Use `devtools::load_all()` before running tests so that internal
helpers are available:

```r
devtools::load_all()
testthat::test_file("tests/testthat/test-read.R")
```

Do not run tests by sourcing files directly.

### Test Helpers Directly

Because helpers are pure and named, each one can and should have its
own unit tests. Tests for a helper are more precise and faster to debug
than tests that route through the full orchestrator just to exercise
one piece of logic.

```r
test_that("split_groups() correctly splits two variable groups", {
  rows <- list(
    c(1, 2, 3), c(4, 5, 6),
    c(0, 0, 0),
    c(7, 8, 9), c(10, 11, 12),
    c(0, 0, 0)
  )
  result <- split_groups(rows)
  expect_length(result, 2L)
  expect_equal(result[[1L]], do.call(rbind, list(c(1,2,3), c(4,5,6))))
  expect_equal(result[[2L]], do.call(rbind, list(c(7,8,9), c(10,11,12))))
})
```

### Snapshot Tests for Conditions

When testing code that raises a message, warning, or error, use
`expect_snapshot()` instead of `expect_error()`, `expect_warning()`,
or `expect_message()` with regex patterns. Regex matching is fragile
and breaks when message wording changes.

```r
# ✅ Preferred — snapshot captures the full condition
expect_snapshot(error = TRUE, pkg_read_data("nonexistent.dat"))

# ✅ Also fine — testing for condition class, not message text
expect_error(pkg_read_data(123), class = "validation_error")

# ❌ Avoid — regex matching is fragile
expect_error(pkg_read_data("nonexistent.dat"), "file does not exist")
```

Use `expect_snapshot(error = TRUE)` rather than `expect_snapshot_error()`
so the error context is captured in addition to the message.

Use `expect_no_error()` instead of `expect_error(..., regexp = NA)`.

When snapshotting code that also produces a return value, assign the
result inside the snapshot to avoid capturing both:

```r
expect_snapshot(
  .res <- pkg_transform(noisy_input)
)
```

### What to Test

For each function, test:

- the expected transformation on typical input
- edge cases (empty input, single element, boundary values)
- that validation catches invalid input (for exported functions)

Test **observable behaviour**, not implementation details. If the
internal algorithm changes but the output stays the same, tests should
still pass.

### Namespace Issues

If tests fail due to namespacing problems, do not delete otherwise
correct tests. Stop and ask for clarification.

---

## 13. Roxygen — Document the Domain, Not the Syntax

Roxygen documentation should answer: *what does this do, why does it
exist, and where does the underlying method come from?* It should not
restate the type signature or repeat what the function name already
says.

Good `@param` entries describe what the parameter means in the problem
domain, not just its R type:

```r
#' @param K_s Saturated hydraulic conductivity (m/s). Must be positive.
```

not:

```r
#' @param K_s A numeric value.
```

Cite methods and data sources in `@references` or inline with the
format defined in the project's decision log, if one exists.

A Roxygen block is simultaneously:

- **A specification** — `@param` defines what inputs mean in the
  domain. `@return` defines expected output structure.
- **A prompt** — an LLM reading a complete Roxygen block has
  everything needed to generate or verify the implementation.
- **A contract** — if the Roxygen says the function returns a tibble
  with columns `time`, `depth`, and `value`, and the implementation
  returns something else, the contradiction is visible in language.
- **A test scaffold** — parameter constraints ("Must be positive")
  directly imply testthat expectations. `@examples` are executable
  code checked by `R CMD check`.

---

## Quick Reference

| Principle | In practice |
|-----------|-------------|
| Read the docs first | `?purrr::map2`, browse vignettes, do not guess |
| Pure functions | All inputs are explicit arguments; no free variables |
| I/O at boundary | `readLines()` once in the orchestrator, nowhere else |
| One job per function | If you need "and" in the name, split it |
| Verb-noun names | `parse_timestamp`, `split_groups`, `is_sentinel` |
| No deep nesting | Max one level of lambda; name anything with `{}` or multi-line |
| Pipes for sequences | `x %>% f() %>% g()` over `g(f(x))` |
| purrr over apply | `map2` not `mapply`; `map_lgl` not `vapply`; `list_rbind` not `do.call(rbind, ...)` |
| Co-locate helpers | Internal helpers live in the same file as their exported function |
| Validate once | At the top of the exported function; helpers trust their inputs |
| Test helpers directly | Don't route all tests through the orchestrator |
| Snapshot conditions | `expect_snapshot(error = TRUE)` not `expect_error(., "regex")` |
| Comments explain why | Names explain what; comments explain the decision or cite the source |
| Roxygen documents domain | "Hydraulic radius (m)" not "A float" |

---

## References

1. Wickham, H. (2019). *Advanced R* (2nd ed.). https://adv-r.hadley.nz/
   — Ch. 6 (Functions & composition), Ch. 9 (Functionals),
     Ch. 10 (Function factories), Ch. 11 (Function operators)
2. Wickham, H., & Grolemund, G. (2023). *R for Data Science* (2nd ed.).
   https://r4ds.hadley.nz/
3. Henry, L., & Wickham, H. purrr package documentation.
   https://purrr.tidyverse.org/reference/index.html
4. Wickham, H. et al. dplyr package documentation.
   https://dplyr.tidyverse.org/reference/index.html
5. Wickham, H. (2011). testthat: Get Started with Testing.
   https://testthat.r-lib.org/
6. Couch, S. (2025). chores: A Collection of LLM Assistants for R.
   https://simonpcouch.github.io/chores/
