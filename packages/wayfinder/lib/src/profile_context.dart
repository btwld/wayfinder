import 'wayfinder_config.dart';

final class ProfileValidationContext {
  const ProfileValidationContext.legacy(this.release)
    : externalBinding = false,
      binding = null,
      configPath = null;

  ProfileValidationContext.external(
    WayfinderProfileBinding value, {
    required this.configPath,
  }) : externalBinding = true,
       release = value.release,
       binding = value;

  final bool externalBinding;
  final String release;
  final WayfinderProfileBinding? binding;
  final String? configPath;
}
