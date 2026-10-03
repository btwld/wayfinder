# Builtins

A builtin is a check the engine implements and versions with its release.
A rule calls it by name with `params`. The rule's id, severity, message, and
docs belong to the Profile. The capability belongs to the engine. A builtin
never holds policy, which is the params, never names a Profile, and never
reports engine health, which is a diagnostic. A builtin
rule takes no `tests`, because exercising it needs a bundle; prove it with an
adversarial fixture instead.

## When a check becomes a builtin

Write a schema rule over subject facts whenever one can express the check.
A check needs a builtin only when it requires at least one of these:

- input beyond the parsed bundle, such as the disk;
- comparison with generated output, or a `--fix`;
- a finding about something absent, located where no subject lives;
- more than one finding per subject.

When a schema cannot express the check and no builtin below fits, the
options are a new generic fact, which the engine adds only if other Profiles
would plausibly use it, or a new capability. A capability that only one
Profile could use with one set of params is a rule in disguise and is
rejected. Until the engine has what the check needs, the check is judgment:
put it in the skill's review map.

## `files-present`

Reports one finding listing every missing path as `{failing}`, located at
the first missing path. A path counts as present when it is any loaded
bundle file.

```json
{
  "type": "object",
  "required": ["paths"],
  "additionalProperties": false,
  "properties": {
    "paths": {"type": "array", "minItems": 1, "uniqueItems": true, "items": {"type": "string", "minLength": 1}}
  }
}
```

```json
{
  "id": "root-structure-files", "category": "structure", "severity": "error", "status": "stable",
  "description": "A bundle MUST contain `index.md` and `log.md` at its root.",
  "message": "The bundle root must contain index.md and log.md; missing {failing}.",
  "check": {"builtin": "files-present", "params": {"paths": ["index.md", "log.md"]}}
}
```

## `path-targets-exist`

Reports one finding per document and target, as `{target}`, when a
path-valued field names something that exists neither in the bundle nor on
disk. It reports nothing when the link graph is unavailable; the engine
reports that as a diagnostic.

```json
{
  "type": "object",
  "required": ["fields"],
  "additionalProperties": false,
  "properties": {
    "fields": {
      "type": "array", "minItems": 1, "uniqueItems": true,
      "items": {"enum": ["resource", "sources.resource", "computation", "executor.resource", "attester.resource"]}
    }
  }
}
```

```json
{
  "id": "source-path-unresolved", "category": "provenance", "severity": "advisory", "status": "stable",
  "description": "A top-level `resource` or `sources[].resource` written as a path resolves to no existing file or directory.",
  "message": "Path {target} does not exist.",
  "check": {"builtin": "path-targets-exist", "params": {"fields": ["resource", "sources.resource"]}}
}
```

## `matches-generated`

Compares each file a generator writes with the bundle. A file that differs
reports the `stale` message. With `extra: "report"`, an `index.md` the
generator would not write reports the `extra` message, unless `keep` lists
it. Both
fill `{path}`. Line endings on disk are read as LF. `wayfinder validate
--fix` writes the generator's output. The `okf-index` generator declares the
package's `implements.release` in the indexes it writes.

```json
{
  "type": "object",
  "required": ["generator"],
  "additionalProperties": false,
  "properties": {
    "generator": {"enum": ["okf-index"]},
    "keep": {"type": "array", "uniqueItems": true, "items": {"type": "string", "minLength": 1}},
    "extra": {"enum": ["report", "ignore"]}
  }
}
```

`keep` defaults to none and `extra` to `report`.

```json
{
  "id": "index-current", "category": "structure", "severity": "error", "status": "stable",
  "description": "Every index.md MUST equal okf's generated index.",
  "message": {"stale": "{path} is not okf's generated index.", "extra": "{path} is not generated."},
  "check": {"builtin": "matches-generated", "params": {"generator": "okf-index", "keep": ["index.md"]}}
}
```
