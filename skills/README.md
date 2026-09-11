# Skills

The agent workflows for [Concepta OKF Profile 2026.1](../profile/okf-profile.md),
shipped together as the `wayfinder` plugin.

## The family

| Skill | Invocation | Responsibility |
| --- | --- | --- |
| [author-knowledge-bundle](author-knowledge-bundle/SKILL.md) | model-invoked | Author bundle content and perform Profile Review. Routes to shared references by operation. |
| [adopt-knowledge-bundle](adopt-knowledge-bundle/SKILL.md) | user-invoked | Seed a new bundle, preserve an existing one, and add agent routing. Uses literal [root-file templates](adopt-knowledge-bundle/SEEDING.md) and delegates review to the authoring skill. |
| [assess-knowledge-bundle](assess-knowledge-bundle/SKILL.md) | user-invoked | Run a deliberate whole-bundle assessment through the shared authoring and review instructions. |
| [use-wayfinder](use-wayfinder/SKILL.md) | model-invoked | Search, index, validate and project the graph of a bundle with Wayfinder's MCP tools or CLI; answer from verified, cited passages. Routes writes and reviews to the skills above. |

Migration remains a scoped project task using the
[implementation guide §5](../implementation/okf-implementation-guide.md#5-migration)
and the authoring skill; there is no separate migration skill.

## Installation and routing

Use the [root README's installation instructions](../README.md#1-install-the-skills).
The native installer installs this family (`wayfinder skills install`) and
`wayfinder update` refreshes it; `wayfinder setup` configures a project's MCP
server.
The `wayfinder` plugin also registers the installed Wayfinder MCP server. Install
the CLI first; use the complete native bundle for indexing and search. By default
it serves `knowledge/` relative to the consuming project. Set
`WAYFINDER_KNOWLEDGE_DIR` to an explicit bundle path when it lives elsewhere, and
`WAYFINDER_EXECUTABLE` if the executable is not on `PATH`. The source repository
itself has no `knowledge/`; contributors enabling the plugin here must select a
real bundle, such as the generic example. No root `.mcp.json` auto-starts a server
merely because this repository was cloned.

Follow the [plugin migration sequence](../docs/install.md#migrate-an-existing-plugin-installation) when changing from an older marketplace or `wayfinder-dist` to the main public
Wayfinder repository.
Keep upstream `okf` write tools separately configured if needed. Wayfinder's
`validate`, `index`, `search` and `graph` tools project and retrieve; they do
not replace concept-authoring writes.

Install the family as a unit: sibling references make a partial installation
incomplete. Keep each installation on one commit so the seed templates, authoring
rules, and assessment instructions agree.

`author-knowledge-bundle` owns concept mechanics. Its description routes bundle
writes and reviews to those instructions; adoption also puts an explicit pointer
in the consuming repository's agent instructions. The other two skills delegate
instead of maintaining independent rule text. Adoption's literal seed templates
are the exception because the resulting root files must stand alone.

## Pinned OKF and Profile rules

The Profile is authoritative for Concepta conventions. Its authoring instructions
are distributed under `author-knowledge-bundle/references/` so an installed copy
can work without access to this repository. The entrypoint checks the bundle's
declared release before applying them.

The [vendored OKF 0.2 specification](author-knowledge-bundle/references/OKF-0.2.md)
provides upstream mechanisms the Profile leaves open, including Attested
Computation and source credibility signals. It is pinned to upstream commit
`3fcbb9f` with Apache-2.0 attribution, so offline consumers read the reviewed
specification instead of a changing `main` URL. Keep it as a reference, not a
second skill or a rewritten specification.

When a Profile rule changes, search the whole skill family for its old wording,
starting with `SEEDING.md`. Check that requirements, recommendations, and optional
mechanisms retain their original force. Conforming output alone cannot establish
that a skill teaches the right rule.
