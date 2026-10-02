import 'package:okf/okf.dart';

import '../profile_package.dart';
import '../wayfinder_config.dart';
import 'catalog.dart';

enum Slot {
  okfFrontmatterKeys('okf.frontmatterKeys'),

  profileFrontmatterKeys('profile.frontmatterKeys'),
  profileTypes('profile.types'),
  profileTags('profile.tags'),
  profileRelationships('profile.relationships'),
  profileActors('profile.actors');

  const Slot(this.id);

  final String id;

  static Slot? byId(String id) {
    for (final slot in values) {
      if (slot.id == id) return slot;
    }
    return null;
  }
}

/// The composed names rules see. Every list is always present, so every
/// slot always has a value and no rule is ever skipped for want of one.
final class Vocabulary {
  const Vocabulary({
    required this.types,
    required this.tags,
    required this.relationships,
    required this.actors,
    required this.frontmatterKeys,
  });

  final List<String> types;
  final List<String> tags;
  final List<String> relationships;
  final List<String> actors;
  final List<String> frontmatterKeys;
}

/// What a project's `wayfinder.json` adds for one binding: vocabulary and
/// actors, never frontmatter keys or rules.
final class ProjectVocabulary {
  const ProjectVocabulary({
    this.types = const [],
    this.tags = const [],
    this.relationships = const [],
    this.actors = const {},
  });

  static const none = ProjectVocabulary();

  final List<WayfinderDefinition> types;
  final List<WayfinderDefinition> tags;
  final List<WayfinderDefinition> relationships;
  final Map<String, WayfinderActorMetadata> actors;
}

final class ProfileCompositionException implements Exception {
  const ProfileCompositionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Profile a bundle is assessed against: a chain of packages, root
/// ancestor first, plus the project's additions. Contributors declare only
/// their own names; the merge happens here, once.
final class EffectiveProfile {
  const EffectiveProfile._(this.chain, this.project, this.vocabulary);

  /// Pure. Throws [ProfileCompositionException] when the chain is empty or
  /// repeats an id, when a type, tag or relationship name repeats across
  /// chain and project, when a frontmatter key repeats along the chain, or
  /// when a tag equals a type, an OKF status, an OKF trust tier or a
  /// relationship.
  ///
  /// Monotonicity is structural: a package contributes only additions and
  /// rules in its own namespace, so nothing here can remove or re-grade an
  /// ancestor's rule.
  factory EffectiveProfile.compose(
    List<ProfilePackage> chain, {
    ProjectVocabulary project = ProjectVocabulary.none,
  }) {
    if (chain.isEmpty) {
      throw const ProfileCompositionException(
        'A Profile chain needs at least one package.',
      );
    }
    final ids = <ProfileId>{};
    for (final package in chain) {
      if (!ids.add(package.id)) {
        throw ProfileCompositionException(
          'Profile ${package.id} appears twice in the chain.',
        );
      }
    }
    final types = _names('type', [
      for (final package in chain) ('Profile ${package.id}', package.types),
      ('The project', project.types),
    ]);
    final relationships = _names('relationship', [
      for (final package in chain)
        ('Profile ${package.id}', package.relationships),
      ('The project', project.relationships),
    ]);
    final tags = _names('tag', [
      for (final package in chain) ('Profile ${package.id}', package.tags),
      ('The project', project.tags),
    ]);
    final others = <(String, Iterable<String>)>[
      ('a declared type name', types.keys),
      (
        'an OKF status value',
        OkfLifecycleStatus.values
            .where((status) => status != OkfLifecycleStatus.unknown)
            .map((status) => status.wireValue),
      ),
      ('an OKF trust tier', OkfTrustTier.values.map((tier) => tier.wireValue)),
      ('a declared relationship name', relationships.keys),
    ];
    for (final MapEntry(key: tag, value: owner) in tags.entries) {
      for (final (what, names) in others) {
        if (names.contains(tag)) {
          throw ProfileCompositionException(
            '$owner declares tag $tag, which equals $what.',
          );
        }
      }
    }
    final frontmatterKeys = _names('frontmatter key', [
      for (final package in chain)
        ('Profile ${package.id}', package.frontmatterKeys),
    ]);
    return EffectiveProfile._(
      List.unmodifiable(chain),
      project,
      Vocabulary(
        types: types.keys.toList(),
        tags: tags.keys.toList(),
        relationships: relationships.keys.toList(),
        actors: project.actors.keys.toList(),
        frontmatterKeys: frontmatterKeys.keys.toList(),
      ),
    );
  }

  static Map<String, String> _names(
    String noun,
    List<(String, List<WayfinderDefinition>)> contributions,
  ) {
    final names = <String, String>{};
    for (final (owner, definitions) in contributions) {
      for (final definition in definitions) {
        if (names.containsKey(definition.name)) {
          throw ProfileCompositionException(
            '$owner declares $noun ${definition.name}, which '
            '${names[definition.name]} already declares.',
          );
        }
        names[definition.name] = owner;
      }
    }
    return names;
  }

  /// Root ancestor first; the bundle's own Profile is [selected].
  final List<ProfilePackage> chain;
  final ProjectVocabulary project;
  final Vocabulary vocabulary;

  ProfilePackage get selected => chain.last;
  String get okfRelease => chain.first.okfRelease;

  /// Rules in evaluation order: ancestors first, each package in file order.
  Iterable<CatalogRule> get rules => chain.expand((package) => package.rules);

  Map<Slot, List<String>> get slots => {
    Slot.okfFrontmatterKeys: okfKnownFrontmatterKeys.toList(),
    Slot.profileFrontmatterKeys: vocabulary.frontmatterKeys,
    Slot.profileTypes: vocabulary.types,
    Slot.profileTags: vocabulary.tags,
    Slot.profileRelationships: vocabulary.relationships,
    Slot.profileActors: vocabulary.actors,
  };
}
