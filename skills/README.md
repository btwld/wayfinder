# Skills

The `wayfinder` plugin ships a Profile-agnostic family. Generic skills own
OKF/CLI mechanics; a Profile's installed skill owns its conventions and judgment.

| Skill | Invocation | Responsibility |
| --- | --- | --- |
| [author-knowledge-bundle](author-knowledge-bundle/SKILL.md) | model | Bundle writes, OKF mechanics and scoped Profile Review; loads each Profile skill. |
| [adopt-knowledge-bundle](adopt-knowledge-bundle/SKILL.md) | user | Bind and seed a bundle, install Profile skills and agent routing. |
| [assess-knowledge-bundle](assess-knowledge-bundle/SKILL.md) | user | Whole-bundle assessment using the shared review flow. |
| [use-wayfinder](use-wayfinder/SKILL.md) | model | Discover, verify, index, validate and explore knowledge; delegates writes. |
| [create-profile](create-profile/SKILL.md) | user | Elicit, write, prove and maintain Profile rules and judgment. |

Install the family together: sibling references make partial copies incomplete.
The [installation guide](../docs/install.md) covers plugin/skill installation,
updates, MCP and startup hooks. Startup does no indexing. Default MCP discovers
configured project bundles; explicit launches restrict it to one. This source
repository has no root `knowledge/`, so select an example project when using it
here. Wayfinder MCP does not expose concept-authoring tools.

## Profile skills

`wayfinder get` installs each Profile's `skill/` into
`.claude/skills/<id>/` and `.agents/skills/<id>/`, pinned to the locked commit.
Projects commit those directories with the lock. `profile.chain[].id` in validation
JSON gives their load order, root first. See
[Profile skills](../docs/wayfinder-configuration.md#profile-skills).
The generic family installs per user; Profile skills install per project.

## Pinned OKF and maintenance

The [OKF 0.2 reference](author-knowledge-bundle/references/OKF-0.2.md) is pinned to
upstream `ad30107`, with Apache-2.0 attribution. Keep its bytes and load relevant
sections on demand; do not rewrite it into another skill.

Keep Profile conventions in their own packages. When CLI contracts change,
search the whole family for retired wording, starting with
[SEEDING.md](adopt-knowledge-bundle/SEEDING.md). Its literal blocks mirror
`KnowledgeSeeds` in `package:wayfinder/adoption.dart`; change both together and
run `packages/wayfinder/test/adoption/seeds_test.dart`.
