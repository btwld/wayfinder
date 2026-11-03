# 0.1.0 (unreleased)

- Initial version, moved from an existing desktop reader: the portable knowledge
  models, file tree and link helpers, and graph layout.
- `KnowledgeGraphCanvas` and `KnowledgeTypePalette` move with them, without a
  design kit: `WayfinderReaderTheme` supplies colours and type,
  `KnowledgeGraphLabels` supplies the words, and hosts can pass the legend's
  icons and tooltip.
- The canvas handles touch, text scaling, right-to-left text, reduced motion and
  screen readers.
- `KnowledgeIndexState` and `KnowledgeIndexProgress` are provisional.
