/// Programmatic adoption: bind a project to a Profile, lock and install
/// it, and seed its knowledge bundle, as the adopt-knowledge-bundle skill
/// describes (ADR-0020).
///
/// [KnowledgeAdoption.plan] reads the project and resolves the Profile, and
/// writes nothing in the project; the plan lists every file, Git fetch and
/// conflict, and fetches only what [AdoptionRequest.allowFetch] allows.
/// [KnowledgeAdoption.apply] writes `wayfinder.json`, `wayfinder.lock`, the
/// seeded bundle, the Profile skills and a `.gitignore` line, then the
/// host's own step, or nothing, while it holds the project's `get` lock,
/// then validates. It never writes `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or
/// hooks: the plan returns the agent-instruction block as text. Like the
/// rest of `package:wayfinder/project.dart`, run it on the isolate that
/// does the process's okf bundle I/O (ADR-0018).
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:wayfinder/adoption.dart';
/// import 'package:wayfinder/project.dart';
/// import 'package:wayfinder/wayfinder.dart';
///
/// Future<void> main() async {
///   final adoption = KnowledgeAdoption(
///     resolver: WayfinderProfileResolver(
///       dataDirectory: WayfinderDataDirectory.resolve(),
///     ),
///   );
///   final plan = await adoption.plan(
///     AdoptionRequest(
///       projectRoot: Directory.current.path,
///       profile: ProfileId.parse('bitwild-profile'),
///       source: const AdoptionSource(
///         git: 'https://github.com/btwld/wayfinder',
///         path: 'profiles/bitwild',
///       ),
///     ),
///   );
///   for (final conflict in plan.conflicts) print(conflict);
///   if (!plan.applicable) return;
///   final result = await adoption.apply(plan);
///   print(result.validation?.gate.wireValue);
///   print(plan.agentInstructions);
/// }
/// ```
library;

export 'src/adoption/knowledge_adoption.dart'
    show KnowledgeAdoption, KnowledgeAdoptionPlan, KnowledgeAdoptionResult;
export 'src/adoption/model.dart'
    show
        AdoptionBundleMode,
        AdoptionConflict,
        AdoptionFile,
        AdoptionFileAction,
        AdoptionFileKind,
        AdoptionProfile,
        AdoptionStep,
        AdoptionStepOutcome,
        AdoptionStepReport,
        KnowledgeAdoptionException;
export 'src/adoption/request.dart'
    show AdoptionRequest, AdoptionSeedConcept, AdoptionSource;
export 'src/adoption/seeds.dart' show KnowledgeSeeds;
