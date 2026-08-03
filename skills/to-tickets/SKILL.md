---
name: to-tickets
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker — edges as text in one file per ticket locally, or native blocking links on a real tracker.
disable-model-invocation: true
---

# To Tickets

Break a plan, spec, or conversation into a set of **tickets** — tracer-bullet vertical slices, each declaring the tickets that **block** it.

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-repo` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the vocabulary from the bundle's Glossary Definitions, and respect the Business Rules, Decisions, and ADRs in the area you're touching — start at `knowledge/index.md`, open that area, and read its index.

Look for opportunities to prefactor the code to make the implementation easier — "make the change easy, then make the easy change." Each prefactor becomes its own structural ticket, separate from the behavioural slices it unblocks.

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) — vertical, NOT a horizontal slice of one layer. Vertical slices touch disjoint files, so they rarely conflict; horizontal slices (all the DB, then all the API) collide in the same shared layer files — avoid them.
- A completed slice is demoable or verifiable on its own.
- Each slice fits in a single fresh context window — and, since each slice becomes a human-reviewed PR, stays reviewable. Count only the **behavioural** lines: the logic that changes what the system does, *not* generated code, fixtures, config, boilerplate, or the structural churn split into its own tickets (a slice's raw diff is usually 2–3× its behavioural core). Aim for ~400 behavioural lines, and split any slice whose behavioural core would run past ~600 — the point where review turns from reading into skimming. Structural diffs can be far bigger and still trivial to review; the ceiling is on behaviour.
- **One kind of change per ticket.** A ticket is *either* structural (moves, renames, extractions, prefactoring, scaffolding — no behaviour change) *or* behavioural (changes what the system does) — never both. A structural diff signs off as "no behaviour change" in seconds; a rename hidden inside a logic change is what makes a diff exhausting to review.
- **Land the contract first.** Types, interfaces, signatures, and schema go in the opening ticket, before any behavioural slice — it reviews trivially (a boundary, not logic) and freezes the interface so later slices build against a stable target instead of renegotiating it, which keeps dependency chains shallow.

</vertical-slice-rules>

So the natural order is **contract → structural/prefactor → behavioural slices**, each behavioural slice a thin vertical tracer bullet.

Give each ticket its **blocking edges** — the other tickets that must complete before it can start. A ticket with no blockers can start immediately. The contract and structural tickets are the blockers of the behavioural slices that depend on them, so the blocking graph naturally sequences contract-first and structural-first.

**Wide refactors are the exception to vertical slicing.** A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Don't force it into a tracer bullet; sequence it as **expand–contract**. First expand: add the new form beside the old so nothing breaks. Then migrate the call sites over in batches sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand, keeping CI green batch to batch because the old form still exists. Finally contract: delete the old form once no caller remains, in a ticket blocked by every migrate batch. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket — green is promised only there.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

### 5. Publish the tickets to the configured tracker

Publish the approved tickets. **How** depends on the tracker `/setup-repo` configured — the tickets are the same either way, only the shape of the blocking edges changes:

- **Local files** → write one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on. Use the per-ticket file template below — one ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → publish one issue per ticket in dependency order (blockers first) so each ticket's blocking edges can reference real identifiers. Use the platform's native blocking / sub-issue relationship where it has one; otherwise set each ticket's "Blocked by" to the blocking issues. Apply the `afk` and `ready` triage labels unless instructed otherwise — the tickets are agent-grabbable by construction.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do NOT close or modify any parent issue.

### 6. Link knowledge to execution

If the work traces to a bundle concept — usually one of `type: Request` — add a `Specified by` relationship bullet on that concept pointing at the parent spec or issue, following the `concepta-okf-profile` skill for the edit and its log entry. Link individual tickets only when a single ticket alone delivers the concept. The tracker stays authoritative for execution state: link, never mirror ticket state into the bundle.

A ticket that **chases an open item** rather than delivering a concept takes `Tracked by` instead: a `type: Question` concept holds the question, what is known, and its evidence trail, while the issue holds who owes the answer and by when. Openness is still read from inbound `Resolves` / `Partially resolves` edges, never from the ticket's status.

<local-ticket-template>

# <NN> — <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective — not a layer-by-layer implementation list.

**Kind:** behavioural — or `structural` for a moves/renames/scaffolding/contract ticket (no behaviour change).

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None — can start immediately".

**Audience:** afk

**Status:** ready

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

</local-ticket-template>

<issue-template>

## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

## Kind

`behavioural` — or `structural` (moves/renames/scaffolding/contract, no behaviour change).

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective — not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

- A reference to each blocking ticket, or "None — can start immediately".

</issue-template>

In either form, avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

Work the frontier one ticket at a time, clearing context between tickets.
