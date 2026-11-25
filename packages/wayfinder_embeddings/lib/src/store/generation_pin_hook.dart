/// A hook for the storage contract suites, exported only by `testing.dart`.
library;

/// Runs after a reader of a store reads the `current` pointer and before it
/// opens the generation the pointer names, with that generation's name.
/// Tests use it to race garbage collection against a read.
final generationPinned = Expando<Future<void> Function(String generation)>(
  'generationPinned',
);
