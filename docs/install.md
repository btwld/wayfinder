# Install Wayfinder

Wayfinder finds and validates knowledge in an existing OKF bundle. Its complete
native installation includes `wayfinder` with built-in Profile validation,
ObjectBox, the embedding runtime, a verified embedding model and license notices.
It does not require Dart, GitHub credentials or administrator access.

The install scripts are the installation path. They install the current native
release. Set `WAYFINDER_VERSION` to install another published release, for
example `0.0.2`.

## Install the native runtime

For macOS Apple Silicon or Linux x64:

```sh
curl -fsSL https://raw.githubusercontent.com/conceptadev/wayfinder/main/tool/install.sh | sh
```

The script installs versioned runtimes under `~/.local/share/wayfinder-runtime`
and exposes `wayfinder` through `~/.local/bin`. It reports if that
command directory needs adding to `PATH`. Set `WAYFINDER_INSTALL_ROOT` and
`WAYFINDER_INSTALL_DIR` to absolute paths to choose different locations. It
refuses to overwrite commands belonging to another installation method.

For Windows x64, run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/conceptadev/wayfinder/main/tool/install.ps1 | iex
```

Windows runtimes live under `%LOCALAPPDATA%\WayfinderRuntime`; set
`WAYFINDER_INSTALL_ROOT` to override that directory. The installer adds the new
runtime's `bin` directory to your user `PATH`. Open a new terminal afterwards.
Other operating system/CPU combinations require their own native verification
before we provide a prebuilt release.

Each installer verifies the archive SHA-256 and all bundled file checksums before
switching commands. Reinstalling repairs missing assets and preserves saved
indexes. Previous runtime directories remain available for running processes;
they may be deleted after those processes have stopped. These checksums detect
corrupt downloads; they are not a claim of code signing or notarization.

## Homebrew

The `conceptadev/tap/wayfinder` formula is no longer updated and still installs
0.0.1-dev.1. Use the install script instead. If you installed the formula, run
`brew uninstall wayfinder` so an older `wayfinder` does not shadow the script's.
Wayfinder includes Profile validation through `wayfinder validate`. Existing
standalone `okfp` installations remain usable, but Wayfinder does not require
them, and previously installed `okfp` commands are not removed automatically.

## Use a knowledge bundle

From a project containing `knowledge/`:

```sh
wayfinder --version
wayfinder validate knowledge
wayfinder index knowledge
wayfinder search knowledge "How do I regain access to my account?"
```

Validation checks the automated gate; contextual Profile judgment remains an
agent/reviewer responsibility. Indexing and search require the full runtime
bundle, so do not copy just the executable. The source repository's illustrative
bundle is `examples/knowledge`; it does not contain a root `knowledge/` directory.

## Agent skills and MCP

The installer also installs the Wayfinder skill family. When the `claude` CLI
is available it installs the `wayfinder` Claude Code plugin, which provides the
skills and the MCP server; otherwise it copies the skills to `~/.claude/skills`.
It also copies them to `~/.agents/skills`, read by Codex and other Agent Skills
clients. Set `WAYFINDER_SKILLS` to `claude`, `agents` or `none` to narrow or
skip this. Wayfinder replaces only skill copies it installed.

```sh
wayfinder skills status
wayfinder skills install --agent=agents
wayfinder setup
```

`wayfinder setup` adds the MCP server to the current project's `.mcp.json` as
`wayfinder mcp knowledge` (`--bundle` selects another path). That is the command
the plugin runs, so Claude Code connects once when both are present. Commit
`.mcp.json` to share it; Claude Code asks for approval before starting project
servers.

`wayfinder setup --hooks` keeps the search index current automatically. It
adds Stop hooks for Claude Code and Codex and git hooks for pulls, checkouts and
rebases; each runs `wayfinder index knowledge --detach`, which returns at once
and re-embeds only changed passages in the background. Claude Code and Codex
run project hooks only after you trust the project (Codex also asks you to
review them with `/hooks`), and each clone enables the git hooks with
`git config core.hooksPath .githooks`. `wayfinder index knowledge --force`
rebuilds an index from scratch.

## Install the Claude Code plugin

Install and verify the commands first. From the consuming project, in Claude Code:

```text
/plugin marketplace add conceptadev/wayfinder
/plugin install wayfinder@wayfinder
```

The plugin includes the author, adopt, assess and use-wayfinder skill family and
registers the Wayfinder MCP server. `/mcp` should list `wayfinder`. Its tools are `validate`,
`index` and `search`. Set `WAYFINDER_KNOWLEDGE_DIR` before launching Claude Code
when the bundle is not `knowledge/`, and `WAYFINDER_EXECUTABLE` when the executable
is outside `PATH`.

### Migrate an existing plugin installation

When moving from the old private marketplace or `wayfinder-dist`, remove its
registration as well as the installed plugin. Claude Code refuses to register
a different repository under an existing marketplace name.

```text
/plugin uninstall concepta-knowledge@wayfinder
/plugin marketplace remove wayfinder
/plugin marketplace add conceptadev/wayfinder
/plugin install wayfinder@wayfinder
```

If you installed `wayfinder@wayfinder` from `wayfinder-dist`, use
`/plugin uninstall wayfinder@wayfinder` for the first command. The remaining
commands are the same. This switches the marketplace to the main public
repository without registering a duplicate server.

If the older marketplace is named `okf-profile`, use
`/plugin uninstall concepta-knowledge@okf-profile` and
`/plugin marketplace remove okf-profile` for the first two commands. Verify
that only `wayfinder@wayfinder` is enabled and `/mcp` lists one Wayfinder server. Normal later upgrades update the `wayfinder` marketplace and
plugin together; they do not require removing the marketplace again.

`wayfinder graph` projects the ordinary OKF relationship graph. Mermaid and
DOT output are text for an external preview; Wayfinder does not render a
picture. Upstream `okf` remains a separate optional tool for write and
concept-authoring operations. Its Windows binary availability is tracked
independently in [okf#43](https://github.com/conceptadev/okf/issues/43).

## Upgrade and troubleshoot

Run `wayfinder update` to install the newest release and refresh the skills and
plugin; `wayfinder update --check` only reports. A Homebrew installation is told
to reinstall with the script, and a Dart installation prints its upgrade command. Interactive commands mention a newer release
at most once a day, using one GitHub Releases API request that sends no bundle
content. It never runs for MCP, CI or non-terminal use; set
`WAYFINDER_NO_UPDATE_CHECK=1` to disable it everywhere.

Run the installer again to install the newest release, or the one
`WAYFINDER_VERSION` names, and to repair an installation.
Restart Claude Code to use the updated executable. An upgrade keeps index data
separate from runtime files. `WAYFINDER_DATA_DIR` selects an explicit data root;
the existing Station-data migration and model environment overrides are described
in the [application package guide](https://pub.dev/packages/wayfinder).

If a command is missing, check its installation directory is on the `PATH` used
to launch your terminal or Claude Code. If an asset is missing, rerun the complete
installer. If search reports a missing or stale index, run `wayfinder index` on
the same bundle. Preserve any operating-system security warning and inspect the
release source; the installer does not disable platform protections.

To uninstall on macOS/Linux, remove the installer-owned command symlinks and
runtime directories. On Windows, remove its recorded runtime bin entry from your
user `PATH` and delete the runtime directory. Remove the plugin separately.
Saved indexes are not removed by uninstalling runtime files.

## Dart developers

```sh
dart pub global activate wayfinder_cli
```

Global activation supports validation and MCP validation. Retrieval additionally
needs the native library/model setup described in the [package guide](https://pub.dev/packages/wayfinder);
the complete native installer handles those assets for end users. The reusable
library is `wayfinder_embeddings`; migrate its dependency and all imports together
when replacing `knowledge_embeddings`.

## Migrate the Dart application package

Before 0.0.1, `wayfinder` was the CLI package. It is now the core library.
Migrate a global Dart installation with:

```sh
dart pub global deactivate wayfinder
dart pub global activate wayfinder_cli
wayfinder --version
```

Script users keep the `wayfinder` command and upgrade with `wayfinder update`.
MCP remains `wayfinder mcp <bundle>` in the CLI package; no extra MCP install is
needed. Library consumers replace `okf_profile` with `wayfinder` and import
`package:wayfinder/wayfinder.dart`. Existing published versions remain available.
