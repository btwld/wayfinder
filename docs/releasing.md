# Release Wayfinder

The public repository is `conceptadev/wayfinder`; the public Homebrew tap is
`conceptadev/homebrew-tap`. All Dart packages use the `concepta.dev` publisher.

## Packages and tags

| Package | Purpose | Publication tag | Workflow |
| --- | --- | --- | --- |
| `wayfinder` | Core Profile validation library | `wayfinder-core-v<version>` | `publish-wayfinder.yml` |
| `wayfinder_cli` | `wayfinder` command and MCP server | `wayfinder-v<version>` | `publish-wayfinder-cli.yml` |
| `wayfinder_embeddings` | Reusable retrieval library | `wayfinder_embeddings-v<version>` | `publish-wayfinder-embeddings.yml` |

The application retains `wayfinder-v` tags and native archive names for installer
compatibility. The core uses a distinct tag namespace so independent library
releases cannot collide with application releases. The old standalone validator
release workflow is retired; historical versions and tags remain available.

## Prepare a release

All three packages and the native archives are published at 0.0.1. Publish the
core and `wayfinder_embeddings` before the CLI, then resolve the CLI from hosted
dependencies outside the workspace and run its publish dry run.

Run contributor checks, native builds and the CLI/MCP installer checks before
tagging. Keep the CLI pubspec, runtime version and plugin version aligned; CI
enforces it. Claude Code updates the plugin only when its version changes, and
`wayfinder update` offers only stable `wayfinder-v` releases, so suffixed
prereleases reach neither.
Installer defaults name the latest verified native release; CI sets
`WAYFINDER_VERSION` to test a prepared version. Promote both defaults together
only after the new archives are published and pass public verification. Publish
tags at the exact checked commit. Never rename binaries across versions or
overwrite published archives.

`wayfinder_cli` still needs assignment to `concepta.dev` and OIDC configuration
for `publish-wayfinder-cli.yml` and `wayfinder-v{{version}}`. Update `wayfinder`
OIDC trust to `publish-wayfinder.yml` and `wayfinder-core-v{{version}}`. Its old
trust belonged to the application. Keep embeddings OIDC unchanged. This is
tracked in [#66](https://github.com/conceptadev/wayfinder/issues/66). GitHub tag
creation using the built-in workflow token must not be relied on to trigger
publication. Each publish workflow recognizes an already-published version and
skips upload.

## Native distribution and Homebrew

Run **Distribute Wayfinder native release** against the checked application tag,
with the successful source CI run ID. CI must belong to that exact commit and
provide macOS ARM64, Linux x64 and Windows x64 bundles. Fetch tags at checkout so
the publishing adapter can verify the application tag locally.

The cli_pkg/Grinder entry points are `wayfinder-deploy-github` and
`wayfinder-deploy-homebrew`. Project adapters retain complete native libraries,
model, licenses and checksums; cli_pkg's default executable archive is insufficient.
The publisher verifies the existing tag and marks only suffixed versions as
prereleases. GitHub uses its built-in `GITHUB_TOKEN` with `contents: write`.

Homebrew exposes only `wayfinder`, including `wayfinder validate`; it has no
`okfp` dependency. Existing standalone validator formulas/installations remain
available for legacy consumers. Tap updates require `HOMEBREW_TAP_GH_TOKEN`,
scoped to Contents read/write on `conceptadev/homebrew-tap`. It is not yet
configured. Never print its value or use it for GitHub release publication.

Native GitHub publication, Homebrew and public installer verification are
separate dependent jobs. A failed Homebrew job can be retried without
republishing packages or replacing release assets. Reruns verify existing
release bytes and refuse to overwrite mismatches. The installer verification
job uses local scripts with `WAYFINDER_VERSION` so it can exercise the new
version before the public defaults are promoted. **Verify public Wayfinder
installation** also runs the public scripts on every installer change to `main`
and weekly, under PowerShell 7 and Windows PowerShell 5.1 on Windows. After publishing, run actual Homebrew
installation/upgrade tests before marking the release deployed. Windows/Linux
validation and external credentials cannot be inferred from local macOS results.

## Partial recovery and token rotation

If only some channels finished, continue from the failed job. Do not recreate
tags, replace published archives or republish a version that pub.dev already
has. The GitHub publisher exits successfully when the existing release bytes
match; a mismatch requires a new version. The Homebrew job stays off until
`HOMEBREW_TAP_GH_TOKEN` is stored ([#65](https://github.com/conceptadev/wayfinder/issues/65)); then set the repository
variable `WAYFINDER_HOMEBREW` to `true`.
Leave installer defaults on the previous release until the new archives and
public verification succeed.

Rotate `HOMEBREW_TAP_GH_TOKEN` with a new fine-grained token owned by
`conceptadev`, limited to `homebrew-tap`, Contents read/write, and a bounded
expiry. Replace the Wayfinder Actions secret through the GitHub UI. Never print
the value, commit it or use it for GitHub release publication. Pub.dev
publication uses OIDC after the first authenticated CLI upload; report that
path as configured until an automated publication verifies it.
