import 'dart:convert';

import 'package:okf_profile/okf_profile.dart';
import 'package:station/src/cli.dart';
import 'package:test/test.dart';

void main() {
  late List<String> output;
  late List<String> errors;
  late StationCli cli;
  setUp(() {
    output = [];
    errors = [];
    cli = StationCli(
      out: output.add,
      err: errors.add,
      knowledge: () =>
          throw StateError('Validation/help must not open retrieval.'),
    );
  });

  test('root help exposes only the three agreed commands', () async {
    expect(await cli.run(['--help']), 0);
    final help = output.join('\n');
    expect(help, contains('validate <bundle>'));
    expect(help, contains('index <bundle>'));
    expect(help, contains('search <bundle>'));
    expect(help, isNot(contains('--mode')));
    expect(help, isNot(contains('models prepare')));
  });

  for (final args in [
    <String>[],
    ['profile', 'validate', '../../examples/knowledge'],
    ['knowledge', 'search', '.', 'query'],
    ['search', '.', 'query', '--mode=dense'],
    ['index'],
    ['search', '.'],
    ['search', '.', ''],
    ['search', '.', 'query', '--limit=0'],
    ['search', '.', 'query', '--limit=oops'],
  ]) {
    test('rejects invalid usage $args', () async {
      expect(await cli.run(args), 2);
      expect(errors, isNotEmpty);
    });
  }

  test('validate shares the full existing result and exit code', () async {
    const bundle = '../../examples/knowledge';
    final expected = await const ProfileValidator().validate(bundle);
    expect(
      await cli.run(['validate', bundle, '--output=json']),
      expected.exitCode,
    );
    expect(jsonDecode(output.single), expected.toJson());
    expect(expected.toJson()['judgment_rules'], {'state': 'UNASSESSED'});
    expect(errors, isEmpty);
  });

  test('command help and version require no local index or model', () async {
    expect(await cli.run(['index', '--help']), 0);
    expect(await cli.run(['search', '--help']), 0);
    expect(await cli.run(['validate', '--help']), 0);
    expect(await cli.run(['--version']), 0);
    expect(errors, isEmpty);
  });

  test('validate preserves an undeclared-profile result', () async {
    const bundle = 'test/fixtures/knowledge';
    final expected = await const ProfileValidator().validate(bundle);
    expect(expected.exitCode, isNot(0));
    expect(
      await cli.run(['validate', bundle, '--output=json']),
      expected.exitCode,
    );
    expect(jsonDecode(output.single), expected.toJson());
  });
}
