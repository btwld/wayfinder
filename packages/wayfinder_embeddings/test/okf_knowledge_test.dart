import 'dart:io';

import 'package:okf/okf.dart';
import 'package:test/test.dart';
import 'package:wayfinder/project.dart'
    show WayfinderCancellationController, WayfinderException;
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'support/counting_embedder.dart';

String concept(String body, {String fields = ''}) =>
    '---\ntype: Guideline\n$fields---\n\n$body\n';

KnowledgeSnapshot snapshot(Map<String, String> sources, {String id = 'test'}) =>
    KnowledgeSnapshot.fromSources(sources, bundleId: id);

/// A [KnowledgeNotice] of one bundle's own response, matched field by field.
Matcher _notice(
  KnowledgeNoticeCode code,
  String message, {
  List<String> paths = const [],
  String? target,
}) => isA<KnowledgeNotice>()
    .having((notice) => notice.code, 'code', code)
    .having((notice) => notice.message, 'message', message)
    .having((notice) => notice.text, 'text', message)
    .having((notice) => notice.paths, 'paths', paths)
    .having((notice) => notice.target, 'target', target)
    .having((notice) => notice.bundle, 'bundle', isNull);

void main() {
  test('metadata filters preserve raw field semantics', () {
    final filter = KnowledgeMetadataFilter(
      tags: {'routing', 'navigation'},
      requiredTags: {'mobile'},
      types: {'Guide'},
      statuses: {'review-ready'},
      pathPrefixes: {'architecture'},
      titleContains: 'ROUTES',
      descriptionContains: 'deep.links',
    );
    final raw = <String, Object?>{
      'tags': ['routing', 'mobile'],
      'type': 'Guide',
      'status': 'review-ready',
      'title': 'App routes',
      'description': 'Uses deep.links literally',
    };
    expect(filter.allows(raw, 'architecture/routes.md'), isTrue);
    expect(filter.allows(raw, 'architecture-other/routes.md'), isFalse);
    expect(
      filter.allows({
        ...raw,
        'tags': ['routing'],
      }, 'architecture/routes.md'),
      isFalse,
    );
    expect(
      filter.allows({
        ...raw,
        'tags': ['Routing', 'mobile'],
      }, 'architecture/routes.md'),
      isFalse,
    );
    expect(
      filter.allows({
        ...raw,
        'description': 'deepXlinks',
      }, 'architecture/routes.md'),
      isFalse,
    );
    expect(
      KnowledgeMetadataFilter(statuses: {'stable'}).allows({}, 'a.md'),
      isTrue,
    );
    expect(
      KnowledgeMetadataFilter(
        titleContains: '42',
      ).allows({'title': 42}, 'a.md'),
      isFalse,
    );
    expect(
      KnowledgeMetadataFilter(tags: {'42'}).allows({
        'tags': [42],
      }, 'a.md'),
      isFalse,
    );
    expect(KnowledgeMetadataFilter().allows({}, 'a.md'), isTrue);
    expect(() => KnowledgeMetadataFilter(tags: {' '}), throwsArgumentError);
    expect(
      () => KnowledgeMetadataFilter(descriptionContains: ''),
      throwsArgumentError,
    );
  });

  test('dense search refuses missing eligible vectors', () async {
    final store = MemoryStore();
    final index = KnowledgeIndex(store: store, embedder: CountingEmbedder());
    await index.synchronize(
      snapshot({'guide.md': concept('Recovery guidance.')}),
    );
    final chunk = (await store.getAllChunks()).single;
    await store.deleteEmbedding(chunk.id);
    await expectLater(
      index.search('recovery'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('every eligible passage'),
        ),
      ),
    );
  });

  test('metadata eligibility precedes dense ranking', () async {
    final store = MemoryStore();
    final index = KnowledgeIndex(store: store, embedder: CountingEmbedder());
    await index.synchronize(
      snapshot({
        for (var i = 0; i < 60; i++)
          'excluded/$i.md': concept(
            'Account access recovery',
            fields: 'tags: [other]\n',
          ),
        'wanted.md': concept(
          'Account access recovery',
          fields: 'tags: [mobile]\n',
        ),
      }),
    );
    final before = await store.getAllEmbeddings();
    {
      final result = await index.search(
        'Account access recovery',

        limit: 1,
        policy: KnowledgeSearchPolicy(
          metadataFilter: KnowledgeMetadataFilter(tags: {'mobile'}),
          expandRelationships: true,
        ),
      );
      expect(result.matches.single.chunk.sourcePath, 'wanted.md');
      expect(result.context.map((hit) => hit.result.chunk.sourcePath), [
        'wanted.md',
      ]);
    }
    expect(await store.getAllEmbeddings(), before);
  });

  test('metadata filters exclude linked and governing context', () async {
    final index = KnowledgeIndex(
      store: MemoryStore(),
      embedder: CountingEmbedder(),
    );
    await index.synchronize(
      snapshot({
        'wanted.md': concept(
          'Routing [related](related.md) [governor](governor.md)',
          fields: 'tags: [mobile]\n',
        ),
        'related.md': concept('Routing details', fields: 'tags: [other]\n'),
        'governor.md': concept('Routing rules', fields: 'tags: [other]\n'),
      }),
    );
    final result = await index.search(
      'Routing',

      contextLimit: 10,
      policy: KnowledgeSearchPolicy(
        metadataFilter: KnowledgeMetadataFilter(tags: {'mobile'}),
        expandRelationships: true,
        governingSources: {'wanted.md': 'governor.md'},
      ),
    );
    expect(result.matches.map((hit) => hit.chunk.sourcePath), ['wanted.md']);
    expect(result.context.map((hit) => hit.result.chunk.sourcePath), [
      'wanted.md',
    ]);
    expect(
      result.notices.single,
      _notice(
        KnowledgeNoticeCode.governingSourceUnavailable,
        'Governing source excluded or has no passage: governor.md',
        paths: ['governor.md'],
      ),
    );
  });

  test(
    'OKF defaults, unknown metadata, CRLF citations, and navigation exclusion',
    () {
      final text = concept(
        '# Recovery\n\nUse the recovery link.',
        fields: 'title: Account access\ncustom: [kept]\n',
      ).replaceAll('\n', '\r\n');
      final parsed = snapshot({
        'guide.md': text,
        'index.md': '# Index',
        'log.md': '# Log',
      });
      final chunk = parsed.chunks.single;
      expect(parsed.metadataFor('guide.md').status, OkfLifecycleStatus.stable);
      expect(parsed.metadataFor('guide.md').trustTier, OkfTrustTier.unverified);
      expect(parsed.metadataFor('guide.md').raw['custom'], ['kept']);
      expect(chunk.content, 'Use the recovery link.');
      expect(text.split('\r\n')[chunk.lineStart - 1], chunk.content);
      expect(
        parsed.textFor(chunk, includeContext: true),
        'Title: Account access\n\nSection: Recovery\n\nPassage:\n\nUse the recovery link.',
      );
      expect(
        () => (parsed.metadataFor('guide.md').raw['custom']! as List).add(
          'changed',
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('footnote definitions are attribution, not retrievable passages', () {
    final parsed = snapshot({
      'guide.md': concept(
        '# Findings\n\nAnnotations can be placed.[^layout]\n\n'
        '[^layout]: Exported annotation layout sample',
        fields:
            'title: PDF export\nsources:\n  - id: layout\n'
            '    resource: /references/annotation-layout.json\n'
            '    title: Exported annotation layout sample\n',
      ),
      'apparatus.md': concept('[^only]: Sole cited source'),
    });
    expect(
      parsed.chunks
          .where((chunk) => chunk.sourcePath == 'guide.md')
          .map((chunk) => chunk.content),
      ['Annotations can be placed.[^layout]'],
    );
    // A body that is only apparatus still has to be searchable.
    final apparatus = parsed.chunks.singleWhere(
      (chunk) => chunk.sourcePath == 'apparatus.md',
    );
    expect(apparatus.type, 'footnote');
    expect(apparatus.content, '[^only]: Sole cited source');
  });

  test(
    'loads literal percent filenames without URI-decoding the filesystem path',
    () async {
      final dir = await Directory.systemTemp.createTemp('okf_percent');
      addTearDown(() => dir.delete(recursive: true));
      await File(
        '${dir.path}/percent%20name.md',
      ).writeAsString(concept('Readable content.'));
      final parsed = await KnowledgeSnapshot.load(
        dir.path,
        bundleId: 'percent',
      );
      expect(parsed.chunks.single.sourcePath, 'percent%20name.md');
    },
  );

  test(
    'metadata changes refresh citations and filters without re-embedding',
    () async {
      final store = MemoryStore();
      final model = CountingEmbedder();
      final index = KnowledgeIndex(store: store, embedder: model);
      final first = snapshot({'guide.md': concept('Recovery instructions.')});
      final initial = await index.synchronize(first);
      expect(initial.embeddedChunks, 1);
      final repeated = await index.synchronize(first);
      expect(repeated.embeddedChunks, 0);
      expect(repeated.writtenChunks, 0);
      final updated = snapshot({
        'guide.md': concept(
          'Recovery instructions.',
          fields:
              'status: deprecated\nverified: {by: human:reviewer, at: "2026-09-09T12:00:00Z"}\n',
        ),
      });
      final changed = await index.synchronize(updated);
      expect(changed.embeddedChunks, 0);
      expect(updated.chunks.single.id, first.chunks.single.id);
      expect(
        updated.chunks.single.lineStart,
        first.chunks.single.lineStart + 2,
      );
      expect(
        (await store.getAllChunks()).single.lineStart,
        updated.chunks.single.lineStart,
      );
      expect(
        updated.metadataFor('guide.md').trustTier,
        OkfTrustTier.humanReviewed,
      );
      expect(
        (await index.search(
          'Recovery',
          policy: KnowledgeSearchPolicy(
            currentOnly: true,
            asOf: DateTime.utc(2026, 9, 9),
          ),
        )).matches,
        isEmpty,
      );
      expect((await index.search('Recovery')).matches, hasLength(1));
      expect(model.documents, ['Recovery instructions.']);
    },
  );

  test(
    'title changes refresh contextual vectors while body vectors are reusable',
    () async {
      final store = MemoryStore();
      final model = CountingEmbedder();
      final body = KnowledgeIndex(store: store, embedder: model);
      final context = KnowledgeIndex(
        store: store,
        embedder: model,
        includeContext: true,
      );
      final first = snapshot({
        'guide.md': concept(
          'Stop writers before restoring.',
          fields: 'title: Restore\n',
        ),
      });
      await body.synchronize(first);
      await context.synchronize(first);
      expect(body.embeddingModelName, endsWith(':okf-body-v1'));
      expect(context.embeddingModelName, endsWith(':okf-context-v2'));
      expect((await context.synchronize(first)).embeddedChunks, 0);
      final revised = snapshot({
        'guide.md': concept(
          'Stop writers before restoring.',
          fields: 'title: Database recovery\n',
        ),
      });
      expect((await body.synchronize(revised)).embeddedChunks, 0);
      expect((await context.synchronize(revised)).embeddedChunks, 1);
      expect(model.documents.last, startsWith('Title: Database recovery\n\n'));
      final described = snapshot({
        'guide.md': concept(
          'Stop writers before restoring.',
          fields: 'title: Database recovery\ndescription: Restore safely\n',
        ),
      });
      expect((await body.synchronize(described)).embeddedChunks, 0);
      expect((await context.synchronize(described)).embeddedChunks, 1);
      expect((await context.synchronize(described)).embeddedChunks, 0);
      expect(model.documents.last, contains('Description: Restore safely'));
      final result = await context.search('Database recovery');
      expect(
        result.matches.single.chunk.content,
        'Stop writers before restoring.',
      );
    },
  );

  test(
    'source replacement deletes stale chunks and retains another bundle',
    () async {
      final store = MemoryStore();
      final index = KnowledgeIndex(store: store, embedder: CountingEmbedder());
      final foreign = KnowledgeIndex(
        store: store,
        embedder: CountingEmbedder(),
      );
      await foreign.synchronize(
        snapshot({'guide.md': concept('Foreign body')}, id: 'other'),
      );
      await index.synchronize(
        snapshot({
          'guide.md': concept('Old instructions'),
          'deleted.md': concept('Delete this document'),
        }),
      );
      final result = await index.synchronize(
        snapshot({'guide.md': concept('New instructions')}),
      );
      expect(result.removedChunks, 2);
      expect(result.embeddedChunks, 1);
      expect(
        (await store.getAllChunks()).map((chunk) => chunk.content),
        unorderedEquals(['Foreign body', 'New instructions']),
      );
      expect(await store.getAllEmbeddings(), hasLength(2));
      expect(
        (await index.search('Old')).matches.map((hit) => hit.chunk.content),
        isNot(contains('Old instructions')),
      );
      expect(
        (await index.search('New')).matches.single.chunk.content,
        'New instructions',
      );
    },
  );

  test('failed inference preserves the complete previous snapshot', () async {
    final model = CountingEmbedder();
    final store = MemoryStore();
    final index = KnowledgeIndex(store: store, embedder: model);
    await index.synchronize(
      snapshot({'guide.md': concept('Original guidance')}),
    );
    final original = await store.getAllChunks();
    model.fail = true;
    await expectLater(
      index.synchronize(snapshot({'replacement.md': concept('New guidance')})),
      throwsStateError,
    );
    expect(await store.getAllChunks(), original);
    expect(
      (await index.search('Original')).matches.single.chunk.content,
      'Original guidance',
    );
  });

  test('failed fitting preserves direct-index chunks and embeddings', () async {
    var fail = false;
    final store = MemoryStore();
    addTearDown(store.close);
    final index = KnowledgeIndex(
      store: store,
      embedder: CountingEmbedder(),
      includeContext: true,
      countTokens: (text) async => fail ? 100 : text.length,
      maxTokens: 64,
    );
    await index.synchronize(
      snapshot({'guide.md': concept('Original guidance')}),
    );
    final chunks = await store.getAllChunks();
    final vectors = await store.getAllEmbeddings();
    fail = true;
    await expectLater(
      index.synchronize(snapshot({'replacement.md': concept('Replacement')})),
      throwsStateError,
    );
    expect(await store.getAllChunks(), chunks);
    expect(await store.getAllEmbeddings(), vectors);
    expect(
      (await index.search('Original')).matches.single.chunk.content,
      'Original guidance',
    );
  });

  test(
    'eligible exact search is complete beyond small candidate windows',
    () async {
      final store = MemoryStore();
      final index = KnowledgeIndex(store: store, embedder: CountingEmbedder());
      final sources = {
        for (var i = 0; i < 100; i++)
          'history/$i.md': concept(
            'Account access recovery $i',
            fields: 'status: deprecated\n',
          ),
        'current.md': concept('Account access recovery'),
        'draft.md': concept(
          'Proposed account access recovery',
          fields: 'status: draft\n',
        ),
      };
      await index.synchronize(snapshot(sources));
      final current = KnowledgeSearchPolicy(
        currentOnly: true,
        asOf: DateTime.utc(2026, 9, 9),
      );
      {
        final hits = await index.search(
          'Account access recovery',

          limit: 2,
          policy: current,
        );
        expect(
          hits.matches.map((hit) => hit.chunk.sourcePath),
          unorderedEquals(['current.md', 'draft.md']),
        );
      }
      final none = await index.search(
        'Account access recovery',

        policy: KnowledgeSearchPolicy(pathPrefixes: {'missing'}),
      );
      expect(none.matches, isEmpty);
    },
  );

  test(
    'current filtering uses the stale boundary and retains missing verification',
    () async {
      final index = KnowledgeIndex(
        store: MemoryStore(),
        embedder: CountingEmbedder(),
      );
      await index.synchronize(
        snapshot({
          'old.md': concept(
            'Rotate signing keys ninety days',
            fields: 'stale_after: 2026-09-09\n',
          ),
          'new.md': concept('Rotate signing keys thirty days'),
        }),
      );
      final hits = await index.search(
        'Rotate signing keys',
        policy: KnowledgeSearchPolicy(
          currentOnly: true,
          asOf: DateTime.utc(2026, 9, 9),
        ),
      );
      expect(hits.matches.single.chunk.sourcePath, 'new.md');
      expect(
        () => KnowledgeSearchPolicy(currentOnly: true),
        throwsArgumentError,
      );
    },
  );

  test(
    'governing chains precede matches without changing query scores',
    () async {
      final index = KnowledgeIndex(
        store: MemoryStore(),
        embedder: CountingEmbedder(focus: 'Local debug'),
      );
      await index.synchronize(
        snapshot({
          'implementation.md': concept('Local debug may disable encryption.'),
          'profile.md': concept('Use the transport standard.'),
          'standard.md': concept('Encrypt all traffic.'),
        }),
      );
      final result = await index.search(
        'Local debug',
        limit: 1,
        contextLimit: 3,
        policy: KnowledgeSearchPolicy(
          governingSources: {
            'implementation.md': 'profile.md',
            'profile.md': 'standard.md',
          },
        ),
      );
      expect(result.matches.single.chunk.sourcePath, 'implementation.md');
      expect(result.context.map((hit) => hit.result.chunk.sourcePath), [
        'standard.md',
        'profile.md',
        'implementation.md',
      ]);
      expect(result.context.first.reason, 'governing');
      expect(
        () => KnowledgeSearchPolicy(
          governingSources: {'a.md': 'b.md', 'b.md': 'a.md'},
        ),
        throwsArgumentError,
      );
      await expectLater(
        index.search(
          'Local',
          policy: KnowledgeSearchPolicy(
            governingSources: {'implementation.md': 'missing.md'},
          ),
        ),
        throwsArgumentError,
      );
      final scoped = await index.search(
        'Local debug',
        policy: KnowledgeSearchPolicy(
          pathPrefixes: {'implementation'},
          governingSources: {'implementation.md': 'standard.md'},
        ),
      );
      expect(
        scoped.context.single.result.chunk.sourcePath,
        'implementation.md',
      );
      expect(
        scoped.notices.single,
        _notice(
          KnowledgeNoticeCode.governingSourceUnavailable,
          'Governing source excluded or has no passage: standard.md',
          paths: ['standard.md'],
        ),
      );
    },
  );

  test('an unresolved target is one notice that names every match linking '
      'to it', () async {
    final index = KnowledgeIndex(
      store: MemoryStore(),
      embedder: CountingEmbedder(focus: 'Shared'),
    );
    await index.synchronize(
      snapshot({
        'b/second.md': concept('Shared [gone](/missing.md) [also](/absent.md)'),
        'a.md': concept('Shared [gone](/missing.md)'),
        'other.md': concept('Unrelated'),
      }),
    );
    final result = await index.search(
      'Shared',
      limit: 2,
      contextLimit: 5,
      policy: KnowledgeSearchPolicy(expandRelationships: true),
    );
    expect(result.matches.map((hit) => hit.chunk.sourcePath), [
      'a.md',
      'b/second.md',
    ]);
    expect(result.notices, [
      _notice(
        KnowledgeNoticeCode.unresolvedRelationship,
        'Unresolved relationship: /missing.md',
        paths: ['a.md', 'b/second.md'],
        target: '/missing.md',
      ),
      _notice(
        KnowledgeNoticeCode.unresolvedRelationship,
        'Unresolved relationship: /absent.md',
        paths: ['b/second.md'],
        target: '/absent.md',
      ),
    ]);
    expect(
      KnowledgeNoticeCode.unresolvedRelationship.wireValue,
      'unresolved-relationship',
    );
    expect(
      KnowledgeNoticeCode.governingSourceUnavailable.wireValue,
      'governing-source-unavailable',
    );
  });

  test('search checks its cancellation before it encodes the query and '
      'before it scores', () async {
    final embedder = _QueryHookEmbedder();
    final index = KnowledgeIndex(store: MemoryStore(), embedder: embedder);
    await index.synchronize(snapshot({'a.md': concept('Routing')}));
    final cancelled = isA<WayfinderException>().having(
      (error) => error.code,
      'code',
      'cancelled',
    );
    await expectLater(
      index.search(
        'Routing',
        cancel: WayfinderCancellationController()..cancel(),
      ),
      throwsA(cancelled),
    );
    expect(embedder.queries, isEmpty, reason: 'cancelled before encoding');
    final during = WayfinderCancellationController();
    embedder.onQuery = during.cancel;
    await expectLater(
      index.search('Routing', cancel: during),
      throwsA(cancelled),
      reason: 'cancelled while encoding, so nothing is scored',
    );
    expect(embedder.queries, ['Routing']);
    embedder.onQuery = null;
    final result = await index.search(
      'Routing',
      cancel: WayfinderCancellationController(),
    );
    expect(result.matches.single.chunk.sourcePath, 'a.md');
  });

  test(
    'declared link expansion is bounded, deduplicated, and scope-aware',
    () async {
      final index = KnowledgeIndex(
        store: MemoryStore(),
        embedder: CountingEmbedder(focus: 'LaunchProcedure'),
      );
      await index.synchronize(
        snapshot({
          'guide/start.md': concept(
            'LaunchProcedure [evidence](../evidence.md). [bad](./missing.md).',
            fields:
                'sources: [{resource: /evidence.md}, {resource: "https://example.invalid/source"}]\n',
          ),
          'evidence.md': concept('Read this proof. [cycle](/guide/start.md)'),
        }),
      );
      final result = await index.search(
        'LaunchProcedure',
        limit: 1,
        contextLimit: 2,
        policy: KnowledgeSearchPolicy(expandRelationships: true),
      );
      expect(result.context.map((hit) => hit.result.chunk.sourcePath), [
        'guide/start.md',
        'evidence.md',
      ]);
      expect(
        result.context.last.edge!.resolution,
        OkfGraphResolution.resolvedConcept,
      );
      expect(result.context.last.viaPath, 'guide/start.md');
      expect(
        result.notices.single,
        _notice(
          KnowledgeNoticeCode.unresolvedRelationship,
          'Unresolved relationship: ./missing.md',
          paths: ['guide/start.md'],
          target: './missing.md',
        ),
      );
      final scoped = await index.search(
        'LaunchProcedure',
        policy: KnowledgeSearchPolicy(
          expandRelationships: true,
          pathPrefixes: {'guide'},
        ),
      );
      expect(scoped.context, hasLength(1));
    },
  );

  test('frontmatter link fields add typed edges to expansion', () async {
    const relationships = OkfLinkField(
      'relationships',
      nameKey: 'relationship',
    );
    final sources = {
      'decision.md': concept(
        'OfflineMode keeps working without a connection.',
        fields:
            'relationships:\n'
            '  - {relationship: depends-on, resource: /sync/engine.md}\n'
            '  - {relationship: tracked-by, resource: /missing.md}\n'
            '  - {resource: "https://example.invalid/issue/1"}\n'
            '  - {relationship: refines}\n',
      ),
      'sync/engine.md': concept('The sync engine queues writes.'),
    };
    final typed = KnowledgeSnapshot.fromSources(
      sources,
      bundleId: 'typed',
      linkFields: const [relationships],
    );
    expect(typed.fieldEdges.map((edge) => edge.toJson()), [
      {
        'source': 'decision',
        'field': 'relationships',
        'name': 'depends-on',
        'raw_target': '/sync/engine.md',
        'resolution': 'resolved-concept',
        'resolved_path': 'sync/engine.md',
        'target_concept': 'sync/engine',
      },
      {
        'source': 'decision',
        'field': 'relationships',
        'name': 'tracked-by',
        'raw_target': '/missing.md',
        'resolution': 'unresolved',
        'resolved_path': 'missing.md',
      },
      {
        'source': 'decision',
        'field': 'relationships',
        'raw_target': 'https://example.invalid/issue/1',
        'resolution': 'external',
      },
    ]);
    expect(
      typed.graph.edges,
      isEmpty,
      reason: 'okf reads no producer key, so the edges exist only as typed',
    );

    final index = KnowledgeIndex(
      store: MemoryStore(),
      embedder: CountingEmbedder(focus: 'OfflineMode'),
    );
    await index.synchronize(typed);
    final result = await index.search(
      'OfflineMode',
      limit: 1,
      contextLimit: 2,
      policy: KnowledgeSearchPolicy(expandRelationships: true),
    );
    expect(result.context.map((hit) => hit.result.chunk.sourcePath), [
      'decision.md',
      'sync/engine.md',
    ]);
    expect(result.context.last.reason, 'relationship');
    expect(result.context.last.fieldEdge!.name, 'depends-on');
    expect(
      result.notices.single,
      _notice(
        KnowledgeNoticeCode.unresolvedRelationship,
        'Unresolved relationship: /missing.md',
        paths: ['decision.md'],
        target: '/missing.md',
      ),
    );

    final reopened = KnowledgeSnapshot.fromMap(
      typed.toMap(),
      linkFields: const [relationships],
    );
    expect(reopened.fieldEdges.map((edge) => edge.toJson()), [
      for (final edge in typed.fieldEdges) edge.toJson(),
    ]);

    final untyped = KnowledgeIndex(
      store: MemoryStore(),
      embedder: CountingEmbedder(focus: 'OfflineMode'),
    );
    await untyped.synchronize(snapshot(sources, id: 'untyped'));
    final plain = await untyped.search(
      'OfflineMode',
      limit: 1,
      contextLimit: 2,
      policy: KnowledgeSearchPolicy(expandRelationships: true),
    );
    expect(plain.context.map((hit) => hit.result.chunk.sourcePath), [
      'decision.md',
    ]);
  });

  test(
    'oversized separators and identifiers recover without losing text',
    () async {
      final original = snapshot({
        'guide.md': concept(
          'Recover access before ${'-' * 700} after separator.',
        ),
        'other.md': concept('Independent searchable guidance.'),
      });
      Future<int> count(String text) async => text.runes.length + 2;
      final fitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 64,
        includeContext: false,
      );
      for (final path in original.conceptPaths) {
        expect(
          fitted.chunks
              .where((c) => c.sourcePath == path)
              .map((c) => c.content)
              .join(),
          original.chunks
              .where((c) => c.sourcePath == path)
              .map((c) => c.content)
              .join(),
        );
      }
      expect(fitted.sources, original.sources);
      for (final chunk in fitted.chunks) {
        expect(
          await count(fitted.textFor(chunk, includeContext: false)),
          lessThanOrEqualTo(64),
        );
      }
    },
  );

  test(
    'token splitting preserves every character and original citation spans',
    () async {
      final original = snapshot({
        'guide.md': concept(
          '# Section\n\none two three four five\nsix seven eight nine ten',
          fields: 'title: Guide\n',
        ),
      });
      Future<int> count(String text) async =>
          RegExp(r'\S+').allMatches(text).length + 2;
      final fitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 8,
        includeContext: true,
      );
      expect(fitted.chunks.length, greaterThan(1));
      expect(
        fitted.chunks.map((chunk) => chunk.content).join(),
        original.chunks.single.content,
      );
      for (final chunk in fitted.chunks) {
        expect(
          await count(fitted.textFor(chunk, includeContext: true)),
          lessThanOrEqualTo(8),
        );
        expect(
          chunk.lineStart,
          greaterThanOrEqualTo(original.chunks.single.lineStart),
        );
        expect(
          chunk.lineEnd,
          lessThanOrEqualTo(original.chunks.single.lineEnd),
        );
      }
      final omitted = await original.fitInputs(
        countTokens: count,
        maxTokens: 3,
        includeContext: true,
      );
      expect(omitted.diagnostics.single.code, 'embedding_context_omitted');
      expect(
        omitted.chunks.map((c) => c.content).join(),
        original.chunks.single.content,
      );
      await expectLater(
        original.fitInputs(
          countTokens: count,
          maxTokens: 2,
          includeContext: true,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Attested Computation concepts stay in metadata and graph while excluded from passages',
    () {
      final parsed = snapshot({
        'alpha.md': concept(
          'LaunchProcedure [computation](computations/view.md).',
        ),
        'computations/view.md':
            '---\ntype: Attested Computation\ntitle: View\n---\n\n'
            'render_view("LaunchProcedure")\n',
        'custom.md':
            '---\ntype: attested computation\ntitle: Custom\n---\n\n'
            'Custom lowercase type keeps its passages.\n',
      });
      expect(parsed.conceptPaths, contains('computations/view.md'));
      expect(
        parsed.metadataFor('computations/view.md').type,
        'Attested Computation',
      );
      expect(
        parsed.chunks.any((c) => c.sourcePath == 'computations/view.md'),
        isFalse,
      );
      expect(parsed.chunks.any((c) => c.sourcePath == 'custom.md'), isTrue);
      final map = parsed.toMap();
      final chunks = List<Map<String, Object?>>.from(map['chunks']! as List)
        ..add(
          Chunk(
            id: 'stale-computation-chunk',
            sourcePath: 'computations/view.md',
            lineStart: 6,
            lineEnd: 6,
            content: 'render_view("LaunchProcedure")',
            type: 'paragraph',
          ).toMap(),
        );
      final contexts = Map<String, String>.from(map['contextTexts']! as Map)
        ..['stale-computation-chunk'] =
            'Title: View\n\nPassage:\n\nrender_view("LaunchProcedure")';
      final reopened = KnowledgeSnapshot.fromMap({
        ...map,
        'chunks': chunks,
        'contextTexts': contexts,
      });
      expect(
        reopened.chunks.any((c) => c.sourcePath == 'computations/view.md'),
        isFalse,
      );
      expect(reopened.chunks.map((c) => c.id), parsed.chunks.map((c) => c.id));
    },
  );
}

/// A [CountingEmbedder] that records each query and calls [onQuery] while
/// it encodes one.
class _QueryHookEmbedder extends CountingEmbedder {
  final queries = <String>[];
  void Function()? onQuery;

  @override
  Future<List<double>> generateQueryVector(String text) async {
    queries.add(text);
    onQuery?.call();
    return super.generateQueryVector(text);
  }
}
