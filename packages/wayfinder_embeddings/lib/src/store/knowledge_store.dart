import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart' show okfBundleLockFileName;
import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';

import '../embedding/base_embedder.dart';
import '../embedding/model_cache.dart' show EmbeddingModelCache;
import '../models/embedding.dart';
import '../okf/knowledge_index.dart';
import '../okf/knowledge_snapshot.dart';
import '../storage/memory_store.dart';
import 'encoder.dart';
import 'generation.dart';
import 'generation_pin_hook.dart';
import 'index_result.dart';
import 'project_search.dart';
import 'shared_encoder.dart';

typedef _SavedIndex = ({
  String configuration,
  String model,
  String source,
  String inventory,
  String generation,
  int dimension,
  int count,
  String checksum,
  List<String> inputs,
  KnowledgeSnapshot snapshot,
});

typedef _CachedSavedIndex = ({String text, int bytes, _SavedIndex index});

/// A published generation a reader holds: its record and its vectors, one
/// row per snapshot chunk.
typedef _Pinned = ({_SavedIndex saved, List<Float32List> vectors});

/// A bundle's index for the store's configuration: its canonical `root`,
/// the namespace `directory` that holds its generations, and the `writer`
/// lock file in that directory.
typedef _Namespace = ({String root, Directory directory, File writer});

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

/// Thrown inside the store when a generation's files cannot be read, which
/// garbage collection after a newer publication explains.
final class _GenerationUnreadable implements Exception {
  const _GenerationUnreadable();
}

/// Saved local indexes of OKF bundles, and dense search over them.
///
/// Each bundle's index lives in [dataDirectory] under
/// `indexes/bundles/<bundle key>/<configuration key>/`. The bundle key hashes
/// the bundle's canonical root, so worktrees and copies get indexes of their
/// own. The configuration key hashes the store's chunking, snapshot and
/// storage configuration with its [encoder]'s identity, so a different
/// model, chunker or format never reads or replaces another's index. Indexes
/// earlier releases wrote elsewhere under `indexes/`, by Wayfinder 0.2
/// (`indexes/<sha256 of the root>/`) or by an ObjectBox-backed store
/// (`indexes/<bundle key>/<configuration key>/` with a `.lock` beside it),
/// are never read, changed or deleted; the first [index] after an upgrade
/// builds anew.
///
/// An index is a sequence of immutable generations,
/// `generation-<id>/{snapshot.json, vectors.f32}`, and a `current` pointer
/// that names the published one. [index] embeds only passages whose inputs
/// changed, writes a complete generation and then replaces the pointer
/// atomically, so a failed or cancelled run leaves the previous generation
/// current. A search reads the pointer and the generation it names, checks
/// the vectors' checksum, and scores every eligible passage exactly in a
/// `MemoryStore`. [search] refuses an index that is missing, stale or
/// incompatible, and never indexes implicitly.
///
/// Only writers lock. [index] and [forget] hold the bundle's
/// `writer.lock` (`WayfinderFileLock`), across isolates and processes;
/// another writer meanwhile fails with `index-busy` instead of waiting.
/// [status], [search] and [searchBundle] hold no lock, so they keep working
/// while an index runs: they read the last published generation, which
/// nothing changes. To tell whether a writer runs, they probe the writer
/// lock with `WayfinderFileLock.isHeld`, a shared lock taken for an instant,
/// which a writer's `WayfinderFileLock.tryExclusive` waits out rather than
/// report as busy. A superseded generation stays for [gracePeriod] after
/// the publication that replaced it, so a reader that read the pointer just
/// before still finds it; garbage collection runs after a later
/// publication, and a reader that loses the race anyway reads the pointer
/// again. With [StaleIndexPolicy.serveWhileRefreshing], a search during a
/// refresh serves the last published generation even when the bundle has
/// changed since, with notices. [forget] and [prune] delete generations and
/// keep the lock file; only [prune] deletes a lock file, once it has gone
/// unused for its period.
///
/// The store never locates a model, downloads anything or loads a native
/// library itself: [encoder] supplies encoders (ADR-0018). okf reads each
/// bundle under its `.okf.lock`, which does not exclude isolates, so a
/// process keeps all okf bundle I/O, this store's included, on one isolate.
///
/// Failures are [WayfinderException]s with a stable code:
///
/// - `bundle-missing` when a bundle root is not a directory;
/// - `data-directory-unavailable`, or `data-directory-invalid` when the data
///   directory is inside the bundle;
/// - `index-busy` when another operation is indexing or forgetting the
///   bundle's index, for [index] and [forget], and for a search with
///   [StaleIndexPolicy.serveWhileRefreshing] while the first index of a
///   bundle is being built or an unusable one replaced; on Windows also
///   when readers keep the `current` pointer open for seconds while [index]
///   publishes or [forget] deletes it;
/// - `index-missing`, `index-stale` or `index-incompatible` when [search]
///   finds no usable index; [status] reports the same as a value;
/// - `bundle-changed` when the bundle changed while an operation read it;
/// - `model-missing` or `model-invalid` from the [encoder], and
///   `model-invalid` when an opened encoder reports another identity;
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
  /// snapshot text, for the operations that follow. Operations still run
  /// concurrently: each call into the shared encoder, a batch of document
  /// embeddings, a query vector or a token count, waits for the one before
  /// it, so a search can run between an index's batches. An operation that
  /// fails in the encoder, or with an error that is not a
  /// [WayfinderException], discards both, and the encoder is disposed once
  /// no operation uses it; an expected failure, such as `index-stale`,
  /// `index-busy` or `cancelled`, keeps them. This suits a long-lived
  /// server. Without it, each operation opens and disposes its own encoder.
  /// [dispose] waits for accepted operations and releases the encoder.
  ///
  /// A superseded generation stays readable for [gracePeriod] after a newer
  /// one is published.
  WayfinderKnowledgeStore({
    required this.dataDirectory,
    required this.encoder,
    this.retainEncoder = false,
    this.cacheBytes = 64 << 20,
    this.gracePeriod = const Duration(minutes: 10),
  }) {
    if (cacheBytes < 0) {
      throw ArgumentError.value(cacheBytes, 'cacheBytes', 'must not be < 0');
    }
    if (gracePeriod.isNegative) {
      throw ArgumentError.value(gracePeriod, 'gracePeriod', 'must not be < 0');
    }
  }

  final Directory dataDirectory;
  final WayfinderEncoderProvider encoder;
  final bool retainEncoder;
  final int cacheBytes;
  final Duration gracePeriod;

  // Increment when chunking, snapshot or application input semantics change.
  // `store` names the generation format. The encoder's identity is part of
  // the configuration key beside it.
  static final _configuration = jsonEncode({
    'version': 4,
    'context': 'okf-context-v2',
    'chunkCharacters': 1000,
    'longInput': 'reject',
    'snapshot': 1,
    'store': IndexGeneration.format,
    'chunkIds': 'bundle-relative',
  });

  /// Chunk IDs hash this constant with each chunk's bundle-relative
  /// identity, because one namespace holds one bundle: a bundle's copies in
  /// other directories get the same IDs and rank alike.
  static const _chunkIdNamespace = '.';

  static final _generationName = RegExp(r'^generation-[a-zA-Z0-9_-]+$');
  static final _supersededName = RegExp(
    r'^(generation-[a-zA-Z0-9_-]+)\.superseded$',
  );
  static final _key = RegExp(r'^[0-9a-f]{64}$');
  static const _writerName = 'writer.lock';
  static const _currentName = 'current';
  static const _pendingName = 'current.pending';

  /// How often a reader reads the pointer when the generation it named
  /// disappears.
  static const _readAttempts = 3;

  /// How long a reader waits before each new read of a pointer it could
  /// not read, such as on Windows while a writer replaces it.
  static const _pointerRetryDelays = [
    Duration(milliseconds: 5),
    Duration(milliseconds: 25),
    Duration(milliseconds: 100),
  ];

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

  SharedEncoder? _retained;
  Future<void>? _opening;
  final Set<Future<void>> _disposals = {};
  final Map<String, _CachedSavedIndex> _cachedSavedIndexes = {};
  Future<void> _pending = Future.value();
  Future<void>? _closing;

  /// The saved index of [bundle] compared with the bundle as it is now:
  /// [KnowledgeIndexRefreshing] while another operation indexes or forgets
  /// it. Holds no lock, probing the writer's, and opens no encoder.
  Future<KnowledgeIndexStatus> status(ProjectBundle bundle) => _admit(() async {
    final index = await _namespace(bundle);
    final files = await _inventory(index.root);
    KnowledgeIndexStatus status;
    try {
      status = _assess(index, files, (await _pin(index))?.saved);
    } on WayfinderException catch (error) {
      if (error.code != 'index-incompatible') rethrow;
      status = KnowledgeIndexIncompatible(error.message);
    }
    if (await WayfinderFileLock.isHeld(index.writer)) {
      return KnowledgeIndexRefreshing(status);
    }
    await _recordUse(index);
    return status;
  });

  /// Creates or refreshes [bundle]'s index. A current index returns without
  /// opening an encoder; [force] discards it and re-embeds every passage.
  ///
  /// [onProgress] receives each [IndexPhase] as the run reaches it, and the
  /// embedding count before the first batch and after every batch. A run
  /// reports [IndexPhase.loading] before it opens the encoder, so loading a
  /// model is reported as loading. [cancel] is checked between steps and
  /// batches, last right after the [IndexPhase.publishing] event: a
  /// cancelled run writes nothing, leaves the current generation, and throws
  /// `cancelled`.
  ///
  /// Searches keep reading the current generation while the run embeds, and
  /// read the new one once it is published.
  Future<WayfinderIndexResult> index(
    ProjectBundle bundle, {
    bool force = false,
    void Function(IndexProgress progress)? onProgress,
    WayfinderCancellation? cancel,
  }) => _admit(() async {
    final index = await _namespace(bundle);
    final lock = await _lockWriter(index);
    try {
      return await _encoding((acquire) async {
        final watch = Stopwatch()..start();
        final root = index.root;
        final directory = index.directory;
        throwIfCancelled(cancel);
        onProgress?.call(const IndexProgress(IndexPhase.scanning));
        final files = await _inventory(root);
        final inventory = _inventoryHash(files);
        _Pinned? previous;
        try {
          previous = await _pin(index);
        } on WayfinderException {
          // Indexing replaces an incomplete or incompatible saved generation.
        }
        if (force) {
          previous = null;
        } else if (_assess(index, files, previous?.saved)
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
        final opened = await acquire();
        throwIfCancelled(cancel);
        final saved = previous?.saved;
        final compatible =
            saved != null &&
            saved.configuration == _configuration &&
            saved.model == _space &&
            saved.source == encoder.identity.source &&
            saved.snapshot.bundleId == root &&
            saved.dimension == opened.embedder.dimension;
        final fitted = compatible && saved.inventory == inventory
            ? saved.snapshot
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
        // The previous generation's passages and vectors, so only changed
        // inputs are embedded.
        final store = compatible ? await _memoryOf(previous!) : MemoryStore();
        final counts =
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
        if (_inventoryHash(await _inventory(root)) != inventory) {
          throw const WayfinderException(
            'bundle-changed',
            'Knowledge changed while indexing.',
          );
        }
        onProgress?.call(const IndexProgress(IndexPhase.publishing));
        throwIfCancelled(cancel);
        final rows = <List<double>>[];
        final inputs = <String>[];
        for (final chunk in fitted.chunks) {
          final vector = await store.getEmbedding(
            chunk.id,
            source: encoder.identity.source,
            modelName: _space,
          );
          final input =
              (store.chunks[chunk.id]?.metadata['okfEmbeddingInputs']
                  as Map?)?[_space];
          if (vector == null || input is! String) {
            throw StateError('Indexing left a passage without its vector.');
          }
          rows.add(vector.vector);
          inputs.add(input);
        }
        final dimension = opened.embedder.dimension;
        final bytes = IndexGeneration.encode(rows, dimension);
        await directory.create(recursive: true);
        final staged = await directory.createTemp('generation-');
        var published = false;
        try {
          await File(
            p.join(staged.path, IndexGeneration.vectorsFile),
          ).writeAsBytes(bytes, flush: true);
          final record = {
            'configuration': _configuration,
            'model': _space,
            'source': encoder.identity.source,
            'inventory': inventory,
            'vectors': {
              'file': IndexGeneration.vectorsFile,
              'format': IndexGeneration.format,
              'dimension': dimension,
              'count': rows.length,
              'sha256': IndexGeneration.digest(bytes),
              'inputs': inputs,
            },
            'snapshot': fitted.toMap(),
          };
          await File(
            p.join(staged.path, IndexGeneration.snapshotFile),
          ).writeAsString(jsonEncode(record), flush: true);
          await _publish(index, p.basename(staged.path));
          published = true;
          await _collectGarbage(index, keep: p.basename(staged.path));
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
      });
    } finally {
      await lock.release();
    }
  });

  /// Searches the saved indexes of [bundles] with one query vector and ranks
  /// their passages together under one [limit], from 1 to 100.
  ///
  /// Every bundle must have a usable index; the first that does not fails
  /// the whole search. [stale] decides whether a stale index may be served
  /// while another operation refreshes it. [filters] select passages by
  /// frontmatter before ranking. Every lifecycle status stays eligible.
  Future<KnowledgeProjectSearch> search(
    List<ProjectBundle> bundles,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
    StaleIndexPolicy stale = StaleIndexPolicy.refuse,
  }) => _admit(
    limit: limit,
    () => _encoding((acquire) async {
      BaseEmbedder? queryEmbedder;
      final responses = <KnowledgeSearchResponse>[];
      final freshness = <KnowledgeSearchFreshness>[];
      for (final bundle in bundles) {
        try {
          final found = await _searchIndex(
            await _namespace(bundle),
            query,
            limit: limit,
            filters: filters,
            stale: stale,
            allContext: true,
            encoder: () async {
              final opened = await acquire();
              queryEmbedder ??= _SharedQueryEmbedder(opened.embedder);
              return WayfinderEncoder(
                queryEmbedder!,
                opened.countTokens,
                opened.maxTokens,
              );
            },
          );
          responses.add(found.response);
          freshness.add(found.freshness);
        } on WayfinderException catch (error) {
          throw WayfinderException(
            error.code,
            '${bundle.root}: ${error.message}',
          );
        }
      }
      return KnowledgeProjectSearch(
        bundles,
        responses,
        limit: limit,
        freshness: freshness,
      );
    }),
  );

  /// Searches the saved index of one [bundle], with its own context policy
  /// rather than a project's shared ranking. [stale] is as for [search].
  Future<KnowledgeBundleSearch> searchBundle(
    ProjectBundle bundle,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
    StaleIndexPolicy stale = StaleIndexPolicy.refuse,
  }) => _admit(
    limit: limit,
    () => _encoding((acquire) async {
      final found = await _searchIndex(
        await _namespace(bundle),
        query,
        limit: limit,
        filters: filters,
        stale: stale,
        encoder: acquire,
      );
      return KnowledgeBundleSearch(
        bundle,
        found.response,
        freshness: found.freshness,
      );
    }),
  );

  /// Deletes every configuration's index of [bundle], whose root may no
  /// longer exist, such as a removed worktree. Throws `index-busy`, and
  /// deletes nothing, while an operation indexes any of them; a search
  /// reading one meanwhile then reports it missing. The lock files stay, so
  /// an operation that opened one meanwhile still excludes the next;
  /// [prune] deletes them once they go unused.
  Future<void> forget(ProjectBundle bundle) => _admit(() async {
    final root = await _canonicalPath(bundle.root);
    if (root == null) return;
    final indexes = Directory(
      p.join(await _resolvedDataDirectory(), 'indexes', 'bundles'),
    );
    final directory = Directory(p.join(indexes.path, _rootKey(root)));
    if (!await directory.exists()) return;
    final namespaces = [
      await for (final entry in directory.list(followLinks: false))
        if (entry is Directory && _key.hasMatch(p.basename(entry.path))) entry,
    ];
    final held = <(Directory, WayfinderFileLock)>[];
    try {
      for (final namespace in namespaces) {
        final lock = await WayfinderFileLock.tryExclusive(
          File(p.join(namespace.path, _writerName)),
        );
        if (lock == null) throw _busy;
        held.add((namespace, lock));
      }
      for (final (namespace, _) in held) {
        await _clear(namespace);
      }
    } finally {
      for (final (_, lock) in held) {
        await lock.release();
      }
    }
  });

  /// Deletes what no bundle will use again: every index of a root that no
  /// longer exists, and indexes of other configurations or encoders that no
  /// operation used for [unusedFor]. Indexes an operation is writing are
  /// left for a later prune. Indexes earlier releases wrote elsewhere under
  /// `indexes/` are never touched.
  ///
  /// A lock file is deleted only once no operation used it for [unusedFor],
  /// as well, so no operation is opening it; one that opened it just before
  /// it went locks the file at its path instead, which `WayfinderFileLock`
  /// checks, so two operations never hold the same index.
  ///
  /// It also deletes the `get` lock files of project roots that no longer
  /// exist, once unused for [unusedFor]
  /// (`WayfinderProfileResolver.pruneProjectLocks`), and the temporary files
  /// of model downloads abandoned at least a day ago under `models/`.
  Future<KnowledgePruneResult> prune({
    Duration unusedFor = const Duration(days: 30),
  }) => _admit(() async {
    final data = await _resolvedDataDirectory();
    final indexes = Directory(p.join(data, 'indexes', 'bundles'));
    final removed = <KnowledgePrunedIndex>[];
    final busy = <String>[];
    final now = DateTime.now();
    if (await indexes.exists()) {
      // Listed first: pruning deletes bundle directories that become empty.
      for (final bundleDirectory
          in await indexes.list(followLinks: false).toList()) {
        if (bundleDirectory is! Directory ||
            !_key.hasMatch(p.basename(bundleDirectory.path))) {
          continue;
        }
        var changed = false;
        for (final namespace
            in await bundleDirectory.list(followLinks: false).toList()) {
          if (namespace is! Directory ||
              !_key.hasMatch(p.basename(namespace.path))) {
            continue;
          }
          final key = p.basename(namespace.path);
          final file = File(p.join(namespace.path, _writerName));
          if (!await file.exists()) {
            changed = await _deleteIfEmpty(namespace) || changed;
            continue;
          }
          // Windows refuses to read a lock file another handle holds, so the
          // note is read only while the lock is free.
          if (await WayfinderFileLock.isHeld(file)) {
            busy.add(namespace.path);
            continue;
          }
          String? root;
          try {
            if (jsonDecode(await file.readAsString()) case {
              'root': final String value,
            }) {
              root = value;
            }
          } on FileSystemException {
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
            final bool cleared;
            try {
              cleared = await _clear(namespace);
            } on WayfinderException {
              busy.add(namespace.path);
              continue;
            }
            if (cleared) {
              removed.add(
                KnowledgePrunedIndex(
                  directory: namespace.path,
                  root: root,
                  reason: why,
                ),
              );
            }
            if (await unused() && await _deleteLockFile(lock)) {
              changed = await _deleteIfEmpty(namespace) || changed;
            }
          } finally {
            await lock.release();
          }
        }
        if (changed) await _deleteIfEmpty(bundleDirectory);
      }
    }
    return KnowledgePruneResult(
      removed: removed,
      busy: busy,
      projectLocks: await WayfinderProfileResolver(
        dataDirectory: Directory(data),
      ).pruneProjectLocks(unusedFor: unusedFor),
      downloads: await EmbeddingModelCache.removeAbandonedDownloads(
        Directory(data),
      ),
    );
  });

  /// Rejects new operations, waits for accepted ones, then disposes a
  /// retained encoder. Later calls return the same future.
  Future<void> dispose() => _closing ??= () async {
    await _pending;
    _cachedSavedIndexes.clear();
    final retained = _retained;
    _retained = null;
    if (retained != null) _evict(retained);
    await Future.wait(_disposals.toList());
  }();

  static const _busy = WayfinderException(
    'index-busy',
    'Index is busy. Retry when the current operation finishes.',
  );

  static const _building = WayfinderException(
    'index-busy',
    'The index is being built. Retry when it finishes.',
  );

  static const _incomplete = WayfinderException(
    'index-incompatible',
    'Saved index is incomplete or incompatible.',
  );

  /// Runs [action] unless the store is closed or [limit], when given, is not
  /// from 1 to 100. Operations run concurrently; [dispose] waits for every
  /// accepted one.
  Future<T> _admit<T>(Future<T> Function() action, {int? limit}) {
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
    final result = Future<T>.sync(action);
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending = Future.wait([_pending, settled]).then<void>((_) {});
    return result;
  }

  /// Runs [action], which may acquire an encoder once through its argument;
  /// releases it afterwards. A failure that may have come from the encoder
  /// discards it and the snapshot cache.
  Future<T> _encoding<T>(
    Future<T> Function(Future<WayfinderEncoder> Function() acquire) action,
  ) async {
    SharedEncoder? held;
    Future<WayfinderEncoder> acquire() async =>
        (held ??= await _acquireEncoder()).encoder;
    try {
      return await action(acquire);
    } catch (error) {
      if (_mayHaveFailedEncoder(error)) {
        _cachedSavedIndexes.clear();
        if (held case final used?) _evict(used);
        if (_retained case final retained?) _evict(retained);
      }
      rethrow;
    } finally {
      if (held case final used?) await _releaseEncoder(used);
    }
  }

  /// Whether [error] may have come from the encoder. Every other
  /// [WayfinderException] is an expected outcome the store raised itself,
  /// such as a stale index, a busy lock or a cancellation.
  static bool _mayHaveFailedEncoder(Object error) => switch (error) {
    WayfinderException(:final code) => const {
      'model-missing',
      'model-invalid',
    }.contains(code),
    _ => true,
  };

  /// An encoder for one operation: a new one, or with [retainEncoder] the
  /// shared one, opened once for every operation that waits for it.
  Future<SharedEncoder> _acquireEncoder() async {
    if (!retainEncoder) return SharedEncoder(await _openEncoder())..users = 1;
    while (true) {
      if (_retained case final retained?) {
        retained.users++;
        return retained;
      }
      // Never load a second model while an evicted one is still disposing.
      await Future.wait([
        for (final disposal in _disposals)
          disposal.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ]);
      if (_retained != null) continue;
      await (_opening ??= () async {
        try {
          _retained = SharedEncoder(await _openEncoder());
        } finally {
          _opening = null;
        }
      }());
    }
  }

  Future<void> _releaseEncoder(SharedEncoder shared) async {
    shared.users--;
    if (!retainEncoder) shared.evicted = true;
    if (shared.evicted && shared.users == 0) await _disposeEncoder(shared);
  }

  /// Keeps new operations off [shared], and disposes it once unused.
  void _evict(SharedEncoder shared) {
    shared.evicted = true;
    if (identical(_retained, shared)) _retained = null;
    if (shared.users == 0) unawaited(_disposeEncoder(shared));
  }

  Future<void> _disposeEncoder(SharedEncoder shared) {
    final disposal = shared.dispose();
    if (_disposals.add(disposal)) {
      disposal.whenComplete(() => _disposals.remove(disposal)).ignore();
    }
    return disposal;
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
    } else if (embedder.dimension <= 0) {
      problem =
          'The encoder reports ${embedder.dimension}-dimensional vectors.';
    } else {
      problem = null;
    }
    if (problem != null) {
      await embedder.dispose();
      throw WayfinderException('model-invalid', problem);
    }
    return opened;
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

  /// [bundle]'s index for the store's configuration.
  Future<_Namespace> _namespace(ProjectBundle bundle) async {
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
    final namespace = Directory(
      p.join(data, 'indexes', 'bundles', _rootKey(root), _configurationKey),
    );
    return (
      root: root,
      directory: namespace,
      writer: File(p.join(namespace.path, _writerName)),
    );
  }

  /// Takes [index]'s writer lock and records the bundle root in it, or
  /// throws `index-busy`.
  Future<WayfinderFileLock> _lockWriter(_Namespace index) async {
    WayfinderFileLock? lock;
    for (var attempt = 0; ; attempt++) {
      try {
        lock = await WayfinderFileLock.tryExclusive(index.writer);
        break;
      } on PathNotFoundException {
        // prune deleted an empty directory between creating it and creating
        // the lock file in it; tryExclusive creates it again.
        if (attempt == 2) throw _busy;
      }
    }
    // tryExclusive locks only the file the path names, so a prune that
    // deleted the lock file meanwhile cannot leave two writers on two files.
    if (lock == null) throw _busy;
    try {
      // The note names the root for prune; writing it records the use.
      await lock.writeNote('${jsonEncode({'root': index.root})}\n');
      return lock;
    } catch (_) {
      await lock.release();
      rethrow;
    }
  }

  /// Records a read of [index] as its last use, which [prune] compares with
  /// its period. Best effort: the lock file may be missing or held.
  static Future<void> _recordUse(_Namespace index) async {
    try {
      await index.writer.setLastModified(DateTime.now());
    } on FileSystemException {
      // No index yet, or Windows refuses while another handle holds it.
    }
  }

  /// Makes [generation] current: marks the generation it replaces as
  /// superseded now, then replaces the pointer atomically. Only the writer
  /// lock's holder calls it.
  static Future<void> _publish(_Namespace index, String generation) async {
    final directory = index.directory.path;
    final pointer = File(p.join(directory, _currentName));
    String? replaced;
    try {
      replaced = await pointer.readAsString();
    } on FileSystemException {
      // The first generation.
    }
    if (replaced != null &&
        replaced != generation &&
        _generationName.hasMatch(replaced)) {
      // Written before the pointer moves, and again by every later
      // publication, so its time never precedes the replacement.
      await File(
        p.join(directory, '$replaced.superseded'),
      ).writeAsString('', flush: true);
    }
    final pending = File(p.join(directory, _pendingName));
    await pending.writeAsString(generation, flush: true);
    await _whileReadersClose(() => pending.rename(pointer.path));
  }

  /// Runs [replace], a rename over or deletion of the `current` pointer.
  /// Windows refuses either while a reader has the pointer open, which a
  /// reader does only while it reads it, so on Windows a refusal is retried
  /// for about two seconds and then reported as `index-busy`. Other
  /// platforms never refuse for a reader.
  static Future<void> _whileReadersClose(
    Future<void> Function() replace,
  ) async {
    var delay = const Duration(milliseconds: 10);
    var waited = Duration.zero;
    while (true) {
      try {
        await replace();
        return;
      } on PathNotFoundException {
        rethrow;
      } on FileSystemException {
        if (!Platform.isWindows) rethrow;
        if (waited >= const Duration(seconds: 2)) throw _busy;
      }
      await Future<void>.delayed(delay);
      waited += delay;
      if (delay < const Duration(milliseconds: 320)) delay *= 2;
    }
  }

  /// Deletes [index]'s generations that are not current and not [keep]:
  /// one never published at once, since no reader ever read its name, and a
  /// superseded one once [gracePeriod] has passed since. A deletion that
  /// fails, such as one of a file Windows holds open, waits for the next
  /// publication.
  Future<void> _collectGarbage(_Namespace index, {required String keep}) async {
    final now = DateTime.now();
    final entries = await index.directory.list(followLinks: false).toList();
    final names = {for (final entry in entries) p.basename(entry.path)};
    for (final entry in entries) {
      final name = p.basename(entry.path);
      try {
        if (entry is Directory &&
            _generationName.hasMatch(name) &&
            name != keep) {
          final marker = File(p.join(index.directory.path, '$name.superseded'));
          final stat = await marker.stat();
          if (stat.type == FileSystemEntityType.notFound ||
              now.difference(stat.modified) >= gracePeriod) {
            await entry.delete(recursive: true);
            if (stat.type != FileSystemEntityType.notFound) {
              await marker.delete();
            }
          }
        } else if (entry is File) {
          // A marker whose generation is gone.
          final match = _supersededName.firstMatch(name);
          if (match != null && !names.contains(match[1])) await entry.delete();
        }
      } on FileSystemException {
        // A later publication retries.
      }
    }
  }

  /// Deletes everything in the namespace [directory] but its writer lock,
  /// while holding that lock. Returns whether there was an index to delete.
  ///
  /// The pointer goes first, so a reader then sees no index rather than a
  /// broken one; when it cannot be deleted, such as while a reader on
  /// Windows keeps it open for seconds, this throws `index-busy`. A
  /// generation a reader still has open on Windows stays for a later
  /// [prune].
  static Future<bool> _clear(Directory directory) async {
    var cleared = false;
    if (!await directory.exists()) return false;
    final pointer = File(p.join(directory.path, _currentName));
    try {
      if (await pointer.exists()) {
        await _whileReadersClose(pointer.delete);
        cleared = true;
      }
    } on PathNotFoundException {
      // Gone already.
    } on FileSystemException {
      throw _busy;
    }
    await for (final entry in directory.list(followLinks: false)) {
      if (p.basename(entry.path) == _writerName) continue;
      try {
        await entry.delete(recursive: true);
        cleared = true;
      } on FileSystemException {
        // Open in a reader on Windows; a later prune deletes it.
      }
    }
    return cleared;
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

  /// Deletes [directory] if it is empty; false when it stays.
  static Future<bool> _deleteIfEmpty(Directory directory) async {
    try {
      if (await directory.list().isEmpty) {
        await directory.delete();
        return true;
      }
    } on FileSystemException {
      // An operation started a new index meanwhile.
    }
    return false;
  }

  /// Searches [index]'s published generation with no lock. A generation
  /// that no longer matches the bundle is served only while another
  /// operation holds the writer lock and [stale] allows it.
  Future<
    ({KnowledgeSearchResponse response, KnowledgeSearchFreshness freshness})
  >
  _searchIndex(
    _Namespace index,
    String query, {
    required int limit,
    required Future<WayfinderEncoder> Function() encoder,
    required StaleIndexPolicy stale,
    bool allContext = false,
    KnowledgeMetadataFilter? filters,
  }) async {
    _Pinned? pinned;
    Map<String, String> files;
    KnowledgeIndexStatus status;
    bool refreshing;
    for (var attempt = 0; ; attempt++) {
      WayfinderException? unusable;
      try {
        pinned = await _pin(index);
      } on WayfinderException catch (error) {
        if (error.code != 'index-incompatible') rethrow;
        pinned = null;
        unusable = error;
      }
      files = await _inventory(index.root);
      status = unusable == null
          ? _assess(index, files, pinned?.saved)
          : KnowledgeIndexIncompatible(unusable.message);
      refreshing =
          stale == StaleIndexPolicy.serveWhileRefreshing &&
          await WayfinderFileLock.isHeld(index.writer);
      if (status is KnowledgeIndexCurrent || refreshing || attempt > 0) break;
      // A writer may have published, and released its lock, since the read:
      // read once more when the pointer moved.
      if (await _pointedGeneration(index) == pinned?.saved.generation) break;
    }
    final Set<String> changed;
    switch (status) {
      case KnowledgeIndexCurrent():
        changed = const {};
      case KnowledgeIndexStale(:final changedPaths) when refreshing:
        changed = changedPaths.toSet();
      case KnowledgeIndexMissing() || KnowledgeIndexIncompatible()
          when refreshing:
        throw _building;
      case KnowledgeIndexMissing():
        throw const WayfinderException('index-missing', 'Index is missing.');
      case KnowledgeIndexStale():
        throw const WayfinderException('index-stale', 'Index is stale.');
      case KnowledgeIndexIncompatible(:final reason):
        throw WayfinderException('index-incompatible', reason);
      case KnowledgeIndexRefreshing():
        throw StateError('An assessment is never refreshing.');
    }
    final (:saved, :vectors) = pinned!;
    final snapshot = saved.snapshot;
    final activeEncoder = await encoder();
    if (activeEncoder.embedder.dimension != saved.dimension) {
      throw WayfinderException(
        'index-incompatible',
        'The saved vectors have ${saved.dimension} dimensions; the encoder '
            'produces ${activeEncoder.embedder.dimension}.',
      );
    }
    final store = await _memoryOf(pinned, chunks: false);
    try {
      var response =
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
      if (_inventoryHash(await _inventory(index.root)) !=
          _inventoryHash(files)) {
        throw const WayfinderException(
          'bundle-changed',
          'Knowledge changed during search.',
        );
      }
      if (refreshing) {
        response = KnowledgeSearchResponse(
          matches: response.matches,
          context: response.context,
          notices: [
            ...response.notices,
            _refreshNotice,
            if (changed.isNotEmpty) _sourceChangedNotice(changed),
          ],
        );
      }
      await _recordUse(index);
      return (
        response: response,
        freshness: KnowledgeSearchFreshness(
          refreshing: refreshing,
          changedPaths: Set.unmodifiable(changed),
        ),
      );
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

  static const _refreshNotice =
      'refresh-in-progress: An index refresh is running; these results come '
      'from the last completed index.';

  /// The generation [index]'s pointer names now, or null.
  static Future<String?> _pointedGeneration(_Namespace index) async {
    try {
      return await File(
        p.join(index.directory.path, _currentName),
      ).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  static String _sourceChangedNotice(Set<String> paths) {
    final sorted = paths.toList()..sort();
    const shown = 10;
    final named = sorted.take(shown).join(', ');
    final more = sorted.length > shown
        ? ' and ${sorted.length - shown} more'
        : '';
    return 'source-changed: $named$more changed after the served index was '
        'built; cited lines marked source changed may differ from the files.';
  }

  /// A [MemoryStore] holding [pinned]'s vectors and, with [chunks], its
  /// passages with a hash of the embedding input each vector encodes, which
  /// `KnowledgeIndex.synchronize` compares to reuse it.
  Future<MemoryStore> _memoryOf(_Pinned pinned, {bool chunks = true}) async {
    final (:saved, :vectors) = pinned;
    final store = MemoryStore();
    final snapshot = saved.snapshot.chunks;
    await store.replaceChunks(
      chunks: [
        if (chunks)
          for (final (i, chunk) in snapshot.indexed)
            chunk.copyWith(
              metadata: {
                ...chunk.metadata,
                'okfEmbeddingInputs': {saved.model: saved.inputs[i]},
              },
            ),
      ],
      embeddings: [
        for (final (i, chunk) in snapshot.indexed)
          Embedding(
            chunkId: chunk.id,
            source: saved.source,
            modelName: saved.model,
            vector: vectors[i],
          ),
      ],
      removeChunkIds: const {},
    );
    return store;
  }

  /// What [saved] is worth against the bundle's [files] now.
  KnowledgeIndexStatus _assess(
    _Namespace index,
    Map<String, String> files,
    _SavedIndex? saved,
  ) {
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
    if (_inventoryHash(files) != saved.inventory) {
      final before = _savedFiles(saved.snapshot);
      return KnowledgeIndexStale([
        for (final path in {...before.keys, ...files.keys}.toList()..sort())
          if (before[path] != files[path]) path,
      ]);
    }
    return KnowledgeIndexCurrent(warnings: saved.snapshot.diagnostics);
  }

  /// The files [snapshot] was built from, as [_inventory] lists them.
  static Map<String, String> _savedFiles(KnowledgeSnapshot snapshot) => {
    for (final entry in snapshot.sources.entries)
      entry.key: sha256.convert(utf8.encode(entry.value)).toString(),
    for (final path in snapshot.assets) path: 'asset',
  };

  /// The generation [index]'s pointer names, with its verified vectors, or
  /// null when nothing was published. Takes no lock: generations never
  /// change once published, and when the one the pointer named disappears,
  /// as garbage collection removes a generation superseded long enough
  /// ago, this reads the pointer again, up to [_readAttempts] times. A
  /// pointer that cannot be read, as on Windows while a writer replaces it,
  /// is read again after each of [_pointerRetryDelays]. A generation that
  /// cannot be read while the pointer still names it is
  /// `index-incompatible`.
  Future<_Pinned?> _pin(_Namespace index) async {
    final directory = index.directory;
    final cacheKey = retainEncoder && await directory.exists()
        ? await directory.resolveSymbolicLinks()
        : null;
    final pointer = File(p.join(directory.path, _currentName));
    String? unreadable;
    var attempts = 0;
    var refused = 0;
    while (attempts < _readAttempts) {
      final String generation;
      try {
        generation = await pointer.readAsString();
      } on PathNotFoundException {
        _cachedSavedIndexes.remove(cacheKey);
        return null;
      } on FileSystemException {
        if (refused == _pointerRetryDelays.length) break;
        await Future<void>.delayed(_pointerRetryDelays[refused++]);
        continue;
      }
      attempts++;
      if (!_generationName.hasMatch(generation) || generation == unreadable) {
        break;
      }
      await generationPinned[this]?.call(generation);
      try {
        return await _readGeneration(directory, generation, cacheKey);
      } on _GenerationUnreadable {
        unreadable = generation;
      }
    }
    _cachedSavedIndexes.remove(cacheKey);
    throw _incomplete;
  }

  /// [generation]'s record and verified vectors. Throws
  /// [_GenerationUnreadable] when a file cannot be read, and
  /// `index-incompatible` when one is not what the record says.
  Future<_Pinned> _readGeneration(
    Directory directory,
    String generation,
    String? cacheKey,
  ) async {
    final String text;
    final Uint8List bytes;
    try {
      text = await File(
        p.join(directory.path, generation, IndexGeneration.snapshotFile),
      ).readAsString();
      bytes = await File(
        p.join(directory.path, generation, IndexGeneration.vectorsFile),
      ).readAsBytes();
    } on FileSystemException {
      throw const _GenerationUnreadable();
    }
    try {
      final saved = _parseRecord(generation, text, cacheKey);
      return (
        saved: saved,
        vectors: IndexGeneration.decode(
          bytes,
          dimension: saved.dimension,
          count: saved.count,
          checksum: saved.checksum,
        ),
      );
    } on Object {
      _cachedSavedIndexes.remove(cacheKey);
      throw _incomplete;
    }
  }

  /// The record [text] of [generation], parsed once per text while the
  /// store retains its encoder.
  _SavedIndex _parseRecord(String generation, String text, String? cacheKey) {
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
      'vectors': {
        'file': IndexGeneration.vectorsFile,
        'format': IndexGeneration.format,
        'dimension': final int dimension,
        'count': final int count,
        'sha256': final String checksum,
        'inputs': final List<Object?> inputs,
      },
      'snapshot': final Map<Object?, Object?> snapshot,
    }) {
      final parsed = KnowledgeSnapshot.fromMap(
        Map<String, Object?>.from(snapshot),
        linkFields: wayfinderLinkFields,
      );
      if (count != parsed.chunks.length || inputs.length != count) {
        throw const FormatException('The record does not match its vectors.');
      }
      final saved = (
        configuration: configuration,
        model: model,
        source: source,
        inventory: inventory,
        generation: generation,
        dimension: dimension,
        count: count,
        checksum: checksum,
        inputs: List<String>.unmodifiable(inputs.cast<String>()),
        snapshot: parsed,
      );
      if (cacheKey != null && _closing == null && text.length <= cacheBytes) {
        _remember(cacheKey, text, saved);
      }
      return saved;
    }
    throw const FormatException('The record is incomplete.');
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
