import 'package:okf/okf_io.dart';

import '../profile_release.dart';
import 'builtins.dart';
import 'facts.dart';

const rootStructureFilesParams = <String, Object?>{
  'type': 'object',
  'required': ['required'],
  'additionalProperties': false,
  'properties': {
    'required': {
      'type': 'array',
      'minItems': 1,
      'items': {'type': 'string', 'minLength': 1},
    },
  },
};

Iterable<Violation> rootStructureFiles(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final loaded = facts.loaded;
  final missing = (params['required']! as List<Object?>)
      .cast<String>()
      .where(
        (path) =>
            !loaded.indexes.containsKey(path) &&
            !loaded.logs.containsKey(path) &&
            !loaded.documents.containsKey(path),
      )
      .toList();
  if (missing.isNotEmpty) {
    yield Violation(missing.first, failing: missing);
  }
}

Map<String, String> generatedIndexes(
  BundleFacts facts,
  Map<String, Object?> params,
) => const OkfIndexGenerator().generate(
  facts.loaded.bundle,
  declareVersion: supportedOkfRelease,
);

/// [text] with CRLF line endings written as LF. A checkout may convert an
/// index's line endings; they are not part of the generated text.
String? withLfLineEndings(String? text) => text?.replaceAll('\r\n', '\n');

Iterable<Violation> indexCurrent(
  BundleFacts facts,
  Map<String, Object?> params,
) sync* {
  final generated = generatedIndexes(facts, params);
  for (final MapEntry(key: path, value: text) in generated.entries) {
    if (withLfLineEndings(facts.loaded.indexes[path]) != text) {
      yield Violation(path, facts: {'path': path}, messageId: 'stale');
    }
  }
  // okf's generator lists every directory that has an index.md, even one it
  // no longer writes, such as a 2026.2 raw/ tier, so the leftover must go. A
  // bundle without concepts keeps the hand-written root index the Profile
  // requires.
  for (final path in facts.loaded.indexes.keys) {
    if (generated.containsKey(path) || path == 'index.md') continue;
    yield Violation(path, facts: {'path': path}, messageId: 'extra');
  }
}
