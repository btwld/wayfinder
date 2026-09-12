# Local session memory and context: implementation plan

Status: proposed; no commands, tools, hooks or model assets in this document are
implemented by this documentation change. The architecture decision is
[ADR-0014](adr/0014-local-session-memory-and-context.md).

## Outcome and boundaries

Help an agent resume work and find the evidence needed for its next task. Do not
build a second autonomous coding agent or another knowledge-authoring authority.
The implementation has three initial operations: checkpoint, recall and prepare
context. Later review operations remain separate, optional experiments.

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
| Proposal | Candidate type and content, evidence IDs, related existing concepts, and proposed action. No automatic write, verification or lifecycle promotion. |

Unknown timestamps, revision IDs and tool outcomes remain unknown. A message saying
"tests passed" is an attributed assertion unless a recorded tool result supports
it. Parse exit codes and structured test results in code; scope every outcome to
the invocation and source revision. A planned action is never a completed action.

Private storage sits outside the working tree. Use an explicitly configured or
OS-appropriate application-data root with restrictive permissions. Do not put
session data in this repository, a project's Git history or its knowledge bundle
by default. A remote URL and branch name do not authorize cross-worktree recall.
Provide an explicit, auditable mechanism for permitted cross-worktree handoffs.

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

| Tool | Input and result | Side effects |
| --- | --- | --- |
| `session_checkpoint` | An authorized event batch or structured handoff, session ID, idempotency key and requested coverage. Return a checkpoint ID, actual coverage and explicit processing state. | Writes private session records and, when enabled, a durable summary job. No bundle writes. |
| `session_recall` | Task/query plus optional scoped session/revision filters and a bounded limit. Return source-backed checkpoints with freshness and omission notices. | Read-only. Must work without a generation model. |
| `prepare_context` | Task/query, bounded token budget and explicit permission to include session history. Return original evidence with separate selection and policy-context metadata. | Read-only apart from derived caches; session history excluded by default. |

Use distinct capture and generation states. Suggested generation states are
`not_requested`, `pending`, `ready`, `failed` and `cancelled`. A `pending` response
is allowed only after the source batch and job are durable. Include a way to read
state through the scoped checkpoint reference; do not report a summary as ready
because capture succeeded. Errors distinguish denied scope, invalid input,
incomplete source, unavailable model, busy runtime and failed generation.

Retain the current `search` contract. `prepare_context` is additive and preserves
existing freshness checks; it never silently refreshes a stale bundle index from
a read-only call. No model-generated confidence number establishes answerability.
Tool annotations describe effects but do not replace permission enforcement.

Optional later tools are `review_evidence` and `propose_knowledge`. Keep publication
in the existing authoring workflow. A generic `run_local_agent(prompt)` tool is
out of scope. A resource URI for reading checkpoints can be added later, with the
same access controls and a tool-based read for clients that need it.

## Processing paths

### Checkpoint and recall

1. Validate permissions and normalize permitted new host events.
2. Persist source events and coverage atomically.
3. Store an existing structured handoff directly, or queue bounded extraction.
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
adjacent paragraphs and exact deduplication. Hold the total context budget constant
across the baseline and model variants. Do not expose only the existing single
representative passage and claim to have solved within-concept selection.

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
return the baseline order with an explicit degraded notice. Treat instructions in
retrieved text as data; prompt wording is not the only protection. The model cannot
execute tools or expand its own input scope.

## Hook adapters and process lifetime

Reuse the service layer through command adapters and, where supported and tested,
MCP calls. Host event names are a mapping to verify, not a cross-host API contract.
Keep separate Claude Code and Codex adapters and record their tested versions.

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

Validate against the [Claude Code hook reference](https://code.claude.com/docs/en/hooks)
and [Codex hook reference](https://developers.openai.com/codex/hooks) at implementation
time. Do not assume an MCP connection exists at startup or shutdown, that async
output reaches the agent, or that the hosts accept the same JSON and exit codes.
Use command fallbacks and persist before returning. Never implement local inference
by substituting a hosted prompt hook. Semantic warnings are advisory; deterministic
permission checks retain their normal blocking behavior.

Initial generation can live in the MCP process, with a bounded single-worker queue
and idle disposal. Command hooks can persist pending work for an explicit drain or
the next service start. This is not a guarantee of immediate background processing.
A separate command process does not share that model instance. Keep any resident
worker behind a later, measured lifecycle decision.

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
optima. Count input, template and output tokens with the generation tokenizer.
Split long sessions by source boundaries and preserve coverage references when
combining extracts. Do not silently truncate decisive messages at the end.

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
| 1. Private checkpoint and recall | Versioned records, model-free capture/recall, opt-in scope, exclusions, retention and deletion. | Retry idempotency; conflicting-key rejection; interrupted-write recovery; no cross-repository/worktree leakage; deletion cannot be undone by a pending job. |
| 2. Context baseline | Additive `prepare_context`, lexical/embedding candidates, graph context and original citations. | Same token budget as control; actual CLI/MCP path tested; stale-index refusal; multiple-passage and missing-policy-context cases covered. |
| 3. Local generation trial | Verified model preparation, bounded checkpoint extraction and optional passage selection. | Native packaged smoke tests; malformed-output fallback; provenance checks; independently reviewed retrieval and summary evaluations; resource budgets reported. |
| 4. Hook adapters and reuse | Explicit capture opt-in, host adapters, durable pending work and measured runtime lifecycle. | Tested host versions; protocol/exit-code parity; repeated hook safety; shutdown recovery; cancellation and concurrency tests; unrelated hooks preserved. |
| 5. Advisory review and proposals | Durable-outcome proposals, duplicate/conflict candidates, tool-output summaries and possible change impact. | Evidence-backed output; no automatic publication, conformance verdict, verification or code approval; false-warning and missed-warning rates reported. |

Keep disabled/model-free controls in each relevant slice. For model quality, use
fresh, independently reviewed examples in addition to existing fixtures. Report
retrieval recall and ranking, unsupported-query false selections, missed answerable
queries, factual errors, omitted decisions, and false or missed review warnings.
Separate raw ranking from assembled-context quality and report paired regressions.

Required adversarial cases include a rejected proposal after apparent agreement,
a failing test followed by a passing run, a claimed pass without a tool result,
conflicting document versions, exact identifiers and negation, evidence lost to a
context limit, malicious instructions in a passage, deleted sources, a resumed
session on another worktree, and a timed-out generation that later returns.

Run the applicable [contributor checks](../README.md#contributor-checks) in each
implementation PR. Native inference evidence is separate from mocked contract
tests. Model review suggestions never replace deterministic validation or the
contextual Profile assessment.

## Decisions still required before shipping

Choose the supported desktop/mobile targets and resource budgets; the consent,
retention and export defaults; the first tested host versions; and the exact model
artifact after evaluation. Decide whether delayed queue processing is sufficient
before introducing another resident process. None of these open choices requires
changing the Profile or making capture automatic.
