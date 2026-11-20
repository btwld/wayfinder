---
name: dora-profile
description: Apply Dora's source-first retrieval, evidence, lifecycle, session-continuity, and data-minimization procedures when writing or reviewing a bundle whose selected Profile chain includes dora-profile.
---

# Dora Profile guidance

`dora-profile` extends Bitwild. It adds no validator rules or vocabulary. The
selected package chain and OKF decide machine conformance; this skill guides
context-dependent author and reviewer judgment. When this skill is silent, use
OKF and the inherited Bitwild guidance.

## Keep Dora's policies canonical

The policies remain in the Dora vault; do not copy them into the bundle or
publish their vault paths. When exact wording matters, open the bundle's
`Dora policy source map` concept and follow each original through its
`sources[].resource`.

When a concept materially derives from one of these policies, point its
`sources[].resource` to the original path. Do not use a generic scope statement
as a source resource, and do not copy the source merely to make the citation
resolve inside the bundle.

## Retrieve before making claims

For Dora questions, query Second Brain before opening vault files. Then follow
the canonical retrieval order: deterministic vault search, live systems
read-only when relevant, local repositories, and the web last. A semantic
search miss is not evidence of absence; when the question is about a specific
fact, identifier, path, history, or error, also perform a deterministic search
before saying it was not found. Verify claims against the source artifact, not
only its description or an earlier summary. Do not read or include customer or
lead records, credentials, or raw transcripts when policy sources answer the
question.

## Separate evidence from interpretation

Describe what an artifact actually establishes. A policy or note can establish
that it states a rule; it does not by itself establish that a live system
currently follows it. Keep observations, supported conclusions, and open
questions distinct. Use OKF `sources` for material derivation from identifiable
source material. Record `generated` and `verified` only when those facts are
known and actual confirmation occurred. Do not add a confidence, credibility,
maturity, or evidence-tier field to frontmatter; preserve Dora's existing
vault metadata in the source and use OKF's own provenance semantics in the
bundle.

## Preserve ambiguous lifecycle state

Treat stale sessions, uncovered recovery breadcrumbs, and unresolved handoffs
as **preserve — ambiguous** until the evidence and owner-directed resolution
required by the original lifecycle policy exist. Age, repetition, a missing
note, or a plausible narrative does not prove completion. Do not auto-close,
delete, or clear uncertain lifecycle records. A static bundle review cannot
verify current lifecycle state; state that limitation and consult the
authoritative lifecycle record when needed.

## Keep session continuity useful and bounded

After a material change, decision, verification, risk, or milestone, capture a
structured checkpoint with Goal, Actions, Evidence, Decisions, Files changed,
Open items, and Exact next step. At a genuine session boundary, follow the
canonical Dora save protocol. Store concise durable summaries only; exclude raw
transcripts, credentials, authentication material, and raw lead or customer
personal data. A checkpoint records progress; it does not by itself prove a
task was archived, closed, or handed off.

## Review flow

Use the [review map](references/review-map.md) to assess these contextual
judgments. A review concern asks the author to act; it does not change the
`wayfinder validate` result. Do not infer missing policy choices. Escalate an
actual conflict with OKF or the inherited Bitwild Profile instead of changing
either one here.
