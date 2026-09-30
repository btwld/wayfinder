# Acceptance and evaluation

All gates below apply to the future implementation. This planning PR has not run
them. Record commands, environment, source/runtime revisions, actual outcomes,
and limitations in the implementation PR. A failure remains visible.

## Deterministic test matrix

Use synthetic fixtures and temporary local Git repositories in the default unit
suite. Network calls must be mocked there. Optional live-source checks are
separate, bounded, and never replace reproducible tests.

| ID | Case | Required result |
| --- | --- | --- |
| T01 | Invalid manifest, duplicate IDs, unsupported adapter, missing required path | Reject with actionable diagnostics before writes |
| T02 | Move a branch/tag after initial resolve | Normal resolve preserves the locked commit; only upgrade moves it |
| T03 | Missing/corrupt cached bytes, missing locked commit, truncated tree, rate limit | Explicit incomplete/error state; no silent fallback to main |
| T04 | Same source fetched twice | Identical canonical content/lock; fetch bookkeeping does not churn the bundle |
| T05 | Duplicate Dart skills in both distributions | One canonical identical source plus aliases; divergent copies remain explicit |
| T06 | YAML recipe differs from generated skill | Preserve both source identities and differences; do not conflate instructions |
| T07 | Markdown includes, fences, link definitions, duplicate headings, Unicode | Accurate original spans and links; unresolved include/cycle is explicit |
| T08 | Glossary backed by data/template rather than a Markdown page | Correct backing files and term IDs; no guessed successful file |
| T09 | Released/unreleased changelog sections, prerelease, patch and stable families | Frozen intended window and paired Dart versions; correct source dates |
| T10 | Migration before/after timeline or platform not stated | Preserve known scope; unknown scope is not made universal |
| T11 | Design proposal with no landing evidence; closed design issue | No shipped claim; execution record remains link-only |
| T12 | Changed per-file license, mixed prose/code licenses, unlicensed linked document | Block affected redistribution; retain required notices on export |
| T13 | Prompt injection, script tags, malicious commands inside imported skills | Treated as data; no process invocation or policy changes |
| T14 | Traversal, symlink escape, encoded traversal, Windows paths, case collision | No read/write outside permitted roots |
| T15 | Redirect to private IP/host, credentials, large response, timeout | Reject/bound acquisition; no secret logging or partial success |
| T16 | Changed source feeding multiple concepts; one concept using several sources | Complete impact set and exact many-to-many evidence mapping |
| T17 | Manual edit or source change after proposal review | Apply refuses stale baseline; existing content unchanged |
| T18 | Failure/interruption between file updates; concurrent apply | Consistent rollback/recovery; no mixed index/log/content state |
| T19 | No-op apply; formatting-only edit; repeated run | No duplicate log entries, content drift, or repeated timestamps |
| T20 | Source removed versus temporarily unavailable | Different findings; neither silently deletes/deprecates knowledge |
| T21 | Index projection | Byte-exact Profile golden cases, directory indexes, ordering, descriptions, encoded links |
| T22 | Profile lock missing/stale and validate invoked | Independent OKF result plus unsupported Profile; no network or writes |
| T23 | Configured 2026.3 versus unchanged legacy 2026.2 examples | Exact dispatch retained; no new legacy registries in 2026.3 |
| T24 | Generated author/source verification and API deprecation | Truthful provenance and document lifecycle; no fabricated verified state |
| T25 | Graph JSON/Mermaid and MCP stdio on completed bundle | Existing contract preserved; real file/line citations; no typed-edge claim |
| T26 | Native index missing/model unavailable or semantic search not run | Explicit skipped/blocked result, not an inferred pass |
| T27 | Standalone public bundle export | Rights envelope included; no secrets, source cache, models, or transient index |

## Corpus coverage gates

Pilot: cover each of the five named skills in AGENT; include supporting framework
and app architecture, relevant glossary knowledge, and one checked historical
migration. Avoid artificially creating one concept for each heading. Report source
coverage, exclusions with reasons, and source-to-concept mappings.

Expanded demonstration: inventory the full Dart and Flutter skill catalogs without
double-counting copies; cover the three explicitly locked stable Flutter release
families and corresponding released Dart changes; include selected migration
material connected to represented subjects and a reviewed design-document set.
Prefer a small set (up to three) of genuinely useful public design documents, not
a dump of issue discussions. An unavailable or unclear-license design document
creates a named gap. Do not claim this dimension complete without admitted evidence.

Every factual derived concept must have followable source evidence. Every copied
or adapted artifact must have an applicable rights decision and required notices.
Every used actor/tag/type must resolve in the actual Profile binding. Preserve
uncertainty and disagreement instead of averaging them into a stable assertion.

## Semantic evaluation: source evidence before answer quality

Create `evaluation/queries.json` in the demonstration project. For each question,
record an ID, exact source-lock hash, baseline SDK/platform scope, expected concept
IDs, evidence spans, allowed answer claims, and explicit non-claims. The expected
set is reviewed by an agent reading the primary evidence; it is not generated by
using the very search results being scored as ground truth.

Use at least these eight query families. The wording can be refined only while
preserving the tested distinction:

| Query | Evidence and distinction |
| --- | --- |
| Where should caching live in the app architecture, and how should I test it? | App-architecture sources plus architecture and testing skills; framework architecture is not an app folder prescription |
| Why does a list inside a column fail layout, and which procedure helps? | Constraint explanation plus layout-fix skill and relevant terminology |
| When should a Flutter app have an extra domain/use-case layer? | Conditional guidance; no invented mandatory layer |
| How do widget tests differ from Dart unit tests for this change? | Both actual skills; common verification steps and distinct runtime scope |
| For the selected SDK baseline, how do I migrate the chosen deprecated API? | Exact migration timeline/platform; not an unsupported current-version claim |
| What is the relationship between widgets, elements, and render objects? | Framework overview/Inside Flutter plus terminology; no universal performance guarantee |
| Did this selected design proposal ship, and where is the evidence? | Separate proposal, implementation link, and released behavior; abstain when evidence is missing |
| Does the bundle establish that this advice applies to an unreleased future SDK? | Negative control: state the coverage limit, do not invent compatibility |

Compare a locked raw-source retrieval baseline with the curated bundle using the
same Wayfinder runtime/model and fixed question set. A raw-source comparison is
an evaluation-only temporary plain-OKF corpus, not the public Profile bundle or
permission to mirror sources. It must have complete source mappings, and its
preparation must not introduce curated answer hints. Record chunking/token-budget
differences so an improvement is not attributed to curation without qualification.

Report passage retrieval separately from final agent answers. Measure whether the
first five passages contain each required evidence item, source/version citation
accuracy, unsupported claims, and correct abstention. Also inspect citation
completeness after the agent follows linked concepts; do not claim Wayfinder itself
performed multi-hop reasoning. Record cold/warm timing only if actually measured.
Do not promise quality or speed gains from the design alone.

Proposed release gate: all eight questions have reviewed evidence targets; final
answers contain zero unsupported claims and correct source/version attribution;
the negative control abstains. At least six of eight questions should have required
initial evidence in the first five results. Treat this as a small demo acceptance
threshold, not a statistically proven retrieval benchmark. Record failures and
query changes; do not tune on the evaluation set and claim general superiority.

## End-to-end and maintenance gates

On a clean checkout, execute the real importer workflow, resolve the Profile with
Wayfinder, run automated validation, perform contextual Profile Review, build the
native search index, run actual search and graph checks, and complete an MCP stdio
handshake/tool cycle. Report native prerequisites and platform actually tested.
No external source fetch is allowed during read-only validation.

Repeat the same locked import and apply: the tracked example must be byte-identical.
Then advance a synthetic upstream source: only dependent proposals should change.
Test a manual bundle edit and a source-license change before apply; both invalidate
the prior approval. Confirm source locks and applied provenance expose pending
updates correctly. Confirm old evidence remains traceable after a concept rename.

Run the repository's existing CI checks plus standalone importer tests and a
network-independent example gate. Add a bounded native smoke/evaluation job only
where the existing runtime setup supports it; an explicit separate native check is
preferable to silently skipping the core demonstration. Do not add scheduled live
upstream crawling or auto-publication to the repository.

## Planning-only checks

For this handoff, check JSON syntax, the example's shape against the merged
`main` project schema, required source IDs and unique work IDs, local documentation links,
Markdown fence balance, and whitespace. These checks do not resolve Git sources,
validate an OKF bundle, assess legal rights, or run the proposed importer.
