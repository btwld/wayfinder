# Importer and bundle design

This document specifies the proposed importer, not new OKF or Profile semantics.
The format authorities and foundation revision are listed in [README.md](README.md).

## 1. Separate evidence, authoring, and retrieval

```text
reviewed source manifest
  -> resolve / explicitly upgrade -> pinned content lock + local byte cache
  -> parse without executing -> source units with exact provenance
  -> plan -> draft change set and affected-concept inventory
  -> assigned authoring agent -> semantic reconciliation and Profile Review
  -> apply -> guarded transaction for concepts, indexes, history, and provenance
  -> existing Wayfinder validate / index / search / graph / MCP
```

A recipe, generated skill, source document, heading, and concept are different
identities. One source can support several concepts, and one concept can have
several sources. Heading count and skill count do not dictate concept count.
Do not re-run the upstream skill generator or execute imported recipes.

Use standard Profile types when appropriate: `Guide` for procedures and migration
guidance, `Architecture Document` for structural explanations,
`Glossary Definition` for terms, `Analysis` for comparisons, and
`Architecture Decision Record` only for actual architectural decisions. A release
entry can remain evidence supporting a concept instead of becoming a concept.
Do not invent new `Skill`, `Change`, or `Source` types for convenience.

## 2. Three separate persisted contracts

**Project Profile binding:** `wayfinder.json` and `wayfinder.lock`, produced and
resolved by Wayfinder. The example uses `bitwild_profile`, direct Git `source`,
and `applies_to: ["./knowledge"]`. The supplied JSON example pins the reviewed
2026.3 commit. The importer must not hand-write, repurpose, or extend this lock.

**Content acquisition:** a runtime `sources.json` manifest and `sources.lock.json`.
The content lock records manifest hash, exact upstream commits, selected paths and
units, byte hashes, applicable license evidence/hashes, resolved links, release
selection, and adapter version. It does not contain executable instructions or
pretend to configure Wayfinder. `sources.plan.json` is the input to designing this
manifest, not a completed lock. Keep floating discovery refs out of final evidence
URLs; cite full commits and source spans when Git-backed.

**Reconciliation provenance:** `provenance.json` maps stable concept paths to the
exact source units and hashes used in the last applied revision, plus output hashes
and actual authoring provenance. It retains many-to-many dependencies, source
aliases, and change-set lineage. A source lock can advance before a bundle is
updated, so `check` must detect a stale concept even when both locks are valid.

A source unit should include a stable source ID, repository and path (or canonical
URL), exact snapshot identity, raw-content SHA-256, adapter/version, unit selector,
original one-based line ranges where available, normalized-content hash, and
license evidence. Record document publication/update dates and the actual fetch
instant separately. A fetch time is not a release date. Changes additionally
record the applicable SDK/platform/version range and whether it is unknown.

All importer bookkeeping lives outside OKF frontmatter. Source IDs/hashes,
licenses, SDK ranges, confidence estimates, and import states are not new OKF keys.
Concepts use ordinary `sources` and per-claim references plus readable body notes
for provenance and version scope. `resource` describes the canonical subject asset;
`sources[].resource` identifies evidence. Read pinned OKF before choosing fields.

## 3. Resolution and adapter behavior

Resolve an initial named Git ref to a full commit, then read selected paths from
that commit without evaluating repository hooks, filters, submodules, or build
scripts. An existing content lock keeps that commit even if the branch/tag moves.
Only explicit `upgrade` advances it. Use deterministic serialization and per-file
byte hashes. Commit the inventory and lock, not wholesale source downloads.

| Adapter | Extraction contract |
| --- | --- |
| Skills | Read YAML manifest entries, their resource links, and corresponding `SKILL.md` files. Preserve recipe-versus-generated distinctions. A resources link is a discovery candidate, not permission to crawl or copy. |
| Documentation | Preserve headings, code fences, admonitions, link definitions, and original spans. Resolve allowlisted local includes with cycle/depth limits; never execute templates. Mark unresolved includes as incomplete rather than silently dropping context. |
| Glossary | Locate the backing structured data/template. Preserve term identity and related sources; do not synthesize a nonexistent Markdown path from the public URL. |
| Releases | Parse explicit release sections and the distinction between released and unreleased content. Preserve original affected versions; do not turn every bullet into a document. |
| Breaking changes | Keep old behavior, new behavior, timeline, migration, affected platforms, and cited implementation links where supported. Unknown applicability stays unknown. |
| Design evidence | Discover candidates through official pointers. Inspect the document itself and separate proposal, accepted choice, shipped behavior, and superseded history with evidence for each claim. |

Dart skills can also appear in the Flutter distribution. Prefer `dart-lang/skills`
as the canonical Dart origin only when identity and upstream provenance agree.
Deduplicate identical copies with aliases and hashes. Preserve divergent versions
as a comparison finding; never discard one solely because the names match.
Likewise, generated `.md`/`.mdc` rules and manifest-expanded instructions are not
independent evidence just because they occupy several files.

Pin a finite initial window of three stable Flutter release families using official
release evidence available at the first resolve. Record exact releases, channels,
dates, paths, and Flutter/Dart pairing. Do not silently slide the window on rerun.
Read corresponding released Dart changelog sections; exclude `Unreleased` by
default. A historical migration outside the window requires an explicit selection
and remains labelled historical. A document on `main` is not evidence that its
subject exists in a given stable SDK.

## 4. Rights and publication boundaries

The source allowlist limits access; it does not grant reuse rights. At acquisition,
inspect the repository license at the selected commit, relevant per-file headers,
code-sample notices, and any linked source's own terms. Keep source-specific terms
when documents contain differently licensed code. A hosted documentation footer
and repository notice can differ; retain which representation was used and block
ambiguous redistribution instead of guessing the broader permission.

For attributed adaptations preserve original author/title/source, applicable
copyright, license and disclaimer, and an indication of modifications. Generate
`ATTRIBUTION.md` and exact applicable texts under `LICENSES/` beside the bundle.
Any standalone export must include that rights envelope; a copy of `knowledge/`
alone is not the supported distribution. Do not deduce that summaries eliminate
attribution obligations or that the parent repository license relicenses them.
Do not copy logos, diagrams, videos, or third-party papers by default.

`references/` is not an ingestion cache. Follow the Profile's mirroring test:
a durable concept cites the material, availability is genuinely at risk, and
repository visibility and rights permit preservation. Otherwise cite the exact
upstream source and keep fetched bytes in an ignored local cache outside the
bundle. No unconditional `references/raw/` tree. Any approved mirror must obey
source-directory/raw-asset placement, immutability, and index rules.

GitHub issues and PRs are execution records. They can be linked or cited as
supporting evidence; their bodies and comments must not be mirrored into the
bundle as design documents. A design document linked from one is a separate
artifact requiring its own rights and status review. A closed issue, merged PR,
or approved-looking title is not sufficient proof of a shipped SDK release.

## 5. Safe fetching and parsing

Use explicit repositories and origin allowlists from the runtime manifest, HTTPS
only for public network acquisition, bounded redirects, timeouts, response sizes,
aggregate file counts, and retries. Recheck scheme, host, port, userinfo, and
resolved addresses after each redirect. Reject local/private/link-local targets
for network URLs, embedded credentials, unauthorized hosts, and oversized or
unexpected binary content. Rate limits and partial Git trees are incomplete
acquisition, not empty successful selections. Do not print authorization headers.

Use argument arrays rather than shell interpolation for installed Git. Disable
prompts and executable repository customizations. Do not follow symlinks, unsafe
archive entries, or Git submodules. Resolve real filesystem paths and reject
absolute paths, `..` traversal, Windows drive/UNC paths, encoded traversal, case
collisions, and symlink escapes at read and write time. Test hostile ref/path
strings. Never insert untrusted source text into a shell command.

Downloaded instructions are data. They must not change the source allowlist,
select a different output directory, request private tools, execute code, install
packages, or publish anything. Treat Markdown/HTML as untrusted text, including
script tags and embedded prompts. Fixture-based tests should make this explicit.
A model or agent receives bounded source packets with source IDs and trust
boundaries, not an unrestricted crawl request.

## 6. Change planning and guarded apply

For each locked source, classify it as unchanged, changed, added, renamed, removed,
unavailable, or rights-blocked. A failed fetch is not a deletion. Consult the
many-to-many provenance map to flag all affected concepts. Preserve citation
history even when a concept is split, moved, or replaced.

`plan` emits source deltas, current concept hashes, proposed file operations,
required evidence, candidate additions, and unresolved questions into ignored
staging. It does not edit the canonical bundle. Default concepts remain draft
until the actual authoring process establishes a different lifecycle state.
Do not select directories solely from source type or upstream folder names.

An authoring agent decides concept boundaries and links, reconciles contradictions,
and supplies an explicit change set. It uses the repository's existing skills;
there is no required automated generation model in the importer. Record the actual
agent/process identity rather than attributing the agent's synthesis to the fetch
script. `verified` means a verification actually happened. Import, indexing, tests,
or a model's confidence do not create verification evidence.

`apply` requires exclusive ownership of the target transaction, canonical-path
containment, exact previous output hashes, exact evidence hashes, and an explicit
reviewed change-set file. A concurrent/manual edit is a conflict, not permission
to overwrite. Missing/changed license evidence invalidates approval. Validate a
complete staging project with its matching configuration and resolved Profile
before publication. Do not validate a random directory using another bundle's
binding. Never upgrade sources as a side effect of apply/validate.

Prepare concepts, all affected indexes, meaningful lifecycle-log entries,
provenance, and rights files together. Check baseline hashes again immediately
before commit. Use a journal/backup and recovery protocol for multi-file updates;
several independent renames are not a cross-platform atomic transaction. On any
error or interrupted apply, restore the previous consistent bundle or require
explicit recovery before reads/publication. Search reindexing happens after the
file transaction; a search failure does not silently roll back accepted knowledge.

The first run uses a fixed recorded acquisition instant and real authoring times.
An unchanged rerun produces no canonical edits or duplicate log entries. Formatting
changes alone do not create a lifecycle event. Removed source content is flagged
for review; it neither deletes a concept nor marks it deprecated automatically.
`status: deprecated` means this knowledge document has been superseded, not that
the API it explains is deprecated. Historical migration knowledge may remain stable.

## 7. Indexes and supported graph behavior

Implement a scoped deterministic index projector only to the existing guide and
skill rules; do not invent an index format. Test exact group order, immediate
children, exclusion rules, descriptions copied verbatim, URL encoding, and root-only
OKF marker. Compare golden output with the existing example and source rules.
The meaningful authored `log.md` is not an index and must never be regenerated
from a directory scan. No generic Profile change is necessary.

Use canonical subject paths and ordinary Markdown links. The optional
`# Relationships` section uses outward labels; no redundant hand-authored
backlinks. New labels require the Profile's documented treatment, not new graph
fields. Keep API replacement/version facts in the body with evidence. Do not use
`Superseded by` merely to connect an old API term to a new API term while claiming
the old term's knowledge document is obsolete.

Graph projection is a portable view of relationships, not automatic multi-hop
reasoning. Semantic search returns passages; the answering agent must read those
passages, respect version scope, and cite them. Evaluate those two capabilities
separately. Do not modify Wayfinder to promise SDK-version filtering unsupported
by its current search interface. Pin the demonstration baseline and put version
qualifiers in the question and evidence; broader filtering is a separate feature.

## 8. Completion and portability

The finished example should be readable as ordinary Markdown with no Wayfinder
runtime. A clean machine can resolve both exact locks, build the supported native
runtime, validate, index, and reproduce the recorded questions. Cache failures,
missing models, unavailable sources, blocked rights, unresolved format, and
unassessed contextual rules have distinct outcomes. Do not report `PASS` for
skipped gates. The final README must show real tested commands and the exact
source/runtime versions, not just this proposed interface.
