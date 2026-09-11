# Examples

[`knowledge/`](knowledge/) is a complete, conformant bundle you can read end to end in a few
minutes. It is the worked example from the profile's Appendix A, kept as real files.
Run the shipped automated gate from the repository root:

```bash
okfp validate examples/knowledge
```

With a Dart SDK instead of the installed binary, `dart run wayfinder_cli:wayfinder validate
examples/knowledge` is equivalent.

Success proves OKF conformance and the deterministic Profile 2026.1 rules only.
The command reports Judgment Rules as `UNASSESSED`; complete Profile conformance
also requires the contextual Profile Review defined by the canonical skill.

**This is not this repository's adopted bundle.** Profile conformance does not
fix repository location or bundle count; Concepta adoption places its working
bundle at `knowledge/`. This illustrative bundle lives under `examples/` so it
cannot be mistaken for the standard's own durable knowledge.

## The story it tells

A client raises a request during a demo. The recording platform expires in 30 days, so the
transcript is mirrored. An analysis follows. The request is specified in GitHub.

```text
knowledge/
  index.md                            # Root index, carries okf_version
  log.md                              # Knowledge lifecycle events only
  profile.md                          # Profile and OKF versions
  types.md                            # All standards plus one registered extension
  actors.md                           # Actors with dated history and unknown affiliation
  reporting/
    index.md                          # Generated semantic navigation
    include-pdf-annotations.md        # Request
    pdf-export-feasibility.md         # Analysis
  ways-of-working/
    index.md
    relationship-labels.md            # Guide defining the project label Assessed by
  references/
    index.md
    2026-07-30-reporting-demo-transcript.md   # Mirrored, immutable
    annotation-layout.json                    # Referenced non-Markdown asset
```

What to look for:

- **A source event is not a concept.** The demo produced a request, and an analysis
  followed, but there is no interpreted record of the event itself. No Interaction Record was
  written, because its combined context was not independently durable — the request
  links straight to the mirrored source artifact (§4.3).
- **Execution stays external.** The request carries `Specified by` toward a GitHub issue. The
  issue's state is never copied into the bundle (§7.3).
- **Relationships are body context over ordinary OKF edges.** Each labelled bullet
  has one target. The request's project-specific `Assessed by` label is defined once
  in a durable Guide and produces only a non-blocking advisory. The analysis
  deliberately links to a not-yet-written pagination contract: OKF still exposes that
  untyped edge, and the Profile reports the unresolved target only as a non-blocking
  advisory (§7, §13, §14.1).
- **Provenance is per-claim.** The request's one substantive sentence carries a footnote keyed
  to a `sources[].id`, so the claim points at the transcript rather than the concept vaguely
  citing it (§6.1).
- **A mirror is a source concept, not an interpreted outcome.** The transcript
  preserves an artifact from the interaction; an Interaction Record would interpret
  its combined context. It is mirrored only because a durable concept cites it and
  the recording expires, after confirming the content is suitable for repository
  visibility — pull-based, never merely because a meeting occurred (§12).
- **Assets stay assets.** The layout sample is referenced through `sources`, has no
  concept frontmatter, and appears under the `Assets` index group with a path-derived
  label and no invented description (§9, §12).
- **`types.md` catches invention.** `Meeting Transcript` is not in the standard vocabulary, so
  it needed a row. That is the mechanism that stops a typo'd type from passing as a new kind of
  thing. All fourteen standard rows remain seeded even when unused, so authors see the
  canonical choices before inventing an extension (§5.2).
- **Affiliation is time-aware and never trust.** The transcription process has
  non-overlapping internal and vendor periods, while an undated source author stays
  explicitly `unknown`. The July generation event resolves to the internal row; none
  of this changes the OKF actor strings or their prefix-derived trust tiers (§6.1.1).
- **Absence of `verified` is a signal, not a defect.** Six of the seven concepts are unverified
  and the verifier reports it as information, never as a finding — the only way to clear such a
  report would be to record a verification that did not happen (§6.2, §14.1).

## Why there is a small subject directory

The request and analysis share the reporting subject, so both live in `reporting/`.
Two concepts are enough when the subject is genuine: a count cannot prove or
disprove the placement, and waiting for a third would create avoidable path churn.

There is no `requests/` or `analyses/` either, and there never will be: those name *kinds*, and
kind is carried by `type`. Reading every request as a set is an index filtered by type, not a
directory (§13).

The directory was not seeded speculatively: the two durable concepts provide the
corpus from which the subject was observed. Its index groups concepts under exact
registered types in registry order, while the root index derives the directory
label from `reporting/` and supplies no authored description. The authored log is
history, not another generated projection.
