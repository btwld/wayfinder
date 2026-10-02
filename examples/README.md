# Examples

[`bitwild/`](bitwild/) is a complete project you can read end to end in a few minutes.
It holds a `wayfinder.json` binding at the project root and a conformant bundle
under `knowledge/`. It is the worked example from the profile's Appendix A, kept as real files.
Run the shipped gate from the repository root:

```bash
wayfinder get examples/bitwild
wayfinder validate examples/bitwild/knowledge
```

With a Dart SDK instead of the installed binary, `dart run wayfinder_cli:wayfinder`
replaces `wayfinder` in both commands.

`get` resolves the binding's Profile source into `wayfinder.lock`. `validate` reads
only that lock and its cache, never the network, so without `get` it reports
`wayfinder/profile-unresolved` and gate `INCOMPLETE`. After `get` the gate is
`PASS` with two notes that never change it. A summary entry names the deliberately
unresolved `pagination-contract.md` relationship target, and the
`wayfinder/project-type` diagnostic names the declared `Meeting Transcript` type.

Success proves OKF conformance and the deterministic Profile rules only.
Complete Profile conformance also requires the contextual Profile Review
defined by the canonical skill.

The source checkout commits no lock, because the binding follows a branch. CI's
[`verify-configured-example.py`](../tool/ci/verify-configured-example.py) copies
the project to a temporary directory, resolves a synthetic local Git source,
checks the gate, confirms that `--fix` writes nothing, and confirms that generic
graph reading needs no lock.

[`acme-notes/`](acme-notes/) is a project that uses
[`profiles/two-rule/`](profiles/two-rule/), a Profile with two rules and no
parent. Its lock holds that one package; nothing in it depends on Bitwild.
[`profiles/two-rule-child/`](profiles/two-rule-child/) is a Profile that
builds on Bitwild. Its package names `profiles/bitwild` as its parent without
`git`, which means the same repository at the same commit, so a project names
only the child and `get` locks both packages at one commit. CI's
[`verify-independent-profile.py`](../tool/ci/verify-independent-profile.py)
resolves both from a synthetic local Git source, checks the lock and the
reported chain, and validates after the source is gone, because validation
reads only the lock and the cache.

**This is not this repository's adopted bundle.** Profile conformance does not
fix repository location or bundle count; Concepta adoption places its working
bundle at `knowledge/`. This illustrative project lives under `examples/` so it
cannot be mistaken for the standard's own durable knowledge.

## The story it tells

A client raises a request during a demo. The recording platform expires in 30 days, so the
transcript is mirrored. An analysis follows. The request is specified in GitHub.

```text
bitwild/
  wayfinder.json                        # Profile source, project type, tags, relationship name, actors
  knowledge/
    index.md                            # Root index, carries okf_version
    log.md                              # Knowledge lifecycle events only
    reporting/
      index.md                          # Generated navigation
      include-pdf-annotations.md        # Request
      pdf-export-feasibility.md         # Analysis
    ways-of-working/
      index.md
      relationship-labels.md            # Guide explaining the project relationship assessed-by
    references/
      index.md
      2026-07-30-reporting-demo-transcript.md   # Mirrored, immutable
      annotation-layout.json                    # Referenced non-Markdown asset
```

What to look for:

- **A source event is not a concept.** The demo produced a request, and an analysis
  followed, but there is no interpreted record of the event itself. No Interaction Record was
  written, because its combined context was not independently durable. The request
  links straight to the mirrored source artifact (§4.3).
- **Execution stays external.** The request carries a `specified-by` relationship toward a
  GitHub issue. The issue's state is never copied into the bundle (§7.3).
- **Relationships are frontmatter, beside the OKF graph.** Each `relationships` entry
  names one relationship and one resource. The request's project-specific `assessed-by`
  is declared in `wayfinder.json`, so the Profile accepts it, and a durable Guide
  explains it once. The analysis deliberately points `constrained-by` at a
  not-yet-written pagination contract. The Profile reports that unresolved target as a
  summary entry, which never changes the gate (§7.2, §13, §14.1).
- **Provenance is per-claim.** The request's one substantive sentence carries a footnote keyed
  to a `sources[].id`, so the claim points at the transcript rather than the concept vaguely
  citing it (§6.1).
- **A mirror is a source concept, not an interpreted outcome.** The transcript
  preserves an artifact from the interaction; an Interaction Record would interpret
  its combined context. It is mirrored only because a durable concept cites it and
  the recording expires, after confirming the content is suitable for repository
  visibility. Mirroring is pull-based. It never happens just because a meeting occurred (§12).
- **Assets stay assets.** The layout sample is referenced through `sources` and has no
  concept frontmatter. The generated `references/` index lists only the transcript, so
  the asset never needs an invented title or description (§9, §12).
- **A declared type catches invention.** `Meeting Transcript` is not in the standard
  vocabulary, so the project declares it in `wayfinder.json` `types`, and validation
  names it in the `wayfinder/project-type` note. An undeclared type fails, which stops a
  typo'd type from passing as a new kind of thing (§5.2).
- **Affiliation is never trust.** `wayfinder.json` holds one record per actor id, so
  the transcription process keeps only its current vendor record. A dated affiliation
  history cannot live in the binding; a project that needs one records it as ordinary
  knowledge. The recording platform's side stays explicitly `unknown`. None of this
  changes the OKF actor strings or their prefix-derived trust tiers (§6.1.1).
- **Absence of `verified` is a signal, not a defect.** Three of the four concepts are
  unverified and validation reports no finding for it. The only way to clear such a
  report would be to record a verification that did not happen (§6.2, §14.1).

## Why there is a small subject directory

The request and analysis share the reporting subject, so both live in `reporting/`.
Two concepts are enough when the subject is genuine: a count cannot prove or
disprove the placement, and waiting for a third would create avoidable path churn.

There is no `requests/` or `analyses/` either, and there never will be: those name *kinds*, and
kind is carried by `type`. Reading every request as a set is an index filtered by type, not a
directory (§13).

The directory was not seeded speculatively: the two durable concepts provide the
corpus from which the subject was observed. Every index is the OKF reference
generator's output, written by `wayfinder validate --fix`. `reporting/index.md`
groups its concepts by type, and the root index lists the directory under
`# Subdirectories` with a generated summary instead of an authored description.
The root index does not list `log.md`: the authored log is history, not another
generated projection.
