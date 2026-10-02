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

/// A descriptor whose rule reports findings: an error or advisory rule with
/// the okf severity it reports at. A note rule has none, so [of] returns
/// null for its descriptor and the rule reports summary entries instead.
final class FindingDescriptor {
  const FindingDescriptor._(this.descriptor, this.severity);

  static FindingDescriptor? of(ProfileRuleDescriptor descriptor) =>
      switch (descriptor.severity.finding) {
        null => null,
        final severity => FindingDescriptor._(descriptor, severity),
      };

  final ProfileRuleDescriptor descriptor;
  final OkfFindingSeverity severity;
}

abstract final class DispatchRule {
  static const profileDeclarationPresent = FindingDescriptor._(
    ProfileRuleDescriptor.error('profile-declaration-present', '§11'),
    OkfFindingSeverity.error,
  );
  static const profileDeclarationReadable = FindingDescriptor._(
    ProfileRuleDescriptor.error('profile-declaration-readable', '§11'),
    OkfFindingSeverity.error,
  );
  static const profileDeclarationFields = FindingDescriptor._(
    ProfileRuleDescriptor.error('profile-declaration-fields', '§11'),
    OkfFindingSeverity.error,
  );
  static const configurationReadable = FindingDescriptor._(
    ProfileRuleDescriptor.error('configuration-readable', '§11'),
    OkfFindingSeverity.error,
  );
  static const configurationBundleBinding = FindingDescriptor._(
    ProfileRuleDescriptor.error('configuration-bundle-binding', '§11'),
    OkfFindingSeverity.error,
  );

  static final all = <ProfileRuleDescriptor>[
    for (final rule in [
      profileDeclarationPresent,
      profileDeclarationReadable,
      profileDeclarationFields,
      configurationReadable,
      configurationBundleBinding,
    ])
      rule.descriptor,
  ];
}
