import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/adoption.dart';
import 'package:wayfinder/wayfinder.dart';

/// The adopt-knowledge-bundle skill's SEEDING.md shows the seed
/// `KnowledgeSeeds` writes; this keeps the two equal.
void main() {
  late List<String> blocks;

  setUpAll(() async {
    // .gitattributes pins skills/** to LF; normalising here as well keeps the
    // comparison independent of how the file was checked out.
    final seeding = (await File(
      p.join('..', '..', 'skills', 'adopt-knowledge-bundle', 'SEEDING.md'),
    ).readAsString()).replaceAll('\r\n', '\n');
    blocks = [
      for (final match in RegExp(
        r'^(`{3,})[a-z]*\n(.*?)^\1$',
        multiLine: true,
        dotAll: true,
      ).allMatches(seeding))
        match[2]!,
    ];
  });

  test('SEEDING.md shows the five seed blocks', () {
    expect(blocks, hasLength(5));
  });

  test('wayfinder.json', () {
    expect(
      blocks[0],
      KnowledgeSeeds.configuration(
        profile: '<profile-id>',
        git: '<repository URL>',
        ref: '<release tag, branch, or commit>',
        path: '<package directory in that repository>',
      ),
    );
  });

  test('the OKF root files', () {
    expect(
      blocks[1],
      KnowledgeSeeds.rootIndex(
        okfVersion: '<OKF release the Profile implements>',
      ),
    );
    expect(blocks[2], KnowledgeSeeds.log(date: '<YYYY-MM-DD>'));
  });

  test('the .gitignore line', () {
    expect(blocks[3], '${KnowledgeSeeds.okfLockIgnore()}\n');
  });

  test('the agent instructions', () {
    expect(
      blocks[4],
      '${KnowledgeSeeds.knowledgeBundleInstructions()}\n'
      '${KnowledgeSeeds.wayfinderInstructions()}',
    );
  });

  test('the seeded configuration parses and names the bundle explicitly', () {
    final text = KnowledgeSeeds.configuration(
      profile: 'acme-notes',
      git: 'https://example.test/profiles.git',
      ref: 'v1',
      path: 'acme',
      bundle: 'docs/knowledge',
    );
    final config = WayfinderProjectConfig.parse(text);
    expect(config.bundles.single.path, 'docs/knowledge');
    expect(text, contains('"applies_to": ["./docs/knowledge"]'));
  });

  test('the root index declares the OKF release as a YAML string', () {
    expect(
      KnowledgeSeeds.rootIndex(okfVersion: '0.2'),
      '---\nokf_version: "0.2"\n---\n\n# Bundle\n\n* [Knowledge Log](log.md)\n',
    );
    expect(KnowledgeSeeds.isoDate(DateTime(987, 3, 4)), '0987-03-04');
    expect(KnowledgeSeeds.okfLockIgnore(bundle: './kb/'), 'kb/.okf.lock');
  });

  test('instruction lines end the Knowledge bundle block', () {
    expect(
      KnowledgeSeeds.knowledgeBundleInstructions(lines: ['One.', 'Two.']),
      endsWith("bundle's chain.\n\nOne.\nTwo.\n"),
    );
  });
}
