"""Regressions for the portable entry's transitive Dart import boundary."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    'reader_closure', Path(__file__).with_name('verify-reader-closure.py'))
closure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(closure)


class ReaderClosureTest(unittest.TestCase):
    def check_sources(self, sources, expected_status):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, source in sources.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source)
            config = root / '.dart_tool/package_config.json'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'packages': [
                {'name': 'wayfinder', 'rootUri': '../packages/wayfinder', 'packageUri': 'lib/'},
                {'name': 'portable', 'rootUri': '../packages/portable', 'packageUri': 'lib/'},
                {'name': 'okf', 'rootUri': '../packages/okf', 'packageUri': 'lib/'},
            ]}))
            output = io.StringIO()
            with patch.object(closure, 'ROOT', root), contextlib.redirect_stderr(output):
                with contextlib.redirect_stdout(output):
                    status = closure.main()
            self.assertEqual(status, expected_status, output.getvalue())
            return output.getvalue()

    def test_native_import_through_package_export_is_rejected(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart': "export 'package:portable/api.dart';",
            'packages/portable/lib/api.dart': "import 'dart:io';",
        }, 1)
        self.assertIn('package:portable/api.dart -> dart:io', output)

    def test_native_conditional_branch_is_checked_on_every_platform(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart':
                "export 'web.dart' if (dart.library.io) 'native.dart';",
            'packages/wayfinder/lib/web.dart': '',
            'packages/wayfinder/lib/native.dart': "import 'dart:ffi';",
        }, 1)
        self.assertIn('native.dart -> dart:ffi', output)

    def test_same_line_directives_cannot_bypass_boundary(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart':
                "library; export 'package:okf/okf.dart'; import 'dart:io';",
        }, 1)
        self.assertIn('knowledge.dart -> dart:io', output)
        self.assertIn('package:okf/okf.dart: forbidden package import', output)

    def test_part_directive_includes_retained_value_source_in_closure(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart': "library; part 'value.dart';",
            'packages/wayfinder/lib/value.dart': "part of 'knowledge.dart'; const value = 1;",
        }, 0)
        self.assertIn('(2 source files)', output)

    def test_comments_and_string_content_do_not_hide_or_invent_directives(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart': '''
// import 'dart:io';
/* outer /* nested */ export 'dart:ffi'; */
export 'value.dart';
const example = "import 'dart:io';";
const url = 'https://example.test';
''',
            'packages/wayfinder/lib/value.dart': "const part = 'not a directive';",
        }, 0)
        self.assertIn('(2 source files)', output)

    def test_adjacent_strings_are_joined(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart': "import 'dart:' /* join */ 'io';",
            'packages/wayfinder/lib/io': '',
        }, 1)
        self.assertIn('dart:io: nonportable SDK import', output)

    def test_comparison_string_is_not_a_directive_uri(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart':
                "export 'web.dart' if (dart.library.io == 'true') 'other.dart';",
            'packages/wayfinder/lib/web.dart': '',
            'packages/wayfinder/lib/other.dart': '',
        }, 0)
        self.assertIn('(3 source files)', output)

    def test_interpolation_in_a_directive_fails_closed(self):
        for uri in ["${'nested'}", '$name']:
            with self.subTest(uri=uri):
                output = self.check_sources({
                    'packages/wayfinder/lib/knowledge.dart':
                        "import '" + uri + "'; import 'dart:io';",
                }, 1)
                self.assertIn('interpolation', output)

    def test_scanning_stops_at_first_declaration(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart':
                "const text = '${\"quotes\"}'; import 'dart:io';",
        }, 0)
        self.assertIn('(1 source files)', output)

    def test_malformed_directives_fail_closed(self):
        for source in ["import 'dart:io", "export 'web.dart'", "import dynamicUri;", "#!/usr/bin/dart\nimport 'dart:io';",
                       "import 'dart\\x3aio';", "export 'a.dart' if (a == ) 'b.dart';"]:
            with self.subTest(source=source):
                self.check_sources({'packages/wayfinder/lib/knowledge.dart': source}, 1)

    def test_relative_directive_cannot_enter_forbidden_package(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart': "export '../../okf/lib/api.dart';",
            'packages/okf/lib/api.dart': '',
        }, 1)
        self.assertIn('forbidden package', output)

    def test_missing_transitive_source_fails_closed(self):
        output = self.check_sources({
            'packages/wayfinder/lib/knowledge.dart': "export 'missing.dart';",
        }, 1)
        self.assertIn('missing.dart: missing source', output)


if __name__ == '__main__':
    unittest.main()
