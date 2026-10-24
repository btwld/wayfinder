import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:wayfinder/project.dart';

import 'embedding_model_spec.dart';

/// The pinned model an [EmbeddingModelCache] provides, and where it goes.
///
/// A host shows these facts before it asks to download: what is fetched
/// ([source], [bytes]), how it is checked ([sha256]) and where it is
/// written ([file]).
final class EmbeddingModelTarget {
  const EmbeddingModelTarget._(this.spec, this.file);

  /// The pinned artifact, including its preprocessing contract.
  final EmbeddingModelSpec spec;

  /// Where the verified model lives in the cache directory.
  final File file;

  /// The immutable URL the bytes are downloaded from.
  Uri get source => Uri.parse(spec.url);

  /// The exact size of the artifact.
  int get bytes => spec.bytes;

  /// The lowercase hexadecimal SHA-256 of the artifact.
  String get sha256 => spec.sha256;
}

/// One step of [EmbeddingModelCache.provision].
///
/// A download reports [ModelDownloading] as bytes arrive, then
/// [ModelVerifying], then [ModelProvisioned]. A model already in place
/// reports only [ModelProvisioned].
sealed class ModelProvisionProgress {
  const ModelProvisionProgress();
}

/// The bytes received so far: reported for the first bytes, about once per
/// percent after them, and for the last.
final class ModelDownloading extends ModelProvisionProgress {
  const ModelDownloading._(this.receivedBytes, this.totalBytes);

  final int receivedBytes;

  /// The pinned size; a download never accepts more.
  final int totalBytes;

  /// Between 0 and 1.
  double get fraction => totalBytes == 0 ? 1 : receivedBytes / totalBytes;
}

/// The download is complete, and its size and SHA-256 are being checked.
final class ModelVerifying extends ModelProvisionProgress {
  const ModelVerifying._();
}

/// The last event: the verified model is in place.
final class ModelProvisioned extends ModelProvisionProgress {
  const ModelProvisioned._(this.file, {required this.downloaded});

  final File file;

  /// Whether this call downloaded [file], rather than finding it verified.
  final bool downloaded;
}

/// The local copy of a pinned embedding model, in one cache directory.
///
/// [locate] never touches the network. [provision] is the only call that
/// downloads, so a host makes it only after the user agrees to fetch the
/// [target]. A download goes to a temporary file in [directory], and only a
/// file whose size and SHA-256 match the pin is renamed into place. Several
/// processes may provision one directory at once: each writes its own
/// temporary file, and every rename installs the same bytes.
///
/// Failures are [WayfinderException]s with these codes:
///
/// - `model-download-failed` for a network error, a response other than
///   200, or a download that receives nothing for [stallTimeout];
/// - `model-invalid` when the downloaded size or SHA-256 differs from the
///   pin, or the response announces a size other than the pinned one;
/// - `model-cache-unavailable` when the cache directory cannot be created or
///   written, something other than the model is in the way of the target,
///   or [remove] cannot delete the model;
/// - `cancelled` when the `WayfinderCancellation` passed to [provision]
///   stops it;
/// - `data-directory-unavailable` from the default constructor, when no
///   `dataDirectory` is given and the Wayfinder data directory cannot be
///   located.
final class EmbeddingModelCache {
  /// A cache of [spec] in `models/<id>` of `dataDirectory`, by default the
  /// Wayfinder data directory ([WayfinderDataDirectory.resolve]), beside its
  /// indexes and Profiles.
  ///
  /// `client` performs downloads and stays open; without one, each
  /// [provision] opens and closes its own.
  EmbeddingModelCache({
    Directory? dataDirectory,
    EmbeddingModelSpec spec = localEmbeddingModel,
    http.Client? client,
    Duration stallTimeout = const Duration(minutes: 1),
  }) : this.inDirectory(
         Directory(
           p.join(
             (dataDirectory ?? WayfinderDataDirectory.resolve()).path,
             'models',
             spec.id,
           ),
         ),
         spec: spec,
         client: client,
         stallTimeout: stallTimeout,
       );

  /// A cache of [spec] in [directory] itself.
  ///
  /// The model keeps the name a staged `models/` directory gives it
  /// ([EmbeddingModelSpec.fileName]), so such a directory is also a cache
  /// directory.
  EmbeddingModelCache.inDirectory(
    this.directory, {
    this.spec = localEmbeddingModel,
    http.Client? client,
    this.stallTimeout = const Duration(minutes: 1),
  }) : _client = client;

  /// Holds the model and, during a download, its temporary file.
  final Directory directory;

  final EmbeddingModelSpec spec;

  /// How long a download may wait for a response, or for its next bytes,
  /// before it fails.
  final Duration stallTimeout;

  final http.Client? _client;

  /// The pinned model and its place in [directory].
  EmbeddingModelTarget get target =>
      EmbeddingModelTarget._(spec, File(p.join(directory.path, spec.fileName)));

  /// The first verified copy of the model: the cache's own, then each of
  /// [alsoCheck] in order, such as the model an installed Wayfinder bundle
  /// ships. Returns null when none matches the pinned size and SHA-256.
  ///
  /// It reads files only and never touches the network.
  Future<File?> locate({Iterable<File> alsoCheck = const []}) async {
    for (final file in [target.file, ...alsoCheck]) {
      if (await _matches(file)) return file;
    }
    return null;
  }

  /// Deletes the model at the [target] and the temporary files of this
  /// cache's downloads, and returns the paths it deleted. It reads and
  /// deletes files only, never touches the network, and deletes a file at
  /// the target whether or not it verifies. The cache directory stays.
  ///
  /// Throws `model-cache-unavailable`, having deleted no model, when
  /// something other than a file or link is at the target, or the model
  /// cannot be deleted, such as one an engine holds open on Windows. A
  /// temporary file that cannot be deleted, such as one a download in
  /// progress holds open on Windows, is left for a later [provision] to
  /// remove. Remove the model while no [provision] runs for this directory,
  /// in this process or another: one that runs meanwhile either fails or
  /// installs the model again.
  Future<List<String>> remove() async {
    final removed = <String>[];
    final path = target.file.path;
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.link) {
        throw WayfinderException(
          'model-cache-unavailable',
          'The embedding model cache ${directory.path} holds something other '
              'than the model at $path.',
        );
      }
      final FileSystemEntity model = type == FileSystemEntityType.link
          ? Link(path)
          : File(path);
      try {
        await model.delete();
        removed.add(path);
      } on PathNotFoundException {
        // Another removal deleted it first.
      } on FileSystemException catch (error) {
        final os = error.osError?.message ?? error.message;
        throw WayfinderException(
          'model-cache-unavailable',
          'The embedding model $path cannot be deleted: $os.',
        );
      }
    }
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File || !_ownPartial.hasMatch(p.basename(entry.path))) {
          continue;
        }
        try {
          await entry.delete();
          removed.add(entry.path);
        } on FileSystemException {
          // Removed meanwhile, or held open by a download on Windows.
        }
      }
    } on FileSystemException {
      // No cache directory: nothing was downloaded.
    }
    return removed;
  }

  /// Installs the verified model in [directory] unless it is already there.
  ///
  /// The stream ends with [ModelProvisioned], or with an error and nothing
  /// installed. A model already in place is reported without a request.
  /// Otherwise the model is downloaded from the [target]'s source, with
  /// [ModelDownloading] as bytes arrive. [cancel], or cancelling the
  /// subscription, stops the download. Either way the temporary file is
  /// removed before the stream ends or the cancellation completes, and
  /// [cancel] ends the stream with a `cancelled` error. A failed or
  /// cancelled download leaves any existing file at the target untouched.
  ///
  /// It also removes the temporary files of downloads that stopped at least
  /// a day ago without removing them, such as one whose process was killed.
  /// A download in progress writes far more often, so its file is kept.
  Stream<ModelProvisionProgress> provision({WayfinderCancellation? cancel}) {
    final stop = Completer<void>();
    void halt() {
      if (!stop.isCompleted) stop.complete();
    }

    late final StreamController<ModelProvisionProgress> events;
    Future<void>? running;
    events = StreamController<ModelProvisionProgress>(
      onListen: () {
        if (cancel != null) unawaited(cancel.whenCancelled.then((_) => halt()));
        running = _provision(events.add, stop.future, cancel)
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) =>
                  events.addError(error, stackTrace),
            )
            .whenComplete(() => unawaited(events.close()));
      },
      onCancel: () {
        halt();
        return running;
      },
    );
    return events.stream;
  }

  Future<void> _provision(
    void Function(ModelProvisionProgress) emit,
    Future<void> stop,
    WayfinderCancellation? cancel,
  ) async {
    var stopped = false;
    unawaited(stop.then((_) => stopped = true));
    void checkStopped() {
      if (stopped) throw const WayfinderException.cancelled();
      throwIfCancelled(cancel);
    }

    checkStopped();
    await _removeAbandonedPartials();
    final found = await locate();
    if (found != null) {
      emit(ModelProvisioned._(found, downloaded: false));
      return;
    }
    checkStopped();
    final File partial;
    try {
      await directory.create(recursive: true);
      partial = await _createPartial();
    } on FileSystemException catch (error) {
      throw _cacheUnavailable(error);
    }
    final abort = Completer<void>();
    unawaited(stop.then((_) => _complete(abort)));
    final client = _client ?? http.Client();
    try {
      final response = await _send(client, stop, abort);
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.listen(null).cancel();
        throw WayfinderException(
          'model-download-failed',
          'Downloading the embedding model from ${target.source} failed: '
              'HTTP ${response.statusCode}.',
        );
      }
      // A client that decodes a compressed body still reports the encoded
      // length, so only an unencoded length can be held to the pin.
      final announced = response.contentLength;
      final encoding = response.headers['content-encoding']?.trim();
      if (announced != null &&
          announced != spec.bytes &&
          (encoding == null ||
              encoding.isEmpty ||
              encoding.toLowerCase() == 'identity')) {
        await response.stream.listen(null).cancel();
        throw WayfinderException(
          'model-invalid',
          'The server announces $announced bytes for the embedding model; '
              'expected ${spec.bytes}.',
        );
      }
      final sink = partial.openWrite();
      // Report about once per percent, not once per network chunk.
      final step = max(1, spec.bytes ~/ 100);
      var received = 0;
      var reported = 0;
      try {
        await _receive(response.stream, stop, (chunk) {
          received += chunk.length;
          if (received > spec.bytes) throw _sizeMismatch(received, more: true);
          sink.add(chunk);
          if (reported == 0 ||
              received == spec.bytes ||
              received - reported >= step) {
            reported = received;
            emit(ModelDownloading._(received, spec.bytes));
          }
        });
      } finally {
        await sink.close();
      }
      checkStopped();
      emit(const ModelVerifying._());
      final size = await partial.length();
      if (size != spec.bytes) throw _sizeMismatch(size);
      final digest = (await crypto.sha256.bind(partial.openRead()).first)
          .toString();
      if (digest != spec.sha256) {
        throw WayfinderException(
          'model-invalid',
          'The downloaded embedding model has SHA-256 $digest; '
              'expected ${spec.sha256}.',
        );
      }
      checkStopped();
      try {
        await partial.rename(target.file.path);
      } on FileSystemException {
        // Windows refuses to replace a file another process holds open, such
        // as a model a concurrent provision installed and an engine loaded.
        if (!await _matches(target.file)) rethrow;
        emit(ModelProvisioned._(target.file, downloaded: false));
        return;
      }
      emit(ModelProvisioned._(target.file, downloaded: true));
    } on WayfinderException {
      rethrow;
    } on Object catch (error) {
      // An aborted request reports its own error; the caller asked to stop.
      if (stopped) throw const WayfinderException.cancelled();
      if (error is FileSystemException) throw _cacheUnavailable(error);
      if (error is http.ClientException || error is IOException) {
        throw WayfinderException(
          'model-download-failed',
          'Downloading the embedding model from ${target.source} failed: '
              '$error',
        );
      }
      rethrow;
    } finally {
      _complete(abort);
      if (_client == null) client.close();
      try {
        if (await partial.exists()) await partial.delete();
      } on FileSystemException {
        // A later provision removes a file Windows still held open here,
        // once it is a day old.
      }
    }
  }

  /// A new, uniquely named file in [directory], so concurrent downloads and
  /// an interrupted earlier one never share it.
  Future<File> _createPartial() async {
    final random = Random.secure();
    for (var attempt = 1; ; attempt++) {
      final suffix = [
        for (var i = 0; i < 8; i++)
          random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      final file = File(p.join(directory.path, _partialName(suffix)));
      try {
        return await file.create(exclusive: true);
      } on FileSystemException {
        if (attempt == 3) rethrow;
      }
    }
  }

  String _partialName(String suffix) => '.${spec.fileName}.$suffix.part';

  /// Deletes the temporary files in [directory] that no download has written
  /// to for [_abandonedAfter]. A download in progress, in this process or
  /// another, fails unless bytes arrive within its stall timeout, a minute
  /// by default, so its file is never that old.
  Future<void> _removeAbandonedPartials() =>
      _removeAbandoned(directory, _ownPartial);

  /// The name of a temporary file of a download of this cache's model.
  late final _ownPartial = RegExp(
    '^${RegExp.escape('.${spec.fileName}.')}[0-9a-f]{16}\\.part\$',
  );

  /// Deletes the temporary files of downloads into the default cache
  /// directories, `models/<id>/` under [dataDirectory], that stopped at
  /// least a day ago without removing them, such as one whose process was
  /// killed, whatever model they were for, and returns their paths.
  /// [provision] does the same for its own model; this serves a host that
  /// cleans its data directory without provisioning again. A download in
  /// progress writes far more often, so its file is kept.
  static Future<List<String>> removeAbandonedDownloads(
    Directory dataDirectory,
  ) async {
    final removed = <String>[];
    final models = Directory(p.join(dataDirectory.path, 'models'));
    try {
      await for (final entry in models.list(followLinks: false)) {
        if (entry is! Directory) continue;
        removed.addAll(await _removeAbandoned(entry, _anyPartial));
      }
    } on FileSystemException {
      // No model cache yet.
    }
    return removed;
  }

  static final _anyPartial = RegExp(r'^\..+\.[0-9a-f]{16}\.part$');

  static Future<List<String>> _removeAbandoned(
    Directory directory,
    RegExp name,
  ) async {
    final removed = <String>[];
    final cutoff = DateTime.now().subtract(_abandonedAfter);
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is! File || !name.hasMatch(p.basename(entry.path))) continue;
        try {
          if ((await entry.lastModified()).isBefore(cutoff)) {
            await entry.delete();
            removed.add(entry.path);
          }
        } on FileSystemException {
          // Another provision removed it first, or Windows holds it open.
        }
      }
    } on FileSystemException {
      // A missing or unreadable directory has nothing to remove.
    }
    return removed;
  }

  static const _abandonedAfter = Duration(days: 1);

  /// The response to a request for the model, abandoned when [stop]
  /// completes or no response arrives within [stallTimeout], even if the
  /// client ignores [abort].
  Future<http.StreamedResponse> _send(
    http.Client client,
    Future<void> stop,
    Completer<void> abort,
  ) {
    final result = Completer<http.StreamedResponse>();
    late final Timer stall;
    void fail(Object error, [StackTrace? stackTrace]) {
      stall.cancel();
      if (result.isCompleted) return;
      result.completeError(error, stackTrace);
      _complete(abort);
    }

    stall = Timer(stallTimeout, () => fail(_stalled()));
    final request = http.AbortableRequest(
      'GET',
      target.source,
      abortTrigger: abort.future,
    );
    unawaited(
      Future.sync(() => client.send(request)).then(
        (response) {
          stall.cancel();
          if (!result.isCompleted) return result.complete(response);
          // Release a response that arrives after the caller gave up.
          unawaited(response.stream.listen(null).cancel());
        },
        onError: (Object error, StackTrace stackTrace) =>
            fail(error, stackTrace),
      ),
    );
    unawaited(stop.then((_) => fail(const WayfinderException.cancelled())));
    return result.future;
  }

  /// Passes each chunk of [body] to [onChunk] until the body ends, fails,
  /// brings nothing for [stallTimeout], or [stop] completes.
  Future<void> _receive(
    Stream<List<int>> body,
    Future<void> stop,
    void Function(List<int> chunk) onChunk,
  ) {
    final done = Completer<void>();
    Timer? stall;
    // A synchronous body can end inside listen, before this is assigned.
    StreamSubscription<List<int>>? subscription;
    void finish([Object? error, StackTrace? stackTrace]) {
      if (done.isCompleted) return;
      stall?.cancel();
      unawaited(subscription?.cancel());
      if (error == null) {
        done.complete();
      } else {
        done.completeError(error, stackTrace);
      }
    }

    void watch() {
      stall?.cancel();
      if (!done.isCompleted) {
        stall = Timer(stallTimeout, () => finish(_stalled()));
      }
    }

    subscription = body.listen(
      (chunk) {
        if (done.isCompleted) return;
        try {
          onChunk(chunk);
          watch();
        } on Object catch (error, stackTrace) {
          finish(error, stackTrace);
        }
      },
      onError: finish,
      onDone: finish,
      cancelOnError: true,
    );
    if (done.isCompleted) unawaited(subscription.cancel());
    watch();
    unawaited(stop.then((_) => finish(const WayfinderException.cancelled())));
    return done.future;
  }

  WayfinderException _stalled() => WayfinderException(
    'model-download-failed',
    'Downloading the embedding model from ${target.source} stalled: nothing '
        'arrived for ${stallTimeout.inSeconds} s.',
  );

  WayfinderException _cacheUnavailable(FileSystemException error) {
    final path = error.path == null ? '' : ' (${error.path})';
    final os = error.osError?.message ?? '';
    return WayfinderException(
      'model-cache-unavailable',
      'The embedding model cache ${directory.path} cannot be written: '
          '${error.message}$path${os.isEmpty ? '' : ': $os'}.',
    );
  }

  WayfinderException _sizeMismatch(int bytes, {bool more = false}) =>
      WayfinderException(
        'model-invalid',
        'The downloaded embedding model has ${more ? 'more than ' : ''}'
            '$bytes bytes; expected ${spec.bytes}.',
      );

  Future<bool> _matches(File file) async {
    try {
      if (await file.length() != spec.bytes) return false;
      final digest = await crypto.sha256.bind(file.openRead()).first;
      return digest.toString() == spec.sha256;
    } on FileSystemException {
      return false;
    }
  }

  static void _complete(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }
}
