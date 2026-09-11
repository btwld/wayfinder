"""Verify the three complete native release archives before publication."""
import argparse
import hashlib
from pathlib import Path
import re
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()
for platform in ['linux-x64', 'macos-arm64', 'windows-x64']:
    archive = args.directory / f'wayfinder-{platform}.tar.gz'
    checksum = archive.with_name(archive.name + '.sha256')
    expected = checksum.read_text().split()[0]
    digest = hashlib.sha256()
    with archive.open('rb') as data:
        for block in iter(lambda: data.read(1024 * 1024), b''):
            digest.update(block)
    if not re.fullmatch('[0-9a-f]{64}', expected) or digest.hexdigest() != expected:
        raise SystemExit(f'Archive checksum mismatch: {platform}')
    with tarfile.open(archive) as bundle:
        files = {}
        for member in bundle.getmembers():
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts or member.issym() or member.islnk():
                raise SystemExit(f'Unsafe archive member: {member.name}')
            if member.isfile():
                if member.name in files:
                    raise SystemExit(f'Duplicate archive member: {member.name}')
                files[member.name] = member
        executable = '.exe' if platform.startswith('windows') else ''
        required = ['SHA256SUMS', f'bin/wayfinder{executable}',
                    'models/embedding.gguf', 'models/manifest.json',
                    'licenses/objectbox/NOTICE', 'licenses/embedding_runtime/NOTICE',
                    'licenses/wayfinder/LICENSE', 'licenses/dart/packages.json',
                    'licenses/dart-sdk/LICENSE', 'LICENSE',
                    *[f'skills/{name}/SKILL.md' for name in [
                        'adopt-knowledge-bundle', 'assess-knowledge-bundle',
                        'author-knowledge-bundle', 'use-wayfinder']]]
        if any(name not in files for name in required):
            raise SystemExit(f'Incomplete native bundle: {platform}')
        manifest = bundle.extractfile(files['SHA256SUMS']).read().decode('utf-8')
        checked = set()
        for line in manifest.splitlines():
            expected_file, name = line.split('  ', 1)
            if name not in files or name in checked:
                raise SystemExit(f'Invalid manifest entry: {name}')
            actual = hashlib.sha256(bundle.extractfile(files[name]).read()).hexdigest()
            if actual != expected_file:
                raise SystemExit(f'Bundled file checksum mismatch: {name}')
            checked.add(name)
        if checked != set(files) - {'SHA256SUMS'}:
            raise SystemExit(f'Unverified files in {platform}')
    print(f'Verified {platform}')
