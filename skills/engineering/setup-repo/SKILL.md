---
name: setup-repo
description: Configure this repo for the engineering skills — set up its issue tracker, triage label vocabulary, and knowledge bundle. Run once before first use of the other engineering skills.
disable-model-invocation: true
---

# Setup Repo

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the label vocabulary for the two triage axes: audience (`afk`/`hitl`) and state (`needs-triage`/`ready`)
- **Knowledge bundle** — durable project knowledge as OKF concepts under `knowledge/`, following the Concepta OKF Profile
- **Agent instructions** — `AGENTS.md` as the source of truth, with `CLAUDE.md` importing it via `@AGENTS.md`

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` at the repo root — does it exist? Is there already an `## Agent skills` section in it? Does it point at the knowledge bundle?
- `CLAUDE.md` at the repo root — does it exist? Does it import `AGENTS.md` (a line containing `@AGENTS.md`)?
- `knowledge/` — does the bundle exist? If so, read `knowledge/index.md` and `knowledge/profile.md`
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use
- Is the `triage` skill installed? (a `triage` skill folder alongside this one, or `triage` in your available skills.) This decides whether Section B runs at all.

### 2. Present findings and ask

Summarise what's present and what's missing. Then take the sections in order — one section, one answer, then the next.

Lead each section with the recommended answer so the user can accept it in a word. Give a one-line explainer only when the choice genuinely branches; skip a section entirely when exploration already settled it (Section B when `triage` isn't installed; Section C is a fixed structure that needs no question).

**Section A — Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-tickets`, `triage`, `to-spec`, and `qa` read from and write to it — they need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Otherwise (or if the user prefers), offer:

- **GitHub** — issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab** — issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Local markdown** — issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.) — ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

Record the choice in `docs/agents/issue-tracker.md`. The GitHub template carries a "PRs as a request surface" flag, defaulted **off** — leave it off and don't raise it; a user who wants external PRs in the triage queue can flip the flag in the file later.

**Section B — Triage label vocabulary.** Skip this section entirely if the `triage` skill isn't installed (exploration told you) — an uninstalled skill needs no labels.

If it is installed, ask exactly one question:

> Do you want to keep the default triage labels? (recommended: **yes**)

The defaults are two axes — **audience** (`afk`, `hitl`) and **state** (`needs-triage`, `ready`) — each label string equal to its name. On **yes**, write them as-is. Only if the user says no — usually because their tracker already uses other names (e.g. `bug:triage` for `needs-triage`) — collect the overrides so `triage` applies existing labels instead of creating duplicates.

**Section C — Knowledge bundle.** The Concepta OKF Profile fixes this configuration,
so there is nothing to ask. Report the versions declared in
`knowledge/profile.md` when the bundle already exists. Otherwise follow the
`okf-profile` skill's canonical [SEEDING.md](../../okf-profile/SEEDING.md) exactly;
it owns the root-file contents and the conditions they implement.

**Create no directories here.** Canonical seeding creates only the bundle root;
the `okf-profile` skill decides later structure from the project's actual
knowledge.

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` and `## Documentation` blocks to add to `AGENTS.md` (see step 4)
- The `@AGENTS.md` line for `CLAUDE.md`, if it isn't already there
- The bundle's five root files, when they need seeding
- The contents of `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` (the latter only when `triage` is installed)

Let them edit before writing.

### 4. Write

Agent instructions live in **`AGENTS.md`**, and `CLAUDE.md` just imports it. Set both up.

**`AGENTS.md` — the source of truth.**

- If `AGENTS.md` exists, edit it. If it doesn't, create it.
- Add the `## Agent skills` and `## Documentation` blocks below, or update them in place if they already exist — don't append duplicates, and don't overwrite user edits to the surrounding sections.
- `AGENTS.md` is the operational bootstrap: commands, safety constraints, generated-file rules, and pointers into the bundle. Durable domain and architecture knowledge belongs in concepts, so keep it out of `AGENTS.md`.

**`CLAUDE.md` — a thin pointer to `AGENTS.md`.**

- If `CLAUDE.md` doesn't exist, create it with a single `@AGENTS.md` line (and a one-line note that the real instructions live in `AGENTS.md`).
- If `CLAUDE.md` exists but has no line containing `@AGENTS.md`, add one near the top and leave the rest alone.
- If it already imports `AGENTS.md`, leave it.

The blocks for `AGENTS.md`:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Knowledge bundle

Durable project knowledge is an OKF bundle at `knowledge/`, following the
Concepta OKF Profile (versions declared in `knowledge/profile.md`). Start at
`knowledge/index.md`, then the area index, then the concept.

Follow the `okf-profile` skill before writing anything under
`knowledge/` — including before creating a directory there.

## Documentation

Durable docs are OKF concepts in `knowledge/` — check `knowledge/index.md`
first to find the right concept, then open it directly. Execution records are
not knowledge: anything a tracker owns the state of — an issue, a ticket, a
pull request, including a spec opened as one — lives in the issue tracker (see
`docs/agents/issue-tracker.md`) and is linked from concepts, never mirrored
into the bundle.

"Specification" is a genre, not a location. A specification the project
maintains as durable knowledge, whose only state is `status`, is a
`Specification` concept filed with its subject. Every durable specification has
exactly one lifecycle owner; one artifact never lives in both places (profile
§5.2, §7.3).
```

Include the `### Triage labels` sub-block, and write `docs/agents/triage-labels.md`, only when `triage` is installed and Section B ran. When it isn't, both are omitted.

Then write the config files using the seed templates in this skill folder:

- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md) — local-markdown issue tracker
- [triage-labels.md](./triage-labels.md) — label mapping (only if `triage` is installed)

Issue-tracker and label config stay under `docs/agents/` — operational agent configuration, not durable knowledge, so it lives outside the bundle. For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description. GitHub is the only tracker with a seed template in this folder; for GitLab or anything else, adapt the GitHub template or write from scratch.

### 5. Done

Tell the user the setup is complete and which engineering skills will now read from these files. Point out that `AGENTS.md` is the source of truth (with `CLAUDE.md` importing it), the bundle starts at `knowledge/index.md` with its versions declared in `knowledge/profile.md`, and `/domain-modeling` will fill it as terms and decisions get resolved — writing concepts at the root first and growing subject directories out of them, so the layout reflects what the project actually knows rather than a guess made today. Mention they can edit `docs/agents/*.md` and bundle concepts directly later — re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.
