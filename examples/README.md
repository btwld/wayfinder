# Examples

[`knowledge/`](knowledge/) is a complete, conformant bundle you can read end to end in a few
minutes. It is the worked example from the profile's Appendix A, kept as real files so you can
run the verifier against it:

```bash
cd examples && python3 ../tools/verify_knowledge_bundle.py --strict .
```

**This is not this repository's bundle.** A repository owns exactly one bundle, rooted at
`knowledge/` (profile §3). This one is illustrative material that happens to be shaped like a
bundle, and it lives under `examples/` so it can never be mistaken for the standard's own
durable knowledge.

## The story it tells

A client raises a request during a demo. The recording platform expires in 30 days, so the
transcript is mirrored. An analysis follows. The request is specified in GitHub.

```text
knowledge/
  index.md                            # Root index, carries okf_version
  log.md                              # Knowledge lifecycle events only
  profile.md                          # Profile and OKF versions
  types.md                            # Every type in use, including the one added
  actors.md                           # Three actors: a person, an agent, a process
  include-pdf-annotations.md          # Request
  pdf-export-feasibility.md           # Analysis
  references/
    index.md
    2026-07-30-reporting-demo-transcript.md   # Mirrored, immutable
```

What to look for:

- **A source event is not a concept.** The demo happened; it left behind a request and an
  analysis, and no record of itself. No Interaction Record was written, because only one
  outcome mattered — so the request links straight to its source (§4.3).
- **Execution stays external.** The request carries `Specified by` toward a GitHub issue. The
  issue's state is never copied into the bundle (§7.3).
- **Provenance is per-claim.** The request's one substantive sentence carries a footnote keyed
  to a `sources[].id`, so the claim points at the transcript rather than the concept vaguely
  citing it (§6.1).
- **A mirror is not knowledge.** The transcript *preserves* an interaction; a concept
  *interprets* one. It is mirrored only because the recording expires — pull-based, never
  because a meeting occurred (§12).
- **`types.md` catches invention.** `Meeting Transcript` is not in the default vocabulary, so
  it needed a row. That is the mechanism that stops a typo'd type from passing as a new kind of
  thing (§5.2).
- **Absence of `verified` is a signal, not a defect.** Five of the six concepts are unverified
  and the verifier reports it as information, never as a finding — the only way to clear such a
  report would be to record a verification that did not happen (§6.2, §14.1).

## Why there are no subject directories

This is the part most readers expect to find and shouldn't. The two subject concepts — the
request and the analysis, as distinct from the root registries the verifier also counts —
share a subject, reporting, and an area is earned at **three** (§3.1 rule 3). Two is not three, so they sit at
the bundle root, and there is no `reporting/`.

There is no `requests/` or `analyses/` either, and there never will be: those name *kinds*, and
kind is carried by `type`. Reading every request as a set is an index filtered by type, not a
directory (§13).

When a third reporting concept arrives, `reporting/` is created and all three move into it in
one logged operation — inbound links repointed, indexes regenerated, a `**Move**` entry each
(§8.2, §10). Their `status` is irrelevant to that; what freezes a path is citation from outside
the bundle, not review state.

A set cannot be named before it is observed. That is the whole argument for waiting, and this
bundle is what waiting looks like.
