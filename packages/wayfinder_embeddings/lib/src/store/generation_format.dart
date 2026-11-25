import 'dart:io';
import 'dart:typed_data';

/// A canonical record and its float32 rows in snapshot chunk order.
final class GenerationData {
  const GenerationData(this.record, this.vectors, {required this.dimension});

  /// Opaque to the format; return this text verbatim on read.
  final String record;
  final List<Float32List> vectors;

  /// The row width, also when there are no rows.
  final int dimension;
}

/// A generation or a required file disappeared or could not be opened.
final class GenerationGone implements Exception {
  const GenerationGone();
}

/// An original float32 row and its ordinal in snapshot chunk order.
final class NearRow {
  const NearRow(this.ordinal, this.vector);

  final int ordinal;
  final Float32List vector;
}

/// Stores one immutable generation. Publication and cleanup belong to the core.
abstract interface class GenerationFormat {
  /// A diagnostic name, never persisted by the core.
  String get name;

  /// A unique identifying filename in the generation directory, written last.
  String get marker;

  Future<void> write(Directory staged, GenerationData data);

  /// Opens without changing the generation. Missing files throw
  /// [GenerationGone]; corrupt content throws a different error.
  Future<GenerationReader> open(Directory generation);
}

/// A read-only view of one generation. Returned row data remains valid until
/// the reader closes. The core detaches any data it keeps beyond that point.
abstract interface class GenerationReader {
  /// The row width the generation was written with.
  int get dimension;

  Future<String> record();
  Future<int> rowCount();

  /// Every original row, in ordinal order, for verification and reuse.
  Future<List<Float32List>> vectors();

  /// Selected original rows in the order requested, including duplicates.
  Future<List<Float32List>> rows(List<int> ordinals);

  /// The [count] rows nearest by cosine similarity, best first, among
  /// [allowed] (null means every row). May return fewer only if there are
  /// fewer eligible rows. Return original float32 values, not normalized or
  /// quantized copies: the core computes final scores and breaks ties.
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  });

  Future<void> close();
}
