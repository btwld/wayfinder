import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:knowledge_embeddings/okf_knowledge.dart';
import 'package:path/path.dart' as p;

import 'index_result.dart';

typedef _SavedIndex = ({
  String configuration,
  String model,
  String source,
  String inventory,
  String generation,
  KnowledgeSnapshot snapshot,
});

class StationException implements Exception {
  const StationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns an encoder and its tokenizer for one command.
class StationEncoder {
  StationEncoder(this.embedder, this.countTokens, this.maxTokens);
  final BaseEmbedder embedder;
  final Future<int> Function(String) countTokens;
  final int maxTokens;
}

/// Coordinates bundle ownership, freshness and completed index generations.
///
/// Commands sharing a bundle serialize before opening ObjectBox. Updates happen
/// in a private generation; only a flushed completion record and closed database
/// may be published. An inference failure never modifies the active generation.
class StationKnowledge {
  StationKnowledge({
    Directory? dataDirectory,
    Future<StationEncoder> Function()? openEncoder,
  }) : dataDirectory = dataDirectory ?? defaultDataDirectory(),
       _openEncoder = openEncoder ?? _openLocalEncoder;

  final Directory dataDirectory;
  final Future<StationEncoder> Function() _openEncoder;
  static final _active = <String>{};
  static final _generationName = RegExp(r'^generation-[a-zA-Z0-9_-]+$');

  // Increment when chunking, snapshot or application input semantics change.
  static final _configuration = jsonEncode({
    'version': 1,
    'model': localEmbeddingModel.toMap(),
    'context': 'okf-context-v1',
    'chunkCharacters': 1000,
    'longInput': 'reject',
    'snapshot': 1,
    'store': '384-v1',
  });

  static Directory defaultDataDirectory() {
    final env = Platform.environment;
    final override = env['STATION_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override);
    }
    final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'];
      if (local != null) return Directory(p.join(local, 'Station'));
    } else if (home != null) {
      if (Platform.isMacOS) {
        return Directory(
          p.join(home, 'Library', 'Application Support', 'Station'),
        );
      }
      final xdg = env['XDG_DATA_HOME'];
      return Directory(
        p.join(
          xdg != null && p.isAbsolute(xdg)
              ? xdg
              : p.join(home, '.local', 'share'),
          'station',
        ),
      );
    }
    throw const StationException(
      'Cannot locate local app data. Set STATION_DATA_DIR.',
    );
  }

  static Future<StationEncoder> _openLocalEncoder() async {
    try {
      var model = defaultEmbeddingModelFile();
      if (!model.existsSync() &&
          !Platform.environment.containsKey('KNOWLEDGE_EMBEDDING_MODEL')) {
        final package = await Isolate.resolvePackageUri(
          Uri.parse('package:knowledge_embeddings/knowledge_embeddings.dart'),
        );
        if (package != null) {
          model = File.fromUri(package.resolve('../models/embedding.gguf'));
        }
      }
      final embedder = await LlamaEmbedder.open(modelFile: model);
      return StationEncoder(
        embedder,
        embedder.countTokens,
        embedder.model.maxTokens,
      );
    } on FileSystemException {
      throw const StationException(
        'The local embedding model is missing or unreadable. Reinstall the complete '
        'Station bundle; for source development run melos run embeddings:prepare.',
      );
    } on FormatException {
      throw const StationException(
        'The local embedding model failed verification. Reinstall the complete Station bundle.',
      );
    }
  }

  Future<T> _withBundle<T>(
    String bundle,
    Future<T> Function(String root, Directory directory) action,
  ) async {
    if (!Platform.isWindows) {
      final name = Platform.isMacOS ? 'libobjectbox.dylib' : 'libobjectbox.so';
      var library = File(
        p.join(
          File(Platform.resolvedExecutable).parent.parent.path,
          'lib',
          name,
        ),
      );
      if (!library.existsSync()) {
        final package = await Isolate.resolvePackageUri(
          Uri.parse('package:knowledge_embeddings/knowledge_embeddings.dart'),
        );
        if (package != null) library = File.fromUri(package.resolve(name));
      }
      if (library.existsSync()) DynamicLibrary.open(library.absolute.path);
    }
    final root = await Directory(bundle).resolveSymbolicLinks();
    if (!await Directory(root).exists()) {
      throw const StationException('The bundle must be a directory.');
    }
    final requested = p.normalize(dataDirectory.absolute.path);
    var ancestor = Directory(requested);
    while (!await ancestor.exists()) {
      if (ancestor.parent.path == ancestor.path) {
        throw const StationException(
          'Cannot resolve the Station data directory.',
        );
      }
      ancestor = ancestor.parent;
    }
    final data = p.normalize(
      p.join(
        await ancestor.resolveSymbolicLinks(),
        p.relative(requested, from: ancestor.path),
      ),
    );
    if (p.equals(root, data) || p.isWithin(root, data)) {
      throw const StationException(
        'Station data must be outside the knowledge bundle.',
      );
    }
    final key = sha256.convert(utf8.encode(root)).toString();
    final directory = Directory(p.join(data, 'indexes', key));
    await directory.create(recursive: true);
    final lockKey = await directory.resolveSymbolicLinks();
    if (!_active.add(lockKey)) {
      throw const StationException(
        'Index is busy. Retry when the current command finishes.',
      );
    }
    RandomAccessFile? lock;
    try {
      lock = await File(
        p.join(directory.path, 'command.lock'),
      ).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const StationException(
          'Index is busy. Retry when the current command finishes.',
        );
      }
      return await action(root, directory);
    } finally {
      try {
        await lock?.close();
      } finally {
        _active.remove(lockKey);
      }
    }
  }

  Future<StationIndexResult> index(String bundle) => _withBundle(bundle, (
    root,
    directory,
  ) async {
    final watch = Stopwatch()..start();
    final inventory = await _inventory(root);
    _SavedIndex? previous;
    try {
      previous = await _readCurrent(directory);
    } on StationException {
      // Index can repair an incompatible/incomplete saved generation.
    }
    final encoder = await _openEncoder();
    try {
      final space = '${encoder.embedder.modelName}:okf-context-v1';
      final compatible =
          previous?.configuration == _configuration &&
          previous?.model == space &&
          previous?.source == encoder.embedder.sourceName;
      final oldDatabase = previous == null
          ? null
          : File(p.join(directory.path, previous.generation, 'data.mdb'));
      if (oldDatabase != null) {
        final schema = File(
          p.join(oldDatabase.parent.path, 'knowledge_embeddings.schema'),
        );
        if (!await oldDatabase.exists() ||
            !await schema.exists() ||
            await schema.readAsString() != '384-v1\n') {
          previous = null;
        }
      }
      final fitted = compatible && previous?.inventory == inventory
          ? previous!.snapshot
          : await (await KnowledgeSnapshot.load(
              root,
              bundleId: root,
            )).fitInputs(
              countTokens: encoder.countTokens,
              maxTokens: encoder.maxTokens,
              includeContext: true,
            );
      final savedInputs = <String, String>{
        for (final entry in fitted.sources.entries)
          entry.key: sha256.convert(utf8.encode(entry.value)).toString(),
        for (final path in fitted.assets) path: 'asset',
      };
      if (_inventoryHash(savedInputs) != inventory) {
        throw const StationException(
          'Knowledge changed while loading. Run station index again.',
        );
      }
      final staged = await directory.createTemp('generation-');
      var published = false;
      try {
        if (compatible && previous != null) {
          final old = p.join(directory.path, previous.generation);
          // No open store or other Station command can write while the lock is held.
          for (final name in ['data.mdb', 'knowledge_embeddings.schema']) {
            await File(p.join(old, name)).copy(p.join(staged.path, name));
          }
        }
        final store = ObjectBoxStore(staged.path);
        late final ({int embeddedChunks, int removedChunks, int writtenChunks})
        counts;
        try {
          counts = await KnowledgeIndex(
            store: store,
            embedder: encoder.embedder,
            includeContext: true,
          ).synchronize(fitted);
        } finally {
          await store.close();
        }
        if (await _inventory(root) != inventory) {
          throw const StationException(
            'Knowledge changed while indexing. Run station index again.',
          );
        }
        final record = {
          'configuration': _configuration,
          'model': space,
          'source': encoder.embedder.sourceName,
          'inventory': inventory,
          'snapshot': fitted.toMap(),
        };
        await File(
          p.join(staged.path, 'snapshot.json'),
        ).writeAsString(jsonEncode(record), flush: true);
        final pointer = File(p.join(directory.path, 'current.pending'));
        await pointer.writeAsString(p.basename(staged.path), flush: true);
        await pointer.rename(p.join(directory.path, 'current'));
        published = true;
        // Only owned, inactive generations can be removed after successful publication.
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is Directory &&
              entry.path != staged.path &&
              _generationName.hasMatch(p.basename(entry.path))) {
            try {
              await entry.delete(recursive: true);
            } on FileSystemException {
              // Reclamation can be retried after a later successful index.
            }
          }
        }
        return StationIndexResult(
          bundle: root,
          index: directory.path,
          embeddedChunks: counts.embeddedChunks,
          removedChunks: counts.removedChunks,
          writtenChunks: counts.writtenChunks,
          elapsedMs: watch.elapsedMilliseconds,
        );
      } finally {
        if (!published && await staged.exists()) {
          await staged.delete(recursive: true);
        }
      }
    } finally {
      await encoder.embedder.dispose();
    }
  });

  Future<KnowledgeSearchResponse> search(
    String bundle,
    String query, {
    int limit = 5,
  }) => _withBundle(bundle, (root, directory) async {
    final record = await _readCurrent(directory);
    if (record == null ||
        record.configuration != _configuration ||
        record.inventory != await _inventory(root)) {
      throw const StationException(
        'Index is missing, stale or incompatible. Run station index <bundle>.',
      );
    }
    final snapshot = record.snapshot;
    if (snapshot.bundleId != root) {
      throw const StationException(
        'Index belongs to another bundle. Run station index <bundle>.',
      );
    }
    final encoder = await _openEncoder();
    try {
      final store = ObjectBoxStore(p.join(directory.path, record.generation));
      try {
        final index = KnowledgeIndex.openSnapshot(
          snapshot: snapshot,
          store: store,
          embedder: encoder.embedder,
          includeContext: true,
        );
        if (record.model != index.embeddingModelName ||
            record.source != encoder.embedder.sourceName) {
          throw const StationException(
            'Embedding configuration changed. Run station index <bundle>.',
          );
        }
        final response = await index.search(
          query,
          mode: KnowledgeRetrievalMode.dense,
          limit: limit,
          policy: KnowledgeSearchPolicy(expandRelationships: true),
        );
        if (record.inventory != await _inventory(root)) {
          throw const StationException(
            'Knowledge changed during search. Run station index <bundle>.',
          );
        }
        return response;
      } finally {
        await store.close();
      }
    } finally {
      await encoder.embedder.dispose();
    }
  });

  Future<_SavedIndex?> _readCurrent(Directory directory) async {
    final pointer = File(p.join(directory.path, 'current'));
    if (!await pointer.exists()) return null;
    try {
      final generation = await pointer.readAsString();
      if (!_generationName.hasMatch(generation)) throw const FormatException();
      final record = Map<String, Object?>.from(
        jsonDecode(
              await File(
                p.join(directory.path, generation, 'snapshot.json'),
              ).readAsString(),
            )
            as Map,
      );
      for (final key in ['configuration', 'model', 'source', 'inventory']) {
        if (record[key] is! String) throw const FormatException();
      }
      return (
        configuration: record['configuration']! as String,
        model: record['model']! as String,
        source: record['source']! as String,
        inventory: record['inventory']! as String,
        generation: generation,
        snapshot: KnowledgeSnapshot.fromMap(
          Map<String, Object?>.from(record['snapshot']! as Map),
        ),
      );
    } on Object {
      throw const StationException(
        'Saved index is incomplete or incompatible. Run station index <bundle>.',
      );
    }
  }

  Future<String> _inventory(String root) async {
    final paths = <String, String>{};
    await for (final entry in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final path = p.posix.joinAll(p.split(p.relative(entry.path, from: root)));
      paths[path] = path.endsWith('.md')
          ? sha256.convert(utf8.encode(await entry.readAsString())).toString()
          : 'asset';
    }
    return _inventoryHash(paths);
  }

  String _inventoryHash(Map<String, String> paths) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            for (final path in paths.keys.toList()..sort()) path: paths[path],
          }),
        ),
      )
      .toString();
}
