# Wayfinder implementation guide

The engine contract for Profile package format **2** and **OKF 0.2 exactly**.

Status: Proposed

---

## 1. Purpose and precedence

Wayfinder checks an OKF bundle in two independent steps. It runs okf's own
validation first, then the rules of the Profile the project selects. A
Profile is a package of vocabulary and rules that adds requirements to OKF
(§5). This guide is the engine contract. It says what a Profile package is,
how the engine selects and evaluates one, what results it reports, and how
tools that generate, validate, and adopt bundles behave.

Precedence is a chain, and every link is one-directional:

> **OKF** wins over the **engine contract**, which wins over each **Profile package**.

The engine contract is this guide plus the JSON Schemas it publishes under
[`docs/schemas/`](../docs/schemas/). A Profile package can add rules within
what the contract allows (§5.3). It can never change OKF or the contract.
This guide holds no Profile's rules. Bitwild, the first Profile, appears here
only as an example; its own rules, rationale, and history live in
[`profiles/bitwild/`](../profiles/bitwild/README.md).

Conformance means what a tool decides, never what a reader infers. A bundle
conforms to OKF when okf reports no error. A bundle conforms to a Profile when
`wayfinder validate` with that Profile selected ends with the gate `PASS`
(§4.1). No prose adds a requirement that the validator does not check. A
Profile's rationale and its skill explain and guide; they are not conformance
requirements (§5.1).

**"Guide" does not mean advisory.** The requirements below carry their RFC
2119 force. They constrain programs and packages, not bundles. "A generator
MUST be idempotent" constrains a tool; "a package MUST NOT declare an OKF key"
constrains a Profile author. A bundle meets the rules of the Profile it
selects, read the way this guide says.

The audience is whoever writes a tool, writes a Profile, or stands up a
repository. That is a handful of people per project, and they read it once.

**Conventions.** MUST, MUST NOT, SHOULD, and MAY carry their RFC 2119 senses.
"Tool" means any program that reads or writes a bundle. "Bundle" means the
directory a `wayfinder.json` entry names in `applies_to`.

---

## 2. Adoption

### 2.1 What a repository does

Adopting a Profile creates one project binding, two bundle root files, and
one agent-instruction paragraph, in this order:

1. **Select the Profile.** Write `wayfinder.json` at the project root with one
   entry keyed by the Profile's id. Give it the Profile's Git source and the
   explicit bundle path in `applies_to` (§4.7). Bitwild's entry is keyed
   `bitwild-profile` with `path` `profiles/bitwild`. Resolve it with
   `wayfinder get` and commit the metadata-only `wayfinder.lock` and the
   Profile skill directories `get` installs. Add only project-specific types,
   tags, relationship names, and actors that actual knowledge uses.
2. **Seed the bundle.** Create `index.md` declaring the package's OKF release
   as `okf_version`, and `log.md`. A Profile's skill may carry literal
   templates in its adoption guidance. The adoption skill's `SEEDING.md`
   carries OKF's own for a Profile without them. Once the bundle holds
   concepts, `wayfinder validate --fix` writes every generated index (§3.1).
3. **Write the repository's agent instruction paragraph.** `AGENTS.md` (or the
   equivalent) MUST say that durable documentation lives in the bundle and
   that the reader starts at its root `index.md`. A Profile's adoption
   guidance may add to it. Bitwild's adds that execution records stay in the
   tracker.

Adoption is not a migration. A bundle with no `wayfinder.json` above it
cannot be assessed (§4.4). A bundle that used the Bitwild 2026.2 in-bundle
selector keeps validating on wayfinder 0.1.x until it migrates, as the
[Bitwild changelog](../profiles/bitwild/CHANGELOG.md) describes.

**Create no directories during seeding.** A Profile may name optional
directories. Bitwild names five. A subject directory is created only when the
repository's actual knowledge gives the adopter enough context to place it.
Setup has none and MUST NOT predict it.

### 2.2 What adoption does not include

A repository does **not** migrate its existing documents as part of adoption.
Adoption gives new knowledge a home. Converting old knowledge is a separate,
scheduled piece of work that follows the selected Profile's own guidance, such
as Bitwild's [migration reference](../profiles/bitwild/skill/references/migration.md).
A repository MAY run for months with a thin bundle beside an unconverted
`docs/` tree, provided §2.1's paragraph says which is authoritative for what.

### 2.3 Definition of done

Adoption is complete when a validator run ends with the gate `PASS`, every
generated index is current, and someone who has never seen the repository can
find the authoritative home for a new decision without asking. The third is
the real test and it is not mechanical.

---

## 3. Index generation

A Profile can require every index to be okf's generated output by naming the
`matches-generated` builtin with `generator: "okf-index"` (§5.6). Bitwild
does. This section binds the tools that write and check that output.

### 3.1 The reference generator

The `okf-index` generator is `OkfIndexGenerator` from the `okf` release the
engine depends on, run over the loaded bundle with the root index declaring
the package's `implements.release` as `okf_version`. A tool that writes or
checks those indexes MUST produce exactly that generator's text. Wayfinder
pins `okf` to the 0.5.0 release (`>=0.5.0 <0.5.1`, the narrowest constraint
pub accepts for a published package) and reports the version it used as JSON
`engine.okf` and a SARIF `tool.extensions` entry (§4.1). Golden reports over
fixtures with generated indexes fail when a resolved `okf` release changes
the generator's output. The generated text is engine contract, so §5.6 says
what an engine release that changes it owes its users.

A validator MUST report every path the generator writes whose file is missing
or whose text differs from the generated text. The comparison is exact apart
from line endings: the generator's rendering is the contract, so no
presentation is left to an implementation and no semantic normalization
applies. A CRLF line ending, which a checkout may write, compares equal to LF,
and `--fix` leaves such an index unchanged.

`wayfinder validate <bundle> --fix` is the safe fix, in the convention of
`eslint --fix` and `ruff --fix`. When a rule in the selected chain uses
`matches-generated`, it first writes the generator's output, then validates
and reports as usual. It MUST:

- **Write only generated `index.md` files**, and only those whose bytes differ.
  It never deletes a file: an `index.md` the generator does not write stays a
  finding until the author deletes it.
- **Write nothing when OKF fails** (`BLOCKED BY OKF`), when no Profile is
  selected, or when the selected chain has no fixable rule. It reports why
  with the `wayfinder/fix-not-applied` warning diagnostic (§4.1).
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

A validator checks the result a generator maintains. A repository
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
| `profile-composition` | error | the chain and the project additions do not compose (§5.7) |
| `profile-skill-stale` | warning | a chain member ships a skill whose installed copy is missing or not at the locked commit (§4.7) |
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
gate or exit status. The validator assesses a Profile's rules and nothing
else. Guidance in a Profile's skill is never assessed, so no output may claim
it was.

The result model also carries summary entries beside the findings. A rule of
severity `note` reports something its Profile permits but wants visible, such
as Bitwild's unresolved internal link. Its entries MUST NOT appear among the
findings or change any component state or the exit status. JSON carries them
as `profile.summary`, a canonically ordered list whose entries have a
finding's `id`, `message`, `location`, `profile_release`, and `help_uri` but
no `severity`. The list is present, even when empty, whenever the selected
chain declares a `note` rule. Text prints a `Summary:` block after the
findings when there is an entry.

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
(§5.4). It MUST name the release of the package that assessed it. The ID
MUST describe the semantic rule rather than a section number, implementation
class, or message text, so integrations can depend on it across refactoring.

The closed validator MUST NOT accept suppressions or exceptions. A bundle cannot
change the rules its project binding selects, and a caller cannot
change them through command options or repository configuration.

### 4.3 What a validator must never report

The engine, its builtins, and its diagnostics MUST NOT report, at any
severity:

- a concept with no `verified` event, or any derived trust tier;
- an external URL that does not resolve;
- a concept using an OKF mechanism that no rule in the selected chain names;
- an unknown type, tag, relationship name, or actor as invalid OKF.

Only a Profile rule reports vocabulary, and it reports a Profile finding.
A Profile package MUST NOT contain a rule that reports either of the first
two items (§5.3). The first matters most. The only way an author can clear a
"missing verification" report is to record a verification that did not
happen, which turns a diagnostic into a corruption of OKF's evidence model.

A tool MAY summarize trust tiers and organizational provenance. A summary
MUST NOT affect exit status.

Validation keeps syntax separate from contextual truth. A rule decides from
the bundle, the packages in the chain, and the project binding. It never
decides whether a type fits a concept, whether metadata is truthful, or
whether a placement is right. Those are judgment, and a Profile carries
judgment in its skill (§5.1). A rule that reports a frontmatter key no
package declares does not break tolerant reading. The engine still loads the
concept, keeps the unknown key, and leaves the OKF result unchanged. Tolerant
reading governs consumers. A Profile rule governs what that Profile's
producers write.

The implementation MUST use the ordinary OKF graph and MUST NOT enrich,
reinterpret, or replace its edges. An implementation that projects a graph
or expands search context MAY read each `relationships` entry as an
additional edge named by its relationship and resolved as the OKF graph
resolves a link target (§5.5). OKF's nodes and edges and their meanings stay
unchanged. A graph output adds such edges under a key of its own, never
inside OKF's edge list, so a consumer of the OKF graph contract reads it
unchanged.

Validation MUST NOT probe the network. An external resource that no longer
resolves remains ordinary OKF provenance or a body link.

### 4.4 Version dispatch

A validator MUST dispatch through `wayfinder.json` alone. For a bundle named
by exactly one `applies_to` path, it follows the lock's `extends` pointers
from that entry's id to the root, reads each package from the local cache at
its locked commit, and dispatches on each package's `format`, which MUST be
`2`, the package format this engine reads. A Profile's `release` is its own
name and never selects engine behavior. The chain need not reach any
particular Profile. The engine verifies safe paths, each package's OKF
binding, and that the chain composes (§5.7). A package is data the engine evaluates, read from
the cache at the locked commit, never from the network.

A bundle with no `wayfinder.json` above it leaves the Profile `NOT ASSESSED`
with the `wayfinder/config-missing` diagnostic and exit `2`. A bundle that an
existing `wayfinder.json` does not list gets `wayfinder/bundle-unbound` the
same way. A file in the bundle never selects a Profile, so a Bitwild 2026.2
in-bundle declaration changes neither outcome. Such a bundle validates on
wayfinder 0.1.x or migrates to a project binding as the
[Bitwild changelog](../profiles/bitwild/CHANGELOG.md) describes. One engine
carries one dispatch path, not a frozen copy of every Profile release.

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
CI MUST NOT treat `INCOMPLETE` as a pass, and MUST NOT present a Profile
skill's guidance as checked.

### 4.6 Compatibility evidence

[`docs/compatibility-review.md`](../docs/compatibility-review.md) records the
engine's review against its `okf` package and the pinned OKF specification.
It answers whether the engine keeps OKF's result and meaning intact. Each
Profile records the OKF review of its own rules and declared keys in its
changelog (§5.10).

### 4.7 Project binding and lock

[`wayfinder.schema.json`](../docs/schemas/wayfinder.schema.json) describes the
project configuration, and §5 describes the package it points at. A
version-1 project file has **one** form: direct Profile sources and the
bundle paths they apply to. It has no `bundles`, `implements`, or
`default_bundle` key.

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

The map key is the package `id`, not an alias, and a package whose `id`
differs from its key is invalid. `source.path` names the package directory in
the locked revision. Types, topic tags, relationship names, and actor lookup
are the only project additions. A project entry cannot declare frontmatter
keys or rules, and it never wires a chain, because a package names its own
parent (§5.7). A project that needs its own rules writes a package, which can
live in the same repository. A registered project type is reported as the
`wayfinder/project-type` note diagnostic (§4.1). Whether the type fits its
concepts is judgment for the Profile's skill.

Every entry applies to at least one bundle. `applies_to` paths MUST be
relative, unique, inside the project after symlink resolution, and not nested
within one another. Several bundles MAY share an entry. A directory inside a
bundle inherits that bundle's Profile and never selects another, and
ambiguous bundle application fails Profile dispatch. `wayfinder.json` and
`wayfinder.lock` are project configuration at the project root, never OKF
concepts. A bundle sits strictly inside the project, so the engine never reads
its configuration from inside a bundle or writes it into an `index.md`.

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

A package MAY name its agent skill directory in `skill`, relative to the
package. After writing the lock, `get` and `upgrade` install each locked
package's skill from its locked commit into `.claude/skills/<id>/` and
`.agents/skills/<id>/` under the project root, with a `.wayfinder-profile`
marker recording `{id, release, commit}`. The skill therefore always matches
the rules it accompanies. Only regular files at paths inside the skill are
installed, and the skill MUST hold `SKILL.md`; anything else fails `get`. Each directory is replaced by
renaming a staged sibling into place. A directory whose marker already names
the locked revision is not rewritten, so `get` still converges. `get` MUST
NOT replace or remove a directory without a marker for its id, and fails
before writing the lock when one is in the way. It removes a marked directory
whose Profile no longer ships a skill or is no longer locked. Projects commit
the installed directories, so agents without wayfinder read the same skill.
`validate` reads each chain member's marker without writing; a missing
directory or a marker for another revision is the `wayfinder/profile-skill-stale`
warning (§4.1), which never changes the gate.

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
engine then evaluates every rule in the chain (§5.6). An ancestor project
config that does not list the bundle never applies to it silently (§4.4).
An unknown package never falls back to the newest rules.

`graph` projects the ordinary OKF graph, plus the `relationships` edges §4.3
permits, without Profile-source resolution.
Embedding `index` and `search` likewise consume the explicit bundle without
resolving unused Profile sources; they do not generate Profile navigation
indexes. A neighboring malformed `wayfinder.json` cannot make ordinary OKF
graph reading fail. Those command boundaries keep OKF reading independent of
Profile selection (§5.2).

The parser checks `wayfinder.json` and each Profile package against their
published JSON Schemas, evaluated by the engine's own schema subset and
embedded in the binary, then runs the cross-document checks a schema cannot
express. Those cover normalized and canonical paths, package parents, package
identity, rule tests, composition of the effective vocabulary, and actor
lookup. A schema alone cannot prove filesystem safety, Git availability, or
whether a concept truthfully uses a type or topic tag. A directory beside the
bundle, such as a `captures/` directory, stays outside it unless a binding
names it as another bundle.

### 4.8 Frontmatter fields and type-specific constraints

Frontmatter is checked in two layers. The `okf` package validates the pinned
OKF 0.2 field shapes and keeps unknown content for tolerant reading. The rules
of the selected chain then add each Profile's constraints, such as Bitwild's
required `status`. §5.5 says which frontmatter keys a package may declare.

The engine has no type-specific property schema. OKF frontmatter is an
upstream contract, not a project-owned object model. A project type records
only a `name` and a `description`. It MUST NOT add `properties`, `required`
fields, or frontmatter keys, so `wayfinder.json` never becomes a second
frontmatter schema. A Profile that needs a type-specific constraint writes a
rule over existing OKF fields or over a key it declares. Information with no
OKF field belongs in the concept body or in a key a package declares under
OKF §4.1. A new meaning for an OKF field needs an upstream OKF change first.

Tags stay OKF topic strings, and a generic OKF consumer tolerates any tag. A
package's `types`, `tags`, and `relationships` lists declare vocabulary, and
the project binding adds names to each. Composition rejects a repeated name
and a tag that collides with another vocabulary (§5.7). What an undeclared
used name means is a Profile rule's choice. Bitwild reports an undeclared tag
as an error. A Profile that wants an open vocabulary writes no such rule.

---

## 5. Profile packages

A Profile is one package: a directory at one Git revision whose
`wayfinder-profile.json` holds everything `wayfinder validate` enforces for it.
[`wayfinder-profile.schema.json`](../docs/schemas/wayfinder-profile.schema.json)
publishes its shape. One parser reads every package, Bitwild's included. The
engine embeds no Profile, holds no installed rules, and treats no Profile as a
base or a default. The
[`create-profile`](../skills/create-profile/SKILL.md) skill writes and
revises packages. This section is the contract every package meets.

### 5.1 A Profile is what the validator enforces

A package holds its identity and OKF binding (§5.4), its vocabulary (§5.5), its
rules (§5.6), and optionally its parent (§5.7). It MAY also name `docs`, a URI
for its rationale, and `skill`, a directory of agent guidance that `get`
installs (§4.7).

Conformance to a Profile is the gate `PASS` with that Profile selected: OKF
passes, every rule in the chain ran, and no rule reported an error. Nothing
else is a conformance requirement. A package's README and skill explain its
rules and guide the judgment its rules cannot decide, such as whether
knowledge earns a concept or a placement fits its subject. Where the README
or the skill disagrees with the package, the package governs and the prose is
in error. A Profile that wants a requirement enforced writes it as a rule. A
requirement that no rule can check is guidance, and no tool reports it as
assessed.

### 5.2 OKF runs first, and its result stands alone

The engine runs okf's validation before any Profile rule. When OKF fails, no
Profile rule runs and the Profile state is `BLOCKED BY OKF`, so a Profile
never reports cascading findings from content OKF rejected. A Profile result
never alters, reclassifies, or replaces the OKF result. Every Profile
therefore holds OKF conformance as a precondition. No package can relax it.

OKF reading never depends on a Profile. `graph`, `index`, and `search` read
the explicit bundle without resolving Profile sources (§4.7), and a broken
Profile selection leaves the OKF report intact.

### 5.3 A Profile only adds to OKF

A Profile is stricter than OKF and never contradicts it. Every rule and every
declared key MUST pass one compatibility test:

- it uses only constructs OKF 0.2 permits;
- it keeps the upstream meaning of every OKF field and reserved file;
- it leaves the OKF graph contract uninterpreted;
- it leaves the independent OKF result unchanged;
- it leaves the bundle readable by a generic OKF consumer that knows nothing
  of the Profile.

A rule that needs a new OKF field or a new meaning for one fails the test. Its
author pursues the change upstream before any Profile depends on it.

A rule MUST NOT report a concept's missing `verified` event or a derived trust
tier, and MUST NOT require a value that only a false statement could supply.
OKF §5.3 gives the absence of verification meaning, and an author can clear
such a finding only by recording a verification that did not happen.

A Profile narrows OKF only through its rules. Where no rule applies, OKF
governs, and anything OKF permits stays permitted. Silence defers to OKF; it
is never a gap to fill with a local convention. A Profile's skill follows the
same rule. Where the skill is silent, an author reads the pinned OKF
specification and follows it.

### 5.4 Identity, release, and format

`id` is the Profile's one name. It is lowercase kebab-case starting with a
letter, at most 64 characters, the Agent Skills name limit. The names `okf`,
`wayfinder`, and those of wayfinder's own skills are reserved. The id is the
finding namespace (§4.2), the key in `wayfinder.json` and the lock, and the
name of the installed skill directory, so no mapping between them exists.

`release` names the package's content. The engine never branches on it. Each
Profile picks its own scheme; Bitwild uses `<year>.<serial>`.

`format` names what the engine must understand to read the package. This
engine reads format `2`. A package with another format is reported as
`wayfinder/profile-unsupported`, never read the old way or partly applied.

`implements` binds the package to one OKF release, `{"id": "okf", "release":
"0.2"}`. Every package in a chain binds the same release, and this engine
reads OKF 0.2. The root index of a bundle declares that release as
`okf_version`.

`docs` is a URI. Each finding's `help_uri`, and each SARIF rule's `helpUri`,
is that URI with the fragment set to the rule's id. The page at `docs`
SHOULD carry a heading per rule id so every help link lands on its rule.

### 5.5 Vocabulary and frontmatter keys

`types`, `tags`, and `relationships` each list names with a one-sentence
description. A project binding adds names to each list (§4.7). These lists
are producer-side declarations. They let a Profile's rules see drift, and
they never license a generic OKF consumer to reject a concept.

`frontmatter_keys` lists the producer keys a package adds under OKF §4.1,
each with the sentence that defines it. A declared key MUST NOT be a key OKF
0.2 defines, and the parser rejects a package that declares one. A declared
key MUST NOT give an OKF field another meaning, which the package's author
reviews (§5.10). Keys are unique along a chain. A project binding cannot
declare keys.

`relationships` is the engine's one link field. Each entry of a concept's
`relationships` list names a relationship and a `resource`, and the engine
reads it as a typed edge resolved as the OKF graph resolves a link target
(§4.3). A Profile that wants typed links declares the `relationships` key
and names its relationships.

### 5.6 Rules and builtins

A rule has an `id` slug, a `category`, a `severity`, a `status`, a
`description`, a `message`, a `check`, and `tests`. Severity is `error`,
`advisory`, or `note`. An error finding fails the gate. An advisory asks for
action and never changes the gate or the exit status. A note is a summary
entry (§4.1). A check is either a JSON Schema over one subject's facts or a
builtin. The parser runs each rule's `tests` and reports a package whose
examples disagree with its check as `wayfinder/profile-invalid`.

A builtin is a check the engine implements and versions with its release. Any
package may call one by name with `params`. The rule's id, severity, message,
and docs belong to the package; the capability belongs to the engine. A check
becomes a builtin only when a schema over one subject's facts cannot express
it, because it needs disk I/O beyond the parsed bundle, a comparison with
generated output or a `--fix`, a finding about something absent, or more than
one finding per subject. A builtin never reports engine health, which is a
diagnostic, and never holds policy, which is its params. The create-profile
[builtins reference](../skills/create-profile/references/builtins.md) lists
each builtin with its params.

Generated text is engine contract. `matches-generated` compares a bundle with
the output of the generator in the engine's `okf` release (§3.1), so the
bytes a Profile accepts depend on that release as well as on the package. The
engine reports the version as `engine.okf`. A wayfinder release that changes
the generator's output MUST say so in its changelog as a breaking change for
every Profile that uses `matches-generated`, and its users regenerate with
`--fix`. A Profile's own release never has to change for it.

### 5.7 Composition

A package names its own parent in `extends`, and a project entry never wires
a chain, so a Profile means the same thing in every project that uses it. A
parent without `git`, `{"path": ...}`, is the package at that
repository-root-relative path in the same repository at the same commit, so
Profiles hosted together release together. A parent with `git`, `{"git",
"ref", "path"}`, resolves from its own repository and ref. Its `git` is a URL
or an absolute path, never a path relative to one project. A chain need not
reach any particular Profile. A cycle fails `get`.

Composition only adds. A child adds rules in its own namespace and adds
vocabulary. It cannot remove, replace, or re-grade an inherited rule, so an
ancestor's findings are the same with or without the child. Format 2 has no
field that changes an inherited rule. A later format may add an explicit one
in the child package, never in `wayfinder.json`.

The engine composes the chain and the entry's project additions into one
effective Profile before evaluating anything. Composition depends on nothing
else, so the same inputs always compose the same way. A type, tag, or
relationship name MUST be unique across the chain and the project additions.
A frontmatter key MUST be unique along the chain. A tag MUST NOT equal a
type, an OKF status, an OKF trust tier, or a relationship name. A violation
is a composition error. `get` composes every chain before it writes the lock,
so it reports the error and leaves the lock as it was. `validate` reports it
as the `wayfinder/profile-composition` diagnostic. A project entry that
repeats one of its own names is a configuration error (`config-invalid`).

Validation evaluates the rules of every package in the chain, root ancestor
first. Each finding names its package's `id` as namespace and its package's
`release`, so an ancestor's findings never depend on a child. A project
locks one revision per Profile id (§4.7), so a namespace in its reports
always means one ruleset.

### 5.8 Selection is exact

The engine selects a Profile only through `wayfinder.json` and its lock
(§4.4). It never falls back to the newest rules, never guesses a Profile from
bundle content, and never applies part of a package. When it cannot select
and read the whole chain, the Profile state is `NOT ASSESSED` and an error
diagnostic says why: `config-missing`, `config-invalid`, `bundle-unbound`,
`profile-unresolved`, `profile-invalid`, `profile-unsupported`, or
`profile-composition` (§4.1). The gate is then `INCOMPLETE` with exit `2`,
unless OKF or an evaluated rule already failed it. A `PASS` always means every
selected rule ran.

### 5.9 Tolerant reading

Consumers MUST keep OKF's tolerant-reader behavior (OKF §11). Unknown concept
types, unknown frontmatter keys, unknown relationship names, unregistered
actors, missing optional content, and broken links MUST stay loadable.
Unknown frontmatter SHOULD stay available to downstream consumers rather
than being dropped on round-trip. Valid OKF that a Profile does not describe
is content to carry forward untouched.

A Profile's rules judge what its producers write. They never change how a
consumer reads. The engine's graph, index, and search commands read a bundle
the same way whichever Profile a project selects. External resource
availability is never a check (§4.3).

### 5.10 Changing the contract and changing a Profile

The engine contract changes through an ADR, an entry in this guide's change
record (§9), and a wayfinder release. A change that would make the engine
read an existing package differently bumps `format`, so an older package is
reported as unsupported rather than reinterpreted. An upstream OKF
specification release needs an engine compatibility review
([`docs/compatibility-review.md`](../docs/compatibility-review.md)) before
the engine reads it.

Each Profile changes through its own release process, in its own repository.
A release MUST carry a change record that names the rules and vocabulary it
changes, the real-use driver, and the migration impact in words: whether
bundles that passed still pass, and what they must do if not. It MUST record
the compatibility test of §5.3 for each new or changed rule and declared key,
and MUST NOT claim compatibility with an OKF release it was not reviewed
against. A published release is a Git ref that never moves, so a lock always
reproduces it. Bitwild's records are its
[changelog](../profiles/bitwild/CHANGELOG.md).

---

## 6. Distribution

This repository distributes the engine and the generic skills, as the root
[`README.md`](../README.md) and [`skills/README.md`](../skills/README.md)
describe. Each Profile distributes itself as a package in a Git repository,
and a project names it from `wayfinder.json`. No project vendors a copy of a
Profile. Two requirements bear on bundles and so are stated here:

- **A Profile's skill must reach every environment that writes to a bundle.**
  An agent that never read the skill cannot apply the judgment the Profile's
  rules leave open, such as where a concept belongs. A Profile's skill ships
  in its package and reaches a project through `get`, pinned to the locked
  commit and committed with the lock (§4.7).
- **The tools must be pinned per repository and dispatch on the packages
  `wayfinder.json` selects** (§4.4), so repositories on different Profiles and
  releases can share one implementation.

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

A tool claims conformance to this guide by satisfying, for the package format
it reads:

- the generator contract (§3), if it writes indexes;
- the exit codes (§4.1), finding IDs (§4.2), the prohibitions (§4.3), and version dispatch
  (§4.4), if it validates;
- tolerant reading (§5.9) in both cases.

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

Revised again in place before publication (2026-10-02): a package MAY name
its agent skill in `skill`. `get` and `upgrade` install it from the locked
commit into the project's `.claude/skills/<id>/` and `.agents/skills/<id>/`
with a `.wayfinder-profile` marker, never touching a directory without one,
and `validate` reports a missing or outdated copy as the
`wayfinder/profile-skill-stale` warning. A Profile id has at most 64
characters, the Agent Skills name limit, so every id names its skill directory
validly. Affected sections:
§§4.1, 4.7, 6, and 9. Driver: a Profile's judgment lived in a user-level
skill family pinned to no Profile revision, so an agent could read guidance
for other rules than the ones `validate` ran. Migration for implementations:
read `skill`, install it after the lock with the marker, warn on a stale
copy, and refuse an id over 64 characters. No configured bundle is affected; a
Profile with a longer id must shorten it, and a project whose Profile ships a
skill commits the installed directories after its next `get`.

Revised again in place before publication (2026-10-02): this guide becomes
the wayfinder engine contract and binds no single Profile. The prose Bitwild
Profile text is deleted. Its framework rules move to the new §5, Profile
packages: what a package is, OKF first and independent, the compatibility
test that keeps every Profile stricter than OKF and never contrary to it,
silence as deference, identity, `release` and `format`, frontmatter keys,
builtins, generated text as engine contract, composition, exact selection,
tolerant reading, and how the contract and each Profile change. Precedence
becomes OKF, then the engine contract, then each Profile package. Conformance
to a Profile is the gate `PASS` with it selected, so a Profile's README and
skill no longer carry requirements of their own. Four statements of the old
text are reversed rather than moved: the prose no longer governs the rules,
a chain no longer has to reach Bitwild, the ban on changing an inherited
rule is a limit of format 2 rather than a permanent rule, and Profile
conformance no longer includes requirements no rule checks. The old §5
migration method moves to Bitwild's skill, the coverage matrix and its §4.6
release gate are deleted, and §§2, 3, 4.3, 4.7, 4.8, 6, and 8 drop
Bitwild-specific text. Affected sections: §§1 through 8, and 9. Driver: a
Profile is what the validator enforces, so a prose Profile above the guide
and a coverage map between them described requirements no tool decided.
Migration for implementations: none; engine behavior is unchanged. A Profile
author reads §5 instead of the Bitwild text.

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

The file keeps its name and path, `implementation/okf-implementation-guide.md`,
so links into it stay stable. It was titled *Implementation Guide* while it sat
below the prose Profile, which was the specification. It now sits above every
Profile package and keeps the name "guide". §1 states why "guide" does not mean
advisory.
