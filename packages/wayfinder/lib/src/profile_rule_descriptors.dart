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
/// A descriptor is the single authority for its rule's finding ID, severity
/// and help link: every finding is built from the descriptor of the rule
/// that reports it, so none of the three can drift.
final class ProfileRuleDescriptor {
  const ProfileRuleDescriptor({
    required this.id,
    required this.severity,
    this.helpUri,
  });

  /// Stable `<profile-id>/<rule-slug>` finding ID.
  final String id;

  /// Severity emitted when the condition is found.
  final RuleSeverity severity;

  /// The package's `docs` with the fragment set to the rule slug, or null
  /// when the package names no docs.
  final Uri? helpUri;
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
