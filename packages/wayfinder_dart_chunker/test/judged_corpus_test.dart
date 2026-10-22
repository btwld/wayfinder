// ignore_for_file: avoid_slow_async_io
// Tests use sync file access for deterministic fixture handling.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder_dart_chunker/wayfinder_dart_chunker.dart';

import 'support/chunk_manifest.dart';

/// The judged retrieval corpus of `wayfinder_embeddings`, in this repository.
///
/// Its qrels name chunk ids, and its golden is the reference chunking that
/// `wayfinder_embeddings` replays for the Dart files it cannot chunk itself.
/// Only this package produces those Dart chunks, so it checks them here and
/// rewrites that golden with `UPDATE_GOLDENS=1`.
final _embeddings = p.join('..', 'wayfinder_embeddings');
final _corpus = Directory(p.join(_embeddings, 'fixtures', 'corpus'));
final _golden = File(
  p.join(_embeddings, 'test', 'goldens', 'baseline_chunks.json'),
);

void main() {
  test(
    'reproduces the judged corpus reference chunks of wayfinder_embeddings',
    () {
      expectChunkGolden(
        registry: defaultCodeRegistry(),
        fixturesDir: _corpus,
        golden: _golden,
      );
    },
    skip: _corpus.existsSync()
        ? null
        : 'Needs the wayfinder repository checkout beside this package.',
  );
}
