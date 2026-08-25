# Concepta Profile 2026.2 implementation coverage

Status: Integration draft — incomplete and unpublished

This non-normative matrix assigns each normative Concepta Profile 2026.2 bundle
rule to its assessment mode. It does not decide whether a rule preserves OKF;
that evidence lives in
[`../docs/compatibility/2026.2-okf-0.2.md`](../docs/compatibility/2026.2-okf-0.2.md).
The Profile remains the source of every rule and its normative force.

## Assignment rules

- A **Deterministic Rule** is assessed by `okfp validate` from bundle state and
  the immutable declared release.
- A **Judgment Rule** is assessed contextually by Profile Review.
- Normative force and assessment mode are independent: mandatory rules may
  require judgment, and deterministic recommendations remain advisories.
- Each normative bundle clause must appear exactly once. A release-governance or
  implementation-only clause is identified separately and is not disguised as
  a bundle check.

## Release-frame coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §11: a Profiled Bundle contains root `profile.md` of type `Knowledge Profile` | MUST | Automated Profile Validation | Presence, path, and parsed type |
| §11: the first body `yaml` block is the declaration and declares `concepta_profile: "2026.2"` and `okf_version: "0.2"` | MUST | Automated Profile Validation | Parsed block position, selector, and exact values |
| §11: declaration OKF version agrees with root index | MUST | Automated Profile Validation | Equality of both parsed values |
| §11: `profile.md` is not used as a standalone definition, extension registry, second schema, or OKF override | MUST NOT | Profile Review | Contextual review of declaration content |

## Structure and navigation coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §3: a bundle contains no nested distribution unit | MUST NOT | Profile Review | Distribution intent and repository context distinguish an area from an independently distributed nested OKF bundle; a nested Profile declaration is only a deterministic signal |
| §3.1: project directories name a genuine shared subject and placement follows that subject | MUST | Profile Review | Directory contents support the path's subject claim; concepts are filed with that subject rather than by type |
| §3.1: a genuine project area may contain any number of concepts | MAY | Profile Review | No count-based concern; placement assessed on subject truth |
| §3.1: authors do not create speculative structure | SHOULD NOT | Profile Review | Current corpus and durable navigation need justify each directory |
| §3.1: every nonempty area contains `index.md` | MUST | Automated Profile Validation | Index presence in each nonempty area |
| §3.1: areas may nest, but only when the subject genuinely subdivides | MAY / SHOULD | Profile Review | Each nested segment adds a truthful, useful subject boundary |
| §3.1: a genuine subject concept is allowed; a generic concept must not duplicate the generated index | MAY / MUST NOT | Profile Review | Concept has specifically named durable knowledge rather than a second navigation artifact |
| §3.2–§3.4: `architecture/`, `ways-of-working/`, `interactions/`, and `references/` are optional and lazy, with their stated ordinary or special roles | MAY | Profile Review | Present fixed directories follow their subject-, time-, or source-axis role; absent names produce no finding |
| §3.3: Interaction Records may nest by cadence or interaction kind | MAY | Profile Review | Nested time-axis placement remains contextual and does not sort general knowledge by type |
| §3.4: nonempty `references/` and each nonempty descendant contain `index.md` | MUST | Automated Profile Validation | Index presence at every nonempty referenced-source level |
| §3.5: root contains `index.md`, `log.md`, `profile.md`, and `types.md` and reserves all five structural names | MUST / MUST NOT | Automated Profile Validation | Required paths present with no conflicting use |
| §3.5, §6.1.1: root `actors.md` exists when required by any used OKF actor-valued field, may otherwise be retained, has exact `type: Actor Registry`, and represents every used actor | MUST / MAY | Automated Profile Validation | Actor-field scan, conditional file presence, parsed exact registry type, and registry row membership |
| §6.1.1: actor and type registries use their fixed ordered table columns | MUST | Automated Profile Validation | Parsed header equality for six actor columns and two type columns |
| §9: every nonempty directory contains an index | MUST | Automated Profile Validation | Recursive directory and index inventory |
| §9: every index matches the exact immediate semantic projection and contains no unique authored navigation knowledge | MUST / MUST NOT | Automated Profile Validation | Parsed groups, membership, order, labels, relative targets, exact concept descriptions, directory entries, and referenced assets |
| §9: harmless Markdown presentation differences do not affect semantic conformance | MUST NOT | Automated Profile Validation | Equivalent parsed index fixtures yield the same result |
| §10: root log uses newest-first ISO date groups and each entry begins `* **<lead word>**:` | MUST | Automated Profile Validation | Parsed heading dates, descending order, and nonempty lead-word shape |
| §10: log lead words use the preferred vocabulary without closing it | SHOULD | Profile Review | Unfamiliar words are reviewed for clarity and never fail solely for being unfamiliar |
| §10: log records material knowledge lifecycle history and omits source-only, formatting-only, and unrelated events | MUST / MUST NOT | Profile Review | Context and, when useful, version history support authored significance and completeness |
| §13: indexes remain rebuildable projections and the authored log is not treated as one | MUST / MUST NOT | Profile Review | No index-only source of truth and no claim that current state mechanically reconstructs history |

## Concepts, trust, and durable-capture coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §4.1: a source event does not become a concept merely because it occurred; creation follows the durable-knowledge test | MUST NOT / MUST | Profile Review | Source context and retained outcome show an independently durable unit rather than ceremony capture |
| §4.2: embed or promote an outcome according to independent identity, lifecycle, provenance, relationships, reuse, replacement, and history | SHOULD | Profile Review | Concept boundary reflects the outcome's contextual reuse and lifecycle needs |
| §4.2.1: split parts needing materially different verification or lifecycle; do not split for size or heading count alone | SHOULD | Profile Review | Frontmatter scope remains truthful without averaging materially different trust or lifecycle state |
| §4.3: an Interaction Record is optional but prohibited without durable combined context, a single outcome links directly to its source, and routine minutes are prohibited | MAY / MUST NOT / SHOULD / MUST NOT | Profile Review | Interaction context justifies a combined record; routine source events do not create one |
| §5.1: every concept has nonempty `type`, `title`, `description`, and an allowed `status` | MUST | Automated Profile Validation | Parsed presence, scalar shape, nonempty values, and `draft` / `stable` / `deprecated` membership |
| §5.1: title, description, and lifecycle metadata are truthful | MUST | Profile Review | Values accurately identify, summarize, and describe the document lifecycle in context |
| §5.1: `generated` is recommended | SHOULD | Automated Profile Validation | Missing field produces a non-blocking advisory |
| §5.1, §6.2: generation provenance is never fabricated | MUST NOT | Profile Review | A present event represents known production and meaningful-change time rather than a conformance placeholder |
| §5.1: Concepta producers add no producer-defined frontmatter fields | MUST NOT | Automated Profile Validation | Parsed keys are defined by pinned OKF 0.2; unknown keys remain preserved and loadable and do not alter the OKF result |
| §5.1: tags do not exactly duplicate type, lifecycle, trust, or relationship labels | MUST NOT | Automated Profile Validation | Parsed tag values are compared with machine-readable values and the standard relationship vocabulary |
| §5.1: tags remain topics rather than semantic aliases for type, lifecycle, trust, or subject-resolution state | MUST NOT | Profile Review | Contextual meaning carries a topic rather than a second source of truth |
| §5.2: root `types.md` has exact `type: Type Registry` and contains all fourteen exact standard rows in canonical order, followed by project rows in lexical order | MUST / MAY | Automated Profile Validation | Parsed exact registry type, row values, and order match the release vocabulary and extension ordering |
| §5.2: every used type is registered; a registered project type is allowed with an advisory | MUST / MAY | Automated Profile Validation | Used-type membership; extension advisory does not affect the automated gate |
| §5.1, §5.2, §14.1: each standard or project-specific type and its registered meaning truthfully fit the concept | MUST | Profile Review | Concept content fits the selected kind and its registered meaning; review does not infer fit from headings, paths, or keywords |
| §5.2: a Business Rule selected by a Decision links to it with `Depends on` | SHOULD | Profile Review | Rule history and relationship meaning support the outward link when the rule records a chosen policy |
| §5.2: a project may use SBVR or another notation for Business Rule bodies | MAY | Profile Review | No notation is required or treated as changing the one-rule-per-concept type boundary |
| §6.1: materially derived claims record identifiable material with OKF `sources`; original work does not invent sources | MUST / MUST NOT | Profile Review | Claims and evidence show complete truthful material provenance or an original contribution |
| §6.1: present sources use required resources and unique IDs; recognized source-attribution footnotes join to those IDs | MUST | Automated Profile Validation | Source shape and ID uniqueness parse deterministically; only labels matching a declared source ID are attribution, so ordinary footnotes remain untouched |
| §6.1: producers do not add stored confidence, credibility, maturity, or evidence-tier fields | MUST NOT | Automated Profile Validation | Frontmatter-key inventory contains no producer-defined verdict field |
| §6.1.1: every actor `Side` belongs to the closed vocabulary and every `Active` value has valid syntax; dated rows for one ID do not overlap | MUST | Automated Profile Validation | Parsed side membership, range grammar, start-before-end, and interval overlap checks |
| §6.1.1: actor identity, affiliation, role, side, and active periods are truthful; unknown replaces unsupported inference | MUST | Profile Review | Evidence supports each registry cell and unresolved affiliation is recorded as `unknown` |
| §6.1.1: affiliation is absent from actor IDs and registry rows do not simulate graph edges | MUST NOT / SHOULD NOT | Profile Review | Stable opaque actor strings and ordinary lookup rows preserve OKF actor and graph contracts |
| §6.2: `verified` records only genuine confirmation and is never inferred from review, migration, status, or affiliation | MUST NOT | Profile Review | Verification evidence supports every event and actor; no event exists solely to satisfy policy |
| §6.2, §14.1: missing `verified` and derived trust tiers produce no finding | MUST NOT | Automated Profile Validation | Unverified fixtures emit neither failure nor advisory; optional trust summaries do not affect exit status |
| §6.3: `status` describes document lifecycle only and does not carry workflow, ownership, due date, movability, or subject certainty | MUST NOT | Profile Review | Contextual reading confirms the OKF lifecycle meaning and external ownership of execution state |
| §6.3.1: subject-settlement assessment stays in body prose and is not stored in frontmatter or derived from links | MUST NOT / MAY / SHOULD | Profile Review | Assessment appears beside reasoning when used; no stored or graph-derived verdict exists |
| §6.4: `stale_after` appears only for an evidenced freshness horizon and never as a type default or placeholder | MUST / MUST NOT | Profile Review | Evidence supports the absolute date and historical type alone neither requires nor prohibits it |

Profile §5.3 deliberately defines no type-specific body-template rule, so missing
skill-prompt headings receive no coverage row and no finding. Actor affiliation
lookup is likewise not an additional bundle requirement: implementations may expose
the row selected at an event time, but unresolved or ambiguous affiliation remains
`unknown` without a finding and never changes the OKF actor value or trust tier.

## Non-bundle frame clauses

These clauses constrain releases, migrations, or implementations rather than a
bundle at rest, so they do not receive a fabricated bundle assessment mode.

| Clause | Owner | Evidence |
| --- | --- | --- |
| Profile preamble: do not publish the integration draft before #19 verifies every release surface | Release integration | #19 publication review |
| §14.1: keep OKF conformance, Profile conformance, Automated Profile Validation, Profile Review, and Complete Profile Assessment distinct | Implementation guide | Guide §§4.1 and 4.5; validator contract tests in #26–#28 and #20 |
| §15.1: every normative Profile rule passes the five-part OKF compatibility test | Release integration | One reviewed row per rule in the compatibility review |
| §15.1: do not publish while compatibility or coverage evidence is incomplete | Release integration | #19 completeness review of both artifacts |
| §15.1: do not claim compatibility with an unreviewed OKF release | Release integration | Release binding and compatibility review identify the same pinned OKF release |
| §15.2: precedence and migration impact remain explicit for every release | Release integration | Profile binding and §15.3 migration text |
| §15.3: a 2026.1 bundle completes every published 2026.2 migration action before changing its declaration | Migration implementation | Whole-bundle migration review after publication |
| §6.1.1, §14.1: unresolved or ambiguous actor affiliation remains non-finding `unknown` | Validator implementation | Lookup tests preserve actor strings and trust tiers while emitting no finding for unresolved history |
| §5.1, §14.2: tolerant readers do not reject unknown frontmatter and preserve it on round-trip at OKF's exact force | Reader implementation | Unknown-key fixtures remain loadable (`MUST NOT` reject) and are retained under the upstream `SHOULD` |

Unsupported-release behavior and caller-policy prohibitions are implementation
rules owned by guide §§4.1, 4.2, and 4.4. They are tested by the validator
delivery slices and are not restated as Profile bundle clauses.

## Completion gate

This matrix is intentionally incomplete while the canonical Profile still
contains unaligned external-boundary text. Issue #25 MUST inventory and assign
every retained or introduced normative bundle clause in that scope; the
release-frame, structure, navigation, concept, trust, and durable-capture
inventories are recorded above.
Issue #19 MUST verify exact, duplicate-free coverage before publication. No
unlisted rule is implicitly covered.
