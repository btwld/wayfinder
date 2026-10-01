import 'concept_builtins.dart';
import 'facts.dart';
import 'structure_builtins.dart';

export 'concept_builtins.dart' show legacyRegistryVocabulary;

/// What a builtin reports; the catalog's rule turns it into a finding.
final class Violation {
  const Violation(
    this.location, {
    this.failing = const [],
    this.facts = const {},
    this.messageId,
  });

  /// Bundle-relative path, or the configuration path for a binding rule.
  final String location;

  /// Values that fill `{failing}`.
  final List<Object?> failing;

  /// Values that fill named placeholders.
  final Map<String, Object?> facts;

  /// Which of the builtin's declared message ids applies.
  final String? messageId;
}

typedef BuiltinBody =
    Iterable<Violation> Function(
      BundleFacts facts,
      Map<String, Object?> params,
    );

/// The files that repair a builtin's violations, keyed by bundle-relative
/// path, for `validate --fix`.
typedef BuiltinFix =
    Map<String, String> Function(
      BundleFacts facts,
      Map<String, Object?> params,
    );

/// A compiled check available to any catalog the engine supports.
final class Builtin {
  const Builtin(
    this.run, {
    this.params = true,
    this.messageIds = const {},
    this.fix,
  });

  final BuiltinBody run;

  /// Present when the check's violations have one safe mechanical repair.
  final BuiltinFix? fix;

  /// Schema the catalog's `params` must satisfy, checked at load.
  final Object? params;

  /// Message ids this builtin names on its violations; a catalog rendering
  /// variants must declare exactly these.
  final Set<String> messageIds;
}

/// The compiled rule surface, by name. Every entry wraps a Profile rule the
/// catalogs still cannot express as a schema.
const builtins = <String, Builtin>{
  'tag-literal-duplication': Builtin(tagLiteralDuplication),
  'configured-type-extension': Builtin(configuredTypeExtension),
  'type-registry-present': Builtin(typeRegistryPresent),
  'type-registry-kind': Builtin(typeRegistryKind),
  'type-registry-columns': Builtin(typeRegistryColumns),
  'type-registry-standards': Builtin(typeRegistryStandards),
  'type-registry-order': Builtin(typeRegistryOrder),
  'registered-type-extension': Builtin(registeredTypeExtension),
  'actor-registry-required': Builtin(actorRegistryRequired),
  'actor-registry-kind': Builtin(actorRegistryKind),
  'actor-registry-columns': Builtin(actorRegistryColumns),
  'actor-row-complete': Builtin(actorRowComplete),
  'actor-side-value': Builtin(actorSideValue),
  'actor-active-interval': Builtin(actorActiveInterval),
  'actor-active-overlap': Builtin(actorActiveOverlap),
  'source-path-unresolved': Builtin(sourcePathUnresolved),
  'relationships-shape': Builtin(relationshipsShape),
  'relationship-label-extension': Builtin(relationshipLabelExtension),
  'link-graph-unavailable': Builtin(linkGraphUnavailable),
  'declared-okf-binding': Builtin(declaredOkfBinding),
  'root-structure-files': Builtin(
    rootStructureFiles,
    params: rootStructureFilesParams,
    messageIds: {'missing', 'reserved'},
  ),
  'index-semantic-projection': Builtin(
    indexSemanticProjection,
    params: indexSemanticProjectionParams,
  ),
  'index-current': Builtin(indexCurrent, fix: generatedIndexes),
};
