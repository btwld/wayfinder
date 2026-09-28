# ADR-0014: Select a built-in Profile through an external project binding

- Status: accepted
- Date: 2026-09-27
- Supersedes: ADR-0004's in-bundle selection and registry-file decisions for Profile 2026.3; its OKF boundary and closed-validator decision remain
- Driver: Profile 2026.3 release; multiple explicit bundles and reusable project bindings

## Context

Real adoption repeated fourteen standard type rows in each `types.md` and
required an actor table for routine agent provenance. `profile.md` made a
release selector look like durable knowledge. A project can also have several
independent bundles that need shared or distinct type, tag, and actor lookup
without treating each subdirectory as a new Profile scope.

OKF 0.2 has no Profile protocol. It reserves `index.md` and `log.md` but does
not require `profile.md`, `types.md`, or `actors.md`. Those were producer rules
of Profile 2026.2, not OKF requirements.

## Decision

Profile 2026.3 uses an explicit project-root `wayfinder.json`: named bindings
select an exact installed Profile ID/release, and bundle entries select one
binding each. The installed implementation is `bitwild_profile/2026.3`, with a
JSON manifest, normative rules, deterministic validator, and agent guidance.
The manifest is not a rule DSL. The validator stays closed; there is no remote
provider loading, composition, inheritance, or per-rule override.

The installed manifest owns eleven standard types and the base tag vocabulary
(empty in 2026.3).
A binding adds project types, tags, and actor lookup metadata. Type and tag
names cannot collide; used values must be declared. The bundle keeps OKF
`index.md` and authored `log.md`, while the three legacy root registry/selector
concepts retire for 2026.3. Subject placement and the four Profile-defined
directory names are unchanged. One Profile applies to a whole bundle; a nested
area cannot select another Profile.

The 2026.2 validator remains available and uses its immutable in-bundle
selector and registries. Unknown IDs/releases produce `UNSUPPORTED`, never a
fallback. Independent OKF conformance, graph projection, and tolerant reading
are unchanged. Search and embedding indexing still operate on one explicit
bundle and do not embed configuration or undeclared captures.

## Consequences

An opt-in migration moves custom types, used tags, and actor IDs to the binding,
removes the three legacy root concepts, and regenerates the root index.
Historical affiliation rows cannot be collapsed into a single JSON actor
entry without losing meaning: preserve material history as ordinary project
knowledge before removing `actors.md`. Existing 2026.2 bundles remain valid
without edits. Release evidence and skills must dispatch by exact release.
