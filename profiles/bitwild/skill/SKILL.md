---
name: bitwild-profile
description: Judgment for OKF 0.2 knowledge bundles under the bitwild-profile Profile. Use before writing, placing, linking, mirroring, moving, retiring, or reviewing concepts in a bundle whose `wayfinder validate --output json` chain lists bitwild-profile, and when adopting a bundle with this Profile.
---

# bitwild-profile

`wayfinder validate` enforces this Profile's rules and decides conformance.
The [Bitwild README](https://github.com/btwld/wayfinder/blob/main/profiles/bitwild/README.md)
explains each rule under its id, and every finding links there. This skill
carries the judgment a validator cannot decide:
whether knowledge earns a concept, where it lives, which type and
relationship name fit, and whether provenance and lifecycle metadata are
truthful.

The generic `author-knowledge-bundle` skill owns OKF mechanics: frontmatter
syntax, the atomic write, and the log format. Read it first. This skill adds
what the Profile decides on top.

## After a write

This Profile requires the indexes okf generates. Run
`wayfinder validate <bundle> --fix` to write the affected indexes, then
`wayfinder validate <bundle>`. Never edit a generated index by hand. The
[adoption reference](references/adoption.md) covers the root index of a
bundle with no concepts.

## Where this skill is silent

Follow pinned OKF 0.2. Silence means OKF already settles the point, so read
the vendored spec and follow it. Never mint a Profile convention to fill the
gap. A mechanism OKF permits and this skill never mentions is permitted.

## Route by operation

Read the reference that covers the write before making it. One write often
needs several.

| Doing | Read first |
| --- | --- |
| Deciding whether something earns a concept, promoting or embedding an outcome, splitting, or writing an Interaction Record | [references/capture.md](references/capture.md) |
| Choosing a type or a body shape | [references/types.md](references/types.md) |
| Writing status, tags, sources, `generated`, `verified`, actors, or `stale_after` | [references/metadata.md](references/metadata.md) |
| Creating or naming a directory, placing a concept, choosing a path, moving, deprecating, deleting, or logging | [references/structure.md](references/structure.md) |
| Typing a link with `relationships`, or linking tracker records | [references/relationships.md](references/relationships.md) |
| Mirroring external material into `references/` | [references/mirroring.md](references/mirroring.md) |
| Keeping raw evidence in `captures/` beside the bundle | [references/captures.md](references/captures.md) |
| Profile Review of a change or the whole bundle | [references/review-map.md](references/review-map.md) |
| Adopting a new bundle with this Profile | [references/adoption.md](references/adoption.md) |
| Converting an existing docs tree into a bundle | [references/migration.md](references/migration.md) |
