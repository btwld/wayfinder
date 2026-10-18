# Release Wayfinder

The public repository is `btwld/wayfinder`. All Dart packages use the
`concepta.dev` publisher.

## Packages and tags

| Package | Purpose | Publication tag | Workflow |
| --- | --- | --- | --- |
| `wayfinder` | Core Profile validation library | `wayfinder-core-v<version>` | `publish-wayfinder.yml` |
| `wayfinder_cli` | `wayfinder` command and MCP server | `wayfinder-v<version>` | `publish-wayfinder-cli.yml` |
| `wayfinder_embeddings` | Reusable retrieval library | `wayfinder_embeddings-v<version>` | `publish-wayfinder-embeddings.yml` |

The application retains `wayfinder-v` tags and native archive names for installer
compatibility. The core uses a distinct tag namespace so independent library
releases cannot collide with application releases.

## Prepare a release

Preparation does not publish. Publish changed core or `wayfinder_embeddings`
dependencies before the CLI, then resolve the CLI from hosted dependencies
outside the workspace and run its publish dry run. An unchanged dependency does
not need another release. `tool/ci/verify-workspace-floors.py` keeps each
sibling floor at the sibling's own version and fails while a depended-on
package has unreleased changes on a version pub.dev already has.

CI requires the CLI pubspec, `wayfinderVersion`, and
`.claude-plugin/plugin.json` to stay aligned. Bump them together with the CLI
changelog.

The plugin does not follow the GitHub release. Claude Code installs it from
this repository's default branch, because `.claude-plugin/marketplace.json`
sets `"source": "./"`. It refreshes the plugin when the version in
`.claude-plugin/plugin.json` changes, whatever the release flag says. Merging
a version bump therefore moves plugin users to the new skills, while
`wayfinder update` and the installers keep them on the latest published
runtime. Run the publication order below right after that merge, so the
runtime ships with the skills.

Publication order:

1. Merge the preparation change and obtain successful source CI for that
   exact commit, including all three native platforms.
2. Publish `wayfinder-core-v<version>`, then
   `wayfinder_embeddings-v<version>`, at the same checked commit and wait for
   each package to become available on pub.dev. Skip any package that did not
   change.
3. Outside the workspace, resolve the CLI with hosted dependencies (no path
   overrides), analyze it and run `dart pub publish --dry-run`.
4. Publish `wayfinder-v<version>` at the same checked commit and wait for CLI
   package publication.
5. Dispatch **Distribute Wayfinder native release** against
   `wayfinder-v<version>` with that successful source CI run ID, then verify
   the public installer jobs.

### Release gates

Run contributor checks, native builds and the CLI/MCP installer checks before
tagging. Keep the CLI pubspec, runtime version and plugin version aligned; CI
enforces it. `wayfinder update` offers only stable `wayfinder-v` releases, so
a suffixed prerelease never reaches it. Claude Code updates the plugin from the
default branch when its version changes, whatever the release flag says, so
merging a version bump ships the skills.
The public installers install GitHub's latest release, so publishing a stable
release makes it the default at once; verify before dispatching. Only
application releases may be GitHub's latest release: the installers refuse any
other tag, and the other packages publish no GitHub releases. CI and `wayfinder update` pin a version with
`WAYFINDER_VERSION`. Publish tags at the exact checked commit. Never rename binaries across versions or
overwrite published archives.

`wayfinder_cli` belongs to `concepta.dev` and its pub.dev GitHub publishing
configuration accepts `btwld/wayfinder` tags matching
`wayfinder-v{{version}}`. The core package accepts
`wayfinder-core-v{{version}}`, and `wayfinder_embeddings` accepts
`wayfinder_embeddings-v{{version}}`. GitHub tag
creation using the built-in workflow token must not be relied on to trigger
publication. Each publish workflow recognizes an already-published version and
skips upload.

## Native distribution

Run **Distribute Wayfinder native release** against the checked application tag,
with the successful source CI run ID. CI must belong to that exact commit and
provide macOS ARM64, Linux x64 and Windows x64 bundles. Fetch tags at checkout so
the publishing adapter can verify the application tag locally.

The cli_pkg/Grinder entry point is `wayfinder-deploy-github`. Its adapter retain complete native libraries,
model, licenses and checksums; cli_pkg's default executable archive is insufficient.
The publisher verifies the existing tag and marks only suffixed versions as
prereleases. GitHub uses its built-in `GITHUB_TOKEN` with `contents: write`.

Homebrew is not a distribution channel. The release publishes no formula.

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
its title and notes. Deleting the release is the only way to withdraw it, and the tag name cannot be
reused afterwards.

Pub.dev publication uses OIDC for all three packages.

Pass the real publish `dart pub publish --force` and nothing else. `--force`
answers the confirmation a workflow cannot and uploads whenever there are no
errors, so a package whose pins draw constraint-width warnings still publishes.
`--ignore-warnings` belongs only on a `--dry-run`, where warnings are otherwise
fatal; pub rejects it on a real publish with exit 64 before uploading anything.
