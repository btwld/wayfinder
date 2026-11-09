import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'knowledge_models.dart';
import 'manifest.dart';
import 'reader.dart';

/// One captured file. Adapters enforce acquisition limits before allocating it.
final class KnowledgeCapturedFile {
  KnowledgeCapturedFile({
    String? bundle,
    required String path,
    required List<int> bytes,
    this.mediaType,
  }) : bundle = bundle == null ? null : knowledgeIdentifier(bundle, 'bundle'),
       path = knowledgeRelativePath(path),
       bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String? bundle;
  final String path;
  final Uint8List bytes;
  final String? mediaType;
  late final String digest = sha256.convert(bytes).toString();
}

/// Plain retained input for host-owned bundle processing, without OKF types.
final class KnowledgeRetainedBundle {
  /// Retains files in full-path order and excludes the root coordination lock.
  KnowledgeRetainedBundle({
    required this.id,
    required this.summary,
    required Iterable<KnowledgeCapturedFile> files,
  }) : files = List.unmodifiable(
         files.where((f) => f.path != '.okf.lock').toList()
           ..sort((a, b) => a.path.compareTo(b.path)),
       );

  /// Host-owned bundle identity.
  final String id;

  /// Captured display name, path and concept count.
  final KnowledgeBundleSummary summary;

  /// Immutable path/byte values, including malformed Markdown and attachments.
  final List<KnowledgeCapturedFile> files;
}

/// Adapter semantic projection derived only from captured bytes. A refused graph
/// is not an empty successful graph. Browsing validation stays unavailable;
/// validation is a separate host operation using retained input.
final class KnowledgeCapturedBundle {
  KnowledgeCapturedBundle({
    required String id,
    required this.summary,
    required Iterable<KnowledgeConcept> concepts,
    KnowledgeGraph? graph,
    this.graphFailure,
    String validationReason =
        'This browsing backend does not validate conformance. Validate retained content separately.',
  }) : id = knowledgeIdentifier(id, 'bundle'),
       concepts = Map.unmodifiable({
         for (final c in concepts) c.id: _freezeConcept(c),
       }),
       graph = graph == null
           ? null
           : KnowledgeGraph(
               bundle: graph.bundle,
               nodes: List.unmodifiable(graph.nodes),
               edges: List.unmodifiable(graph.edges),
             ),
       validation = KnowledgeValidationUnavailable(validationReason) {
    knowledgeRelativePath(summary.path);
    if ((graph == null) == (graphFailure == null)) {
      throw ArgumentError('Supply a graph or its refusal, not both.');
    }
  }
  final String id;
  final KnowledgeBundleSummary summary;
  final Map<String, KnowledgeConcept> concepts;
  final KnowledgeGraph? graph;
  final KnowledgeFailure? graphFailure;
  final KnowledgeValidationUnavailable validation;
}

/// Immutable retained capture. Its content-addressed revision covers raw bytes
/// external observations and semantic projections; no session counter acts as
/// a revision.
final class KnowledgeCapture {
  /// Retains immutable file, projection and optional external-existence inputs.
  KnowledgeCapture({
    required Iterable<KnowledgeCapturedFile> files,
    required Iterable<KnowledgeCapturedBundle> bundles,
    Map<String, Map<String, bool>> externalPathObservations = const {},
  }) : files = List.unmodifiable(files),
       bundles = List.unmodifiable(bundles),
       externalPathObservations = Map.unmodifiable({
         for (final id in externalPathObservations.keys.toList()..sort())
           id: Map<String, bool>.unmodifiable({
             for (final path
                 in externalPathObservations[id]!.keys.toList()..sort())
               path: externalPathObservations[id]![path]!,
           }),
       }) {
    final ids = <String>{};
    for (final bundle in this.bundles) {
      if (!ids.add(bundle.id)) throw ArgumentError('Duplicate bundle identity');
    }
    for (final bundle in this.bundles) {
      for (final concept in bundle.concepts.values) {
        knowledgeRelativePath('${concept.id}.md');
        if (concept.bundle != bundle.id ||
            concept.path != '${bundle.summary.path}/${concept.id}.md' ||
            concept.lineCount < 1 ||
            !this.files.any(
              (f) => f.bundle == bundle.id && f.path == '${concept.id}.md',
            )) {
          throw ArgumentError(
            'Concept must address an inventoried bundle file.',
          );
        }
      }
      if (bundle.summary.conceptCount != bundle.concepts.length ||
          (bundle.graph != null && bundle.graph!.bundle != bundle.id)) {
        throw ArgumentError(
          'Bundle projection does not match its identity/count.',
        );
      }
    }
    final addresses = <(String?, String)>{};
    for (final file in this.files) {
      if (file.bundle != null && !ids.contains(file.bundle)) {
        throw ArgumentError('Unknown bundle in inventory');
      }
      if (!addresses.add((file.bundle, file.path))) {
        throw ArgumentError('Duplicate resource address');
      }
    }
  }
  final List<KnowledgeCapturedFile> files;
  final List<KnowledgeCapturedBundle> bundles;

  /// Captured existence by bundle ID and decoded outside-bundle relative path.
  /// Missing keys are unknown, not absent; no live disk fallback is permitted.
  final Map<String, Map<String, bool>> externalPathObservations;

  /// SHA-256 of sorted resource bytes/addresses and bundle identities/paths.
  /// Unlike [revision], this excludes semantic projections.
  late final String manifestFingerprint = knowledgeManifestFingerprint(
    files: [for (final f in files) (f.bundle, f.path, f.digest)],
    bundles: [for (final b in bundles) (b.id, b.summary.path)],
  );

  late final String revision = sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'externalPathObservations': externalPathObservations,
            'files': [
              for (final f in files) [f.bundle, f.path, f.digest, f.mediaType],
            ],
            'bundles': [
              for (final b in bundles)
                {
                  'id': b.id,
                  'path': b.summary.path,
                  'name': b.summary.name,
                  'validation': b.validation.reason,
                  'concepts': [
                    for (final c in b.concepts.values)
                      [
                        c.id,
                        c.path,
                        c.title,
                        c.type,
                        c.status,
                        c.body,
                        _yamlRevision(c.frontmatter),
                        c.bundle,
                        c.citation,
                        c.description,
                        c.tags,
                        c.trust.name,
                        c.lineCount,
                        [
                          for (final v in c.sources)
                            [v.id, v.resource, v.title, v.author, v.path],
                        ],
                        [
                          for (final v in c.relationships)
                            [
                              v.relationship,
                              v.target,
                              v.resolution.name,
                              v.conceptId,
                              v.path,
                            ],
                        ],
                        [
                          for (final v in c.backlinks)
                            [
                              v.conceptId,
                              v.path,
                              v.title,
                              v.origin.name,
                              v.relationship,
                            ],
                        ],
                        _stamp(c.generated),
                        [for (final v in c.verified) _stamp(v)],
                        c.staleAfter?.toIso8601String(),
                        c.computation == null
                            ? null
                            : [
                                c.computation!.runtime,
                                [
                                  for (final v in c.computation!.reads)
                                    [
                                      v.target,
                                      v.origin.name,
                                      v.resolution.name,
                                      v.conceptId,
                                      v.path,
                                    ],
                                ],
                              ],
                      ],
                  ],
                  'graph': b.graph == null
                      ? null
                      : {
                          'nodes': [
                            for (final n in b.graph!.nodes)
                              [n.id, n.path, n.title, n.type],
                          ],
                          'edges': [
                            for (final e in b.graph!.edges)
                              [
                                e.source,
                                e.target,
                                e.origin.name,
                                e.resolution.name,
                                e.relationship,
                                e.path,
                              ],
                          ],
                        },
                  'refusal': b.graphFailure == null
                      ? null
                      : [
                          b.graphFailure!.code.name,
                          b.graphFailure!.operation,
                          b.graphFailure!.message,
                          b.graphFailure!.path,
                        ],
                },
            ],
          }),
        ),
      )
      .toString();
}

/// Shared lease mechanics for retained-byte adapters. Capture is coalesced, but
/// each caller gets an independent lease. Cancellation never cancels another
/// caller's capture. Close/revoke reject access before draining accepted work.
abstract base class CapturedKnowledgeProject implements KnowledgeProject {
  CapturedKnowledgeProject(
    String id, {
    required Future<KnowledgeCapture> Function() capture,
  }) : id = knowledgeIdentifier(id, 'project'),
       _capture = capture;
  final Future<KnowledgeCapture> Function() _capture;
  @override
  final String id;
  final _revocations = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get revocations => _revocations.stream;
  final _leases = <_Snapshot>{};
  final _pending = <Future<void>>{};
  Future<KnowledgeCapture>? _capturing;
  Future<void>? _closing;
  bool _closed = false;
  bool _revoked = false;

  void _check(String operation) {
    if (_closed) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.closed,
        operation,
        'The project is closed.',
      );
    }
    if (_revoked) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.denied,
        operation,
        'Source access was revoked.',
      );
    }
  }

  /// Permanent grant loss. Hosts create a new project after obtaining a new grant.
  void revoke() {
    if (_revoked || _closed) return;
    _revoked = true;
    _revocations.add(null);
  }

  @override
  Future<KnowledgeProjectSnapshot> refresh({
    KnowledgeCancellation? cancel,
  }) async {
    _check('refresh');
    cancel?.check('refresh');
    final source = _capturing ??= _startCapture();
    late final KnowledgeCapture data;
    try {
      data = await (cancel == null
          ? source
          : Future.any([
              source,
              cancel.whenCancelled.then<KnowledgeCapture>((_) {
                cancel.check('refresh');
                throw StateError('Cancellation did not cancel');
              }),
            ]));
    } catch (_) {
      // A failed acquisition cannot override a later loss of source authority.
      _check('refresh');
      cancel?.check('refresh');
      rethrow;
    }
    _check('refresh');
    cancel?.check('refresh');
    final lease = _Snapshot(this, data);
    _leases.add(lease);
    return lease;
  }

  Future<KnowledgeCapture> _startCapture() {
    final result = Future<KnowledgeCapture>.sync(_capture);
    final drained = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending.add(drained);
    unawaited(
      drained.then((_) {
        _pending.remove(drained);
        _capturing = null;
      }),
    );
    return result;
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    _closed = true;
    // Closing announces grant loss only once. A synchronous revoke subscriber
    // may itself close the project; emitting again would reenter this stream.
    if (!_revoked) {
      _revoked = true;
      _revocations.add(null);
    }
    unawaited(_drain().then(done.complete, onError: done.completeError));
    return done.future;
  }

  Future<void> _drain() async {
    await Future.wait([for (final lease in _leases.toList()) lease.release()]);
    await Future.wait(_pending.toList());
    await _revocations.close();
  }
}

/// Deterministic backend for apps, examples and contract fixtures. Changing
/// [current] affects only subsequent refreshes; existing leases retain bytes.
final class MemoryKnowledgeProject extends CapturedKnowledgeProject {
  factory MemoryKnowledgeProject({
    required String id,
    required KnowledgeCapture capture,
  }) => MemoryKnowledgeProject._(id, _MemorySource(capture));
  MemoryKnowledgeProject._(super.id, this._source)
    : super(capture: _source.load);
  final _MemorySource _source;
  KnowledgeCapture get current => _source.current;
  set current(KnowledgeCapture value) => _source.current = value;
}

final class _MemorySource {
  _MemorySource(this.current);
  KnowledgeCapture current;
  Future<KnowledgeCapture> load() async => current;
}

final class _Snapshot implements KnowledgeProjectSnapshot {
  _Snapshot(this.owner, KnowledgeCapture capture) : _data = capture {
    _files = List.unmodifiable([
      for (final f in data.files)
        KnowledgeResourceEntry(
          handle: KnowledgeResourceHandle(
            project: owner.id,
            revision: data.revision,
            bundle: f.bundle,
            path: f.path,
          ),
          sizeBytes: f.bytes.length,
          digest: f.digest,
          mediaType: f.mediaType,
        ),
    ]);
    _bundles = List.unmodifiable([
      for (final b in data.bundles) _Bundle(this, b),
    ]);
  }
  final CapturedKnowledgeProject owner;
  KnowledgeCapture? _data;
  KnowledgeCapture get data => _data!;
  List<KnowledgeResourceEntry> _files = const [];
  List<KnowledgeBundleSnapshot> _bundles = const [];
  bool released = false;
  Future<void>? releasing;
  final pending = <Future<void>>{};
  void check(String operation) {
    owner._check(operation);
    if (released) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.closed,
        operation,
        'The snapshot lease was released.',
      );
    }
  }

  @override
  String get projectId {
    check('snapshot');
    return owner.id;
  }

  @override
  String get revision {
    check('snapshot');
    return data.revision;
  }

  @override
  List<KnowledgeResourceEntry> get files {
    check('inventory');
    return _files;
  }

  @override
  List<KnowledgeBundleSnapshot> get bundles {
    check('bundles');
    return _bundles;
  }

  @override
  KnowledgeBundleSnapshot bundle(String id) {
    check('bundle');
    return _bundles.firstWhere(
      (b) => b.id == id,
      orElse: () => throw KnowledgeFailure(
        KnowledgeFailureCode.notFound,
        'bundle',
        'The bundle is not in this snapshot.',
      ),
    );
  }

  Future<T> run<T>(
    String operation,
    KnowledgeCancellation? cancel,
    T Function() action,
  ) {
    check(operation);
    cancel?.check(operation);
    final future = Future<T>(() {
      check(operation);
      cancel?.check(operation);
      return action();
    });
    final done = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    pending.add(done);
    unawaited(done.then((_) => pending.remove(done)));
    return future;
  }

  @override
  Future<KnowledgeSourceBytes> read(
    KnowledgeResourceHandle handle, {
    int maxBytes = 16 * 1024 * 1024,
    KnowledgeCancellation? cancel,
  }) async {
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    return run('read', cancel, () {
      if (handle.project != owner.id || handle.revision != data.revision) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.revisionUnavailable,
          'read',
          'The handle does not belong to this revision.',
        );
      }
      final index = _files.indexWhere((e) => e.handle == handle);
      if (index < 0) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.notFound,
          'read',
          'The resource is not in the permitted inventory.',
          path: handle.path,
        );
      }
      final file = data.files[index];
      if (file.bytes.length > maxBytes) {
        throw KnowledgeFailure(
          KnowledgeFailureCode.tooLarge,
          'read',
          'The resource exceeds the read limit.',
          path: handle.path,
        );
      }
      return KnowledgeSourceBytes(entry: _files[index], bytes: file.bytes);
    });
  }

  @override
  Map<String, Map<String, bool>> get externalPathObservations {
    check('externalPathObservations');
    return data.externalPathObservations;
  }

  @override
  KnowledgeRetainedBundle loadBundle(String bundleId) {
    check('loadBundle');
    final captured = data.bundles.where((b) => b.id == bundleId).firstOrNull;
    if (captured == null) {
      throw KnowledgeFailure(
        KnowledgeFailureCode.notFound,
        'loadBundle',
        'The bundle is not in this snapshot.',
      );
    }
    return KnowledgeRetainedBundle(
      id: captured.id,
      summary: bundle(bundleId).summary,
      files: data.files.where((f) => f.bundle == bundleId),
    );
  }

  @override
  Future<void> release() {
    if (releasing != null) return releasing!;
    released = true;
    return releasing = Future.wait(pending.toList()).then((_) {
      owner._leases.remove(this);
      _data = null;
      _files = const [];
      _bundles = const [];
    });
  }
}

final class _Bundle implements KnowledgeBundleSnapshot {
  _Bundle(this.lease, this.data);
  final _Snapshot lease;
  final KnowledgeCapturedBundle data;
  @override
  String get id {
    lease.check('bundle');
    return data.id;
  }

  @override
  String get revision {
    lease.check('bundle');
    return lease.data.revision;
  }

  @override
  KnowledgeBundleSummary get summary {
    lease.check('bundle');
    final summary = data.summary;
    return KnowledgeBundleSummary(
      name: summary.name,
      path: summary.path,
      conceptCount: summary.conceptCount,
      revision: int.parse(lease.data.revision.substring(0, 12), radix: 16),
    );
  }

  @override
  List<KnowledgeResourceEntry> get files =>
      List.unmodifiable(lease.files.where((e) => e.handle.bundle == data.id));
  @override
  List<KnowledgeConceptSummary> get concepts {
    lease.check('concepts');
    return List.unmodifiable([
      for (final c in data.concepts.values)
        KnowledgeConceptSummary(
          bundle: data.id,
          id: c.id,
          path: c.path,
          title: c.title,
          description: c.description,
          type: c.type,
          tags: c.tags,
        ),
    ]);
  }

  @override
  Future<KnowledgeConcept> concept(
    String id, {
    KnowledgeCancellation? cancel,
  }) async => lease.run(
    'concept',
    cancel,
    () =>
        data.concepts[id] ??
        (throw KnowledgeFailure(
          KnowledgeFailureCode.notFound,
          'concept',
          'The concept is not in this snapshot.',
        )),
  );
  @override
  Future<KnowledgeGraph> graph({KnowledgeCancellation? cancel}) async => lease
      .run('graph', cancel, () => data.graph ?? (throw data.graphFailure!));
  @override
  KnowledgeValidationUnavailable get validation {
    lease.check('validation');
    return data.validation;
  }
}

Object? _freeze(Object? value, [Set<Object>? active]) {
  if (value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is DateTime) {
    return value;
  }
  final ancestors = active ?? HashSet<Object>.identity();
  if (!ancestors.add(value)) {
    throw ArgumentError('Cyclic metadata is not supported.');
  }
  try {
    if (value is Map<Object?, Object?>) {
      return Map<Object?, Object?>.unmodifiable({
        for (final entry in value.entries)
          _scalarKey(entry.key): _freeze(entry.value, ancestors),
      });
    }
    if (value is Iterable<Object?>) {
      return List<Object?>.unmodifiable(
        value.map((v) => _freeze(v, ancestors)),
      );
    }
    throw ArgumentError('Unsupported metadata value: ${value.runtimeType}.');
  } finally {
    ancestors.remove(value);
  }
}

Object? _scalarKey(Object? key) {
  if (key == null ||
      key is String ||
      key is num ||
      key is bool ||
      key is DateTime) {
    return key;
  }
  throw ArgumentError('Metadata mapping keys must be scalar values.');
}

// JSON is just the final encoder, not the metadata domain: tagged mapping
// entries preserve scalar key types, dates and nonfinite numbers without
// coercing or altering the source's supported YAML values.
Object? _yamlRevision(Object? value) => switch (value) {
  final Map<Object?, Object?> map => [
    'map',
    [
      for (final e in map.entries)
        [_yamlRevision(e.key), _yamlRevision(e.value)],
    ],
  ],
  final Iterable<Object?> list => ['list', list.map(_yamlRevision).toList()],
  final DateTime date => ['date', date.toIso8601String()],
  final String string => ['string', string],
  final bool boolean => ['bool', boolean],
  final int integer => ['int', integer.toString()],
  final double number => ['double', number.toString()],
  null => ['null'],
  _ => throw ArgumentError('Unsupported metadata value: ${value.runtimeType}.'),
};
KnowledgeConcept _freezeConcept(KnowledgeConcept c) => KnowledgeConcept(
  bundle: c.bundle,
  id: c.id,
  path: c.path,
  citation: c.citation,
  title: c.title,
  description: c.description,
  type: c.type,
  status: c.status,
  tags: List.unmodifiable(c.tags),
  trust: c.trust,
  frontmatter: Map<String, Object?>.unmodifiable({
    for (final entry in c.frontmatter.entries) entry.key: _freeze(entry.value),
  }),
  sources: List.unmodifiable(c.sources),
  relationships: List.unmodifiable(c.relationships),
  backlinks: List.unmodifiable(c.backlinks),
  generated: c.generated,
  verified: List.unmodifiable(c.verified),
  staleAfter: c.staleAfter,
  computation: c.computation == null
      ? null
      : KnowledgeComputation(
          runtime: c.computation!.runtime,
          reads: List.unmodifiable(c.computation!.reads),
        ),
  body: c.body,
  lineCount: c.lineCount,
);

Object? _stamp(KnowledgeConceptStamp? v) =>
    v == null ? null : [v.by, v.at?.toIso8601String(), v.written];
