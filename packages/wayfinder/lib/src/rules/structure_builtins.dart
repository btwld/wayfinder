import 'package:ack/ack.dart';
import 'package:okf/okf_io.dart';

import 'builtins.dart';
import 'facts.dart';

final filesPresentParams = Ack.object({
  'paths': Ack.list(Ack.string().minLength(1)).minItems(1).unique(),
});

Iterable<Violation> filesPresent(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final present = facts.loaded.paths.toSet();
  final missing = (params['paths']! as List<Object?>)
      .cast<String>()
      .where((path) => !present.contains(path))
      .toList();
  if (missing.isNotEmpty) {
    yield Violation(missing.first, failing: missing);
  }
}

final matchesGeneratedParams = Ack.object({
  'generator': Ack.literal('okf-index'),
  'version': Ack.literal(okfIndexGeneratorRevision).optional(),
  'keep': Ack.list(Ack.string().minLength(1)).unique().optional(),
  'extra': Ack.enumString(['report', 'ignore']).optional(),
});

/// What `generator` writes for the bundle, by bundle-relative path. The
/// generated text declares the Profile's `implements.release`. The bytes are
/// those of the engine's okf release, reported as `engine.okf`, and every okf
/// release with one [okfIndexGeneratorRevision] writes the same bytes. A
/// package that pins `version` names that revision, so it loads only on an
/// engine whose generator writes the bytes its verdicts assume.
Map<String, String> generated(BundleFacts facts, Map<String, Object?> params) =>
    switch (params['generator']) {
      'okf-index' => const OkfIndexGenerator().generate(
        facts.loaded.bundle,
        declareVersion: facts.profile.okfRelease,
      ),
      final other => throw StateError('unknown generator $other'),
    };

/// [text] with CRLF line endings written as LF. A checkout may convert an
/// index's line endings; they are not part of the generated text.
String? withLfLineEndings(String? text) => text?.replaceAll('\r\n', '\n');

/// `stale` for every generated path whose file is missing or differs, and,
/// unless `extra` is `ignore`, `extra` for every index on disk the
/// generator does not write and `keep` does not exempt. Line endings are
/// folded here and when the fix writes, so the two always agree.
Iterable<Violation> matchesGenerated(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final expected = generated(facts, params);
  for (final MapEntry(key: path, value: text) in expected.entries) {
    if (withLfLineEndings(facts.loaded.indexes[path]) != text) {
      yield Violation(path, facts: {'path': path}, messageId: 'stale');
    }
  }
  if (params['extra'] == 'ignore') return;
  final keep = (params['keep'] as List<Object?>? ?? const []).toSet();
  for (final path in facts.loaded.indexes.keys) {
    if (expected.containsKey(path) || keep.contains(path)) continue;
    yield Violation(path, facts: {'path': path}, messageId: 'extra');
  }
}
