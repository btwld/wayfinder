---
name: bitwild-profile
description: Judgment for OKF 0.2 knowledge bundles under the bitwild-profile Profile. Use before writing, placing, linking, mirroring, moving, retiring, or reviewing concepts in a bundle whose `wayfinder validate --output json` chain lists bitwild-profile, and when adopting a bundle with this Profile.
---

# bitwild-profile

`wayfinder validate` enforces this Profile's rules. This skill carries the
judgment a validator cannot decide: whether knowledge earns a concept, where
it lives, which type and relationship name fit, and whether provenance and
lifecycle metadata are truthful.

The generic `author-knowledge-bundle` skill owns OKF mechanics: frontmatter
syntax, the atomic write, generated indexes, and the log format. Read it
first. This skill adds what the Profile decides on top.

## What this Profile narrows

The Profile is a thin layer on OKF 0.2. It defines no file type and never
changes the meaning of an OKF field. Compared with bare OKF:

- A concept carries only OKF-defined frontmatter keys plus `relationships`.
  A project cannot add keys.
- `status` is knowledge lifecycle only: `draft`, `stable`, or `deprecated`.
- `tags` carry topic only.
- Directories name subjects, never kinds of document. Five directory names
  are fixed; every other name is the project's own.
- Every `index.md` is okf's generated output.
- Every root log entry starts with a bold lead word and a colon.

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
