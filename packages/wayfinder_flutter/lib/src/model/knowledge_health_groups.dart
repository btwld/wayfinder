// Portable: how the Health view groups a bundle's findings, by rule or by
// document, most severe first.
import 'package:flutter/foundation.dart' show immutable;

import 'knowledge_models.dart';
import 'knowledge_severity.dart';
import 'knowledge_words.dart';

/// How the Health view groups findings.
enum KnowledgeHealthGrouping {
  rule('By rule'),
  document('By document');

  const KnowledgeHealthGrouping(this.label);
  final String label;
}

/// Findings that share a rule or a document.
@immutable
final class KnowledgeHealthGroup {
  const KnowledgeHealthGroup({
    required this.key,
    required this.severity,
    required this.findings,
  });

  /// The rule id, or the document path (empty for findings with none).
  final String key;

  /// The most severe level among [findings].
  final KnowledgeSeverity severity;
  final List<KnowledgeFinding> findings;

  /// How many documents the findings name.
  int get documentCount =>
      {for (final finding in findings) finding.path ?? ''}.length;

  /// The message every finding shares, or null when they differ.
  String? get sharedMessage {
    final first = findings.firstOrNull?.message;
    return findings.every((finding) => finding.message == first) ? first : null;
  }
}

/// [findings] whose level is in [levels], grouped by [grouping]: the most
/// severe groups first, then the largest, then by key. Within a group,
/// findings keep their order, the most severe first.
List<KnowledgeHealthGroup> groupKnowledgeFindings(
  Iterable<KnowledgeFinding> findings, {
  required KnowledgeHealthGrouping grouping,
  Set<KnowledgeSeverity> levels = const {
    KnowledgeSeverity.error,
    KnowledgeSeverity.warning,
    KnowledgeSeverity.suggestion,
  },
}) {
  final groups = <String, List<KnowledgeFinding>>{};
  for (final finding in findings) {
    if (!levels.contains(finding.level)) continue;
    final key = switch (grouping) {
      KnowledgeHealthGrouping.rule => finding.id,
      KnowledgeHealthGrouping.document => finding.path ?? '',
    };
    groups.putIfAbsent(key, () => []).add(finding);
  }
  final result = [
    for (final MapEntry(:key, :value) in groups.entries)
      KnowledgeHealthGroup(
        key: key,
        severity: value
            .map((finding) => finding.level)
            .reduce((a, b) => a.index <= b.index ? a : b),
        findings: sortedBySeverity(value),
      ),
  ];
  result.sort((a, b) {
    final bySeverity = a.severity.index.compareTo(b.severity.index);
    if (bySeverity != 0) return bySeverity;
    final bySize = b.findings.length.compareTo(a.findings.length);
    return bySize != 0 ? bySize : a.key.compareTo(b.key);
  });
  return result;
}

/// A rule id in words: its last segment, de-hyphenated and capitalised,
/// such as `Internal link bundle relative`.
String knowledgeRuleName(String ruleId) {
  final tail = ruleId
      .split(RegExp('[/:.]'))
      .lastWhere((segment) => segment.isNotEmpty, orElse: () => ruleId);
  final words = knowledgeHumanize(tail);
  return words.isEmpty ? ruleId : words;
}
