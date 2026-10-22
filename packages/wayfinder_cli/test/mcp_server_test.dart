import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:okf/okf_io.dart';
import 'package:path/path.dart' as p;
import 'package:wayfinder_embeddings/okf_knowledge.dart';
import 'package:wayfinder_embeddings/wayfinder_embeddings.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder/wayfinder.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/knowledge.dart';
import 'package:wayfinder_cli/src/index_result.dart';
import 'package:wayfinder_cli/src/mcp_server.dart';
import 'package:wayfinder_cli/src/search_output.dart';
import 'package:test/test.dart';

import 'support.dart';

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
      await copyBitwildPackage(source.path);
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
            'bitwild-profile': {
              'source': {
                'git': source.path,
                'ref': 'v2026.3',
                'path': 'profiles/bitwild',
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
        (((config['profiles'] as Map)['bitwild-profile']['tags']) as List).add({
          'name': 'new-topic',
          'description': 'A new project topic',
        });
        await configFile.writeAsString(jsonEncode(config));
        cliOutput.clear();
        expect(await cli.run(['validate', root.path, '--output=json']), 2);
        final staleCli = jsonDecode(cliOutput.single) as Map<String, dynamic>;
        expect((staleCli['okf'] as Map)['state'], 'PASS');
        expect((staleCli['profile'] as Map)['state'], 'NOT ASSESSED');
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
        expect(knowledge.disposed, isTrue);
      });

      test('MCP rejects every supplied retired mode', () async {
        for (final mode in ['dense', 'bm25', 'hybrid']) {
          final result = await client.callTool(
            CallToolRequest(
              name: 'search',
              arguments: {'query': 'password', 'mode': mode},
            ),
          );
          expect(result.isError, isTrue);
        }
        expect(knowledge.calls, isEmpty);
        final result = await client.callTool(
          const CallToolRequest(
            name: 'search',
            arguments: {'query': 'password'},
          ),
        );
        expect(result.isError, isNot(true));
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

      test('validation preserves findings, diagnostics and the gate without '
          'inference', () async {
        final expected = await validateWithProfileSources(
          root,
          resolver: _defaultResolver(),
        );
        final result = await client.callTool(
          const CallToolRequest(name: 'validate'),
        );
        expect(result.isError, isNot(true));
        expect(_payload(result), {
          ...expected.toJson(),
          'exit_code': expected.exitCode,
        });
        expect(_payload(result), contains('diagnostics'));
        expect(_payload(result)['gate'], {'state': expected.gate.wireValue});
        expect(knowledge.calls, isEmpty);
      });

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
          expect(
            (result.content.single as TextContent).text,
            'Notice: fixture notice\nNo passages found.',
          );
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
              name: 'search',
              arguments: {'query': 'caching', 'reranker': 'bge-v2-m3-metal'},
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching', 'reranker': 'qwen3-0.6b-metal'},
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching', 'researchContext': 'dense'},
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {
                'query': 'caching',
                'researchContext': 'dense-sections',
              },
            ),
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching', 'researchTrace': true},
            ),
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
              arguments: {'query': 'x', 'mode': 'unknown'},
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

    group('$protocol project bundles', () {
      late Directory project;
      late _Knowledge knowledge;
      late McpClient client;
      late IOStreamTransport serverTransport;
      late Future<void> serving;
      const paths = ['.wayfinder/bundles/shared-kit', 'knowledge'];
      Future<void> configure(List<String> bundles) =>
          File(p.join(project.path, 'wayfinder.json')).writeAsString(
            jsonEncode({
              'version': 1,
              'profiles': {
                'test-profile': {
                  'source': {
                    'git': 'https://example.test/profile',
                    'ref': 'main',
                    'path': 'profile',
                  },
                  'applies_to': bundles,
                },
              },
            }),
          );
      setUp(() async {
        project = await Directory.systemTemp.createTemp(
          'wayfinder-mcp-project-',
        );
        await Directory(p.join(project.path, '.git')).create();
        for (final path in [...paths, 'unconfigured']) {
          final bundle = await Directory(
            p.join(project.path, path),
          ).create(recursive: true);
          await for (final file in Directory(
            'test/fixtures/knowledge',
          ).list()) {
            if (file is File) {
              await file.copy(p.join(bundle.path, p.basename(file.path)));
            }
          }
        }
        await configure(paths);
        knowledge = _Knowledge();
        final incoming = StreamController<List<int>>();
        final outgoing = StreamController<List<int>>();
        serverTransport = IOStreamTransport(
          stream: incoming.stream,
          sink: outgoing.sink,
        );
        serving = WayfinderMcpServer(
          workingDirectory: project,
          knowledge: knowledge,
        ).serve(transport: serverTransport);
        client = McpClient(
          const Implementation(name: 'project-test', version: '1.0.0'),
          options: McpClientOptions(protocol: protocol),
        );
        await client.connect(
          IOStreamTransport(stream: outgoing.stream, sink: incoming.sink),
        );
      });
      tearDown(() async {
        await client.close();
        await serverTransport.close();
        await serving;
        await project.delete(recursive: true);
      });

      test(
        'search defaults to all configured bundles with CLI-equivalent ranking and citations',
        () async {
          await client.listTools();
          expect(knowledge.calls, isEmpty);
          final result = await client.callTool(
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching', 'limit': 2},
            ),
          );
          expect(result.isError, isNot(true));
          final text = (result.content.single as TextContent).text;
          expect(text, contains('## Matches'));
          expect(
            text,
            contains('### knowledge/guide.md:1-2 [knowledge; stable; match]'),
          );
          expect(
            text,
            contains(
              '### ${paths.first}/guide.md:1-2 [shared-kit; stable; match]',
            ),
          );
          expect(knowledge.calls, hasLength(1));
          expect(knowledge.calls.single, startsWith('searchBundles:'));
          expect(knowledge.calls.single, isNot(contains('unconfigured')));
          final output = <String>[];
          final cli = WayfinderCli(
            out: output.add,
            knowledge: () => knowledge,
            workingDirectory: project,
            notices: false,
          );
          expect(await cli.run(['search', 'caching', '--limit=2']), 0);
          expect(text, output.single);
          final limited =
              ((await client.callTool(
                        const CallToolRequest(
                          name: 'search',
                          arguments: {'query': 'caching', 'limit': 1},
                        ),
                      )).content.single
                      as TextContent)
                  .text;
          expect(
            limited,
            contains('### knowledge/guide.md:1-2 [knowledge; stable; match]'),
          );
          expect(limited, isNot(contains('shared-kit')));
        },
      );

      test(
        'index refreshes every configured bundle with CLI-equivalent JSON',
        () async {
          final result = await client.callTool(
            const CallToolRequest(name: 'index'),
          );
          expect(result.isError, isNot(true));
          final bundles = _payload(result)['bundles'] as List;
          expect(bundles.map((bundle) => bundle['path']), paths);
          expect(knowledge.calls.map((call) => p.basename(call)), [
            'shared-kit',
            'knowledge',
          ]);
          final output = <String>[];
          final cli = WayfinderCli(
            out: output.add,
            knowledge: () => knowledge,
            workingDirectory: project,
            notices: false,
          );
          expect(await cli.run(['index', '--output=json']), 0);
          expect(_payload(result), jsonDecode(output.single));
          expect(
            await File(p.join(project.path, 'wayfinder.lock')).exists(),
            isFalse,
          );
        },
      );

      test('validation and graph keep independent bundle reports', () async {
        final validation = _payload(
          await client.callTool(const CallToolRequest(name: 'validate')),
        );
        final graph = _payload(
          await client.callTool(const CallToolRequest(name: 'graph')),
        );
        for (var i = 0; i < paths.length; i++) {
          final root = await Directory(
            p.join(project.path, paths[i]),
          ).resolveSymbolicLinks();
          final expected = await validateWithProfileSources(
            root,
            resolver: _defaultResolver(),
          );
          expect((validation['bundles'] as List)[i], {
            'name': p.basename(paths[i]),
            'path': paths[i],
            ...expected.toJson(),
            'exit_code': expected.exitCode,
          });
          expect((graph['bundles'] as List)[i], {
            'name': p.basename(paths[i]),
            'path': paths[i],
            ...(await projectWayfinderGraph(root)).toJson(),
          });
        }
        expect(knowledge.calls, isEmpty);
        expect(
          await File(p.join(project.path, 'wayfinder.lock')).exists(),
          isFalse,
        );
      });

      test(
        'graph load failures identify the bundle and leave the session usable',
        () async {
          final broken = File(p.join(project.path, paths.first, 'broken.md'));
          await broken.writeAsBytes(const [0xff, 0xfe]);
          final result = await client.callTool(
            const CallToolRequest(name: 'graph'),
          );
          expect(result.isError, true);
          final message = (result.content.single as TextContent).text;
          expect(message, startsWith('${paths.first}: '));
          expect(message, contains('broken.md'));
          expect(message, contains('okf/invalid-utf8'));
          await broken.delete();
          expect(
            (await client.callTool(
              const CallToolRequest(name: 'graph'),
            )).isError,
            isNot(true),
          );
          expect(knowledge.calls, isEmpty);
        },
      );

      test(
        'missing and stale bundles fail search without partial output or implicit indexing',
        () async {
          final missing = Directory(p.join(project.path, paths.first));
          await missing.delete(recursive: true);
          final absent = await client.callTool(
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching'},
            ),
          );
          expect(absent.isError, true);
          expect(
            (absent.content.single as TextContent).text,
            contains('does not exist'),
          );
          expect(knowledge.calls, isEmpty);
          await missing.create(recursive: true);
          knowledge.failSearch = true;
          final stale = await client.callTool(
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching'},
            ),
          );
          expect(stale.isError, true);
          expect(
            (stale.content.single as TextContent).text,
            contains('wayfinder index'),
          );
          expect(
            knowledge.calls.every((call) => call.startsWith('searchBundles:')),
            isTrue,
          );
          knowledge.failSearch = false;
          expect(
            (await client.callTool(
              const CallToolRequest(name: 'index'),
            )).isError,
            isNot(true),
          );
          expect(
            (await client.callTool(
              const CallToolRequest(
                name: 'search',
                arguments: {'query': 'caching'},
              ),
            )).isError,
            isNot(true),
          );
        },
      );

      test(
        'discovery follows configuration edits and supports conventional knowledge fallback',
        () async {
          await configure(['knowledge']);
          final selected =
              ((await client.callTool(
                        const CallToolRequest(
                          name: 'search',
                          arguments: {'query': 'caching'},
                        ),
                      )).content.single
                      as TextContent)
                  .text;
          expect(
            selected,
            contains('### knowledge/guide.md:1-2 [knowledge; stable; match]'),
          );
          expect(selected, isNot(contains('shared-kit')));
          await File(p.join(project.path, 'wayfinder.json')).delete();
          final fallback =
              ((await client.callTool(
                        const CallToolRequest(
                          name: 'search',
                          arguments: {'query': 'caching'},
                        ),
                      )).content.single
                      as TextContent)
                  .text;
          expect(fallback, selected);
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

  test(
    'formatSearchMarkdown emits ## Matches and ## Related Context with resolved sources while searchOutput preserves raw JSON',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'wayfinder-markdown-sources-',
      );
      addTearDown(() => temp.delete(recursive: true));
      await Directory(
        p.join(temp.path, 'billing', 'raw exports'),
      ).create(recursive: true);
      await File(p.join(temp.path, 'billing', 'Makefile')).writeAsString('');
      final matchA = SearchResult(
        chunk: Chunk(
          id: 'c1',
          sourcePath: 'billing/invoicing.md',
          lineStart: 10,
          lineEnd: 20,
          content: 'Direct match A body.',
          type: 'paragraph',
          metadata: {
            'okf': {
              'frontmatter': {
                'type': 'Specification',
                'title': 'Invoicing',
                'status': 'stable',
                'sources': [
                  {
                    'id': 'S1',
                    'resource': '../../captures/pkg/analysis.md#finding-2',
                  },
                  {'id': 'S2', 'resource': '/references/revenue.v2.md#table-1'},
                  {'id': 'S3', 'resource': 'references/source notes.md'},
                  {'id': 'S4', 'resource': './references/other notes.md'},
                  {'id': 'S5', 'resource': 'references/evidence.parquet'},
                  {'id': 'S6', 'resource': 'Makefile'},
                  {'id': 'S7', 'resource': 'raw exports'},
                  {'id': 'S8', 'resource': 'données/rapport_été.md'},
                  {'id': 'S9', 'resource': 'acme.sales'},
                  {'id': 'S10', 'resource': 'all queries in acme.sales'},
                  {'id': 'S11', 'resource': 'extracted PDF/OOXML text'},
                  {'id': 'S12', 'resource': '//docs.example.test/spec'},
                  {
                    'id': 'S13',
                    'resource': 'references/evidence.parquet?download=1#row-4',
                  },
                  {'id': 'S14', 'resource': 'FY2026/Q1'},
                  {'id': 'S15', 'resource': 'archive/%FF.md'},
                  {'resource': 'https://example.test/spec#s1'},
                ],
              },
              'headingPath': ['Rules', 'Timing'],
            },
          },
        ),
        embedding: null,
        similarity: 0.91,
      );
      final matchB = SearchResult(
        chunk: Chunk(
          id: 'c2',
          sourcePath: 'billing/terms.md',
          lineStart: 1,
          lineEnd: 5,
          content: 'Direct match B body.',
          type: 'paragraph',
        ),
        embedding: null,
        similarity: 0.82,
      );
      final relatedHit = KnowledgeContextHit(
        SearchResult(
          chunk: Chunk(
            id: 'c3',
            sourcePath: 'billing/oq-12.md',
            lineStart: 4,
            lineEnd: 9,
            content: 'Related question body.',
            type: 'paragraph',
          ),
          embedding: null,
          similarity: 0.65,
        ),
        'relationship',
        viaPath: 'billing/invoicing.md',
      );
      final matchBRelationHit = KnowledgeContextHit(
        matchB,
        'relationship',
        viaPath: 'billing/invoicing.md',
      );
      final response = KnowledgeSearchResponse(
        matches: [matchA, matchB],
        // Even if context only had room for matchA + relatedHit, matchB stays in ## Matches.
        context: [
          KnowledgeContextHit(matchA, 'match'),
          matchBRelationHit,
          relatedHit,
        ],
        notices: const [],
      );
      final markdown = formatSearchMarkdown(
        response,
        prefix: 'knowledge/',
        bundle: 'knowledge',
        bundleRoot: temp.path,
      );
      expect(markdown, contains('## Matches'));
      expect(
        markdown,
        contains(
          '### knowledge/billing/invoicing.md:10-20 [knowledge; stable; match]',
        ),
      );
      expect(
        markdown,
        contains(
          '### knowledge/billing/terms.md:1-5 [knowledge; stable; match]\n'
          '- **Relation:** relationship via knowledge/billing/invoicing.md\n\n'
          'Direct match B body.',
        ),
      );
      expect(
        markdown,
        contains(
          '- **Sources:** [S1] captures/pkg/analysis.md#finding-2, '
          '[S2] knowledge/references/revenue.v2.md#table-1, '
          '[S3] knowledge/billing/references/source notes.md, '
          '[S4] knowledge/billing/references/other notes.md, '
          '[S5] knowledge/billing/references/evidence.parquet, '
          '[S6] knowledge/billing/Makefile, '
          '[S7] knowledge/billing/raw exports, '
          '[S8] knowledge/billing/données/rapport_été.md, '
          '[S9] acme.sales, '
          '[S10] all queries in acme.sales, '
          '[S11] extracted PDF/OOXML text, '
          '[S12] //docs.example.test/spec, '
          '[S13] knowledge/billing/references/evidence.parquet?download=1#row-4, '
          '[S14] FY2026/Q1, '
          '[S15] knowledge/billing/archive/%FF.md, '
          'https://example.test/spec#s1',
        ),
      );
      expect(markdown, contains('## Related Context'));
      expect(
        markdown,
        contains(
          '### knowledge/billing/oq-12.md:4-9 [knowledge; stable; relationship]',
        ),
      );
      expect(
        markdown,
        contains(
          '- **Relation:** relationship via knowledge/billing/invoicing.md',
        ),
      );
      final json = searchOutput(response);
      final jsonFrontmatter =
          ((((json['matches'] as List).first as Map)['chunk']
                      as Map)['metadata']
                  as Map)['okf']
              as Map;
      expect((jsonFrontmatter['frontmatter'] as Map)['sources'], [
        {'id': 'S1', 'resource': '../../captures/pkg/analysis.md#finding-2'},
        {'id': 'S2', 'resource': '/references/revenue.v2.md#table-1'},
        {'id': 'S3', 'resource': 'references/source notes.md'},
        {'id': 'S4', 'resource': './references/other notes.md'},
        {'id': 'S5', 'resource': 'references/evidence.parquet'},
        {'id': 'S6', 'resource': 'Makefile'},
        {'id': 'S7', 'resource': 'raw exports'},
        {'id': 'S8', 'resource': 'données/rapport_été.md'},
        {'id': 'S9', 'resource': 'acme.sales'},
        {'id': 'S10', 'resource': 'all queries in acme.sales'},
        {'id': 'S11', 'resource': 'extracted PDF/OOXML text'},
        {'id': 'S12', 'resource': '//docs.example.test/spec'},
        {
          'id': 'S13',
          'resource': 'references/evidence.parquet?download=1#row-4',
        },
        {'id': 'S14', 'resource': 'FY2026/Q1'},
        {'id': 'S15', 'resource': 'archive/%FF.md'},
        {'resource': 'https://example.test/spec#s1'},
      ]);
    },
  );

  test(
    'explicit bundle retains project-relative citation prefix from sibling, parent, or bundle directories',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'wayfinder-mcp-explicit-subdir-',
      );
      addTearDown(() => project.delete(recursive: true));
      await Directory(p.join(project.path, '.git')).create();
      final siblingDir = await Directory(
        p.join(project.path, 'src', 'app'),
      ).create(recursive: true);
      final docsDir = await Directory(
        p.join(project.path, 'docs'),
      ).create(recursive: true);
      final bundle = await Directory(
        p.join(docsDir.path, 'knowledge'),
      ).create(recursive: true);
      for (final workingDir in [siblingDir, docsDir, bundle]) {
        final knowledge = _HitKnowledge();
        final incoming = StreamController<List<int>>();
        final outgoing = StreamController<List<int>>();
        final serverTransport = IOStreamTransport(
          stream: incoming.stream,
          sink: outgoing.sink,
        );
        final serving = WayfinderMcpServer(
          rootPath: bundle.path,
          workingDirectory: workingDir,
          knowledge: knowledge,
        ).serve(transport: serverTransport);
        final client = McpClient(
          const Implementation(name: 'subdir-test', version: '1.0.0'),
        );
        await client.connect(
          IOStreamTransport(stream: outgoing.stream, sink: incoming.sink),
        );
        try {
          final result = await client.callTool(
            const CallToolRequest(
              name: 'search',
              arguments: {'query': 'caching'},
            ),
          );
          expect(result.isError, isNot(true));
          final text = (result.content.single as TextContent).text;
          final expectedPrefix = workingDir.path == siblingDir.path
              ? 'docs/knowledge/'
              : 'knowledge/';
          expect(
            text,
            contains('### ${expectedPrefix}guide.md:1-2 [stable; match]'),
            reason: 'workingDirectory=${workingDir.path}',
          );
          final cliOut = <String>[];
          final cli = WayfinderCli(
            out: cliOut.add,
            workingDirectory: workingDir,
            knowledge: () => knowledge,
            notices: false,
          );
          final relativeBundle = p.relative(bundle.path, from: workingDir.path);
          expect(
            await cli.run(['search', relativeBundle, 'caching']),
            0,
            reason: 'CLI relative workingDirectory=${workingDir.path}',
          );
          expect(cliOut.single, text);
        } finally {
          await client.close();
          await serverTransport.close();
          await serving;
        }
      }
    },
  );

  test(
    'formatSearchMarkdown collapses multiline metadata fields without altering passage lines',
    () {
      final hit = SearchResult(
        chunk: Chunk(
          sourcePath: 'guide.md',
          lineStart: 1,
          lineEnd: 2,
          content: 'First line\nSecond line \x1b[31mRed\x1b[0m\tTabbed',
          type: 'paragraph',
          metadata: {
            'okf': {
              'frontmatter': {
                'type': 'Guide\n## Injected Type',
                'title': 'Line 1\n## Related Context\nLine 2\x1b[2J',
                'status': 'stable\n### fake',
              },
              'headingPath': ['Intro\n## Section', 'Sub\r\nHeading'],
            },
          },
        ),
        embedding: null,
        similarity: 0.9,
      );
      final markdown = formatSearchMarkdown(
        KnowledgeSearchResponse(
          matches: [hit],
          context: [KnowledgeContextHit(hit, 'match')],
          notices: const ['Notice line 1\n## Fake Notice Heading'],
        ),
      );
      expect(
        markdown,
        contains(
          '- **Type:** Guide ## Injected Type | '
          r'**Title:** Line 1 ## Related Context Line 2\u{001b}[2J',
        ),
      );
      expect(
        markdown,
        contains('- **Section:** Intro ## Section > Sub Heading'),
      );
      expect(
        markdown,
        contains(
          'First line\nSecond line \\u{001b}[31mRed\\u{001b}[0m\tTabbed',
        ),
      );
      expect(
        markdown,
        contains('Notice: Notice line 1 ## Fake Notice Heading'),
      );
      expect(markdown, isNot(contains('\n## Related Context\n')));
    },
  );
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
  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }

  List<KnowledgeInputDiagnostic> warnings = const [];

  @override
  Future<List<KnowledgeSearchResponse>> searchBundles(
    List<String> bundles,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) async {
    calls.add('searchBundles:${bundles.join(',')}:$query:$limit');
    if (failSearch) {
      throw const WayfinderException(
        'index-stale',
        'Index is stale. Run wayfinder index.',
      );
    }
    return [
      for (final bundle in bundles)
        KnowledgeSearchResponse(
          matches: [
            SearchResult(
              chunk: Chunk(
                sourcePath: 'guide.md',
                lineStart: 1,
                lineEnd: 2,
                content: 'Caching guidance',
                type: 'paragraph',
              ),
              embedding: null,
              similarity: p.basename(bundle) == 'knowledge' ? 0.9 : 0.5,
            ),
          ],
          context: [],
          notices: [],
        ),
    ];
  }

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
        'index-stale',
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

class _HitKnowledge extends _Knowledge {
  @override
  Future<KnowledgeSearchResponse> search(
    String bundle,
    String query, {
    int limit = 5,
    KnowledgeMetadataFilter? filters,
  }) async {
    final hit = SearchResult(
      chunk: Chunk(
        sourcePath: 'guide.md',
        lineStart: 1,
        lineEnd: 2,
        content: 'Caching guidance',
        type: 'paragraph',
      ),
      embedding: null,
      similarity: 0.9,
    );
    return KnowledgeSearchResponse(
      matches: [hit],
      context: [KnowledgeContextHit(hit, 'match')],
      notices: const [],
    );
  }
}

/// The resolver the server uses by default.
WayfinderProfileResolver _defaultResolver() =>
    WayfinderProfileResolver(dataDirectory: WayfinderDataDirectory.resolve());
