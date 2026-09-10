# Wayfinder naming and release plan

Decision date: 2026-09-10. Scope: name the existing knowledge application,
rename its repository, and publish the functional CLI under `concepta.dev`.
This is a product/distribution change; no OKF or Profile conventions change.

## Names and boundaries

| Piece | Name / location | Decision |
| --- | --- | --- |
| Product and repository | Wayfinder / `conceptadev/wayfinder` | Renames the knowledge project formerly hosted at `conceptadev/okf-profile` |
| Dart application | `wayfinder`, `packages/wayfinder/` | Renames the unpublished `station` package |
| Executable | `wayfinder` | `validate`, `index`, `search`, and `mcp` retain their behavior |
| MCP server identity | `wayfinder` | Tool names remain `validate`, `index`, and `search` |
| Native bundle | `build/wayfinder/bundle/` | Build with `dart run tool/build_wayfinder.dart` or `melos run wayfinder:build` |
| Retrieval library | `knowledge_embeddings` | Keep its reusable purpose explicit; initial publication is a dependency of Wayfinder |
| Profile library and executable | `okf_profile` / `okfp` | Preserve the published package and consumer validation command |
| Standard and guide | Concepta OKF Profile / existing canonical paths | Preserve release 2026.1, OKF 0.2 authority, and older skill release dispatch |
| Plugin marketplace | `wayfinder` | Install `concepta-knowledge@wayfinder` from `conceptadev/wayfinder` |
| Skill plugin and skill names | `concepta-knowledge` / existing skill family | Preserve existing workflows and responsibilities |
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
filenames and describe the prepublication Station decisions; current usage lives
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
For an existing plugin installation, remove the old marketplace registration
and register `conceptadev/wayfinder`, then install `concepta-knowledge@wayfinder`.
Copied/symlinked skills and existing `okfp` CI gates continue to work.

Existing conformant bundles remain conformant. No Profile release, bundle
migration, taxonomy change, or published-package discontinuation is needed.

## Publication sequence

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

Package-specific workflows use `wayfinder-v{{version}}` and
`knowledge_embeddings-v{{version}}` tags, including prerelease suffixes. Each
workflow checks its tag against the package version, resolves dependencies,
analyzes, tests, and performs a publish dry run without OIDC credentials. A
separate job on the same tag obtains the short-lived OIDC token and uploads with
`--skip-validation`; it does not repeat dependency resolution with the scoped
publishing credential. The embedding dry run allows warnings for reviewed exact
native dependency pins; validation errors still fail.

Enable those exact repository/tag combinations in each new package's pub.dev
Admin page. Exercise the dependency workflow with `0.0.1-dev.1`, which updates
remaining library-facing Station references to Wayfinder; the initial `dev.0`
archive remains immutable. The existing `okf_profile` automation was disabled when inspected;
its separate stable `v{{version}}` release flow is outside this first Wayfinder
prerelease. Reconcile PR #62 before enabling that flow.

Continue no-Dart installation work in #53 / PR #54. Reconcile its installers,
public distribution mirror, Homebrew assets and plugin MCP wiring with Wayfinder
before shipping them. The repository remains private under the current decision;
public source visibility is a separate action. Consequently, repository links
require access until visibility or public distribution is resolved.

See [Dart publication documentation](https://dart.dev/tools/pub/publishing) and
[pub.dev naming policy](https://pub.dev/policy#name-squatting).
