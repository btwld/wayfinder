# Ways of Working (canonical copy)

This is the shared process layer, canonical here in the repo so agents read it in context.
A human-readable mirror lives in the MS 365 business registry. If the two ever disagree,
this copy wins; update here first, then re-sync the mirror.

Guiding rule: humans steer, agents execute. Verification keeps pace with generation, so the
test and review layer is what holds quality.

## How work flows, discovery to done
1. Capture (intake): every request, bug, or feedback becomes an issue via a template. No side channels.
2. Triage weekly: label (type, area, priority), size, deduplicate, decide if worth pursuing.
3. Discovery and shaping: research the problem against the codebase, draft the spec, define
   acceptance criteria, get sign-off. Agents draft; humans decide. Validate before build; nothing
   reaches Ready without it.
4. Ready: clear acceptance criteria and an approved spec (definition of ready).
5. Build: on a branch, behind a feature flag when it touches live behavior. The PR references its
   issue and updates the spec in the same change. The agent writes the code and its tests.
6. Test and review: parallel review passes (security, performance, architecture, observability),
   automated and end-to-end tests in CI on the PR, and the validation gate must pass. The agent
   does first-pass review; a human owns the merge.
7. Deploy and promote: STG then PROD. On STG the running system is checked and designated users run
   UAT (accept against the acceptance criteria) before PROD; a human approves each promotion; roll
   out progressively (flag, canary, full) with rollback ready.
8. Done: acceptance criteria met, merged, spec updated (definition of done).
9. Operate and feed back: monitor, triage incidents and feedback back into issues. The loop closes.

## Human-in-the-loop gates (a human decides, not the agent)
1. Spec sign-off before build. 2. Ready gate (acceptance criteria). 3. Merge decision.
4. UAT acceptance on STG (internal product owner, or the client on delivery work). 5. Promotion
approval STG to PROD (no self-promote). 6. Fix decision on incidents.

## Environments (we run STG and PROD; promote one direction; store no client data, read live via MCP; OAuth)
- Local / sandbox: agent works here, output untrusted until verified. Not shared.
- CI on the PR: automated tests, review passes, and the validation gate run here before merge. Checks, not an environment.
- STG (staging): production-like, OAuth, no client data; verify the running system, run UAT (designated users accept against the acceptance criteria), and run the beta for named users behind a flag. A separate UAT environment is added only if a client requires isolation.
- PROD (production): promoted from STG by human approval, progressive rollout, rollback ready.

## Steps to a beta release
1. Spec approved, scope frozen to MVP. 2. Build behind a feature flag. 3. Per PR: agent review plus
validation gate plus automated and end-to-end tests in CI; human merges. 4. Promote to STG (the beta
environment), smoke-test internally. 5. Human approves; enable the flag for named beta users with a
direct deep link. 6. Observability on; feedback and bugs into issues; fix loop. 7. Exit beta when UAT
is signed off, acceptance criteria are met, and no P0 or P1 open, then promote to PROD.

## Scope discipline
Minimum viable, no creep. Handle every negative path (loading, empty, error, failure). Build in
insight and easy troubleshooting. Get stakeholder sign-off before build.

## Priority
P0 blocks the program, P1 this cycle, P2 scheduled, P3 low or parked.

## Boundary with the business registry (MS 365)
Decisions, goals, budgets, trackers, meetings, and sensitive info live in MS 365. Specs, ADRs,
RFCs, skills, and code live here. Link, never copy. Store nothing of the client's; read client data
live and read-only via an MCP.
# Ways of Working (canonical copy)

This is the shared process layer, canonical here in the repo so agents read it in context.
A human-readable mirror lives in the MS 365 business registry. If the two ever disagree,
this copy wins; update here first, then re-sync the mirror.

Guiding rule: humans steer, agents execute. Verification keeps pace with generation, so the
test and review layer is what holds quality.

## How work flows, discovery to done
1. Capture (intake): every request, bug, or feedback becomes an issue via a template. No side channels.
2. Triage weekly: label (type, area, priority), size, deduplicate, decide if worth pursuing.
3. Discovery and shaping: research the problem against the codebase, draft the spec, define
   acceptance criteria, get sign-off. Agents draft; humans decide. Validate before build; nothing
   reaches Ready without it.
4. Ready: clear acceptance criteria and an approved spec (definition of ready).
5. Build: on a branch, behind a feature flag when it touches live behavior. The PR references its
   issue and updates the spec in the same change. The agent writes the code and its tests.
6. Test and review: parallel review passes (security, performance, architecture, observability),
   automated and end-to-end tests in CI on the PR, and the validation gate must pass. The agent
   does first-pass review; a human owns the merge.
7. Deploy and promote: STG then PROD; the running system is verified on STG before PROD; a human
   approves each promotion; roll out progressively (flag, canary, full) with rollback ready.
8. Done: acceptance criteria met, merged, spec updated (definition of done).
9. Operate and feed back: monitor, triage incidents and feedback back into issues. The loop closes.

## Human-in-the-loop gates (a human decides, not the agent)
1. Spec sign-off before build. 2. Ready gate (acceptance criteria). 3. Merge decision.
4. Promotion approval between environments (no self-promote to PROD). 5. Fix decision on incidents.

## Environments (we run STG and PROD; promote one direction; store no client data, read live via MCP; OAuth)
- Local / sandbox: agent works here, output untrusted until verified. Not shared.
- CI on the PR: automated tests, review passes, and the validation gate run here before merge. Checks, not an environment.
- STG (staging): production-like, OAuth, no client data; verify the running system here; beta runs here for named users behind a flag.
- PROD (production): promoted from STG by human approval, progressive rollout, rollback ready.

## Steps to a beta release
1. Spec approved, scope frozen to MVP. 2. Build behind a feature flag. 3. Per PR: agent review plus
validation gate plus automated and end-to-end tests in CI; human merges. 4. Promote to STG (the beta
environment), smoke-test internally. 5. Human approves; enable the flag for named beta users with a
direct deep link. 6. Observability on; feedback and bugs into issues; fix loop. 7. Exit beta when
acceptance criteria are met and no P0 or P1 open, then promote to PROD.

## Scope discipline
Minimum viable, no creep. Handle every negative path (loading, empty, error, failure). Build in
insight and easy troubleshooting. Get stakeholder sign-off before build.

## Priority
P0 blocks the program, P1 this cycle, P2 scheduled, P3 low or parked.

## Boundary with the business registry (MS 365)
Decisions, goals, budgets, trackers, meetings, and sensitive info live in MS 365. Specs, ADRs,
RFCs, skills, and code live here. Link, never copy. Store nothing of the client's; read client data
live and read-only via an MCP.
# Ways of Working (canonical copy)

This is the shared process layer, canonical here in the repo so agents read it in context.
A human-readable mirror lives in the MS 365 business registry. If the two ever disagree,
this copy wins; update here first, then re-sync the mirror.

Guiding rule: humans steer, agents execute. Verification keeps pace with generation, so the
test and review layer is what holds quality.

## How work flows, discovery to done
1. Capture (intake): every request, bug, or feedback becomes an issue via a template. No side channels.
2. Triage weekly: label (type, area, priority), size, deduplicate, decide if worth pursuing.
3. Discovery and shaping: research the problem against the codebase, draft the spec, define
   acceptance criteria, get sign-off. Agents draft; humans decide. Validate before build; nothing
   reaches Ready without it.
4. Ready: clear acceptance criteria and an approved spec (definition of ready).
5. Build: on a branch, behind a feature flag when it touches live behavior. The PR references its
   issue and updates the spec in the same change. The agent writes the code and its tests.
6. Test and review: parallel review passes (security, performance, architecture, observability),
   tests and end-to-end checks in a preview environment, and the validation gate must pass. The
   agent does first-pass review; a human owns the merge.
7. Deploy and promote: dev, then staging, then production; verify at each step; a human approves
   each promotion; roll out progressively (flag, canary, full) with rollback ready.
8. Done: acceptance criteria met, merged, spec updated (definition of done).
9. Operate and feed back: monitor, triage incidents and feedback back into issues. The loop closes.

## Human-in-the-loop gates (a human decides, not the agent)
1. Spec sign-off before build. 2. Ready gate (acceptance criteria). 3. Merge decision.
4. Promotion approval between environments (no self-promote to prod). 5. Fix decision on incidents.

## Environments (promote one direction; store no client data, read live via MCP; OAuth)
- Local / sandbox: agent works here, output untrusted until verified.
- Preview (per PR): ephemeral, run end-to-end and security checks on the running change.
- Dev / integration: merged work, integration tests.
- Staging (beta): production-like, OAuth, no client data; beta runs here for named users behind a flag.
- Production: promoted by human approval, progressive rollout, rollback ready.

## Steps to a beta release
1. Spec approved, scope frozen to MVP. 2. Build behind a feature flag. 3. Per PR: agent review plus
validation gate plus preview end-to-end; human merges. 4. Integrate in dev, extended tests. 5. Promote
to staging, smoke-test internally. 6. Human approves; enable the flag for named beta users with a
direct deep link. 7. Observability on; feedback and bugs into issues; fix loop. 8. Exit beta when
acceptance criteria are met and no P0 or P1 open, then promote to production.

## Scope discipline
Minimum viable, no creep. Handle every negative path (loading, empty, error, failure). Build in
insight and easy troubleshooting. Get stakeholder sign-off before build.

## Priority
P0 blocks the program, P1 this cycle, P2 scheduled, P3 low or parked.

## Boundary with the business registry (MS 365)
Decisions, goals, budgets, trackers, meetings, and sensitive info live in MS 365. Specs, ADRs,
RFCs, skills, and code live here. Link, never copy. Store nothing of the client's; read client data
live and read-only via an MCP.
# Ways of Working (canonical copy)

This is the shared process layer, canonical here in the repo so agents read it in context.
A human-readable mirror lives in the MS 365 business registry. If the two ever disagree,
this copy wins; update here first, then re-sync the mirror.

## How work flows, intake to done
1. Capture: every request, bug, or piece of feedback becomes an issue. No side channels.
2. Triage weekly: label (type, area, priority), size, deduplicate, link to its spec.
3. Prioritize on the board (Now / Next / Later) with a milestone.
4. Ready: an issue is workable only with clear acceptance criteria (definition of ready).
5. Build: a PR references its issue and updates the spec in the same change.
6. Review and gates: pass the validation gate; keep PRs small; a second reviewer checks.
7. Done: acceptance criteria met, merged, spec updated (definition of done).

## Scope discipline
Minimum viable, no creep. Handle every negative path (loading, empty, error, failure).
Build in insight and easy troubleshooting. Get stakeholder sign-off before build.

## Priority
P0 blocks the program, P1 this cycle, P2 scheduled, P3 low or parked.

## Boundary with the business registry (MS 365)
Decisions, goals, budgets, trackers, meetings, and sensitive info live in MS 365.
Specs, ADRs, RFCs, skills, and code live here. Link, never copy. Store nothing of the
client's; read client data live and read-only via an MCP.
