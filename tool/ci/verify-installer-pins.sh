#!/usr/bin/env bash
# The CLI pubspec, runtime version and plugin version name one prepared release,
# so update checks and plugin updates agree. Both public installers default to
# the same published release; a prepared version may be newer. Promote the
# defaults only after its archives are verified.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$root" <<'PY'
from pathlib import Path
import json, re, sys
root = Path(sys.argv[1])
def text(file):
    return (root / file).read_text()
def value(file, pattern):
    match = re.search(pattern, text(file), re.M)
    if not match:
        raise SystemExit(f'Missing version in {file}')
    return match[1]
def precedence(version):
    core, _, prerelease = version.partition('-')
    return tuple(map(int, core.split('.'))), not prerelease, prerelease
package = value('packages/wayfinder_cli/pubspec.yaml', r'^version: (.+)$')
runtime = value('packages/wayfinder_cli/lib/src/version.dart',
                r"^const wayfinderVersion = '([^']+)';$")
plugin = json.loads(text('.claude-plugin/plugin.json'))['version']
if runtime != package or plugin != package:
    raise SystemExit(f'Versions differ: pubspec={package}, runtime={runtime}, plugin={plugin}')
shell = value('tool/install.sh', r'^version="\$\{WAYFINDER_VERSION:-([^}]+)\}"$')
powershell = value('tool/install.ps1', r"^\$WayfinderVersion = '([^']+)'$")
if shell != powershell:
    raise SystemExit(f'Installer defaults differ: shell={shell}, PowerShell={powershell}')
if precedence(shell) > precedence(package):
    raise SystemExit(f'Installer default {shell} is newer than the prepared package {package}')
if 'WAYFINDER_VERSION' not in text('tool/install.sh') or '$env:WAYFINDER_VERSION' not in text('tool/install.ps1'):
    raise SystemExit('Both installers must honor WAYFINDER_VERSION for CI')
print(f'Installer defaults {shell}; prepared package {package}')
PY
