/// Core validation for Wayfinder knowledge bundles.
///
/// Used by the wayfinder_cli command and MCP server.
library;

export 'src/profile_finding.dart';
export 'src/profile_release.dart'
    show
        builtinProfileId,
        externalProfileRelease,
        externalStandardTypes,
        externalStandardTags;
export 'src/published_schemas.dart' show profileManifestSchemaViolation;
export 'src/validation.dart'
    show
        AutomatedGateState,
        OkfState,
        ProfileFix,
        ProfileState,
        ProfileSourceResolution,
        ProfileValidationResult,
        ProfileValidator;
export 'src/wayfinder_config.dart';
