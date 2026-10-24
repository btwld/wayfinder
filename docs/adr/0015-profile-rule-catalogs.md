# ADR-0015: Profile rules are data

- Status: accepted
- Date: 2026-10-01
- Updated: 2026-10-07 (Ack evaluates rule schemas)
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

## Consequences

Profile authors change rules by editing their package and its examples.
Adding a fact, builtin, or schema keyword is an engine release. Golden reports
for every fixture are the regression oracle for engine changes, so a wording
change is a reviewed golden diff.

A package is data, so it cannot run code or change another package's
findings. Its `pattern` keywords run on Dart's backtracking regular-expression
engine, though, and a hostile pattern can stall validation, so a project
configures only Profile sources it trusts.

## Reconsider when

A real rule cannot be expressed over the engine's facts and builtins without a
rule-specific fact.
