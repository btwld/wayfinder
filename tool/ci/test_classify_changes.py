"""Path classification and the required check, without network or Dart."""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    'classify_changes', Path(__file__).with_name('classify_changes.py'))
classify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(classify)

ROOT = Path(__file__).resolve().parents[2]
PULL_REQUEST_TYPES = 'types: [opened, synchronize, reopened, ready_for_review]'
PULL_REQUEST_WORKFLOWS = (
    'ci.yml',
    'installer-scripts.yml',
    'verify-public-install.yml',
)
DISPATCH_RUNNER = (
    "${{ github.event_name == 'workflow_dispatch' && inputs.runner "
    "|| 'ubuntu-latest' }}"
)


class ClassificationTest(unittest.TestCase):
    def test_documentation_readme_license_template_and_assets_are_non_code(self):
        non_code = [
            'docs/contributing.md',
            'docs/adr/0009-local-knowledge-retrieval.md',
            'README.md',
            'readme',
            'packages/wayfinder/README.md',
            'LICENSE',
            'packages/wayfinder/LICENSE',
            'tool/LICENSE.txt',
            '.github/ISSUE_TEMPLATE/bug.md',
            '.github/PULL_REQUEST_TEMPLATE/pull_request.md',
            '.github/pull_request_template.md',
            'assets/logo.svg',
            'docs/images/flow.png',
            'skills/author-knowledge-bundle/SKILL.md',
            'implementation/okf-implementation-guide.md',
            'profiles/bitwild/README.md',
            'AGENTS.md',
            'examples/README.md',
        ]
        for path in non_code:
            with self.subTest(path=path):
                self.assertTrue(classify.is_non_code(path))
                self.assertFalse(classify.should_run([path], 'code'))

    def test_contract_examples_skill_fixtures_and_sources_are_code(self):
        code = [
            'docs/schemas/wayfinder.schema.json',
            'docs/schemas/wayfinder-profile.schema.json',
            '.github/workflows/ci.yml',
            'packages/wayfinder/lib/wayfinder.dart',
            'packages/wayfinder/test/a_test.dart',
            'packages/wayfinder/test/fixtures/note.md',
            'packages/wayfinder_embeddings/fixtures/corpus/page.md',
            'examples/bitwild/knowledge/index.md',
            'examples/profiles/two-rule/wayfinder-profile.json',
            'profiles/bitwild/skill/references/types.md',
            'profiles/bitwild/wayfinder-profile.json',
            'profiles/bitwild/versions/okf-profile-2026.2.md',
            'tool/install.sh',
            'tool/ci/classify_changes.py',
            'pubspec.yaml',
        ]
        for path in code:
            with self.subTest(path=path):
                self.assertTrue(classify.is_code(path))

    def test_one_code_path_keeps_heavy_jobs(self):
        self.assertTrue(classify.should_run(
            ['docs/contributing.md', 'packages/wayfinder/lib/wayfinder.dart'],
            'code',
        ))

    def test_empty_or_unknown_history_runs_code_jobs(self):
        self.assertTrue(classify.should_run([], 'code'))
        self.assertTrue(classify.should_run(None, 'code'))
        self.assertIsNone(classify.changed_paths('0' * 40, 'a' * 40, '..'))

    def test_installer_and_public_install_watch_their_own_files(self):
        self.assertTrue(classify.should_run(['tool/install.sh'], 'installer'))
        self.assertFalse(classify.should_run(['docs/contributing.md'], 'installer'))
        self.assertTrue(classify.should_run(
            ['tool/verify_public_install.py'], 'public-install'))
        self.assertFalse(classify.should_run(
            ['tool/test_install_platform.sh'], 'public-install'))
        self.assertTrue(classify.should_run(None, 'installer'))

    def test_git_diff_separates_a_readme_commit_from_a_source_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment = dict(
                os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
            subprocess.run(['git', 'init', '-q', '-b', 'main'], cwd=root, check=True)
            (root / 'README.md').write_text('a\n', encoding='utf-8')
            base = _commit(root, environment)
            (root / 'README.md').write_text('b\n', encoding='utf-8')
            head = _commit(root, environment)
            original = Path.cwd()
            try:
                os.chdir(root)
                paths = classify.changed_paths(base, head, '..')
                self.assertEqual(paths, ['README.md'])
                self.assertFalse(classify.should_run(paths, 'code'))
                (root / 'lib.dart').write_text('void main() {}\n', encoding='utf-8')
                source = _commit(root, environment)
                paths = classify.changed_paths(head, source, '..')
                self.assertEqual(paths, ['lib.dart'])
                self.assertTrue(classify.should_run(paths, 'code'))
            finally:
                os.chdir(original)


class RequiredCheckTest(unittest.TestCase):
    def test_code_changes_require_every_heavy_job(self):
        passed, _ = classify.evaluate(
            changes='success', run=True,
            results={'test': 'success', 'native-retrieval': 'success'},
            may_skip=set(),
        )
        self.assertEqual(passed, 'passed')
        failed, message = classify.evaluate(
            changes='success', run=True,
            results={'test': 'success', 'native-retrieval': 'skipped'},
            may_skip=set(),
        )
        self.assertEqual(failed, 'failed')
        self.assertIn('native-retrieval=skipped', message)

    def test_non_code_skip_still_passes_the_required_check(self):
        status, message = classify.evaluate(
            changes='success', run=False,
            results={'test': 'skipped', 'native-retrieval': 'skipped'},
            may_skip=set(),
        )
        self.assertEqual(status, 'passed')
        self.assertIn('still reports success', message)

    def test_an_intentional_platform_skip_is_allowed_only_by_name(self):
        status, _ = classify.evaluate(
            changes='success', run=True,
            results={'posix': 'success', 'windows': 'skipped'},
            may_skip={'windows'},
        )
        self.assertEqual(status, 'passed')
        failed, _ = classify.evaluate(
            changes='success', run=True,
            results={'posix': 'skipped', 'windows': 'skipped'},
            may_skip={'windows'},
        )
        self.assertEqual(failed, 'failed')

    def test_classification_or_job_failure_fails_the_required_check(self):
        for changes, results in (
            ('failure', {'test': 'skipped'}),
            ('success', {'test': 'failure'}),
            ('success', {'test': 'cancelled'}),
        ):
            with self.subTest(changes=changes, results=results):
                status, _ = classify.evaluate(
                    changes=changes, run=True,
                    results=results, may_skip=set(),
                )
                self.assertEqual(status, 'failed')

    def test_require_cli_uses_the_environment(self):
        completed = subprocess.run(
            ['python3', str(ROOT / 'tool/ci/classify_changes.py'), '--require'],
            check=False,
            capture_output=True,
            text=True,
            env=dict(
                os.environ,
                CHANGES='success',
                RUN='false',
                RESULTS='test=skipped',
                MAY_SKIP='',
            ),
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        failed = subprocess.run(
            ['python3', str(ROOT / 'tool/ci/classify_changes.py'), '--require'],
            check=False,
            capture_output=True,
            text=True,
            env=dict(
                os.environ,
                CHANGES='success',
                RUN='true',
                RESULTS='test=failure',
                MAY_SKIP='',
            ),
        )
        self.assertEqual(failed.returncode, 1)


class WorkflowContractTest(unittest.TestCase):
    def test_pull_request_types_are_exactly_the_four_best_practice_types(self):
        forbidden = (
            'labeled', 'unlabeled', 'assigned', 'unassigned', 'edited',
            'converted_to_draft', 'closed', 'locked', 'ready_for_review ',
        )
        for name in PULL_REQUEST_WORKFLOWS:
            text = (ROOT / '.github/workflows' / name).read_text(encoding='utf-8')
            types = [
                line.strip() for line in text.splitlines()
                if line.strip().startswith('types:')
            ]
            with self.subTest(workflow=name):
                self.assertEqual(types, [PULL_REQUEST_TYPES])
                for word in forbidden:
                    self.assertNotIn(word, types[0])
                self.assertNotIn('paths-ignore', text)
                self.assertNotIn('\n    paths:', text)
                self.assertIn('cancel-in-progress: true', text)
                self.assertIn('branches: [main]', text)
                self.assertIn('python3 tool/ci/classify_changes.py --require', text)
                self.assertNotIn('DRAFT:', text)
                self.assertNotIn('Draft pull requests do not satisfy', text)

    def test_every_pull_request_job_skips_a_draft(self):
        for name in PULL_REQUEST_WORKFLOWS:
            text = (ROOT / '.github/workflows' / name).read_text(encoding='utf-8')
            jobs = _job_names(text)
            self.assertGreaterEqual(len(jobs), 2, name)
            with self.subTest(workflow=name):
                for job in jobs:
                    header = _job_section(text, f'{job}:').split('\n    steps:', 1)[0]
                    self.assertIn('if:', header, job)
                    self.assertIn(
                        'github.event.pull_request.draft == false', header, job)
        source = (ROOT / 'tool/ci/classify_changes.py').read_text(encoding='utf-8')
        self.assertNotIn("os.environ.get('DRAFT'", source)
        self.assertNotIn('Draft pull requests do not satisfy', source)

    def test_heavy_jobs_skip_drafts_and_light_jobs_use_ubuntu_slim(self):
        expectations = {
            'ci.yml': ('test:', 'native-retrieval:'),
            'installer-scripts.yml': ('posix:', 'windows:'),
            'verify-public-install.yml': ('install:',),
        }
        for name, heavy in expectations.items():
            text = (ROOT / '.github/workflows' / name).read_text(encoding='utf-8')
            with self.subTest(workflow=name):
                self.assertGreaterEqual(text.count('runs-on: ubuntu-slim'), 2)
                for job in heavy:
                    section = _job_section(text, job)
                    self.assertIn('needs.changes.outputs.run', section)
                    self.assertIn('github.event.pull_request.draft == false', section)

    def test_macos_is_not_a_pull_request_runner(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            text = path.read_text(encoding='utf-8')
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith('runs-on:'):
                    self.assertNotIn('macos', stripped.casefold(), path.name)
        public = (ROOT / '.github/workflows' / 'verify-public-install.yml').read_text(
            encoding='utf-8')
        self.assertIn('macos-15', public)
        self.assertIn(f'runs-on: {DISPATCH_RUNNER}', public)
        ci = (ROOT / '.github/workflows' / 'ci.yml').read_text(encoding='utf-8')
        self.assertIn('os: [ubuntu-latest]', ci)
        installer = (ROOT / '.github/workflows' / 'installer-scripts.yml').read_text(
            encoding='utf-8')
        self.assertNotIn('macos', installer.casefold())

    def test_publish_and_distribution_stay_standard_ubuntu_without_pull_requests(self):
        for name in (
            'publish-wayfinder.yml',
            'publish-wayfinder-cli.yml',
            'publish-wayfinder-embeddings.yml',
            'publish-wayfinder-dart-chunker.yml',
            'distribute-wayfinder.yml',
        ):
            text = (ROOT / '.github/workflows' / name).read_text(encoding='utf-8')
            with self.subTest(workflow=name):
                self.assertNotIn('pull_request:', text)
                self.assertIn('cancel-in-progress: false', text)
                self.assertNotIn('ubuntu-slim', text)
                self.assertNotIn('macos', text.casefold())


def _job_names(text: str) -> list[str]:
    """Top-level job ids under ``jobs:``."""
    jobs = text.split('\njobs:\n', 1)[1]
    names = []
    for line in jobs.splitlines():
        if (
            line.startswith('  ')
            and not line.startswith('   ')
            and line.endswith(':')
            and ' ' not in line.strip()[:-1]
        ):
            names.append(line.strip()[:-1])
    return names


def _job_section(text: str, job: str) -> str:
    """The body of a top-level job, through the line before the next job."""
    marker = f'\n  {job}\n'
    start = text.index(marker) + len(marker)
    lines = []
    for line in text[start:].splitlines(keepends=True):
        if len(line) > 2 and line.startswith('  ') and line[2] != ' ':
            break
        lines.append(line)
    return ''.join(lines)


def _commit(root: Path, environment: dict[str, str]) -> str:
    for command in (
        ['git', 'add', '.'],
        ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
         '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture'],
    ):
        subprocess.run(command, cwd=root, env=environment, check=True)
    return subprocess.run(
        ['git', 'rev-parse', 'HEAD'],
        cwd=root, env=environment, check=True, capture_output=True, text=True,
    ).stdout.strip()


if __name__ == '__main__':
    unittest.main()
