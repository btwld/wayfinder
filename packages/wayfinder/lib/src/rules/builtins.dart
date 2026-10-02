import 'concept_builtins.dart';
import 'facts.dart';
import 'structure_builtins.dart';

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
    this.fix,
  });

  final BuiltinBody run;

  final BuiltinFix? fix;

  final Object? paramsSchema;

  final Set<String> messagePlaceholders;

  final Set<String> messageIds;
}

const builtins = <String, Builtin>{
  'source-path-unresolved': Builtin(
    sourcePathUnresolved,
    messagePlaceholders: {'target'},
  ),
  'root-structure-files': Builtin(
    rootStructureFiles,
    paramsSchema: rootStructureFilesParams,
    messagePlaceholders: {'failing'},
  ),
  'index-current': Builtin(
    indexCurrent,
    messagePlaceholders: {'path'},
    fix: generatedIndexes,
    messageIds: {'stale', 'extra'},
  ),
};
