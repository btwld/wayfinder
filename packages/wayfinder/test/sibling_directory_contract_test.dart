import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

void main() {
  test(
    'directory facts are neutral and Bitwild owns its placement exceptions',
    () async {
      final project = await copyFixture('configured-project');
      addTearDown(() => project.delete(recursive: true));
      final bundle = p.join(project.path, 'knowledge');
      final template = await File(p.join(bundle, 'sample.md')).readAsString();
      Future<void> write(String path, String content) async {
        final file = File(p.joinAll([bundle, ...p.posix.split(path)]));
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
      }

      // The shipped structure fixture has an ordinary same-stem pair and
      // references/vendor/; Bitwild's example also carries references/ mirrors.
      // Exercise those existing directory forms under a Profile with no Bitwild
      // policy, including root names, nested names and near-prefix controls.
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
      final bitwildResult = await const ProfileValidator().validate(
        bundle,
        SelectedProfile(
          EffectiveProfile.compose([
            bitwild,
          ], project: configuration.profiles[bitwild.id]!.project),
        ),
        fix: true,
      );
      final neutral = ProfilePackage.parse(
        packageJson(
          id: 'directory-probe',
          rules: [
            ruleJson(
              'same-stem-directory',
              subject: 'concept',
              schema: {
                'properties': {
                  'sibling_directory': {'const': false},
                },
              },
              valid: [
                {'sibling_directory': false},
              ],
              invalid: [
                {'sibling_directory': true},
              ],
            ),
          ],
        ),
      );
      final neutralResult = await const ProfileValidator().validate(
        bundle,
        SelectedProfile(EffectiveProfile.compose([neutral])),
      );
      Map<String, Object?> projection(ProfileValidationResult result) => {
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
      };
      final expected = jsonDecode(
        await File(
          'test/contract_goldens/sibling-directory.json',
        ).readAsString(),
      );
      expect({
        'independent_profile': projection(neutralResult),
        'bitwild': projection(bitwildResult),
      }, expected);
    },
  );
}
