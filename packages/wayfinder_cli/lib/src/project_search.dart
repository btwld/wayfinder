import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

import 'project_bundles.dart';

typedef ProjectMatch = ({ProjectBundle bundle, SearchResult hit});
typedef ProjectContext = ({ProjectBundle bundle, KnowledgeContextHit hit});

/// Ranks across bundles without conflating equal source paths in different roots.
class ProjectSearchResult {
  ProjectSearchResult(
    this.bundles,
    List<KnowledgeSearchResponse> results, {
    required int limit,
  }) {
    final candidates =
        <ProjectMatch>[
          for (var i = 0; i < bundles.length; i++)
            for (final hit in results[i].matches)
              (bundle: bundles[i], hit: hit),
        ]..sort((a, b) {
          final score = b.hit.similarity.compareTo(a.hit.similarity);
          if (score != 0) return score;
          final bundle = a.bundle.path.compareTo(b.bundle.path);
          if (bundle != 0) return bundle;
          final path = a.hit.chunk.sourcePath.compareTo(b.hit.chunk.sourcePath);
          return path != 0 ? path : a.hit.chunk.id.compareTo(b.hit.chunk.id);
        });
    matches.addAll(candidates.take(limit));
    final seen = <(String, String)>{};
    void add(ProjectBundle bundle, KnowledgeContextHit hit) {
      if (context.length < limit &&
          seen.add((bundle.root, hit.result.chunk.sourcePath))) {
        context.add((bundle: bundle, hit: hit));
      }
    }

    for (final match in matches) {
      add(match.bundle, KnowledgeContextHit(match.hit, 'match'));
      final result = results[bundles.indexOf(match.bundle)];
      for (final related in result.context.where(
        (hit) =>
            hit.reason == 'relationship' &&
            hit.viaPath == match.hit.chunk.sourcePath,
      )) {
        add(match.bundle, related);
      }
    }
    for (var i = 0; i < bundles.length; i++) {
      notices.addAll(results[i].notices.map((n) => '${bundles[i].name}: $n'));
    }
  }

  final List<ProjectBundle> bundles;
  final matches = <ProjectMatch>[];
  final context = <ProjectContext>[];
  final notices = <String>[];

  Map<String, Object?> toJson() => {
    'bundles': bundles.map((bundle) => bundle.toJson()).toList(),
    'matches': [
      for (final match in matches)
        {
          'bundle': match.bundle.name,
          'bundlePath': match.bundle.path,
          'chunk': match.hit.chunk.toMap(),
          'similarity': match.hit.similarity,
        },
    ],
    'context': [
      for (final entry in context)
        {
          'bundle': entry.bundle.name,
          'bundlePath': entry.bundle.path,
          'chunk': entry.hit.result.chunk.toMap(),
          'similarity': entry.hit.result.similarity,
          'reason': entry.hit.reason,
          if (entry.hit.viaPath != null) 'viaPath': entry.hit.viaPath,
        },
    ],
    'notices': notices,
  };
}
