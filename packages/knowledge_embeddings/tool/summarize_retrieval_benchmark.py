"""Summarize recorded runs, preserving per-query regressions and paired uncertainty."""
import argparse
import json
import itertools
import pathlib
import random

parser = argparse.ArgumentParser()
parser.add_argument('directory')
parser.add_argument('output')
parser.add_argument('--models', action='store_true', help='Group dense/hybrid runs by model and compare model pairs')
args = parser.parse_args()
root = pathlib.Path(args.directory)

def distribution(values):
    ordered = sorted(values)
    return {'count': len(values), 'p50': ordered[len(ordered)//2],
            'p95': ordered[int(len(ordered)*.95)], 'min': ordered[0], 'max': ordered[-1]}

def quality(rows, field):
    answerable = [q for q in rows if q[field]['answerable']]
    absent = [q for q in rows if not q[field]['answerable']]
    return {'answerable': len(answerable), 'top1Correct': sum(q[field]['top1'] for q in answerable),
            **{key: sum(q[field][key] for q in answerable)/len(answerable) for key in ['recall3', 'recall10', 'rr']},
            'unanswerable': len(absent), 'unanswerableWithCandidates': sum(q[field]['candidates']>0 for q in absent)}

def paired(rows, baseline):
    reference = {q['id']: q for q in baseline}
    assert {q['id'] for q in rows} == set(reference)
    differences = {q['id']: int(q['context']['top1'])-int(reference[q['id']]['context']['top1'])
                   for q in rows if q['context']['answerable']}
    topic_deltas = {}
    for q in rows:
        if q['id'] in differences:
            topic_deltas.setdefault(q['topic'], []).append(differences[q['id']])
    rng = random.Random(91307)
    topics = list(topic_deltas)
    samples = []
    for _ in range(10000):
        draws = [value for topic in rng.choices(topics, k=len(topics)) for value in topic_deltas[topic]]
        samples.append(sum(draws)/len(draws))
    samples.sort()
    return {'top1Delta': sum(differences.values())/len(differences),
            'topicBootstrap95': [samples[250], samples[9750]], 'topics': len(topics),
            'wins': [key for key, value in differences.items() if value > 0],
            'losses': [key for key, value in differences.items() if value < 0]}

def case_name(run):
    if args.models and run['arm'] in ['dense', 'hybrid']:
        return run['arm'] + '/' + run['modelSpec']['id']
    return run['arm']

report = {'splits': {}, 'comparisons': {}}
for split in ['development', 'test']:
    runs = [json.loads(p.read_text()) for p in (root/split).glob('*.json') if p.name != 'index.json']
    assert len({r['passageManifestSha256'] for r in runs}) == 1, 'Cases must share identical passages'
    report['splits'][split] = {}
    cases = sorted({case_name(r) for r in runs})
    for arm in cases:
        report['splits'][split][arm] = {}
        for store in ['memory', 'objectbox']:
            selected = [r for r in runs if case_name(r)==arm and r['store']==store]
            fresh = [r for r in selected if r['scenario']=='fresh']
            measured = next(r for r in fresh if r['repetition']==0)
            assert all(r['quality']==measured['quality'] for r in selected), 'Nondeterministic quality'
            assert all(r['passageManifestSha256']==measured['passageManifestSha256'] for r in selected)
            rows = measured['quality']
            summary = {'initialEncodingPassagesPerSecond': (measured['initialEmbedded'] * 1000 / measured['initialDocumentEncodingMs']) if measured['initialDocumentEncodingMs'] else None,
                       'modelSpec': measured.get('modelSpec'),
                       'uncachedQueriesPerSecond': measured['uncached']['count'] * 1000 / measured['uncached']['totalMs'],
                       'raw': quality(rows,'raw'), 'context': quality(rows,'context'),
                       'groups': {group: quality([q for q in rows if q['group']==group], 'context')
                                  for group in sorted(set(q['group'] for q in rows)) if group!='unanswerable'},
                       'fresh': {key: distribution([r[key] for r in fresh]) for key in
                                 ['timeToFirstResultMs','modelOpenMs','parseMs','syncMs','peakRssBytes','databaseBytes']},
                       'reopen': {key: distribution([r[key] for r in selected if r['scenario']=='reopen']) for key in
                                  ['timeToFirstResultMs','syncMs']} if store=='objectbox' else None,
                       **{key: measured[key] for key in ['uncached','cached','queryEncoding','rankingAndRawContext','policyAssembly','updates','initialEmbedded','initialDocumentEncodingMs','initialWriteMs','uncachedQueryEncodings','cachedQueryEncodings','modelOpened','totalDocumentEncodings','totalQueryEncodings','passageManifestSha256']},
                       'queries': [{key: q[key] for key in ['id','topic','group','raw','context']} for q in rows]}
            report['splits'][split][arm][store] = summary
        assert report['splits'][split][arm]['memory']['queries']==report['splits'][split][arm]['objectbox']['queries']
    baseline = report['splits'][split]['bm25']['memory']['queries']
    report['comparisons'][split] = {}
    for arm in cases:
        if arm == 'bm25':
            continue
        rows = report['splits'][split][arm]['memory']['queries']
        report['comparisons'][split][arm] = paired(rows, baseline)
    if args.models:
        pairs = report.setdefault('modelComparisons', {}).setdefault(split, [])
        for mode in ['dense', 'hybrid']:
            for baseline_name, candidate in itertools.combinations([c for c in cases if c.startswith(mode + '/')], 2):
                pairs.append({'baseline': baseline_name, 'candidate': candidate,
                              **paired(report['splits'][split][candidate]['memory']['queries'],
                                       report['splits'][split][baseline_name]['memory']['queries'])})
report['scale'] = {p.stem:json.loads(p.read_text()) for p in root.glob('scale-*.json')}
for name in ['builds','model-preparation','token-validation']:
    path=root/(name+'.json')
    if path.exists(): report[name]=json.loads(path.read_text())
pathlib.Path(args.output).write_text(json.dumps(report,indent=2)+'\n')
for arm,data in report['splits']['test'].items():
    print(arm, data['memory']['context'], 'uncached',data['memory']['uncached'],
          'start',data['memory']['fresh']['timeToFirstResultMs'])
print('Paired comparisons:',report['comparisons']['test'])
