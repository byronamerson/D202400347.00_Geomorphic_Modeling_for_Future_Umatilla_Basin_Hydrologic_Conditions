# Tidy Analysis as Three Operations: Add, Summarize, Expand

*Agent reference — a companion to R Development Principles.
Before writing any data-wrangling pipeline, read this document to
decide which operation comes next. When a pipeline feels tangled,
return here: the answer is almost always that you skipped a step
or mixed two operations together.*

---

## The Core Idea

Every tidy analysis pipeline is a sequence of three operations:

1. **Add** — enrich rows by creating or joining columns so each row
   moves closer to being self-contained for the target calculation.
2. **Summarize** — collapse rows by computing group-level aggregates
   once every row already contains the variables the summary needs.
3. **Expand** — bring in data from another table or granularity via
   joins, either to enrich before summarizing or to broadcast
   summaries back to finer-grained observations.

The operations are not a rigid sequence. Real pipelines cycle through
them — add, then join, then add again, then summarize, then rejoin
the summary back. The framework answers the question *"what should I
do next?"* at every step.

---

## Operation 1 — Add Columns (`mutate`)

### What it does

`mutate()` creates new columns from existing ones. It preserves every
row. After a mutate, the data frame has the same number of rows and
the same unit of observation — it just knows more about each row.

### When to use it

Use `mutate()` when the downstream calculation needs a variable that
does not exist yet but can be derived from columns already present.
Typical cases:

- Deriving a grouping variable from raw data (water year from date,
  fiscal quarter from timestamp, age class from birthdate).
- Computing a rate, ratio, or difference from two existing columns.
- Creating a flag or classification via `case_when()` or `if_else()`.
- Building an intermediate value that a later mutate will use.

### The enrichment principle

Each `mutate()` should bring every row closer to containing all the
information the final calculation requires. Think of it as
*progressive enrichment*: the row starts sparse and gains context
with each step. The signal that enrichment is done is that you can
write the summary function call using only column names already in
the data frame.

### Grouped mutate — still an Add operation

`group_by() |> mutate()` adds a column computed within groups but
**preserves every row**. This is still an Add operation, not a
Summarize. Use it for within-group lags, cumulative sums, ranks,
running means, or deviations from a group statistic.

```r
# Add a column: change in life expectancy from prior year, by country
df <- df |>
  group_by(country) |>
  mutate(le_delta = lifeExp - lag(lifeExp)) |>
  ungroup()
```

Always `ungroup()` immediately after a grouped mutate unless the
next verb explicitly requires the same groups.

### Agent checklist — before writing a mutate

- [ ] Does the new column have a clear, descriptive name?
- [ ] Is the computation vectorized (no per-row loops)?
- [ ] Can I verify the result with a quick sanity check
      (e.g., a known value should equal 1, a flag should be TRUE
      for specific rows)?
- [ ] Am I creating this column because a downstream step needs it,
      not just because I can?

---

## Operation 2 — Summarize Groups (`group_by |> summarize`)

### What it does

`group_by() |> summarize()` splits the data into groups, applies an
aggregate function within each group, and returns one row per group.
**It changes the unit of observation.** Daily measurements become
annual summaries. Individual transactions become customer totals.

### When to use it

Summarize when the question asks about groups, not individual
observations: "What is the mean discharge per site per water year?"
"Which category has the highest conversion rate?" "How many events
occurred in each region?"

### The readiness test

**Do not summarize until every row contains all the variables the
summary function needs.** Concretely:

1. The grouping variable(s) must already be columns in the data frame.
2. The value(s) to aggregate must already be columns.
3. Any normalizing or contextual variable (drainage area, population)
   must be present if the summary uses it.

If any of these are missing, go back to Add or Expand first.
Premature summarization — collapsing before rows are self-contained —
is the single most common pipeline error.

### Summarization changes grain

After summarizing, always confirm: *what does one row represent now?*
State it explicitly in a comment if the answer is not obvious from
the grouping variables.

```r
# After this step, one row = one site × one water year
annual <- daily |>
  group_by(site_id, water_year) |>
  summarize(
    mean_q  = mean(discharge, na.rm = TRUE),
    max_q   = max(discharge, na.rm = TRUE),
    n_obs   = n(),
    .groups = "drop"
  )
```

### Leftover grouping

Always use `.groups = "drop"` in `summarize()` or call `ungroup()`
immediately after. Leftover grouping is a silent source of
downstream bugs — subsequent mutates or summaries will operate
within groups you forgot about.

### Agent checklist — before writing a summarize

- [ ] Have I confirmed that every variable needed by the summary
      function is already a column?
- [ ] Have I stated (at least mentally) what one row will represent
      after the summarize?
- [ ] Am I using `.groups = "drop"` or calling `ungroup()`?
- [ ] Is the summary function correct? (`mean()` not `sum()` when
      I want an average; `n()` not `length()` for row counts.)

---

## Operation 3 — Expand via Joins (`left_join` and friends)

### What it does

Joins combine columns from two tables by matching on shared key
columns. They serve two distinct purposes in the workflow:

- **Enrichment joins** add columns from a lookup table without
  changing row count. Example: joining site metadata (drainage area,
  aquifer type) to a time-series table by site ID. Conceptually
  identical to `mutate()`, but the information lives in another
  table. dplyr calls these "mutating joins" for exactly this reason.

- **Expansion joins** increase row count by broadcasting
  coarser-grained data to finer-grained observations. Example:
  joining a site table (one row per site) to a monitoring-point
  table (many points per site). This is the inverse of summarization.

### When to use it

Use a join when the variable you need for an Add or Summarize step
lives in a different table. Also use a join to bring a summary back
to the observation level — the *summarize-then-rejoin* pattern:

```r
# Summarize annual totals, classify years, rejoin to daily data
annual_class <- daily |>
  group_by(site_id, water_year) |>
  summarize(total_q = sum(discharge), .groups = "drop") |>
  mutate(year_type = case_when(
    total_q > quantile(total_q, 0.75) ~ "wet",
    total_q < quantile(total_q, 0.25) ~ "dry",
    TRUE ~ "normal"
  ))

daily_classified <- daily |>
  left_join(annual_class |> select(site_id, water_year, year_type),
            by = c("site_id", "water_year"))
```

### Protecting data grain

Joins can silently multiply rows if the key relationship is not what
you expect. Before every join:

1. **Identify the key columns** — what uniquely identifies a row in
   each table?
2. **Check for duplicates** on the join key in the right-hand table
   if you expect a many-to-one enrichment join. A quick
   `count(rhs, key) |> filter(n > 1)` catches surprises.
3. **State the expected effect on row count**: same (enrichment),
   increase (expansion), or decrease (semi/anti join).
4. **Verify after joining**: compare `nrow()` before and after. If
   row count changed unexpectedly, stop and investigate.

### Agent checklist — before writing a join

- [ ] Do I know which columns form the join key?
- [ ] Have I checked for unexpected duplicates in the right-hand table?
- [ ] Am I using `left_join()` by default? (Prefer `left_join` unless
      there is a specific reason for `inner_join`, `anti_join`, etc.)
- [ ] Have I explicitly specified the `by` argument? Never rely on
      auto-detected keys.
- [ ] After the join, does one row still represent what I think it
      represents?

---

## Tracking the Unit of Observation

The central concept in this framework is not any function — it is the
**unit of observation**. Every operation either preserves it, collapses
it, or expands it:

| Operation | Effect on unit of observation |
|-----------|------------------------------|
| `mutate()` | Preserves (same rows, more columns) |
| Enrichment join | Preserves (same rows, more columns from another table) |
| `group_by() |> mutate()` | Preserves (adds within-group computations) |
| `group_by() |> summarize()` | Collapses (one row per group) |
| Expansion join | Expands (rows multiply via one-to-many key) |

At every step in a pipeline, you should be able to complete this
sentence: *"Each row represents one ______."* If you cannot, stop
and clarify before proceeding. Annotate grain changes with comments
in the pipeline.

---

## Common Mistakes and How to Avoid Them

### Premature summarization

**Symptom:** You need to add a grouping variable or a normalizing
column *after* the summarize call, forcing awkward workarounds.

**Fix:** Before writing `summarize()`, run the readiness test. If
any variable is missing, go back to Add or Expand.

### Row-wise thinking

**Symptom:** You reach for a loop, `apply()`, or `rowwise()` to do
something "for each row."

**Fix:** Reframe as a column operation. "For each row, compute X
from A and B" is `mutate(X = f(A, B))`. If the function is truly
not vectorized, use `purrr::map2()` or `purrr::pmap()` rather than
`rowwise()`.

### Silent row multiplication after a join

**Symptom:** `nrow()` increases after what you thought was an
enrichment join. Downstream summaries are inflated.

**Fix:** Check for duplicate keys before joining. After joining,
verify row count matches expectations.

### Leftover grouping

**Symptom:** A mutate or summarize produces bizarre results because
the data is still grouped from a previous step.

**Fix:** Always `.groups = "drop"` or `ungroup()` immediately after
every `summarize()` and every grouped `mutate()`.

### Using `mean(c(x1, x2, x3))` instead of `rowMeans()`

**Symptom:** `mutate(avg = mean(c(a, b, c)))` returns the same value
for every row — the grand mean of all values across all rows.

**Fix:** Use `rowMeans(pick(a, b, c))` or
`(a + b + c) / 3` for per-row means.

---

## The Decision at Every Step

When building or reviewing a pipeline, ask at each step:

1. **Does each row have everything the next operation needs?**
   - No → **Add** a column via `mutate()`, or **Expand** via a join.
   - Yes → proceed to the next question.

2. **Does the question ask about individual observations or groups?**
   - Groups → **Summarize**.
   - Observations → keep rows as-is; maybe Add more columns.

3. **Does the result need to go back to a finer grain?**
   - Yes → **Expand** by joining the summary back to the
     observation-level table.

This decision tree, applied at every step, produces clean pipelines
that read as a sequence of explicit analytical choices rather than an
opaque block of code.

---

## Cross-Language Reference

The three operations are language-independent. When working in Python
rather than R, the same framework applies with different syntax:

| Operation | dplyr (R) | pandas | polars |
|-----------|-----------|--------|--------|
| Add columns | `mutate()` | `.assign()` | `.with_columns()` |
| Summarize | `group_by() + summarize()` | `.groupby().agg()` | `.group_by().agg()` |
| Expand via join | `left_join()` | `.merge()` | `.join()` |
| Grouped add | `group_by() + mutate()` | `.groupby().transform()` | `.with_columns(...over())` |

The thinking is the same: enrich rows, collapse groups, bridge tables.
Only the verbs change.

---

## Quick Reference

| Principle | In practice |
|-----------|-------------|
| Add before summarize | Every variable the summary needs must be a column first |
| Track the grain | State what one row represents before and after every operation |
| Readiness test | If you cannot write `summarize(result = f(col))` using existing columns, go back to Add or Expand |
| Grouped mutate ≠ summarize | `group_by() + mutate()` preserves rows; `group_by() + summarize()` collapses them |
| Enrichment join ≈ mutate | A `left_join` that preserves row count is conceptually the same as adding a column |
| Check keys before joining | `count(rhs, key) |> filter(n > 1)` catches duplicates |
| Always drop groups | `.groups = "drop"` in `summarize()`, `ungroup()` after grouped `mutate()` |
| Summarize-then-rejoin | Compute a group statistic, then join it back to observation-level data — this is the standard cycle |
| Comment grain changes | `# After this step, one row = one site × one water year` |
| Column names as contracts | Prefix conventions (`id_`, `amt_`, `cat_`) make programmatic operations safer across all three operations |
