import 'dart:convert';

import 'package:test/test.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';

void main() {
  group('ChunkMetadata', () {
    test('treats additional metadata as part of equality', () {
      final first = ChunkMetadata(
        sourcePath: 'lib/auth_service.dart',
        contentType: 'dart',
        additionalMetadata: const {'package': 'auth'},
      );
      final second = ChunkMetadata(
        sourcePath: 'lib/auth_service.dart',
        contentType: 'dart',
        additionalMetadata: const {'package': 'billing'},
      );

      expect(first, isNot(equals(second)));
    });

    test(
      'keeps additional metadata immutable and round-trips through maps',
      () {
        final metadata = ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: 'dart',
          additionalMetadata: const {'package': 'auth', 'owner': 'platform'},
        );

        expect(
          () => metadata.additionalMetadata['package'] = 'billing',
          throwsA(isA<UnsupportedError>()),
        );
        expect(ChunkMetadata.fromMap(metadata.toMap()), metadata);
      },
    );

    test('toMap returns a detached mutable additional metadata snapshot', () {
      final metadata = ChunkMetadata(
        sourcePath: 'lib/auth_service.dart',
        contentType: 'dart',
        additionalMetadata: const {'package': 'auth', 'owner': 'platform'},
      );

      final serialized = metadata.toMap();
      final serializedAdditionalMetadata =
          serialized['additionalMetadata']! as Map<String, Object?>;

      serializedAdditionalMetadata['package'] = 'billing';

      expect(serializedAdditionalMetadata['package'], 'billing');
      expect(metadata.additionalMetadata['package'], 'auth');
    });

    test(
      'keeps nested additional metadata collections immutable and detached',
      () {
        final tags = ['auth', 'token'];
        final details = <String, Object?>{'owner': 'platform', 'tags': tags};
        final metadata = ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: 'dart',
          additionalMetadata: {'details': details},
        );

        details['owner'] = 'security';
        tags.add('refresh');

        final storedDetails =
            metadata.additionalMetadata['details']! as Map<String, Object?>;
        final storedTags = storedDetails['tags']! as List<Object?>;

        expect(storedDetails['owner'], 'platform');
        expect(storedTags, ['auth', 'token']);
        expect(
          () => storedDetails['owner'] = 'security',
          throwsUnsupportedError,
        );
        expect(() => storedTags.add('refresh'), throwsUnsupportedError);
      },
    );

    test('toMap detaches nested additional metadata collection snapshots', () {
      final metadata = ChunkMetadata(
        sourcePath: 'lib/auth_service.dart',
        contentType: 'dart',
        additionalMetadata: {
          'details': {
            'owner': 'platform',
            'tags': ['auth', 'token'],
          },
        },
      );

      final serialized = metadata.toMap();
      final serializedAdditionalMetadata =
          serialized['additionalMetadata']! as Map<String, Object?>;
      final serializedDetails =
          serializedAdditionalMetadata['details']! as Map<String, Object?>;
      final serializedTags = serializedDetails['tags']! as List<Object?>;

      serializedDetails['owner'] = 'security';
      serializedTags.add('refresh');

      final storedDetails =
          metadata.additionalMetadata['details']! as Map<String, Object?>;
      final storedTags = storedDetails['tags']! as List<Object?>;
      expect(serializedDetails['owner'], 'security');
      expect(serializedTags, ['auth', 'token', 'refresh']);
      expect(storedDetails['owner'], 'platform');
      expect(storedTags, ['auth', 'token']);
    });

    test(
      'normalizes set additional metadata to immutable JSON-encodable lists',
      () {
        final metadata = ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: 'dart',
          additionalMetadata: {
            'tags': {'auth', 'token'},
            'details': {
              'flags': {'stable', 'indexed'},
            },
          },
        );

        final storedTags =
            metadata.additionalMetadata['tags']! as List<Object?>;
        final storedDetails =
            metadata.additionalMetadata['details']! as Map<String, Object?>;
        final storedFlags = storedDetails['flags']! as List<Object?>;

        expect(storedTags, ['auth', 'token']);
        expect(storedFlags, ['stable', 'indexed']);
        expect(() => storedTags.add('refresh'), throwsUnsupportedError);
        expect(() => storedFlags.add('public'), throwsUnsupportedError);
        expect(jsonEncode(metadata.additionalMetadata), isA<String>());
        expect(jsonEncode(metadata.toMap()), isA<String>());
      },
    );

    test(
      'rejects additional metadata with non-string keys with a format error',
      () {
        expect(
          () => ChunkMetadata.fromMap({
            'sourcePath': 'lib/auth_service.dart',
            'contentType': 'dart',
            'additionalMetadata': {1: 'not-a-string-key'},
          }),
          throwsFormatException,
        );
      },
    );

    test('rejects non-json-encodable additional metadata values', () {
      expect(
        () => ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: 'dart',
          additionalMetadata: {'createdAt': DateTime.utc(2026)},
        ),
        throwsArgumentError,
      );
      expect(
        () => ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: 'dart',
          additionalMetadata: const {'score': double.nan},
        ),
        throwsArgumentError,
      );
      expect(
        () => ChunkMetadata.fromMap({
          'sourcePath': 'lib/auth_service.dart',
          'contentType': 'dart',
          'additionalMetadata': {'createdAt': DateTime.utc(2026)},
        }),
        throwsFormatException,
      );
      expect(
        () => ChunkMetadata.fromMap({
          'sourcePath': 'lib/auth_service.dart',
          'contentType': 'dart',
          'additionalMetadata': const {'score': double.infinity},
        }),
        throwsFormatException,
      );
    });

    test('rejects blank identity fields and metadata keys', () {
      expect(
        () => ChunkMetadata(sourcePath: '', contentType: 'dart'),
        throwsArgumentError,
      );
      expect(
        () => ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        () => ChunkMetadata(
          sourcePath: 'lib/auth_service.dart',
          contentType: 'dart',
          additionalMetadata: const {'': 'auth'},
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank serialized identity fields with a format error', () {
      expect(
        () => ChunkMetadata.fromMap({
          'sourcePath': '',
          'contentType': 'dart',
          'additionalMetadata': const <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => ChunkMetadata.fromMap({
          'sourcePath': 'lib/auth_service.dart',
          'contentType': ' ',
          'additionalMetadata': const <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => ChunkMetadata.fromMap({
          'sourcePath': 'lib/auth_service.dart',
          'contentType': 'dart',
          'additionalMetadata': const {'': 'auth'},
        }),
        throwsFormatException,
      );
    });
  });
}
