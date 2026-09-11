"""Build a public documentation/plugin projection without copying source history."""
import argparse
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('destination', type=Path)
parser.add_argument('--tag', required=True)
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
destination = args.destination.resolve()
if destination == source or destination in source.parents:
    parser.error('Destination must not contain the source checkout')
destination.mkdir(parents=True, exist_ok=True)
# Explicit public document allowlist. No package source, fixtures, repository
# configuration, .context, credentials, client material or git history is copied.
for name in ['skills', '.claude-plugin', 'profile', 'implementation']:
    target = destination / name
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source / name, target)
for relative in ['tool/install.sh', 'tool/install.ps1', 'docs/install.md', 'docs/compatibility-review.md', 'LICENSE']:
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / relative, target)
readme = (source / 'tool/dist/README.md').read_text()
readme = readme.replace('{{TAG}}', args.tag).replace('{{SOURCE_REPO}}', 'conceptadev/wayfinder')
(destination / 'README.md').write_text(readme)
manifest = destination / '.claude-plugin/plugin.json'
plugin = json.loads(manifest.read_text())
plugin['homepage'] = 'https://github.com/conceptadev/wayfinder-dist'
plugin['repository'] = 'https://github.com/conceptadev/wayfinder-dist'
manifest.write_text(json.dumps(plugin, indent=2) + '\n')
print(destination)
