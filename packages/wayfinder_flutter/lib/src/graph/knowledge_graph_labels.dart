import '../model/knowledge_models.dart';
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

  /// A link written in a concept's text, when the edge names no relationship.
  String get linkedInText => 'Linked in text';

  /// A link from a concept's resource.
  String get resourceLink => 'Resource';

  /// A link from a concept's source.
  String get sourceLink => 'Source';

  /// A link from a concept's computation.
  String get computationLink => 'Computation';

  /// A link from a concept's executor.
  String get executorLink => 'Executor';

  /// A link from a concept's attester.
  String get attesterLink => 'Attester';

  /// A typed relationship that names no type of its own.
  String get relatedLink => 'Related';

  /// What [origin] is called when the edge names no relationship.
  String linkOrigin(KnowledgeLinkOrigin origin) => switch (origin) {
    KnowledgeLinkOrigin.body => linkedInText,
    KnowledgeLinkOrigin.resource => resourceLink,
    KnowledgeLinkOrigin.sourceResource => sourceLink,
    KnowledgeLinkOrigin.computation => computationLink,
    KnowledgeLinkOrigin.executorResource => executorLink,
    KnowledgeLinkOrigin.attesterResource => attesterLink,
    KnowledgeLinkOrigin.relationships => relatedLink,
  };

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
