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
