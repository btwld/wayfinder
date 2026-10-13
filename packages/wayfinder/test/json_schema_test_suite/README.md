# JSON-Schema-Test-Suite (vendored subset)

Cases from the official
[JSON-Schema-Test-Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite),
commit `5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`, directory
`tests/draft2020-12/`. Only the keyword files for the rule-schema keyword
subset in `lib/src/rules/schema.dart` are vendored, plus
`optional/format/date-time.json`. Files are byte-identical to upstream; the
`LICENSE` file is the suite's own (MIT).

`test/json_schema_test_suite_test.dart` runs every group through `RuleSchema`.
A group whose schema leaves the subset must be refused as unsupported, and the
runner names each refused group per file. Every other case must be accepted
exactly when it is valid, and the published-schema renderer must report a
violation exactly when it is invalid.

Refresh with:

```sh
base=https://raw.githubusercontent.com/json-schema-org/JSON-Schema-Test-Suite/5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8
curl -fsSL "$base/tests/draft2020-12/<keyword>.json" -o <keyword>.json
curl -fsSL "$base/tests/draft2020-12/optional/format/date-time.json" -o optional/format/date-time.json
curl -fsSL "$base/LICENSE" -o LICENSE
```
