"""Run isolated compiled arms; long performance runs are deliberately manual."""
import argparse
import json
import pathlib
import shutil
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--binary', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--split', choices=['development', 'test'], required=True)
parser.add_argument('--starts', type=int, default=10)
parser.add_argument('--models-directory', help='Prepared experimental model directories; omitting retains the original XS-only comparison')
options = parser.parse_args()
output = pathlib.Path(options.output).resolve()
output.mkdir(parents=True, exist_ok=True)
binary = pathlib.Path(options.binary).resolve()
entries = []
models = []
if options.models_directory:
    for manifest in sorted(pathlib.Path(options.models_directory).resolve().glob('*/manifest.json')):
        spec = json.loads(manifest.read_text())
        if spec['id'] != manifest.parent.name:
            raise ValueError('Model manifest ID must equal its directory name')
        models.append((spec['id'], manifest.parent / 'embedding.gguf'))
    if not models:
        raise ValueError('No prepared model manifests found')
cases = ([(arm, None, None) for arm in ['keyword', 'bm25']] +
         [(arm, model, path) for model, path in models for arm in ['dense', 'hybrid']]
         if models else [(arm, None, None) for arm in ['keyword', 'bm25', 'dense', 'hybrid']])
for repetition in range(options.starts):
    offset = repetition % len(cases)
    ordered = cases[offset:] + cases[:offset]
    for store in (['memory', 'objectbox'] if repetition % 2 == 0 else ['objectbox', 'memory']):
        for arm, model, model_file in ordered:
            if shutil.disk_usage(output).free < 1024**3:
                raise RuntimeError('Less than 1 GiB free; benchmark stopped to avoid disk interference')
            case = f'{arm}-{model}' if model else arm
            db = output / f'db-{case}-{store}-{repetition}'
            for scenario in (['fresh', 'reopen'] if store == 'objectbox' else ['fresh']):
                name = f'{case}-{store}-{repetition}-{scenario}'
                path = output / f'{name}.json'
                command = [str(binary), f'--arm={arm}', f'--store={store}',
                           f'--split={options.split}', f'--database={db}',
                           f'--output={path}',
                           f'--iterations={1000 if repetition == 0 and scenario == "fresh" else 0}']
                if model:
                    command.extend([f'--model={model}', f'--model-file={model_file}'])
                start = time.perf_counter()
                with (output / f'{name}.log').open('w') as log:
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
                wall = (time.perf_counter() - start) * 1000
                result = json.loads(path.read_text())
                if arm in ['keyword', 'bm25']:
                    assert not result['modelOpened']
                    assert result['totalDocumentEncodings'] == result['totalQueryEncodings'] == 0
                    assert result['stats']['embeddings'] == 0
                if scenario == 'reopen':
                    assert result['initialEmbedded'] == 0
                assert result['truncatedInputs'] == 0
                if model:
                    assert result['modelSpec']['id'] == model
                result['processWallMs'] = wall
                result['databaseBytes'] = sum(p.stat().st_size for p in db.rglob('*') if p.is_file()) if db.exists() else 0
                result['scenario'] = scenario
                result['repetition'] = repetition
                path.write_text(json.dumps(result, indent=2) + '\n')
                entries.append(path.name)
                (output / 'index.json').write_text(json.dumps(entries, indent=2) + '\n')
                print(f'{options.split} {name}: first={result["timeToFirstResultMs"]:.1f}ms wall={wall:.1f}ms', flush=True)
            if db.exists():
                shutil.rmtree(db)
