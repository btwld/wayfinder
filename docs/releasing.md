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
   commit in `source.json`. A separate App token is needed only to update Homebrew.
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

## Release App configuration

Only the Homebrew cross-repository jobs require a private organization-owned GitHub App with
**Contents: read and write** and implicit metadata access, installed only on
`homebrew-tap`. No webhook or user authorization is needed.
Store its App ID in the source repository's `RELEASE_APP_ID` Actions variable and
its private key in `RELEASE_APP_PRIVATE_KEY`. Workflow tokens remain scoped to the
selected repositories; do not store a developer's personal GitHub token in CI.

The App setup is pending GitHub's owner re-authentication. The existence of the
workflow does not prove that cross-repository publishing credentials work. The
first successful Homebrew update is the operational verification. Native GitHub
release publication does not require this App.
