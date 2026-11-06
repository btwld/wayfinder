// Portable: how a reader names and ranks finding severities. Errors and
// warnings ask for attention; advisories and notes are suggestions, which
// never colour anything.
import 'package:flutter/foundation.dart' show immutable;

import 'knowledge_models.dart';
import 'knowledge_words.dart';

/// The severity a reader sees: Error, Warning or Suggestion.
enum KnowledgeSeverity {
  error('Error', 'errors'),
  warning('Warning', 'warnings'),
  suggestion('Suggestion', 'suggestions');

  const KnowledgeSeverity(this.label, this.plural);

  /// The singular name, such as `Warning`.
  final String label;

  /// The lower-case plural, such as `warnings`.
  final String plural;

  /// Whether this severity asks for attention: errors and warnings do,
  /// suggestions never do.
  bool get needsAttention => this != KnowledgeSeverity.suggestion;

  /// `1 warning`, `2 warnings`.
  String count(int n) => knowledgeCount(n, label.toLowerCase(), plural);
}

/// The reader-facing severity of a validation severity: advisories and
/// notes are suggestions.
KnowledgeSeverity knowledgeSeverityOf(KnowledgeFindingSeverity severity) =>
    switch (severity) {
      KnowledgeFindingSeverity.error => KnowledgeSeverity.error,
      KnowledgeFindingSeverity.warning => KnowledgeSeverity.warning,
      KnowledgeFindingSeverity.advisory ||
      KnowledgeFindingSeverity.note => KnowledgeSeverity.suggestion,
    };

/// The reader-facing severity of [KnowledgeFinding.severity].
extension KnowledgeFindingLevel on KnowledgeFinding {
  KnowledgeSeverity get level => knowledgeSeverityOf(severity);
}

/// [findings] errors first, then warnings, then suggestions, each kept in
/// its original order.
List<KnowledgeFinding> sortedBySeverity(Iterable<KnowledgeFinding> findings) {
  final list = findings.toList();
  final order = {for (final (i, f) in list.indexed) f: i};
  return list..sort((a, b) {
    final bySeverity = a.level.index.compareTo(b.level.index);
    return bySeverity != 0 ? bySeverity : order[a]!.compareTo(order[b]!);
  });
}

/// Counts of findings by reader-facing severity, with the words the header,
/// status bar and reader use for them.
@immutable
final class KnowledgeHealth {
  const KnowledgeHealth({
    this.errors = 0,
    this.warnings = 0,
    this.suggestions = 0,
  });

  factory KnowledgeHealth.of(Iterable<KnowledgeFinding> findings) {
    var errors = 0, warnings = 0, suggestions = 0;
    for (final finding in findings) {
      switch (finding.level) {
        case KnowledgeSeverity.error:
          errors++;
        case KnowledgeSeverity.warning:
          warnings++;
        case KnowledgeSeverity.suggestion:
          suggestions++;
      }
    }
    return KnowledgeHealth(
      errors: errors,
      warnings: warnings,
      suggestions: suggestions,
    );
  }

  final int errors;
  final int warnings;
  final int suggestions;

  /// Whether there is nothing that needs attention; suggestions may remain.
  bool get isHealthy => errors == 0 && warnings == 0;

  /// The most severe level that needs attention, or null when healthy.
  KnowledgeSeverity? get worst => errors > 0
      ? KnowledgeSeverity.error
      : warnings > 0
      ? KnowledgeSeverity.warning
      : null;

  /// Errors and warnings only, such as `1 error · 2 warnings`; empty when
  /// healthy.
  String get attentionLabel => [
    if (errors > 0) KnowledgeSeverity.error.count(errors),
    if (warnings > 0) KnowledgeSeverity.warning.count(warnings),
  ].join(' · ');

  /// `1 warning · 2 suggestions`; empty when there are no findings.
  String get summaryLabel => [
    if (attentionLabel.isNotEmpty) attentionLabel,
    if (suggestions > 0) KnowledgeSeverity.suggestion.count(suggestions),
  ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is KnowledgeHealth &&
      other.errors == errors &&
      other.warnings == warnings &&
      other.suggestions == suggestions;

  @override
  int get hashCode => Object.hash(errors, warnings, suggestions);
}
