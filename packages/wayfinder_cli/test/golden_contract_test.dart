import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';
import 'package:wayfinder_cli/src/cli.dart';
import 'package:wayfinder_cli/src/mcp_server.dart';
import 'package:wayfinder_cli/src/version.dart';
import 'package:wayfinder_embeddings/knowledge_store.dart';
import 'package:wayfinder_embeddings/testing.dart';

import 'support.dart';

/// Pins today's CLI and MCP output contracts, so a library move or refactor
/// shows every change to them as a reviewed golden diff.
///
/// The project in `test/fixtures/contract-project` binds the frozen Profile in
/// `test/fixtures/contract-profile` from a local Git source, so nothing is
/// fetched and a Bitwild release leaves these goldens alone. It indexes with a
/// deterministic encoder instead of the local model. Its passages are written
/// so that no two chunks of one concept tie, because ties fall back to chunk
/// IDs. Temporary paths, the bundle and configuration keys, chunk IDs, the
/// Profile commit, the server version and timings are normalized; every other
/// byte is compared. Retrieval needs no native library.
///
/// Regenerate with `UPDATE_GOLDENS=1 dart test test/golden_contract_test.dart`
/// only for an intended contract change, then review the diff.
void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  late _ContractProject fixture;
  final retrieval = [
    'index.json',
    'search.md',
    'search_project.json',
    'search_bundle.json',
  ];

  Future<void> expectGolden(String name, String actual) async {
    final golden = File(p.join(_goldens, name));
    if (update) {
      await golden.parent.create(recursive: true);
      await golden.writeAsString(actual);
      return;
    }
    if (!await golden.exists()) {
      fail(
        'No golden at ${golden.path}; run '
        'UPDATE_GOLDENS=1 dart test test/golden_contract_test.dart.',
      );
    }
    final expected = await golden.readAsString();
    if (actual == expected) return;
    fail(
      '${golden.path} differs from the current output '
      '(- golden, + current):\n${_lineDiff(expected, actual)}\n'
      '${_resolvedSerializers()}'
      'Regenerate with UPDATE_GOLDENS=1 dart test '
      'test/golden_contract_test.dart only for a reviewed contract change.',
    );
  }

  // create() removes its own temporary directory when it fails, so the
  // teardown is registered only for a fixture that exists.
  setUpAll(() async {
    fixture = await _ContractProject.create();
    addTearDown(fixture.dispose);
  });

  test('MCP handshakes and tools/list match tools_list.json', () async {
    final project = await fixture.mcpWire();
    final bundle = await fixture.mcpWire(
      rootPath: p.join(fixture.project.path, 'knowledge'),
    );
    final stateless = await fixture.mcpWire(protocol: McpProtocol.require2026);
    expect(
      bundle.tools,
      project.tools,
      reason: 'both scopes register the same tools',
    );
    // The CLI version moves only in release preparation, and the protocol
    // versions are mcp_dart's; keep both out of the contract so neither
    // rewrites this golden.
    Map<String, Object?> serverInfo(Object? info) {
      final map = Map<String, Object?>.from(info! as Map);
      expect(
        map['version'],
        wayfinderVersion,
        reason: 'the server advertises the CLI version',
      );
      return {...map, 'version': '<wayfinder-version>'};
    }

    final initialize = {...project.handshake}..remove('protocolVersion');
    initialize['serverInfo'] = serverInfo(initialize['serverInfo']);
    final discover = {...stateless.handshake}..remove('supportedVersions');
    final meta = Map<String, Object?>.from(discover['_meta']! as Map);
    meta[_serverInfoMeta] = serverInfo(meta[_serverInfoMeta]);
    discover['_meta'] = meta;
    await expectGolden(
      'tools_list.json',
      fixture.json({
        'initialize': initialize,
        'bundleInstructions': bundle.handshake['instructions'],
        'tools/list': project.tools,
        // MCP 2026-07-28: server/discover replaces initialize, and mcp_dart
        // lists the same tools in name order without execution.
        'require2026': {
          'server/discover': discover,
          'tools/list': stateless.tools,
        },
      }),
    );
  });

  test('validate JSON matches validate.json', () async {
    final payload = await fixture.mcpCall('validate');
    final reports = (payload['bundles']! as List).cast<Map<String, Object?>>();
    expect(reports.map((report) => report['path']), [
      'kits/shared-kit',
      'knowledge',
    ]);
    // MCP wraps the CLI's per-bundle JSON; pin that both agree.
    for (final report in reports) {
      final (code, out) = await fixture.cli([
        'validate',
        p.join(fixture.project.path, report['path']! as String),
        '--output=json',
      ]);
      expect(code, report['exit_code']);
      expect(
        fixture.normalize(jsonDecode(out)),
        fixture.normalize({
          for (final MapEntry(:key, :value) in report.entries)
            if (!const {'name', 'path', 'exit_code'}.contains(key)) key: value,
        }),
      );
    }
    await expectGolden('validate.json', fixture.json(payload));
  });

  group('retrieval', () {
    late String index;
    setUpAll(() async {
      final (code, out) = await fixture.cli(['index', '--output=json']);
      expect(code, 0);
      index = fixture.json(jsonDecode(out));
    });

    test('project index JSON matches index.json', () async {
      await expectGolden('index.json', index);
    });

    // A limit of 2 leaves the depends-on target out of the matches, so the
    // Markdown also shows ## Related Context.
    test('MCP project search Markdown matches search.md', () async {
      final markdown = await fixture.mcpSearch(_query, limit: 2);
      final (code, text) = await fixture.cli(['search', _query, '--limit=2']);
      expect(code, 0);
      expect(text, markdown, reason: 'CLI text search prints the same');
      await expectGolden('search.md', '${fixture.text(markdown)}\n');
    });

    test('CLI project search JSON matches search_project.json', () async {
      final (code, out) = await fixture.cli([
        'search',
        _query,
        '--output=json',
      ]);
      expect(code, 0);
      await expectGolden('search_project.json', fixture.json(jsonDecode(out)));
    });

    test('CLI bundle search JSON matches search_bundle.json', () async {
      final (code, out) = await fixture.cli([
        'search',
        p.join(fixture.project.path, 'knowledge'),
        _query,
        '--output=json',
      ]);
      expect(code, 0);
      await expectGolden('search_bundle.json', fixture.json(jsonDecode(out)));
    });

    // The goldens number chunk IDs, so this pins what they do not: the
    // same project elsewhere gets the same IDs.
    test('CLI search JSON chunk IDs do not depend on where the project '
        'lives', () async {
      final elsewhere = await _ContractProject.create();
      addTearDown(elsewhere.dispose);
      expect(elsewhere.project.path, isNot(fixture.project.path));
      final (indexed, _) = await elsewhere.cli(['index', '--output=json']);
      expect(indexed, 0);
      Future<List<String>> ids(_ContractProject project) async {
        final (code, out) = await project.cli([
          'search',
          _query,
          '--output=json',
        ]);
        expect(code, 0);
        final found = <String>[];
        void walk(Object? value) {
          switch (value) {
            case Map():
              for (final MapEntry(:key, :value) in value.entries) {
                if ((key == 'id' || key == 'parentChunkId') &&
                    value is String &&
                    _sha256.hasMatch(value)) {
                  found.add(value);
                } else {
                  walk(value);
                }
              }
            case List():
              value.forEach(walk);
          }
        }

        walk(jsonDecode(out));
        return found;
      }

      final here = await ids(fixture);
      expect(here, isNotEmpty);
      expect(await ids(elsewhere), here);
    });
  });

  test('the goldens directory holds exactly the contract goldens', () {
    final names = Directory(
      _goldens,
    ).listSync().map((entity) => p.basename(entity.path)).toList()..sort();
    expect(names, [...retrieval, 'tools_list.json', 'validate.json']..sort());
  }, skip: update);
}

final _goldens = p.join('test', 'goldens');
final _sha256 = RegExp(r'^[0-9a-f]{64}$');
const _query = 'password recovery';
const _model = 'contract-fixture-v1';

const _serverInfoMeta = 'io.modelcontextprotocol/serverInfo';

typedef _McpWire = ({Map<String, Object?> handshake, List<Object?> tools});

/// A temporary project with two configured bundles, the frozen contract
/// Profile locked from a local Git repository, and a private Wayfinder data
/// directory.
final class _ContractProject {
  _ContractProject._(
    this._temp,
    this._roots,
    this._commit,
    this.project,
    this._resolver,
  );

  final Directory _temp;
  final List<String> _roots;
  final String _commit;
  final Directory project;
  final WayfinderProfileResolver _resolver;

  Directory get _data => Directory(p.join(_temp.path, 'data'));

  static Future<_ContractProject> create() async {
    final temp = await Directory.systemTemp.createTemp('wayfinder-golden-');
    try {
      return await _create(temp);
    } catch (_) {
      await temp.delete(recursive: true);
      rethrow;
    }
  }

  static Future<_ContractProject> _create(Directory temp) async {
    final canonical = await temp.resolveSymbolicLinks();
    final source = await Directory(p.join(temp.path, 'source')).create();
    final profile = File(
      p.join('test', 'fixtures', 'contract-profile', 'wayfinder-profile.json'),
    );
    final package = File(
      p.join(source.path, 'profiles', 'contract', 'wayfinder-profile.json'),
    );
    await package.parent.create(recursive: true);
    await profile.copy(package.path);
    final release =
        (jsonDecode(await profile.readAsString()) as Map)['release']! as String;
    final environment = {
      ...wayfinderGitEnvironment(Platform.environment),
      'GIT_AUTHOR_NAME': 'Wayfinder Test',
      'GIT_AUTHOR_EMAIL': 'test@example.test',
      'GIT_AUTHOR_DATE': '2026-10-01T00:00:00Z',
      'GIT_COMMITTER_NAME': 'Wayfinder Test',
      'GIT_COMMITTER_EMAIL': 'test@example.test',
      'GIT_COMMITTER_DATE': '2026-10-01T00:00:00Z',
    };
    Future<String> git(List<String> arguments) async {
      final result = await Process.run(
        'git',
        [
          '-c',
          'core.autocrlf=false',
          '-c',
          'commit.gpgsign=false',
          '-c',
          'tag.gpgsign=false',
          ...arguments,
        ],
        workingDirectory: source.path,
        environment: environment,
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).trim();
    }

    await git(['init', '-q']);
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'Profile']);
    await git(['tag', 'v$release']);
    final commit = await git(['rev-parse', 'HEAD']);

    final project = await Directory(p.join(temp.path, 'project')).create();
    final fixture = Directory(p.join('test', 'fixtures', 'contract-project'));
    await for (final entity in fixture.list(recursive: true)) {
      if (entity is! File) continue;
      final target = File(
        p.join(project.path, p.relative(entity.path, from: fixture.path)),
      );
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
    await File(p.join(project.path, 'wayfinder.json')).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'profiles': {
          'contract-profile': {
            'source': {'git': source.path, 'ref': 'v$release', 'path': 'profiles/contract'},
            'applies_to': ['knowledge', 'kits/shared-kit'],
            'actors': {
              'process:fixture': {'name': 'Fixture process'},
            },
            'tags': [
              {'name': 'accounts', 'description': 'Account access'},
            ],
          },
        },
      })}\n',
    );
    final resolver = WayfinderProfileResolver(
      dataDirectory: Directory(p.join(temp.path, 'data')),
    );
    await resolver.resolve(project.path);
    // Longest first, so a canonical path never leaves a partial match behind.
    final roots = {canonical, temp.path}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return _ContractProject._(temp, roots, commit, project, resolver);
  }

  Future<void> dispose() => _temp.delete(recursive: true);

  WayfinderKnowledgeStore _knowledge({bool retainEncoder = false}) =>
      WayfinderKnowledgeStore(
        dataDirectory: _data,
        retainEncoder: retainEncoder,
        // Space-separated words as tokens. Every passage fits 28 with its
        // context except weather.md's, whose long description alone exceeds
        // it, so indexing embeds that passage body-only and reports one
        // embedding_context_omitted warning.
        encoder: DeterministicEncoderProvider(
          model: _model,
          maxTokens: 28,
          create: () => DeterministicTestEmbedder(
            modelName: _model,
            vectorOf: keywordVector,
          ),
        ),
      );

  /// Runs one CLI command from the project root and returns its exit code
  /// and standard output.
  Future<(int, String)> cli(List<String> arguments) async {
    final out = <String>[];
    final code = await WayfinderCli(
      out: out.add,
      err: (_) {},
      knowledge: _knowledge,
      profileResolver: () => _resolver,
      workingDirectory: project,
      notices: false,
    ).run(arguments);
    return (code, out.join('\n'));
  }

  /// Serves one MCP session over in-memory streams and records every
  /// JSON-RPC message the server writes, as a client receives it.
  Future<(T, List<Map<String, Object?>>)> _session<T>(
    Future<T> Function(McpClient client) body, {
    String? rootPath,
    McpProtocol protocol = McpProtocol.legacy,
  }) async {
    final toServer = StreamController<List<int>>();
    final fromServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    final tap = StreamController<List<int>>();
    fromServer.stream.listen(
      (bytes) {
        toClient.add(bytes);
        tap.add(bytes);
      },
      onDone: () {
        toClient.close();
        tap.close();
      },
    );
    final wire = tap.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => Map<String, Object?>.from(jsonDecode(line) as Map))
        .toList();
    final transport = IOStreamTransport(
      stream: toServer.stream,
      sink: fromServer.sink,
    );
    final serving = WayfinderMcpServer(
      rootPath: rootPath,
      workingDirectory: project,
      knowledge: _knowledge(retainEncoder: true),
      profileResolver: _resolver,
    ).serve(transport: transport);
    final client = McpClient(
      const Implementation(name: 'wayfinder-golden', version: '1.0.0'),
      options: McpClientOptions(protocol: protocol),
    );
    T result;
    try {
      await client.connect(
        IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
      );
      result = await body(client);
    } finally {
      await client.close();
      await transport.close();
      await serving;
      await fromServer.close();
    }
    return (result, await wire);
  }

  /// The raw handshake result (`initialize`, or `server/discover` under
  /// [McpProtocol.require2026]) and `tools/list` result.
  Future<_McpWire> mcpWire({
    String? rootPath,
    McpProtocol protocol = McpProtocol.legacy,
  }) async {
    final (_, wire) = await _session(
      (client) => client.listTools(),
      rootPath: rootPath,
      protocol: protocol,
    );
    Map<String, Object?> resultWith(String key) => Map<String, Object?>.from(
      wire
              .map((message) => message['result'])
              .whereType<Map<Object?, Object?>>()
              .singleWhere((result) => result.containsKey(key))
          as Map,
    );
    return (
      handshake: resultWith('capabilities'),
      tools: resultWith('tools')['tools']! as List<Object?>,
    );
  }

  /// One project-mode tool call whose single text block is JSON.
  Future<Map<String, Object?>> mcpCall(String name) async {
    final (result, _) = await _session(
      (client) => client.callTool(CallToolRequest(name: name)),
    );
    expect(result.isError, isNot(true));
    return Map<String, Object?>.from(
      jsonDecode((result.content.single as TextContent).text) as Map,
    );
  }

  /// One project-mode `search` call, returning its Markdown text block.
  Future<String> mcpSearch(String query, {required int limit}) async {
    final (result, _) = await _session(
      (client) => client.callTool(
        CallToolRequest(
          name: 'search',
          arguments: {'query': query, 'limit': limit},
        ),
      ),
    );
    expect(result.isError, isNot(true));
    return (result.content.single as TextContent).text;
  }

  /// Pretty-printed, normalized JSON with a final newline.
  String json(Object? value) =>
      '${const JsonEncoder.withIndent('  ').convert(normalize(value))}\n';

  /// Chunk IDs are hashes, so each becomes a label numbered by first
  /// appearance, which keeps matches and context linked.
  Object? normalize(Object? value) {
    final chunks = <String, String>{};
    Object? walk(Object? value) => switch (value) {
      Map() => {
        for (final MapEntry(:key, :value) in value.entries)
          key as String: switch ((key, value)) {
            ('elapsedMs', int()) => 0,
            ('id' || 'parentChunkId', final String id)
                when _sha256.hasMatch(id) =>
              chunks.putIfAbsent(id, () => '<chunk-${chunks.length + 1}>'),
            _ => walk(value),
          },
      },
      List() => [for (final item in value) walk(item)],
      String() => _path(value),
      _ => value,
    };
    return walk(value);
  }

  /// Replaces the machine-specific temporary root in Markdown output.
  String text(String value) =>
      _roots.fold(value, (text, root) => text.replaceAll(root, '<tmp>'));

  String _path(String value) {
    var result = text(value);
    // Windows paths: compare one separator spelling everywhere.
    if (result.contains('<tmp>')) result = result.replaceAll(r'\', '/');
    return result
        .replaceAll(_commit, '<profile-commit>')
        .replaceAll(
          RegExp(r'indexes/bundles/[0-9a-f]{64}/[0-9a-f]{64}'),
          'indexes/bundles/<bundle-key>/<configuration-key>',
        );
  }
}

/// The resolved versions of the packages that serialize the MCP wire bytes,
/// so a mismatch after a dependency upgrade names its likely cause.
String _resolvedSerializers() {
  final lock = File(p.join('..', '..', 'pubspec.lock'));
  if (!lock.existsSync()) return '';
  final text = lock.readAsStringSync();
  final versions = [
    for (final name in ['mcp_dart', 'ack', 'ack_mcp_dart'])
      if (RegExp(
            '^  $name:\n(?:    .*\n)*?    version: "([^"]+)"',
            multiLine: true,
          ).firstMatch(text)
          case final match?)
        '$name ${match[1]}',
  ];
  return versions.isEmpty
      ? ''
      : 'Resolved ${versions.join(', ')}; a dependency upgrade can move the '
            'MCP bytes too.\n';
}

/// A line diff with two lines of context around each change.
String _lineDiff(String expected, String actual) {
  final a = expected.split('\n');
  final b = actual.split('\n');
  final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  final edits = <(String, int, int, String)>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      edits.add((' ', i, j, a[i]));
      i++;
      j++;
    } else if (i < a.length &&
        (j == b.length || lcs[i + 1][j] >= lcs[i][j + 1])) {
      edits.add(('-', i, j, a[i]));
      i++;
    } else {
      edits.add(('+', i, j, b[j]));
      j++;
    }
  }
  const context = 2;
  final shown = List.filled(edits.length, false);
  for (var k = 0; k < edits.length; k++) {
    if (edits[k].$1 == ' ') continue;
    for (
      var c = max(0, k - context);
      c <= min(edits.length - 1, k + context);
      c++
    ) {
      shown[c] = true;
    }
  }
  final lines = <String>[];
  for (var k = 0; k < edits.length; k++) {
    if (!shown[k]) continue;
    if (k == 0 || !shown[k - 1]) {
      lines.add(
        '@@ golden line ${edits[k].$2 + 1}, current line ${edits[k].$3 + 1} @@',
      );
    }
    lines.add('${edits[k].$1} ${edits[k].$4}');
  }
  const limit = 200;
  return lines.length <= limit
      ? lines.join('\n')
      : '${lines.take(limit).join('\n')}\n… ${lines.length - limit} more lines';
}
