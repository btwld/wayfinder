import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:okf/okf_io.dart' show OkfBundleLoader, OkfBundleLoadResult;
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_reader_local/wayfinder_reader_local.dart';

import 'local_project_test.dart' show failure;

ProfileSelection selection({bool paths = false, bool actors = false}) =>
    SelectedProfile(
      EffectiveProfile.compose([
        ProfilePackage.parse(
          jsonEncode({
            'format': 3,
            'id': 'test-profile',
            'release': '1.0',
            'implements': {'id': 'okf', 'release': '0.2'},
            'rules': [
              if (actors)
                {
                  'id': 'used-actor-registered',
                  'category': 'vocabulary',
                  'severity': 'error',
                  'status': 'stable',
                  'description': 'Used actors must be registered.',
                  'message': 'Used actor {id} must be registered.',
                  'check': {
                    'subject': 'actor',
                    'schema': {
                      'properties': {
                        'id': {r'$ref': r'#/$defs/profile.actors'},
                      },
                    },
                  },
                  'tests': {
                    'slots': {
                      'profile.actors': ['process:registered'],
                    },
                    'valid': [
                      {'id': 'process:registered', 'first_use': 'a.md'},
                    ],
                    'invalid': [
                      {'id': 'process:unregistered', 'first_use': 'a.md'},
                    ],
                  },
                },
              if (paths)
                {
                  'id': 'paths',
                  'category': 'structure',
                  'severity': 'error',
                  'status': 'stable',
                  'description': 'Resources must exist.',
                  'message': 'Missing {target}.',
                  'check': {
                    'builtin': 'path-targets-exist',
                    'params': {
                      'fields': ['resource'],
                    },
                  },
                },
            ],
          }),
        ),
      ]),
    );

ProfileValidator retainedValidator(Map<String, bool> observations) =>
    ProfileValidator(
      outsideBundleExists: (path) =>
          observations[path] ??
          (throw KnowledgeFailure(
            KnowledgeFailureCode.unavailable,
            'validate',
            'No retained observation.',
            path: path,
          )),
    );

Future<ProfileValidationResult> validateApart(
  OkfBundleLoadResult loaded,
  ProfileSelection selection,
  Map<String, bool> observations,
) => Isolate.run(
  () => retainedValidator(observations).validateLoaded(loaded, selection),
);

void main() {
  late Directory root;
  late LocalKnowledgeProject project;
  Future<void> write(String path, String text) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reader-assessment-');
    await write(
      'knowledge/index.md',
      '---\nokf_version: "0.2"\n---\n# Index\n\n* [A](a.md) - A note.\n',
    );
    await write(
      'knowledge/log.md',
      '# Bundle Update Log\n\n## 2026-11-08\n\n* **Creation**: Created notes.\n',
    );
    await write(
      'knowledge/a.md',
      '---\ntype: Guide\ntitle: Original\n---\nBody\n',
    );
    project = await LocalKnowledgeProject.open(
      root: root,
      id: 'p',
      bundleIds: {'knowledge': 'docs'},
    );
  });
  tearDown(() async {
    await project.close();
    await root.delete(recursive: true);
  });

  test(
    'retained validation without observations refuses synthetic-root disk fallback',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: ../outside.txt\n---\nBody\n',
      );
      await write('outside.txt', 'exists in the granted root');
      final snapshot = await project.refresh();
      expect(
        () => const ProfileValidator().validateLoaded(
          buildOkfBundle(snapshot.loadBundle('docs')),
          selection(paths: true),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'cause',
            contains('outsideBundleExists'),
          ),
        ),
      );
    },
  );

  test(
    'retained load matches the on-disk loader collections and ordering',
    () async {
      await write(
        'knowledge/a/b.md',
        '---\ntype: Guide\ntitle: B\n---\nBody\n',
      );
      await write('knowledge/a/index.md', '# Notes\n\n* [B](b.md) - B note.\n');
      await write(
        'knowledge/a/log.md',
        '# Bundle Update Log\n\n## 2026-11-08\n\n* **Creation**: Created B.\n',
      );
      await write('knowledge/a/.okf.lock', 'protocol');
      await write('knowledge/.asset', 'hidden regular asset');
      await write('knowledge/a/asset.txt', 'attachment');
      final snapshot = await project.refresh();
      final loaded = buildOkfBundle(snapshot.loadBundle('docs'));
      final disk = await const OkfBundleLoader().inspect(
        '${root.path}/knowledge',
      );
      expect(loaded.paths, disk.paths);
      expect(loaded.documents.keys.toList(), disk.documents.keys.toList());
      expect(loaded.indexes, disk.indexes);
      expect(loaded.logs, disk.logs);
      expect(loaded.assets, disk.assets);
      expect(
        loaded.validate().report.toJson(),
        disk.validate().report.toJson(),
      );
    },
  );

  test(
    'observations use bundle identities and idle reuse ignores identity sort order',
    () async {
      await project.close();
      await write(
        'wayfinder.json',
        '{"version":1,"profiles":{"demo":{"source":{"git":"https://invalid.example/never","ref":"main","path":"profile"},"applies_to":["knowledge","other"]}}}',
      );
      await write(
        'other/a.md',
        '---\ntype: Guide\ntitle: Other\nresource: ../target.txt\n---\n',
      );
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: ../target.txt\n---\n',
      );
      await write('target.txt', 'present');
      project = await LocalKnowledgeProject.open(
        root: root,
        id: 'p',
        bundleIds: {'knowledge': 'z-id', 'other': 'a-id'},
      );
      final snapshot = await project.refresh();
      expect(snapshot.externalPathObservations, {
        'z-id': {'../target.txt': true},
        'a-id': {'../target.txt': true},
      });
      final idle = await project.refresh();
      expect(
        idle.externalPathObservations,
        same(snapshot.externalPathObservations),
      );
    },
  );

  test(
    'validates retained displayed bytes in an isolate after live edits',
    () async {
      final old = await project.refresh();
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: Changed\n---\nNew\n',
      );
      final next = await project.refresh();
      final selected = selection();
      final loaded = buildOkfBundle(old.loadBundle('docs'));
      expect(loaded.documents['a.md']!.metadata.title, 'Original');
      expect(
        buildOkfBundle(
          next.loadBundle('docs'),
        ).documents['a.md']!.metadata.title,
        'Changed',
      );
      final result = await validateApart(
        loaded,
        selected,
        old.externalPathObservations['docs']!,
      );
      expect(result.gate, GateState.pass, reason: result.toJson().toString());
      expect(await File('${root.path}/knowledge/.okf.lock').exists(), isFalse);
      expect(await Directory('${root.path}/.wayfinder').exists(), isFalse);
    },
  );

  test(
    'unknown Profile stays incomplete; later selection needs no recapture',
    () async {
      await write('wayfinder.lock', 'retained lock bytes');
      final snapshot = await project.refresh();
      final lock = snapshot.files.singleWhere(
        (f) => f.handle.path == 'wayfinder.lock',
      );
      expect((await snapshot.read(lock.handle)).text, 'retained lock bytes');
      final loaded = buildOkfBundle(snapshot.loadBundle('docs'));
      final validator = retainedValidator(
        snapshot.externalPathObservations['docs']!,
      );
      final before = validator.validateLoaded(
        loaded,
        UnselectedProfile([
          EngineDiagnostic(DiagnosticCode.profileUnresolved, 'Not cached.'),
        ]),
      );
      final after = validator.validateLoaded(loaded, selection());
      expect(
        before.gate,
        GateState.incomplete,
        reason: before.toJson().toString(),
      );
      expect(after.gate, GateState.pass);
    },
  );

  test(
    'external existence is captured and validated after live deletion',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: ../outside.txt\n---\nBody\n',
      );
      await write('outside.txt', 'present');
      final snapshot = await project.refresh();
      final observations = snapshot.externalPathObservations['docs']!;
      expect(observations, {'../outside.txt': true});
      await File('${root.path}/outside.txt').delete();
      final selected = selection(paths: true);
      final result = await validateApart(
        buildOkfBundle(snapshot.loadBundle('docs')),
        selected,
        observations,
      );
      expect(result.gate, GateState.pass);
      final next = await project.refresh();
      expect(next.externalPathObservations['docs'], {'../outside.txt': false});
      expect(
        next.files.map((f) => (f.handle.bundle, f.handle.path, f.digest)),
        snapshot.files.map((f) => (f.handle.bundle, f.handle.path, f.digest)),
      );
      expect(next.revision, isNot(snapshot.revision));
      expect(
        retainedValidator(next.externalPathObservations['docs']!)
            .validateLoaded(buildOkfBundle(next.loadBundle('docs')), selected)
            .gate,
        GateState.fail,
      );
    },
  );

  test(
    'external absence is retained after creation; idle refresh reuses observations',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: ../outside.txt\n---\nBody\n',
      );
      final snapshot = await project.refresh();
      expect(snapshot.externalPathObservations['docs'], {
        '../outside.txt': false,
      });
      final idle = await project.refresh();
      expect(idle.revision, snapshot.revision);
      expect(
        idle.externalPathObservations,
        same(snapshot.externalPathObservations),
      );
      await write('outside.txt', 'new');
      expect(
        retainedValidator(snapshot.externalPathObservations['docs']!)
            .validateLoaded(
              buildOkfBundle(snapshot.loadBundle('docs')),
              selection(paths: true),
            )
            .gate,
        GateState.fail,
      );
      expect((await project.refresh()).externalPathObservations['docs'], {
        '../outside.txt': true,
      });
    },
  );

  test(
    'external paths beyond the grant or through links remain unknown',
    () async {
      for (final target in [
        '../../outside.txt',
        '../linked.txt',
        '../linked-dir/file.txt',
      ]) {
        await write(
          'knowledge/a.md',
          '---\ntype: Guide\ntitle: A\nresource: $target\n---\nBody\n',
        );
        if (!await Link('${root.path}/linked.txt').exists()) {
          await write('target.txt', 'present');
          await Link('${root.path}/linked.txt').create('target.txt');
          await Link('${root.path}/linked-dir').create('knowledge');
        }
        final snapshot = await project.refresh();
        expect(snapshot.externalPathObservations['docs'], isEmpty);
        expect(
          () => retainedValidator(snapshot.externalPathObservations['docs']!)
              .validateLoaded(
                buildOkfBundle(snapshot.loadBundle('docs')),
                selection(paths: true),
              ),
          throwsA(failure(KnowledgeFailureCode.unavailable)),
        );
      }
    },
  );

  test(
    'nested coordination files stay browsable but are not OKF assets',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: /a/.okf.lock\n---\nBody\n',
      );
      await write('knowledge/a/.okf.lock', 'nested coordination file');
      final snapshot = await project.refresh();
      final lock = snapshot.files.singleWhere(
        (f) => f.handle.path == 'a/.okf.lock',
      );
      expect(
        (await snapshot.read(lock.handle)).text,
        'nested coordination file',
      );
      final selected = selection(paths: true);
      final loaded = buildOkfBundle(snapshot.loadBundle('docs'));
      expect(loaded.assets, isNot(contains('a/.okf.lock')));
      expect(loaded.paths, isNot(contains('a/.okf.lock')));
      final result = retainedValidator(
        snapshot.externalPathObservations['docs']!,
      ).validateLoaded(loaded, selected);
      final live = await const ProfileValidator().validate(
        '${root.path}/knowledge',
        selected,
      );
      expect(live.gate, GateState.fail);
      expect(live.findings.single.id, 'test-profile/paths');
      expect(live.findings.single.path, 'a.md');
      expect(result.toJson(), live.toJson());
    },
  );

  test('actor first-use findings follow the core loader full-path order', () async {
    await write(
      'knowledge/a.md',
      '---\ntype: Guide\ntitle: A\ngenerated: {by: process:unregistered, at: 2026-11-08T00:00:00Z}\n---\nBody\n',
    );
    await write(
      'knowledge/a/b.md',
      '---\ntype: Guide\ntitle: B\ngenerated: {by: process:unregistered, at: 2026-11-08T00:00:00Z}\n---\nBody\n',
    );
    await write(
      'knowledge/a/index.md',
      '# Notes\n\n* [B](b.md) - Another note.\n',
    );
    final snapshot = await project.refresh();
    // Directory traversal intentionally differs from full-path lexical order.
    final capturedPaths = snapshot.files.map((f) => f.handle.path).toList();
    expect(
      capturedPaths.indexOf('a/b.md'),
      lessThan(capturedPaths.indexOf('a.md')),
    );
    final selected = selection(actors: true);
    final loaded = buildOkfBundle(snapshot.loadBundle('docs'));
    expect(loaded.documents.keys.toList(), ['a.md', 'a/b.md']);
    final result = retainedValidator(
      snapshot.externalPathObservations['docs']!,
    ).validateLoaded(loaded, selected);
    final live = await const ProfileValidator().validate(
      '${root.path}/knowledge',
      selected,
    );
    expect(live.gate, GateState.fail);
    expect(live.findings.single.id, 'test-profile/used-actor-registered');
    expect(live.findings.single.path, 'a.md');
    expect(result.toJson(), live.toJson());
  });

  test('malformed Markdown refuses before validating partial bytes', () async {
    await write('knowledge/bad.md', '---\ntype: [\n---\n');
    final snapshot = await project.refresh();
    expect(
      () => buildOkfBundle(snapshot.loadBundle('docs')),
      throwsA(failure(KnowledgeFailureCode.invalidContent)),
    );
  });

  test(
    'loaded internal targets follow retained inventory, not current disk',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: /asset.txt\n---\nBody\n',
      );
      await write('knowledge/asset.txt', 'retained');
      final snapshot = await project.refresh();
      await File('${root.path}/knowledge/asset.txt').delete();
      final selected = selection(paths: true);
      final result = retainedValidator(
        snapshot.externalPathObservations['docs']!,
      ).validateLoaded(buildOkfBundle(snapshot.loadBundle('docs')), selected);
      expect(result.gate, GateState.pass, reason: result.toJson().toString());
      final live = await const ProfileValidator().validate(
        '${root.path}/knowledge',
        selected,
      );
      expect(live.gate, GateState.fail);
    },
  );
}
