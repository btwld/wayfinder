import 'wayfinder_config.dart';

final class ProfileValidationContext {
  const ProfileValidationContext.legacy(
    this.release, {
    required Map<String, String> this.declaration,
  }) : externalBinding = false,
       binding = null,
       configPath = null;

  ProfileValidationContext.external(
    WayfinderProfileBinding value, {
    required this.configPath,
  }) : externalBinding = true,
       release = value.release,
       binding = value,
       declaration = null;

  final bool externalBinding;
  final String release;
  final WayfinderProfileBinding? binding;
  final String? configPath;

  /// The 2026.2 `profile.md` declaration values.
  final Map<String, String>? declaration;
}
