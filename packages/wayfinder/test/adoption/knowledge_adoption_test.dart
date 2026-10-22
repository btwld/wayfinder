import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/adoption.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

final _bitwild = ProfileId.parse('bitwild-profile');
final _acme = ProfileId.parse('acme-notes');
final _day = DateTime(2026, 10, 22);

void main() {
  late Directory temp;
  late Directory source;
  late String commit;
  late Directory project;
  late Directory data;
  late WayfinderProfileResolver resolver;
  late KnowledgeAdoption adoption;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-adoption-');
    (directory: source, :commit) = await profileSource(temp);
    project = await emptyRepository(temp);
    data = Directory(p.join(temp.path, 'data'));
    resolver = WayfinderProfileResolver(dataDirectory: data);
    adoption = KnowledgeAdoption(resolver: resolver, clock: () => _day);
  });

  tearDown(() => temp.delete(recursive: true));

  String bundle([String name = 'knowledge']) => p.join(project.path, name);

  AdoptionRequest bitwild({
    String? ref,
    bool offline = false,
    List<String> instructionLines = const [],
  }) => AdoptionRequest(
    projectRoot: project.path,
    profile: _bitwild,
    source: AdoptionSource(
      git: source.path,
      path: 'profiles/bitwild',
      ref: ref,
    ),
    instructionLines: instructionLines,
    offline: offline,
  );

  AdoptionRequest twoRule({
    List<AdoptionSeedConcept> concepts = const [],
    bool bindExisting = false,
  }) => AdoptionRequest(
    projectRoot: project.path,
    profile: _acme,
    source: AdoptionSource(
      git: source.path,
      path: 'examples/profiles/two-rule',
      ref: 'main',
    ),
    concepts: concepts,
    bindExisting: bindExisting,
  );

  Future<ProfileValidationResult> validate([String name = 'knowledge']) =>
      validateWithProfileSources(
        bundle(name),
        // A fresh resolver, as a later `wayfinder validate` would use.
        resolver: WayfinderProfileResolver(dataDirectory: data),
      );

  Matcher failsWith(String code) => throwsA(
    isA<KnowledgeAdoptionException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );

  Future<void> expectWrittenAsPlanned(KnowledgeAdoptionPlan plan) async {
    for (final file in plan.files) {
      final bytes = await File(
        p.joinAll([project.path, ...file.path.split('/')]),
      ).readAsBytes();
      expect(sha256.convert(bytes).toString(), file.sha256, reason: file.path);
      expect(bytes.length, file.size, reason: file.path);
    }
  }

  group('adopting an empty Git repository', () {
    test('with Bitwild from its default branch, pinned to the resolved '
        'commit', () async {
      final plan = await adoption.plan(bitwild());
      expect(await gitStatus(project.path), isEmpty);
      expect(plan.conflicts, isEmpty);
      expect(plan.applicable, isTrue);
      expect(plan.mode, AdoptionBundleMode.seed);
      expect(plan.profile.id, _bitwild);
      expect(plan.profile.release, '2026.3');
      expect(plan.profile.ref, commit);
      expect(plan.profile.commit, commit);
      expect(plan.profile.chain.map((package) => package.id), [_bitwild]);
      expect(plan.fetches, hasLength(1));
      expect(plan.fetches.single.kind, ProfileFetchKind.clone);
      expect(plan.fetches.single.git, source.path);
      expect(plan.fetches.single.ref, isNull);
      expect(plan.validation.gate, GateState.pass);

      final paths = [for (final file in plan.files) file.path];
      expect(paths.take(4), [
        'knowledge/index.md',
        'knowledge/log.md',
        'wayfinder.json',
        'wayfinder.lock',
      ]);
      expect(paths.last, '.gitignore');
      expect(
        paths,
        containsAll([
          '.claude/skills/bitwild-profile/.wayfinder-profile',
          '.claude/skills/bitwild-profile/SKILL.md',
          '.agents/skills/bitwild-profile/.wayfinder-profile',
          '.agents/skills/bitwild-profile/SKILL.md',
        ]),
      );
      final configuration = plan.files.firstWhere(
        (file) => file.path == 'wayfinder.json',
      );
      expect(
        configuration.content,
        KnowledgeSeeds.configuration(
          profile: 'bitwild-profile',
          git: source.path,
          ref: commit,
          path: 'profiles/bitwild',
        ),
      );
      final skill = plan.files.firstWhere(
        (file) => file.path == '.claude/skills/bitwild-profile/SKILL.md',
      );
      expect(skill.content, isNull);
      expect(skill.action, AdoptionFileAction.create);

      final result = await adoption.apply(plan);
      expect(result.complete, isTrue);
      expect([for (final step in result.steps) step.step], AdoptionStep.values);
      expect(
        result.steps.map((step) => step.outcome),
        everyElement(AdoptionStepOutcome.done),
      );
      expect(result.written, paths);
      await expectWrittenAsPlanned(plan);
      expect(
        await File(p.join(bundle(), 'index.md')).readAsString(),
        KnowledgeSeeds.rootIndex(okfVersion: '0.2'),
      );
      expect(
        await File(p.join(bundle(), 'log.md')).readAsString(),
        KnowledgeSeeds.log(date: '2026-10-22'),
      );
      expect(
        await File(p.join(project.path, '.gitignore')).readAsString(),
        'knowledge/.okf.lock\n',
      );
      final validation = await validate();
      expect(validation.gate, GateState.pass);
      expect(validation.profileId, _bitwild);
      expect(validation.diagnostics, isEmpty);
    });

    test('with two-rule at a branch and a seed concept, writing the '
        'generated indexes', () async {
      final concept = await File(
        p.join(
          '..',
          '..',
          'examples',
          'acme-notes',
          'knowledge',
          'operations',
          'restart-the-api.md',
        ),
      ).readAsString();
      final plan = await adoption.plan(
        twoRule(
          concepts: [
            AdoptionSeedConcept(
              path: 'operations/restart-the-api.md',
              text: concept,
            ),
          ],
        ),
      );
      expect(await gitStatus(project.path), isEmpty);
      expect(plan.conflicts, isEmpty);
      expect(plan.profile.ref, 'main');
      expect(plan.profile.commit, commit);
      expect(plan.validation.gate, GateState.pass);
      expect(
        [
          for (final file in plan.files)
            if (file.kind == AdoptionFileKind.bundle) file.path,
        ],
        [
          'knowledge/index.md',
          'knowledge/log.md',
          'knowledge/operations/index.md',
          'knowledge/operations/restart-the-api.md',
        ],
      );
      // The generated root index, as in the acme-notes example.
      expect(
        plan.files.first.content,
        await File(
          p.join('..', '..', 'examples', 'acme-notes', 'knowledge', 'index.md'),
        ).readAsString(),
      );

      final result = await adoption.apply(plan);
      expect(result.complete, isTrue);
      await expectWrittenAsPlanned(plan);
      expect(
        await File(
          p.join(project.path, '.claude', 'skills', 'acme-notes', 'SKILL.md'),
        ).exists(),
        isTrue,
      );
      expect((await validate()).gate, GateState.pass);
      // validate --fix finds nothing left to write.
      final fixed = await validateWithProfileSources(
        bundle(),
        resolver: resolver,
        fix: true,
      );
      expect(fixed.fixed, isEmpty);
      expect(fixed.gate, GateState.pass);
    });

    test('with Bitwild, a seed concept and the actor it names', () async {
      final concept = await File(
        p.join(
          '..',
          '..',
          'examples',
          'bitwild',
          'knowledge',
          'ways-of-working',
          'relationship-labels.md',
        ),
      ).readAsString();
      const actor = WayfinderActorMetadata(name: 'Claude Code', side: 'tool');
      final plan = await adoption.plan(
        AdoptionRequest(
          projectRoot: project.path,
          profile: _bitwild,
          source: AdoptionSource(
            git: source.path,
            path: 'profiles/bitwild',
            ref: 'main',
          ),
          concepts: [
            AdoptionSeedConcept(
              path: 'ways-of-working/relationship-labels.md',
              text: concept,
            ),
          ],
          vocabulary: const ProjectVocabulary(
            actors: {'claude-code/opus-5': actor},
          ),
          logDescription:
              'Established the knowledge bundle under the bitwild-profile '
              'Profile.',
        ),
      );
      expect(plan.conflicts, isEmpty);
      expect(plan.validation.gate, GateState.pass);
      expect(
        [
          for (final file in plan.files)
            if (file.kind == AdoptionFileKind.bundle) file.path,
        ],
        [
          'knowledge/index.md',
          'knowledge/log.md',
          'knowledge/ways-of-working/index.md',
          'knowledge/ways-of-working/relationship-labels.md',
        ],
      );
      // The generated root index replaces the seed's, which linked log.md.
      expect(plan.files.first.content, isNot(contains('log.md')));
      final configuration = WayfinderProjectConfig.parse(
        plan.files.firstWhere((file) => file.path == 'wayfinder.json').content!,
      );
      expect(configuration.profiles[_bitwild]!.project.actors.keys, [
        'claude-code/opus-5',
      ]);

      final result = await adoption.apply(plan);
      expect(result.complete, isTrue);
      await expectWrittenAsPlanned(plan);
      expect(
        await File(p.join(bundle(), 'log.md')).readAsString(),
        contains('under the bitwild-profile Profile.'),
      );
      final validation = await validate();
      expect(validation.gate, GateState.pass);
      expect(
        (await validateWithProfileSources(
          bundle(),
          resolver: resolver,
          fix: true,
        )).fixed,
        isEmpty,
      );
    });

    test('binding an existing bundle writes nothing in it', () async {
      await copyTree(
        p.join('..', '..', 'examples', 'acme-notes', 'knowledge'),
        [project.path, 'knowledge'],
      );
      await commitAll(project.path);
      final unbound = await adoption.plan(twoRule());
      expect(unbound.conflicts.map((conflict) => conflict.code), [
        'bundle-exists',
      ]);

      final plan = await adoption.plan(twoRule(bindExisting: true));
      expect(await gitStatus(project.path), isEmpty);
      expect(plan.conflicts, isEmpty);
      expect(plan.mode, AdoptionBundleMode.bind);
      expect(
        plan.files.where((file) => file.kind == AdoptionFileKind.bundle),
        isEmpty,
      );
      final result = await adoption.apply(plan);
      expect(
        result.steps
            .firstWhere((step) => step.step == AdoptionStep.bundle)
            .outcome,
        AdoptionStepOutcome.skipped,
      );
      expect(result.complete, isTrue);
      expect(
        (await gitStatus(
          project.path,
        )).where((line) => line.contains('knowledge/')),
        isEmpty,
      );
    });
  });

  test('plan leaves git status --porcelain empty and writes nothing in the '
      'project', () async {
    await File(p.join(project.path, 'README.md')).writeAsString('# Project\n');
    await File(p.join(project.path, '.gitignore')).writeAsString('build/');
    await Directory(bundle()).create();
    await File(p.join(bundle(), '.keep')).create();
    await commitAll(project.path);
    await File(p.join(bundle(), '.keep')).delete();
    expect(await Directory(bundle()).list().isEmpty, isTrue);
    final before = await fileSnapshot(project.path);
    final status = await gitStatus(project.path);

    final plan = await adoption.plan(bitwild());
    expect(await fileSnapshot(project.path), before);
    expect(await gitStatus(project.path), status);
    expect(await Directory(bundle()).list().isEmpty, isTrue);
    expect(plan.conflicts, isEmpty);
    final gitignore = plan.files.last;
    expect(gitignore.path, '.gitignore');
    expect(gitignore.action, AdoptionFileAction.append);
    expect(gitignore.content, '\nknowledge/.okf.lock\n');

    // An offline plan reads the cache as it is, a branch included.
    for (final ref in [commit, 'main']) {
      final again = await adoption.plan(bitwild(ref: ref, offline: true));
      expect(again.fetches, isEmpty);
      expect(again.profile.commit, commit);
    }
    await expectLater(
      adoption.plan(bitwild(ref: 'missing', offline: true)),
      throwsA(
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'fetch-required',
        ),
      ),
    );
    expect(await fileSnapshot(project.path), before);

    await adoption.apply(plan);
    expect(
      await File(p.join(project.path, '.gitignore')).readAsString(),
      'build/\nknowledge/.okf.lock\n',
    );
    expect((await validate()).gate, GateState.pass);
  });

  test('an offline plan with nothing cached names the fetch it needs', () {
    expect(
      adoption.plan(bitwild(offline: true)),
      throwsA(
        isA<WayfinderException>()
            .having((error) => error.code, 'code', 'fetch-required')
            .having((error) => error.message, 'message', contains(source.path)),
      ),
    );
  });

  test('an unmarked .claude/skills/<id> is refused before anything is '
      'written', () async {
    final own = Directory(
      p.join(project.path, '.claude', 'skills', 'bitwild-profile'),
    );
    await own.create(recursive: true);
    await File(p.join(own.path, 'SKILL.md')).writeAsString('# Mine\n');
    await commitAll(project.path);
    final before = await fileSnapshot(project.path);

    final plan = await adoption.plan(bitwild());
    expect(plan.applicable, isFalse);
    expect(plan.conflicts.map((conflict) => (conflict.code, conflict.path)), [
      ('skill-unowned', '.claude/skills/bitwild-profile'),
    ]);
    expect(plan.toJson()['conflicts'], [containsPair('code', 'skill-unowned')]);

    await expectLater(adoption.apply(plan), failsWith('adoption-conflict'));
    expect(await fileSnapshot(project.path), before);
    expect(await gitStatus(project.path), isEmpty);
    try {
      await adoption.apply(plan);
    } on KnowledgeAdoptionException catch (error) {
      expect(error.steps.map((step) => (step.step, step.outcome)), [
        (AdoptionStep.check, AdoptionStepOutcome.failed),
      ]);
    }
  });

  test('AGENTS.md, CLAUDE.md, .mcp.json and hooks are never written', () async {
    await File(
      p.join(project.path, 'AGENTS.md'),
    ).writeAsString('# Agents\n\n## Agent skills\n');
    await File(p.join(project.path, 'CLAUDE.md')).writeAsString('@AGENTS.md\n');
    await commitAll(project.path);
    final agents = await File(p.join(project.path, 'AGENTS.md')).readAsBytes();
    final claude = await File(p.join(project.path, 'CLAUDE.md')).readAsBytes();
    final hooks = await fileSnapshot(p.join(project.path, '.git', 'hooks'));

    final plan = await adoption.plan(
      bitwild(
        instructionLines: [
          'Execution records stay in the tracker and are linked from concepts.',
        ],
      ),
    );
    final paths = [for (final file in plan.files) file.path];
    for (final path in ['AGENTS.md', 'CLAUDE.md', '.mcp.json']) {
      expect(paths, isNot(contains(path)));
    }
    expect(
      paths.where(
        (path) => path.startsWith('.githooks/') || path.startsWith('.git/'),
      ),
      isEmpty,
    );
    expect(
      plan.agentInstructions,
      KnowledgeSeeds.knowledgeBundleInstructions(
        lines: [
          'Execution records stay in the tracker and are linked from concepts.',
        ],
      ),
    );
    expect(
      plan.agentInstructions,
      endsWith(
        "skill of each Profile in the bundle's chain.\n\n"
        'Execution records stay in the tracker and are linked from concepts.\n',
      ),
    );

    final result = await adoption.apply(plan);
    expect(result.complete, isTrue);
    expect(result.agentInstructions, plan.agentInstructions);
    expect(await File(p.join(project.path, 'AGENTS.md')).readAsBytes(), agents);
    expect(await File(p.join(project.path, 'CLAUDE.md')).readAsBytes(), claude);
    expect(await File(p.join(project.path, '.mcp.json')).exists(), isFalse);
    expect(
      await Directory(p.join(project.path, '.githooks')).exists(),
      isFalse,
    );
    expect(await fileSnapshot(p.join(project.path, '.git', 'hooks')), hooks);
    final hooksPath = await Process.run('git', [
      'config',
      '--get',
      'core.hooksPath',
    ], workingDirectory: project.path);
    expect(hooksPath.exitCode, 1);
    final status = await gitStatus(project.path);
    expect(status, isNot(anyElement(contains('AGENTS.md'))));
    expect(status, isNot(anyElement(contains('CLAUDE.md'))));
  });

  group('apply refuses a plan whose inputs changed', () {
    test('in the project', () async {
      final plan = await adoption.plan(bitwild());
      await File(p.join(project.path, '.gitignore')).writeAsString('build/\n');
      final before = await fileSnapshot(project.path);

      await expectLater(adoption.apply(plan), failsWith('adoption-stale'));
      expect(await fileSnapshot(project.path), before);
      expect(
        await File(p.join(project.path, 'wayfinder.json')).exists(),
        isFalse,
      );
    });

    test('in the bundle', () async {
      final plan = await adoption.plan(bitwild());
      await Directory(bundle()).create();
      await File(p.join(bundle(), 'draft.md')).writeAsString('# Draft\n');
      final before = await fileSnapshot(project.path);

      await expectLater(adoption.apply(plan), failsWith('adoption-stale'));
      expect(await fileSnapshot(project.path), before);
    });

    test('in the Profile cache', () async {
      final plan = await adoption.plan(bitwild());
      await for (final entity in Directory(
        p.join(data.path, 'profiles', 'packages'),
      ).list()) {
        if (entity is File) await entity.writeAsString('{}');
      }

      await expectLater(adoption.apply(plan), failsWith('resolution-stale'));
      expect(await gitStatus(project.path), isEmpty);
    });
  });

  test('a step that fails undoes the steps before it', () async {
    // A marked copy from an earlier revision, which applying replaces.
    final previous = Directory(
      p.join(project.path, '.agents', 'skills', 'bitwild-profile'),
    );
    await previous.create(recursive: true);
    await File(p.join(previous.path, '.wayfinder-profile')).writeAsString(
      '${jsonEncode({'id': 'bitwild-profile', 'release': '2026.2', 'commit': '0' * 40})}\n',
    );
    await File(p.join(previous.path, 'SKILL.md')).writeAsString('# Old\n');
    await commitAll(project.path);
    final before = await fileSnapshot(project.path);

    final plan = await adoption.plan(bitwild());
    expect(plan.conflicts, isEmpty);
    expect(
      plan.files
          .firstWhere(
            (file) => file.path == '.agents/skills/bitwild-profile/SKILL.md',
          )
          .action,
      AdoptionFileAction.replace,
    );

    // Another get holds the project, so the profile step fails.
    final root = await project.resolveSymbolicLinks();
    final held = await WayfinderFileLock.tryExclusive(
      File(
        p.join(
          data.path,
          'projects',
          '${sha256.convert(utf8.encode(root))}.get.lock',
        ),
      ),
    );
    addTearDown(() => held?.release());
    KnowledgeAdoptionException? failure;
    try {
      await adoption.apply(plan);
    } on KnowledgeAdoptionException catch (error) {
      failure = error;
    }
    expect(failure?.code, 'resolution-busy');
    expect(failure!.steps.map((step) => (step.step, step.outcome)), [
      (AdoptionStep.check, AdoptionStepOutcome.done),
      (AdoptionStep.bundle, AdoptionStepOutcome.undone),
      (AdoptionStep.configuration, AdoptionStepOutcome.undone),
      (AdoptionStep.profile, AdoptionStepOutcome.failed),
    ]);
    expect(await fileSnapshot(project.path), before);
    expect(await gitStatus(project.path), isEmpty);
    expect(await Directory(bundle()).exists(), isFalse);

    await held!.release();
    final result = await adoption.apply(plan);
    expect(result.complete, isTrue);
    expect(
      await File(p.join(previous.path, 'SKILL.md')).readAsString(),
      isNot('# Old\n'),
    );
  });

  test('a .gitignore that ignores the lock already is left alone', () async {
    await File(
      p.join(project.path, '.gitignore'),
    ).writeAsString('**/.okf.lock\n');
    final plan = await adoption.plan(bitwild());
    expect(
      plan.files.where((file) => file.kind == AdoptionFileKind.gitignore),
      isEmpty,
    );
    final result = await adoption.apply(plan);
    expect(
      result.steps
          .firstWhere((step) => step.step == AdoptionStep.gitignore)
          .outcome,
      AdoptionStepOutcome.skipped,
    );
    expect(
      await File(p.join(project.path, '.gitignore')).readAsString(),
      '**/.okf.lock\n',
    );
  });

  test('ignoreOkfLock false leaves .gitignore unwritten', () async {
    final plan = await adoption.plan(
      AdoptionRequest(
        projectRoot: project.path,
        profile: _bitwild,
        source: AdoptionSource(git: source.path, path: 'profiles/bitwild'),
        ignoreOkfLock: false,
      ),
    );
    expect(plan.files.where((file) => file.path == '.gitignore'), isEmpty);
    await adoption.apply(plan);
    expect(await File(p.join(project.path, '.gitignore')).exists(), isFalse);
  });

  test('an existing configuration or lock is a conflict', () async {
    await File(p.join(project.path, 'wayfinder.json')).writeAsString('{}');
    await File(p.join(project.path, 'wayfinder.lock')).writeAsString('{}');
    final plan = await adoption.plan(bitwild());
    expect(plan.conflicts.map((conflict) => conflict.code), [
      'configuration-exists',
      'lock-exists',
    ]);
  });

  test('a bundle path through a file or a link is a conflict', () async {
    await File(p.join(project.path, 'docs')).writeAsString('');
    final throughFile = await adoption.plan(
      AdoptionRequest(
        projectRoot: project.path,
        profile: _bitwild,
        source: AdoptionSource(git: source.path, path: 'profiles/bitwild'),
        bundle: 'docs/knowledge',
      ),
    );
    expect(throughFile.conflicts.map((conflict) => conflict.code), [
      'bundle-not-directory',
    ]);
    if (Platform.isWindows) return;
    final elsewhere = await Directory(p.join(temp.path, 'elsewhere')).create();
    await Link(bundle()).create(elsewhere.path);
    final throughLink = await adoption.plan(bitwild());
    expect(throughLink.conflicts.map((conflict) => conflict.code), [
      'bundle-link',
    ]);
  });

  test('a nested bundle path creates its parents and removes them when '
      'undone', () async {
    final request = AdoptionRequest(
      projectRoot: project.path,
      profile: _bitwild,
      source: AdoptionSource(git: source.path, path: 'profiles/bitwild'),
      bundle: 'docs/knowledge',
    );
    final plan = await adoption.plan(request);
    expect(
      plan.files.firstWhere((file) => file.path == 'wayfinder.json').content,
      contains('"applies_to": ["./docs/knowledge"]'),
    );
    expect(plan.files.last.content, 'docs/knowledge/.okf.lock\n');

    final root = await project.resolveSymbolicLinks();
    final held = await WayfinderFileLock.tryExclusive(
      File(
        p.join(
          data.path,
          'projects',
          '${sha256.convert(utf8.encode(root))}.get.lock',
        ),
      ),
    );
    await expectLater(adoption.apply(plan), failsWith('resolution-busy'));
    await held!.release();
    expect(await Directory(p.join(project.path, 'docs')).exists(), isFalse);
    expect(await gitStatus(project.path), isEmpty);

    final result = await adoption.apply(plan);
    expect(result.complete, isTrue);
    expect((await validate('docs/knowledge')).gate, GateState.pass);
  });

  test('a request that cannot describe an adoption is refused', () async {
    Future<void> refused(AdoptionRequest request) => expectLater(
      adoption.plan(request),
      throwsA(
        isA<WayfinderException>().having(
          (error) => error.code,
          'code',
          'adoption-invalid',
        ),
      ),
    );
    final bitwildSource = AdoptionSource(
      git: source.path,
      path: 'profiles/bitwild',
    );
    await refused(
      AdoptionRequest(
        projectRoot: project.path,
        profile: _bitwild,
        source: bitwildSource,
        bundle: '../outside',
      ),
    );
    await refused(
      AdoptionRequest(
        projectRoot: project.path,
        profile: _bitwild,
        source: bitwildSource,
        concepts: const [AdoptionSeedConcept(path: 'index.md', text: '')],
      ),
    );
    await refused(
      AdoptionRequest(
        projectRoot: project.path,
        profile: _bitwild,
        source: const AdoptionSource(
          git: 'https://user:secret@example.test/profiles.git',
          path: 'profiles/bitwild',
        ),
      ),
    );
    await refused(
      AdoptionRequest(
        projectRoot: project.path,
        profile: _bitwild,
        source: bitwildSource,
        bindExisting: true,
        concepts: const [AdoptionSeedConcept(path: 'a.md', text: '# A\n')],
      ),
    );
    expect(await gitStatus(project.path), isEmpty);
  });

  test('the plan reports as JSON', () async {
    final plan = await adoption.plan(bitwild(ref: 'main'));
    final json = plan.toJson();
    expect(json.keys, [
      'project',
      'bundle',
      'mode',
      'profile',
      'fetches',
      'files',
      'skills',
      'removed_skills',
      'conflicts',
      'applicable',
      'gate',
      'agent_instructions',
    ]);
    expect(json['profile'], {
      'id': 'bitwild-profile',
      'release': '2026.3',
      'source': {'git': source.path, 'ref': 'main', 'path': 'profiles/bitwild'},
      'commit': commit,
      'chain': [
        {'id': 'bitwild-profile', 'release': '2026.3', 'commit': commit},
      ],
    });
    expect(json['gate'], 'PASS');
    expect(json['skills'], [
      {
        'id': 'bitwild-profile',
        'directories': [
          '.claude/skills/bitwild-profile',
          '.agents/skills/bitwild-profile',
        ],
        'written': true,
      },
    ]);
    expect((json['files']! as List).first, {
      'path': 'knowledge/index.md',
      'kind': 'bundle',
      'action': 'create',
      'sha256': sha256
          .convert(utf8.encode(KnowledgeSeeds.rootIndex(okfVersion: '0.2')))
          .toString(),
      'bytes': utf8.encode(KnowledgeSeeds.rootIndex(okfVersion: '0.2')).length,
      'content': KnowledgeSeeds.rootIndex(okfVersion: '0.2'),
    });
    expect(jsonDecode(jsonEncode(json)), json);
  });
}
