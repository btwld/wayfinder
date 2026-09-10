import 'package:ack/ack.dart';

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
});
