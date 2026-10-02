import 'package:okf/okf.dart';

enum RuleSeverity {
  error(OkfFindingSeverity.error),
  advisory(OkfFindingSeverity.advisory),
  note(null);

  const RuleSeverity(this.finding);

  final OkfFindingSeverity? finding;
}

/// Read-only metadata describing one deterministic Profile rule,
/// mirroring okf's `okfSpecRuleDescriptors`.
///
/// A descriptor is the single authority for its rule's finding ID, severity,
/// and normative Profile clause reference: every finding is built from the
/// descriptor of the rule that reports it, so none of the three can drift.
final class ProfileRuleDescriptor {
  const ProfileRuleDescriptor({
    required this.id,
    required this.severity,
    required this.rule,
  });

  const ProfileRuleDescriptor.error(String slug, this.rule)
    : id = 'concepta-profile/$slug',
      severity = RuleSeverity.error;

  /// Stable `concepta-profile/<rule-slug>` finding ID.
  final String id;

  /// Severity emitted when the condition is found.
  final RuleSeverity severity;

  /// The normative Profile clause reference the rule assesses.
  final String rule;
}

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
