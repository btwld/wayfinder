import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:path/path.dart' as p;

import 'graph.dart';
import 'index_result.dart';

typedef _SavedIndex = ({
  String configuration,
  String model,
  String source,
  String inventory,
  String generation,
  KnowledgeSnapshot snapshot,
});

typedef _CachedSavedIndex = ({
  String directory,
  String text,
  _SavedIndex index,
});

/// Scoped to one project query; native model ownership stays with the command.
class _SharedQueryEmbedder extends BaseEmbedder {
  _SharedQueryEmbedder(this.delegate);
  final BaseEmbedder delegate;
  Future<List<double>>? _vector;

  @override
  String get sourceName => delegate.sourceName;
  @override
  String get modelName => delegate.modelName;
  @override
  int get dimension => delegate.dimension;
  @override
  Future<List<double>> generateEmbedding(String text) =>
      delegate.generateEmbedding(text);
  @override
  Future<List<double>> generateQueryVector(String text) =>
      _vector ??= delegate.generateQueryVector(text);
}

class WayfinderException implements Exception {
  const WayfinderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns an encoder and its tokenizer for one command.
class WayfinderEncoder {
  WayfinderEncoder(this.embedder, this.countTokens, this.maxTokens);
  final BaseEmbedder embedder;
  final Future<int> Function(String) countTokens;
  final int maxTokens;
}

/// Coordinates bundle ownership, freshness and completed index generations.
///
/// Commands sharing a bundle serialize before opening ObjectBox. Updates happen
/// in a private generation; only a flushed completion record and closed database
/// may be published. An inference failure never modifies the active generation.
class WayfinderKnowledge {
  WayfinderKnowledge({
    Directory? dataDirectory,
    this.keepEncoderAlive = false,
    Future<WayfinderEncoder> Function()? openEncoder,
    ({String model, String source})? encoderIdentity,
  }) : dataDirectory = dataDirectory ?? defaultDataDirectory(),
       _openEncoder = openEncoder ?? _openLocalEncoder,
       _encoderIdentity = encoderIdentity,
       _localEncoder = openEncoder == null && !_modelOverride();

  /// An explicit model path must be verified by loading it, so an invalid
  /// setting fails instead of reporting a current index.
  static bool _modelOverride() {
    final env = Platform.environment;
    return env.containsKey('WAYFINDER_EMBEDDING_MODEL') ||
        env.containsKey('KNOWLEDGE_EMBEDDING_MODEL');
  }

  /// MCP keeps a lazily opened encoder across calls; one-shot CLI calls do not.
  /// Retrieval operations are serialized while sharing the native encoder.
  final bool keepEncoderAlive;
  int _encoderSessions = 0;
  bool get _retainEncoder => keepEncoderAlive || _encoderSessions > 0;
  final Object _encoderRetentionKey = Object();
  WayfinderEncoder? _retainedEncoder;
  // Reuse only one completely parsed record, never an open store or response.
  // File contents are still read on every call; source freshness is independent.
  static const _maxCachedSnapshotBytes = 64 * 1024 * 1024;
  _CachedSavedIndex? _cachedSavedIndex;
  Future<void> _pending = Future.value();
  Future<void>? _closing;

  Future<T> _retrieval<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future.error(StateError('Wayfinder knowledge service is closed.'));
    }
    // Admission decides both serialization and encoder ownership. Async source
    // reads must not let an older standalone operation join a newer session.
    final retain = _retainEncoder;
    Future<T> run() =>
        runZoned(action, zoneValues: {_encoderRetentionKey: retain});
    if (!retain) {
      // One-shot callers retain their existing concurrency, but shutdown must
      // still wait until every accepted operation releases its own resources.
      final result = Future<T>.sync(run);
      final settled = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _pending = Future.wait([_pending, settled]).then<void>((_) {});
      return result;
    }
    final result = _pending.then((_) async {
      try {
        return await run();
      } catch (_) {
        _cachedSavedIndex = null;
        // Do not reuse a potentially failed native encoder on the next call.
        await _disposeRetainedEncoder();
        rethrow;
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<WayfinderEncoder> _acquireEncoder() async {
    final retain =
        Zone.current[_encoderRetentionKey] as bool? ?? _retainEncoder;
    if (!retain) return _openEncoder();
    return _retainedEncoder ??= await _openEncoder();
  }

  Future<void> _releaseEncoder(WayfinderEncoder? encoder) async {
    // A standalone operation can overlap the start of a retained session. Its
    // private encoder stays privately owned even when the session policy changes.
    if (!identical(encoder, _retainedEncoder)) {
      await encoder?.embedder.dispose();
    }
  }

  /// Retains one lazily opened encoder for a multi-step command, then releases
  /// it. The long-lived MCP policy still owns its encoder beyond this scope.
  Future<T> withEncoderSession<T>(Future<T> Function() action) async {
    if (_closing != null) {
      throw StateError('Wayfinder knowledge service is closed.');
    }
    _encoderSessions++;
    try {
      return await action();
    } finally {
      _encoderSessions--;
      while (!_retainEncoder) {
        final pending = _pending;
        await pending;
        // Another session may have accepted work and already ended its action
        // while this drain awaited an older tail. Dispose only at a stable tail.
        if (_retainEncoder) break;
        if (!identical(pending, _pending)) continue;
        await _disposeRetainedEncoder();
        break;
      }
    }
  }

  Future<void> _disposeRetainedEncoder() async {
    final encoder = _retainedEncoder;
    _retainedEncoder = null;
    await encoder?.embedder.dispose();
  }

  /// Reject new work, drain accepted operations, then release native resources.
  Future<void> dispose() => _closing ??= () async {
    await _pending;
    _cachedSavedIndex = null;
    await _disposeRetainedEncoder();
  }();

  final Directory dataDirectory;
  final Future<WayfinderEncoder> Function() _openEncoder;

  /// Identity of an injected encoder, so a current index is recognized without
  /// loading it. The local model's identity is fixed by [_configuration]: a
  /// model path override must verify against the same specification.
  final ({String model, String source})? _encoderIdentity;
  final bool _localEncoder;
  static final _active = <String>{};
  static final _generationName = RegExp(r'^generation-[a-zA-Z0-9_-]+$');

  // Increment when chunking, snapshot or application input semantics change.
  // Lossless oversized-segment recovery and conditional context omission change
  // effective inputs; earlier configurations require one rebuild.
  static final _configuration = jsonEncode({
    'version': 3,
    // Model identity, not provenance: re-mirroring the same verified weights
    // must not force every machine to reindex.
    'model': localEmbeddingModel.identityMap,
    'context': 'okf-context-v2',
    'chunkCharacters': 1000,
    'longInput': 'reject',
    'snapshot': 1,
    'store': '384-v1',
  });

  static Directory defaultDataDirectory() {
    final env = Platform.environment;
    final override = env['WAYFINDER_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override);
    }
    final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'];
      if (local != null) return Directory(p.join(local, 'Wayfinder'));
    } else if (home != null) {
      if (Platform.isMacOS) {
        return Directory(
          p.join(home, 'Library', 'Application Support', 'Wayfinder'),
        );
      }
      final xdg = env['XDG_DATA_HOME'];
      return Directory(
        p.join(
          xdg != null && p.isAbsolute(xdg)
              ? xdg
              : p.join(home, '.local', 'share'),
          'wayfinder',
        ),
      );
    }
    throw const WayfinderException(
      'Cannot locate local app data. Set WAYFINDER_DATA_DIR.',
    );
  }

  static Future<WayfinderEncoder> _openLocalEncoder() async {
    String? modelPath;
    try {
      var model = defaultEmbeddingModelFile();
      if (!model.existsSync() &&
          !Platform.environment.containsKey('WAYFINDER_EMBEDDING_MODEL') &&
          !Platform.environment.containsKey('KNOWLEDGE_EMBEDDING_MODEL')) {
        final package = await Isolate.resolvePackageUri(
          Uri.parse('package:wayfinder_embeddings/wayfinder_embeddings.dart'),
        );
        if (package != null) {
          model = File.fromUri(package.resolve('../models/embedding.gguf'));
        }
      }
      modelPath = model.path;
      final embedder = await LlamaEmbedder.open(modelFile: model);
      return WayfinderEncoder(
        embedder,
        embedder.countTokens,
        embedder.model.maxTokens,
      );
    } on FileSystemException {
      throw WayfinderException(
        'The local embedding model is missing or unreadable ($modelPath). Reinstall the complete '
        'Wayfinder bundle; for source development run melos run wayfinder_embeddings:prepare.',
      );
    } on FormatException {
      throw WayfinderException(
        'The local embedding model failed verification ($modelPath). Reinstall the complete Wayfinder bundle.',
      );
    }
  }

  Future<T> _withBundle<T>(
    String bundle,
    Future<T> Function(String root, Directory directory) action,
  ) async {
    {
      final name = Platform.isWindows
          ? 'objectbox.dll'
          : Platform.isMacOS
          ? 'libobjectbox.dylib'
          : 'libobjectbox.so';
      var library = File(
        p.join(
          File(Platform.resolvedExecutable).parent.parent.path,
          Platform.isWindows ? 'bin' : 'lib',
          name,
        ),
      );
      if (!library.existsSync()) {
        final package = await Isolate.resolvePackageUri(
          Uri.parse('package:wayfinder_embeddings/wayfinder_embeddings.dart'),
        );
        if (package != null) library = File.fromUri(package.resolve(name));
      }
      if (!library.existsSync()) {
        throw const WayfinderException(
          'The ObjectBox native library is missing. Reinstall the complete '
          'Wayfinder bundle; for source development run melos run objectbox:install.',
        );
      }
      try {
        // Load the selected asset before ObjectBox's fallback discovery, which
        // can print diagnostics to stdout and corrupt an MCP transport.
        DynamicLibrary.open(library.absolute.path);
      } on ArgumentError {
        throw const WayfinderException(
          'The ObjectBox native library cannot load on this platform. '
          'Reinstall the matching Wayfinder bundle.',
        );
      }
    }
    final root = await Directory(bundle).resolveSymbolicLinks();
    if (!await Directory(root).exists()) {
      throw const WayfinderException('The bundle must be a directory.');
    }
    final requested = p.normalize(dataDirectory.absolute.path);
    var ancestor = Directory(requested);
    while (!await ancestor.exists()) {
      if (ancestor.parent.path == ancestor.path) {
        throw const WayfinderException(
          'Cannot resolve the Wayfinder data directory.',
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
      throw const WayfinderException(
        'Wayfinder data must be outside the knowledge bundle.',
      );
    }
    final key = sha256.convert(utf8.encode(root)).toString();
    final directory = Directory(p.join(data, 'indexes', key));
    await directory.create(recursive: true);
    final lockKey = await directory.resolveSymbolicLinks();
    if (!_active.add(lockKey)) {
      throw const WayfinderException(
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
        throw const WayfinderException(
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

  /// Whether the saved index matches the bundle, so [index] has nothing to do.
  Future<bool> isCurrent(String bundle) =>
      _withBundle(bundle, (root, directory) async {
        final _SavedIndex? saved;
        try {
          saved = await _readCurrent(directory);
        } on WayfinderException {
          return false;
        }
        return _isCurrent(root, directory, await _inventory(root), saved);
      });

  /// Creates or refreshes the saved index. A current index returns without
  /// loading the model; [force] discards it and re-embeds every passage.
  Future<WayfinderIndexResult> index(String bundle, {bool force = false}) =>
      _retrieval(() => _index(bundle, force: force));

  Future<WayfinderIndexResult> _index(
    String bundle, {
    bool force = false,
  }) => _withBundle(bundle, (root, directory) async {
    final watch = Stopwatch()..start();
    final inventory = await _inventory(root);
    _SavedIndex? previous;
    try {
      previous = await _readCurrent(directory);
    } on WayfinderException {
      // Index can repair an incompatible/incomplete saved generation.
    }
    if (force) {
      previous = null;
    } else if (await _isCurrent(root, directory, inventory, previous)) {
      return WayfinderIndexResult(
        bundle: root,
        index: directory.path,
        embeddedChunks: 0,
        removedChunks: 0,
        writtenChunks: 0,
        elapsedMs: watch.elapsedMilliseconds,
        current: true,
        warnings: previous!.snapshot.diagnostics,
      );
    }
    final encoder = await _acquireEncoder();
    try {
      final space = '${encoder.embedder.modelName}:okf-context-v2';
      final compatible =
          previous?.configuration == _configuration &&
          previous?.model == space &&
          previous?.source == encoder.embedder.sourceName;
      final oldDatabase = previous == null
          ? null
          : File(p.join(directory.path, previous.generation, 'data.mdb'));
      if (oldDatabase != null) {
        if (!await oldDatabase.exists() ||
            !ObjectBoxStore.hasSupportedSchema(oldDatabase.parent.path)) {
          previous = null;
        }
      }
      final fitted = compatible && previous?.inventory == inventory
          ? previous!.snapshot
          : await (await KnowledgeSnapshot.load(
              root,
              bundleId: root,
              linkFields: wayfinderLinkFields,
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
        throw const WayfinderException(
          'Knowledge changed while loading. Run wayfinder index again.',
        );
      }
      final staged = await directory.createTemp('generation-');
      var published = false;
      try {
        if (compatible && previous != null) {
          final old = p.join(directory.path, previous.generation);
          // No open store or other Wayfinder command can write while the lock is held.
          await File(
            p.join(old, 'data.mdb'),
          ).copy(p.join(staged.path, 'data.mdb'));
          for (final name in ObjectBoxStore.schemaMarkerNames) {
            final marker = File(p.join(old, name));
            if (await marker.exists()) {
              await marker.copy(p.join(staged.path, name));
            }
          }
        }
        final store = ObjectBoxStore.open(staged.path);
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
          throw const WayfinderException(
            'Knowledge changed while indexing. Run wayfinder index again.',
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
        return WayfinderIndexResult(
          bundle: root,
          index: directory.path,
          warnings: fitted.diagnostics,
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
      await _releaseEncoder(encoder);
    }
  });

  Future<KnowledgeSearchResponse> search(
    String bundle,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) =>
      _retrieval(() => _search(bundle, query, limit: limit, filters: filters));

  Future<KnowledgeSearchResponse> _search(
    String bundle,
    String query, {
    required int limit,
    KnowledgeMetadataFilter? filters,
  }) async {
    WayfinderEncoder? encoder;
    try {
      return await _searchBundle(
        bundle,
        query,
        limit: limit,
        filters: filters,
        encoder: () async {
          return encoder ??= await _acquireEncoder();
        },
      );
    } finally {
      await _releaseEncoder(encoder);
    }
  }

  /// One model and one query vector for all selected bundles. Each bundle keeps
  /// its existing saved index, freshness checks and operation lock.
  Future<List<KnowledgeSearchResponse>> searchBundles(
    List<String> bundles,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) => _retrieval(
    () => _searchBundles(bundles, query, limit: limit, filters: filters),
  );

  Future<List<KnowledgeSearchResponse>> _searchBundles(
    List<String> bundles,
    String query, {
    required int limit,
    KnowledgeMetadataFilter? filters,
  }) async {
    WayfinderEncoder? encoder;
    BaseEmbedder? queryEmbedder;
    try {
      final results = <KnowledgeSearchResponse>[];
      for (final bundle in bundles) {
        try {
          results.add(
            await _searchBundle(
              bundle,
              query,
              limit: limit,
              filters: filters,
              allContext: true,
              encoder: () async {
                encoder ??= await _acquireEncoder();
                queryEmbedder ??= _SharedQueryEmbedder(encoder!.embedder);
                return WayfinderEncoder(
                  queryEmbedder!,
                  encoder!.countTokens,
                  encoder!.maxTokens,
                );
              },
            ),
          );
        } on WayfinderException catch (error) {
          throw WayfinderException('$bundle: ${error.message}');
        }
      }
      return results;
    } finally {
      await _releaseEncoder(encoder);
    }
  }

  Future<KnowledgeSearchResponse> _searchBundle(
    String bundle,
    String query, {
    required int limit,
    required Future<WayfinderEncoder> Function() encoder,
    bool allContext = false,
    KnowledgeMetadataFilter? filters,
  }) => _withBundle(bundle, (root, directory) async {
    final record = await _readCurrent(directory);
    if (record == null ||
        record.configuration != _configuration ||
        record.inventory != await _inventory(root)) {
      throw const WayfinderException(
        'Index is missing, stale or incompatible. Run wayfinder index <bundle>.',
      );
    }
    final snapshot = record.snapshot;
    if (snapshot.bundleId != root) {
      throw const WayfinderException(
        'Index belongs to another bundle. Run wayfinder index <bundle>.',
      );
    }
    final activeEncoder = await encoder();
    final store = ObjectBoxStore.open(
      p.join(directory.path, record.generation),
    );
    try {
      final index = KnowledgeIndex.fromSnapshot(
        snapshot: snapshot,
        store: store,
        embedder: activeEncoder.embedder,
        includeContext: true,
      );
      if (record.model != index.embeddingModelName ||
          record.source != activeEncoder.embedder.sourceName) {
        throw const WayfinderException(
          'Embedding configuration changed. Run wayfinder index <bundle>.',
        );
      }
      final response = await index.search(
        query,
        limit: limit,
        contextLimit: allContext ? snapshot.conceptPaths.length : null,
        policy: KnowledgeSearchPolicy(
          expandRelationships: true,
          metadataFilter: filters,
        ),
      );
      if (record.inventory != await _inventory(root)) {
        throw const WayfinderException(
          'Knowledge changed during search. Run wayfinder index <bundle>.',
        );
      }
      return response;
    } on StateError catch (error) {
      if (error.message.startsWith(
        'Dense search requires compatible embeddings',
      )) {
        throw WayfinderException(
          '${error.message} Run wayfinder index <bundle>.',
        );
      }
      rethrow;
    } finally {
      await store.close();
    }
  });

  /// Mirrors search's staleness checks, plus the encoder identity search
  /// compares after loading the model.
  Future<bool> _isCurrent(
    String root,
    Directory directory,
    String inventory,
    _SavedIndex? saved,
  ) async {
    if (saved == null ||
        saved.configuration != _configuration ||
        saved.inventory != inventory ||
        saved.snapshot.bundleId != root) {
      return false;
    }
    final identity = _encoderIdentity;
    if (identity != null) {
      if (saved.model != '${identity.model}:okf-context-v2' ||
          saved.source != identity.source) {
        return false;
      }
    } else if (!_localEncoder) {
      return false;
    }
    final generation = p.join(directory.path, saved.generation);
    return await File(p.join(generation, 'data.mdb')).exists() &&
        ObjectBoxStore.hasSupportedSchema(generation);
  }

  Future<_SavedIndex?> _readCurrent(Directory directory) async {
    final pointer = File(p.join(directory.path, 'current'));
    if (!await pointer.exists()) {
      _cachedSavedIndex = null;
      return null;
    }
    try {
      final generation = await pointer.readAsString();
      if (!_generationName.hasMatch(generation)) throw const FormatException();
      final text = await File(
        p.join(directory.path, generation, 'snapshot.json'),
      ).readAsString();
      final canonicalDirectory = keepEncoderAlive
          ? await directory.resolveSymbolicLinks()
          : null;
      final cached = _cachedSavedIndex;
      if (keepEncoderAlive &&
          cached != null &&
          cached.directory == canonicalDirectory &&
          cached.index.generation == generation &&
          cached.text == text) {
        return cached.index;
      }
      _cachedSavedIndex = null;
      final record = Map<String, Object?>.from(jsonDecode(text) as Map);
      for (final key in ['configuration', 'model', 'source', 'inventory']) {
        if (record[key] is! String) throw const FormatException();
      }
      final saved = (
        configuration: record['configuration']! as String,
        model: record['model']! as String,
        source: record['source']! as String,
        inventory: record['inventory']! as String,
        generation: generation,
        snapshot: KnowledgeSnapshot.fromMap(
          Map<String, Object?>.from(record['snapshot']! as Map),
          linkFields: wayfinderLinkFields,
        ),
      );
      if (keepEncoderAlive &&
          _closing == null &&
          (text.length * 3 <= _maxCachedSnapshotBytes ||
              (text.length <= _maxCachedSnapshotBytes &&
                  utf8.encode(text).length <= _maxCachedSnapshotBytes))) {
        _cachedSavedIndex = (
          directory: canonicalDirectory!,
          text: text,
          index: saved,
        );
      }
      return saved;
    } on Object {
      _cachedSavedIndex = null;
      throw const WayfinderException(
        'Saved index is incomplete or incompatible. Run wayfinder index <bundle>.',
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
