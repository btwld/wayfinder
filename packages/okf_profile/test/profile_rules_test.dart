import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('reports the supported release binding through text output', () async {
    final result = await runProcess(
      <String>['validate', fixture('invalid-binding')],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    expect(result.stdout, contains('Profile 2026.1: FAIL'));
    expect(
      result.stdout,
      contains('concepta-profile/okf-release-binding (2026.1 §11)'),
    );
    expect(result.stdout, endsWith('Automated gate: FAIL'));
  });

  test('validates concept metadata through text and JSON output', () async {
    final jsonResult = await runProcess(
      <String>['validate', '--output', 'json', fixture('invalid-concepts')],
    );

    expect(jsonResult.exitCode, 1);
    expect(jsonResult.stderr, isEmpty);
    final output = jsonDecode(jsonResult.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'FAIL');
    expect(
      findingSummary(profile),
      <String>[
        'error concepta-profile/concept-baseline-fields bad.md',
        'error concepta-profile/frontmatter-fields-okf bad.md',
        'error concepta-profile/status-value bad.md',
        'error concepta-profile/tag-literal-duplication bad.md',
        'advisory concepta-profile/generation-provenance-recommended '
            'profile.md',
        'advisory concepta-profile/generation-provenance-recommended types.md',
      ],
    );
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final textResult = await runProcess(
      <String>['validate', fixture('invalid-concepts')],
    );
    expect(textResult.exitCode, 1);
    expect(textResult.stderr, isEmpty);
    for (final id in <String>[
      'concepta-profile/concept-baseline-fields',
      'concepta-profile/frontmatter-fields-okf',
      'concepta-profile/status-value',
      'concepta-profile/tag-literal-duplication',
      'concepta-profile/generation-provenance-recommended',
    ]) {
      expect(textResult.stdout, contains(id));
    }
  });

  test('validates registries, sources, and relationships deterministically',
      () async {
    final arguments = <String>[
      'validate',
      '--output',
      'json',
      fixture('invalid-conventions'),
    ];
    final result = await runProcess(arguments);
    final repeated = await runProcess(arguments);

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    expect(repeated.stdout, result.stdout);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      <String>[
        'error concepta-profile/actor-active-interval actors.md',
        'error concepta-profile/actor-active-overlap actors.md',
        'error concepta-profile/actor-row-complete actors.md',
        'error concepta-profile/actor-side-value actors.md',
        'error concepta-profile/relationships-shape bad.md',
        'error concepta-profile/source-attribution-join bad.md',
        'error concepta-profile/source-entry-shape bad.md',
        'error concepta-profile/source-id-unique bad.md',
        'error concepta-profile/used-actor-registered bad.md',
        'error concepta-profile/used-type-registered bad.md',
        'error concepta-profile/relationships-shape numbered.md',
        'error concepta-profile/relationships-shape plain.md',
        'advisory concepta-profile/registered-type-extension types.md',
        'error concepta-profile/type-registry-order types.md',
        'error concepta-profile/type-registry-standards types.md',
      ],
    );
    for (final finding in profile['findings']! as List<Object?>) {
      final value = finding! as Map<String, Object?>;
      expect(value['profile_release'], '2026.1');
      expect(value['rule'], isNotEmpty);
    }
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final text = await runProcess(
      <String>['validate', fixture('invalid-conventions')],
    );
    expect(text.exitCode, 1);
    expect(text.stdout, contains('Profile 2026.1: FAIL'));
    expect(text.stdout, contains('concepta-profile/relationships-shape'));
  });

  test('keeps concept advisories and absence boundaries gate-neutral',
      () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('advisory-concepts')],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(
      findingSummary(profile),
      <String>[
        'advisory concepta-profile/generation-provenance-recommended note.md',
        'advisory concepta-profile/internal-link-bundle-relative note.md',
        'advisory concepta-profile/internal-link-unresolved note.md',
        'advisory concepta-profile/relationship-label-extension note.md',
        'advisory concepta-profile/registered-type-extension types.md',
      ],
    );
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});

    final text = await runProcess(
      <String>['validate', fixture('advisory-concepts')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('advisory concepta-profile/'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('validates prose source descriptors with slashes and non-ASCII cleanly',
      () async {
    // Regression for the okf 0.1.2 graph-builder crash: a sources[].resource
    // prose descriptor containing both a slash and an em dash killed okfp
    // mid-assessment. okf 0.2.0 resolves it as a descriptor edge; the
    // link-graph guard stays as defense in depth.
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('graph-failure')],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final okf = output['okf']! as Map<String, Object?>;
    expect(okf['state'], 'PASS');
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(findingSummary(profile), isEmpty);
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});
  });

  test('validates structure, indexes, logs, and referenced assets', () async {
    final arguments = <String>[
      'validate',
      '--output',
      'json',
      fixture('invalid-structure'),
    ];
    final result = await runProcess(arguments);

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      <String>[
        'error concepta-profile/directory-index-present analyses/index.md',
        'error concepta-profile/index-semantic-projection index.md',
        'error concepta-profile/log-entry-lead-word log.md',
        'error concepta-profile/index-semantic-projection references/index.md',
      ],
    );
    expect(profile['state'], 'FAIL');
    expect(output['judgment_rules'], <String, Object?>{
      'state': 'UNASSESSED',
    });
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final text = await runProcess(
      <String>['validate', fixture('invalid-structure')],
    );
    expect(text.exitCode, 1);
    expect(text.stdout, contains('concepta-profile/index-semantic-projection'));
    expect(text.stdout, contains('concepta-profile/log-entry-lead-word'));
    expect(text.stdout, endsWith('Automated gate: FAIL'));
  });

  test('flags non-index markdown inside a references raw/ tier', () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('invalid-raw')],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      contains('error concepta-profile/raw-directory-markdown '
          'references/walkthrough-2026-08-25/raw/stray.md'),
    );
    expect(
      findingSummary(profile).where((line) => line.startsWith('error')),
      hasLength(1),
    );
    expect(profile['state'], 'FAIL');
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final text = await runProcess(
      <String>['validate', fixture('invalid-raw')],
    );
    expect(text.exitCode, 1);
    expect(
      text.stdout,
      contains('raw/stray.md: error concepta-profile/raw-directory-markdown'),
    );
    expect(text.stdout, endsWith('Automated gate: FAIL'));
  });

  test('flags a raw/ tier sitting directly under references/', () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        fixture('invalid-raw-placement'),
      ],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      contains(
        'error concepta-profile/raw-directory-placement references/raw',
      ),
    );
    expect(
      findingSummary(profile).where((line) => line.startsWith('error')),
      hasLength(1),
    );
    expect(profile['state'], 'FAIL');
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

    final text = await runProcess(
      <String>['validate', fixture('invalid-raw-placement')],
    );
    expect(text.exitCode, 1);
    expect(
      text.stdout,
      contains(
        'references/raw: error concepta-profile/raw-directory-placement',
      ),
    );
    expect(text.stdout, endsWith('Automated gate: FAIL'));
  });

  test('accepts presentation-equivalent indexes and contextual boundaries',
      () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        fixture('structure-boundary'),
      ],
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(
      findingSummary(profile),
      <String>[
        'advisory concepta-profile/concept-area-name-collision topic.md',
        'advisory concepta-profile/registered-type-extension types.md',
      ],
    );
    expect(output['judgment_rules'], <String, Object?>{
      'state': 'UNASSESSED',
    });
    expect(output['automated_gate'], <String, Object?>{'state': 'PASS'});

    final text = await runProcess(
      <String>['validate', fixture('structure-boundary')],
    );
    expect(text.exitCode, 0);
    expect(text.stdout, contains('concept-area-name-collision'));
    expect(text.stdout, endsWith('Automated gate: PASS'));
  });

  test('checks every semantic index projection dimension independently',
      () async {
    final rootIndexCases = <String, String Function(String)>{
      'membership': (source) => source.replaceFirst(
          '- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n',
          ''),
      'group identity': (source) =>
          source.replaceFirst('# Guide', '# Analysis'),
      'group order': (source) => source.replaceFirst(
          '# Guide\n\n- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.\n- [Topic](topic.md) - Durable knowledge that happens to share a name with an area.\n\n# Field Note\n\n- [Boundary note](boundary-note.md) - Exercises **custom** [type](types.md) projection order.',
          '# Field Note\n\n- [Boundary note](boundary-note.md) - Exercises **custom** [type](types.md) projection order.\n\n# Guide\n\n- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.\n- [Topic](topic.md) - Durable knowledge that happens to share a name with an area.'),
      'entry order': (source) => source.replaceFirst(
          '- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.\n- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.',
          '- [Interaction axis context](interactions.md) - Durable context beside the time-axis directory of the same name.\n- [Alpha guide](alpha.md) - Sorts before the same-type topic entry.'),
      'label': (source) =>
          source.replaceFirst('[Alpha guide]', '[Wrong label]'),
      'target': (source) => source.replaceFirst('(alpha.md)', '(wrong.md)'),
      'description': (source) => source.replaceFirst(
          'Sorts before the same-type topic entry.',
          'Changes copied navigation.'),
      'directory entry': (source) =>
          source.replaceFirst('- [references](references/)\n', ''),
    };
    for (final entry in rootIndexCases.entries) {
      final bundle = await copyFixture('structure-boundary');
      addTearDown(() => bundle.delete(recursive: true));
      final index = File(p.join(bundle.path, 'index.md'));
      final source = (await index.readAsString()).replaceAll('\r\n', '\n');
      final mutated = entry.value(source);
      expect(mutated, isNot(source), reason: entry.key);
      await index.writeAsString(mutated);

      final result = await runProcess(
        <String>['validate', '--output', 'json', bundle.path],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      expect(result.exitCode, 1, reason: entry.key);
      expect(
        findingSummary(profile),
        contains('error concepta-profile/index-semantic-projection index.md'),
        reason: entry.key,
      );
    }

    for (final path in <String>[
      'references/index.md',
      'references/vendor/index.md',
    ]) {
      final bundle = await copyFixture('structure-boundary');
      addTearDown(() => bundle.delete(recursive: true));
      final index = File(p.join(bundle.path, path));
      await index.writeAsString(
        (await index.readAsString()).replaceFirst('.txt)', '-wrong.txt)'),
      );
      if (path == 'references/index.md') {
        await index.writeAsString(
          (await index.readAsString())
              .replaceFirst('(clip.mp4)', '(wrong.mp4)'),
        );
      }

      final result = await runProcess(
        <String>['validate', '--output', 'json', bundle.path],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      expect(result.exitCode, 1, reason: path);
      expect(
        findingSummary(profile),
        contains('error concepta-profile/index-semantic-projection $path'),
        reason: path,
      );
    }
  });

  test('rejects index entry targets that decode wrong or diverge as URLs',
      () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        fixture('invalid-index-encoding'),
      ],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, isEmpty);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final okf = output['okf']! as Map<String, Object?>;
    expect(okf['state'], 'PASS');
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'FAIL');
    expect(
      findingSummary(profile),
      <String>[
        // A well-formed escape decoding to a name the projection lacks.
        'error concepta-profile/index-semantic-projection '
            'references/encoded/index.md',
        // A raw `#`, which a URL consumer would split as a fragment.
        'error concepta-profile/index-semantic-projection '
            'references/fragmented/index.md',
        // `%2F`, an escape aliasing the path separator.
        'error concepta-profile/index-semantic-projection '
            'references/slashed/index.md',
        // A stray `%` outside any valid escape sequence.
        'error concepta-profile/index-semantic-projection '
            'references/stray/index.md',
        // `%FF`: valid hex, undecodable as UTF-8 — a finding, not a crash.
        'error concepta-profile/index-semantic-projection '
            'references/undecodable/index.md',
      ],
    );
    expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});
  });

  test('requires the root structural files without repository discovery',
      () async {
    final result = await runProcess(
      <String>[
        'validate',
        '--output',
        'json',
        fixture('missing-structure-root'),
      ],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      <String>[
        'error concepta-profile/root-structure-files index.md',
        'error concepta-profile/okf-release-binding profile.md',
      ],
    );
  });

  test('reserves structural concept names for the bundle root', () async {
    for (final filename in <String>['profile.md', 'types.md', 'actors.md']) {
      final bundle = await copyFixture('structure-boundary');
      addTearDown(() => bundle.delete(recursive: true));
      final source = File(
        p.join(bundle.path, 'topic', 'Upper-ID-2026-08-22.md'),
      );
      final title = 'Reserved $filename';
      final description =
          'Uses reserved structural name $filename outside the bundle root.';
      final concept = File(p.join(bundle.path, 'topic', filename));
      await concept.writeAsString(
        (await source.readAsString())
            .replaceFirst('title: Legacy Identifier', 'title: $title')
            .replaceFirst(
              'description: Keeps a path whose identity cannot be judged from syntax alone.',
              'description: $description',
            )
            .replaceFirst('# Legacy Identifier', '# $title'),
      );
      final index = File(p.join(bundle.path, 'topic', 'index.md'));
      await index.writeAsString(
        '${(await index.readAsString()).trimRight()}\n'
        '- [$title]($filename) - $description\n',
      );

      final result = await runProcess(
        <String>['validate', '--output', 'json', bundle.path],
      );
      final output = jsonDecode(result.stdout) as Map<String, Object?>;
      final okf = output['okf']! as Map<String, Object?>;
      final profile = output['profile']! as Map<String, Object?>;
      expect(okf['state'], 'PASS', reason: filename);
      expect(result.exitCode, 1, reason: filename);
      expect(profile['state'], 'FAIL', reason: filename);
      expect(
        findingSummary(profile),
        contains(
          'error concepta-profile/root-structure-files topic/$filename',
        ),
        reason: filename,
      );
      expect(output['automated_gate'], <String, Object?>{'state': 'FAIL'});

      if (filename == 'profile.md') {
        final text = await runProcess(
          <String>['validate', bundle.path],
        );
        expect(text.exitCode, 1);
        expect(
          text.stdout,
          contains('topic/profile.md: error '
              'concepta-profile/root-structure-files'),
        );
        expect(text.stdout, endsWith('Automated gate: FAIL'));
      }
    }
  });

  test('keeps structure finding order independent of file creation order',
      () async {
    for (final name in <String>[
      'invalid-structure',
      'structure-boundary',
    ]) {
      final source = Directory(fixture(name));
      final reversed = await Directory.systemTemp.createTemp('okfp-structure-');
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

      final original = await runProcess(
        <String>['validate', '--output', 'json', source.path],
      );
      final reordered = await runProcess(
        <String>['validate', '--output', 'json', reversed.path],
      );

      expect(reordered.exitCode, original.exitCode, reason: name);
      expect(reordered.stdout, original.stdout, reason: name);
      expect(reordered.stderr, original.stderr, reason: name);
    }
  });

  test('validates declaration and registry identities and table columns',
      () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('invalid-registries')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      <String>[
        'error concepta-profile/actor-registry-columns actors.md',
        'error concepta-profile/actor-registry-kind actors.md',
        'error concepta-profile/profile-declaration-kind profile.md',
        'error concepta-profile/type-registry-columns types.md',
        'error concepta-profile/type-registry-kind types.md',
      ],
    );
  });

  test('requires the actor registry only when actor fields are used', () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('missing-actors')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
        findingSummary(profile),
        contains(
          'error concepta-profile/actor-registry-required actors.md',
        ));
  });

  test('requires every actor row cell before validating its values', () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('empty-actor-cells')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      <String>[
        'error concepta-profile/actor-active-interval actors.md',
        'error concepta-profile/actor-row-complete actors.md',
        'error concepta-profile/actor-side-value actors.md',
      ],
    );
  });

  test('requires the type registry before resolving used types', () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('missing-types')],
    );

    expect(result.exitCode, 1);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(
      findingSummary(profile),
      contains('error concepta-profile/type-registry-present types.md'),
    );
  });

  test('allows an actor-free bundle without an empty registry', () async {
    final result = await runProcess(
      <String>['validate', '--output', 'json', fixture('actor-free')],
    );

    expect(result.exitCode, 0);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    final profile = output['profile']! as Map<String, Object?>;
    expect(profile['state'], 'PASS');
    expect(
      findingSummary(profile),
      <String>[
        'advisory concepta-profile/generation-provenance-recommended profile.md',
        'advisory concepta-profile/generation-provenance-recommended types.md',
      ],
    );
  });
}
