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
- Malformed citations with oversized line numbers return null instead of throwing.
- The graph fills its bounded viewport under loose cross-axis constraints, such
  as an `Expanded` child of a `Column`, rather than collapsing to zero width.
- `KnowledgeIndexState` and `KnowledgeIndexProgress` are provisional.
