import 'package:test/test.dart';
import 'package:wayfinder_reader/wayfinder_reader.dart';

void main() {
  test('portable handles and identities reject C1 control characters', () {
    expect(
      () => KnowledgeResourceHandle(
        project: 'p',
        revision: 'r',
        path: 'bad\u0085.txt',
      ),
      throwsArgumentError,
    );
    expect(
      () => KnowledgeResourceHandle(
        project: 'p\u0085',
        revision: 'r',
        path: 'file.txt',
      ),
      throwsArgumentError,
    );
  });
}
