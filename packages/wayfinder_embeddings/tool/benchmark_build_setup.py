"""Measure clean and cached native builds in disposable package copies."""
import pathlib, tempfile, shutil, subprocess, time, json
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
options = parser.parse_args()
output = pathlib.Path(options.output).resolve()
output.mkdir(parents=True, exist_ok=True)
root=pathlib.Path(__file__).resolve().parents[3]
pkg=root/'packages/wayfinder_embeddings'
results={}
scratch=pathlib.Path(tempfile.mkdtemp(prefix='comparison-clean-build-'))
try:
    target=scratch/'package'
    shutil.copytree(pkg,target,ignore=shutil.ignore_patterns('build','.dart_tool','comparison_results','*.dylib','*.so','*.dll'))
    shutil.rmtree(target/'models',ignore_errors=True)
    llama=scratch/'llamadart'
    shutil.copytree(pathlib.Path.home()/'.pub-cache/hosted/pub.dev/llamadart-0.8.23',llama,ignore=shutil.ignore_patterns('.dart_tool','build'))
    if (root/'pubspec.lock').exists(): shutil.copy2(root/'pubspec.lock',target/'pubspec.lock')
    manifest=target/'pubspec.yaml'
    text=manifest.read_text().replace('resolution: workspace\n','')
    text+='\ndependency_overrides:\n  llamadart:\n    path: ../llamadart\nhooks:\n  user_defines:\n    llamadart:\n      llamadart_native_runtimes: [llama_cpp]\n      llamadart_native_backends: [cpu]\n'
    manifest.write_text(text)
    logroot=output
    def run(name,cmd):
        start=time.perf_counter()
        with (logroot/(name+'.log')).open('w') as log:
            subprocess.run(cmd,cwd=target,stdout=log,stderr=subprocess.STDOUT,check=True)
        results[name+'Ms']=(time.perf_counter()-start)*1000
    run('resolve',['dart','pub','get'])
    run('cleanNativeBuild',['dart','build','cli','--target=bin/benchmark_retrieval.dart','--output=build/benchmark'])
    results['nativeCacheArtifactBytes']=sum(p.stat().st_size for p in (llama/'.dart_tool').rglob('*') if p.is_file())
    run('cachedNativeBuild',['dart','build','cli','--target=bin/benchmark_retrieval.dart','--output=build/benchmark'])
    results['cliBeforeModelAndObjectBoxBytes']=sum(p.stat().st_size for p in (target/'build/benchmark/bundle').rglob('*') if p.is_file())
    run('objectboxSetup',['bash','tool/install_objectbox.sh'])
    results['objectboxLibraryBytes']=(target/'lib/libobjectbox.dylib').stat().st_size
    results['note']='Task copy with empty project and llamadart native caches. Dart SDK and package cache warm. Model download measured separately. Native cache bytes are disk artifacts, not wire traffic.'
finally:
    (output/'builds.json').write_text(json.dumps(results,indent=2)+'\n')
    shutil.rmtree(scratch)
