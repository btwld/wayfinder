# wayfinder_flutter

Flutter models, graph widgets and reader helpers for OKF knowledge bundles.
A host app supplies the knowledge, state and look.

The package is unpublished and early. It holds the portable knowledge models, the
file-tree projection and link helpers, the graph layout, and
`KnowledgeGraphCanvas`. Concrete backends, controllers, search UI and the other
reader widgets follow; there is no runnable example app yet.

It depends only on Flutter: no design kit and no `MaterialApp`. Hosts own sign-in,
storage, navigation and app chrome, and widgets report intent through callbacks.

See the [integration and graph guide](doc/integration.md) for the core-to-Flutter
mapping, graph ownership, indexing branch boundaries and remaining product work.

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
flutter test
```

Format with the stable Flutter SDK. Analyze and test on Flutter 3.47.5 and on
stable, as the package workflow does. Stable defines the format, the same rule
as the rest of the repository.
