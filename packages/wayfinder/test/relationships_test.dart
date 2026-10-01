import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/profile_release.dart';
import 'package:wayfinder/src/rules/catalog.dart';
import 'package:wayfinder/src/rules/evaluate.dart';
import 'package:wayfinder/src/rules/facts.dart';
import 'package:wayfinder/src/rules/profile.dart';

void main() {
  late Directory bundle;

  setUp(() async {
    bundle = await Directory.systemTemp.createTemp('wayfinder-relationships-');
  });

  tearDown(() => bundle.delete(recursive: true));

  Future<void> write(String path, String text) async {
    final file = File(p.joinAll([bundle.path, ...p.posix.split(path)]));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<BundleFacts> project() async {
    final loaded = await const OkfBundleLoader().inspect(bundle.path);
    return BundleFacts.project(
      loaded,
      profile: EffectiveProfile(
        RuleCatalog.installed(builtinProfileId, externalProfileRelease),
        Vocabulary(
          standardTypes: const [],
          types: const ['Guide'],
          tags: const [],
          relationships: externalStandardRelationships
              .map((row) => row.$1)
              .toList(),
          actors: const [],
        ),
      ),
    );
  }

  Map<String, Object?> concept(BundleFacts facts, String path) => facts
      .of(SubjectKind.concept)
      .singleWhere((subject) => subject.locations['self'] == path)
      .facts;

  test(
    'relationship targets resolve exactly as okf resolves body links',
    () async {
      const targets = [
        '/area/note.md',
        'note.md',
        '../root.md',
        '../../outside.md',
        '/area/missing.md',
        'missing.md',
        '/area/asset.pdf',
        '/area',
        'https://example.test/spec',
        'mailto:team@example.test',
        '#heading',
        'note.md#heading',
        '%E2%9C%93.md',
      ];
      await write('root.md', '---\ntype: Guide\n---\n');
      await write('area/note.md', '---\ntype: Guide\n---\n');
      await write('area/✓.md', '---\ntype: Guide\n---\n');
      await write('area/asset.pdf', 'pdf');
      await write(
        'area/source.md',
        [
          '---',
          'type: Guide',
          'relationships:',
          for (final target in targets)
            '  - {relationship: related-to, resource: ${jsonEncode(target)}}',
          '---',
          '',
          for (final target in targets) '[link]($target)',
        ].join('\n'),
      );

      final facts = concept(await project(), 'area/source.md');
      final links = {
        for (final edge
            in (facts['edges']! as List<Object?>).cast<Map<String, Object?>>())
          if (edge['origin'] == 'body') edge['target']: edge,
      };
      final relationships = facts['relationships']! as List<Object?>;
      expect(relationships, hasLength(targets.length));
      for (final (index, target) in targets.indexed) {
        final link = links[target];
        expect(link, isNotNull, reason: 'okf drew no body edge for $target');
        final relationship = relationships[index]! as Map<String, Object?>;
        expect(relationship['resource'], target);
        expect(relationship['relationship'], 'related-to');
        for (final key in ['internal', 'bundle_relative']) {
          expect(relationship[key], link![key], reason: '$key of $target');
        }
        expect(
          relationship['resolved'],
          ['resolved-concept', 'resolved-asset'].contains(link!['resolution']),
          reason: 'resolved of $target',
        );
      }
    },
  );

  test('a relationships value that is not a list fails whole', () async {
    await write(
      'scalar.md',
      '---\ntype: Guide\nrelationships: depends-on /a.md\n---\n',
    );
    await write(
      'mapping.md',
      '---\ntype: Guide\n'
          'relationships: {relationship: depends-on, resource: /scalar.md}\n'
          '---\n',
    );
    await write('empty.md', '---\ntype: Guide\nrelationships:\n---\n');
    await write(
      'mixed.md',
      '---\ntype: Guide\nrelationships:\n'
          '  - {relationship: depends-on, resource: /scalar.md}\n'
          '  - depends-on\n'
          '  - {relationship: inspired-by, resource: /scalar.md}\n'
          '---\n',
    );
    final facts = await project();
    final shape = {
      for (final finding in evaluate(facts.profile, facts).findings)
        if (finding.id == 'concepta-profile/relationship-shape')
          finding.path: finding.message,
    };
    expect(
      shape.keys,
      unorderedEquals(['scalar.md', 'mapping.md', 'mixed.md']),
    );
    expect(shape['scalar.md'], endsWith('found depends-on /a.md.'));
    expect(
      shape['mapping.md'],
      endsWith('found {relationship: depends-on, resource: /scalar.md}.'),
    );
    expect(
      shape['mixed.md'],
      endsWith(
        'found depends-on, {relationship: inspired-by, resource: /scalar.md}.',
      ),
    );
  });

  test('load rejects a declared frontmatter key OKF already defines', () {
    final catalog = jsonDecode(
      jsonEncode({
        'format': 1,
        'namespace': 'x',
        'profile': {'id': 'x', 'release': '2026.1'},
        'frontmatter_keys': {'sources': 'Provenance, again.'},
        'rules': <Object?>[],
      }),
    );
    expect(
      () => RuleCatalog.parse(jsonEncode(catalog)),
      throwsA(
        isA<RuleCatalogException>()
            .having((error) => error.where, 'where', 'frontmatter_keys.sources')
            .having(
              (error) => error.message,
              'message',
              contains('OKF frontmatter key'),
            ),
      ),
    );
    expect(
      RuleCatalog.installed(
        builtinProfileId,
        externalProfileRelease,
      ).frontmatterKeys.keys,
      ['relationships'],
    );
  });
}
