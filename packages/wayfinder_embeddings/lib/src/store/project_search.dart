import 'package:okf/okf.dart' show OkfConceptId;
import 'package:wayfinder/project.dart' show ProjectBundle;

import '../models/chunk.dart';
import '../models/search_result.dart';
import '../okf/knowledge_index.dart';
import 'search_output.dart';

/// One cited passage of a search: a match, or context reached from one.
///
/// [sourcePath] is relative to [bundle]'s root, and [lineStart] to
/// [lineEnd] are lines of that file as it was indexed. Retrieved text is
/// source data, not instructions, and a high [similarity] is no evidence that
/// the passage answers the query.
final class KnowledgeCitation {
  KnowledgeCitation._({
    required this.bundle,
    required this.chunk,
    required this.similarity,
    required this.reason,
    this.viaPath,
    this.relationship,
  });

  factory KnowledgeCitation._of(
    ProjectBundle bundle,
    SearchResult result, {
    required String reason,
    String? viaPath,
    String? relationship,
  }) => KnowledgeCitation._(
    bundle: bundle,
    chunk: result.chunk,
    similarity: result.similarity,
    reason: reason,
    viaPath: viaPath,
    relationship: relationship,
  );

  factory KnowledgeCitation._context(
    ProjectBundle bundle,
    KnowledgeContextHit hit,
  ) => KnowledgeCitation._of(
    bundle,
    hit.result,
    reason: hit.reason,
    viaPath: hit.viaPath,
    relationship: hit.fieldEdge?.name,
  );

  /// The bundle the passage belongs to.
  final ProjectBundle bundle;

  /// The indexed passage, with its metadata.
  final Chunk chunk;

  /// The query's similarity to the passage.
  final double similarity;

  /// Why the passage is included: `match` for a ranked match, otherwise the
  /// policy that selected it, such as `relationship`.
  final String reason;

  /// The source path of the passage this context was reached from.
  final String? viaPath;

  /// The typed `relationships` entry this context was reached through, such
  /// as `depends-on`; null for an untyped body link.
  final String? relationship;

  String get sourcePath => chunk.sourcePath;
  int get lineStart => chunk.lineStart;
  int get lineEnd => chunk.lineEnd;
  String get content => chunk.content;

  /// The OKF concept ID, [sourcePath] without `.md`; null for a file that is
  /// not a concept.
  String? get conceptId {
    try {
      return OkfConceptId.fromDocumentPath(sourcePath).value;
    } on FormatException {
      return null;
    }
  }

  Map<Object?, Object?>? get _frontmatter =>
      ((chunk.metadata['okf'] as Map?)?['frontmatter']) as Map?;

  String? _field(String name) => switch (_frontmatter?[name]) {
    final String value when value.trim().isNotEmpty => value,
    _ => null,
  };

  /// The concept's frontmatter `title`.
  String? get title => _field('title');

  /// The concept's frontmatter `type`.
  String? get type => _field('type');

  /// The concept's frontmatter `status`; null when absent, which OKF reads
  /// as `stable`.
  String? get status => _field('status');
}

/// A search across a project's bundles, ranked together under one limit.
///
/// Equal source paths in different bundles stay separate citations. Ties in
/// similarity break by bundle path, then source path, then chunk ID; chunk
/// IDs do not depend on where a bundle is checked out, so copies of one
/// bundle rank alike.
final class KnowledgeProjectSearch {
  /// Ranks the per-bundle [responses], one for each of [bundles] in order,
  /// keeping the best [limit] matches and at most [limit] context passages:
  /// each match, followed by the relationship context reached from it.
  KnowledgeProjectSearch(
    List<ProjectBundle> bundles,
    List<KnowledgeSearchResponse> responses, {
    required int limit,
  }) : bundles = List.unmodifiable(bundles),
       responses = List.unmodifiable(responses) {
    if (bundles.length != responses.length) {
      throw ArgumentError('Supply one response per bundle.');
    }
    final candidates =
        <({ProjectBundle bundle, SearchResult hit})>[
          for (final (i, bundle) in bundles.indexed)
            for (final hit in responses[i].matches) (bundle: bundle, hit: hit),
        ]..sort((a, b) {
          final score = b.hit.similarity.compareTo(a.hit.similarity);
          if (score != 0) return score;
          final bundle = a.bundle.path.compareTo(b.bundle.path);
          if (bundle != 0) return bundle;
          final path = a.hit.chunk.sourcePath.compareTo(b.hit.chunk.sourcePath);
          return path != 0 ? path : a.hit.chunk.id.compareTo(b.hit.chunk.id);
        });
    final ranked = candidates.take(limit).toList();
    final context = <KnowledgeCitation>[];
    final seen = <(String, String)>{};
    void add(KnowledgeCitation citation) {
      if (context.length < limit &&
          seen.add((citation.bundle.root, citation.sourcePath))) {
        context.add(citation);
      }
    }

    for (final match in ranked) {
      add(KnowledgeCitation._of(match.bundle, match.hit, reason: 'match'));
      final response = responses[bundles.indexOf(match.bundle)];
      for (final related in response.context.where(
        (hit) =>
            hit.reason == 'relationship' &&
            hit.viaPath == match.hit.chunk.sourcePath,
      )) {
        add(KnowledgeCitation._context(match.bundle, related));
      }
    }
    matches = List.unmodifiable([
      for (final match in ranked)
        KnowledgeCitation._of(match.bundle, match.hit, reason: 'match'),
    ]);
    this.context = List.unmodifiable(context);
    notices = List.unmodifiable([
      for (final (i, bundle) in bundles.indexed)
        for (final notice in responses[i].notices) '${bundle.name}: $notice',
    ]);
  }

  /// The bundles searched, in order.
  final List<ProjectBundle> bundles;

  /// Each bundle's own response, which the result was ranked from.
  final List<KnowledgeSearchResponse> responses;

  /// The best matches across all bundles, best first.
  late final List<KnowledgeCitation> matches;

  /// The matches and the relationship context reached from each, in that
  /// order, within the limit.
  late final List<KnowledgeCitation> context;

  /// Each bundle's notices, prefixed with its name.
  late final List<String> notices;

  /// The JSON of `wayfinder search --output=json` in project mode.
  Map<String, Object?> toJson() => {
    'bundles': [for (final bundle in bundles) bundle.toJson()],
    'matches': [
      for (final match in matches)
        {
          'bundle': match.bundle.name,
          'bundlePath': match.bundle.path,
          'chunk': match.chunk.toMap(),
          'similarity': match.similarity,
        },
    ],
    'context': [
      for (final entry in context)
        {
          'bundle': entry.bundle.name,
          'bundlePath': entry.bundle.path,
          'chunk': entry.chunk.toMap(),
          'similarity': entry.similarity,
          'reason': entry.reason,
          'viaPath': ?entry.viaPath,
        },
    ],
    'notices': notices,
  };

  /// `## Matches` and `## Related Context` with citations of the form
  /// `bundle-path/source-path:lines`, then the notices: the text of
  /// `wayfinder search` and the MCP `search` tool. Control characters are
  /// escaped.
  String toMarkdown() => renderSearchMarkdown(
    matches: [for (final match in matches) _passage(match)],
    context: [for (final entry in context) _passage(entry)],
    notices: notices,
  );

  static MarkdownPassage _passage(KnowledgeCitation citation) => (
    prefix: '${citation.bundle.path}/',
    bundle: citation.bundle.name,
    bundleRoot: citation.bundle.root,
    chunk: citation.chunk,
    reason: citation.reason,
    relationship: citation.relationship,
    viaPath: citation.viaPath,
  );
}

/// A search of one bundle, with its context unranked against other bundles.
final class KnowledgeBundleSearch {
  KnowledgeBundleSearch(this.bundle, this.response)
    : matches = List.unmodifiable([
        for (final hit in response.matches)
          KnowledgeCitation._of(bundle, hit, reason: 'match'),
      ]),
      context = List.unmodifiable([
        for (final hit in response.context)
          KnowledgeCitation._context(bundle, hit),
      ]);

  /// The bundle searched.
  final ProjectBundle bundle;

  /// The underlying response, with the graph edges each context passage was
  /// reached through.
  final KnowledgeSearchResponse response;

  /// Query-ranked matches, one best passage per concept.
  final List<KnowledgeCitation> matches;

  /// The context policy selected, matches included.
  final List<KnowledgeCitation> context;

  /// Unresolved links and excluded context.
  List<String> get notices => response.notices;

  /// The JSON of `wayfinder search <bundle> --output=json`.
  Map<String, Object?> toJson() => {
    'context': [
      for (final entry in context)
        {
          'chunk': entry.chunk.toMap(),
          'similarity': entry.similarity,
          'reason': entry.reason,
          'viaPath': ?entry.viaPath,
          'relationship': ?entry.relationship,
        },
    ],
    'matches': [
      for (final match in matches)
        {'chunk': match.chunk.toMap(), 'similarity': match.similarity},
    ],
    'notices': notices,
  };

  /// `## Matches` and `## Related Context` with citations of the form
  /// `prefix` + `source-path:lines`, then the notices. [prefix] is how the
  /// reader reaches the bundle, such as `knowledge/`. Control characters are
  /// escaped.
  String toMarkdown({String prefix = ''}) {
    MarkdownPassage passage(KnowledgeCitation citation) => (
      prefix: prefix,
      bundle: null,
      bundleRoot: bundle.root,
      chunk: citation.chunk,
      reason: citation.reason,
      relationship: citation.relationship,
      viaPath: citation.viaPath,
    );
    return renderSearchMarkdown(
      matches: [for (final match in matches) passage(match)],
      context: [for (final entry in context) passage(entry)],
      notices: notices,
    );
  }
}
