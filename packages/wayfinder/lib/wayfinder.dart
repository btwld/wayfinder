/// Core validation for Wayfinder knowledge bundles.
///
/// Used by the wayfinder_cli command and MCP server.
library;

export 'src/diagnostics.dart';
export 'src/field_edges.dart'
    show OkfFieldEdge, OkfLinkField, okfFieldEdges, relationshipsLinkField;
export 'src/profile_finding.dart';
export 'src/profile_release.dart'
    show
        builtinProfileId,
        externalProfileRelease,
        externalStandardTypes,
        externalStandardTags,
        externalStandardRelationships;
export 'src/published_schemas.dart' show profileManifestSchemaViolation;
export 'src/rules/catalog.dart' show RuleCatalog, RuleCatalogException;
export 'src/sarif.dart' show internalErrorSarif, toSarif;
export 'src/validation.dart'
    show
        Assessed,
        BlockedByOkf,
        GateState,
        NotAssessed,
        OkfState,
        ProfileAssessment,
        ProfileState,
        ProfileSourceResolution,
        ProfileValidationResult,
        ProfileValidator,
        internalErrorJson;
export 'src/wayfinder_config.dart';
