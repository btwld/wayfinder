# Wayfinder project configuration

**Status: proposed schema for the next Profile release.** Runtime support and
bundle migration are not part of this document's addition.

Wayfinder uses two JSON documents with different responsibilities:

- [`wayfinder.schema.json`](schemas/wayfinder.schema.json) describes a project's
  `wayfinder.json` binding.
- [`wayfinder-profile.schema.json`](schemas/wayfinder-profile.schema.json)
  describes the manifest shipped with an installed Profile implementation.

## Project configuration

The project file sits beside the bundles at the repository root:

```json
{
  "version": 1,
  "default_bundle": "knowledge",
  "profiles": {
    "knowledge_profile": {
      "implements": "bitwild_profile/2026.3",
      "types": [
        {
          "name": "Source Document",
          "description": "An authoritative captured document."
        }
      ],
      "actors": {
        "claude-code/opus-5": {
          "name": "Claude Code"
        }
      },
      "tags": [
        {
          "name": "captures",
          "description": "Evidence-related topic"
        }
      ]
    }
  },
  "bundles": [
    {
      "id": "knowledge",
      "path": "knowledge",
      "profile": "knowledge_profile"
    }
  ]
}
```

`profiles` are project-local bindings. `implements` resolves to an installed
Profile by stable ID and exact release. A binding may add custom types and actor
lookup metadata; it does not redefine Profile rules.

`bundles` are explicit. A nested directory is not a new bundle unless it has a
separate entry. Bundle paths resolve relative to `wayfinder.json` and must stay
inside the project. The loader, not JSON Schema alone, checks that bundle IDs,
paths, and Profile references are unique and resolvable.

The effective type registry for a bundle is:

```text
Profile standard types + binding custom types
```

Custom type names must not collide with standard types or one another. The
binding actor map is a lookup for IDs used in OKF provenance. Registry presence
does not prove authorship or verification.

## Tags and the captures layer

The Profile manifest's `tags` array defines stable, reusable tag vocabulary. A
project binding's `tags` array extends that vocabulary for its own bundles. A
tag definition is vocabulary only; it does not automatically apply the tag to
every concept. Concepts still opt in explicitly through frontmatter:

```yaml
tags: [reporting, evidence]
```

`captures/` is normally an evidence layer beside the OKF bundle, not a bundle
and not a Profile scope. Its `intake.md` files therefore do not participate in
concept-tag validation or Wayfinder search. A durable concept in `knowledge/`
may use a project tag such as `evidence` when that topic is meaningful, but
Wayfinder must not infer a tag merely because a concept cites a capture.

If a project deliberately exposes captures as a separate searchable OKF bundle,
that bundle gets its own Profile binding, type registry, tag registry, and actor
lookup. It does not inherit the main `knowledge/` binding implicitly.

## Sharing and defaults

The reusable base Profile is shared by installing the same pinned Profile
package on each machine. A committed `wayfinder.json` shares the project
binding and exact release reference; it does not carry executable validator
code. A binding may be reused by several bundles when their custom types, tags,
and actor lookup are intentionally the same. Use separate named bindings when
those registries differ. Do not copy project-specific actors between projects
without reviewing their meaning.

The schema's `default_bundle` is a proposed future convenience. Current
Wayfinder commands still require an explicit bundle path; `wayfinder setup`
defaults its MCP configuration to `knowledge`, and an MCP server serves one
startup-selected bundle. Future config-aware commands may use
`default_bundle` only when no explicit bundle is supplied. They must not
recursively discover directories or silently merge bundles.

## Profile manifest

An installed Profile publishes a manifest such as:

```json
{
  "id": "bitwild_profile",
  "release": "2026.3",
  "implements": {
    "id": "okf",
    "release": "0.2"
  },
  "standard_types": [
    {
      "name": "Decision",
      "description": "A durable non-architectural decision."
    },
    {
      "name": "Guide",
      "description": "Durable operational or engineering guidance."
    }
  ],
  "tags": [
    {
      "name": "governance",
      "description": "Governance-related topic"
    }
  ]
}
```

The manifest is identity and compatibility metadata. The installed Profile also
ships its normative rules, deterministic validator, and contextual review
guidance. The manifest is not an executable rule language.

`implements` selects an upstream format release. It does not introduce Profile
inheritance. A reusable rule-set change is published as a new Profile release
or a distinct Profile ID; `extends`, overrides, and composition are out of scope
for the first schema.

Profiles declare tag definitions, and project bindings add project-specific
definitions. The selected Profile release decides the severity for an
undeclared used tag; the project binding cannot silently change that severity.
Declared tag names must be unique, must not collide between the Profile and
binding, and must not be duplicated within one concept. The first Bitwild
external-binding release should make the JSON registry authoritative and treat
an undeclared used tag as an error.

## Validation order

Wayfinder should process a configured bundle in this order:

1. Validate the JSON document against the schema.
2. Resolve the bundle path safely and resolve its Profile binding.
3. Resolve the installed Profile manifest and exact release.
4. Run independent OKF validation.
5. Merge standard and custom types and validate concept type references.
6. Validate actor references and binding metadata.
7. Run deterministic Profile rules and report judgment rules separately.

JSON Schema catches shape and primitive types. Cross-document checks remain
Wayfinder behavior; a schema cannot prove that a bundle exists, that a Profile
is installed, or that a concept's actor reference is actually used correctly.

## Compatibility

This schema is intended for a future Profile release. Existing 2026.2 bundles
continue to use their in-bundle `profile.md`, `types.md`, and conditional
`actors.md` declarations until an explicit migration is implemented.
