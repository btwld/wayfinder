import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';

void main() {
  late Directory project;
  late List<ProjectBundle> bundles;
  Future<void> note(String path, String metadata) async {
    final file = File(p.join(project.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString('---\n$metadata\n---\nContent.\n');
  }

  Future<Map<String, Object?>> run(
    Map<String, Object?> query, {
    int limit = 100,
    int offset = 0,
  }) async => (await queryWayfinderBundles(
    bundles,
    WayfinderQuery.fromJson(query),
    limit: limit,
    offset: offset,
  )).toJson();
  List<Map<String, Object?>> rows(Map<String, Object?> result) =>
      (result['rows']! as List).cast<Map<String, Object?>>();
  Matcher code(String value) =>
      throwsA(isA<WayfinderException>().having((e) => e.code, 'code', value));

  setUp(() async {
    project = await Directory.systemTemp.createTemp('query-test-');
    bundles = [
      ProjectBundle(
        'knowledge',
        'knowledge',
        p.join(project.path, 'knowledge'),
      ),
    ];
    await note(
      'knowledge/a.md',
      'type: Research\ntitle: Alpha\ntags: [theology, reading]',
    );
    await note(
      'knowledge/nested/b.md',
      'type: Research\ntitle: Beta\nstatus: draft\ntags: [theology]',
    );
    await note(
      'knowledge/c.md',
      'type: Guide\ntitle: Gamma\nstatus: custom\ntags: [reading]',
    );
  });
  tearDown(() => project.delete(recursive: true));

  test('exact filters AND fields, OR values, every required tag', () async {
    final result = await run({
      'where': {
        'types': ['Research'],
        'tags': ['other', 'theology'],
        'required_tags': ['reading', 'theology'],
      },
    });
    expect(result['total'], 1);
    expect(rows(result).single['id'], 'a');
    expect(
      (await run({
        'where': {
          'tags': ['THEOLOGY'],
        },
      }))['total'],
      0,
    );
  });
  test(
    'raw status and effective status remain distinct; custom states survive',
    () async {
      final result = await run({
        'where': {
          'statuses': ['stable'],
        },
        'select': ['status', 'effective_status'],
      });
      expect(rows(result).single['values'], {
        'status': null,
        'effective_status': 'stable',
      });
      expect(
        (await run({
          'where': {
            'statuses': ['custom'],
          },
        }))['total'],
        1,
      );
    },
  );
  test(
    'literal text and hierarchical prefixes use existing search semantics',
    () async {
      expect(
        (await run({
          'where': {'title_contains': 'ALP'},
        }))['total'],
        1,
      );
      expect(
        (await run({
          'where': {'title_contains': 'A.*'},
        }))['total'],
        0,
      );
      expect(
        (await run({
          'where': {
            'path_prefixes': ['nested'],
          },
        }))['total'],
        1,
      );
      expect(
        (await run({
          'where': {
            'path_prefixes': ['nest'],
          },
        }))['total'],
        0,
      );
      expect(
        (await run({
          'where': {'description_contains': 'anything'},
        }))['total'],
        0,
      );
    },
  );
  test(
    'grouping counts the entire matching population before pagination',
    () async {
      final result = await run({'group_by': 'type'}, limit: 1);
      expect(result['total'], 3);
      expect(result['group_total'], 2);
      expect(result['has_more'], true);
      expect(result['groups'], [
        {'key': 'Guide', 'count': 1},
      ]);
      expect((await run({'group_by': 'type'}, offset: 1))['groups'], [
        {'key': 'Research', 'count': 2},
      ]);
    },
  );
  test(
    'sort is stable, missing last in both directions, totals precede pagination',
    () async {
      await note('knowledge/no-title.md', 'type: Guide');
      final spec = {
        'order_by': [
          {'field': 'title', 'direction': 'desc'},
        ],
      };
      final result = await run(spec, limit: 2);
      expect(rows(result).map((r) => r['id']), ['c', 'nested/b']);
      expect(result['total'], 4);
      expect(result['has_more'], true);
      expect(rows(await run(spec, offset: 3)).single['id'], 'no-title');
      expect((await run(spec, offset: 99))['returned'], 0);
    },
  );
  test('bundle identity disambiguates equal IDs and sorting ties', () async {
    await note('other/a.md', 'type: Research\ntitle: Alpha');
    bundles.add(ProjectBundle('other', 'other', p.join(project.path, 'other')));
    final result = await run({
      'where': {'title_contains': 'alpha'},
    });
    expect(rows(result).map((r) => [r['bundle'], r['id']]), [
      ['knowledge', 'a'],
      ['other', 'a'],
    ]);
  });
  test('default and tied orders compare IDs rather than filenames', () async {
    await note('knowledge/alpha.md', 'type: Guide\ntitle: Same');
    await note('knowledge/alpha-beta.md', 'type: Guide\ntitle: Same');
    for (final order in [
      <Map<String, Object?>>[],
      [
        {'field': 'title', 'direction': 'asc'},
      ],
    ]) {
      final result = await run({
        'where': {'title_contains': 'Same'},
        'order_by': order,
      });
      expect(rows(result).map((r) => r['id']), ['alpha', 'alpha-beta']);
    }
  });
  test(
    'queries reread sources, exclude reserved files/assets and preserve bytes',
    () async {
      await File(
        p.join(bundles.first.root, 'index.md'),
      ).writeAsString('# Index\n* [Alpha](a.md) - Research.\n');
      await File(
        p.join(bundles.first.root, 'raw.md.source'),
      ).writeAsString('original');
      final path = p.join(bundles.first.root, 'a.md');
      final before = await File(path).readAsBytes();
      expect((await run({}))['total'], 3);
      expect(await File(path).readAsBytes(), before);
      await note('knowledge/new.md', 'type: Reference');
      expect((await run({}))['total'], 4);
    },
  );
  test(
    'partial load refuses whole project instead of silently skipping',
    () async {
      await File(
        p.join(bundles.first.root, 'bad.md'),
      ).writeAsString('no frontmatter');
      await expectLater(run({}), throwsA(isA<WayfinderQueryRefused>()));
    },
  );
  test('cancellation stops before reading a bundle', () async {
    final cancel = WayfinderCancellationController()..cancel();
    await expectLater(
      queryWayfinderBundles(
        bundles,
        WayfinderQuery.fromJson({}),
        cancel: cancel,
      ),
      code('cancelled'),
    );
  });
  test('a concurrent writer cannot produce a silently complete view', () async {
    for (var i = 0; i < 100; i++) {
      await note('knowledge/load-$i.md', 'type: Research');
    }
    final source = File(p.join(bundles.first.root, 'a.md'));
    var writes = 0;
    final writer = Timer.periodic(const Duration(milliseconds: 1), (_) {
      writes++;
      source.writeAsStringSync(
        '---\ntype: Research\ntitle: Revision $writes\n---\n',
      );
    });
    try {
      await expectLater(
        run({}),
        throwsA(
          isA<WayfinderException>().having(
            (e) => e.code,
            'code',
            anyOf('query-source-changed', 'query-refused'),
          ),
        ),
      );
      expect(writes, greaterThan(0));
    } finally {
      writer.cancel();
    }
  });
  test(
    'definitions reject executable fields, invalid selectors and grouping combinations',
    () {
      for (final spec in <Map<String, Object?>>[
        {'sql': 'select *'},
        {'select': []},
        {
          'select': ['body'],
        },
        {
          'where': {
            'types': [' '],
          },
        },
        {
          'where': {'unknown': true},
        },
        {
          'order_by': [
            {'field': 'title', 'direction': 'wrong'},
          ],
        },
        {'group_by': 'tags'},
        {
          'group_by': 'type',
          'select': ['title'],
        },
        {
          'select': ['title', 'title'],
        },
        {
          'where': {'types': null},
        },
      ]) {
        expect(
          () => WayfinderQuery.fromJson(spec),
          throwsA(anyOf(isA<WayfinderException>(), isA<ArgumentError>())),
        );
      }
    },
  );
  test(
    'invalid pagination and duplicate bundle identities are rejected',
    () async {
      await expectLater(run({}, limit: 1001), code('query-invalid'));
      await expectLater(run({}, offset: -1), code('query-invalid'));
      bundles.add(bundles.first);
      await expectLater(run({}), code('query-invalid'));
    },
  );
  test('table cells escape delimiters, controls and HTML', () async {
    await note('knowledge/escape.md', 'type: Guide\ntitle: "A|<b>\\nC"');
    final result = await queryWayfinderBundles(
      bundles,
      WayfinderQuery.fromJson({}),
    );
    expect(result.toText(), contains('A&#124;&lt;b&gt;\\u{a}C'));
    expect(result.toText(), contains('more: false'));
  });
  test(
    'unselected alias metadata stays unexpanded; selected alias DAG is bounded',
    () async {
      final yaml = StringBuffer('type: Guide\ntitle: Alias test\n');
      yaml.writeln('a0: &a0 [leaf]');
      for (var level = 1; level <= 12; level++) {
        yaml.writeln(
          'a$level: &a$level [${List.filled(10, '*a${level - 1}').join(', ')}]',
        );
      }
      await note('knowledge/aliases.md', yaml.toString());
      expect((await run({}))['total'], 4);
      await note('knowledge/aliases.md', '${yaml}resource: *a12');
      expect(
        (await run({}))['total'],
        4,
        reason: 'unselected resource is not expanded',
      );
      await expectLater(
        run({
          'select': ['resource'],
        }),
        code('query-metadata-limit'),
      );
    },
  );
  test(
    'selected nested map keys cannot be silently coerced or collide',
    () async {
      await note(
        'knowledge/map.md',
        "type: Guide\nresource: {1: first, '1': second}",
      );
      expect((await run({}))['total'], 4);
      await expectLater(
        run({
          'select': ['resource'],
        }),
        code('query-metadata-invalid'),
      );
    },
  );
  test(
    'selected nonfinite numbers refuse instead of becoming JSON null',
    () async {
      await note('knowledge/nonfinite.md', 'type: Guide\nresource: .inf');
      await expectLater(
        run({
          'select': ['resource'],
        }),
        code('query-metadata-invalid'),
      );
    },
  );
  group('saved definitions', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory(
        p.join(project.path, '.wayfinder', 'queries'),
      ).create(recursive: true);
    });
    Future<File> save(String text) =>
        File(p.join(directory.path, 'reading.json')).writeAsString(text);
    Future<WayfinderQuery> load([String id = 'reading']) =>
        loadWayfinderSavedQuery(project, bundles, id);
    test('saved and inline results agree from a nested directory', () async {
      final spec = {
        'where': {
          'types': ['Research'],
        },
        'select': ['title'],
      };
      await save(jsonEncode({'format': 1, ...spec}));
      final nested = await Directory(p.join(project.path, 'working')).create();
      final saved = await loadWayfinderSavedQuery(nested, bundles, 'reading');
      expect(
        (await queryWayfinderBundles(bundles, saved)).toJson(),
        await run(spec),
      );
    });
    test(
      'malformed, duplicate (including escaped), unknown and oversized definitions refuse',
      () async {
        for (final source in [
          '{',
          '{"format":2}',
          '{"format":1,"format":1}',
          r'{"format":1,"where":{"types":[],"\u0074ypes":["Guide"]}}',
          '{"format":1,"command":"touch file"}',
          ' ' * 65537,
        ]) {
          await save(source);
          await expectLater(
            load(),
            throwsA(anyOf(isA<WayfinderException>(), isA<FormatException>())),
          );
        }
      },
    );
    test('IDs cannot escape the project', () async {
      for (final id in [
        '../secret',
        '/tmp/private',
        'UPPER',
        'a--b',
        '',
        'a' * 65,
      ]) {
        await expectLater(load(id), code('query-invalid'));
      }
    });
    test('file and directory symlinks cannot widen scope', () async {
      final outside = await Directory.systemTemp.createTemp('query-outside-');
      addTearDown(() => outside.delete(recursive: true));
      final target = await File(
        p.join(outside.path, 'secret.json'),
      ).writeAsString('{"format":1}');
      await Link(p.join(directory.path, 'reading.json')).create(target.path);
      await expectLater(load(), code('query-scope'));
      await directory.delete(recursive: true);
      await Link(directory.path).create(outside.path);
      await expectLater(load(), code('query-scope'));
    }, skip: Platform.isWindows ? 'POSIX symlink fixture' : false);
    test('saved definitions cannot be used for an external bundle', () async {
      await save('{"format":1}');
      await expectLater(
        loadWayfinderSavedQuery(project, [
          ProjectBundle('outside', 'outside', Directory.systemTemp.path),
        ], 'reading'),
        code('query-scope'),
      );
    });
  });
}
