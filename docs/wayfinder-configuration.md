# Wayfinder project configuration

A project selects its Profiles in one version-1 file, `wayfinder.json`:
direct Git Profile sources with explicit bundle paths. It is the only way
Wayfinder selects a Profile. The project says which Profile applies where;
each Profile package says what it builds on.

Wayfinder uses two JSON documents with different responsibilities:

- [`wayfinder.schema.json`](schemas/wayfinder.schema.json) describes the
  direct-source project configuration.
- [`wayfinder-profile.schema.json`](schemas/wayfinder-profile.schema.json)
  describes a Profile package, the one file a Profile ships.

## The project file

Place `wayfinder.json` at the project root. A Profile entry is keyed by its
Profile identity and says where its package comes from and which bundle
folders use it:

```json
{
  "version": 1,
  "profiles": {
    "bitwild-profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "main",
        "path": "profiles/bitwild"
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
is the directory inside that revision that holds the package file
`wayfinder-profile.json`. A ref has no `branch/`, `tag/`, or `commit/` prefix.
The fetched package is authoritative for the Profile release. Its `id` must
equal the map key, so a key also follows the package id grammar.

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
bundle directories, and it lists at least one, because an entry exists to
apply its Profile. Use another entry when a bundle needs a different Profile
or project vocabulary. A Profile's parents never need an entry of their own:
the package names them.

The configuration does not contain a `bundles` array or a `default_bundle`.
Profile application is declared by `applies_to`. `wayfinder search "<query>"`
and `wayfinder index` discover those paths from the nearest project file.
`--bundle <folder-name>` optionally selects one bundle; names come from the
configured folder paths. An explicit bundle path remains available. Validation
and graph commands still require one explicit bundle.

## Project vocabulary

A Profile package owns its types, frontmatter keys, rules, OKF binding, and
documentation. A project Profile entry may add local vocabulary alongside
`source` and `applies_to`:

- `types` adds project-specific type names and descriptions.
- `tags` declares project topics; concepts still opt into them in frontmatter.
- `relationships` declares project relationship names for the `relationships`
  frontmatter key; its description is the name's one definition.
- `actors` provides lookup metadata for actor IDs used by the project.

The effective type, tag, and relationship registries are the vocabulary of
every package in the chain plus these project additions. A project entry that
repeats one of its own names is a configuration error, reported as
`wayfinder/config-invalid`. Registry presence does not prove authorship,
truth, or verification. A project entry adds vocabulary only. It cannot
declare a frontmatter key or a rule, because only a package carries those.

## Building on another Profile

A Profile package names its own parent in `extends`. The project never wires
the chain, so a Profile means the same thing in every project that uses it.
A project that wants Bitwild plus a client's additions names only the
client's Profile:

```json
{
  "version": 1,
  "profiles": {
    "client-profile": {
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

The client's package declares the parent in one of two shapes:

```json
"extends": {"git": "https://github.com/btwld/wayfinder", "ref": "bitwild-v2026.3", "path": "profiles/bitwild"}
```

```json
"extends": {"path": "profiles/bitwild"}
```

With `git`, the parent is the package at `path` in that repository at `ref`.
The `git` value is a URL or an absolute path, never a relative one, because a
relative path would resolve differently in each project. Without `git`, the
parent is the package at `path`, relative to the repository root, in the same
repository at the same commit as the child. A repository that hosts several
Profiles releases them together this way.
[`examples/profiles/two-rule-child/`](../examples/profiles/two-rule-child/)
extends Bitwild like this, so any ref of this repository gives both packages
from one commit.

An extending Profile is identified by its own `id`. It inherits every rule
and every name its ancestors declare, then adds its own. A child package
lists only what it adds. It cannot replace a name or change an inherited
rule, so a parent's findings are the same with or without the child. A
package that extends itself, directly or through its ancestors, fails `get`.

No Profile is a base. A chain ends at the first package without
`extends`, and a package with no parent stands alone.
[`examples/profiles/two-rule/`](../examples/profiles/two-rule/) is a Profile
with two rules and no parent, and
[`examples/acme-notes/`](../examples/acme-notes/) is a project that uses it.
Bitwild is one package among others, fetched like any other, so a chain does
not have to reach it.

The engine composes the chain and the project entry before it evaluates
anything. Composition reads nothing but those inputs, so the same packages
and entry always compose the same way. It enforces these constraints:

- A type, tag, or relationship name is unique across the chain and the
  project entry.
- A frontmatter key is unique along the chain.
- A tag never equals a type, an OKF status value, an OKF trust tier, or a
  relationship name.

Every package in a chain binds to the same OKF release because the engine
reads one OKF release and refuses any other package when it parses it, before
composition starts. A violation of the constraints above is a composition
error. `get` composes every chain before it writes the lock, so it reports
the error and leaves the lock as it was. `validate` reports it as
`wayfinder/profile-composition` with the Profile `NOT ASSESSED`. Composition
owns these checks because only the whole chain can show a collision between
two packages.

## Profile packages

A Profile is one package file, `wayfinder-profile.json`, in the shape of
[`wayfinder-profile.schema.json`](schemas/wayfinder-profile.schema.json). One
file carries the identity, the vocabulary, and the rules, so they cannot
drift apart within a revision. The Bitwild package is
[`profiles/bitwild/wayfinder-profile.json`](../profiles/bitwild/wayfinder-profile.json).
This minimal package shows the shape with two rules:

```json
{
  "$schema": "https://github.com/btwld/wayfinder/blob/main/docs/schemas/wayfinder-profile.schema.json",
  "format": 2,
  "id": "client-profile",
  "release": "1.0.0",
  "implements": {"id": "okf", "release": "0.2"},
  "docs": "https://github.com/example/client-profile/blob/main/profile/README.md",
  "types": [
    {"name": "Runbook", "description": "Operational steps for one recurring task"}
  ],
  "rules": [
    {
      "id": "status-value",
      "category": "vocabulary",
      "severity": "error",
      "status": "stable",
      "description": "A concept's `status` MUST be `draft`, `stable`, or `deprecated`.",
      "message": "Status must be draft, stable, or deprecated.",
      "check": {
        "subject": "frontmatter",
        "schema": {
          "properties": {
            "status": {"enum": ["draft", "stable", "deprecated"]}
          }
        }
      },
      "tests": {
        "valid": [{"status": "draft"}, {}],
        "invalid": [{"status": "final"}]
      }
    },
    {
      "id": "root-structure-files",
      "category": "structure",
      "severity": "error",
      "status": "stable",
      "description": "A bundle MUST contain `index.md` and `log.md` at its root.",
      "message": "The bundle root must contain index.md and log.md; missing {failing}.",
      "check": {
        "builtin": "files-present",
        "params": {"paths": ["index.md", "log.md"]}
      }
    }
  ]
}
```

The fields have these jobs:

- `format` is the package format the engine reads, always `2` here. Engine
  compatibility is this integer, never a Profile release.
- `id` is the Profile identity in lowercase kebab-case, at most 64
  characters. It is the finding namespace (`client-profile/status-value`), the
  `wayfinder.json` key, the lock key, and the name of the Profile's installed
  skill, which is why it follows the Agent Skills name limit. The names `okf`, `wayfinder`, `use-wayfinder`,
  `author-knowledge-bundle`, `adopt-knowledge-bundle`,
  `assess-knowledge-bundle`, and `create-profile` are reserved.
- `release` is the Profile's own release name. The engine treats it as opaque
  and reports it with each finding.
- `implements` names the OKF release the Profile binds to. The engine refuses
  a release its okf dependency cannot read.
- `extends` optionally names the parent Profile, as described in
  [Building on another Profile](#building-on-another-profile).
- `docs` is an optional absolute URI where the Profile explains its rules. A
  finding's help link is that URI with the fragment set to the rule id, so each
  rule id is expected to be a heading there.
- `skill` optionally names the package directory that holds the Profile's
  agent skill, relative to the package, as described in
  [Profile skills](#profile-skills).
- `types`, `tags`, `relationships`, and `frontmatter_keys` are lists of
  `{name, description}` definitions. Any package may declare frontmatter keys.
  A key OKF already defines is an error.
- `$defs` holds schemas a rule may reference. The engine adds one entry per
  slot, named by the slot id, such as `#/$defs/profile.types`, for the
  composed vocabulary; a package entry may not use a slot id.
- `rules` holds the package's rules. A rule only adds findings.

A rule's `check` is either a schema check or a builtin. A schema check names
a `subject` and a JSON Schema in the engine's keyword subset, which Ack
evaluates. It may also
name an `each` array fact, which runs the schema once per element. Its
`tests` hold valid and invalid examples. The engine runs them when it parses
the package, so a package whose examples disagree with its own check never
loads. The root subject also exposes `has_concepts` and `index_links`, the
root index's link targets in order, or null when the root index is absent or
unreadable. Each target is resolved the way OKF resolves a link from the
root: query and fragment are stripped, `.` segments and a leading `/` are
folded, so `./log.md`, `/log.md` and `log.md#top` all read as `log.md`,
while an external URL is kept as written.

A builtin is an engine capability for a check a schema cannot express. Each
builtin is named for what it checks and takes parameters, so one capability
serves many rules:

| Builtin | Params | Reports |
| --- | --- | --- |
| `files-present` | `paths`, a non-empty list of unique bundle-relative paths | one finding listing every missing path as `{failing}` |
| `path-targets-exist` | `fields`, a non-empty unique subset of `resource`, `sources.resource`, `computation`, `executor.resource`, `attester.resource` | one finding per document and target whose path exists neither in the bundle nor on disk, as `{target}` |
| `matches-generated` | `generator`, only `okf-index` today. `version`, the okf release the package's verdicts assume; a wayfinder built on another okf cannot load the package. Default none. `keep`, paths never reported as extra, default none. `extra`, `report` or `ignore`, default `report`. CRLF line endings on disk are read as LF, as the fix writes them. | a `stale` or `extra` message per `{path}`. `--fix` writes the generator's output. |

The `okf-index` generator declares the package's `implements.release` in the
indexes it writes. The JSON report names the okf version the engine generated
with as `engine.okf`, and SARIF names it as a `tool.extensions` entry. A byte
change in generated output therefore reads as an engine upgrade, not as a
Profile change.

The engine reads every package through one parser, Bitwild's included, and
never applies a package it cannot evaluate in part. A package that cannot be
read makes `get` fail with the reason. A package already locked makes
`validate` report the Profile `NOT ASSESSED` beside the independent OKF result,
with one of these diagnostics:

- `wayfinder/profile-invalid` when a package is malformed. A schema
  violation, a bad id, a repeated name, an OKF frontmatter key, or examples
  that disagree with their check are all malformed.
- `wayfinder/profile-unsupported` when a package is well-formed for another
  engine. It may declare another `format`, an OKF release this okf cannot
  read, or a builtin this engine lacks. Upgrade `wayfinder` to assess it.
- `wayfinder/profile-composition` when the chain does not compose.

## Sources and lockfile

`wayfinder.lock` records every package the project's Profiles need, keyed by
Profile id. For the client project above, whose package extends Bitwild at
`bitwild-v2026.3`, it reads:

```json
{
  "lock_version": 1,
  "configuration_sha256": "<hash of canonical wayfinder.json>",
  "packages": {
    "bitwild-profile": {
      "source": "https://github.com/btwld/wayfinder",
      "requested_ref": "bitwild-v2026.3",
      "resolved_commit": "<commit>",
      "path": "profiles/bitwild",
      "release": "2026.3"
    },
    "client-profile": {
      "source": "https://github.com/example/client-profile",
      "requested_ref": "v1.0.0",
      "resolved_commit": "<other commit>",
      "path": "profile",
      "release": "1.0.0",
      "extends": "bitwild-profile"
    }
  }
}
```

The lock stays flat however deep a chain is, because `extends` names the
parent's entry.
A parent at the same revision gets its child's `source`, `requested_ref`, and
`resolved_commit`.
`release` is the package's own `release`. A project locks one source of each
Profile id, its `git`, `ref`, and `path`, resolved to one commit. An id
therefore names one finding namespace everywhere in the project. When two
chains describe the same Profile id with different sources, `get` fails and
names both sources, even when they resolve to the same commit. Make them
agree. A lock in an older shape is treated as absent, and `get` rewrites it.

The hash is computed from canonical JSON, so formatting-only edits do not
invalidate the lock. A semantic change to `wayfinder.json` makes it stale.
The lock stores dependency-resolution metadata only. It has no Profile rules,
project vocabulary, knowledge content, credentials, or executable validator
code. The locked commit identifies each package. Commit the lock with
`wayfinder.json`; Git credentials stay outside the configuration and lock,
and fetched objects remain in the local cache.

The command surface is deliberately small:

```text
wayfinder get [project]        # resolve declared refs, write the lock, install skills
wayfinder upgrade [project]    # deliberately advance a branch or tag
wayfinder validate ./knowledge # read current lock/cache; never fetch or write
```

`get` resolves each entry's chain and respects a current lock. Run twice with
nothing changed, it fetches nothing and writes nothing: the lock's bytes and
every installed skill stay as they were.
If project vocabulary changes, it updates the configuration hash while
retaining a previously locked commit for an unchanged source. `upgrade`
refreshes a mutable branch or tag and writes its new commit; a pinned commit
does not move.

`validate` follows the lock's `extends` entries from the bundle's Profile to
its root and reads each package from the local cache at its locked commit. It
never fetches or writes the lock. If the lock is missing or stale, lacks the
chain, or a package is not in the cache or disagrees with the release or
parent the lock records, it still reports the independent OKF result and the
`wayfinder/profile-unresolved` diagnostic. Whenever it selects a Profile,
including when OKF fails and the state is `BLOCKED BY OKF`, the JSON result
names it as `profile.id` and `profile.release` and lists its chain as
`profile.chain`, root first, each entry with its `id`, `release`, and locked
`commit`. Only a `NOT ASSESSED` result omits them. Run `get` to recover the exact
locked commit or `upgrade` to deliberately select a new revision. Neither
command silently substitutes a moved branch or tag for a locked commit.
`graph`, `index`, and `search` do not use Profile sources or resolve the
lock; they read each concept's `relationships` key directly, so a
relationship name they show need not be declared.

## Profile skills

A rule decides what a validator can check. The judgment it cannot check, such
as when a page earns its own concept, belongs in the Profile's agent skill. A
package ships one by naming its directory in `skill`:

```text
profile/
  wayfinder-profile.json   # "skill": "skill"
  skill/
    SKILL.md               # name: client-profile
    references/review.md
```

The directory holds an [Agent Skills](https://agentskills.io/specification)
skill. Its `SKILL.md` frontmatter `name` is the Profile id, because the
installed directory is named by the id and Agent Skills requires the two to
match. Every Profile id is a valid skill name.
[`examples/profiles/two-rule/skill/`](../examples/profiles/two-rule/skill/SKILL.md)
is a small example.

`get` and `upgrade` install the skill of every locked package that ships one,
from the package's locked commit, into the project root beside
`wayfinder.json`:

```text
.claude/skills/client-profile/   # read by Claude Code
.agents/skills/client-profile/   # read by agents such as Codex
```

Each directory holds the skill's regular files and a `.wayfinder-profile`
marker that records `{id, release, commit}`. The skill and the rules come from
one commit, so the judgment an agent reads always matches the rules
`validate` runs. A skill directory without `SKILL.md`, or one that holds a
symlink, a submodule, or an entry whose path would leave the skill, fails
`get` before anything is written.

Each directory is staged as a hidden sibling and renamed into place, so an
agent never reads a half-written skill. A directory whose marker already names
the locked revision is left alone, which keeps a second `get` from writing
anything. `get` removes a directory it installed when the package no longer
ships a skill or the Profile is no longer locked. It never replaces or removes
a directory without its marker. When one is in the way, `get` fails before it
writes the lock and names the directory. Move it aside and run the command
again.

**Commit the installed skill directories** with `wayfinder.json` and
`wayfinder.lock`. Teammates and agents without wayfinder then get the same
skill, and a Profile upgrade shows its judgment diff in the same pull request
as the lock change. Do not edit an installed skill by hand, because the next
revision replaces it. A project's own guidance belongs in a skill directory of
its own.

`validate` checks each chain member's installed skill against the lock and
never writes it. A missing directory, or a marker that names another
revision, reports the `wayfinder/profile-skill-stale` warning with the
directories to refresh. It does not change the gate or the exit status,
because the rules still ran. Run `get` to reinstall the locked revision.

## Tags and directories beside a bundle

A Profile package's `tags` array defines stable reusable vocabulary. A
project entry extends that vocabulary for the bundles in `applies_to`:

```yaml
tags: [customer-reporting]
```

A tag definition does not apply a tag automatically. Concepts opt in through
frontmatter, and a tag must describe the concept's actual topic.

A directory beside an OKF bundle, such as a layer of raw evidence, is not part
of the bundle or of any Profile's scope. Its files take no part in tag
validation or Wayfinder search. To make such a directory a searchable OKF
bundle, add its path to the appropriate `applies_to` list and give it the
Profile and vocabulary it needs.

## Profile packages and sharing

A package is data, never code. The engine embeds no Profile, so it treats
Bitwild exactly as it treats any other package. The Bitwild package is
`bitwild-profile`, release `2026.3`, bound to OKF `0.2`, with twelve types, no
tags, eleven relationship names, and the `relationships` frontmatter key. Its
[`README.md`](../profiles/bitwild/README.md) holds one heading per rule id, so
each finding's help link lands on its rule. Its
[skill](../profiles/bitwild/skill/SKILL.md) carries the judgment its rules
cannot check, including the review map Profile Review uses.

A committed `wayfinder.json` shares the Profile source reference, application
paths, and project vocabulary. The lock shares the resolved commit. Neither
file carries rules or validator code. Each machine resolves the same source
into its local cache. The committed skill directories share the Profile's
judgment at that commit.

## Validation order

For `validate`, Wayfinder processes the explicit bundle in this order:

1. Inspect the bundle and run independent OKF validation.
2. Discover the nearest `wayfinder.json` above the bundle. Without one, the
   run reports `wayfinder/config-missing`; with one that does not list the
   bundle, `wayfinder/bundle-unbound`. Either leaves the Profile
   `NOT ASSESSED`.
3. Parse the selected configuration, check safe `applies_to` paths, and read
   the selected chain from a current lock/cache without network or writes,
   following each locked package's `extends` to the root.
4. Parse each package in the chain, including its rule tests, then compose
   the chain and the project entry. A package that fails reports
   `profile-invalid` or `profile-unsupported`, and a chain that does not
   compose reports `profile-composition`. A chain member's installed skill
   that is missing or not at the locked commit reports the
   `profile-skill-stale` warning.
5. When OKF passed, run the rules of every package in the chain against the
   composed vocabulary, parent first. Contextual rules are left to Profile
   Review.
6. Derive the gate. An OKF failure or an error finding fails it. Otherwise
   any error diagnostic, such as a selection that failed in steps 2 to 4,
   makes it `INCOMPLETE`.

Wayfinder checks `wayfinder.json` and each package against the published
schemas first and reports the first violation with its JSON pointer, for
example `wayfinder.json is invalid at /profiles/client-profile: has unknown
property rules.` It then enforces the checks that a schema cannot prove,
such as package parents, composition, overlapping bundle paths, whether a
bundle exists, whether a source resolved, and whether a concept's actor
reference is used correctly.

## Compatibility and migration

The former `profiles` + `bundles` / `implements` version-1 draft was
never published and is not accepted by this parser. Convert any
pre-release draft configuration to direct `source` + `applies_to` before
validation.

A published Bitwild 2026.2 bundle declares its Profile inside the bundle, and
this engine does not read that declaration. Such a bundle reports
`wayfinder/config-missing` and gate `INCOMPLETE` until it migrates. To keep
validating it unchanged, pin wayfinder 0.1.x. The
[Bitwild changelog](../profiles/bitwild/CHANGELOG.md#20263) describes the
migration to a `wayfinder.json` binding.
