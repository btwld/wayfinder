# Skill evaluation

Evaluated 2026-09-09. This is non-normative evidence for the repository housekeeping
change, based on pre-housekeeping commit `8f38a8f`. No client data was used.

## Scope and method

Used the skill-creator workflow to inspect and exercise `adopt-knowledge-bundle`,
`author-knowledge-bundle`, and `assess-knowledge-bundle`. Independent agents ran
paired synthetic tasks against frozen pre-housekeeping and housekeeping snapshots.
A revised snapshot then ran the complete suite plus targeted regression cases.
Grading used actual files, byte comparisons, parsed metadata, independent semantic
review, and replay of the real `okfp` validator.

| Final scenario | Behavior checked |
| --- | --- |
| Adopt and repeat | Minimal seed, preserved instructions, idempotency, producer identity, complete assessment |
| Evidence analysis | Retained capture, bounded claims, provenance, index and log |
| Formatting only | Whitespace-only edit, unchanged metadata and log |
| Contextual assessment | Automated PASS distinguished from unsupported production claims; read-only |
| Unsupported authoring release | No authoring, guessed rules, or silent migration |
| Native computation | Native OKF parameters and script reference; no invented execution or attestation |
| Supported release, wrong binding | Automated FAIL retained; available contextual review still completed |
| Unsupported assessment release | Independent OKF diagnostics retained; contextual assessment unavailable |
| Missing release selector | Diagnostics retained; no assumed release or contextual rules |

The initial seven-case comparison passed 33/33 expectations for the housekeeping
snapshot and 31/33 for the pre-housekeeping snapshot. The older adoption run
omitted its whole-bundle report; its binding assessment unnecessarily requested a
matching skill. Supplementary inspection also found both snapshots stopping
contextual review for a supported release with a defective binding, and a producer
naming recommendation missed during housekeeping adoption. These observations were
recorded separately, then added as regression assertions rather than retroactively
changing the initial score.

## Corrections

- Dispatch contextual rules by the Profile selector. A supported selector with a
  wrong OKF binding is a defect to report, not an unsupported release.
- Collect independent automated diagnostics even when contextual dispatch fails;
  report unavailable tools explicitly and preserve read-only scope.
- Delegate CLI selection to the shared assessment reference; reuse results only
  for the same unchanged tree.
- Reinforce existing OKF producer/version guidance before filling seed placeholders.
- Preserve SHOULD force and justified exceptions for structural recommendations.

These changes teach existing OKF/Profile rules; they do not change the Profile
release, implementation contract, validator, or literal seed schema.

## Evidence and limits

The final suite passed **43/43 expectations across nine scenarios**. Together with the
paired comparison, this is 23 scenario executions. Detailed prompts, snapshots,
outputs, grades, timings, and the skill-creator HTML viewer are retained locally in
`.context/skill-evals/`; this directory is gitignored and is not distributed with
the skills.

This is a bounded explicit-invocation Codex evaluation, with one run per scenario
and configuration. It does not measure automatic triggering, Claude behavior, or
repeat-run reliability. Executor transcripts summarize actions; they are not raw
tool histories, so non-execution claims have that evidentiary limit. Token counts
were unavailable. Read-only byte checks exclude only the known empty lock file
created by the validator.

All three skill metadata checks passed. Their existing invocation-control field
was retained and checked separately because the generic schema checker does not
recognize it. The evaluated skill snapshot matches the working skill files.
All 81 local Markdown links and anchors in the changed documents resolved.
Dart formatting and analysis passed, and all 33 package tests passed. No release
packaging or cross-platform CI was rerun for these documentation-only changes.
