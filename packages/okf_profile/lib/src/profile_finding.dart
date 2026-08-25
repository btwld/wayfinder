enum ProfileFindingSeverity {
  error('error'),
  advisory('advisory');

  const ProfileFindingSeverity(this.wireValue);

  final String wireValue;
}

final class ProfileFinding {
  const ProfileFinding({
    required this.id,
    required this.message,
    required this.rule,
    this.severity = ProfileFindingSeverity.error,
    this.profileRelease,
    this.path = 'profile.md',
  });

  final String id;
  final String message;
  final String rule;
  final ProfileFindingSeverity severity;
  final String? profileRelease;
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'severity': severity.wireValue,
        'profile_release': profileRelease,
        'rule': rule,
        'path': path,
        'message': message,
      };

  String toText() {
    final release = profileRelease == null ? '' : '$profileRelease ';
    return '$path: ${severity.wireValue} $id ($release$rule): $message';
  }
}
