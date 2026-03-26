# R Development Principles: LLM Companion

*Behavioral directives for writing R code in this project. Derived
from the R Development Principles reference document and the tidy
analysis framework (Add, Summarize, Expand). This version is for
you, the LLM collaborator. The human has a fuller reference document
with worked examples.*

---

## The one rule

Decompose a big problem into smaller pieces, then solve each piece
with a function. Each function taken by itself is simple. Complexity
is handled by composing functions. Everything below is a consequence.

---

## Read the docs — every time

Before writing code that uses a package, read its current
documentation. Do not rely on training. Package APIs change. Argument
names differ between similar functions. A function you think you know
may have a better alternative in a newer version.

This applies especially to: purrr, dplyr, tidyr, rlang, testthat.
Read help pages and vignettes. If a function does what you need, use
it rather than building it.

---

## Pure functions

The output depends only on the inputs. No side effects. No free
variables captured from the parent scope. If a helper needs a value,
it takes that value as an explicit argument.

I/O (file reading, writing, system calls) happens exactly once, in
the outermost orchestrator function. Every internal helper works on
in-memory objects. This makes every helper testable without touching
the filesystem.

---

## One function, one job

A function that does two things should be two functions. Warning
signs: the name contains "and," it needs a long comment explaining
multiple phases, it's longer than one screen, or testing it requires
complex setup to exercise one behaviour.

If you find yourself writing a function that does too much, stop and
propose decomposition. Don't write the monolith and plan to refactor
later.

---

## Naming

Function names are verb-noun pairs that describe the transformation:
`locate_headers`, `parse_timestamp`, `split_groups`, `is_sentinel`.

Exported public functions use the package prefix (`pkg_*`). Internal
helpers do not.

If you cannot name a function clearly, it is doing too much.

---

## No deep nesting

Don't nest functions inside functions. Don't nest `map()` inside
`map()`. Name the inner function and move it out.

Maximum nesting: one level of anonymous function inside a `map()`
call, for short obvious lambdas only. Two levels → name the inner
function. Three levels → never acceptable.

---

## Composition style

Three options, in order of preference for this project:

1. **Pipes** (`%>%` or `|>`) for sequential transformations where
   each step is a clear verb. This is the default for data
   transformation pipelines.
2. **Named intermediates** when the intermediate result is
   scientifically meaningful or will be referenced more than once.
   Give the intermediate a good name.
3. **Nesting** (`f(g(x))`) only for short sequences (2 steps max).

Never nest more than 2 calls deep. If you're writing
`as_tibble(do.call(rbind, lapply(...)))`, rewrite it as a pipe.

---

## purrr over apply

Use purrr, not the apply family. The apply family has inconsistent
argument order, inconsistent return types, and the `SIMPLIFY`
footgun.

| Instead of | Use |
|---|---|
| `lapply(x, f)` | `map(x, f)` |
| `vapply(x, f, logical(1))` | `map_lgl(x, f)` |
| `mapply(f, x, y, SIMPLIFY=FALSE)` | `map2(x, y, f)` |
| `do.call(rbind, list_of_dfs)` | `list_rbind(list_of_dfs)` |

Exception: `do.call(rbind, ...)` for stacking numeric vectors into
a matrix has no purrr equivalent. Keep it with a comment.

---

## Short lambda rule

Anonymous functions inside `map()` are fine when:
- One expression, self-evident
- No braces needed
- Called only once
- No comment needed to explain it

If any of those fail, name the function and move it out.

---

## Comments explain why, names explain what

If a comment restates what the code does, the code should be a named
function instead. Comments are for: why a decision was made, citing
a source, flagging a non-obvious constraint.

---

## File layout

Exported functions live in their own files (`R/read.R`, `R/plot.R`).
Internal helpers for a given exported function are co-located in the
same file, below the exported function they serve.

Migration rule: if a helper becomes useful to a second exported
function, move it to `R/utils-*.R` at that point — not before. No
premature abstraction.

---

## Validate at the boundary

Input validation (`stopifnot`, `stop()`, `match.arg()`) belongs at
the top of the exported function, before any computation. Internal
helpers assume their inputs are already valid — they do not re-check.

Shared validation logic that applies across multiple functions
belongs in a named `validate_*` helper.

---

## Testing

testthat 3e. Test files mirror source files: `R/read.R` →
`tests/testthat/test-read.R`.

Use `devtools::load_all()` before running tests so internal helpers
are available.

Test helpers directly — don't route all tests through the
orchestrator just to exercise one piece of logic.

For conditions (errors, warnings, messages): use
`expect_snapshot(error = TRUE)` over regex matching. Regex is
fragile. Use `expect_no_error()` over `expect_error(..., regexp = NA)`.

Test observable behaviour, not implementation details. If the
internal algorithm changes but output stays the same, tests should
still pass.

If tests fail due to namespacing problems, do not delete correct
tests. Stop and ask for clarification.

---

## Roxygen — document the domain

`@param` entries describe what the parameter means in the problem
domain, with constraints: `@param K_s Saturated hydraulic
conductivity (m/s). Must be positive.` — not `@param K_s A numeric
value.`

`@return` specifies structure and the unit of observation — what
one row represents.

`@details` captures domain rules, assumptions, algorithm choice.

---

## Tidy pipeline structure: Add, Summarize, Expand

When writing data transformation functions, structure the pipeline
around three operations:

### Add (enrich)

Use `mutate()` to add columns that bring each row closer to
self-containment for the target calculation. Data stays in the data
frame — do not extract columns into free-standing vectors to
manipulate outside the pipeline.

The readiness signal for the next phase: every row contains all
the variables the summary function needs.

Grouped mutate (`group_by() + mutate()`) is still an "add" operation
— it preserves rows while enriching them with group-aware values.

### Summarize (collapse)

Use `group_by() + summarize()` with `.groups = "drop"`. This is
split-apply-combine.

Summarization changes the unit of observation. After
`group_by(site, water_year) %>% summarize(mean_q = mean(discharge))`,
each row no longer represents a daily measurement — it represents
a site-year combination. Track this shift explicitly.

The readiness signal: every row contains all the variables needed.
If a variable is missing, you need more enrichment (or a join)
before you can summarize.

### Expand (join)

Joins bring in data from another table. Two purposes:

- **Enrichment joins** add columns without changing row count
  (joining site metadata to a time series by site ID). These are
  conceptually similar to `mutate()` — the information comes from
  another table.
- **Expansion joins** increase rows by broadcasting coarser-grained
  data to finer-grained observations. This is the inverse of
  summarization.

Always ask: "What does one row represent?" before and after every
join. If a left join encounters a one-to-many relationship
unexpectedly, rows multiply silently, corrupting downstream
summaries.

### The summarize-then-rejoin pattern

Compute group-level summaries, then join them back to
observation-level data. Example: compute annual mean discharge per
site, classify years as wet/dry/normal, then join that classification
back to daily observations. This round-trip is common in
environmental analysis.

### Not every function is a pipeline

The Add / Summarize / Expand structure applies to data transformation
functions. Not every function is a data transformation. For
non-pipeline functions, the other principles (pure, one job, validate
at boundary, etc.) still apply.

---

## Implementation idiom checklist

When writing tidy R code in this project, use:

- `dplyr::if_else()` over base `ifelse()`
- `dplyr::case_when()` for multi-condition branching
- Pipes for sequential transformations
- `arrange()` inside the pipe for ordering
- `.groups = "drop"` on every `summarize()` call
- Named intermediates when the intermediate is scientifically
  meaningful
- `purrr::map*` over `apply` family
- No free-standing vectors extracted from data frames for
  manipulation outside the pipeline
