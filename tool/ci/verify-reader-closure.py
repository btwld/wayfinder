#!/usr/bin/env python3
"""Keep portable/model-free reader dependencies independent of retrieval."""
from pathlib import Path
import re
import sys

from publication import dependencies

ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN = {'wayfinder_embeddings', 'llamadart', 'objectbox', 'objectbox_flutter_libs'}


def main() -> int:
    specs = {p.parent.name: p.read_text() for p in (ROOT / 'packages').glob('*/pubspec.yaml')}
    errors = []
    for start in ('wayfinder_reader', 'wayfinder_reader_local', 'wayfinder_flutter'):
        pending, seen = [start], set()
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            if name in FORBIDDEN:
                errors.append(f'{start}: forbidden runtime dependency {name}')
            if name in specs:
                pending.extend(dependencies(specs[name]))
    portable = ROOT / 'packages/wayfinder_reader/lib'
    for path in portable.rglob('*.dart'):
        for uri in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)", path.read_text()):
            if uri in ('dart:io', 'dart:ffi', 'dart:ui') or uri.startswith((
                'package:flutter/', 'package:wayfinder/', 'package:okf/',
                'package:wayfinder_reader_local/',
            )):
                errors.append(f'{path.relative_to(ROOT)}: nonportable import {uri}')
    if set(dependencies(specs['wayfinder_reader'])) - {'crypto', 'meta'}:
        errors.append('portable reader: review and explicitly allow new runtime dependencies')
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print('Reader runtime closures are portable/model-free (no retrieval/native model packages).')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
