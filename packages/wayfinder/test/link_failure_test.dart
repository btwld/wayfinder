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
    bundle = await Directory.systemTemp.createTemp('wayfinder-links-');
    Future<void> write(String path, String text) async {
      final file = File(p.joinAll([bundle.path, ...p.posix.split(path)]));
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    await write(
      'source.md',
      '---\ntype: Guide\nrelationships:\n'
          '  - {relationship: depends-on, resource: target.md}\n'
          '---\n\nSee [target](target.md).\n',
    );
    await write('target.md', '---\ntype: Guide\n---\n');
  });

  tearDown(() => bundle.delete(recursive: true));

  EffectiveProfile profile(String release) => EffectiveProfile(
    [RuleCatalog.installed(builtinProfileId, release)],
    const Vocabulary(
      standardTypes: [],
      types: ['Guide'],
      relationships: ['depends-on'],
    ),
  );

  Map<String, Object?> source(BundleFacts facts) => facts
      .of(SubjectKind.concept)
      .singleWhere((subject) => subject.locations['self'] == 'source.md')
      .facts;

  List<String> linkFindings(EffectiveProfile profile, BundleFacts facts) => [
    for (final finding in evaluate(profile, facts).findings)
      if (finding.id.contains('link') || finding.id.contains('relationship'))
        '${finding.id} ${finding.path}',
  ];

  for (final (release, path) in [
    (legacyProfileRelease, 'profile.md'),
    (externalProfileRelease, 'index.md'),
  ]) {
    test('$release reports a link resolution failure at $path and assesses '
        'no link rule', () async {
      final loaded = await const OkfBundleLoader().inspect(bundle.path);
      final effective = profile(release);
      final facts = BundleFacts.project(
        loaded,
        profile: effective,
        buildGraph: (_) => throw StateError('forced'),
      );
      expect(
        source(facts).keys,
        isNot(contains(anyOf('edges', 'relationships', 'inbound'))),
      );
      expect(linkFindings(effective, facts), [
        'concepta-profile/link-graph-unavailable $path',
      ]);
      final unavailable = evaluate(effective, facts).findings.singleWhere(
        (finding) => finding.id == 'concepta-profile/link-graph-unavailable',
      );
      expect(unavailable.message, contains('forced'));
    });
  }

  test(
    '2026.3 assesses the relative relationship target when links resolve',
    () async {
      final loaded = await const OkfBundleLoader().inspect(bundle.path);
      final effective = profile(externalProfileRelease);
      final facts = BundleFacts.project(loaded, profile: effective);
      expect(source(facts)['relationships'], hasLength(1));
      expect(linkFindings(effective, facts), [
        'concepta-profile/internal-link-bundle-relative source.md',
        'concepta-profile/relationship-bundle-relative source.md',
      ]);
    },
  );
}
