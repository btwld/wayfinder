# ADR-0016: Make every Profile an independent package the validator enforces

- Status: proposed (accepted when it merges with the change that implements it)
- Date: 2026-10-02
- Scope: Profile representation, selection, results, builtins, and Profile skills, from package format 2 onward
- Supersedes: [ADR-0004](0004-closed-concepta-profile-validator.md) wholly; [ADR-0014](0014-external-profile-bindings.md) in part, for its installed base, its exact-release dispatch, and `extends` in `wayfinder.json`
- Amends: [ADR-0008](0008-okfp-adopts-okf-finding-contract.md), whose finding namespace becomes the Profile id; [ADR-0015](0015-profile-rule-catalogs.md), whose rule catalog becomes the `rules` of one package with no installed catalog
- Driver: a second knowledge base that needs its own Profile without Bitwild, and engine failures that let link rules pass unassessed

## Context

ADR-0015 made rules data, but it kept the shape that existed when rules were
compiled Dart. The engine installed one base Profile, and every chain had to
reach it. Nine separate checks enforced that base, and any other Profile
identity made dispatch `UNSUPPORTED`. A child manifest had to declare the
base's release, and the catalog repeated the manifest's identity. Vocabulary
was split between the manifest and the catalog. A consumer's `wayfinder.json`
wired each chain with `extends`, so one Profile could mean different things in
different projects.

The engine also reported its own failures as Profile rules. A link graph that
could not be built was a rule finding, and up to seven link rules then passed
without running. A configuration note was a summary rule, and a failed
`--fix` was a fix state.

Above all of this sat the prose Profile, which claimed authority over the
catalog. It held 81 judgment statements no validator could check, and a
coverage matrix mapped each clause to automated validation or review. A
bundle could pass `wayfinder validate` and still fail its Profile, and no tool
could say which.

## Decision

**A Profile is a package, and the package is the Profile.** A Profile is one
directory at one Git revision holding `wayfinder-profile.json` in package
format 2: identity, OKF binding, vocabulary, frontmatter keys, rules, an
optional parent, an optional `docs` URI, and an optional skill. One parser
reads every package through one boundary. The engine embeds no Profile and
treats none as a base or a default. Bitwild is fetched like any other
Profile, from `profiles/bitwild/` in this repository.

**Conformance is what the validator decides.** Conformance to a Profile is
the gate `PASS` with that Profile selected. A package's README explains its
rules, with one heading per rule id so each finding's `help_uri` lands on its
rule. Its skill carries the judgment no rule can decide. Neither adds a
requirement, and where either disagrees with the package, the package
governs. The prose Profile, its coverage matrix, and its release gate are
deleted. The framework contract every package meets lives once, in the
[engine contract](../../implementation/okf-implementation-guide.md#5-profile-packages).

**Precedence is OKF, then the engine contract, then each Profile.** The
engine contract is the implementation guide plus the published schemas. A
package adds rules within it and never contradicts OKF.

**The id is the namespace.** A Profile id is lowercase kebab-case, at most 64
characters, and never a reserved name. It is the finding namespace, the
`wayfinder.json` key, the lock key, and the skill directory name. Bitwild's
id is `bitwild-profile`, and its findings are `bitwild-profile/*`.

**A package names its own parent.** `extends` lives in the package, either at
the same revision or at its own Git ref, so a Profile means the same thing in
every project. A chain need not reach any particular Profile. Composition only
adds, and format 2 has no field that changes an inherited rule. The lock is
flat and holds one revision per Profile id per project.

**The engine reports its own health as diagnostics.** A closed set of
`wayfinder/*` diagnostics replaces release dispatch states, the link-graph
and project-type rules, and fix states. The gate is derived, never stored.
It is `FAIL` when OKF fails or a rule reports an error, `INCOMPLETE` when an
error diagnostic means some rule did not run, and `PASS` otherwise, so a
`PASS` always means every selected rule ran. The Profile state is `NOT
ASSESSED` when no Profile could be selected. `UNSUPPORTED` and the judgment
component are gone.

**Builtins are engine capabilities.** A builtin is a check the engine
implements, named for what it checks and configured by `params`. A check
becomes one only when a schema over one subject's facts cannot express it.
Three remain: `files-present`, `path-targets-exist`, and `matches-generated`.
The generator text `matches-generated` compares with is engine contract, and
the engine reports its `okf` version.

**Each Profile ships its own skill.** `skill` in the package names a
directory that `wayfinder get` installs, pinned to the locked commit, into
`.claude/skills/<id>/` and `.agents/skills/<id>/`. Projects commit the
installed copies. The generic skills under `skills/` know OKF and the CLI and
no particular Profile. They load each Profile's skill by the chain that
`validate` reports. `create-profile` writes and revises packages.

**The 2026.2 in-bundle selector is a clean break.** The engine dispatches
only through `wayfinder.json`. A 2026.2 bundle validates on wayfinder 0.1.x
or migrates. Bitwild's superseded snapshots stay under
`profiles/bitwild/versions/` as an archive nothing reads.

## Options considered

- **Keep a manifest and a catalog, without the duplication.** Rejected
  because the pointer between them and the two-file read stayed, and a
  two-rule Profile still needed two files.
- **Keep `extends` in `wayfinder.json`.** Rejected because a Profile's
  meaning would vary by project, so its skill could not be written against a
  fixed parent.
- **Embed Bitwild as a seeded cache.** Rejected because the engine would ship
  and version one Profile again. Validation is already offline after `get`. A
  seeded mirror can come later as distribution only.
- **Keep the prose Profile as the authority over the package.** Rejected
  because it made conformance something no tool decided.
- **Keep `UNSUPPORTED` beside a new `INCOMPLETE`.** Rejected because both
  exit `2` and their difference already lives in the diagnostics.

## Consequences

A Profile author edits one file and gets one parse error at `get` rather than
a silent difference at `validate`. Any Profile, including one with two rules
and no Bitwild, is selected, fetched, and evaluated by the path Bitwild uses.

Bitwild's conformance claim narrows to its rules. The judgment its prose
required becomes guidance in its skill, and the
[Bitwild changelog](../../profiles/bitwild/CHANGELOG.md) records the
narrowing and the statements that could become rules later. Every Bitwild
finding id changes namespace, from `concepta-profile/*` to
`bitwild-profile/*`. Consumers rename their `wayfinder.json` key, point
`source.path` at `profiles/bitwild`, and run `wayfinder get`.

A run that cannot assess everything now exits `2` even when OKF and every
evaluated rule pass. A link graph failure no longer lets link rules pass.

`AGENTS.md` splits changes into two kinds. A change to the engine contract
needs an ADR and a guide change record, and a `format` bump when an existing
package would read differently. A change to a Profile follows that Profile's
own release process in its changelog.

## Reconsider when

A child Profile needs to exclude or re-grade an inherited rule. That needs a
named field in the child package and a new `format`, never consumer
configuration. Reconsider the flat lock when one project needs two revisions
of one Profile at once.
