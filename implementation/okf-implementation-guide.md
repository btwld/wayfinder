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
behaviour the profile deliberately leaves open — for example, the Profile names
the `okf` release whose reference generator every index must match, while this
guide binds how a tool pins that release and detects drift from it.

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
   direct `bitwild-profile` Git source at `profiles/bitwild` and the explicit
   bundle path in its `applies_to` list. Resolve it with `wayfinder get` and
   commit the resulting metadata-only `wayfinder.lock`. Add only project-specific type, tag, and
   actor definitions that actual knowledge uses.
2. **Seed the bundle.** Create `index.md` carrying `okf_version: "0.2"` and
   `log.md` under `knowledge/`. The adoption skill's `SEEDING.md` carries the
   literal template. Once the bundle holds concepts, `wayfinder validate --fix` writes every index (§3.1).
3. **Write the repository's agent instruction paragraph.** `AGENTS.md` (or the
   equivalent) MUST say that durable documentation lives in the bundle, that
   the reader starts at `knowledge/index.md`, and that execution records stay
   in the tracker.

Adoption is not a migration. An existing 2026.2 bundle has no `wayfinder.json`,
so this engine cannot assess it (§4.4). It keeps validating on wayfinder 0.1.x
until it migrates to a project binding as Profile §15.3 describes.

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
generator (profile §9), and names the `okf` release that generator comes
from. This section binds the tools that write and check its output.

### 3.1 The reference generator (2026.3)

Profile 2026.3 §9 names the reference generator: `OkfIndexGenerator` in `okf`
0.5.0, run over the loaded bundle with the root index declaring
`okf_version: "0.2"`. A tool that writes or checks 2026.3 indexes MUST produce
exactly that release's generator text. Wayfinder builds with `okf` 0.5.0, but
its package constraint stays a caret range (`^0.5.0`) for library consumers,
so dependency resolution alone does not hold the release. Golden reports over
fixtures with generated indexes are the check: they fail when a resolved `okf`
release changes the generator's output, and adopting that release waits for
the Profile revision §9 requires.

A validator MUST report every path the generator writes whose file is missing
or whose text differs from the generated text. The comparison is exact apart
from line endings: the generator's rendering is the contract, so no
presentation is left to an implementation and no semantic normalization
applies. A CRLF line ending, which a checkout may write, compares equal to LF,
and `--fix` leaves such an index unchanged.

`wayfinder validate <bundle> --fix` is the safe fix, in the convention of
`eslint --fix` and `ruff --fix`. For a bundle whose selected Profile is
2026.3, it first writes the generator's output, then validates and reports as
usual. It MUST:

- **Write only generated `index.md` files**, and only those whose bytes differ.
  It never deletes a file: an `index.md` the generator does not write stays a
  finding until the author deletes it.
- **Write nothing when OKF fails** (`BLOCKED BY OKF`), when Profile dispatch
  fails, or when the selected release has no fixable rules. It reports why with the `wayfinder/fix-not-applied` warning
  diagnostic (§4.1).
- **Be idempotent.** A second run over its own output writes nothing.
- **Refuse to write through a symbolic link** at any path segment below the
  bundle root, and replace each file atomically.
- **Report a failed write.** When a write fails it stops, reports the files
  already written, and reports the failure as the `wayfinder/fix-failed` error
  diagnostic. A partly written bundle cannot pass the gate (§4.1).

When a fix ran, its JSON report adds `fix.written`, the bundle-relative paths
it wrote in path order, between `diagnostics` and `gate` (§4.1). Without
`--fix` the report is unchanged.

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

---

## 4. Validation

### 4.1 Results and exit codes

The command surface is `wayfinder validate <bundle> [--config <file>] [--fix]
[--output text|json|sarif]`; §3.1 defines `--fix`. The bundle path is required and implementations MUST
inspect exactly that directory. Config discovery MAY walk up to find the
project's `wayfinder.json`, but MUST NOT select a different bundle. They MUST NOT
accept a caller-selected Profile or rule set, or provide `--strict` or
another switch that promotes recommendations into requirements.

Text and JSON MUST expose three distinct results and the gate they derive:

| Result | Values |
| --- | --- |
| OKF conformance | `PASS`, `FAIL` |
| Profile assessment | `PASS`, `FAIL`, `BLOCKED BY OKF`, `NOT ASSESSED` |
| Diagnostics | a list, each entry at level `error`, `warning`, or `note` |
| Gate | `PASS`, `FAIL`, `INCOMPLETE` |

The independent OKF report MUST remain intact and Profile findings MUST NOT
reclassify it. The OKF component is okf's own report projection: one
canonically ordered findings array with namespaced identifiers and the
two-tier error/advisory severity model, in which a file that failed to load
is an error finding like any other. OKF conformance is `PASS` exactly when
that report holds no error-severity finding; the validator judges it
non-strict, so an OKF advisory never fails OKF conformance. If OKF fails,
deterministic Profile validation MUST stop as `BLOCKED BY OKF` without
cascading findings from partial content. `NOT ASSESSED` means no Profile was
selected, and an error diagnostic always says why.

A diagnostic is the engine reporting on its own run, never on the bundle. Its
`id` is `wayfinder/<code>` from a closed set the engine owns, so no Profile
package can declare, suppress, or reuse one. A diagnostic carries a `message`
and, when it has one, a `location` that is either a bundle-relative path or the project
configuration file as the caller named it. Configuration diagnostics say why
a Profile could not be selected or what the configuration adds to it.
Execution diagnostics say what the run could not do. Configuration
diagnostics are reported even when OKF fails, so one run names every problem
that blocks a complete assessment.

| Code | Level | Reported when |
| --- | --- | --- |
| `config-missing` | error | no `wayfinder.json` is found above the bundle |
| `config-invalid` | error | the configuration cannot be read |
| `bundle-unbound` | error | the configuration does not apply to the bundle |
| `profile-unresolved` | error | the lock is missing, stale, or lacks the bundle's chain, or a package is not in the local cache or disagrees with the release or parent the lock records |
| `profile-invalid` | error | a package in the chain is malformed, such as a schema violation, a bad id, a repeated name, an OKF frontmatter key, or rule examples that disagree with their check |
| `profile-unsupported` | error | a package in the chain is well-formed for another engine, with another `format`, an OKF release this okf cannot read, or a builtin this engine lacks; upgrading wayfinder is the remedy |
| `profile-composition` | error | the chain and the project additions do not compose (§4.7) |
| `project-type` | note | the configuration adds a type to the Profile types |
| `link-graph-unavailable` | error | the OKF link graph could not be built, so link rules were not assessed |
| `fix-failed` | error | a `--fix` write failed |
| `fix-not-applied` | warning | `--fix` was requested but did not run |
| `internal-error` | error | the run stopped before it had a result |

The gate is derived, never stored. It is `FAIL` when OKF fails or any Profile
finding is an error, because one witness proves non-conformance and missing
assessment cannot unfind it. Otherwise it is `INCOMPLETE` when any diagnostic
is an error, because a rule that did not run cannot pass. Otherwise it is
`PASS`, so a `PASS` always means every selected rule ran. Exit `0` means
`PASS`, exit `1` means `FAIL`, and exit `2` means `INCOMPLETE`, including
usage and I/O outcomes. Advisories, warnings, and notes MUST NOT change the
gate or exit status. The validator never assesses Judgment Rules, so no
result reports them and no output may claim they ran.

The result model also carries summary entries beside the findings. A
release's summary rules report what it permits (Profile §14.1), and their
entries MUST NOT appear among the findings or change any component state or
the exit status. JSON carries them as `profile.summary`, a canonically ordered
list whose entries have a finding's `id`, `message`, `location`,
`profile_release`, and `rule` but no `severity`; the list is present, even when
empty, whenever the assessed release declares a summary rule. Text prints a
`Summary:` block after the findings when there is an entry.

JSON carries the results as `okf`, `profile`, `diagnostics`, `gate`, and
`engine`, in that order, with `fix` between `diagnostics` and `gate` when a fix
ran (§3.1). `diagnostics` is always present, even when empty, and `gate` is
`{"state": ...}`. When a Profile was assessed, `profile` names it. Its `id`
and `release` are the bundle's own package, and `chain` lists every package the
run evaluated, root ancestor first, as `{id, release, commit}` with the
locked commit. An agent loads one Profile skill per `chain` entry. `engine` is `{"okf": "<version>"}`, the okf package version
the engine generates indexes with, so a byte change in generated output reads
as an engine upgrade rather than a Profile change. A finding or summary entry
whose package names `docs` carries `help_uri`, that URI with the fragment set
to the rule id. Text prints a `Diagnostics:` block after the summary when
there is one, and ends with `Gate:` and the gate's value. When `--output` is
`json` or `sarif` and the run stops before it has a result, the output is
still a parseable result. It holds only the `wayfinder/internal-error`
diagnostic and the `INCOMPLETE` gate, so a machine reader never mistakes
empty output for a pass. Its SARIF log has no rule descriptors and no
results, carries the diagnostic as its one execution notification, and has
only `gate` among the run properties, because no OKF or Profile result
exists.

`sarif` carries the same findings as JSON in a SARIF 2.1.0 log for code
scanning. Each OKF and Profile finding is one result whose `ruleId` is its
finding ID; `error` maps to SARIF `error` and `advisory` to `warning`. Each
summary entry follows the findings as a result of kind `informational` with
level `none`, as SARIF §3.27.10 requires for a kind other than `fail`.
The selected chain's rules are the run's rule descriptors, each with a
`helpUri` when its package names `docs`. The okf package version is a
`tool.extensions` entry named `okf`. Each diagnostic
is a notification on the run's invocation, in `toolConfigurationNotifications`
or `toolExecutionNotifications` by its kind, with one `driver.notifications`
descriptor per code reported. `executionSuccessful` is `false` exactly when a
diagnostic is an error. The OKF state, Profile id and release, Profile
state, and gate are run properties because SARIF has no field for them. The exit status is the same
as for text and JSON.

### 4.2 Findings carry stable identifiers

Every deterministic Profile finding MUST carry a stable machine-readable ID
alongside its prose, `<namespace>/<rule-slug>`, where the namespace is the
`id` of the package that declares the rule, such as `bitwild-profile`
(Profile §11). It MUST name the release of the package that assessed it. The ID
MUST describe the semantic rule rather than a section number, implementation
class, or message text, so integrations can depend on it across refactoring.

The closed validator MUST NOT accept suppressions or exceptions. A bundle cannot
change the rules its project binding selects, and a caller cannot
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

Profile 2026.3 checks the selected binding's actor lookup under its §6.1.1.
The check never rejects the concept as invalid OKF, alters its actor string, or changes its
derived trust tier.

Validation MUST keep syntax separate from contextual truth. It checks required
metadata presence and shape, release-specific standard type definitions and
used-type registration, actor side membership, source structure, unique
source IDs, and recognized attribution joins. A footnote is source attribution only when its label matches a
declared source ID; ordinary Markdown footnotes are not findings. It MAY expose
organizational affiliation; when it does, it MUST resolve the applicable actor
record through Profile §6.1.1. Unresolved or ambiguous affiliation remains `unknown`
and MUST NOT produce a finding. Validation MUST leave durable-capture boundaries,
type and registered-meaning fit (Profile §§5.1–5.2, §14.1),
metadata truth, actor identity and affiliation, missing material provenance,
evidence for freshness, and semantic tag aliases to Profile Review. Missing
`generated` produces an advisory and missing `verified` produces no finding. A
registered project-specific type produces the `wayfinder/project-type` note
diagnostic (§4.1, Profile §5.2).

For external boundaries, validation MUST assess the shape and vocabulary
requirements Profile §7.2 places on the `relationships` frontmatter key as
deterministic rules. It MUST resolve each `resource` exactly as the OKF graph
resolves a link target, and report a non-bundle-relative internal target as an
advisory and an unresolved internal target as a summary entry (Profile §§7.2,
14.1). A non-bundle-relative internal link is an advisory and an unresolved
internal link is a summary entry. Neither affects the gate or exit status, and validation MUST preserve the unresolved
edge exposed by the OKF graph. It MUST NOT infer
relationship meaning, lifecycle ownership, path conformance, whether a date is
intrinsic identity, or whether an external citation can be repaired. The complete
path rule belongs to Profile Review because a preserved external ID has no
Profile-specific syntax that separates it mechanically from the authored slug.

The implementation MUST use the ordinary OKF graph and MUST NOT enrich,
reinterpret, or replace its edges. An implementation that projects a graph or expands search context MAY read each `relationships`
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

A validator MUST dispatch through `wayfinder.json` alone. For a bundle named
by exactly one `applies_to` path, it follows the lock's `extends` pointers
from that entry's id to the root, reads each package from the local cache at
its locked commit, and dispatches on each package's `format`, which MUST be
`2`, the package format this engine reads. A Profile's `release` is its own
name and never selects engine behavior. The chain need not reach any base
Profile. The engine verifies safe paths, each package's OKF binding, and that
the chain composes (§4.7). A package is data the engine evaluates, read from
the cache at the locked commit, never from the network.

A bundle with no `wayfinder.json` above it leaves the Profile `NOT ASSESSED`
with the `wayfinder/config-missing` diagnostic and exit `2`. A bundle that an
existing `wayfinder.json` does not list gets `wayfinder/bundle-unbound` the
same way. A file in the bundle never selects a Profile, so a 2026.2 in-bundle
declaration changes neither outcome. A 2026.2 bundle therefore validates on wayfinder
0.1.x or migrates to a project binding as Profile §15.3 describes; one engine
carries one dispatch path, not a frozen copy of every release.

An explicit `--config` path MUST exist and name the requested bundle. A
package this engine cannot read leaves the Profile `NOT ASSESSED` with the
`wayfinder/profile-unsupported` diagnostic and exit `2`, preserving any
independent OKF result. A malformed or unreadable selector also prevents
dispatch, with the configuration diagnostic §4.1 names. The
validator MUST NOT silently apply the newest rules or reinterpret an old bundle
because a neighboring project config exists. Generic OKF reading remains
available even when Profile dispatch fails.

### 4.5 Where it runs

A validator SHOULD run in CI on any change touching the bundle. One `wayfinder
validate <bundle>` invocation is the complete model-independent gate; a
separate OKF command MAY still be useful for focused upstream diagnostics.
CI MUST NOT treat `INCOMPLETE` as a pass, and MUST NOT claim that Judgment
Rules or Complete Profile Assessment ran.

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

This subsection implements Profile §11. The project configuration and Profile package shapes are described by
[`wayfinder.schema.json`](../docs/schemas/wayfinder.schema.json) and
[`wayfinder-profile.schema.json`](../docs/schemas/wayfinder-profile.schema.json).
A version-1 project file has **one** form: direct Profile sources and the bundle
paths they apply to. It has no `bundles`, `implements`, or `default_bundle` key.

```json
{
  "version": 1,
  "profiles": {
    "bitwild-profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "main",
        "path": "profiles/bitwild"
      },
      "applies_to": ["./knowledge"],
      "types": [
        {"name": "Project Note", "description": "A project-specific durable note"}
      ]
    }
  }
}
```

The map key is the package `id`, not an alias. A Profile is one package file,
`wayfinder-profile.json`, at `source.path` in the locked revision. It carries
the package `format`, the Profile's own `release`, its OKF binding, its
vocabulary (`types`, `tags`, `relationships`, `frontmatter_keys`), and its
`rules`, in the shape `wayfinder-profile.schema.json` publishes. One parser
reads every package, Bitwild's included; the engine embeds no Profile and
holds no installed rules. A package whose `id` differs from its map key is
invalid.

A package names its own parent in `extends`; a project entry never wires a
chain, so a Profile means the same thing in every project that uses it. A
parent without `git`, `{"path": ...}`, is the package at that
repository-root-relative path in the same repository at the same commit as
the child, so Profiles hosted together release together. A parent with
`git`, `{"git", "ref", "path"}`, resolves from its own repository and ref;
its `git` is a URL or an absolute path, never a path relative to one
project. The chain need not reach any base Profile. A child inherits its
ancestors' packages and adds its own, but cannot replace inherited names or
change an inherited rule. A cycle fails `get`. Every entry applies to at
least one bundle, and ambiguous bundle application fails Profile dispatch.
Types, topic tags, relationship names and actor lookup are the only project
additions; a project entry cannot declare frontmatter keys or rules. A
registered custom type is reported as the `wayfinder/project-type` note
diagnostic (§4.1); contextual meaning belongs to Profile Review.

The engine composes the chain and the entry's project additions into one
effective Profile before evaluating anything. Composition depends on nothing
else, so the same inputs always compose the same way. A type, tag, or
relationship name MUST be unique across the chain and the project
additions; a frontmatter key MUST be unique along the chain; a tag MUST NOT
equal a type, an OKF status, an OKF trust tier, or a relationship name. Every
package in a chain binds to the one OKF release the engine reads, which the
package parser enforces before composition. A violation is a
composition error. `get` composes every entry's chain before it writes the
lock, so it reports the error and leaves the lock as it was; `validate`
reports it as the `wayfinder/profile-composition` diagnostic. A project entry that repeats one
of its own names is still a configuration error (`config-invalid`).

Validation evaluates the rules of every package in the chain, parent first,
and each finding names its package's `id` as namespace and its package's
`release`, so an ancestor's findings never depend on a child. A malformed
package reports `wayfinder/profile-invalid`; a package well-formed for
another engine, through another `format`, an OKF release this okf cannot
read, or a builtin this engine lacks, reports `wayfinder/profile-unsupported`.
`get` fails with the same reason, and `validate` leaves the Profile `NOT
ASSESSED`. A package is never partially applied.

A relative local `source.git` is resolved from the directory containing
`wayfinder.json`, not the process working directory. Cache identity uses that
resolved location; the lock preserves the declared source spelling. A
drive-relative path is invalid.

`get` resolves every entry's chain and writes `wayfinder.lock` atomically.
The lock is flat. Its `packages` map holds each Profile id's `source`,
`requested_ref`, `resolved_commit`, `path`, `release`, and, for a child,
`extends`, the parent's id. A project locks **one revision per Profile id**,
so an id names one ruleset and one finding namespace everywhere in it.
`get` checks that when it adds each package, and two chains that need
different revisions of one id fail with both refs named. `get` converges.
With an unchanged configuration, lock and cache, it fetches nothing and
leaves the lock's bytes alone. `upgrade` deliberately refreshes mutable refs.
A canonical-JSON hash invalidates the lock on semantic config changes, not
formatting changes; an unchanged source retains its locked commit during
`get`. The lock contains revision metadata, never project knowledge,
credentials, vocabulary or rules. The local Git cache holds fetched
objects.
If a current lock's selected commit is absent, a read-only command does not
substitute the current branch tip: run `get` to recover the exact commit or
`upgrade` to select a new revision deliberately. Failed resolution leaves the
previous lock intact.

Validation operates on **one explicit bundle**. The implementation first
inspects it under OKF 0.2. A failing OKF result blocks Profile assessment but
is never reclassified. It parses the selected project config, whose
diagnostics are reported even when OKF fails, checks safe
path/identity/release and reads only the selected Profile chain from a
current lock/cache, checking each package's `release` and parent against
the lock. Missing or stale source state leaves
the Profile `NOT ASSESSED` with the `wayfinder/profile-unresolved` diagnostic
alongside the independent OKF report; neither
CLI `validate` nor read-only MCP `validate` fetches or writes a lock. The
configured Profile then checks the root `index.md` `okf_version: "0.2"`,
standard and custom type/tag/actor references, and the other deterministic
Profile rules. An ancestor project config that does not list the bundle never
applies to it silently (§4.4). Unknown releases never fall back to the newest
rules.

`graph` projects the ordinary OKF graph, plus the `relationships` edges §4.3
permits, without Profile-source resolution.
Embedding `index` and `search` likewise consume the explicit bundle without
resolving unused Profile sources; they do not generate Profile navigation
indexes. A neighboring malformed `wayfinder.json` cannot make ordinary OKF
graph reading fail. Those command boundaries implement the separate outcomes
required by Profile §§14.1–14.2.

The parser checks `wayfinder.json` and each Profile package against their
published JSON Schemas, evaluated by the engine's own schema subset and
embedded in the binary, then runs the cross-document checks a schema cannot
express. Those cover normalized and canonical paths, package parents, package
identity, rule tests, composition of the effective vocabulary, and actor
lookup. A schema alone cannot prove filesystem safety, Git availability, or whether a concept
truthfully uses a type or topic tag. `captures/` remains outside the
bundle unless explicitly declared as another OKF bundle; no nested area
inherits a different Profile.

### 4.8 Frontmatter fields and type-specific constraints

Validation has two layers of frontmatter checking. The
upstream `okf` package validates the pinned OKF 0.2 field shapes and preserves
unknown content for tolerant reading. The Bitwild Profile adds only its
bundle conformance constraints:

| Field or family | Coverage |
| --- | --- |
| `type` | Required non-empty string; membership in the selected Profile's standard types plus binding custom types |
| `title`, `description` | Required non-empty strings |
| `status` | Required string with `draft`, `stable`, or `deprecated`, unless a future Profile release explicitly changes it |
| `tags` | Bitwild 2026.3 declares the actual Profile and project tag vocabulary in JSON, rejects duplicate declarations and duplicate values within one concept, reports an undeclared used tag according to the release rule, and rejects at composition a declared tag name that collides with another declared vocabulary (Profile §5.1) |
| `generated`, `verified`, `stale_after` | OKF shape and timestamp diagnostics with upstream meanings; no Profile-specific fields for trust or freshness |
| `sources` | OKF shape plus source-entry, unique-ID, attribution-join, and path diagnostics, run after binding resolution |
| `relationships` | The one key the release declares (Profile §7.2): a list of `relationship` and `resource` mappings, checked for shape, declared names, and target resolution |
| Other frontmatter keys | Keys neither OKF nor a package in the chain declares fail; a project entry cannot declare frontmatter keys |

Any package declares its additional frontmatter keys in its
`frontmatter_keys` list, each with the sentence that defines it. Keys are
unique along the chain, and `frontmatter-fields-declared` accepts exactly
OKF's keys and those the chain declares. OKF §4.1 permits producers
additional keys, but a declared key MUST NOT be one OKF 0.2 defines or
redefine an OKF field, so the engine rejects at load a package that declares
an OKF key, and the compatibility review records each declared key.
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
packages in the selected chain declare their tags and the project binding adds
project tags. Wayfinder MUST reject duplicate names within either list and
collisions between the lists, reject duplicate values within one concept, and
apply the selected Profile release's explicit rule for an undeclared used tag.
For Bitwild 2026.3, an undeclared used tag is an error; a Profile that needs an
open vocabulary must state that as a different release rule. Relationship names
follow the same model: each package's `relationships` list declares its
names, the binding adds project names under the same duplicate and
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
   concepts with a `superseded-by` relationship, so the
   history stays inspectable. A migration that
   drops what was replaced destroys the record of how understanding moved.

Before editing, a migration MUST inventory missing baseline metadata, used and
standard types, producer-defined fields, actor history, tags, and materially
derived claims. Mechanical normalization may declare used project types in the
binding and reshape supported syntax; it MUST NOT guess a title,
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
`relationships` entries, but Profile Review decides path conformance, relationship meaning,
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
- **The tools must be pinned per repository and dispatch on the release `wayfinder.json`
  selects** (§4.4), so repositories on different profile releases can share one
  implementation.

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
block, and SARIF `informational` results; §4.7 reports a registered custom type as a
summary entry. A graph that cannot be built is reported at `index.md`, which
every 2026.3 bundle has, instead of `profile.md`. Affected sections: §§4.1, 4.7,
and 9. Driver: Profile 2026.3 §14.1 now reports what it permits as summary
entries, and §5.1 checks colliding tag names where the binding declares them.
Migration for implementations: route a release's summary rules to the summary,
emit the new JSON key and SARIF informational results, and reject a colliding tag declaration
while reading and composing the binding; 2026.2 output is unchanged.

Revised in place before publication: §§4.2, 4.4 and 4.7 read a non-base
source's rule catalog at its locked commit and evaluate the catalog chain,
base first, with each finding in its catalog's namespace; the lock is
unchanged. Affected sections: §§4.2, 4.4, 4.7, and 9. Driver: Profile 2026.3
§11 lets a non-base entry ship a rule catalog. Migration for implementations:
parse a named catalog whole and fail dispatch as `UNSUPPORTED` on anything the
engine lacks, keep the installed base catalog authoritative, and list every
catalog's descriptors in SARIF output.

Revised in place before publication: Profile 2026.3 §9 now names the
generator's `okf` release, so §§1 and 3 cite it there and keep only how a tool
pins that release and detects drift from it, and §3.1 states that `--fix`
never deletes a leftover index. §4.3 reports a registered project type and an
unresolved internal link or relationship target under 2026.3 as summary
entries, as §4.1 and Profile §14.1 already did, and cites Profile §7.2 for the
relationship shape instead of restating it; §4.8 states that a colliding tag
declaration fails at configuration. Affected sections: §§1, 3, 3.1, 4.3, 4.8,
and 9. Driver: a guide that pinned the release decided which index bytes
conform, which is a bundle rule the Profile owns; §§4.3 and 4.8 still
described the advisories and per-concept tag check that the summary-entry
revision replaced.
Migration for implementations: none; the release and the checks are
unchanged.

Revised in place before publication: §4.1 replaces the four result components
with OKF, Profile assessment, diagnostics, and a derived gate. The engine's own
reports become `wayfinder/*` diagnostics: release dispatch problems, the
project-type note, a link graph that cannot be built, `--fix` failure or
refusal, and a run that stopped. They are no longer Profile findings, summary
entries, or fix states. Profile state `UNSUPPORTED` becomes `NOT ASSESSED`,
gate `UNSUPPORTED` becomes `INCOMPLETE`, and the Judgment Rules component is
removed because no validator assesses it. SARIF reports diagnostics as
invocation notifications. Affected sections: §§3.1, 4.1, 4.3, 4.4, 4.5, 4.7,
and 9. Driver: a link graph failure let link rules pass unassessed, and engine
failures dressed as rules could not be told apart from bundle findings.
Migration for implementations: emit `diagnostics` and `gate`, derive the gate
from OKF, error findings, and error diagnostics, and drop `judgment_rules` and
`automated_gate`. A bundle is affected only where its result relied on a
removed rule id or on a graph failure being a `FAIL`; it is now `INCOMPLETE`.

Revised in place before publication: the engine dispatches only through
`wayfinder.json`. §4.4 drops the root `profile.md` selector, so a bundle with
no `wayfinder.json` above it gets the `wayfinder/config-missing` diagnostic
and the `INCOMPLETE` gate whatever its root files say. §3.4's 2026.2
projection and the 2026.2 rows, columns, and asides elsewhere are removed.
Affected sections: §§2.1, 3, 3.1, 3.4, 4.1, 4.2, 4.3, 4.4, 4.7, 4.8, 5.5, 6,
and 9. Driver: the maintainers chose a clean break so the engine carries no
Profile-specific legacy code; the 2026.2 declaration path was what kept
in-bundle registries and frozen 2026.2 rules in the engine. Migration for
implementations: delete the in-bundle declaration reader and the 2026.2 rules,
and report an unconfigured bundle as `config-missing`. A 2026.2 bundle keeps
validating on wayfinder 0.1.x, or migrates to a `wayfinder.json` binding as
Profile §15.3 describes. No configured bundle is affected.

Revised in place before publication (2026-10-02): the engine embeds no
Profile. A Profile is one package file, `wayfinder-profile.json` in package
format 2, read by one parser for every Profile; the separate manifest and
rule catalog are gone, `standard_types` is `types`, and `frontmatter_keys` is
a list any package may declare. There is no base Profile, so a chain need not
reach Bitwild. Bitwild's package is `bitwild-profile` at `profiles/bitwild/`,
and its findings are `bitwild-profile/*`. Builtins are engine capabilities
with params, named for what they check: `files-present`,
`path-targets-exist`, and `matches-generated`. The per-rule `ref` is removed;
a package's `docs` URI yields each finding's `help_uri` in JSON and `helpUri`
in SARIF. JSON adds `engine.okf` and SARIF a `tool.extensions` entry naming
the okf version used to generate indexes. The new rule
`bitwild-profile/root-index-lists-log` requires the root index of a bundle
with no concepts to link only `log.md`. Composition collisions become the
`wayfinder/profile-composition` diagnostic, and `wayfinder/profile-invalid`
joins the closed set. Affected sections: §§2.1, 4.1, 4.2, 4.4, 4.7, 4.8, and
9. Driver: an engine that embedded one Profile and required every chain to
reach it could not assess a Profile that stands alone, such as one a second
knowledge base ships, and a change in generated output could not be told
apart from a Profile change. Migration for implementations: parse format 2
packages through one boundary, compose the chain before evaluating it, report
the new diagnostics, and emit `help_uri`, `helpUri`, and `engine.okf`. A
configured bundle must rename its `wayfinder.json` key to `bitwild-profile`,
point `source.path` at `profiles/bitwild`, and run `wayfinder get`; its
finding ids change namespace from `concepta-profile/*` to
`bitwild-profile/*`.

Revised again in place before publication (2026-10-02): composition lives in
the package. A package names its parent in `extends`, either at the same
revision (`{"path"}`) or at its own (`{"git", "ref", "path"}`), and
`wayfinder.json` loses `extends`; every entry applies to at least one bundle.
The lock's `profiles` map becomes a flat `packages` map keyed by Profile id,
each entry with `release` and an optional `extends`, holding one revision per
id. `get` composes each chain before writing the lock and leaves an unchanged
lock's bytes alone. JSON `profile` adds `id` and `chain`, and SARIF adds the
`profile_id` run property. Affected sections: §§4.1, 4.4, 4.7, and 9.
Driver: a Profile whose parent each consumer wired could mean different
things in different projects, so a Profile's own guidance could not be
written against a fixed parent. Migration for implementations: read
`extends` from the package, lock `packages`, and select a bundle's chain by
the lock's `extends` pointers. A configured bundle whose `wayfinder.json`
used `extends` names only the child entry, moves the parent into the child
package's `extends`, and runs `wayfinder get`; an older lock is rewritten.

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
