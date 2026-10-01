# Bitwild Profile 2026.3 implementation coverage

Status: Complete — Profile 2026.3 release evidence

The [2026.2 coverage matrix](profile-coverage-2026.2.md) is preserved for
legacy release dispatch.

This non-normative matrix assigns each normative Bitwild Profile 2026.3 bundle
rule to its assessment mode. It does not decide whether a rule preserves OKF;
that evidence lives in
[`../docs/compatibility-review.md`](../docs/compatibility-review.md).
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

## Inventory audit

The publication review normalized repeated statements of the same semantic rule
to one row and retained distinct deterministic and contextual obligations as
separate rules. The tables below assign every applicable bundle and release-frame rule. Every bundle row names exactly one assessment mode;
none is duplicated between Automated Profile Validation and Profile Review.

## Release-frame coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §11: exactly one project-root version-1 direct `source` + `applies_to` entry names the whole bundle; no `bundles`, `implements`, or `default_bundle` form | MUST / MUST NOT | Automated Profile Validation | Configuration shape and unique selected bundle path |
| §11: source manifest identity/release, base `bitwild_profile/2026.3`, and OKF 0.2 binding match exactly | MUST | Automated Profile Validation | Selected source chain, manifest parity, and root index `okf_version` |
| §11: `extends` is additive, reaches the base, and has no missing parent, cycle, collision, or ambiguous application | MAY / MUST / MUST NOT | Automated Profile Validation | Parent graph, effective registries, and unique whole-bundle selection |
| §11: `applies_to` paths stay relative, unique, inside the project after symlink resolution, and do not nest; independent bundles may share an entry | MUST / MAY | Automated Profile Validation | Normalized and canonical path checks |
| §11: configuration and resolution lock remain outside the bundle and its index | MUST NOT | Profile Review | Confirm project metadata lives beside, not inside, the selected bundle; an unrelated mirrored asset with the same basename is not configuration |
| §11: unknown IDs/releases and unresolved sources never silently fall back | MUST NOT | Automated Profile Validation | Unsupported result with independent OKF result retained |
| §11: a child does not replace Profile rules, load executable rules, or change OKF semantics | MUST NOT | Profile Review | Review manifest/entry vocabulary and authored usage for semantic overrides; validator accepts only declarative metadata |

## Structure and navigation coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §3: a bundle contains no nested distribution unit | MUST NOT | Profile Review | Distribution intent and repository context distinguish an area from an independently distributed nested OKF bundle |
| §3.1: project directories name a genuine shared subject and placement follows that subject | MUST | Profile Review | Directory contents support the path's subject claim; concepts are filed with that subject rather than by type |
| §3.1: a genuine project area may contain any number of concepts | MAY | Profile Review | No count-based concern; placement assessed on subject truth |
| §3.1: authors do not create speculative structure | SHOULD NOT | Profile Review | Current corpus and durable navigation need justify each directory |
| §3.1: every area contains its generated `index.md` | MUST | Automated Profile Validation | `index-current`: the area's generated index exists and matches |
| §3.1: areas may nest, but only when the subject genuinely subdivides | MAY / SHOULD | Profile Review | Each nested segment adds a truthful, useful subject boundary |
| §3.1: a genuine subject concept is allowed; a generic concept must not duplicate the generated index | MAY / MUST NOT | Profile Review | Concept has specifically named durable knowledge rather than a second navigation artifact |
| §3.2–§3.4: `architecture/`, `ways-of-working/`, `interactions/`, and `references/` are optional and lazy, with their stated ordinary or special roles | MAY | Profile Review | Present fixed directories follow their subject-, time-, or source-axis role; absent names produce no finding |
| §3.3: Interaction Records may nest by cadence or interaction kind | MAY | Profile Review | Nested time-axis placement remains contextual and does not sort general knowledge by type |
| §3.4: `references/` levels carry the generated indexes §9 requires; asset-only directories need none | MUST | Automated Profile Validation | `index-current` at every `references/` level the generator indexes |
| §3.4: within a `raw/` tier and its subdirectories the only markdown file is each directory's own `index.md`, and `raw` neither names a source directory nor sits directly under `references/` | MAY / MUST NOT | Automated Profile Validation | Non-index markdown under any `raw/` directory and a `raw/` directly under `references/` fail deterministically; declining the optional tier produces no finding |
| §3.4, §12: a `raw/` tier holds verbatim originals byte-for-byte, and the derived mirror sits beside `raw/` naming the original through `sources` | MUST | Profile Review | Whether tier contents are unmodified originals of cited sources needs source context no path rule can prove |
| §3.5: root contains `index.md` and `log.md`, not legacy registry/declaration concepts | MUST / MUST NOT | Automated Profile Validation | Root-file presence and absence of legacy names |
| §3.6: optional `computations/` contains only `Attested Computation` concepts and indexes; it may nest, and computations may instead live with their subject | MAY / MUST | Profile Review | Every concept under `computations/` is an Attested Computation; consumers stay with their subjects and link to it |
| §3.6: every directory under `computations/` contains its generated `index.md` | MUST | Automated Profile Validation | `index-current`, as for areas |
| §6.1.1: every used actor appears in the selected binding lookup | MUST | Automated Profile Validation | Actor-field scan and ID membership |
| §5.2, §6.1.1: binding definitions have required names, descriptions, and permitted actor-side values | MUST | Automated Profile Validation | JSON shape and value checks |
| §9: every `index.md` the pinned okf reference generator writes exists with exactly the generated text, the root declaring `okf_version: "0.2"` | MUST | Automated Profile Validation | `index-current` regenerates with `OkfIndexGenerator` and reports each missing or differing path; `validate --fix` writes them |
| §9: a bundle with no concepts has a root index declaring `okf_version: "0.2"` and listing only `log.md` | MUST | Profile Review | The generator writes no root index for such a bundle, so `index-current` does not check it; `okf-release-binding` still checks the marker |
| §9: a directory the generator does not index, such as an asset-only `raw/` tier, carries no `index.md` | MUST NOT | Automated Profile Validation | `index-current` reports every `index.md` the generator does not write, except the root of a bundle with no concepts |
| §10: root log uses newest-first ISO date groups and each entry begins `* **<lead word>**:` | MUST | Automated Profile Validation | Nonempty lead-word shape is a deterministic Profile finding; heading-date validity and descending order are diagnostics of the independent OKF check within the same `okfp validate` invocation |
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
| §5.1: Bitwild producers add no producer-defined frontmatter fields | MUST NOT | Automated Profile Validation | Parsed keys are defined by pinned OKF 0.2; unknown keys remain preserved and loadable and do not alter the OKF result |
| §5.1: tags do not exactly duplicate type, lifecycle, trust, or relationship labels | MUST NOT | Automated Profile Validation | Parsed tag values are compared with machine-readable values and the standard relationship vocabulary |
| §5.1: used tags are declared once in the merged manifest/binding registry and not repeated within a concept | MUST / MUST NOT | Automated Profile Validation | Registry membership, collisions, and per-concept duplicate checks |
| §5.1: tags remain topics rather than semantic aliases for type, lifecycle, trust, or subject-resolution state | MUST NOT | Profile Review | Contextual meaning carries a topic rather than a second source of truth |
| §5.2: the base manifest has twelve standard types, including Attested Computation, and the binding adds unique, noncolliding custom types | MUST / MAY | Automated Profile Validation | Manifest parity, custom-definition shape, duplicate and collision checks |
| §5.2: every used type is registered; a registered project type is allowed with an advisory | MUST / MAY | Automated Profile Validation | Used-type membership; extension advisory does not affect the automated gate |
| §5.1, §5.2, §14.1: each standard or project-specific type and its registered meaning truthfully fit the concept | MUST | Profile Review | Concept content fits the selected kind and its registered meaning; review does not infer fit from headings, paths, or keywords |
| §5.2: a Business Rule selected by a Decision links to it with `Depends on` | SHOULD | Profile Review | Rule history and relationship meaning support the outward link when the rule records a chosen policy |
| §5.2: a project may use SBVR or another notation for Business Rule bodies | MAY | Profile Review | No notation is required or treated as changing the one-rule-per-concept type boundary |
| §6.1: materially derived claims record identifiable material with OKF `sources`; original work does not invent sources | MUST / MUST NOT | Profile Review | Claims and evidence show complete truthful material provenance or an original contribution |
| §6.1: present sources use required resources and unique IDs; recognized source-attribution footnotes join to those IDs | MUST | Automated Profile Validation | Source shape and ID uniqueness parse deterministically; only labels matching a declared source ID are attribution, so ordinary footnotes remain untouched |
| §6.1 (OKF §5.1): a path-shaped `resource` or `sources[].resource` names an artifact a consumer can follow | SHOULD | Automated Profile Validation | Bundle-relative and relative paths are resolved against the bundle root and the concept's directory, including paths that leave the bundle; a path naming no file or directory produces a non-blocking advisory, while URLs and scope descriptors produce no finding |
| §6.1: producers do not add stored confidence, credibility, maturity, or evidence-tier fields | MUST NOT | Automated Profile Validation | Frontmatter-key inventory contains no producer-defined verdict field |
| §6.1.1: optional actor `side` uses its closed vocabulary | MUST | Automated Profile Validation | Side enum check |
| §6.1.1: actor identity and optional affiliation, role, and side are truthful | MUST | Profile Review | Evidence supports lookup metadata; unknown is used for uncertain affiliation |
| §6.1.1: actor IDs remain opaque and lookup does not change OKF trust or graph edges | MUST NOT | Profile Review | Identity and graph semantics remain upstream |
| §6.2: `verified` records only genuine confirmation and is never inferred from review, migration, status, or affiliation | MUST NOT | Profile Review | Verification evidence supports every event and actor; no event exists solely to satisfy policy |
| §6.2, §14.1: missing `verified` and derived trust tiers produce no finding | MUST NOT | Automated Profile Validation | Unverified fixtures emit neither failure nor advisory; optional trust summaries do not affect exit status |
| §6.3: `status` describes document lifecycle only and does not carry workflow, ownership, due date, movability, or subject certainty | MUST NOT | Profile Review | Contextual reading confirms the OKF lifecycle meaning and external ownership of execution state |
| §6.3.1: subject-settlement assessment stays in body prose and is not stored in frontmatter or derived from links | MUST NOT / MAY / SHOULD | Profile Review | Assessment appears beside reasoning when used; no stored or graph-derived verdict exists |
| §6.4: `stale_after` appears only for an evidenced freshness horizon and never as a type default or placeholder | MUST / MUST NOT | Profile Review | Evidence supports the absolute instant and historical type alone neither requires nor prohibits it |
| §6.5: every timestamp-valued key is an ISO 8601 datetime with an explicit UTC offset, and no date-only or offset-less value is written | MUST NOT | Automated Profile Validation | The `okf` package reports each offending field as the non-blocking `okf/timestamp-without-offset` advisory naming the exact key; `okf validate --strict` escalates it |
| §14.1: a concept beside an area of the same name produces only a non-blocking advisory | MUST NOT | Automated Profile Validation | Same-name root or sibling fixture emits an advisory without changing Profile conformance, automated gate, or exit status |

Profile §5.3 deliberately defines no type-specific body-template rule, so missing
skill-prompt headings receive no coverage row and no finding. Actor lookup is
assessed as specified above; it does not change OKF actor semantics.

## Relationships and external-boundary coverage

| Profile clause | Force | Assessment | Expected evidence |
| --- | --- | --- | --- |
| §7.1: bundle-relative internal links are preferred | SHOULD | Automated Profile Validation | Non-bundle-relative internal targets produce a non-blocking advisory; either form remains an ordinary OKF link |
| §7.1, §14.1–§14.2: unresolved internal links are permitted and produce only a non-blocking advisory | MAY / MUST NOT | Automated Profile Validation | Missing-target fixture leaves both conformance results unchanged and emits an advisory with no exit effect |
| §7.2: a concept may carry an optional Relationships section, each entry has exactly one label and one target, and no relationship schema appears in producer-defined frontmatter | MAY / MUST / MUST NOT | Automated Profile Validation | Parsed section accepts absence and checks one label plus one Markdown target per bullet; frontmatter inventory rejects producer-defined relationship fields without changing OKF tolerance |
| §7.2: preferred labels retain their outward meanings; additional labels are permitted, advised, and defined once in a durable Guide | MAY / SHOULD | Profile Review | Context supports label semantics and a project label has one durable definition; deterministic output only notes the extension |
| §7.3: tracker-owned execution records remain external, their state is not copied, and every durable specification has one lifecycle owner | MUST / MUST NOT | Profile Review | Tracker and bundle inspection shows one authoritative artifact and links rather than mirrored workflow state |
| §7.3: one concept may accumulate several execution records or none | MAY | Profile Review | No cardinality finding; contextual traceability distinguishes independent work records from copied state |
| §8.1: authored path slugs use readable lowercase kebab-case, paths exclude mutable metadata, dates appear only for intrinsic chronology, and externally cited IDs are preserved verbatim | MUST / MUST NOT | Profile Review | Subject history and external references identify the slug/ID boundary and justify the path; creation time, freshness, workflow, editable versions, mutable metadata, and renumbering are rejected contextually |
| §8.2: a concept may move at any status; a repairable move coordinates known inbound links, affected indexes, and authored history; an unrepairable known external citation freezes the path | MAY / MUST / MUST NOT / SHOULD | Profile Review | Move review inspects status independence, known citations, and the coordinated update; an execution relationship prompts review but is not itself a finding |
| §8.3: stable concepts normally deprecate and link an available successor; drafts may be deleted; exceptional stable hard deletion is narrowly justified and reviewed | SHOULD / MUST / MAY / MUST | Profile Review | Lifecycle history, successor availability, deletion reason, and treatment of known citations support the retirement choice |
| §12: mirrored external material enters only through `references/` | MUST | Profile Review | Source context distinguishes a mirror from authored context and confirms its placement without inferring from path alone |
| §12: Markdown identified as a mirror has baseline metadata and original-source provenance | MUST | Profile Review | Review identifies the mirror and confirms present original-source provenance; the general §5.1 baseline and §6.1 source-shape checks apply deterministically to the authored concept, but no automated rule identifies a mirror or requires a source entry to exist |
| §12: mirrored Markdown remains immutable once cited | MUST | Profile Review | Authored history and citing concepts establish the snapshot boundary and whether later edits altered source content |
| §12: mirroring is pull-based on a durable citation, genuine availability risk, and suitable repository visibility | MUST / MAY / MUST NOT | Profile Review | Source context supports preservation need and access; occurrence alone never triggers capture |
| §12: text and cited images may be mirrored, with confidentiality sanitization and image optimization | MAY / MUST | Profile Review | Review confirms that retained content and image representation are suitable without inventing a generic size threshold |
| §12: video, audio, and other heavy binaries remain external; an appropriate transcript is preferred when their content must survive | MUST NOT / SHOULD | Profile Review | Repository context and artifact characteristics identify impractical media and a suitable preservation form without inventing an extension, MIME, signature, or byte threshold |
| §12: curated external-system context may remain an ordinary resource-bound concept; a non-mirrored source retains a followable OKF resource when known, uses a scope descriptor only when inherently unfollowable, and records a material preservation reason | MAY / MUST / MUST NOT / SHOULD | Profile Review | Source representation preserves upstream semantics and body context explains a durable preservation choice when useful |
| §14.2: external resource availability never becomes a conformance gate | MUST NOT | Automated Profile Validation | Validation performs no network probe and a dead external URL creates no finding |

## Non-bundle frame clauses

These clauses constrain releases, migrations, or implementations rather than a
bundle at rest, so they do not receive a fabricated bundle assessment mode.

| Clause | Owner | Evidence |
| --- | --- | --- |
| §14.1: keep OKF conformance, Profile conformance, Automated Profile Validation, Profile Review, and Complete Profile Assessment distinct | Implementation guide | Guide §§4.1 and 4.5; validator contract tests in #26–#28 and #20 |
| §15.1: every normative Profile rule passes the five-part OKF compatibility test | Release integration | One reviewed row per rule in the compatibility review |
| §15.1: do not publish while compatibility or coverage evidence is incomplete | Release integration | #19 completeness review of both artifacts |
| §15.1: do not claim compatibility with an unreviewed OKF release | Release integration | Release binding and compatibility review identify the same pinned OKF release |
| §15.2: precedence and migration impact remain explicit for every release | Release integration | Profile binding and §15.3 migration text |
| §6.1.1, §14.1: an implementation using binding actor lookup preserves actor strings and OKF-derived trust; historical affiliation is not inferred from a static entry | Consumer implementation | Validator checks ID membership; contextual review does not invent time-dependent affiliation from a static lookup |
| §5.1, §14.2: tolerant readers do not reject unknown frontmatter and preserve it on round-trip at OKF's exact force | Reader implementation | Unknown-key fixtures remain loadable (`MUST NOT` reject) and are retained under the upstream `SHOULD` |
| §7.1–§7.2, §13, §14.2: tolerant readers preserve unknown relationship labels, unresolved targets, and ordinary untyped graph edges | Reader implementation | Unknown-label and unresolved-target fixtures remain loadable and expose the unchanged OKF edge through the public OKF graph |
| §8.2: tooling checks known inbound bundle links during coordinated moves without making unresolved edges blocking | Authoring and validator implementation | Move workflow repairs discovered references; final validation retains any unresolved edge as a non-blocking advisory |
| §1.3: authors defer to pinned OKF when the Profile is silent and do not invent Bitwild conventions | Authoring implementation | Canonical Profile skill delegates the question to vendored OKF 0.2 and treats upstream-permitted content as available |
| §14.2: consumers keep any other OKF 0.2 mechanism the Profile does not describe loadable and finding-free | Reader and validator implementation | Silent-mechanism fixtures retain upstream meaning and produce no Profile finding |

Unsupported-release behavior and caller-policy prohibitions are implementation
rules owned by guide §§4.1, 4.2, and 4.4. They are tested by the validator
delivery slices and are not restated as Profile bundle clauses.

## OKF co-reporting

okf 0.2.0 checks some territory the Profile also rules on, always at advisory
severity in the independent OKF report: `okf/unsupported-okf-version` (root
index `okf_version`) under the Profile's error-level
`concepta-profile/okf-release-binding` in legacy 2026.2, and `okf/non-portable-index-link`
on an index §9 also requires to match generated output. The audit of the 0.1.2 → 0.2.0 severity re-tiering
found no rule crossing the blocking boundary — every 0.1.2 `error` remains an
`error`, every `warning` became a non-gating `advisory` — so no assignment in
this matrix moved. Duplicate reporting is deliberate and stays: the OKF
report is preserved unreclassified (ADR-0004, ADR-0008), the Profile keeps
its own stricter rule, and neither layer filters the other's findings. An OKF
advisory never changes OKF conformance, the automated gate, or the exit
status; the `okf-advisory` fixture pins this.

## Completion gate

This matrix inventories the release frame, structure, navigation, concept,
trust, durable capture, relationship, identity, execution, lifecycle, mirroring,
tolerant-reading, and release-governance clauses. Publication review found no
duplicate assignment and no unassessed rule; no unlisted rule is implicitly
covered.
