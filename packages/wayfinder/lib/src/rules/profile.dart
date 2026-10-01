import 'package:okf/okf.dart';

import 'catalog.dart';

/// A vocabulary a catalog schema may reference through `x-slot`. The engine
/// fills each slot per validation; a catalog naming another slot is
/// rejected at load.
enum Slot {
  okfFrontmatterKeys('okf.frontmatterKeys'),

  /// The base catalog's declared frontmatter keys. Only the installed
  /// release declares keys (Profile §5.1), so a source catalog adds none.
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

/// Slot values for one validation. A null list means the slot's provider
/// could not produce it, so every rule that references the slot is skipped;
/// an empty list is available and accepts nothing.
final class Vocabulary {
  const Vocabulary({
    required this.standardTypes,
    this.projectTypes = const [],
    this.types,
    this.tags,
    this.relationships,
    this.actors,
  });

  /// The release's standard types, in manifest order.
  final List<String> standardTypes;

  /// The types the project adds, in declaration order.
  final List<String> projectTypes;

  /// The registered types the `profile.types` slot accepts. The 2026.2
  /// registry fixes this as its own rows, which may omit a standard type.
  final List<String>? types;
  final List<String>? tags;

  /// The declared relationship names; under 2026.2, its standard
  /// `# Relationships` labels.
  final List<String>? relationships;
  final List<String>? actors;
}

/// What one bundle is validated against: the catalog chain, the slot
/// values it is evaluated with, and where the selection came from.
final class EffectiveProfile {
  const EffectiveProfile(
    this.catalogs,
    this.vocabulary, {
    this.configPath,
    this.declaration,
  });

  /// Base first: the installed release's catalog, then the catalog each
  /// source Profile along the `extends` chain ships, parent before child.
  /// Every catalog is evaluated whole and reports in its own namespace, so
  /// a child can only add findings (Profile §11).
  final List<RuleCatalog> catalogs;
  final Vocabulary vocabulary;

  /// The installed release's catalog, which names the release assessed.
  RuleCatalog get base => catalogs.first;

  Map<Slot, List<String>> get slots => {
    Slot.okfFrontmatterKeys: okfKnownFrontmatterKeys.toList(),
    Slot.profileFrontmatterKeys: base.frontmatterKeys.keys.toList(),
    Slot.profileTypes: ?vocabulary.types,
    Slot.profileTags: ?vocabulary.tags,
    Slot.profileRelationships: ?vocabulary.relationships,
    Slot.profileActors: ?vocabulary.actors,
  };

  /// The configuration path a finding about the project binding reports at.
  final String? configPath;

  /// The values of an in-bundle `profile.md` declaration.
  final Map<String, String>? declaration;
}
