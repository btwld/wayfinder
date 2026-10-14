import 'package:ack/ack.dart';
import 'package:okf/okf_io.dart';

import '../generated/published_schemas.g.dart';
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
  'version': Ack.literal(okfPackageVersion).optional(),
  'keep': Ack.list(Ack.string().minLength(1)).unique().optional(),
  'extra': Ack.enumString(['report', 'ignore']).optional(),
});

/// What `generator` writes for the bundle, by bundle-relative path. The
/// generated text declares the Profile's `implements.release`; which okf
/// generator wrote it is the engine's okf dependency, reported as
/// `engine.okf`. A package that pins `version` loads only on an engine with
/// that okf, so a generator upgrade cannot change its verdicts unannounced.
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
