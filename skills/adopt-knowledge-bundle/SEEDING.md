# Seeding a knowledge bundle

The generic parts of an adoption seed. The selected Profile's skill supplies
the rest: its own root-file templates and any agent-instruction lines.
Replace placeholders with project facts.

The fenced blocks mirror `KnowledgeSeeds` in `package:wayfinder/adoption.dart`;
a parity test keeps their bytes equal. Adoption fills project facts, the
package's declared id, resolved ref/commit, OKF release and date. Its plan returns
agent instructions for the host to place.

## `wayfinder.json`

At the project root:

```json
{
  "version": 1,
  "profiles": {
    "<profile-id>": {
      "source": {
        "git": "<repository URL>",
        "ref": "<release tag, branch, or commit>",
        "path": "<package directory in that repository>"
      },
      "applies_to": ["./knowledge"]
    }
  }
}
```

The key is the Profile id. Add project `types`, `tags`, `relationships`, and
`actors` to the entry only when a concept needs them. Never copy the
Profile's own vocabulary into this file. Run `wayfinder get` and commit
`wayfinder.lock` with the installed skill directories. `validate` never
fetches or updates them.

## OKF root files

Use these only when the Profile's skill gives no root files of its own.

`knowledge/index.md`:

````markdown
---
okf_version: "<OKF release the Profile implements>"
---

# Bundle

* [Knowledge Log](log.md)
````

`knowledge/log.md`:

````markdown
# Knowledge Log

## <YYYY-MM-DD>

* **Initialization**: Established the knowledge bundle.
````

For generated-index rules, handwrite this index only while there are no concepts.
The first Profile-aware concept write, or `wayfinder validate knowledge --fix`,
generates indexes; okf's generated root omits the seed's `log.md` link. Never edit
generated indexes. Otherwise maintain them per OKF §8.

## `.gitignore`

okf creates its lock file, `.okf.lock`, at the bundle root when it first
writes the bundle. Add this line to the project's `.gitignore` unless
`.gitignore` already lists it:

```gitignore
knowledge/.okf.lock
```

## Agent instructions

Add both blocks to `AGENTS.md` under `## Agent skills`. Append the lines the
Profile's adoption guidance gives to the end of `### Knowledge bundle`.

```markdown
### Knowledge bundle

Durable project documentation and knowledge live in the OKF bundle at
`knowledge/`. `wayfinder.json` binds it to a Profile, and `wayfinder get`
installs each Profile's skill under `.claude/skills/` and `.agents/skills/`.
Start at `knowledge/index.md`, then the area index, then the concept.

Follow the `author-knowledge-bundle` skill before writing anything under
`knowledge/`, including before creating a directory there. It loads the
skill of each Profile in the bundle's chain.

### Wayfinder

Search the bundle before answering questions about the project's decisions,
requirements, conventions, ownership or prior analysis. Use the `wayfinder` MCP
server's `search` tool, or `wayfinder search knowledge "<question>"` when MCP is
unavailable. Search never answers from a stale index: if it reports one, run
`index` and search again. Verify cited passages before relying on them, and run
`validate` before claiming the bundle conforms. The `use-wayfinder` skill has
the details.

Run `wayfinder setup --hooks` once per clone: it registers the MCP server in
`.mcp.json` and refreshes the index after pulls, checkouts and rebases that
change the bundle.
```

**Freshness clarification:** the literal seed above is kept in parity with the
code generator. Current search can serve the previous snapshot during refresh,
with `refresh-in-progress` and possibly `source-changed` notices; without a refresh
it refuses stale indexes. Follow [use-wayfinder](../use-wayfinder/SKILL.md#operations-and-boundaries)
and verify changed sources before relying on them.
