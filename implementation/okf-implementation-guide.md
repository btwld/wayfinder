# Concepta OKF Profile — Implementation Guide

**Version 2026.1** — binds **Concepta OKF Profile 2026.1**, which profiles **OKF 0.2**

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
behaviour the profile deliberately leaves open — the profile says an index MUST carry each
concept's `description` verbatim; this document says what a generator does about the one
line an index carries that no concept can supply.

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

Adoption is five files and one paragraph, in this order:

1. **Seed the root.** `index.md`, `log.md`, `profile.md`, `types.md`, `actors.md`, exactly
   as the profile's §3.5 defines them. The skill's `SEEDING.md` carries the literal text.
2. **Declare the versions.** `profile.md`'s first fenced `yaml` block carries
   `concepta_profile` and `okf_version`; the root index's frontmatter carries the same
   `okf_version` (profile §11).
3. **Seed `types.md` with the types actually used** — three rows on day one, since the
   three root concepts are the only concepts. Add a row before first use of a new type,
   never after.
4. **Seed `actors.md`** with whoever authored those files. It is cheap now and awkward
   later, because the first `generated.by` is already an actor.
5. **Write the repository's agent instruction paragraph.** `AGENTS.md` (or the equivalent)
   MUST say that durable documentation lives in the bundle, that the reader starts at
   `knowledge/index.md`, and that execution records stay in the tracker. Without it an
   agent will write a `docs/` file beside the bundle and both will be half right.

**Create no directories.** Not `architecture/`, not `ways-of-working/`, not a subject area
— an area is earned at three concepts (profile §3.1), and the four profile-fixed names are
*permitted* early, not *recommended* early. A seeded tree of empty directories is the
prediction the profile exists to prevent, and it also trips the validator, which reports an
empty area.

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
- **Copy `description` verbatim** from each concept's frontmatter into its entry.
- **Emit an entry for every non-reserved `.md` file** in the directory, and for every
  nonempty subdirectory.
- **Preserve the root index's frontmatter**, including `okf_version`, unchanged.
- **Write an `index.md` for every nonempty directory**, including each nonempty level of
  `references/`.

A generator MUST NOT:

- **Invent a description.** A concept with no `description` gets an entry with an empty
  description and an advisory, never a description synthesized from its title or body.
- **Discard anything it did not generate.** See §3.3.
- **Reorder existing entries.** See §3.2.

### 3.2 Order is authored; membership and descriptions are generated

Entry order carries meaning a generator cannot reconstruct. `initial-business/` lists its
glossary as package, balance, then the two buckets — the order the domain is learned in,
not the order the filenames sort in. Alphabetizing it would be a silent loss.

So the split is:

- **Grouping** is generated: entries group by `type` under headings, definitions first
  (profile §9).
- **Membership and descriptions** are generated: exactly the concepts present, described
  exactly as their frontmatter describes them.
- **Order within a group** is preserved. Entries already present keep their relative order;
  a concept new to the group is appended to the end of it, where a human can move it.

Heading text for a type group MUST be derivable from `types.md` — ordinarily the pluralized
type name. A generator MAY carry a display map, which MUST live in the tool, never in a
bundle file, because a bundle file holding it would be a projection that became a source of
truth (profile §13).

### 3.3 The line no concept can supply

An entry linking a *directory* carries an authored one-line description of the area's
subject, because a directory has no frontmatter (profile §9). It is the one line in an
index that is not derived, and a generator that regenerated it would either delete it or
invent it.

A generator MUST therefore read the existing index before writing it, carry every
directory line forward verbatim, and for a directory that has no line yet emit a
placeholder and report it as needing an author. This is the only state an index generator
carries across runs, and keeping the list of exceptions at exactly one is deliberate.

### 3.4 Verification without generation

A validator checks the same invariants a generator maintains (profile §14.1: a missing or
stale index, a description that disagrees with its concept). A repository MAY therefore
hand-maintain its indexes indefinitely and rely on the validator to catch drift. The
generator is a convenience for scale, not a conformance requirement, and no bundle is
non-conformant for lacking one.

---

## 4. Validation

### 4.1 Severities and exit codes

The two severities are the profile's (§14.1) and are not restated here. What this document
fixes is the process contract, so that CI behaves the same way everywhere:

| Condition | Exit |
| --- | --- |
| No OKF violations, no advisories | `0` |
| Advisories only, without `--strict` | `0` |
| Advisories only, with `--strict` | `1` |
| One or more OKF §11 violations | `1` |
| No bundle found | `2` |

A validator MUST accept `--strict` with exactly this meaning, and MUST locate the bundle by
walking up from a given path for `knowledge/index.md` rather than assuming its own location
in the tree. That is what lets one installed tool serve every repository.

### 4.2 Findings carry stable identifiers

Every finding MUST carry a stable machine-readable ID alongside its prose, namespaced by
the level that owns it — `okf/type-missing`, `profile/area-below-minimum`,
`profile/index-description-mismatch`. Prose is for the author; the ID is what a repository
suppresses in CI when it has accepted a deviation deliberately, and a diagnostic that can
only be suppressed by text match is one that gets suppressed by disabling the tool.

A validator SHOULD support suppressing a finding ID for a path, and MUST record any
suppression somewhere a reader of the repository can see it.

### 4.3 What a validator must never report

The profile forbids reporting a missing `verified` event (§14.1) and requires tolerant
reading (§14.2). Concretely, a conforming validator MUST NOT report, at any severity:

- a concept with no `verified` event, or any derived trust tier;
- an unrecognized `type`, relationship label, or frontmatter key, as anything other than
  the registry advisories the profile names;
- an actor absent from `actors.md`, as anything more than an advisory;
- an external URL that does not resolve;
- a concept using an OKF 0.2 mechanism the profile is silent about.

The first is the load-bearing one. The only way an author can clear a "missing
verification" report is to record a verification that did not happen, which converts a
diagnostic into a corruption of the evidence model — the one failure mode this whole design
is built to prevent.

A validator MAY summarize trust tiers and organizational provenance, and such a summary
MUST NOT affect exit status.

### 4.4 Version dispatch

A validator MUST read `concepta_profile` from `profile.md` and apply the rules of that
release.

- An **unrecognized version format** is not an error. The value is opaque; a validator that
  parsed it as semver would have broken on the 2026.1 release, which is exactly the reason
  the format changed.
- An **unknown release** — well-formed but not implemented — means the validator checks OKF
  conformance only, reports the unknown release as an advisory, and exits accordingly. It
  MUST NOT fall back to the newest rules it knows, because a bundle written against an older
  release would then be reported for deviating from a rule that did not exist when it was
  written.
- A **missing declaration** is an advisory, and validation proceeds at OKF level.

### 4.5 Where it runs

A validator SHOULD run in CI on any change touching the bundle, and SHOULD run with
`--strict` there once a repository's advisories are at zero. Adopting `--strict` before that
point trains everyone to ignore a red build.

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

**Then cluster** by subject. Areas fall out of the clusters, subject to the three-concept
rule; a cluster of one or two is not an area, and its concepts sit at the bundle root until
the third arrives.

Doing these in the other order reproduces the kind-named tree, because a set of documents
sorted by what they are will always look like it wants folders named after what they are.

### 5.3 Granularity is the promotion rule, applied at scale

Migration is where the promotion rule (profile §4.2) does its heaviest work, because the
source tree's granularity is an artifact of how it was written, not of what has a lifecycle.

The test is unchanged: an outcome earns a concept when it needs independent status,
provenance, relationships, reuse, replacement, or history.

*Worked example.* A software requirements specification carrying 149 atomic requirements
across 17 capability areas. One concept per requirement gives each its own `sources`,
`verified`, and derived trust tier — the highest fidelity available — and is wrong: 149
concepts swamp the areas they sit in, and an atomic requirement has no lifecycle apart from
the capability area and the rule it formalizes. One concept per *capability area*, with
requirements in the body and their IDs preserved verbatim, is the granularity the rule
selects. Mixed provenance inside the concept is then handled by footnotes keyed to
`sources[].id` (profile §6.1), and the split test that would override this — materially
different *verification* across parts of one concept (profile §4.2.1) — does not apply,
because a capability area is signed off as a unit or not at all.

The same reasoning goes the other way for standing rules: one rule per concept, because each
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

1. **Never promote evidence.** Reformatting is not confirmation. A migrated assertion gets
   no `verified` entry — adding one as a formality silently converts an internal reading
   into a client sign-off, and it is unrecoverable, because nothing in the record
   distinguishes a genuine confirmation from a clerical one.
2. **IDs survive verbatim.** Any identifier the outside world cites is already frozen
   (profile §8.1, §8.2). Never renumber during a migration; a migration is exactly when it
   is most tempting and most damaging.
3. **Supersession is preserved, not deleted.** Superseded material migrates as `deprecated`
   concepts with `Superseded by` links, so the history stays inspectable. A migration that
   drops what was replaced destroys the record of how understanding moved.

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
  kind-named directory, and that is a knowledge defect a validator reports only as an
  advisory about an area name. Skill distribution is what makes conformance achievable
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

**2026.1** — first release. Binds profile 2026.1. Establishes adoption (§2), the index
generator contract (§3), the validation process contract (§4), and the migration method
(§5), each of which existed only as project-local practice or as an unwritten obligation
beforehand. Cross-bundle references (§7) remain deferred, as the profile leaves them.

Titled *Implementation Guide* rather than *Implementation Specification*, and filed under
`implementation/`. The profile is also a specification, so a subordinate document called "the
spec" inverted the precedence it was trying to state, and the two filenames differed by one
suffix. The rename is editorial and carries no rule change; §1 states why "guide" does not
mean advisory.

Known gaps, stated rather than hidden: the index generator described in §3 is specified but
not yet written, and §4.2's finding IDs are specified but not yet carried by
`tools/verify_knowledge_bundle.py`.
