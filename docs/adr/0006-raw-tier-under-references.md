# ADR-0006: A `raw/` tier for verbatim originals under `references/`

- Status: accepted
- Date: 2026-08-25

## Context

QA of the first real migration against Profile 2026.1 showed `references/`
mixing two kinds of file with nothing structural marking the boundary: verbatim
originals (PDFs, exports, text dumps — non-markdown assets) and the readable
mirrors derived from them (typed concepts such as a `Meeting Transcript`). The
guarantee that matters for an original — *byte-for-byte, never transformed,
hashable against its source* — was carried by file extension alone, an implicit
convention a reader has to already know.

An explicit home for originals cannot be built by exempting content from the
format. OKF makes every markdown file in a bundle a concept, and the Profile
may not narrow or suspend that (precedence chain; ADR-0004's compatibility
test). Verbatim frontmatter-less markdown inside the bundle is therefore
impossible, and the tier boundary has to be drawn with the two levers OKF
leaves to producers: file extension and directory organization.

## Decision

- A source directory under `references/` MAY keep the verbatim originals it
  preserves in a `raw/` subdirectory.
- Within `raw/` and any of its subdirectories, the only markdown permitted is
  each directory's own `index.md`. The index obligation for nonempty
  directories stands unchanged; everything else in the tier is a non-concept
  asset and stays byte-for-byte.
- A readable mirror derived from an original is a sibling of `raw/` in the
  source directory — never inside it — and names the original through its OKF
  `sources`.
- The tier is **per source directory**, not a single bundle-level tree. The
  original stays next to its mirror, and `references/`' source-and-date
  grouping exists once instead of being duplicated in a parallel hierarchy.
- The markdown restriction is deterministic and enforced by `okfp validate`
  (finding `concepta-profile/raw-directory-markdown`).

The rule passes ADR-0004's five-question OKF compatibility test: it narrows a
producer organization choice OKF explicitly leaves free, adds no field,
filename meaning, or graph interpretation, leaves the independent OKF verdict
untouched, and a generic OKF consumer reads a `raw/` directory as an ordinary
subdirectory whose index lists assets.

**Release handling.** This ships as an in-place amendment to 2026.1, not as a
new release. 2026.1 is still in its QA period — the migration that surfaced the
gap is the profile's first real corpus, and no production adoption exists — and
§15.2 states the structural model is not frozen. The §15.3 change record's
2026.1 entry names the amendment. Once the profile has adopted bundles in the
wild, a convention change of this kind takes a new release per `AGENTS.md`;
this exception is the QA period, not a precedent.

## Consequences

- Existing conformant bundles stay conformant: the tier is a MAY, and the
  MUST NOT binds only bundles that adopt it.
- `raw` becomes a reserved directory name within `references/`: a source
  directory must not itself be named `raw/`, because the rule keys on the name.
- The validator gains one deterministic structure rule; the authoring skill's
  source-mirroring reference teaches the tier as part of mirroring.
- Deciding not to create `raw/` remains ordinary: a source directory with no
  originals to preserve, or whose assets sit directly beside their mirrors from
  before this amendment, is untouched until its author chooses the tier.
