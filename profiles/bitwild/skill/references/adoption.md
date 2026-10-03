# Adopting a bundle with this Profile

The generic `adopt-knowledge-bundle` skill runs adoption. It reads this
reference for the Profile's seed. Replace placeholders with project facts.
Create no subject directories: the corpus earns them later.

## `wayfinder.json` entry

```json
{
  "version": 1,
  "profiles": {
    "bitwild-profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "<release tag or branch>",
        "path": "profiles/bitwild"
      },
      "applies_to": ["./knowledge"]
    }
  }
}
```

The package supplies the twelve standard types and eleven relationship names.
Do not copy them into project files. Add project `types`, `tags`,
`relationships`, and `actors` to this entry only when a concept needs them,
and never invent them during seeding.

## `knowledge/index.md`

````markdown
---
okf_version: "0.2"
---

# Bundle

* [Knowledge Log](log.md)
````

Write this index by hand only while the bundle holds no concepts; the
`root-index-lists-log` rule requires it to link only `log.md` then. Once a
concept exists, `wayfinder validate knowledge --fix` replaces it with okf's
generated root index, which does not list `log.md`.

## `knowledge/log.md`

````markdown
# Knowledge Log

## <YYYY-MM-DD>

* **Initialization**: Established the knowledge bundle under the bitwild-profile Profile.
````

## Agent instructions

Add this line to the end of the generic `### Knowledge bundle` block:

```markdown
Execution records stay in the tracker and are linked from concepts.
```

When the project holds raw source material, seed `captures/` and add its
block from [captures.md](captures.md).

## Review

Review the seed with **Scope: whole bundle** per
[review-map.md](review-map.md). A bundle holding only its root files is fully
adopted, not half-finished.
