#!/usr/bin/env bash
# Public installer defaults stay on the last published working release until
# stable archives exist. CI sets WAYFINDER_VERSION to test the prepared package.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$root" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
def text(file):
    return (root / file).read_text()
def value(file, pattern):
    match = re.search(pattern, text(file), re.M)
    if not match:
        raise SystemExit(f'Missing version in {file}')
    return match[1]
package = value('packages/wayfinder_cli/pubspec.yaml', r'^version: (.+)$')
shell = value('tool/install.sh', r'^version="\$\{WAYFINDER_VERSION:-([^}]+)\}"$')
powershell = value('tool/install.ps1', r"^\$WayfinderVersion = '([^']+)'$")
published = '0.0.1-dev.1'
if shell != published or powershell != published:
    raise SystemExit(
        f'Public installer defaults must stay on {published} until 0.0.1 '
        f'archives are published: shell={shell}, PowerShell={powershell}'
    )
if 'WAYFINDER_VERSION' not in text('tool/install.sh') or '$env:WAYFINDER_VERSION' not in text('tool/install.ps1'):
    raise SystemExit('Both installers must honor WAYFINDER_VERSION for CI')
print(f'Installer defaults {published}; prepared package {package}')
PY
