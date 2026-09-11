import 'dart:convert';

import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('Chunk', () {
    test('treats metadata as part of equality', () {
      final first = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: const {'language': 'dart'},
      );
      final second = Chunk(
        id: 'chunk-1',
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: const {'language': 'typescript'},
      );

      expect(first, isNot(equals(second)));
    });

    test('keeps metadata immutable and round-trips through maps', () {
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: const {'language': 'dart', 'name': 'AuthService'},
      );

      expect(
        () => chunk.metadata['language'] = 'typescript',
        throwsA(isA<UnsupportedError>()),
      );
      expect(Chunk.fromMap(chunk.toMap()), chunk);
    });

    test('toMap returns a detached mutable metadata snapshot', () {
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: const {'language': 'dart', 'name': 'AuthService'},
      );

      final serialized = chunk.toMap();
      final serializedMetadata =
          serialized['metadata']! as Map<String, Object?>;

      serializedMetadata['language'] = 'typescript';

      expect(serializedMetadata['language'], 'typescript');
      expect(chunk.metadata['language'], 'dart');
    });

    test('keeps nested metadata collections immutable and detached', () {
      final tags = ['auth', 'token'];
      final details = <String, Object?>{'owner': 'platform', 'tags': tags};
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: {'details': details},
      );

      details['owner'] = 'security';
      tags.add('refresh');

      final storedDetails = chunk.metadata['details']! as Map<String, Object?>;
      final storedTags = storedDetails['tags']! as List<Object?>;

      expect(storedDetails['owner'], 'platform');
      expect(storedTags, ['auth', 'token']);
      expect(() => storedDetails['owner'] = 'security', throwsUnsupportedError);
      expect(() => storedTags.add('refresh'), throwsUnsupportedError);
    });

    test('toMap detaches nested metadata collection snapshots', () {
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: {
          'details': {
            'owner': 'platform',
            'tags': ['auth', 'token'],
          },
        },
      );

      final serialized = chunk.toMap();
      final serializedMetadata =
          serialized['metadata']! as Map<String, Object?>;
      final serializedDetails =
          serializedMetadata['details']! as Map<String, Object?>;
      final serializedTags = serializedDetails['tags']! as List<Object?>;

      serializedDetails['owner'] = 'security';
      serializedTags.add('refresh');

      final storedDetails = chunk.metadata['details']! as Map<String, Object?>;
      final storedTags = storedDetails['tags']! as List<Object?>;
      expect(serializedDetails['owner'], 'security');
      expect(serializedTags, ['auth', 'token', 'refresh']);
      expect(storedDetails['owner'], 'platform');
      expect(storedTags, ['auth', 'token']);
    });

    test('normalizes set metadata to immutable JSON-encodable lists', () {
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
        metadata: {
          'tags': {'auth', 'token'},
          'details': {
            'flags': {'stable', 'indexed'},
          },
        },
      );

      final storedTags = chunk.metadata['tags']! as List<Object?>;
      final storedDetails = chunk.metadata['details']! as Map<String, Object?>;
      final storedFlags = storedDetails['flags']! as List<Object?>;

      expect(storedTags, ['auth', 'token']);
      expect(storedFlags, ['stable', 'indexed']);
      expect(() => storedTags.add('refresh'), throwsUnsupportedError);
      expect(() => storedFlags.add('public'), throwsUnsupportedError);
      expect(jsonEncode(chunk.metadata), isA<String>());
      expect(jsonEncode(chunk.toMap()), isA<String>());
    });

    test('copyWith recomputes ids when stable identity fields change', () {
      final chunk = Chunk(
        sourcePath: 'lib/auth_service.dart',
        lineStart: 1,
        lineEnd: 10,
        content: 'class AuthService {}',
        type: 'class',
      );

      final renamed = chunk.copyWith(content: 'class SessionService {}');
      final metadataOnly = chunk.copyWith(metadata: const {'language': 'dart'});
      final explicitId = chunk.copyWith(
        id: 'explicit-id',
        content: 'class UserService {}',
      );

      expect(renamed.id, isNot(chunk.id));
      expect(
        renamed.id,
        deterministicChunkId(
          sourcePath: renamed.sourcePath,
          lineStart: renamed.lineStart,
          lineEnd: renamed.lineEnd,
          content: renamed.content,
          type: renamed.type,
        ),
      );
      expect(metadataOnly.id, chunk.id);
      expect(explicitId.id, 'explicit-id');
    });

    test('rejects invalid source line ranges', () {
      expect(
        () => Chunk(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 0,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
        ),
        throwsArgumentError,
      );
      expect(
        () => Chunk(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 10,
          lineEnd: 9,
          content: 'class AuthService {}',
          type: 'class',
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid line ranges for deterministic ids', () {
      expect(
        () => deterministicChunkId(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 0,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
        ),
        throwsArgumentError,
      );
      expect(
        () => deterministicChunkId(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 10,
          lineEnd: 9,
          content: 'class AuthService {}',
          type: 'class',
        ),
        throwsArgumentError,
      );
    });

    test(
      'rejects invalid serialized source line ranges with a format error',
      () {
        expect(
          () => Chunk.fromMap({
            'id': 'chunk-1',
            'sourcePath': 'lib/auth_service.dart',
            'lineStart': 0,
            'lineEnd': 10,
            'content': 'class AuthService {}',
            'type': 'class',
            'metadata': const <String, Object?>{},
          }),
          throwsFormatException,
        );
        expect(
          () => Chunk.fromMap({
            'id': 'chunk-1',
            'sourcePath': 'lib/auth_service.dart',
            'lineStart': 2,
            'lineEnd': 1,
            'content': 'class AuthService {}',
            'type': 'class',
            'metadata': const <String, Object?>{},
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects blank identity fields and metadata keys', () {
      expect(
        () => Chunk(
          id: '',
          sourcePath: 'lib/auth_service.dart',
          lineStart: 1,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
        ),
        throwsArgumentError,
      );
      expect(
        () => Chunk(
          sourcePath: ' ',
          lineStart: 1,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
        ),
        throwsArgumentError,
      );
      expect(
        () => Chunk(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 1,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => Chunk(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 1,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
          metadata: const {'': 'dart'},
        ),
        throwsArgumentError,
      );
    });

    test('rejects metadata with non-string keys with a format error', () {
      expect(
        () => Chunk.fromMap({
          'id': 'chunk-1',
          'sourcePath': 'lib/auth_service.dart',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': 'class',
          'metadata': {1: 'not-a-string-key'},
        }),
        throwsFormatException,
      );
    });

    test('rejects non-json-encodable metadata values', () {
      expect(
        () => Chunk(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 1,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
          metadata: {'createdAt': DateTime.utc(2026)},
        ),
        throwsArgumentError,
      );
      expect(
        () => Chunk(
          sourcePath: 'lib/auth_service.dart',
          lineStart: 1,
          lineEnd: 10,
          content: 'class AuthService {}',
          type: 'class',
          metadata: const {'score': double.nan},
        ),
        throwsArgumentError,
      );
      expect(
        () => Chunk.fromMap({
          'id': 'chunk-1',
          'sourcePath': 'lib/auth_service.dart',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': 'class',
          'metadata': {'createdAt': DateTime.utc(2026)},
        }),
        throwsFormatException,
      );
      expect(
        () => Chunk.fromMap({
          'id': 'chunk-1',
          'sourcePath': 'lib/auth_service.dart',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': 'class',
          'metadata': const {'score': double.infinity},
        }),
        throwsFormatException,
      );
    });

    test('rejects blank serialized identity fields with a format error', () {
      expect(
        () => Chunk.fromMap({
          'id': '',
          'sourcePath': 'lib/auth_service.dart',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': 'class',
          'metadata': const <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => Chunk.fromMap({
          'id': 'chunk-1',
          'sourcePath': '',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': 'class',
          'metadata': const <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => Chunk.fromMap({
          'id': 'chunk-1',
          'sourcePath': 'lib/auth_service.dart',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': ' ',
          'metadata': const <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => Chunk.fromMap({
          'id': 'chunk-1',
          'sourcePath': 'lib/auth_service.dart',
          'lineStart': 1,
          'lineEnd': 10,
          'content': 'class AuthService {}',
          'type': 'class',
          'metadata': const {'': 'dart'},
        }),
        throwsFormatException,
      );
    });
  });
}
