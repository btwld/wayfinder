import 'dart:collection';

import 'bundle.dart';
import 'finding.dart';
import 'profile.dart';

/// Executes one catalog rule against a loaded bundle and profile manifest.
typedef OkfRuleRunner = Iterable<OkfFinding> Function(
  OkfBundle bundle,
  OkfProfileManifest manifest,
);

/// The layer that owns a registered rule.
enum OkfRuleOwner {
  /// The base OKF specification.
  base,

  /// An additional profile constraint.
  profile,
}

/// The complete registration record for one executable rule.
final class OkfRuleCatalogEntry {
  /// Creates a catalog entry.
  OkfRuleCatalogEntry({
    required this.id,
    required String prose,
    required this.owner,
    required this.defaultSeverity,
    required Map<String, Object?> parameterSchema,
    required this.run,
  })  : prose = _requireProse(prose),
        parameterSchema = UnmodifiableMapView<String, Object?>(
          Map<String, Object?>.of(parameterSchema),
        );

  /// The stable ID emitted by this rule.
  final OkfFindingId id;

  /// Human-readable rule prose used by the generated ID registry.
  final String prose;

  /// The specification layer that owns the rule.
  final OkfRuleOwner owner;

  /// The severity used when the manifest does not override parameters.
  final OkfFindingSeverity defaultSeverity;

  /// The schema for parameters accepted by this rule.
  final Map<String, Object?> parameterSchema;

  /// The rule implementation invoked by validator dispatch.
  final OkfRuleRunner run;
}

String _requireProse(String prose) {
  if (prose.trim().isEmpty) {
    throw ArgumentError.value(prose, 'prose', 'Rule prose cannot be empty');
  }
  return prose;
}
