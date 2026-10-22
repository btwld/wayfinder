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
/// Only this package produces those Dart chunks, so this test is that
/// golden's only writer: it checks it, and rewrites all of it with
/// `UPDATE_GOLDENS=1`. `wayfinder_embeddings` only compares against it.
final _embeddings = p.join('..', 'wayfinder_embeddings');
final _corpus = Directory(p.join(_embeddings, 'fixtures', 'corpus'));
final _golden = File(
  p.join(_embeddings, 'test', 'goldens', 'baseline_chunks.json'),
);

/// Whether this runs in CI, where the checkout is always complete.
///
/// This is the only check of the corpus's Dart chunks, so in CI a missing
/// corpus fails it instead of skipping it.
final _inCi = Platform.environment['CI'] == 'true';

void main() {
  test(
    'reproduces the judged corpus reference chunks of wayfinder_embeddings',
    () {
      expect(
        _corpus.existsSync(),
        isTrue,
        reason:
            'The judged corpus of wayfinder_embeddings is not at '
            '${_corpus.path}; update this test if it moved.',
      );
      expectChunkGolden(
        registry: defaultCodeRegistry(),
        fixturesDir: _corpus,
        golden: _golden,
      );
    },
    skip: _corpus.existsSync() || _inCi
        ? null
        : 'Needs the wayfinder repository checkout beside this package.',
  );
}
