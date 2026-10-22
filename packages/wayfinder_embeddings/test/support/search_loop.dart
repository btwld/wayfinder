/// A search loop for the read-while-index tests: it searches one bundle
/// with `StaleIndexPolicy.serveWhileRefreshing` until told to stop, and
/// records every failure, every result that differs from a reference, and
/// how often a refresh was running.
///
/// The concurrency test runs [searchLoop] in a second isolate, and this
/// file's [main] as a subprocess from a kernel snapshot, which runs no build
/// hooks:
///
/// ```sh
/// dart compile kernel test/support/search_loop.dart --output=search_loop.dill
/// dart search_loop.dill <data> <bundle root> <reference>
/// ```
///
/// The subprocess prints `refresh` once it has seen a refresh, and a final
/// `summary <json>` line once its stdin closes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wayfinder/project.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/src/store/generation_pin_hook.dart';
import 'package:wayfinder_embeddings/testing.dart';

/// The model every encoder of the concurrency test reports.
const concurrencyModel = 'concurrency-fixture-v1';

/// The query every search of the loop runs.
const concurrencyQuery = 'password recovery link';

/// What a search returned, without its notices, which a refresh changes.
String searchFingerprint(KnowledgeBundleSearch result) {
  final json = result.toJson();
  return jsonEncode({'matches': json['matches'], 'context': json['context']});
}

/// Searches the bundle at [root] until [stop] completes, comparing each
/// result with [reference], and calls [onRefresh] the first time a search
/// reports a refresh in progress.
Future<Map<String, Object?>> searchLoop({
  required String data,
  required String root,
  required String reference,
  required Future<void> stop,
  void Function()? onRefresh,
}) async {
  final store = WayfinderKnowledgeStore(
    dataDirectory: Directory(data),
    encoder: DeterministicEncoderProvider(model: concurrencyModel),
  );
  final bundle = ProjectBundle('knowledge', 'knowledge', root);
  var stopped = false;
  unawaited(stop.then((_) => stopped = true));
  var searches = 0;
  var refreshes = 0;
  var pins = 0;
  final failures = <String>[];
  final mismatches = <String>[];
  generationPinned[store] = (_) async => pins++;
  try {
    while (!stopped) {
      try {
        final result = await store.searchBundle(
          bundle,
          concurrencyQuery,
          stale: StaleIndexPolicy.serveWhileRefreshing,
        );
        searches++;
        if (result.freshness.refreshing &&
            result.notices.any(
              (notice) => notice.code == KnowledgeNoticeCode.refreshInProgress,
            )) {
          if (refreshes++ == 0) onRefresh?.call();
        }
        final fingerprint = searchFingerprint(result);
        if (fingerprint != reference) mismatches.add(fingerprint);
      } on Object catch (error) {
        failures.add('$error');
      }
      // Lets the stop signal arrive.
      await Future<void>.delayed(Duration.zero);
    }
  } finally {
    await store.dispose();
  }
  return {
    'searches': searches,
    'refreshes': refreshes,
    'retries': pins - searches - failures.length,
    'failures': failures,
    'mismatches': mismatches,
  };
}

Future<void> main(List<String> arguments) async {
  final [data, root, referenceFile] = arguments;
  final stop = Completer<void>();
  stdin.listen(null, onDone: stop.complete);
  final summary = await searchLoop(
    data: data,
    root: root,
    reference: await File(referenceFile).readAsString(),
    stop: stop.future,
    onRefresh: () => stdout.writeln('refresh'),
  );
  stdout.writeln('summary ${jsonEncode(summary)}');
  await stdout.flush();
}
