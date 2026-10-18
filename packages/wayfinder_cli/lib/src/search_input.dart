import 'package:ack/ack.dart';
import 'package:wayfinder_embeddings/okf_knowledge.dart';

/// Shared search contract after CLI argument strings are converted to numbers.
// Include Unicode NEXT LINE, which Dart trim treats as whitespace.
final wayfinderSearchInput = Ack.object({
  'query': Ack.string()
      .minLength(1)
      .matches(
        r'[^\s\u0085]',
        message: 'Query must contain non-whitespace characters.',
      ),
  'limit': Ack.integer().min(1).max(100).optional().withDefault(5),
  'surroundingLines': Ack.integer().min(0).max(100).optional(),
  'contextTokens': Ack.integer().min(1).max(65536).optional(),
});

KnowledgeContextWindowOptions? searchContextWindowOptions(
  Map<String, Object?> input,
) => input['surroundingLines'] == null && input['contextTokens'] == null
    ? null
    : KnowledgeContextWindowOptions(
        surroundingLines: input['surroundingLines'] as int? ?? 12,
        maxTokens: input['contextTokens'] as int? ?? 4096,
      );
