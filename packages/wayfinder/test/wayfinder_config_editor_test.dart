import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
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
