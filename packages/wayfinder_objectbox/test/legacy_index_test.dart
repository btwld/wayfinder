import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';
import 'package:wayfinder_storage_testing/wayfinder_storage_testing.dart';

void main() {
  const harness = GenerationFormatHarness.plain();

  test('an ObjectBox-backed index is never read, changed or deleted', () async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-legacy-');
    addTearDown(() => temp.delete(recursive: true));
    var data = Directory(p.join(temp.path, 'data'));
    final bundle = await copyStoreBundle(temp);
    WayfinderKnowledgeStore store() => WayfinderKnowledgeStore(
      dataDirectory: data,
      encoder: DeterministicEncoderProvider(),
    );

    // The layout an ObjectBox-backed store wrote:
    // indexes/<bundle key>/<configuration key>.lock beside
    // <configuration key>/{current,generation-*/{data.mdb,schema
    // markers,snapshot.json}}, with a record that, read, would be current
    // for this bundle and encoder.
    final built = await store().index(bundle);
    final record = Map<String, Object?>.from(
      jsonDecode(await harness.readRecord(currentGeneration(built.index)))
          as Map,
    );
    final configuration = Map<String, Object?>.from(
      jsonDecode(record['configuration']! as String) as Map,
    );
    configuration['store'] = '384-v1';
    record
      ..['configuration'] = jsonEncode(configuration)
      ..remove('vectors');
    final key = keyFor(DeterministicTestEmbedder.defaultModelName);
    final old = Directory(
      p.join(
        temp.path,
        'wave1-data',
        'indexes',
        sha256
            .convert(utf8.encode(jsonEncode({'root': bundle.root})))
            .toString(),
      ),
    );
    final generation = await Directory(
      p.join(old.path, key, 'generation-objectbox'),
    ).create(recursive: true);
    for (final file in Directory(
      'test/fixtures/objectbox-0.2.0',
    ).listSync().whereType<File>()) {
      if (p.extension(file.path) == '.md') continue;
      await file.copy(p.join(generation.path, p.basename(file.path)));
    }
    await File(
      p.join(generation.path, 'snapshot.json'),
    ).writeAsString(jsonEncode(record));
    await File(
      p.join(old.path, key, 'current'),
    ).writeAsString('generation-objectbox');
    final lock = File(p.join(old.path, '$key.lock'));
    await lock.writeAsString('${jsonEncode({'root': bundle.root})}\n');
    // Unused for long, so a prune that reached it would delete it.
    await lock.setLastModified(
      DateTime.now().subtract(const Duration(days: 400)),
    );
    final before = await treeBytes(old);
    final modified = (await lock.stat()).modified;

    data = Directory(p.join(temp.path, 'wave1-data'));
    final upgraded = store();
    expect(await upgraded.status(bundle), isA<KnowledgeIndexMissing>());
    final rebuilt = await upgraded.index(bundle);
    expect(rebuilt.current, isFalse);
    expect(rebuilt.embeddedChunks, built.embeddedChunks);
    expect(p.isWithin(old.path, rebuilt.index), isFalse);
    expect(
      (await upgraded.searchBundle(bundle, 'password')).matches,
      isNotEmpty,
    );
    await upgraded.index(bundle, force: true);
    await upgraded.forget(bundle);
    await upgraded.prune(unusedFor: Duration.zero);
    await Directory(bundle.root).rename('${bundle.root}-moved');
    await upgraded.prune(unusedFor: Duration.zero);
    expect(await treeBytes(old), before);
    expect((await lock.stat()).modified, modified);
  });
}

/// The configuration key the last ObjectBox knowledge store used before
/// naming the embedding runtime.
String keyFor(String model) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          'configuration': jsonEncode({
            'version': 4,
            'context': 'okf-context-v2',
            'chunkCharacters': 1000,
            'longInput': 'reject',
            'snapshot': 1,
            'store': '384-v1',
            'chunkIds': 'bundle-relative',
          }),
          'model': '$model:okf-context-v2',
          'source': DeterministicTestEmbedder.source,
        }),
      ),
    )
    .toString();
