import 'package:flutter/foundation.dart' show immutable;
import 'package:wayfinder/knowledge.dart';

export 'package:wayfinder/knowledge.dart';

/// A bundle's validation verdict, as `wayfinder validate` derives it.
enum KnowledgeGate {
  pass('PASS'),
  fail('FAIL'),
  incomplete('INCOMPLETE');

  const KnowledgeGate(this.wireValue);
  final String wireValue;
}

enum KnowledgeFindingSeverity { error, warning, advisory, note }

/// Which check reported a finding: okf, the Profile's rules, or Wayfinder
/// itself (a Profile it could not resolve, for example).
enum KnowledgeFindingSource { okf, profile, engine }

/// The bundle a project reads first: exact path `knowledge`, then a bundle
/// named `knowledge`, else the most concepts (first by path among equals).
/// Returns null when there is none.
KnowledgeBundleSummary? preferredKnowledgeBundle(
  Iterable<KnowledgeBundleSummary> bundles,
) {
  KnowledgeBundleSummary? preferred;
  KnowledgeBundleSummary? namedKnowledge;
  for (final bundle in bundles) {
    if (bundle.path == 'knowledge') return bundle;
    if (bundle.name == 'knowledge') namedKnowledge ??= bundle;
    if (preferred == null ||
        bundle.conceptCount > preferred.conceptCount ||
        (bundle.conceptCount == preferred.conceptCount &&
            bundle.path.compareTo(preferred.path) < 0)) {
      preferred = bundle;
    }
  }
  return namedKnowledge ?? preferred;
}

@immutable
final class KnowledgeFinding {
  const KnowledgeFinding({
    required this.id,
    required this.severity,
    required this.message,
    this.path,
    this.line,
    required this.source,
  });

  /// The rule or check id, such as an okf code or a Profile rule.
  final String id;
  final KnowledgeFindingSeverity severity;
  final String message;

  /// The file relative to the project root, when the finding names one.
  final String? path;
  final int? line;
  final KnowledgeFindingSource source;
}

/// How `wayfinder validate` judges a bundle: its gate, the Profile it
/// used, and every finding.
@immutable
final class KnowledgeBundleValidation {
  const KnowledgeBundleValidation({
    required this.gate,
    this.profileId,
    this.findings = const [],
  });

  final KnowledgeGate gate;

  /// The Profile's id, when one judged the bundle.
  final String? profileId;
  final List<KnowledgeFinding> findings;
}
