import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

const _start = 'knowledge/guides/start.md';
const _note = 'knowledge/guides/deep/only/note.md';
const _rootIndex = 'knowledge/index.md';

const _knowledge = [
  KnowledgeBundleSummary(name: 'knowledge', path: 'knowledge', conceptCount: 2),
];

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
    final tree = KnowledgeFileTreeProjection(_files, bundles: _knowledge);
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

    test('with no bundle or one at the root, there is no prefix to remove', () {
      const atRoot = KnowledgeBundleSummary(
        name: 'root',
        path: '.',
        conceptCount: 2,
      );
      for (final bundles in [
        const <KnowledgeBundleSummary>[],
        const [atRoot],
      ]) {
        final tree = KnowledgeFileTreeProjection(_files, bundles: bundles);
        expect(labels(tree.roots), ['knowledge', 'wayfinder.json']);
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

  group('with several bundles', () {
    const bundles = [
      KnowledgeBundleSummary(
        name: 'captures',
        path: 'captures',
        conceptCount: 1,
      ),
      KnowledgeBundleSummary(
        name: 'knowledge',
        path: 'knowledge',
        conceptCount: 1,
      ),
    ];
    const files = [
      KnowledgeFileEntry(
        path: 'wayfinder.json',
        kind: KnowledgeFileKind.config,
      ),
      KnowledgeFileEntry(
        path: 'captures/calls/kickoff.md',
        kind: KnowledgeFileKind.concept,
        bundle: 'captures',
        conceptId: 'calls/kickoff',
        title: 'Kickoff call',
        type: 'Guide',
        warningCount: 1,
      ),
      KnowledgeFileEntry(
        path: 'knowledge/guides/start.md',
        kind: KnowledgeFileKind.concept,
        bundle: 'knowledge',
        conceptId: 'guides/start',
        title: 'Getting started',
        type: 'Guide',
      ),
    ];
    const capturesId = 'bundle:captures';

    test('each is a section, and files outside them stay at the top', () {
      final tree = KnowledgeFileTreeProjection(files, bundles: bundles);
      expect(tree.roots.map((node) => (node.kind, node.label)), [
        (KnowledgeTreeNodeKind.bundle, 'captures'),
        (KnowledgeTreeNodeKind.bundle, 'knowledge'),
        (KnowledgeTreeNodeKind.file, 'wayfinder.json'),
      ]);
      expect(KnowledgeFileTreeProjection.bundleId('captures'), capturesId);
      expect(tree.directoryIds, contains(capturesId));
    });

    test('a section counts its files and reports its worst finding', () {
      final tree = KnowledgeFileTreeProjection(files, bundles: bundles);
      final captures = tree.byId[capturesId]!;
      expect(captures.fileCount, 1);
      expect(captures.attention, KnowledgeSeverity.warning);
      expect(tree.byId['bundle:knowledge']!.attention, isNull);
    });

    test('a section shows its folders only while expanded', () {
      final tree = KnowledgeFileTreeProjection(files, bundles: bundles);
      expect(
        tree
            .visible((id) => id == capturesId)
            .map((row) => (row.node.label, row.depth)),
        [
          ('captures', 0),
          ('calls', 1),
          ('knowledge', 0),
          ('wayfinder.json', 0),
        ],
      );
    });

    test('a file\'s ancestors end at its section', () {
      final tree = KnowledgeFileTreeProjection(files, bundles: bundles);
      expect(
        tree.ancestorsOf(
          KnowledgeFileTreeProjection.fileId('captures/calls/kickoff.md'),
        ),
        ['directory:captures/calls', capturesId],
      );
    });

    test('a filter keeps the section that holds a match', () {
      final tree = KnowledgeFileTreeProjection(files, bundles: bundles);
      expect(rowLabels(tree.visible((_) => true, query: 'kickoff')), [
        'captures',
        'calls',
        'Kickoff call',
      ]);
    });

    test('by type, the same type stays apart in each section', () {
      final tree = KnowledgeFileTreeProjection(
        files,
        grouping: KnowledgeTreeGrouping.types,
        bundles: bundles,
      );
      final guides = tree.byId['type:captures/Guide']!;
      expect(guides.label, 'Guide');
      expect(guides.path, 'captures/Guide');
      expect(guides.parentId, capturesId);
      expect(labels(guides.children), ['Kickoff call']);
      expect(labels(tree.byId['type:knowledge/Guide']!.children), [
        'Getting started',
      ]);
    });

    test('a single bundle is not a section', () {
      final tree = KnowledgeFileTreeProjection(
        files,
        grouping: KnowledgeTreeGrouping.types,
        bundles: const [
          KnowledgeBundleSummary(
            name: 'knowledge',
            path: 'knowledge',
            conceptCount: 1,
          ),
        ],
      );
      expect(tree.byId, isNot(contains('bundle:knowledge')));
      expect(tree.byId['type:Guide']!.fileCount, 2);
      expect(tree.byId['type:Guide']!.parentId, isNull);
    });
  });
}
