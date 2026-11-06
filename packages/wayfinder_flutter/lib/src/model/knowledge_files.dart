import 'package:flutter/foundation.dart' show listEquals;

import 'knowledge_severity.dart';

/// Kind of file inside a workspace's knowledge bundle or root configuration.
enum KnowledgeFileKind { concept, indexFile, log, config, reference }

/// One file in a workspace's knowledge bundle or root configuration.
final class KnowledgeFileEntry {
  const KnowledgeFileEntry({
    required this.path,
    required this.kind,
    this.bundle,
    this.conceptId,
    this.title,
    this.type = '',
    this.errorCount = 0,
    this.warningCount = 0,
    this.tags = const [],
  });

  final String path;
  final KnowledgeFileKind kind;
  final String? bundle;
  final String? conceptId;
  final String? title;
  final String type;

  /// This file's validation errors.
  final int errorCount;

  /// This file's validation warnings. Suggestions are not counted per file.
  final int warningCount;
  final List<String> tags;

  bool get isConcept => kind == KnowledgeFileKind.concept;

  /// Whether this is an attachment: any file that is not Markdown.
  bool get isAttachment => !path.toLowerCase().endsWith('.md');

  /// The file's name, such as `payment-terms.md`.
  String get fileName => path.substring(path.lastIndexOf('/') + 1);

  /// What the tree and reader call this file: a concept's title, else its
  /// file name.
  String get label =>
      isConcept && (title?.trim().isNotEmpty ?? false) ? title! : fileName;

  /// The most severe finding that needs attention, or null.
  KnowledgeSeverity? get attention => errorCount > 0
      ? KnowledgeSeverity.error
      : warningCount > 0
      ? KnowledgeSeverity.warning
      : null;

  /// What kind of file this is, in a word: the concept type, else the role.
  String get roleLabel {
    if (isConcept && type.isNotEmpty) return type;
    return switch (kind) {
      KnowledgeFileKind.concept => 'Concept',
      KnowledgeFileKind.indexFile => 'Index',
      KnowledgeFileKind.log => 'Log',
      KnowledgeFileKind.config => 'Configuration',
      KnowledgeFileKind.reference =>
        isAttachment ? 'Attachment' : 'Markdown file',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is KnowledgeFileEntry &&
      path == other.path &&
      kind == other.kind &&
      bundle == other.bundle &&
      conceptId == other.conceptId &&
      title == other.title &&
      type == other.type &&
      errorCount == other.errorCount &&
      warningCount == other.warningCount &&
      listEquals(tags, other.tags);

  @override
  int get hashCode => Object.hash(
    path,
    kind,
    bundle,
    conceptId,
    title,
    type,
    errorCount,
    warningCount,
    Object.hashAll(tags),
  );
}

/// How the tree arranges each bundle: its folders on disk, or its concepts
/// grouped by type.
enum KnowledgeTreeGrouping {
  folders('Folders'),
  types('Types');

  const KnowledgeTreeGrouping(this.label);
  final String label;
}
