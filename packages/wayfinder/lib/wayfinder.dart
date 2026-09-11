/// Core validation for Wayfinder knowledge bundles.
///
/// Used by the wayfinder_cli command and MCP server.
library;

export 'src/profile_finding.dart';
export 'src/validation.dart'
    show
        AutomatedGateState,
        OkfState,
        ProfileState,
        ProfileValidationResult,
        ProfileValidator;
