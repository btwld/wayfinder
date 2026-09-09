import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knowledge_embeddings/knowledge_embeddings.dart';
import 'package:ollama_dart/ollama_dart.dart' as ollama;
import 'package:test/test.dart';

void main() {
  group('OllamaEmbedder', () {
    test('uses the explicit package default model when omitted', () {
      final embedder = OllamaEmbedder();

      expect(embedder.model, OllamaModel.defaultEmbedding);
      expect(embedder.modelName, 'embeddinggemma');
    });

    test('exposes the recommended Qwen3 code embedding model tag', () {
      expect(OllamaModel.qwen3Embedding06B.value, 'qwen3-embedding:0.6b');
      expect(
        OllamaModel.recommendedCodeEmbedding,
        OllamaModel.qwen3Embedding06B,
      );
    });

    test('exposes known model dimensions before the first request', () {
      expect(OllamaModel.embeddingGemma.knownDimension, 768);
      expect(OllamaModel.nomicEmbedText.knownDimension, 768);
      expect(OllamaModel.qwen3Embedding06B.knownDimension, 1024);
      expect(OllamaModel.custom('custom-embed').knownDimension, isNull);

      expect(OllamaEmbedder().dimension, 768);
      expect(
        OllamaEmbedder(model: OllamaModel.qwen3Embedding06B).dimension,
        1024,
      );
    });

    test('resolves common model aliases to typed Ollama models', () {
      expect(OllamaModel.fromName(''), OllamaModel.defaultEmbedding);
      expect(OllamaModel.fromName('gemma'), OllamaModel.embeddingGemma);
      expect(
        OllamaModel.fromName('embeddinggemma:latest'),
        OllamaModel.embeddingGemma,
      );
      expect(OllamaModel.fromName('nomic'), OllamaModel.nomicEmbedText);
      expect(
        OllamaModel.fromName('nomic-embed-text:latest'),
        OllamaModel.nomicEmbedText,
      );
      expect(OllamaModel.fromName('qwen3'), OllamaModel.qwen3Embedding06B);
      expect(
        OllamaModel.fromName('qwen3-embedding:0.6b'),
        OllamaModel.qwen3Embedding06B,
      );
      expect(OllamaModel.fromName('qwen3-embedding').value, 'qwen3-embedding');
      expect(
        OllamaModel.fromName('custom-code-model').value,
        'custom-code-model',
      );
    });

    test('validates custom model identifiers', () {
      expect(
        OllamaModel.custom(' custom-code-model ').value,
        'custom-code-model',
      );
      expect(() => OllamaModel.custom(''), throwsArgumentError);
      expect(() => OllamaModel.custom('   '), throwsArgumentError);
    });

    test('throws when Ollama is unavailable', () async {
      final embedder = OllamaEmbedder(
        baseUrl: Uri.parse('http://127.0.0.1:65535'),
        model: OllamaModel.embeddingGemma,
        retries: 0,
      );

      await expectLater(
        embedder.generateEmbedding('hello'),
        throwsA(isA<OllamaEmbedderException>()),
      );
      await embedder.dispose();
    });

    test(
      'times out slow model listing when request timeout is configured',
      () async {
        final embedder = OllamaEmbedder(
          model: OllamaModel.embeddingGemma,
          client: _fakeClient(listModelsDelay: const Duration(seconds: 1)),
          requestTimeout: const Duration(milliseconds: 20),
        );

        await expectLater(
          embedder.generateEmbedding('hello'),
          throwsA(
            isA<OllamaEmbedderException>().having(
              (e) => e.message,
              'message',
              contains('Timed out'),
            ),
          ),
        );
        await embedder.dispose();
      },
    );

    test('reports a missing local model', () async {
      final embedder = OllamaEmbedder(
        model: OllamaModel.nomicEmbedText,
        client: _fakeClient(),
      );

      await expectLater(
        embedder.generateEmbedding('hello'),
        throwsA(
          isA<OllamaEmbedderException>().having(
            (e) => e.message,
            'message',
            contains('ollama pull nomic-embed-text'),
          ),
        ),
      );
      await embedder.dispose();
    });

    test('validates known model dimensions against embedding responses', () {
      final embedder = OllamaEmbedder(
        model: OllamaModel.embeddingGemma,
        client: _fakeClient(embedding: const [0.1, 0.2, 0.3]),
      );

      expect(
        embedder.generateEmbedding('hello'),
        throwsA(
          isA<OllamaEmbedderException>()
              .having((e) => e.message, 'message', contains('embeddinggemma'))
              .having((e) => e.message, 'message', contains('expected 768'))
              .having((e) => e.message, 'message', contains('returned 3')),
        ),
      );
    });

    test('learns custom model dimensions from the first embedding', () async {
      final embedder = OllamaEmbedder(
        model: OllamaModel.custom('custom-embed'),
        client: _fakeClient(
          models: const ['custom-embed:latest'],
          embedding: const [0.1, 0.2, 0.3],
        ),
      );

      expect(() => embedder.dimension, throwsStateError);

      final embedding = await embedder.generateEmbedding('hello');

      expect(embedding, const [0.1, 0.2, 0.3]);
      expect(embedder.dimension, 3);
      await embedder.dispose();
    });

    test('embeds a batch of texts in one request', () async {
      final requests = <Map<String, Object?>>[];
      final embedder = OllamaEmbedder(
        model: OllamaModel.custom('custom-embed'),
        client: _fakeClient(
          models: const ['custom-embed:latest'],
          embedding: const [0.1, 0.2, 0.3],
          onEmbedRequest: requests.add,
        ),
      );

      final vectors = await embedder.generateEmbeddings(const [
        'alpha',
        'beta',
      ]);

      expect(vectors, hasLength(2));
      expect(requests, hasLength(1));
      expect(requests.single['input'], const ['alpha', 'beta']);
      await embedder.dispose();
    });

    test('forwards the requested dimensions to the server', () async {
      final requests = <Map<String, Object?>>[];
      final embedder = OllamaEmbedder(
        model: OllamaModel.qwen3Embedding06B,
        dimensions: 768,
        client: _fakeClient(
          models: const ['qwen3-embedding:0.6b'],
          embedding: List<double>.filled(768, 0.1),
          onEmbedRequest: requests.add,
        ),
      );

      expect(embedder.dimension, 768);
      expect(embedder.modelName, 'qwen3-embedding:0.6b@768');

      final embedding = await embedder.generateEmbedding('hello');

      expect(embedding, hasLength(768));
      expect(requests.single['dimensions'], 768);
      await embedder.dispose();
    });

    test('rejects responses that do not match the requested dimensions', () {
      final embedder = OllamaEmbedder(
        model: OllamaModel.custom('custom-embed'),
        dimensions: 4,
        client: _fakeClient(
          models: const ['custom-embed:latest'],
          embedding: const [0.1, 0.2, 0.3],
        ),
      );

      expect(embedder.dimension, 4);
      expect(embedder.modelName, 'custom-embed@4');
      expect(
        embedder.generateEmbedding('hello'),
        throwsA(
          isA<OllamaEmbedderException>().having(
            (e) => e.message,
            'message',
            contains('expected 4'),
          ),
        ),
      );
    });

    test('rejects non-finite embedding response values', () async {
      final embedder = OllamaEmbedder(
        model: OllamaModel.custom('custom-embed'),
        client: _fakeClient(
          models: const ['custom-embed:latest'],
          embeddingJson: '[0.1,1e400,0.3]',
        ),
      );

      await expectLater(
        embedder.generateEmbedding('hello'),
        throwsA(
          isA<OllamaEmbedderException>()
              .having((e) => e.message, 'message', contains('non-finite'))
              .having((e) => e.message, 'message', contains('index 1')),
        ),
      );
      await embedder.dispose();
    });

    test('creates dimension-aware embedders from model descriptors', () {
      final truncated = OllamaEmbedder.fromModelName('embeddinggemma@512');
      expect(truncated.model, OllamaModel.embeddingGemma);
      expect(truncated.dimensions, 512);
      expect(truncated.modelName, 'embeddinggemma@512');

      final tagged = OllamaEmbedder.fromModelName(
        'nomic-embed-text:latest@512',
      );
      expect(tagged.model, OllamaModel.nomicEmbedText);
      expect(tagged.dimensions, 512);
      expect(tagged.modelName, 'nomic-embed-text@512');

      final native = OllamaEmbedder.fromModelName('embeddinggemma@768');
      expect(native.dimensions, 768);
      expect(native.modelName, 'embeddinggemma');

      final custom = OllamaEmbedder.fromModelName('custom-embed@384');
      expect(custom.model.value, 'custom-embed');
      expect(custom.dimensions, 384);
      expect(custom.modelName, 'custom-embed@384');
    });

    test('rejects invalid dimension model descriptors', () {
      expect(
        () => OllamaEmbedder.fromModelName('embeddinggemma@nope'),
        throwsArgumentError,
      );
      expect(
        () => OllamaEmbedder.fromModelName('embeddinggemma@0'),
        throwsArgumentError,
      );
    });

    test('rejects invalid Ollama request configuration', () {
      expect(() => OllamaEmbedder(retries: -1), throwsA(isA<ArgumentError>()));
      expect(
        () => OllamaEmbedder(requestTimeout: Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => OllamaEmbedder(dimensions: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// Builds an Ollama client backed by a fake HTTP transport.
///
/// [models] are the model ids `/api/tags` reports. [embedding] is the vector
/// returned for every input in an `/api/embed` request, and [embeddingJson]
/// overrides it with raw JSON text. [onEmbedRequest] receives the decoded embed
/// request body.
ollama.OllamaClient _fakeClient({
  Duration listModelsDelay = Duration.zero,
  List<String> models = const ['embeddinggemma:latest'],
  List<double> embedding = const [0.1, 0.2, 0.3],
  String? embeddingJson,
  void Function(Map<String, Object?> request)? onEmbedRequest,
}) {
  final httpClient = MockClient((request) async {
    if (request.url.path.endsWith('/api/tags')) {
      if (listModelsDelay > Duration.zero) {
        await Future<void>.delayed(listModelsDelay);
      }
      return http.Response(
        jsonEncode({
          'models': [
            for (final model in models) {'name': model, 'model': model},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }

    if (request.url.path.endsWith('/api/embed')) {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      onEmbedRequest?.call(body);
      final input = body['input'];
      final inputCount = input is List ? input.length : 1;
      // Built as text so a test can return values jsonEncode rejects, such as
      // the out-of-range literal that decodes to infinity.
      final vectorJson = embeddingJson ?? jsonEncode(embedding);
      final vectors = List<String>.filled(inputCount, vectorJson).join(',');
      return http.Response(
        '{"model":${jsonEncode(body['model'])},"embeddings":[$vectors]}',
        200,
        headers: const {'content-type': 'application/json'},
      );
    }

    return http.Response('not found', 404);
  });

  return ollama.OllamaClient(
    config: const ollama.OllamaConfig(
      baseUrl: 'http://127.0.0.1:11434',
      retryPolicy: ollama.RetryPolicy(maxRetries: 0),
    ),
    httpClient: httpClient,
  );
}
