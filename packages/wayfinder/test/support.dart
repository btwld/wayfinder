import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wayfinder/wayfinder.dart';

/// One severity/id/path line per profile finding, in report order.
List<String> findingSummary(Map<String, Object?> profile) =>
    (profile['findings']! as List<Object?>).map((value) {
      final finding = value! as Map<String, Object?>;
      final location = finding['location']! as Map<String, Object?>;
      return '${finding['severity']} ${finding['id']} ${location['path']}';
    }).toList();

// Fixture paths use `/` on every platform: a configured fixture's config path
// is reported as supplied, so goldens must not depend on the host separator.
String fixture(String name) => p.posix.join('test', 'fixtures', name);

String fixtureBundle(String path) =>
    File(p.posix.join(path, 'wayfinder.json')).existsSync()
    ? p.posix.join(path, 'knowledge')
    : path;

final ProfilePackage bitwild = ProfilePackage.parse(
  File(
    p.join('..', '..', 'profiles', 'bitwild', 'wayfinder-profile.json'),
  ).readAsStringSync(),
);

Future<ProfileValidationResult> validateFixture(
  String path, {
  bool discoverConfig = false,
  bool fix = false,
  List<ProfilePackage> children = const [],
  ProfileValidator validator = const ProfileValidator(),
}) async {
  final config = p.posix.join(path, 'wayfinder.json');
  final bundle = fixtureBundle(path);
  return validator.validate(
    bundle,
    await selectFixture(
      bundle,
      configPath: discoverConfig || !File(config).existsSync() ? null : config,
      children: children,
    ),
    fix: fix,
  );
}

Future<ProfileSelection> selectFixture(
  String bundle, {
  String? configPath,
  List<ProfilePackage> children = const [],
}) async {
  final BoundBundle bound;
  try {
    bound = await WayfinderProjectConfig.bind(bundle, configPath: configPath);
  } on BundleBindingException catch (error) {
    return UnselectedProfile([error.diagnostic]);
  }
  try {
    return SelectedProfile(
      EffectiveProfile.compose([
        bitwild,
        ...children,
      ], project: bound.binding.project),
      config: bound.config,
    );
  } on ProfileCompositionException catch (error) {
    final failure = compositionFailure(bound.binding.id, error);
    return UnselectedProfile([
      EngineDiagnostic(failure.code, failure.message, location: bound.config),
    ]);
  }
}

/// Every package [packageJson] has encoded in this isolate, so
/// ack_parity_test can compare evaluators over the packages other suites
/// build.
final builtPackages = <String>[];

String packageJson({
  String id = 'probe',
  String release = '1.0',
  List<Object?> rules = const [],
  Map<String, Object?> extra = const {},
}) {
  final json = jsonEncode({
    'format': 2,
    'id': id,
    'release': release,
    'implements': {'id': 'okf', 'release': '0.2'},
    ...extra,
    'rules': rules,
  });
  builtPackages.add(json);
  return json;
}

Map<String, Object?> ruleJson(
  String id, {
  required String subject,
  required Object schema,
  required List<Object?> valid,
  required List<Object?> invalid,
  String severity = 'error',
  String message = 'm',
  Map<String, Object?> check = const {},
}) => {
  'id': id,
  'category': 'structure',
  'severity': severity,
  'status': 'stable',
  'description': message,
  'message': message,
  'check': {'subject': subject, 'schema': schema, ...check},
  'tests': {'valid': valid, 'invalid': invalid},
};

Future<Directory> copyFixture(String name) async {
  final source = Directory(fixture(name));
  final destination = await Directory.systemTemp.createTemp('okfp-fixture-');
  await for (final entity in source.list(recursive: true)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: source.path);
    final copy = File(p.join(destination.path, relative));
    await copy.parent.create(recursive: true);
    await entity.copy(copy.path);
  }
  return destination;
}
