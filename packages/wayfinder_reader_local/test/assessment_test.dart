import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_reader_local/wayfinder_reader_local.dart';

import 'local_project_test.dart' show failure;

ProfileSelection selection({bool paths = false}) => SelectedProfile(
  EffectiveProfile.compose([
    ProfilePackage.parse(
      jsonEncode({
        'format': 3,
        'id': 'test-profile',
        'release': '1.0',
        'implements': {'id': 'okf', 'release': '0.2'},
        'rules': [
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

Future<ProfileValidationResult> validateApart(
  KnowledgeBundleAssessmentInput input,
  ProfileSelection selection,
) => Isolate.run(() => input.validate(selection));

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
    'validates retained displayed bytes in an isolate after live edits',
    () async {
      final old = await project.refresh();
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: Changed\n---\nNew\n',
      );
      final next = await project.refresh();
      final selected = selection();
      final result = await old.assessBundle('docs', (input) async {
        expect(input.loaded.documents['a.md']!.metadata.title, 'Original');
        expect(input.capture.revision, old.revision);
        return validateApart(input, selected);
      });
      expect(result.revision, old.revision);
      expect(result.revision, isNot(next.revision));
      expect(
        result.value.gate,
        GateState.pass,
        reason: result.value.toJson().toString(),
      );
      expect(await File('${root.path}/knowledge/.okf.lock').exists(), isFalse);
      expect(await Directory('${root.path}/.wayfinder').exists(), isFalse);
    },
  );

  test(
    'unknown Profile stays incomplete; later selection needs no recapture',
    () async {
      await write('wayfinder.lock', 'retained lock bytes');
      final snapshot = await project.refresh();
      final before = await snapshot.assessBundle('docs', (input) {
        expect(
          utf8.decode(
            input.capture.files
                .singleWhere((f) => f.path == 'wayfinder.lock')
                .bytes,
          ),
          'retained lock bytes',
        );
        return input.validate(
          UnselectedProfile([
            EngineDiagnostic(DiagnosticCode.profileUnresolved, 'Not cached.'),
          ]),
        );
      });
      final after = await snapshot.assessBundle(
        'docs',
        (input) => input.validate(selection()),
      );
      expect(
        before.value.gate,
        GateState.incomplete,
        reason: before.value.toJson().toString(),
      );
      expect(after.value.gate, GateState.pass);
      expect(before.revision, after.revision);
    },
  );

  test(
    'external observations refuse rather than consulting live disk',
    () async {
      await write(
        'knowledge/a.md',
        '---\ntype: Guide\ntitle: A\nresource: ../outside.txt\n---\nBody\n',
      );
      await write('outside.txt', 'exists live');
      final snapshot = await project.refresh();
      await expectLater(
        snapshot.assessBundle(
          'docs',
          (input) => input.validate(selection(paths: true)),
        ),
        throwsA(failure(KnowledgeFailureCode.unavailable)),
      );
    },
  );

  test('malformed Markdown refuses without assessing partial bytes', () async {
    await write('knowledge/bad.md', '---\ntype: [\n---\n');
    final snapshot = await project.refresh();
    await expectLater(
      snapshot.assessBundle('docs', (_) => fail('partial input')),
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
      final result = await snapshot.assessBundle(
        'docs',
        (input) => input.validate(selected),
      );
      expect(
        result.value.gate,
        GateState.pass,
        reason: result.value.toJson().toString(),
      );
      final live = await const ProfileValidator().validate(
        '${root.path}/knowledge',
        selected,
      );
      expect(live.gate, GateState.fail);
    },
  );
}
