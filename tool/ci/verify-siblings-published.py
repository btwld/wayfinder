#!/usr/bin/env python3
"""Require a package's exact workspace dependencies to be available on pub.dev."""
import argparse
import json
from pathlib import Path
import runpy
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
FLOORS = runpy.run_path(str(Path(__file__).with_name('verify-workspace-floors.py')))


def sibling_versions(package: str, root: Path = ROOT, *, read_text=Path.read_text) -> dict[str, str]:
    packages = FLOORS['workspace_packages'](root, read_text=read_text)
    if package not in packages:
        raise ValueError(f'Unknown workspace package: {package}')
    dependencies = packages[package][2]
    return {name: packages[name][1] for name in sorted(dependencies) if name in packages}


def published_versions(name: str) -> set[str]:
    try:
        with urllib.request.urlopen(f'https://pub.dev/api/packages/{name}', timeout=30) as response:
            return {entry['version'] for entry in json.load(response)['versions']
                    if not entry.get('retracted', False)}
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return set()
        raise


def missing_siblings(versions: dict[str, str], published=published_versions) -> list[str]:
    return [f'{name} {version}' for name, version in versions.items()
            if version not in published(name)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package')
    args = parser.parse_args()
    missing = missing_siblings(sibling_versions(args.package))
    if missing:
        parser.exit(1, 'Unpublished or retracted siblings: ' + ', '.join(missing) +
                    '. Publish them first, then rerun the same immutable tag.\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
