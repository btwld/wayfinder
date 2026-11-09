# wayfinder_flutter

A shared model-free knowledge reader/controller plus the existing graph SDK.
The same `KnowledgeReader` selects bundles, concepts, raw files/attachments and
graph against portable memory or local-file backends. No embeddings dependency,
model setup or search index is needed. Validation is explicitly unavailable/not
assessed; semantic search is absent, not simulated.

`package:wayfinder/knowledge.dart` owns portable values and revision-bound snapshots;
Flutter re-exports them at existing model import paths. Native loading and
`buildOkfBundle` come from `package:wayfinder/project.dart`; the UI depends only
on the portable entry. Hosts own grants, source
selection, storage and teardown. Graph widgets remain design-kit independent;
the minimal reader uses Material controls under a host `MaterialApp`.

See [integration and migration](doc/integration.md) and the
[runnable native memory/local example](example/README.md). This package remains
unpublished; 0.2 replaces the provisional 0.1 backend/search signatures.

## The knowledge graph

`layOutKnowledgeGraph` turns a `KnowledgeGraph` into a `KnowledgeGraphScene`, laying
out a large graph on another isolate. `KnowledgeGraphCanvas` draws the scene, with
pan, zoom, hover cards and a legend.

```dart
final scene = await layOutKnowledgeGraph(
  graph,
  const KnowledgeGraphQuery(scope: KnowledgeGraphScope.whole),
);

KnowledgeGraphCanvas(
  scene: scene,
  // Pass every concept of the bundle, so a type keeps its colour in any view.
  palette: KnowledgeTypePalette.of(concepts),
  activeId: selectedId,
  attentionOf: (node) => null,
  onSelect: (id) => setState(() => selectedId = id),
  onOpen: openDocument,
);
```

A `GlobalKey<KnowledgeGraphCanvasState>` gives a host's own toolbar `fit()` and
`recentre()`. The legend shows icons only if the host passes `typeIconOf` and
`kindIconOf`, and `tooltipBuilder` puts the host's tooltip on its "Other" row. Its
words come from `KnowledgeGraphLabels`; extend that class to translate them.

Keep the same `KnowledgeGraphScene` instance across rebuilds: a new one clears the
canvas's label cache. A changed layout refits and fades the view.

With a mouse, hovering shows a node's card and a double click opens it. With touch,
a tap selects a node and shows its card, and a long press or a double tap opens it.
Screen readers open a node with its long-press action, which is hinted as Open.
Graph keyboard navigation remains product follow-up.

## Theming

Wrap the widgets in a `WayfinderReaderTheme` to map a design system onto them.
Without one, they use `WayfinderReaderThemeData.dark()` or `.light()` to match the
platform's brightness. Start from one of those and use `copyWith`, so a value added
later keeps its default.

```dart
WayfinderReaderTheme(
  data: const WayfinderReaderThemeData.dark().copyWith(fontFamily: 'Geist'),
  child: canvas,
);
```

## Development

This package is outside the repository's Dart workspace, so working on Wayfinder's
other packages needs no Flutter SDK. `pubspec.yaml` requires Dart `^3.13.0` and
Flutter `>=3.47.5`. The root contributor checks use Dart 3.11, which is below
this package's floor, so `flutter pub get` here needs the versions above. From
this directory:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test --concurrency=2
```

Format with the stable Flutter SDK. Analyze and test on Flutter 3.47.5 and on
stable, as the package workflow does. Stable defines the format, the same rule
as the rest of the repository.
