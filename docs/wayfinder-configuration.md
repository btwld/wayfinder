# Wayfinder project configuration

Proposed Profile 2026.3 uses one version-1 project configuration shape:
direct Git Profile sources with explicit bundle paths. Published 2026.2
bundles keep their in-bundle declarations.

Wayfinder uses two JSON documents with different responsibilities:

- [`wayfinder.schema.json`](schemas/wayfinder.schema.json) describes the
  direct-source project configuration.
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
        "ref": "main",
        "path": "profile"
      },
      "applies_to": ["./knowledge"],
      "tags": [
        {
          "name": "customer-reporting",
          "description": "Customer-facing reporting topic"
        }
      ],
      "relationships": [
        {
          "name": "assessed-by",
          "description": "The target is the analysis that assessed this concept"
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

For a local Git source, a relative `source.git` path is resolved from the
directory containing `wayfinder.json`, not the caller's working directory.
The lock retains the declared spelling; the local cache keys the resolved
location. Drive-relative paths such as `C:profile` are not supported.
Passwordless SSH URLs such as `ssh://git@github.com/org/repo.git` and Git's
SCP-style `git@github.com:org/repo.git` are supported. Do not put credentials
in the source URL.

`applies_to` contains bundle directories relative to `wayfinder.json`. Use the
explicit `./knowledge` form. A path must stay inside the project and identify
a bundle that exists when the command runs. One Profile entry may list several
bundle directories. A parent used only by `extends` may have an empty
`applies_to` array. Use another entry when a bundle needs a different Profile
or project vocabulary.

The configuration does not contain a `bundles` array or a `default_bundle`.
Commands receive a bundle path explicitly, and Profile application is declared
by `applies_to`.

## Project vocabulary

A Profile package owns the standard types, normative rules, OKF compatibility,
and review guidance. A project Profile entry may add local vocabulary alongside
`source` and `applies_to`:

- `types` adds project-specific type names and descriptions.
- `tags` declares project topics; concepts still opt into them in frontmatter.
- `relationships` declares project relationship names for the `relationships`
  frontmatter key (Profile §7.2); its description is the name's one definition.
- `actors` provides lookup metadata for actor IDs used by the project.

The effective type, tag, and relationship registries are the Profile
vocabulary plus these project additions. Names must be unique and must not
collide with standard fields or Profile definitions. Registry presence does
not prove authorship, truth, or verification. A project entry adds vocabulary
only: it cannot declare a frontmatter key, which only a Profile release does.

## Profile inheritance

`extends` is optional and independent of `applies_to`:

```json
{
  "version": 1,
  "profiles": {
    "bitwild_profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "main",
        "path": "profile"
      },
      "applies_to": []
    },
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

An extending Profile is identified by its own key and manifest. It inherits
project types, tags, relationship names, and actors from its declared parent,
then adds definitions from its own manifest and project entry. A child manifest
lists only its new types, tags, and relationship names. The chain must reach `bitwild_profile/2026.3`, whose fetched
vocabulary must exactly match the installed compiled validator. A child may
add vocabulary; it cannot replace a name, change Profile rules, or execute
rules from Git. Missing parents, cycles, collisions, and unsupported releases
are errors.

## Sources and lockfile

`wayfinder.lock` records the exact source selected after resolution:

```json
{
  "lock_version": 1,
  "configuration_sha256": "<hash of canonical wayfinder.json>",
  "profiles": {
    "bitwild_profile": {
      "source": "https://github.com/btwld/wayfinder",
      "requested_ref": "main",
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
code. Commit it with `wayfinder.json`; Git credentials stay outside the
configuration and lock, and fetched objects remain in the local cache.

The command surface is deliberately small:

```text
wayfinder get [project]        # resolve declared refs and write the lock
wayfinder upgrade [project]    # deliberately advance a branch or tag
wayfinder validate ./knowledge # read current lock/cache; never fetch or write
```

`get` resolves each declared source and respects a current lock. If project
vocabulary changes, it updates the configuration hash while retaining a
previously locked commit for an unchanged source. `upgrade` refreshes a mutable
branch or tag and writes its new commit; a pinned commit does not move.

`validate` reads only the selected Profile chain from a current lock and
local cache. It never fetches or writes the lock. If either is missing or
stale, it still reports the independent OKF result and a Profile-resolution
finding. Run `get` to recover the exact locked commit or `upgrade` to
deliberately select a new revision. Neither command silently substitutes a
moved branch or tag for a locked commit. `graph`, `index`, and `search`
do not use Profile sources or resolve the lock; they read each concept's
`relationships` key directly, so a relationship name they show need not be
declared.

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
`bitwild_profile/2026.3`, exactly compatible with OKF `0.2`, with twelve
standard types, no base tags, and eleven standard relationship names. The
current validator has compiled metadata and tests it against that manifest; it
does not load arbitrary Profile JSON.
The Profile package also ships normative text and contextual review guidance.

A committed `wayfinder.json` shares the Profile source reference, application
paths, and project vocabulary. The lock shares the resolved commit. Neither
file carries executable validator code. Each machine resolves the same source
into its local cache.

## Validation order

For `validate`, Wayfinder processes the explicit bundle in this order:

1. Inspect the bundle and run independent OKF validation.
2. For an OKF-conformant bundle, discover a project configuration only if it
   selects this bundle; otherwise retain its legacy 2026.2 dispatch.
3. Parse the selected configuration, check safe `applies_to` paths, and read
   the selected chain from a current lock/cache without network or writes.
4. Check manifest identity, exact Profile release, and OKF binding.
5. Merge standard and project vocabulary, then run deterministic Profile rules.
   Report contextual rules separately as unassessed.

Wayfinder checks `wayfinder.json` and each Profile manifest against the
published schemas first and reports the first violation with its JSON pointer,
for example `wayfinder.json is invalid at /profiles/client: has unknown
property rules.` It then enforces the cross-document checks that a schema
cannot prove, such as `extends` chains, overlapping bundle paths, whether a
bundle exists, whether a source resolved, and whether a concept's actor
reference is used correctly.

## Compatibility and migration

The former `profiles` + `bundles` / `implements` version-1 draft was
never published and is not accepted by the 2026.3 parser. Convert any
pre-release draft configuration to direct `source` + `applies_to` before
validation. Published 2026.2 bundles still use in-bundle `profile.md`,
`types.md`, and conditional `actors.md` declarations, without requiring a
neighboring `wayfinder.json`.

Migrating a 2026.2 bundle is explicit work: add a direct-source entry and
lock, move project vocabulary and actor lookup to the project configuration,
then remove the old root registries and regenerate the index. Preserve
time-dependent affiliation history as an ordinary project concept before
removing `actors.md`. Validate and perform contextual Profile Review. Do
not change a release selector merely to make a validation finding disappear.
Subject-placement rules remain Profile rules; no placement map belongs in JSON.
