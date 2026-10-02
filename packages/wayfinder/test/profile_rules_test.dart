import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test('reports the supported release binding through text output', () async {
    final result = await validateFixture(fixture('configured-binding'));
    final text = result.toTextLines().join('\n');

    expect(result.exitCode, 1);
    expect(text, contains('Profile 2026.3: FAIL'));
    expect(text, contains('concepta-profile/okf-release-binding (2026.3 §11)'));
    expect(text, endsWith('Gate: FAIL'));
  });

  test('validates concept metadata through text and JSON output', () async {
    final result = await validateFixture(fixture('invalid-concepts'));
    final profile = result.toJson()['profile']! as Map<String, Object?>;

    expect(result.exitCode, 1);
    expect(profile['state'], 'FAIL');
    expect(findingSummary(profile), <String>[
      'error concepta-profile/concept-baseline-fields bad.md',
      'advisory concepta-profile/generation-provenance-recommended bad.md',
      'error concepta-profile/status-value bad.md',
    ]);
    expect(result.gate, GateState.fail);
    final text = result.toTextLines().join('\n');
    for (final id in <String>[
      'concepta-profile/concept-baseline-fields',
      'concepta-profile/status-value',
      'concepta-profile/generation-provenance-recommended',
    ]) {
      expect(text, contains(id));
    }
  });

  test('validates sources and relationships deterministically', () async {
    final result = await validateFixture(fixture('configured-conventions'));
    final repeated = await validateFixture(fixture('configured-conventions'));

    expect(jsonEncode(repeated.toJson()), jsonEncode(result.toJson()));
    expect(result.exitCode, 1);
    for (final finding in result.findings) {
      expect(finding.profileRelease, '2026.3');
      expect(finding.rule, isNotEmpty);
    }
  });

  test('reports source paths that resolve to nothing as advisories', () async {
    // A path inside the bundle that names no file, and a relative path that
    // leaves the bundle and names nothing on disk, both earn an advisory; a
    // path that leaves the bundle and exists, a URL, and a descriptor do not.
    final result = await validateFixture(fixture('unresolved-source-path'));
    final profile = result.toJson()['profile']! as Map<String, Object?>;

    expect(result.exitCode, 0);
    expect(profile['state'], 'PASS');
    expect(
      findingSummary(profile),
      List.filled(
        3,
        'advisory concepta-profile/source-path-unresolved note.md',
      ),
    );
    expect(result.gate, GateState.pass);
  });

  test('joins adjacent footnote references to their definitions', () async {
    // `[^a][^b]` parses as a reference link and stays literal text, so the
    // attribution join must be decided by the definition, not the parser.
    final result = await validateFixture(fixture('adjacent-footnotes'));

    expect(result.exitCode, 0);
    expect(result.profileState, ProfileState.pass);
    expect(result.findings, isEmpty);
  });

  test('a definition shown only inside a fence does not join', () async {
    final result = await validateFixture(fixture('fenced-footnote'));
    final profile = result.toJson()['profile']! as Map<String, Object?>;

    expect(result.exitCode, 1);
    expect(findingSummary(profile), <String>[
      'error concepta-profile/source-attribution-join note.md',
    ]);
  });

  test(
    'validates prose source descriptors with slashes and non-ASCII cleanly',
    () async {
      // A sources[].resource descriptor carrying both a slash and a non-ASCII
      // character reads as a link the graph builder must resolve; the whole
      // assessment dies if it throws instead of treating it as a descriptor.
      final result = await validateFixture(fixture('source-descriptor'));

      expect(result.exitCode, 0);
      expect(result.okfState, OkfState.pass);
      expect(result.profileState, ProfileState.pass);
      expect(result.findings, isEmpty);
      expect(result.diagnostics, isEmpty);
    },
  );

  test(
    'requires the root structural files without repository discovery',
    () async {
      final result = await validateFixture(fixture('missing-structure-root'));
      final profile = result.toJson()['profile']! as Map<String, Object?>;

      expect(result.exitCode, 1);
      expect(findingSummary(profile), <String>[
        'error concepta-profile/okf-release-binding index.md',
        'error concepta-profile/root-structure-files index.md',
      ]);
    },
  );

  test(
    'keeps structure finding order independent of file creation order',
    () async {
      final source = Directory(fixture('configured-structure'));
      final reversed = await Directory.systemTemp.createTemp(
        'wayfinder-structure-',
      );
      addTearDown(() => reversed.delete(recursive: true));
      final files = await source
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      for (final file in files.reversed) {
        final relative = p.relative(file.path, from: source.path);
        final destination = File(p.join(reversed.path, relative));
        await destination.parent.create(recursive: true);
        await file.copy(destination.path);
      }

      final original = await validateFixture(source.path);
      final reordered = await validateFixture(reversed.path);

      expect(original.findings, isNotEmpty);
      expect(
        jsonEncode(reordered.toJson()['profile']),
        jsonEncode(original.toJson()['profile']),
      );
      expect(reordered.exitCode, original.exitCode);
    },
  );
}
