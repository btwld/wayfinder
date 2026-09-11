# ADR-0013: A `captures/` evidence layer beside the bundle, and `Source Document` pointers inside it

- Status: proposed
- Date: 2026-09-11

## Context

The Profile governs stored knowledge and deliberately leaves source ingestion out
of scope (§1.2: "no transcript pipeline, outcome detection, or classification is
specified"). The first client-project adoption showed what fills that gap when
nothing is specified. The project arrived with 31 raw files — meeting transcripts
in `.docx`, Basecamp thread exports, a slide deck, and the client's own
specifications and sample data — in an `assets/` folder nobody had designed. The
first authoring pass produced 28 concepts and drifted in two ways:

1. **Restating authoritative documents.** Five concepts paraphrased the client's
   own specifications (a file-naming document, a comparison rule, a field
   dictionary). Each made the bundle a second lifecycle owner for a document the
   client maintains — the two-sources-of-truth drift §1 opens with — and each
   would silently go stale. §7.3 does not reach these: its test is whether a
   tracker owns the artifact's state, and none of them has one. §12 does, and
   keeps them external behind a followable `sources[].resource`.
2. **Losing the event context.** The Profile rightly bans routine minutes as
   concepts (§4.1, §4.3), but that leaves nowhere to record who was in a
   meeting, what it contradicted, what it did *not* settle, and which files it
   delivered. That context was reconstructed from scratch during authoring and
   would be reconstructed again by the next agent.

Both fixes exist as prior art. The LLM Wiki pattern the Profile cites (§1.4)
keeps an immutable raw layer beside the compiled wiki, with a summary page per
ingested source. Other Concepta projects keep dated evidence packages with an
`analysis.md` each. ADR-0006 gives *mirrored* originals a `raw/` tier — but only
under `references/`, only when a concept cites them and their availability is at
risk (§12), and never as summaries of source events, because every markdown file
inside the bundle is a concept.

## Decision

Propose, for the next Profile release and for the skills now:

1. **A `captures/` directory beside the bundle**, outside it, holding one dated
   package per source event or delivery: `captures/<YYYY-MM-DD>-<channel>-<slug>/`
   with `<channel>` one of `meeting`, `thread`, `delivery`. The date is when the
   event happened — meeting day, thread start, or the day files were received —
   never the capture day. Originals keep their file names and are never edited; a
   growing thread gets a new dated export file.
2. **An `intake.md` per package** (not a concept; `captures/` is not a bundle):
   channel, date, participants, originals with hashes, sensitivity, a short
   summary, which concepts it fed, what it contradicts, what it leaves open. This
   is where per-event summaries live, so the §4.1 bar inside the bundle can stay
   strict.
3. **A `Source Document` concept type**, registered per project now (§5.2) and a
   candidate standard type for the next release. It points at an authoritative
   document kept in `captures/` through OKF `resource`, and its body says only
   what the document covers and where later evidence differs. The document is
   never restated. This gives the "one artifact, one home" rule of §7.3 a
   concrete shape for documents a client owns.
4. **`adopt-knowledge-bundle` seeds the layer**: `captures/index.md`, the
   `intake.md` template, and an `AGENTS.md` block stating the authority rule —
   captures are evidence, the bundle is canonical, and when they disagree the
   capture is re-read and the concept fixed.

Confirmation stays a status change inside the bundle (`draft` → `stable` plus
`verified`), never a move between layers.

## Why outside the bundle

- OKF makes every markdown file in a bundle a concept. Event summaries and
  intake notes are not durable knowledge and must not become concepts, so they
  cannot live inside.
- §12 permits mirroring only when availability is at risk. Files already
  committed to the repository are not at risk; copying them into `references/`
  would be "mirroring because a meeting happened".
- Transcripts carry commercial terms and member-level data. Keeping them out of
  the bundle keeps them out of Wayfinder's index and out of cited answers.
- The bundle stays a pure OKF bundle for any consumer; `captures/` is invisible
  to OKF tooling by construction.

## Consequences

- Existing conformant bundles stay conformant: nothing inside the bundle
  changes except an optional registered type.
- Projects without external source material simply omit `captures/`.
- Projects wanting captures searchable can serve `captures/` as a second,
  separate Wayfinder bundle; this ADR does not require it.
- The intake note's "fed into" list is maintained by hand. A later tool could
  derive it from `sources` back-references; not in scope.
- Open for the release process: whether `Source Document` becomes a standard
  row in `types.md` (§5.2) and whether §12 gains a sentence pointing at the
  layer for material that is *not* mirrored.
