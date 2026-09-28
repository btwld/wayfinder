import 'wayfinder_config.dart';

final class ProfileValidationContext {
  const ProfileValidationContext.legacy(this.release)
    : externalBinding = false,
      binding = null;

  ProfileValidationContext.external(WayfinderProfileBinding value)
    : externalBinding = true,
      release = value.release,
      binding = value;

  final bool externalBinding;
  final String release;
  final WayfinderProfileBinding? binding;
}
