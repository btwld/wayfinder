# ADR-0019: Profile-aware writes

- Status: accepted
- Date: 2026-10-22
- Updated: 2026-10-22 (what a host's write pipeline needed: the
  content-change rule as a public function and a log that records only
  content changes, the OKF finding delta, and project files a host captures
  with its selection, tracked when no Profile is selected too, including
  each closer configuration path, absent); 2026-10-22 (adoption shares the
  assessor seam, and core offers a bounded assessment,
  [ADR-0020](0020-programmatic-adoption.md))
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
`KnowledgeLogEntry`, or several as `KnowledgeLogEntries` in the order given
under one date, exactly as given; okf's lifecycle entry; or none. The
entries are inserted into the existing log as lines in its own style, so no
authored byte changes; only a log that cannot take them that way is
re-emitted in okf's canonical form. A write that changes nothing else records
no entry, and a `KnowledgeContentLog` records its entry only when the write
changes content, on the rule below, so a host that logs content changes
only lets the writer decide on the concept it read. The library names no
lead words; a Profile's skill does.

**The writer stamps provenance.** A `KnowledgeStamp` names the actor. Content
a write creates or changes (body, `title`, `description` or `type`) records
`generated: {by, at}`; a link, a deprecation or another field keeps it. A
verified stamp also appends `{by, at}` to `verified`. A change that supplies
either key itself is refused. The rule is public, as
`changesConceptContent` over two documents and
`UpdateConcept.changesContent`, and the plan's `changesContent` reports what
`prepare` decided, so a host never re-implements it.

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
candidate's. The plan splits the candidate's OKF findings the same way, by
finding id and location path, beside okf's whole report, so a host can name
what a write broke; the OKF gate stays the whole candidate.

When no Profile can be selected (no `wayfinder.json`, an unresolved Profile,
or a chain that does not compose), the base and the candidate carry the same
diagnostics, so the delta is empty and the plan is judged by OKF alone; the
committed bundle then validates `NOT_ASSESSED`, not `PASS`. The plan says so
through `assessed`, and whether to write an unassessed bundle is the host's
policy, not the library's: a host may let a person write while refusing an
agent.

**The assessment is a seam the host may move.** A Profile's rules are the
one unbounded step: a pattern can be slow. `prepare` therefore reads the
bundle and lets okf prepare the candidate under okf's shared claim, releases
it, and only then calls a `KnowledgeAssessor` once with a
`KnowledgeAssessmentInput`: the base and candidate load results and the
selection, plain data with no file handle or lock. The default runs
`KnowledgeAssessmentInput.assess` on the calling isolate; a host that must
bound it runs it on an isolate it kills at a deadline, as
`KnowledgeAssessmentInput.assessWithin` does. Adoption takes the same
assessor with an input that holds one bundle and no base, so a host
composes one assessor for both. Judging outside the
claim is safe because the commit rechecks okf's snapshot, and it keeps a
slow rule from blocking writers in other processes. `prepare` and `commit`
take a `WayfinderCancellation`: checked between steps, passed to the
resolver and the assessor, and never during okf's write transaction.

**Failures are typed.** Besides `write-refused`, `write-stale` and the
change codes, a bundle the file system will not let the writer lock, read or
write is `write-failed` (`KnowledgeWriteFailedException`), which says
whether okf's rollback also failed and left part of the write.

**Stale plans are refused.** `commit` holds okf's exclusive claim, refuses a
plan when a project file its selection came from changed since, and lets okf
refuse a changed bundle. The project files are the `wayfinder.json` the
bundle was bound through and the `wayfinder.lock` beside it, whether or not
a Profile was selected, since a lock that appears would select one, with
each closer `wayfinder.json` path binding looked at first, absent; when no
configuration binds the bundle, they are each `wayfinder.json` path binding
looked at, absent. Either way a configuration that appears where binding
looked would bind the bundle. A host that selects itself passes the files
it captured with its selection, digests included, so a change between its
selection and `prepare` is refused too. Either failure is `write-stale`,
naming the project files that changed, and nothing is written. The check
runs under okf's lock of the bundle, while `relock` and `get` hold the
project's `get` lock, so it is not atomic with them: one that rewrites a
project file between the check and okf's write goes unseen. No lock spans
both, and taking the project's lock in `commit`, which never waits, would
fail writes during every `get`; a host that both relocks and writes
serializes the two itself.

**`validate --fix` writes under the same lock.** When a fix has something to
write, it takes `OkfBundleLock.write`, loads the bundle again and writes; a fix
with nothing to write takes no lock and creates no `.okf.lock`. A lock it
cannot take, such as in a bundle it may not write, is a failed write: the
`wayfinder/fix-failed` diagnostic with nothing written, as before the lock.

## Consequences

A host writes a Profile bundle with the same verdict `validate` reaches after
the commit, refusals that name the finding or path, and diffs limited to the
files the change affects. The writer obeys the one-isolate rule of ADR-0018:
`prepare` holds okf's shared claim while it reads and `commit` its exclusive
one; only the assessment, which touches no bundle file, may run on another
isolate.

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
