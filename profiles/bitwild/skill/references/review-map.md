# Review map

The generic `author-knowledge-bundle` assessment flow owns the report. Judge these
checks independently of validation; do not duplicate machine findings as judgment.
Routine scope is changes and directly affected placement/indexes/links/dependents;
adoption, upgrades, migrations and reorganizations use whole-bundle scope. Mark
not applicable only after checking scope.

**Required** violations mean CHANGES REQUIRED. **Recommended** deviations are
concerns and require changes only without a context-supported reason.
**Permitted** cases never become concerns. Report `Reviewed` by section name:
C=capture, T=types, M=metadata, S=structure, I=identity, R=relationships,
E=execution, L=log, X=mirroring, K=captures.

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| C1 | Concepts pass the durable-knowledge test; occurrence alone is insufficient. | Required | [capture.md](capture.md#source-events-are-not-concepts) |
| C2 | Promote outcomes needing independent status, provenance, relationships, reuse, replacement or history. | Recommended | [capture.md](capture.md#promote-or-embed-an-outcome) |
| C3 | Keep small outcomes embedded when never referenced independently. | Recommended | [capture.md](capture.md#promote-or-embed-an-outcome) |
| C4 | Start ambiguous outcomes embedded. | Recommended | [capture.md](capture.md#promote-or-embed-an-outcome) |
| C5 | Split materially different verification or lifecycles. | Recommended | [capture.md](capture.md#split-a-concept) |
| C6 | Interaction Records need durable combined context; never routine minutes. | Required | [capture.md](capture.md#interaction-records) |
| C7 | A single durable outcome links directly to its source, without an Interaction Record. | Recommended | [capture.md](capture.md#interaction-records) |
| T1 | Standard types match intended meaning. | Required | [types.md](types.md#choose-between-neighbours) |
| T2 | Project types match their declared meaning. | Required | [types.md](types.md#choose-between-neighbours) |
| T3 | A policy rule carries `depends-on` to its selecting Decision. | Recommended | [types.md](types.md#choose-between-neighbours) |
| T4 | Project type descriptions truthfully define their names. | Required | [types.md](types.md#project-types) |
| M1 | Every frontmatter value is truthful. | Required | [metadata.md](metadata.md#baseline-frontmatter) |
| M2 | Never invent generated actor/time. | Required | [metadata.md](metadata.md#production-and-verification) |
| M3 | Tags never substitute for kind, lifecycle, trust or settledness. | Required | [metadata.md](metadata.md#tags) |
| M4 | Record identifiable material derivation in `sources`. | Required | [metadata.md](metadata.md#sources) |
| M5 | Never invent sources to satisfy M4. | Required | [metadata.md](metadata.md#sources) |
| M6 | Actor records are truthful; unknown affiliation stays `unknown`. | Required | [metadata.md](metadata.md#actors) |
| M7 | Review, migration and conformance alone never create verification. | Required | [metadata.md](metadata.md#production-and-verification) |
| M8 | Use stale_after only for evidenced horizons, never defaults/placeholders. | Required | [metadata.md](metadata.md#freshness) |
| M9 | Define adopted settledness vocabulary once in ways-of-working. | Recommended | [metadata.md](metadata.md#how-settled-the-subject-is) |
| M10 | Timestamp keys use datetimes with explicit UTC offsets. | Required | [metadata.md](metadata.md#baseline-frontmatter) |
| S1 | Project directories name subjects, never document kinds. | Required | [structure.md](structure.md#name-directories-after-subjects) |
| S2 | No speculative structure beyond the corpus. | Recommended | [structure.md](structure.md#areas) |
| S3 | Nest areas only for genuine subject subdivisions. | Recommended | [structure.md](structure.md#areas) |
| S4 | No generic overview or concept duplicates a generated index. | Required | [structure.md](structure.md#areas) |
| S5 | Use existing area/parent unless a new shared subject is justified. | Recommended | [structure.md](structure.md#areas) |
| S6 | Concepts live with their subjects. | Required | [structure.md](structure.md#placement) |
| S7 | No nested bundles. | Required | [structure.md](structure.md) |
| S8 | Config and lock stay outside the bundle. | Required | [structure.md](structure.md) |
| S9 | computations holds only Attested Computations and their indexes. | Required | [structure.md](structure.md#fixed-directories) |
| I1 | Readable kebab-case slugs; cited identifiers retain case. | Required | [structure.md](structure.md#ids-and-paths) |
| I2 | Dates in paths express intrinsic chronology, never mutable metadata. | Required | [structure.md](structure.md#ids-and-paths) |
| I3 | Filenames omit status, owner, priority and Profile release. | Required | [structure.md](structure.md#ids-and-paths) |
| I4 | Preserve externally cited IDs verbatim. | Required | [structure.md](structure.md#ids-and-paths) |
| I5 | No frozen path changed. | Required | [structure.md](structure.md#moves-and-frozen-paths) |
| I6 | Before moving execution-linked concepts, inspect execution records for citations. | Recommended | [structure.md](structure.md#moves-and-frozen-paths) |
| I7 | Deprecate retired stable concepts instead of deleting. | Recommended | [structure.md](structure.md#retirement) |
| I8 | Deprecated concepts with successors carry superseded-by. | Required | [structure.md](structure.md#retirement) |
| I9 | Stable hard deletes need exceptional justification and assessed citations/successors. | Required | [structure.md](structure.md#retirement) |
| R1 | No relationship is recorded in `sources`. | Required | [relationships.md](relationships.md) |
| R2 | resolves means closure; partial progress is partially-resolves. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R3 | No redundant name back along an already typed edge. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R4 | related-to does not hide a missing project name. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R5 | Unresolved internal targets are deliberate planned links. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R6 | Names fit declared meanings better than neighbors. | Recommended | [relationships.md](relationships.md#choose-a-name) |
| R7 | Project relationship descriptions truthfully define names. | Required | [relationships.md](relationships.md#standard-names) |
| E1 | Never mirror issues or PRs into the bundle. | Required | [relationships.md](relationships.md#execution-stays-external) |
| E2 | Link tracker specifications; do not mirror. | Required | [relationships.md](relationships.md#execution-stays-external) |
| E3 | No specification exists as both tracker record and concept. | Required | [relationships.md](relationships.md#execution-stays-external) |
| E4 | Durable specifications have exactly one lifecycle owner. | Required | [relationships.md](relationships.md#execution-stays-external) |
| L1 | Log excludes non-durable events, formatting and unrelated activity. | Required | [structure.md](structure.md#the-log) |
| L2 | Log creations, substantive changes, deprecations, replacements, moves (both paths) and new areas. | Recommended | [structure.md](structure.md#the-log) |
| L3 | Use a preferred lead word when it fits. | Recommended | [structure.md](structure.md#the-log) |
| X1 | External material entered only through `references/`. | Required | [mirroring.md](mirroring.md) |
| X2 | Mirrors need durable citations, genuine availability risk and suitable visibility. | Required | [mirroring.md](mirroring.md) |
| X3 | Event occurrence alone never justifies mirroring. | Required | [mirroring.md](mirroring.md) |
| X4 | Sanitize mirrored text where confidentiality demands. | Required | [mirroring.md](mirroring.md#by-medium) |
| X5 | Mirror only cited, optimized images. | Required | [mirroring.md](mirroring.md#by-medium) |
| X6 | Never commit video, audio or heavy binaries. | Required | [mirroring.md](mirroring.md#by-medium) |
| X7 | Preserve needed heavy-binary content as a transcript. | Recommended | [mirroring.md](mirroring.md#by-medium) |
| X8 | Non-mirrored sources retain ordinary OKF resource meaning. | Required | [mirroring.md](mirroring.md#deciding-not-to-mirror) |
| X9 | State material non-mirroring reasons in the body. | Recommended | [mirroring.md](mirroring.md#deciding-not-to-mirror) |
| X10 | Never replace a followable resource with a scope descriptor. | Required | [mirroring.md](mirroring.md#deciding-not-to-mirror) |
| X11 | Markdown mirrors cite their originals in sources. | Required | [mirroring.md](mirroring.md#what-a-mirror-is) |
| X12 | Never edit cited mirror content. | Required | [mirroring.md](mirroring.md#what-a-mirror-is) |
| K1 | Capture packages have intake.md and unedited originals. | Required | [captures.md](captures.md#packages) |
| K2 | Newly tracked originals require confirmed repository visibility. | Required | [captures.md](captures.md#packages) |

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
