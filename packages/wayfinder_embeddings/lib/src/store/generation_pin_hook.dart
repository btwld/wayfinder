/// A hook this package's tests set on a `WayfinderKnowledgeStore`. No
/// public library exports it, so it is not part of the store's API.
library;

/// Runs after a reader of a store reads the `current` pointer and before it
/// opens the generation the pointer names, with that generation's name.
/// Tests use it to race garbage collection against a read.
final generationPinned = Expando<Future<void> Function(String generation)>(
  'generationPinned',
);
