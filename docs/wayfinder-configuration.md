# Wayfinder project configuration

**Status: proposed direct Profile source design.** The current 2026.3 runtime
still accepts installed Profile bindings through the legacy configuration shape.
The source and lockfile design below is the target model; the compatibility
notes at the end keep that distinction explicit.

Wayfinder uses two JSON documents with different responsibilities:

- [`wayfinder.schema.json`](schemas/wayfinder.schema.json) describes the
  current runtime's legacy project configuration. The parser and schema will
  move to the direct source shape as the planned design is implemented.
- [`wayfinder-profile.schema.json`](schemas/wayfinder-profile.schema.json)
  describes the manifest shipped with a Profile package.

## The project file

Place `wayfinder.json` at the project root. A Profile entry is keyed by its
Profile identity and says where its package comes from and which bundle
folders use it:

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
      "applies_to": ["./knowledge"],
      "tags": [
        {
          "name": "customer-reporting",
          "description": "Customer-facing reporting topic"
        }
      ]
    }
  }
}
```

The profile key is the identity. It replaces the old `knowledge_profile` alias;
there is no second name to connect a Profile to a bundle. `source.git` names the
repository, `source.ref` selects a branch, tag, or commit, and `source.path`
is the Profile directory inside that revision. A ref has no `branch/`, `tag/`,
or `commit/` prefix. The fetched manifest is authoritative for the Profile
release and must report the same identity as the map key.

`applies_to` contains bundle directories relative to `wayfinder.json`. Use the
explicit `./knowledge` form. A path must stay inside the project and identify
a bundle that exists when the command runs. One Profile entry may list several
bundle directories. Use another entry when a bundle needs a different Profile
or a different project vocabulary.

The configuration does not contain a `bundles` array or a `default_bundle`.
Commands receive a bundle path explicitly, and Profile application is declared
by `applies_to`.

## Project vocabulary

A Profile package owns the standard types, normative rules, OKF compatibility,
and review guidance. A project Profile entry may add local vocabulary alongside
`source` and `applies_to`:

- `types` adds project-specific type names and descriptions.
- `tags` declares project topics; concepts still opt into them in frontmatter.
- `actors` provides lookup metadata for actor IDs used by the project.

The effective type and tag registries are the Profile vocabulary plus these
project additions. Names must be unique and must not collide with standard
fields or Profile definitions. Registry presence does not prove authorship,
truth, or verification.

## Profile inheritance

`extends` is optional and independent of `applies_to`:

```json
{
  "version": 1,
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

An extending Profile is still identified by its own key and manifest. `extends`
provides a planned composition relationship for additive vocabulary and
reviewed Profile metadata. It does not permit arbitrary rule overrides; an
unsupported override is an explicit configuration error.

## Sources and lockfile

`wayfinder.lock` records the exact source selected after resolution:

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

The hash is computed from canonical JSON, so formatting-only edits do not
invalidate the lock. A semantic change to `wayfinder.json` makes it stale. The
lock stores dependency-resolution metadata only: it has no Profile rules,
project vocabulary, knowledge content, credentials, or executable validator
code. Commit it with `wayfinder.json`; fetched Profile contents and credentials
remain in the local cache.

The command surface is deliberately small:

```text
wayfinder get [project]        # resolve declared refs and write the lock
wayfinder upgrade [project]    # deliberately advance a branch or tag
wayfinder validate ./knowledge # resolve when needed, then validate the bundle
```

`get` resolves each declared source and respects a current lock. `upgrade` is
the only command that intentionally moves a mutable branch or tag forward. A
pinned commit does not move.

`validate`, `index`, `search`, and `graph` all run the same resolver before
their normal work. If the lock is missing or its configuration hash is stale,
the resolver performs the equivalent of `get` and writes the lock. If the lock
is current, resolution is a no-op and a current source cache can be used
without network access. A failed resolution stops the command before it reads
bundle content and leaves the previous lock unchanged.

## Tags and captures

The Profile manifest's `tags` array defines stable reusable vocabulary. A
project entry extends that vocabulary for the bundles in `applies_to`:

```yaml
tags: [customer-reporting]
```

A tag definition does not apply a tag automatically. Concepts opt in through
frontmatter, and a tag must describe the concept's actual topic.

`captures/` is normally an evidence layer beside an OKF bundle, not a bundle or
Profile scope. Its `intake.md` files therefore do not participate in concept
tag validation or Wayfinder search. If a project deliberately exposes
captures as a searchable OKF bundle, add its path to the appropriate
`applies_to` list and give it the Profile and vocabulary it needs.

## Profile manifest and sharing

A Profile manifest is distribution and compatibility metadata, not an
executable rule language. The installed Bitwild manifest is
[`profile/wayfinder-profile.json`](../profile/wayfinder-profile.json):
`bitwild_profile/2026.3`, exactly compatible with OKF `0.2`, with eleven
standard types and no base tags. The current validator has compiled metadata
and tests it against that manifest; it does not load arbitrary Profile JSON.
The Profile package also ships normative text and contextual review guidance.

A committed `wayfinder.json` shares the Profile source reference, application
paths, and project vocabulary. The lock shares the resolved commit. Neither
file carries executable validator code. Each machine resolves the same source
into its local cache.

## Validation order

Every bundle command begins with the shared resolver. It refreshes a missing or
stale lock as described above, then Wayfinder processes the selected bundle in
this order:

1. Parse `wayfinder.json` and enforce its shape and cross-field rules.
2. Normalize each `applies_to` path safely and select the matching Profile.
3. Check the lock, source cache, Profile manifest identity, and Profile release.
4. Run independent OKF validation.
5. Merge standard and project types and validate concept type references.
6. Validate actor references, tags, and project metadata.
7. Run deterministic Profile rules and report contextual rules separately.

The published JSON Schema describes shape and primitive types. Wayfinder's
parser enforces the cross-document checks that a schema cannot prove, such as
whether a bundle exists, whether a source resolved, and whether a concept's
actor reference is used correctly.

## Current runtime compatibility and migration

The current 2026.3 runtime still reads the legacy `profiles` plus `bundles`
shape with an `implements` field. Existing 2026.2 bundles still use their
in-bundle `profile.md`, `types.md`, and conditional `actors.md` declarations.
This compatibility path is separate from the direct source design above; it
must not be presented as the new model.

To migrate a legacy project, keep each bundle path, move its `profile` key into
the matching Profile entry's `applies_to`, replace `implements` with a Profile
source, and keep its custom `types`, `tags`, and `actors` on that entry. Remove
`default_bundle` and the old `bundles` array. If a legacy `actors.md` contains
time-dependent affiliation history, preserve that history as an ordinary
project concept before removing the registry. Subject-placement rules remain
Profile rules; no placement map belongs in JSON.
