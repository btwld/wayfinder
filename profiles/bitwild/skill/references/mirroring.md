# Mirroring sources into `references/`

External material enters the bundle only through `references/`, and only on
demand. Mirror an artifact only when all three hold:

- a durable concept cites it through `sources`;
- its availability is genuinely at risk, where being outside project control
  is evidence to weigh, not enough by itself;
- the material may live at the repository's visibility.

Never mirror merely because a meeting, call, or thread happened. The bundle
inherits the repository's access controls and has no per-concept scheme, so
mirroring widens who can read the material. Confirm the visibility before
mirroring.

## What a mirror is

- A mirrored Markdown artifact is a concept, such as `type: Meeting
  Transcript` declared in the project's `wayfinder.json`. It carries the
  baseline frontmatter and a `sources` entry naming the original recording,
  thread, or document.
- A mirror is an immutable snapshot once cited. Never edit its content.
- A non-Markdown asset under `references/` is not a concept and carries no
  frontmatter. The concepts citing it give its context.
- `references/` is organized by source and date, may nest, and is exempt
  from subject naming.
- Curated context about an external system that stays external may be an
  ordinary concept whose `resource` names that system. No mirror is needed.

## By medium

| Medium | Policy |
| --- | --- |
| Text: transcripts, exported documents, chat threads | May be mirrored in full. Sanitize it where confidentiality demands. |
| Images | Only when a concept cites them. Optimize them first. |
| Video, audio, other heavy binaries | Never commit them. Keep them external and linked. When their content must outlive the external system, mirror an appropriate transcript instead. |

## The `raw/` tier

A source directory may keep verbatim originals in a `raw/` subdirectory.
The tier is optional; originals may also sit beside their mirrors.

- `raw/` and its subdirectories hold only byte-for-byte assets. No Markdown
  file is allowed there, not even `index.md`.
- The mirror derived from an original sits beside `raw/`, and its `sources`
  entry names the original.
- `raw/` belongs to a source directory, never directly under `references/`.
  `raw` is reserved for the tier, so give a source directory another name.

Validation checks placement and the Markdown ban. It cannot check byte
fidelity to the external source.

## Deciding not to mirror

A decision not to mirror is durable too. Keep ordinary OKF meaning in
`sources[].resource`: a followable URL or path when one exists, or a scope
descriptor when the source is inherently unfollowable. Never replace a known
followable resource with a descriptor to silence an availability advisory.
When the reason for not mirroring matters to future preservation, state it
in the body.

```yaml
sources:
  - id: demo-0730
    resource: Client demo recording, 30 July 2026, retained outside this repository
    title: Reporting demo, 30 July 2026
    author: process:meeting-platform
    last_modified: 2026-07-30T00:00:00Z
```
