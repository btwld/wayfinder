import 'package:okf/okf.dart';

/// The sole mint for stable finding IDs owned by the profile layer.
abstract final class OkfProfileFindingIds {
  /// The degrade finding used when a bundle has no profile declaration.
  static final OkfFindingId noProfileDeclared = rule('no-profile-declared');

  /// The degrade finding used when a declared release cannot be resolved.
  static final OkfFindingId unknownProfileRelease =
      rule('unknown-profile-release');

  /// Mints the stable `profile/<code>` ID for a profile rule.
  static OkfFindingId rule(String code) =>
      OkfFindingId.fromParts('profile', code);

  /// Mints the stable ID owned by one frontmatter schema keyword.
  static OkfFindingId frontmatter(String keyword) =>
      rule('frontmatter-$keyword');
}

/// Creates and registers a profile rule through the upstream catalog seam.
///
/// The returned value is the upstream [OkfRuleCatalogEntry], so this package
/// introduces no parallel catalog-entry contract.
OkfRuleCatalogEntry registerOkfProfileRule(
  OkfRuleCatalog catalog, {
  required String code,
  required String prose,
  required String owner,
  required OkfFindingSeverity defaultSeverity,
  required Map<String, Object?> parameterSchema,
  required OkfRuleRun run,
}) {
  final entry = OkfRuleCatalogEntry(
    id: OkfProfileFindingIds.rule(code),
    prose: prose,
    owner: owner,
    defaultSeverity: defaultSeverity,
    parameterSchema: parameterSchema,
    run: run,
  );
  catalog.register(entry);
  return entry;
}
