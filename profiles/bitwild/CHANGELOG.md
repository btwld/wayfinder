# Bitwild Profile changelog

Each entry names a release or an in-place revision, newest first. It states
what changed, the real use that drove it, and the migration impact for bundles
that conformed before it. Entries older than the top one are history and keep
the names of their time. The 2026.2 and 2026.1 entries cite sections of that
release's prose text, which [`versions/`](versions/) keeps. The 2026.3 prose
text is gone, so its entries name sections by subject.

## 2026.3 revision for Profile independence (2026-10-02)

Release 2026.3 was not yet published, so this revision changes it in place and
keeps the release name. It changes how the Profile is packaged, named,
fetched, and enforced. Bundle rules change in one place, the new
`root-index-lists-log` rule.
[compatibility-review.md](compatibility-review.md) records the OKF review of
each rule in this revision.

**One package file.** The manifest `wayfinder-profile.json` and the rule
catalog `wayfinder-rules.json` merge into one `wayfinder-profile.json` in
package format 2. `standard_types` is renamed `types`, and `frontmatter_keys`
becomes a list of `name` and `description` entries. Migration impact: none for
bundles. A child Profile that shipped a manifest and a catalog merges them
into one format 2 package.

**No installed base.** The engine no longer installs Bitwild or requires a
Profile chain to reach it. Bitwild is fetched from its Git source like any
other Profile, from `profiles/bitwild` in the wayfinder repository. A Profile
can stand alone. Migration impact: a project runs `wayfinder get` once to
fetch the package. Validation reads only the locked copy after that.

**New id and finding namespace.** The id `bitwild_profile` becomes
`bitwild-profile`, and findings move from `concepta-profile/<rule-id>` to
`bitwild-profile/<rule-id>`. The id, the namespace, and the installed skill
directory are now one string. Rule ids after the slash are unchanged.
Migration impact: every finding id changes. Tooling that matched
`concepta-profile/*` must match `bitwild-profile/*`.

**Help links replace clause references.** Each rule's `ref` pointed at a
section of the prose Profile text. The package now sets `docs` to
[README.md](README.md), and the engine derives each finding's `help_uri` in
JSON and `helpUri` in SARIF as `docs#<rule-id>`. The JSON finding drops its
`rule` field. Migration impact: tooling that read `rule` reads `help_uri`.

**Two rules became engine diagnostics.** `link-graph-unavailable` and
`configured-type-extension` described the engine and the configuration, not
the bundle. The engine now reports them as the
`wayfinder/link-graph-unavailable` and `wayfinder/project-type` diagnostics.
Migration impact: a bundle whose link graph cannot be built gets the
`INCOMPLETE` gate instead of `FAIL`. A project type in use is still reported
as a note. The 2026.2 rule `tag-literal-duplication` had no 2026.3
counterpart, because 2026.3 checks tags where they are declared. Its engine
code is deleted with the 2026.2 dispatch.

**Builtins became engine capabilities.** Three rules used checks written for
Bitwild. They now name generic engine capabilities and pass Bitwild's choices
as params. `root-structure-files` uses `files-present` with `paths`.
`source-path-unresolved` uses `path-targets-exist` with `fields`.
`index-current` uses `matches-generated` with `generator`, `keep`, and
`version` pinned to okf 0.5.0, so an okf upgrade in a later wayfinder cannot
change index verdicts under a locked Bitwild. The rule ids stay, so findings
keep their ids. Migration impact: none for bundles. Bitwild loads only on a
wayfinder built with okf 0.5.0 until a later revision moves the pin.

**New rule `root-index-lists-log`.** The root `index.md` of a bundle with no
concepts must link only `log.md`. The prose text required it, but no rule
checked it, because the index generator writes no root index for such a
bundle. Migration impact: a bundle with no concepts whose root index lists
anything else now fails. A bundle with concepts is unaffected.

**`extends` lives in the package.** A Profile names its parent in its own
package, so its meaning no longer depends on how each project wires it.
`wayfinder.json` loses `extends`, and every entry applies to at least one
bundle. Bitwild has no parent. Migration impact: a project that set `extends`
in `wayfinder.json` names only the child entry there, moves the parent into
the child package's `extends`, and runs `wayfinder get`.

**The skill ships with the package.** The Bitwild judgment that lived in
wayfinder's generic skills now lives in [`skill/`](skill/SKILL.md). `wayfinder
get` installs it into `.claude/skills/bitwild-profile/` and
`.agents/skills/bitwild-profile/`, pinned to the locked commit. Migration
impact: commit the installed directories after the next `wayfinder get`.

**Clean break from 2026.2.** The engine no longer reads the in-bundle
`profile.md` selector. A bundle with no `wayfinder.json` above it gets the
`wayfinder/config-missing` diagnostic and the `INCOMPLETE` gate. Migration
impact: a 2026.2 bundle pins wayfinder 0.1.x, or migrates to a
`wayfinder.json` binding as the [2026.3 entry](#20263) describes.

**The prose Profile text is replaced.** `profile/okf-profile.md` is deleted.
Its framework rules, which apply to every Profile, moved to the [Profile
packages section of the implementation
guide](../../implementation/okf-implementation-guide.md#5-profile-packages).
Bitwild's rationale moved to [README.md](README.md), its judgment to the
skill, and its change records to this file. The superseded snapshots moved
from `profile/versions/` to [`versions/`](versions/). Migration impact: none
for bundles.

**Conformance narrows to the rules.** Conformance used to mean every MUST in
the prose text, whether a rule or a reviewer assessed it. It now means exactly
what this package's rules decide, which is the `PASS` gate from `wayfinder
validate` with this package selected. The judgment requirements the prose
held, such as subject-named directories, truthful metadata, and pull-based
mirroring, are skill guidance. The skill's [review
map](skill/references/review-map.md) keeps their force for review, but they
are no longer part of a conformance claim. Statements a schema rule could
check are listed under [Candidate rules](#candidate-rules-not-conformance).
Migration impact: no bundle that passed validation fails because of this
change.

**For a configured project.** Make these changes once:

1. Rename the `profiles` key in `wayfinder.json` from `bitwild_profile` to
   `bitwild-profile`.
2. Point `source.path` at `profiles/bitwild`, and set `source.ref` to a
   revision that contains it.
3. Remove `extends` from every entry, as described above.
4. Run `wayfinder get`, then commit `wayfinder.lock` and the installed skill
   directories.
5. Update any tooling that matched `concepta-profile/*` to match
   `bitwild-profile/*`.

## 2026.3 revision for summary entries and tag names

Revised in place before publication. What the Profile permits is reported as a
summary entry, not an advisory. A registered project-specific type and an
unresolved internal link or relationship target are conformant, so tooling
reports them apart from findings, and only advisories that ask an author to
act or review remain. A declared tag name MUST NOT equal a declared type name,
an OKF status value or trust tier, or a declared relationship name. This
replaces the per-concept check of a tag against that concept's own type,
status, trust tier, and relationship names. Driver: SARIF output for code
scanning raised every advisory as a warning, including each project type in
use and each planned link, which no author action clears. Once every used tag
is declared, a tag that repeats another vocabulary is a property of the
declaration. The per-concept check reported it once per concept that used it
and not at all while unused. Migration impact: no concept changes, and no
bundle's result changes except through its tags. A binding that declares a tag
equal to any declared type name, status value, trust tier, or relationship
name now fails at configuration, before any concept is assessed. That holds
even when no concept uses the tag, or when the tag equals a type other than
the type of the concept that carries it. Rename or remove that tag. 2026.2
bundles are unaffected.

## 2026.3 revision for child rule catalogs

Revised in place before publication. A non-base entry's source may ship a rule
catalog, the data form every Profile's automated rules now take, and its rules
add findings in the entry's own namespace. The earlier text forbade loading
executable rules from a source. A catalog is data the installed validator
evaluates, so that line holds. The prohibition narrows to replacing, omitting,
re-grading, or parameterizing an ancestor's rules, declaring frontmatter keys,
and shipping a catalog for the base. The conformance section makes the
installed catalog the machine-readable form of the automated rules, which must
agree with the clauses they cite. Driver: a second knowledge base on the same
okf release keeps its own rules beside its vocabulary. A child Profile with
vocabulary but no rules could not express a stricter policy, such as a closed
type subset, without a validator release. Migration impact: none for bundles.
A conformant 2026.3 bundle stays conformant, since no existing source names a
catalog and an ancestor's findings are unchanged by a child's. A child catalog
the installed validator cannot evaluate makes dispatch `UNSUPPORTED` rather
than silently dropping rules. Upgrade the validator or correct the catalog.
2026.2 bundles are unaffected.

## 2026.3 revision for relationships in frontmatter

Revised in place before publication. Typed relationships move from the `#
Relationships` body section to the top-level frontmatter key `relationships`,
a list of `relationship` and `resource` mappings. This release declares it as
its one additional producer key under OKF §4.1. A declared key never reuses or
redefines an OKF key, and relationships stay out of `sources`, whose OKF §5.1
meaning is derivation. Relationship names become declared vocabulary like
tags. The manifest declares the eleven standard names in kebab-case, a project
binding MAY declare more, and an undeclared name is an error rather than an
advisory. Driver: a labelled body link reached OKF's graph, and Wayfinder
graph and search, only as an untyped link, and checking the body grammar
needed a Profile-specific Markdown parser. A second knowledge base on the same
okf release records its typed edges in frontmatter, where its gate checks
names and targets with a schema. Migration impact: a bundle written to the
earlier 2026.3 text that carries a `# Relationships` section still conforms,
but the section is ordinary prose and its labels no longer type anything. To
keep them, move each bullet into `relationships`, with its label in kebab-case
as `relationship` and its link target as `resource`. Then delete the emptied
section, and declare each nonstandard label in the binding's `relationships`
list. 2026.2 bundles keep the body section under 2026.2.

## 2026.3 revision for generated indexes

Revised in place before publication. Every index is the output of the OKF
reference index generator instead of a Profile-defined projection. The
`Bundle`, `Directories`, and `Assets` groups, the Profile type order, and the
label, target-encoding, and per-nonempty-directory rules are withdrawn. A
directory holding only non-concept assets, such as a `raw/` tier, needs no
index. The index section names the generator's `okf` release, 0.5.0, and the
versioning section states that a release changing the generator's output needs
a Profile revision. Driver: the custom projection diverged from the index
shape OKF's own tooling generates, so bundles needed a Profile-specific
generator to stay conformant. A second knowledge base on the same okf release
already checks its indexes with `okf index --check`, and teammates on the
native `wayfinder` binary need the generator without a Dart toolchain.
Migration impact: an index written to the earlier 2026.3 projection no longer
conforms. `wayfinder validate --fix` regenerates every index the generator
writes but never deletes a file. Delete each `index.md` it then reports as one
the generator does not write, such as one left in a `raw/` tier or another
asset-only directory. 2026.2 bundles and the 2026.2 projection are unaffected.

## 2026.3

Moves Profile selection and project vocabulary out of bundle concepts into
direct Git-sourced project-root `wayfinder.json` entries. Entries may add
vocabulary through explicit parent chains. The installed `bitwild_profile`
validator remains closed. Driver: real adoption and validation work found
repeated standard `types.md` tables, mandatory actor tables for routine agent
provenance, and `profile.md` configuration masquerading as knowledge. Multiple
independent bundles need reusable but distinct bindings, and a repeatable
source revision across machines. The OKF-defined Attested Computation type
joins the standard registry, so producers can use OKF §10 without declaring an
OKF type as custom. The subject-placement rule is unchanged. `computations/`
joins the named directories as the OKF §10.4 home for Attested Computations,
so the Profile follows OKF's own directory choice instead of reading it as a
kind-named folder. Migration impact: an existing conformant 2026.2 bundle
remains conformant to 2026.2 and continues to validate under that release. To
adopt 2026.3, create a direct-source entry, resolve and commit its lock, and
move custom types, tags, and actor IDs into the entry. Then remove the three
legacy root registry and declaration concepts, regenerate the root index, and
retain `index.md` and `log.md`. Used tags must be declared. Preserve material
actor affiliation history from the old table as ordinary knowledge before
removing the table, because a single JSON lookup cannot express dated rows.
This is an opt-in migration, not a silent reinterpretation of old bundles.

## 2026.2 amendment

Amended in place. §6.5 of the [2026.2 text](versions/okf-profile-2026.2.md)
withdraws the three producer SHOULDs (quoted timestamps, block-style
structured values, and `verified` as a list) and drops the day-only
`T00:00:00Z` authoring sentence. Driver: those sentences contradicted or
extended the OKF specification's own examples. YAML spelling and day
resolution belong to OKF and `okf format --migrate-timestamps`. Migration
impact: none. A bundle conformant under the unamended 2026.2 stays conformant.

## 2026.2

Adopts the upstream OKF 0.2 revision that makes every timestamp an ISO 8601
datetime with an explicit UTC offset. Moves the pinned specification to its
canonical repository, `open-knowledge-format` at `ad30107`, which holds the
same text as `knowledge-catalog` `62432a0`, the commit the `okf` package
names. Affected sections of the [2026.2 text](versions/okf-profile-2026.2.md):
the §5.5 row of the OKF section map, §6.4, the new §6.5, §11's release
binding, and every timestamp in the examples. Driver: upstream restated
`stale_after` as an absolute instant compared against `now` rather than a
calendar day, dropped `last_modified`'s date-only type, and made
`usage_window` a datetime range. A Profile that still called `stale_after` a
date would contradict the specification it binds. Migration impact: a bundle
conformant under 2026.1 stays conformant. The `okf` package reports a
date-only timestamp as the non-blocking `okf/timestamp-without-offset`
advisory and leaves its conformance verdict unchanged, so no bundle becomes
non-conformant by standing still. Two exceptions apply. `okf validate
--strict` escalates advisories to failures, so it begins failing on date-only
timestamps it used to accept. A concept east of UTC may now go stale later
than it did when staleness was a local calendar comparison. `okf format
--migrate-timestamps` rewrites date-only values to `T00:00:00Z`.

## 2026.1

Initial release. Binds OKF 0.2 exactly, published together with the rule-level
compatibility review and the implementation coverage matrix.

Amended in place during its QA period (ADR-0006): §3.4 and §12 of the [2026.1
text](versions/okf-profile-2026.1.md) add the optional per-source `raw/` tier
for verbatim originals under `references/`. Driver: the first migration QA
showed originals and derived mirrors mixing in one tier, with nothing
structural marking the boundary. Migration impact: none. The tier is a MAY,
and its Markdown restriction binds only bundles that adopt it, so a bundle
conformant before the amendment remains conformant unchanged.

A second QA-period amendment (ADR-0007): §9 writes targets as relative URLs
and compares them percent-decoded, rejecting the spellings a URL reads
differently, such as a raw `?` or `#` and escapes that decode to `/`. Driver:
the same migration's verbatim originals carry filenames with spaces,
parentheses, and characters outside ASCII that no target spelling could
satisfy. Markdown parsing normalizes destinations to a percent-encoded form,
which the raw-path comparison then rejected. Migration impact: a previously
conformant target decodes to itself and stays conformant, unless it carried a
raw `?` or `#`. That target now needs the encoded spelling a URL consumer
actually resolves to the file.

## Candidate rules (not conformance)

The prose text made these statements, and a schema rule could check each one.
None is a rule today, so none is part of conformance. A release adds a
statement here as a rule only with its own entry above, because each one
changes the result for some bundle that passes now. Statements that need
source context stay review guidance in the skill.

Checkable with today's facts:

- **Only computations in `computations/`.** Every concept under
  `computations/` is an `Attested Computation`. The check uses the concept
  subject, where a `path` starting with `computations/` requires `type` to
  equal `Attested Computation`, plus the file subject to keep non-Markdown
  files out. Not a rule yet because it is a new requirement, and a release
  must first decide whether a scoped `log.md` or an asset may sit there.
- **Configuration stays outside the bundle.** `wayfinder.json` and
  `wayfinder.lock` never sit inside the bundle. The check uses the file
  subject, rejecting those two names. Not a rule yet because it is a new
  requirement on bundles that pass today.
- **Timestamps carry an offset.** `generated.at`, `verified.at` or
  `verified[].at`, `stale_after`, `sources[].last_modified`, and
  `usage_window.from` and `.to` are datetimes with an explicit UTC offset. The
  check uses the frontmatter subject, with `format: date-time` on each field.
  Not a rule yet because okf already reports it as the
  `okf/timestamp-without-offset` advisory, and an error here would fail
  bundles that pass today. RFC 3339 `date-time` is also slightly stricter than
  okf's offset check.
- **Mirrors carry `sources`.** A Markdown concept under `references/` carries
  a `sources` entry naming its original. The check uses the concept subject,
  where a `path` starting with `references/` requires the `sources` key. Not a
  rule yet because it is a new requirement, and only presence is checkable.
  Whether the entry names the original stays a judgment.
- **Preferred log lead words.** A root log entry uses `Initialization`,
  `Creation`, `Update`, `Move`, `Area created`, or `Deprecation` when one
  fits. The check uses the log subject, an advisory enum on each entry's
  `action`. Not a rule yet because the statement is a SHOULD with an open
  vocabulary, and an advisory would flag every other lead word, which
  conforms.

Checkable with a new fact or capability:

- **Lowercase kebab-case slugs.** Authored path slugs are lowercase
  kebab-case, and an externally cited ID that leads a slug keeps its case. The
  check uses the file subject, a pattern on each path segment. Not a rule yet
  because nothing marks where a cited ID ends, so a pattern would flag
  legitimate paths. It needs a fact or a declared ID syntax.
- **No nested bundle.** A bundle contains no nested bundle. Needs a fact that
  marks a directory as a bundle root. okf already rejects the only marker OKF
  defines, an `okf_version` in a nested index, as `invalid-index-frontmatter`.
- **Mirror only what is cited.** An artifact under `references/` is mirrored
  only when a concept cites it through `sources`. Needs a fact for inbound
  source edges, which today cover relationships only. Availability risk and
  visibility stay judgments.
- **Images only when cited.** An image is mirrored only when a concept cites
  it. Needs a fact listing what cites an asset.
- **Mirrors stay immutable once cited.** Needs a capability that compares a
  file with an earlier revision. That is not a fact of one bundle state.
- **Directories are not named after kinds.** No directory name equals the slug
  of a declared type name, such as `decisions/`. Needs a slot of slugified
  type names. It would catch only the plain cases, so the judgment stays in
  review.
