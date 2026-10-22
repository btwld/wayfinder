import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/adoption.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';

import '../support.dart' show selectFixture;
import 'support.dart';

// What a host composing adoption needs: its own Profile assessment, each
// step as it happens, the Profile id the package declares, and its own
// files in the staleness check.

final _bitwild = ProfileId.parse('bitwild-profile');
final _acme = ProfileId.parse('acme-notes');
final _day = DateTime(2026, 10, 22);

/// A title that `^(a+)+$` takes exponential time to reject.
final _hostileTitle = '${'a' * 40}b';

void main() {
  late Directory temp;
  late Directory source;
  late String commit;
  late Directory project;
  late Directory data;
  late WayfinderProfileResolver resolver;
  late KnowledgeAdoption adoption;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-adoption-host-');
    (directory: source, :commit) = await profileSource(temp);
    project = await emptyRepository(temp);
    data = Directory(p.join(temp.path, 'data'));
    resolver = WayfinderProfileResolver(dataDirectory: data);
    adoption = KnowledgeAdoption(resolver: resolver, clock: () => _day);
  });

  tearDown(() => temp.delete(recursive: true));

  String bundle() => p.join(project.path, 'knowledge');

  AdoptionRequest bitwild({
    ProfileId? profile,
    String? ref,
    bool offline = false,
    bool bindExisting = false,
    List<String> hostInputs = const [],
  }) => AdoptionRequest(
    projectRoot: project.path,
    profile: profile,
    source: AdoptionSource(
      git: source.path,
      path: 'profiles/bitwild',
      ref: ref,
    ),
    offline: offline,
    bindExisting: bindExisting,
    hostInputs: hostInputs,
  );

  Future<KnowledgeAdoptionException> applyFailure(
    KnowledgeAdoptionPlan plan, {
    Future<void> Function()? hostStep,
    void Function(AdoptionStepReport report)? onStep,
  }) async {
    try {
      await adoption.apply(plan, hostStep: hostStep, onStep: onStep);
    } on KnowledgeAdoptionException catch (error) {
      return error;
    }
    fail('apply succeeded');
  }

  List<(AdoptionStep, AdoptionStepOutcome)> outcomes(
    Iterable<AdoptionStepReport> reports,
  ) => [for (final report in reports) (report.step, report.outcome)];

  group('a host assessor', () {
    test('replaces the in-process assessment in plan and apply', () async {
      final inputs = <KnowledgeAssessmentInput>[];
      final cancels = <WayfinderCancellation?>[];
      final controller = WayfinderCancellationController();
      final elsewhere = KnowledgeAdoption(
        resolver: resolver,
        clock: () => _day,
        assess: (input, cancel) async {
          inputs.add(input);
          cancels.add(cancel);
          return Isolate.run(input.assess);
        },
      );
      final plan = await elsewhere.plan(bitwild(), cancel: controller);
      expect(inputs, hasLength(1));
      expect(inputs.single.base, isNull);
      expect(inputs.single.candidate.rootPath, bundle());
      expect(inputs.single.candidate.indexes.keys, ['index.md']);
      expect(
        (inputs.single.selection as SelectedProfile).profile.selected.id,
        _bitwild,
      );
      expect(cancels.single, same(controller));
      expect(plan.validation.gate, GateState.pass);
      expect(
        jsonEncode(plan.validation.toJson()),
        jsonEncode((await adoption.plan(bitwild())).validation.toJson()),
      );

      final result = await elsewhere.apply(plan, cancel: controller);
      expect(inputs, hasLength(2));
      expect(inputs.last.base, isNull);
      expect(inputs.last.candidate.rootPath, bundle());
      expect(inputs.last.candidate.logs.keys, ['log.md']);
      expect(cancels.last, same(controller));
      expect(result.complete, isTrue);
      expect(
        jsonEncode(result.validation!.toJson()),
        jsonEncode(
          (await validateWithProfileSources(
            bundle(),
            resolver: resolver,
          )).toJson(),
        ),
      );
    });

    test('decides both gates: its verdict is the one plan and apply '
        'report', () async {
      var calls = 0;
      final unassessed = KnowledgeAdoption(
        resolver: resolver,
        clock: () => _day,
        assess: (input, cancel) async {
          calls++;
          // A host's own verdict, as one that refuses to judge would give.
          return KnowledgeAssessment(
            base: null,
            candidate: const ProfileValidator().validateLoaded(
              input.candidate,
              UnselectedProfile([
                const EngineDiagnostic(
                  DiagnosticCode.configMissing,
                  'The host judged nothing.',
                ),
              ]),
            ),
            baseFindings: const [],
          );
        },
      );
      final plan = await unassessed.plan(bitwild());
      expect(plan.validation.gate, GateState.incomplete);
      expect(plan.validation.profileState, ProfileState.notAssessed);
      expect(plan.toJson()['gate'], 'INCOMPLETE');
      final result = await unassessed.apply(plan);
      expect(calls, 2);
      expect(result.validation!.gate, GateState.incomplete);
      expect(result.complete, isFalse);
      // The project itself passes, as the in-process assessment says.
      expect(
        (await validateWithProfileSources(bundle(), resolver: resolver)).gate,
        GateState.pass,
      );
    });

    test('that fails stops planning, and fails only the validate step of '
        'apply', () async {
      final plan = await adoption.plan(bitwild());
      final failing = KnowledgeAdoption(
        resolver: resolver,
        clock: () => _day,
        assess: (input, cancel) async => throw const WayfinderException(
          'assessment-timeout',
          'The Profile assessment did not finish.',
        ),
      );
      await expectLater(
        failing.plan(bitwild()),
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'assessment-timeout',
          ),
        ),
      );

      final result = await failing.apply(plan);
      expect(result.validation, isNull);
      expect(result.complete, isFalse);
      final validate = result.steps.last;
      expect(validate.step, AdoptionStep.validate);
      expect(validate.outcome, AdoptionStepOutcome.failed);
      expect(validate.code, 'assessment-timeout');
      expect(validate.toJson()['code'], 'assessment-timeout');
      // Validation undoes nothing.
      expect(await File(p.join(bundle(), 'index.md')).exists(), isTrue);
      expect(
        (await validateWithProfileSources(bundle(), resolver: resolver)).gate,
        GateState.pass,
      );
    });
  });

  group('assessWithin', () {
    late Directory slow;

    setUp(() async {
      slow = await _slowProfileSource(temp);
    });

    AdoptionRequest slowRequest(String title) => AdoptionRequest(
      projectRoot: project.path,
      source: AdoptionSource(git: slow.path, path: 'profile', ref: 'main'),
      concepts: [AdoptionSeedConcept(path: 'note.md', text: _concept(title))],
    );

    KnowledgeAdoption bounded(Duration timeout) => KnowledgeAdoption(
      resolver: resolver,
      clock: () => _day,
      assess: (input, cancel) =>
          input.assessWithin(timeout: timeout, cancel: cancel),
    );

    test('stops a Profile rule that runs past its timeout when '
        'planning', () async {
      final watch = Stopwatch()..start();
      await expectLater(
        bounded(
          const Duration(milliseconds: 300),
        ).plan(slowRequest(_hostileTitle)),
        throwsA(
          isA<WayfinderException>()
              .having((error) => error.code, 'code', 'assessment-timeout')
              .having(
                (error) => error.message,
                'message',
                contains('within 300 ms'),
              ),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      expect(await gitStatus(project.path), isEmpty);
    });

    test('stops it in the validate step of apply, which undoes '
        'nothing', () async {
      final adopting = bounded(const Duration(milliseconds: 300));
      final plan = await adopting.plan(slowRequest('A plain title'));
      expect(plan.validation.gate, GateState.pass);
      final result = await adopting.apply(
        plan,
        // The host's own step leaves a concept the Profile cannot judge in
        // time.
        hostStep: () => File(
          p.join(bundle(), 'note.md'),
        ).writeAsString(_concept(_hostileTitle)),
      );
      expect(result.validation, isNull);
      expect(outcomes(result.steps).last, (
        AdoptionStep.validate,
        AdoptionStepOutcome.failed,
      ));
      expect(result.steps.last.code, 'assessment-timeout');
      expect(
        await File(p.join(project.path, 'wayfinder.json')).exists(),
        isTrue,
      );
    });

    test('returns what assess returns, and stops when cancelled', () async {
      final example = p.posix.join('..', '..', 'examples', 'bitwild');
      final loaded = await const OkfBundleLoader().inspect(
        p.posix.join(example, 'knowledge'),
      );
      final selection = await selectFixture(
        p.posix.join(example, 'knowledge'),
        configPath: p.posix.join(example, 'wayfinder.json'),
      );
      expect(selection, isA<SelectedProfile>());
      final input = KnowledgeAssessmentInput.bundle(
        bundle: loaded,
        selection: selection,
      );
      final bounded = await input.assessWithin();
      expect(bounded.base, isNull);
      expect(bounded.baseFindings, isEmpty);
      expect(
        jsonEncode(bounded.candidate.toJson()),
        jsonEncode(input.assess().candidate.toJson()),
      );
      expect(bounded.candidate.gate, GateState.pass);

      // A write's input judges both bundles there too.
      final write = KnowledgeAssessmentInput(
        base: loaded,
        candidate: loaded,
        selection: selection,
      );
      final judged = await write.assessWithin();
      expect(
        jsonEncode(judged.base!.toJson()),
        jsonEncode(write.assess().base!.toJson()),
      );

      final hostile = await _hostileInput(slow);
      final cancel = WayfinderCancellationController();
      Timer(const Duration(milliseconds: 200), cancel.cancel);
      await expectLater(
        hostile.assessWithin(cancel: cancel),
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      await expectLater(
        input.assessWithin(cancel: cancel),
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
    });

    test('reports an input it cannot send as assessment-failed', () async {
      final loaded = await const OkfBundleLoader().inspect(
        p.join('..', '..', 'examples', 'bitwild', 'knowledge'),
      );
      final port = ReceivePort();
      addTearDown(port.close);
      final input = KnowledgeAssessmentInput.bundle(
        bundle: loaded,
        selection: await selectFixture(
          p.posix.join('..', '..', 'examples', 'bitwild', 'knowledge'),
          configPath: p.posix.join(
            '..',
            '..',
            'examples',
            'bitwild',
            'wayfinder.json',
          ),
        ),
        // A graph builder holding a port cannot cross to another isolate.
        validator: ProfileValidator(
          buildGraph: (bundle) {
            port.sendPort.send(null);
            return OkfGraph.fromBundle(bundle);
          },
        ),
      );
      await expectLater(
        input.assessWithin(),
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'assessment-failed',
          ),
        ),
      );
    });
  });

  group('onStep', () {
    final steps = [
      AdoptionStep.check,
      AdoptionStep.bundle,
      AdoptionStep.configuration,
      AdoptionStep.profile,
      AdoptionStep.gitignore,
      AdoptionStep.host,
    ];

    test('reports every step as it starts and ends, in order', () async {
      final plan = await adoption.plan(bitwild());
      final reports = <AdoptionStepReport>[];
      final result = await adoption.apply(
        plan,
        hostStep: () async {
          // Reported before the host step runs.
          expect(reports.last.step, AdoptionStep.host);
          expect(reports.last.outcome, AdoptionStepOutcome.started);
        },
        onStep: reports.add,
      );
      expect(outcomes(reports), [
        for (final step in AdoptionStep.values) ...[
          (step, AdoptionStepOutcome.started),
          (step, AdoptionStepOutcome.done),
        ],
      ]);
      // The ends are what the result reports, and nothing else.
      expect(
        [
          for (final report in reports)
            if (report.outcome != AdoptionStepOutcome.started)
              jsonEncode(report.toJson()),
        ],
        [for (final step in result.steps) jsonEncode(step.toJson())],
      );
      expect(
        reports
            .firstWhere((report) => report.step == AdoptionStep.bundle)
            .paths,
        isEmpty,
      );
      expect(
        reports.lastWhere((report) => report.step == AdoptionStep.bundle).paths,
        ['knowledge/index.md', 'knowledge/log.md'],
      );
      expect(result.complete, isTrue);
    });

    for (final failing in steps) {
      test('fails the ${failing.wireValue} step when it throws as that step '
          'starts, undoing every step before it', () async {
        final before = await fileSnapshot(project.path);
        final plan = await adoption.plan(bitwild());
        final reports = <AdoptionStepReport>[];
        var hostRan = false;
        final failure = await applyFailure(
          plan,
          hostStep: () async => hostRan = true,
          onStep: (report) {
            reports.add(report);
            if (report.step == failing &&
                report.outcome == AdoptionStepOutcome.started) {
              throw StateError('Stopped at ${failing.wireValue}.');
            }
          },
        );
        final index = steps.indexOf(failing);
        final finished = [
          for (final step in steps.take(index))
            if (step != AdoptionStep.host) step,
        ];
        expect(failure.code, 'adoption-failed');
        expect(failure.message, 'Bad state: Stopped at ${failing.wireValue}.');
        expect(outcomes(reports), [
          for (final step in finished) ...[
            (step, AdoptionStepOutcome.started),
            (step, AdoptionStepOutcome.done),
          ],
          (failing, AdoptionStepOutcome.started),
          (failing, AdoptionStepOutcome.failed),
          for (final step in finished.reversed)
            if (step != AdoptionStep.check) (step, AdoptionStepOutcome.undone),
        ]);
        expect(outcomes(failure.steps), [
          for (final step in finished)
            (
              step,
              step == AdoptionStep.check
                  ? AdoptionStepOutcome.done
                  : AdoptionStepOutcome.undone,
            ),
          (failing, AdoptionStepOutcome.failed),
        ]);
        expect(failure.steps.last.code, 'adoption-failed');
        expect(hostRan, isFalse);
        expect(await fileSnapshot(project.path), before);
        expect(await gitStatus(project.path), isEmpty);

        // Nothing was half done: the same plan applies.
        expect((await adoption.apply(plan)).complete, isTrue);
      });
    }

    test('fails a step whose end it throws for, undoing that step '
        'too', () async {
      final before = await fileSnapshot(project.path);
      final plan = await adoption.plan(bitwild());
      final reports = <AdoptionStepReport>[];
      final failure = await applyFailure(
        plan,
        onStep: (report) {
          reports.add(report);
          if (report.step == AdoptionStep.configuration &&
              report.outcome == AdoptionStepOutcome.done) {
            throw StateError('No.');
          }
        },
      );
      expect(outcomes(reports).skip(4), [
        (AdoptionStep.configuration, AdoptionStepOutcome.started),
        (AdoptionStep.configuration, AdoptionStepOutcome.done),
        (AdoptionStep.configuration, AdoptionStepOutcome.failed),
        (AdoptionStep.bundle, AdoptionStepOutcome.undone),
      ]);
      expect(outcomes(failure.steps), [
        (AdoptionStep.check, AdoptionStepOutcome.done),
        (AdoptionStep.bundle, AdoptionStepOutcome.undone),
        (AdoptionStep.configuration, AdoptionStepOutcome.failed),
      ]);
      expect(await fileSnapshot(project.path), before);
    });

    test('reports a failing step and the undo of each earlier one, and '
        'what it throws for those is ignored', () async {
      final plan = await adoption.plan(bitwild());
      final reports = <AdoptionStepReport>[];
      final failure = await applyFailure(
        plan,
        hostStep: () async => throw StateError('The host failed.'),
        onStep: (report) {
          reports.add(report);
          if (report.outcome
              case AdoptionStepOutcome.failed || AdoptionStepOutcome.undone) {
            throw StateError('Ignored.');
          }
        },
      );
      expect(failure.message, 'Bad state: The host failed.');
      expect(outcomes(reports).skip(10), [
        (AdoptionStep.host, AdoptionStepOutcome.started),
        (AdoptionStep.host, AdoptionStepOutcome.failed),
        (AdoptionStep.gitignore, AdoptionStepOutcome.undone),
        (AdoptionStep.profile, AdoptionStepOutcome.undone),
        (AdoptionStep.configuration, AdoptionStepOutcome.undone),
        (AdoptionStep.bundle, AdoptionStepOutcome.undone),
      ]);
      expect(await gitStatus(project.path), isEmpty);
    });

    test('fails a skipped step it throws for, undoing every step before '
        'it', () async {
      // A bound bundle skips the bundle step; a listed lock file skips the
      // .gitignore step.
      await copyTree(
        p.join('..', '..', 'examples', 'acme-notes', 'knowledge'),
        [project.path, 'knowledge'],
      );
      await File(
        p.join(project.path, '.gitignore'),
      ).writeAsString('knowledge/.okf.lock\n');
      await commitAll(project.path);
      final before = await fileSnapshot(project.path);
      final plan = await adoption.plan(bitwild(bindExisting: true));
      expect(plan.conflicts, isEmpty);
      for (final skipping in [AdoptionStep.bundle, AdoptionStep.gitignore]) {
        final reports = <AdoptionStepReport>[];
        final failure = await applyFailure(
          plan,
          onStep: (report) {
            reports.add(report);
            if (report.step == skipping &&
                report.outcome == AdoptionStepOutcome.skipped) {
              throw StateError('Not skipped.');
            }
          },
        );
        final finished = steps.take(steps.indexOf(skipping));
        expect(failure.message, 'Bad state: Not skipped.');
        expect(outcomes(reports), [
          for (final step in finished) ...[
            (step, AdoptionStepOutcome.started),
            (
              step,
              step == AdoptionStep.bundle
                  ? AdoptionStepOutcome.skipped
                  : AdoptionStepOutcome.done,
            ),
          ],
          (skipping, AdoptionStepOutcome.started),
          (skipping, AdoptionStepOutcome.skipped),
          (skipping, AdoptionStepOutcome.failed),
          for (final step in finished.toList().reversed)
            if (step != AdoptionStep.check && step != AdoptionStep.bundle)
              (step, AdoptionStepOutcome.undone),
        ], reason: skipping.wireValue);
        expect(outcomes(failure.steps).last, (
          skipping,
          AdoptionStepOutcome.failed,
        ));
        expect(await fileSnapshot(project.path), before);
        expect(await gitStatus(project.path), isEmpty);
      }
    });

    test('what it throws for the host step\'s end is ignored, and the '
        'host\'s writes and Wayfinder\'s stay', () async {
      final agents = File(p.join(project.path, 'AGENTS.md'));
      final plan = await adoption.plan(bitwild(hostInputs: ['AGENTS.md']));
      final reports = <AdoptionStepReport>[];
      final result = await adoption.apply(
        plan,
        hostStep: () => agents.writeAsString(plan.agentInstructions),
        onStep: (report) {
          reports.add(report);
          if (report.step == AdoptionStep.host &&
              report.outcome == AdoptionStepOutcome.done) {
            throw StateError('Too late.');
          }
        },
      );
      expect(outcomes(reports).skip(10), [
        (AdoptionStep.host, AdoptionStepOutcome.started),
        (AdoptionStep.host, AdoptionStepOutcome.done),
        (AdoptionStep.validate, AdoptionStepOutcome.started),
        (AdoptionStep.validate, AdoptionStepOutcome.done),
      ]);
      expect(result.complete, isTrue);
      expect(await agents.readAsString(), plan.agentInstructions);
      for (final file in plan.files) {
        expect(
          await File(
            p.joinAll([project.path, ...file.path.split('/')]),
          ).exists(),
          isTrue,
          reason: file.path,
        );
      }
    });

    test(
      'hears undo-failed for a step whose undo fails',
      () async {
        final plan = await adoption.plan(bitwild());
        final reports = <AdoptionStepReport>[];
        final failure = await applyFailure(
          plan,
          hostStep: () async {
            // The seeded files can no longer be removed.
            await _chmod('555', bundle());
            throw StateError('The host failed.');
          },
          onStep: reports.add,
        );
        await _chmod('755', bundle());
        if (!failure.steps.any(
          (step) => step.outcome == AdoptionStepOutcome.undoFailed,
        )) {
          markTestSkipped('This user deletes files in a read-only directory.');
          return;
        }
        expect(outcomes(reports).skip(10), [
          (AdoptionStep.host, AdoptionStepOutcome.started),
          (AdoptionStep.host, AdoptionStepOutcome.failed),
          (AdoptionStep.gitignore, AdoptionStepOutcome.undone),
          (AdoptionStep.profile, AdoptionStepOutcome.undone),
          (AdoptionStep.configuration, AdoptionStepOutcome.undone),
          (AdoptionStep.bundle, AdoptionStepOutcome.undoFailed),
        ]);
        expect(
          jsonEncode(reports.last.toJson()),
          jsonEncode(
            failure.steps
                .firstWhere((step) => step.step == AdoptionStep.bundle)
                .toJson(),
          ),
        );
      },
      skip: Platform.isWindows ? 'chmod is POSIX' : false,
    );

    test('a check that refuses the plan is the only step reported', () async {
      final plan = await adoption.plan(bitwild());
      await File(p.join(project.path, '.gitignore')).writeAsString('build/\n');
      final reports = <AdoptionStepReport>[];
      final failure = await applyFailure(plan, onStep: reports.add);
      expect(failure.code, 'adoption-stale');
      expect(outcomes(reports), [
        (AdoptionStep.check, AdoptionStepOutcome.started),
        (AdoptionStep.check, AdoptionStepOutcome.failed),
      ]);
      expect(reports.last.code, 'adoption-stale');
    });

    test('fails the validate step when it throws as validation starts, '
        'undoing nothing', () async {
      final plan = await adoption.plan(bitwild());
      final reports = <AdoptionStepReport>[];
      final result = await adoption.apply(
        plan,
        onStep: (report) {
          reports.add(report);
          if (report.step == AdoptionStep.validate &&
              report.outcome == AdoptionStepOutcome.started) {
            throw StateError('Not now.');
          }
        },
      );
      expect(outcomes(reports).skip(12), [
        (AdoptionStep.validate, AdoptionStepOutcome.started),
        (AdoptionStep.validate, AdoptionStepOutcome.failed),
      ]);
      expect(result.validation, isNull);
      expect(result.complete, isFalse);
      expect(outcomes(result.steps).last, (
        AdoptionStep.validate,
        AdoptionStepOutcome.failed,
      ));
      expect(result.steps.last.message, 'Bad state: Not now.');
      expect(
        (await validateWithProfileSources(bundle(), resolver: resolver)).gate,
        GateState.pass,
      );
    });

    test('a cancellation after the host step fails only the validate '
        'step', () async {
      final plan = await adoption.plan(bitwild());
      final cancel = WayfinderCancellationController();
      final result = await adoption.apply(
        plan,
        cancel: cancel,
        hostStep: () async => cancel.cancel(),
      );
      expect(result.validation, isNull);
      expect(result.steps.last.code, 'cancelled');
      expect(
        await File(p.join(project.path, 'wayfinder.lock')).exists(),
        isTrue,
      );
    });
  });

  group('the Profile id', () {
    test('a request without one adopts the id the package declares, '
        'fetching the source once', () async {
      final plan = await adoption.plan(bitwild());
      expect(plan.request.profile, isNull);
      expect(plan.profile.id, _bitwild);
      expect(plan.profile.ref, commit);
      expect(plan.fetches.map((fetch) => (fetch.kind, fetch.ref)), [
        (ProfileFetchKind.clone, null),
      ]);
      expect(
        plan.files.firstWhere((file) => file.path == 'wayfinder.json').content,
        KnowledgeSeeds.configuration(
          profile: 'bitwild-profile',
          git: source.path,
          ref: commit,
          path: 'profiles/bitwild',
        ),
      );
      expect(plan.validation.gate, GateState.pass);

      // A branch is resolved once too, and kept as the binding's ref.
      final branch = await adoption.plan(bitwild(ref: 'main'));
      expect(branch.profile.id, _bitwild);
      expect(branch.profile.ref, 'main');
      expect(branch.profile.commit, commit);
      expect(branch.fetches.map((fetch) => (fetch.kind, fetch.ref)), [
        (ProfileFetchKind.refresh, 'main'),
      ]);
      final offline = await adoption.plan(bitwild(ref: 'main', offline: true));
      expect(offline.fetches, isEmpty);
      expect(offline.profile.id, _bitwild);

      final result = await adoption.apply(branch);
      expect(result.complete, isTrue);
      final validation = await validateWithProfileSources(
        bundle(),
        resolver: WayfinderProfileResolver(dataDirectory: data),
      );
      expect(validation.profileId, _bitwild);
      expect(validation.gate, GateState.pass);
    });

    test('a request naming the declared id adopts it', () async {
      final plan = await adoption.plan(bitwild(profile: _bitwild));
      expect(plan.profile.id, _bitwild);
      expect(plan.fetches, hasLength(1));
    });

    test('a request naming another id is a typed conflict, and nothing is '
        'written', () async {
      final before = await fileSnapshot(project.path);
      Object? failure;
      try {
        await adoption.plan(bitwild(profile: _acme));
      } on AdoptionProfileConflictException catch (error) {
        failure = error;
      }
      expect(
        failure,
        isA<AdoptionProfileConflictException>()
            .having((error) => error.code, 'code', 'adoption-profile-conflict')
            .having((error) => error.requested, 'requested', _acme)
            .having((error) => error.declared, 'declared', _bitwild)
            .having((error) => error.git, 'git', source.path)
            .having((error) => error.path, 'path', 'profiles/bitwild')
            .having((error) => error.commit, 'commit', commit)
            .having(
              (error) => error.message,
              'message',
              allOf(contains('bitwild-profile'), contains('acme-notes')),
            ),
      );
      expect(await fileSnapshot(project.path), before);
      expect(await gitStatus(project.path), isEmpty);
    });

    test('a request without one that cannot be a binding is refused before '
        'any Git, naming no stand-in id', () async {
      final request = AdoptionRequest(
        projectRoot: project.path,
        source: AdoptionSource(git: source.path, path: '../outside'),
      );
      await expectLater(
        adoption.plan(request),
        throwsA(
          isA<WayfinderException>()
              .having((error) => error.code, 'code', 'adoption-invalid')
              .having(
                (error) => error.message,
                'message',
                contains('/profiles/<id>/source/path'),
              ),
        ),
      );
      expect(await data.exists(), isFalse, reason: 'nothing was cloned');
    });

    test('a package whose id cannot be read fails as resolving it '
        'would', () async {
      final broken = await _repository(temp, 'broken', {
        'profile/wayfinder-profile.json': '{"format": 2, "id": "Not An Id"}',
      });
      await expectLater(
        adoption.plan(
          AdoptionRequest(
            projectRoot: project.path,
            source: AdoptionSource(git: broken.path, path: 'profile'),
          ),
        ),
        throwsA(
          isA<WayfinderProfileResolutionException>().having(
            (error) => error.diagnostic,
            'diagnostic',
            DiagnosticCode.profileInvalid,
          ),
        ),
      );
      await expectLater(
        adoption.plan(
          AdoptionRequest(
            projectRoot: project.path,
            source: AdoptionSource(git: broken.path, path: 'missing'),
          ),
        ),
        throwsA(
          isA<WayfinderProfileResolutionException>().having(
            (error) => error.message,
            'message',
            contains('has no package at missing/wayfinder-profile.json'),
          ),
        ),
      );
      expect(await gitStatus(project.path), isEmpty);
    });
  });

  group('host inputs', () {
    test('a host input that changes after planning is refused before '
        'anything is written', () async {
      final agents = File(p.join(project.path, 'AGENTS.md'));
      await agents.writeAsString('# Agents\n');
      await commitAll(project.path);
      final plan = await adoption.plan(
        bitwild(hostInputs: ['AGENTS.md', 'docs', './CONTRIBUTING.md']),
      );
      expect(plan.conflicts, isEmpty);

      await agents.writeAsString('# Agents\n\nEdited meanwhile.\n');
      final before = await fileSnapshot(project.path);
      final reports = <AdoptionStepReport>[];
      var hostRan = false;
      final failure = await applyFailure(
        plan,
        hostStep: () async => hostRan = true,
        onStep: reports.add,
      );
      expect(failure.code, 'adoption-stale');
      expect(failure.changedPaths, ['AGENTS.md']);
      expect(failure.message, contains('AGENTS.md'));
      expect(outcomes(failure.steps), [
        (AdoptionStep.check, AdoptionStepOutcome.failed),
      ]);
      expect(failure.steps.single.code, 'adoption-stale');
      expect(hostRan, isFalse);
      expect(await fileSnapshot(project.path), before);

      // One that appears, and a file below a directory input, count too.
      await agents.writeAsString('# Agents\n');
      await File(p.join(project.path, 'CONTRIBUTING.md')).writeAsString('');
      await Directory(p.join(project.path, 'docs')).create();
      await File(p.join(project.path, 'docs', 'guide.md')).writeAsString('');
      final appeared = await applyFailure(plan);
      expect(appeared.code, 'adoption-stale');
      expect(appeared.changedPaths, ['CONTRIBUTING.md', 'docs']);
    });

    test('unchanged host inputs let the host step write them', () async {
      final agents = File(p.join(project.path, 'AGENTS.md'));
      await agents.writeAsString('# Agents\n');
      final plan = await adoption.plan(bitwild(hostInputs: ['AGENTS.md']));
      final result = await adoption.apply(
        plan,
        hostStep: () =>
            agents.writeAsString('# Agents\n\n${plan.agentInstructions}'),
      );
      expect(result.complete, isTrue);
      expect(await agents.readAsString(), contains('### Knowledge bundle'));
      expect(plan.files.map((file) => file.path), isNot(contains('AGENTS.md')));
    });

    test('a host input outside the project is refused', () async {
      for (final path in [
        '../AGENTS.md',
        '/etc/hosts',
        '.git/config',
        '.GIT/config',
        'docs/.Git',
        '',
      ]) {
        await expectLater(
          adoption.plan(bitwild(hostInputs: [path])),
          throwsA(
            isA<WayfinderException>().having(
              (error) => error.code,
              'code',
              'adoption-invalid',
            ),
          ),
          reason: path,
        );
      }
      expect(await data.exists(), isFalse);
    });

    test('a host input that is a symbolic link counts with what it points '
        'to', () async {
      final agents = File(p.join(project.path, 'AGENTS.md'));
      await agents.writeAsString('# Agents\n');
      final claude = Link(p.join(project.path, 'CLAUDE.md'));
      await claude.create('AGENTS.md');
      await commitAll(project.path);
      final plan = await adoption.plan(bitwild(hostInputs: ['CLAUDE.md']));
      expect(plan.conflicts, isEmpty);

      // An edit made through the link.
      await agents.writeAsString('# Agents\n\nEdited meanwhile.\n');
      final before = await fileSnapshot(project.path);
      var hostRan = false;
      final edited = await applyFailure(
        plan,
        hostStep: () async => hostRan = true,
      );
      expect(edited.code, 'adoption-stale');
      expect(edited.changedPaths, ['CLAUDE.md']);
      expect(outcomes(edited.steps), [
        (AdoptionStep.check, AdoptionStepOutcome.failed),
      ]);
      expect(hostRan, isFalse);
      expect(await fileSnapshot(project.path), before);

      // The link moved to a file with the same bytes.
      await agents.writeAsString('# Agents\n');
      await File(p.join(project.path, 'README.md')).writeAsString('# Agents\n');
      await claude.update('README.md');
      final moved = await applyFailure(plan);
      expect(moved.changedPaths, ['CLAUDE.md']);

      // As planned again, the plan applies.
      await claude.update('AGENTS.md');
      expect((await adoption.apply(plan)).complete, isTrue);
    }, skip: Platform.isWindows ? 'needs symbolic links' : false);

    test('a host input that resolves outside the project or into .git is '
        'refused, and one moved outside after planning is stale', () async {
      final outside = await Directory(p.join(temp.path, 'outside')).create();
      await File(p.join(outside.path, 'AGENTS.md')).writeAsString('# Out\n');
      await Link(p.join(project.path, 'vendor')).create(outside.path);
      await Link(
        p.join(project.path, 'SHARED.md'),
      ).create(p.join('..', 'outside', 'AGENTS.md'));
      await Link(
        p.join(project.path, 'config'),
      ).create(p.join('.git', 'config'));
      await Link(p.join(project.path, 'here')).create('.');
      await Link(p.join(project.path, 'loop-a')).create('loop-b');
      await Link(p.join(project.path, 'loop-b')).create('loop-a');
      for (final path in [
        'vendor/AGENTS.md',
        'vendor',
        'SHARED.md',
        'config',
        'here',
        'loop-a',
      ]) {
        await expectLater(
          adoption.plan(bitwild(hostInputs: [path])),
          throwsA(
            isA<WayfinderException>()
                .having((error) => error.code, 'code', 'adoption-invalid')
                .having(
                  (error) => error.message,
                  'message',
                  contains('Host input $path'),
                ),
          ),
          reason: path,
        );
      }
      expect(await data.exists(), isFalse);

      // A directory linked within the project resolves there.
      final documentation = await Directory(
        p.join(project.path, 'documentation'),
      ).create();
      await File(
        p.join(documentation.path, 'AGENTS.md'),
      ).writeAsString('# Agents\n');
      final docs = Link(p.join(project.path, 'docs'));
      await docs.create('documentation');
      final plan = await adoption.plan(bitwild(hostInputs: ['docs/AGENTS.md']));
      expect(plan.conflicts, isEmpty);

      // Pointed outside after planning, it is stale, and nothing is written.
      await docs.update(outside.path);
      final before = await fileSnapshot(project.path);
      final failure = await applyFailure(plan);
      expect(failure.code, 'adoption-stale');
      expect(failure.changedPaths, ['docs/AGENTS.md']);
      expect(await fileSnapshot(project.path), before);
    }, skip: Platform.isWindows ? 'needs symbolic links' : false);
  });
}

Future<void> _chmod(String mode, String path) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) throw StateError('chmod failed: ${result.stderr}');
}

/// A concept whose `title` is [title].
String _concept(String title) =>
    '---\n'
    'type: Note\n'
    'title: $title\n'
    'description: A note.\n'
    '---\n'
    '\n'
    '# Note\n';

/// The package of `slow-notes`, whose one rule matches every concept title
/// against `^(a+)+$|^[A-Z]`: quick on its own tests and on a capitalized
/// title, and exponential on [_hostileTitle].
String _slowPackage() => jsonEncode({
  'format': 2,
  'id': 'slow-notes',
  'release': '1',
  'implements': {'id': 'okf', 'release': '0.2'},
  'rules': [
    {
      'id': 'title-shape',
      'category': 'structure',
      'severity': 'advisory',
      'status': 'stable',
      'description': 'A title is a run of a.',
      'message': 'The title is not a run of a.',
      'check': {
        'subject': 'frontmatter',
        'schema': {
          'properties': {
            'title': {'type': 'string', 'pattern': r'^(a+)+$|^[A-Z]'},
          },
        },
      },
      'tests': {
        'valid': [
          {'title': 'aaa'},
        ],
        'invalid': [
          {'title': 'b'},
        ],
      },
    },
  ],
});

/// A local Git repository under [temp] holding the slow Profile at
/// `profile`, committed once on `main`.
Future<Directory> _slowProfileSource(Directory temp) => _repository(
  temp,
  'slow',
  {'profile/wayfinder-profile.json': _slowPackage()},
);

/// A local Git repository under [temp] named [name], holding [files] by
/// path, committed once on `main`.
Future<Directory> _repository(
  Directory temp,
  String name,
  Map<String, String> files,
) async {
  final directory = await Directory(p.join(temp.path, name)).create();
  await fixtureGit(directory.path, ['init', '-q', '-b', 'main']);
  await fixtureGit(directory.path, [
    'config',
    'user.email',
    'test@example.test',
  ]);
  await fixtureGit(directory.path, ['config', 'user.name', 'Wayfinder Test']);
  await fixtureGit(directory.path, ['config', 'commit.gpgsign', 'false']);
  for (final MapEntry(key: path, value: text) in files.entries) {
    final file = File(p.joinAll([directory.path, ...path.split('/')]));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }
  await fixtureGit(directory.path, ['add', '.']);
  await fixtureGit(directory.path, ['commit', '-q', '-m', name]);
  return directory;
}

/// A one-concept bundle with [_hostileTitle], in memory, selected with the
/// slow Profile of [slow].
Future<KnowledgeAssessmentInput> _hostileInput(Directory slow) async {
  final package = ProfilePackage.parse(
    await File(
      p.join(slow.path, 'profile', 'wayfinder-profile.json'),
    ).readAsString(),
  );
  final documents = {
    'note.md': OkfDocument.parse(
      _concept(_hostileTitle),
      sourcePath: 'note.md',
    ),
  };
  final indexes = {'index.md': KnowledgeSeeds.rootIndex(okfVersion: '0.2')};
  final logs = {'log.md': KnowledgeSeeds.log(date: '2026-10-22')};
  return KnowledgeAssessmentInput.bundle(
    bundle: OkfBundleLoadResult(
      rootPath: p.join(slow.path, 'knowledge'),
      bundle: OkfBundle.fromDocuments(documents, indexes: indexes, logs: logs),
      documents: documents,
      indexes: indexes,
      logs: logs,
      assets: const [],
      report: OkfReport(),
    ),
    selection: SelectedProfile(
      EffectiveProfile.compose([package], project: ProjectVocabulary.none),
    ),
  );
}
