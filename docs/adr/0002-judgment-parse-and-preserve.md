# ADR-0002: The manifest `judgment` section is parse-and-preserve

- Status: superseded by [ADR-0004](0004-closed-concepta-profile-validator.md)
- Date: 2026-08-14
- Issues: [#5](https://github.com/btwld/okf-profile/issues/5)

## Context

The manifest's `judgment:` section declares the rules tools must not attempt —
a declared machine/human boundary the spec wants (user story 5 of #3). But no
slice consumes it with engine behaviour. Freezing execution semantics for an
interface with zero adapters either ships dead surface carried forever or
forces a semantics fight when a future consumer finds the frozen shape wrong.

## Decision

The `judgment` section stays in the manifest as declared data. The #5 contract
freezes parse-and-preserve only: the toolchain stores and lists the entries and
assigns no execution semantics. Semantics are decided when a slice consumes
them, in a superseding record.

## Consequences

- User story 5 is satisfied (the boundary is declared, not implicit).
- The frozen contract carries no speculative execution surface.
- A future consumer (e.g. a reviewer checklist tool) triggers the semantics
  decision with a real adapter in hand.
