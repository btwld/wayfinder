import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;

import '../../knowledge_embeddings.dart';
import '../models/metadata_collections.dart';

/// A parsed bundle projection with original citation locations and graph edges.
/// Indexes and logs remain navigation/history, rather than duplicate passages.
class KnowledgeSnapshot {
  KnowledgeSnapshot._(
    this.bundleId,
    this.chunks,
    this.graph,
    this._metadata,
    this._contextTexts,
  );

  final String bundleId;
  final List<Chunk> chunks;
  final OkfGraph graph;
  final Map<String, OkfMetadata> _metadata;
  final Map<String, String> _contextTexts;

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
      final onlyHeadings = bodyChunks.every((chunk) => chunk.type == 'heading');
      for (final raw in bodyChunks) {
        if (raw.type == 'heading') {
          final level = raw.metadata['headingLevel']! as int;
          headings.removeWhere((heading) => heading.level >= level);
          headings.add((level: level, text: raw.content));
          if (!onlyHeadings) continue;
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
    );
  }

  Set<String> get conceptPaths => Set.unmodifiable(_metadata.keys);

  /// Typed OKF metadata, with its upstream defaults and trust semantics.
  OkfMetadata metadataFor(String path) =>
      _metadata[path] ??
      (throw ArgumentError.value(path, 'path', 'Unknown concept'));

  /// Retrieval input; the original source passage is never overwritten.
  String textFor(Chunk chunk, {required bool includeContext}) =>
      includeContext ? _contextTexts[chunk.id]! : chunk.content;

  /// Splits oversized passages at whitespace using the actual tokenizer.
  /// Preserves text, character spans, and citation lines. Context counts against
  /// the budget; if context plus one word cannot fit, throws without truncation.
  Future<KnowledgeSnapshot> fitInputs({
    required Future<int> Function(String) countTokens,
    required int maxTokens,
    required bool includeContext,
  }) async {
    if (maxTokens <= 0) throw ArgumentError.value(maxTokens, 'maxTokens');
    final output = <Chunk>[];
    final texts = <String, String>{};
    for (final chunk in chunks) {
      final full = textFor(chunk, includeContext: includeContext);
      final contextual = _contextTexts[chunk.id]!;
      final prefix = contextual.substring(
        0,
        contextual.length - chunk.content.length,
      );
      if (await countTokens(full) <= maxTokens) {
        output.add(chunk);
        texts[chunk.id] = contextual;
        continue;
      }
      final ends = RegExp(
        r'\S+\s*',
      ).allMatches(chunk.content).map((match) => match.end).toList();
      var start = 0;
      var first = 0;
      while (start < chunk.content.length) {
        var low = first;
        var high = ends.length - 1;
        int? chosen;
        while (low <= high) {
          final mid = (low + high) ~/ 2;
          final passage = chunk.content.substring(start, ends[mid]);
          final input = includeContext ? '$prefix$passage' : passage;
          if (await countTokens(input) <= maxTokens) {
            chosen = mid;
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        if (chosen == null) {
          throw StateError(
            'Cannot fit context and one word within $maxTokens tokens: ${chunk.sourcePath}',
          );
        }
        final end = ends[chosen];
        final passage = chunk.content.substring(start, end);
        final lineStart =
            chunk.lineStart +
            '\n'.allMatches(chunk.content.substring(0, start)).length;
        final id = sha256
            .convert(utf8.encode(jsonEncode([chunk.id, start, end])))
            .toString();
        final split = chunk.copyWith(
          id: id,
          content: passage,
          lineStart: lineStart,
          lineEnd: lineStart + '\n'.allMatches(passage.trimRight()).length,
          metadata: {
            'okf': {
              ...chunk.metadata['okf']! as Map<String, Object?>,
              'parentChunkId': chunk.id,
              'characterStart': start,
              'characterEnd': end,
            },
          },
        );
        output.add(split);
        texts[id] = '$prefix$passage';
        start = end;
        first = chosen + 1;
      }
    }
    return KnowledgeSnapshot._(
      bundleId,
      List.unmodifiable(output),
      graph,
      _metadata,
      Map.unmodifiable(texts),
    );
  }
}
