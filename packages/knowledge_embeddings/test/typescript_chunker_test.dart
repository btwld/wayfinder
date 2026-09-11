import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:test/test.dart';

void main() {
  group('TypeScriptChunker', () {
    final chunker = TypeScriptChunker();
    final metadata = ChunkMetadata(
      sourcePath: 'lib/example.ts',
      contentType: 'typescript',
    );

    test('captures classes with decorators and includes methods', () {
      const content = '''
@Injectable()
export class UserService {
  // Loads users from API
  public loadUsers(): Promise<void> {
    return fetch('/users').then(() => undefined);
  }
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      expect(chunks.map((c) => c.type), containsAll(['class', 'method']));
      final methodChunk = chunks.firstWhere(
        (c) => c.metadata['function'] == 'loadUsers',
      );
      expect(methodChunk.content, contains('// Loads users from API'));
      expect(methodChunk.metadata['class'], 'UserService');
    });

    test('captures class property arrow functions and top-level arrows', () {
      const content = '''
export class ArrowExamples {
  public handleSubmit = async (): Promise<void> => {
    console.log('submit');
  };
}

export const buildLabel = (name: string) => {
  return 'Label: ' + name;
};
''';

      final chunks = chunker.chunkContent(content, metadata);

      final propertyMethod = chunks.where(
        (c) => c.metadata['function'] == 'handleSubmit',
      );
      expect(propertyMethod, isNotEmpty);
      expect(propertyMethod.first.type, anyOf('method', 'function'));

      final topLevel = chunks.firstWhere(
        (c) => c.metadata['function'] == 'buildLabel',
      );
      expect(topLevel.type, 'function');
      expect(topLevel.content, contains('Label:'));
    });

    test('captures generic and single-parameter arrow functions', () {
      const content = '''
export const renderSelect = <T,>(props: SelectProps<T>) => {
  return props.options.map((option) => option.label).join(',');
};

const normalizeLabel = value => {
  return String(value).trim().toLowerCase();
};
''';

      final chunks = chunker.chunkContent(content, metadata);

      final genericArrow = chunks.singleWhere(
        (c) => c.metadata['function'] == 'renderSelect',
      );
      final singleParameterArrow = chunks.singleWhere(
        (c) => c.metadata['function'] == 'normalizeLabel',
      );

      expect(genericArrow.type, 'function');
      expect(genericArrow.content, contains('SelectProps<T>'));
      expect(singleParameterArrow.type, 'function');
      expect(singleParameterArrow.content, contains('toLowerCase'));
    });

    test('captures expression-bodied arrow functions', () {
      const content = '''
export const formatPrice = (amount: number): string => amount.toFixed(2);

const userId = user => user.id;
''';

      final chunks = chunker.chunkContent(content, metadata);

      final typedArrow = chunks.singleWhere(
        (c) => c.metadata['function'] == 'formatPrice',
      );
      final singleParameterArrow = chunks.singleWhere(
        (c) => c.metadata['function'] == 'userId',
      );

      expect(typedArrow.type, 'function');
      expect(typedArrow.lineStart, 1);
      expect(typedArrow.lineEnd, 1);
      expect(typedArrow.content, contains('amount.toFixed(2)'));
      expect(singleParameterArrow.type, 'function');
      expect(singleParameterArrow.content, contains('user.id'));
    });

    test('captures expression-bodied class property arrow methods', () {
      const content = '''
export class Labels {
  public format = (value: string): string => value.trim();
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      final method = chunks.singleWhere(
        (c) => c.metadata['function'] == 'format',
      );

      expect(method.type, 'method');
      expect(method.metadata['class'], 'Labels');
      expect(method.lineStart, 2);
      expect(method.lineEnd, 2);
      expect(method.content, contains('value.trim()'));
    });

    test('does not let method bodies affect following method names', () {
      const content = '''
export class SessionController {
  startSession(): void {
    if (this.enabled) {
      this.log('start');
    }
  }

  stopSession(): void {
    this.log('stop');
  }
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      expect(
        chunks.where((c) => c.metadata['function'] == 'startSession'),
        hasLength(1),
      );
      expect(
        chunks.where((c) => c.metadata['function'] == 'stopSession'),
        hasLength(1),
      );
      expect(chunks.where((c) => c.metadata['function'] == 'if'), isEmpty);
    });

    test('uses the declaration start line for multi-line signatures', () {
      const content = '''
export async function createSession(
  userId: string,
  options: SessionOptions,
): Promise<Session> {
  return buildSession(userId, options);
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      final functionChunk = chunks.singleWhere(
        (c) => c.metadata['function'] == 'createSession',
      );
      expect(functionChunk.lineStart, 1);
      expect(functionChunk.content, startsWith('export async function'));
      expect(functionChunk.content, contains('options: SessionOptions'));
    });

    test('captures enum declarations', () {
      const content = '''
export enum OrderStatus {
  Pending = 'pending',
  Paid = 'paid',
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      final enumChunk = chunks.singleWhere(
        (c) => c.metadata['enum'] == 'OrderStatus',
      );
      expect(enumChunk.type, 'enum');
      expect(enumChunk.content, contains("Paid = 'paid'"));
    });

    test('captures semicolon and object type aliases', () {
      const content = '''
export type PaymentMethod = 'card' | 'bank';

export type PaymentPayload = {
  method: PaymentMethod;
  amount: number;
};
''';

      final chunks = chunker.chunkContent(content, metadata);

      final unionAlias = chunks.singleWhere(
        (c) => c.metadata['typeAlias'] == 'PaymentMethod',
      );
      final objectAlias = chunks.singleWhere(
        (c) => c.metadata['typeAlias'] == 'PaymentPayload',
      );
      expect(unionAlias.type, 'type');
      expect(unionAlias.content, contains("'card' | 'bank'"));
      expect(objectAlias.type, 'type');
      expect(objectAlias.content, contains('amount: number'));
    });

    test('captures namespaces and functions inside them', () {
      const content = '''
export namespace Validation {
  export function isEmail(value: string): boolean {
    return value.includes('@');
  }
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      final namespaceChunk = chunks.singleWhere(
        (c) => c.metadata['namespace'] == 'Validation' && c.type == 'namespace',
      );
      final functionChunk = chunks.singleWhere(
        (c) => c.metadata['function'] == 'isEmail',
      );
      expect(namespaceChunk.content, contains('namespace Validation'));
      expect(functionChunk.type, 'function');
      expect(functionChunk.metadata['namespace'], 'Validation');
    });

    test('captures export default functions', () {
      const content = '''
export default async function loadSession(userId: string): Promise<Session> {
  return fetchSession(userId);
}
''';

      final chunks = chunker.chunkContent(content, metadata);

      final functionChunk = chunks.singleWhere(
        (c) => c.metadata['function'] == 'loadSession',
      );
      expect(functionChunk.type, 'function');
      expect(
        functionChunk.content,
        startsWith('export default async function'),
      );
    });

    test('summarizes oversized containers while retaining child chunks', () {
      const content = '''
export class SessionController {
  startSession(): void {
    const refreshToken = 'abc';
    console.log(refreshToken);
  }

  stopSession(): void {
    console.log('stop');
  }
}
''';

      final chunks = TypeScriptChunker(
        maxChunkLength: 90,
      ).chunkContent(content, metadata);

      final classChunk = chunks.singleWhere(
        (chunk) =>
            chunk.type == 'class' &&
            chunk.metadata['class'] == 'SessionController',
      );
      final startMethodChunk = chunks.singleWhere(
        (chunk) => chunk.metadata['function'] == 'startSession',
      );

      expect(classChunk.type, 'class');
      expect(classChunk.metadata['summary'], isTrue);
      expect(classChunk.metadata['truncated'], isTrue);
      expect(classChunk.lineEnd, 1);
      expect(classChunk.content, 'export class SessionController');
      expect(classChunk.content, isNot(contains('refreshToken')));
      expect(classChunk.content, isNot(contains('stopSession')));
      expect(startMethodChunk.content, contains('refreshToken'));
    });

    test('budgets functions by non-whitespace characters', () {
      final content = [
        'export function padded(): void {',
        '        const value = 1;',
        '}',
      ].join('\n');

      final chunker = TypeScriptChunker(maxChunkLength: 42);
      final chunks = chunker.chunkContent(content, metadata);
      final functionChunk = chunks.singleWhere(
        (chunk) => chunk.metadata['function'] == 'padded',
      );

      expect(functionChunk.content, contains('const value = 1'));
      expect(functionChunk.metadata['summary'], isNull);
      expect(_nonWhitespaceLength(functionChunk.content), 42);
      expect(functionChunk.content.length, greaterThan(chunker.maxChunkLength));
    });

    test('rejects invalid chunk budgets', () {
      expect(
        () => TypeScriptChunker(maxChunkLength: 0),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
      expect(
        () => TypeScriptChunker(maxChunkLength: -1),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxChunkLength',
          ),
        ),
      );
    });

    test('falls back to file chunk when no signatures found', () {
      const content = 'const version = 1 as const;';
      final chunks = chunker.chunkContent(content, metadata);
      expect(chunks, hasLength(1));
      expect(chunks.single.type, 'file');
    });
  });
}

int _nonWhitespaceLength(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').length;
}
