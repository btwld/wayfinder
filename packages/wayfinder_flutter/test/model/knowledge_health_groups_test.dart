import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

KnowledgeFinding _finding(
  String id,
  KnowledgeFindingSeverity severity, {
  String? path,
  String message = 'Message',
}) =>
    KnowledgeFinding(id: id, severity: severity, message: message, path: path);

void main() {
  final warningX = _finding('a', KnowledgeFindingSeverity.warning, path: 'x');
  final warningY = _finding('a', KnowledgeFindingSeverity.warning, path: 'y');
  final errorX = _finding(
    'b',
    KnowledgeFindingSeverity.error,
    path: 'x',
    message: 'Other',
  );
  final note = _finding('c', KnowledgeFindingSeverity.note);
  final findings = [warningX, warningY, note, errorX];

  test('by rule: the most severe group first', () {
    final groups = groupKnowledgeFindings(
      findings,
      grouping: KnowledgeHealthGrouping.rule,
    );
    expect([for (final group in groups) group.key], ['b', 'a', 'c']);
    expect(groups[0].severity, KnowledgeSeverity.error);
    expect(groups[2].severity, KnowledgeSeverity.suggestion);
    expect(groups[1].documentCount, 2);
    expect(groups[1].sharedMessage, 'Message');
  });

  test('by document: the worst finding first inside each group', () {
    final groups = groupKnowledgeFindings(
      findings,
      grouping: KnowledgeHealthGrouping.document,
    );
    expect([for (final group in groups) group.key], ['x', 'y', '']);
    expect(groups[0].severity, KnowledgeSeverity.error);
    expect(groups[0].findings, [errorX, warningX]);
    expect(groups[0].sharedMessage, isNull);
  });

  test('a larger group comes first among equally severe ones', () {
    final groups = groupKnowledgeFindings([
      _finding('small', KnowledgeFindingSeverity.warning),
      _finding('large', KnowledgeFindingSeverity.warning),
      _finding('large', KnowledgeFindingSeverity.warning),
    ], grouping: KnowledgeHealthGrouping.rule);
    expect([for (final group in groups) group.key], ['large', 'small']);
  });

  test('levels leave out the other findings', () {
    final groups = groupKnowledgeFindings(
      findings,
      grouping: KnowledgeHealthGrouping.rule,
      levels: const {KnowledgeSeverity.suggestion},
    );
    expect([for (final group in groups) group.key], ['c']);
  });

  test('knowledgeRuleName reads the last segment of a rule id', () {
    expect(knowledgeRuleName('okf/non-portable-name'), 'Non portable name');
    expect(knowledgeRuleName('wayfinder:config.missing'), 'Missing');
    expect(knowledgeRuleName('plain_rule'), 'Plain rule');
  });
}
