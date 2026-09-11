# Install Wayfinder

Wayfinder finds and validates knowledge in an existing OKF bundle. Its complete
native installation includes `wayfinder` with built-in Profile validation,
ObjectBox, the embedding runtime, a verified embedding model and license notices.
It does not require Dart, GitHub credentials or administrator access.

The install scripts are the primary installation path. They install the current
native release, 0.0.1. Set `WAYFINDER_VERSION` to install another published
release, for example `0.0.1-dev.1`.

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

## Install with Homebrew

On macOS Apple Silicon or Linux x64:

```sh
brew install conceptadev/tap/wayfinder
```

The formula still installs 0.0.1-dev.1 until the tap update tracked in
[#65](https://github.com/conceptadev/wayfinder/issues/65) is published. Use the
install script for 0.0.1. Wayfinder includes Profile validation through `wayfinder validate`; no separate
validator installation or Dart SDK is required. Upgrade with `brew update` then
`brew upgrade wayfinder`. Existing standalone `okfp` installations remain usable,
but new Wayfinder installations do not require them. Previously installed `okfp`
commands are not removed automatically.

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

## Install the Claude Code plugin

Install and verify the commands first. From the consuming project, in Claude Code:

```text
/plugin marketplace add conceptadev/wayfinder
/plugin install wayfinder@wayfinder
```

The plugin includes the author, adopt and assess skill family and registers the
Wayfinder MCP server. `/mcp` should list `wayfinder`. Its tools are `validate`,
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

Upstream `okf` remains a separate optional tool for OKF graph
and write operations; Wayfinder does not implement those capabilities. Its
Windows binary availability is tracked independently in
[okf#43](https://github.com/conceptadev/okf/issues/43).

## Upgrade and troubleshoot

Run the installer again to install its pinned release or repair that release.
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

Homebrew and script users keep the `wayfinder` command and upgrade normally.
MCP remains `wayfinder mcp <bundle>` in the CLI package; no extra MCP install is
needed. Library consumers replace `okf_profile` with `wayfinder` and import
`package:wayfinder/wayfinder.dart`. Existing published versions remain available.
