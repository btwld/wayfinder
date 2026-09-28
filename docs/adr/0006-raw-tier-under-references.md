# ADR-0006: Keep verbatim originals in a per-source `raw/` tier

- Status: accepted
- Date: 2026-08-25
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0006-raw-tier-under-references.md))
- Scope: Profile 2026.1 and later

## Context

A migration exposed a missing boundary under `references/`: verbatim source
assets and readable concept mirrors sat together. Originals need byte fidelity,
but OKF treats every Markdown file in a bundle as a concept. The Profile cannot
exempt Markdown from that rule.

## Decision

A source directory under `references/` may put preserved originals in its own
`raw/` subdirectory. Only each nonempty directory's required `index.md` may be
Markdown inside that tier; other files remain verbatim assets. A readable mirror
is a sibling of `raw/` and cites its original through OKF `sources`.

The tier is per source, not a bundle-level parallel tree. A source directory
cannot itself be named `raw/`, and `raw/` cannot sit directly under
`references/`. The validator checks placement and Markdown eligibility, while
Profile Review judges whether mirroring is needed and appropriate.

This uses OKF-permitted directory organization and asset files. It adds no
field, filename meaning, or exception to OKF's concept model.

## Options considered

- Exempting Markdown from OKF's concept model was rejected as incompatible
  with the upstream format.
- A bundle-level parallel raw tree was rejected because it would separate an
  original from the source directory and its readable mirror.

## Consequences

Adopting the tier is optional; existing conformant bundles need no migration.
A flat `references/` must first group material by source before using it.
The 2026.1 change was made during that release's initial QA period and recorded
in its change record. It is a historical exception, not a precedent for
changing a published Profile without a new release.

## Reconsider when

Reopen this layout if a later OKF specification changes Markdown or asset
semantics, or if real bundles demonstrate that per-source placement cannot
preserve provenance and safe visibility.
