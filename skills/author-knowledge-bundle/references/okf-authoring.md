# OKF authoring

Part of the `author-knowledge-bundle` skill. This reference covers what OKF
0.2 itself requires of a concept. Each Profile skill in the bundle's chain
narrows it; where they differ, the Profile skill wins inside what OKF allows.
The vendored [OKF 0.2 specification](./OKF-0.2.md) is the authority.

## Files

- Every `.md` file other than `index.md` and `log.md` is a concept document
  (OKF §3.1). Those two names are reserved at every level.
- Non-Markdown files are assets, not concepts. They carry no frontmatter.
- An `index.md` is optional and navigational (OKF §8). If a Profile in the
  chain requires generated indexes, run `wayfinder validate <bundle> --fix`
  to write them and never edit one by hand. Otherwise write or omit each
  `index.md` as OKF §8 and the Profile skills allow.

## Frontmatter

A concept starts with YAML frontmatter. OKF requires a nonempty `type`
(OKF §4.1). Copy the YAML shape of every OKF field from OKF §4 and §5; never
invent a spelling.

```yaml
---
type: <concept type>
title: <display name>
description: <one sentence>
status: <lifecycle value>
tags: [<topic>]
---
```

- `generated`, `verified`, `sources`, `status`, and `stale_after` have the
  meanings OKF §5 gives them. A Profile may restrict which values are allowed,
  never what a field means.
- Every timestamp is an instant with a UTC offset. A date-only or offset-less
  value raises `okf/timestamp-without-offset`.
  `okf format --migrate-timestamps` rewrites such values.
- OKF permits producer keys beyond the ones it defines (OKF §4.1). A Profile
  may restrict which keys a concept carries. Follow each Profile skill in
  the chain.
- When reading, preserve unknown types, fields, and names. Valid OKF you do
  not recognize is content, not an error.

## Sources and attribution

Record material a claim derives from in `sources` (OKF §5.1). Each entry
needs a `resource`. To attribute one claim, put a footnote in the body whose
label equals the entry's `id`.

## Links

Link to another concept with a bundle-relative path that starts with `/`,
such as `/reporting/token-contract.md` (OKF §6.1). A broken internal link is
valid OKF and repairable. Path-valued fields such as `resource` follow
OKF §6.2. Mirrored external material follows the `references/` convention of
OKF §6.3, as each Profile narrows it.

## Log

`log.md` holds date-grouped entries, newest first, under `## YYYY-MM-DD`
headings (OKF §9). Write each entry as `* **<Lead word>**: <what changed>`.
