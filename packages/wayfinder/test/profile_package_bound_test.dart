import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

import 'support.dart';

/// A package whose second rule's tests run `^(a+)+$` on a near miss, which
/// backtracks for longer than any test runs.
final _hostile = File(
  p.join(
    'test',
    'project',
    'fixtures',
    'hostile-pattern',
    'wayfinder-profile.json',
  ),
).readAsStringSync();

void main() {
  test('reads Bitwild as parse does', () async {
    final json = await File(
      p.join('..', '..', 'profiles', 'bitwild', 'wayfinder-profile.json'),
    ).readAsString();
    final bounded = await ProfilePackage.parseWithin(json);
    expect(bounded.id, bitwild.id);
    expect(bounded.release, bitwild.release);
    expect(
      bounded.rules.map((rule) => rule.descriptor.id),
      bitwild.rules.map((rule) => rule.descriptor.id),
    );
    expect(
      bounded.types.map((type) => type.name),
      bitwild.types.map((type) => type.name),
    );
  });

  test('throws what parse throws', () async {
    final disagreeing = packageJson(
      rules: [
        ruleJson(
          'a',
          subject: 'actor',
          schema: {
            'properties': {
              'id': {'const': 'a'},
            },
          },
          valid: [
            {'id': 'b'},
          ],
          invalid: [
            {'id': 'c'},
          ],
        ),
      ],
    );
    final unsupported = (jsonDecode(packageJson()) as Map<String, Object?>)
      ..['format'] = 3;
    for (final json in [disagreeing, jsonEncode(unsupported), '{']) {
      Object? expected;
      try {
        ProfilePackage.parse(json);
      } on ProfilePackageException catch (error) {
        expected = error;
      }
      expected as ProfilePackageException;
      await expectLater(
        ProfilePackage.parseWithin(json),
        throwsA(
          isA<ProfilePackageException>()
              .having((error) => error.where, 'where', expected.where)
              .having((error) => error.message, 'message', expected.message)
              .having(
                (error) => error.unsupported,
                'unsupported',
                expected.unsupported,
              )
              .having((error) => error.timedOut, 'timedOut', isFalse),
        ),
        reason: json,
      );
    }
  });

  test('stops a package whose rule tests run past the timeout, naming the '
      'rule', () async {
    final watch = Stopwatch()..start();
    // Long enough for a loaded runner to reach the second rule; the
    // hostile pattern runs far longer.
    await expectLater(
      ProfilePackage.parseWithin(_hostile, timeout: const Duration(seconds: 2)),
      throwsA(
        isA<ProfilePackageException>()
            .having((error) => error.timedOut, 'timedOut', isTrue)
            .having((error) => error.unsupported, 'unsupported', isFalse)
            .having((error) => error.where, 'where', 'rules[1].tests')
            .having(
              (error) => '$error',
              'text',
              'did not finish within 2 seconds at rules[1].tests',
            ),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('reports a parse that stops on another error as the package\'s, '
      'without parsing it again here', () async {
    // A value nested a million arrays deep overflows the stack while the
    // package's schemas are read, which throws a StackOverflowError that no
    // ProfilePackageException catches. It is built as text, because encoding
    // it would overflow here first. (A long subject for a backtracking
    // pattern overflows only Dart 3.12's regular-expression engine; 3.11's
    // grows its backtracking stack without a limit.)
    final json = packageJson(
      rules: [
        ruleJson(
          'deep',
          subject: 'frontmatter',
          schema: {
            'properties': {
              'title': {'type': 'array'},
            },
          },
          valid: [
            {'title': 'DEEP'},
          ],
          invalid: [
            {'title': 'c'},
          ],
        ),
      ],
    ).replaceFirst('"DEEP"', '${'[' * 1000000}${']' * 1000000}');
    expect(
      () => ProfilePackage.parse(json),
      throwsA(isA<StackOverflowError>()),
    );
    await expectLater(
      ProfilePackage.parseWithin(json),
      throwsA(
        isA<ProfilePackageException>()
            .having((error) => error.where, 'where', 'package')
            .having(
              (error) => error.message,
              'message',
              'failed: Stack Overflow',
            )
            .having((error) => error.timedOut, 'timedOut', isFalse)
            .having((error) => error.unsupported, 'unsupported', isFalse),
      ),
    );
  });

  test('the default bound is ten seconds', () {
    expect(ProfilePackage.parseTimeout, const Duration(seconds: 10));
  });
}
