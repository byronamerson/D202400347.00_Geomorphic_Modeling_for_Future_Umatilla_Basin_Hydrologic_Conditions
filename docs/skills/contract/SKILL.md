---
name: contract
description: >
  Contract-first development workflow for R functions. Activate when
  writing new functions using a contract-first, test-second,
  implement-last approach, whether the contract is rendered as Roxygen
  or as a structured comment block. Also relevant for TDD,
  spec-driven, or documentation-first work. Do NOT activate for quick
  exploratory scripts, plotting, data inspection, or tasks where the
  user has not indicated a contract-first or test-driven approach.
metadata:
  short-description: Contract-first, test-driven R development workflow
---

# Contract-First Development Workflow

This skill defines the contract-first, test-second, implement-last
workflow for R functions. In packages, the contract is rendered as
Roxygen. In scripts, it is rendered as a structured comment block with
the same fields. The full research base, references, and extended
discussion are in `docs/contract-first-development.md`.

The philosophical foundation is in `docs/lingua.md`.

---

## The Three Layers

Every function has three specification layers, each in a different
medium:

| Layer | Medium | Purpose |
|-------|--------|---------|
| **Intent** | Natural language (contract) | What the function does, why, domain rules |
| **Behavior** | Executable tests (testthat) | Given inputs, what outputs are expected |
| **Implementation** | Code | The algorithm — written last |

Without the intent layer, tests validate whatever the code happens
to do. Without the behavior layer, intent is unverified prose. The
three layers create a verification chain where errors in one layer
are visible from another.

---

## The Workflow — For Each Function

### 1. Write the contract

- In packages, write a Roxygen block.
- In scripts, write a structured comment block with the same fields.
- Title line states purpose.
- Input descriptions capture domain semantics and constraints.
- Output description defines expected structure.
- Key decisions and assumptions are recorded explicitly.
- Cite methods when they shape the implementation.

Attach the contract to an empty function signature (placeholder body).

### 2. Derive tests from the contract

Each constraint in the contract implies a test:

- "Must be positive" → test negative values are rejected
- "Returns a tibble with columns x, y, z" → test output structure
- "Sentinel rows identified by all-zero values" → test with known patterns

### 3. Run tests and confirm they fail (RED)

This verifies the tests are meaningful and not trivially passing.

### 4. Implement (GREEN)

Write the code — or ask the LLM to write it. Provide the contract
and failing tests as context.

Prompt: "Here is the documentation and the failing tests. Write the
implementation. Do not modify the tests or the contract."

### 5. Run tests and confirm they pass

If they fail, feed the error back and iterate on implementation only.

### 6. Refactor with tests as safety net

Clean up, improve naming, simplify logic. Verify tests still pass.

### 7. Commit on green

---

## The "Marking Your Own Homework" Problem

When an LLM writes code and then writes tests for that code, it
generates tests that validate whatever the code already does — bugs
included. This is the central argument for human-authored tests and
for the intent layer preceding both tests and implementation.

---

## Key Pitfalls

1. **Test modification trap.** LLMs modify tests to match buggy code
   instead of fixing the code. Prevention: lock test files, commit
   tests before implementation, use explicit instructions ("NEVER
   modify test files").

2. **Mocks that hide real bugs.** Minimize mocking. Prefer
   integration tests. Verify mocks match real API contracts.

3. **Overfitting to test cases.** Code passes specific tests without
   a correct general solution. Prevention: property-based testing,
   unhappy-path tests.

4. **Testing implementation, not behavior.** Tests couple to *how*
   code works rather than *what* it does. Prevention: test observable
   inputs and outputs, not internal state.

5. **Trivially passing tests.** Tests that inflate coverage without
   catching real faults. Prevention: always verify the red phase.

---

## What the Human Owns vs. What the LLM Helps With

| Step | Human | LLM |
|------|-------|-----|
| Contract | Author (domain knowledge required) | Can draft from discussion, human refines |
| Test expectations | Author (defines "correct") | Can suggest additional edge cases |
| Test scaffolding | — | Generates boilerplate |
| Implementation | Reviews and approves | Generates, constrained by contract + tests |
| Refactoring | Directs intent | Executes under test safety net |
| Decision recording | Decides what to record | Helps draft commit messages, comments |

---

## Project-Level Practices

- Before starting a feature, discuss the approach in natural language.
  Clarify requirements, decompose the problem, surface edge cases.
- Write a brief spec or design note for non-trivial features.
- Break work into small, independently testable units.

---

## Connection to R Development Principles

This workflow depends on the `$r-dev` skill conventions: pure
functions, one job per function, validation at the boundary, and a
boundary contract rendered appropriately for its context. When this
skill is active, the `$r-dev` conventions are assumed.
