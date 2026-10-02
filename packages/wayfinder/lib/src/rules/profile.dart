import 'package:okf/okf.dart';

import 'catalog.dart';
import 'registries.dart';

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

final class Vocabulary {
  const Vocabulary({
    required this.standardTypes,
    this.projectTypes = const [],
    this.types,
    this.tags,
    this.relationships,
    this.actors,
  });

  final List<String> standardTypes;

  final List<String> projectTypes;

  final List<String>? types;
  final List<String>? tags;

  final List<String>? relationships;
  final List<String>? actors;
}

final class EffectiveProfile {
  const EffectiveProfile(
    this.catalogs,
    this.vocabulary, {
    this.configPath,
    this.legacy,
  });

  final List<RuleCatalog> catalogs;
  final Vocabulary vocabulary;

  RuleCatalog get base => catalogs.first;

  Map<Slot, List<String>> get slots => {
    Slot.okfFrontmatterKeys: okfKnownFrontmatterKeys.toList(),
    Slot.profileFrontmatterKeys: base.frontmatterKeys.keys.toList(),
    Slot.profileTypes: ?vocabulary.types,
    Slot.profileTags: ?vocabulary.tags,
    Slot.profileRelationships: ?vocabulary.relationships,
    Slot.profileActors: ?vocabulary.actors,
  };

  final String? configPath;

  /// What the 2026.2 dispatch read from the bundle: the profile.md
  /// declaration and the registries its vocabulary came from.
  final ({Map<String, String> declaration, LegacyRegistries registries})?
  legacy;
}
