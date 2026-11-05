#!/usr/bin/env python3
"""Require successful push/main source CI at the immutable publication SHA."""
import json
import os
from pathlib import Path
import subprocess
import sys

# publication.py sits beside this script and is not an installed package.
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from dataclasses import asdict  # noqa: E402

from publication import Gate, source_ci  # noqa: E402


def verify(runs, sha, repository):
    checks = [source_ci(run, sha, repository) for run in runs]
    return next(
        (check for check in checks if check.status == 'passed'),
        Gate(
            'source-ci',
            'blocked',
            'No successful push/main source CI names this publication commit.',
            [check.details for check in checks],
        ),
    )


def main():
    try:
        repository, sha = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA']
        endpoint = (
            f'repos/{repository}/actions/workflows/ci.yml/runs'
            f'?head_sha={sha}&event=push&branch=main&per_page=100'
        )
        runs = json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))
        gate = verify(runs['workflow_runs'], sha, repository)
    except (OSError, KeyError, ValueError, subprocess.SubprocessError) as error:
        gate = Gate('source-ci', 'blocked', f'Cannot establish source CI: {error}')
    print(json.dumps(asdict(gate)))
    return 0 if gate.status == 'passed' else 2


if __name__ == '__main__':
    raise SystemExit(main())
