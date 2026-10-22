# ADR-0019: Profile-aware writes

- Status: accepted
- Date: 2026-10-22
- Scope: the write path for a bundle a Profile governs: how a change becomes a
  candidate, which reserved files it rewrites, how the candidate is judged,
  and when it commits; `validate --fix` under okf's bundle lock, and the
  `.okf.lock` file both leave. No Profile rule, package format or result
  changes.
- Driver: [#45](https://github.com/btwld/wayfinder/issues/45). Agents and
  hosts wrote Profile bundles with raw file edits, because okf's writes
  rewrite indexes and the log in okf's own way and judge only OKF.
- Builds on [ADR-0015](0015-profile-rule-catalogs.md) and
  [ADR-0018](0018-embeddable-libraries.md)

## Context

okf 0.5 has one safe write path: `OkfBundleChangeApplier.prepare` overlays a
change set, regenerates the changed concept's ancestor indexes with okf's
generator, prepends its own lifecycle entry to the root log, and refuses a
candidate the OKF Spec rejects; `commit` writes exactly those bytes under the
bundle's exclusive `.okf.lock` and refuses a bundle that changed since. A
Profile adds what that path cannot see: its own rules, and, through
`matches-generated`, the exact index text it requires, with the root index
declaring the package's `implements.release`. The root log is authored
history, which a tool must not derive (guide §3.2).

#45 asked where the Profile's projection belongs: in Wayfinder, beside okf's
transaction, or in okf's writer as a seam Wayfinder fills. okf 0.5.1 adds that
seam: `prepare(project:)` lets the caller rewrite reserved `index.md` and
`log.md` texts before okf validates the candidate and binds its bytes into
the commit plan, and `OkfPreparedCandidate.toLoadResult()` hands the candidate
to a validator in memory.

## Decision

**One write path, in the core library.** `package:wayfinder/authoring.dart`
holds `KnowledgeWriter`. `prepare` maps one `KnowledgeChange` (create, update,
link, deprecate, or the `RegenerateIndexes` repair) onto okf's change set and
calls okf's `prepare` with a projection. It writes nothing. `commit` writes
the plan through okf's `commit`. The transaction stays in okf, which settles
#45 with its second option, limited to reserved files.

**Links go into `relationships`.** A link appends a
`{relationship, resource}` entry to the concept's `relationships` field, the
engine's one link field (guide §5.5), instead of okf's `sources`, and a
deprecation may append others, such as a replacement. A resource written for
a concept is its bundle-relative path.

**Only indexes whose generated text changes are rewritten.** When the
selected chain has a fixable rule, the projection asks
`ProfileProjection.generatedFiles` what the rules generate for the base and
for the candidate, and writes exactly the generated text of each index the
two differ on. An index the change does not affect keeps its bytes, even a
stale one, and okf's own regeneration of an ancestor whose generated text is
unchanged is dropped. Rewriting every stale index is the explicit
`RegenerateIndexes` repair, which writes exactly what `validate --fix`
writes. Without a fixable rule, okf's ancestor regeneration stands.

**The caller authors the log.** A write records the caller's
`KnowledgeLogEntry` exactly as given, okf's lifecycle entry, or none. The
entries are inserted into the existing log as lines in its own style, so no
authored byte changes; only a log that cannot take them that way is
re-emitted in okf's canonical form. A write that changes nothing else records
no entry. The library names no lead words; a Profile's skill does.

**The writer stamps provenance.** A `KnowledgeStamp` names the actor. Content
a write creates or changes (body, `title`, `description` or `type`) records
`generated: {by, at}`; a link, a deprecation or another field keeps it. A
verified stamp also appends `{by, at}` to `verified`. A change that supplies
either key itself is refused.

**The candidate is judged in memory, by a delta.** `validateLoaded` assesses
the base and okf's prepared candidate with the same selection, never reading
the candidate back from disk; `path-targets-exist` consults the loaded
inventory before the disk, so it sees the files the write adds. The OKF gate
is the whole bundle, as okf judges it. The Profile gate is a delta: a
candidate finding is pre-existing when the base reports one with the same
rule id and path, counted as a multiset, and introduced otherwise. A plan is
committable when okf accepts the candidate and it introduces no error
finding and no error diagnostic, so one unrelated broken concept does not
block every write, while a caller that wants a passing gate checks the
candidate's.

**Stale plans are refused.** `commit` holds okf's exclusive claim, refuses a
plan whose `wayfinder.json` or `wayfinder.lock` changed since `prepare` when
its selection names them, and lets okf refuse a changed bundle. Either
failure is `write-stale`, and nothing is written.

**`validate --fix` writes under the same lock.** When a fix has something to
write, it takes `OkfBundleLock.write`, loads the bundle again and writes; a fix
with nothing to write takes no lock and creates no `.okf.lock`. A lock it
cannot take, such as in a bundle it may not write, is a failed write: the
`wayfinder/fix-failed` diagnostic with nothing written, as before the lock.

## Consequences

A host writes a Profile bundle with the same verdict `validate` reaches after
the commit, refusals that name the finding or path, and diffs limited to the
files the change affects. The writer obeys the one-isolate rule of ADR-0018:
`prepare` holds okf's shared claim and `commit` its exclusive one.

A write re-serializes the concept it changes in okf's canonical form, so its
frontmatter layout may change; the other files keep their bytes. okf takes
its lock by creating `.okf.lock` at the bundle root, so a commit or a fix that
writes leaves that file. okf's loader ignores it, and so does the inventory
`wayfinder index` and `search` compare to decide freshness, at any depth; a
project ignores it in Git, as this repository does.

The library adds no MCP tool, and ADR-0011 still exposes no authoring tool.
Write tools over this library are a separate decision. Move and delete are
not changes yet.

## Reconsider when

okf gains move or delete changes, a Profile needs a generated file other
than an index, or a Profile's own rules need the log to carry entries a
caller cannot supply.
