import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/src/config_layout.dart';
import 'package:wayfinder/wayfinder.dart';

final _acme = ProfileId.parse('acme-notes');

const _source = WayfinderProfileSource(
  git: 'https://example.test/profiles.git',
  ref: 'v1',
  path: 'acme',
);

void main() {
  final examples = [
    for (final name in ['acme-notes', 'bitwild', 'flutter-knowledge'])
      File(p.join('..', '..', 'examples', name, 'wayfinder.json')),
  ];

  group('WayfinderProjectConfig.toJson', () {
    for (final file in examples) {
      test('round-trips ${p.basename(file.parent.path)}', () async {
        final text = await file.readAsString();
        final config = WayfinderProjectConfig.parse(text);
        final again = WayfinderProjectConfig.parse(config.encode());
        expect(again.toJson(), config.toJson());
        expect(config.toJson(), _withoutFormatting(jsonDecode(text)));
      });
    }

    test('writes each bundle path in the explicit ./ form', () {
      final config = WayfinderProjectConfig.parse(
        jsonEncode({
          'version': 1,
          'profiles': {
            'acme-notes': {
              'source': _source.toJson(),
              'applies_to': ['knowledge', './docs/kb/'],
            },
          },
        }),
      );
      expect(
        (config.toJson()['profiles']! as Map)['acme-notes'],
        containsPair('applies_to', ['./knowledge', './docs/kb']),
      );
    });
  });

  group('WayfinderConfigEncoder', () {
    test('writes the documented layout, ending with a newline', () async {
      final acme = await examples.first.readAsString();
      expect(const WayfinderConfigEncoder().convert(jsonDecode(acme)), acme);
      expect(WayfinderConfigEditor.parse(acme).encode(), acme);
    });

    test('keeps key order and puts a list of objects one per line', () {
      expect(
        const WayfinderConfigEncoder().convert({
          'b': [
            {'name': 'x', 'description': 'y'},
          ],
          'a': <String, Object?>{},
          'c': <Object?>[],
          'd': ['./one', './two'],
        }),
        '{\n'
        '  "b": [\n'
        '    {\n'
        '      "name": "x",\n'
        '      "description": "y"\n'
        '    }\n'
        '  ],\n'
        '  "a": {},\n'
        '  "c": [],\n'
        '  "d": ["./one", "./two"]\n'
        '}\n',
      );
    });
  });

  _minimalEncodingTests(examples[1]);

  group('WayfinderConfigEditor', () {
    test('builds a configuration from nothing', () {
      final editor = WayfinderConfigEditor.empty()
        ..setProfile(_acme, _source, appliesTo: ['knowledge']);
      final config = editor.config;
      expect(config.profiles[_acme]!.source.ref, 'v1');
      expect(config.bundles.single.path, 'knowledge');
      expect(editor.encode(), contains('"applies_to": ["./knowledge"]'));
      expect(
        () => WayfinderConfigEditor.empty().setProfile(_acme, _source),
        throwsArgumentError,
      );
    });

    test('keeps fields it does not model and values as written', () {
      final editor = WayfinderConfigEditor.parse(
        jsonEncode({
          'version': 1,
          'x-generator': 'studio',
          'profiles': {
            'acme-notes': {
              'source': {
                'git': 'https://example.test/old.git',
                'ref': 'main',
                'path': 'acme',
                'x-mirror': 'internal',
              },
              'applies_to': ['knowledge'],
              'x-notes': {'owner': 'docs'},
              'actors': {
                'human:sam': {'name': 'Sam', 'x-handle': '@sam'},
              },
            },
          },
        }),
      );
      editor
        ..setProfile(_acme, _source)
        ..putActor(
          _acme,
          'human:sam',
          const WayfinderActorMetadata(name: 'Sam Lee', role: 'Editor'),
        );
      final json = editor.toJson();
      expect(json['x-generator'], 'studio');
      final entry = (json['profiles']! as Map)['acme-notes']! as Map;
      expect(entry['source'], {
        'git': 'https://example.test/profiles.git',
        'ref': 'v1',
        'path': 'acme',
        'x-mirror': 'internal',
      });
      expect(entry['applies_to'], ['knowledge']);
      expect(entry['x-notes'], {'owner': 'docs'});
      expect((entry['actors']! as Map)['human:sam'], {
        'name': 'Sam Lee',
        'x-handle': '@sam',
        'role': 'Editor',
      });
      expect(jsonDecode(editor.encode()), json);
      // Version 1 has no such fields, so the result does not validate.
      expect(() => editor.config, throwsA(isA<WayfinderConfigException>()));
    });

    test('edits bundles, vocabulary and actors', () {
      final editor = WayfinderConfigEditor.empty()
        ..setProfile(_acme, _source, appliesTo: ['./knowledge'])
        ..addBundle(_acme, 'knowledge')
        ..addBundle(_acme, 'docs/kb')
        ..putDefinition(
          _acme,
          WayfinderVocabulary.types,
          const WayfinderDefinition(name: 'Runbook', description: 'Steps'),
        )
        ..putDefinition(
          _acme,
          WayfinderVocabulary.tags,
          const WayfinderDefinition(name: 'ops', description: 'Operations'),
        )
        ..putDefinition(
          _acme,
          WayfinderVocabulary.types,
          const WayfinderDefinition(name: 'Runbook', description: 'Procedure'),
        )
        ..putActor(
          _acme,
          'human:sam',
          const WayfinderActorMetadata(name: 'Sam', side: 'internal'),
        );
      var project = editor.config.profiles[_acme]!;
      expect(project.appliesTo, ['knowledge', 'docs/kb']);
      expect(project.project.types.single.description, 'Procedure');
      expect(project.project.tags.single.name, 'ops');
      expect(project.project.actors['human:sam']!.side, 'internal');

      editor
        ..removeBundle(_acme, './docs/kb/')
        ..removeDefinition(_acme, WayfinderVocabulary.tags, 'ops')
        ..removeActor(_acme, 'human:sam');
      project = editor.config.profiles[_acme]!;
      expect(project.appliesTo, ['knowledge']);
      expect(project.project.tags, isEmpty);
      expect(project.project.actors, isEmpty);
      final entry = (editor.toJson()['profiles']! as Map)['acme-notes'] as Map;
      expect(entry.keys, ['source', 'applies_to', 'types']);

      editor.removeProfile(_acme);
      expect(editor.toJson()['profiles'], isEmpty);
    });

    test('refuses a document an edit could not keep whole', () {
      expect(
        () => WayfinderConfigEditor.parse('[]'),
        throwsA(isA<WayfinderConfigException>()),
      );
      expect(
        () => WayfinderConfigEditor.parse('{'),
        throwsA(isA<WayfinderConfigException>()),
      );
      expect(
        () => WayfinderConfigEditor.parse('{"version": 1, "version": 1}'),
        throwsA(isA<WayfinderConfigException>()),
      );
      expect(
        () => WayfinderConfigEditor.empty().putActor(
          _acme,
          'human:sam',
          const WayfinderActorMetadata(name: 'Sam'),
        ),
        throwsA(isA<WayfinderConfigException>()),
      );
    });
  });
}

final _bitwild = ProfileId.parse('bitwild-profile');

const _assistant = WayfinderActorMetadata(
  name: 'Claude Code over MCP',
  side: 'tool',
);

void _minimalEncodingTests(File bitwildExample) {
  group('WayfinderConfigEditor.encode(minimal: true)', () {
    late String text;

    setUp(() async => text = await bitwildExample.readAsString());

    /// [editor]'s minimal text, after checking it decodes to the edits.
    String minimal(WayfinderConfigEditor editor) {
      final encoded = editor.encode(minimal: true);
      expect(jsonDecode(encoded), editor.toJson());
      expect(WayfinderConfigEditor.parse(encoded).toJson(), editor.toJson());
      return encoded;
    }

    test('adding an actor changes only those bytes', () {
      final editor = WayfinderConfigEditor.parse(text)
        ..putActor(_bitwild, 'mcp:claude-code', _assistant);
      const last =
          '          "side": "vendor"\n'
          '        }';
      expect(text.split(last), hasLength(2));
      expect(
        minimal(editor),
        text.replaceFirst(
          last,
          '$last,\n'
          '        "mcp:claude-code": {\n'
          '          "name": "Claude Code over MCP",\n'
          '          "side": "tool"\n'
          '        }',
        ),
      );
      // The full encoder lays the whole document out again.
      expect(editor.encode(), isNot(minimal(editor)));
    });

    test("keeps the document's indentation, key order, line endings and "
        'values as written', () {
      String crlf(List<String> lines) => '${lines.join('\r\n')}\r\n';
      final source = crlf([
        '{',
        '    "profiles": {',
        '        "acme-notes": {',
        '            "applies_to": [',
        '                "./knowledge"',
        '            ],',
        '            "source": {"git": "https://example.test/old.git", '
            '"ref": "main", "path": "acme"},',
        r'            "x-notes": "As written"',
        '        }',
        '    },',
        '    "version": 1',
        '}',
      ]);
      final editor = WayfinderConfigEditor.parse(source)
        ..setProfile(_acme, _source)
        ..addBundle(_acme, 'docs')
        ..putActor(
          _acme,
          'human:sam',
          const WayfinderActorMetadata(name: 'Sam'),
        );
      expect(
        minimal(editor),
        crlf([
          '{',
          '    "profiles": {',
          '        "acme-notes": {',
          '            "applies_to": [',
          '                "./knowledge",',
          '                "./docs"',
          '            ],',
          '            "source": {"git": "https://example.test/profiles.git", '
              '"ref": "v1", "path": "acme"},',
          r'            "x-notes": "As written",',
          '            "actors": {',
          '                "human:sam": {',
          '                    "name": "Sam"',
          '                }',
          '            }',
          '        }',
          '    },',
          '    "version": 1',
          '}',
        ]),
      );
    });

    test('removing members and items cuts out exactly them and their '
        'separators', () {
      final editor = WayfinderConfigEditor.parse(text)
        ..removeActor(_bitwild, 'human:chris')
        ..removeActor(_bitwild, 'process:meeting-transcription')
        ..removeDefinition(
          _bitwild,
          WayfinderVocabulary.relationships,
          'assessed-by',
        )
        ..removeDefinition(_bitwild, WayfinderVocabulary.tags, 'export');
      expect(
        minimal(editor),
        text
            .replaceFirst(RegExp(r'"human:chris": \{[^}]*\},\n {8}'), '')
            .replaceFirst(
              RegExp(r',\n {8}"process:meeting-transcription": \{[^}]*\}'),
              '',
            )
            .replaceFirst(RegExp(r'"relationships": \[[^\]]*\],\n {6}'), '')
            .replaceFirst(RegExp(r',\n {8}\{"name": "export"[^}]*\}'), ''),
      );
    });

    test('a document written on one line stays on one line', () {
      final source = jsonEncode({
        'version': 1,
        'profiles': {
          'acme-notes': {
            'source': _source.toJson(),
            'applies_to': ['./knowledge'],
          },
        },
      });
      final editor = WayfinderConfigEditor.parse(source)
        ..addBundle(_acme, 'docs')
        ..putActor(
          _acme,
          'human:sam',
          const WayfinderActorMetadata(name: 'Sam'),
        );
      expect(
        minimal(editor),
        source.replaceFirst(
          '"applies_to":["./knowledge"]',
          '"applies_to":["./knowledge","./docs"],'
              '"actors":{"human:sam":{"name":"Sam"}}',
        ),
      );
    });

    test('a list that both gains and loses items is written whole, and the '
        'rest keeps its bytes', () {
      final source = text.replaceFirst(
        '"applies_to": ["./knowledge"]',
        '"applies_to": [ "./a" ,"./b","./knowledge" ]',
      );
      final editor = WayfinderConfigEditor.parse(source)
        ..removeBundle(_bitwild, 'a')
        ..removeBundle(_bitwild, 'b')
        ..addBundle(_bitwild, 'docs');
      expect(
        minimal(editor),
        text.replaceFirst(
          '"applies_to": ["./knowledge"]',
          '"applies_to": ["./knowledge", "./docs"]',
        ),
      );
    });

    test("an edit that reorders a profile's members writes that object "
        'whole, and the rest keeps its bytes', () {
      // A layout the full encoder would not write, outside the profile.
      final source = text.replaceFirst('"version": 1,', '"version" : 1,');
      expect(source, isNot(text));
      // Removing every tag drops the list; adding one back puts it last.
      final editor = WayfinderConfigEditor.parse(source)
        ..removeDefinition(_bitwild, WayfinderVocabulary.tags, 'reporting')
        ..removeDefinition(_bitwild, WayfinderVocabulary.tags, 'export')
        ..putDefinition(
          _bitwild,
          WayfinderVocabulary.tags,
          const WayfinderDefinition(
            name: 'reporting',
            description: 'Reporting and document generation',
          ),
        );
      final profile = (editor.toJson()['profiles']! as Map)['bitwild-profile'];
      expect((profile as Map).keys.last, 'tags');
      const key = '"bitwild-profile": ';
      final start = source.indexOf(key) + key.length;
      const end = '\n  }\n}\n';
      expect(source, endsWith(end));
      final written = const WayfinderConfigEncoder()
          .convert(profile)
          .trimRight()
          .replaceAll('\n', '\n    ');
      expect(minimal(editor), '${source.substring(0, start)}$written$end');
      expect(minimal(editor), isNot(editor.encode()));
    });

    test('a member added before one that remains writes its object whole, '
        'and the rest keeps its bytes', () {
      const source =
          '{\n'
          '  "keep" :  [ 1,2 ],\n'
          '  "object": {\n'
          '    "b": 1,\n'
          '    "c":  2\n'
          '  }\n'
          '}\n';
      expect(
        spliceJson(source, {
          'keep': [1, 2],
          'object': {'a': 0, 'b': 1, 'c': 2},
        }),
        '{\n'
        '  "keep" :  [ 1,2 ],\n'
        '  "object": {\n'
        '    "a": 0,\n'
        '    "b": 1,\n'
        '    "c": 2\n'
        '  }\n'
        '}\n',
      );
    });

    test('a spliced text that does not parse back to the edits, or that '
        'the editor refuses, is not used', () {
      final edited = WayfinderConfigEditor.parse(text)
        ..putActor(_bitwild, 'mcp:claude-code', _assistant);
      final document = edited.toJson();
      expect(spliceJsonChecked(text, document), edited.encode(minimal: true));
      for (final splice in <String Function(String, Object?)>[
        // Other JSON.
        (source, _) => source,
        // Not JSON.
        (source, _) => source.substring(1),
        // Throws as a parser does.
        (_, _) => throw const FormatException('Unexpected character'),
      ]) {
        expect(spliceJsonChecked(text, document, splice: splice), isNull);
      }
      // A text the caller refuses, as the editor refuses a repeated key.
      expect(spliceJsonChecked(text, document, accept: (_) => false), isNull);
    });

    test('an editor with no source text encodes in full', () {
      final editor = WayfinderConfigEditor.empty()
        ..setProfile(_acme, _source, appliesTo: ['knowledge']);
      expect(editor.encode(minimal: true), editor.encode());
    });
  });
}

/// [value] as `toJson` writes it: every bundle path explicit.
Object? _withoutFormatting(Object? value, [String? key]) => switch (value) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries)
      key.toString(): _withoutFormatting(value, key.toString()),
  },
  final List<Object?> list when key == 'applies_to' => [
    for (final path in list)
      WayfinderProfileBinding.explicitBundlePath(path! as String),
  ],
  final List<Object?> list => [
    for (final item in list) _withoutFormatting(item),
  ],
  _ => value,
};
