import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/src/model/knowledge.dart';

KnowledgeFinding _finding(
  KnowledgeFindingSeverity severity, [
  String id = 'r',
]) => KnowledgeFinding(id: id, severity: severity, message: 'message');

void main() {
  test('advisories and notes are suggestions', () {
    expect(
      {
        for (final s in KnowledgeFindingSeverity.values)
          s: knowledgeSeverityOf(s),
      },
      {
        KnowledgeFindingSeverity.error: KnowledgeSeverity.error,
        KnowledgeFindingSeverity.warning: KnowledgeSeverity.warning,
        KnowledgeFindingSeverity.advisory: KnowledgeSeverity.suggestion,
        KnowledgeFindingSeverity.note: KnowledgeSeverity.suggestion,
      },
    );
    expect(KnowledgeSeverity.suggestion.needsAttention, isFalse);
    expect(KnowledgeSeverity.warning.needsAttention, isTrue);
    expect(KnowledgeSeverity.warning.count(1), '1 warning');
    expect(KnowledgeSeverity.suggestion.count(3), '3 suggestions');
  });

  test('health counts only errors and warnings as needing attention', () {
    final calm = KnowledgeHealth.of([
      for (var i = 0; i < 219; i++) _finding(KnowledgeFindingSeverity.advisory),
      _finding(KnowledgeFindingSeverity.note),
    ]);
    expect(calm.isHealthy, isTrue);
    expect(calm.worst, isNull);
    expect(calm.attentionLabel, isEmpty);
    expect(calm.summaryLabel, '220 suggestions');

    final mixed = KnowledgeHealth.of([
      _finding(KnowledgeFindingSeverity.warning),
      _finding(KnowledgeFindingSeverity.error),
      _finding(KnowledgeFindingSeverity.warning),
      _finding(KnowledgeFindingSeverity.advisory),
    ]);
    expect(mixed.isHealthy, isFalse);
    expect(mixed.worst, KnowledgeSeverity.error);
    expect(mixed.attentionLabel, '1 error · 2 warnings');
    expect(mixed.summaryLabel, '1 error · 2 warnings · 1 suggestion');
    expect(const KnowledgeHealth().summaryLabel, isEmpty);
  });

  test('findings sort errors first and keep their order within a level', () {
    final sorted = sortedBySeverity([
      _finding(KnowledgeFindingSeverity.note, 'n'),
      _finding(KnowledgeFindingSeverity.warning, 'w1'),
      _finding(KnowledgeFindingSeverity.error, 'e'),
      _finding(KnowledgeFindingSeverity.warning, 'w2'),
    ]);
    expect(sorted.map((f) => f.id), ['e', 'w1', 'w2', 'n']);
  });
}
