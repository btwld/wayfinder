import 'package:okf/okf.dart';

import 'catalog.dart';

/// A vocabulary a catalog schema may reference through `x-slot`. The engine
/// fills each slot per validation; a catalog naming another slot is
/// rejected at load.
enum Slot {
  okfFrontmatterKeys('okf.frontmatterKeys'),
  profileTypes('profile.types'),
  profileTags('profile.tags'),
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
  final List<String>? actors;

  Map<Slot, List<String>> get slots => {
    Slot.okfFrontmatterKeys: okfKnownFrontmatterKeys.toList(),
    Slot.profileTypes: ?types,
    Slot.profileTags: ?tags,
    Slot.profileActors: ?actors,
  };
}

/// What one bundle is validated against: the selected release's catalog,
/// the slot values it is evaluated with, and where the selection came from.
final class EffectiveProfile {
  const EffectiveProfile(
    this.catalog,
    this.vocabulary, {
    this.configPath,
    this.declaration,
  });

  final RuleCatalog catalog;
  final Vocabulary vocabulary;

  /// The configuration path a finding about the project binding reports at.
  final String? configPath;

  /// The values of an in-bundle `profile.md` declaration.
  final Map<String, String>? declaration;
}
