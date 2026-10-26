# Release Wayfinder

The public repository is `btwld/wayfinder`. All Dart packages use the
`concepta.dev` publisher.

## Packages and tags

| Package | Purpose | Publication tag | Workflow |
| --- | --- | --- | --- |
| `wayfinder` | Core Profile validation library | `wayfinder-core-v<version>` | `publish-wayfinder.yml` |
| `wayfinder_cli` | `wayfinder` command and MCP server | `wayfinder-v<version>` | `publish-wayfinder-cli.yml` |
| `wayfinder_embeddings` | Reusable retrieval library | `wayfinder_embeddings-v<version>` | `publish-wayfinder-embeddings.yml` |
| `wayfinder_dart_chunker` | Dart source chunking for `wayfinder_embeddings` | `wayfinder_dart_chunker-v<version>` | `publish-wayfinder-dart-chunker.yml` |

The application retains `wayfinder-v` tags and native archive names for installer
compatibility. The core uses a distinct tag namespace so independent library
releases cannot collide with application releases.

## Prepare a release

The [1.0 compatibility contract](stability.md) names the prepared public
surfaces and support/migration boundaries. A `1.0.0` preparation commit does
not publish a package, activate an installer release, or establish platform
success without its checks.

Preparation does not publish. Publish changed core or `wayfinder_embeddings`
dependencies before the CLI, then resolve the CLI from hosted dependencies
outside the workspace and run its publish dry run. An unchanged dependency does
not need another release. `wayfinder_dart_chunker` depends on
`wayfinder_embeddings`, and no other package depends on it, so publish it after
the `wayfinder_embeddings` version it requires is on pub.dev; it is off the
CLI's path. `tool/ci/verify-workspace-floors.py` keeps each
sibling floor at the sibling's own version and fails while a depended-on
package has unreleased changes on a version pub.dev already has.
A changelog collects those changes under `# Unreleased`, or under
`# <version> (unreleased)` once the version is raised; the script reads both.
The preparation change renames either heading to `# <version>`.

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
6. If `wayfinder_dart_chunker` changed, publish
   `wayfinder_dart_chunker-v<version>` at the same checked commit.

### Release preflight

Before publication, run the read-only preflight against the clean prepared
commit. It reads public pub.dev metadata and, when supplied, the source CI
run through `gh`; it never creates tags, uploads packages, or dispatches a
workflow:

```sh
python3 tool/ci/release-preflight.py \
  --ci-run-id <successful-source-CI-run-id> \
  --output .context/release-preflight.json
```

The tool requires Python 3.10 or later and Git. Reading a CI run requires `gh`;
the opt-in hosted check also requires Dart. The report distinguishes **passed**,
**blocked** prerequisites, and **failed**
checks. Exit `0` means this preflight passed, `2` means a prerequisite/check is
still missing, and `1` means an actual check failed. A successful PR run is
candidate evidence, not release-eligible source CI: release preparation needs
a successful `ci.yml` **push on `main`** in `btwld/wayfinder` for the exact
checked commit. A run for another repository, workflow or SHA cannot supply
that evidence. Do not use a green older SHA or local Mac checks in its place.

The CLI's sibling floors name the prepared core and embeddings versions.
Until those versions exist on pub.dev, the hosted-dependency and hosted-CLI
gates are **blocked**, not a successful workspace simulation or a demonstrated
CLI defect. Follow the publication order above; a workspace `dart pub publish
--dry-run` checks that local package, not the not-yet-published hosted graph.
The Dart chunker is off the CLI path and keeps its separate first-publication
administrator requirement below.

Once the changed siblings are published, finish the hosted check with:

```sh
python3 tool/ci/release-preflight.py \
  --ci-run-id <successful-source-CI-run-id> \
  --hosted-cli-check \
  --output .context/release-preflight.json
```

The opt-in check stages only regular files read from the captured immutable
Git commit, not the live CLI worktree, in a
fresh temporary directory **outside the workspace**, removes only its
`resolution: workspace`, refuses overrides and pre-existing resolution/build
state, and runs `dart pub get`, `dart pub deps --json`, analysis and `dart pub
publish --dry-run`. The dependency graph must contain hosted siblings, not
workspace/path/Git copies. The preflight accepts the repository's plain
top-level pubspec layout and refuses ambiguous alternate layouts rather than
trying to parse arbitrary YAML. Output is saved at the requested path and
command logs beside it in `<report-stem>.logs/`; the temporary package is
removed. HEAD identity and tracked/untracked source state are rechecked before
staging and before reporting success; edits or a new HEAD require a rerun.
This is a stale-source check, not an adversarial filesystem transaction.
Run without `--output` to print only the report.

A passing preflight is not release completion. All-platform native inputs,
the authorized publication tasks and pinned/public installer verification
remain separate gates. The source CI runs the preflight's offline unit tests,
not this necessarily blocked release-stage command while its own run is pending.

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
`wayfinder-core-v{{version}}`, `wayfinder_embeddings` accepts
`wayfinder_embeddings-v{{version}}`, and `wayfinder_dart_chunker` is to
accept `wayfinder_dart_chunker-v{{version}}`. pub.dev can configure automated
publishing only for a package that exists, so the first
`wayfinder_dart_chunker` version is published by hand: from a clean checkout of
the checked commit, a `concepta.dev` admin runs `dart pub publish` in
`packages/wayfinder_dart_chunker`, moves the package to the publisher, and
configures its GitHub publishing before the next version is tagged. GitHub tag
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

Pub.dev publication uses OIDC for every package, after the first manual
`wayfinder_dart_chunker` upload.

Pass the real publish `dart pub publish --force` and nothing else. `--force`
answers the confirmation a workflow cannot and uploads whenever there are no
errors, so a package whose pins draw constraint-width warnings still publishes.
`--ignore-warnings` belongs only on a `--dry-run`, where warnings are otherwise
fatal; pub rejects it on a real publish with exit 64 before uploading anything.
