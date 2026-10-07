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
releases cannot collide with application releases. The old standalone validator
release workflow is retired; historical versions and tags remain available.

## Prepare a release

Core `wayfinder` 0.1.0, `wayfinder_cli` 0.1.1, `wayfinder_embeddings` 0.1.1, and
the native `wayfinder-v0.1.1` archives are published. The next prepared release
is described below; preparation does not publish it. Publish changed core or
`wayfinder_embeddings` dependencies before the CLI, then resolve the CLI from
hosted dependencies outside the workspace and run its publish dry run. An
unchanged dependency does not need another release.

### Published: 0.1.1

Shipped 16 September 2026 as GitHub Latest
[`wayfinder-v0.1.1`](https://github.com/btwld/wayfinder/releases/tag/wayfinder-v0.1.1),
with `wayfinder_embeddings-v0.1.1`. Core stayed at published 0.1.0. That patch
fixed oversized-input indexing ([#100](https://github.com/btwld/wayfinder/issues/100),
[#101](https://github.com/btwld/wayfinder/pull/101)) and installer input
validation ([#99](https://github.com/btwld/wayfinder/pull/99)).

### Prepared pre-releases: 0.2.0-beta.1

Core `wayfinder` evaluates rule schemas with Ack `^1.7.0-beta.5`, a
pre-release. Pub requires a package that depends on a pre-release to be one
itself. All three packages are therefore `0.2.0-beta.1`, and every sibling
floor is `^0.2.0-beta.1`. Stable `0.2.0` follows once Ack `1.7.0` is stable.

| Component | Prepared version | Publication tag |
| --- | --- | --- |
| `wayfinder_cli`, native runtime and plugin | 0.2.0-beta.1 | `wayfinder-v0.2.0-beta.1` |
| `wayfinder_embeddings` | 0.2.0-beta.1 | `wayfinder_embeddings-v0.2.0-beta.1` |
| `wayfinder` core | 0.2.0-beta.1 | `wayfinder-core-v0.2.0-beta.1` |

Suffixed versions become GitHub pre-releases. `wayfinder update` offers only
stable `wayfinder-v` releases, and the installers resolve only a stable latest
release. A user gets the beta runtime only by naming it in `WAYFINDER_VERSION`.

The plugin does not follow the GitHub release. Claude Code installs it from
this repository's default branch, because `.claude-plugin/marketplace.json`
sets `"source": "./"`. It refreshes the plugin when the version in
`.claude-plugin/plugin.json` changes, whatever the release flag says. Merging
this version to the default branch therefore moves plugin users to the
0.2.0-beta.1 skills, while `wayfinder update` and the installers keep them on
the latest stable runtime. Run the publication order below right after that
merge, so the beta runtime ships with the skills.

CI requires the CLI pubspec, `wayfinderVersion`, and
`.claude-plugin/plugin.json` to stay aligned. The version lock is applied on
the CLI pubspec, `wayfinderVersion`, `.claude-plugin/plugin.json`, and the CLI
changelog. The CLI depends on `wayfinder_embeddings` `^0.2.0-beta.1`.

The Profile package work puts Bitwild at `bitwild-profile` 2026.3 in package
format 2. The CLI and `wayfinder_embeddings` depend on `wayfinder`
`^0.2.0-beta.1`, so publish core first.
`tool/ci/verify-workspace-floors.py` keeps each sibling floor at the sibling's
own version and fails while a depended-on package has unreleased changes on a
version pub.dev already has.

The embeddings release also makes a breaking API-placement cleanup. Callers
must migrate to receiver-owned chunking, type-owned chunk identity and snapshot
opening, the top-level `embeddingIdentityKey(...)` and
`fuseReciprocalRanks(...)` helpers, and the result/configuration factories
listed in the package changelog. No deprecated aliases or compatibility
wrappers are provided.

The Profile-teaching fix from
[#106](https://github.com/btwld/wayfinder/pull/106), an in-place Profile 2026.2
amendment, was planned as a stable CLI 0.1.2. That release never shipped. The
fix now waits on this beta and stable 0.2.0. Until a release reaches them, the
skills bundled with the 0.1.1 runtime still teach the withdrawn YAML SHOULDs.
The fix withdraws the invented §6.5 producer SHOULDs (quoted timestamps,
block-style mappings, `verified` as a list) so the Profile, examples, and
authoring skill copy OKF §5 spelling. Skills treat an unsupported Profile
release as `NEEDS HUMAN` and refuse to change `concepta_profile`; the method
is implementation guide §5 when that file is present. Graph CLI filters are
documented to match MCP.

**Upgrade:** plugin users get the new skills when this version reaches the
default branch. To run the beta runtime, install with
`WAYFINDER_VERSION=0.2.0-beta.1`. `wayfinder update` moves to stable 0.2.0 once
it ships. Existing 2026.2 bundles stay conformant; no Profile serial, model
change or ObjectBox schema change is needed. Embeddings callers must migrate to
the receiver-owned and type-owned APIs listed in the package changelog; no
deprecated aliases or compatibility wrappers are provided. New writes should
copy YAML shape from OKF §5. Do not bump a bundle's `concepta_profile` as a
repair.

Publication order for this release:

1. Merge this preparation change and obtain successful source CI for that
   exact commit, including all three native platforms.
2. Publish `wayfinder-core-v0.2.0-beta.1`, then
   `wayfinder_embeddings-v0.2.0-beta.1`, at the same checked commit and wait
   for each package to become available on pub.dev.
3. Outside the workspace, resolve the CLI with hosted dependencies (core
   and embeddings 0.2.0-beta.1, no path overrides), analyze it and run
   `dart pub publish --dry-run`.
4. Publish `wayfinder-v0.2.0-beta.1` at the same checked commit and wait for CLI
   package publication.
5. Dispatch **Distribute Wayfinder native release** against `wayfinder-v0.2.0-beta.1`
   with that successful source CI run ID, then verify the public installer jobs.

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
`wayfinder_embeddings-v{{version}}`. All three configurations are verified, not
merely saved: the 0.1.0 release uploaded every package through OIDC on
September 14, 2026, which is the confirmation
[#66](https://github.com/btwld/wayfinder/issues/66) was waiting on. GitHub tag
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

Homebrew is not a supported channel, and the `btwld/homebrew-tap` formula
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

Pub.dev publication uses OIDC after the first authenticated CLI upload. The
0.1.0 release exercised that path for all three packages, so it is verified
rather than merely configured.

Pass the real publish `dart pub publish --force` and nothing else. `--force`
answers the confirmation a workflow cannot and uploads whenever there are no
errors, so a package whose pins draw constraint-width warnings still publishes.
`--ignore-warnings` belongs only on a `--dry-run`, where warnings are otherwise
fatal; pub rejects it on a real publish with exit 64 before uploading anything.
