# ADR-0004: First implement a closed Concepta Profile validator

- Status: accepted
- Date: 2026-08-21
- Issues: [#17](https://github.com/conceptadev/okf-profile/issues/17)
- Supersedes: [ADR-0001](0001-ack-behind-interpreter-seam.md), [ADR-0002](0002-judgment-parse-and-preserve.md), [ADR-0003](0003-suppressions-in-profile-yaml.md)

## Context

The Concepta OKF Profile earns its place by concentrating company-wide choices
that OKF deliberately leaves to producers. Removing it would scatter those
choices across repositories, skills, and tools. The proposed generic Profile
platform did not pass the same deletion test: with only one real Profile, its
manifest language, provider seam, executable registry, suppressions, and
Profile-aware write path added interfaces for hypothetical consumers rather
than concentrating proven variation.

The Profile also contains two different kinds of convention. Some requirements
can be determined reliably from bundle state; others require contextual
judgment, such as deciding whether a directory names the true subject shared by
its concepts. Treating both as deterministic rules would make the CLI overclaim
what it had proved.

## Decision

The first implementation is a closed Concepta OKF Profile validator layered in
one direction over the public `okf` library. `okf` remains independently
responsible for OKF loading, models, Spec conformance, and generic bundle
operations; it never knows that the Concepta Profile exists.

Only a bundle conforms to the Profile. Repository adoption choices such as the
bundle's location, the number of bundles in a repository, installation, and CI
belong to the implementation guide and setup skills rather than bundle
conformance.

The validator dispatches by the Concepta release selected in `profile.md` and
applies that release's immutable deterministic rules. It exposes the OKF and
automated Profile results separately. A bundle cannot inject, omit, replace, or
parameterize the release's rules.

The CLI may also report deterministic `SHOULD` and `SHOULD NOT` advice, but
advisories do not affect conformance or exit status. The first interface has no
global `--strict` mode that promotes every recommendation into a requirement.

A successful CLI run claims only that OKF conformance and the deterministic
Profile checks passed. It explicitly reports judgment rules as unassessed and
has no model dependency. Complete Profile assessment combines that automated
result with a separate Profile Review; the CLI does not claim complete Profile
conformance on its own.

Normative force and assessment mode are independent. A rule is a `MUST`, `MUST
NOT`, `SHOULD`, or `SHOULD NOT` because of its policy force, not because code can
evaluate it. Deterministic rules are assessed by the CLI; judgment rules are
assessed contextually by humans and agents. The deterministic CLI has no model
dependency and does not claim to prove contextual judgment.

One model-invoked `okf-profile` skill owns both the authoring and post-write
Profile Review workflows. It teaches only the Concepta delta and explicitly
delegates OKF mechanics to the OKF documentation and tools. Other engineering
skills delegate to it rather than copying its rules, because copied upstream or
Profile instructions can drift.

The normative Profile states bundle rules without naming their implementation.
The implementation guide carries an exhaustive coverage matrix mapping every
normative clause to deterministic CLI validation or contextual Profile Review,
and the skill implements the review side of that mapping. Assessment mode is
therefore explicit without making tool architecture part of bundle conformance.

A generic Profile protocol and the related machinery are deferred until real
use supplies at least a second Profile or another concrete trigger recorded in
issue #17.

## Consequences

- The first implementation has no public Profile provider seam, executable rule
  registry, caller-selected activation, or standalone Profile Definition YAML.
- Suppressions wait for a migration that demonstrates their need and governance.
- Profile-aware MCP writes and Profile-owned filesystem transactions wait for a
  concrete authoring workflow that plain OKF operations cannot support.
- `profile.md` remains the in-bundle release declaration and ordinary OKF
  concept; it does not become a rule configuration surface.
- The first `okfp` interface validates only. Authoring and generic bundle
  mutation are not added to it.
- `okfp validate` obtains and exposes the closed OKF validation result before
  applying Concepta checks. Running `okf validate` separately remains useful for
  focused base diagnostics but is not required for a complete Profile gate.
- The next Profile release and implementation slices must be reshaped through a
  new design session rather than revived from the superseded issue set.
