import 'dart:collection';

import 'bundle.dart';
import 'concept_id.dart';
import 'document.dart';
import 'finding.dart';
import 'profile.dart';

/// A prospective mutation to an OKF bundle.
sealed class OkfBundleChange {
  const OkfBundleChange();
}

/// A request to create a concept document at a new bundle path.
final class OkfCreateConceptChange extends OkfBundleChange {
  /// Creates a concept creation request.
  const OkfCreateConceptChange({
    required this.path,
    required this.document,
  });

  /// The POSIX-style bundle-relative document path.
  final String path;

  /// The prospective concept document.
  final OkfDocument document;
}

/// A patch to an existing concept that preserves fields it does not name.
final class OkfUpdateConceptChange extends OkfBundleChange {
  /// Creates a concept update request.
  OkfUpdateConceptChange({
    required this.conceptId,
    Map<String, Object?> setFrontmatter = const <String, Object?>{},
    Iterable<String> removeFrontmatter = const <String>[],
    this.body,
  })  : setFrontmatter = UnmodifiableMapView<String, Object?>(
          Map<String, Object?>.of(setFrontmatter),
        ),
        removeFrontmatter = UnmodifiableSetView<String>(
          Set<String>.of(removeFrontmatter),
        );

  /// The concept to update.
  final OkfConceptId conceptId;

  /// Frontmatter keys and values to create or replace.
  final Map<String, Object?> setFrontmatter;

  /// Frontmatter keys to remove.
  final Set<String> removeFrontmatter;

  /// A replacement Markdown body, or `null` to preserve the existing body.
  final String? body;
}

/// A request to add a labeled relationship between two concepts.
final class OkfLinkConceptsChange extends OkfBundleChange {
  /// Creates a concept-link request.
  const OkfLinkConceptsChange({
    required this.source,
    required this.target,
    required this.label,
  });

  /// The concept that owns the relationship.
  final OkfConceptId source;

  /// The concept referenced by the relationship.
  final OkfConceptId target;

  /// The manifest vocabulary label for the relationship.
  final String label;
}

/// A request to mark an existing concept as deprecated.
final class OkfDeprecateConceptChange extends OkfBundleChange {
  /// Creates a concept deprecation request.
  const OkfDeprecateConceptChange({required this.conceptId, this.note});

  /// The concept to deprecate.
  final OkfConceptId conceptId;

  /// Optional context to retain in the bundle log.
  final String? note;
}

/// The outcome of an atomic bundle apply operation.
enum OkfBundleApplyStatus {
  /// Validation accepted the changes and every file update committed.
  applied,

  /// Validation refused the changes and no file was modified.
  refused,
}

/// The observable result of applying a bundle change set.
final class OkfBundleApplyResult {
  /// Creates an atomic apply result.
  OkfBundleApplyResult({
    required this.status,
    required this.report,
    Iterable<String> changedPaths = const <String>[],
  }) : changedPaths = List<String>.unmodifiable(changedPaths);

  /// Whether the change set was committed or refused.
  final OkfBundleApplyStatus status;

  /// The prospective validation report for the overlaid bundle.
  final OkfReport report;

  /// Paths committed by an applied result, in deterministic order.
  final List<String> changedPaths;
}

/// The single prospective-validation and atomic-write seam for bundle edits.
abstract interface class OkfBundleChangeSet {
  /// The ordered change descriptions in this operation.
  List<OkfBundleChange> get changes;

  /// Validates the bundle produced by overlaying [changes] on [bundle].
  OkfReport validate(OkfBundle bundle, OkfProfileManifest manifest);

  /// Validates and atomically applies this change set below [rootPath].
  ///
  /// A refused result leaves the filesystem untouched. An implementation
  /// failure must roll back every staged path before completing with an error.
  Future<OkfBundleApplyResult> apply({
    required String rootPath,
    required OkfBundle bundle,
    required OkfProfileManifest manifest,
  });
}
