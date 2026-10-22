# ADR-0015: Profile rules are data

- Status: accepted
- Date: 2026-10-01
- Updated: 2026-10-07 (Ack evaluates rule schemas); 2026-10-22 (`matches-generated` pins okf's generator revision)
- Scope: how a Profile's rules are represented and evaluated
- Driver: a second knowledge base, over the same okf release, that keeps its frontmatter rules in JSON Schema

## Context

Every Profile rule was compiled Dart, with release differences branched
inside rule bodies. A Profile author could not add, drop, or re-grade a rule
without a binary release. A probe over every fixture showed that one JSON
Schema per rule, evaluated against a typed record, reproduces the compiled
findings for frontmatter and structure rules. The rules that resisted this
were either not Profile rules, such as tool failures, or policy mixed with
Markdown parsing.

## Decision

A Profile's rules are data in its package
([ADR-0016](0016-independent-profile-packages.md)): each rule declares its
id, category, severity, status, description, message, and check. The engine
evaluates them in three parts.

1. **Facts.** After OKF passes, the engine parses the bundle once into typed
   subjects, such as `frontmatter`, `concept`, `directory`, `file`, `log`, and
   `root`. Every join happens here. A fact is added only when more than one
   Profile would plausibly use it.
2. **Checks.** A check is a JSON Schema over one subject kind, answering pass
   or fail, or a named builtin with `params`. Finding identity, location, and
   cardinality come from the rule and the subject, never from schema-library
   errors. [Ack](https://pub.dev/packages/ack) evaluates each schema. The
   engine owns the JSON Schema keyword subset it admits, the analysis that
   checks a schema's property names against its subject's facts, and all
   message wording. The description of
   [`wayfinder-profile.schema.json`](../schemas/wayfinder-profile.schema.json)
   lists that subset.
3. **Declaration.** A package enforces exactly the rules it declares; it turns
   a rule off by not declaring it. There are no consumer overrides or
   suppressions.

Each schema rule carries pass and fail `tests` that run when the package is
parsed. A rule's severity is `error`, `advisory`, or `note`; a note produces
summary entries, never findings. A package that names a subject, builtin, or
keyword the engine lacks is reported unsupported and never partially applied.

A builtin whose verdicts depend on code the engine does not own pins that
code by what it produces, not by its release. `matches-generated` compares a
bundle with okf's index generator, and its optional `version` param names
okf's generator revision, `okfIndexGeneratorRevision`: the okf release that
last changed the generator's output. okf changes that output only in a minor
release, so the engine depends on a range of okf releases within one
revision and reports the release it runs as `engine.okf`. A package that sets
`version` loads only on an engine whose generator writes the bytes its
verdicts assume, and the engine can take an okf release that leaves those
bytes alone without any Profile changing its release
([guide §§3.1 and 5.6](../../implementation/okf-implementation-guide.md#56-rules-and-builtins)).

## Options considered

- **One annotated schema per Profile.** Rejected because finding identity
  would depend on schema-library error reports, and one schema cannot carry a
  severity per rule.
- **An evaluator owned by the engine.** Replaced by Ack, because findings
  never read schema errors; only pass or fail comes from Ack, and the
  published schemas word their first failure from Ack's `keyword` and
  `pointer` locators.
- **An expression language such as CEL or JSONLogic.** Rejected for lack of a
  mature Dart implementation and for the review cost of cross-record
  expressions in source-provided rules.
- **Consumer overrides in the style of ESLint or Spectral.** Rejected because
  a Profile is a conformance contract; authors control rules by declaring
  them.
- **`version` as the okf release, with okf pinned to one patch release.**
  Replaced, because any okf release, even one that leaves the generator's
  output alone, then changed the pin and stopped every package that sets
  `version` from loading. A host that embeds the engine could not take an okf
  fix without a wayfinder release.

## Consequences

Profile authors change rules by editing their package and its examples.
Adding a fact, builtin, or schema keyword is an engine release. Golden reports
for every fixture are the regression oracle for engine changes, so a wording
change is a reviewed golden diff.

Pinning the generator revision keeps package format 2. Format names what the
engine must understand to read a package, and no package reads differently:
`version` keeps its syntax and still names the generator output a package's
verdicts assume. Every released engine that reads format 2 runs okf 0.5.0,
whose generator revision is 0.5.0, so a package that sets `version` to
`0.5.0`, Bitwild 2026.3 included, loads and yields the same findings as
before, and no other value could load on a released engine. Only the
`engine.okf` value moves with the okf release, which guide §5.6 already
treats as an engine change rather than a Profile change.

A package is data, so it cannot run code or change another package's
findings. Its `pattern` keywords run on Dart's backtracking regular-expression
engine, though, and a hostile pattern can stall validation, so a project
configures only Profile sources it trusts.

## Reconsider when

A real rule cannot be expressed over the engine's facts and builtins without a
rule-specific fact.
