import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

void main() {
  KnowledgeFileEntry concept({
    String? title = 'Payment terms',
    String type = 'Guide',
    int errors = 0,
    int warnings = 0,
  }) => KnowledgeFileEntry(
    path: 'knowledge/finance/payment-terms.md',
    kind: KnowledgeFileKind.concept,
    title: title,
    type: type,
    errorCount: errors,
    warningCount: warnings,
  );

  test('a concept reads by its title, then by its file name', () {
    expect(concept().label, 'Payment terms');
    expect(concept(title: '  ').label, 'payment-terms.md');
    expect(concept(title: null).label, 'payment-terms.md');
    expect(concept().fileName, 'payment-terms.md');
  });

  test('other files read by their file name, whatever their title', () {
    const index = KnowledgeFileEntry(
      path: 'knowledge/index.md',
      kind: KnowledgeFileKind.indexFile,
      title: 'Ignored',
    );
    expect(index.label, 'index.md');
    expect(index.isConcept, isFalse);
  });

  test('an attachment is any file that is not Markdown', () {
    expect(concept().isAttachment, isFalse);
    expect(
      const KnowledgeFileEntry(
        path: 'knowledge/NOTES.MD',
        kind: KnowledgeFileKind.reference,
      ).isAttachment,
      isFalse,
    );
    expect(
      const KnowledgeFileEntry(
        path: 'knowledge/logo.png',
        kind: KnowledgeFileKind.reference,
      ).isAttachment,
      isTrue,
    );
  });

  test('attention is the most severe finding that needs it', () {
    expect(concept().attention, isNull);
    expect(concept(warnings: 2).attention, KnowledgeSeverity.warning);
    expect(concept(errors: 1, warnings: 2).attention, KnowledgeSeverity.error);
  });

  test('roleLabel names the concept type, else the role', () {
    expect(concept().roleLabel, 'Guide');
    expect(concept(type: '').roleLabel, 'Concept');
    String role(String path, KnowledgeFileKind kind) =>
        KnowledgeFileEntry(path: path, kind: kind).roleLabel;
    expect(role('a/index.md', KnowledgeFileKind.indexFile), 'Index');
    expect(role('a/log.md', KnowledgeFileKind.log), 'Log');
    expect(role('wayfinder.json', KnowledgeFileKind.config), 'Configuration');
    expect(role('a/b.png', KnowledgeFileKind.reference), 'Attachment');
    expect(role('a/b.md', KnowledgeFileKind.reference), 'Markdown file');
  });

  test('entries are equal by value, tags included', () {
    const a = KnowledgeFileEntry(
      path: 'a.md',
      kind: KnowledgeFileKind.concept,
      tags: ['x', 'y'],
    );
    final same = KnowledgeFileEntry(
      path: 'a.md',
      kind: KnowledgeFileKind.concept,
      tags: List.of(const ['x', 'y']),
    );
    const other = KnowledgeFileEntry(
      path: 'a.md',
      kind: KnowledgeFileKind.concept,
      tags: ['x'],
    );
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(other));
  });
}
