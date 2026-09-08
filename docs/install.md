# Installing the Concepta OKF Profile tools

For anyone on a Concepta project who wants to work with a `knowledge/` bundle from
Claude Code. It needs no Dart, no GitHub CLI, and no administrator rights.

You end up with three things:

| What | Why you need it |
| --- | --- |
| `okf` | The OKF engine. Claude Code talks to it (the `okf` MCP server) to read the bundle. |
| `okfp` | The Profile validator. The skills run `okfp validate knowledge` as the automated gate. |
| The `concepta-knowledge` plugin | The skills that author, adopt, and assess a bundle, plus the MCP wiring. |

## Prerequisites

- [Claude Code](https://claude.com/claude-code), installed and signed in.
- On macOS, [Homebrew](https://brew.sh) is the easiest route. The one-line installer
  below works without it.

## 1. Install the binaries

### macOS

With Homebrew:

```sh
brew install conceptadev/tap/okf conceptadev/tap/okfp
```

Homebrew builds both tools from their published source and upgrades them with
`brew upgrade`. The first install fetches a Dart SDK as a build dependency; it
stays inside Homebrew and you never touch it.

Without Homebrew (Apple Silicon only):

```sh
curl -fsSL https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.sh | sh
```

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.sh | sh
```

Homebrew on Linux works too, with the same command as macOS.

### Windows

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.ps1 | iex
```

Then open a new terminal so the updated `PATH` is picked up.

> Windows builds of `okf` are not published yet (tracked in
> [conceptadev/okf#43](https://github.com/conceptadev/okf/issues/43)).
> Until they are, the installer stops with "could not download okf-windows-x64.exe".

The installer puts both binaries in `~/.local/bin` on macOS and Linux, and in
`%LOCALAPPDATA%\okf\bin` on Windows. Set `OKF_INSTALL_DIR` before running it to
choose another directory.

## 2. Install the plugin

In Claude Code:

```
/plugin marketplace add conceptadev/okf-profile-dist
/plugin install concepta-knowledge@okf-profile
```

This installs the three skills and registers the `okf` MCP server. If you installed
the plugin before the binaries, restart Claude Code once the binaries are in place;
until then the server shows as failed, which is expected.

## 3. Check that it worked

In any terminal:

```sh
okf --version
okfp --version
```

Both print a name and a version. In Claude Code, `/mcp` lists `okf`. Open a
repository that has a `knowledge/` bundle and ask Claude to list its concepts; the
answer comes through the `okf` server. Running `okfp validate knowledge` there
reports the automated gate.

## 4. Upgrade

- Homebrew: `brew upgrade okf okfp`.
- One-line installer: run the same command again. It replaces a binary only when
  the pinned version changed, and says "nothing to do" otherwise.
- Plugin: `/plugin marketplace update okf-profile`, then `/plugin update concepta-knowledge`.
  The plugin tracks releases, so an update brings the skills that match the current
  binaries.

## 5. Uninstall

- Homebrew: `brew uninstall okf okfp`.
- macOS and Linux installer: delete `okf` and `okfp` from `~/.local/bin`.
- Windows: delete `%LOCALAPPDATA%\okf`, and remove that path from your user `PATH`
  (Settings → System → About → Advanced system settings → Environment Variables).
- Plugin: `/plugin uninstall concepta-knowledge`.

## If something looks wrong

- **"command not found" right after installing.** The installer tells you when its
  directory is not on your `PATH` and prints the line to add. Open a new terminal
  afterwards. On Windows, a new terminal is always needed after the first install.
- **`/mcp` shows `okf` as failed.** Claude Code could not find `okf` on the `PATH` it
  was started with. Confirm `okf --version` works in a terminal, then restart Claude
  Code from that same terminal.
- **macOS says the app "cannot be opened because the developer cannot be verified".**
  This appears only for binaries downloaded through a browser. The installer and
  Homebrew never trigger it. If you did download by hand, run
  `xattr -d com.apple.quarantine <path-to-binary>` once.
- **Windows SmartScreen warns about the download.** The installer clears the
  mark-of-the-web itself. If you downloaded by hand, right-click the file → Properties
  → Unblock.
- **Something else.** Open an issue in the `okf-profile` repository with the output
  of the command that failed.

## For Dart developers

`okfp` is also published on pub.dev as the `okf_profile` package, and `okf` as
`okf`. With a Dart SDK, `dart pub global activate okf_profile` or
`dart run okf_profile:okfp validate knowledge` inside a repository that depends on
it are equivalent to the binaries above, and that is the path CI jobs with a Dart
SDK use.
