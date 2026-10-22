import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:objectbox/objectbox.dart' show Store;
import 'package:okf/okf_io.dart' show okfBundleLockFileName;
import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';

import '../embedding/base_embedder.dart';
import '../okf/knowledge_index.dart';
import '../okf/knowledge_snapshot.dart';
import '../storage/embedding_entities.dart' show objectBoxEmbeddingDimension;
import '../storage/objectbox_store.dart';
import 'encoder.dart';
import 'index_result.dart';
import 'project_search.dart';

typedef _SavedIndex = ({
  String configuration,
  String model,
  String source,
  String inventory,
  String generation,
  KnowledgeSnapshot snapshot,
});

typedef _CachedSavedIndex = ({String text, int bytes, _SavedIndex index});

/// A bundle's index for the store's configuration: its canonical `root`,
/// the namespace `directory` that holds its generations, and the `lock`
/// file beside that directory.
typedef _Namespace = ({String root, Directory directory, File lock});

/// One query vector for every bundle of a project search; the encoder stays
/// owned by the operation.
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

/// Saved local indexes of OKF bundles, and dense search over them.
///
/// Each bundle's index lives in [dataDirectory] under
/// `indexes/<bundle key>/<configuration key>/`. The bundle key hashes the
/// bundle's canonical root, so worktrees and copies get indexes of their
/// own. The configuration key hashes the store's chunking, snapshot and
/// storage configuration with its [encoder]'s identity, so a different
/// model, chunker or format never reads or replaces another's index. An
/// index Wayfinder 0.2 wrote (`indexes/<sha256 of the root>/`) is never read,
/// changed or deleted; the first [index] after an upgrade builds anew.
///
/// An index is a sequence of generations: [index] stages one, embeds only
/// passages whose inputs changed, and publishes it only once it is complete,
/// so a failed or cancelled run leaves the previous one current and deletes
/// what it staged. [search] refuses an index that is missing, stale or
/// incompatible, and never indexes implicitly.
///
/// One operation at a time holds a bundle's index, across isolates and
/// processes, through the `<configuration key>.lock` file beside it
/// (`WayfinderFileLock`); another operation on it meanwhile fails with
/// `index-busy` instead of waiting. A search while an index runs is
/// therefore refused. [forget] and [prune] delete index directories and
/// keep their lock files; only [prune] deletes a lock file, once it has gone
/// unused for its period.
///
/// The store never locates a model, downloads anything or loads a native
/// library from disk itself: [encoder] supplies encoders, and
/// [loadObjectBox], when given, makes ObjectBox's library available first
/// (ADR-0018). okf reads each bundle under its `.okf.lock`, which does not
/// exclude isolates, so a process keeps all okf bundle I/O, this store's
/// included, on one isolate.
///
/// Failures are [WayfinderException]s with a stable code:
///
/// - `bundle-missing` when a bundle root is not a directory;
/// - `data-directory-unavailable`, or `data-directory-invalid` when the data
///   directory is inside the bundle;
/// - `index-busy` when another operation holds the bundle's index;
/// - `index-missing`, `index-stale` or `index-incompatible` when [search]
///   finds no usable index; [status] reports the same as a value;
/// - `bundle-changed` when the bundle changed while an operation read it;
/// - `model-missing` or `model-invalid` from the [encoder], and
///   `model-invalid` when an opened encoder reports another identity or
///   dimension;
/// - `objectbox-unavailable` from [loadObjectBox], or when ObjectBox's
///   native library cannot load;
/// - `cancelled` when an [index] run was cancelled;
/// - `closed` after [dispose].
///
/// A project [search] prefixes each message with the failing bundle's root.
/// Messages are sentences for a reader and never name a command; a host
/// says how to index.
///
/// A host's tests may extend this class to replace operations; tests that
/// index for real use `package:wayfinder_embeddings/testing.dart`.
class WayfinderKnowledgeStore {
  /// A store over [dataDirectory], usually `WayfinderDataDirectory.resolve()`.
  ///
  /// With [retainEncoder], the store opens one encoder on first use and
  /// keeps it, with each bundle's parsed snapshot up to [cacheBytes] of
  /// snapshot text, for the operations that follow. [index], [search] and
  /// [searchBundle] then run one at a time; [status], [forget] and [prune],
  /// which need no encoder, do not wait for them. An operation that fails
  /// in the encoder or ObjectBox, or with an error that is not a
  /// [WayfinderException], discards both; an expected failure, such as
  /// `index-stale`, `index-busy` or `cancelled`, keeps them. This suits a
  /// long-lived server. Without it, each operation opens and disposes its
  /// own encoder and operations run concurrently. [dispose] waits for
  /// accepted operations and releases the encoder.
  ///
  /// [loadObjectBox] runs before the store first opens an ObjectBox
  /// database, and again after it fails. Leave it null when the host loaded
  /// ObjectBox already or ships it where ObjectBox finds it, such as
  /// Flutter's `objectbox_flutter_libs`. Either way the store then checks
  /// that the library loads, and reports `objectbox-unavailable` when it does
  /// not; what ObjectBox prints while it looks for the library is dropped,
  /// so it never reaches a host's stdout.
  WayfinderKnowledgeStore({
    required this.dataDirectory,
    required this.encoder,
    this.retainEncoder = false,
    this.cacheBytes = 64 << 20,
    this.loadObjectBox,
  }) {
    if (cacheBytes < 0) {
      throw ArgumentError.value(cacheBytes, 'cacheBytes', 'must not be < 0');
    }
  }

  final Directory dataDirectory;
  final WayfinderEncoderProvider encoder;
  final bool retainEncoder;
  final int cacheBytes;
  final FutureOr<void> Function()? loadObjectBox;

  // Increment when chunking, snapshot or application input semantics change,
  // or when the inference runtime does: another llama.cpp build can change
  // vectors from the same model. Version 5 is llamadart 0.15 with
  // llamadart-native v0.7.0-2 (tool/src/native_cli_assets.dart). The
  // encoder's identity is part of the configuration key beside it.
  static final _configuration = jsonEncode({
    'version': 5,
    'context': 'okf-context-v2',
    'chunkCharacters': 1000,
    'longInput': 'reject',
    'snapshot': 1,
    'store': '384-v1',
    'chunkIds': 'bundle-relative',
  });

  /// Chunk IDs hash this constant with each chunk's bundle-relative
  /// identity, because one namespace holds one bundle: a bundle's copies in
  /// other directories get the same IDs and rank alike.
  static const _chunkIdNamespace = '.';

  static final _generationName = RegExp(r'^generation-[a-zA-Z0-9_-]+$');
  static final _key = RegExp(r'^[0-9a-f]{64}$');
  static final _lockName = RegExp(r'^([0-9a-f]{64})\.lock$');

  String get _space => '${encoder.identity.model}:okf-context-v2';

  late final String _configurationKey = sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'configuration': _configuration,
            'model': _space,
            'source': encoder.identity.source,
          }),
        ),
      )
      .toString();

  /// The bundle key of [root]. Hashing an object, not the bare path as 0.2
  /// did, keeps it from naming a 0.2 index directory.
  static String _rootKey(String root) =>
      sha256.convert(utf8.encode(jsonEncode({'root': root}))).toString();

  WayfinderEncoder? _retainedEncoder;
  Future<void>? _disposingEncoder;
  Future<void>? _objectBoxReady;
  final Map<String, _CachedSavedIndex> _cachedSavedIndexes = {};
  Future<void> _pending = Future.value();
  Future<void>? _closing;

  /// The saved index of [bundle] compared with the bundle as it is now.
  /// Opens no encoder and no database.
  Future<KnowledgeIndexStatus> status(ProjectBundle bundle) => _admit(
    () => _withIndex(bundle, (index) async {
      final files = await _inventory(index.root);
      final _SavedIndex? saved;
      try {
        saved = await _readCurrent(index.directory);
      } on WayfinderException catch (error) {
        return KnowledgeIndexIncompatible(error.message);
      }
      return _assess(index, files, saved);
    }),
    encoder: false,
  );

  /// Creates or refreshes [bundle]'s index. A current index returns without
  /// opening an encoder; [force] discards it and re-embeds every passage.
  ///
  /// [onProgress] receives each [IndexPhase] as the run reaches it, and the
  /// embedding count before the first batch and after every batch. A run
  /// reports [IndexPhase.loading] before it opens ObjectBox and the encoder,
  /// so loading a model is reported as loading. [cancel]
  /// is checked between steps and batches, last right after the
  /// [IndexPhase.publishing] event: a cancelled run deletes the generation it
  /// staged, leaves the current one, and throws `cancelled`.
  Future<WayfinderIndexResult> index(
    ProjectBundle bundle, {
    bool force = false,
    void Function(IndexProgress progress)? onProgress,
    WayfinderCancellation? cancel,
  }) => _admit(
    () => _withIndex(bundle, (index) async {
      final watch = Stopwatch()..start();
      final root = index.root;
      final directory = index.directory;
      throwIfCancelled(cancel);
      onProgress?.call(const IndexProgress(IndexPhase.scanning));
      final files = await _inventory(root);
      final inventory = _inventoryHash(files);
      _SavedIndex? previous;
      try {
        previous = await _readCurrent(directory);
      } on WayfinderException {
        // Indexing replaces an incomplete or incompatible saved generation.
      }
      if (force) {
        previous = null;
      } else if (await _assess(index, files, previous)
          case KnowledgeIndexCurrent(:final warnings)) {
        return WayfinderIndexResult(
          bundle: root,
          index: directory.path,
          embeddedChunks: 0,
          removedChunks: 0,
          writtenChunks: 0,
          elapsedMs: watch.elapsedMilliseconds,
          current: true,
          warnings: warnings,
        );
      }
      onProgress?.call(const IndexProgress(IndexPhase.loading));
      throwIfCancelled(cancel);
      await _ensureObjectBox();
      final opened = await _acquireEncoder();
      try {
        throwIfCancelled(cancel);
        final compatible =
            previous?.configuration == _configuration &&
            previous?.model == _space &&
            previous?.source == encoder.identity.source;
        if (previous != null &&
            !await _hasDatabase(p.join(directory.path, previous.generation))) {
          previous = null;
        }
        final fitted = compatible && previous?.inventory == inventory
            ? previous!.snapshot
            : await (await KnowledgeSnapshot.load(
                root,
                bundleId: root,
                idNamespace: _chunkIdNamespace,
                linkFields: wayfinderLinkFields,
              )).fitInputs(
                countTokens: opened.countTokens,
                maxTokens: opened.maxTokens,
                includeContext: true,
              );
        if (_inventoryHash(_savedFiles(fitted)) != inventory) {
          throw const WayfinderException(
            'bundle-changed',
            'Knowledge changed while loading.',
          );
        }
        throwIfCancelled(cancel);
        await directory.create(recursive: true);
        final staged = await directory.createTemp('generation-');
        var published = false;
        try {
          if (compatible && previous != null) {
            final old = p.join(directory.path, previous.generation);
            // Only the lock holder writes this namespace.
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
          late final ({
            int embeddedChunks,
            int removedChunks,
            int writtenChunks,
          })
          counts;
          try {
            counts =
                await KnowledgeIndex(
                  store: store,
                  embedder: opened.embedder,
                  includeContext: true,
                ).synchronize(
                  fitted,
                  onEmbedded: onProgress == null
                      ? null
                      : (embedded, total) => onProgress(
                          IndexProgress(
                            IndexPhase.embedding,
                            completed: embedded,
                            total: total,
                          ),
                        ),
                  cancel: cancel,
                );
          } finally {
            await store.close();
          }
          if (_inventoryHash(await _inventory(root)) != inventory) {
            throw const WayfinderException(
              'bundle-changed',
              'Knowledge changed while indexing.',
            );
          }
          onProgress?.call(const IndexProgress(IndexPhase.publishing));
          throwIfCancelled(cancel);
          final record = {
            'configuration': _configuration,
            'model': _space,
            'source': encoder.identity.source,
            'inventory': inventory,
            'snapshot': fitted.toMap(),
          };
          await File(
            p.join(staged.path, 'snapshot.json'),
          ).writeAsString(jsonEncode(record), flush: true);
          final pointer = File(p.join(directory.path, 'current.pending'));
          await pointer.writeAsString(p.basename(staged.path), flush: true);
          try {
            await pointer.rename(p.join(directory.path, 'current'));
          } on PathNotFoundException {
            // Only another holder of this namespace removes the pending
            // pointer; this run publishes nothing.
            throw _busy;
          }
          published = true;
          // Only this namespace's inactive generations, after publication.
          await for (final entry in directory.list(followLinks: false)) {
            if (entry is Directory &&
                entry.path != staged.path &&
                _generationName.hasMatch(p.basename(entry.path))) {
              try {
                await entry.delete(recursive: true);
              } on FileSystemException {
                // A later successful index retries the reclamation.
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
        await _releaseEncoder(opened);
      }
    }),
  );

  /// Searches the saved indexes of [bundles] with one query vector and ranks
  /// their passages together under one [limit], from 1 to 100.
  ///
  /// Every bundle must have a current index; the first that does not fails
  /// the whole search. [filters] select passages by frontmatter before
  /// ranking. Every lifecycle status stays eligible.
  Future<KnowledgeProjectSearch> search(
    List<ProjectBundle> bundles,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) => _admit(limit: limit, () async {
    WayfinderEncoder? opened;
    BaseEmbedder? queryEmbedder;
    try {
      final responses = <KnowledgeSearchResponse>[];
      for (final bundle in bundles) {
        try {
          responses.add(
            await _withIndex(
              bundle,
              (index) => _searchIndex(
                index,
                query,
                limit: limit,
                filters: filters,
                allContext: true,
                encoder: () async {
                  opened ??= await _acquireEncoder();
                  queryEmbedder ??= _SharedQueryEmbedder(opened!.embedder);
                  return WayfinderEncoder(
                    queryEmbedder!,
                    opened!.countTokens,
                    opened!.maxTokens,
                  );
                },
              ),
            ),
          );
        } on WayfinderException catch (error) {
          throw WayfinderException(
            error.code,
            '${bundle.root}: ${error.message}',
          );
        }
      }
      return KnowledgeProjectSearch(bundles, responses, limit: limit);
    } finally {
      await _releaseEncoder(opened);
    }
  });

  /// Searches the saved index of one [bundle], with its own context policy
  /// rather than a project's shared ranking.
  Future<KnowledgeBundleSearch> searchBundle(
    ProjectBundle bundle,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) => _admit(limit: limit, () async {
    WayfinderEncoder? opened;
    try {
      return KnowledgeBundleSearch(
        bundle,
        await _withIndex(
          bundle,
          (index) => _searchIndex(
            index,
            query,
            limit: limit,
            filters: filters,
            encoder: () async => opened ??= await _acquireEncoder(),
          ),
        ),
      );
    } finally {
      await _releaseEncoder(opened);
    }
  });

  /// Deletes every configuration's index of [bundle], whose root may no
  /// longer exist, such as a removed worktree. Throws `index-busy`, and
  /// deletes nothing, while an operation holds any of them. The lock files
  /// stay, so an operation that opened one meanwhile still excludes the
  /// next; [prune] deletes them once they go unused.
  Future<void> forget(ProjectBundle bundle) => _admit(encoder: false, () async {
    final root = await _canonicalPath(bundle.root);
    if (root == null) return;
    final indexes = Directory(
      p.join(await _resolvedDataDirectory(), 'indexes', _rootKey(root)),
    );
    if (!await indexes.exists()) return;
    final keys = <String>{};
    await for (final entry in indexes.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is File) {
        if (_lockName.firstMatch(name) case final match?) keys.add(match[1]!);
      } else if (entry is Directory && _key.hasMatch(name)) {
        keys.add(name);
      }
    }
    final held = <(String, WayfinderFileLock)>[];
    try {
      for (final key in keys) {
        final lock = await WayfinderFileLock.tryExclusive(
          File(p.join(indexes.path, '$key.lock')),
        );
        if (lock == null) throw _busy;
        held.add((key, lock));
      }
      for (final (key, _) in held) {
        final namespace = Directory(p.join(indexes.path, key));
        if (await namespace.exists()) await namespace.delete(recursive: true);
      }
    } finally {
      for (final (_, lock) in held) {
        await lock.release();
      }
    }
  });

  /// Deletes indexes no bundle will use again: every index of a root that
  /// no longer exists, and indexes of other configurations or encoders
  /// that no operation used for [unusedFor]. Indexes an operation holds are
  /// left for a later prune; 0.2 index directories are never touched.
  ///
  /// A lock file is deleted only once no operation used it for [unusedFor],
  /// as well: deleting a lock file that another operation has just opened
  /// would let two operations hold the same index, and a long-unused one is
  /// not being opened.
  Future<KnowledgePruneResult> prune({
    Duration unusedFor = const Duration(days: 30),
  }) => _admit(encoder: false, () async {
    final indexes = Directory(
      p.join(await _resolvedDataDirectory(), 'indexes'),
    );
    final removed = <KnowledgePrunedIndex>[];
    final busy = <String>[];
    if (!await indexes.exists()) return const KnowledgePruneResult();
    final now = DateTime.now();
    // Listed first: pruning deletes bundle directories that become empty.
    for (final bundleDirectory
        in await indexes.list(followLinks: false).toList()) {
      if (bundleDirectory is! Directory ||
          !_key.hasMatch(p.basename(bundleDirectory.path))) {
        continue;
      }
      final locks = [
        await for (final entry in bundleDirectory.list(followLinks: false))
          if (entry is File && _lockName.hasMatch(p.basename(entry.path)))
            entry,
      ];
      var changed = false;
      for (final file in locks) {
        final key = _lockName.firstMatch(p.basename(file.path))![1]!;
        final namespace = Directory(p.join(bundleDirectory.path, key));
        String? root;
        try {
          if (jsonDecode(await file.readAsString()) case {
            'root': final String value,
          }) {
            root = value;
          }
        } on FileSystemException {
          // Windows refuses to read a lock file another handle holds.
          busy.add(namespace.path);
          continue;
        } on FormatException {
          // No note yet: the root is unknown.
        }
        Future<bool> unused() async {
          final FileStat stat;
          try {
            stat = await file.stat();
          } on FileSystemException {
            return false;
          }
          return stat.type == FileSystemEntityType.file &&
              now.difference(stat.modified) >= unusedFor;
        }

        Future<String?> reason() async {
          if (root != null && !await Directory(root).exists()) {
            return 'missing-root';
          }
          if (key == _configurationKey) return null;
          return await unused() ? 'other-configuration' : null;
        }

        if (await reason() == null) continue;
        final lock = await WayfinderFileLock.tryExclusive(file);
        if (lock == null) {
          busy.add(namespace.path);
          continue;
        }
        try {
          // A holder may have used it between the check and the lock.
          final why = await reason();
          if (why == null) continue;
          if (await namespace.exists()) {
            await namespace.delete(recursive: true);
            removed.add(
              KnowledgePrunedIndex(
                directory: namespace.path,
                root: root,
                reason: why,
              ),
            );
          }
          if (await unused()) changed = await _deleteLockFile(lock) || changed;
        } finally {
          await lock.release();
        }
      }
      if (changed) await _deleteIfEmpty(bundleDirectory);
    }
    return KnowledgePruneResult(removed: removed, busy: busy);
  });

  /// Rejects new operations, waits for accepted ones, then disposes a
  /// retained encoder. Later calls return the same future.
  Future<void> dispose() => _closing ??= () async {
    await _pending;
    _cachedSavedIndexes.clear();
    await _disposeRetainedEncoder();
  }();

  static const _busy = WayfinderException(
    'index-busy',
    'Index is busy. Retry when the current operation finishes.',
  );

  /// Runs [action] unless the store is closed or [limit], when given, is not
  /// from 1 to 100. With a retained encoder, actions that need the
  /// [encoder] run one at a time, and only a failure that may have come from
  /// the encoder or ObjectBox discards it and the snapshot cache.
  Future<T> _admit<T>(
    Future<T> Function() action, {
    bool encoder = true,
    int? limit,
  }) {
    if (_closing != null) {
      return Future.error(
        const WayfinderException('closed', 'The knowledge store is closed.'),
      );
    }
    if (limit != null && (limit < 1 || limit > 100)) {
      return Future.error(
        ArgumentError.value(limit, 'limit', 'must be from 1 to 100'),
      );
    }
    if (!retainEncoder || !encoder) {
      // Concurrent, but dispose still waits for every accepted operation.
      final result = Future<T>.sync(action);
      final settled = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _pending = Future.wait([_pending, settled]).then<void>((_) {});
      return result;
    }
    final result = _pending.then((_) async {
      try {
        return await action();
      } catch (error) {
        if (_mayHaveFailedEncoder(error)) {
          _cachedSavedIndexes.clear();
          // Never reuse an encoder that may have failed.
          await _disposeRetainedEncoder();
        }
        rethrow;
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Whether [error] may have come from the encoder or ObjectBox. Every
  /// other [WayfinderException] is an expected outcome the store raised
  /// itself, such as a stale index, a busy lock or a cancellation.
  static bool _mayHaveFailedEncoder(Object error) => switch (error) {
    WayfinderException(:final code) => const {
      'model-missing',
      'model-invalid',
      'objectbox-unavailable',
    }.contains(code),
    _ => true,
  };

  Future<WayfinderEncoder> _acquireEncoder() async {
    if (!retainEncoder) return _openEncoder();
    await _disposingEncoder;
    return _retainedEncoder ??= await _openEncoder();
  }

  Future<WayfinderEncoder> _openEncoder() async {
    final opened = await encoder.open();
    final embedder = opened.embedder;
    final identity = encoder.identity;
    final String? problem;
    if (embedder.modelName != identity.model ||
        embedder.sourceName != identity.source) {
      problem =
          'The encoder reports ${embedder.sourceName} ${embedder.modelName}, '
          'not ${identity.source} ${identity.model}, the identity its '
          'provider declares.';
    } else if (embedder.dimension != objectBoxEmbeddingDimension) {
      problem =
          'The encoder produces ${embedder.dimension}-dimensional vectors; '
          'the index stores $objectBoxEmbeddingDimension.';
    } else {
      problem = null;
    }
    if (problem != null) {
      await embedder.dispose();
      throw WayfinderException('model-invalid', problem);
    }
    return opened;
  }

  Future<void> _releaseEncoder(WayfinderEncoder? opened) async {
    if (!identical(opened, _retainedEncoder)) await opened?.embedder.dispose();
  }

  Future<void> _disposeRetainedEncoder() {
    final retained = _retainedEncoder;
    _retainedEncoder = null;
    if (retained == null) return _disposingEncoder ?? Future.value();
    final previous = _disposingEncoder;
    late final Future<void> current;
    current =
        () async {
          await previous;
          await retained.embedder.dispose();
        }().whenComplete(() {
          if (identical(_disposingEncoder, current)) _disposingEncoder = null;
        });
    return _disposingEncoder = current;
  }

  Future<void> _ensureObjectBox() => _objectBoxReady ??=
      Future.sync(() async {
        await loadObjectBox?.call();
        _checkObjectBox();
      }).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _objectBoxReady = null;
          Error.throwWithStackTrace(error, stackTrace);
        },
      );

  /// Makes ObjectBox load its native library now, if the process has not
  /// loaded it yet, and reports `objectbox-unavailable` when it cannot.
  /// ObjectBox prints a hint to stdout when its search fails, which would
  /// corrupt a host's stdio transport; this drops it.
  static void _checkObjectBox() {
    try {
      runZoned(
        Store.databaseVersion,
        zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
      );
    } on Object catch (error) {
      throw WayfinderException(
        'objectbox-unavailable',
        'The ObjectBox native library cannot load ($error).',
      );
    }
  }

  /// The data directory with symbolic links resolved, as far as it exists.
  Future<String> _resolvedDataDirectory() async =>
      await _canonicalPath(dataDirectory.path) ??
      (throw const WayfinderException(
        'data-directory-unavailable',
        'Cannot resolve the Wayfinder data directory.',
      ));

  /// [path], absolute and with symbolic links resolved as far as it exists,
  /// so a path that no longer exists, such as a removed worktree, names what
  /// it named while it existed. Null when no ancestor of it exists.
  static Future<String?> _canonicalPath(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) return directory.resolveSymbolicLinks();
    final requested = p.normalize(directory.absolute.path);
    var ancestor = Directory(requested);
    while (!await ancestor.exists()) {
      if (ancestor.parent.path == ancestor.path) return null;
      ancestor = ancestor.parent;
    }
    return p.normalize(
      p.join(
        await ancestor.resolveSymbolicLinks(),
        p.relative(requested, from: ancestor.path),
      ),
    );
  }

  /// Runs [action] holding [bundle]'s index.
  Future<T> _withIndex<T>(
    ProjectBundle bundle,
    Future<T> Function(_Namespace index) action,
  ) async {
    final directory = Directory(bundle.root);
    if (!await directory.exists()) {
      throw const WayfinderException(
        'bundle-missing',
        'The bundle must be a directory.',
      );
    }
    final root = await directory.resolveSymbolicLinks();
    final data = await _resolvedDataDirectory();
    if (p.equals(root, data) || p.isWithin(root, data)) {
      throw const WayfinderException(
        'data-directory-invalid',
        'Wayfinder data must be outside the knowledge bundle.',
      );
    }
    final indexes = p.join(data, 'indexes', _rootKey(root));
    final index = (
      root: root,
      directory: Directory(p.join(indexes, _configurationKey)),
      lock: File(p.join(indexes, '$_configurationKey.lock')),
    );
    WayfinderFileLock? lock;
    for (var attempt = 0; ; attempt++) {
      try {
        lock = await WayfinderFileLock.tryExclusive(index.lock);
        break;
      } on PathNotFoundException {
        // prune deleted the empty bundle directory between creating it and
        // creating the lock file in it; tryExclusive creates it again.
        if (attempt == 2) throw _busy;
      }
    }
    if (lock == null) throw _busy;
    try {
      // prune deleted the lock file while this descriptor waited.
      if (!await index.lock.exists()) throw _busy;
      // The note names the root for prune; writing it records the use.
      await lock.writeNote('${jsonEncode({'root': root})}\n');
      return await action(index);
    } finally {
      await lock.release();
    }
  }

  /// Deletes the lock file [lock] holds, and releases it. False when the
  /// file stays: Windows keeps a file another handle has open, and a later
  /// prune deletes it.
  static Future<bool> _deleteLockFile(WayfinderFileLock lock) async {
    Future<bool> delete() async {
      try {
        await lock.file.delete();
        return true;
      } on FileSystemException {
        return false;
      }
    }

    // POSIX deletes an open file, so delete it while holding the lock;
    // Windows needs the handle closed first.
    if (Platform.isWindows) {
      await lock.release();
      return delete();
    }
    final deleted = await delete();
    await lock.release();
    return deleted;
  }

  static Future<void> _deleteIfEmpty(Directory directory) async {
    try {
      if (await directory.list().isEmpty) await directory.delete();
    } on FileSystemException {
      // An operation started a new index meanwhile.
    }
  }

  Future<KnowledgeSearchResponse> _searchIndex(
    _Namespace index,
    String query, {
    required int limit,
    required Future<WayfinderEncoder> Function() encoder,
    bool allContext = false,
    KnowledgeMetadataFilter? filters,
  }) async {
    final record = await _readCurrent(index.directory);
    final files = await _inventory(index.root);
    switch (await _assess(index, files, record)) {
      case KnowledgeIndexMissing():
        throw const WayfinderException('index-missing', 'Index is missing.');
      case KnowledgeIndexStale():
        throw const WayfinderException('index-stale', 'Index is stale.');
      case KnowledgeIndexIncompatible(:final reason):
        throw WayfinderException('index-incompatible', reason);
      case KnowledgeIndexCurrent():
        break;
    }
    final saved = record!;
    final snapshot = saved.snapshot;
    await _ensureObjectBox();
    final activeEncoder = await encoder();
    final store = ObjectBoxStore.open(
      p.join(index.directory.path, saved.generation),
    );
    try {
      final response =
          await KnowledgeIndex.fromSnapshot(
            snapshot: snapshot,
            store: store,
            embedder: activeEncoder.embedder,
            includeContext: true,
          ).search(
            query,
            limit: limit,
            contextLimit: allContext ? snapshot.conceptPaths.length : null,
            policy: KnowledgeSearchPolicy(
              expandRelationships: true,
              metadataFilter: filters,
            ),
          );
      if (_inventoryHash(await _inventory(index.root)) != saved.inventory) {
        throw const WayfinderException(
          'bundle-changed',
          'Knowledge changed during search.',
        );
      }
      return response;
    } on StateError catch (error) {
      if (error.message.startsWith(
        'Dense search requires compatible embeddings',
      )) {
        throw WayfinderException('index-incompatible', error.message);
      }
      rethrow;
    } finally {
      await store.close();
    }
  }

  /// What [saved] is worth against the bundle's [files] now.
  Future<KnowledgeIndexStatus> _assess(
    _Namespace index,
    Map<String, String> files,
    _SavedIndex? saved,
  ) async {
    if (saved == null) return const KnowledgeIndexMissing();
    if (saved.configuration != _configuration) {
      return const KnowledgeIndexIncompatible(
        'The saved index has another configuration.',
      );
    }
    if (saved.model != _space || saved.source != encoder.identity.source) {
      return const KnowledgeIndexIncompatible(
        'Embedding configuration changed.',
      );
    }
    if (saved.snapshot.bundleId != index.root) {
      return const KnowledgeIndexIncompatible(
        'Index belongs to another bundle.',
      );
    }
    if (!await _hasDatabase(p.join(index.directory.path, saved.generation))) {
      return const KnowledgeIndexIncompatible(
        'Saved index is incomplete or incompatible.',
      );
    }
    if (_inventoryHash(files) != saved.inventory) {
      final before = _savedFiles(saved.snapshot);
      return KnowledgeIndexStale([
        for (final path in {...before.keys, ...files.keys}.toList()..sort())
          if (before[path] != files[path]) path,
      ]);
    }
    return KnowledgeIndexCurrent(warnings: saved.snapshot.diagnostics);
  }

  static Future<bool> _hasDatabase(String generation) async =>
      await File(p.join(generation, 'data.mdb')).exists() &&
      ObjectBoxStore.hasSupportedSchema(generation);

  /// The files [snapshot] was built from, as [_inventory] lists them.
  static Map<String, String> _savedFiles(KnowledgeSnapshot snapshot) => {
    for (final entry in snapshot.sources.entries)
      entry.key: sha256.convert(utf8.encode(entry.value)).toString(),
    for (final path in snapshot.assets) path: 'asset',
  };

  Future<_SavedIndex?> _readCurrent(Directory directory) async {
    final cacheKey = retainEncoder && await directory.exists()
        ? await directory.resolveSymbolicLinks()
        : null;
    final pointer = File(p.join(directory.path, 'current'));
    if (!await pointer.exists()) {
      _cachedSavedIndexes.remove(cacheKey);
      return null;
    }
    try {
      final generation = await pointer.readAsString();
      if (!_generationName.hasMatch(generation)) throw const FormatException();
      final text = await File(
        p.join(directory.path, generation, 'snapshot.json'),
      ).readAsString();
      final cached = _cachedSavedIndexes.remove(cacheKey);
      if (cached != null &&
          cached.index.generation == generation &&
          cached.text == text) {
        _cachedSavedIndexes[cacheKey!] = cached;
        return cached.index;
      }
      if (jsonDecode(text) case {
        'configuration': final String configuration,
        'model': final String model,
        'source': final String source,
        'inventory': final String inventory,
        'snapshot': final Map<Object?, Object?> snapshot,
      }) {
        final saved = (
          configuration: configuration,
          model: model,
          source: source,
          inventory: inventory,
          generation: generation,
          snapshot: KnowledgeSnapshot.fromMap(
            Map<String, Object?>.from(snapshot),
            linkFields: wayfinderLinkFields,
          ),
        );
        if (cacheKey != null && _closing == null && text.length <= cacheBytes) {
          _remember(cacheKey, text, saved);
        }
        return saved;
      }
      throw const FormatException();
    } on Object {
      _cachedSavedIndexes.remove(cacheKey);
      throw const WayfinderException(
        'index-incompatible',
        'Saved index is incomplete or incompatible.',
      );
    }
  }

  /// Caches [saved] while its UTF-8 [text] fits [cacheBytes], evicting the
  /// oldest entries.
  void _remember(String key, String text, _SavedIndex saved) {
    final bytes = utf8.encode(text).length;
    if (bytes > cacheBytes) return;
    var total = _cachedSavedIndexes.values.fold<int>(
      0,
      (sum, item) => sum + item.bytes,
    );
    while (_cachedSavedIndexes.isNotEmpty && total + bytes > cacheBytes) {
      final evicted = _cachedSavedIndexes.remove(
        _cachedSavedIndexes.keys.first,
      );
      if (evicted != null) total -= evicted.bytes;
    }
    _cachedSavedIndexes[key] = (text: text, bytes: bytes, index: saved);
  }

  /// Every file of the bundle at [root] as okf's loader sees it: a SHA-256
  /// of each Markdown file's text, or `asset`. Never opens a file named
  /// `.okf.lock`, which okf excludes and another process may hold.
  static Future<Map<String, String>> _inventory(String root) async {
    final files = [
      await for (final entry in Directory(
        root,
      ).list(recursive: true, followLinks: false))
        if (entry is File && p.basename(entry.path) != okfBundleLockFileName)
          entry,
    ];
    final paths = <String, String>{};
    const batchSize = 32;
    for (var i = 0; i < files.length; i += batchSize) {
      final end = i + batchSize < files.length ? i + batchSize : files.length;
      final batch = await Future.wait(
        files.getRange(i, end).map((entry) async {
          final path = p.posix.joinAll(
            p.split(p.relative(entry.path, from: root)),
          );
          final digest = path.endsWith('.md')
              ? sha256
                    .convert(utf8.encode(await entry.readAsString()))
                    .toString()
              : 'asset';
          return MapEntry(path, digest);
        }),
      );
      paths.addEntries(batch);
    }
    return paths;
  }

  static String _inventoryHash(Map<String, String> paths) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            for (final path in paths.keys.toList()..sort()) path: paths[path],
          }),
        ),
      )
      .toString();
}
