import 'package:okf/okf.dart';

/// Read-only metadata describing one deterministic Profile rule,
/// mirroring okf's `okfSpecRuleDescriptors`.
///
/// A descriptor is the single authority for its rule's finding ID, severity,
/// and normative Profile clause reference: every finding is built from the
/// descriptor of the rule that reports it, so none of the three can drift.
/// A release's descriptors come from its rule catalog; only the findings
/// that precede release dispatch are declared in [DispatchRule].
final class ProfileRuleDescriptor {
  const ProfileRuleDescriptor({
    required this.id,
    required this.severity,
    required this.rule,
  });

  const ProfileRuleDescriptor.error(String slug, this.rule)
    : id = 'concepta-profile/$slug',
      severity = OkfFindingSeverity.error;

  const ProfileRuleDescriptor.advisory(String slug, this.rule)
    : id = 'concepta-profile/$slug',
      severity = OkfFindingSeverity.advisory;

  /// Stable `concepta-profile/<rule-slug>` finding ID.
  final String id;

  /// Severity emitted when the condition is found.
  final OkfFindingSeverity severity;

  /// The normative Profile clause reference the rule assesses.
  final String rule;
}

/// Findings reported while selecting a Profile release, before any catalog
/// can declare them.
abstract final class DispatchRule {
  static const profileDeclarationPresent = ProfileRuleDescriptor.error(
    'profile-declaration-present',
    '§11',
  );
  static const profileDeclarationReadable = ProfileRuleDescriptor.error(
    'profile-declaration-readable',
    '§11',
  );
  static const profileDeclarationFields = ProfileRuleDescriptor.error(
    'profile-declaration-fields',
    '§11',
  );
  static const configurationReadable = ProfileRuleDescriptor.error(
    'configuration-readable',
    '§11',
  );
  static const configurationBundleBinding = ProfileRuleDescriptor.error(
    'configuration-bundle-binding',
    '§11',
  );

  static const all = <ProfileRuleDescriptor>[
    profileDeclarationPresent,
    profileDeclarationReadable,
    profileDeclarationFields,
    configurationReadable,
    configurationBundleBinding,
  ];
}
