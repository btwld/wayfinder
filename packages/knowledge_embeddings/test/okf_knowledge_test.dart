import 'dart:io';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/okf_knowledge.dart';
import 'package:okf/okf.dart';
import 'package:test/test.dart';

String concept(String body, {String fields = ''}) =>
    '---\ntype: Guideline\n$fields---\n\n$body\n';

KnowledgeSnapshot snapshot(Map<String, String> sources, {String id = 'test'}) =>
    KnowledgeSnapshot.fromSources(sources, bundleId: id);

void main() {
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
        'Account access\n\nRecovery\n\nUse the recovery link.',
      );
      expect(
        () => (parsed.metadataFor('guide.md').raw['custom']! as List).add(
          'changed',
        ),
        throwsUnsupportedError,
      );
    },
  );

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
      expect(body.embeddingModelName, isNot(context.embeddingModelName));
      final revised = snapshot({
        'guide.md': concept(
          'Stop writers before restoring.',
          fields: 'title: Database recovery\n',
        ),
      });
      expect((await body.synchronize(revised)).embeddedChunks, 0);
      expect((await context.synchronize(revised)).embeddedChunks, 1);
      expect(model.documents.last, startsWith('Database recovery\n\n'));
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
      final foreign = KnowledgeIndex(store: store);
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
      expect(await store.getAllEmbeddings(), hasLength(1));
      expect((await index.search('Old')).matches, isEmpty);
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
      for (final mode in KnowledgeRetrievalMode.values) {
        final hits = await index.search(
          'Account access recovery',
          mode: mode,
          limit: 2,
          candidateLimit: 1,
          policy: current,
        );
        expect(
          hits.matches.map((hit) => hit.chunk.sourcePath),
          unorderedEquals(['current.md', 'draft.md']),
        );
      }
      final none = await index.search(
        'Account access recovery',
        mode: KnowledgeRetrievalMode.dense,
        policy: KnowledgeSearchPolicy(pathPrefixes: {'missing'}),
      );
      expect(none.matches, isEmpty);
    },
  );

  test(
    'current filtering uses the stale boundary and retains missing verification',
    () async {
      final index = KnowledgeIndex(store: MemoryStore());
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
      final index = KnowledgeIndex(store: MemoryStore());
      await index.synchronize(
        snapshot({
          'implementation.md': concept('Local debug may disable encryption.'),
          'profile.md': concept('Use the transport standard.'),
          'standard.md': concept('Encrypt all traffic.'),
        }),
      );
      final result = await index.search(
        'Local debug',
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
      expect(scoped.notices, contains(contains('Governing source excluded')));
    },
  );

  test(
    'declared link expansion is bounded, deduplicated, and scope-aware',
    () async {
      final index = KnowledgeIndex(store: MemoryStore());
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
      expect(result.notices, contains(contains('Unresolved relationship')));
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
      await expectLater(
        original.fitInputs(
          countTokens: count,
          maxTokens: 3,
          includeContext: true,
        ),
        throwsStateError,
      );
    },
  );
}

class CountingEmbedder extends BaseEmbedder {
  final documents = <String>[];
  bool fail = false;
  @override
  String get sourceName => 'test';
  @override
  String get modelName => 'fixed';
  @override
  int get dimension => 384;
  @override
  Future<List<double>> generateEmbedding(String text) async {
    if (fail) throw StateError('inference failed');
    documents.add(text);
    return [1, ...List<double>.filled(383, 0)];
  }

  @override
  Future<List<double>> generateQueryVector(String text) async => [
    1,
    ...List<double>.filled(383, 0),
  ];
}
