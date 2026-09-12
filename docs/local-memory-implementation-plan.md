# Local session memory and context: implementation plan

Status: proposed; no commands, tools, hooks or model assets in this document are
implemented by this documentation change. The architecture decision is
[ADR-0014](adr/0014-local-session-memory-and-context.md).

## Outcome and boundaries

First test the two requested model tasks: selecting supplied search passages and
summarizing a supplied session segment. Use synthetic or explicitly authorized
fixtures on one declared desktop CLI target with the pinned runtime. No automatic
capture, queue, retained worker or new MCP tool is required for this feasibility
test. Compare each task against its own model-free control.

Then add checkpoint/recall and passage-selection integration as separate useful
slices. Graph-assisted context, cross-worktree handoffs, mobile support, new review
tools and a resident service are deferred options, not first-release requirements.
Do not build a second autonomous agent or another knowledge-authoring authority.

The repository baseline is `d25427d620ea7bcb60148781414601e38e95acff`.
[ADR-0009](adr/0009-local-knowledge-retrieval.md) owns the accepted retrieval
choice. [ADR-0012](adr/0012-wayfinder-graph-projection.md) keeps knowledge writes
in upstream `okf`. [ADR-0013](adr/0013-captures-layer-outside-the-bundle.md)
proposes an external evidence layer; it does not enable transcript capture.

## Proposed application records

These records belong to application storage, not OKF frontmatter. Define their
versioned schemas before implementing persistence.

| Record | Required information and invariants |
| --- | --- |
| Source event | Application-assigned repository/worktree/session identity; host event identity when available; source timestamp separately from capture timestamp; event kind; permitted payload or source reference; payload hash; available revision and dirty-worktree context. |
| Checkpoint | Source event range and IDs; known omissions; goal; observations; explicit decisions; rejected proposals; unresolved questions; proposed next steps; author/model identity and source references per item. |
| Context pack | Query/task; selected source IDs and original spans; revision/content hashes; separate matches, policy context and session history; token accounting; exclusions, unresolved links and degraded-mode notices. |

Unknown timestamps, revision IDs and tool outcomes remain unknown. A message saying
"tests passed" is an attributed assertion unless a recorded tool result supports
it. Parse exit codes and structured test results in code; scope every outcome to
the invocation and source revision. A planned action is never a completed action.
A caller-supplied JSON field claiming to be a tool result remains an assertion
unless its origin is established through the authorized host adapter. Valid IDs
and citations prove source identity, not that a generated claim follows from it.

Private storage sits outside the working tree. Use an explicitly configured or
OS-appropriate application-data root with restrictive permissions. Do not put
session data in this repository, a project's Git history or its knowledge bundle
by default. A remote URL and branch name do not authorize cross-worktree recall.
Cross-worktree sharing is off in the first release, not an automatic feature.

### Capture and retention

Persist a validated event batch before acknowledging capture. Use an idempotency
key scoped to host, repository, worktree, session and source range. Retrying the
same payload returns the original checkpoint reference; reusing the key with a
different payload fails. Use transactional writes or atomic publication with a
single writer and recovery tests.

Missing, unreadable or excluded source segments produce explicit coverage gaps.
Do not claim a full-session summary when only selected events were available.
Keep original permitted events or durable source references within the retention
policy; a summary is never its own independent evidence.

Before capture can be enabled, implement exclusions, size limits, export consent,
retention and deletion. Delete or invalidate related summaries, embeddings, pending
jobs and caches with the source records. Prevent an in-flight job from republishing
deleted material. Document backup limitations rather than promise secure erasure
from media or backups the application does not control.

## Proposed MCP contracts

Names are provisional. All tools operate within an authorized startup-selected
scope. Arguments cannot select arbitrary files, directories or repositories.
Application-generated IDs and authorized host references resolve within that scope.
Bind the canonical project/worktree and allowed host transcript source at trusted
setup, separately from the existing bundle root. Consent comes from operator
configuration outside model-controlled inputs. A request to include history, a
session ID or a claimed host identity cannot grant access. Reject mismatches; check
policy again at read, job execution and publication. Apply the same rules to caches.
Resolve transcript references without arbitrary path or symlink escape. These are
application controls, not isolation from processes running as the same OS user.

| Tool | Input and result | Side effects |
| --- | --- | --- |
| `session_checkpoint` | An authorized event batch or structured handoff, session ID, idempotency key and requested coverage. Return a checkpoint ID, actual coverage and explicit processing state. | Writes private session records and optional summary output. Durable jobs are deferred. No bundle writes. |
| `session_recall` | Either an exact scoped checkpoint ID, or a query with scoped filters and a bounded limit. Exact lookup returns capture/summary state and actual coverage, including failed or unsummarized records. | Read-only. Requires disclosure permission; works without a generation model. |
| `prepare_context` | Task/query, output budget and a request to include session history. The service independently checks disclosure permission. Return original evidence with selection, policy-context and budget metadata. | Read-only apart from derived caches; session history excluded by default. |

Capture success is independent of summary success. Start with `not_requested`,
`running`, `ready` and `failed` summary states, with bounded synchronous extraction
on explicit requests. Recover an interrupted `running` attempt as failed and reject
its late publication after a retry. An unavailable model never discards a capture. Add `pending`
and `cancelled` only with a durable job and a tested drain/recovery path; name the
next-start or explicit-drain trigger in the response, not an implied running worker.
Exact checkpoint lookup remains available after failure or a client timeout.

Retain the current `search` contract. `prepare_context` is additive and preserves
existing freshness checks; it never silently refreshes a stale bundle index from
a read-only call. No model-generated confidence number establishes answerability.
Tool annotations describe effects but do not replace permission enforcement.

Optional later tools are `review_evidence` and `propose_knowledge`. Keep publication
in the existing authoring workflow. A generic `run_local_agent(prompt)` tool is
out of scope. MCP resources and new proposal record types are also deferred.

## Processing paths

### Checkpoint and recall

1. Validate permissions and normalize permitted new host events.
2. Persist source events and coverage atomically.
3. Store a structured handoff directly; run bounded extraction only when requested.
   Automatic event hooks initially capture only; explicit checkpoint calls may extract.
   A durable queue is a later option, not required for the first checkpoint.
4. Validate extracted source IDs and separate observations from proposals.
5. Publish a checkpoint only if its sources are still present and compatible.
6. On recall, compare worktree/revision context and show stale evidence as history,
   not as a claim about the current files.

Start recall with metadata and lexical retrieval. Add existing local embeddings
only if evaluation justifies them; keep their namespace separate from bundle
vectors. A disabled or missing generation model does not disable capture or recall.

### Context preparation and passage selection

Start with existing retrieval and explicit scope/lifecycle policy. Preserve
`matches`, policy-selected `context` and `notices`; authority is not a model score.
Include only authorized session history, clearly marked as historical source data.

The CLI currently calls `KnowledgeIndex` through
[`WayfinderKnowledge.search`](../packages/wayfinder_cli/lib/src/knowledge.dart).
The generic [`SearchReranker`](../packages/wayfinder_embeddings/lib/src/search/search_reranker.dart)
interface is reusable, but implementing it alone does not connect it to that CLI
path. The implementation slice must test the actual MCP-to-service call chain.

Evaluate two or three candidate passages per concept before reduction, bounded
adjacent paragraphs and exact deduplication. Compare (A) shipped retrieval, (B)
improved model-free assembly, and (C) the exact candidates from B with local
selection. Keep source eligibility and output budget fixed; do not attribute B
improvements to the model. Test candidate-order sensitivity. A post-search selector
over existing results is a valid narrow first slice, but cannot fix passages
already discarded by within-concept reduction.

The local selection task returns only supplied passage IDs in order. A minimal
illustrative result is:

```json
{
  "selected_ids": ["passage-17", "passage-04"]
}
```

Reject unknown IDs, duplicates, invalid types, oversize outputs and out-of-scope
references. Reconstruct final passages and citations from trusted stored records,
not model-generated paths or line numbers. Preserve policy-required context even
when the model excludes it from query-ranked matches. Report when a budget prevents
its inclusion instead of silently dropping it.

A valid empty selection and an inference failure are distinct. For a failure,
return the model-free order for the same eligible candidates with an explicit
degraded notice, under the same output budget. Treat instructions in
retrieved text as data; prompt wording is not the only protection. The model cannot
execute tools or expand its own input scope.

## Hook adapters and process lifetime

Reuse the service layer through command adapters and, where supported and tested,
MCP calls. The lifecycle table describes options, not required first-release hooks.
Host event names are a mapping to verify, not a cross-host API contract.
Implement one declared host/version first, then test a separate adapter for the
other host. Shared event names do not establish identical behavior.

| Lifecycle event | Proposed action |
| --- | --- |
| Start or resume | Read a cached handoff, validate scope and freshness, then inject only permitted bounded context. |
| Before compaction | Capture new permitted events before optional summarization. |
| Relevant tool result or edit | Record allowed metadata and changed paths; combine repeated events rather than invoke the model every time. |
| Turn stop | Checkpoint the new segment and preserve the existing index-refresh behavior. Guard against recursive stop handling. |
| Session end | Flush pending capture data. Do not depend on inference completing during shutdown. |
| Git merge, checkout or rewrite | Preserve index refresh and invalidate incompatible derived context; do not infer that a Git event authorizes transcript capture. |

Existing hook setup is in
[`agent_setup.dart`](../packages/wayfinder_cli/lib/src/agent_setup.dart).
The current `setup --hooks` behavior must not silently gain transcript access.
Add separate opt-in configuration for capture and for returning session material
to the host. Preserve unrelated hooks and settings; test installation, repeat
installation, removal, quoting and paths containing spaces or shell characters.

Use an event-specific response adapter: an MCP checkpoint result is not a hook
control envelope. Never forward model JSON as hook decisions. Capture-only Stop
hooks return a host-valid no-op, without continuation text or blocking decisions;
read context through recall or a tested context-accepting event. A direct `mcp_tool`
hook needs a compatible deterministic response wrapper, not just the tool name.

The [Claude Code](https://code.claude.com/docs/en/hooks) and
[Codex](https://developers.openai.com/codex/hooks) references checked on 2026-09-11
support command and connected-MCP hooks. Codex MCP hooks do not request per-call
tool approval and do not support SessionEnd. Claude command async results can
reach a later turn; they are not guaranteed at teardown. Treat these as documented
capabilities, not tested installed versions. Startup may precede MCP connection;
use command fallbacks. Persist before returning; test exact event JSON and exit
codes. Hosted prompt/agent hooks are not local inference.

Start generation with explicit bounded calls. Only add model retention or a
single-worker queue after measuring startup and hook needs. A command process does
not share the MCP process model. Pending work needs a documented drain, not a
promise that an unstarted worker is processing it. A resident service is deferred.

The existing server opens and closes retrieval resources per operation. Any retained
generation runtime needs explicit cancellation, queue limits, busy behavior and
shutdown tests. Use separate chat contexts per job; model reuse is not conversation
reuse. Cancellation after capture does not undo a durable source write. Keep stdout
reserved for the protocol and diagnostics free of captured payloads.

## Model trial and budgets

The candidate and file-size basis live in ADR-0014. Keep the embedding model and
its preprocessing identity unchanged. No weights are added by this proposal.

Start experiments with text-only input, non-thinking mode, a 4,096-token total
context, and task-specific output caps. These are proposed settings, not measured
optima. Count model input, template and generated output with its tokenizer.
The returned context pack has a separate consumer budget: identify its tokenizer
or label counts as estimates and enforce a byte limit. Do not equate Qwen tokens
with host tokens. Budget the entire serialized pack, including source text,
citations, notices and history, not just the short selected-ID JSON. Model-free
preparation cannot require loading Qwen merely to count output tokens.
Split long sessions at source boundaries; preserve coverage and do not silently
truncate decisive messages at the end.

Record immutable model revision, exact byte count, verified SHA-256, license,
llamadart/native runtime, chat template, prompt/schema version, context settings,
platform and backend. Verify text generation and structured-output behavior with
the repository's pinned runtime before assuming upstream compatibility. Test other
quantizations only as separately identified candidates.

Measure combined model bytes, packaged installation size, cold startup, warm
latency, queue delay, peak process memory and output tokens. The sub-1-GB model
artifact target is not a sub-1-GB RAM guarantee. Hardware and latency/memory budgets
must be declared before deciding whether a task should become a default.

Local-only generation never sends source data to a fallback API. Material returned
to a hosted agent may enter that agent's context; require a separate disclosure
policy, apply exclusions before storage and output, and minimize returned text.

## Delivery slices and acceptance gates

| Slice | Deliverable | Gate before enabling |
| --- | --- | --- |
| 0. Two-task feasibility | Explicit local generation on supplied passage sets and session segments; no automatic capture or new service. | Verified artifact; pinned-runtime smoke; separately judged selection and summary quality against model-free controls; measured startup, latency and memory on one named desktop target. |
| 1. Private checkpoint and recall | Model-free records, exact checkpoint lookup, opt-in scope, exclusions, retention and deletion; optional extraction only if its trial passes. | Retry/conflicting-key handling; crash recovery; trusted consent; no cross-worktree leakage; no resurrection after deletion. |
| 2. Passage-selection integration | Additive `prepare_context` with original citations, existing policy context and optional selection only if its trial passes. | Actual CLI/MCP path tested; stale-index refusal; A/B/C controls; separate model/consumer budgets; fallback and missing-policy-context tests. |
| 3. One-host capture adapter | Capture-only lifecycle hooks with separate consent; extend to another host only after its tests. | Version-pinned event envelopes; no Stop continuation; late-result and teardown recovery; unrelated hooks preserved. |

Slices 1 and 2 are independent. Graph-assisted expansion, review/proposal tools,
cross-worktree sharing, mobile deployment and retained workers require later scope
decisions and evidence. They are not commitments of this initial delivery.

Keep disabled/model-free controls in each relevant slice. For model quality, use
fresh, independently reviewed examples in addition to existing fixtures. Report
retrieval recall and ranking, unsupported-query false selections, missed answerable
queries, factual errors, omitted decisions, and false or missed review warnings.
Separate raw ranking from assembled-context quality and report paired regressions.

Required adversarial cases include a rejected proposal after apparent agreement,
a failing test followed by a passing run, a claimed pass without a tool result,
conflicting document versions, exact identifiers and negation, evidence lost to a
context limit, malicious instructions in a passage, deleted sources, a resumed
session on another worktree, and a timed-out generation that later returns. Also
test forged disclosure flags, spoofed tool-result origins, differing tokenizers,
large reconstructed passages after short ID output, failed-checkpoint exact lookup,
and hook output that would accidentally continue an agent turn.

Run the applicable [contributor checks](../README.md#contributor-checks) in each
implementation PR. Native inference evidence is separate from mocked contract
tests. Model review suggestions never replace deterministic validation or the
contextual Profile assessment.

## Decisions still required before shipping

Choose one supported desktop CLI target, resource budgets, consent/retention
defaults, the first host/version and the evaluated artifact. A model card, upstream
example or valid JSON is not evidence of task quality. Keep failed tasks disabled
and retain their model-free path. Broader targets and persistent workers are later
decisions; none requires changing the Profile or making capture automatic.
