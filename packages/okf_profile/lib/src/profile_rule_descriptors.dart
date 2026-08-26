import 'package:okf/okf.dart';

/// Read-only metadata describing one deterministic Concepta Profile rule,
/// mirroring okf's `okfSpecRuleDescriptors`.
///
/// Descriptors carry the identity and per-rule metadata — the normative
/// Profile clause reference and the emitted severity — and no prose: the
/// Profile document owns each rule's statement, and restating it here would
/// be a second copy to drift. Execution stays fixed inside the closed
/// validator; a descriptor cannot alter validation.
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

/// Every finding the closed Concepta Profile validator can emit.
const List<ProfileRuleDescriptor> profileRuleDescriptors =
    <ProfileRuleDescriptor>[
  // Release dispatch and declaration (validation.dart).
  ProfileRuleDescriptor(
    id: 'concepta-profile/profile-declaration-present',
    severity: OkfFindingSeverity.error,
    rule: '§11',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/profile-declaration-readable',
    severity: OkfFindingSeverity.error,
    rule: '§11',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/profile-declaration-fields',
    severity: OkfFindingSeverity.error,
    rule: '§11',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/okf-release-binding',
    severity: OkfFindingSeverity.error,
    rule: '§11',
  ),
  // Concept rules.
  ProfileRuleDescriptor(
    id: 'concepta-profile/profile-declaration-kind',
    severity: OkfFindingSeverity.error,
    rule: '§11',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/concept-baseline-fields',
    severity: OkfFindingSeverity.error,
    rule: '§5.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/frontmatter-fields-okf',
    severity: OkfFindingSeverity.error,
    rule: '§5.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/status-value',
    severity: OkfFindingSeverity.error,
    rule: '§5.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/tag-literal-duplication',
    severity: OkfFindingSeverity.error,
    rule: '§5.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/generation-provenance-recommended',
    severity: OkfFindingSeverity.advisory,
    rule: '§5.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/type-registry-present',
    severity: OkfFindingSeverity.error,
    rule: '§5.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/type-registry-kind',
    severity: OkfFindingSeverity.error,
    rule: '§5.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/type-registry-columns',
    severity: OkfFindingSeverity.error,
    rule: '§6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/type-registry-standards',
    severity: OkfFindingSeverity.error,
    rule: '§5.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/type-registry-order',
    severity: OkfFindingSeverity.error,
    rule: '§5.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/used-type-registered',
    severity: OkfFindingSeverity.error,
    rule: '§5.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/registered-type-extension',
    severity: OkfFindingSeverity.advisory,
    rule: '§5.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-registry-required',
    severity: OkfFindingSeverity.error,
    rule: '§3.5, §6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-registry-kind',
    severity: OkfFindingSeverity.error,
    rule: '§3.5, §6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-registry-columns',
    severity: OkfFindingSeverity.error,
    rule: '§6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-row-complete',
    severity: OkfFindingSeverity.error,
    rule: '§3.5, §6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-side-value',
    severity: OkfFindingSeverity.error,
    rule: '§6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-active-interval',
    severity: OkfFindingSeverity.error,
    rule: '§6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/actor-active-overlap',
    severity: OkfFindingSeverity.error,
    rule: '§6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/used-actor-registered',
    severity: OkfFindingSeverity.error,
    rule: '§3.5, §6.1.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/source-entry-shape',
    severity: OkfFindingSeverity.error,
    rule: '§6.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/source-id-unique',
    severity: OkfFindingSeverity.error,
    rule: '§6.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/source-attribution-join',
    severity: OkfFindingSeverity.error,
    rule: '§6.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/relationships-shape',
    severity: OkfFindingSeverity.error,
    rule: '§7.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/relationship-label-extension',
    severity: OkfFindingSeverity.advisory,
    rule: '§7.2',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/link-graph-unavailable',
    severity: OkfFindingSeverity.error,
    rule: '§7.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/internal-link-bundle-relative',
    severity: OkfFindingSeverity.advisory,
    rule: '§7.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/internal-link-unresolved',
    severity: OkfFindingSeverity.advisory,
    rule: '§7.1, §14.1–§14.2',
  ),
  // Structure rules.
  ProfileRuleDescriptor(
    id: 'concepta-profile/raw-directory-placement',
    severity: OkfFindingSeverity.error,
    rule: '§3.4',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/raw-directory-markdown',
    severity: OkfFindingSeverity.error,
    rule: '§3.4',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/root-structure-files',
    severity: OkfFindingSeverity.error,
    rule: '§3.5',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/directory-index-present',
    severity: OkfFindingSeverity.error,
    rule: '§3.1, §3.4, §9',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/concept-area-name-collision',
    severity: OkfFindingSeverity.advisory,
    rule: '§14.1',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/index-semantic-projection',
    severity: OkfFindingSeverity.error,
    rule: '§9',
  ),
  ProfileRuleDescriptor(
    id: 'concepta-profile/log-entry-lead-word',
    severity: OkfFindingSeverity.error,
    rule: '§10',
  ),
];

final Map<String, ProfileRuleDescriptor> _descriptorsById =
    <String, ProfileRuleDescriptor>{
  for (final descriptor in profileRuleDescriptors) descriptor.id: descriptor,
};

/// The descriptor for [id], or null when no rule mints that ID.
ProfileRuleDescriptor? profileRuleDescriptor(String id) => _descriptorsById[id];
