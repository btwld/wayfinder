#!/usr/bin/env bash
# The CLI pubspec, runtime version and plugin version name one prepared release,
# so update checks and plugin updates agree. Public installers resolve the
# newest stable release at install time instead of pinning a default.
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
package = value('packages/wayfinder_cli/pubspec.yaml', r'^version: (.+)$')
runtime = value('packages/wayfinder_cli/lib/src/version.dart',
                r"^const wayfinderVersion = '([^']+)';$")
plugin = json.loads(text('.claude-plugin/plugin.json'))['version']
if runtime != package or plugin != package:
    raise SystemExit(f'Versions differ: pubspec={package}, runtime={runtime}, plugin={plugin}')
# Installers resolve the newest stable release at install time; a pinned
# default would silently hold every new install back.
if 'version="${WAYFINDER_VERSION:-}"' not in text('tool/install.sh'):
    raise SystemExit('install.sh must default to the latest release and honor WAYFINDER_VERSION')
if '$WayfinderVersion = $env:WAYFINDER_VERSION' not in text('tool/install.ps1'):
    raise SystemExit('install.ps1 must default to the latest release and honor WAYFINDER_VERSION')
print(f'Installers resolve the latest release; prepared package {package}')
PY
