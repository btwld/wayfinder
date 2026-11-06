# 0.1.0 (unreleased)

- Initial version, moved from an existing desktop reader: the portable knowledge
  models, file tree and link helpers, and graph layout.
- `KnowledgeGraphCanvas` and `KnowledgeTypePalette` move with them, without a
  design kit: `WayfinderReaderTheme` supplies colours and type,
  `KnowledgeGraphLabels` supplies the words, and hosts can pass the legend's
  icons and tooltip.
- The canvas handles touch, text scaling, right-to-left text, reduced motion and
  screen readers.
- Review fixes keep wheel zoom from fighting Fit, discard pending clicks on
  removed nodes, repaint scaled/directional text, and preserve hover colours
  across label caching. Shared graph targets use their nearest ring; resolved
  attachment IDs use their project-relative path rather than a raw link target.
- Synthetic graph target IDs now start with `/` (for example,
  `/unresolved:gone`) so they cannot collide with valid OKF concept IDs.
  Real concept IDs are unchanged. Hosts storing synthetic IDs must rebuild them
  from the scene; treat IDs as opaque and use node `kind`, `path` and `target`
  for navigation instead of parsing IDs.
- A non-concept link whose written target equals its source concept ID keeps its
  target node and edge; self-link suppression applies only to concept links.
- Graph labels preserve encoded URL path segments with invalid UTF-8 instead of
  aborting scene construction; valid URL segments still display decoded text.
- Live text size, direction and font changes refit an already-fitted canvas while
  preserving manually panned or zoomed views.
- Multiword title searches normalize per-word fallback scores so partial
  title/id/tag matches cannot outrank an exact title or title prefix.
- Search snippets retain the first match inside an unbroken token when moving
  either boundary to a space would exclude it.
- Malformed citations with oversized line numbers return null instead of throwing.
- The graph fills its bounded viewport under loose cross-axis constraints, such
  as an `Expanded` child of a `Column`, rather than collapsing to zero width.
- Graph paint is clipped to its viewport so panned or zoomed nodes, edges and
  labels cannot cover adjacent host content.
- `KnowledgeIndexState` and `KnowledgeIndexProgress` are provisional.
- Flattening a single bundle preserves files and folders with the same displayed
  names as project files, keeping their project-relative IDs and ancestry.
