#!/usr/bin/env python3
"""Read-only pre-publication checks; this never tags, uploads or dispatches CI.

Exit 0: these preflight gates passed (not release completion).
Exit 2: external prerequisites or an explicitly requested check are missing.
Exit 1: a check failed. JSON and command logs retain that distinction.
"""

import argparse
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = 'btwld/wayfinder'
CLI = Path('packages/wayfinder_cli')
CLI_SIBLINGS = ('wayfinder', 'wayfinder_embeddings')


@dataclass
class Gate:
    name: str
    status: str
    message: str
    details: object = None


def source_ci(run: dict, sha: str, repository: str = REPOSITORY) -> Gate:
    """PR CI is candidate evidence, not release-eligible push/main evidence."""
    details = {'url': run.get('html_url'), 'event': run.get('event'),
               'head_sha': run.get('head_sha')}
    if run.get('repository', {}).get('full_name') != repository:
        return Gate('source-ci', 'failed', 'CI belongs to another repository.', details)
    if run.get('path') != '.github/workflows/ci.yml':
        return Gate('source-ci', 'failed', 'Run is not the source CI workflow.', details)
    if run.get('head_sha') != sha:
        return Gate('source-ci', 'failed', 'CI does not name the checked commit.', details)
    if run.get('status') != 'completed':
        return Gate('source-ci', 'blocked', 'Exact-source CI has not completed.', details)
    if run.get('conclusion') != 'success':
        return Gate('source-ci', 'failed', 'Exact-source CI did not succeed.', details)
    if run.get('event') != 'push' or run.get('head_branch') != 'main':
        return Gate('source-ci', 'blocked',
                    'Successful candidate CI is not release-eligible push/main CI.', details)
    return Gate('source-ci', 'passed', 'Successful push/main CI names this exact commit.', details)


def published_versions(name: str) -> set[str]:
    try:
        with urllib.request.urlopen(f'https://pub.dev/api/packages/{name}', timeout=30) as response:
            return {entry['version'] for entry in json.load(response)['versions']}
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return set()
        raise


def hosted_dependencies(versions: dict[str, str], published) -> Gate:
    missing = [f'{name} {version}' for name, version in versions.items()
               if version not in published(name)]
    if missing:
        return Gate('hosted-dependencies', 'blocked',
                    'Publish the CLI sibling versions in dependency order before hosted resolution.',
                    {'unpublished': missing})
    return Gate('hosted-dependencies', 'passed',
                'Both exact CLI sibling versions are available on pub.dev.', versions)


def standalone_pubspec(text: str) -> str:
    """Keep the checked repo pubspec; remove only its workspace resolution.

    This deliberately accepts this repository's plain top-level key layout,
    not arbitrary YAML syntax. Fail closed on quoted/merged/flow top-level
    layouts so an override key cannot evade the hosted-only check.
    """
    lines = []
    removed = False
    for line in text.splitlines(keepends=True):
        if not line.strip() or line.lstrip().startswith('#') or line[0].isspace():
            lines.append(line)
            continue
        match = re.fullmatch(r'([a-z][a-z0-9_]*):(?:[^\r\n]*)\r?\n?', line)
        if not match:
            raise ValueError('Hosted preflight requires plain unquoted top-level pubspec keys.')
        key = match[1]
        if key in ('dependency_overrides', 'workspace'):
            raise ValueError(f'Hosted preflight refuses {key}.')
        if key == 'resolution':
            if not re.fullmatch(r'resolution:[ \t]*workspace[ \t]*(?:#[^\r\n]*)?\r?\n?', line):
                raise ValueError('Unexpected package resolution setting.')
            if removed:
                raise ValueError('Repeated package resolution setting.')
            removed = True
            continue
        lines.append(line)
    if not removed:
        raise ValueError('Expected the checked CLI package workspace resolution.')
    return ''.join(lines)


def check_hosted_graph(graph: dict) -> None:
    packages = {entry['name']: entry for entry in graph['packages']}
    if graph.get('root') != 'wayfinder_cli':
        raise ValueError('Dependency graph is not the staged standalone CLI.')
    for name in CLI_SIBLINGS:
        if packages.get(name, {}).get('source') != 'hosted':
            raise ValueError(f'{name} did not resolve from a hosted source.')
    if any(entry['source'] not in ('root', 'hosted', 'sdk')
           or (entry['source'] == 'root' and entry['name'] != 'wayfinder_cli')
           for entry in graph['packages']):
        raise ValueError('Standalone graph contains a workspace, path or Git dependency.')


def execute(command: list[str], cwd: Path, environment: dict) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, env=environment, capture_output=True,
                          text=True, timeout=300)


def committed_bytes(root: Path, sha: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{sha}:{path}'], cwd=root)


def hosted_cli(root: Path, sha: str, logs: Path | None, runner=execute) -> Gate:
    """Stage the captured commit, never live workspace files or package config."""
    commands = []
    tracked = subprocess.check_output(
        ['git', 'ls-tree', '-rz', sha, '--', CLI.as_posix()], cwd=root)
    with tempfile.TemporaryDirectory(prefix='wayfinder-hosted-cli-') as temporary:
        stage = Path(temporary).resolve()
        if stage == root or root in stage.parents:
            raise ValueError('TMPDIR must be outside the source workspace.')
        for entry in tracked.split(b'\0'):
            if not entry:
                continue
            metadata, path = entry.decode().split('\t', 1)
            mode, kind, _ = metadata.split(' ')
            relative = path
            relative_package = Path(relative).relative_to(CLI)
            if kind != 'blob' or mode not in ('100644', '100755'):
                raise ValueError(f'Hosted preflight requires a regular Git file: {relative}')
            if relative_package.parts[0] in ('.dart_tool', 'build') or \
                    relative_package.name in ('pubspec.lock', 'pubspec_overrides.yaml'):
                raise ValueError(f'Unexpected tracked resolution/build state: {relative}')
            target = stage / relative_package
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(committed_bytes(root, sha, relative))
            target.chmod(0o755 if mode == '100755' else 0o644)
        pubspec = stage / 'pubspec.yaml'
        pubspec.write_text(standalone_pubspec(pubspec.read_text()))
        if (stage / '.dart_tool').exists():
            raise ValueError('Staged package already has a package configuration.')
        environment = dict(os.environ, PUB_HOSTED_URL='https://pub.dev')
        environment.pop('DART_PACKAGE_CONFIG', None)
        for name, command in [
            ('pub-get', ['dart', 'pub', 'get']),
            ('dependencies', ['dart', 'pub', 'deps', '--json']),
            ('analysis', ['dart', 'analyze', '--fatal-infos']),
            ('publish-dry-run', ['dart', 'pub', 'publish', '--dry-run']),
        ]:
            result = runner(command, stage, environment)
            log = None
            if logs:
                logs.mkdir(parents=True, exist_ok=True)
                log = logs / f'hosted-cli-{name}.log'
                log.write_text(result.stdout + result.stderr)
            commands.append({'command': command, 'exit_code': result.returncode,
                             'log': str(log) if log else None})
            if result.returncode:
                return Gate('hosted-cli', 'failed', f'Standalone CLI {name} failed.', commands)
            if name == 'dependencies':
                check_hosted_graph(json.loads(result.stdout))
    return Gate('hosted-cli', 'passed',
                'Standalone hosted CLI resolved, analyzed and passed publish --dry-run; no upload.', commands)


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def preflight(root: Path, ci_run_id: str | None, hosted_check: bool,
              logs: Path | None, published=published_versions, runner=execute) -> dict:
    sha = git(root, 'rev-parse', 'HEAD')
    dirty = git(root, 'status', '--porcelain', '--untracked-files=normal')
    gates = [Gate('source-tree', 'blocked' if dirty else 'passed',
                  'Commit the prepared candidate before release verification.' if dirty
                  else 'Checked source tree is clean.', {'head': sha})]

    def recheck_source() -> bool:
        current = git(root, 'rev-parse', 'HEAD')
        changed = git(root, 'status', '--porcelain', '--untracked-files=normal')
        if current != sha or changed:
            gates[0] = Gate('source-tree', 'blocked',
                            'Source HEAD or tracked/untracked files changed; rerun this preflight.',
                            {'head': sha, 'current_head': current})
            return False
        return True

    if ci_run_id:
        result = runner(['gh', 'api', f'repos/{REPOSITORY}/actions/runs/{ci_run_id}'],
                        root, dict(os.environ))
        if result.returncode:
            gates.append(Gate('source-ci', 'blocked', 'Could not read the supplied source CI run.'))
        else:
            gates.append(source_ci(json.loads(result.stdout), sha))
    else:
        gates.append(Gate('source-ci', 'blocked', 'Supply successful exact-source push/main CI with --ci-run-id.'))
    versions = {}
    for name in CLI_SIBLINGS:
        text = committed_bytes(root, sha, f'packages/{name}/pubspec.yaml').decode()
        match = re.search(r'^version: (\S+)$', text, re.M)
        if not match:
            raise ValueError(f'Cannot read checked {name} version.')
        versions[name] = match[1]
    try:
        dependencies = hosted_dependencies(versions, published)
    except (OSError, ValueError, KeyError) as error:
        dependencies = Gate('hosted-dependencies', 'blocked',
                            f'Cannot establish pub.dev availability: {error}')
    gates.append(dependencies)
    current_source = recheck_source()
    if dirty or not current_source or dependencies.status != 'passed' or not hosted_check:
        gates.append(Gate('hosted-cli', 'blocked',
                          'Requires a clean source, published siblings and --hosted-cli-check. '
                          'A workspace dry-run is not hosted-resolution evidence.'))
    else:
        gates.append(hosted_cli(root, sha, logs, runner))
    recheck_source()
    status = 'failed' if any(g.status == 'failed' for g in gates) else \
        'blocked' if any(g.status == 'blocked' for g in gates) else 'passed'
    return {'scope': 'Source-CI and hosted-CLI pre-publication preflight; not release completion.',
            'head': sha, 'status': status, 'gates': [asdict(g) for g in gates],
            'not_performed': ['package upload', 'tag creation', 'native publication',
                              'all-platform distribution verification', 'public installer verification']}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--ci-run-id')
    parser.add_argument('--hosted-cli-check', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.ci_run_id and not args.ci_run_id.isdecimal():
        parser.error('--ci-run-id must be numeric')
    logs = args.output.parent / (args.output.stem + '.logs') if args.output else None
    try:
        report = preflight(args.root.resolve(), args.ci_run_id, args.hosted_cli_check, logs)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report = {'status': 'failed', 'error': str(error)}
    rendered = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end='')
    return {'passed': 0, 'blocked': 2, 'failed': 1}[report['status']]


if __name__ == '__main__':
    raise SystemExit(main())
