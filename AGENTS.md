# Agent Operating Rules for This Repository

Collaboration philosophy: `docs/lingua.md`
R development principles: `$r-dev` skill / `docs/r-principles.md`
Contract-first workflow: `$contract` skill / `docs/contract-first-development.md`

---

# Security Baseline

The sandbox restricts file writes to this repository. These
rules cover what the sandbox does not.

- Stay inside this repository for all file reads and searches.
  Do not read, list, or search outside the repo — no home
  directory, no system paths, no other projects, no network
  drives.
- Do not read `.Renviron`, `.Rprofile`, or any file likely to
  contain credentials. If you think you need something outside
  the repo, ask.
- Treat all out-of-repository paths as sensitive by default.

# Git Policy

Read-only without approval: `git status`, `git diff`, `git log`.
Everything else — commit, push, pull, branch, rebase, tag, config
— requires explicit approval.

# Interaction Style (Repository Supplement)

The global `~/.codex/AGENTS.md` governs voice and pacing.
These additions apply here:

- Execution is opt-in. Do not run R code unless explicitly asked.
  Inspecting sessions and environments via btw/positron is fine.
- Do not provide downstream steps whose value depends on an
  unverified upstream result.
- When a task is sequential or uncertain, state the immediate
  next step, wait, then continue.
- A short agreed-upon function is better than a long unconfirmed
  implementation.

# How We Work

This is interactive development, not agentic. Default to
proposing before implementing.

When asked to write or modify code:
1. Briefly explain the plan.
2. Wait for confirmation unless the change is trivial.
3. If design choices are unclear, present options and state
   the current lean.

# Agent Inertia

Before a substantial coding action:
1. Identify the governing rules here.
2. Inspect repository code and docs relevant to the task.
3. State what is observed versus inferred.
4. Propose the smallest reasonable next step.

When scope changes, multiple files are edited, or a prior
approach fails — pause and restate the task and next step.

# Tools

| Tool               | Purpose                                          |
|--------------------|--------------------------------------------------|
| btw / positron MCP | R session context, environment, IDE state, files |
| context7 MCP       | Package and library documentation lookup         |
| `.codex/bin/uv.cmd`| Python tooling within the repo (when needed)     |

Do not invoke `python`, `pip`, or `uv` directly.

# R Execution Approval

Allowed without approval: inspecting R sessions, environments,
data structures, package metadata, project files.

Requires approval: sourcing, evaluating, testing, modifying
environment objects, rendering, installing packages. If
execution would help, propose the exact command, explain why,
and wait.

# API Verification

Before using any library function, verify it exists, confirm
its arguments and return value. Use btw/positron for R context,
context7 for package docs. Never guess APIs.

# Testing, Error Handling, Output

- testthat 3e. Mirror test files to source files. Test helpers
  directly. Snapshot conditions. Test behaviour, not internals.
- If a change breaks tests: undo, read the failing test, plan
  before retrying.
- Describe changes concisely. Include diffs when useful. Do not
  dump full files unless asked.

# Skills and Reference Documents

| Skill      | Trigger                                    |
|------------|--------------------------------------------|
| `$r-dev`   | Writing, reviewing, refactoring R code     |
| `$contract`| Contract-first / TDD workflow              |

| Document                             | Contents                    |
|--------------------------------------|-----------------------------|
| `docs/lingua.md`                     | Collaboration philosophy    |
| `docs/r-principles.md`               | R development guide         |
| `docs/contract-first-development.md` | Contract-first workflow     |
| `docs/PROJECT_CONTEXT.md`            | Applied science context     |
