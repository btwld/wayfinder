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

/// The Bitwild package as checked in, read through the one parse boundary
/// every Profile uses. Tests see no embedded or privileged copy.
final ProfilePackage bitwild = ProfilePackage.parse(
  File(
    p.join('..', '..', 'profiles', 'bitwild', 'wayfinder-profile.json'),
  ).readAsStringSync(),
);

/// Validates a fixture the way the CLI would after `wayfinder get`, through
/// [selectFixture]. A fixture holding its own `wayfinder.json` is bound by
/// that file unless [discoverConfig] asks for the walk up from the bundle.
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

/// Selects the Profile for [bundle] as the resolver does, with [bitwild]
/// followed by [children] standing in for the locked chain: the same
/// binding lookup, then composition with the binding's project additions.
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

/// A minimal format-2 package for tests: [rules] report as `<id>/<slug>`.
String packageJson({
  String id = 'probe',
  String release = '1.0',
  List<Object?> rules = const [],
  Map<String, Object?> extra = const {},
}) => jsonEncode({
  'format': 2,
  'id': id,
  'release': release,
  'implements': {'id': 'okf', 'release': '0.2'},
  ...extra,
  'rules': rules,
});

/// A schema rule over [subject] whose examples are [valid] and [invalid].
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
