#!/usr/bin/env python3
"""Verify the actual transitive portable knowledge entry-point import closure."""
from pathlib import Path
import json
import sys
from urllib.parse import unquote, urlparse

from publication import dependencies

ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN_PACKAGES = {
    'ffi', 'okf', 'flutter', 'wayfinder_embeddings', 'llamadart',
    'objectbox', 'objectbox_flutter_libs',
}
FORBIDDEN_SDK = {'dart:io', 'dart:ffi', 'dart:ui', 'dart:mirrors'}


def import_uris(source: str):
    """Read directive URI strings, including conditional branches and parts.

    Tokenize strings and nested comments so code examples in comments/strings
    cannot hide or invent directives. Dart allows multiple directives per line.
    """
    tokens = []
    i = 0
    while i < len(source):
        if source.startswith('//', i):
            end = source.find('\n', i)
            i = len(source) if end < 0 else end + 1
            continue
        if source.startswith('/*', i):
            depth, i = 1, i + 2
            while i < len(source) and depth:
                if source.startswith('/*', i):
                    depth, i = depth + 1, i + 2
                elif source.startswith('*/', i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            continue
        raw = source[i] == 'r' and source[i + 1:i + 2] in ('"', "'")
        if raw or source[i] in ('"', "'"):
            i += int(raw)
            quote = source[i]
            delimiter = quote * (3 if source.startswith(quote * 3, i) else 1)
            i += len(delimiter)
            start = i
            while i < len(source) and not source.startswith(delimiter, i):
                i += 2 if source[i] == '\\' and not raw else 1
            tokens.append(('string', source[start:i]))
            i += len(delimiter)
        elif source[i].isalpha() or source[i] in ('_', '$'):
            start = i
            i += 1
            while i < len(source) and (source[i].isalnum() or source[i] in ('_', '$')):
                i += 1
            tokens.append(('word', source[start:i]))
        else:
            if not source[i].isspace():
                tokens.append(('symbol', source[i]))
            i += 1
    i = 0
    while i + 1 < len(tokens):
        if (tokens[i][0] == 'word' and tokens[i][1] in ('import', 'export', 'part')
                and tokens[i + 1][0] == 'string'):
            i += 1
            while i < len(tokens) and tokens[i] != ('symbol', ';'):
                if tokens[i][0] == 'string':
                    yield tokens[i][1]
                i += 1
        i += 1


def main() -> int:
    config_file = ROOT / '.dart_tool/package_config.json'
    if not config_file.exists():
        print('Run dart pub get before checking the knowledge import closure.', file=sys.stderr)
        return 1
    packages = {}
    for package in json.loads(config_file.read_text())['packages']:
        root = package['rootUri']
        parsed = urlparse(root)
        if parsed.scheme and parsed.scheme != 'file':
            print(f'Unsupported package root: {root}', file=sys.stderr)
            return 1
        directory = Path(unquote(parsed.path)) if parsed.scheme else config_file.parent / unquote(root)
        packages[package['name']] = (directory / package.get('packageUri', 'lib/')).resolve()
    entry = ROOT / 'packages/wayfinder/lib/knowledge.dart'
    pending, seen, errors = [(entry, 'package:wayfinder/knowledge.dart')], set(), []
    while pending:
        path, route = pending.pop()
        path = path.resolve()
        if path in seen:
            continue
        seen.add(path)
        if not path.is_file():
            errors.append(f'{route}: missing source {path}')
            continue
        for uri in import_uris(path.read_text()):
            next_route = f'{route} -> {uri}'
            if uri.startswith('dart:'):
                if uri in FORBIDDEN_SDK:
                    errors.append(f'{next_route}: nonportable SDK import')
                continue
            if uri.startswith('package:'):
                name, _, relative = uri[len('package:'):].partition('/')
                if name in FORBIDDEN_PACKAGES:
                    errors.append(f'{next_route}: forbidden package import')
                    continue
                if name not in packages:
                    errors.append(f'{next_route}: unresolved package')
                    continue
                pending.append((packages[name] / relative, next_route))
            elif urlparse(uri).scheme:
                errors.append(f'{next_route}: unsupported import URI')
            else:
                pending.append((path.parent / uri, next_route))
    # Native core and Flutter may use other core entries, but remain model-free.
    specs = {p.parent.name: p.read_text() for p in (ROOT / 'packages').glob('*/pubspec.yaml')}
    for start in ('wayfinder', 'wayfinder_flutter'):
        todo, visited = [start], set()
        while todo:
            name = todo.pop()
            if name in visited:
                continue
            visited.add(name)
            if name in {'wayfinder_embeddings', 'llamadart', 'objectbox', 'objectbox_flutter_libs'}:
                errors.append(f'{start}: forbidden runtime dependency {name}')
            if name in specs:
                todo.extend(dependencies(specs[name]))
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print(f'knowledge.dart transitive closure is portable/model-free ({len(seen)} source files); native core/Flutter are model-free.')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
