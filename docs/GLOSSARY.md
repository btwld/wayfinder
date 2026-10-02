# Wayfinder glossary

The shared language for validating Open Knowledge Format bundles against
Profiles with wayfinder.

## Language

**OKF Specification**:
The authoritative Open Knowledge Format specification. The engine contract and
every Profile build on it and cannot redefine or weaken its meaning.
_Avoid_: Base profile, upstream profile

**Engine contract**:
The [implementation guide](../implementation/okf-implementation-guide.md) and the
JSON Schemas under [`schemas/`](schemas/). It says what a Profile package is and
how wayfinder selects, evaluates, and reports on one. It ranks below OKF and
above every Profile.
_Avoid_: Profile text

**Profile**:
A package of vocabulary and rules that adds requirements to OKF. A Profile is
what `wayfinder validate` enforces. Bitwild is the first one.
_Avoid_: Format, base Profile, standard

**Profile package**:
A directory at one Git revision holding `wayfinder-profile.json` in package
format 2, and optionally a README, a changelog, and a skill. The package is the
Profile; its prose explains it and adds no requirement.
_Avoid_: Manifest, rule catalog

**Profile id**:
A package's one name. It is the finding namespace, the key in `wayfinder.json`
and the lock, and the name of the installed skill directory, such as
`bitwild-profile`.
_Avoid_: Alias, namespace mapping

**Chain**:
A Profile and the ancestors its package names through `extends`, root ancestor
first. A chain need not reach any particular Profile.
_Avoid_: Base chain

**Effective Profile**:
The chain and the project binding's additions composed into one set of
vocabulary and rules before evaluation.
_Avoid_: Merged registry

**Profile Binding**:
The project-root `wayfinder.json` entry whose direct Git `source` and
`applies_to` paths select one Profile for a whole bundle, with additive project
types, tags, relationship names, and actor lookup. It cannot define or override
rules.
_Avoid_: Rule manifest, per-directory Profile

**Builtin**:
A check the engine implements and versions, which any package's rule can call by
name with `params`. It names what it can check, never the rule a Profile builds
with it.
_Avoid_: Built-in rule, plugin

**OKF Conformance**:
The judgment, made exclusively under the OKF Specification by okf, that a bundle
meets OKF's conformance requirements.
_Avoid_: Base acceptance

**Profile Conformance**:
The gate `PASS` from `wayfinder validate` with that Profile selected. OKF passes,
every rule in the chain runs, and no rule reports an error.
_Avoid_: OKF conformance, policy acceptance

**Engine diagnostic**:
A `wayfinder/<code>` report about the run itself, never about the bundle, such as
a missing configuration or a link graph that could not be built.
_Avoid_: Profile finding, rule

**Gate**:
The one result derived from OKF, Profile findings, and diagnostics. It is `FAIL`
when OKF fails or a rule reports an error, `INCOMPLETE` when an error diagnostic
means a rule did not run, and `PASS` otherwise.
_Avoid_: Automated gate, UNSUPPORTED

**Profile skill**:
A Profile's agent guidance, shipped in its package and installed by
`wayfinder get`. It carries the judgment no rule can decide and is not
conformance.
_Avoid_: Judgment rules, normative text

**Profile Review**:
A contextual review by a human or agent using a Profile's skill, such as whether
a placement fits its subject. It is guidance, distinct from validation, and never
reported as checked.
_Avoid_: Validation, deterministic finding

**Profile Review Report**:
A structured, non-bundle summary of a Profile Review, suitable for the active
interaction or pull request. It records reasoning and escalations without
becoming knowledge content.
_Avoid_: Bundle concept, conformance certificate
