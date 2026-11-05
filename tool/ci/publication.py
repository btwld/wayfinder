"""Importable release checks shared by the publication scripts.

`listed_versions` is every version pub.dev returns, including retracted
ones. `published_versions` is the set a dependent can resolve, so retracted
versions are absent. Those are different questions; do not merge them.
`standalone_pubspec` accepts this repository's plain top-level key layout
and fails closed on anything else. It is not a YAML parser.
"""

from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from typing import NamedTuple
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = 'btwld/wayfinder'
CLI = Path('packages/wayfinder_cli')


class WorkspacePackage(NamedTuple):
    member: str
    version: str
    dependencies: dict[str, str]


def dependencies(text: str) -> dict[str, str]:
    """Each direct dependency and its inline constraint; "" for a map form."""
    match = re.search(r'^dependencies:\n((?:[ \t]+.*\n|\n)*)', text, re.M)
    return dict(re.findall(r'^  (\w+):[ \t]*(.*?)[ \t]*$', match[1], re.M)) if match else {}


def unreleased(changelog: Path) -> bool:
    """Whether `# Unreleased` or `# <version> (unreleased)` lists changes."""
    match = re.search(
        r'^# (?:Unreleased|\S+ \(unreleased\))\n(.*?)(?=^# |\Z)',
        changelog.read_text(),
        re.M | re.S,
    )
    return bool(match and match[1].strip())


def _version_entries(name: str) -> list:
    try:
        with urllib.request.urlopen(
            f'https://pub.dev/api/packages/{name}', timeout=30
        ) as response:
            return json.load(response)['versions']
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return []
        raise


def listed_versions(name: str) -> set[str]:
    """Every version pub.dev lists, including retracted ones."""
    return {entry['version'] for entry in _version_entries(name)}


def published_versions(name: str) -> set[str]:
    """Versions a dependent can resolve. Retracted versions are absent."""
    return {
        entry['version']
        for entry in _version_entries(name)
        if not entry.get('retracted', False)
    }


def workspace_packages(root: Path, *, read_text=Path.read_text) -> dict[str, WorkspacePackage]:
    members = re.findall(r'^  - (\S+)$', read_text(root / 'pubspec.yaml'), re.M)
    packages = {}
    for member in members:
        pubspec = root / member / 'pubspec.yaml'
        text = read_text(pubspec)
        name = re.search(r'^name: (\S+)$', text, re.M)
        version = re.search(r'^version: (\S+)$', text, re.M)
        if not name or not version:
            raise ValueError(f'Cannot read name/version from {pubspec}.')
        packages[name[1]] = WorkspacePackage(member, version[1], dependencies(text))
    return packages


def sibling_versions(package: str, root: Path = ROOT, *, read_text=Path.read_text) -> dict[str, str]:
    packages = workspace_packages(root, read_text=read_text)
    if package not in packages:
        raise ValueError(f'Unknown workspace package: {package}')
    own = packages[package].dependencies
    return {name: packages[name].version for name in sorted(own) if name in packages}


def missing_siblings(versions: dict[str, str], published=published_versions) -> list[str]:
    return [
        f'{name} {version}'
        for name, version in versions.items()
        if version not in published(name)
    ]


@dataclass
class Gate:
    name: str
    status: str
    message: str
    details: object = None


def source_ci(run: dict, sha: str, repository: str = REPOSITORY) -> Gate:
    """PR CI is candidate evidence, not release-eligible push/main evidence."""
    details = {
        'url': run.get('html_url'),
        'event': run.get('event'),
        'head_sha': run.get('head_sha'),
    }
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
        return Gate(
            'source-ci',
            'blocked',
            'Successful candidate CI is not release-eligible push/main CI.',
            details,
        )
    return Gate(
        'source-ci', 'passed', 'Successful push/main CI names this exact commit.', details
    )


def hosted_dependencies(versions: dict[str, str], published) -> Gate:
    missing = missing_siblings(versions, published)
    if missing:
        return Gate(
            'hosted-dependencies',
            'blocked',
            'Publish the CLI sibling versions in dependency order before hosted resolution.',
            {'unpublished': missing},
        )
    return Gate(
        'hosted-dependencies',
        'passed',
        'All exact CLI sibling versions are available on pub.dev.',
        versions,
    )


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


def check_hosted_graph(graph: dict, versions: dict[str, str]) -> None:
    packages = {entry['name']: entry for entry in graph['packages']}
    if graph.get('root') != 'wayfinder_cli':
        raise ValueError('Dependency graph is not the staged standalone CLI.')
    for name, version in versions.items():
        if packages.get(name, {}).get('source') != 'hosted':
            raise ValueError(f'{name} did not resolve from a hosted source.')
        if packages[name].get('version') != version:
            raise ValueError(f'{name} did not resolve to prepared version {version}.')
    if any(
        entry['source'] not in ('root', 'hosted', 'sdk')
        or (entry['source'] == 'root' and entry['name'] != 'wayfinder_cli')
        for entry in graph['packages']
    ):
        raise ValueError('Standalone graph contains a workspace, path or Git dependency.')


def execute(command: list[str], cwd: Path, environment: dict) -> subprocess.CompletedProcess:
    return subprocess.run(
        command, cwd=cwd, env=environment, capture_output=True, text=True, timeout=300
    )


def committed_bytes(root: Path, sha: str, path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{sha}:{path}'], cwd=root)


def hosted_cli(
    root: Path, sha: str, logs: Path | None, runner=execute, *, versions: dict[str, str]
) -> Gate:
    """Stage the captured commit, never live workspace files or package config."""
    commands = []
    try:
        tracked = subprocess.check_output(
            ['git', 'ls-tree', '-rz', sha, '--', CLI.as_posix()], cwd=root
        )
        with tempfile.TemporaryDirectory(prefix='wayfinder-hosted-cli-') as temporary:
            stage = Path(temporary).resolve()
            if stage == root or root in stage.parents:
                raise ValueError('TMPDIR must be outside the source workspace.')
            for entry in tracked.split(b'\0'):
                if not entry:
                    continue
                metadata, path = entry.decode().split('\t', 1)
                mode, kind, _ = metadata.split(' ')
                relative_package = Path(path).relative_to(CLI)
                if kind != 'blob' or mode not in ('100644', '100755'):
                    raise ValueError(f'Hosted preflight requires a regular Git file: {path}')
                if relative_package.parts[0] in ('.dart_tool', 'build') or relative_package.name in (
                    'pubspec.lock',
                    'pubspec_overrides.yaml',
                ):
                    raise ValueError(f'Unexpected tracked resolution/build state: {path}')
                target = stage / relative_package
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(committed_bytes(root, sha, path))
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
                commands.append(
                    {
                        'command': command,
                        'exit_code': result.returncode,
                        'log': str(log) if log else None,
                    }
                )
                if result.returncode:
                    return Gate('hosted-cli', 'failed', f'Standalone CLI {name} failed.', commands)
                if name == 'dependencies':
                    check_hosted_graph(json.loads(result.stdout), versions)
        return Gate(
            'hosted-cli',
            'passed',
            'Standalone hosted CLI resolved, analyzed and passed publish --dry-run; no upload.',
            commands,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return Gate(
            'hosted-cli', 'blocked', f'Hosted verification could not run: {error}', commands
        )


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def prepared_versions(root: Path, sha: str) -> dict[str, str]:
    return sibling_versions(
        'wayfinder_cli',
        root,
        read_text=lambda path: committed_bytes(
            root, sha, path.relative_to(root).as_posix()
        ).decode(),
    )


def preflight(
    root: Path,
    ci_run_id: str | None,
    hosted_check: bool,
    logs: Path | None,
    published=published_versions,
    runner=execute,
) -> dict:
    sha = git(root, 'rev-parse', 'HEAD')
    dirty = git(root, 'status', '--porcelain', '--untracked-files=normal')
    gates = [
        Gate(
            'source-tree',
            'blocked' if dirty else 'passed',
            'Commit the prepared candidate before release verification.'
            if dirty
            else 'Checked source tree is clean.',
            {'head': sha},
        )
    ]

    def recheck_source() -> bool:
        current = git(root, 'rev-parse', 'HEAD')
        changed = git(root, 'status', '--porcelain', '--untracked-files=normal')
        if current != sha or changed:
            gates[0] = Gate(
                'source-tree',
                'blocked',
                'Source HEAD or tracked/untracked files changed; rerun this preflight.',
                {'head': sha, 'current_head': current},
            )
            return False
        return True

    if ci_run_id:
        try:
            result = runner(
                ['gh', 'api', f'repos/{REPOSITORY}/actions/runs/{ci_run_id}'],
                root,
                dict(os.environ),
            )
            if result.returncode:
                gates.append(Gate('source-ci', 'blocked', 'Could not read the supplied source CI run.'))
            else:
                gates.append(source_ci(json.loads(result.stdout), sha))
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            gates.append(Gate('source-ci', 'blocked', f'Could not establish source CI: {error}'))
    else:
        gates.append(
            Gate(
                'source-ci',
                'blocked',
                'Supply successful exact-source push/main CI with --ci-run-id.',
            )
        )
    try:
        versions = prepared_versions(root, sha)
    except (ValueError, KeyError) as error:
        dependencies_gate = Gate(
            'hosted-dependencies', 'failed', f'Invalid committed sibling metadata: {error}'
        )
    except (OSError, subprocess.SubprocessError) as error:
        dependencies_gate = Gate(
            'hosted-dependencies', 'blocked', f'Cannot read committed sibling metadata: {error}'
        )
    else:
        try:
            dependencies_gate = hosted_dependencies(versions, published)
        except (OSError, ValueError, KeyError) as error:
            dependencies_gate = Gate(
                'hosted-dependencies', 'blocked', f'Cannot establish pub.dev availability: {error}'
            )
    gates.append(dependencies_gate)
    current_source = recheck_source()
    if dirty or not current_source or dependencies_gate.status != 'passed' or not hosted_check:
        gates.append(
            Gate(
                'hosted-cli',
                'blocked',
                'Requires a clean source, published siblings and --hosted-cli-check. '
                'A workspace dry-run is not hosted-resolution evidence.',
            )
        )
    else:
        try:
            gates.append(hosted_cli(root, sha, logs, runner, versions=versions))
        except (ValueError, KeyError) as error:
            gates.append(Gate('hosted-cli', 'failed', str(error)))
    recheck_source()
    status = (
        'failed'
        if any(gate.status == 'failed' for gate in gates)
        else 'blocked'
        if any(gate.status == 'blocked' for gate in gates)
        else 'passed'
    )
    return {
        'scope': 'Source-CI and hosted-CLI pre-publication preflight; not release completion.',
        'head': sha,
        'status': status,
        'gates': [asdict(gate) for gate in gates],
        'not_performed': [
            'package upload',
            'tag creation',
            'native publication',
            'all-platform distribution verification',
            'public installer verification',
        ],
    }
