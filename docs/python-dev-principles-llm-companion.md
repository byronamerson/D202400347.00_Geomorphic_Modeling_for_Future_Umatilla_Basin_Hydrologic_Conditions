# Python Development Principles: LLM Companion

*Behavioral directives for writing Python code in this project. Derived from the Python Development Principles reference document and the tidy analysis framework (Add, Summarize, Expand). This version is for you, the LLM collaborator. The human has a fuller reference document with worked examples.*

---

## The one rule

Decompose a big problem into smaller pieces, then solve each piece with a function. Each function taken by itself is simple. Complexity is handled by composing functions. Everything below is a consequence.

---

## Read the docs — every time

Before writing code that uses a package, read its current documentation. Do not rely on training. Python's scientific stack moves fast — pandas, xarray, geopandas and scipy all change between minor releases.

This applies especially to: pandas, numpy, xarray, geopandas, pathlib, pytest. If a function does what you need, use it rather than building it.

---

## Pure functions

The output depends only on the inputs. No side effects. No free variables captured from the enclosing scope. If a helper needs a value, it takes that value as an explicit argument.

I/O (file reading, writing, system calls) happens exactly once, in the outermost orchestrator function. Every internal helper works on in-memory objects. This makes every helper testable without touching the filesystem.

### Never mutate a DataFrame in place

Pandas permits in-place modification, but it obscures data flow and makes debugging hard. Return new objects. Never pass `inplace=True`.

```python
# ❌ Mutates the caller's DataFrame
df["discharge_cms"] = df["discharge_cfs"] * 0.028317

# ✅ Returns a new DataFrame
df = df.assign(discharge_cms=lambda d: d["discharge_cfs"] * 0.028317)
```

---

## One function, one job

A function that does two things should be two functions. Warning signs: the name contains "and," it needs a long comment explaining multiple phases, it's longer than one screen, or testing it requires complex setup to exercise one behaviour.

If you find yourself writing a function that does too much, stop and propose decomposition. Don't write the monolith and plan to refactor later.

---

## Naming

Function names are verb-noun pairs that describe the transformation: `locate_headers`, `parse_timestamp`, `split_groups`, `is_sentinel`.

Internal helpers carry a leading underscore (`_parse_block`). Public functions — those meant to be imported — do not.

If you cannot name a function clearly, it is doing too much.

---

## No deep nesting

Don't nest comprehensions inside comprehensions. Don't nest lambdas inside lambdas. Name the inner operation and move it out.

Maximum nesting: one level of comprehension or one short lambda, for obvious transformations only. Two levels → name the inner operation. Three levels → never acceptable.

Flatten nested lists with `itertools.chain.from_iterable()`, not a double comprehension.

---

## Composition style

Three options, in order of preference for this project:

1. **Method chains** for sequential DataFrame or Series transformations. Wrap long chains in parentheses, one method per line, so steps can be commented out or reordered.
2. **Named intermediates** when the intermediate result is scientifically meaningful or will be referenced more than once. Give the intermediate a good name.
3. **Nesting** (`f(g(x))`) only for short sequences (2 calls max).

Never nest more than 2 calls deep. If you're writing `pd.concat(list(map(f, xs))).reset_index(drop=True)`, rewrite it as a chain.

### `.pipe()` puts your own functions into a chain

`.pipe()` is Python's closest equivalent to the R pipe. Each piped function takes a DataFrame as its first argument and returns a DataFrame. This is how a named helper joins a chain without breaking it, and it is what lets the orchestrator read as a sequence of verbs.

```python
result = (
    raw_df
    .pipe(remove_outliers, col="discharge_cms")
    .pipe(add_water_year)
    .pipe(flag_bankfull_events, threshold=150.0)
)
```

### `.assign()` creates columns

`.assign()` returns a new DataFrame and keeps the chain unbroken. It is the equivalent of dplyr's `mutate()`. Use a lambda inside `.assign()` when the new column depends on columns created earlier in the same chain.

---

## Comprehensions over manual loops

| Instead of | Use |
| --- | --- |
| `for x in xs: result.append(f(x))` | `[f(x) for x in xs]` |
| `for x in xs: if cond(x): ...` | `[x for x in xs if cond(x)]` |
| accumulating a dict in a loop | `{k: f(v) for k, v in items}` |
| flattening nested lists | `itertools.chain.from_iterable(xss)` |
| building a DataFrame row by row | `pd.DataFrame(records)` from a list of dicts |

`enumerate()` and `zip()` loops are already readable; leave them.

Never append to a DataFrame in a loop. Build a list of records and construct the DataFrame once.

### Avoid `.apply(axis=1)`

Row-wise `.apply()` is a Python loop disguised as a method — slow and usually unnecessary. Prefer a vectorised expression, `np.where()`, or `np.select()` for multi-condition branching.

---

## Short lambda rule

Anonymous functions are fine when:

- One expression, self-evident
- Fits on one line
- Called only once
- No comment needed to explain it

If any of those fail, name the function and move it out.

---

## Comments explain why, names explain what

If a comment restates what the code does, the code should be a named function instead. Comments are for: why a decision was made, citing a source, flagging a non-obvious constraint.

---

## Docstrings describe the domain

Use the numpydoc sections — Parameters, Returns, Notes, References.

Parameter entries describe what the parameter means in the problem domain, with units and constraints: `r_h : float — Hydraulic radius (m). Cross-sectional area divided by wetted perimeter.` — not `r_h : float — A number.`

Returns specifies structure and the unit of observation — what one row represents.

Notes captures domain rules, assumptions, and algorithm choice. References cites the equation or method source.

---

## File layout

Public functions live in descriptively named modules (`read.py`, `hydraulics.py`). Internal helpers for a given public function live in the same file, below the function they serve, with a leading underscore.

Migration rule: if a helper becomes useful to a second module, move it to a shared `utils_*.py` at that point — not before. No premature abstraction.

Project structure separates `src/`, `tests/`, `notebooks/`, and `data/`, with `data/raw/` immutable. Notebooks are for exploration and communication only. Any function used more than once, or any transformation that is part of a repeatable workflow, belongs in `src/`.

---

## Type hints

Type hints are documentation, not enforcement. Use them on public function signatures; they are optional on internal helpers. Prefer `str | Path` over bare `str` for anything that takes a filesystem path, and use `pathlib.Path` rather than `os.path`.

---

## Validate at the boundary

Input validation belongs at the top of the public function, before any computation. Raise the specific exception — `FileNotFoundError`, `ValueError` — with a message naming the offending value. Internal helpers assume their inputs are already valid; they do not re-check.

Shared validation logic belongs in a named `_validate_*` helper.

---

## Testing

pytest. Test files mirror source files: `src/pkg/read.py` → `tests/test_read.py`. Shared fixtures go in `conftest.py`.

Install in development mode (`pip install -e ".[dev]"`) before running tests.

Test helpers directly — don't route all tests through the orchestrator just to exercise one piece of logic.

Never assert exact equality on floats. Use `pytest.approx` with an explicit tolerance, and `np.testing.assert_allclose` for arrays.

Test observable behaviour, not implementation details. If the internal algorithm changes but output stays the same, tests should still pass.

---

## Tooling

Ruff for both linting and formatting, configured in `pyproject.toml`. It replaces Black, flake8, and isort. Run it through pre-commit so formatting never falls behind.

---

## Tidy pipeline structure: Add, Summarize, Expand

When writing data transformation functions, structure the pipeline around three operations.

### Add (enrich)

Use `.assign()` to add columns that bring each row closer to self-containment for the target calculation. Data stays in the DataFrame — do not extract columns into free-standing Series or arrays to manipulate outside the chain.

The readiness signal for the next phase: every row contains all the variables the summary function needs.

A grouped transform (`.groupby(...).transform(...)`) is still an "add" operation — it preserves rows while enriching them with group-aware values. This is the pandas equivalent of a grouped `mutate()`.

### Summarize (collapse)

Use `.groupby(...).agg(...)` with named aggregations, then `.reset_index()` so the result is a flat DataFrame rather than one carrying a group index.

```python
annual = (
    daily
    .groupby(["site", "water_year"])
    .agg(peak_q=("discharge_cms", "max"), mean_q=("discharge_cms", "mean"))
    .reset_index()
)
```

Summarization changes the unit of observation. After the call above, each row no longer represents a daily measurement — it represents a site-year. Track this shift explicitly.

Avoid `MultiIndex` results where a flat frame will do. A hierarchical index is a second representation to reason about, and it makes downstream joins and plotting harder to follow.

### Expand (join)

`pd.merge()` brings in data from another table. Two purposes:

- **Enrichment joins** add columns without changing row count (joining reach metadata to a time series by reach ID). These are conceptually similar to `.assign()` — the information comes from another table.
- **Expansion joins** increase rows by broadcasting coarser-grained data to finer-grained observations. This is the inverse of summarization.

Always ask: "What does one row represent?" before and after every join. Pass `validate=` to `pd.merge()` ("one_to_one", "one_to_many", "many_to_one") so an unexpected relationship raises instead of silently multiplying rows and corrupting downstream summaries.

### The summarize-then-rejoin pattern

Compute group-level summaries, then merge them back to observation-level data. Example: compute annual mean discharge per site, classify years as wet/dry/normal, then join that classification back to daily observations. This round-trip is common in environmental analysis.

### Not every function is a pipeline

The Add / Summarize / Expand structure applies to data transformation functions. For everything else, the other principles (pure, one job, validate at boundary) still apply.

---

## Implementation idiom checklist

When writing Python in this project, use:

- `.assign()` over `df["x"] = ...`
- `.pipe()` to insert named helpers into a chain
- `np.where()` for two-way branching; `np.select()` for multi-way
- Method chains wrapped in parentheses, one method per line
- `.reset_index()` after `.agg()` — prefer flat frames to MultiIndex
- `validate=` on every `pd.merge()`
- `pathlib.Path` over `os.path`
- Comprehensions over accumulation loops
- `pytest.approx` and `np.testing.assert_allclose` for floats
- No `inplace=True`, no `.apply(axis=1)`, no `.append()` in a loop
- No free-standing Series extracted from a DataFrame for manipulation outside the chain