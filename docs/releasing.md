# Release Wayfinder

The public repository is `conceptadev/wayfinder`. All Dart packages use the
`concepta.dev` publisher.

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
The public installers install GitHub's latest release, so publishing a stable
release makes it the default at once; verify before dispatching. Only
application releases may be GitHub's latest release: the installers refuse any
other tag, and the other packages publish no GitHub releases. CI and `wayfinder update` pin a version with
`WAYFINDER_VERSION`. Publish tags at the exact checked commit. Never rename binaries across versions or
overwrite published archives.

`wayfinder_cli` belongs to `concepta.dev` and its pub.dev GitHub publishing
configuration accepts `conceptadev/wayfinder` tags matching
`wayfinder-v{{version}}`. The core package accepts
`wayfinder-core-v{{version}}`. These settings were saved on September 11, 2026;
report automated publishing as configured, not verified, until an upload succeeds.
The embeddings publishing configuration still needs confirmation under
[#66](https://github.com/conceptadev/wayfinder/issues/66). GitHub tag
creation using the built-in workflow token must not be relied on to trigger
publication. Each publish workflow recognizes an already-published version and
skips upload.

## Native distribution

Run **Distribute Wayfinder native release** against the checked application tag,
with the successful source CI run ID. CI must belong to that exact commit and
provide macOS ARM64, Linux x64 and Windows x64 bundles. Fetch tags at checkout so
the publishing adapter can verify the application tag locally.

The cli_pkg/Grinder entry points are `wayfinder-deploy-github` and
`wayfinder-deploy-homebrew`. Project adapters retain complete native libraries,
model, licenses and checksums; cli_pkg's default executable archive is insufficient.
The publisher verifies the existing tag and marks only suffixed versions as
prereleases. GitHub uses its built-in `GITHUB_TOKEN` with `contents: write`.

Homebrew is not a supported channel, and the `conceptadev/homebrew-tap` formula
is not updated. The `publish-homebrew` job stays in the workflow but runs only
when the repository variable `WAYFINDER_HOMEBREW` is `true`, which also requires
`HOMEBREW_TAP_GH_TOKEN` with Contents read/write on that tap. Never print the
token or use it for GitHub release publication.

Native GitHub publication and public installer verification are separate
dependent jobs. A failed job can be retried without republishing packages or
replacing release assets. Reruns verify existing
release bytes and refuse to overwrite mismatches. The installer verification
job uses local scripts with `WAYFINDER_VERSION`, so it exercises exactly the new
version. **Verify public Wayfinder
installation** also runs the public scripts on every installer change to `main`
and weekly, under PowerShell 7 and Windows PowerShell 5.1 on Windows.
Windows/Linux validation and external credentials cannot be inferred from local
macOS results.

## Partial recovery

If only some channels finished, continue from the failed job. Do not recreate
tags, replace published archives or republish a version that pub.dev already
has. The GitHub publisher exits successfully when the existing release bytes
match; a mismatch requires a new version. If public verification fails after
publishing, publish a fixed higher version: the installers resolve GitHub's
latest release, so it supersedes the broken one for every new install. A
published release cannot be demoted — an immutable release accepts edits only to
its title and notes, and `publish-release.sh` refuses to publish a mutable one.
Deleting the release is the only way to withdraw it, and the tag name cannot be
reused afterwards.

Pub.dev publication uses OIDC after the first authenticated CLI upload; report
that path as configured until an automated publication verifies it.
