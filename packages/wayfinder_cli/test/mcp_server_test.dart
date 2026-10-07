import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/graph.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:wayfinder_cli/src/index_result.dart';
import 'package:wayfinder_cli/src/mcp_server.dart';
import 'package:wayfinder_cli/src/profile_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('rejects missing and non-directory roots before serving', () async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-mcp-root-');
    addTearDown(() => temp.delete(recursive: true));
    final file = await File('${temp.path}/file').writeAsString('fixture');
    for (final root in [file.path, '${temp.path}/missing']) {
      await expectLater(
        WayfinderMcpServer(rootPath: root, knowledge: _Knowledge()).serve(),
        throwsA(isA<FileSystemException>()),
      );
    }
  });
  test(
    'read-only MCP validate uses the same locked 2026.3 binding as CLI',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'wayfinder-mcp-profile-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final source = await Directory(p.join(temp.path, 'source')).create();
      final project = await Directory(p.join(temp.path, 'project')).create();
      final root = await Directory(p.join(project.path, 'knowledge')).create();
      final fixture = Directory(
        '../../packages/wayfinder/test/fixtures/configured-project/knowledge',
      );
      await for (final entity in fixture.list()) {
        if (entity is File) {
          await entity.copy(p.join(root.path, p.basename(entity.path)));
        }
      }
      await Directory(p.join(source.path, 'profile')).create();
      await File(
        '../../profile/wayfinder-profile.json',
      ).copy(p.join(source.path, 'profile', 'wayfinder-profile.json'));
      Future<void> git(List<String> arguments) async {
        final result = await Process.run(
          'git',
          arguments,
          workingDirectory: source.path,
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }

      await git(['init', '-q']);
      await git(['config', 'user.email', 'test@example.test']);
      await git(['config', 'user.name', 'Wayfinder Test']);
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'Profile']);
      await git(['tag', 'v2026.3']);
      await File(p.join(project.path, 'wayfinder.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'profiles': {
            'bitwild_profile': {
              'source': {
                'git': source.path,
                'ref': 'v2026.3',
                'path': 'profile',
              },
              'applies_to': ['knowledge'],
              'actors': {
                'process:fixture': {'name': 'Fixture process'},
              },
              'tags': [
                {'name': 'governance', 'description': 'Governance topic'},
              ],
            },
          },
        }),
      );
      final resolver = WayfinderProfileResolver(
        dataDirectory: Directory(p.join(temp.path, 'data')),
      );
      await resolver.resolve(project.path);
      final lock = File(p.join(project.path, 'wayfinder.lock'));
      final lockedBytes = await lock.readAsBytes();
      final incoming = StreamController<List<int>>();
      final outgoing = StreamController<List<int>>();
      final transport = IOStreamTransport(
        stream: incoming.stream,
        sink: outgoing.sink,
      );
      final serving = WayfinderMcpServer(
        rootPath: root.path,
        knowledge: _Knowledge(),
        profileResolver: resolver,
      ).serve(transport: transport);
      final client = McpClient(
        const Implementation(name: 'configured-test', version: '1.0.0'),
        options: const McpClientOptions(protocol: McpProtocol.legacy),
      );
      try {
        await client.connect(
          IOStreamTransport(stream: outgoing.stream, sink: incoming.sink),
        );
        final result = await client.callTool(
          const CallToolRequest(name: 'validate'),
        );
        final expected = await validateWithProfileSources(
          root.path,
          resolver: resolver,
        );
        expect(expected.profileRelease, '2026.3');
        expect(expected.profileState, ProfileState.pass);
        expect(_payload(result), {
          ...expected.toJson(),
          'exit_code': expected.exitCode,
        });
        final cliOutput = <String>[];
        final cli = WayfinderCli(
          out: cliOutput.add,
          err: (_) {},
          notices: false,
          profileResolver: () => resolver,
        );
        expect(await cli.run(['validate', root.path, '--output=json']), 0);
        final cliResult = jsonDecode(cliOutput.single) as Map<String, dynamic>;
        expect(_payload(result), {...cliResult, 'exit_code': 0});

        final configFile = File(p.join(project.path, 'wayfinder.json'));
        final config =
            jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
        (((config['profiles'] as Map)['bitwild_profile']['tags']) as List).add({
          'name': 'new-topic',
          'description': 'A new project topic',
        });
        await configFile.writeAsString(jsonEncode(config));
        cliOutput.clear();
        expect(await cli.run(['validate', root.path, '--output=json']), 2);
        final staleCli = jsonDecode(cliOutput.single) as Map<String, dynamic>;
        expect((staleCli['okf'] as Map)['state'], 'PASS');
        expect((staleCli['profile'] as Map)['state'], 'UNSUPPORTED');
        final staleMcp = await client.callTool(
          const CallToolRequest(name: 'validate'),
        );
        expect(_payload(staleMcp), {...staleCli, 'exit_code': 2});
        expect(await lock.readAsBytes(), lockedBytes);
      } finally {
        await client.close();
        await transport.close();
        await serving;
      }
    },
  );
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
        serving = WayfinderMcpServer(
          rootPath: root,
          knowledge: knowledge,
        ).serve(transport: serverTransport);
        client = McpClient(
          const Implementation(name: 'wayfinder-test', version: '1.0.0'),
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
          unorderedEquals(['validate', 'index', 'search', 'graph']),
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
        expect(
          tools.singleWhere((t) => t.name == 'graph').annotations?.readOnlyHint,
          true,
        );
        final schema = tools
            .singleWhere((t) => t.name == 'search')
            .inputSchema
            .toJson();
        expect(schema['type'], 'object');
        expect(schema['additionalProperties'], false);
        expect(schema['required'], ['query']);
        final properties = schema['properties'] as Map;
        expect(properties['query'], containsPair('pattern', r'[^\s\u0085]'));
        expect(
          properties['limit'],
          allOf(
            containsPair('type', 'integer'),
            containsPair('minimum', 1),
            containsPair('maximum', 100),
            containsPair('default', 5),
          ),
        );
        expect(knowledge.calls, isEmpty);
        final graphSchema = tools
            .singleWhere((t) => t.name == 'graph')
            .inputSchema
            .toJson();
        expect(graphSchema['type'], 'object');
        expect(graphSchema['additionalProperties'], false);
        expect(graphSchema['required'], isNull);
        final graphProperties = graphSchema['properties'] as Map;
        expect(
          graphProperties['types'],
          allOf(
            containsPair('type', 'array'),
            containsPair('uniqueItems', true),
          ),
        );
        expect(
          graphProperties['resolutions'],
          containsPair(
            'items',
            containsPair('enum', wayfinderGraphResolutions()),
          ),
        );
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

      test('graph projects the ordinary OKF JSON without retrieval', () async {
        final loaded = await const OkfBundleLoader().inspect(root);
        expect(loaded.hasFindings, isFalse);
        final expected = OkfGraph.fromBundle(loaded.bundle);
        final result = await client.callTool(
          const CallToolRequest(name: 'graph'),
        );
        expect(result.isError, isNot(true));
        expect(_payload(result), {
          ...expected.toJson(),
          'field_edges': <Object?>[],
        });
        final filtered = await client.callTool(
          const CallToolRequest(
            name: 'graph',
            arguments: {
              'types': ['reference'],
            },
          ),
        );
        expect(_payload(filtered), {
          ...OkfGraph.fromBundle(
            loaded.bundle,
            query: OkfGraphQuery(conceptTypes: ['reference']),
          ).toJson(),
          'field_edges': <Object?>[],
        });
        expect(knowledge.calls, isEmpty);
      });

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
            const CallToolRequest(name: 'search', arguments: {'query': ''}),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': '\u0085'},
            ),
            const CallToolRequest(name: 'search', arguments: {'query': null}),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'x', 'limit': null},
            ),
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
            const CallToolRequest(name: 'graph', arguments: {'mode': 'dense'}),
            const CallToolRequest(name: 'graph', arguments: {'types': null}),
            const CallToolRequest(
              name: 'graph',
              arguments: {
                'resolutions': ['nope'],
              },
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

      test('index warnings match CLI JSON in one text block', () async {
        knowledge.warnings = const [
          KnowledgeInputDiagnostic(
            code: 'embedding_context_omitted',
            sourcePath: 'guide.md',
            lineStart: 5,
            lineEnd: 12,
            affectedChunks: 1,
          ),
        ];
        final result = await client.callTool(
          const CallToolRequest(name: 'index'),
        );
        expect(result.isError, isNot(true));
        expect(result.content, hasLength(1));
        final output = <String>[];
        final errors = <String>[];
        final cli = WayfinderCli(
          out: output.add,
          err: errors.add,
          knowledge: () => knowledge,
        );
        expect(await cli.run(['index', root, '--output=json']), 0);
        expect(_payload(result), jsonDecode(output.single));
        expect(
          _payload(result)['warnings'],
          knowledge.warnings.map((d) => d.toJson()).toList(),
        );
        expect(errors, isEmpty);
      });

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
          contains('wayfinder index'),
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

  test('graph load findings are a tool error', () async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-mcp-graph-');
    addTearDown(() => temp.delete(recursive: true));
    await File('${temp.path}/broken.md').writeAsBytes(const [0xff, 0xfe]);
    final incoming = StreamController<List<int>>();
    final outgoing = StreamController<List<int>>();
    final serverTransport = IOStreamTransport(
      stream: incoming.stream,
      sink: outgoing.sink,
    );
    final serving = WayfinderMcpServer(
      rootPath: temp.path,
      knowledge: _Knowledge(),
    ).serve(transport: serverTransport);
    final client = McpClient(
      const Implementation(name: 'wayfinder-test', version: '1.0.0'),
    );
    await client.connect(
      IOStreamTransport(stream: outgoing.stream, sink: incoming.sink),
    );
    addTearDown(() async {
      await client.close();
      await serverTransport.close();
      await serving;
    });
    final result = await client.callTool(const CallToolRequest(name: 'graph'));
    expect(result.isError, true);
    expect(
      (result.content.single as TextContent).text,
      contains('okf/invalid-utf8'),
    );
  });
}

Map<String, Object?> _payload(CallToolResult result) =>
    Map<String, Object?>.from(
      jsonDecode((result.content.single as TextContent).text) as Map,
    );

class _Knowledge extends WayfinderKnowledge {
  _Knowledge() : super(dataDirectory: Directory.systemTemp);
  final calls = <String>[];
  final indexStarted = Completer<void>();
  Completer<void>? finishIndex;
  bool indexFinished = false;
  bool failSearch = false;
  List<KnowledgeInputDiagnostic> warnings = const [];

  @override
  Future<WayfinderIndexResult> index(
    String bundle, {
    bool force = false,
  }) async {
    calls.add('index:$bundle');
    if (!indexStarted.isCompleted) indexStarted.complete();
    await finishIndex?.future;
    indexFinished = true;
    return WayfinderIndexResult(
      bundle: bundle,
      index: 'fixture-index',
      warnings: warnings,
      embeddedChunks: 3,
      removedChunks: 0,
      writtenChunks: 3,
      elapsedMs: 0,
    );
  }

  @override
  Future<KnowledgeSearchResponse> search(
    String bundle,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) async {
    calls.add('search:$bundle:$query:$limit');
    if (failSearch) {
      throw const WayfinderException(
        'Index is stale. Run wayfinder index <bundle>.',
      );
    }
    return KnowledgeSearchResponse(
      matches: [],
      context: [],
      notices: ['fixture notice'],
    );
  }
}
