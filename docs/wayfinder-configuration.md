# Wayfinder project configuration

**Status: implemented for `bitwild_profile/2026.3`.** Existing 2026.2 bundles
continue to use their in-bundle declaration until explicitly migrated.

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
          "name": "customer-reporting",
          "description": "Customer-facing reporting topic"
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
Profile by stable ID and exact release. A binding may add custom types, declared
tags, and actor lookup metadata; it does not redefine Profile rules.
The current runtime installs only `bitwild_profile/2026.3`. Several named
bindings may select it; an unknown Profile ID or release is reported as
unsupported, not dynamically downloaded or treated as Bitwild.

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

## Git Profile sources and lockfile (planned)

The current 2026.3 runtime resolves an installed Profile. The following source
and lockfile design is planned; it is not accepted configuration syntax yet.

A project may retrieve a Profile from Git using a Pub-style revision reference:

```json
{
  "version": 1,
  "profiles": {
    "bitwild_profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "v2026.3",
        "path": "profile"
      },
      "applies_to": ["./knowledge"]
    }
  }
}
```

`ref` may be a branch, tag, or commit. It does not use `branch/`, `tag/`, or
`commit/` prefixes. `path` is the directory inside the Git revision that carries
the Profile package. The package manifest supplies the Profile ID and release;
the project configuration does not repeat them. Wayfinder verifies that the
manifest ID matches `bitwild_profile` and that its release has a supported
validator.

`applies_to` is independent of Profile inheritance. A direct Profile can apply
to one or more bundle directories. A custom Profile may additionally use
`extends`:

```json
{
  "profiles": {
    "client_profile": {
      "extends": "bitwild_profile",
      "source": {
        "git": "https://github.com/example/client-profile",
        "ref": "v1.0.0",
        "path": "profile"
      },
      "applies_to": ["./knowledge"]
    }
  }
}
```

`extends` is a planned composition relationship, not an arbitrary rule override.
The first implementation should permit declared project vocabulary additions and
report any unsupported override explicitly.

### Lockfile

`wayfinder.lock` records the exact Profile source used after resolution:

```json
{
  "lock_version": 1,
  "configuration_sha256": "<hash of canonical wayfinder.json>",
  "profiles": {
    "bitwild_profile": {
      "source": "https://github.com/btwld/wayfinder",
      "requested_ref": "v2026.3",
      "resolved_commit": "<commit>",
      "path": "profile",
      "profile_release": "2026.3"
    }
  }
}
```

The configuration hash is calculated from canonical JSON, so whitespace-only
formatting changes do not invalidate the lock. A real change to `wayfinder.json`
causes `wayfinder get` to refresh the lock. `get` resolves the declared
reference and respects the lock when it is current; `upgrade` deliberately moves
branches or tags to their latest available revision and rewrites the lock.

The proposed command flow is:

```text
wayfinder get [project]        # resolve declared refs and write the lock
wayfinder upgrade [project]    # request newer branch/tag revisions
wayfinder validate ./knowledge # resolve when needed, then validate the bundle
```

All bundle commands use one shared resolution step before they run. When the
lock is missing or its configuration hash is stale, that step does the same work
as `wayfinder get` and writes the lock. When the lock is current, it is a no-op.
`upgrade` is the only command that deliberately moves a branch or tag forward.

The lockfile is not a second configuration file. It does not contain Profile
rules, project types/tags/actors, knowledge content, credentials, or mutable user
choices. It records Profile resolution so every bundle command can reuse the same
source. It records reproducible resolution metadata only. It can be committed
with `wayfinder.json`; fetched Profile contents and credentials belong in the
local cache and must not be committed.

## Tags and the captures layer

The Profile manifest's `tags` array defines stable, reusable tag vocabulary. A
project binding's `tags` array extends that vocabulary for its own bundles. A
tag definition is vocabulary only; it does not automatically apply the tag to
every concept. Concepts still opt in explicitly through frontmatter:

```yaml
tags: [customer-reporting]
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

The schema's `default_bundle` is reserved for future command selection. Current
Wayfinder commands still require an explicit bundle path; `wayfinder setup`
defaults its MCP configuration to `knowledge`, and an MCP server serves one
startup-selected bundle. Future config-aware commands may use
`default_bundle` only when no explicit bundle is supplied. They must not
recursively discover directories or silently merge bundles.

## Profile manifest

The installed Profile publishes [its canonical manifest](../profile/wayfinder-profile.json):
`bitwild_profile/2026.3`, binding exactly to OKF `0.2`, with eleven standard
types in Profile order and no base tags. Its names and descriptions are not
repeated here to avoid a competing copy. The current validator has compiled
built-in Profile metadata; a parity test checks its identity, standard types,
and tags against the shipped manifest. Runtime validation does not load
arbitrary Profile JSON. The manifest is distribution and compatibility metadata,
not an executable rule language. The installed Profile also ships normative
text and contextual review guidance.

`implements` selects an upstream format release. It does not introduce Profile
inheritance. A reusable rule-set change is published as a new Profile release
or a distinct Profile ID; `extends`, overrides, and composition are out of scope
for the first schema.

Profiles declare tag definitions, and project bindings add project-specific
definitions. The selected Profile release decides the severity for an
undeclared used tag; the project binding cannot silently change that severity.
Declared tag names must be unique, must not collide between the Profile and
binding, and must not be duplicated within one concept. Bitwild 2026.3 makes
the JSON registry authoritative and treats an undeclared used tag as an error.
Its installed manifest declares no base tags; projects declare the topics they
actually use.

## Validation order

Wayfinder processes a configured bundle in this order:

1. Parse `wayfinder.json` and enforce its schema shape and cross-field rules.
2. Resolve the bundle path safely and resolve its Profile binding.
3. Select the exact supported built-in Profile release; its packaged manifest
   is checked for parity with compiled metadata in tests.
4. Run independent OKF validation.
5. Merge standard and custom types and validate concept type references.
6. Validate actor references and binding metadata.
7. Run deterministic Profile rules and report judgment rules separately.

The published JSON Schema describes shape and primitive types; Wayfinder's
parser enforces that contract directly rather than invoking a JSON Schema
engine at runtime. Cross-document checks remain Wayfinder behavior: a schema
cannot prove that a bundle exists, that a Profile is installed, or that a
concept's actor reference is actually used correctly.

## Compatibility

Existing 2026.2 bundles continue to use their in-bundle `profile.md`,
`types.md`, and conditional `actors.md` declarations. To migrate one, add its
bundle and binding to `wayfinder.json`, move custom types, tags, and actor IDs
into the binding, remove the three legacy root concepts, and update the root
`index.md`. If `actors.md` contains time-dependent affiliation history,
preserve that history as an ordinary project concept before removing the
registry; one JSON actor entry cannot represent several historical periods.
The subject-placement rules remain Profile rules and are unchanged;
no placement map belongs in JSON.
