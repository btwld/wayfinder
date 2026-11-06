// Portable: the few word forms a reader builds, in one place.

/// [n] and [noun], plural unless [n] is one: `1 concept`, `2 concepts`.
/// [plural] is the noun's plural when it is not [noun] and `s`.
String knowledgeCount(int n, String noun, [String? plural]) =>
    '$n ${n == 1 ? noun : plural ?? '${noun}s'}';

/// A name as words, capitalised: `depends-on` reads `Depends on`.
String knowledgeHumanize(String name) {
  final words = name.replaceAll(RegExp('[-_]+'), ' ').trim();
  return words.isEmpty
      ? words
      : '${words[0].toUpperCase()}${words.substring(1)}';
}
