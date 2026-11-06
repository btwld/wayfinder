import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/src/graph/knowledge_graph_painter.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KnowledgeGraphViewport viewport;
  late ValueNotifier<KnowledgeGraphHover?> hover;
  late KnowledgeGraphLabelCache cache;
  late KnowledgeGraphScene scene;

  setUp(() {
    viewport = KnowledgeGraphViewport();
    hover = ValueNotifier(null);
    cache = KnowledgeGraphLabelCache();
    scene = KnowledgeGraphScene(
      query: const KnowledgeGraphQuery(scope: KnowledgeGraphScope.whole),
      nodes: const [
        KnowledgeGraphSceneNode(
          id: 'guide',
          title: 'Guide',
          type: 'Guide',
          kind: KnowledgeGraphNodeKind.concept,
          distance: null,
        ),
      ],
      links: const [],
      positions: Float64List.fromList([150, 100]),
      focus: null,
    );
  });

  tearDown(() {
    cache.clear();
    hover.dispose();
    viewport.dispose();
  });

  KnowledgeGraphPainter painter({
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
  }) => KnowledgeGraphPainter(
    scene: scene,
    viewport: viewport,
    hover: hover,
    labels: cache,
    labelOrder: const [0],
    labelRank: const [0],
    palette: KnowledgeTypePalette.of(const []),
    theme: const WayfinderReaderThemeData.dark(),
    textScaler: textScaler,
    textDirection: direction,
    activeIndex: null,
    attention: const [null],
    words: const KnowledgeGraphLabels(),
    onSelect: (_) {},
    onOpen: (_) {},
  );

  Future<Uint8List> pixels(KnowledgeGraphPainter painter) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(300, 180));
    final picture = recorder.endRecording();
    final image = await picture.toImage(300, 180);
    try {
      final data = await image.toByteData();
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('text scale and reading direction changes repaint the canvas', () {
    final original = painter();
    expect(
      painter(textScaler: const TextScaler.linear(2)).shouldRepaint(original),
      isTrue,
    );
    expect(
      painter(direction: TextDirection.rtl).shouldRepaint(original),
      isTrue,
    );
  });

  test('hover paints the same label after a warm or cold cache', () async {
    final graph = painter();
    final normal = await pixels(graph);
    hover.value = const KnowledgeGraphHover(node: 0, at: Offset(150, 100));
    final warmed = await pixels(graph);
    cache.clear();
    final fresh = await pixels(graph);
    expect(
      normal,
      isNot(orderedEquals(fresh)),
      reason: 'hover emphasises the label',
    );
    expect(warmed, orderedEquals(fresh));
  });
}
