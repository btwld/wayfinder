import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The library's messages say what happened and name no command
/// (ADR-0018): a host words what to run, as the `wayfinder` command adds
/// `Run wayfinder get.`. This reads every string literal under `lib/`,
/// adjacent literals joined as Dart joins them, and refuses one that tells
/// someone to run a command.
///
/// Two files hold text a host writes into a project or publishes rather
/// than messages, and may name commands: the adoption seeds, whose
/// `AGENTS.md` block and bundle seeds tell agents what to run, and the
/// published schemas, whose descriptions document the command.
void main() {
  const content = {'src/adoption/seeds.dart', 'src/generated'};

  final commands = RegExp(
    r'\bwayfinder (get|upgrade|validate|index|search|graph|mcp|skills|setup'
    r'|update|session-context)\b'
    r'|\brun wayfinder\b'
    r'|\b(run|rerun) the command\b'
    r'|\bmelos run\b',
    caseSensitive: false,
  );

  test('no library message names a command', () {
    final offending = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final path = p.posix.joinAll(p.split(p.relative(file.path, from: 'lib')));
      if (!path.endsWith('.dart') ||
          content.any((skipped) => path.startsWith(skipped))) {
        continue;
      }
      for (final literal in stringLiterals(file.readAsStringSync())) {
        if (commands.hasMatch(literal)) offending.add('$path: $literal');
      }
    }
    expect(offending, isEmpty);
  });

  test('the scan sees joined, interpolated and nested literals', () {
    expect(
      stringLiterals(r'''
        // 'Run wayfinder get.' in a comment is not a message.
        /* nor 'here' /* nested */ */
        final a = 'Run wayfinder '
            // a comment between the parts
            "get.";
        final b = 'Profile ${id ? 'x' : "y"} is $state.';
        final c = r'raw \n' """triple ${'in'}""";
      '''),
      [
        'Run wayfinder get.',
        'x',
        'y',
        'Profile … is ….',
        'in',
        r'raw \ntriple …',
      ],
    );
  });
}

/// Every string literal in [source], outside comments, with adjacent
/// literals joined and each interpolation as `…`. A literal inside an
/// interpolation is listed on its own, before the literal that holds it.
List<String> stringLiterals(String source) =>
    (_Scanner(source)..code(until: null)).literals;

final class _Scanner {
  _Scanner(this.source);

  final String source;
  final literals = <String>[];
  var index = 0;

  bool at(String text) => source.startsWith(text, index);

  /// Scans code up to the `}` that closes an interpolation, or to the end
  /// when [until] is null, collecting the literals it meets.
  void code({required String? until}) {
    var depth = 0;
    StringBuffer? joined;
    var joinable = false;
    void flush() {
      if (joined != null) literals.add(joined.toString());
      joined = null;
      joinable = false;
    }

    while (index < source.length) {
      if (at('//')) {
        index = source.indexOf('\n', index);
        if (index < 0) index = source.length;
        continue;
      }
      if (at('/*')) {
        skipBlockComment();
        continue;
      }
      final char = source[index];
      if (char.trim().isEmpty) {
        index++;
        continue;
      }
      final raw = char == 'r' && (at("r'") || at('r"'));
      if (raw || char == "'" || char == '"') {
        if (!joinable) flush();
        final text = string(raw: raw);
        (joined ??= StringBuffer()).write(text);
        joinable = true;
        continue;
      }
      joinable = false;
      if (char == '{') depth++;
      if (char == '}') {
        if (depth == 0 && until == '}') {
          index++;
          flush();
          return;
        }
        depth--;
      }
      // An identifier that ends in r, such as `bar'`, is not a raw string.
      if (RegExp(r'[A-Za-z0-9_$]').hasMatch(char)) {
        while (index < source.length &&
            RegExp(r'[A-Za-z0-9_$]').hasMatch(source[index])) {
          index++;
        }
        continue;
      }
      index++;
    }
    flush();
  }

  void skipBlockComment() {
    var depth = 0;
    while (index < source.length) {
      if (at('/*')) {
        depth++;
        index += 2;
      } else if (at('*/')) {
        depth--;
        index += 2;
        if (depth == 0) return;
      } else {
        index++;
      }
    }
  }

  /// The text of the string literal at [index], which starts with its
  /// quote (after `r` when [raw]), and moves past it.
  String string({required bool raw}) {
    if (raw) index++;
    final quote = source[index];
    final triple = at(quote * 3);
    final close = triple ? quote * 3 : quote;
    index += close.length;
    final text = StringBuffer();
    while (index < source.length && !at(close)) {
      final char = source[index];
      if (!raw && char == r'\') {
        text.write(source.substring(index, index + 2));
        index += 2;
      } else if (!raw && at(r'${')) {
        index += 2;
        code(until: '}');
        text.write('…');
      } else if (!raw && char == r'$') {
        index++;
        while (index < source.length &&
            RegExp(r'[A-Za-z0-9_]').hasMatch(source[index])) {
          index++;
        }
        text.write('…');
      } else {
        text.write(char);
        index++;
      }
    }
    index += close.length;
    return text.toString();
  }
}
