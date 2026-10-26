# ADR-0027: All rules use the shared effective vocabulary

- Status: accepted
- Date: 2026-10-26
- Scope: clarify format 2 composition; no runtime or package interpretation change
- Amends: [ADR-0015](0015-profile-rule-catalogs.md) and [ADR-0016](0016-independent-profile-packages.md)

## Context

The engine composes all vocabulary before evaluating rules. The shipped
`examples/profiles/two-rule-child` adds the tag `billing`, which an inherited
tag-declaration check then accepts. The guide's §5.7 and ADR-0015's statement
that a package cannot change another package's findings overstate the
isolation: rule definitions are isolated, but vocabulary inputs are shared.

## Decision

Keep the existing behavior. Every rule receives the vocabulary of the whole
chain plus the project entry. A child cannot replace, remove, or re-grade an
inherited rule; it can add vocabulary that changes that rule's results.
Findings retain their declaring package's namespace and release.

Correct the guide, schema descriptions, and generic authoring guidance, and
record the distinction in a composition regression and golden. Do not bind
each ancestor to a separate vocabulary: that would change existing verdicts
and defeat the shipped child example's tag extension.

## Consequences

Format stays 2 because packages read exactly as before. No Profile release,
bundle migration, or generated bundle-index update is needed. Profile authors must
test both new rules and inherited checks affected by their added vocabulary.
