#!/usr/bin/env python3
"""Decide which CI jobs a diff must run, and whether the required check passes.

Heavy jobs skip in two cases. A draft pull request has not asked for them
yet. A diff that is only non-code does not exercise them. The required
check still finishes: GitHub counts a skipped required check as success, so
a draft has to fail this check instead of skipping it. ``ready_for_review``
starts a new run in which the draft flag is clear.

Non-code is documentation, a readme, a license, an issue or pull-request
template, or a non-build asset. These stay code even when the filename
looks like documentation, because CI reads them:

- ``docs/schemas/`` is the published contract ``--check`` compares
- ``examples/`` bundles and profiles are validated, except a readme or license
- Profile ``skill/`` text is compared to the package vocabulary
- ``test``, ``tests``, ``goldens``, ``fixtures``, and Profile ``versions/``
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys


ASSET_SUFFIXES = {
    '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.ico', '.icns',
    '.bmp', '.tif', '.tiff', '.ttf', '.otf', '.woff', '.woff2', '.pdf',
}
MARKDOWN_SUFFIXES = {'.md', '.markdown', '.mdx'}
CODE_DIRECTORY_NAMES = {'test', 'tests', 'goldens', 'fixtures'}
INSTALLER_FILES = frozenset({
    '.github/workflows/installer-scripts.yml',
    'tool/install.ps1',
    'tool/install.sh',
    'tool/test_install_arch.ps1',
    'tool/test_install_platform.sh',
    'tool/verify_installer.ps1',
})
PUBLIC_INSTALL_FILES = frozenset({
    '.github/workflows/verify-public-install.yml',
    'tool/verify_public_install.py',
    'tool/install.sh',
    'tool/install.ps1',
})


def normalize(path: str) -> str:
    """Repo-relative POSIX path, without a leading ``./``."""
    text = path.replace('\\', '/').strip()
    while text.startswith('./'):
        text = text[2:]
    return text


def _name(path: str) -> str:
    return path.rsplit('/', 1)[-1].casefold()


def _suffix(path: str) -> str:
    name = _name(path)
    dot = name.rfind('.')
    return name[dot:] if dot > 0 else ''


def _readme_or_license(path: str) -> bool:
    name = _name(path)
    if name in {'readme', 'license', 'licence', 'copying'}:
        return True
    return name.startswith(('readme.', 'license.', 'licence.', 'copying.'))


def _template(path: str) -> bool:
    return (
        path.startswith('.github/ISSUE_TEMPLATE/')
        or path.startswith('.github/PULL_REQUEST_TEMPLATE/')
        or path == '.github/pull_request_template.md'
    )


def _forced_code(path: str) -> bool:
    if path.startswith('docs/schemas/'):
        return True
    if path.startswith('examples/') and not _readme_or_license(path):
        return True
    if path.startswith('profiles/') and (
        '/skill/' in f'/{path}' or '/versions/' in f'/{path}'
    ):
        return True
    return any(part in CODE_DIRECTORY_NAMES for part in path.split('/'))


def is_non_code(path: str) -> bool:
    """Whether one changed path can skip heavy CI by itself."""
    relative = normalize(path)
    if not relative or _forced_code(relative):
        return False
    if relative.startswith('docs/') or _template(relative):
        return True
    if _suffix(relative) in MARKDOWN_SUFFIXES or _readme_or_license(relative):
        return True
    return _suffix(relative) in ASSET_SUFFIXES


def is_code(path: str) -> bool:
    return not is_non_code(path)


def _zero_sha(value: str) -> bool:
    return not value or set(value) <= {'0'}


def should_run(paths: list[str] | None, mode: str) -> bool:
    """Whether the heavy jobs for ``mode`` must run.

    ``None`` means the base commit is missing. Run the work rather than
    guess that the diff was empty.
    """
    if paths is None:
        return True
    if mode == 'code':
        return not paths or any(is_code(path) for path in paths)
    watched = INSTALLER_FILES if mode == 'installer' else PUBLIC_INSTALL_FILES
    if mode not in {'installer', 'public-install'}:
        raise ValueError(f'Unknown classification mode: {mode}')
    return any(normalize(path) in watched for path in paths)


def changed_paths(base: str, head: str, dots: str) -> list[str] | None:
    """Paths touched between ``base`` and ``head``, or ``None`` if ``base`` is unusable."""
    if dots not in {'..', '...'}:
        raise ValueError(f'Unsupported diff dots: {dots}')
    if _zero_sha(base) or _zero_sha(head):
        return None
    result = subprocess.run(
        ['git', 'diff', '--name-status', '--find-renames', f'{base}{dots}{head}'],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(detail or 'git diff failed')
    paths = []
    for line in result.stdout.splitlines():
        parts = line.split('\t')
        paths.extend(normalize(path) for path in parts[1:] if path)
    return paths


def evaluate(
    *,
    draft: bool,
    changes: str,
    run: bool,
    results: dict[str, str],
    may_skip: set[str],
) -> tuple[str, str]:
    """Return ``passed`` or ``failed`` and the line the required check prints.

    A draft fails even when every heavy job succeeded. Those jobs are
    supposed to be skipped, and a green draft would satisfy branch
    protection before ``ready_for_review`` runs them.
    """
    if draft:
        return (
            'failed',
            'Draft pull requests do not satisfy required checks. '
            'Heavy jobs stay skipped until the pull request is marked ready '
            'for review. A skipped required check would count as success.',
        )
    if changes != 'success':
        return ('failed', f'Change classification did not succeed ({changes}).')
    bad = {
        name: result
        for name, result in results.items()
        if result not in {'success', 'skipped'}
    }
    if bad:
        return ('failed', f'Jobs did not succeed: {_format(bad)}.')
    if run:
        missing = {
            name: result
            for name, result in results.items()
            if name not in may_skip and result != 'success'
        }
        if missing:
            return ('failed', f'Required jobs did not succeed: {_format(missing)}.')
        return ('passed', 'Required jobs succeeded.')
    return (
        'passed',
        'Heavy jobs were skipped. This required check still reports success.',
    )


def _format(results: dict[str, str]) -> str:
    return ', '.join(f'{name}={result}' for name, result in sorted(results.items()))


def _write_output(name: str, value: str) -> None:
    line = f'{name}={value}'
    print(line)
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write(line + '\n')


def _parse_results(raw: str) -> dict[str, str]:
    results = {}
    for item in raw.split(','):
        item = item.strip()
        if not item:
            continue
        name, separator, value = item.partition('=')
        if not separator or not name:
            raise ValueError(f'Expected name=result in RESULTS, got {item!r}.')
        results[name] = value
    return results


def classify_from_env(mode: str) -> int:
    paths = changed_paths(
        os.environ.get('BASE_SHA', ''),
        os.environ.get('HEAD_SHA', ''),
        os.environ.get('DIFF_DOTS', '..'),
    )
    run = should_run(paths, mode)
    if paths is None:
        print('Base commit is unavailable; heavy jobs will run.')
    else:
        print(f'{len(paths)} changed path(s).')
        for path in paths:
            print(f'{"code" if is_code(path) else "non-code"}\t{path}')
    _write_output('run', 'true' if run else 'false')
    return 0


def require_from_env() -> int:
    status, message = evaluate(
        draft=os.environ.get('DRAFT', 'false') == 'true',
        changes=os.environ['CHANGES'],
        run=os.environ.get('RUN', '') == 'true',
        results=_parse_results(os.environ.get('RESULTS', '')),
        may_skip={
            item.strip()
            for item in os.environ.get('MAY_SKIP', '').split(',')
            if item.strip()
        },
    )
    print(message)
    return 0 if status == 'passed' else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--mode',
        choices=('code', 'installer', 'public-install'),
        help='Which heavy jobs the diff can skip.',
    )
    parser.add_argument(
        '--require',
        action='store_true',
        help='Exit from the draft and heavy-job results in the environment.',
    )
    args = parser.parse_args(argv)
    try:
        if args.require:
            return require_from_env()
        if not args.mode:
            parser.error('--mode is required unless --require is set')
        return classify_from_env(args.mode)
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(f'Change classification failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
