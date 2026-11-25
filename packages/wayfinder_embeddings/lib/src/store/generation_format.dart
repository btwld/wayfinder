import 'dart:io';
import 'dart:typed_data';

/// What a format writes: the canonical record and its float32 rows in
/// snapshot chunk order.
final class GenerationData {
  const GenerationData(this.record, this.vectors, {required this.dimension});

  /// The canonical record. A format stores it unchanged and never parses it.
  final String record;

  /// One row per snapshot chunk, in chunk order.
  final List<Float32List> vectors;

  /// The row width, also when there are no rows.
  final int dimension;
}

/// Thrown when a generation or one of its files is missing or cannot be
/// opened, so the core can read the `current` pointer again.
final class GenerationGone implements Exception {
  const GenerationGone();
}

/// An original float32 row and its ordinal in snapshot chunk order.
final class NearRow {
  const NearRow(this.ordinal, this.vector);

  final int ordinal;
  final Float32List vector;
}

/// A storage layout for one immutable generation.
///
/// The core owns publication, the `current` pointer and cleanup.
abstract interface class GenerationFormat {
  /// A name for messages and test groups. The core never stores it.
  String get name;

  /// The file name that identifies this format in a generation directory.
  String get marker;

  /// Writes [data] into the empty directory [staged].
  ///
  /// Write only inside [staged], flush every file, and write [marker] last.
  /// Preserve every float32 bit.
  Future<void> write(Directory staged, GenerationData data);

  /// Opens [generation] for reading and leaves it unchanged.
  ///
  /// Throws [GenerationGone] when a file is missing. Throws a different error
  /// when the content is corrupt.
  Future<GenerationReader> open(Directory generation);
}

/// A read-only view of one generation.
///
/// Rows that a reader returns stay valid until [close]. The core copies any
/// row it keeps after that.
abstract interface class GenerationReader {
  /// The row width the generation was written with.
  int get dimension;

  /// Returns the record exactly as it was written.
  Future<String> record();

  /// Returns the number of rows.
  Future<int> rowCount();

  /// Returns every row in ordinal order. The core reads all rows only to
  /// verify or republish a generation, never to search.
  Future<List<Float32List>> vectors();

  /// Returns the rows at [ordinals], in the order given, including repeats.
  Future<List<Float32List>> rows(List<int> ordinals);

  /// Returns the [count] rows nearest to [query] by cosine similarity, best
  /// first.
  ///
  /// When [allowed] is not null, only those ordinals are eligible. Return
  /// fewer than [count] rows only when fewer rows are eligible; the core
  /// treats any other short answer as an incompatible index. Return the
  /// stored float32 values, not normalized or quantized copies, because the
  /// core computes the final scores and breaks ties.
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  });

  /// Releases the files and native resources the reader holds.
  Future<void> close();
}
