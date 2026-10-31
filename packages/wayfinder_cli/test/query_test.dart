import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/mcp_server.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';

void main() {
  late Directory project;
  late List<String> out;
  late List<String> err;
  late WayfinderCli cli;
  setUp(() async {
    project = await Directory.systemTemp.createTemp('query-cli-');
    final bundle = await Directory(p.join(project.path, 'knowledge')).create();
    await File(p.join(bundle.path, 'one.md')).writeAsString(
      '---\ntype: Guide\ntitle: One\ntags: [routing]\n---\nText.\n',
    );
    await File(
      p.join(bundle.path, 'two.md'),
    ).writeAsString('---\ntype: Research\ntitle: Two\n---\nText.\n');
    final saved = File(
      p.join(project.path, '.wayfinder', 'queries', 'guides.json'),
    );
    await saved.parent.create(recursive: true);
    await saved.writeAsString('{"format":1,"where":{"types":["Guide"]}}');
    out = [];
    err = [];
    cli = WayfinderCli(
      workingDirectory: project,
      out: out.add,
      err: err.add,
      notices: false,
      knowledge: () => throw StateError('Query opened retrieval'),
    );
  });
  tearDown(() => project.delete(recursive: true));
  Map<String, Object?> result() =>
      jsonDecode(out.single) as Map<String, Object?>;

  test('CLI exact and saved queries agree without opening retrieval', () async {
    expect(await cli.run(['query', '--type', 'Guide', '--output', 'json']), 0);
    final inline = result();
    out.clear();
    expect(await cli.run(['query', '--saved', 'guides', '--output=json']), 0);
    expect(result(), inline);
    expect(err, isEmpty);
  });
  test('standalone bundle and grouped totals, help and text output', () async {
    expect(
      await cli.run([
        'query',
        'knowledge',
        '--group-by',
        'type',
        '--limit',
        '1',
        '--output=json',
      ]),
      0,
    );
    expect(result()['total'], 2);
    expect(result()['group_total'], 2);
    expect(result()['has_more'], true);
    out.clear();
    expect(await cli.run(['query', '--tag', 'routing']), 0);
    expect(out.single, contains('| knowledge | one |'));
    out.clear();
    expect(await cli.run(['query', '--help']), 0);
    expect(out.single, contains('--saved'));
  });
  test(
    'invalid/conflicting inputs fail and JSON errors remain structured',
    () async {
      for (final flags in [
        ['--saved=guides', '--type=Guide'],
        ['--limit=0'],
        ['--limit=no'],
        ['--offset=-1'],
        ['--order-by=title:up'],
        ['--select=body'],
        ['knowledge', '--bundle=knowledge'],
        ['--saved=../private'],
        ['--group-by=type', '--select=title'],
        ['--saved=missing'],
      ]) {
        out.clear();
        err.clear();
        expect(
          await cli.run(['query', ...flags, '--output=json']),
          2,
          reason: flags.toString(),
        );
        expect(err, isNotEmpty);
        expect(result(), isA<Map>());
      }
    },
  );
  test('invalid source produces refusal with exit one', () async {
    await File(
      p.join(project.path, 'knowledge', 'bad.md'),
    ).writeAsString('---\ntype: [bad\n---\n');
    expect(await cli.run(['query', '--output=json']), 1);
    expect(result()['error'], 'query-refused');
    expect(out, hasLength(1));
  });
  test('real MCP, CLI and Dart agree; query never opens an encoder', () async {
    final incoming = StreamController<List<int>>();
    final outgoing = StreamController<List<int>>();
    final encoder = _NoEncoder();
    final store = WayfinderKnowledgeStore(
      dataDirectory: Directory(p.join(project.path, 'unused-data')),
      encoder: encoder,
    );
    final transport = IOStreamTransport(
      stream: incoming.stream,
      sink: outgoing.sink,
    );
    final serving = WayfinderMcpServer(
      workingDirectory: project,
      knowledge: store,
    ).serve(transport: transport);
    final client = McpClient(
      const Implementation(name: 'query-test', version: '1.0.0'),
      options: const McpClientOptions(protocol: McpProtocol.legacy),
    );
    try {
      await client.connect(
        IOStreamTransport(stream: outgoing.stream, sink: incoming.sink),
      );
      final tool = (await client.listTools()).tools.singleWhere(
        (t) => t.name == 'query',
      );
      expect(tool.annotations?.readOnlyHint, true);
      Future<Map<String, Object?>> call(Map<String, dynamic> input) async {
        final response = await client.callTool(
          CallToolRequest(name: 'query', arguments: input),
        );
        expect(response.isError, isNot(true));
        return jsonDecode((response.content.single as TextContent).text)
            as Map<String, Object?>;
      }

      final remote = await call({'saved': 'guides'});
      expect(await cli.run(['query', '--type=Guide', '--output=json']), 0);
      expect(remote, result());
      final bundles = await discoverWayfinderQueryBundles(project);
      expect(
        (await queryWayfinderBundles(
          bundles,
          WayfinderQuery.fromJson({
            'where': {
              'types': ['Guide'],
            },
          }),
        )).toJson(),
        remote,
      );
      expect(
        (await call({
          'query': {'group_by': 'type'},
          'limit': 1,
        }))['total'],
        2,
      );
      for (final input in <Map<String, dynamic>>[
        {},
        {'saved': 'guides', 'query': {}},
        {
          'query': {'sql': 'select'},
        },
        {'query': {}, 'root': '/tmp'},
        {'query': {}, 'limit': 0},
        {'saved': '../private'},
        {
          'query': {
            'where': {
              'tags': [' '],
            },
          },
        },
        {
          'query': {
            'group_by': 'type',
            'select': ['title'],
          },
        },
      ]) {
        expect(
          (await client.callTool(
            CallToolRequest(name: 'query', arguments: input),
          )).isError,
          true,
          reason: input.toString(),
        );
      }
      expect(encoder.opens, 0);
      expect(
        await Directory(p.join(project.path, 'unused-data')).exists(),
        false,
      );
    } finally {
      await client.close();
      await transport.close();
      await serving;
    }
  });
}

class _NoEncoder implements WayfinderEncoderProvider {
  int opens = 0;
  @override
  WayfinderEncoderIdentity get identity => (model: 'absent', source: 'absent');
  @override
  Future<WayfinderEncoder> open() async {
    opens++;
    throw StateError('Query opened an encoder');
  }
}
