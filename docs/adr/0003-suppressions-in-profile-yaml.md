# ADR-0003: Suppressions declare in `profile.yaml`

- Status: superseded by [ADR-0004](0004-closed-concepta-profile-validator.md)
- Date: 2026-08-14
- Issues: [#10](https://github.com/conceptadev/okf-profile/issues/10), #5, #12

## Context

Per-finding-ID suppression is the migration path through the CI gate (adopt the
gate, suppress, burn down), but the original slice described its configuration
surface in one word — "configuration" — with no location or format. It is a
cross-repository contract read by a pinned binary, like `profile.yaml` itself,
and deserved the same contract treatment.

## Decision

Suppressions declare in the reserved sidecar `profile.yaml`, under
`suppressions:`: a list of finding IDs, each with an optional note. The shape
freezes in #5. One reserved file carries the bundle's governance state — what
governs it and its acknowledged, temporary deviations — checked into the
repository, visible in review, removable. The toolchain reads it identically on
every surface (CLI and MCP); the CI action needs no configuration input.

Suppressions scope to okfp's Report, which carries profile findings only
(2026-08-14 validation-scope review): an entry naming an ID outside the
`profile/...` namespace, or one the catalog does not know, produces an
advisory, so stale or misdirected suppressions surface instead of rotting.
Suppression's exit-code interaction is Verdict semantics owned by okf's
Finding contract (suppressions pass through as data), not re-decided per
surface.

## Consequences

- No second sidecar file; one file carries the bundle's governance state.
- The gate's "one step, zero configuration" claim survives migration.
- The base gate is untouched by suppression: base conformance never has
  acknowledged deviations.
