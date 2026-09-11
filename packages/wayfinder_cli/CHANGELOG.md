# Unreleased

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
