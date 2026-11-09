import 'package:okf/okf_io.dart';
import 'package:test/test.dart';
import 'package:wayfinder/wayfinder.dart';

void main() {
  test(
    'shared classification keeps reserved basenames distinct from concepts at every depth',
    () {
      for (final prefix in ['', 'nested/']) {
        expect(
          classifyBundleFile('${prefix}index.md'),
          BundleFileKind.indexDocument,
        );
        expect(
          classifyBundleFile('${prefix}log.md'),
          BundleFileKind.logDocument,
        );
        expect(classifyBundleFile('${prefix}index.MD'), BundleFileKind.asset);
        expect(classifyBundleFile('$prefix.okf.lock'), BundleFileKind.asset);
        for (final name in [
          'a.md',
          'index-notes.md',
          'log-notes.md',
          '.hidden.md',
        ]) {
          final path = '$prefix$name';
          expect(classifyBundleFile(path), BundleFileKind.concept);
          expect(OkfConceptId.fromDocumentPath(path).documentPath, path);
        }
        expect(
          () => OkfConceptId.fromDocumentPath('${prefix}index.md'),
          throwsFormatException,
        );
        expect(
          () => OkfConceptId.fromDocumentPath('${prefix}log.md'),
          throwsFormatException,
        );
      }
    },
  );
}
