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

The validator dispatches by the Concepta release selected in `profile.md` and
applies that release's immutable enforceable requirements. It exposes the OKF
and Profile results separately, and its composed validation succeeds only when
both are conformant. A bundle cannot inject, omit, replace, or parameterize the
release's rules.

Judgment-heavy conventions remain available to authors and agents through the
normative Profile, skills, and guides, but the deterministic CLI does not claim
to prove them. The Profile must distinguish enforceable requirements from
judgment guidance as its next release is shaped.

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
- The next Profile release and implementation slices must be reshaped through a
  new design session rather than revived from the superseded issue set.
