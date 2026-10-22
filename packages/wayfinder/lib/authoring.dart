/// Profile-aware writes to a knowledge bundle: prepare one change, judge
/// the candidate with okf and the selected Profile in memory, then commit
/// exactly what was judged.
///
/// `KnowledgeWriter.prepare` maps a [KnowledgeChange] onto okf's change set,
/// regenerates only the indexes whose generated text the change alters,
/// records the caller's log entry, and validates the candidate as
/// `wayfinder validate` would after the commit. It writes nothing.
/// `KnowledgeWriter.commit` writes the plan under okf's bundle lock, or
/// refuses one that okf rejects, that adds a Profile error, or whose bundle,
/// configuration or lock changed since. It needs `dart:io`; a host runs it
/// on the isolate that does its other okf bundle I/O (ADR-0018). ADR-0019
/// records these decisions.
///
/// ```dart
/// import 'package:okf/okf.dart';
/// import 'package:wayfinder/authoring.dart';
/// import 'package:wayfinder/project.dart';
///
/// Future<void> link(String bundle) async {
///   final writer = KnowledgeWriter(
///     resolver: WayfinderProfileResolver(
///       dataDirectory: WayfinderDataDirectory.resolve(),
///     ),
///   );
///   final plan = await writer.prepare(
///     bundle,
///     LinkConcepts(
///       source: OkfConceptId('reporting/include-pdf-annotations'),
///       relationship: KnowledgeRelationship.toConcept(
///         relationship: 'related-to',
///         target: OkfConceptId('ways-of-working/relationship-labels'),
///       ),
///     ),
///     stamp: const KnowledgeStamp.generated(by: 'claude-code/opus-5'),
///     logEntry: KnowledgeLog.none,
///   );
///   if (plan.committable) await writer.commit(plan);
/// }
/// ```
library;

export 'src/authoring/knowledge_change.dart'
    show
        CreateConcept,
        DeprecateConcept,
        KnowledgeChange,
        KnowledgeRelationship,
        LinkConcepts,
        RegenerateIndexes,
        UpdateConcept;
export 'src/authoring/knowledge_log.dart' show KnowledgeLog, KnowledgeLogEntry;
export 'src/authoring/knowledge_stamp.dart' show KnowledgeStamp;
export 'src/authoring/knowledge_writer.dart'
    show
        KnowledgeChangeException,
        KnowledgeCommitResult,
        KnowledgeFileDiff,
        KnowledgeStaleWriteException,
        KnowledgeWritePlan,
        KnowledgeWriteRefusedException,
        KnowledgeWriter;
