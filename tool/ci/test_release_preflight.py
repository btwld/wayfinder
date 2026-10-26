"""Contract checks for the read-only release preflight; no Dart or network."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    'release_preflight', Path(__file__).with_name('release-preflight.py'))
preflight = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = preflight
SPEC.loader.exec_module(preflight)


def ci(**changes):
    return {'repository': {'full_name': 'btwld/wayfinder'},
            'path': '.github/workflows/ci.yml', 'head_sha': 'checked-sha',
            'status': 'completed', 'conclusion': 'success', 'event': 'push',
            'head_branch': 'main', 'html_url': 'https://example.test/ci', **changes}


def graph(**sources):
    return {'root': 'wayfinder_cli', 'packages': [
        {'name': 'wayfinder_cli', 'source': 'root'},
        *[{'name': name, 'source': sources.get(name, 'hosted')}
          for name in ('wayfinder', 'wayfinder_embeddings')],
    ]}


def commit(root):
    environment = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
    for command in (['git', 'add', '.'],
                    ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.test',
                     '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture']):
        subprocess.run(command, cwd=root, env=environment, check=True)
    return preflight.git(root, 'rev-parse', 'HEAD')


def repository(root):
    subprocess.run(['git', 'init', '-q', '-b', 'main'], cwd=root, check=True)
    return commit(root)


class SourceCiTest(unittest.TestCase):
    def test_exact_successful_push_main_is_release_eligible(self):
        self.assertEqual(preflight.source_ci(ci(), 'checked-sha').status, 'passed')

    def test_successful_pr_is_candidate_evidence_not_a_failed_check(self):
        result = preflight.source_ci(ci(event='pull_request', head_branch='feature'), 'checked-sha')
        self.assertEqual(result.status, 'blocked')
        self.assertEqual(result.details['event'], 'pull_request')

    def test_wrong_repo_workflow_or_sha_cannot_supply_release_evidence(self):
        for changes in ({'repository': {'full_name': 'someone/else'}},
                        {'path': '.github/workflows/other.yml'},
                        {'head_sha': 'another-sha'}):
            with self.subTest(changes=changes):
                self.assertEqual(preflight.source_ci(ci(**changes), 'checked-sha').status, 'failed')

    def test_running_and_failed_ci_are_distinct(self):
        self.assertEqual(preflight.source_ci(ci(status='in_progress', conclusion=None),
                                            'checked-sha').status, 'blocked')
        self.assertEqual(preflight.source_ci(ci(conclusion='failure'),
                                            'checked-sha').status, 'failed')

    def test_distribution_adapter_requires_release_eligible_source_ci(self):
        workflow = (preflight.ROOT / '.github/workflows/distribute-wayfinder.yml').read_text()
        section = workflow.split('      - name: Require the application tag and successful CI\n', 1)[1]
        inline = textwrap.dedent(section.split('        run: |\n', 1)[1].split('      - uses:', 1)[0])
        sha = 'a' * 40

        def command_output(command, **kwargs):
            if command[:4] == ['git', 'rev-list', '-n', '1']:
                return sha + '\n'
            self.assertEqual(command, ['gh', 'api', 'repos/btwld/wayfinder/actions/runs/123'])
            return json.dumps(run)

        original_directory = Path.cwd()
        try:
            os.chdir(preflight.ROOT)
            for event, branch, accepted in [('pull_request', 'feature', False),
                                            ('pull_request', 'main', False),
                                            ('push', 'feature', False), ('push', 'main', True)]:
                with self.subTest(event=event, branch=branch):
                    run = ci(head_sha=sha, event=event, head_branch=branch)
                    with mock.patch.dict(os.environ, {'GITHUB_SHA': sha,
                                                     'GITHUB_REPOSITORY': 'btwld/wayfinder',
                                                     'CI_RUN_ID': '123'}, clear=True), \
                            mock.patch('subprocess.check_output', side_effect=command_output) as commands:
                        if accepted:
                            exec(compile(inline, '<distribution-prepare>', 'exec'), {})
                        else:
                            with self.assertRaises(SystemExit):
                                exec(compile(inline, '<distribution-prepare>', 'exec'), {})
                        self.assertEqual(commands.call_count, 2)
        finally:
            os.chdir(original_directory)


class HostedProbeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='preflight-source-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.cli = self.root / preflight.CLI
        self.cli.mkdir(parents=True)
        (self.cli / 'pubspec.yaml').write_text(
            'name: wayfinder_cli\nversion: 1.0.0\nresolution: workspace\n'
            'environment:\n  sdk: ">=3.11.0 <4.0.0"\n'
            'dependencies:\n  wayfinder: ^1.0.0\n  wayfinder_embeddings: ^1.0.0\n')
        (self.cli / 'lib').mkdir()
        (self.cli / 'lib' / 'owned.dart').write_text('const owned = true;\n')
        # These must never reach the hosted package, even though they exist
        # in the source workspace and are convenient for a local dry-run.
        (self.cli / '.dart_tool').mkdir()
        (self.cli / '.dart_tool' / 'package_config.json').write_text('workspace config')
        (self.cli / 'ignored.txt').write_text('not in the checked source')
        (self.root / 'packages/wayfinder').mkdir()
        (self.root / 'packages/wayfinder' / 'workspace-only.dart').write_text('not hosted')
        (self.root / '.gitignore').write_text('**/.dart_tool/\n**/ignored.txt\n')
        self.sha = repository(self.root)

    def test_external_stage_uses_only_checked_files_and_hosted_dependencies(self):
        calls = []
        source_pubspec = (self.cli / 'pubspec.yaml').read_bytes()

        def runner(command, cwd, environment):
            self.assertNotEqual(cwd, self.root)
            self.assertNotIn(self.root, cwd.parents)
            self.assertEqual((cwd / 'lib/owned.dart').read_text(), 'const owned = true;\n')
            self.assertFalse((cwd / 'ignored.txt').exists())
            self.assertFalse((cwd / 'packages').exists())
            self.assertNotIn('resolution:', (cwd / 'pubspec.yaml').read_text())
            self.assertEqual(environment['PUB_HOSTED_URL'], 'https://pub.dev')
            if not calls:
                self.assertFalse((cwd / '.dart_tool').exists())
            calls.append(command)
            return subprocess.CompletedProcess(command, 0,
                                               json.dumps(graph()) if command[2] == 'deps' else 'ok', '')

        result = preflight.hosted_cli(self.root, self.sha, None, runner)
        self.assertEqual(result.status, 'passed')
        self.assertEqual(calls, [
            ['dart', 'pub', 'get'], ['dart', 'pub', 'deps', '--json'],
            ['dart', 'analyze', '--fatal-infos'], ['dart', 'pub', 'publish', '--dry-run']])
        self.assertEqual((self.cli / 'pubspec.yaml').read_bytes(), source_pubspec)
        self.assertEqual((self.cli / '.dart_tool/package_config.json').read_text(), 'workspace config')

    def test_stage_reads_immutable_commit_bytes_not_current_worktree(self):
        source = self.cli / 'lib/owned.dart'
        source.write_text('const untested = true;\n')

        def runner(command, cwd, environment):
            self.assertEqual((cwd / 'lib/owned.dart').read_text(), 'const owned = true;\n')
            return subprocess.CompletedProcess(command, 0,
                                               json.dumps(graph()) if command[2] == 'deps' else 'ok', '')

        result = preflight.hosted_cli(self.root, self.sha, None, runner)
        self.assertEqual(result.status, 'passed')
        self.assertEqual(source.read_text(), 'const untested = true;\n')

    def test_workspace_path_or_git_sibling_is_refused_before_analysis(self):
        for source in ('root', 'path', 'git'):
            calls = []

            def runner(command, cwd, environment):
                calls.append(command)
                return subprocess.CompletedProcess(command, 0,
                                                   json.dumps(graph(wayfinder=source)), '')

            with self.subTest(source=source):
                with self.assertRaises(ValueError):
                    preflight.hosted_cli(self.root, self.sha, None, runner)
                self.assertEqual(len(calls), 2)

    def test_command_failure_retains_exit_and_logs_without_upload(self):
        with tempfile.TemporaryDirectory() as temporary:
            logs = Path(temporary)
            result = preflight.hosted_cli(
                self.root, self.sha, logs,
                lambda command, cwd, environment: subprocess.CompletedProcess(command, 1, '', 'resolution failed'))
            self.assertEqual(result.status, 'failed')
            self.assertEqual(result.details[0]['exit_code'], 1)
            self.assertEqual((logs / 'hosted-cli-pub-get.log').read_text(), 'resolution failed')

    def test_override_file_and_override_keys_are_not_staged(self):
        for text in ('dependency_overrides:\n  wayfinder: any\n',
                     '"dependency_overrides": {}\n',
                     '<<: *overrides\n', '{name: cli, dependency_overrides: {}}\n'):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    preflight.standalone_pubspec('resolution: workspace\n' + text)
        (self.cli / 'pubspec_overrides.yaml').write_text('dependency_overrides: {}\n')
        sha = commit(self.root)
        with self.assertRaises(ValueError):
            preflight.hosted_cli(self.root, sha, None)

    @unittest.skipIf(os.name == 'nt', 'fixture needs a POSIX symlink')
    def test_git_symlink_mode_is_refused(self):
        (self.cli / 'linked.dart').symlink_to('lib/owned.dart')
        sha = commit(self.root)
        with self.assertRaisesRegex(ValueError, 'regular Git file'):
            preflight.hosted_cli(self.root, sha, None)


class PreflightPrerequisiteTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='preflight-committed-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in (*preflight.CLI_SIBLINGS, 'wayfinder_cli'):
            directory = self.root / 'packages' / name
            directory.mkdir(parents=True)
            (directory / 'pubspec.yaml').write_text(
                f'name: {name}\nversion: 1.0.0\nresolution: workspace\n')
        self.sha = repository(self.root)

    def test_unpublished_siblings_do_not_run_hosted_commands(self):
        def refuse(command, cwd, environment):
            self.fail(f'No hosted process may run for unpublished dependencies: {command}')

        report = preflight.preflight(self.root, None, True, None,
                                    published=lambda name: {'0.2.0'}, runner=refuse)
        self.assertEqual(report['status'], 'blocked')
        gates = {gate['name']: gate for gate in report['gates']}
        self.assertEqual(gates['source-tree']['status'], 'passed')
        self.assertEqual(gates['hosted-dependencies']['details']['unpublished'],
                         ['wayfinder 1.0.0', 'wayfinder_embeddings 1.0.0'])
        self.assertEqual(gates['hosted-cli']['status'], 'blocked')

    def test_dirty_tracked_or_untracked_source_never_becomes_ready(self):
        def ci_only(command, cwd, environment):
            self.assertEqual(command[0], 'gh', 'Dirty source must not run the hosted probe.')
            return subprocess.CompletedProcess(command, 0, json.dumps(ci(head_sha=self.sha)), '')

        for relative in ('packages/wayfinder/pubspec.yaml', 'untracked.dart'):
            with self.subTest(relative=relative):
                file = self.root / relative
                original = file.read_bytes() if file.exists() else None
                file.write_text((file.read_text() if file.exists() else '') + '# untested edit\n')
                try:
                    report = preflight.preflight(self.root, '123', True, None,
                                                published=lambda name: {'1.0.0'}, runner=ci_only)
                    self.assertEqual(report['status'], 'blocked')
                    self.assertEqual(report['gates'][0]['status'], 'blocked')
                finally:
                    file.write_bytes(original) if original is not None else file.unlink()

    def test_clean_exact_source_and_independent_hosted_graph_can_pass(self):
        calls = []

        def runner(command, cwd, environment):
            calls.append(command)
            if command[0] == 'gh':
                result = ci(head_sha=self.sha)
            elif command[1:3] == ['pub', 'deps']:
                result = graph()
                result['packages'].append({'name': 'flutter', 'source': 'sdk'})
            else:
                result = {}
            return subprocess.CompletedProcess(command, 0, json.dumps(result), '')

        report = preflight.preflight(self.root, '123', True, None,
                                    published=lambda name: {'1.0.0'}, runner=runner)
        self.assertEqual(report['status'], 'passed')
        self.assertTrue(all(gate['status'] == 'passed' for gate in report['gates']))
        self.assertEqual(len(calls), 5)
        self.assertEqual(calls[-1], ['dart', 'pub', 'publish', '--dry-run'])

    def test_tracked_edit_during_ci_lookup_blocks_before_hosted_probe(self):
        def runner(command, cwd, environment):
            self.assertEqual(command[0], 'gh', 'Stale source must not run the hosted probe.')
            (self.root / 'packages/wayfinder_cli/pubspec.yaml').write_text(
                'name: wayfinder_cli\nversion: 99.0.0\nresolution: workspace\n')
            return subprocess.CompletedProcess(command, 0, json.dumps(ci(head_sha=self.sha)), '')

        report = preflight.preflight(self.root, '123', True, None,
                                    published=lambda name: {'1.0.0'}, runner=runner)
        self.assertEqual(report['status'], 'blocked')
        self.assertEqual(report['gates'][0]['status'], 'blocked')
        self.assertIn('rerun', report['gates'][0]['message'])

    def test_clean_head_advance_during_ci_lookup_still_requires_rerun(self):
        def runner(command, cwd, environment):
            self.assertEqual(command[0], 'gh', 'A different HEAD must not run hosted commands.')
            (self.root / 'new-source.txt').write_text('new commit\n')
            commit(self.root)
            return subprocess.CompletedProcess(command, 0, json.dumps(ci(head_sha=self.sha)), '')

        report = preflight.preflight(self.root, '123', True, None,
                                    published=lambda name: {'1.0.0'}, runner=runner)
        self.assertEqual(preflight.git(self.root, 'status', '--porcelain'), '')
        self.assertEqual(report['status'], 'blocked')
        self.assertNotEqual(report['gates'][0]['details']['head'],
                            report['gates'][0]['details']['current_head'])

    def test_edit_during_hosted_commands_blocks_final_report(self):
        def runner(command, cwd, environment):
            if command[0] == 'gh':
                data = ci(head_sha=self.sha)
            else:
                if command == ['dart', 'pub', 'get']:
                    (self.root / 'late-source.txt').write_text('untested edit\n')
                data = graph() if command[1:3] == ['pub', 'deps'] else {}
            return subprocess.CompletedProcess(command, 0, json.dumps(data), '')

        report = preflight.preflight(self.root, '123', True, None,
                                    published=lambda name: {'1.0.0'}, runner=runner)
        self.assertEqual(report['status'], 'blocked')
        self.assertEqual(report['gates'][0]['status'], 'blocked')
        self.assertEqual(report['gates'][-1]['status'], 'passed')


if __name__ == '__main__':
    unittest.main()
