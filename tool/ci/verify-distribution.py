"""Verify the three complete native release archives before publication."""
import argparse
import hashlib
from pathlib import Path
import re
import tarfile

# llamadart's build hook bundles llama.cpp for the CPU only, as the workspace's
# hooks.user_defines selects: no GPU backend module, CUDA runtime, LiteRT-LM or
# stable-diffusion library may reach a release.
FOREIGN_RUNTIME = re.compile(
    r'^(?:ggml-(?:vulkan|cuda|hip|opencl|blas|metal|sycl|cann|musa|rpc)\b'
    r'|cu(?:dart|blas|blaslt)64'
    r'|.*litert|.*webgpu_dawn|dxcompiler|dxil|gemmamodelconstraintprovider'
    r'|.*stable[-_]?diffusion)')
NATIVE_LIBRARY = re.compile(r'\.(?:dll|dylib|so)(?:\.[0-9a-z]+)*$')


def canonical_library(name):
    """A native library's name without `lib`, extension, SONAME or platform."""
    stem = NATIVE_LIBRARY.sub('', name.lower())
    stem = stem[3:] if stem.startswith('lib') else stem
    return re.sub(r'-(?:windows|linux|macos)-[a-z0-9_]+$', '', stem)


def check_embedding_runtime(platform, files):
    """The llama.cpp runtime under lib/, CPU only, plus Windows' bin/ copies."""
    libraries = {}
    for name in files:
        path = Path(name)
        if len(path.parts) == 2 and path.parts[0] in ('lib', 'bin') and \
                NATIVE_LIBRARY.search(path.name.lower()):
            libraries.setdefault(path.parts[0], set()).add(
                canonical_library(path.name))
    found = libraries.get('lib', set()) | libraries.get('bin', set())
    foreign = sorted(name for name in found if FOREIGN_RUNTIME.match(name))
    if foreign:
        raise SystemExit(
            f'Native bundle {platform} ships more than the CPU llama.cpp '
            f'runtime: {", ".join(foreign)}')
    if 'llamadart' not in libraries.get('lib', set()):
        raise SystemExit(f'Native bundle {platform} lacks llamadart in lib/')
    if platform.startswith('windows'):
        for directory in ('lib', 'bin'):
            if not any(name.startswith('ggml-cpu')
                       for name in libraries.get(directory, set())):
                raise SystemExit(
                    f'Native bundle {platform} lacks the CPU backend in '
                    f'{directory}/')


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
                    'licenses/embedding_runtime/NOTICE',
                    'licenses/wayfinder/LICENSE', 'licenses/dart/packages.json',
                    'licenses/dart-sdk/LICENSE', 'LICENSE',
                    *[f'skills/{name}/SKILL.md' for name in [
                        'adopt-knowledge-bundle', 'assess-knowledge-bundle',
                        'author-knowledge-bundle', 'create-profile',
                        'use-wayfinder']]]
        if any(name not in files for name in required):
            raise SystemExit(f'Incomplete native bundle: {platform}')
        # The command keeps its indexes as plain files and needs no ObjectBox.
        if any('objectbox' in Path(name).name.lower() or
               name.startswith('licenses/objectbox/') for name in files):
            raise SystemExit(f'Unexpected ObjectBox asset: {platform}')
        check_embedding_runtime(platform, files)
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
