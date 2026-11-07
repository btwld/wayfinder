import 'package:flutter_test/flutter_test.dart';
import 'package:wayfinder_flutter/wayfinder_flutter.dart';

void main() {
  test('a bundle summary is equal only at the same revision', () {
    KnowledgeBundleSummary summary({
      String name = 'knowledge',
      String path = 'knowledge',
      int conceptCount = 2,
      int revision = 1,
    }) => KnowledgeBundleSummary(
      name: name,
      path: path,
      conceptCount: conceptCount,
      revision: revision,
    );

    expect(summary(), summary());
    expect(summary().hashCode, summary().hashCode);
    expect(summary(), isNot(summary(revision: 2)));
    expect(summary(), isNot(summary(name: 'other')));
    expect(summary(), isNot(summary(path: 'other')));
    expect(summary(), isNot(summary(conceptCount: 3)));
  });

  test('a bundle summary starts at revision zero', () {
    const summary = KnowledgeBundleSummary(
      name: 'knowledge',
      path: 'knowledge',
      conceptCount: 2,
    );
    expect(summary.revision, 0);
  });
}
