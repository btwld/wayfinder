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
| §3.5, §6.1.1: root `actors.md` exists when required by any used OKF actor-valued field, may otherwise be retained, and every used actor is represented | MUST / MAY | Automated Profile Validation | Actor-field scan, conditional file presence, and registry row membership |
| §6.1.1: actor and type registries use their fixed ordered table columns | MUST | Automated Profile Validation | Parsed header equality for six actor columns and two type columns |
| §9: every nonempty directory contains an index | MUST | Automated Profile Validation | Recursive directory and index inventory |
| §9: every index matches the exact immediate semantic projection and contains no unique authored navigation knowledge | MUST / MUST NOT | Automated Profile Validation | Parsed groups, membership, order, labels, relative targets, exact concept descriptions, directory entries, and referenced assets |
| §9: harmless Markdown presentation differences do not affect semantic conformance | MUST NOT | Automated Profile Validation | Equivalent parsed index fixtures yield the same result |
| §10: root log uses newest-first ISO date groups and each entry begins `* **<lead word>**:` | MUST | Automated Profile Validation | Parsed heading dates, descending order, and nonempty lead-word shape |
| §10: log lead words use the preferred vocabulary without closing it | SHOULD | Profile Review | Unfamiliar words are reviewed for clarity and never fail solely for being unfamiliar |
| §10: log records material knowledge lifecycle history and omits source-only, formatting-only, and unrelated events | MUST / MUST NOT | Profile Review | Context and, when useful, version history support authored significance and completeness |
| §13: indexes remain rebuildable projections and the authored log is not treated as one | MUST / MUST NOT | Profile Review | No index-only source of truth and no claim that current state mechanically reconstructs history |
| §13: graph consumers keep Markdown edges untyped and registry rows add no Profile-only nodes or edges | MUST / MUST NOT | Profile Review | Graph views preserve ordinary OKF links and do not reinterpret structural tables |
| §13: a graph is completely rebuildable from the bundle and carries no graph-only state | MUST / MUST NOT | Profile Review | Graph design and outputs identify the bundle artifacts from which every node, edge, and datum rebuilds |

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

Unsupported-release behavior and caller-policy prohibitions are implementation
rules owned by guide §§4.1, 4.2, and 4.4. They are tested by the validator
delivery slices and are not restated as Profile bundle clauses.

## Completion gate

This matrix is intentionally incomplete while the canonical Profile still
contains unaligned 2026.1 domain text. Issues #24 and #25 MUST inventory and
assign every retained or introduced normative bundle clause in their scope; the
structure and navigation inventory is recorded above.
Issue #19 MUST verify exact, duplicate-free coverage before publication. No
unlisted rule is implicitly covered.
