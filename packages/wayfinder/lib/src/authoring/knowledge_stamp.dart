/// Who makes a write, and whether they also confirm the concept against its
/// sources (OKF 0.2 §5.2).
///
/// Content the write creates or changes, a concept's body, `title`,
/// `description` or `type`, records `generated: {by, at}`. A link, a
/// deprecation, or an update of other fields keeps the concept's `generated`
/// as it is. A [KnowledgeStamp.verified] stamp also appends `{by, at}` to
/// the concept's `verified` events, turning a bare mapping into a list. The
/// repair `RegenerateIndexes` changes no concept and records neither.
final class KnowledgeStamp {
  /// [by] writes the change.
  const KnowledgeStamp.generated({required this.by, this.at})
    : verifies = false;

  /// [by] writes the change and confirms the concept as it stands after it.
  const KnowledgeStamp.verified({required this.by, this.at}) : verifies = true;

  /// An actor, such as `human:chris` or `claude-code/opus-5` (OKF 0.2 §7).
  final String by;

  /// When; the writer's clock when null. Written in UTC to the second, such
  /// as `2026-10-22T09:30:00Z`.
  final DateTime? at;

  /// Whether the write appends a `verified` event.
  final bool verifies;
}
