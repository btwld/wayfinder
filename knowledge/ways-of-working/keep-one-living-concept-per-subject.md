---
type: Decision
title: Keep one living concept per subject
description: Every concept states current truth and is edited in place; nothing is deprecated or superseded, and the `current-truth` Profile enforces it.
status: stable
generated: { by: claude-code/fable-5, at: "2026-11-18T13:53:00Z" }
sources:
  - resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#architecture-decision-log
    title: Architecture decision log, header
  - resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/adr/README.md
    title: Architecture decisions
---

# Decision

## One concept states current truth for a subject

Each subject has one concept under `knowledge/`. The concept says what holds
now, in present tense. A Decision or an Architecture Decision Record states
its rules under `# Decision`, with one `##` heading per rule when it holds
more than one. A rule says what is chosen, why, and what it costs. Cite a rule
by the concept path and the heading anchor, for example
`knowledge/ways-of-working/keep-one-living-concept-per-subject.md#a-concept-names-no-successor`.

## A change edits the owning concept in place

A changed decision rewrites the rule where it stands. The position that lost
becomes one bullet under `# Rejected` that says what it was and why it lost.
The change adds one `Update` entry to [the log](../log.md), and a new concept
adds one `Creation` entry. Git and the pull request hold the earlier wording.
A concept carries no dated history and no amendment section. Review holds
that shape.

## Retired record numbers live only in sources

A concept that absorbs a numbered record cites it as a `sources` entry with
`id: adr-00NN` and a permalink pinned at a commit. No concept takes a record
number as its id, and no body names one.
`grep -rl 'id: adr-00NN' knowledge/` names the concepts that own a number.

## A concept is never deprecated

No concept has `status: deprecated`. A subject that no longer holds is
deleted, and Git holds what it said. A retired word is listed under `# Avoid`
in the concept of the term that replaces it. The `current-truth` rule
`a-concept-is-never-deprecated` reports a violation as an error.

## A concept names no successor

No concept carries a `superseded-by` relationship. Every concept in the bundle
is current truth, so none points at another as its replacement. The
`current-truth` rule `a-concept-names-no-successor` reports a violation as an
error.

# Why

An unattended agent acts on whichever single document it opens. A chain of
records, or a deprecated concept beside its successor, lets that one read land
on a rule that no longer holds. A query returns every status unless the caller
filters ([structured queries](../../docs/queries.md#filters-and-columns)), and
in search "all lifecycle states remain eligible"
([CLI guide](../../packages/wayfinder_cli/README.md)).

The two rules a tool can check are data in the `current-truth` Profile
package, [`.wayfinder/profile/wayfinder-profile.json`](../../.wayfinder/profile/wayfinder-profile.json),
which extends Bitwild. The engine evaluates them, so the CLI, MCP and SARIF
give the same verdict. Each rule id is the slug of its heading above, so a
finding's help link opens the rule. Plain Bitwild does not hold this model. It
declares `superseded-by` as a standard relationship and accepts `deprecated`
as a status ([status-value](../../profiles/bitwild/README.md#status-value)),
so it passes both shapes.

This model departs from Bitwild's guidance in two places. Bitwild itself does
not change.

- [Migration invariant 3](../../profiles/bitwild/skill/references/migration.md#three-invariants),
  "Supersession is preserved, not deleted". Superseded material does not
  migrate as deprecated concepts, because a deprecated concept stays one
  search hit away from a reader that does not filter by status.
- [Retirement](../../profiles/bitwild/skill/references/structure.md#retirement)
  and review checks I7 and I9 of the
  [review map](../../profiles/bitwild/skill/references/review-map.md), which
  ask an author to deprecate a retired stable concept and to justify a hard
  delete. Here a retired subject is deleted, for the same reason.

# Rejected

- Immutable numbered records that supersede one another. A reader walks a
  chain to find current truth, and one record read alone can state a rule
  that no longer holds.
- A deprecated concept kept for each retired record or term. Its title stays
  in the indexes and the search results beside the concept that replaces it.
  No term is retired today, and a retired word fits in the `# Avoid` list of
  the live term.
- An `amended-by` relationship between records. The subject stays spread over
  two concepts, and a reader who opens one of them misses the other.
- The model stated in prose only. Plain Bitwild passes both rejected shapes,
  so nothing would stop them.
- A script that applies its own rules beside `wayfinder validate`. It gives a
  second verdict that the CLI, MCP and SARIF do not report, in the repository
  that ships the rule engine.
- A rule against amendment headings. The engine's `headings` fact reads
  top-level headings only
  ([`body.dart`](../../packages/wayfinder/lib/src/rules/body.dart)), so the
  rule cannot see a `## Amendment` heading.
