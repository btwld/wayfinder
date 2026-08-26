import 'package:okf/okf.dart';

/// Read-only metadata describing one deterministic Concepta Profile rule,
/// mirroring okf's `okfSpecRuleDescriptors`.
///
/// Descriptors are the single source of each rule's severity and normative
/// Profile clause reference — `profileFinding` reads them when a rule
/// reports — and carry no prose: the Profile document owns each rule's
/// statement, and restating it here would be a second copy to drift.
/// Execution stays fixed inside the closed validator; a descriptor cannot
/// alter validation.
final class ProfileRuleDescriptor {
  const ProfileRuleDescriptor({
    required this.id,
    required this.severity,
    required this.rule,
  });

  /// Stable `concepta-profile/<rule-slug>` finding ID.
  final String id;

  /// Severity emitted when the condition is found.
  final OkfFindingSeverity severity;

  /// The normative Concepta Profile clause reference the rule assesses.
  final String rule;
}

const OkfFindingSeverity _error = OkfFindingSeverity.error;
const OkfFindingSeverity _advisory = OkfFindingSeverity.advisory;

/// One row per rule: slug, severity, normative rule reference.
const List<(String, OkfFindingSeverity, String)> _rules = [
  // Release dispatch and declaration (validation.dart).
  ('profile-declaration-present', _error, '§11'),
  ('profile-declaration-readable', _error, '§11'),
  ('profile-declaration-fields', _error, '§11'),
  ('okf-release-binding', _error, '§11'),
  // Concept rules.
  ('profile-declaration-kind', _error, '§11'),
  ('concept-baseline-fields', _error, '§5.1'),
  ('frontmatter-fields-okf', _error, '§5.1'),
  ('status-value', _error, '§5.1'),
  ('tag-literal-duplication', _error, '§5.1'),
  ('generation-provenance-recommended', _advisory, '§5.1'),
  ('type-registry-present', _error, '§5.2'),
  ('type-registry-kind', _error, '§5.2'),
  ('type-registry-columns', _error, '§6.1.1'),
  ('type-registry-standards', _error, '§5.2'),
  ('type-registry-order', _error, '§5.2'),
  ('used-type-registered', _error, '§5.2'),
  ('registered-type-extension', _advisory, '§5.2'),
  ('actor-registry-required', _error, '§3.5, §6.1.1'),
  ('actor-registry-kind', _error, '§3.5, §6.1.1'),
  ('actor-registry-columns', _error, '§6.1.1'),
  ('actor-row-complete', _error, '§3.5, §6.1.1'),
  ('actor-side-value', _error, '§6.1.1'),
  ('actor-active-interval', _error, '§6.1.1'),
  ('actor-active-overlap', _error, '§6.1.1'),
  ('used-actor-registered', _error, '§3.5, §6.1.1'),
  ('source-entry-shape', _error, '§6.1'),
  ('source-id-unique', _error, '§6.1'),
  ('source-attribution-join', _error, '§6.1'),
  ('relationships-shape', _error, '§7.2'),
  ('relationship-label-extension', _advisory, '§7.2'),
  ('link-graph-unavailable', _error, '§7.1'),
  ('internal-link-bundle-relative', _advisory, '§7.1'),
  ('internal-link-unresolved', _advisory, '§7.1, §14.1–§14.2'),
  // Structure rules.
  ('raw-directory-placement', _error, '§3.4'),
  ('raw-directory-markdown', _error, '§3.4'),
  ('root-structure-files', _error, '§3.5'),
  ('directory-index-present', _error, '§3.1, §3.4, §9'),
  ('concept-area-name-collision', _advisory, '§14.1'),
  ('index-semantic-projection', _error, '§9'),
  ('log-entry-lead-word', _error, '§10'),
];

/// Every finding the closed Concepta Profile validator can emit.
final List<ProfileRuleDescriptor> profileRuleDescriptors =
    List<ProfileRuleDescriptor>.unmodifiable(<ProfileRuleDescriptor>[
  for (final (slug, severity, rule) in _rules)
    ProfileRuleDescriptor(
      id: 'concepta-profile/$slug',
      severity: severity,
      rule: rule,
    ),
]);

final Map<String, ProfileRuleDescriptor> _descriptorsById =
    <String, ProfileRuleDescriptor>{
  for (final descriptor in profileRuleDescriptors) descriptor.id: descriptor,
};

/// The descriptor for [id], or null when no rule mints that ID.
ProfileRuleDescriptor? profileRuleDescriptor(String id) => _descriptorsById[id];
