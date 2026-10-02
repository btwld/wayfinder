# Bitwild Profile

Release 2026.3 of the Bitwild Profile, an OKF 0.2 Profile package.
The engine derives each finding's help link from this file. Every rule
id below is a heading, so `README.md#<rule-id>` resolves. Each heading
currently carries the rule's normative statement only; the rationale behind
each rule is still in the Profile text and will move here.

## Rules

### okf-release-binding

The bundle root index MUST declare `okf_version: "0.2"`.

### configuration-legacy-registry

A bundle using this release MUST NOT carry legacy root `profile.md`, `types.md`, or `actors.md` registries as competing configuration.

### configured-tag-undeclared

Every used tag MUST be declared by the selected Profile manifest or project binding.

### configured-tag-duplicate

A concept MUST NOT repeat a tag value.

### concept-baseline-fields

A concept MUST carry nonempty `type`, `title`, `description`, and `status` fields.

### frontmatter-fields-declared

A concept MUST NOT carry a frontmatter key that neither OKF 0.2 defines nor the selected Profile release declares.

### status-value

A concept's `status` MUST be `draft`, `stable`, or `deprecated`.

### generation-provenance-recommended

A concept carries no `generated` field recording how its current content was produced.

### used-type-registered

Every used concept type MUST resolve in the merged type registry of the selected Profile binding.

### used-actor-registered

When an actor ID is used in `generated.by`, `verified[].by`, or `sources[].author`, the selected Profile binding MUST contain that exact ID with a nonempty `name`.

### source-entry-shape

When `sources` is present, every entry MUST be a mapping carrying the nonempty `resource` OKF requires. okf reports the same gap as its `invalid-sources` or `invalid-source` advisory; this rule raises it to an error.

### source-id-unique

Within one concept, each present `sources[].id` MUST be unique.

### source-attribution-join

A body footnote reference whose label exactly matches a `sources[].id` is source attribution and MUST join to its footnote definition.

### source-path-unresolved

A top-level `resource` or `sources[].resource` written as a path resolves to no existing file or directory.

### relationship-shape

When `relationships` is present, it MUST be a list whose every entry is a mapping with exactly a nonempty `relationship` name and a nonempty `resource` that okf reads as a link target, never a scope descriptor or an invalid path.

### used-relationship-declared

Every used relationship name MUST be declared by the selected Profile manifest or project binding.

### internal-link-bundle-relative

An internal link uses a target without the leading `/` of a bundle-relative link.

### internal-link-unresolved

An internal link's target is absent from the bundle.

### relationship-bundle-relative

An internal relationship target is written without the leading `/` of a bundle-relative link.

### relationship-unresolved

An internal relationship target is absent from the bundle.

### raw-directory-placement

A `raw/` tier belongs to a source directory and MUST NOT sit directly under `references/`.

### raw-directory-markdown

Within `raw/` and any of its subdirectories under `references/`, no markdown file is permitted; `index-current` reports a leftover `index.md` there (§9).

### root-structure-files

A bundle MUST contain `index.md` and `log.md` at its root.

### root-index-lists-log

The root `index.md` of a bundle with no concepts MUST link only `log.md`.

### concept-area-name-collision

A concept sits beside an area of the same name rather than inside it.

### index-current

Every directory the OKF reference index generator indexes MUST contain an `index.md` identical to the generator's output for the bundle, and a directory holding only non-concept assets, such as a `raw/` tier, MUST NOT carry one.

### log-entry-lead-word

Every root `log.md` entry MUST start with a nonempty bold lead word followed by a colon.
