/// A Wayfinder project on disk: its bundles, Profile resolution and
/// selection, validation from that selection, and the graph projection.
///
/// The `wayfinder` command and MCP server are a shell over this library.
/// It needs `dart:io` and, on POSIX systems, `dart:ffi` for its file lock.
/// It runs Git only through a [GitRunner], downloads nothing else, and
/// writes only `wayfinder.lock`, Profile skills, `--fix` output and its
/// data directory. A host keeps all okf bundle I/O of one process on one
/// isolate, because okf's bundle lock does not exclude isolates (ADR-0018).
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:wayfinder/project.dart';
///
/// final project = await WayfinderProject.discover(Directory.current);
/// final resolver = WayfinderProfileResolver(
///   dataDirectory: WayfinderDataDirectory.resolve(),
/// );
/// for (final bundle in project.bundles) {
///   final result = await validateWithProfileSources(
///     bundle.root,
///     resolver: resolver,
///   );
///   print('${bundle.name}: ${result.gate.wireValue}');
/// }
/// ```
library;

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
        GitResult,
        GitRunner,
        runGit,
        wayfinderGitEnvironment,
        wayfinderGitOptions,
        wayfinderGitTimeout;
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
        ProfileLock,
        ProfileResolutionPlan,
        ProfileResolutionResult,
        WayfinderProfileResolutionException,
        WayfinderProfileResolver,
        validateWithProfileSources;
export 'src/project/profile_skills.dart'
    show MaterializedSkill, ProfileSkills, SkillFile, SkillRevision;
export 'src/project/project_bundles.dart'
    show ProjectBundle, WayfinderProject, explicitBundlePrefix;
