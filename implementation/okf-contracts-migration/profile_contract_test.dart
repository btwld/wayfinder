import 'package:okf/okf.dart';
import 'package:test/test.dart';

void main() {
  test('finding contract owns identifiers and report projections', () {
    final base = OkfFindingId.base('missing-type');
    final profile = OkfFindingId.profile('unknown-profile-release');
    final schema = OkfFindingId.frontmatter('required');
    final suppression = OkfSuppression(
      findingId: profile,
      note: 'Pinned engine cannot read this release yet.',
    );
    final finding = OkfFinding(
      id: profile,
      severity: OkfFindingSeverity.advisory,
      message: 'The declared profile release is unknown.',
      location: const OkfFindingLocation(logicalPath: 'profile.yaml'),
    );
    final report = _Report(
      <OkfReportedFinding>[
        OkfReportedFinding(finding: finding, suppression: suppression),
      ],
    );

    expect(base.value, 'okf/missing-type');
    expect(profile.value, 'profile/unknown-profile-release');
    expect(schema.value, 'profile/frontmatter-required');
    expect(OkfFindingId.parse(schema.value), schema);
    expect(report.toText(), contains(profile.value));
    expect(report.toJson()['suppressed_count'], 1);
    expect(report.verdict.exitCode, 0);
  });

  test('profile contract preserves manifest and declaration data', () {
    final ruleId = OkfFindingId.profile('minimum-area-size');
    final manifest = OkfProfileManifest(
      profile: 'concepta',
      version: '2026.2',
      extendsBase: 'okf/0.2',
      vocabularies: <String, Iterable<String>>{
        'types': <String>['Metric'],
        'labels': <String>['depends-on'],
      },
      schemas: <String, Map<String, Object?>>{
        'Metric': <String, Object?>{
          'type': 'object',
          'required': <String>['type'],
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
          id: OkfFindingId.profile('concept-placement'),
          data: <String, Object?>{'note': 'Human review only.'},
        ),
      ],
    );
    final declaration = OkfProfileDeclaration(
      profile: 'concepta',
      version: '2026.2',
      okfVersion: '0.2',
      suppressions: <OkfSuppression>[
        OkfSuppression(findingId: ruleId),
      ],
    );

    expect(manifest.vocabularies['types'], <String>['Metric']);
    expect(manifest.schemas['Metric']!['type'], 'object');
    expect(manifest.rules.single.id, ruleId);
    expect(manifest.judgment.single.data['note'], 'Human review only.');
    expect(declaration.suppressions.single.findingId, ruleId);
  });

  test('catalog entries run against a bundle and manifest', () {
    final bundle = OkfBundle.fromDocuments(const <String, OkfDocument>{});
    final manifest = OkfProfileManifest(
      profile: 'example',
      version: '1',
      extendsBase: 'okf/0.2',
    );
    final entry = OkfRuleCatalogEntry(
      id: OkfFindingId.profile('example-rule'),
      prose: 'Example profiles require an example concept.',
      owner: OkfRuleOwner.profile,
      defaultSeverity: OkfFindingSeverity.advisory,
      parameterSchema: const <String, Object?>{
        'minimum': <String, Object?>{'type': 'integer'},
      },
      run: (loadedBundle, loadedManifest) sync* {
        if (loadedBundle.concepts.isEmpty) {
          yield OkfFinding(
            id: OkfFindingId.profile('example-rule'),
            severity: OkfFindingSeverity.advisory,
            message: '${loadedManifest.profile} has no concepts.',
          );
        }
      },
    );

    expect(entry.run(bundle, manifest).single.id, entry.id);
    expect(entry.parameterSchema['minimum'], isNotNull);
  });

  test('bundle changes expose prospective validation and atomic apply',
      () async {
    final manifest = OkfProfileManifest(
      profile: 'example',
      version: '1',
      extendsBase: 'okf/0.2',
    );
    final bundle = OkfBundle.fromDocuments(const <String, OkfDocument>{});
    final changeSet = _ChangeSet(<OkfBundleChange>[
      OkfCreateConceptChange(
        path: 'metrics/revenue.md',
        document: OkfDocument(
          frontmatter: <String, Object?>{'type': 'Metric'},
        ),
      ),
      OkfUpdateConceptChange(
        conceptId: OkfConceptId('metrics/revenue'),
        setFrontmatter: const <String, Object?>{'title': 'Revenue'},
      ),
      OkfLinkConceptsChange(
        source: OkfConceptId('metrics/revenue'),
        target: OkfConceptId('datasets/orders'),
        label: 'derived-from',
      ),
      OkfDeprecateConceptChange(
        conceptId: OkfConceptId('metrics/revenue'),
        note: 'Replaced by net revenue.',
      ),
    ]);

    expect(changeSet.validate(bundle, manifest).verdict, OkfVerdict.passed);
    final result = await changeSet.apply(
      rootPath: '/bundle',
      bundle: bundle,
      manifest: manifest,
    );
    expect(result.status, OkfBundleApplyStatus.applied);
    expect(result.changedPaths, contains('metrics/revenue.md'));
  });

  test('index and log entry models share the public interface', () {
    const index = OkfIndexEntry(
      type: 'Metric',
      title: 'Revenue',
      link: 'revenue.md',
      description: 'Recognized revenue.',
    );
    final log = OkfLogEntry(
      date: DateTime.utc(2026, 8, 14),
      description: 'Created [Revenue](metrics/revenue.md).',
    );

    expect(index.link, 'revenue.md');
    expect(log.date, DateTime.utc(2026, 8, 14));
  });
}

final class _Report implements OkfReport {
  _Report(this.findings);

  @override
  final List<OkfReportedFinding> findings;

  @override
  OkfVerdict get verdict => OkfVerdict.passed;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'suppressed_count':
            findings.where((finding) => finding.isSuppressed).length,
      };

  @override
  String toText() =>
      findings.map((reported) => reported.finding.id.value).join('\n');
}

final class _ChangeSet implements OkfBundleChangeSet {
  _ChangeSet(this.changes);

  @override
  final List<OkfBundleChange> changes;

  @override
  Future<OkfBundleApplyResult> apply({
    required String rootPath,
    required OkfBundle bundle,
    required OkfProfileManifest manifest,
  }) async =>
      OkfBundleApplyResult(
        status: OkfBundleApplyStatus.applied,
        report: validate(bundle, manifest),
        changedPaths: const <String>['metrics/revenue.md'],
      );

  @override
  OkfReport validate(OkfBundle bundle, OkfProfileManifest manifest) =>
      _Report(const <OkfReportedFinding>[]);
}
