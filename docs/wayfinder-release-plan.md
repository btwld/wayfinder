> Current package layout: `wayfinder` is the core library, `wayfinder_cli`
> supplies the command and MCP server, and `wayfinder_embeddings` provides
> retrieval. The standalone validator release pipeline is retired. See
> [releasing](releasing.md) for current tags and publication order. The records
> below describe the earlier rename/publication and are historical.

# Wayfinder naming and release plan

Source, plugin, documentation and native releases live together in public
`conceptadev/wayfinder`. Use [installation](install.md) for current user commands
and [releasing](releasing.md) for the deployment procedure. The earlier separate
`wayfinder-dist` repository is obsolete; deletion is pending GitHub identity
confirmation. It is not an installation or publishing dependency.

Decision date: 2026-09-10. Scope: name the existing knowledge application,
rename its repository, and publish the functional CLI under `concepta.dev`.
This is a product/distribution change; no OKF or Profile conventions change.

## Current names and boundaries

| Piece | Name / location | Decision |
| --- | --- | --- |
| Product and repository | Wayfinder / `conceptadev/wayfinder` | Renames the knowledge project formerly hosted at `conceptadev/okf-profile` |
| Dart application | `wayfinder`, `packages/wayfinder_cli/` | Renames the unpublished `station` package |
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
in the [application guide](../packages/wayfinder_cli/README.md).

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
`conceptadev/wayfinder`, then install `wayfinder@wayfinder`. See the
[verified migration sequence](install.md#migrate-an-existing-plugin-installation).
Copied/symlinked skills and existing `okfp` CI gates continue to work.

Existing conformant bundles remain conformant. No Profile release, bundle
migration or taxonomy change is needed. The old `knowledge_embeddings` package is discontinued and points to
`wayfinder_embeddings`; its published versions remain available.

## Current publication and integration state

- `wayfinder 0.0.1-dev.1` and `wayfinder_embeddings 0.0.1-dev.0` are published
  under `concepta.dev`. `okf_profile 0.2.1-dev.0` supplies the validator API;
  stable `0.2.0` remains available.
- The retrieval, CLI, MCP, naming and installation PRs (#58, #59, #60, #63
  and #54) are merged. Historical branch names and ADR filenames remain stable.
- Native archives for Linux x64, macOS ARM64 and Windows x64 are attached to
  [the Wayfinder release](https://github.com/conceptadev/wayfinder/releases/tag/wayfinder-v0.0.1-dev.1).
  Public installation, validation, indexing, search and unchanged-index reuse
  pass on all three platforms. The Concepta tap contains `wayfinder` and `okfp`.
- The plugin is installed from `conceptadev/wayfinder`. Existing marketplace
  registrations must be migrated as described in the installation guide.
- GitHub releases use the built-in repository token. Homebrew automation follows
  OKF's `HOMEBREW_TAP_GH_TOKEN` pattern; no new GitHub App is required. The tap
  secret and the non-Dart teammate walkthrough remain tracked in #53.

The application has published successfully through OIDC. The replacement
library's OIDC trust is configured; its upload path will be exercised on its
next substantive release. Existing package versions and native release assets
remain unchanged.

The rename preserves database UIDs and vector identity. Both schema markers
are accepted during migration, the model override keeps a legacy fallback, and
preparation reuses verified legacy model caches. See the
[library migration guide](../packages/wayfinder_embeddings/README.md#migrating-from-knowledge_embeddings)
and [ObjectBox build review](objectbox-build-review.md).

## Historical initial publication sequence (completed)

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


The sequence above records the original publication, before the library and
plugin received their final Wayfinder names. It is historical evidence, not the
procedure for the next release.
