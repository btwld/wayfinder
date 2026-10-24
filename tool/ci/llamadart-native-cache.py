"""Print the path and key that cache llamadart's native downloads in CI.

llamadart's build hook downloads its pinned llamadart-native release into the
resolved llamadart package, under .dart_tool/llamadart/native_bundles/, and
checks each archive against the SHA-256 it pins. A later build reuses the
extracted libraries there without hashing them again, so the key names the
llamadart version and its native release exactly, and a restored cache never
stands in for another release. Run it from the workspace after `dart pub get`;
it appends `path=` and `key=` lines to $GITHUB_OUTPUT, or prints them.
"""
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request

root = Path(__file__).resolve().parents[2]
config_file = root / '.dart_tool' / 'package_config.json'
config = json.loads(config_file.read_text(encoding='utf-8'))
uri = next((entry['rootUri'] for entry in config['packages']
            if entry['name'] == 'llamadart'), None)
if uri is None:
    raise SystemExit('llamadart is not in the package configuration')
if uri.startswith('file:'):
    package = Path(urllib.request.url2pathname(urllib.parse.urlparse(uri).path))
else:
    package = (config_file.parent / urllib.parse.unquote(uri)).resolve()
version = re.search(r'^version:\s*(\S+)\s*$',
                    (package / 'pubspec.yaml').read_text(encoding='utf-8'),
                    re.MULTILINE)
pins = package / 'lib' / 'src' / 'hook' / 'native_release_pins.dart'
tag = re.search(r"^const llamaCppTag = '([^']+)';",
                pins.read_text(encoding='utf-8'), re.MULTILINE)
if version is None or tag is None:
    raise SystemExit(f'Cannot read the llamadart version or its native release '
                     f'from {package}')
lines = [
    f'path={package / ".dart_tool" / "llamadart" / "native_bundles"}',
    f'key=llamadart-{version[1]}-native-{tag[1]}',
]
output = os.environ.get('GITHUB_OUTPUT')
if output:
    with open(output, 'a', encoding='utf-8') as file:
        file.write(''.join(f'{line}\n' for line in lines))
else:
    print('\n'.join(lines))
