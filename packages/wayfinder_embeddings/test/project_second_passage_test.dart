import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';

/// Each passage's marker fixes its cosine similarity to every query.
const _scores = {
  'marker-a1': 1.0,
  'marker-a2': 0.99,
  'marker-c': 0.96,
  'marker-z': 0.95,
  'marker-b': 0.1,
  'marker-w': 0.05,
};

List<double> _vector(String text) {
  final score =
      _scores.entries
          .where((entry) => text.contains(entry.key))
          .firstOrNull
          ?.value ??
      1.0;
  return [score, math.sqrt(1 - score * score), ...List.filled(382, 0.0)];
}

Future<ProjectBundle> _bundle(
  Directory temp,
  String name,
  Map<String, String> bodies,
) async {
  final root = await Directory(p.join(temp.path, name)).create();
  for (final MapEntry(key: path, value: body) in bodies.entries) {
    await File(p.join(root.path, path)).writeAsString(
      '---\ntitle: ${p.basenameWithoutExtension(path)}\n'
      'type: Guideline\n---\n\n$body\n',
    );
  }
  return ProjectBundle(name, name, root.path);
}

void main() {
  test('project search keeps second passages and every linked concept '
      'of a small bundle', () async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-second-');
    addTearDown(() => temp.delete(recursive: true));
    // Three concepts: a's two passages and c's link to b would exceed a
    // context limit of three passages.
    final small = await _bundle(temp, 'small', {
      'a.md': '## One\n\nmarker-a1 guidance.\n\n## Two\n\nmarker-a2 guidance.',
      'c.md': 'marker-c guidance. See [b](b.md).',
      'b.md': 'marker-b guidance.',
    });
    final other = await _bundle(temp, 'other', {
      'z.md': 'marker-z guidance.',
      'w.md': 'marker-w guidance.',
    });
    final store = WayfinderKnowledgeStore(
      dataDirectory: Directory(p.join(temp.path, 'data')),
      encoder: DeterministicEncoderProvider(
        create: () => DeterministicTestEmbedder(vectorOf: _vector),
      ),
    );
    addTearDown(store.dispose);
    await store.index(small);
    await store.index(other);

    final found = await store.search([small, other], 'query', limit: 3);

    expect(found.matches.map((hit) => '${hit.bundle.name}/${hit.sourcePath}'), [
      'small/a.md',
      'small/c.md',
      'other/z.md',
    ]);
    expect(
      [
        for (final hit in found.context)
          (hit.bundle.name, hit.sourcePath, hit.reason, hit.chunk.content),
      ],
      [
        ('small', 'a.md', 'match', 'marker-a1 guidance.'),
        ('small', 'a.md', 'match', 'marker-a2 guidance.'),
        ('small', 'c.md', 'match', 'marker-c guidance. See [b](b.md).'),
        ('small', 'b.md', 'relationship', 'marker-b guidance.'),
      ],
    );
  });
}
