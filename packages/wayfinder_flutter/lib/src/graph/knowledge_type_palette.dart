import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

import '../model/knowledge.dart';

/// The hues the Graph gives the eight commonest concept types of a bundle,
/// most distinct first; every other type is "Other". None is red or amber,
/// which mean errors and warnings. Dark-theme hues are the light 400 tones,
/// light-theme hues the 600 tones, so each holds at least 3:1 against its
/// background.
const knowledgeTypeHues = (
  dark: [
    Color(0xFF60A5FA), // blue
    Color(0xFFA78BFA), // violet
    Color(0xFF2DD4BF), // teal
    Color(0xFFF472B6), // pink
    Color(0xFFA3E635), // lime
    Color(0xFFFB923C), // orange
    Color(0xFFE879F9), // fuchsia
    Color(0xFF4ADE80), // green
  ],
  light: [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0D9488),
    Color(0xFFDB2777),
    Color(0xFF65A30D),
    Color(0xFFEA580C),
    Color(0xFFC026D3),
    Color(0xFF16A34A),
  ],
);

/// The colour of each concept type in a bundle, the same in every graph of
/// it: the eight commonest types by concept count (ties by name) get a hue,
/// the rest share the muted "Other".
@immutable
final class KnowledgeTypePalette {
  KnowledgeTypePalette._(Map<String, int> hued) : hued = Map.unmodifiable(hued);

  /// The palette of [concepts]' types: pass every concept of the bundle,
  /// not those in view, so a type keeps its colour from view to view.
  factory KnowledgeTypePalette.of(Iterable<KnowledgeConceptSummary> concepts) {
    final counts = <String, int>{};
    for (final concept in concepts) {
      final type = concept.type.trim();
      if (type.isEmpty) continue;
      counts[type] = (counts[type] ?? 0) + 1;
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return KnowledgeTypePalette._({
      for (final (i, type) in ranked.take(hueCount).indexed) type: i,
    });
  }

  /// How many types get a hue of their own.
  static final hueCount = knowledgeTypeHues.dark.length;

  /// The hue index of each coloured type.
  final Map<String, int> hued;

  /// Whether [type] has a hue of its own, rather than "Other".
  bool hasHue(String type) => hued.containsKey(type.trim());

  /// The colour of [type] in [brightness].
  Color colorOf(String type, Brightness brightness, Color other) {
    final index = hued[type.trim()];
    if (index == null) return other;
    final hues = brightness == Brightness.dark
        ? knowledgeTypeHues.dark
        : knowledgeTypeHues.light;
    return hues[index];
  }

  @override
  bool operator ==(Object other) =>
      other is KnowledgeTypePalette && mapEquals(other.hued, hued);

  @override
  int get hashCode => Object.hashAllUnordered(
    hued.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
