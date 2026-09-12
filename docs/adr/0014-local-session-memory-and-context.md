# ADR-0014: Optional local session memory and context preparation

- Status: proposed
- Date: 2026-09-11
- Scope: Wayfinder application services, MCP and agent hooks; no Profile change
- Baseline: `d25427d620ea7bcb60148781414601e38e95acff`
- Delivery: [implementation plan](../local-memory-implementation-plan.md)

This is a design proposal, not shipped functionality or approval of every later
feature. Each production change needs its own reviewed implementation PR. This
change enables no capture, hooks, model downloads or change of bundle authority.

## Context

Wayfinder already retrieves local knowledge and projects its relationships. Agents
also need to recover prior work, carry the right evidence into a new task, and
identify durable outcomes without treating every conversation as project knowledge.
A small local generation model may help with those bounded tasks. Session storage,
permissions, exact metadata and source validation do not require that model.

The baseline provides:

- `validate`, `index`, `search` and `graph` in the
  [MCP server](../../packages/wayfinder_cli/lib/src/mcp_server.dart).
- Index-refresh hooks in
  [agent setup](../../packages/wayfinder_cli/lib/src/agent_setup.dart), but no
  session-capture contract.
- A generic reranking interface in the
  [embedding package](../../packages/wayfinder_embeddings/README.md).
  The CLI uses its separate knowledge-search path.
- [ADR-0009](0009-local-knowledge-retrieval.md), which prioritizes measured
  passage-selection improvements and separates relevance from answerability.
- [ADR-0013](0013-captures-layer-outside-the-bundle.md), a proposed evidence
  layer outside the bundle. That layer is not permission to commit agent sessions.

## Proposed decision

### 1. Add bounded services, not another autonomous agent

The two initial tasks are selecting supplied search passages and summarizing a
supplied session segment. Test both with the pinned runtime before building a
memory service. Use synthetic or explicitly authorized fixtures; no automatic
transcript capture is needed for that experiment. Storage and hook integration
can follow independently. Enable each model task only if its own evaluation passes.

Dart controls storage, authorization, source identity, budgets and publication.
The model receives no general filesystem, shell or network tools. Graph-assisted
context, cross-worktree handoffs and advisory review are later options, not
requirements for the first usable slice.

Keep current validation, embedding identity, search behavior and graph projection
unchanged unless a separate implementation explicitly changes their contracts.
Session features are optional and disabled until configured. Existing users need
no model download, reindexing or new permission merely to keep using Wayfinder.

### 2. Separate source events, derived memory and maintained knowledge

Store permitted session events in private application data outside the repository
and outside the bundle. Record repository, worktree, session and revision context;
a branch name alone is not a sufficient identity. Preserve source IDs and event
coverage for every checkpoint. Capture and disclosure consent come from trusted
operator configuration, never from a model-supplied flag or session ID. The current
bundle root does not itself authorize access to host transcripts or other worktrees.

Treat summaries, selected context and review suggestions as rebuildable outputs.
Keep observations, explicit decisions, rejected proposals and suggested next steps
distinct. Do not recursively summarize summaries as the sole record of evidence.
An agent-authored handoff can be stored directly with its authorship and evidence;
reprocessing it with the local model is optional.

Maintained knowledge still uses the existing authoring workflow. Propose durable
outcomes as drafts; do not automatically create routine minutes, overwrite stable
concepts or mark generated claims verified. Follow the
[concept-authoring reference](../../skills/author-knowledge-bundle/references/concept-authoring.md)
rather than introduce another set of bundle rules.

The proposed `captures/` layer remains distinct. Exporting a session or attaching
an original there requires an explicit visibility decision. Do not index that
directory, treat it as an OKF bundle, or widen search scope implicitly. Neither
an intake summary nor a session summary replaces an authoritative source document.

### 3. Preserve evidence during context preparation

Start with eligible passages and existing policy context. Later context assembly
may add graph traversal and explicitly permitted session history. Keep source text,
exact identifiers, citations, revisions and unresolved-context notices.

First compare improved model-free passage assembly with the existing baseline.
Then evaluate optional generation-based passage selection with the same source
filters and total context budget. A selection cannot recover a passage discarded
before the model sees it. Allow multiple candidates per concept in the experiment,
as recommended by ADR-0009.

Return selected source IDs, not invented confidence scores. Validate IDs and spans
in code. A valid empty selection means no candidate was selected, not a proven
absence of an answer. A failed selection falls back to the baseline with a notice;
it must not masquerade as a successful empty result.

### 4. Use one optional local generation capability

Keep Arctic XS for embeddings. Trial
[Qwen3.5-0.8B Q4_K_M GGUF](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/blob/main/Qwen3.5-0.8B-Q4_K_M.gguf)
for text-only generation. The [published pointer](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/raw/main/Qwen3.5-0.8B-Q4_K_M.gguf)
checked on 2026-09-11 lists 532,517,120 bytes. With the existing 25,279,840-byte
embedding artifact, the total is 557,796,960 bytes (about 558 MB). This is publisher
metadata, not a downloaded-and-verified release pin, measured RAM or installation
size. No vision projector is part of this text-only trial.

The original constraint is a generation model under one gigabyte. As a conservative
proposal, target less than 1,000,000,000 bytes for both installed model artifacts
combined. That stricter packaging target is a design choice, not a RAM guarantee.
Start evaluation in non-thinking mode, which is the
[model card's default](https://huggingface.co/Qwen/Qwen3.5-0.8B), with a bounded
context and schema-constrained outputs. This is a candidate, not a quality winner
or a compatibility guarantee for the pinned Wayfinder runtime. The
[published llamadart changelog](https://pub.dev/packages/llamadart/changelog)
provides Qwen3.5 support evidence, not a Wayfinder task benchmark. The trial must use
llamadart 0.8.23 and the native pins recorded in its
[NOTICE](../../packages/wayfinder_embeddings/tool/native_assets/NOTICE), or report
a separately reviewed runtime upgrade.

Preparation owns explicit download, immutable revision, SHA-256 verification,
license and attribution. Runtime uses a verified local file and never silently
switches to a hosted model. Ship no weights in Git. Record the artifact, runtime,
chat template and prompt/schema identities in evaluation results and caches.

### 5. Keep MCP and hooks as adapters

Propose `session_checkpoint`, `session_recall` and `prepare_context` tools. Keep
ordinary command adapters for hosts or lifecycle events that cannot call MCP.
Neither adapter duplicates the storage or generation implementation.

Hooks capture small permitted deltas before optional inference. They do not load
a model after every tool call, depend on shutdown completion, or continue a turn
because a semantic check failed. Preserve existing index-refresh hooks and require
separate opt-in for session capture and for disclosure to an agent host.

Use llamadart directly for local generation. The tool receives only the session
data explicitly supplied or authorized by its host adapter; an MCP connection is
not an implicit feed of the whole conversation. Returning data to a hosted agent
is a disclosure boundary even when analysis ran locally.

### 6. Keep review suggestions advisory

Outside the initial delivery, experiments may propose knowledge updates, flag
likely duplicates, compare a claim with supplied evidence, summarize tool failures,
or explain change impact using recorded relationships. They neither certify conformance nor
approve code. Missing support in a bounded evidence set does not establish falsity.
Permissions, structural validation, source checks and test outcomes stay in code.

## Alternatives and consequences

The first baseline is model-free capture plus existing retrieval. Saving a main
agent's structured handoff may remove the need for a second inference call. A
dedicated reranker is another search experiment, but does not provide session
summaries. A hosted model is not an automatic fallback for local-only operations.

The proposed model creates download, startup, memory, battery and latency costs.
Retaining it in a process requires concurrency, cancellation, idle disposal and
shutdown rules. A separate CLI process does not share an MCP process's loaded
model. Add a resident worker only after measurement justifies that extra service.

Risks include omitted decisions, invented outcomes, stale worktree context,
prompt injection in source text, duplicated memories and unintended disclosure.
Use opt-in capture, bounded inputs, provenance, deterministic validation, retention
and deletion, explicit degraded results and independent evaluation to manage them.
Valid JSON alone is not evidence that a summary or selection is correct.

## Acceptance and migration

Follow the staged acceptance gates in the implementation plan. Do not enable a
model task by default until independently reviewed examples establish a useful
benefit within declared resource budgets. Report paired regressions and abstention
errors, not only aggregate gains.

This proposal changes no Profile release, OKF field, type registry, validation
finding or authoring skill. Existing conformant bundles stay conformant. Any later
change to those contracts follows the normal release process. Generated session
records and semantic review suggestions are not Profile Review Reports.
