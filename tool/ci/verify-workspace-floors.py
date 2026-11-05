#!/usr/bin/env python3
"""Keep sibling dependency floors resolvable outside the workspace.

Workspace resolution always links a sibling's source, so a floor that admits
an older published release builds here and fails for a consumer who resolves
that release. Two rules close the gap. A dependent's floor is the sibling's
own version. A sibling with unreleased changes carries a version pub.dev does
not have yet, so that floor can only resolve to the source it was tested on.
"""

from pathlib import Path
import sys

# publication.py sits beside this script and is not an installed package.
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from publication import (  # noqa: E402
    ROOT,
    listed_versions,
    unreleased,
    workspace_packages,
)


def main() -> int:
    packages = workspace_packages(ROOT)
    failures = []
    depended = set()
    for package in packages.values():
        for name, constraint in package.dependencies.items():
            if name not in packages:
                continue
            depended.add(name)
            if constraint != f'^{packages[name].version}':
                failures.append(
                    f"{package.member}: {name} {constraint or '<map form>'}; "
                    f'expected ^{packages[name].version}'
                )
    for name in sorted(depended):
        member, version = packages[name].member, packages[name].version
        if unreleased(ROOT / member / 'CHANGELOG.md') and version in listed_versions(name):
            failures.append(
                f'{member}: unreleased changes on {version}, which pub.dev already has; '
                'raise the version'
            )
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
