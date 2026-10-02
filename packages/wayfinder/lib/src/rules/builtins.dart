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
    this.paramsSchema = const {'type': 'object', 'additionalProperties': false},
    this.messagePlaceholders = const {},
    this.messageIds = const {},
    this.installedOnlyIn,
    this.fix,
  });

  final BuiltinBody run;

  final BuiltinFix? fix;

  final Object? paramsSchema;

  final Set<String> messagePlaceholders;

  final Set<String> messageIds;

  final String? installedOnlyIn;
}

const builtins = <String, Builtin>{
  'tag-literal-duplication': Builtin(
    tagLiteralDuplication,
    messagePlaceholders: {'failing'},
  ),
  'type-registry-present': Builtin(
    typeRegistryPresent,
    installedOnlyIn: legacyProfileRelease,
  ),
  'type-registry-kind': Builtin(
    typeRegistryKind,
    installedOnlyIn: legacyProfileRelease,
  ),
  'type-registry-columns': Builtin(
    typeRegistryColumns,
    installedOnlyIn: legacyProfileRelease,
  ),
  'type-registry-standards': Builtin(
    typeRegistryStandards,
    installedOnlyIn: legacyProfileRelease,
  ),
  'type-registry-order': Builtin(
    typeRegistryOrder,
    installedOnlyIn: legacyProfileRelease,
  ),
  'registered-type-extension': Builtin(
    registeredTypeExtension,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-registry-required': Builtin(
    actorRegistryRequired,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-registry-kind': Builtin(
    actorRegistryKind,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-registry-columns': Builtin(
    actorRegistryColumns,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-row-complete': Builtin(
    actorRowComplete,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-side-value': Builtin(
    actorSideValue,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-active-interval': Builtin(
    actorActiveInterval,
    installedOnlyIn: legacyProfileRelease,
  ),
  'actor-active-overlap': Builtin(
    actorActiveOverlap,
    installedOnlyIn: legacyProfileRelease,
  ),
  'source-path-unresolved': Builtin(
    sourcePathUnresolved,
    messagePlaceholders: {'target'},
  ),
  'source-attribution-in-source': Builtin(
    sourceAttributionInSource,
    installedOnlyIn: legacyProfileRelease,
  ),
  'relationships-shape': Builtin(
    relationshipsShape,
    installedOnlyIn: legacyProfileRelease,
  ),
  'relationship-label-extension': Builtin(
    relationshipLabelExtension,
    messagePlaceholders: {'label'},
    installedOnlyIn: legacyProfileRelease,
  ),
  'link-graph-unavailable': Builtin(
    linkGraphUnavailable,
    messagePlaceholders: {'error'},
    installedOnlyIn: legacyProfileRelease,
  ),
  'declared-okf-binding': Builtin(
    declaredOkfBinding,
    installedOnlyIn: legacyProfileRelease,
  ),
  'root-structure-files': Builtin(
    rootStructureFiles,
    paramsSchema: rootStructureFilesParams,
    messagePlaceholders: {'failing'},
    messageIds: {'missing', 'reserved'},
  ),
  'index-semantic-projection': Builtin(
    indexSemanticProjection,
    paramsSchema: indexSemanticProjectionParams,
    installedOnlyIn: legacyProfileRelease,
  ),
  'index-current': Builtin(
    indexCurrent,
    messagePlaceholders: {'path'},
    fix: generatedIndexes,
    messageIds: {'stale', 'extra'},
  ),
};
