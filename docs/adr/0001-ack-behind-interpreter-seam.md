# ADR-0001: okf_profile owns frontmatter finding IDs; ack hides behind the interpreter seam

- Status: superseded by [ADR-0004](0004-closed-concepta-profile-validator.md)
- Date: 2026-08-14
- Issues: [#7](https://github.com/btwld/okf-profile/issues/7)

## Context

The original frontmatter slice mapped ack's constraint keys onto public finding
IDs and pinned that mapping — and the ack dependency version — by test. The
version pin was the tell: a third-party package's internal vocabulary had
become load-bearing in the system's most stable contract (finding IDs are
versioned in the registry, echoed in MCP refusals, and gated on in CI). The
pinned mapping test also reached past the interpreter's stated interface.

## Decision

The interpreter is a deep module: manifest schema subset plus frontmatter in,
findings out. okf_profile owns the finding IDs through a keyword table — each
supported schema keyword maps to a stable `profile/frontmatter-<keyword>` ID,
inside the namespace grammar okf's Finding contract freezes
(conceptadev/okf#3). ack stays entirely inside the implementation: its
constraint keys and JSON Pointer paths translate to IDs and Report locations
behind the seam, and nothing outside the interpreter references them. The ack
version stays pinned as dependency hygiene, not as an ID-stability mechanism.

ack itself stays — settled 2026-08-14. This decision changes who owns the IDs,
not which validator runs.

## Consequences

- An ack upgrade cannot change a finding ID; interface-level fixtures prove it.
- The interpreter is tested through its interface only.
- ack becomes swappable in principle (a future JSON Schema engine would be a
  second adapter behind the same seam).
