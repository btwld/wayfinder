# Open documentation and implementation decisions

These are unresolved maintenance decisions, not Profile rules or accepted
ADRs. Maintainers own the next evidence review; do not silently settle an item
while condensing historical records. The source is the
[2026-09-09 maintenance review at `dfd46e1`](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/maintenance-review.md),
which was a dated snapshot rather than current guidance.

| Decision | Current boundary | Evidence needed before changing it |
| --- | --- | --- |
| Human-only migration checkpoint | Bitwild's [migration reference](../profiles/bitwild/skill/references/migration.md) asks a person to read the area index, while [Profile assessment](../skills/author-knowledge-bundle/references/profile-assessment.md) supports human or agent review. | Decide whether the human-only step is intentional, using a real migration review; then align the Bitwild skill and the generic skill without weakening contextual review. |
| Bitwild publication status | The [Bitwild package](../profiles/bitwild/wayfinder-profile.json) names release `2026.3`, and its [changelog](../profiles/bitwild/CHANGELOG.md) records the revisions made before publication. Nothing yet tags the release. | Confirm the release process and tag name before a project pins a Bitwild ref other than a commit. |
| Cross-bundle references | [Engine contract §7](../implementation/okf-implementation-guide.md#7-cross-bundle-references) defers a dedicated mechanism; ordinary URLs remain available. | Check whether multiple live bundles now provide the missing design evidence; define a mechanism only through an engine contract change if the generic need is proven. |
| Committed Profile skills | `wayfinder get` installs each Profile's skill into `.claude/skills/<id>/` and `.agents/skills/<id>/`, and projects commit them like a lock ([ADR-0016](adr/0016-independent-profile-packages.md)). Whether Codex reads repository-level `.agents/skills` is unverified. | A manual Codex session in a project with an installed Profile skill; a team that prefers to gitignore the copies. |
| Iterating on a Profile locally | A Profile author tests a package through `wayfinder get` against a local `git:` path, one commit per iteration. | Evidence from Profile authors that a `--profile <dir>` validate flag is worth the new CLI option. |
| Link fields as Profile data | The engine reads one link field, `relationships`, as typed edges ([engine contract §5.5](../implementation/okf-implementation-guide.md#55-vocabulary-and-frontmatter-keys)). | A Profile that needs typed links under another key, or that pays a cost for `relationships` it does not use. |
| Derived OKF release rule | Bitwild's `okf-release-binding` rule restates the package's `implements.release` and could drift from it. | Decide whether the engine should fill the expected `okf_version` from `implements`, so no Profile restates it. |
| Project-type notes | A registered project type is reported as the `wayfinder/project-type` note diagnostic. | Evidence from real runs on whether the note helps or is noise. |
| Changing an inherited rule | Package format 2 has no field that lets a child Profile exclude or re-grade a parent rule ([engine contract §5.7](../implementation/okf-implementation-guide.md#57-composition)). | A child Profile that needs it; the change is a named field in the child package and a new `format`. |
