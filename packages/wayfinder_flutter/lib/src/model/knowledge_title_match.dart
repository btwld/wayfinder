// Portable: the instant half of search. Concepts match on their title, id
// and tags, best first, with the matched parts of the title to highlight.
import 'package:flutter/foundation.dart' show immutable;

import 'knowledge_models.dart';

/// A span of text, `[start, end)`.
typedef KnowledgeTextRange = ({int start, int end});

/// A concept that matched a title search.
@immutable
final class KnowledgeTitleMatch {
  const KnowledgeTitleMatch({
    required this.concept,
    required this.score,
    this.titleRanges = const [],
  });

  final KnowledgeConceptSummary concept;

  /// Higher is better.
  final int score;

  /// The parts of the title that matched, sorted and disjoint.
  final List<KnowledgeTextRange> titleRanges;
}

/// The concepts that match [query] on title, id or tags, best first:
/// an exact title, then a title prefix, a word of the title, a part of a
/// word, then letters of the title in order; id and tag matches rank below
/// title matches of the same kind. Each word of a query of several words
/// must match somewhere.
List<KnowledgeTitleMatch> knowledgeTitleMatches(
  Iterable<KnowledgeConceptSummary> concepts,
  String query, {
  int? limit,
}) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final whole = words.join(' ');
  final matches = <KnowledgeTitleMatch>[];
  for (final concept in concepts) {
    final title = concept.title.toLowerCase();
    final id = concept.id.toLowerCase();
    final tags = [for (final tag in concept.tags) tag.toLowerCase()];
    var score = 0;
    final ranges = <KnowledgeTextRange>[];
    // The whole query against the title first, letters in order included.
    final full = _scoreField(title, whole, fuzzy: true);
    if (full != null) {
      score = full.score + 200;
      ranges.addAll(full.ranges);
    } else {
      var matchedAll = true;
      for (final word in words) {
        final inTitle = _scoreField(title, word, fuzzy: words.length == 1);
        final inId = _scoreField(id, word, fuzzy: false);
        final inTags = [
          for (final tag in tags) ?_scoreField(tag, word, fuzzy: false),
        ];
        final bestTag = inTags.isEmpty
            ? 0
            : inTags.map((m) => m.score).reduce((a, b) => a > b ? a : b);
        final best = [
          inTitle?.score ?? 0,
          ((inId?.score ?? 0) * 0.6).round(),
          (bestTag * 0.7).round(),
        ].reduce((a, b) => a > b ? a : b);
        if (best == 0) {
          matchedAll = false;
          break;
        }
        score += best;
        if (inTitle != null) ranges.addAll(inTitle.ranges);
      }
      if (!matchedAll) continue;
      // Keep per-word matches on the same scale as a whole-title match.
      score = (score / words.length).round();
    }
    matches.add(
      KnowledgeTitleMatch(
        concept: concept,
        score: score,
        titleRanges: _merge(ranges),
      ),
    );
  }
  matches.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byLength = a.concept.title.length.compareTo(b.concept.title.length);
    if (byLength != 0) return byLength;
    return a.concept.title.compareTo(b.concept.title);
  });
  return limit == null || matches.length <= limit
      ? matches
      : matches.sublist(0, limit);
}

({int score, List<KnowledgeTextRange> ranges})? _scoreField(
  String field,
  String needle, {
  required bool fuzzy,
}) {
  if (needle.isEmpty || field.isEmpty) return null;
  if (field == needle) {
    return (score: 1000, ranges: [(start: 0, end: field.length)]);
  }
  final at = field.indexOf(needle);
  if (at == 0) {
    return (score: 900, ranges: [(start: 0, end: needle.length)]);
  }
  if (at > 0) {
    // Prefer the start of a word anywhere in the field.
    final wordStart = RegExp('(^|[^a-z0-9])${RegExp.escape(needle)}')
        .firstMatch(field);
    if (wordStart != null) {
      final start = wordStart.start + wordStart.group(1)!.length;
      return (score: 700, ranges: [(start: start, end: start + needle.length)]);
    }
    return (score: 500, ranges: [(start: at, end: at + needle.length)]);
  }
  if (!fuzzy || needle.length < 2) return null;
  // Letters in order, preferring word starts; too scattered is no match.
  final ranges = <KnowledgeTextRange>[];
  var position = 0;
  var gaps = 0;
  for (var i = 0; i < needle.length; i++) {
    final char = needle[i];
    if (char == ' ') continue;
    final found = field.indexOf(char, position);
    if (found < 0) return null;
    gaps += found - position;
    if (ranges.isNotEmpty && ranges.last.end == found) {
      ranges[ranges.length - 1] = (start: ranges.last.start, end: found + 1);
    } else {
      ranges.add((start: found, end: found + 1));
    }
    position = found + 1;
  }
  if (gaps > needle.length * 3 + 6) return null;
  final score = 300 - gaps * 4 - ranges.length * 6;
  return score <= 0 ? null : (score: score, ranges: ranges);
}

List<KnowledgeTextRange> _merge(List<KnowledgeTextRange> ranges) {
  if (ranges.length < 2) return ranges;
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <KnowledgeTextRange>[sorted.first];
  for (final range in sorted.skip(1)) {
    final last = merged.last;
    if (range.start <= last.end) {
      merged[merged.length - 1] = (
        start: last.start,
        end: range.end > last.end ? range.end : last.end,
      );
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// Where the words of [query] (two letters or more) occur in [text], any
/// case, for highlighting a passage.
List<KnowledgeTextRange> knowledgeQueryRanges(String text, String query) {
  final lower = text.toLowerCase();
  final ranges = <KnowledgeTextRange>[];
  for (final word in query.toLowerCase().split(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  )) {
    if (word.length < 2) continue;
    var from = 0;
    while (true) {
      final at = lower.indexOf(word, from);
      if (at < 0) break;
      ranges.add((start: at, end: at + word.length));
      from = at + word.length;
    }
  }
  return _merge(ranges);
}

/// A passage cut to about [length] characters around its first match of
/// [query], on word boundaries, with `…` where it was cut.
String knowledgeSnippet(String text, String query, {int length = 220}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= length) return flat;
  final ranges = knowledgeQueryRanges(flat, query);
  var start = ranges.isEmpty ? 0 : ranges.first.start - length ~/ 3;
  if (start < 0) start = 0;
  if (start > 0) {
    final space = flat.indexOf(' ', start);
    if (space >= 0 && space < ranges.first.start) start = space + 1;
  }
  var end = start + length;
  if (end >= flat.length) {
    end = flat.length;
  } else {
    final space = flat.lastIndexOf(' ', end);
    if (space > start && (ranges.isEmpty || space >= ranges.first.end)) {
      end = space;
    }
  }
  return '${start > 0 ? '…' : ''}${flat.substring(start, end)}'
      '${end < flat.length ? '…' : ''}';
}
