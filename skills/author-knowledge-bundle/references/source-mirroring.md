# Mirroring sources into `references/`

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch and
atomic write sequence apply.

Mirror an external artifact only when a durable concept cites it through `sources`, its availability is genuinely at risk, and the material may live at repository visibility. A source being outside project control is evidence to consider, not enough by itself. Never mirror merely because a meeting, call, or thread happened.

- Mirrored markdown artifacts are concepts (e.g. `type: Meeting Transcript`, registered in `types.md`) with a `sources` entry naming the original recording, thread, or document. They remain immutable snapshots once cited.
- `references/` is not an area: it is organized by source and date, is exempt from subject naming, and may nest — but a nonempty `references/` and each nonempty subdirectory still needs an `index.md`.
- Text may be mirrored in full and must be sanitized where confidentiality demands. Images only when cited, optimized first. Video, audio, and other heavy binaries never — keep the followable source external and prefer an appropriate transcript when preservation is needed.
- Non-markdown assets under `references/` are not concepts; the concepts citing them provide their context.
- **A source directory may use a `raw/` tier for verbatim originals.** The tier is optional; originals may remain beside their mirrors without it. When used, the only markdown inside `raw/` and its descendants is each directory's `index.md`; everything else stays a byte-for-byte asset. `okfp validate` checks placement and markdown restrictions, not byte fidelity to the external source. The mirror derived from an original sits beside `raw/`, its `sources` entry naming the original. The tier sits inside a source directory, never directly under `references/`, and `raw` is reserved for it — give a source directory another name. See the index projection reference for linking filenames that need URL encoding.
- **Deciding not to mirror is also durable.** Preserve ordinary OKF source meaning: keep a known followable URL or path in `sources[].resource`; use a scope descriptor only when the source is inherently unfollowable. A material non-mirroring reason should be stated in the body. Never replace a followable resource with a descriptor merely to silence availability concerns.
