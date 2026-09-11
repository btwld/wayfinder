# Release Wayfinder and the Profile validator

Source, installation files, plugin documents and native archives all live in the
public `conceptadev/wayfinder` repository; formulas live in
`conceptadev/homebrew-tap`. The packages are published under `concepta.dev`.

## Package publication

- `wayfinder-v{{version}}` publishes the application through
  `publish-wayfinder.yml`.
- `wayfinder_embeddings-v{{version}}` publishes the reusable library through
  `publish-wayfinder-embeddings.yml`.
- The validator keeps `v{{version}}` tags and `release.yml`; its package is
  `okf_profile` and executable is `okfp`.

For each package, bump its pubspec, changelog and applicable version constants,
resolve its hosted dependencies, run the contributor checks and publish dry run,
then tag the checked commit. pub.dev OIDC trust is configured separately per
package. Verification resolves dependencies without publishing credentials;
publishing mints credentials after dependency resolution. Published versions and
existing release assets are not overwritten.

## Complete native runtime distribution

1. Update the Wayfinder version, both installer pins and plugin version together.
   `tool/ci/verify-installer-pins.sh` verifies the application/installer versions.
2. Run CI for the release commit. The stable Linux x64, macOS ARM64 and Windows x64
   jobs build complete bundles, run relocated native CLI/MCP/retrieval checks,
   and test installation without Dart. Installer checks exercise quoted paths,
   repair, saved-index reuse and corrupt-download refusal.
3. Once all CI jobs pass, run **Distribute Wayfinder native release** on that same
   commit, supplying its CI run ID. The workflow rejects a different commit,
   failed CI or another workflow's artifacts.
4. The workflow downloads and verifies all three native archives, then publishes
   them in this repository using its built-in `GITHUB_TOKEN`, recording the build
   commit in `source.json`. The existing `HOMEBREW_TAP_GH_TOKEN` credential pattern is used for Homebrew.
5. Verify the actual public installer URLs and Homebrew installation without
   source-repository credentials. Remove the installation guide's rollout-pending
   notice only after these checks succeed.

The native builder includes the application and `okfp` executables, embedding
model, Dart/llamadart libraries, ObjectBox and dependency notices. The archive
builder writes `SHA256SUMS` for the bundle and an archive `.sha256` sidecar.
Windows needs DLLs beside the executable as well as Dart's `lib` asset directory.
The configuration review is [ObjectBox and native builds](objectbox-build-review.md).

Native publication is resumable: an existing release must contain byte-identical
archives and source metadata. A mismatching release requires a new version.
Homebrew updates run separately, so a tap failure can be retried after publication.

## Independent validator releases

`release.yml` keeps the existing validator verification, native platform matrix,
public GitHub release and pub.dev publication. Validator binaries are attached
to their validator tag in this repository; there is no separate mirror.
`bump-homebrew.sh` bootstraps or updates `Formula/okfp.rb` from the public pub.dev
archive; it updates the URL, version and digest together.

The standalone `okfp` Homebrew formula uses a pinned Dart SDK only during its build.
Wayfinder's formula installs the complete prebuilt bundle and depends on `okfp`
for the command exposed to skills. A Wayfinder release preserves an existing
validator formula, allowing validator releases to advance independently.
Upstream `okf` and its formula remain independently maintained.

## Release tooling and credentials

Like [conceptadev/okf](https://github.com/conceptadev/okf/blob/main/tool/release/tool/grind.dart),
this repository keeps `cli_pkg 2.15.2` and Grinder in `tool/release`, isolated
from the runtime packages. `cli_pkg` provides the standalone compiler tasks;
project deployment tasks publish validated artifacts and update the existing
`conceptadev/homebrew-tap` repository.

Wayfinder uses `wayfinder-deploy-github` and `wayfinder-deploy-homebrew`.
Its complete bundles retain native libraries, model and dependency notices;
`cli_pkg`'s default executable-only archive cannot replace them. Its default
GitHub task also uses bare version tags, while this monorepo keeps package-prefixed
tags. The small deployment adapters preserve those contracts. The validator
continues to use the corresponding `okfp-*` tasks. Pub.dev publishing uses OIDC.

GitHub releases use the built-in `GITHUB_TOKEN` with `contents: write`. Homebrew
updates use `HOMEBREW_TAP_GH_TOKEN`, the same secret name used by OKF, with write
access to `conceptadev/homebrew-tap`. Make that credential available to this
repository through organization or repository Actions secrets. Secrets cannot
be copied out of another repository through the GitHub API. No new GitHub App,
App ID, or private key is required. The tap credential is not yet configured for
Wayfinder; automatic Homebrew updates require it, while native releases do not.
