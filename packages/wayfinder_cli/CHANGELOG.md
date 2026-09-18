# 0.1.2

- Refresh the plugin and authoring skills so they copy OKF §5 inline
  frontmatter and refuse a silent Profile release change.
- An unsupported Profile release is reported as `NEEDS HUMAN`, not a 2026.2
  judgment failure. Graph CLI filters match the MCP graph tools.

After upgrading, run `wayfinder update` so the plugin and skills refresh.
Existing 2026.2 bundles stay conformant. Profile validation, the embedding
model, the ObjectBox schema, and index configuration are unchanged.

# 0.1.1

- Recover oversized separators and identifiers without aborting bundle indexing
  or editing source files, using `wayfinder_embeddings` 0.1.1.
- Report oversized-input recoveries as structured `warnings` in completed/current
  CLI JSON and MCP index results, and escaped stderr warnings in text mode.
- Replay persisted warnings without loading the model, including foreground calls
  after detached completion; detached status acknowledgements are unchanged.
- Bump application index configuration to 3 for lossless splitting and conditional
  context omission. Existing indexes require one rebuild; source bundles need no edits.
- Harden the public installers' platform and input validation before network
  access, including an explicit error for unknown Windows architectures.

After upgrading, run `wayfinder index <bundle>` once before searching. JSON
consumers must allow the additive `warnings` field. Profile validation, the
embedding model, and the ObjectBox schema are unchanged.

# 0.1.0

- Report Profile 2026.2 and depend on `okf` ^0.5.0. `wayfinder validate` prints
  `Profile 2026.2` and treats a bundle declaring `2026.1` as an unsupported
  release. Date-only timestamps surface as okf's non-blocking
  `okf/timestamp-without-offset` advisory and leave the gate passing.

# 0.0.4

- `wayfinder graph <bundle>` prints the bundle's OKF relationship graph as JSON,
  Mermaid or DOT, filtered by type, path prefix or link resolution. MCP clients
  get a read-only `graph` tool.
- Native installs also report `sources` paths that resolve to nothing as
  validation advisories, and no longer treat adjacent footnote references
  (`[^a][^b]`) as a missing-source error. The pub.dev package gains both
  with the next `wayfinder` core release.

# 0.0.3

- Homebrew installations are directed to the install script because the formula
  is no longer updated.

- `wayfinder index` returns without loading the model when the saved index
  already matches the bundle, and reports `current` in JSON output.
- `index --force` discards the saved index and re-embeds every passage.
- `index --detach` returns at once and indexes in the background only when the
  bundle changed.
- `wayfinder setup --hooks` refreshes the index after Claude Code and Codex
  turns and after git pulls, checkouts and rebases.

# 0.0.2

- `wayfinder skills install|status|remove` installs the bundled agent skills for
  Claude Code, through the `wayfinder` plugin when the `claude` CLI is available,
  and for `~/.agents/skills` readers such as Codex.
- `wayfinder setup` adds the Wayfinder MCP server to a project's `.mcp.json`.
- `wayfinder update` upgrades installer-managed runtimes and refreshes skills
  and the plugin. Interactive commands mention a newer release at most daily.
- Native bundles include the skill family.

# 0.0.1

Application moves from wayfinder to wayfinder_cli. The executable remains wayfinder, including MCP. Core validation comes from wayfinder; native installs no longer require okfp.

# Changelog

## 0.0.1-dev.1

- Use the `wayfinder_embeddings` package for retrieval.
- Preserve saved indexes across the library rename; write compatible schema markers.
- Support `WAYFINDER_EMBEDDING_MODEL` while retaining the legacy override.
- Align package setup, native builds and documentation with Wayfinder naming.

## 0.0.1-dev.0

- Validates explicit local OKF bundles through the existing OKF Profile checks.
- Indexes and searches bundle passages using verified local embeddings and
  persistent ObjectBox storage, preserving original citations.
- Reuses compatible vectors and rejects stale or incompatible indexes.
- Serves validation, indexing, and search over MCP stdio.
- Keeps contextual Profile judgment explicitly unassessed by automated checks.

Indexing and search require separately prepared model weights and native
libraries. The Dart package does not include the complete native runtime bundle.
