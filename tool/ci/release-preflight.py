#!/usr/bin/env python3
"""Read-only pre-publication checks; this never tags, uploads or dispatches CI.

Exit 0: these preflight gates passed (not release completion).
Exit 2: external prerequisites or an explicitly requested check are missing.
Exit 1: a check failed. JSON and command logs retain that distinction.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys

# publication.py sits beside this script and is not an installed package.
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from publication import (  # noqa: E402
    CLI,
    ROOT,
    git,
    hosted_cli,
    missing_siblings,
    preflight,
    published_versions,
    sibling_versions,
    source_ci,
    standalone_pubspec,
    workspace_packages,
)


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
    except (OSError, subprocess.SubprocessError) as error:
        report = {'status': 'blocked', 'error': str(error), 'gates': []}
    except (ValueError, KeyError) as error:
        report = {'status': 'failed', 'error': str(error), 'gates': []}
    rendered = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end='')
    return {'passed': 0, 'blocked': 2, 'failed': 1}[report['status']]


if __name__ == '__main__':
    raise SystemExit(main())
