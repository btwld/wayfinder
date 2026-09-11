# Wayfinder naming and release plan

Decision date: 2026-09-10. Scope: name the existing knowledge application,
rename its repository, and publish the functional CLI under `concepta.dev`.
This is a product/distribution change; no OKF or Profile conventions change.

## Current names and boundaries

| Piece | Name / location | Decision |
| --- | --- | --- |
| Product and repository | Wayfinder / `conceptadev/wayfinder` | Renames the knowledge project formerly hosted at `conceptadev/okf-profile` |
| Dart application | `wayfinder`, `packages/wayfinder/` | Renames the unpublished `station` package |
| Executable | `wayfinder` | `validate`, `index`, `search`, and `mcp` retain their behavior |
| MCP server identity | `wayfinder` | Tool names remain `validate`, `index`, and `search` |
| Native bundle | `build/wayfinder/bundle/` | Build with `dart run tool/build_wayfinder.dart` or `melos run wayfinder:build` |
| Retrieval library | `wayfinder_embeddings` | Replaces the initially published `knowledge_embeddings`; generic APIs remain reusable |
| Profile library and executable | `okf_profile` / `okfp` | Preserve the published package and consumer validation command |
| Standard and guide | Concepta OKF Profile / existing canonical paths | Preserve release 2026.1, OKF 0.2 authority, and older skill release dispatch |
| Plugin marketplace | `wayfinder` | Install `wayfinder@wayfinder` from `conceptadev/wayfinder` |
| Skill plugin and skill names | `wayfinder` / existing skill family | Migrate the plugin identity; preserve skill invocations, workflows and responsibilities |
| Publisher | `concepta.dev` | Existing Concepta verified publisher |
| Application license | BSD 3-Clause | Package-local license; embedding library retains its BSD attribution |
| Profile/repository license | Existing Apache-2.0 | This rename does not relicense the Profile or third-party assets |

The separate `conceptadev/station` delivery platform is a different project.
Its repository and contents are not part of this rename. Git branches retain
existing names, including the three reviewed implementation branches.

## Migration

Replace development invocations of `station` with `wayfinder`, including
`dart run wayfinder:wayfinder`, executable paths in MCP host configurations,
and references to `packages/wayfinder`. Build and native verification scripts
use `wayfinder` in their filenames. Accepted ADR-0010/0011 retain their historical
filenames and record the prototype naming history; current usage lives
in the [application guide](../packages/wayfinder/README.md).

`WAYFINDER_DATA_DIR` replaces `STATION_DATA_DIR`. Defaults use `Wayfinder` on
macOS/Windows and `wayfinder` on Linux. The default therefore starts a new index:
run `wayfinder index <bundle>` to rebuild. Existing Station data is left intact.
For an intentional reuse, set `WAYFINDER_DATA_DIR` to the old app-data directory;
the existing compatibility checks still decide whether reindexing is required.
Do not run both tools against that directory concurrently. No knowledge source
files are moved or rewritten by the rename.

Update Git remotes to `https://github.com/conceptadev/wayfinder.git`.
GitHub redirects the old repository URL; use the new URL in maintained links.
For an existing plugin installation, uninstall the old `concepta-knowledge`
plugin, remove the old marketplace registration, register
`conceptadev/wayfinder-dist`, then install `wayfinder@wayfinder`. See the
[verified migration sequence](install.md#migrate-an-existing-plugin-installation).
Copied/symlinked skills and existing `okfp` CI gates continue to work.

Existing conformant bundles remain conformant. No Profile release, bundle
migration or taxonomy change is needed. The old retrieval package can be
discontinued with a replacement pointer after the new library is published.

## Initial publication sequence (completed)

1. Run analysis, formatting, package tests, the example validation gate, and the
   relocated native CLI/MCP probes against the renamed package.
2. Check archives with `dart pub publish --dry-run`. Preserve all Dart sources:
   the embedding package's model download ignore must be `/models/`, because
   an unanchored `models/` also excludes `lib/src/models/`.
3. Publish functional `knowledge_embeddings 0.0.1-dev.0` first. The exact native
   dependency pins are intentional for the tested runtime and generated schema;
   retain them despite pub's advisory about constraint width.
4. Publish `okf_profile 0.2.1-dev.0`, which exports the existing validator API.
   Published `0.2.0` does not export that API, so require `^0.2.1-dev.0` in
   Wayfinder. This does not change Profile rules or validation behavior.
5. Resolve Wayfinder against hosted dependencies outside the workspace, verify
   validation and executable installation, and publish `wayfinder 0.0.1-dev.0`.
   This ships the existing CLI/MCP implementation; it is not a placeholder.
6. Transfer both new packages to the existing `concepta.dev` publisher using
   their pub.dev Admin pages. Initial uploads use the authorized Google account;
   pub does not publish a new package directly to a verified publisher.
7. Verify package versions, publisher ownership, and a clean hosted install.

Published source archives contain the package's code, generic fixtures and
package documentation. They exclude downloaded model weights, native libraries,
local indexes, build output, and `.context/`. Global activation supports
validation and MCP discovery. Full semantic retrieval additionally requires the
prepared native/model assets described in the application guide.

## Integration and subsequent distribution

The release-preparation branch is stacked on the reviewed Station MCP branch.
Merge the existing stack in order (#58, #59, #60), retargeting dependencies to
`main`, then integrate this rename. Do not merge or rewrite the old branches as
part of a repository rename. Release automation still publishes `okf_profile`
using its existing stable `v<version>` tags; do not use those tags for Wayfinder.

Package-specific workflows now use `wayfinder-v{{version}}` and
`wayfinder_embeddings-v{{version}}`. Verification resolves dependencies, analyzes,
tests and dry-runs without OIDC credentials. A separate job publishes the checked
tag with `--skip-validation` and does not repeat credentialed resolution.
The original `knowledge_embeddings` tags and published archives remain historical
releases. Reconcile PR #62 before enabling the separate `okf_profile` stable
`v{{version}}` publication flow.

Continue no-Dart installation work in #53 / PR #54. Reconcile its installers,
public distribution mirror, Homebrew assets and plugin MCP wiring with Wayfinder
before shipping them. The repository remains private under the current decision;
public source visibility is a separate action. Consequently, repository links
require access until visibility or public distribution is resolved.

See [Dart publication documentation](https://dart.dev/tools/pub/publishing) and
[pub.dev naming policy](https://pub.dev/policy#name-squatting).

## Initial release result

The initial release completed on 2026-09-10:

- `wayfinder 0.0.1-dev.0` is published under `concepta.dev`.
- `knowledge_embeddings 0.0.1-dev.0` bootstrapped the package; `0.0.1-dev.1`
  completed the library documentation rename and was published through GitHub
  OIDC in [run 34541277082](https://github.com/conceptadev/wayfinder/actions/runs/34541277082).
- `okf_profile 0.2.1-dev.0` supplies the public validator API under the existing
  `concepta.dev` publisher; stable `0.2.0` remains available.
- Wayfinder and knowledge_embeddings trust the renamed repository and their
  package-specific tag patterns. No long-lived publishing secret was added.
- A fresh isolated pub cache installed `wayfinder 0.0.1-dev.0` from hosted
  dependencies, reported the correct version, validated the example bundle,
  and completed MCP initialization with the `wayfinder` server identity.

The source changes are on `chore/station-publication` for integration after the
existing implementation stack. The branch name is retained; product names do not
require rewriting branch history. The repository remains private, and the
no-Dart installer/distribution work remains tracked in #53 / PR #54.

## Follow-up package and plugin migration

The initial decision to preserve `knowledge_embeddings` and `concepta-knowledge`
was superseded by the complete Wayfinder naming plan. The current implementation
uses `wayfinder_embeddings` and the `wayfinder` plugin. Published
`wayfinder_embeddings 0.0.1-dev.0` under `concepta.dev` and configured its exact
package-specific OIDC trust. Published `wayfinder 0.0.1-dev.1` through GitHub OIDC
against the hosted replacement library. Fresh-cache application/consumer checks
and bidirectional saved-index checks passed; `knowledge_embeddings` is now
discontinued with `wayfinder_embeddings` as its replacement. Existing package
versions remain available. The new library's OIDC upload is to be exercised on
its next substantive release.

The rename keeps database UIDs and vector identity unchanged. Both schema marker
names are supported during migration; the new model override has a legacy
fallback, and preparation reuses verified legacy model caches. See the
[library migration guide](../packages/wayfinder_embeddings/README.md#migrating-from-knowledge_embeddings)
and [ObjectBox build review](objectbox-build-review.md).

The public distribution repository and no-Dart installers remain integration
work in #53/#54 until actual unauthenticated install checks pass. Source repository
visibility stays private. Publication and distribution results must be recorded
here when completed; intended names alone do not establish an available channel.

The public plugin repository now exists. An isolated Claude Code installation
successfully migrated from `concepta-knowledge@wayfinder`, loaded all three
skills with only one enabled plugin, and connected its Wayfinder MCP server.
A separate clean configuration fetched the public marketplace over HTTPS with
Git credentials disabled. Native public release `wayfinder-v0.0.1-dev.1` now includes verified archives for
all three supported platforms. The public macOS installer and Homebrew install
pass. Initial publication used the authorized maintainer CLI; the GitHub App
automation still awaits owner re-authentication and a successful workflow run.
