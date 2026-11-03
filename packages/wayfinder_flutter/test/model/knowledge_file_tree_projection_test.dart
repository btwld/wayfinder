import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

const _start = 'knowledge/guides/start.md';
const _note = 'knowledge/guides/deep/only/note.md';
const _rootIndex = 'knowledge/index.md';

const _files = [
  KnowledgeFileEntry(path: _rootIndex, kind: KnowledgeFileKind.indexFile),
  KnowledgeFileEntry(
    path: 'knowledge/guides/index.md',
    kind: KnowledgeFileKind.indexFile,
  ),
  KnowledgeFileEntry(
    path: _start,
    kind: KnowledgeFileKind.concept,
    title: 'Start here',
    type: 'Guide',
    errorCount: 1,
  ),
  KnowledgeFileEntry(
    path: _note,
    kind: KnowledgeFileKind.concept,
    warningCount: 1,
    tags: ['billing'],
  ),
  KnowledgeFileEntry(
    path: 'knowledge/assets/logo.png',
    kind: KnowledgeFileKind.reference,
  ),
  KnowledgeFileEntry(path: 'wayfinder.json', kind: KnowledgeFileKind.config),
];

void main() {
  List<String> labels(Iterable<KnowledgeFileTreeNode> nodes) => [
    for (final node in nodes) node.label,
  ];
  List<String> rowLabels(List<KnowledgeFileTreeRow> rows) => [
    for (final row in rows) row.node.label,
  ];

  group('by folder', () {
    final tree = KnowledgeFileTreeProjection(_files, rootPrefix: 'knowledge');
    final guides =
        tree.byId[KnowledgeFileTreeProjection.folderId('knowledge/guides')]!;

    test('the bundle folder is not repeated; folders come before files', () {
      expect(labels(tree.roots), [
        'assets',
        'guides',
        'index.md',
        'wayfinder.json',
      ]);
    });

    test('a folder holding only one folder joins its label', () {
      expect(labels(guides.children), ['deep/only', 'index.md', 'Start here']);
      expect(guides.children.first.path, 'knowledge/guides/deep/only');
    });

    test('a folder counts its files and reports its worst finding', () {
      expect(guides.fileCount, 3);
      expect(guides.attention, KnowledgeSeverity.error);
      expect(guides.children.first.attention, KnowledgeSeverity.warning);
    });

    test('ancestors run from the nearest folder up', () {
      expect(tree.ancestorsOf(KnowledgeFileTreeProjection.fileId(_note)), [
        KnowledgeFileTreeProjection.folderId('knowledge/guides/deep/only'),
        KnowledgeFileTreeProjection.folderId('knowledge/guides'),
      ]);
      expect(tree.ancestorsOf('no such row'), isEmpty);
    });

    test('only expanded folders show their children', () {
      expect(rowLabels(tree.visible((_) => false)), labels(tree.roots));
      final rows = tree.visible((id) => id == guides.id);
      expect(rowLabels(rows), [
        'assets',
        'guides',
        'deep/only',
        'index.md',
        'Start here',
        'index.md',
        'wayfinder.json',
      ]);
      expect(rows[2].depth, 1);
    });

    test('a query keeps matching files and their folders', () {
      expect(rowLabels(tree.visible((_) => true, query: 'START')), [
        'guides',
        'Start here',
      ]);
      expect(rowLabels(tree.visible((_) => true, query: 'billing')), [
        'guides',
        'deep/only',
        'note.md',
      ]);
      expect(rowLabels(tree.visible((_) => true, query: 'nothing')), isEmpty);
    });

    test('a query never hides the file being read', () {
      expect(
        rowLabels(tree.visible((_) => true, query: 'START', keep: _rootIndex)),
        ['guides', 'Start here', 'index.md'],
      );
    });

    test('a file listed twice appears once', () {
      final twice = KnowledgeFileTreeProjection([..._files, ..._files]);
      expect(twice.files, hasLength(_files.length));
    });

    test('a bundle at the root has no prefix to remove', () {
      for (final prefix in ['', '.']) {
        final root = KnowledgeFileTreeProjection(_files, rootPrefix: prefix);
        expect(labels(root.roots), ['knowledge', 'wayfinder.json']);
      }
    });
  });

  test('by type, concepts group by type and untyped ones come last', () {
    final tree = KnowledgeFileTreeProjection(
      _files,
      grouping: KnowledgeTreeGrouping.types,
    );
    expect(labels(tree.roots), [
      'Guide',
      knowledgeUntypedGroup,
      knowledgeOtherFilesGroup,
      knowledgeAttachmentsGroup,
    ]);
    expect(labels(tree.roots.first.children), ['Start here']);
    expect(tree.roots.first.kind, KnowledgeTreeNodeKind.group);
    expect(labels(tree.roots[2].children), ['index.md', 'index.md']);
    expect(labels(tree.roots[3].children), ['logo.png', 'wayfinder.json']);
  });
}
