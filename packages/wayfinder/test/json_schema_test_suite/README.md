# JSON-Schema-Test-Suite (vendored subset)

Cases from the official
[JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite),
commit `5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`, directory
`tests/draft2020-12/`. Only the keyword files that
`lib/src/rules/predicate.dart` claims to support are vendored, plus
`optional/format/date-time.json`. Files are byte-identical to upstream; the
`LICENSE` file is the suite's own (MIT).

`test/predicate_test.dart` runs every group. Groups whose schema uses a keyword
outside the predicate's subset fail to compile and are counted, not evaluated.

Refresh with:

```sh
base=https://raw.githubusercontent.com/json-schema-org/JSON-Schema-Test-Suite/5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8
curl -fsSL "$base/tests/draft2020-12/<keyword>.json" -o <keyword>.json
curl -fsSL "$base/tests/draft2020-12/optional/format/date-time.json" -o optional/format/date-time.json
curl -fsSL "$base/LICENSE" -o LICENSE
```
