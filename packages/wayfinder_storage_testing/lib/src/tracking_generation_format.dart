import 'dart:io';
import 'dart:typed_data';

import 'package:wayfinder_embeddings/knowledge_store.dart';

/// Wraps a format and records what the core asks of its readers.
final class TrackingGenerationFormat implements GenerationFormat {
  TrackingGenerationFormat(this.delegate);

  /// The format that does the work.
  final GenerationFormat delegate;

  /// The `count` of each `nearest` call.
  final nearestCounts = <int>[];

  /// The ordinals each `nearest` call returned.
  final nearestOrdinals = <List<int>>[];

  /// The ordinals of each `rows` call.
  final rowRequests = <List<int>>[];

  /// How many readers opened.
  int opens = 0;

  /// How many readers closed.
  int closes = 0;

  /// How many `vectors` calls the readers answered.
  int vectorReads = 0;

  /// Whether `nearest` returns one row fewer than asked.
  bool short = false;

  @override
  String get name => delegate.name;
  @override
  String get marker => delegate.marker;
  @override
  Future<void> write(Directory staged, GenerationData data) =>
      delegate.write(staged, data);
  @override
  Future<GenerationReader> open(Directory generation) async {
    final reader = await delegate.open(generation);
    opens++;
    return _TrackingReader(this, reader);
  }
}

final class _TrackingReader implements GenerationReader {
  const _TrackingReader(this.tracking, this.delegate);
  final TrackingGenerationFormat tracking;
  final GenerationReader delegate;

  @override
  int get dimension => delegate.dimension;
  @override
  Future<String> record() => delegate.record();
  @override
  Future<int> rowCount() => delegate.rowCount();
  @override
  Future<List<Float32List>> vectors() {
    tracking.vectorReads++;
    return delegate.vectors();
  }

  @override
  Future<List<Float32List>> rows(List<int> ordinals) {
    tracking.rowRequests.add(ordinals);
    return delegate.rows(ordinals);
  }

  @override
  Future<List<NearRow>> nearest(
    Float32List query,
    int count, {
    Set<int>? allowed,
  }) async {
    tracking.nearestCounts.add(count);
    final rows = await delegate.nearest(
      query,
      tracking.short ? count - 1 : count,
      allowed: allowed,
    );
    tracking.nearestOrdinals.add(rows.map((row) => row.ordinal).toList());
    return rows;
  }

  @override
  Future<void> close() async {
    await delegate.close();
    tracking.closes++;
  }
}
