#!/usr/bin/env python3
"""Require successful push/main source CI at the immutable publication SHA."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location(
    'release_preflight', Path(__file__).with_name('release-preflight.py'))
preflight = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = preflight
SPEC.loader.exec_module(preflight)


def verify(runs, sha, repository):
    checks = [preflight.source_ci(run, sha, repository) for run in runs]
    return next((check for check in checks if check.status == 'passed'),
                preflight.Gate('source-ci', 'blocked',
                               'No successful push/main source CI names this publication commit.',
                               [check.details for check in checks]))


def main():
    try:
        repository, sha = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA']
        endpoint = (f'repos/{repository}/actions/workflows/ci.yml/runs'
                    f'?head_sha={sha}&event=push&branch=main&per_page=100')
        runs = json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))
        gate = verify(runs['workflow_runs'], sha, repository)
    except (OSError, KeyError, ValueError, subprocess.SubprocessError) as error:
        gate = preflight.Gate('source-ci', 'blocked', f'Cannot establish source CI: {error}')
    print(json.dumps(preflight.asdict(gate)))
    return 0 if gate.status == 'passed' else 2


if __name__ == '__main__':
    raise SystemExit(main())
