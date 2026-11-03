import '../model/knowledge_severity.dart';
import '../model/knowledge_words.dart';

/// The words a `KnowledgeGraphCanvas` shows and announces, in English.
///
/// Extend it and override what changes to translate them.
class KnowledgeGraphLabels {
  /// The English words.
  const KnowledgeGraphLabels();

  /// A node for a concept that has no type.
  String get concept => 'Concept';

  /// A node for a file that is no concept.
  String get attachment => 'Attachment';

  /// A node for a link out of the bundle.
  String get external => 'External';

  /// A node for a link that leads nowhere.
  String get unresolved => 'Unresolved';

  /// [target], a link that leads nowhere, on a hover card.
  String unresolvedTarget(String target) => '$unresolved: $target';

  /// The legend row for concepts whose type has no colour of its own.
  String get other => 'Other';

  /// The tooltip of [other] when no concept in it has a type.
  String get conceptsWithoutType => 'Concepts without a type';

  /// The legend's name for a solid line.
  String get relationship => 'Relationship';

  /// The legend's name for a dashed line.
  String get inText => 'In text';

  /// How many concepts and links are in view.
  String stats(int concepts, int links) =>
      '${knowledgeCount(concepts, 'concept')} · '
      '${knowledgeCount(links, 'link')}';

  /// A whole-bundle graph with no links.
  String get noLinksInBundle => 'No links in this bundle.';

  /// A local graph with no links within [steps].
  String noLinksWithin(int steps) =>
      'No links within ${knowledgeCount(steps, 'step')}.';

  /// Announced for the concept a local graph centres on.
  String get focus => 'focus';

  /// Announced for a node with findings of [severity].
  String hasFindings(KnowledgeSeverity severity) => 'has ${severity.plural}';

  /// The screen-reader hint for opening a node.
  String get open => 'Open';
}
