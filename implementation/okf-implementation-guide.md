# Concepta OKF Profile — Implementation Guide

**Version 2026.2** — binds **Concepta OKF Profile 2026.2**, which profiles
**OKF 0.2 exactly**

Status: Proposed

---

## 1. Purpose and precedence

The profile specifies **what a bundle is**. This document specifies **how one is built,
checked, and kept**: what a repository does to adopt the profile, what the tools must do,
and how an existing document tree becomes a bundle.

Precedence is a chain, and every link is one-directional:

> **OKF** wins over the **profile**, which wins over this **guide**.

This document therefore MUST NOT restate, extend, or narrow a profile rule. Where it
appears to, the profile governs and this text is defective. What it may do is bind
behaviour the profile deliberately leaves open — for example, the Profile defines
the semantic index result while this guide requires a generator to be idempotent
and choose a deterministic Markdown rendering.

**"Guide" does not mean advisory.** The requirements below are normative and carry their
RFC 2119 force; what distinguishes this document from the profile is not strictness but
*what conforms to it*. The profile is normative on **bundles** — a bundle either conforms
or it does not. This guide is normative on **implementations**: tools, adoptions, and
migrations. "A generator MUST be idempotent" constrains a program, never a bundle, which is
why it could not have been written in the profile.

Its audience differs for the same reason. The profile is read by anyone writing a concept.
This is read by whoever stands up a repository, writes a tool, or runs a migration — a
handful of people per project, once.

**Conventions.** MUST, MUST NOT, SHOULD, and MAY carry their RFC 2119 senses. "Tool" means
any program that reads or writes a bundle. "Bundle" always means the one at `knowledge/`.

---

## 2. Adoption

### 2.1 What a repository does

Adoption is four required files, one conditional file, and one paragraph, in this
order:

1. **Seed the required root.** `index.md`, `log.md`, `profile.md`, and `types.md`,
   exactly as the profile's §3.5 defines them. The skill's `SEEDING.md` carries the
   literal text.
2. **Declare the versions.** `profile.md`'s first fenced `yaml` block carries
   `concepta_profile` and `okf_version`; the root index's frontmatter carries the same
   `okf_version` (profile §11).
3. **Seed `types.md` with the complete standard vocabulary.** Retain all fourteen
   canonical rows in Profile order, including unused standards. Add a
   project-specific row before first use and keep extensions in lexical order.
4. **Apply the actor condition.** If any seeded concept records `generated.by` or
   another OKF actor-valued field, seed `actors.md` with every used actor. Record
   only evidenced identity and affiliation, using `unknown` rather than guessing,
   and give each dated row a non-overlapping active period. If no actor-valued field
   is present, omit the registry or seed it voluntarily.
5. **Write the repository's agent instruction paragraph.** `AGENTS.md` (or the equivalent)
   MUST say that durable documentation lives in the bundle, that the reader starts at
   `knowledge/index.md`, and that execution records stay in the tracker. Without it an
   agent will write a `docs/` file beside the bundle and both will be half right.

**Create no directories during generic seeding.** `architecture/`,
`ways-of-working/`, `interactions/`, and `references/` are optional lazy names, not
required layout. A subject directory is created only when the repository's actual
knowledge gives the adopter enough context to make that placement judgment; setup
has none and MUST NOT predict it.

### 2.2 What adoption does not include

A repository does **not** migrate its existing documents as part of adoption. Adoption
gives new knowledge a home; §5 converts old knowledge, and it is a separate, scheduled
piece of work. A repository MAY run for months with a thin bundle beside an unconverted
`docs/` tree, provided §2.1's paragraph says which is authoritative for what.

### 2.3 Definition of done

Adoption is complete when a validator run is clean, the root index lists exactly the
concepts that exist, and someone who has never seen the repository can find the
authoritative home for a new decision without asking. The third is the real test and it is
not mechanical.

---

## 3. Index generation

The profile tightens OKF §8's verbatim-description SHOULD into a MUST (profile §9). That is
what makes an index mechanically checkable and safely regenerable, and it costs a two-file
write per concept. Past a few dozen concepts the cost is paid by a generator or it is paid
in drift.

### 3.1 Contract

A generator MUST:

- **Be deterministic.** The same tree produces byte-identical output.
- **Be idempotent.** Running it on its own output changes nothing.
- **Build the semantic projection in profile §9.** Parse concepts, the root type
  registry, immediate directories, and eligible referenced assets as inputs; do
  not treat an existing index as authored input.
- **Preserve the root index's frontmatter**, including `okf_version`, unchanged.
- **Write an `index.md` for every nonempty directory**, including each nonempty level of
  `references/`.
- **Choose one deterministic Markdown rendering** of the semantic result. Formatting
  is an implementation choice until a later lint contract fixes presentation.

A generator MUST NOT:

- **Invent missing semantic data.** It reports a missing title, description, type
  registration, or other required projection input instead of synthesizing one.
- **Preserve authored index-only state.** Existing group order, entry order,
  directory descriptions, and extra prose are drift from a generated projection,
  not state to carry forward.

### 3.2 Semantic comparison

A validator MUST parse an index into groups and entries and compare that model with
the profile §9 projection. It MUST compare membership, group identity and order,
entry order, labels, targets, and descriptions. It MUST NOT fail semantic
conformance for bullets, whitespace, heading markers, or other Markdown
presentation that parses to the same model.

This comparison keeps two responsibilities separate:

- generation may choose and normalize presentation; and
- validation decides only whether the parsed navigation semantics are correct.

Presentation lint and automatic formatting are deferred. They MUST NOT be smuggled
into semantic validation as byte comparison.

### 3.3 Authored history stays outside generation

The root log is not an index input or output. A generator MUST preserve it
unchanged; an author or authoring workflow records meaningful history separately.
Current concepts and version-control diffs may assist that workflow, but an
implementation MUST NOT claim they can reconstruct the log's significance or
completeness mechanically.

### 3.4 Verification without generation

A validator checks the semantic result a generator maintains (profile §9). A
repository MAY hand-maintain indexes and rely on validation to catch drift. The
generator is an implementation convenience, not a required bundle artifact; the
indexes themselves remain required for every nonempty directory.

---

## 4. Validation

### 4.1 Results and exit codes

The command surface for Profile 2026.2 is `okfp validate <bundle> [--output
text|json]`. The bundle path is required and implementations MUST inspect
exactly that directory. They MUST NOT discover a repository bundle by walking
upward, accept a caller-selected Profile or rule set, or provide `--strict` or
another switch that promotes recommendations into requirements.

Text and JSON MUST expose four distinct components:

| Component | States |
| --- | --- |
| OKF conformance | `PASS`, `FAIL` |
| Deterministic Profile validation | `PASS`, `FAIL`, `UNSUPPORTED`, `BLOCKED BY OKF` |
| Judgment Rules | `UNASSESSED` |
| Automated gate | `PASS`, `FAIL`, `UNSUPPORTED` |

The independent OKF report MUST remain intact and Profile findings MUST NOT
reclassify it. If OKF fails, deterministic Profile validation MUST stop as
`BLOCKED BY OKF` without cascading findings from partial content. Exit `0`
means OKF and deterministic Profile checks passed; exit `1` means either failed;
exit `2` means the invocation could not assess the declared release, including
usage, I/O, and unsupported-release outcomes. Advisories MUST NOT change the
automated gate or exit status.

### 4.2 Findings carry stable identifiers

Every deterministic Profile finding MUST carry a stable machine-readable ID
alongside its prose in the `concepta-profile/<rule-slug>` namespace, and MUST
name the Profile release and normative rule reference it assesses. The ID MUST
describe the semantic rule rather than a section number, implementation class,
or message text, so integrations can depend on it across refactoring.

The closed validator MUST NOT accept suppressions or exceptions. A bundle cannot
change the immutable rules selected by its declaration, and a caller cannot
change them through command options or repository configuration.

### 4.3 What a validator must never report

The profile forbids reporting a missing `verified` event (§14.1) and requires tolerant
reading (§14.2). Concretely, a conforming validator MUST NOT report, at any severity:

- a concept with no `verified` event, or any derived trust tier;
- an unrecognized `type` or relationship label as anything other than the
  producer-side registry advisories the Profile names;
- an external URL that does not resolve;
- a concept using an OKF 0.2 mechanism the profile is silent about.

The producer-defined-frontmatter prohibition is different: the validator MUST
report a Profile failure when a Profiled Bundle contains a key that OKF 0.2 does
not define, while preserving the unknown key and leaving the independent OKF
result unchanged. Tolerant reading governs consumption; the Profile rule governs
what Concepta producers write.

The first is the load-bearing one. The only way an author can clear a "missing
verification" report is to record a verification that did not happen, which converts a
diagnostic into a corruption of the evidence model — the one failure mode this whole design
is built to prevent.

A validator MAY summarize trust tiers and organizational provenance, and such a summary
MUST NOT affect exit status.

The conditional registry and complete actor-row requirements in profile §6.1.1
are Deterministic Rules. Reporting their absence as a Profile failure does not
reject the concept as invalid OKF, alter its actor string, or change its derived
trust tier.

Validation MUST keep syntax separate from contextual truth. It checks required
metadata presence and shape, canonical type rows and ordering, used-type
registration, actor side membership and non-overlapping period syntax,
source structure, unique source IDs, recognized attribution joins, and literal
tag duplication. A footnote is source attribution only when its label matches a
declared source ID; ordinary Markdown footnotes are not findings. It MAY expose
the organizational row selected at an event timestamp, but unresolved or ambiguous
affiliation remains `unknown` and MUST NOT produce a finding. Validation MUST leave
durable-capture boundaries, standard-type fit,
metadata truth, actor identity and affiliation, missing material provenance,
evidence for freshness, and semantic tag aliases to Profile Review. A registered
project-specific type and missing `generated` produce advisories; missing
`verified` produces no finding.

A concept beside an area of the same name produces only the non-blocking
placement advisory named by Profile §14.1. It MUST NOT change Profile
conformance, the automated gate, or exit status; Profile Review decides whether
the concept should move into the area.

For external boundaries, validation MUST check the one-label/one-target
Relationships shape as a deterministic rule. It MUST report a non-bundle-relative
internal target, an additional relationship label, and an unresolved internal target
only as advisories that do not affect the automated gate or exit status,
and it MUST preserve the unresolved edge exposed by the OKF graph. It MUST NOT infer
relationship meaning, lifecycle ownership, path conformance, whether a date is
intrinsic identity, or whether an external citation can be repaired. The complete
path rule belongs to Profile Review because a preserved external ID has no
Profile-specific syntax that separates it mechanically from the authored slug.

The implementation MUST use the ordinary OKF graph without an adapter. It exposes
Relationships targets and unresolved links as the same untyped body edges as any
other Markdown link and MUST NOT enrich, reinterpret, or replace those edges with
Profile labels.

Profile Review assesses whether a cited artifact faces genuine availability risk,
whether repository visibility and sanitization are appropriate, whether images are
optimized, whether media is heavy enough to stay external, and whether an exceptional
stable-concept deletion is justified. The Profile deliberately defines no mechanical
media inventory or threshold. Network availability MUST NOT be probed as a
conformance check; an external resource that no longer resolves remains ordinary OKF
provenance or a body link.

### 4.4 Version dispatch

A validator MUST read `concepta_profile` from `profile.md` and apply the rules of that
release. It MUST read the first fenced `yaml` block in the body as the Profile
declaration and MUST NOT infer release values from another block or from
frontmatter.

- An **unrecognized version format** is not an error. The value is opaque; a validator that
  parsed it as semver would have broken on the 2026.1 release, which is exactly the reason
  the format changed.
- The first validator MUST implement only Profile 2026.2. Any other declared
  value produces `UNSUPPORTED PROFILE RELEASE`, deterministic Profile state
  `UNSUPPORTED`, automated-gate state `UNSUPPORTED`, and exit `2`, while still
  exposing the independent OKF result. Unsupported is tool capability, not a
  Profile-conformance verdict.
- A validator MUST NOT fall back to the newest rules it knows. A declaration
  selects an immutable release; neither the caller nor the bundle may inject,
  omit, replace, or parameterize its rules.
- A missing or unreadable declaration prevents release dispatch and is reported
  without claiming a Profile-conformance result. Any OKF result available from
  the independent validation remains separately visible.

### 4.5 Where it runs

A validator SHOULD run in CI on any change touching the bundle. One `okfp
validate <bundle>` invocation is the complete model-independent automated gate;
a separate OKF command MAY still be useful for focused upstream diagnostics.
CI MUST NOT claim that Judgment Rules or Complete Profile Assessment ran.

### 4.6 Release evidence

Profile 2026.2 has two non-normative release artifacts with different jobs:

- [`../docs/compatibility/2026.2-okf-0.2.md`](../docs/compatibility/2026.2-okf-0.2.md)
  records the rule-level compatibility review against pinned OKF 0.2.
- [`profile-coverage-2026.2.md`](profile-coverage-2026.2.md) assigns each normative Profile
  clause to deterministic validation or contextual Profile Review.

The compatibility review MUST NOT stand in for implementation coverage, and the
coverage matrix MUST NOT imply that a rule is compatible merely because an
assessment exists. Issue #19 verified that both artifacts account for every
normative rule before publishing the release.

---

## 5. Migration

Converting an existing tree into a bundle. The method below is generic; a project's own
measurements and slice plan are project artifacts and stay in the project.

### 5.1 Measure before deciding

Produce, from the actual tree: a document inventory with sizes; every identifier scheme in
use and how many documents cite each; the cross-reference graph; and the set of generators,
scripts, and downstream artifacts that read those documents.

The last is the one that gets skipped and the one that hurts. A tree with two scripts
parsing `FR-*` out of markdown has constraints that no reading of the documents reveals.

### 5.2 Classify, then cluster — in that order

**Classify** each candidate node by the `type` it would carry. This is a judgment about what
a document *is*, made independently of where it will live.

**Then cluster** by subject. Areas fall out of genuine shared subjects in the
actual corpus. No count establishes that judgment: a small coherent cluster may
be an area, while a large assortment with no truthful shared subject may not.

Doing these in the other order reproduces the kind-named tree, because a set of documents
sorted by what they are will always look like it wants folders named after what they are.

### 5.3 Granularity is the promotion rule, applied at scale

Migration is where the promotion rule (profile §4.2) does its heaviest work, because the
source tree's granularity is an artifact of how it was written, not of what has a lifecycle.

The recommendation is unchanged: an outcome normally earns a concept when it needs
independent status, provenance, relationships, reuse, replacement, or history.
Migration applies that guidance contextually and may retain a legitimate reviewed
exception.

*Worked example.* A software requirements specification carrying 149 atomic requirements
across 17 capability areas. One concept per requirement gives each its own `sources`,
`verified`, and derived trust tier — the highest fidelity available — and is wrong: 149
concepts swamp the areas they sit in, and an atomic requirement has no lifecycle apart from
the capability area and the rule it formalizes. In this corpus, Profile Review recommends
one concept per *capability area*, with requirements in the body and their IDs preserved
verbatim. Mixed provenance inside the concept is then handled by footnotes keyed to
`sources[].id` (profile §6.1), and the split test that would override this — materially
different *verification* across parts of one concept (profile §4.2.1) — does not apply,
because a capability area is signed off as a unit or not at all.

The same reasoning normally goes the other way for standing rules: one rule per concept, because each
carries its own provenance and its own trust tier, and averaging them would let a
well-evidenced rule lend its confidence to a thin one.

### 5.4 Slice vertically, never by kind

A slice is **one subject, migrated whole** — its terms, its rules, its open questions, its
specification, its analyses. Never "all the glossary this week."

- Order slices along the dependency spine, and never begin a slice whose inbound
  dependencies are unmigrated.
- One slice per working session. A half-migrated subject is two sources of truth for that
  subject, which is the condition the migration exists to end.
- A slice is complete only when every concept in it satisfies the per-concept write, its
  area index has been **read end to end** by a person, and the validator passes on the tree
  as it stands — including the hybrid state, which it must, since the tree is hybrid for the
  whole migration.

Placement is reviewed, not verified. Nothing mechanical detects a concept filed under the
wrong subject; only a person reading the area index does.

### 5.5 Invariants that generalize

Three migration invariants are not project-specific and every migration MUST carry them:

1. **Never promote evidence.** Reformatting is not confirmation. Preserve every
   truthful existing `verified` event, but add a new one only when an actor genuinely
   confirms the content against its sources or `resource`. Adding one as a migration
   formality silently converts an internal reading into apparent sign-off, and nothing
   in the record distinguishes genuine confirmation from a clerical event.
2. **IDs survive verbatim.** Any identifier the outside world cites is already frozen
   (profile §8.1, §8.2). Never renumber during a migration; a migration is exactly when it
   is most tempting and most damaging.
3. **Supersession is preserved, not deleted.** Superseded material migrates as `deprecated`
   concepts with `Superseded by` links, so the history stays inspectable. A migration that
   drops what was replaced destroys the record of how understanding moved.

For a 2026.2 migration, the implementation MUST inventory missing baseline
metadata, used and standard types, producer-defined fields, actor history, tags,
and materially derived claims before editing. Mechanical normalization may add
canonical type rows and reshape supported syntax; it MUST NOT guess a title,
description, lifecycle state, generation actor, verification event, affiliation,
freshness horizon, or source. Those truth-bearing gaps require Profile Review and
remain visible until evidence supplies the value.

For each producer-defined field, migration MUST adjudicate the value before
removing the key. It moves the information to an applicable OKF-defined field or
to body prose, preserving unknown provenance and meaning; when no truthful mapping
is known, the gap stays visible for Profile Review rather than being deleted.

The migration MUST also review existing meeting notes, source-event documents, and
Interaction Records against the durable-capture boundary. It retires or reshapes
routine minutes that have no durable combined context. For other outcome boundaries,
the migration SHOULD apply the Profile's promotion and splitting recommendations;
legitimate reviewed exceptions may remain embedded or combined. A filename or type
cannot make that decision mechanically.

The migration MUST inventory labelled relationships, tracker-owned artifacts,
specifications, externally cited concept IDs, planned moves, stable concepts selected
for retirement, and mirrored material. It mechanically reshapes malformed
Relationships entries, but Profile Review decides path conformance, label meaning,
lifecycle ownership, intrinsic chronology, citation repairability, deletion exceptions,
mirror classification and placement, availability risk, visibility, sanitization,
image optimization, and media classification. It externalizes media that Profile
Review identifies as prohibited. Repairable moves update known links, indexes, and
authored history together; an unrepairable known external citation freezes the path.
A followable external source remains a followable OKF resource when it is not
mirrored; migration MUST NOT replace it with a scope descriptor merely to avoid an
availability advisory.

A project MAY add invariants — a sanitization boundary excluding credentials, prices, or
raw transcripts is common — and SHOULD record them where the migration is executed, not in
the bundle's knowledge.

### 5.6 Retiring the old tree

Decide, before the first slice, whether the old tree is **fully replaced** or **phased
out**, and record it as a decision concept. Both are workable; leaving it undecided is not,
because each slice will then re-decide it. Full replacement is faster and ends drift sooner;
phased retirement is safer per step and keeps a working package throughout, at the cost of
running two authoritative homes for the duration.

Either way, generated deliverables and the scripts behind them read the old documents, and
each needs a bundle-sourced replacement before the documents it reads disappear.

---

## 6. Distribution

Distribution is owned by the repository that hosts the profile — the same one hosting this
guide — and its mechanics are documented there, in the root `README.md` and `skills/README.md`.
Consumers install the skills into their own agent's skills directory and pin the tools; no
project repository vendors a copy of the profile. Two requirements bear on bundles and so are
stated here:

- **The agent skill must reach every environment that writes to a bundle.** A subject-named
  tree is not self-inferrable: an agent that has never read the profile skill invents a
  kind-named directory, and only contextual Profile Review can establish that placement
  defect. Skill distribution is what makes conformance achievable
  rather than merely checkable.
- **The tools must be pinned per repository and dispatch on the declared release** (§4.4),
  so repositories on different profile releases can share one implementation.

---

## 7. Cross-bundle references

Deferred, and it stays deferred until a second bundle exists to design against — a
referencing mechanism designed against one bundle would encode that bundle's shape.

Until then, a bundle referencing another bundle's concept uses an ordinary URL link, which
OKF already tolerates and which a graph loader treats as an external node. A project MUST
NOT invent a cross-bundle identifier scheme in the meantime; a URL that later becomes a
first-class reference is a rewrite of one link kind, while a private scheme is a migration.

---

## 8. Conforming implementations

A tool claims conformance to this guide by satisfying, for the profile release it
implements:

- the generator contract (§3.1–§3.3), if it writes indexes;
- the exit codes (§4.1), finding IDs (§4.2), the prohibitions (§4.3), and version dispatch
  (§4.4), if it validates;
- tolerant reading (profile §14.2) in both cases.

A tool MAY implement a subset — validation without generation is the common case — and
states which. Nothing here licenses a tool to reject a bundle that is valid OKF.

---

## 9. Change record

**2026.2.** Establishes the closed validation
result model, release dispatch, and separate compatibility and coverage evidence
for the Profile 2026.2 integration. The driver was implementation work that
could not distinguish an independent OKF result, a deterministic Profile result,
and contextual judgment while the earlier guide treated all Profile findings as
advisories and allowed callers to promote them through `--strict`.

The structure slice also replaces preservation of authored index ordering and
directory descriptions with semantic generation and comparison, keeps authored
history outside generation, makes actor-registry seeding conditional, and removes
count-based clustering. The driver was real generator work that could not
reproduce index-only knowledge and real bundles that churned paths at arbitrary
concept counts without making subject placement more truthful.

The concept, trust, and durable-capture slice assigns syntactic metadata, type,
source, tag, and actor checks to validation while leaving semantic truth to Profile
Review (§4.3), seeds the complete standard type vocabulary (§2.1), and makes
migration preserve unknown provenance while reviewing event-derived concepts
(§5.5). The driver was real authoring and migration work that fabricated
verification and affiliation to clear mechanical expectations, while sparse type
seeding and metadata left agents without a reliable vocabulary or index input.

The external-boundary slice assigns relationship shape plus unresolved-link,
non-bundle-relative-link, and label advisories to deterministic validation while
leaving semantic relationships, lifecycle ownership, path identity, move
repairability, deletion, and media and mirroring judgments to Profile Review. The
driver was real authoring work that duplicated tracker state, froze repairable paths,
enriched ordinary OKF edges, and either mirrored confidential heavy sources
indiscriminately or weakened their OKF provenance when leaving them external.

An implementation conformant to guide 2026.1 does not automatically conform to
this release. To migrate, it MUST adopt the
explicit command, result, exit, and unsupported-release contract in §4 and the
structural obligations in §§2–3 and the external-boundary validation and migration
obligations in §§4–5.

**2026.1** — first release. Binds profile 2026.1. Establishes adoption (§2), the index
generator contract (§3), the validation process contract (§4), and the migration method
(§5), each of which existed only as project-local practice or as an unwritten obligation
beforehand. Cross-bundle references (§7) remain deferred, as the profile leaves them.

Titled *Implementation Guide* rather than *Implementation Specification*, and filed under
`implementation/`. The profile is also a specification, so a subordinate document called "the
spec" inverted the precedence it was trying to state, and the two filenames differed by one
suffix. The rename is editorial and carries no rule change; §1 states why "guide" does not
mean advisory.

Current known gap: the index generator described in §3 is specified but not yet implemented.
