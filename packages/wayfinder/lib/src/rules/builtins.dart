import '../profile_release.dart';
import 'concept_builtins.dart';
import 'facts.dart';
import 'structure_builtins.dart';

export 'concept_builtins.dart' show legacyRegistryVocabulary;

final class Violation {
  const Violation(
    this.location, {
    this.failing = const [],
    this.facts = const {},
    this.messageId,
  });

  final String location;

  final List<Object?> failing;

  final Map<String, Object?> facts;

  final String? messageId;
}

typedef BuiltinBody =
    Iterable<Violation> Function(
      BundleFacts facts,
      Map<String, Object?> params,
    );

typedef BuiltinFix =
    Map<String, String> Function(
      BundleFacts facts,
      Map<String, Object?> params,
    );

final class Builtin {
  const Builtin(
    this.run, {
    this.params = const {'type': 'object', 'additionalProperties': false},
    this.fills = const {},
    this.messageIds = const {},
    this.release,
    this.fix,
  });

  final BuiltinBody run;

  final BuiltinFix? fix;

  /// What `params` must satisfy; by default, nothing may be passed.
  final Object? params;

  /// The placeholder names a message may use: `failing` when a violation
  /// lists failing values, and the fact names every violation carries.
  final Set<String> fills;

  final Set<String> messageIds;

  /// The installed Profile release whose conventions this builtin encodes.
  /// Only that release's installed catalog may name it.
  final String? release;
}

const builtins = <String, Builtin>{
  'tag-literal-duplication': Builtin(tagLiteralDuplication, fills: {'failing'}),
  'configured-type-extension': Builtin(
    configuredTypeExtension,
    fills: {'name'},
  ),
  'type-registry-present': Builtin(
    typeRegistryPresent,
    release: legacyProfileRelease,
  ),
  'type-registry-kind': Builtin(
    typeRegistryKind,
    release: legacyProfileRelease,
  ),
  'type-registry-columns': Builtin(
    typeRegistryColumns,
    release: legacyProfileRelease,
  ),
  'type-registry-standards': Builtin(
    typeRegistryStandards,
    release: legacyProfileRelease,
  ),
  'type-registry-order': Builtin(
    typeRegistryOrder,
    release: legacyProfileRelease,
  ),
  'registered-type-extension': Builtin(
    registeredTypeExtension,
    release: legacyProfileRelease,
  ),
  'actor-registry-required': Builtin(
    actorRegistryRequired,
    release: legacyProfileRelease,
  ),
  'actor-registry-kind': Builtin(
    actorRegistryKind,
    release: legacyProfileRelease,
  ),
  'actor-registry-columns': Builtin(
    actorRegistryColumns,
    release: legacyProfileRelease,
  ),
  'actor-row-complete': Builtin(
    actorRowComplete,
    release: legacyProfileRelease,
  ),
  'actor-side-value': Builtin(actorSideValue, release: legacyProfileRelease),
  'actor-active-interval': Builtin(
    actorActiveInterval,
    release: legacyProfileRelease,
  ),
  'actor-active-overlap': Builtin(
    actorActiveOverlap,
    release: legacyProfileRelease,
  ),
  'source-path-unresolved': Builtin(sourcePathUnresolved, fills: {'target'}),
  'source-attribution-in-source': Builtin(
    sourceAttributionInSource,
    release: legacyProfileRelease,
  ),
  'relationships-shape': Builtin(
    relationshipsShape,
    release: legacyProfileRelease,
  ),
  'relationship-label-extension': Builtin(
    relationshipLabelExtension,
    fills: {'label'},
    release: legacyProfileRelease,
  ),
  'link-graph-unavailable': Builtin(
    linkGraphUnavailable,
    params: linkGraphUnavailableParams,
    fills: {'error'},
  ),
  'declared-okf-binding': Builtin(
    declaredOkfBinding,
    release: legacyProfileRelease,
  ),
  'root-structure-files': Builtin(
    rootStructureFiles,
    params: rootStructureFilesParams,
    fills: {'failing'},
    messageIds: {'missing', 'reserved'},
  ),
  'index-semantic-projection': Builtin(
    indexSemanticProjection,
    params: indexSemanticProjectionParams,
    release: legacyProfileRelease,
  ),
  'index-current': Builtin(
    indexCurrent,
    fills: {'path'},
    fix: generatedIndexes,
    messageIds: {'stale', 'extra'},
  ),
};
