import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knowledge_embeddings/okf_knowledge.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:okf_profile/okf_profile.dart';
import 'package:station/src/knowledge.dart';
import 'package:station/src/mcp_server.dart';
import 'package:test/test.dart';

void main() {
  test('rejects missing and non-directory roots before serving', () async {
    final temp = await Directory.systemTemp.createTemp('station-mcp-root-');
    addTearDown(() => temp.delete(recursive: true));
    final file = await File('${temp.path}/file').writeAsString('fixture');
    for (final root in [file.path, '${temp.path}/missing']) {
      await expectLater(
        StationMcpServer(rootPath: root, knowledge: _Knowledge()).serve(),
        throwsA(isA<FileSystemException>()),
      );
    }
  });
  for (final protocol in [McpProtocol.legacy, McpProtocol.require2026]) {
    group('$protocol', () {
      late McpClient client;
      late IOStreamTransport serverTransport;
      late Future<void> serving;
      late _Knowledge knowledge;
      late String root;
      setUp(() async {
        root = await Directory(
          'test/fixtures/knowledge',
        ).resolveSymbolicLinks();
        knowledge = _Knowledge();
        final incoming = StreamController<List<int>>();
        final outgoing = StreamController<List<int>>();
        serverTransport = IOStreamTransport(
          stream: incoming.stream,
          sink: outgoing.sink,
        );
        serving = StationMcpServer(
          rootPath: root,
          knowledge: knowledge,
        ).serve(transport: serverTransport);
        client = McpClient(
          const Implementation(name: 'station-test', version: '1.0.0'),
          options: McpClientOptions(protocol: protocol),
        );
        await client.connect(
          IOStreamTransport(stream: outgoing.stream, sink: incoming.sink),
        );
      });
      tearDown(() async {
        knowledge.finishIndex?.complete();
        await client.close();
        await serverTransport.close();
        await serving;
      });

      test('discovery is lazy and tools describe their effects', () async {
        final tools = (await client.listTools()).tools;
        expect(
          tools.map((tool) => tool.name),
          unorderedEquals(['validate', 'index', 'search']),
        );
        expect(
          tools.singleWhere((t) => t.name == 'index').annotations?.readOnlyHint,
          false,
        );
        expect(
          tools
              .singleWhere((t) => t.name == 'search')
              .annotations
              ?.readOnlyHint,
          true,
        );
        expect(knowledge.calls, isEmpty);
      });

      test(
        'validation preserves findings and unassessed judgment without inference',
        () async {
          final expected = await const ProfileValidator().validate(root);
          final result = await client.callTool(
            const CallToolRequest(name: 'validate'),
          );
          expect(result.isError, isNot(true));
          expect(_payload(result), {
            ...expected.toJson(),
            'exit_code': expected.exitCode,
          });
          expect(_payload(result)['judgment_rules'], {'state': 'UNASSESSED'});
          expect(knowledge.calls, isEmpty);
        },
      );

      test(
        'index and search use the bound service and search defaults',
        () async {
          final index = await client.callTool(
            const CallToolRequest(name: 'index'),
          );
          expect(_payload(index)['embeddedChunks'], 3);
          final result = await client.callTool(
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'forgotten password'},
            ),
          );
          expect(result.isError, isNot(true));
          expect(_payload(result), {
            'matches': [],
            'context': [],
            'notices': ['fixture notice'],
          });
          await client.callTool(
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'password', 'limit': 2.0},
            ),
          );
          expect(knowledge.calls, [
            'index:$root',
            'search:$root:forgotten password:5',
            'search:$root:password:2',
          ]);
        },
      );

      test(
        'closed schemas reject bad arguments before service calls',
        () async {
          for (final request in [
            const CallToolRequest(
              name: 'index',
              arguments: {'bundle': '/another/root'},
            ),
            const CallToolRequest(
              name: 'validate',
              arguments: {'strict': true},
            ),
            const CallToolRequest(name: 'search', arguments: {}),
            const CallToolRequest(name: 'search', arguments: {'query': '  '}),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'x', 'limit': 0},
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'x', 'limit': 101},
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'x', 'limit': 1.5},
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'x', 'mode': 'dense'},
            ),
          ]) {
            expect(
              (await client.callTool(request)).isError,
              true,
              reason: request.toJson().toString(),
            );
          }
          expect(knowledge.calls, isEmpty);
        },
      );

      test('a stale-index error does not end the session', () async {
        knowledge.failSearch = true;
        final error = await client.callTool(
          const CallToolRequest(
            name: 'search',
            arguments: {'query': 'password'},
          ),
        );
        expect(error.isError, true);
        expect(
          (error.content.single as TextContent).text,
          contains('station index'),
        );
        knowledge.failSearch = false;
        final recovered = await client.callTool(
          const CallToolRequest(
            name: 'search',
            arguments: {'query': 'password'},
          ),
        );
        expect(recovered.isError, isNot(true));
      });

      test(
        'disconnect drains an active operation before completing serve',
        () async {
          knowledge.finishIndex = Completer<void>();
          final call = client.callTool(const CallToolRequest(name: 'index'));
          // Disconnect can reject the pending client request; observe it before closing.
          final observed = call.then<void>((_) {}, onError: (Object _) {});
          await knowledge.indexStarted.future;
          var stopped = false;
          final completion = serving.then((_) => stopped = true);
          await client.close();
          await serverTransport.close();
          await Future<void>.delayed(Duration.zero);
          expect(stopped, false);
          knowledge.finishIndex!.complete();
          knowledge.finishIndex = null;
          await completion;
          await observed;
          expect(knowledge.indexFinished, true);
        },
      );
    });
  }
}

Map<String, Object?> _payload(CallToolResult result) =>
    Map<String, Object?>.from(
      jsonDecode((result.content.single as TextContent).text) as Map,
    );

class _Knowledge extends StationKnowledge {
  _Knowledge() : super(dataDirectory: Directory.systemTemp);
  final calls = <String>[];
  final indexStarted = Completer<void>();
  Completer<void>? finishIndex;
  bool indexFinished = false;
  bool failSearch = false;

  @override
  Future<Map<String, Object?>> index(String bundle) async {
    calls.add('index:$bundle');
    if (!indexStarted.isCompleted) indexStarted.complete();
    await finishIndex?.future;
    indexFinished = true;
    return {'embeddedChunks': 3};
  }

  @override
  Future<KnowledgeSearchResponse> search(
    String bundle,
    String query, {
    int limit = 5,
  }) async {
    calls.add('search:$bundle:$query:$limit');
    if (failSearch) {
      throw const StationException(
        'Index is stale. Run station index <bundle>.',
      );
    }
    return KnowledgeSearchResponse(
      matches: [],
      context: [],
      notices: ['fixture notice'],
    );
  }
}
