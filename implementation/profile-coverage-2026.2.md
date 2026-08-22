# Concepta Profile 2026.2 implementation coverage

Status: Integration draft — incomplete and unpublished

This non-normative matrix assigns each normative Concepta Profile 2026.2 bundle
rule to its assessment mode. It does not decide whether a rule preserves OKF;
that evidence lives in
[`../docs/compatibility/2026.2-okf-0.2.md`](../docs/compatibility/2026.2-okf-0.2.md).
The Profile remains the source of every rule and its normative force.

## Assignment rules

- A **Deterministic Rule** is assessed by `okfp validate` from bundle state and
  the immutable declared release.
- A **Judgment Rule** is assessed contextually by Profile Review.
- Normative force and assessment mode are independent: mandatory rules may
  require judgment, and deterministic recommendations remain advisories.
- Each normative bundle clause must appear exactly once. A release-governance or
  implementation-only clause is identified separately and is not disguised as
  a bundle check.

## Release-frame coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §11: a Profiled Bundle contains root `profile.md` of type `Knowledge Profile` | MUST | Automated Profile Validation | Presence, path, and parsed type |
| §11: the first body `yaml` block is the declaration and declares `concepta_profile: "2026.2"` and `okf_version: "0.2"` | MUST | Automated Profile Validation | Parsed block position, selector, and exact values |
| §11: declaration OKF version agrees with root index | MUST | Automated Profile Validation | Equality of both parsed values |
| §11: `profile.md` is not used as a standalone definition, extension registry, second schema, or OKF override | MUST NOT | Profile Review | Contextual review of declaration content |

## Non-bundle frame clauses

These clauses constrain releases, migrations, or implementations rather than a
bundle at rest, so they do not receive a fabricated bundle assessment mode.

| Clause | Owner | Evidence |
| --- | --- | --- |
| Profile preamble: do not publish the integration draft before #19 verifies every release surface | Release integration | #19 publication review |
| §14.1: keep OKF conformance, Profile conformance, Automated Profile Validation, Profile Review, and Complete Profile Assessment distinct | Implementation guide | Guide §§4.1 and 4.5; validator contract tests in #26–#28 and #20 |
| §15.1: every normative Profile rule passes the five-part OKF compatibility test | Release integration | One reviewed row per rule in the compatibility review |
| §15.1: do not publish while compatibility or coverage evidence is incomplete | Release integration | #19 completeness review of both artifacts |
| §15.1: do not claim compatibility with an unreviewed OKF release | Release integration | Release binding and compatibility review identify the same pinned OKF release |
| §15.2: precedence and migration impact remain explicit for every release | Release integration | Profile binding and §15.3 migration text |
| §15.3: a 2026.1 bundle completes every published 2026.2 migration action before changing its declaration | Migration implementation | Whole-bundle migration review after publication |

Unsupported-release behavior and caller-policy prohibitions are implementation
rules owned by guide §§4.1, 4.2, and 4.4. They are tested by the validator
delivery slices and are not restated as Profile bundle clauses.

## Completion gate

This matrix is intentionally incomplete while the canonical Profile still
contains unaligned 2026.1 domain text. Issues #23, #24, and #25 MUST inventory
and assign every retained or introduced normative bundle clause in their scope.
Issue #19 MUST verify exact, duplicate-free coverage before publication. No
unlisted rule is implicitly covered.
