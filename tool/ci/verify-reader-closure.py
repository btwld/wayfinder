#!/usr/bin/env python3
"""Verify the actual transitive portable knowledge entry-point import closure."""
from pathlib import Path
import json
import sys
from urllib.parse import unquote, urlparse

from publication import dependencies

ROOT = Path(__file__).resolve().parents[2]
MODEL_PACKAGES = {'wayfinder_embeddings', 'llamadart', 'objectbox', 'objectbox_flutter_libs'}
FORBIDDEN_PACKAGES = {'ffi', 'okf', 'flutter'} | MODEL_PACKAGES
FORBIDDEN_SDK = {'dart:io', 'dart:ffi', 'dart:ui', 'dart:mirrors'}


def import_uris(source: str):
    """Parse only Dart's directive prefix; unsupported syntax fails closed."""
    def tokens():
        i = 0
        while i < len(source):
            if source[i].isspace():
                i += 1
                continue
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
                if depth:
                    raise ValueError('unterminated directive comment')
                continue
            raw = source[i] == 'r' and source[i + 1:i + 2] in ('"', "'")
            if raw or source[i] in ('"', "'"):
                i += int(raw)
                quote = source[i]
                delimiter = quote * (3 if source.startswith(quote * 3, i) else 1)
                i += len(delimiter)
                start = i
                while i < len(source) and not source.startswith(delimiter, i):
                    if not raw and source[i] == '$':
                        raise ValueError('interpolation in a directive is forbidden')
                    if not raw and source[i] == '\\':
                        raise ValueError('escaped directive strings are unsupported')
                    if len(delimiter) == 1 and source[i] in '\r\n':
                        raise ValueError('unterminated directive string')
                    i += 1
                if i == len(source):
                    raise ValueError('unterminated directive string')
                yield ('string', source[start:i])
                i += len(delimiter)
            elif source[i].isalpha() or source[i] in ('_', '$'):
                start = i
                i += 1
                while i < len(source) and (source[i].isalnum() or source[i] in ('_', '$')):
                    i += 1
                yield ('word', source[start:i])
            else:
                yield ('symbol', source[i])
                i += 1

    stream = iter(tokens())
    token = next(stream, None)
    while token is not None:
        # Metadata can precede a directive or the first declaration.
        if token == ('symbol', '@'):
            token = next(stream, None)
            if token is None or token[0] != 'word':
                raise ValueError('unsupported directive metadata')
            token = next(stream, None)
            while token == ('symbol', '.'):
                token = next(stream, None)
                if token is None or token[0] != 'word':
                    raise ValueError('unsupported directive metadata')
                token = next(stream, None)
            if token == ('symbol', '('):
                depth = 1
                while depth:
                    token = next(stream, None)
                    if token is None:
                        raise ValueError('unterminated directive metadata')
                    if token == ('symbol', '('):
                        depth += 1
                    elif token == ('symbol', ')'):
                        depth -= 1
                token = next(stream, None)
            continue
        if token[0] != 'word':
            raise ValueError('unsupported syntax before a declaration')
        if token[1] not in ('library', 'import', 'export', 'part'):
            return  # Dart requires directives before declarations.
        directive = token[1]
        body = []
        while (token := next(stream, None)) != ('symbol', ';'):
            if token is None:
                raise ValueError('unterminated directive')
            body.append(token)
        i = 0

        def take(kind, value=None):
            nonlocal i
            if i >= len(body) or body[i][0] != kind or (value is not None and body[i][1] != value):
                raise ValueError(f'unsupported {directive} directive')
            result = body[i][1]
            i += 1
            return result

        def identifier():
            take('word')
            while i < len(body) and body[i] == ('symbol', '.'):
                take('symbol', '.')
                take('word')

        def string():
            value = take('string')
            while i < len(body) and body[i][0] == 'string':
                value += take('string')
            return value

        if directive == 'library':
            if body:
                identifier()
        elif directive == 'part' and body[:1] == [('word', 'of')]:
            take('word', 'of')
            if i < len(body) and body[i][0] == 'string':
                string()  # The containing library already reaches this part.
            else:
                identifier()
        else:
            yield string()
            if directive != 'part':
                while i < len(body) and body[i] == ('word', 'if'):
                    take('word', 'if')
                    take('symbol', '(')
                    identifier()
                    if i < len(body) and body[i] == ('symbol', '='):
                        take('symbol', '=')
                        take('symbol', '=')
                        string()  # Comparison value, never an import URI.
                    take('symbol', ')')
                    yield string()
                if i < len(body) and body[i] == ('word', 'deferred'):
                    take('word', 'deferred')
                    take('word', 'as')
                    take('word')
                elif i < len(body) and body[i] == ('word', 'as'):
                    take('word', 'as')
                    take('word')
                while i < len(body) and body[i] in [('word', 'show'), ('word', 'hide')]:
                    take('word')
                    take('word')
                    while i < len(body) and body[i] == ('symbol', ','):
                        take('symbol', ',')
                        take('word')
        if i != len(body):
            raise ValueError(f'unsupported {directive} directive')
        token = next(stream, None)


def main() -> int:
    config_file = ROOT / '.dart_tool/package_config.json'
    if not config_file.exists():
        print('Run dart pub get before checking the knowledge import closure.', file=sys.stderr)
        return 1
    packages = {}
    package_roots = {}
    for package in json.loads(config_file.read_text())['packages']:
        root = package['rootUri']
        parsed = urlparse(root)
        if parsed.scheme and parsed.scheme != 'file':
            print(f'Unsupported package root: {root}', file=sys.stderr)
            return 1
        directory = Path(unquote(parsed.path)) if parsed.scheme else config_file.parent / unquote(root)
        package_roots[package['name']] = directory.resolve()
        packages[package['name']] = (directory / package.get('packageUri', 'lib/')).resolve()
    entry = ROOT / 'packages/wayfinder/lib/knowledge.dart'
    pending, seen, errors = [(entry, 'package:wayfinder/knowledge.dart')], set(), []
    while pending:
        path, route = pending.pop()
        path = path.resolve()
        if path in seen:
            continue
        seen.add(path)
        owner = max((name for name, root in package_roots.items() if path.is_relative_to(root)),
                    key=lambda name: len(package_roots[name].parts), default=None)
        if owner in FORBIDDEN_PACKAGES:
            errors.append(f'{route}: forbidden package {owner}')
            continue
        if not path.is_file():
            errors.append(f'{route}: missing source {path}')
            continue
        try:
            uris = list(import_uris(path.read_text()))
        except ValueError as error:
            errors.append(f'{route}: {error}')
            continue
        for uri in uris:
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
            if name in MODEL_PACKAGES:
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
