"""Run the POSIX installer with real native assets and a local download fixture."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
args = parser.parse_args()
archive = args.archive.resolve()
workspace = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='wayfinder install ') as temporary:
    root = Path(temporary)
    downloads = root / 'downloads'
    downloads.mkdir()
    for source in [archive, archive.with_name(archive.name + '.sha256')]:
        shutil.copy2(source, downloads / source.name)
    shim = root / 'shim'
    shim.mkdir()
    curl = shim / 'curl'
    curl.write_text('''#!/bin/sh
set -eu
url= destination=
while [ "$#" -gt 0 ]; do
  case "$1" in
    https://*) url="$1"; shift ;;
    -o) destination="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$WAYFINDER_TEST_DOWNLOADS/${url##*/}" "$destination"
''')
    curl.chmod(0o755)
    env = dict(os.environ,
               PATH=f'{shim}:/usr/bin:/bin:/usr/sbin:/sbin',
               WAYFINDER_TEST_DOWNLOADS=str(downloads),
               WAYFINDER_INSTALL_ROOT=str(root / 'runtime'),
               WAYFINDER_INSTALL_DIR=str(root / 'commands'),
               WAYFINDER_DATA_DIR=str(root / 'data'))
    if shutil.which('dart', path=env['PATH']):
        raise RuntimeError('Probe PATH must not contain Dart')
    for name in ['WAYFINDER_EMBEDDING_MODEL', 'KNOWLEDGE_EMBEDDING_MODEL']:
        env.pop(name, None)
    def install(expected=0):
        result = subprocess.run(['/bin/sh', str(workspace / 'tool/install.sh')],
                                env=env, capture_output=True, text=True, timeout=120)
        if result.returncode != expected:
            raise AssertionError((result.returncode, result.stdout, result.stderr))
    install()
    binary = root / 'commands/wayfinder'
    corpus = workspace / 'packages/wayfinder_cli/test/fixtures/knowledge'
    def command(*arguments):
        return subprocess.run([str(binary), *map(str, arguments)], env=env,
                              cwd=root, capture_output=True, text=True,
                              check=True, timeout=120)
    first = json.loads(command('index', corpus, '--output=json').stdout)
    assert first['embeddedChunks'] > 0
    command('search', corpus, 'password', '--output=json')
    # Reinstall repairs a missing model and preserves existing retrieval data.
    installed = binary.resolve().parent.parent
    (installed / 'models/embedding.gguf').unlink()
    install()
    repeated = json.loads(command('index', corpus, '--output=json').stdout)
    assert repeated['embeddedChunks'] == 0
    previous = binary.resolve()
    # A bad download checksum must leave the working commands intact.
    checksum = downloads / (archive.name + '.sha256')
    checksum.write_text('0' * 64 + '  ' + archive.name + '\n')
    install(expected=1)
    assert binary.resolve() == previous
    command('search', corpus, 'password', '--output=json')
    command('validate', workspace / 'examples/knowledge')
    assert not (root / 'commands/okfp').exists()
    print('PASS: no-Dart install, quoted paths, retrieval, repair, index reuse, corrupt download refusal.')
