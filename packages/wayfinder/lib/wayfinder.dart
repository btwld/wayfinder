/// Core validation for Wayfinder knowledge bundles: OKF, then the rules of
/// a selected Profile package. Projects on disk, Profile resolution and the
/// graph projection are in `package:wayfinder/project.dart`.
library;

export 'src/bundle_file_kind.dart';
export 'src/diagnostics.dart';
export 'src/field_edges.dart'
    show OkfFieldEdge, OkfLinkField, okfFieldEdges, relationshipsLinkField;
export 'src/path_targets.dart'
    show
        InBundlePath,
        MissingPath,
        NotAPath,
        OutsidePath,
        PathTarget,
        pathTargetDisplay,
        resolvePathTarget;
export 'src/profile_finding.dart';
export 'src/profile_package.dart';
export 'src/profile_rule_descriptors.dart'
    show ProfileRuleDescriptor, RuleSeverity;
export 'src/rules/catalog.dart' show BuiltinCheck, CatalogRule, SchemaCheck;
export 'src/rules/facts.dart' show bundleInventoryPaths;
export 'src/rules/profile.dart'
    show
        EffectiveProfile,
        ProfileCompositionException,
        ProjectVocabulary,
        Slot,
        Vocabulary;
export 'src/sarif.dart' show internalErrorSarif, toSarif;
export 'src/validation.dart'
    show
        Assessed,
        BlockedByOkf,
        GateState,
        NotAssessed,
        OkfState,
        ProfileAssessment,
        ProfileProjection,
        ProfileState,
        ProfileSelection,
        ProfileValidationResult,
        ProfileValidator,
        SelectedProfile,
        UnselectedProfile,
        compositionFailure,
        internalErrorJson;
export 'src/wayfinder_config.dart';
