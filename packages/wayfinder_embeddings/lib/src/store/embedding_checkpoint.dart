import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../embedding/base_embedder.dart';
import 'generation.dart';

/// The vectors an unfinished index run embedded, so that the next run of the
/// bundle embeds only the rest.
///
/// One append-only file in an index directory, whose configuration key has
/// already fixed the model and the chunking, and whose writer lock the caller
/// holds. The file starts with a 16-byte header, the ASCII magic
/// `WFCP32\0\x01`, the dimension as a little-endian unsigned 32-bit integer,
/// and four zero bytes. Then come fixed-width records: the SHA-256 of an
/// embedding input, its vector as little-endian IEEE 754 float32 values, and
/// the SHA-256 of those two fields.
///
/// A vector is keyed by its input, not by its passage, for the reason a
/// generation's `inputs` are: the same model gives the same input the same
/// vector, so a passage edited between two runs is embedded again and the
/// rest are still reused. Reading stops at the first record that does not
/// check out, as a process killed mid-write leaves, and the next append
/// overwrites from there.
///
/// Keeping the file is an optimization, so failing to read or write it never
/// fails a run: the next run embeds those vectors again.
final class EmbeddingCheckpoint {
  EmbeddingCheckpoint(this.file);

  /// The file's name in an index directory.
  static const fileName = 'embeddings.partial';

  static const _headerBytes = 16;
  static const _digestBytes = 32;
  static final _magic = Uint8List.fromList([...ascii.encode('WFCP32'), 0, 1]);

  final File file;

  final _vectors = <String, List<double>>{};
  var _dimension = 0;
  var _validBytes = 0;
  RandomAccessFile? _output;
  var _failed = false;

  /// Reads the vectors [file] holds for [dimension]-dimensional embeddings.
  /// A file with another header holds none. With [resume] false, starts empty
  /// without reading the file; the next successful append replaces its contents.
  Future<void> load(int dimension, {bool resume = true}) async {
    _dimension = dimension;
    _vectors.clear();
    _validBytes = 0;
    if (!resume) return;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return;
    }
    if (!_startsWithHeader(bytes)) return;
    _validBytes = _headerBytes;
    final width = _digestBytes + dimension * 4;
    final view = ByteData.sublistView(bytes);
    while (_validBytes + width + _digestBytes <= bytes.length) {
      final start = _validBytes;
      final digest = sha256.convert(
        Uint8List.sublistView(bytes, start, start + width),
      );
      if (!_matches(digest.bytes, bytes, start + width)) return;
      final key = _hex(
        Uint8List.sublistView(bytes, start, start + _digestBytes),
      );
      _vectors[key] = [
        for (var i = 0; i < dimension; i++)
          view.getFloat32(start + _digestBytes + i * 4, Endian.little),
      ];
      _validBytes = start + width + _digestBytes;
    }
  }

  /// Adds a vector for each input hash in [inputs], flushed so that it
  /// survives the process. A vector a generation could not hold is left out,
  /// so that a later run asks for it again.
  Future<void> append(List<String> inputs, List<List<double>> vectors) async {
    if (_failed) return;
    final records = BytesBuilder(copy: false);
    for (final (index, input) in inputs.indexed) {
      final Uint8List encoded;
      try {
        encoded = IndexGeneration.encode([vectors[index]], _dimension);
      } on ArgumentError {
        continue;
      }
      final width = _dimension * 4;
      final body = Uint8List(_digestBytes + width)
        ..setRange(0, _digestBytes, _parseDigest(input))
        ..setRange(
          _digestBytes,
          _digestBytes + width,
          encoded,
          encoded.length - width,
        );
      records
        ..add(body)
        ..add(sha256.convert(body).bytes);
    }
    if (records.isEmpty) return;
    try {
      final output = _output ??= await _openOutput();
      await output.writeFrom(records.takeBytes());
      await output.flush();
    } on FileSystemException {
      _failed = true;
      await close();
    }
  }

  /// Closes the file, which stays for the next run.
  Future<void> close() async {
    final output = _output;
    _output = null;
    try {
      await output?.close();
    } on FileSystemException {
      // Everything written was flushed.
    }
  }

  /// Deletes the file, and what this object read from it.
  Future<void> discard() async {
    await close();
    _vectors.clear();
    _validBytes = 0;
    try {
      await file.delete();
    } on FileSystemException {
      // Missing, or a later run overwrites or deletes it.
    }
  }

  /// [bytes] in lowercase hexadecimal, as `Digest.toString` writes a digest.
  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _parseDigest(String digest) => Uint8List.fromList([
    for (var i = 0; i < _digestBytes; i++)
      int.parse(digest.substring(i * 2, i * 2 + 2), radix: 16),
  ]);

  bool _startsWithHeader(Uint8List bytes) {
    if (bytes.length < _headerBytes) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return ByteData.sublistView(bytes).getUint32(8, Endian.little) ==
        _dimension;
  }

  static bool _matches(List<int> digest, Uint8List bytes, int offset) {
    for (var i = 0; i < _digestBytes; i++) {
      if (digest[i] != bytes[offset + i]) return false;
    }
    return true;
  }

  /// Opens [file] for appending after its last valid record, dropping
  /// whatever follows, and writes its header when it has none.
  Future<RandomAccessFile> _openOutput() async {
    final output = await file.open(mode: FileMode.append);
    try {
      await output.truncate(_validBytes);
      await output.setPosition(_validBytes);
      if (_validBytes == 0) {
        final header = Uint8List(_headerBytes)
          ..setRange(0, _magic.length, _magic);
        ByteData.sublistView(header).setUint32(8, _dimension, Endian.little);
        await output.writeFrom(header);
        _validBytes = _headerBytes;
      }
      return output;
    } on FileSystemException {
      await output.close();
      rethrow;
    }
  }
}

/// An embedder that takes each input's vector from a checkpoint when it holds
/// one, encodes the rest with [delegate], and adds those to the checkpoint.
///
/// A reused vector counts as a batch's own, so a run's progress starts over
/// from zero, passes quickly over what an earlier run finished, and then
/// reports how much of the whole remains. Disposing it does nothing: the
/// delegate's owner disposes the delegate.
final class ResumingEmbedder extends BaseEmbedder {
  ResumingEmbedder(this.delegate, this.checkpoint);

  final BaseEmbedder delegate;
  final EmbeddingCheckpoint checkpoint;

  /// The inputs this embedder answered from [checkpoint].
  int reused = 0;

  @override
  String get sourceName => delegate.sourceName;

  @override
  String get modelName => delegate.modelName;

  @override
  int get dimension => delegate.dimension;

  @override
  Future<List<double>> generateEmbedding(String text) =>
      delegate.generateEmbedding(text);

  @override
  Future<List<double>> generateQueryVector(String text) =>
      delegate.generateQueryVector(text);

  @override
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final hashes = [
      for (final text in texts) sha256.convert(utf8.encode(text)).toString(),
    ];
    final vectors = [for (final hash in hashes) checkpoint._vectors[hash]];
    final missing = [
      for (final (index, vector) in vectors.indexed)
        if (vector == null) index,
    ];
    reused += texts.length - missing.length;
    if (missing.isNotEmpty) {
      final encoded = await delegate.generateEmbeddings([
        for (final index in missing) texts[index],
      ]);
      if (encoded.length != missing.length ||
          encoded.any((vector) => vector.length != dimension)) {
        throw StateError('Embedder returned an invalid batch shape.');
      }
      for (final (position, index) in missing.indexed) {
        vectors[index] = encoded[position];
      }
      await checkpoint.append([
        for (final index in missing) hashes[index],
      ], encoded);
    }
    return vectors.cast<List<double>>();
  }
}
