# ADR-0015: Evaluate Profiles as rule catalogs

- Status: proposed
- Date: 2026-10-01
- Scope: Profile rule representation, validator engine, and Profile packages from 2026.3 onward
- Supersedes: [ADR-0004](0004-closed-concepta-profile-validator.md)'s compiled rule representation; [ADR-0014](0014-external-profile-bindings.md)'s vocabulary-only manifest and its exclusion of source-provided rules
- Amends: [ADR-0008](0008-okfp-adopts-okf-finding-contract.md) (descriptor source, finding arguments, summary entries, SARIF)
- Driver: a second real knowledge base's gate, over the same okf release, that keeps its frontmatter rules in JSON Schema

## Context

Every Profile rule was Dart: 47 descriptor constants and about 1,200 lines of
rule bodies. Release differences were 16 `externalBinding` branches inside
those bodies, and the standard type list existed both in Dart and in
`profile/wayfinder-profile.json`, kept equal by a test. A Profile author could
not add, drop, or re-grade a rule without a binary release.

A second knowledge base on the same okf release keeps its frontmatter rules in
one JSON Schema plus `x-` annotations. Its gate maps schema-library errors back
to rule ids by error type and instance path, and its structural rule kinds
remain code. A probe over every
wayfinder fixture showed that one schema per rule, evaluated against a typed
record, reproduces the compiled findings for the frontmatter and structure
rules, and that the rules which resisted this were either not Profile rules
(tool failures, telemetry advisories, a hand-checked generated index) or policy
mixed with markdown parsing.

## Decision

A Profile's automated rules are a **rule catalog**: a versioned JSON document
that is the source of truth for every rule's id, severity, clause, statement,
message, and check. The prose Profile keeps rationale and Profile Review
judgments, and links to the catalog instead of restating automated rules.

The validator becomes a closed **engine** with three parts:

1. **Facts.** After OKF validation passes, the engine parses the bundle once
   into typed subjects: `frontmatter`, `concept`, `actor`, `directory`, `file`,
   `log`, and `root`. Every join (actor first use, area siblings, footnote to
   source) happens here. A fact is added only when another Profile would
   plausibly use it.
2. **Checks.** A rule's check is either a JSON Schema evaluated against one
   subject kind, answering pass or fail, or a named builtin with parameters.
   Finding identity, location, and cardinality come from the rule and the
   subject, never from schema-library errors. The engine owns a small
   evaluator for a declared JSON Schema keyword subset, conformance-tested
   against the JSON-Schema-Test-Suite.
3. **Catalogs.** A catalog declares every rule it enforces. A Profile turns a
   rule off by not declaring it. `extends` imports a parent catalog whole and
   only adds rules in the child's namespace. No consumer overrides or
   suppressions exist.

Profiles are packages: a manifest and a catalog, embedded in the binary or read
from a Git source pinned by `wayfinder.lock`. Catalogs are data evaluated by the
installed engine, which keeps ADR-0014's line that fetched JSON is data and
executable validation stays installed, and replaces its clause that no rules
come from a source. A non-base manifest names its catalog (`rules`); the
resolver reads it at the locked commit, so the lock has no field for it, and
validation reads it from the cache. The catalog must declare the manifest's
identity, report in the namespace that identity names, and declare no
frontmatter keys. The effective chain is the installed base catalog followed
by each source catalog, parent first; every catalog is evaluated whole, so an
ancestor's findings are the same with or without a child. The base source
never names a catalog. A catalog that names a subject, slot, builtin, or
keyword the engine lacks resolves to `UNSUPPORTED` and is never partially
applied.

Findings keep OKF's wire format. The contract is the finding id, severity,
path, and template arguments; message wording is editorial. SARIF 2.1.0 is an
additional output.

A rule's severity is `error`, `advisory`, or `note`. A note rule reports what
the Profile permits as summary entries, which Profile §14.1 keeps apart from
findings: they are never findings and never change a result state or the exit
code.

OKF independence, `BLOCKED BY OKF`, exact-release dispatch, never-fetch
validation, and the four-part result from ADR-0004 are unchanged. The frozen
2026.2 rules ship as an embedded catalog whose registry checks are builtins.

## Options considered

- **One annotated schema per Profile (that second gate's shape).** Rejected because
  finding identity would depend on schema-library error reports, which the two
  Dart libraries produce differently, and one schema cannot carry a severity or
  clause per rule.
- **A facts document with location templates.** Rejected because the template
  language duplicates what a typed subject already knows.
- **An expression language (CEL, JSONLogic).** Rejected for lack of a mature
  Dart implementation and editor support, and for the review cost of
  cross-record expressions in source-provided rules.
- **Consumer overrides in the style of ESLint or Spectral.** Rejected because a
  Profile is a conformance contract; authors control rules by declaring them.

## Consequences

Profile authors change rules by editing a catalog and its examples; each rule
carries pass and fail examples that run as tests. Adding a fact, builtin, or
schema keyword is an engine release. Golden reports for every fixture are the
regression oracle for engine changes; they compare the full report, so a
wording change is a reviewed golden diff.

A read-only probe expressed that second gate's 32 rules as a catalog for this
engine: 22 were expressible and 18 matched its findings exactly across 41
mutated copies of its bundles; 5 needed a fact or builtin the engine lacked and
5 compare two revisions rather than one bundle state, which this engine does
not assess.

Removing the restated rules from the Profile prose is follow-up work, not part
of this change. Until it lands, the Profile still states every automated rule
in prose and governs: Profile §14.1 makes the installed catalog the
machine-readable form of those rules, each citing the clause it assesses and
agreeing with it, and a disagreement is a catalog defect.

Plugins that add facts or builtins from outside the binary remain out of scope.

## Reconsider when

A real rule cannot be expressed over the engine's facts and builtins without a
rule-specific fact, or a second Profile needs consumer-side overrides.
