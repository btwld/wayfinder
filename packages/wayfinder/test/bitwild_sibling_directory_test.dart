import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

/// Bitwild's directory exemptions are a Profile regression. The golden lives
/// with the package; the engine contract golden covers only an independent
/// Profile.
void main() {
  test('Bitwild keeps its directory exemptions in its own golden', () async {
    final project = await copyFixture('configured-project');
    addTearDown(() => project.delete(recursive: true));
    final bundle = p.join(project.path, 'knowledge');
    final template = await File(p.join(bundle, 'sample.md')).readAsString();
    Future<void> write(String path, String content) async {
      final file = File(p.joinAll([bundle, ...p.posix.split(path)]));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }

    for (final stem in [
      'billing',
      'interactions',
      'interactions/dailies',
      'references',
      'references/vendor',
      'references.vendor',
      'references-extra',
      'department/references',
    ]) {
      await write('$stem.md', template);
      await write('$stem/note.md', template);
    }
    await write('asset.md', template);
    await write(
      'asset/original.bin',
      'An asset also makes a directory visible.',
    );
    await write('empty.md', template);
    await Directory(p.join(bundle, 'empty')).create();

    final configuration = WayfinderProjectConfig.parse(
      await File(p.join(project.path, 'wayfinder.json')).readAsString(),
    );
    final result = await const ProfileValidator().validate(
      bundle,
      SelectedProfile(
        EffectiveProfile.compose([
          bitwild,
        ], project: configuration.profiles[bitwild.id]!.project),
      ),
      fix: true,
    );
    expect(
      {
        'okf': result.okfState.wireValue,
        'gate': result.gate.wireValue,
        'findings': [
          for (final finding in result.findings)
            {
              'id': finding.id,
              'severity': finding.severity.wireValue,
              'path': finding.path,
            },
        ],
      },
      jsonDecode(
        await File(
          '../../profiles/bitwild/test/goldens/sibling-directory.json',
        ).readAsString(),
      ),
    );
  });
}
