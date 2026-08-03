# Ways of Working (canonical copy)

This is the shared process layer, canonical here so agents read it in context. It describes
how Concepta **project repositories** run; this repository itself carries no `knowledge/`
bundle (see AGENTS.md). A human-readable mirror lives in the MS 365 business registry. If
the two ever disagree, this copy wins; update here first, then re-sync the mirror.

Guiding rule: humans steer, agents execute. Verification keeps pace with generation, so the
test and review layer is what holds quality.

## Where things live
- Durable project knowledge — terms, decisions, ADRs, open questions, specifications the
  project maintains: the project repo's OKF bundle at `knowledge/`, following the Concepta OKF Profile.
  Start at `knowledge/index.md`. Directories name subjects, not kinds of document.
- Work items: GitHub is the source of truth for technical and product items (issues, PRs, RFCs).
  Zoho stays as the system we log to for now: it holds business and admin requests, and a copy of
  the GitHub issues so the team logs time and tracks the sprint there. Time always logs in Zoho.
- Decisions and status: the MS 365 business registry.
- Capture once at the front door: technical or product work becomes a GitHub issue (the source of
  truth) and is copied into Zoho for logging, time, and sprint visibility; business or admin
  requests (resend, remind, re-invite, chase an action) live in Zoho. Linear is parked as a
  possible future internal to-do with GitHub sync, not adopted.

## How work flows, discovery to done
1. Capture (intake): every request, bug, or feedback becomes an issue via a template. No side channels.
2. Triage weekly: label (type, area, priority), size, deduplicate, decide if worth pursuing.
3. Discovery and shaping: research the problem against the codebase, draft the spec, define
   acceptance criteria, get sign-off. Agents draft; humans decide. Validate before build.
4. Ready: clear acceptance criteria and an approved spec (definition of ready).
5. Build: on a branch, behind a feature flag when it touches live behavior. The PR references its
   issue, and the spec — wherever it lives, tracker or bundle — is updated to match before merge. The agent writes the code and its tests.
6. Test and review: code review and security review on by default, plus parallel passes
   (performance, architecture, observability); automated and end-to-end tests in CI (GitHub
   Actions); the validation gate must pass. Agent does first-pass review; a human owns the merge.
7. Deploy and promote: STG then UAT then PROD (all on AWS) via GitHub Actions. Verify the running
   system on STG; designated users run acceptance testing on UAT (and the beta runs there for named
   users) before PROD; a human approves each promotion; roll out progressively (flag, canary, full)
   with rollback ready.
8. Done: acceptance criteria met, merged, spec updated (definition of done).
9. Operate and feed back: monitor, triage incidents and feedback back into issues. The loop closes.

## Human-in-the-loop gates (a human decides, not the agent)
1. Spec sign-off before build. 2. Ready gate (acceptance criteria). 3. Merge decision.
4. UAT acceptance in the UAT environment (internal product owner, or the client on delivery work).
5. Promotion approval STG to UAT to PROD (no self-promote). 6. Fix decision on incidents.

## Environments (we run STG, UAT, and PROD, all on AWS; promote one direction; store no client data, read live via MCP; OAuth)
- Local / sandbox: agent works here, output untrusted until verified. Not shared.
- CI on the PR (GitHub Actions): automated tests, code and security review passes, and the validation gate run here before merge. Checks, not an environment.
- STG (staging): production-like, OAuth, no client data; verify the running system after merge (integration and smoke tests).
- UAT (user acceptance): production-like; designated users accept against the acceptance criteria, and the beta runs here for named users behind a flag.
- PROD (production): promoted from UAT by human approval, progressive rollout, rollback ready.

## Steps to a beta release
1. Spec approved, scope frozen to MVP. 2. Build behind a feature flag. 3. Per PR: agent review plus
validation gate plus automated and end-to-end tests in CI; human merges. 4. Verify on STG, then
promote to UAT (the acceptance and beta environment); smoke-test internally. 5. Human approves;
enable the flag for named beta users with a direct deep link. 6. Observability on; feedback and bugs
into issues; fix loop. 7. Exit beta when UAT is signed off, criteria are met, and no P0 or P1 open,
then promote to PROD.

## Maturity stage and where we are heading
We track against Anthropic's stages of AI adoption (by number of agents and your role): Step 0 gated,
Step 1 assisted (one agent, you are its pair), Step 2 parallel (orchestrate several agents in isolated
workspaces, review diffs not keystrokes), and more autonomous beyond. We are at Step 1 moving to
Step 2. The unlock: a self-verification loop we trust (tests, build, end-to-end), auto mode, and
automated code review. The human role shifts from pair to orchestrator.

## Running agents (the Step 2 setup)
- Auto mode with pre-approved safe bash and MCP commands; anything else still prompts. The human
  gates above still hold; auto mode only covers safe execution during build.
- Worktree or sandbox isolation per agent, so several run at once. Output untrusted until verified.
- Code review and security review on by default; same quality bar for human and agent code.
- Capabilities: Claude Code and Cowork, Claude Code Review and Claude Security Review, worktree
  isolation and auto mode, plus the Analytics and Compliance APIs for oversight.

## Guardrails (governance by default)
- Scoped access (RBAC), audit logs, secrets injected not embedded; run in our own cloud (AWS).
- Centrally managed policy and model settings, defined once and applied everywhere.
- Per-seat spend caps and cost tracking (serves the north star on resource burn).
- Telemetry exported (OpenTelemetry) into observability.

## How this maps to Stargate (our own platform)
The generic mechanisms above are being built as Concepta's own platform, so we run on one platform,
not stitched point tools. Open RFCs: Workspace Registry (distributes shared skills, context, rules),
Human-in-the-loop runtime (the gates), Workflow Evals (the self-verification layer), Durable workflow
execution and Schedules/Local Worker (automated pipelines), AI Builder Stack (the platform). Owner:
Leo; proposed RFCs in btwld/stargate discussions, confirm before depending on any one.

## Scope discipline
Minimum viable, no creep. Handle every negative path (loading, empty, error, failure). Build in
insight and easy troubleshooting. Get stakeholder sign-off before build.

## Priority
P0 blocks the program, P1 this cycle, P2 scheduled, P3 low or parked.

## Boundary with the business registry (MS 365)
Decisions, goals, budgets, trackers, meetings, and sensitive info live in MS 365. Durable project
knowledge (the `knowledge/` bundle), skills, and code live in the repo. Link, never copy. Store
nothing of the client's; read client data live and read-only via an MCP.

Execution records are a third place, and they stay there: anything a tracker owns the state of —
an issue, a ticket, a PR, including a spec opened as one — lives in the tracker and is linked from
a concept, never mirrored into the bundle. One artifact, one home.

Sources: Steps of AI Adoption (Anthropic, 2026); The Agentic SDLC (Augment Code, 2026).
