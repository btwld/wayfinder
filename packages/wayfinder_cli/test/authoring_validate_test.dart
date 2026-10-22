import 'dart:convert';
import 'dart:io';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/authoring.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_cli/src/cli.dart';

import 'support.dart';

/// Profile-aware writes through `package:wayfinder/authoring.dart`, judged
/// after each commit by the `validate` command, on a copy of the Bitwild
/// example. `package:wayfinder`'s own tests cover the writer in depth.
void main() {
  late Directory temp;
  late String bundle;
  late WayfinderProfileResolver resolver;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-authoring-');
    final source = await Directory(p.join(temp.path, 'source')).create();
    await _git(source.path, ['init', '-q']);
    await _git(source.path, ['config', 'user.email', 'test@example.test']);
    await _git(source.path, ['config', 'user.name', 'Wayfinder Test']);
    await copyBitwildPackage(source.path);
    await _git(source.path, ['add', '-A']);
    await _git(source.path, ['commit', '-q', '-m', 'Profile']);
    final commit = (await _git(source.path, ['rev-parse', 'HEAD'])).trim();

    final project = p.join(temp.path, 'project');
    const example = '../../examples/bitwild';
    await for (final entity in Directory(example).list(recursive: true)) {
      if (entity is! File) continue;
      final copy = File(
        p.join(project, p.relative(entity.path, from: example)),
      );
      await copy.parent.create(recursive: true);
      await entity.copy(copy.path);
    }
    final configFile = File(p.join(project, 'wayfinder.json'));
    final config = jsonDecode(await configFile.readAsString()) as Map;
    final binding = (config['profiles'] as Map)['bitwild-profile'] as Map;
    (binding['source'] as Map)
      ..['git'] = source.path
      ..['ref'] = commit;
    await configFile.writeAsString(jsonEncode(config));
    resolver = WayfinderProfileResolver(
      dataDirectory: Directory(p.join(temp.path, 'data')),
    );
    await resolver.resolve(project);
    bundle = p.join(project, 'knowledge');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<String> validateGate() async {
    final output = <String>[];
    final cli = WayfinderCli(
      out: output.add,
      err: output.add,
      notices: false,
      profileResolver: () => resolver,
    );
    expect(await cli.run(['validate', bundle, '--output', 'json']), 0);
    final report = jsonDecode(output.single) as Map<String, Object?>;
    return (report['gate']! as Map)['state']! as String;
  }

  test('validate passes after each committed create, update, link and '
      'deprecate', () async {
    final writer = KnowledgeWriter(resolver: resolver);
    const stamp = KnowledgeStamp.generated(by: 'claude-code/opus-5');
    final contract = OkfConceptId('reporting/pagination-contract');
    final changes = <(KnowledgeChange, KnowledgeLog)>[
      (
        CreateConcept(
          id: contract,
          frontmatter: {
            'type': 'Specification',
            'title': 'Pagination contract',
            'description': 'How the renderer splits an export into pages.',
            'status': 'draft',
          },
          body: '# Specification\n\nPages break at section bounds.\n',
        ),
        const KnowledgeLogEntry(
          action: 'Creation',
          description:
              'Recorded [Pagination contract]'
              '(/reporting/pagination-contract.md).',
        ),
      ),
      (
        UpdateConcept(
          id: contract,
          frontmatter: {'title': 'Export pagination contract'},
        ),
        const KnowledgeLogEntry(
          action: 'Update',
          description: 'Renamed the pagination contract.',
        ),
      ),
      (
        LinkConcepts(
          source: OkfConceptId('reporting/pdf-export-feasibility'),
          relationship: KnowledgeRelationship.toConcept(
            relationship: 'depends-on',
            target: contract,
          ),
        ),
        KnowledgeLog.none,
      ),
      (
        DeprecateConcept(id: contract, note: 'Folded into the analysis.'),
        KnowledgeLog.lifecycle,
      ),
    ];

    expect(await validateGate(), 'PASS');
    for (final (change, log) in changes) {
      final plan = await writer.prepare(
        bundle,
        change,
        stamp: stamp,
        logEntry: log,
      );
      expect(plan.committable, isTrue, reason: '$change');
      await writer.commit(plan);
      expect(await validateGate(), 'PASS', reason: '$change');
    }
  });
}

Future<String> _git(String directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}
