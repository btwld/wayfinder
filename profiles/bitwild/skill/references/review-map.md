# Review map

This is the contextual surface of Profile Review for this Profile. The
generic `author-knowledge-bundle` skill owns the review flow and the report
format. This map says what to judge.

`wayfinder validate` already decides every rule in the package. Never
restate a validator finding as a judgment, and never judge a check below as
passed because validation passed.

## Scope

Routine review covers the changed concepts and what they directly affect:
placement, indexes, relationships, and dependents. Adoption, release
upgrades, [migrations](migration.md), and structural reorganizations cover
the whole bundle.
Mark a section not applicable only after checking it against the scope.

## Force

- **Required.** A clear violation makes the outcome `CHANGES REQUIRED`.
- **Recommended.** Not following it is a concern. It requires changes only
  when the change ignores it with no reason the context supports.
- **Permitted.** Never report it as a concern. The [permitted](#permitted)
  section lists these so a reviewer does not flag them.

The `Reviewed` line of the report names the sections below by their ids,
such as `capture, types, structure`.

## capture

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| C1 | No concept exists merely because a source event occurred; each passes the durable-knowledge test. | Required | [capture.md](capture.md#source-events-are-not-concepts) |
| C2 | An outcome that needs independent status, provenance, relationships, reuse, replacement, or history is its own concept. | Recommended | [capture.md](capture.md#promote-or-embed-an-outcome) |
| C3 | A small outcome that is never referenced on its own stays embedded where it arose. | Recommended | [capture.md](capture.md#promote-or-embed-an-outcome) |
| C4 | An ambiguous outcome starts embedded. | Recommended | [capture.md](capture.md#promote-or-embed-an-outcome) |
| C5 | A concept whose parts carry materially different verification or lifecycle is split. | Recommended | [capture.md](capture.md#split-a-concept) |
| C6 | An Interaction Record exists only when the combined context is durable, and never as routine minutes. | Required | [capture.md](capture.md#interaction-records) |
| C7 | A single outcome that mattered links straight to its original source, with no Interaction Record. | Recommended | [capture.md](capture.md#interaction-records) |

## types

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| T1 | A standard type matches its intended meaning. | Required | [types.md](types.md#choose-between-neighbours) |
| T2 | A project type matches the meaning its `wayfinder.json` entry declares. | Required | [types.md](types.md#choose-between-neighbours) |
| T3 | A rule that turned out to be a policy a Decision selected carries `depends-on` to that Decision. | Recommended | [types.md](types.md#choose-between-neighbours) |
| T4 | Each project type declared in `wayfinder.json` has a description that truthfully defines it. | Required | [types.md](types.md#project-types) |

## metadata

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| M1 | Every frontmatter value is truthful. | Required | [metadata.md](metadata.md#baseline-frontmatter) |
| M2 | `generated` is never invented, including when the producer or time is unknown. | Required | [metadata.md](metadata.md#production-and-verification) |
| M3 | No tag stands in for kind, lifecycle, trust, or settledness. | Required | [metadata.md](metadata.md#tags) |
| M4 | A claim that materially derives from identifiable material records it in `sources`. | Required | [metadata.md](metadata.md#sources) |
| M5 | No source is invented to satisfy M4. | Required | [metadata.md](metadata.md#sources) |
| M6 | Actor records are truthful, and an unknown affiliation is `unknown`, not a guess. | Required | [metadata.md](metadata.md#actors) |
| M7 | No `verified` event records review, migration, or conformance work. | Required | [metadata.md](metadata.md#production-and-verification) |
| M8 | `stale_after` appears only with an evidenced horizon, never as a default or placeholder. | Required | [metadata.md](metadata.md#freshness) |
| M9 | An adopted settledness vocabulary is defined once in a `ways-of-working/` concept. | Recommended | [metadata.md](metadata.md#how-settled-the-subject-is) |
| M10 | Every timestamp-valued key is a datetime with an explicit UTC offset, never date-only or offset-less. | Required | [metadata.md](metadata.md#baseline-frontmatter) |

## structure

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| S1 | Every project directory names a subject, not a kind of document. | Required | [structure.md](structure.md#name-directories-after-subjects) |
| S2 | No speculative structure exists for subjects the corpus does not show. | Recommended | [structure.md](structure.md#areas) |
| S3 | Areas nest only where a subject genuinely subdivides. | Recommended | [structure.md](structure.md#areas) |
| S4 | No generic `overview.md` or other concept duplicates a generated index. | Required | [structure.md](structure.md#areas) |
| S5 | A new concept goes into an existing area or the parent unless the corpus supports a new shared subject. | Recommended | [structure.md](structure.md#areas) |
| S6 | Every concept lives with its subject. | Required | [structure.md](structure.md#placement) |
| S7 | The bundle contains no nested bundle. | Required | [structure.md](structure.md) |
| S8 | `wayfinder.json` and `wayfinder.lock` sit outside the bundle. | Required | [structure.md](structure.md) |
| S9 | `computations/`, where it exists, holds only `Attested Computation` concepts and their indexes. | Required | [structure.md](structure.md#fixed-directories) |

## identity

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| I1 | Authored slugs are readable lowercase kebab-case; externally cited IDs keep their case. | Required | [structure.md](structure.md#ids-and-paths) |
| I2 | A date appears in a path only where chronology is part of identity, never for creation time, freshness, workflow, or version. | Required | [structure.md](structure.md#ids-and-paths) |
| I3 | No filename carries status, owner, priority, or a Profile release. | Required | [structure.md](structure.md#ids-and-paths) |
| I4 | An externally cited identifier is preserved verbatim. | Required | [structure.md](structure.md#ids-and-paths) |
| I5 | No frozen path changed. | Required | [structure.md](structure.md#moves-and-frozen-paths) |
| I6 | Before a concept with an execution relationship moved, its execution record was checked for citations. | Recommended | [structure.md](structure.md#moves-and-frozen-paths) |
| I7 | A retired stable concept is deprecated, not deleted. | Recommended | [structure.md](structure.md#retirement) |
| I8 | A deprecated concept with a successor carries `superseded-by`. | Required | [structure.md](structure.md#retirement) |
| I9 | A hard-deleted stable concept had an exceptional reason that outweighs historical preservation, and its known citations and successors were assessed. | Required | [structure.md](structure.md#retirement) |

## relationships

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| R1 | No relationship is recorded in `sources`. | Required | [relationships.md](relationships.md) |
| R2 | `resolves` marks genuine closure; partial progress is `partially-resolves`. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R3 | No name is written back along an edge that already has one. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R4 | `related-to` is not standing in for a missing project name. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R5 | An unresolved internal target is a deliberate planned link, not a mistake. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R6 | Each relationship name fits its declared meaning better than its neighbours. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R7 | Each project relationship name declared in `wayfinder.json` has a description that truthfully defines it. | Required | [relationships.md](relationships.md#standard-names) |

## execution

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| E1 | No tracker issue or pull request is mirrored into the bundle. | Required | [relationships.md](relationships.md#execution-stays-external) |
| E2 | A specification opened as a tracker issue is linked, not mirrored. | Required | [relationships.md](relationships.md#execution-stays-external) |
| E3 | No specification exists both as a tracker record and as a concept. | Required | [relationships.md](relationships.md#execution-stays-external) |
| E4 | Every durable specification has exactly one lifecycle owner. | Required | [relationships.md](relationships.md#execution-stays-external) |

## log

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| L1 | The log records no non-durable source event, formatting-only edit, or unrelated activity. | Required | [structure.md](structure.md#the-log) |
| L2 | Each lifecycle event in scope has a log entry: a creation, a substantive change, a deprecation, a replacement, a move with both paths, or a new area. | Recommended | [structure.md](structure.md#the-log) |
| L3 | An entry uses a preferred lead word when one fits. | Recommended | [structure.md](structure.md#the-log) |

## mirroring

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| X1 | External material entered only through `references/`. | Required | [mirroring.md](mirroring.md) |
| X2 | Each mirror is cited by a durable concept, at genuine availability risk, and fit for repository visibility. | Required | [mirroring.md](mirroring.md) |
| X3 | Nothing was mirrored merely because a meeting, call, or thread happened. | Required | [mirroring.md](mirroring.md) |
| X4 | Mirrored text is sanitized where confidentiality demands. | Required | [mirroring.md](mirroring.md#by-medium) |
| X5 | Mirrored images are cited and optimized. | Required | [mirroring.md](mirroring.md#by-medium) |
| X6 | No video, audio, or heavy binary is committed. | Required | [mirroring.md](mirroring.md#by-medium) |
| X7 | Content that must outlive an external heavy binary is preserved as a transcript. | Recommended | [mirroring.md](mirroring.md#by-medium) |
| X8 | A non-mirrored source keeps ordinary OKF meaning in `sources[].resource`. | Required | [mirroring.md](mirroring.md#deciding-not-to-mirror) |
| X9 | A material reason for not mirroring is stated in the body. | Recommended | [mirroring.md](mirroring.md#deciding-not-to-mirror) |
| X10 | No scope descriptor replaces a known followable resource. | Required | [mirroring.md](mirroring.md#deciding-not-to-mirror) |
| X11 | Each mirrored Markdown artifact carries a `sources` entry naming its original. | Required | [mirroring.md](mirroring.md#what-a-mirror-is) |
| X12 | No cited mirror's content changed. | Required | [mirroring.md](mirroring.md#what-a-mirror-is) |

## captures

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| K1 | Every capture package has an `intake.md`, and its originals are unedited. | Required | [captures.md](captures.md#packages) |
| K2 | An original the repository did not track before was added only after the user confirmed its visibility. | Required | [captures.md](captures.md#packages) |

## permitted

Never report any of these as a concern.

| ID | Permitted |
| --- | --- |
| P1 | An area holds any number of concepts that genuinely share its subject. |
| P2 | An area has sub-areas. |
| P3 | An area holds a specifically named concept about its subject. |
| P4 | The bundle omits any of `architecture/`, `ways-of-working/`, `interactions/`, `references/`, and `computations/`. |
| P5 | `interactions/` nests by cadence or kind. |
| P6 | `references/` nests into subdirectories. |
| P7 | A source directory keeps originals in `raw/`. |
| P8 | Ordinary concepts sit at the bundle root. |
| P9 | Attested Computations live in `computations/`. |
| P10 | An Attested Computation lives with the subject it computes instead. |
| P11 | `computations/` nests. |
| P12 | An Interaction Record exists for an interaction whose combined context is durable. |
| P13 | A Business Rule uses SBVR or any other notation. |
| P14 | The verifier is a person, an agent, or a process. |
| P15 | The body names which party can answer an open point. |
| P16 | The project adopts a settledness vocabulary. |
| P17 | A concept links to several execution records. |
| P18 | A concept links to no execution record. |
| P19 | A path changes while every known citation can be repaired. |
| P20 | A concept moves at any `status`. |
| P21 | A draft is deleted. |
| P22 | Text is mirrored in full. |
| P23 | Curated context about an external system is an ordinary concept whose `resource` names it. |
| P24 | A concept carries no `verified` event. |

## Escalate with NEEDS HUMAN

The generic escalation cases of the assessment flow apply to every check
here, including an ambiguous required check and a proposed exception. This
Profile's judgments most often need context from outside the repository:

- whether an external citation can be repaired (I5, I6, I9);
- whether a hard delete's reason outweighs historical preservation (I9);
- whether material may live at the repository's visibility (X2, X4);
- whether a source is still available (X2);
- whether an actor record or affiliation is true (M6).

Name the check id and the missing context in `Concerns`.
