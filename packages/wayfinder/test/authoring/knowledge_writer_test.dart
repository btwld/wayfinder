import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/authoring.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

import '../project/support.dart';
import 'support.dart';

final _now = DateTime.utc(2026, 10, 22, 9, 30);
const _agent = KnowledgeStamp.generated(by: 'claude-code/opus-5');
final _contract = OkfConceptId('reporting/pagination-contract');
final _request = OkfConceptId('reporting/include-pdf-annotations');
final _analysis = OkfConceptId('reporting/pdf-export-feasibility');
final _labels = OkfConceptId('ways-of-working/relationship-labels');

CreateConcept _createContract() => CreateConcept(
  id: _contract,
  frontmatter: {
    'type': 'Specification',
    'title': 'Pagination contract',
    'description': 'How the renderer splits an export into pages.',
    'status': 'draft',
    'tags': ['reporting', 'export'],
  },
  body: '# Specification\n\nThe renderer breaks pages at section bounds.\n',
);

const _creation = KnowledgeLogEntry(
  action: 'Creation',
  description:
      'Recorded [Pagination contract](/reporting/pagination-contract.md).',
);

void main() {
  late Directory temp;
  late String project;
  late String bundle;
  late WayfinderProfileResolver resolver;
  late KnowledgeWriter writer;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-authoring-');
    (:project, :bundle, :resolver) = await bitwildExample(temp);
    writer = KnowledgeWriter(resolver: resolver, clock: () => _now);
  });

  tearDown(() => temp.delete(recursive: true));

  Future<ProfileValidationResult> validate() =>
      validateWithProfileSources(bundle, resolver: resolver);

  String read(String path) => File(p.join(bundle, path)).readAsStringSync();

  OkfDocument concept(OkfConceptId id) =>
      OkfDocument.parse(read(id.documentPath));

  /// Prepares and commits [change], checks the plan judged the bundle
  /// `validate` then reads, and returns what was written.
  Future<List<String>> write(
    KnowledgeChange change, {
    KnowledgeStamp stamp = _agent,
    KnowledgeLog log = KnowledgeLog.lifecycle,
  }) async {
    final plan = await writer.prepare(
      bundle,
      change,
      stamp: stamp,
      logEntry: log,
    );
    expect(plan.introduced, isEmpty);
    expect(plan.committable, isTrue);
    final result = await writer.commit(plan);
    expect(result.changedPaths, plan.changedPaths);
    final after = await validate();
    expect(after.gate, GateState.pass, reason: after.toTextLines().join('\n'));
    expect(plan.candidate.toJson(), after.toJson());
    return result.changedPaths;
  }

  test('create, update, link and deprecate each commit a bundle validate '
      'passes', () async {
    expect((await validate()).gate, GateState.pass);

    expect(await write(_createContract(), log: _creation), [
      'index.md',
      'log.md',
      'reporting/index.md',
      'reporting/pagination-contract.md',
    ]);
    expect(concept(_contract).frontmatter['generated'], {
      'by': 'claude-code/opus-5',
      'at': '2026-10-22T09:30:00Z',
    });
    expect(read('reporting/index.md'), contains('[Pagination contract]'));

    final reviewed = DateTime.utc(2026, 10, 23, 8);
    expect(
      await write(
        UpdateConcept(
          id: _contract,
          frontmatter: {
            'description':
                'How the renderer splits an export into pages.'
                ' Applies until 1 November 2026.',
          },
        ),
        stamp: KnowledgeStamp.verified(by: 'human:chris', at: reviewed),
        log: const KnowledgeLogEntry(
          action: 'Update',
          description:
              'Dated [Pagination contract](/reporting/pagination-contract.md).',
        ),
      ),
      ['log.md', 'reporting/index.md', 'reporting/pagination-contract.md'],
    );
    final updated = concept(_contract).frontmatter;
    expect(updated['generated'], {
      'by': 'human:chris',
      'at': '2026-10-23T08:00:00Z',
    });
    expect(updated['verified'], {
      'by': 'human:chris',
      'at': '2026-10-23T08:00:00Z',
    });

    final generated = concept(_request).frontmatter['generated'];
    expect(
      await write(
        LinkConcepts(
          source: _request,
          relationship: KnowledgeRelationship.toConcept(
            relationship: 'related-to',
            target: _labels,
          ),
        ),
        log: KnowledgeLog.none,
      ),
      ['reporting/include-pdf-annotations.md'],
    );
    final linked = concept(_request).frontmatter;
    expect((linked['relationships'] as List).last, {
      'relationship': 'related-to',
      'resource': '/ways-of-working/relationship-labels.md',
    });
    expect(linked['generated'], generated);

    expect(
      await write(
        DeprecateConcept(
          id: _contract,
          relationships: [
            KnowledgeRelationship.toConcept(
              relationship: 'superseded-by',
              target: _analysis,
            ),
          ],
        ),
        log: const KnowledgeLogEntry(
          action: 'Deprecation',
          description:
              'Replaced [Pagination contract](/reporting/pagination-contract.md).',
        ),
      ),
      ['log.md', 'reporting/pagination-contract.md'],
    );
    final deprecated = concept(_contract).frontmatter;
    expect(deprecated['status'], 'deprecated');
    expect(deprecated['relationships'], [
      {
        'relationship': 'superseded-by',
        'resource': '/reporting/pdf-export-feasibility.md',
      },
    ]);
    expect(deprecated['generated'], updated['generated']);
  });

  test('a link already present, or a write that changes nothing, writes '
      'nothing and records no entry', () async {
    final plan = await writer.prepare(
      bundle,
      LinkConcepts(
        source: _request,
        relationship: const KnowledgeRelationship(
          relationship: 'assessed-by',
          resource: '/reporting/pdf-export-feasibility.md',
        ),
      ),
      stamp: _agent,
      logEntry: _creation,
    );
    expect(plan.diff, isEmpty);
    expect(plan.committable, isTrue);
    expect((await writer.commit(plan)).changedPaths, isEmpty);
    expect(await _status(project), isEmpty);
  });

  test('a supplied log entry is written exactly as given, keeping every '
      'authored byte', () async {
    final before = read('log.md');
    await write(_createContract(), log: _creation);
    final created =
        '## 2026-10-22\n'
        '* **Creation**: Recorded [Pagination contract]'
        '(/reporting/pagination-contract.md).\n\n';
    expect(
      read('log.md'),
      before.replaceFirst('## 2026-10-02', '$created## 2026-10-02'),
    );

    await write(
      UpdateConcept(id: _contract, body: '# Specification\n\nRevised.\n'),
      log: const KnowledgeLogEntry(
        action: 'Update',
        description: 'Revised the contract.',
      ),
    );
    expect(
      read('log.md'),
      before.replaceFirst(
        '## 2026-10-02',
        '## 2026-10-22\n'
            '* **Update**: Revised the contract.\n'
            '* **Creation**: Recorded [Pagination contract]'
            '(/reporting/pagination-contract.md).\n\n'
            '## 2026-10-02',
      ),
    );
  });

  test("okf's lifecycle entry joins the authored log in its own style, and "
      'none records nothing', () async {
    final before = read('log.md');
    await write(_createContract());
    expect(
      read('log.md'),
      before.replaceFirst(
        '## 2026-10-02',
        '## 2026-10-22\n'
            '* **Created**: [Pagination contract]'
            '(reporting/pagination-contract.md)\n\n'
            '## 2026-10-02',
      ),
    );

    final logged = read('log.md');
    expect(
      await write(
        UpdateConcept(id: _contract, body: '# Specification\n\nRevised.\n'),
        log: KnowledgeLog.none,
      ),
      ['reporting/pagination-contract.md'],
    );
    expect(read('log.md'), logged);
  });

  test('a log entry dated within the history, or written to a CRLF log, '
      'keeps every authored byte; a malformed log is not rewritten', () async {
    final before = read('log.md');
    final created =
        '* **Creation**: Recorded [Pagination contract]'
        '(/reporting/pagination-contract.md).';
    Future<String> createOn(DateTime day) async {
      final plan = await KnowledgeWriter(
        resolver: resolver,
        clock: () => day,
      ).prepare(bundle, _createContract(), stamp: _agent, logEntry: _creation);
      return plan.diff.singleWhere((file) => file.path == 'log.md').after;
    }

    expect(
      await createOn(DateTime.utc(2026, 8, 15)),
      before.replaceFirst(
        '## 2026-07-31',
        '## 2026-08-15\n$created\n\n## 2026-07-31',
      ),
    );
    expect(
      await createOn(DateTime.utc(2026, 7, 31)),
      before.replaceFirst('## 2026-07-31\n', '## 2026-07-31\n$created\n'),
    );
    expect(
      await createOn(DateTime.utc(2026, 7, 1)),
      '$before\n## 2026-07-01\n$created\n',
    );

    final log = File(p.join(bundle, 'log.md'));
    await log.writeAsString(before.replaceAll('\n', '\r\n'));
    expect(
      await createOn(_now),
      before
          .replaceFirst(
            '## 2026-10-02',
            '## 2026-10-22\n$created\n\n## 2026-10-02',
          )
          .replaceAll('\n', '\r\n'),
    );

    // okf reads a log without a dated section as malformed.
    await log.writeAsString('# Knowledge Log\n');
    await expectLater(
      createOn(_now),
      throwsA(
        isA<KnowledgeChangeException>().having(
          (error) => error.code,
          'code',
          'log-unwritable',
        ),
      ),
    );
  });

  test('a log entry the log cannot hold as given is refused before any '
      'work', () async {
    for (final entry in const [
      KnowledgeLogEntry(action: 'Creation', description: 'Two\nlines'),
      KnowledgeLogEntry(action: ' Creation', description: 'Padded'),
      KnowledgeLogEntry(action: 'A**: B', description: 'Ambiguous'),
      KnowledgeLogEntry(action: 'Creation', description: ''),
    ]) {
      await expectLater(
        writer.prepare(
          bundle,
          _createContract(),
          stamp: _agent,
          logEntry: entry,
        ),
        throwsArgumentError,
      );
    }
  });

  test('a write that adds a Profile error is refused and leaves git diff '
      'clean', () async {
    final plan = await writer.prepare(
      bundle,
      _createContract(),
      stamp: const KnowledgeStamp.generated(by: 'claude-code/opus-9'),
      logEntry: _creation,
    );
    expect(plan.okf.isConformant, isTrue);
    expect(plan.committable, isFalse);
    expect(plan.introduced.map((finding) => '${finding.id} ${finding.path}'), [
      'bitwild-profile/used-actor-registered '
          'reporting/pagination-contract.md',
    ]);
    expect(plan.candidate.gate, GateState.fail);
    expect(plan.base.gate, GateState.pass);
    await expectLater(
      writer.commit(plan),
      throwsA(
        isA<KnowledgeWriteRefusedException>()
            .having((error) => error.code, 'code', 'write-refused')
            .having(
              (error) => error.message,
              'message',
              contains('bitwild-profile/used-actor-registered'),
            ),
      ),
    );
    expect(
      (await Process.run('git', [
        'diff',
        '--exit-code',
      ], workingDirectory: project)).exitCode,
      0,
    );
    expect(await _status(project), isEmpty);
  });

  test('a write okf refuses is refused, and names the path', () async {
    final plan = await writer.prepare(
      bundle,
      UpdateConcept(id: _request, frontmatter: {'type': null}),
      stamp: _agent,
    );
    expect(plan.okf.isConformant, isFalse);
    expect(plan.committable, isFalse);
    expect(plan.candidate.profileState, ProfileState.blockedByOkf);
    await expectLater(
      writer.commit(plan),
      throwsA(
        isA<KnowledgeWriteRefusedException>().having(
          (error) => error.message,
          'message',
          contains('reporting/include-pdf-annotations.md'),
        ),
      ),
    );
    expect(await _status(project), isEmpty);
  });

  test('an error the bundle already reports does not refuse a write, and '
      'an unrelated stale index is not rewritten', () async {
    final stale = File(p.join(bundle, 'ways-of-working', 'index.md'));
    await stale.writeAsString(
      (await stale.readAsString()).replaceFirst(
        "Project relationship labels used beyond the Profile's preferred "
            'vocabulary.',
        'Hand-edited description.',
      ),
    );
    await commitAll(project, 'Stale index');
    final staleBytes = await stale.readAsBytes();
    final baseline = await validate();
    expect(
      baseline.findings.map((finding) => '${finding.id} ${finding.path}'),
      ['bitwild-profile/index-current ways-of-working/index.md'],
    );

    final plan = await writer.prepare(
      bundle,
      _createContract(),
      stamp: _agent,
      logEntry: _creation,
    );
    expect(plan.changedPaths, [
      'index.md',
      'log.md',
      'reporting/index.md',
      'reporting/pagination-contract.md',
    ]);
    expect(plan.introduced, isEmpty);
    expect(plan.preExisting.map((finding) => '${finding.id} ${finding.path}'), [
      'bitwild-profile/index-current ways-of-working/index.md',
    ]);
    expect(plan.committable, isTrue);
    await writer.commit(plan);
    expect(await stale.readAsBytes(), staleBytes);
    final after = await validate();
    expect(after.findings.map((finding) => finding.path), [
      'ways-of-working/index.md',
    ]);
    expect(plan.candidate.toJson(), after.toJson());
  });

  test('Regenerate writes byte for byte what validate --fix writes', () async {
    final other = await Directory(p.join(temp.path, 'other')).create();
    final fixed = await bitwildExample(other);
    for (final root in [bundle, fixed.bundle]) {
      await File(p.join(root, 'reporting', 'index.md')).delete();
      final index = File(p.join(root, 'ways-of-working', 'index.md'));
      await index.writeAsString(
        (await index.readAsString()).replaceFirst('Project', 'Old'),
      );
    }

    final plan = await writer.prepare(
      bundle,
      const RegenerateIndexes(),
      stamp: _agent,
    );
    expect(plan.changedPaths, [
      'reporting/index.md',
      'ways-of-working/index.md',
    ]);
    expect(plan.committable, isTrue);
    expect(plan.candidate.gate, GateState.pass);
    await writer.commit(plan);

    final fix = await validateWithProfileSources(
      fixed.bundle,
      resolver: fixed.resolver,
      fix: true,
    );
    expect(fix.fixed, plan.changedPaths);
    expect(await _files(bundle), await _files(fixed.bundle));
    expect((await validate()).gate, GateState.pass);
  });

  test(
    'Regenerate on a current bundle writes nothing and takes no lock',
    () async {
      final plan = await writer.prepare(
        bundle,
        const RegenerateIndexes(),
        stamp: _agent,
        logEntry: _creation,
      );
      expect(plan.diff, isEmpty);
      expect((await writer.commit(plan)).changedPaths, isEmpty);
      expect(await _status(project), isEmpty);
    },
  );

  test('Regenerate without a fixable rule is not applied', () async {
    final selection = SelectedProfile(
      EffectiveProfile.compose([
        ProfilePackage.parse(
          '{"format": 2, "id": "plain", "release": "1", '
          '"implements": {"id": "okf", "release": "0.2"}, "rules": []}',
        ),
      ]),
    );
    await expectLater(
      writer.prepare(
        bundle,
        const RegenerateIndexes(),
        stamp: _agent,
        selection: selection,
      ),
      throwsA(
        isA<KnowledgeChangeException>().having(
          (error) => error.code,
          'code',
          'fix-not-applied',
        ),
      ),
    );
  });

  test(
    'a plan whose bundle changed after prepare is refused at commit',
    () async {
      final plan = await writer.prepare(
        bundle,
        _createContract(),
        stamp: _agent,
        logEntry: _creation,
      );
      final labels = File(p.join(bundle, _labels.documentPath));
      await labels.writeAsString('${await labels.readAsString()}\nMore.\n');
      await expectLater(
        writer.commit(plan),
        throwsA(
          isA<KnowledgeStaleWriteException>().having(
            (error) => error.code,
            'code',
            'write-stale',
          ),
        ),
      );
      expect(
        File(p.join(bundle, _contract.documentPath)).existsSync(),
        isFalse,
      );
      // The commit took okf's lock before it found the bundle changed.
      expect(await _status(project), [
        ' M knowledge/${_labels.documentPath}',
        '?? knowledge/$okfBundleLockFileName',
      ]);
    },
  );

  test('a plan whose configuration changed after prepare is refused at '
      'commit', () async {
    final plan = await writer.prepare(bundle, _createContract(), stamp: _agent);
    final config = File(p.join(project, 'wayfinder.json'));
    await config.writeAsString('${await config.readAsString()}\n');
    await expectLater(
      writer.commit(plan),
      throwsA(isA<KnowledgeStaleWriteException>()),
    );
    expect(File(p.join(bundle, _contract.documentPath)).existsSync(), isFalse);
  });

  test('a plan commits once', () async {
    final plan = await writer.prepare(bundle, _createContract(), stamp: _agent);
    await writer.commit(plan);
    await expectLater(writer.commit(plan), throwsStateError);
  });

  test('generated is restamped only when content changes, and verified '
      'appends an event', () async {
    final generated = concept(_request).frontmatter['generated'];
    await write(
      UpdateConcept(
        id: _request,
        frontmatter: {
          'tags': ['reporting'],
        },
      ),
      stamp: const KnowledgeStamp.generated(by: 'human:chris'),
      log: KnowledgeLog.none,
    );
    expect(concept(_request).frontmatter['generated'], generated);

    await write(
      UpdateConcept(id: _request),
      stamp: KnowledgeStamp.verified(
        by: 'claude-code/opus-5',
        at: DateTime.utc(2026, 10, 24),
      ),
      log: KnowledgeLog.none,
    );
    final verified = concept(_request).frontmatter;
    expect(verified['generated'], generated);
    expect(verified['verified'], [
      {'by': 'human:chris', 'at': '2026-07-31T09:00:00Z'},
      {'by': 'claude-code/opus-5', 'at': '2026-10-24T00:00:00Z'},
    ]);
  });

  test('a change that names a stamped field, or describes no concept, is '
      'refused before any write', () async {
    await expectLater(
      writer.prepare(
        bundle,
        UpdateConcept(
          id: _request,
          frontmatter: {
            'verified': {'by': 'human:chris', 'at': '2026-10-22T00:00:00Z'},
          },
        ),
        stamp: _agent,
      ),
      throwsArgumentError,
    );
    await expectLater(
      writer.prepare(
        bundle,
        UpdateConcept(id: OkfConceptId('reporting/missing')),
        stamp: _agent,
      ),
      throwsA(
        isA<KnowledgeChangeException>().having(
          (error) => error.code,
          'code',
          'concept-not-found',
        ),
      ),
    );
    await expectLater(
      writer.prepare(
        bundle,
        CreateConcept(id: _request, frontmatter: {'type': 'Request'}),
        stamp: _agent,
      ),
      throwsA(
        isA<KnowledgeChangeException>().having(
          (error) => error.code,
          'code',
          'concept-exists',
        ),
      ),
    );
    expect(await _status(project), isEmpty);
  });
}

/// `git status --porcelain` lines, so an untracked `.okf.lock` shows.
Future<List<String>> _status(String project) async {
  final status = await Process.run('git', [
    'status',
    '--porcelain',
    '--untracked-files=all',
  ], workingDirectory: project);
  return [
    for (final line in (status.stdout as String).split('\n'))
      if (line.isNotEmpty) line,
  ];
}

/// Every file of [bundle] but okf's lock file, with its bytes.
Future<Map<String, List<int>>> _files(String bundle) async => {
  for (final MapEntry(:key, :value) in (await fileSnapshot(bundle)).entries)
    if (p.basename(key) != okfBundleLockFileName) key: value,
};
