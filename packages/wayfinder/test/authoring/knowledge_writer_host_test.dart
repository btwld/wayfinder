import 'dart:io';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/authoring.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

/// What a host's write pipeline relies on beside the write itself: the
/// content-change rule, the OKF delta, and the project files a plan's
/// selection came from.
final _now = DateTime.utc(2026, 10, 22, 9, 30);
const _agent = KnowledgeStamp.generated(by: 'claude-code/opus-5');
final _request = OkfConceptId('reporting/include-pdf-annotations');
final _analysis = OkfConceptId('reporting/pdf-export-feasibility');
final _labels = OkfConceptId('ways-of-working/relationship-labels');
final _contract = OkfConceptId('reporting/pagination-contract');

const _update = KnowledgeLogEntry(
  action: 'Update',
  description:
      'Revised [Include PDF annotations]'
      '(/reporting/include-pdf-annotations.md).',
);

CreateConcept _createContract() => CreateConcept(
  id: _contract,
  frontmatter: {
    'type': 'Specification',
    'title': 'Pagination contract',
    'description': 'How the renderer splits an export into pages.',
    'status': 'draft',
  },
  body: '# Specification\n\nThe renderer breaks pages at section bounds.\n',
);

void main() {
  late Directory temp;
  late String project;
  late String bundle;
  late WayfinderProfileResolver resolver;
  late KnowledgeWriter writer;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-authoring-host-');
    (:project, :bundle, :resolver) = await bitwildExample(temp);
    writer = KnowledgeWriter(resolver: resolver, clock: () => _now);
  });

  tearDown(() => temp.delete(recursive: true));

  String read(String path) => File(p.join(bundle, path)).readAsStringSync();

  OkfDocument concept(OkfConceptId id) =>
      OkfDocument.parse(read(id.documentPath));

  group('content changes', () {
    test('changesConceptContent follows the documented rule', () {
      final before = OkfDocument(
        frontmatter: {
          'type': 'Request',
          'title': 'Include PDF annotations',
          'description': 'Keep reviewer notes in exported PDFs.',
          'status': 'draft',
          'tags': ['reporting'],
        },
        body: '# Request\n\nKeep the notes.\n',
      );
      OkfDocument edited(Map<String, Object?> fields, {String? body}) =>
          before.copyWith(
            frontmatter: {...before.frontmatter, ...fields}
              ..removeWhere((key, value) => value == null),
            body: body,
          );

      expect(changesConceptContent(null, before), isTrue);
      expect(changesConceptContent(before, edited({})), isFalse);
      for (final key in ['type', 'title', 'description']) {
        expect(
          changesConceptContent(before, edited({key: 'Other'})),
          isTrue,
          reason: 'changing $key',
        );
        expect(
          changesConceptContent(before, edited({key: null})),
          isTrue,
          reason: 'removing $key',
        );
      }
      expect(
        changesConceptContent(
          before,
          edited({
            'status': 'deprecated',
            'tags': ['export'],
            'relationships': [
              {'relationship': 'related-to', 'resource': '/index.md'},
            ],
            'generated': {'by': 'human:chris', 'at': '2026-10-22T00:00:00Z'},
            'verified': {'by': 'human:chris', 'at': '2026-10-22T00:00:00Z'},
          }),
        ),
        isFalse,
      );
      expect(
        changesConceptContent(before, edited({}, body: 'Other.\n')),
        isTrue,
      );
      // What okf's serialization normalizes is no change.
      expect(
        changesConceptContent(
          before,
          edited({}, body: '# Request\r\n\r\nKeep the notes.'),
        ),
        isFalse,
      );
      // Values compare deeply.
      expect(
        changesConceptContent(
          OkfDocument(
            frontmatter: {
              'title': ['a', 'b'],
            },
          ),
          OkfDocument(
            frontmatter: {
              'title': ['a', 'b'],
            },
          ),
        ),
        isFalse,
      );
    });

    test('UpdateConcept.changesContent and the plan decide as the rule, and '
        'only a content change restamps generated', () async {
      final current = concept(_request);
      final cases = {
        UpdateConcept(
          id: _request,
          frontmatter: {
            'tags': ['reporting'],
          },
        ): false,
        UpdateConcept(
          id: _request,
          frontmatter: {'title': current.frontmatter['title']},
        ): false,
        UpdateConcept(id: _request, body: current.body): false,
        UpdateConcept(
          id: _request,
          frontmatter: {'description': 'Keep reviewer notes in every PDF.'},
        ): true,
        UpdateConcept(id: _request, body: '${current.body}\nMore.\n'): true,
      };
      for (final MapEntry(key: update, value: changes) in cases.entries) {
        expect(
          update.changesContent(current),
          changes,
          reason: '${update.frontmatter} ${update.body}',
        );
        final plan = await writer.prepare(
          bundle,
          update,
          stamp: _agent,
          logEntry: KnowledgeLog.none,
        );
        expect(plan.changesContent, changes);
        final written = plan.diff
            .where((file) => file.path == _request.documentPath)
            .map((file) => OkfDocument.parse(file.after).frontmatter);
        expect(
          written.map((frontmatter) => frontmatter['generated']),
          everyElement(
            changes
                ? {'by': 'claude-code/opus-5', 'at': '2026-10-22T09:30:00Z'}
                : current.frontmatter['generated'],
          ),
        );
      }

      Future<bool> changesContent(KnowledgeChange change) async =>
          (await writer.prepare(bundle, change, stamp: _agent)).changesContent;
      expect(await changesContent(_createContract()), isTrue);
      expect(
        await changesContent(
          LinkConcepts(
            source: _request,
            relationship: KnowledgeRelationship.toConcept(
              relationship: 'related-to',
              target: _labels,
            ),
          ),
        ),
        isFalse,
      );
      expect(await changesContent(DeprecateConcept(id: _analysis)), isFalse);
      expect(await changesContent(const RegenerateIndexes()), isFalse);
    });

    test(
      'KnowledgeContentLog records its entry only for a content change',
      () async {
        final log = read('log.md');
        final tags = await writer.prepare(
          bundle,
          UpdateConcept(
            id: _request,
            frontmatter: {
              'tags': ['reporting'],
            },
          ),
          stamp: _agent,
          logEntry: const KnowledgeContentLog(_update),
        );
        expect(tags.changesContent, isFalse);
        expect(tags.changedPaths, isNot(contains('log.md')));
        await writer.commit(tags);
        expect(read('log.md'), log);

        final deprecation = await writer.prepare(
          bundle,
          DeprecateConcept(id: _analysis, note: 'Superseded.'),
          stamp: _agent,
          logEntry: const KnowledgeContentLog(KnowledgeLog.lifecycle),
        );
        expect(deprecation.changedPaths, isNot(contains('log.md')));

        final description = await writer.prepare(
          bundle,
          UpdateConcept(
            id: _request,
            frontmatter: {'description': 'Keep reviewer notes in every PDF.'},
          ),
          stamp: _agent,
          logEntry: const KnowledgeContentLog(_update),
        );
        expect(description.changesContent, isTrue);
        expect(description.committable, isTrue);
        await writer.commit(description);
        expect(
          read('log.md'),
          log.replaceFirst(
            '## 2026-10-02',
            '## 2026-10-22\n'
                '* **Update**: Revised [Include PDF annotations]'
                '(/reporting/include-pdf-annotations.md).\n\n'
                '## 2026-10-02',
          ),
        );

        for (final invalid in const [
          KnowledgeContentLog(KnowledgeLog.none),
          KnowledgeContentLog(KnowledgeContentLog(_update)),
        ]) {
          await expectLater(
            writer.prepare(
              bundle,
              UpdateConcept(id: _request),
              stamp: _agent,
              logEntry: invalid,
            ),
            throwsArgumentError,
          );
        }
      },
    );
  });

  test('the plan lists the OKF findings the candidate introduces apart from '
      'those the bundle already has, beside the whole OKF result', () async {
    // A concept the bundle already holds without its type.
    final analysis = File(p.join(bundle, _analysis.documentPath));
    final document = OkfDocument.parse(await analysis.readAsString());
    await analysis.writeAsString(
      document
          .copyWith(frontmatter: {...document.frontmatter}..remove('type'))
          .serialize(),
    );
    String describe(OkfFinding finding) =>
        '${finding.id.value} ${finding.location?.path}';

    final breaking = await writer.prepare(
      bundle,
      UpdateConcept(id: _request, frontmatter: {'type': null}),
      stamp: _agent,
    );
    expect(breaking.okf.report.findings.map(describe), [
      'okf/missing-type ${_request.documentPath}',
      'okf/missing-type ${_analysis.documentPath}',
    ]);
    expect(breaking.introducedOkf.map(describe), [
      'okf/missing-type ${_request.documentPath}',
    ]);
    expect(breaking.preExistingOkf.map(describe), [
      'okf/missing-type ${_analysis.documentPath}',
    ]);
    expect(breaking.committable, isFalse);

    final harmless = await writer.prepare(
      bundle,
      UpdateConcept(
        id: _request,
        frontmatter: {
          'tags': ['reporting'],
        },
      ),
      stamp: _agent,
    );
    expect(harmless.introducedOkf, isEmpty);
    expect(harmless.preExistingOkf.map(describe), [
      'okf/missing-type ${_analysis.documentPath}',
    ]);
    // The OKF gate is still the whole candidate.
    expect(harmless.committable, isFalse);
  });

  group('project files', () {
    late String config;
    late String lock;

    setUp(() {
      config = p.join(project, 'wayfinder.json');
      lock = p.join(project, 'wayfinder.lock');
    });

    test('a plan judged without a Profile is refused when the lock its '
        'selection lacked appears before commit', () async {
      final locked = await File(lock).readAsBytes();
      await File(lock).delete();
      final plan = await writer.prepare(
        bundle,
        _createContract(),
        stamp: _agent,
      );
      expect(plan.selection, isA<UnselectedProfile>());
      expect(plan.projectFiles.sha256.keys, [config, lock]);
      expect(plan.projectFiles.sha256[lock], isNull);
      expect(plan.committable, isTrue);

      await File(lock).writeAsBytes(locked);
      await expectLater(
        writer.commit(plan),
        throwsA(
          isA<KnowledgeStaleWriteException>()
              .having((error) => error.code, 'code', 'write-stale')
              .having((error) => error.projectFiles, 'projectFiles', [lock]),
        ),
      );
      expect(
        File(p.join(bundle, _contract.documentPath)).existsSync(),
        isFalse,
      );
    });

    test("a host's unselected Profile tracks the configuration its reason "
        'names', () async {
      await File(lock).delete();
      final selection = await resolver.select(bundle, projectRoot: project);
      expect(selection, isA<UnselectedProfile>());
      final plan = await writer.prepare(
        bundle,
        _createContract(),
        stamp: _agent,
        selection: selection,
      );
      expect(plan.projectFiles.sha256.keys, [config, lock]);
      await File(
        config,
      ).writeAsString('${await File(config).readAsString()}\n');
      await expectLater(
        writer.commit(plan),
        throwsA(
          isA<KnowledgeStaleWriteException>().having(
            (error) => error.projectFiles,
            'projectFiles',
            [config],
          ),
        ),
      );
    });

    test('project files a host captured before selecting refuse a change '
        'that landed between its selection and prepare', () async {
      final files = await KnowledgeProjectFiles.forBundle(
        bundle,
        projectRoot: project,
      );
      expect(files.sha256.keys, [config, lock]);
      final selection = await resolver.select(bundle, projectRoot: project);
      // Another writer edits the configuration after the host selected.
      await File(
        config,
      ).writeAsString('${await File(config).readAsString()}\n');
      final plan = await writer.prepare(
        bundle,
        _createContract(),
        stamp: _agent,
        selection: selection,
        projectFiles: files,
      );
      expect(plan.projectFiles, same(files));
      await expectLater(
        writer.commit(plan),
        throwsA(
          isA<KnowledgeStaleWriteException>().having(
            (error) => error.projectFiles,
            'projectFiles',
            [config],
          ),
        ),
      );
      expect(
        File(p.join(bundle, _contract.documentPath)).existsSync(),
        isFalse,
      );
    });

    test('a configuration that appears closer to the bundle than the one '
        'that bound it makes the plan stale', () async {
      // The bundle moves one level down, and a host relocks the edit that
      // binds it there.
      final nested = p.join(project, 'sub', 'knowledge');
      await copyDirectory(bundle, nested);
      await resolver.relock(
        project,
        edit: (text) => text.replaceFirst('"./knowledge"', '"./sub/knowledge"'),
      );
      final closer = p.join(project, 'sub', 'wayfinder.json');
      final tracked = [closer, config, lock];

      final bound = await KnowledgeProjectFiles.forBundle(
        nested,
        projectRoot: project,
      );
      expect(bound.sha256.keys, tracked);
      expect(bound.sha256[closer], isNull);
      // A configuration a host names is tracked alone with its lock.
      expect(
        (await KnowledgeProjectFiles.forBundle(
          nested,
          configPath: config,
          projectRoot: project,
        )).sha256.keys,
        [config, lock],
      );

      final selection = await resolver.select(nested, projectRoot: project);
      expect(selection, isA<SelectedProfile>());
      final plans = [
        await writer.prepare(
          nested,
          _createContract(),
          stamp: _agent,
          projectRoot: project,
        ),
        await writer.prepare(
          nested,
          _createContract(),
          stamp: _agent,
          selection: selection,
          projectRoot: project,
        ),
      ];
      for (final plan in plans) {
        expect(plan.assessed, isTrue);
        expect(plan.projectFiles.sha256.keys, tracked);
      }

      await File(closer).writeAsString(await File(config).readAsString());
      for (final plan in plans) {
        await expectLater(
          writer.commit(plan),
          throwsA(
            isA<KnowledgeStaleWriteException>().having(
              (error) => error.projectFiles,
              'projectFiles',
              [closer],
            ),
          ),
        );
      }
      expect(
        File(p.join(nested, _contract.documentPath)).existsSync(),
        isFalse,
      );
    });

    test('the default constructor makes each path absolute when it is '
        'built', () async {
      final digest = KnowledgeProjectFiles.digest(
        await File(config).readAsBytes(),
      );
      final files = KnowledgeProjectFiles({
        p.relative(config): digest,
        p.join(project, 'sub', '..', 'wayfinder.lock'): null,
      });
      expect(files.sha256, {config: digest, lock: null});
      expect(
        () => KnowledgeProjectFiles({
          config: digest,
          p.join(project, '.', 'wayfinder.json'): null,
        }),
        throwsArgumentError,
      );
    });

    test('digests a host read itself are checked the same way', () async {
      final files = KnowledgeProjectFiles({
        config: KnowledgeProjectFiles.digest(await File(config).readAsBytes()),
        lock: KnowledgeProjectFiles.digest(await File(lock).readAsBytes()),
      });
      expect(files.sha256, (await KnowledgeProjectFiles.read(config)).sha256);
      final plan = await writer.prepare(
        bundle,
        _createContract(),
        stamp: _agent,
        selection: await resolver.select(bundle, projectRoot: project),
        projectFiles: files,
      );
      expect(
        (await writer.commit(plan)).changedPaths,
        contains(_contract.documentPath),
      );
    });

    test(
      'a bundle no configuration binds tracks each configuration path '
      'binding looked at, so one that appears makes the plan stale',
      () async {
        final root = p.join(temp.path, 'plain');
        final plain = p.join(root, 'knowledge');
        await copyDirectory(bundle, plain);
        final plan = await writer.prepare(
          plain,
          _createContract(),
          stamp: _agent,
          projectRoot: root,
        );
        expect(plan.assessed, isFalse);
        final candidate = p.join(root, 'wayfinder.json');
        expect(plan.projectFiles.sha256, {candidate: null});

        await File(candidate).writeAsString(await File(config).readAsString());
        await expectLater(
          writer.commit(plan),
          throwsA(
            isA<KnowledgeStaleWriteException>().having(
              (error) => error.projectFiles,
              'projectFiles',
              [candidate],
            ),
          ),
        );
        expect(
          File(p.join(plain, _contract.documentPath)).existsSync(),
          isFalse,
        );
      },
    );
  });
}
