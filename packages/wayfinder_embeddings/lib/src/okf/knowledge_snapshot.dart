import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../../wayfinder_embeddings.dart';
import '../models/metadata_collections.dart';
import 'knowledge_input_diagnostic.dart';

/// A parsed bundle projection with original citation locations and graph edges.
/// Indexes and logs remain navigation/history, rather than duplicate passages.
class KnowledgeSnapshot {
  KnowledgeSnapshot._(
    this.bundleId,
    this.chunks,
    this.graph,
    this._metadata,
    this._contextTexts,
    this.sources,
    this.assets, [
    this._recoveries = const [],
  ]);

  // One record per original chunk/code, never per emitted fragment. Keeping
  // identities (rather than only aggregate counts) makes reopened refits lossless.
  final List<_InputRecovery> _recoveries;

  /// Durable recoveries, sorted by source path and code. Counts refer to
  /// original chunks, not fitted fragments or retry attempts.
  late final List<KnowledgeInputDiagnostic> diagnostics = _aggregate(
    _recoveries,
  );

  final String bundleId;
  final List<Chunk> chunks;
  final OkfGraph graph;
  final Map<String, OkfMetadata> _metadata;
  final Map<String, String> _contextTexts;

  /// Original inputs retained to rebuild upstream OKF graph/metadata semantics.
  final Map<String, String> sources;
  final List<String> assets;

  /// Loads a complete inventory using OKF's symlink and parse protections.
  /// No store mutation occurs until the entire snapshot has been read.
  static Future<KnowledgeSnapshot> load(
    String root, {
    required String bundleId,
    int maxChunkLength = 1000,
  }) async {
    final loaded = await const OkfBundleLoader().inspect(root);
    if (loaded.hasFindings) throw OkfBundleLoadException(loaded);
    final sources = <String, String>{...loaded.indexes, ...loaded.logs};
    for (final path in loaded.documents.keys) {
      final file = File(p.joinAll([loaded.rootPath, ...p.posix.split(path)]));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException('Concept changed during loading', path);
      }
      sources[path] = await file.readAsString();
    }
    return KnowledgeSnapshot.fromSources(
      sources,
      bundleId: bundleId,
      assets: loaded.assets,
      maxChunkLength: maxChunkLength,
    );
  }

  /// Parses source text through OKF; producer-defined metadata is retained.
  /// [bundleId] must be stable across updates and unique within a shared store.
  factory KnowledgeSnapshot.fromSources(
    Map<String, String> sources, {
    required String bundleId,
    Iterable<String> assets = const [],
    int maxChunkLength = 1000,
  }) {
    if (bundleId.trim().isEmpty) {
      throw ArgumentError.value(bundleId, 'bundleId');
    }
    final documents = <String, OkfDocument>{};
    final indexes = <String, String>{};
    final logs = <String, String>{};
    for (final entry in sources.entries) {
      switch (p.posix.basename(entry.key)) {
        case 'index.md':
          indexes[entry.key] = entry.value;
        case 'log.md':
          logs[entry.key] = entry.value;
        default:
          documents[entry.key] = OkfDocument.parse(
            entry.value,
            sourcePath: entry.key,
          );
      }
    }
    final bundle = OkfBundle.fromDocuments(
      documents,
      indexes: indexes,
      logs: logs,
      assets: assets,
    );
    final chunker = MarkdownChunker(maxChunkLength: maxChunkLength);
    final chunks = <Chunk>[];
    final metadata = <String, OkfMetadata>{};
    final contextTexts = <String, String>{};
    for (final entry in bundle.concepts.entries) {
      final path = entry.key.documentPath;
      final document = entry.value;
      final frontmatter = freezeMetadataMap(
        document.frontmatter,
        name: 'frontmatter',
      );
      metadata[path] = OkfMetadata.fromFrontmatter(frontmatter);
      final source = sources[path]!
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      // OKF's body is an exact normalized suffix, including its optional blank
      // separator handling. Derive offsets without another frontmatter parser.
      final prefix = source.substring(0, source.length - document.body.length);
      final offset = '\n'.allMatches(prefix).length;
      final bodyChunks = chunker.chunkContent(
        document.body,
        ChunkMetadata(sourcePath: path, contentType: 'markdown'),
      );
      final headings = <({int level, String text})>[];
      // Headings and footnote definitions are document apparatus: headings
      // become context for the passages under them, and OKF resolves per-claim
      // attribution through `sources` rather than footnote prose (OKF 0.2
      // §5.1). A body made only of apparatus still has to be searchable.
      final onlyApparatus = bodyChunks.every(
        (chunk) => chunk.type == 'heading' || chunk.type == 'footnote',
      );
      for (final raw in bodyChunks) {
        if (raw.type == 'heading') {
          final level = raw.metadata['headingLevel']! as int;
          headings.removeWhere((heading) => heading.level >= level);
          headings.add((level: level, text: raw.content));
          if (!onlyApparatus) continue;
        } else if (raw.type == 'footnote' && !onlyApparatus) {
          continue;
        }
        // Identity uses body-relative ranges so adding frontmatter does not
        // invalidate unchanged body embeddings. Citation ranges remain absolute.
        final id = sha256
            .convert(utf8.encode(jsonEncode([bundleId, raw.id])))
            .toString();
        final chunk = raw.copyWith(
          id: id,
          lineStart: raw.lineStart + offset,
          lineEnd: raw.lineEnd + offset,
          metadata: {
            'okf': {
              'bundleId': bundleId,
              'frontmatter': frontmatter,
              'headingPath': headings.map((heading) => heading.text).toList(),
            },
          },
        );
        chunks.add(chunk);
        final context = <String>{
          document.title ?? entry.key.value.split('/').last,
          ...headings.map((heading) => heading.text),
        }.where((text) => text.trim().isNotEmpty && text != raw.content);
        contextTexts[id] = [...context, raw.content].join('\n\n');
      }
    }
    return KnowledgeSnapshot._(
      bundleId,
      List.unmodifiable(chunks),
      OkfGraph.fromBundle(bundle),
      Map.unmodifiable(metadata),
      Map.unmodifiable(contextTexts),
      Map.unmodifiable(sources),
      List.unmodifiable(assets),
    );
  }

  Set<String> get conceptPaths => Set.unmodifiable(_metadata.keys);

  /// A versioned, lossless projection including fitted passages and citations.
  /// Commit this with the corresponding store and embedding configuration.
  Map<String, Object?> toMap() => {
    'version': 1,
    'bundleId': bundleId,
    'sources': sources,
    'assets': assets,
    'chunks': chunks.map((chunk) => chunk.toMap()).toList(),
    'contextTexts': _contextTexts,
    'inputRecoveries': _recoveries.map((r) => r.toMap()).toList(),
  };

  /// Reopens saved passages without tokenization or embedding inference.
  /// Graph and typed metadata meanings are reconstructed by upstream OKF.
  factory KnowledgeSnapshot.fromMap(Map<String, Object?> map) {
    if (map['version'] != 1) {
      throw const FormatException('Unsupported knowledge snapshot version.');
    }
    final original = KnowledgeSnapshot.fromSources(
      Map<String, String>.from(map['sources']! as Map),
      bundleId: map['bundleId']! as String,
      assets: List<String>.from(map['assets']! as List),
    );
    final chunks = (map['chunks']! as List)
        .map((value) => Chunk.fromMap(Map<String, Object?>.from(value as Map)))
        .toList();
    final contexts = Map<String, String>.from(map['contextTexts']! as Map);
    final ids = chunks.map((chunk) => chunk.id).toSet();
    if (ids.length != chunks.length ||
        contexts.length != ids.length ||
        chunks.any(
          (chunk) =>
              !original.conceptPaths.contains(chunk.sourcePath) ||
              !(contexts[chunk.id]?.endsWith(chunk.content) ?? false),
        )) {
      throw const FormatException('Inconsistent saved knowledge passages.');
    }
    return KnowledgeSnapshot._(
      original.bundleId,
      List.unmodifiable(chunks),
      original.graph,
      original._metadata,
      Map.unmodifiable(contexts),
      original.sources,
      original.assets,
      List.unmodifiable(
        (map['inputRecoveries'] as List? ?? const []).map(
          (value) =>
              _InputRecovery.fromMap(Map<String, Object?>.from(value as Map)),
        ),
      ),
    );
  }

  /// Typed OKF metadata, with its upstream defaults and trust semantics.
  OkfMetadata metadataFor(String path) =>
      _metadata[path] ??
      (throw ArgumentError.value(path, 'path', 'Unknown concept'));

  /// Retrieval input; the original source passage is never overwritten.
  String textFor(Chunk chunk, {required bool includeContext}) =>
      includeContext ? _contextTexts[chunk.id]! : chunk.content;

  /// Fits complete effective inputs with the actual tokenizer, without overlap
  /// or truncation. Whitespace stays attached to nonblank text. Irreducible
  /// contextual failures retry the original chunk without derived context;
  /// irreducible body failures remain errors.
  Future<KnowledgeSnapshot> fitInputs({
    required Future<int> Function(String) countTokens,
    required int maxTokens,
    required bool includeContext,
  }) async {
    if (maxTokens <= 0) throw ArgumentError.value(maxTokens, 'maxTokens');
    final output = <Chunk>[];
    final texts = <String, String>{};
    final recoveries = {for (final r in _recoveries) (r.originalId, r.code): r};
    final groups = <String, List<Chunk>>{};
    for (final chunk in chunks) {
      final okf = chunk.metadata['okf']! as Map;
      final root = okf['parentChunkId'] as String? ?? chunk.id;
      groups.putIfAbsent(root, () => []).add(chunk);
    }
    for (final entry in groups.entries) {
      final group = entry.value;
      final first = group.first;
      final originalMetadata = first.metadata['okf']! as Map;
      final originalStart =
          originalMetadata['originalLineStart'] as int? ?? first.lineStart;
      final originalEnd =
          originalMetadata['originalLineEnd'] as int? ?? group.last.lineEnd;
      void record(String code) {
        recoveries[(entry.key, code)] = _InputRecovery(
          entry.key,
          code,
          first.sourcePath,
          originalStart,
          originalEnd,
        );
      }

      Future<({List<Chunk> chunks, Map<String, String> texts, bool split})?>
      attempt(bool context, {bool restart = false}) async {
        final staged = <Chunk>[];
        final inputs = <String, String>{};
        var segmentSplit = false;
        // On context failure retry the complete original body, including when
        // this snapshot was already fitted and reopened. Ordinary refits retain
        // their existing fragment boundaries and IDs.
        final retryMetadata = Map<String, Object?>.from(originalMetadata)
          ..remove('parentChunkId')
          ..remove('characterStart')
          ..remove('characterEnd')
          ..remove('originalLineStart')
          ..remove('originalLineEnd');
        final inputsToFit = restart
            ? [
                first.copyWith(
                  id: entry.key,
                  content: group.map((chunk) => chunk.content).join(),
                  lineStart: originalStart,
                  lineEnd: originalEnd,
                  metadata: {...first.metadata, 'okf': retryMetadata},
                ),
              ]
            : group;
        for (final chunk in inputsToFit) {
          final contextual = context ? _contextTexts[chunk.id]! : '';
          final prefix = context
              ? contextual.substring(
                  0,
                  contextual.length - chunk.content.length,
                )
              : '';
          final ranges = <(int, int)>[];
          Future<bool> fit(int start, int end) async {
            final passage = chunk.content.substring(start, end);
            final input = '$prefix$passage';
            if (input.trim().isEmpty) return false;
            if (await countTokens(input) <= maxTokens) {
              ranges.add((start, end));
              return true;
            }
            // Keep outer whitespace on a nonblank fragment: the encoder rejects
            // blank inputs even when their token count fits. Only split inside
            // the nonblank span; the full, untrimmed halves are measured again.
            final textStart = end - passage.trimLeft().length;
            final textEnd = start + passage.trimRight().length;
            // Prefer a whitespace endpoint nearest the midpoint. No inference
            // about other token counts is made from this input's count.
            final middle = (textStart + textEnd) ~/ 2;
            final boundaries = RegExp(r'\s+')
                .allMatches(passage)
                .map((m) => start + m.end)
                .where((i) => i > textStart && i < textEnd);
            int? cut;
            for (final boundary in boundaries) {
              if (cut == null ||
                  (boundary - middle).abs() < (cut - middle).abs()) {
                cut = boundary;
              }
            }
            if (cut == null) {
              cut = middle;
              if (cut > textStart &&
                  cut < textEnd &&
                  chunk.content.codeUnitAt(cut) >= 0xdc00 &&
                  chunk.content.codeUnitAt(cut) <= 0xdfff &&
                  chunk.content.codeUnitAt(cut - 1) >= 0xd800 &&
                  chunk.content.codeUnitAt(cut - 1) <= 0xdbff) {
                cut--;
                if (cut == textStart) cut += 2;
              }
              if (cut <= textStart || cut >= textEnd) return false;
              segmentSplit = true;
            }
            return await fit(start, cut) && await fit(cut, end);
          }

          if (!await fit(0, chunk.content.length)) return null;
          final okf = chunk.metadata['okf']! as Map<String, Object?>;
          final offset = okf['characterStart'] as int? ?? 0;
          for (final (start, end) in ranges) {
            final passage = chunk.content.substring(start, end);
            final unchanged = start == 0 && end == chunk.content.length;
            final id = unchanged
                ? chunk.id
                : sha256
                      .convert(
                        utf8.encode(
                          jsonEncode([entry.key, offset + start, offset + end]),
                        ),
                      )
                      .toString();
            final lineStart =
                chunk.lineStart +
                '\n'.allMatches(chunk.content.substring(0, start)).length;
            staged.add(
              unchanged
                  ? chunk
                  : chunk.copyWith(
                      id: id,
                      content: passage,
                      lineStart: lineStart,
                      lineEnd:
                          lineStart +
                          '\n'.allMatches(passage.trimRight()).length,
                      metadata: {
                        ...chunk.metadata,
                        'okf': {
                          ...okf,
                          'parentChunkId': entry.key,
                          'characterStart': offset + start,
                          'characterEnd': offset + end,
                          'originalLineStart': originalStart,
                          'originalLineEnd': originalEnd,
                        },
                      },
                    ),
            );
            inputs[id] = '$prefix$passage';
          }
        }
        return (chunks: staged, texts: inputs, split: segmentSplit);
      }

      var result = await attempt(includeContext);
      if (result == null && includeContext) {
        result = await attempt(false, restart: true);
        if (result != null) record('embedding_context_omitted');
      }
      if (result == null) {
        throw StateError(
          'Cannot fit body-only input within $maxTokens tokens: ${first.sourcePath}',
        );
      }
      if (result.split) record('oversized_segment_split');
      output.addAll(result.chunks);
      texts.addAll(result.texts);
    }
    return KnowledgeSnapshot._(
      bundleId,
      List.unmodifiable(output),
      graph,
      _metadata,
      Map.unmodifiable(texts),
      sources,
      assets,
      List.unmodifiable(recoveries.values),
    );
  }
}

class _InputRecovery {
  const _InputRecovery(
    this.originalId,
    this.code,
    this.sourcePath,
    this.lineStart,
    this.lineEnd,
  );
  final String originalId;
  final String code;
  final String sourcePath;
  final int lineStart;
  final int lineEnd;

  factory _InputRecovery.fromMap(Map<String, Object?> map) => _InputRecovery(
    map['originalId']! as String,
    map['code']! as String,
    map['sourcePath']! as String,
    map['lineStart']! as int,
    map['lineEnd']! as int,
  );
  Map<String, Object?> toMap() => {
    'originalId': originalId,
    'code': code,
    'sourcePath': sourcePath,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
  };
}

List<KnowledgeInputDiagnostic> _aggregate(List<_InputRecovery> recoveries) {
  final groups = <(String, String), Map<String, _InputRecovery>>{};
  for (final r in recoveries) {
    groups.putIfAbsent((r.sourcePath, r.code), () => {})[r.originalId] = r;
  }
  final diagnostics = <KnowledgeInputDiagnostic>[];
  for (final entry in groups.entries) {
    final values = entry.value.values;
    diagnostics.add(
      KnowledgeInputDiagnostic(
        code: entry.key.$2,
        sourcePath: entry.key.$1,
        lineStart: values
            .map((r) => r.lineStart)
            .reduce((a, b) => a < b ? a : b),
        lineEnd: values.map((r) => r.lineEnd).reduce((a, b) => a > b ? a : b),
        affectedChunks: values.length,
      ),
    );
  }
  diagnostics.sort((a, b) {
    final path = a.sourcePath.compareTo(b.sourcePath);
    return path != 0 ? path : a.code.compareTo(b.code);
  });
  return List.unmodifiable(diagnostics);
}
