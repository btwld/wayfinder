# Bitwild Profile

This directory holds release 2026.3 of the Bitwild Profile, an OKF 0.2
Profile package with the id `bitwild-profile`. The package itself is
[`wayfinder-profile.json`](wayfinder-profile.json). A bundle conforms to this
Profile when `wayfinder validate`, with this package selected, reports the
`PASS` gate. This file explains why each rule exists. It adds no requirement
of its own.

Each rule id below is a heading, so the `help_uri` of a finding lands on the
rule that raised it.

## Purpose

Bitwild runs many codebases with many contributors, and durable project
knowledge arrives from two directions. Engineering knowledge, such as
terminology, architecture decisions, and operational guidance, has long lived
in repository documents. Business knowledge, such as client requests,
planning outcomes, demo feedback, and investigations, lives in calls, chat
threads, and meeting transcripts. It rarely survives the system it was born
in.

Without one model for both, the same failures repeat. Client context leaves
with the tool or the person who held it. A request, its analysis, the
decision, the specification, and the issue that delivers it describe one
concern with no durable link between them. Every meeting becomes a document,
or nothing does. Folders named after document kinds scatter one subject
across the tree, so a path name carries no reliable meaning. Each repository,
skill, and agent learns a local layout instead of one shared standard.

The Profile exists to fix that. Its goals are these:

- One Git-versioned home for durable knowledge, beside the code.
- Engineering and business knowledge in one model, without turning every
  meeting, message, or transcript into a document.
- One vocabulary and one structure across Bitwild repositories, so a reader
  who knows one bundle can find their way in the next.
- Trackers stay authoritative. Issues, tickets, and pull requests stay in
  GitHub and Linear, and concepts link to them.
- Any OKF reader can read a Bitwild bundle without knowing this Profile.
- Conventions are versioned and checked by a machine.

The Profile does not ingest source events, build a graph database, control
access per concept, require a human review step, or manage large binaries.
It never names a project's subjects. It fixes the structural model and the
type vocabulary, and each project names what it has knowledge about.

A proprietary format would solve none of these problems better than an open
one, and it would cost interoperability and upkeep. So the Profile adds
conventions to OKF instead of replacing it. The working model, a persistent
agent-maintained Markdown knowledge base with an index, a log, and curated
sources, is the LLM Wiki pattern from
[Andrej Karpathy's llm-wiki note](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).
That note inspired OKF and this Profile. It carries no normative weight.

## What it narrows in OKF

The Profile constrains how Bitwild uses OKF. It never changes what an OKF
field means. Every Profile package works this way, and the
[Profile packages section of the implementation guide](../../implementation/okf-implementation-guide.md#5-profile-packages)
states that contract once, including what happens where a package is silent.
Read this package beside the
[pinned OKF 0.2 specification](../../skills/author-knowledge-bundle/references/OKF-0.2.md).

The rules narrow OKF in these places:

- A concept carries `type`, `title`, `description`, and `status`. OKF
  requires only `type`, and the other three make a concept legible from its
  frontmatter alone ([concept-baseline-fields](#concept-baseline-fields)).
- A concept uses only OKF keys plus `relationships`, so every key in a
  Bitwild bundle has one meaning
  ([frontmatter-fields-declared](#frontmatter-fields-declared)).
- `status` is one of the three OKF values and describes the document only
  ([status-value](#status-value)).
- Types, tags, relationship names, and actors are declared vocabulary, so a
  typo or an invented kind fails instead of passing as a new name
  ([used-type-registered](#used-type-registered)).
- Every `index.md` is the output of the OKF reference index generator, so
  every index can be checked and regenerated
  ([index-current](#index-current)).
- The root index declares `okf_version: "0.2"`, which OKF leaves optional
  ([okf-release-binding](#okf-release-binding)).
- Every root log entry starts with a bold lead word
  ([log-entry-lead-word](#log-entry-lead-word)).
- A source entry without `resource` is an error here, where okf reports it
  as an advisory ([source-entry-shape](#source-entry-shape)).

The skill adds conventions that no rule checks, such as directories named
after subjects. They guide authors and reviewers. They are not part of
conformance.

## Where judgment lives

Much of what makes a bundle good needs context a validator does not have.
Does this knowledge earn a concept? Where does it belong? Which type fits,
and is the metadata true? That judgment lives in the Profile's skill,
[`skill/SKILL.md`](skill/SKILL.md). `wayfinder get` installs it into a
project, pinned to the same commit as these rules.
[`skill/references/review-map.md`](skill/references/review-map.md) lists
every check a reviewer makes and how strongly it applies. A review concern
asks an author to act. It never changes the result of `wayfinder validate`.

## Rules

### okf-release-binding

The bundle root index MUST declare `okf_version: "0.2"`.

OKF lets a bundle declare the version it targets and leaves the declaration
optional. This release binds OKF 0.2 exactly, so the bundle states which
specification it follows and no reader has to guess. The package names the
Profile release and the bundle names the OKF release. Each version number
then has one owner, and neither is mistaken for the other.

### configuration-legacy-registry

A bundle MUST NOT carry root `profile.md`, `types.md`, or `actors.md`
registries.

Release 2026.2 kept Profile selection, the type registry, and the actor
table as concepts at the bundle root. Release 2026.3 moved them into the
project's `wayfinder.json`. Configuration written as a concept read like
knowledge, and every bundle repeated the same standard type table. A
leftover registry is a second configuration that decides nothing, and a
reader could still trust it. [CHANGELOG.md](CHANGELOG.md) describes the
migration.

### configured-tag-undeclared

Every tag a concept uses MUST be declared by a package in the selected chain
or by the project's `wayfinder.json` entry.

Tags carry topic and nothing else. A declared tag has one name and one
description, so a project keeps one list of topics a reader can sweep, and
a typo or a one-off alias fails where everyone can see it. Declaration also
lets the engine reject a tag that equals a type, an OKF status, an OKF trust
tier, or a relationship name before it assesses any concept. Whether a
declared tag truthfully describes a concept is a review judgment
([metadata.md](skill/references/metadata.md#tags)).

### configured-tag-duplicate

A concept MUST NOT repeat a tag value.

A tag either applies to a concept or it does not. A second copy adds no
information, so the rule keeps each concept's tags a set.

### concept-baseline-fields

A concept MUST carry nonempty `type`, `title`, `description`, and `status`
fields.

OKF requires only `type`. `title` and `description` make a concept's
identity and purpose readable without opening its body, and the generated
index copies `description` into each entry. OKF reads an absent `status` as
`stable`, so a draft that omits it claims a maturity it does not have. The
rule checks presence only. Whether each value is true is a review judgment
([metadata.md](skill/references/metadata.md#baseline-frontmatter)).

### frontmatter-fields-declared

A concept MUST NOT carry a frontmatter key that OKF 0.2 does not define and
no package in the selected chain declares.

This package declares one key, `relationships`. A key declared in a package
has one meaning for every Bitwild reader, and a generic OKF reader loads it
as one more unknown key. A key each producer invents has a meaning only its
author knows. The rule also keeps out the confidence, credibility, maturity,
and evidence-tier fields that OKF deliberately leaves to the reader, because
a stored score is subjective and goes stale. A project cannot declare keys
in `wayfinder.json`. This is a producer rule. It never lets a reader reject
a document with an unknown key.

### status-value

A concept's `status` MUST be `draft`, `stable`, or `deprecated`.

`status` records the knowledge lifecycle of the document. Workflow states
such as accepted, blocked, or shipped describe execution, and execution
state belongs to the tracker. okf reports any other value as an advisory.
This rule makes it an error, so a workflow state cannot pass as a lifecycle
value. How settled the subject is belongs in the body
([metadata.md](skill/references/metadata.md#status)).

### generation-provenance-recommended

A concept SHOULD carry `generated`, recording how its current content was
produced. This rule is an advisory.

Knowing who or what produced the content, and when, helps a reader weigh it.
The rule stays an advisory because the only way to clear an error with no
known producer would be to invent one. Never write a `generated` value you
do not know
([metadata.md](skill/references/metadata.md#production-and-verification)).

### used-type-registered

Every concept type MUST resolve in the merged type registry of the selected
chain and the project's `wayfinder.json` entry.

`type` is the only place a concept's kind lives. The directory, filename,
and tags never carry it. This package declares twelve standard types, and a
project declares its own. The rule stops a typo or an invented kind from
passing as a new kind of thing. The engine reports each project type in use
as the `wayfinder/project-type` note, so recurring needs can inform a later
release. Whether a type fits the content is a review judgment
([types.md](skill/references/types.md)).

### used-actor-registered

When a concept uses an actor ID in `generated.by`, `verified[].by`, or
`sources[].author`, the project's `wayfinder.json` entry MUST hold that exact
ID with a nonempty `name`.

Actor IDs stay opaque OKF strings. The lookup gives each one a readable name
and, when known, an organization, role, and side. A reader can then tell who
`human:chris` is without asking. The lookup never changes the actor string
or its OKF trust tier, and it does not prove authorship
([metadata.md](skill/references/metadata.md#actors)).

### source-entry-shape

When `sources` is present, every entry MUST be a mapping with the nonempty
`resource` that OKF requires.

A source entry without `resource` names nothing a reader can follow or
weigh, so its provenance claim is empty. okf reports the gap as its
`invalid-sources` or `invalid-source` advisory. This rule raises it to an
error ([metadata.md](skill/references/metadata.md#sources)).

### source-id-unique

Within one concept, each `sources[].id` that is present MUST be unique.

A body footnote attributes a claim to a source by naming its id. Two
sources with one id make every such footnote ambiguous.

### source-attribution-join

A body footnote reference whose label equals a `sources[].id` is source
attribution, and it MUST have its footnote definition.

Per-claim attribution lets one concept carry claims from different sources
without splitting. A reference with no definition shows the reader a claim
of provenance with nothing behind it. A footnote whose label matches no
source id stays ordinary Markdown and is not checked
([metadata.md](skill/references/metadata.md#sources)).

### source-path-unresolved

A top-level `resource` or a `sources[].resource` written as a path SHOULD
resolve to an existing file or directory. This rule is an advisory.

A path that resolves to nothing gives the reader no source to open, and the
advisory points at the reference to repair. It stays an advisory because
OKF tolerates a missing target and availability is never a conformance gate.
Never replace a followable resource with a scope descriptor to clear it
([mirroring.md](skill/references/mirroring.md#deciding-not-to-mirror)).

### relationship-shape

When `relationships` is present, it MUST be a list of mappings. Each holds
exactly a nonempty `relationship` name and a nonempty `resource` that okf
reads as a link target, never a scope descriptor or an invalid path.

`relationships` is the one frontmatter key this package declares. A fixed
shape lets graph and search tools read typed edges without a parser of their
own. A relationship points at something a reader can follow, so its target
is a bundle path or a URL. Relationships are not provenance and never go in
`sources`, which records what the content derives from
([relationships.md](skill/references/relationships.md)).

### used-relationship-declared

Every relationship name a concept uses MUST be declared by a package in the
selected chain or by the project's `wayfinder.json` entry.

This package declares eleven names, each read from the containing concept
outward. A project may declare more. The declaration is where a name's
meaning is defined once, so every author applies it the same way. Whether a
name fits the edge it types is a review judgment
([relationships.md](skill/references/relationships.md#choose-a-name)).

### internal-link-bundle-relative

An internal link SHOULD use a bundle-relative target, with a leading `/`.
This rule is an advisory.

OKF prefers bundle-relative links. They keep working when the concept that
holds them moves, because they do not depend on its directory. OKF only
recommends them, so the rule asks rather than fails.

### internal-link-unresolved

An internal link whose target is absent from the bundle is reported as a
note.

OKF tolerates a broken link, and a missing target can be knowledge not yet
written. The note never changes the gate. A move that leaves an inbound link
pointing at the old path is unfinished, and this note is how you find it.
Keep a deliberate planned link and repair a mistaken one
([structure.md](skill/references/structure.md#moves-and-frozen-paths)).

### relationship-bundle-relative

An internal relationship target SHOULD be bundle-relative, with a leading
`/`. This rule is an advisory.

A relationship target follows the same rules as a link, for the same
reasons as [internal-link-bundle-relative](#internal-link-bundle-relative).

### relationship-unresolved

An internal relationship target that is absent from the bundle is reported
as a note.

Like an unresolved link, the target can be knowledge not yet written, and
the note never changes the gate. Review decides whether the edge is planned
or a mistake
([relationships.md](skill/references/relationships.md#choose-a-name)).

### raw-directory-placement

A `raw/` tier belongs to a source directory and MUST NOT sit directly under
`references/`.

The tier keeps a source's verbatim originals beside the readable mirror
derived from them. `references/` itself is not a source directory, so a flat
`references/` first organizes into source directories and then adopts the
tier ([mirroring.md](skill/references/mirroring.md#the-raw-tier)).

### raw-directory-markdown

No Markdown file is permitted in a `raw/` tier under `references/` or in any
of its subdirectories. [index-current](#index-current) reports a leftover
`index.md` there.

Everything in the tier is an original asset kept byte for byte. A Markdown
file there would read as a concept to every OKF tool. Keying the rule on the
directory name keeps the line between originals and derived mirrors
structural. The first migration with this Profile found the two mixed in one
directory, with nothing to tell them apart
([mirroring.md](skill/references/mirroring.md#the-raw-tier)).

### root-structure-files

A bundle MUST contain `index.md` and `log.md` at its root.

OKF reserves both names. The root index is where every reader and agent
starts, and the log is the only authored record of how the knowledge
changed. Profile configuration lives in `wayfinder.json`, outside the
bundle, so these two are the only required root files.

### root-index-lists-log

The root `index.md` of a bundle with no concepts MUST link only `log.md`.

The index generator writes no root index for a bundle with no concepts, so
[index-current](#index-current) cannot check a new bundle's root. Until the
first concept exists, the hand-written root index declares the OKF release
and links only the log. The first `wayfinder validate --fix` after a concept
lands replaces it with the generated root index
([adoption.md](skill/references/adoption.md#knowledgeindexmd)).

### concept-area-name-collision

A concept SHOULD NOT sit beside a directory of the same name. This rule is
an advisory.

An area holds every concept whose subject is one thing, so a concept named
for the same subject belongs inside it. The pair can also mean the area is
named after one member instead of what its members share. Placement is a
judgment, so the rule asks rather than fails
([structure.md](skill/references/structure.md#areas)).

### index-current

Every directory the OKF reference index generator indexes MUST contain an
`index.md` identical to the generator's output for the bundle. A directory
holding only non-concept assets, such as a `raw/` tier, MUST NOT carry one.

Indexes let a reader reach a concept from the root without reading the
bundle. A generated index can be checked and regenerated, with no second
source of truth, and one index shape serves every OKF tool. An index never
carries authored content, because the next regeneration discards a hand
edit. Knowledge worth keeping belongs in a concept. The generator's text is
part of the contract, so the engine reports which okf release produced it.
CRLF line endings match the same text. `wayfinder validate --fix` writes
every index the generator produces and never deletes a file, so delete a
leftover index in an asset-only directory by hand.

### log-entry-lead-word

Every root `log.md` entry MUST start with a nonempty bold lead word followed
by a colon, as in `* **Creation**:`.

A lead word lets a reader scan the log by kind of event. The skill lists the
preferred words. Any other word still conforms, because OKF leaves the
vocabulary open. What deserves a log entry is a review judgment
([structure.md](skill/references/structure.md#the-log)).

## Release history

[CHANGELOG.md](CHANGELOG.md) records each release and revision, newest
first, with its migration impact and the candidate rules not yet adopted.
[compatibility-review.md](compatibility-review.md) records, rule by rule,
why each rule stays compatible with OKF 0.2. [`versions/`](versions/) holds
immutable snapshots of superseded releases. They are an inert archive. The
engine never reads them.
