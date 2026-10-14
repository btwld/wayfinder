# Seeding a knowledge bundle

The generic parts of an adoption seed. The selected Profile's skill supplies
the rest: its own root-file templates and any agent-instruction lines.
Replace placeholders with project facts.

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

If a Profile in the chain requires generated indexes, write this index by
hand only while the bundle holds no concepts. Once it holds one,
`wayfinder validate knowledge --fix` writes every generated index. Never
edit a generated index by hand. Without such a Profile, keep each
`index.md` current yourself, as OKF §8 describes.

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
