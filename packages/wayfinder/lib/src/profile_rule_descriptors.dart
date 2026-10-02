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

  /// Stable `concepta-profile/<rule-slug>` finding ID.
  final String id;

  /// Severity emitted when the condition is found.
  final RuleSeverity severity;

  /// The normative Profile clause reference the rule assesses.
  final String rule;
}

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
