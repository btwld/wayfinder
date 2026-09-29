# ADR-0014: Bind a closed Profile through direct project sources

- Status: accepted
- Date: 2026-09-27
- Revised: 2026-09-29 (before the proposed 2026.3 release)
- Scope: Profile 2026.3 project binding and exact-release dispatch
- Supersedes: ADR-0004's in-bundle selection and registry-file decisions for Profile 2026.3; its OKF boundary and closed-validator decision remain
- Driver: Profile 2026.3 adoption; reproducible source revisions and reusable project vocabulary

The 2026-09-27 version selected installed-only bindings and rejected source
loading and inheritance. This revision records the unshipped PR #113 design
after review; the [earlier text at `dfd46e1`](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0014-external-profile-bindings.md)
remains the provenance of that choice. This is a changed decision, not a claim
that Git sourcing was considered in the original discussion.

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

Profile 2026.3 uses an explicit project-root `wayfinder.json`: each Profile key
names its identity, Git source and bundle paths in `applies_to`. A source
manifest declares identity, exact release, OKF binding and vocabulary, not
executable rules. `get` and `upgrade` resolve a revision into a metadata-only
`wayfinder.lock`; read-only validation uses a current lock/cache and never
fetches or rewrites them. The installed `bitwild_profile/2026.3` implementation
retains its normative text, deterministic validator and agent guidance. No
source can replace or parameterize those compiled rules.

The installed manifest owns twelve standard types and the base tag vocabulary
(empty in 2026.3). A source or project entry adds types, tags, and actor
lookup metadata.
`extends` composes those additions explicitly along a chain to the installed
base. Duplicate or colliding names, cycles and missing parents are rejected.
Used values must be declared. The bundle keeps OKF
`index.md` and authored `log.md`, while the three legacy root registry/selector
concepts retire for 2026.3. Subject placement and the four Profile-defined
directory names are unchanged. One Profile applies to a whole bundle; a nested
area cannot select another Profile.

The 2026.2 validator remains available and uses its immutable in-bundle
selector and registries. Unknown IDs/releases produce `UNSUPPORTED`, never a
fallback. Independent OKF conformance, graph projection, and tolerant reading
are unchanged. Search and embedding indexing still operate on one explicit
bundle and do not embed configuration or undeclared captures.

## Options considered

- Keeping release selectors and all registries in every bundle was rejected
  because it duplicated standard vocabulary and made configuration look like
  project knowledge.
- The original installed-only binding avoided remote rule loading but could
  not pin a reusable external vocabulary source across machines. The 2026-09-29
  revision replaces that selection before release.

## Consequences

A remote provider or rule DSL remains out of scope: fetched JSON is data, and
executable validation stays installed.

An opt-in migration moves custom types, used tags, and actor IDs to the direct
source entry, removes the three legacy root concepts, and regenerates the root
index.
Historical affiliation rows cannot be collapsed into a single JSON actor
entry without losing meaning: preserve material history as ordinary project
knowledge before removing `actors.md`. Existing 2026.2 bundles remain valid
without edits. Release evidence and skills must dispatch by exact release.
The source cache and lock may be unavailable; that prevents Profile dispatch
but neither invalidates the independent OKF result nor blocks the ordinary OKF
graph. Retrieval does not resolve Profile sources.

## Reconsider when

Reopen the binding design only when a second installed ruleset or real use
demonstrates a need beyond additive vocabulary composition. Do not infer a
general remote provider platform from the existence of Git source manifests.
