import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:wayfinder_embeddings/src/store/generation.dart';
import 'package:wayfinder_embeddings/src/store/sqlite_generation.dart';

/// Test-only record access for deliberate corruption and cache invalidation.
/// Updating the checksum lets tests exercise the domain decoder after SQLite.
class GenerationRecord {
  GenerationRecord(String path) : file = File(path);
  final File file;

  Future<String> readAsString() async {
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      return db
              .select('SELECT record_json FROM generation_records')
              .single['record_json']
          as String;
    } finally {
      db.close();
    }
  }

  Future<void> writeAsString(String text) async {
    final db = sqlite3.open(file.path);
    try {
      db.execute('BEGIN');
      db.execute(
        'INSERT OR REPLACE INTO generation_records (id, record_json, checksum) VALUES (1, ?, ?)',
        [text, sha256.convert(utf8.encode(text)).toString()],
      );
      // Coherent record edits update the typed chunk projection as well.
      // Malformed records deliberately remain malformed for refusal tests.
      try {
        final map = jsonDecode(text) as Map;
        final snapshot = map['snapshot'];
        if (snapshot is Map && snapshot['chunks'] is List) {
          for (final chunk in snapshot['chunks'] as List) {
            final c = chunk as Map;
            db.execute(
              'UPDATE stored_chunks SET source_path = ?, line_start = ?, line_end = ?, content = ?, type = ?, metadata_json = ? WHERE id = ?',
              [
                c['sourcePath'],
                c['lineStart'],
                c['lineEnd'],
                c['content'],
                c['type'],
                jsonEncode(c['metadata']),
                c['id'],
              ],
            );
          }
        }
      } on FormatException {
        /* Deliberate invalid JSON. */
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      db.close();
    }
  }

  Future<FileStat> stat() => file.stat();
  Future<void> setLastModified(DateTime value) => file.setLastModified(value);
  Future<void> delete() async {
    final db = sqlite3.open(file.path);
    try {
      db.execute('DELETE FROM generation_records');
    } finally {
      db.close();
    }
  }
}

GenerationRecord generationRecord(Directory directory) =>
    GenerationRecord(p.join(directory.path, SqliteGeneration.fileName));

Future<Uint8List> generationVectors(Directory directory) async {
  final loaded = await SqliteGeneration.read(directory);
  final record = jsonDecode(loaded.record) as Map;
  final byId = {
    for (final embedding in loaded.embeddings)
      embedding.chunkId: embedding.vector,
  };
  return IndexGeneration.encode([
    for (final chunk in loaded.chunks) byId[chunk.id]!,
  ], (record['vectors'] as Map)['dimension'] as int);
}
