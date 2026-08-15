import 'package:okf/okf.dart';

import 'declaration.dart';
import 'manifest.dart';
import 'rule.dart';

/// The result of resolving a bundle's profile declaration.
sealed class OkfProfileResolution {
  const OkfProfileResolution();
}

/// A declared profile successfully paired with its manifest release.
final class OkfResolvedProfile extends OkfProfileResolution {
  /// Creates a resolved profile from its declaration and manifest.
  const OkfResolvedProfile({
    required this.declaration,
    required this.manifest,
  });

  /// The declaration discovered in the governed bundle.
  final OkfProfileDeclaration declaration;

  /// The manifest selected for the declared profile release.
  final OkfProfileManifest manifest;
}

/// A resolution that degrades without activating profile rules.
sealed class OkfDegradedProfileResolution extends OkfProfileResolution {
  const OkfDegradedProfileResolution();

  /// The stable advisory ID representing this degrade state.
  OkfFindingId get findingId;
}

/// The degrade state for a bundle without a profile declaration.
final class OkfNoProfileDeclared extends OkfDegradedProfileResolution {
  /// Creates the missing-declaration state.
  const OkfNoProfileDeclared();

  @override
  OkfFindingId get findingId => OkfProfileFindingIds.noProfileDeclared;
}

/// The degrade state for a declaration whose release cannot be resolved.
final class OkfUnknownProfileRelease extends OkfDegradedProfileResolution {
  /// Creates an unknown-release state for [declaration].
  const OkfUnknownProfileRelease(this.declaration);

  /// The declaration that named an unavailable profile release.
  final OkfProfileDeclaration declaration;

  @override
  OkfFindingId get findingId => OkfProfileFindingIds.unknownProfileRelease;
}

/// A manifest rule activation paired with its resolved catalog entry.
final class OkfActivatedProfileRule {
  /// Creates one activated, parameterized profile rule.
  const OkfActivatedProfileRule({
    required this.activation,
    required this.entry,
  });

  /// The manifest activation that selected [entry].
  final OkfProfileRuleActivation activation;

  /// The upstream catalog entry selected by the manifest.
  final OkfRuleCatalogEntry entry;

  /// Parameters validated for execution with [entry].
  OkfRuleParameters get parameters => activation.parameters;
}

/// A resolved profile whose catalog rules have been activated.
///
/// Executing these rules into an [OkfReport] and [OkfVerdict] is a later
/// slice; this contract freezes the data shape only.
final class OkfActivatedProfile {
  /// Creates an activated profile in manifest rule order.
  OkfActivatedProfile({
    required this.resolved,
    Iterable<OkfActivatedProfileRule> rules = const <OkfActivatedProfileRule>[],
  }) : rules = List<OkfActivatedProfileRule>.unmodifiable(rules);

  /// The declaration and manifest that selected these rules.
  final OkfResolvedProfile resolved;

  /// The activated, parameterized rules in execution order.
  final List<OkfActivatedProfileRule> rules;
}
