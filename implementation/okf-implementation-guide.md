# Bitwild OKF Profile — Implementation Guide

**Version 2026.3** — binds **Bitwild OKF Profile 2026.3**, which profiles
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
behaviour the profile deliberately leaves open — for example, the Profile requires
every index to be the reference generator's output while this guide pins the
`okf` release that generator comes from.

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

Adoption of Profile 2026.3 creates one project binding, two bundle root
files, and one agent-instruction paragraph, in this order:

1. **Select the release.** Write `wayfinder.json` at the project root with one
   direct `bitwild_profile` Git source and the explicit bundle path in its
   `applies_to` list. Resolve it with `wayfinder get` and commit the resulting
   metadata-only `wayfinder.lock`. Add only project-specific type, tag, and
   actor definitions that actual knowledge uses.
2. **Seed the bundle.** Create `index.md` carrying `okf_version: "0.2"` and
   `log.md` under `knowledge/`. The adoption skill's `SEEDING.md` carries the
   literal template. Do not copy the 2026.2 `profile.md`, `types.md`, or
   `actors.md` concepts into a new 2026.3 bundle. Once the bundle holds
   concepts, `wayfinder validate --fix` writes every index (§3.1).
3. **Write the repository's agent instruction paragraph.** `AGENTS.md` (or the
   equivalent) MUST say that durable documentation lives in the bundle, that
   the reader starts at `knowledge/index.md`, and that execution records stay
   in the tracker.

Existing 2026.2 bundles retain their old root files and declaration; adoption
is not a migration. See §5 for migration.

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

Adoption is complete when a validator run is clean, every index is current, and
someone who has never seen the repository can find the authoritative home for a
new decision without asking. The third is the real test and it is
not mechanical.

---

## 3. Index generation

Profile 2026.3 makes every index the output of the OKF reference index
generator (profile §9). This section pins that generator and binds the tools
that write and check its output. Profile 2026.2 keeps its own semantic
projection; §3.4 preserves that legacy contract unchanged.

### 3.1 The reference generator (2026.3)

The reference generator for Profile 2026.3 is `OkfIndexGenerator` in `okf`
0.5.0, the release Wayfinder builds with, run over the loaded bundle with the
root index declaring `okf_version: "0.2"`. A tool that writes or checks 2026.3
indexes MUST use this generator release. An `okf` release that changes the
generator's output changes which bytes conform, so adopting it requires a
revision of this guide that pins the new release.

A validator MUST report every path the generator writes whose file is missing
or whose text differs from the generated text. The comparison is exact: the
generator's rendering is the contract, so no presentation is left to an
implementation and no semantic normalization applies.

`wayfinder validate <bundle> --fix` is the safe fix, in the convention of
`eslint --fix` and `ruff --fix`. For a bundle whose selected Profile is
2026.3, it first writes the generator's output, then validates and reports as
usual. It MUST:

- **Write only generated `index.md` files**, and only those whose bytes differ.
- **Write nothing when OKF fails** (`BLOCKED BY OKF`), when Profile dispatch
  fails, or when the selected release has no fixable rules, as 2026.2 has
  none. Its output says which applied.
- **Be idempotent.** A second run over its own output writes nothing.
- **Refuse to write through a symbolic link.**

Its JSON report adds a `fix` object before `okf`; without `--fix` the report
is unchanged.

`okf index <bundle> --declare-version 0.2 --check` reports the same stale
paths from the `okf` command line.

### 3.2 Authored history stays outside generation

The root log is not an index input or output. A generator MUST preserve it
unchanged; an author or authoring workflow records meaningful history separately.
Current concepts and version-control diffs may assist that workflow, but an
implementation MUST NOT claim they can reconstruct the log's significance or
completeness mechanically.

### 3.3 Verification without generation

A validator checks the result a generator maintains (profile §9). A repository
MAY write indexes by any means and rely on validation to catch drift. The
generator is an implementation convenience, not a required bundle artifact.

### 3.4 Legacy contract (2026.2)

This subsection binds Profile 2026.2 only. Its semantic projection is the one
in the 2026.2 Profile snapshot, and ADR-0007 still governs its target
comparison.

The profile tightens OKF §8's verbatim-description SHOULD into a MUST (profile §9). That is
what makes an index mechanically checkable and safely regenerable, and it costs a two-file
write per concept. Past a few dozen concepts the cost is paid by a generator or it is paid
in drift.

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

`--fix` never writes a 2026.2 bundle; its indexes stay hand-maintained or come from a
tool that implements this projection.

---

## 4. Validation

### 4.1 Results and exit codes

The command surface is `wayfinder validate <bundle> [--config <file>] [--fix]
[--output text|json|sarif]`; §3.1 defines `--fix`. The bundle path is required and implementations MUST
inspect exactly that directory. Config discovery MAY walk up to find the
project's `wayfinder.json`, but MUST NOT select a different bundle. They MUST NOT
accept a caller-selected Profile or rule set, or provide `--strict` or
another switch that promotes recommendations into requirements.

Text and JSON MUST expose four distinct components:

| Component | States |
| --- | --- |
| OKF conformance | `PASS`, `FAIL` |
| Deterministic Profile validation | `PASS`, `FAIL`, `UNSUPPORTED`, `BLOCKED BY OKF` |
| Judgment Rules | `UNASSESSED` |
| Automated gate | `PASS`, `FAIL`, `UNSUPPORTED` |

The independent OKF report MUST remain intact and Profile findings MUST NOT
reclassify it. The OKF component is okf's own report projection: one
canonically ordered findings array with namespaced identifiers and the
two-tier error/advisory severity model, in which a file that failed to load
is an error finding like any other. OKF conformance is `PASS` exactly when
that report holds no error-severity finding; the validator judges it
non-strict, so an OKF advisory never fails OKF conformance. If OKF fails,
deterministic Profile validation MUST stop as `BLOCKED BY OKF` without
cascading findings from partial content. Exit `0` means OKF and deterministic
Profile checks passed; exit `1` means either failed; exit `2` means the
invocation could not assess the declared release, including usage, I/O, and
unsupported-release outcomes. Advisories — OKF's or the Profile's — MUST NOT
change the automated gate or exit status.

The result model also carries summary entries beside the findings. A
release's summary rules report what it permits (Profile §14.1), and their
entries MUST NOT appear among the findings or change any component state or
the exit status. JSON carries them as `profile.summary`, a canonically ordered
list whose entries have a finding's `id`, `message`, `location`,
`profile_release`, and `rule` but no `severity`; the list is present, even when
empty, whenever the assessed release declares a summary rule. Text prints a
`Summary:` block after the findings when there is an entry.

`sarif` carries the same findings as JSON in a SARIF 2.1.0 log for code
scanning. Each OKF and Profile finding is one result whose `ruleId` is its
finding ID; `error` maps to SARIF `error` and `advisory` to `warning`. Each
summary entry follows the findings as a `note` result of kind `informational`.
The selected release's rules are the run's rule descriptors, and the four
component states are run properties because SARIF has no field for them. The
exit status is the same as for text and JSON.

### 4.2 Findings carry stable identifiers

Every deterministic Profile finding MUST carry a stable machine-readable ID
alongside its prose, `<namespace>/<rule-slug>`, where the namespace is the
catalog's: `concepta-profile` for the installed rules, and the Profile
identity in kebab-case for a source catalog (Profile §11). It MUST name the
release and normative rule reference of the catalog that assessed it. The ID
MUST describe the semantic rule rather than a section number, implementation
class, or message text, so integrations can depend on it across refactoring.

The closed validator MUST NOT accept suppressions or exceptions. A bundle cannot
change the immutable rules selected by its declaration, and a caller cannot
change them through command options or repository configuration.

### 4.3 What a validator must never report

The profile forbids reporting a missing `verified` event (§14.1) and requires tolerant
reading (§14.2). Concretely, a conforming validator MUST NOT report, at any severity:

- a concept with no `verified` event, or any derived trust tier;
- an unrecognized `type`, tag, or relationship name as anything other than the
  producer-side vocabulary finding the selected release names;
- an external URL that does not resolve;
- a concept using an OKF 0.2 mechanism the profile is silent about.

The producer-defined-frontmatter prohibition is different: the validator MUST
report a Profile failure when a Profiled Bundle contains a key that OKF 0.2 does
not define and the selected release does not declare (§4.8), while preserving
the unknown key and leaving the independent OKF result unchanged. Tolerant reading governs consumption; the Profile rule governs
what Concepta producers write.

The first is the load-bearing one. The only way an author can clear a "missing
verification" report is to record a verification that did not happen, which converts a
diagnostic into a corruption of the evidence model — the one failure mode this whole design
is built to prevent.

A validator MAY summarize trust tiers and organizational provenance, and such a summary
MUST NOT affect exit status.

For Profile 2026.2, the conditional `actors.md` registry and complete actor-row
requirements in its §6.1.1 are Deterministic Rules. Profile 2026.3 instead
checks the selected binding's actor lookup under its §6.1.1. Neither check
rejects the concept as invalid OKF, alters its actor string, or changes its
derived trust tier.

Validation MUST keep syntax separate from contextual truth. It checks required
metadata presence and shape, release-specific standard type definitions and
used-type registration, actor side membership and (for 2026.2 only)
non-overlapping period syntax, source structure, unique source IDs, recognized
attribution joins, and literal
tag duplication. A footnote is source attribution only when its label matches a
declared source ID; ordinary Markdown footnotes are not findings. It MAY expose
organizational affiliation; when it does, it MUST resolve the applicable registry
row through Profile §6.1.1. Unresolved or ambiguous affiliation remains `unknown`
and MUST NOT produce a finding. Validation MUST leave durable-capture boundaries,
type and registered-meaning fit (Profile §§5.1–5.2, §14.1),
metadata truth, actor identity and affiliation, missing material provenance,
evidence for freshness, and semantic tag aliases to Profile Review. A registered
project-specific type and missing `generated` produce advisories; missing
`verified` produces no finding.

For external boundaries under Profile 2026.3, validation MUST check the
`relationships` frontmatter key of Profile §7.2 as a deterministic rule: a
present value that is not a list, an entry that is not a mapping of exactly
`relationship` and `resource`, an empty `resource`, and an undeclared
relationship name are failures. It MUST resolve each `resource` exactly as the
OKF graph resolves a link target, and report a non-bundle-relative internal
target and an unresolved internal target only as advisories that do not affect
the automated gate or exit status. Under Profile 2026.2 it instead checks the
one-label/one-target `# Relationships` body shape and reports an additional
label as an advisory. Under either release it MUST report a non-bundle-relative
or unresolved internal link only as an advisory and preserve the unresolved
edge exposed by the OKF graph. It MUST NOT infer
relationship meaning, lifecycle ownership, path conformance, whether a date is
intrinsic identity, or whether an external citation can be repaired. The complete
path rule belongs to Profile Review because a preserved external ID has no
Profile-specific syntax that separates it mechanically from the authored slug.

The implementation MUST use the ordinary OKF graph and MUST NOT enrich,
reinterpret, or replace its edges. Under 2026.2 a `# Relationships` target is the
same untyped body edge as any other Markdown link. Under 2026.3 an implementation
that projects a graph or expands search context MAY read each `relationships`
entry as an additional edge named by its relationship and resolved as the OKF
graph resolves a link target. OKF's nodes and edges and their meanings stay
unchanged: a graph output adds such edges under a key of its own, never inside
OKF's edge list, so a consumer of the OKF graph contract reads it unchanged.

Profile Review assesses whether a cited artifact faces genuine availability risk,
whether repository visibility and sanitization are appropriate, whether images are
optimized, whether media is heavy enough to stay external, and whether an exceptional
stable-concept deletion is justified. The Profile deliberately defines no mechanical
media inventory or threshold. Network availability MUST NOT be probed as a
conformance check; an external resource that no longer resolves remains ordinary OKF
provenance or a body link.

### 4.4 Version dispatch

A validator MUST dispatch using exactly one of two selectors:

- For a bundle named by exactly one `applies_to` path in `wayfinder.json`,
  read its selected source chain from a current lock/cache and dispatch on
  manifest identity and exact release. `bitwild_profile/2026.3` selects this
  release. Verify safe paths, the manifest's OKF 0.2 binding, and parity of the
  base vocabulary with the compiled validator. A source manifest supplies
  declarations and may name the rule catalog its Profile ships; the catalog
  is data the installed engine evaluates, read from the cache at the locked
  commit, never from the network.
- For an unlisted legacy bundle, read `concepta_profile` from the first fenced
  `yaml` block in root `profile.md`. `"2026.2"` selects the immutable legacy
  validator; it is never interpreted as 2026.3.

An explicit `--config` path MUST exist and name the requested bundle. Unknown
IDs or releases produce `UNSUPPORTED` and exit `2`, preserving any independent
OKF result. A malformed or unreadable selector also prevents dispatch. The
validator MUST NOT silently apply the newest rules or reinterpret an old bundle
because a neighboring project config exists. Generic OKF reading remains
available even when Profile dispatch fails.

### 4.5 Where it runs

A validator SHOULD run in CI on any change touching the bundle. One `okfp
validate <bundle>` invocation is the complete model-independent automated gate;
a separate OKF command MAY still be useful for focused upstream diagnostics.
CI MUST NOT claim that Judgment Rules or Complete Profile Assessment ran.

### 4.6 Release evidence

Profile 2026.3 has two non-normative release artifacts with different jobs:

- [`../docs/compatibility-review.md`](../docs/compatibility-review.md)
  records the rule-level compatibility review against pinned OKF 0.2.
- [`profile-coverage.md`](profile-coverage.md) assigns each normative Profile
  clause to deterministic validation or contextual Profile Review.

Profile §15.1 owns their separation and the publication gate. Implementations
MUST use the coverage matrix, not the compatibility review, to determine whether
each normative clause is assessed by Automated Profile Validation or contextual
Profile Review.

### 4.7 External Profile binding (2026.3)

This subsection implements Profile §11. The published 2026.2 selector and
registries remain immutable; migration to proposed 2026.3 is explicit.
The project configuration and manifest shapes are described by
[`wayfinder.schema.json`](../docs/schemas/wayfinder.schema.json) and
[`wayfinder-profile.schema.json`](../docs/schemas/wayfinder-profile.schema.json).
A version-1 project file has **one** form: direct Profile sources and the bundle
paths they apply to. It has no `bundles`, `implements`, or `default_bundle` key.

```json
{
  "version": 1,
  "profiles": {
    "bitwild_profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "main",
        "path": "profile"
      },
      "applies_to": ["./knowledge"],
      "types": [
        {"name": "Project Note", "description": "A project-specific durable note"}
      ]
    }
  }
}
```

The map key is the manifest identity, not an alias. The manifest supplies its
release, upstream OKF binding and vocabulary. `bitwild_profile/2026.3` is the
installed closed ruleset; its fetched vocabulary must match the compiled
standard registry exactly. Each other Profile entry must `extends` a declared
parent chain reaching this base. A parent may be source-only with
`applies_to: []`; a child adds manifest and project vocabulary, but cannot
replace inherited names. Missing parents, cycles, collisions, unsupported
releases, and ambiguous bundle application fail Profile dispatch. Types,
topic tags, relationship names and actor lookup are the only local additions;
a binding cannot declare frontmatter keys. A registered custom type is
reported as a summary entry (§4.1); contextual meaning belongs to Profile
Review.

A non-base manifest may name its rule catalog (`"rules":
"wayfinder-rules.json"`, relative to the manifest). The resolver reads the
catalog with the same revision read as the manifest and parses it whole as
data (`wayfinder-rules.schema.json`); it must declare the manifest's identity
and release, report in the namespace Profile §11 derives from that identity,
and declare no frontmatter keys. The effective catalog chain is the installed
base catalog followed by each source catalog along `extends`, parent first.
Validation evaluates every catalog in the chain and each finding names its own
catalog's release and namespace, so an ancestor's findings never depend on a
child. A base manifest that names a catalog, a missing catalog file, or a
catalog naming a subject, slot, builtin, or keyword this engine lacks fails
resolution with the reason, which `get` reports and `validate` reports as
`UNSUPPORTED`; a catalog is never partially applied. The lock gains no field,
because its commit identifies the manifest and the catalog alike.

A relative local `source.git` is resolved from the directory containing
`wayfinder.json`, not the process working directory. Cache identity uses that
resolved location; the lock preserves the declared source spelling. A
drive-relative path is invalid.

`get` resolves all declared refs, writes `wayfinder.lock` atomically and
reuses a current lock. `upgrade` deliberately refreshes mutable refs. A
canonical-JSON hash invalidates the lock on semantic config changes, not
formatting changes; an unchanged source retains its locked commit during
`get`. The lock contains revision metadata, never project knowledge,
credentials, vocabulary or catalogs. The local Git cache holds fetched
objects.
If a current lock's selected commit is absent, a read-only command does not
substitute the current branch tip: run `get` to recover the exact commit or
`upgrade` to select a new revision deliberately. Failed resolution leaves the
previous lock intact.

Validation operates on **one explicit bundle**. The implementation first
inspects it under OKF 0.2. A failing OKF result blocks Profile assessment but
is never reclassified. For an OKF-conformant bundle, it parses the selected
project config, checks safe path/identity/release and reads only the selected
Profile chain from a current lock/cache. Missing or stale source state yields
`UNSUPPORTED` Profile dispatch alongside the independent OKF report; neither
CLI `validate` nor read-only MCP `validate` fetches or writes a lock. The
configured Profile then checks the root `index.md` `okf_version: "0.2"`,
standard and custom type/tag/actor references, and the other deterministic
Profile rules. An unlisted 2026.2 bundle keeps its in-bundle declaration; an
ancestor project config cannot silently migrate it. Unknown releases never
fall back to the newest rules.

`graph` projects the ordinary OKF graph, plus the `relationships` edges §4.3
permits, without Profile-source resolution.
Embedding `index` and `search` likewise consume the explicit bundle without
resolving unused Profile sources; they do not generate Profile navigation
indexes. A neighboring malformed `wayfinder.json` cannot make ordinary OKF
graph reading fail. Those command boundaries implement the separate outcomes
required by Profile §§14.1–14.2.

The parser checks `wayfinder.json` and each Profile manifest against their
published JSON Schemas, evaluated by the engine's own schema subset and
embedded in the binary, then runs the cross-document checks a schema cannot
express. Those cover normalized and canonical paths, `extends` chains, manifest
identity and release, the effective vocabulary and actor lookup. A schema
alone cannot prove filesystem safety, Git availability, or whether a concept
truthfully uses a type or topic tag. `captures/` remains outside the
bundle unless explicitly declared as another OKF bundle; no nested area
inherits a different Profile.

### 4.8 Frontmatter fields and type-specific constraints

Validation has two layers of frontmatter checking. The
upstream `okf` package validates the pinned OKF 0.2 field shapes and preserves
unknown content for tolerant reading. The Bitwild Profile adds only its
producer-side constraints:

| Field or family | Legacy 2026.2 coverage | Configured 2026.3 coverage |
| --- | --- | --- |
| `type` | Required non-empty string; membership in the `types.md` registry | Membership in the selected Profile's standard types plus binding custom types |
| `title`, `description` | Required non-empty strings | Unchanged |
| `status` | Required string with `draft`, `stable`, or `deprecated` | Unchanged unless a future Profile release explicitly changes it |
| `tags` | OKF shape plus an error-level Profile check for literal duplication of type, status, trust, or relationship labels | Bitwild 2026.3 declares the actual Profile and project tag vocabulary in JSON, rejects duplicate declarations and duplicate values within one concept, reports an undeclared used tag according to the release rule, and checks literal duplication against the declared relationship names |
| `generated`, `verified`, `stale_after` | OKF shape and timestamp diagnostics; actor extraction and trust semantics remain separate | Keep upstream meanings; do not add Profile-specific fields for trust or freshness |
| `sources` | OKF shape plus source-entry, unique-ID, attribution-join, and path diagnostics | Keep upstream meanings and run the same checks after binding resolution |
| `relationships` | Not a Profile key, so it fails like any producer-defined key; labelled links live in a `# Relationships` body section | The one key the release declares (Profile §7.2): a list of `relationship` and `resource` mappings, checked for shape, declared names, and target resolution |
| Other frontmatter keys | Unknown producer-defined keys fail the current Profile rule | Keys neither OKF nor the release declares fail; a binding cannot declare frontmatter keys |

A Profile release declares its additional frontmatter keys in its rule
catalog's `frontmatter_keys`, each with the sentence that defines it, and
`frontmatter-fields-declared` accepts exactly OKF's keys and those. OKF §4.1
permits producers additional keys, but a declared key MUST NOT be one OKF 0.2
defines or redefine an OKF field, so the engine rejects at load a catalog that
declares an OKF key, and the compatibility review records each declared key.
OKF's own fields keep their meaning: the 2026.3 `relationships` key stays out of
`sources`, whose OKF §5.1 meaning is derivation.

The current implementation therefore has no type-specific property schema. This
is deliberate: the Profile defines no type-specific body template, and OKF
frontmatter is an upstream contract rather than a project-owned object model.
The new JSON type extension records only a custom type's `name` and
`description`; it MUST NOT add arbitrary `properties`, `required` fields, or
per-project frontmatter keys.

If a future Profile needs a type-specific constraint, it MUST constrain existing
OKF fields using a new reviewed Profile release. It MUST NOT turn
`wayfinder.json` into a second frontmatter schema or allow a project to add
fields such as `owner`, `priority`, `confidence`, or `maturity`. Information
that has no OKF field belongs in the concept body or in a key a reviewed Profile
release declares under OKF §4.1; a new meaning for an OKF field requires an
upstream OKF change before a Profile can depend on it.

Tags remain OKF topic strings, but the next Bitwild binding treats its `tags`
arrays as a declared vocabulary rather than a list of recommendations. The
selected Profile manifest declares its base tags and the project binding adds
project tags. Wayfinder MUST reject duplicate names within either list and
collisions between the lists, reject duplicate values within one concept, and
apply the selected Profile release's explicit rule for an undeclared used tag.
For Bitwild 2026.3, an undeclared used tag is an error; a Profile that needs an
open vocabulary must state that as a different release rule. Relationship names
follow the same model: the manifest's `relationships` list declares the
standard names, the binding adds project names under the same duplicate and
collision rules, and an undeclared used name is an error.

The Profile's tag rule remains a Profile convention, not an OKF requirement:
generic OKF consumers still tolerate arbitrary tag strings. Semantic aliases
and whether a declared tag is a truthful topic remain Profile Review concerns.

The provenance of these limits matters. `status` is an OKF lifecycle field and
`draft`, `stable`, and `deprecated` are OKF's values; the Profile makes the
otherwise-optional field explicit and requires that it continue to describe the
document lifecycle. `tags` is also an OKF field, but OKF deliberately leaves its
vocabulary open. The topic-only and literal-duplication limits are therefore
Bitwild Profile conventions, not OKF requirements. A generic OKF consumer must
still tolerate an absent status, other producer-defined tags, and unknown type
values when it reads a bundle outside this Profile.

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
   concepts with a `superseded-by` relationship (2026.2: a `Superseded by` label), so the
   history stays inspectable. A migration that
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
for retirement, and mirrored material. It mechanically writes labelled links as
`relationships` entries (2026.2: reshapes malformed `# Relationships` entries),
but Profile Review decides path conformance, relationship meaning,
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
Consumers install the skills per that documented distribution and pin the tools; no
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

- the generator contract for its release (§3), if it writes indexes;
- the exit codes (§4.1), finding IDs (§4.2), the prohibitions (§4.3), and version dispatch
  (§4.4), if it validates;
- tolerant reading (profile §14.2) in both cases.

A tool MAY implement a subset — validation without generation is the common case — and
states which. Nothing here licenses a tool to reject a bundle that is valid OKF.

---

## 9. Change record

**2026.3.** Binds Profile 2026.3. Implements explicit `wayfinder.json`
release dispatch while preserving the 2026.2 in-bundle path. Affected sections:
§§2, 4.1, 4.4, 4.7–4.8, and 9. Driver: reusable Profile bindings,
reproducible source revisions, and removal of repeated in-bundle configuration.
It also adds `--output sarif` (§4.1), the same findings as a SARIF 2.1.0 log,
so CI can upload them to code scanning. Migration for implementations: add direct-source configuration, explicit
get/upgrade lock management, read-only validation of a selected Profile,
safe path and registry checks, and per-release index projection; retain legacy
dispatch and independent OKF results. Existing 2026.2 bundles remain
supported without edits.

Revised in place before publication: §3 makes 2026.3 indexes the output of
okf's reference generator, pins `okf` 0.5.0, replaces semantic comparison with
exact comparison for 2026.3, and adds `validate --fix`; the 2026.2 generator
contract and semantic comparison move unchanged to §3.4. Affected sections:
§§1, 2.1, 2.3, 3, and 8. Driver: Profile 2026.3 §9 now defers to okf's
generator. Migration for implementations: generate and compare 2026.3 indexes
with the pinned generator, and keep the 2026.2 projection for 2026.2 bundles.

Revised in place before publication: §§4.3 and 4.8 check the 2026.3
`relationships` frontmatter key and its declared names instead of the
`# Relationships` body section, accept the frontmatter keys a release declares,
and let a graph or search projection add relationship edges beside the OKF
graph without changing it; §4.7 adds relationship names to the binding
vocabulary, and §4.1 names `--fix` in the command surface. Affected sections:
§§4.1, 4.3, 4.7, 4.8, 5.5, and 9. Driver: Profile 2026.3 §7.2 moves typed
relationships into frontmatter. Migration for implementations: parse a
release's declared keys and relationship vocabulary, resolve relationship
targets as the OKF graph resolves links, and keep the body-section checks for
2026.2 bundles.

Revised in place before publication: §4.1 adds summary entries to the result
model beside the findings, as `profile.summary` in JSON, a `Summary:` text
block, and SARIF `note` results; §4.7 reports a registered custom type as a
summary entry. A graph that cannot be built is reported at `index.md`, which
every 2026.3 bundle has, instead of `profile.md`. Affected sections: §§4.1, 4.7,
and 9. Driver: Profile 2026.3 §14.1 now reports what it permits as summary
entries, and §5.1 checks colliding tag names where the binding declares them.
Migration for implementations: route a release's summary rules to the summary,
emit the new JSON key and SARIF notes, and reject a colliding tag declaration
while reading and composing the binding; 2026.2 output is unchanged.

Revised in place before publication: §§4.2, 4.4 and 4.7 read a non-base
source's rule catalog at its locked commit and evaluate the catalog chain,
base first, with each finding in its catalog's namespace; the lock is
unchanged. Affected sections: §§4.2, 4.4, 4.7, and 9. Driver: Profile 2026.3
§11 lets a non-base entry ship a rule catalog. Migration for implementations:
parse a named catalog whole and fail dispatch as `UNSUPPORTED` on anything the
engine lacks, keep the installed base catalog authoritative, and list every
catalog's descriptors in SARIF output.

**2026.2.** Binds Profile 2026.2. The Profile adopted the upstream OKF 0.2
revision in which every timestamp is an ISO 8601 datetime with an explicit UTC
offset, and moved the pinned specification to the canonical
`open-knowledge-format` repository. No guide contract changes: adoption,
the generator contract, the validation process contract with its release
dispatch, migration, and distribution are all unchanged. Release dispatch now
accepts `"2026.2"` as the supported release and reports any other declared
release as unsupported, which is the behavior §4 already specified. Migration
for an implementation is the release string alone; a bundle migration is the
optional `okf format --migrate-timestamps` pass the Profile's §15.3 describes.

**2026.1.** First release. Binds Profile 2026.1. Establishes adoption (§2), the
index generator contract (§3), the validation process contract (§4) with its
closed result model and release dispatch, the migration method (§5), and
distribution (§6). Cross-bundle references (§7) remain deferred, as the profile
leaves them. Amended in place when the okf toolchain released 0.2.0: §4.1's
OKF-component wording is restated over okf's finding contract (ADR-0008) — a
toolchain clarification, with the result model, exit codes, and rules
unchanged.

Titled *Implementation Guide* and filed under `implementation/`: the profile is
itself a specification, so a subordinate document called "the spec" would invert
the precedence it is trying to state. §1 states why "guide" does not mean
advisory.
