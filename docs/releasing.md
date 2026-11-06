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
releases cannot collide with application releases. Profile releases follow that
package's own policy; see the
[Profile change checklist](contributing.md#profile-changes).

## Format-3 rollout window

The published 0.4.0 engine reads format 2. A project tracking Bitwild at
`ref: main` must pin its last format-2 revision before this preparation lands:
`6890664959cad82da01bc4d9baeaf210d819055c`, with path `profiles/bitwild`.
Run `get` with the 0.4.0 engine and commit the refreshed lock and installed
skills. Keep that pin until a compatible 0.5 runtime is available, then move
the source ref and every parent ref to format 3 and refresh again.

The plugin's skill update becomes available from the default branch at merge;
it does not wait for a native release. Keep existing plugin/runtime versions
aligned during this window. Native distribution remains paused; merging the
preparation does not promise immediate native 0.5 availability. Coordinate
runtime availability and project pins before landing the format/plugin flip.

## Prepare a release

The [0.5 compatibility contract](stability.md) names the public surfaces and
support/migration boundaries.

Preparation does not publish. Publish changed core or `wayfinder_embeddings`
dependencies before the CLI, then resolve the CLI from hosted dependencies
outside the workspace and run its publish dry run. An unchanged dependency does
not need another release. `tool/ci/verify-workspace-floors.py` keeps each
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

Each package publication workflow first requires successful push/main source
CI for the exact tagged commit. Passing PR candidate CI alone does not satisfy
that gate. Each workflow also derives its sibling dependencies from the
workspace pubspecs and requires their exact prepared versions on pub.dev,
excluding retracted versions. If this gate trips, publish the missing siblings
first and rerun the workflow on the same immutable tag.
Upload reruns skip an occupied package version, including a retracted one:
retraction does not free its version number. A retracted sibling still fails
the dependency gate and needs a new usable version before dependents publish.

While native distribution is paused, pub.dev-only releases may proceed with
successful push/main CI for the exact commit and hosted-dependency checks; the
three-platform native and public installer gates apply when native distribution
resumes.

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
The native distribution workflow reuses this same CI eligibility check before
downloading artifacts; a successful PR or feature-branch push cannot replace
release-eligible push/main CI.

The CLI's sibling floors name the prepared core and embeddings versions.
Until those versions exist on pub.dev, the hosted-dependency and hosted-CLI
gates are **blocked**, not a successful workspace simulation or a demonstrated
CLI defect. Follow the publication order above; a workspace `dart pub publish
--dry-run` checks that local package, not the not-yet-published hosted graph.

Once the changed siblings are published, finish the hosted check with:

```sh
python3 tool/ci/release-preflight.py \
  --ci-run-id <successful-source-CI-run-id> \
  --hosted-cli-check \
  --output .context/release-preflight.json
```

Sibling names and prepared versions come from the requested root's workspace
and member pubspecs at the captured commit. That same mapping drives the
pub.dev availability gate and hosted graph verification; live metadata edits
cannot change what is checked. Invalid committed metadata is reported with
the completed gates, and dirty source still requires a rerun.

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
tagging. `wayfinder update` offers only stable `wayfinder-v` releases, so
a suffixed prerelease never reaches it.
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
`wayfinder_embeddings-v{{version}}`. GitHub tag creation using the built-in
workflow token must not be relied on to trigger publication. Each publish
workflow recognizes an already-published version and skips upload.

## Native distribution

Native distribution is currently paused under the
[hosted runner policy](contributing.md#hosted-runner-policy). Active Linux CI
does not provide the complete three-platform inputs required below. Resume
the paused platform verification before attempting native publication.

Run **Distribute Wayfinder native release** against the checked application tag,
with the successful source CI run ID. CI must belong to that exact commit and
provide macOS ARM64, Linux x64 and Windows x64 bundles. Fetch tags at checkout so
the publishing adapter can verify the application tag locally.

The cli_pkg/Grinder entry point is `wayfinder-deploy-github`. Its adapter retains complete native libraries,
model, licenses and checksums; cli_pkg's default executable archive is insufficient.
The publisher verifies the existing tag and marks only suffixed versions as
prereleases. GitHub uses its built-in `GITHUB_TOKEN` with `contents: write`.

Homebrew is not a distribution channel. The release publishes no formula.

Native GitHub publication and public installer verification are separate
dependent jobs. A failed job can be retried without republishing packages or
replacing release assets. Reruns verify existing
release bytes and refuse to overwrite mismatches. The installer verification
job uses local scripts with `WAYFINDER_VERSION`, so it exercises exactly the new
version. **Verify public Wayfinder installation** runs on Ubuntu for installer
changes and weekly. Pull requests, pushes, and the weekly run stay on Ubuntu.
Dispatch **Verify public Wayfinder installation** and choose the macOS or
Windows runner to smoke-test the published archives on those platforms; that
choice is the only way those runners start. The **Installer scripts** workflow
checks Windows PowerShell 5.1 and PowerShell 7 on installer pull requests.

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

Pub.dev publication uses OIDC for every package.

Pass the real publish `dart pub publish --force` and nothing else. `--force`
answers the confirmation a workflow cannot and uploads whenever there are no
errors, so a package whose pins draw constraint-width warnings still publishes.
`--ignore-warnings` belongs only on a `--dry-run`, where warnings are otherwise
fatal; pub rejects it on a real publish with exit 64 before uploading anything.
