# Package format 3

The engine's schema is
`https://github.com/btwld/wayfinder/blob/main/docs/schemas/wayfinder-profile.schema.json`.
This reference summarizes it for authors.

## Layout

```text
<package>/
  wayfinder-profile.json   identity, vocabulary, and rules
  README.md                one heading per rule id; the docs URL points here
  CHANGELOG.md             one entry per release
  skill/
    SKILL.md               name: <id>
    references/            guidance, review map, adoption seed
```

A repository may host several packages. A child in the same repository can
name its parent by path, so both release at one commit.

## Fields

| Field | Required | Holds |
| --- | --- | --- |
| `format` | yes | `3` |
| `id` | yes | Lowercase kebab-case, at most 64 characters. Not `okf`, `wayfinder`, or a wayfinder skill name. |
| `release` | yes | The Profile's own release name: letters, digits, `.`, `+`, `-`. Opaque to the engine. |
| `implements` | yes | `{"id": "okf", "release": "<OKF release>"}` |
| `extends` | no | The parent: `{"path"}` for the same repository at the same commit, or `{"git", "ref", "path"}` for another revision. |
| `docs` | no | Absolute URI. A finding's help link is `docs#<rule-id>`. |
| `skill` | no | Package-relative directory of the skill, usually `"skill"`. |
| `types`, `tags`, `relationships` | no | Lists of `{"name", "description"}`. |
| `frontmatter_keys` | no | Keys beyond OKF's, each `{"name", "description"}`. A key OKF defines is rejected. |
| `$defs` | no | Schemas rules may `$ref` as `#/$defs/<name>`, including slots. |
| `rules` | yes | The rules this package adds. |

A child only adds. It cannot change or remove a parent's rule or
vocabulary. Names stay unique across the chain and the project entry.
Every rule uses the vocabulary of the whole chain plus the project entry,
so an added name can change an inherited rule's findings. It does not change
that rule's definition, severity, namespace, or release.

## Rules

```json
{
  "id": "known-type",
  "category": "vocabulary",
  "severity": "error",
  "status": "stable",
  "description": "Every concept type MUST be declared.",
  "message": "Type {type} is not declared.",
  "check": {"subject": "concept", "schema": {"properties": {"type": {"$ref": "#/$defs/profile.types"}}}},
  "tests": {"slots": {"profile.types": ["Runbook"]}, "valid": [{"type": "Runbook"}], "invalid": [{"type": "Memo"}]}
}
```

- `id`: kebab-case. Findings report it as `<package id>/<rule id>`.
- `category`: `structure`, `vocabulary`, `provenance`, `linking`, or
  `history`.
- `severity`: `error` fails the gate. `advisory` is a finding that does not.
  `note` reports something the Profile permits, never as a finding.
- `status`: `preview`, `stable`, or `deprecated`.
- `description`: the rule's normative statement.
- `message`: finding text. `{<fact>}` inserts a fact of the subject.
  `{failing}` inserts the failing elements and needs `each`. A builtin may
  take an object of messages keyed by the message ids it names.
- `check`: a schema check, or a builtin from [builtins.md](builtins.md).
- `tests`: required for a schema check, not allowed for a builtin.

## Schema checks

A schema check runs a JSON Schema against the facts of each subject, and
[Ack](https://pub.dev/packages/ack) evaluates it. The schema uses the
engine's keyword subset: `type`, `enum`, `const`, `pattern`,
`minLength`, `maxLength`, `required`, `minProperties`, `properties`,
`additionalProperties`, `propertyNames`, `items`, `uniqueItems`,
`minItems`, `maxItems`, `contains`, `not`, `allOf`, `anyOf`, `oneOf`,
`if`/`then`/`else`, `$ref` to `#/$defs/<name>`, and `format: date-time`.
Any other keyword, including any `x-` key, makes the package unsupported.
The annotations `$schema`, `$comment`, `title`, `description`, `examples`,
`default` and `deprecated` must be well-formed 2020-12 values. A `$schema`,
when present, must name the 2020-12 meta-schema,
`https://json-schema.org/draft/2020-12/schema`; any other makes the package
unsupported. `$id`, `$schema` and `$defs` may appear only at the schema's
root.

| Subject | One per | Facts |
| --- | --- | --- |
| `frontmatter` | concept | the concept's frontmatter as written |
| `concept` | concept | `path`, `type`, `status`, `keys`, `tags` (`value`, `count`), `source_ids`, `headings` (`value`, `normalized`), `edges` (`origin`, `target`, `resolution`, `internal`, `bundle_relative`), `relationships` (`entry`, `resolution`, `internal`, `bundle_relative`, `resolved`), `inbound` (`relationship`, `from`), `footnotes` (`value`, `referenced`, `defined`, `is_source_id`), `sibling_directory` |
| `actor` | actor id used | `id`, `first_use` |
| `directory` | directory | `path`, `has_index`; may report `at: "index"` |
| `file` | file | `path`, `name`, `markdown` |
| `root` | bundle | `okf_version`, `files`, `has_concepts`, `index_links` |
| `log` | root log | `entries` (`date`, `action`) |

- `each` names an array fact. The schema then runs once per element, and a
  list of plain values gives elements as `{"value": …}`.
- `failing_field` names the element field that fills `{failing}`, `value` by
  default.
- `at` names the location to report, `self` by default.

`sibling_directory` is a boolean: the loaded file inventory contains a
directory beside the concept with the same name as its filename without
`.md`. For `references/vendor.md`, that directory is `references/vendor/`.
No directory name is special. A directory is represented by files in the
inventory; an empty on-disk directory alone is not included. In-memory
candidates use their candidate inventory, not a separate disk lookup.
Use `path` in a rule to express this Profile's own directory exemptions.

## Migrating format 2

This engine refuses format 2 as `profile-unsupported`; it does not give old
packages new facts silently. Review uses of `sibling_directory`, whose old
implementation excluded directories under `interactions/` and `references/`.
If the Profile chose those exemptions, express them in its schema; otherwise
explicitly accept the neutral fact's additional true cases. Change `format`
to `3` and follow the Profile's release process, including its compatibility
and migration record. A package whose own rules do not use this fact needs
no rule changes, but its parents must also be migrated. Review the entire
chain: its verdicts stay unchanged only when no rule uses the fact or every
affected package explicitly preserves its prior policy.

Move project source refs and any pinned parent refs to migrated revisions,
then refresh and commit locks and installed skills with `get` or `upgrade`.
Running `upgrade` cannot move an immutable old ref to a new release. A project
may instead retain an engine that reads its existing format 2 package.

## Slots

A slot is the composed vocabulary: the whole chain plus the project entry.
Inherited rules receive these same slots, not an ancestor-only vocabulary.
The engine supplies a `$defs` entry named by each slot id, so
`{"$ref": "#/$defs/profile.types"}` stands for "one of these names". A
package's own `$defs` may not use a slot id.

| Slot | Values |
| --- | --- |
| `profile.types` | declared type names |
| `profile.tags` | declared tag names |
| `profile.relationships` | declared relationship names |
| `profile.frontmatterKeys` | declared frontmatter keys |
| `profile.actors` | actor ids in the project entry |
| `okf.frontmatterKeys` | keys OKF defines; tests get them automatically |

## Tests

`valid` and `invalid` each hold at least one example. An example is a fact
map for the subject, or one element when the check has `each`. `slots` gives
the slot values the examples assume, and every slot the check uses needs
one. The engine runs the tests whenever it parses the package; `wayfinder
get` fails on the first example that disagrees with its check. Reading a
package, its tests included, must finish within ten seconds, or `get` fails
and `validate` reports `wayfinder/profile-timeout`. Keep `pattern` free of
nested quantifiers such as `(a+)+`, which backtrack without end on a near
miss; a package's tests take milliseconds. Keep examples small, too: one
deep or long enough to overflow the engine's stack fails the package as
`wayfinder/profile-invalid`.

Write an invalid example for each way the rule should fire, and a valid one
for each nearby case it must not catch.

## Skill

`skill/SKILL.md` starts with frontmatter whose `name` is the Profile id and
whose `description` says when to use it: writing or reviewing in a bundle
whose `wayfinder validate --output json` chain lists the id. `get` installs
every regular file under `skill/`; symlinks fail `get`. The generic
assessment flow expects the skill to route to a review map.
