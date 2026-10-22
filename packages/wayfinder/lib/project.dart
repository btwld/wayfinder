/// A Wayfinder project on disk: its bundles, Profile resolution and
/// selection, validation from that selection, and the graph projection.
///
/// The `wayfinder` command and MCP server are a shell over this library.
/// It needs `dart:io` and, on POSIX systems, `dart:ffi` for its file lock.
/// It runs Git only through a [GitRunner], downloads nothing else, and
/// writes only `wayfinder.lock`, Profile skills, `--fix` output, its data
/// directory, and `wayfinder.json` when a host's relock edits it. A host
/// keeps all okf bundle I/O of one process on one isolate, because okf's
/// bundle lock does not exclude isolates (ADR-0018).
/// The resolver parses each Profile package on a short-lived isolate of its
/// own, so a package whose rule tests stall fails rather than hangs.
///
/// Given a project root, discovery and binding read nothing above it; the
/// command opts into its search of the working directory's ancestors with
/// `searchAncestors: true`.
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:wayfinder/project.dart';
///
/// final project = await WayfinderProject.discover(Directory('/work/app'));
/// final resolver = WayfinderProfileResolver(
///   dataDirectory: WayfinderDataDirectory.resolve(),
/// );
/// for (final bundle in project.bundles) {
///   final result = await validateWithProfileSources(
///     bundle.root,
///     projectRoot: project.root,
///     resolver: resolver,
///   );
///   print('${bundle.name}: ${result.gate.wireValue}');
/// }
/// ```
library;

// The kind of a ProfileLockChange, shared with the diagnostics that report
// one (EngineDiagnostic.lockChange).
export 'src/diagnostics.dart' show ProfileLockChangeKind;
export 'src/project/cancellation.dart'
    show
        WayfinderCancellation,
        WayfinderCancellationController,
        throwIfCancelled;
export 'src/project/data_directory.dart' show WayfinderDataDirectory;
export 'src/project/exception.dart' show WayfinderException;
export 'src/project/file_lock.dart' show WayfinderFileLock;
export 'src/project/git.dart'
    show
        GitProcess,
        GitProcessStarter,
        GitResult,
        GitRunner,
        gitMayReachRemote,
        gitSubcommand,
        runGit,
        startGitProcess,
        wayfinderConfiguredSshCommand,
        wayfinderGitEnvironment,
        wayfinderGitMaxOutputBytes,
        wayfinderGitOptions,
        wayfinderGitRemoteSubcommands,
        wayfinderGitTimeout,
        wayfinderSshCommand;
export 'src/project/graph.dart'
    show
        WayfinderGraphResult,
        projectWayfinderGraph,
        wayfinderGraphOutputs,
        wayfinderGraphResolutions,
        wayfinderLinkFields;
export 'src/project/graph_input.dart' show wayfinderGraphInput;
export 'src/project/profile_resolver.dart'
    show
        LockedPackage,
        ProfileFetch,
        ProfileFetchKind,
        ProfileFetchPolicy,
        ProfileFetchRequiredException,
        ProfileLock,
        ProfileRelockFailedException,
        ProfileRelockResult,
        ProfileResolutionBusyException,
        ProfileResolutionPlan,
        ProfileResolutionResult,
        ProfileSkillDirectoriesException,
        WayfinderProfileResolutionException,
        WayfinderProfileResolver,
        validateWithProfileSources;
export 'src/project/profile_skills.dart'
    show
        MaterializedSkill,
        ProfileSkillDirectory,
        ProfileSkillDirectoryState,
        ProfileSkillText,
        ProfileSkills,
        SkillFile,
        SkillRevision;
export 'src/project/profile_status.dart'
    show
        ProfileBindingState,
        ProfileBindingStatus,
        ProfileLocalCopy,
        ProfileLockChange,
        ProfileLockChangeRequiredException,
        ProfileResolutionStatus;
export 'src/project/project_bundles.dart'
    show ProjectBundle, WayfinderProject, explicitBundlePrefix;
