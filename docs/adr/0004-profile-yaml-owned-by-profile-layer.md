# ADR-0004: `profile.yaml` belongs to the profile layer; base okf never learns the name

- Status: accepted
- Date: 2026-08-14
- Issues: [#5](https://github.com/btwld/okf-profile/issues/5), #3

## Context

The 2026-08-14 architecture review (pre-split) phrased the sidecar as
"reserved in the loader", which could read as a base-okf obligation. After the
toolchain split that reading is wrong and dangerous: it is the one remaining
place where profile knowledge could creep back into okf. As of
conceptadev/okf#20, okf's loader classifies every non-markdown file as an
ordinary asset and its source contains no profile-specific handling; the
question is who "reserves" the filename.

## Decision

The filename `profile.yaml` is defined, documented, and reserved by this
codebase alone. Base okf must never special-case it: to okf's loader it is an
ordinary non-markdown asset, indistinguishable from any other. The okfp
bundle-loading wrapper is the seam that knows the name — it reads the
declaration, resolves the manifest, and applies every profile-layer semantic
(never a concept, never a graph target, the degrade findings when absent or
unresolvable).

If a future need arises to hide the file from base-okf asset semantics, it is
met on this side, or by a generic okf affordance any caller can use (for
example, a caller-supplied exclude list) — never by a `profile.yaml` literal
in okf.

## Consequences

- okf stays profile-blind, and the property is mechanically checkable: the
  string `profile` never appears in okf's source.
- Supersedes the review's "reserved in the loader" phrasing: the reserving
  loader is okfp's wrapper, not okf's.
- Any base-okf rule that someday inspects assets treats `profile.yaml` like
  any other file; okfp owns any carve-out.
