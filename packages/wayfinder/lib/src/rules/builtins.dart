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
    this.needsLinks = false,
    this.fix,
  });

  final BuiltinBody run;

  /// Reads the OKF link graph, so [run] is skipped when it cannot be built.
  final bool needsLinks;

  final BuiltinFix? fix;

  final Object? paramsSchema;

  final Set<String> messagePlaceholders;

  final Set<String> messageIds;
}

/// The engine's capabilities, named for what they check and never for a
/// rule a Profile builds with them. A check belongs here only when a schema
/// over one subject's facts cannot express it: it needs I/O beyond the
/// parsed bundle, compares with generated output or fixes, reports
/// something absent where no subject lives, or reports several findings per
/// subject. Policy is params, set by the package; engine health is an
/// `EngineDiagnostic`; no capability names a Profile.
const builtins = <String, Builtin>{
  'files-present': Builtin(
    filesPresent,
    paramsSchema: filesPresentParams,
    messagePlaceholders: {'failing'},
  ),
  'path-targets-exist': Builtin(
    pathTargetsExist,
    paramsSchema: pathTargetsExistParams,
    messagePlaceholders: {'target'},
    needsLinks: true,
  ),
  'matches-generated': Builtin(
    matchesGenerated,
    paramsSchema: matchesGeneratedParams,
    messagePlaceholders: {'path'},
    messageIds: {'stale', 'extra'},
    fix: generated,
  ),
};
