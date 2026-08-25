# Concepta Profile 2026.1 compatibility with OKF 0.2

Status: Complete — Profile 2026.1 release evidence

This non-normative review records whether each normative Concepta Profile
2026.1 rule preserves the pinned OKF 0.2 contract. It is specification-safety
evidence, not implementation coverage and not a second source of Profile rules.
The Profile remains authoritative over every summary here.

## Compatibility test

A rule passes only when all five answers are yes:

1. Does it use only constructs OKF 0.2 permits?
2. Does it preserve every OKF field and reserved file's upstream meaning?
3. Does it leave OKF's untyped graph contract uninterpreted?
4. Does it leave the independent OKF conformance result unchanged?
5. Can a generic OKF consumer read the bundle normally?

A rule that needs a new field or new upstream meaning fails this test and cannot
ship in the Profile. It must be removed or pursued upstream first.

## Inventory audit

The publication review traced every normative clause in the canonical Profile
through this artifact and the separate coverage matrix. This review has 61
compatibility records: a record may group adjacent clauses only when they use the
same OKF construct and all five answers are identical. The coverage matrix keeps
assessment assignments separate and exactly once. No compatibility record is
implicit, unassessed, or inherited merely by silence.

## Release-frame review

| Profile rule | OKF basis | Compatibility result | Reasoning |
| --- | --- | --- | --- |
| §11 requires `profile.md` as an ordinary `Knowledge Profile` concept | §3.1 makes every non-reserved Markdown file a concept; §4 requires only `type` | Pass | The declaration uses ordinary concept frontmatter and keeps its selector in body Markdown, adding no field or reserved filename. |
| §11 binds `concepta_profile: "2026.1"` to `okf_version: "0.2"` and requires agreement with the root index | §12 permits `okf_version` in root index frontmatter; §4.2 leaves body Markdown free-form | Pass | The Profile narrows a producer choice and cross-checks two ordinary representations without changing either value's OKF meaning. |
| §11 prohibits treating the declaration as a rule-definition, extension registry, second schema, or OKF override | §4.1 permits producer extensions but does not assign Profile semantics to them | Pass | The prohibition prevents a Concepta mechanism from redefining OKF or changing the selected release; generic consumers still see an ordinary concept. |
| §14.1 defines Profile conformance separately from OKF conformance | §11 exclusively defines OKF conformance and tolerant rejection behavior | Pass | Profile conformance adds a producer policy result without changing the upstream conditions or generic-consumer verdict. |
| §14.1 distinguishes Automated Profile Validation, Profile Review, and Complete Profile Assessment | No OKF implementation mechanism is changed | Pass | These terms divide Concepta assessment responsibilities; the implementation guide preserves and exposes the independent OKF result. |
| §15.1 requires every Profile rule to pass this compatibility test | Whole specification, especially §§3.1, 4, 6, 8, 9, and 11 | Pass | This is a release-governance constraint that prevents incompatible rules; it adds no bundle representation. |
| §1.3 requires authors to defer to pinned OKF where the Profile is silent and prohibits inventing a Concepta convention | Whole specification | Pass | The rule directs producers to upstream meaning and prevents a competing local format; it adds no bundle construct. |
| §14.2 preserves tolerant reading for unknown fields, types, actors, labels, optional content, broken links, and silent OKF mechanisms | §§4.1 and 11 require tolerant reading and preserve unknown extensions | Pass | Profile producer failures remain separate from the independent OKF result, and consumers retain upstream loadability and preservation force. |
| §15.1 requires an exact reviewed OKF binding and prohibits claims against an unreviewed upstream release | §12 versions OKF independently | Pass | Release governance makes the compatibility claim narrower and reproducible without changing bundle version semantics. |
| §15.2 keeps Profile and OKF versions distinct and requires explicit migration impact | §12 owns only OKF versioning | Pass | The Profile's separate release identifier and migration prose do not reinterpret `okf_version`. |

## Structure and navigation review

| Profile rule | OKF basis | Compatibility result | Reasoning |
| --- | --- | --- | --- |
| §3 requires directories to organize concepts rather than nested distribution units | §3 defines one directory tree as a bundle | Pass | This narrows producer organization without changing any file or concept meaning. |
| §3.1 requires project directories to name shared subjects, permits any genuine area size, and discourages speculative structure | §3 lets producers organize concepts however makes sense | Pass | Subject placement and contextual restraint select among permitted paths; generic consumers continue to see an ordinary directory tree. |
| §3.1 permits nested subject areas and ordinary subject concepts but prohibits a concept that merely duplicates generated navigation | §3 permits nested directories; §4.2 permits free-form concept bodies; §8 defines indexes | Pass | The rules constrain producer boundaries without reserving another filename or changing the distinction between concepts and indexes. |
| §3.2 defines optional lazy `architecture/` and `ways-of-working/` as ordinary subject areas | §3 permits producer-chosen directory names | Pass | The names select two optional organization choices and carry no OKF semantics for generic readers. |
| §3.3 defines optional lazy `interactions/` as a time-axis exception | §3 permits domain-independent organization; §6 permits ordinary links | Pass | Interaction Records remain ordinary concepts and the exception changes neither their type meaning nor graph edges. |
| §3.4 defines optional lazy `references/`, including nesting and per-directory indexes | §6.3 already defines the `references/` convention; §8 permits indexes at every level | Pass | The Profile narrows use of the upstream convention without redefining mirrored concepts or path-valued fields. |
| §3.4 permits a per-source `raw/` tier whose only markdown is each directory's `index.md`, reserves the name within `references/`, and keeps derived mirrors outside it | §3.1 leaves subdirectory organization to producers and makes only markdown files concepts; §8 permits indexes at every level | Pass | The rule narrows directory organization and markdown placement OKF leaves free; assets stay non-concepts, every index keeps its upstream meaning, and the independent OKF verdict is unchanged. |
| §3.5 requires root `index.md`, `log.md`, `profile.md`, and `types.md`, with `actors.md` conditional on actor-valued fields | §3.1 reserves `index.md` and `log.md`; every other Markdown file is an ordinary concept | Pass | Required presence is a producer constraint; the reserved files retain their upstream meanings and both registries remain ordinary concepts. |
| §6.1.1 requires every used actor in root `actors.md` and fixes its six-column table; root `types.md` uses its fixed two-column table | §4.2 leaves body Markdown free-form; §7 keeps actor IDs as strings | Pass | Body tables add lookup structure without changing actor strings, trust tiers, frontmatter, or graph meaning; missing rows affect only the Profile result. |
| §9 requires `index.md` in every nonempty directory | §8 makes indexes optional for OKF and §11 forbids base rejection when absent | Pass | This is an additional Profile producer requirement; a missing index never changes the independent OKF result. |
| §9 defines exact immediate membership and fixed `Bundle`, type, `Directories`, and `Assets` groups | §8 permits one or more grouped sections and directory entries | Pass | Every projected item is represented with the existing OKF index syntax; non-Markdown assets remain files rather than concepts. |
| §9 derives group and entry order, labels, relative targets, and descriptions and omits empty groups | §8 permits generated indexes and recommends concept descriptions | Pass | Tightening producer output to deterministic values changes no upstream field or index-entry meaning. |
| §9 treats semantic equivalence rather than Markdown presentation as conformance | §8 specifies structural Markdown rather than canonical bytes | Pass | Parsed comparison preserves the upstream format and avoids inventing a stricter presentation language. |
| §10 requires the root log, OKF date ordering, and a nonempty bold lead word followed by a colon while keeping the vocabulary extensible | §9 defines newest-first ISO date groups and conventional bold lead words | Pass | The Profile requires a shape OKF already permits and does not close or reinterpret the upstream lead-word convention. |
| §10 limits log entries to knowledge lifecycle history and prohibits unrelated events; §13 excludes the authored log from projections | §9 defines logs as history, not as generated state | Pass | Authorship and content selection narrow producer practice without changing reserved-file syntax or claiming that current concepts can reconstruct history. |

## Concepts, trust, and durable-capture review

| Profile rule | OKF basis | Compatibility result | Reasoning |
| --- | --- | --- | --- |
| §4.1 prohibits creating concepts from source events merely because they occurred and requires the durable-knowledge judgment | §2 defines a concept as a unit of knowledge; §4.2 leaves bodies free-form | Pass | The rule narrows what Concepta producers retain without changing the representation or preventing source-event artifacts from being cited or mirrored under §12. |
| §4.2 recommends promotion when an outcome needs independent identity and §4.2.1 recommends splitting for materially different verification or lifecycle | §2 makes each Markdown document one concept; §5 assigns metadata at concept scope | Pass | The boundary guidance selects among ordinary OKF concepts and preserves per-claim source attribution rather than inventing finer-grained fields. |
| §4.3 permits Interaction Records only for durable combined context and prohibits routine minutes | §4.1 leaves type vocabulary to producers | Pass | `Interaction Record` remains an ordinary producer-defined type; the Profile narrows when Concepta creates one without changing OKF type semantics. |
| §5.1 requires nonempty, truthful `type`, `title`, `description`, and `status` with their OKF meanings | §4.1 defines all four fields and §5.4 defines `status` values and its absent default | Pass | Requiring accurate use of recommended or optional upstream fields is a producer narrowing; generic consumers read the same fields and the independent OKF result remains unchanged. |
| §5.1 recommends `generated`, prohibits fabricating it, and prohibits producer-defined frontmatter while retaining tolerant reading | §4.1 permits producer extensions, prohibits rejection, and recommends preserving unknown keys on round-trip; §5.2 defines `generated` | Pass | Concepta may restrict its own output while consumers keep OKF's exact `MUST NOT` rejection and `SHOULD` preservation force; missing generation remains valid OKF and Profile-conformant. |
| §5.1 restricts tags to topics and prohibits duplicating type, lifecycle, trust, or subject-resolution state | §4.1 defines tags as cross-cutting categorization and assigns the other fields their own meanings | Pass | The rule keeps one source of truth for upstream signals and narrows tag content without changing how generic consumers parse tags. |
| §5.2 requires root `types.md` to be an ordinary `Type Registry` concept and §6.1.1 requires present root `actors.md` to be an ordinary `Actor Registry` concept | §3.1 makes every non-reserved Markdown file a concept; §4.1 requires only a nonempty open-vocabulary `type` | Pass | Both identities use ordinary producer type values and add no reserved filename, field meaning, or basis for generic-consumer rejection. |
| §5.2 requires all fourteen standard registry rows in canonical order, registration of every used type, and lexical project extensions | §4.1 leaves types decentralized and requires consumers to tolerate unknown values; §4.2 permits body tables | Pass | The registry is producer-side body Markdown. Missing or extended rows affect only the Profile result and never license rejection by an OKF consumer. |
| §5.1, §5.2, and §14.1 permit registered project types with an advisory and require every standard or project-specific type and its registered meaning to fit the concept | §4.1 recommends descriptive type values and tolerates unknown types | Pass | Contextual type selection narrows Concepta authoring while preserving OKF's open vocabulary and tolerant consumption. |
| §5.2 recommends linking a Business Rule to the Decision that selected it | §4.2 and §6.1 permit ordinary Markdown links between concepts | Pass | `Depends on` remains readable relationship prose around an ordinary untyped OKF edge. |
| §5.2 permits SBVR or another notation within Business Rule bodies | §4.2 leaves bodies free-form and §4.1 leaves domain schemas out of scope | Pass | The notation changes no frontmatter, type, or graph meaning and remains ordinary body content. |
| §5.3 defines no body template and leaves missing headings outside conformance | §4.2 makes concept bodies free-form with only upstream conventional headings | Pass | Moving templates to authoring guidance removes a Profile body narrowing; the optional Relationships convention remains ordinary Markdown. |
| §6.1 requires `sources` for materially derived claims, prohibits invented sources and stored credibility verdicts, and checks unique IDs and recognized attribution joins | §5.1 defines sources, scope descriptors, footnote joins, and objective credibility signals while rejecting stored scores | Pass | The rule selects the upstream provenance mechanism only when material derivation exists. A footnote is recognized as attribution only by matching a source ID, so ordinary Markdown footnotes remain free-form body content. |
| §6.1.1 closes `Side`, requires unknown affiliation when evidence is absent, and records non-overlapping active periods | §4.2 permits body tables; §7 leaves actor IDs as strings | Pass | Organizational lookup data stays in ordinary body Markdown and neither changes actor syntax nor adds an OKF trust input. |
| §6.1.1 resolves actor rows at event time and leaves ambiguous affiliation unknown | §5.1–§5.2 supply event timestamps and optional source modification dates; §5.3 derives trust only from actor prefixes | Pass | Historical lookup is a Profile projection over permitted values; it never rewrites the actor string, rejects the OKF value, or alters prefix-derived trust. |
| §6.2 prohibits invented `generated` and `verified` events and makes missing verification produce no finding | §5.2 defines the two events; §5.3 makes no verification the unverified tier and §11 forbids rejection for missing optional trust fields | Pass | The rule protects truthful absence and reinforces rather than narrows OKF's trust model. |
| §6.3 confines `status` to document lifecycle and prohibits workflow or subject-settlement meanings | §5.4 defines status solely as draft, stable, or deprecated document lifecycle | Pass | The Profile preserves the upstream field meaning and routes other state to body prose or external trackers. |
| §6.3.1 keeps subject-settlement assessment in body prose and prohibits deriving it from frontmatter or links | §4.2 leaves body prose free; §6.1 makes links untyped and §11 tolerates unresolved links | Pass | The rule avoids a new field or graph meaning and keeps contextual judgment beside its evidence. |
| §6.4 permits `stale_after` only for an evidenced freshness horizon and prohibits type defaults or placeholders | §5.5 defines an optional absolute staleness date | Pass | The Profile narrows when producers use the existing field without changing its date semantics or requiring it for any type. |
| §14.1 makes a concept beside an area of the same name a non-blocking advisory | §3 permits both root concepts and subdirectories and §11 does not reject either arrangement | Pass | The advisory calls for contextual placement review without changing either conformance result or prohibiting an OKF-permitted tree. |

## Relationships and external-boundary review

| Profile rule | OKF basis | Compatibility result | Reasoning |
| --- | --- | --- | --- |
| §7.1 prefers bundle-relative internal links | §6.1 supports both bundle-relative and relative links and recommends the former | Pass | The Profile repeats the upstream preference without prohibiting either representation or changing resolution. |
| §7.1 keeps unresolved internal links loadable and non-blocking while permitting a contextual advisory | §6.1 says a broken target is not malformed and §11 forbids rejecting a bundle for broken cross-links | Pass | The advisory preserves the ordinary edge and never changes either the OKF or Profile conformance result. |
| §7.2 requires one label and one target in each optional Relationships entry, prefers an extensible vocabulary, permits documented project labels with an advisory, and prohibits relationship frontmatter | §4.2 leaves bodies free-form and §6.1 reads relationship kind from surrounding prose | Pass | Labels remain body prose around one ordinary Markdown link; no frontmatter schema, closed consumer vocabulary, or typed graph is introduced. |
| §7.3 keeps tracker-owned execution records external and gives every durable specification exactly one lifecycle owner | §3 permits a bundle as a subdirectory and §4.2 permits external links | Pass | The rule constrains Concepta storage ownership while a generic consumer sees ordinary concepts and external Markdown links; tracker state does not redefine OKF `status`. |
| §7.3 permits one concept to link several execution records or none | §4.2 and §6.1 permit any number of ordinary Markdown links | Pass | The permission adds no cardinality or required edge to the OKF graph. |
| §8.1 requires readable lowercase-kebab authored slugs, excludes mutable metadata, preserves cited IDs, and permits dates only for intrinsic chronology | §2 defines concept ID as the path and §3 leaves producer organization open | Pass | These are producer-side path choices. They neither change how a generic consumer derives an ID nor introduce an identifier field. |
| §8.2 permits a move at any status, coordinates known internal links, indexes, and authored history, and freezes a path only for an unrepairable known external citation | §5.4 defines status independently of path and §6.1 tolerates unresolved links; §§8–9 define indexes and logs | Pass | Coordinated repair narrows authoring without treating lifecycle as identity or unresolved links as malformed; the freeze preserves outside citations. |
| §8.3 normally deprecates stable concepts, requires an available successor link, permits draft deletion, and permits exceptional reviewable stable deletion | §5.4 defines `deprecated` as kept for links and history; §6.1 permits the successor link | Pass | The normal path uses the upstream lifecycle value and an ordinary link. Deletion is repository history policy, not a new OKF status. |
| §12 permits external material to enter only through `references/` and makes mirroring pull-based on citation, genuine availability risk, and suitable visibility | §6.3 defines `references/` as the conventional mirror location and §5.1 defines source citation | Pass | The rule narrows when and where Concepta copies a source without making the optional upstream directory required for bundles with no mirror. |
| §12 requires mirrored Markdown to retain the Profile baseline, original-source provenance, and snapshot immutability once cited | §§4–5 define ordinary concept metadata and sources | Pass | A mirror remains an ordinary concept using upstream fields; immutability constrains producer updates without changing those fields or generic reading. |
| §12 keeps non-Markdown referenced assets as files rather than concepts | §3.1 defines non-reserved Markdown as concepts and §6.3 permits referenced code and material | Pass | The boundary adds no frontmatter to assets and does not make them graph nodes. |
| §12 permits text and cited images with required sanitization and optimization | §6.3 permits mirrored material and §4.2 leaves source bodies free-form | Pass | Access and repository-weight constraints select producer behavior without adding sensitivity or optimization metadata to OKF. |
| §12 keeps video, audio, and other heavy binaries external and prefers a transcript when preservation is needed | §5.1 permits external resources and §6.3 makes mirroring optional | Pass | The bundle continues to cite external media normally; an optional transcript is an ordinary mirrored source concept, not a replacement graph or provenance mechanism. |
| §12 permits curated external-system context as an ordinary resource-bound concept and requires non-mirrored sources to retain a known followable resource, limits scope descriptors to inherently unfollowable sources, and recommends recording material reasons | §§4.1 and 5.1 define concept resources, concrete source resources, and population or scope descriptors | Pass | The rules preserve upstream distinctions and keep preservation reasoning in free-form body prose rather than weakening provenance or adding metadata. |
| §14.2 keeps external-resource availability outside conformance | §11 does not make network resolution a rejection condition | Pass | A dead external resource remains ordinary body or provenance content and changes neither independent OKF nor Profile conformance. |
| §14.1 assigns relationship shape to deterministic validation, relationship and unresolved-link extensions to non-blocking advice, and contextual external-boundary meaning to Profile Review | §11 fixes only OKF rejection conditions | Pass | Assessment assignment changes no bundle construct or OKF result and explicitly prevents contextual inference from being presented as deterministic graph or source truth. |

## Completion gate

This review records the release frame, structure, navigation, concept, trust,
durable capture, relationship, identity, execution, lifecycle, mirroring,
tolerant-reading, and release-governance inventories. Every record passes the
five-part test; no omitted rule passes by silence.
