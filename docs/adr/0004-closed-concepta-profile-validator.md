# ADR-0004: First implement a closed Concepta Profile validator

- Status: accepted
- Date: 2026-08-21
- Deferred exploration: [#17](https://github.com/conceptadev/wayfinder/issues/17)
- Specification: [#21](https://github.com/conceptadev/wayfinder/issues/21)
- Release delivery: [#22](https://github.com/conceptadev/wayfinder/issues/22), [#23](https://github.com/conceptadev/wayfinder/issues/23), [#24](https://github.com/conceptadev/wayfinder/issues/24), [#25](https://github.com/conceptadev/wayfinder/issues/25), [#19](https://github.com/conceptadev/wayfinder/issues/19)
- Validator delivery: [#26](https://github.com/conceptadev/wayfinder/issues/26), [#27](https://github.com/conceptadev/wayfinder/issues/27), [#28](https://github.com/conceptadev/wayfinder/issues/28), [#20](https://github.com/conceptadev/wayfinder/issues/20)

## Context

The Concepta OKF Profile earns its place by concentrating company-wide choices
that OKF deliberately leaves to producers. Removing it would scatter those
choices across repositories, skills, and tools. The proposed generic Profile
platform did not pass the same deletion test: with only one real Profile, its
manifest language, provider seam, executable registry, suppressions, and
Profile-aware write path added interfaces for hypothetical consumers rather
than concentrating proven variation.

The Profile also contains two different kinds of convention. Some requirements
can be determined reliably from bundle state; others require contextual
judgment, such as deciding whether a directory names the true subject shared by
its concepts. Treating both as deterministic rules would make the CLI overclaim
what it had proved.

## Decision

The first implementation is a closed Concepta OKF Profile validator layered in
one direction over the public `okf` library. `okf` remains independently
responsible for OKF loading, models, Spec conformance, and generic bundle
operations; it never knows that the Concepta Profile exists.

Every Profile rule must pass an OKF 0.2 compatibility test. It may require or
discourage an OKF-permitted producer choice, but it must use only OKF-permitted
constructs, preserve every OKF field and reserved file's upstream meaning, leave
the OKF graph contract uninterpreted, and never turn a Profile result into an OKF
result. A generic OKF consumer must remain able to read the bundle normally. A
rule that needs a new OKF field or meaning is rejected or pursued upstream before
the Profile can adopt it.

Only a bundle conforms to the Profile. Repository adoption choices such as the
bundle's location, the number of bundles in a repository, installation, and CI
belong to the implementation guide and setup skills rather than bundle
conformance.

A Profiled Bundle always contains root `index.md`, `log.md`, `profile.md`, and
`types.md`. It also contains root `actors.md` whenever any concept uses an actor
identifier in an OKF actor-valued field. The CLI can determine this condition
from bundle state; an actor-free bundle need not carry an empty registry.

`types.md` must declare every type used by the bundle. The Profile publishes a
preferred standard vocabulary but does not close that vocabulary: a project may
register a type that the Profile does not yet define. An unregistered used type
fails deterministic Profile validation. A registered nonstandard type produces
a non-blocking advisory, and Profile Review determines whether an existing
standard type would have expressed the concept accurately. Repeated extensions
are evidence for a later Profile release, not an implicit change to the current
release. OKF consumers remain required to tolerate every type; these are
producer-side Profile rules only.

Every bundle seeds and retains all fourteen standard Profile types in
`types.md`, including types it has not used yet, in the Profile's canonical
order and with their standard meanings. Project-specific types follow in lexical
order when introduced. Indexes form groups only for types actually present in
concepts. A concept using a standard type must match that type's meaning; this is
a mandatory judgment rule assessed by Profile Review.

When present, `actors.md` uses the fixed columns `Actor ID`, `Name`,
`Organization`, `Side`, `Role`, and `Active`. Automated validation checks the
table shape and that every actor identifier used by the bundle is represented;
Profile Review assesses whether the recorded identity, affiliation, role, and
active period are true in context.

`Side` is the closed vocabulary `client`, `internal`, `vendor`, `tool`, and
`unknown`. Automated validation checks membership in that vocabulary; Profile
Review checks whether the selected value is truthful. Authors and agents use
`unknown` rather than infer an affiliation without evidence.

One OKF actor ID may have multiple registry rows with non-overlapping `Active`
periods when affiliation changes. `generated` and `verified` resolve the row at
their event timestamp; `sources[].author` may use an applicable
`last_modified`, but without a reliable date its affiliation remains `unknown`.
The registry never changes the actor string, its OKF prefix, or OKF-derived trust
tier, and ambiguity never invalidates the underlying OKF value. Automated
validation checks interval shape and overlap; Profile Review checks historical
truth.

The root `log.md` is authored bundle history, not a projection of current
concept state. This is consistent with OKF 0.2 §9, which defines logs as
date-grouped history and does not require them to be derived. Automated
validation checks its presence and mechanically decidable format and ordering
rules. Every entry has a bold lead word. The Profile supplies a preferred but
extensible vocabulary including `Creation`, `Update`, `Move`, and
`Deprecation`; an unfamiliar lead word is not by itself a failure. Profile
Review assesses whether material lifecycle events were recorded. Version-control
history may corroborate that review but is not the log's source of truth.

Indexes are fully derived, discardable navigation. Their membership, grouping,
ordering, labels, and descriptions must be recoverable deterministically from
paths, concept metadata, and the type registry. They contain no authored
directory description or ordering that exists only in an index. A caller may
therefore regenerate them through generic OKF write operations without a
Profile-specific write planner. The next Profile release must define the
projection's inputs and result; the implementation guide may describe tool
mechanics but cannot change that result.

Index conformance is semantic rather than byte-for-byte. Automated validation
compares parsed membership, grouping, ordering, labels, targets, and
descriptions while ignoring harmless Markdown presentation differences. A
later linting phase may diagnose or normalize presentation without changing
conformance. The root index covers `log.md`, `profile.md`, `types.md`, optional
`actors.md`, every other root concept, and every immediate directory; it omits
only itself. `log.md` belongs to the fixed `Bundle` group.

The canonical semantic projection uses a root `Bundle` group for `log.md`,
`profile.md`, `types.md`, and optional `actors.md`. Other concepts are grouped
under their exact registered type name. Immediate subdirectories appear under
`Directories`; that name avoids misclassifying the special `references/`
directory as an area. Type groups follow registry order, with custom types
afterward in lexical order. Entries within a group sort by title and then path.
Directory labels derive from their paths and carry no invented description.
Non-Markdown files under `references/` appear in an `Assets` group.

Every nonempty directory must contain an `index.md`; automated validation can
assess that rule completely. The Profile continues to define four optional,
lazily created directory names: `architecture/` and `ways-of-working/` are
ordinary conventional subject areas, while `interactions/` and `references/`
retain their special time- and source-oriented organization.

Project-named directories must name the subject their contents share rather
than a document type. This remains a mandatory Profile rule even though its
full meaning requires judgment. Automated validation checks only mechanically
provable collisions with registered type names; Profile Review assesses whether
the claimed shared subject and each concept's placement are truthful.

The Profile no longer requires three concepts before an area may exist. A
numeric threshold cannot establish a shared subject and would force path churn
when a third concept appears. Authors and agents should not create speculative
areas, but Profile Review evaluates that guidance from the actual corpus rather
than from a count.

The Profile sets no numeric threshold for further index grouping or directory
nesting. Type grouping is already deterministic; additional subject nesting is
a contextual navigation decision assessed by Profile Review.

An area may contain an ordinary, specifically named concept with durable
knowledge about its subject. It must not contain a generic `overview.md` that
merely duplicates the generated index. Profile Review distinguishes a real
subject concept from a second navigation artifact.

A Profiled Bundle may use every frontmatter field defined by its pinned OKF
release but must not introduce producer-defined fields. Automated validation
checks the keys against OKF. Information with no OKF field belongs in the body
or another existing OKF mechanism; a new structured field must be added
upstream before a later Profile release can rely on it. The Profile cannot
extend OKF's schema on its own.

Tags express topics only. They must not duplicate a concept's type, lifecycle,
trust, or resolution state. Automated validation catches literal duplication
with machine-readable fields and values; Profile Review catches semantic aliases
that would create a second source of truth.

Every Concepta concept must carry nonempty `type`, `title`, `description`, and
`status` fields using their OKF-defined meanings. Automated validation checks
presence, shape, and closed values; Profile Review assesses whether the title,
description, and lifecycle state are accurate. `generated` remains recommended:
its absence produces a non-blocking advisory, and neither a tool nor an agent may
fabricate provenance to clear it. Other OKF fields are used when their upstream
meaning applies.

A concept that materially derives claims from identifiable source material must
record that material with OKF `sources`. Automated validation checks source
shape and joins from attribution footnotes; Profile Review assesses whether
material provenance is missing. Original analysis, guidance, and decisions do
not invent sources merely to satisfy the rule.

`verified` is recorded only when an actor actually performed the verification
OKF defines. Its absence is meaningful trust data and produces neither a failure
nor an advisory. The Profile therefore removes any recommendation that confirmed
facts should carry a verification event.

`status` describes the document lifecycle using only OKF's meanings. It must not
encode execution workflow or an assessment of how settled the subject is.
Automated validation checks its value; Profile Review checks its meaning in
context. `stale_after` is similarly evidence-based: the Profile does not prohibit
it by concept type, and authors use it only when the content has a genuine
freshness horizon.

Unresolved internal links remain non-blocking advisories. Automated validation
reports them while preserving OKF's unresolved-edge representation; neither OKF
nor Profile conformance fails solely because a target is absent. Profile Review
may still identify an unresolved edge as a concern in its context.

Tracker-owned issues, pull requests, and other execution records stay external
and must not be mirrored as bundle concepts. Their workflow state remains in the
tracker, while durable concepts link to them. Whether an artifact is execution
or durable knowledge is determined by which system owns its lifecycle, and a
durable specification has exactly one authoritative home. This is a mandatory
judgment rule assessed by Profile Review.

The Profile publishes a preferred relationship-label vocabulary but permits a
project to introduce another label. Automated validation reports a nonstandard
label as a non-blocking advisory. Its meaning is defined once in a durable
project Guide and Profile Review checks its use; the first implementation adds
neither a relationship registry nor a label-provider mechanism.

Profile relationships remain structured Markdown in the optional
`# Relationships` section. Automated validation checks that each entry has one
label and one target, and Profile Review assesses its meaning. The ordinary OKF
graph discovers each target as a body-link edge and remains the only graph
implementation; its edge contract is intentionally untyped and the Profile does
not reinterpret or enrich it. The Profile skill authors the section through a
generic OKF concept update rather than depending on `link-concepts`, whose
producer-defined `sources` representation is different from this convention.

Concept paths use readable lowercase kebab-case and exclude mutable metadata
such as status, owner, priority, and Profile version. An identifier already
cited outside the bundle may lead a readable slug and must not be renumbered.
Dates may appear whenever chronology is part of the subject's stable identity;
they must not encode mere creation time, freshness, workflow state, or an
editable version. Profile Review assesses the complete path rule because an
externally cited ID has no Profile-specific syntax that deterministic validation
can distinguish from the authored slug.

A move repairs known inbound links, regenerates affected indexes, and records
the event in the authored root log. A path freezes only when a known external
citation cannot be repaired. The skill performs those coordinated authoring
steps; the final validator checks the resulting bundle state and reports any
unresolved internal link as the non-blocking advisory already defined above.

Stable concepts are normally retired with `status: deprecated` and a successor
relationship when one exists. Draft concepts may be deleted. Hard deletion of a
stable concept is reserved for security, privacy, legal, secret-removal, or
genuinely erroneous-content cases and is assessed through Profile Review.

The root `profile.md` declaration remains compact Markdown whose first fenced
YAML block declares both `concepta_profile` and `okf_version`. The latter must
match the root index declaration and the OKF release bound by the selected
Profile release. Automated validation checks all three values for agreement.

The first validator implements only the new Profile release. A declaration for
an older or newer release produces a distinct `UNSUPPORTED PROFILE RELEASE`
result rather than a Profile-conformance verdict, while the independent OKF
result is still exposed. Historical validators are added only when a real
migration demonstrates the need.

Material is mirrored under `references/` only when a concept cites it, its
availability is genuinely at risk, and repository visibility is appropriate.
Text and necessary optimized images may be mirrored; heavy audio, video, and
other binaries stay external, with a transcript preferred when preservation is
needed. Automated validation checks baseline and original-source provenance for
content identified as a mirror. Profile Review assesses mirror classification and
placement, need, availability risk, confidentiality, sanitization, optimization,
and media classification because the Profile defines no canonical detector or
weight threshold.

The Profile does not enumerate unused OKF mechanisms. Where the Profile is
silent, every mechanism allowed by the pinned OKF release remains allowed and
is interpreted only by OKF. In particular, the existing Attested Computation
inventory is removed rather than maintained as a parallel compatibility list.

A source event becomes a concept only when it produces durable knowledge worth
preserving. Meetings, messages, recordings, and transcripts must not become
concepts merely because they occurred. This is a mandatory judgment rule
applied by the authoring skill and Profile Review, never inferred by the CLI.

Promotion and splitting remain recommendations because legitimate boundary
cases exist. An outcome should become its own concept when it needs independent
lifecycle, provenance, relationships, reuse, or history; a concept should split
when its parts need materially different lifecycle or verification. Their
`SHOULD` force reflects acceptable variation rather than assessment difficulty.

An Interaction Record must not be routine minutes. It is created only when an
interaction's combined context is itself durable; otherwise authors capture its
durable outcomes with provenance and leave the source event external.

Type-specific body shapes move to compact authoring guidance in the Profile
skill. Their headings are not validated and are not bundle-conformance rules.
Bodies retain OKF's freedom except for the optional machine-readable
`# Relationships` section defined above.

The validator dispatches by the Concepta release selected in `profile.md` and
applies that release's immutable deterministic rules. It exposes the OKF and
automated Profile results separately. A bundle cannot inject, omit, replace, or
parameterize the release's rules.

The first command surface is `okfp validate <bundle> [--output text|json]`.
The bundle path is required. There is no `--profile`, `--strict`, or equivalent
caller-selected policy option; the release comes only from the bundle's
`profile.md`, and advisories never change the exit status.

Exit code `0` means both OKF and deterministic Profile checks passed. Exit code
`1` means either set of checks failed. Exit code `2` means the invocation could
not assess the declared Profile release, including usage, I/O, and unsupported
release outcomes; unsupported is never described as nonconformance.

Text and JSON expose four explicit states: OKF is `PASS` or `FAIL`;
deterministic Profile validation is `PASS`, `FAIL`, `UNSUPPORTED`, or
`BLOCKED BY OKF`; judgment rules are `UNASSESSED`; and the automated gate is
`PASS`, `FAIL`, or `UNSUPPORTED`. The OKF Report is preserved exactly and
Profile findings cannot reclassify it.

`okfp` loads and validates through the public `okf` Dart library exactly once;
it does not spawn the `okf` executable or reproduce OKF parsing, models,
findings, graph behavior, or filesystem rules. When OKF fails, deterministic
Profile validation stops with `BLOCKED BY OKF`, emits no cascading Profile
findings from the partial bundle, and the automated gate exits `1`.

Validation inspects exactly the bundle directory supplied by the caller. It
does not walk upward for `knowledge/` or assume any repository layout. A single
`okfp validate <bundle>` invocation is the complete automated CI gate because it
already includes and exposes OKF validation; a separate `okf validate` remains
optional for focused base diagnostics.

Each deterministic Profile finding has a stable semantic identifier in the
`concepta-profile/<rule-slug>` namespace and also names the Profile release and
normative rule reference. Identifiers do not depend on section numbering or
implementation class names.

The CLI may also report deterministic `SHOULD` and `SHOULD NOT` advice, but
advisories do not affect conformance or exit status. The first interface has no
global `--strict` mode that promotes every recommendation into a requirement.

A successful CLI run claims only that OKF conformance and the deterministic
Profile checks passed. It explicitly reports judgment rules as unassessed and
has no model dependency. Complete Profile assessment combines that automated
result with a separate Profile Review; the CLI does not claim complete Profile
conformance on its own.

Normative force and assessment mode are independent. A rule is a `MUST`, `MUST
NOT`, `SHOULD`, or `SHOULD NOT` because of its policy force, not because code can
evaluate it. Deterministic rules are assessed by the CLI; judgment rules are
assessed contextually by humans and agents. The deterministic CLI has no model
dependency and does not claim to prove contextual judgment.

One model-invoked `okf-profile` skill owns both the authoring and post-write
Profile Review workflows. It teaches only the Concepta delta and explicitly
delegates OKF mechanics to the OKF documentation and tools. Other engineering
skills delegate to it rather than copying its rules, because copied upstream or
Profile instructions can drift.

An agent may complete Profile Review autonomously when the judgment rules are
clear and the required context is available. It escalates ambiguous mandatory
rules, apparent rule conflicts, missing external context, and proposed
exceptions to a human. The skill emits a standardized Profile Review Report in
the active interaction or pull request; it does not add a generic review
certificate to the bundle. Only independently durable decisions or rationale
belong in bundle content.

The report is concise Markdown. It identifies the Profile release, review
scope, automated-validation state, reviewed judgment-rule references, and one
outcome: `PASS`, `CHANGES REQUIRED`, or `NEEDS HUMAN`. It gives detailed prose
only for concerns, decisions, or uncertainty. Routine review covers changed
concepts and their directly affected placement, indexes, relationships, and
dependents; adoption, Profile upgrades, migrations, and structural
reorganizations review the whole bundle. Automated validation always checks the
whole bundle.

The normative Profile states bundle rules without naming their implementation.
The implementation guide carries an exhaustive coverage matrix mapping every
normative clause to deterministic CLI validation or contextual Profile Review,
and the skill implements the review side of that mapping. Assessment mode is
therefore explicit without making tool architecture part of bundle conformance.

A generic Profile protocol and the related machinery are deferred until real
use supplies at least a second Profile or another concrete trigger recorded in
issue #17.

These decisions ship as Concepta Profile `2026.1`, which carries its own change
record and driver in §15.3.

The release includes a non-normative, rule-by-rule OKF compatibility review at
`docs/compatibility-review.md`. Profile §15.3 summarizes and links that
evidence; the separate implementation coverage matrix maps each normative rule
to automated validation or Profile Review. Compatibility evidence answers
whether a rule preserves OKF, while coverage answers how Concepta assesses it.

Delivery uses tracer-bullet slices under specification #21. A release-frame
slice gates three domain slices covering structure, concepts, and external
boundaries; #19 integrates and publishes them atomically so no distribution
surface teaches stale rules. An OKF-backed validator tracer then gates concept
and structure validation slices; #20 integrates their coverage, installs CI,
and removes the legacy validator. Each slice fits one fresh context while the
two integration tickets preserve atomic release and gate outcomes.

## Consequences

- The first implementation has no public Profile provider seam, executable rule
  registry, caller-selected activation, or standalone Profile Definition YAML.
- Suppressions wait for a migration that demonstrates their need and governance.
- Profile-aware MCP writes and Profile-owned filesystem transactions wait for a
  concrete authoring workflow that plain OKF operations cannot support.
- `profile.md` remains the in-bundle release declaration and ordinary OKF
  concept; it does not become a rule configuration surface.
- `log.md` must be removed from every definition and example of a derived
  projection in the next Profile release.
- Existing indexes must remove authored directory descriptions and regenerate
  into the canonical semantic groups and ordering. Removing the large-index
  numeric threshold and allowing genuine subject concepts otherwise relaxes the
  Profile.
- Canonical index presentation and automatic formatting are deferred to a
  separate linting phase; the first validator needs only the semantic check.
- No typed-relationship graph, graph adapter, or upstream OKF request is added
  now. A concrete consumer that cannot operate on OKF's untyped edges is the
  trigger to revisit that decision.
- Removing the three-concept area threshold relaxes the Profile. Existing
  conformant bundles require no migration, and smaller existing subject areas
  do not become nonconformant.
- Broadening date-bearing identities and the exceptional reasons for deleting a
  stable concept invalidates no existing conformant bundle.
- Removing type-specific body templates from Profile assessment relaxes the
  Profile and requires no migration of existing content.
- A bundle declaring an older Profile release must update its declaration and
  complete that release's stated migration before the first validator can assess
  Profile conformance. Until then its Profile result is unsupported, not failed.
- `tools/verify_knowledge_bundle.py` is deprecated as an implementation surface
  and is deleted in the validator change once `okfp validate` replaces its CI
  responsibilities. It does not remain as a fallback validator.
- Bundles using a type absent from `types.md` become nonconformant under the next
  Profile release and must register it. Already registered project-specific
  types remain conformant and gain only an advisory.
- Type registries missing any standard Profile type must add the canonical row;
  unused standard rows do not require placeholder concepts or index groups.
- Concepts missing `title`, `description`, or `status` become nonconformant under
  the next Profile release and must add truthful values. Missing `generated`
  remains conformant and gains only an advisory.
- Concepts materially derived from identifiable sources become nonconformant if
  that provenance is omitted and must add truthful `sources` entries. Removing
  verification pressure and type-based freshness advice invalidates no existing
  conformant bundle.
- The first `okfp` interface validates only. Authoring and generic bundle
  mutation are not added to it.
- `okfp validate` obtains and exposes the closed OKF validation result before
  applying Concepta checks. Running `okf validate` separately remains useful for
  focused base diagnostics but is not required for a complete Profile gate.
- CI runs the model-independent automated gate only. It must not claim that
  judgment rules or complete Profile conformance were assessed.
- The next Profile release and implementation slices must be reshaped through a
  new design session rather than revived from the superseded issue set.
