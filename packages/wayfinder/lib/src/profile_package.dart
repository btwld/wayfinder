import 'dart:convert';

import 'package:okf/okf.dart';
import 'package:path/path.dart' as p;

import 'published_schemas.dart';
import 'rules/catalog.dart';
import 'wayfinder_config.dart' show WayfinderDefinition, WayfinderProfileSource;

/// The package `format` this engine evaluates. Engine compatibility is this
/// integer, never a Profile release. A package with another format is
/// refused whole, never partially evaluated.
const supportedPackageFormat = 2;

/// The OKF release whose bundles this engine's facts and index generator
/// understand. An engine capability, not vocabulary.
const supportedOkfRelease = '0.2';

/// A Profile identity in okf's finding-namespace grammar, so the id is used
/// verbatim as the finding namespace (`<id>/<rule-slug>`), the lock key and
/// the installed skill directory name. The grammar admits no `/`, `.` or
/// `_`, so an id is always a safe single path segment.
extension type const ProfileId._(String value) implements Object {
  static final grammar = RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$');

  /// Agent Skills' name limit. The installed skill directory is named by the
  /// id, and the grammar already meets the name's other constraints.
  static const maxLength = 64;

  /// Names a Profile may not take: the other finding namespaces, wayfinder's
  /// own skills, which share the agent skill directories with installed
  /// Profile skills, and the directories Claude Code reserves there.
  static const reserved = {
    'okf',
    'wayfinder',
    'use-wayfinder',
    'author-knowledge-bundle',
    'adopt-knowledge-bundle',
    'assess-knowledge-bundle',
    'create-profile',
    'synced',
    'anthropic-skills',
  };

  /// Throws [FormatException] for a malformed or reserved id.
  static ProfileId parse(String value) {
    if (!grammar.hasMatch(value)) {
      throw FormatException(
        'a Profile id is lowercase kebab-case starting with a letter',
        value,
      );
    }
    if (value.length > maxLength) {
      throw FormatException(
        'a Profile id has at most $maxLength characters',
        value,
      );
    }
    if (reserved.contains(value)) {
      throw FormatException('$value is reserved', value);
    }
    return ProfileId._(value);
  }
}

sealed class PackageParent {
  const PackageParent();
}

/// `"extends": {"path": ...}`: the package at [path], relative to the
/// repository root, in the same repository at the same commit as the child.
/// A repository that hosts several Profiles releases them together.
final class SameRevision extends PackageParent {
  const SameRevision(this.path);

  final String path;
}

/// `"extends": {"git": ..., "ref": ..., "path": ...}`: a parent resolved
/// from its own repository and ref.
final class OtherRevision extends PackageParent {
  const OtherRevision(this.source);

  final WayfinderProfileSource source;
}

/// A malformed package, or one this engine cannot evaluate. Load is the
/// only step that can fail; once a package has parsed, evaluation never
/// throws for any bundle.
final class ProfilePackageException implements Exception {
  const ProfilePackageException(
    this.where,
    this.message, {
    this.unsupported = false,
  });

  /// Path into the package JSON, such as `rules[3].check.subject`.
  final String where;
  final String message;

  /// True when the package may be well-formed for another engine (its
  /// format, OKF release or a builtin is unknown here), so the remedy is to
  /// upgrade wayfinder rather than to fix the Profile.
  final bool unsupported;

  @override
  String toString() => '$message at $where';
}

/// One Profile at one revision: everything `wayfinder validate` enforces
/// for it. Every package, including Bitwild, is read by [parse] and nothing
/// else; the engine embeds no Profile.
final class ProfilePackage {
  const ProfilePackage._({
    required this.id,
    required this.release,
    required this.okfRelease,
    required this.parent,
    required this.docs,
    required this.skill,
    required this.types,
    required this.tags,
    required this.relationships,
    required this.frontmatterKeys,
    required this.rules,
  });

  /// Parses one `wayfinder-profile.json`. The published schema rejects the
  /// shape; the parser then rejects what the schema cannot see: an
  /// unsupported format or OKF release, a reserved id, a name repeated
  /// within a noun, a declared frontmatter key OKF already defines, and
  /// every rule-level problem [compileRules] reports, including a rule
  /// whose own examples disagree with its check.
  static ProfilePackage parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw ProfilePackageException('package', error.message);
    }
    if (decoded case {
      'format': final int format,
    } when format != supportedPackageFormat) {
      throw ProfilePackageException(
        'format',
        'package format $format is not supported; this wayfinder reads '
            'format $supportedPackageFormat',
        unsupported: true,
      );
    }
    if (profilePackageSchemaViolation(decoded) case (
      :final where,
      :final reason,
    )) {
      throw ProfilePackageException(where, reason);
    }
    final root = decoded! as Map<String, Object?>;
    final okfRelease =
        (root['implements']! as Map<String, Object?>)['release']! as String;
    if (okfRelease != supportedOkfRelease) {
      throw ProfilePackageException(
        'implements.release',
        'OKF $okfRelease is not supported; this wayfinder reads OKF '
            '$supportedOkfRelease',
        unsupported: true,
      );
    }
    final ProfileId id;
    try {
      id = ProfileId.parse(root['id']! as String);
    } on FormatException catch (error) {
      throw ProfilePackageException('id', error.message);
    }
    final docs = switch (root['docs']) {
      final String uri =>
        Uri.tryParse(uri) ??
            (throw ProfilePackageException('docs', 'is not a valid URI')),
      _ => null,
    };
    final parent = switch (root['extends']) {
      {
        'git': final String git,
        'ref': final String ref,
        'path': final String path,
      } =>
        OtherRevision(
          WayfinderProfileSource(
            git: git,
            ref: ref,
            path: p.posix.normalize(path),
          ),
        ),
      {'path': final String path} => SameRevision(p.posix.normalize(path)),
      _ => null,
    };
    if (parent case OtherRevision(:final source)) {
      if (WayfinderProfileSource.locationProblem(source.git)
          case final problem?) {
        throw ProfilePackageException('extends.git', problem);
      }
    }
    final skill = switch (root['skill']) {
      final String path => p.posix.normalize(path),
      _ => null,
    };
    final frontmatterKeys = _definitions(root, 'frontmatter_keys');
    for (final key in frontmatterKeys) {
      if (okfKnownFrontmatterKeys.contains(key.name)) {
        throw ProfilePackageException(
          'frontmatter_keys',
          'an OKF frontmatter key cannot be declared again: ${key.name}',
        );
      }
    }
    return ProfilePackage._(
      id: id,
      release: root['release']! as String,
      okfRelease: okfRelease,
      parent: parent,
      docs: docs,
      skill: skill,
      types: _definitions(root, 'types'),
      tags: _definitions(root, 'tags'),
      relationships: _definitions(root, 'relationships'),
      frontmatterKeys: frontmatterKeys,
      rules: compileRules(
        root['rules']! as List<Object?>,
        namespace: id,
        defs: root[r'$defs'] as Map<String, Object?>? ?? const {},
        helpUri: (slug) => docs?.replace(fragment: slug),
      ),
    );
  }

  static List<WayfinderDefinition> _definitions(
    Map<String, Object?> root,
    String field,
  ) {
    try {
      return WayfinderDefinition.parseList(root[field]);
    } on FormatException catch (error) {
      throw ProfilePackageException(field, 'repeats the name ${error.source}');
    }
  }

  final ProfileId id;

  /// Opaque to the engine; recorded in the lock and reports.
  final String release;

  /// `implements.release`. The index generator declares it in the indexes
  /// it writes, so the engine holds no copy of it.
  final String okfRelease;

  /// The Profile this one builds on; null for a root Profile.
  final PackageParent? parent;

  /// Where the Profile explains its rules. A rule's help URI is this with
  /// its fragment set to the rule slug; null means findings carry none.
  final Uri? docs;

  /// The package-relative directory holding the Profile's agent skill, if
  /// it ships one. It is installed under the Profile id, which is therefore
  /// the skill's name.
  final String? skill;

  final List<WayfinderDefinition> types;
  final List<WayfinderDefinition> tags;
  final List<WayfinderDefinition> relationships;

  /// The producer frontmatter keys this Profile declares, OKF §4.1's
  /// additional keys. Never an OKF key.
  final List<WayfinderDefinition> frontmatterKeys;

  /// Compiled rules in file order; each descriptor already carries
  /// `<id>/<slug>` and its help URI, so reporting cannot drift from the
  /// package.
  final List<CatalogRule> rules;
}
