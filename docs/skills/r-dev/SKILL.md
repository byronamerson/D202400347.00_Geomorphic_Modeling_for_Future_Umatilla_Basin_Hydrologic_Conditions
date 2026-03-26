# R Development Skill

*Directives for writing R code in this project. Read this alongside
`docs/lingua.md` and `docs/r-principles.md` before starting any R
work. These directives are addressed to you as a collaborator.*

---

## The Contract Is Mandatory

Every non-trivial or reusable R function — whether in a package or a
script — **must have a boundary contract** before it has an
implementation. No exceptions.

The contract covers three fields:

- **Purpose** — what the function does and its role in the workflow
- **Inputs and outputs** — what goes in and what comes out, with
  domain meaning and constraints
- **Key decisions** — assumptions, algorithm choices, or domain
  rules that shaped the implementation

### In R packages — Roxygen

```r
#' Split rows into logical groups separated by sentinel markers
#'
#' @param rows List of parsed row vectors from a single time block.
#'   Length must be >= 1.
#' @return A list of matrices, one per variable group. Returns an
#'   empty list if `rows` contains only sentinel rows.
#'
#' @details Sentinel rows are identified by all-zero values across
#'   all columns. These are format artifacts written by the data
#'   logger, not physical data — they are discarded, not returned.
split_groups <- function(rows) { ... }
```

### In scripts — structured comment block

Use the same three fields in a structured comment block. Mirror
the Roxygen structure — purpose on the first line, then
inputs/outputs, then key decisions:

```r
# Split rows into logical groups separated by sentinel markers.
# rows (list of row vectors, length >= 1) -> list of matrices, one per group.
# Sentinel rows (all columns zero) are format artifacts — discarded, not returned.
split_groups <- function(rows) { ... }
```

**The form is different. The obligation is identical.** A script
function without a boundary contract is incomplete.

### Moving to a package

When a script function moves into a package, translate its
comment block to Roxygen. The fields map directly:

- First line → title
- Input/output line(s) → `@param` and `@return`
- Key decisions line → `@details`

You are translating markup, not rethinking the contract.

---

## Contract Before Implementation

**Write the contract first. Always.**

1. Write the function signature and the Roxygen block or comment
   block. Leave the body empty or as a `stop("not implemented")`.
2. Show the human the contract and get confirmation before
   proceeding.
3. Derive tests from the contract. Each constraint implies a test.
4. Implement once the contract is confirmed and tests are failing.

Do not write implementation and then document it. That is
backwards and produces documentation that describes code rather
than code that satisfies a specification.

---

## What Makes a Contract Good

### Domain meaning, not type names

```r
# ❌ Noise — tells the LLM nothing about the domain
#' @param K_s A numeric value.

# ✅ Domain contract — describes meaning, units, and constraints
#' @param K_s Saturated hydraulic conductivity (m/s). Must be positive.
#'   Typical range 1e-7 (clay) to 1e-3 (coarse gravel).
```

The `@param` description is how you communicate domain rules to
the LLM and to the test-writer. A constraint stated here
("Must be positive") implies a `testthat` expectation:

```r
expect_error(compute_k(K_s = -0.01), class = "validation_error")
```

### Output structure, not just type

```r
# ❌ Weak
#' @return A data frame.

# ✅ Specific — gives the LLM everything needed to generate or verify
#' @return A tibble with columns: time (numeric, hours since epoch),
#'   depth (numeric, m below surface), value (numeric, measurement units
#'   depend on variable). One row per observation. No missing values in
#'   any column.
```

### Decisions that would otherwise be invisible

```r
#' @details The van Genuchten (1980) parameterisation is used for the
#'   soil water retention curve. The Mualem (1976) pore-size distribution
#'   model is assumed. If theta falls below theta_r, the function clamps
#'   to theta_r rather than throwing an error — this is a numerical
#'   stability choice, not a physical claim.
```

---

## Roxygen Standards (R Packages)

Follow these conventions for all exported functions:

- **Title line**: one sentence, no full stop, verb phrase
  (`Compute`, `Extract`, `Locate`, `Build`)
- **`@param`**: domain meaning + units + constraints, not just
  type. All parameters documented. Order matches function
  signature.
- **`@return`**: structure of the output with column names and
  types for data frames/tibbles. State invariants ("No missing
  values in key columns").
- **`@details`**: algorithm choices, domain rules, edge-case
  handling, caveats. This is where you record non-obvious
  decisions.
- **`@references`**: cite the method, equation, or standard. Use
  author-year format. This is how domain knowledge is anchored.
- **`@examples`**: at minimum one working example using only
  base R or declared dependencies. Must pass `R CMD check`.

Do not write placeholder Roxygen:

```r
# ❌ Not a contract — just markup with no content
#' @param x Input data
#' @return Output
```

Internal helpers (not exported) use the structured comment block
format. They follow the same three-field standard.

---

## Tests Follow From the Contract

Once the contract is written, test derivation is mechanical:

| Contract statement | Test it implies |
|--------------------|----------------|
| `@param K_s Must be positive` | `expect_error()` on zero and negative values |
| `@return tibble with columns time, depth, value` | `expect_named(result, c("time", "depth", "value"))` |
| `@return No missing values in key columns` | `expect_false(anyNA(result$time))` etc. |
| `@details Sentinel rows are discarded` | Fixture with known sentinels; output contains none |
| `@param rows Length must be >= 1` | `expect_error()` on empty list |

Derive these tests before writing the implementation. Run them.
Confirm they fail. Then implement.

---

## Validation at the Boundary

For exported functions, validate inputs at the top before any
computation:

```r
pkg_read_data <- function(path, var_names = c("pressure", "temperature")) {
  stopifnot(file.exists(path))
  stopifnot(is.character(var_names), length(var_names) >= 1L)
  # ... rest of function
}
```

Internal helpers **do not re-validate**. They trust that the
exported function has already checked inputs. If you find
yourself adding `stopifnot` to an internal helper, that is a
signal the boundary check is missing or insufficient.

---

## File Layout

Exported functions live in descriptively named files under `R/`.
Internal helpers for a given exported function live in the same
file, below the function they serve.

```
R/read.R
  pkg_read_data()       <- exported, full Roxygen block
  locate_headers()      <- internal, structured comment block
  parse_timestamp()     <- internal, structured comment block
  extract_block()       <- internal, structured comment block
```

When a helper becomes useful to a second exported function, move
it to a shared utils file at that point — not before.

---

## The Sequence

When asked to write an R function, follow this sequence without
being prompted:

1. **Contract first.** Write the Roxygen block (package) or
   comment block (script) and the function signature. Body is
   empty.
2. **Confirm.** Show the contract to the human and ask if it
   captures the intent correctly.
3. **Tests.** Derive tests from the contract.
4. **Implement.** Write the body to satisfy the contract and pass
   the tests.
5. **Do not modify the contract or tests during implementation.**
   If implementation reveals the contract was wrong, surface the
   conflict and ask the human to resolve it.
