# Concepta OKF Profile — distribution

The public distribution surface of [{{SOURCE_REPO}}](https://github.com/{{SOURCE_REPO}}),
generated from release **{{TAG}}**. Nothing here is edited by hand: every file is
projected by the source repository's release workflow, and the release assets are
the `okfp` binaries that workflow built.

| What | Where |
| --- | --- |
| The `concepta-knowledge` Claude Code plugin (skills + MCP wiring) | [`skills/`](skills/), [`.claude-plugin/`](.claude-plugin/) |
| Installation guide | [`docs/install.md`](docs/install.md) |
| Installers for `okf` and `okfp` | [`tool/install.sh`](tool/install.sh), [`tool/install.ps1`](tool/install.ps1) |
| `okfp` binaries | this repository's [releases](../../releases) |

## Install

```
/plugin marketplace add conceptadev/okf-profile-dist
/plugin install concepta-knowledge@okf-profile
```

macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.ps1 | iex
```

The full guide, including Homebrew, upgrades, and uninstalling, is
[`docs/install.md`](docs/install.md).

## Issues and changes

File issues and propose changes against the source repository. Pull requests here
are overwritten by the next release.
