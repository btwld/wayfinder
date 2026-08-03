---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets. Be compliant with /comment-cleanup rules.

Before writing code, check the knowledge bundle: start at `knowledge/index.md`, open the area covering what you're changing, and read its index — the Glossary Definitions give you its vocabulary and the Business Rules, Decisions, and Questions there constrain the approach. `knowledge/architecture/` carries system-wide structure and ADRs.

Use test-driven development where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

## Review — fresh eyes

Spawn a subagent (Agent tool, `general-purpose`) to run the `thermo-nuclear-code-quality-review` skill against the current branch's changes — committed and uncommitted. Read-only: it changes no files, and returns prioritized findings and an approve/block verdict as its final message.

Address the findings yourself in the main context — you hold the spec context the reviewer lacks. Then spawn a fresh reviewer to confirm. Repeat until a reviewer approves or only explicitly justified waivers remain.

## Simplify — fresh eyes

Spawn another subagent to run the `simplify` skill scoped to this branch's changes; it may edit files. If that skill is unavailable to it, have it apply reuse, simplification, and efficiency cleanups directly, preserving behavior.

Re-run typechecking and the full test suite after it returns.

## Commit

/caveman-commit your work to the current branch. If you're in `main` or not in a git flow branch, then /git-flow-branch-creator first.

## Link knowledge to execution

If this work implements a bundle concept — a Request, Decision, or ADR — add an `Implemented by` relationship bullet on that concept pointing at the PR (or branch), following the `concepta-okf-profile` skill for the edit and its log entry. The tracker and PR stay authoritative for execution state: link, never mirror it into the bundle.
