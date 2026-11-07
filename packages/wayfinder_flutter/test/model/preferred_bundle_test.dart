import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/src/model/knowledge.dart';

KnowledgeBundleSummary _bundle(String path, int concepts, {String? name}) =>
    KnowledgeBundleSummary(
      name: name ?? path.split('/').last,
      path: path,
      conceptCount: concepts,
    );

void main() {
  test('a project opens on its knowledge bundle first', () {
    expect(
      preferredKnowledgeBundle([
        _bundle('captures', 220),
        _bundle('knowledge', 12),
      ])?.path,
      'knowledge',
    );
    expect(
      preferredKnowledgeBundle([
        _bundle('docs/notes', 220),
        _bundle('docs/kb', 3, name: 'knowledge'),
      ])?.path,
      'docs/kb',
    );
  });

  test('without one, it opens on the bundle with the most concepts', () {
    expect(
      preferredKnowledgeBundle([
        _bundle('archive', 4),
        _bundle('captures', 220),
        _bundle('drafts', 9),
      ])?.path,
      'captures',
    );
    expect(
      preferredKnowledgeBundle([_bundle('b', 5), _bundle('a', 5)])?.path,
      'a',
    );
    expect(preferredKnowledgeBundle(const []), isNull);
  });

  test('root knowledge wins over nested namesakes in either order', () {
    final root = _bundle('knowledge', 1);
    final nested = _bundle('a/knowledge', 200);
    for (final bundles in [
      [nested, root],
      [root, nested],
    ]) {
      expect(preferredKnowledgeBundle(bundles)?.path, 'knowledge');
    }
  });
}
