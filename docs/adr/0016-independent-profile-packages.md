# ADR-0016: Every Profile is an independent package the validator enforces

- Status: accepted
- Date: 2026-10-02
- Scope: Profile representation, selection, results, builtins, and Profile skills, from package format 2
- Driver: a second knowledge base that needs its own Profile without Bitwild, and engine failures that let link rules pass unassessed

## Context

The engine used to install one base Profile that every chain had to reach,
and any other Profile identity was unsupported. A consumer's `wayfinder.json`
wired each chain, so one Profile could mean different things in different
projects. The engine reported its own failures as Profile rules: a link graph
that could not be built became a finding, and the link rules then passed
without running. Above all this sat a prose Profile that claimed authority
over the rules but held judgments no validator could check, so a bundle could
pass `wayfinder validate` and still fail its Profile, and no tool could say
which.

## Decision

**A Profile is a package, and the package is the Profile.** A Profile is one
directory at one Git revision holding `wayfinder-profile.json` in package
format 2: identity, OKF binding, vocabulary, frontmatter keys, rules
([ADR-0015](0015-profile-rule-catalogs.md)), an optional parent, an optional
`docs` URI, and an optional skill. One parser reads every package. The engine
embeds no Profile and treats none as a base or a default.

**Conformance is what the validator decides.** Conformance to a Profile is the
gate `PASS` with that Profile selected. A package's README explains its rules,
one heading per rule id, so each finding's `help_uri` lands on its rule. Its
skill carries the judgment no rule can decide. Neither adds a requirement. The
framework contract lives once, in the
[engine contract](../../implementation/okf-implementation-guide.md#5-profile-packages).

**Precedence is OKF, then the engine contract, then each Profile.** The engine
contract is the implementation guide plus the published schemas.

**The id is the namespace.** A Profile id is lowercase kebab-case, at most 64
characters, and never a reserved name. It is the finding namespace, the
`wayfinder.json` key, the lock key, and the skill directory name.

**A package names its own parent.** `extends` lives in the package, at the
same revision or at its own Git ref, so a Profile means the same thing in
every project. Composition only adds. `wayfinder get` resolves each Profile's
Git source to one commit in a flat `wayfinder.lock`; validation reads the
lock and local cache and never fetches.

**The engine reports its own health as diagnostics.** A closed set of
`wayfinder/*` diagnostics covers configuration and execution problems. The
gate is derived: `FAIL` when OKF fails or a rule reports an error,
`INCOMPLETE` when an error diagnostic means some rule did not run, and `PASS`
otherwise, so a `PASS` always means every selected rule ran.

**Builtins are engine capabilities.** A builtin is named for what it checks
and configured by `params`. It never holds policy, never names a Profile, and
never reports engine health. A check becomes one only when a schema over one
subject's facts cannot express it.

**Each Profile ships its own skill.** `wayfinder get` installs a package's
`skill` directory, pinned to the locked commit, into `.claude/skills/<id>/`
and `.agents/skills/<id>/`, and projects commit the copies. The generic skills
under `skills/` know OKF and the CLI and no particular Profile.

## Options considered

- **A separate manifest and rule catalog.** Rejected because the pointer
  between them and the two-file read stayed, and a two-rule Profile still
  needed two files.
- **`extends` in `wayfinder.json`.** Rejected because a Profile's meaning
  would vary by project, so its skill could not be written against a fixed
  parent.
- **Embedding Bitwild as a seeded cache.** Rejected because the engine would
  ship and version one Profile again.
- **A prose Profile with authority over the package.** Rejected because it
  made conformance something no tool decided.

## Consequences

A Profile author edits one file and gets one parse error at `get` rather than
a silent difference at `validate`. Any Profile, including one with two rules
and no Bitwild, is selected, fetched, and evaluated by the same path, which
[`examples/profiles/two-rule`](../../examples/profiles/two-rule/README.md)
exercises in CI. A run that cannot assess everything exits `2` even when OKF
and every evaluated rule pass.

A change to the engine contract needs an ADR, a guide change record, and a
`format` bump when an existing package would read differently. A change to a
Profile follows that Profile's own release process.

## Reconsider when

A child Profile needs to exclude or re-grade an inherited rule; that needs a
named field in the child package and a new `format`, never consumer
configuration. Reconsider the flat lock when one project needs two revisions
of one Profile at once.
