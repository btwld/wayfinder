# Skills

Wayfinder's own agent workflows, shipped together as the `wayfinder` plugin.
They know OKF and the `wayfinder` CLI, and no particular Profile. Each
Profile's conventions reach agents through that Profile's own skill.

## The family

| Skill | Invocation | Responsibility |
| --- | --- | --- |
| [author-knowledge-bundle](author-knowledge-bundle/SKILL.md) | model-invoked | Author bundle content and perform Profile Review. Owns OKF mechanics and the write sequence, and loads the skill of each Profile in the bundle's chain. |
| [adopt-knowledge-bundle](adopt-knowledge-bundle/SKILL.md) | user-invoked | Bind a new bundle to a Profile, install its skill, seed the root files the Profile gives, and add agent routing. Generic parts live in [SEEDING.md](adopt-knowledge-bundle/SEEDING.md). |
| [assess-knowledge-bundle](assess-knowledge-bundle/SKILL.md) | user-invoked | Run a deliberate whole-bundle assessment through the shared assessment reference and each Profile's review map. |
| [use-wayfinder](use-wayfinder/SKILL.md) | model-invoked | Search, index, validate and project the graph of a bundle with Wayfinder's MCP tools or CLI; answer from verified, cited passages. Routes writes and reviews to the skills above. |
| [create-profile](create-profile/SKILL.md) | user-invoked | Create, revise, or maintain a Profile package: ask its author what a machine enforces and what is judgment, write its rules with tests and its skill, prove both, and release it. |

## Profile skills

A Profile's judgment ships as that Profile's skill, in its package, beside
the rules that `wayfinder validate` enforces. `create-profile` writes it.
`wayfinder get` installs it into each project that uses the Profile, as
`.claude/skills/<id>/` and `.agents/skills/<id>/`, pinned to the commit the
lock records, and the project commits it. Its name is the Profile id, which
`validate --output json` lists as `profile.chain[].id`, so the authoring
skill loads the skill of each Profile in a bundle's chain. See
[Profile skills](../docs/wayfinder-configuration.md#profile-skills).

This family installs at user level, once per machine, and stays the same for
every Profile. Profile skills install per project.

## Installation and routing

Use the [root README's installation instructions](../README.md#1-install-the-skills).
The native installer installs this family (`wayfinder skills install`) and
`wayfinder update` refreshes it; `wayfinder setup` configures a project's MCP
server.
`wayfinder setup --session-hooks` adds a short startup pointer to `use-wayfinder`
for Claude, Codex, and Gemini; Grok reads it from `AGENTS.md`. That skill links
to author, adopt, and assess for the relevant task. Startup does no indexing.
The `wayfinder` plugin also registers the installed Wayfinder MCP server. Install
the CLI first; use the complete native bundle for indexing and search. By default
it serves `knowledge/` relative to the consuming project. Set
`WAYFINDER_KNOWLEDGE_DIR` to an explicit bundle path when it lives elsewhere, and
`WAYFINDER_EXECUTABLE` if the executable is not on `PATH`. The source repository
itself has no `knowledge/`; contributors enabling the plugin here must select a
real bundle, such as an example project. No root `.mcp.json` auto-starts a server
merely because this repository was cloned.

Follow the [plugin migration sequence](../docs/install.md#migrate-an-existing-plugin-installation) when changing from an older marketplace or `wayfinder-dist` to the main public
Wayfinder repository.
Keep upstream `okf` write tools separately configured if needed. Wayfinder's
`validate`, `index`, `search` and `graph` tools project and retrieve; they do
not replace concept-authoring writes.

Install the family as a unit: sibling references make a partial installation
incomplete.

`author-knowledge-bundle` owns concept mechanics. Its description routes bundle
writes and reviews to it, and adoption also puts an explicit pointer in the
consuming repository's agent instructions. The other skills delegate instead
of keeping their own rule text.

## Pinned OKF

The [vendored OKF 0.2 specification](author-knowledge-bundle/references/OKF-0.2.md)
answers every question no Profile skill settles. It is pinned to upstream
commit `ad30107` in the canonical `open-knowledge-format` repository, with
Apache-2.0 attribution, so offline consumers read the reviewed specification
instead of a changing `main` URL. Keep it as a reference, not a second skill
or a rewritten specification.

## Changing these skills

Keep them Profile-agnostic. A convention one Profile chooses belongs in that
Profile's skill, written through `create-profile`, never here. When the CLI's
contract changes, such as a diagnostic id or the JSON shape, search the whole
family for the old wording, starting with `SEEDING.md`.
