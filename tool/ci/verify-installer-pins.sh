#!/usr/bin/env bash
# Both native installers must install the application version built by this tree.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$root" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
def value(file, pattern):
    match = re.search(pattern, (root / file).read_text(), re.M)
    if not match:
        raise SystemExit(f'Missing version in {file}')
    return match[1]
package = value('packages/wayfinder_cli/pubspec.yaml', r'^version: (.+)$')
shell = value('tool/install.sh', r'^version="([^"]+)"$')
powershell = value('tool/install.ps1', r"^\$WayfinderVersion = '([^']+)'$")
if package != shell or package != powershell:
    raise SystemExit(f'Version mismatch: package={package}, shell={shell}, PowerShell={powershell}')
print(f'Installers match Wayfinder {package}')
PY
