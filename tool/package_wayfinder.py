"""Archive a complete native bundle and write its SHA-256 download checksum."""
import argparse
import hashlib
from pathlib import Path
import tarfile

def sha256_file(file):
    digest = hashlib.sha256()
    with file.open('rb') as data:
        for block in iter(lambda: data.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('bundle', type=Path)
parser.add_argument('archive', type=Path)
args = parser.parse_args()
bundle = args.bundle.resolve()
archive = args.archive.resolve()
if bundle == archive or bundle in archive.parents:
    parser.error('Archive must be outside the bundle')
for name in ['LICENSE', 'models/embedding.gguf', 'models/manifest.json',
             'licenses/objectbox/NOTICE', 'licenses/okf_profile/LICENSE']:
    if not (bundle / name).is_file():
        parser.error(f'Incomplete bundle: {name}')
for command in ['wayfinder', 'okfp']:
    if not any((bundle / 'bin' / (command + suffix)).is_file()
               for suffix in ['', '.exe']):
        parser.error(f'Incomplete bundle: {command}')
entries = []
for file in sorted(bundle.rglob('*')):
    if file.is_symlink():
        parser.error(f'Bundle must contain regular files: {file}')
    if file.is_file() and file.name != 'SHA256SUMS':
        digest = sha256_file(file)
        entries.append(f'{digest}  {file.relative_to(bundle).as_posix()}\n')
(bundle / 'SHA256SUMS').write_text(''.join(entries), encoding='utf-8')
archive.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(archive, 'w:gz') as output:
    for file in sorted(bundle.iterdir()):
        output.add(file, arcname=file.name)
digest = sha256_file(archive)
archive.with_name(archive.name + '.sha256').write_text(
    f'{digest}  {archive.name}\n', encoding='utf-8')
print(archive)
