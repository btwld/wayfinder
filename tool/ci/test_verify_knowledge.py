"""The knowledge gate's exit contract and chain derivation, without Dart."""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    'verify_knowledge', Path(__file__).with_name('verify-knowledge.py'))
gate = importlib.util.module_from_spec(SPEC)
# dataclasses resolves a class's annotations through sys.modules.
sys.modules[SPEC.name] = gate
SPEC.loader.exec_module(gate)


class ChainPathsTest(unittest.TestCase):
    def project(self, config, packages):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / gate.CONFIG).write_text(json.dumps(config))
        for path, package in packages.items():
            (root / path).mkdir(parents=True)
            (root / path / gate.PACKAGE).write_text(json.dumps(package))
        return root

    def test_the_real_binding_needs_its_package_and_every_parent(self):
        self.assertEqual(gate.chain_paths(gate.ROOT), ('.wayfinder/profile', 'profiles/bitwild'))

    def test_a_source_or_parent_in_another_repository_is_refused(self):
        remote = {'profiles': {'p': {'source': {'git': 'https://example.test/p.git', 'path': 'p'}}}}
        with self.assertRaisesRegex(gate.GateDidNotRun, 'names the source https://example.test/p.git'):
            gate.chain_paths(self.project(remote, {}))
        local = {'profiles': {'p': {'source': {'git': '.', 'path': 'p'}}}}
        parent = {'extends': {'git': 'https://example.test/q.git', 'path': 'q'}}
        with self.assertRaisesRegex(gate.GateDidNotRun, 'extends names the repository'):
            gate.chain_paths(self.project(local, {'p': parent}))


class ExitCodeTest(unittest.TestCase):
    """Exit 1 is Wayfinder's FAIL, so a gate that never reached a verdict is 2."""

    def exit_code(self, wayfinder):
        original = gate.WAYFINDER
        gate.WAYFINDER = wayfinder
        self.addCleanup(setattr, gate, 'WAYFINDER', original)
        with contextlib.redirect_stderr(io.StringIO()) as stderr:
            code = gate.main([])
        return code, stderr.getvalue()

    def test_a_missing_wayfinder_executable_is_2(self):
        code, stderr = self.exit_code(('/nonexistent/wayfinder',))
        self.assertEqual(code, 2)
        self.assertIn('FileNotFoundError', stderr)

    def test_a_report_without_a_gate_is_2(self):
        code, stderr = self.exit_code((sys.executable, '-c', 'print("{}")'))
        self.assertEqual(code, 2)
        self.assertIn("KeyError: 'gate'", stderr)


if __name__ == '__main__':
    unittest.main()
