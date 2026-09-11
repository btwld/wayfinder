"""Exercise published installers with no Dart SDK or repository credentials."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ('https://raw.githubusercontent.com/conceptadev/wayfinder/'
          + os.environ.get('WAYFINDER_INSTALLER_REF', 'main') + '/tool/')

def download_installer(script):
    if os.environ.get('WAYFINDER_USE_LOCAL_INSTALLER') == '1':
        data = (ROOT / 'tool' / script.name).read_bytes()
    else:
        # Fetch the current public file when validating a just-published correction.
        url = PUBLIC + script.name + '?verification=' + str(time.time_ns())
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read()
    script.write_bytes(data)
    print(f'{script.name} SHA-256: {hashlib.sha256(data).hexdigest()}', flush=True)

with tempfile.TemporaryDirectory(prefix='wayfinder-public-') as temporary:
    work = Path(temporary)
    env = {key: value for key, value in os.environ.items()
           if key not in {'GH_TOKEN', 'GITHUB_TOKEN', 'DART_HOME', 'PUB_CACHE'}}
    env['WAYFINDER_INSTALL_ROOT'] = str(work / 'runtime')
    env['WAYFINDER_INSTALL_DIR'] = str(work / 'bin')
    env['WAYFINDER_DATA_DIR'] = str(work / 'data')
    if os.name == 'nt':
        system = Path(os.environ['SystemRoot']) / 'System32'
        if os.environ.get('WAYFINDER_POWERSHELL') == 'powershell':
            # Windows PowerShell 5.1 is the default shell on a fresh machine.
            powershell = str(system / 'WindowsPowerShell/v1.0/powershell.exe')
        else:
            powershell = shutil.which('pwsh')
            if not powershell:
                raise SystemExit('PowerShell 7 is required for this Windows check')
        env['PATH'] = os.pathsep.join([str(system), str(Path(powershell).parent)])
        script = work / 'install.ps1'
        download_installer(script)
        # Run the script as the documented `irm ... | iex` command does.
        subprocess.run([powershell, '-NoProfile', '-Command',
                        f"Get-Content -Raw -LiteralPath '{script}' | Invoke-Expression"],
                       env=env, check=True)
        bins = list((work / 'runtime').glob('*/bin/wayfinder.exe'))
        if len(bins) != 1:
            raise SystemExit(f'Expected one installed runtime, found {len(bins)}')
        binary_dir = bins[0].parent
        suffix = '.exe'
    else:
        env['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin'
        script = work / 'install.sh'
        download_installer(script)
        subprocess.run(['/bin/sh', str(script)], env=env, check=True)
        binary_dir = work / 'bin'
        suffix = ''
    if shutil.which('dart', path=env['PATH']):
        raise SystemExit('This check requires an environment without Dart')
    env['PATH'] = str(binary_dir) + os.pathsep + env['PATH']
    wayfinder = str(binary_dir / ('wayfinder' + suffix))
    fixture = str(ROOT / 'examples/knowledge')
    for command in [
        [wayfinder, '--version'],
        [wayfinder, 'validate', fixture],
        [wayfinder, 'index', fixture],
        [wayfinder, 'search', fixture, 'PDF annotations'],
    ]:
        subprocess.run(command, env=env, check=True, timeout=180)
    repeated = subprocess.run([wayfinder, 'index', fixture], env=env,
                              check=True, capture_output=True, text=True, timeout=180)
    print(repeated.stdout)
    if ': 0 embedded,' not in repeated.stdout:
        raise SystemExit('Unchanged public runtime index unexpectedly embedded content')
print('Public installer, validation, retrieval and index reuse passed without Dart.')
