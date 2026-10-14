# ADR-0004: Validate a closed Profile over OKF

- Status: accepted
- Date: 2026-08-21
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0004-closed-concepta-profile-validator.md))
- Scope: first Concepta Profile validator; in-bundle selection through 2026.2
- Superseded in part by [ADR-0014](0014-external-profile-bindings.md) for Profile 2026.3
- Superseded in part, if accepted: by [ADR-0015](0015-profile-rule-catalogs.md), which replaces the compiled rule representation with rule catalogs evaluated by a closed engine; the OKF boundary, closed validator, exact-release dispatch and four-part result stand
- Driver: [Profile specification](https://github.com/btwld/wayfinder/issues/21) and [validator delivery](https://github.com/btwld/wayfinder/issues/20)
- Deferred exploration: [#17](https://github.com/btwld/wayfinder/issues/17)

This record describes the historical design through [Profile 2026.2](../../profile/versions/okf-profile-2026.2.md); [Profile 2026.1](../../profile/versions/okf-profile-2026.1.md) is also preserved. Read [ADR-0014](0014-external-profile-bindings.md) and the [proposed Profile](../../profile/okf-profile.md) for 2026.3 behavior.

## Context

OKF defines the interoperable bundle. The Profile adds producer conventions
that OKF leaves open. A generic Profile platform would have added a manifest
language, provider seam, executable registry, and suppressions for hypothetical
consumers, while only one Profile had demonstrated use. The first validator
also needed to distinguish checks decidable from bundle state from judgments
that require project context.

## Decision

Implement a closed Profile validator on the public `okf` library. OKF owns
loading, models, Spec conformance, and graph behavior; it has no Profile
dependency. Profile rules may narrow an OKF-permitted producer choice, but
must add no OKF field or meaning, alter no reserved-file or graph contract,
leave OKF findings independent, and preserve tolerant reading.

Only bundles conform to the Profile. Repository location, installation, and
CI are implementation choices. The Profile is selected by its exact release;
unknown releases are `UNSUPPORTED`, not silently treated as the latest.

For the initial releases, the bundle's `profile.md` selects the release and
`types.md` and conditional `actors.md` hold registries. These are ordinary OKF
concepts, not a separate configuration language. The standard type vocabulary
is open to registered project types. The root `log.md` is authored history,
while `index.md` files are discardable semantic projections. The Profile
constrains subject placement, durable concept boundaries, provenance, status,
relationships, and source mirroring without redefining their OKF mechanisms.
The immutable [2026.1](../../profile/versions/okf-profile-2026.1.md) and
[2026.2](../../profile/versions/okf-profile-2026.2.md) Profiles own their
exact bundle rules; this ADR does not duplicate them.

Validation has two distinct assessment modes:

- The model-independent CLI checks deterministic rules over the whole bundle.
  It preserves the OKF report and gives Profile findings stable
  `concepta-profile/<rule-slug>` identifiers. An OKF failure blocks dependent
  Profile checks rather than producing cascading findings.
- Profile Review assesses contextual rules, including truthful placement,
  meaning, provenance, lifecycle, and source-mirroring need. An agent may
  complete clear cases and escalates unresolved context or rule conflicts.
  Its report belongs in the interaction or review, not as a bundle certificate.

The automated result exposes OKF `PASS`/`FAIL`, Profile
`PASS`/`FAIL`/`UNSUPPORTED`/`BLOCKED BY OKF`, judgment rules `UNASSESSED`,
and an automated gate. Recommendations are non-blocking; there is no global
`--strict` switch. An automated pass never claims complete Profile conformance.
A single validator invocation is the automated CI gate because it already
includes OKF validation.

Do not add a generic provider platform, per-rule overrides or suppressions,
Profile-specific graph, or Profile-aware write transaction without demonstrated
need. Skills own coordinated authoring and Profile Review; the implementation
guide owns validator and migration behavior.

## Options considered

- A generic provider and rule-registry platform was deferred because one
  demonstrated Profile did not justify its extra interfaces.
- A validator that reports contextual judgments as deterministic failures was
  rejected because it would overclaim what bundle state proves.

## Consequences

The closed boundary keeps OKF independently usable and lets future Profile
releases change producer conventions without changing the format. In
particular, there is no numeric area threshold, invented frontmatter, or
requirement to turn every source event into a concept. Contextual questions
remain visible rather than being misreported as deterministic failures.

The initial interface was `okfp validate <bundle> [--output text|json]`.
[ADR-0008](0008-okfp-adopts-okf-finding-contract.md) changed its report wire
format when OKF did; [ADR-0010](0010-wayfinder-cli.md) added the Wayfinder
application. [ADR-0014](0014-external-profile-bindings.md) later replaced
in-bundle selection and registries for 2026.3, retaining the closed validator,
independent OKF result, and legacy-release dispatch. These later decisions do
not rewrite what 2026.2 bundles meant.

Rule-level [OKF compatibility evidence](../compatibility-review-2026.2.md)
and [assessment coverage](../../implementation/profile-coverage-2026.2.md)
answer different questions and remain separate from this decision record.

## Reconsider when

Reopen the closed boundary when a second real Profile or another concrete
trigger recorded in [#17](https://github.com/btwld/wayfinder/issues/17)
requires provider composition, rule discovery, or Profile-aware transactions,
and the additional contract can be governed without weakening the OKF boundary.
