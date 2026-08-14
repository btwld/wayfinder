import 'package:okf/okf.dart';
import 'package:okf_profile/okf_profile.dart';
import 'package:test/test.dart';

void main() {
  test('manifest preserves its complete declared data', () {
    final ruleId = OkfProfileFindingIds.rule('minimum-area-size');
    expect(
      OkfProfileFindingIds.frontmatter('required').value,
      'profile/frontmatter-required',
    );
    final manifest = OkfProfileManifest(
      profile: 'example',
      version: '2026.2',
      extendsBase: 'okf/0.2',
      vocabularies: OkfProfileVocabularies(
        conceptTypes: <String>['Metric'],
        relationshipLabels: <String>['depends-on'],
      ),
      schemas: <String, Map<String, Object?>>{
        'Metric': <String, Object?>{
          'type': 'object',
          'required': <Object?>[
            'type',
            <String, Object?>{'nested': true},
          ],
        },
      },
      rules: <OkfProfileRuleActivation>[
        OkfProfileRuleActivation(
          id: ruleId,
          parameters: <String, Object?>{'minimum': 3},
        ),
      ],
      judgment: <OkfJudgmentDeclaration>[
        OkfJudgmentDeclaration(
          id: OkfProfileFindingIds.rule('concept-placement'),
          data: <String, Object?>{
            'note': 'Human review only.',
            'future': <Object?>['preserved'],
          },
        ),
      ],
    );

    expect(manifest.vocabularies.conceptTypes, <String>['Metric']);
    expect(
      manifest.vocabularies.relationshipLabels,
      <String>['depends-on'],
    );
    expect(manifest.schemas['Metric']!['type'], 'object');
    expect(manifest.rules.single.id, ruleId);
    expect(manifest.judgment.single.data['future'], <Object?>['preserved']);

    expect(
      () => manifest.schemas['Metric']!['type'] = 'string',
      throwsUnsupportedError,
    );
    expect(
      () => (manifest.schemas['Metric']!['required']! as List<Object?>)
          .add('title'),
      throwsUnsupportedError,
    );
    expect(
      () => manifest.judgment.single.data['future'] = null,
      throwsUnsupportedError,
    );
  });

  test('bundle declaration uses the Verdict suppression shape', () {
    final suppression = OkfFindingSuppression(
      id: OkfProfileFindingIds.rule('minimum-area-size'),
      note: 'Migration in progress.',
    );
    final declaration = OkfProfileDeclaration(
      profile: 'example',
      version: '2026.2',
      okfVersion: '0.2',
      suppressions: <OkfFindingSuppression>[suppression],
    );

    expect(okfProfileDeclarationFilename, 'profile.yaml');
    expect(declaration.suppressions.single, same(suppression));
    expect(
      () => declaration.suppressions.add(suppression),
      throwsUnsupportedError,
    );
  });

  test('profile rules register through the okf catalog seam', () {
    final catalog = OkfRuleCatalog();
    final entry = registerOkfProfileRule(
      catalog,
      code: 'minimum-area-size',
      prose: 'Areas contain a configured minimum number of concepts.',
      owner: 'example profile section 3.1',
      defaultSeverity: OkfFindingSeverity.advisory,
      parameterSchema: <String, Object?>{
        'minimum': <String, Object?>{'type': 'integer'},
      },
      run: (bundle, parameters) => <OkfFinding>[
        if (bundle.concepts.length < (parameters['minimum']! as int))
          OkfFinding(
            id: OkfProfileFindingIds.rule('minimum-area-size'),
            severity: OkfFindingSeverity.advisory,
            message: 'The bundle is below the configured minimum.',
          ),
      ],
    );

    expect(catalog.entries.single, same(entry));
    expect(entry.id.value, 'profile/minimum-area-size');
    expect(entry.prose, contains('minimum number'));
    expect(entry.owner, 'example profile section 3.1');
    expect(entry.defaultSeverity, OkfFindingSeverity.advisory);
    expect(entry.parameterSchema['minimum'], isA<Map<String, Object?>>());
    expect(
      entry.run(
        OkfBundle.fromDocuments(const <String, OkfDocument>{}),
        <String, Object?>{'minimum': 3},
      ),
      hasLength(1),
    );
  });

  test('dispatch types connect resolution, activation, and Verdict', () {
    final declaration = OkfProfileDeclaration(
      profile: 'example',
      version: '2026.2',
      okfVersion: '0.2',
    );
    final manifest = OkfProfileManifest(
      profile: 'example',
      version: '2026.2',
      extendsBase: 'okf/0.2',
    );
    final catalog = OkfRuleCatalog();
    final entry = registerOkfProfileRule(
      catalog,
      code: 'example-rule',
      prose: 'Example rule.',
      owner: 'example profile',
      defaultSeverity: OkfFindingSeverity.advisory,
      parameterSchema: const <String, Object?>{},
      run: (bundle, parameters) => const <OkfFinding>[],
    );
    final resolved = OkfResolvedProfile(
      declaration: declaration,
      manifest: manifest,
    );
    final activated = OkfActivatedProfile(
      resolved: resolved,
      rules: <OkfActivatedProfileRule>[
        OkfActivatedProfileRule(
          entry: entry,
          parameters: <String, Object?>{'enabled': true},
        ),
      ],
    );
    final report = OkfReport();
    final verdict = OkfVerdict.of(report);

    expect(activated.resolved.manifest, same(manifest));
    expect(activated.rules.single.entry, same(entry));
    expect(verdict.report, same(report));
    expect(verdict.result, OkfExitCode.success);

    expect(
      const OkfNoProfileDeclared().findingId,
      OkfProfileFindingIds.noProfileDeclared,
    );
    expect(
      OkfUnknownProfileRelease(declaration).findingId,
      OkfProfileFindingIds.unknownProfileRelease,
    );
  });
}
