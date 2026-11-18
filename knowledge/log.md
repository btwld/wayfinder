# Knowledge Log

## 2026-11-18

* **Update**: [Keep published documents at their paths](ways-of-working/keep-published-documents-at-their-paths.md) names `.github/CONTRIBUTING.md` as GitHub's pointer file, not a stub.
* **Creation**: [Release Wayfinder](ways-of-working/release-wayfinder.md) Package tags, preparation, publication order, the read-only preflight, release gates, native distribution and partial recovery.
* **Creation**: [Ration hosted runners](ways-of-working/ration-hosted-runners.md) Linux-only source tests, paused native distribution, zero jobs on a draft, heavy jobs skipped on a non-code diff, and the always-on knowledge job.
* **Creation**: [Develop in the Dart workspace](ways-of-working/develop-in-the-dart-workspace.md) Workspace layout, ObjectBox installation, the pinned model and native bundle builds.
* **Creation**: [Regenerate schemas and goldens](ways-of-working/regenerate-schemas-and-goldens.md) When and how to regenerate the embedded schemas and each golden file.
* **Creation**: [Run the contributor checks](ways-of-working/run-contributor-checks.md) The core commands, the test lanes, formatting, and the two knowledge commands.
* **Creation**: [Change a Profile](ways-of-working/change-a-profile.md) The same-change checklist for a Bitwild rule or vocabulary change, stable paths, and the skill wording search.
* **Creation**: [Change the engine contract](ways-of-working/change-the-engine-contract.md) The same-change checklist for a contract change and the review an OKF release needs.
* **Creation**: [Define compatibility in the stability contract and release on main evidence](ways-of-working/define-compatibility-and-release-evidence.md) Public surfaces and obligations live in `docs/stability.md`, and a release needs successful CI from the exact commit's push to main plus hosted CLI resolution.
* **Creation**: [Bound document capture and inventory the rest](reader/bound-document-capture.md) Only classified Markdown and configuration bytes are captured, and attachments and over-budget documents are inventoried with refusals.
* **Creation**: [Browse read-only through core entry points](reader/browse-read-only-through-core-entry-points.md) Portable values behind `knowledge.dart`, bounded native browsing behind `project.dart`, and the rules for roots, hidden entries and capture reuse.
* **Creation**: [Keep the Flutter reader outside the Dart workspace](reader/keep-the-flutter-reader-outside-the-workspace.md) Reader models and widgets live in `packages/wayfinder_flutter`, free of any design kit and out of the pub workspace.
* **Area created**: [reader](reader/index.md) holds read-only browsing: the core entry points, capture limits, the Flutter SDK.
* **Creation**: [Adopt by plan, then apply](authoring/adopt-by-plan-then-apply.md) A previewable plan and a guarded apply, offline relock, and adoption requests that refuse parent and `.git` segments.
* **Creation**: [Write through one path with a delta gate](authoring/write-through-a-delta-gate.md) One prepare, assess and commit path through okf: the whole candidate passes OKF, and the Profile may gain no error.
* **Area created**: [authoring](authoring/index.md) holds changing a bundle through the libraries: governed writes and adoption.
* **Creation**: [Keep dependencies compatible with hosts](architecture/keep-dependencies-host-compatible.md) Ack 2 and analyzer 13 are adopted for host compatibility, which moves ObjectBox to its 6 preview until the first stable 6 release.
* **Creation**: [Expose embeddable libraries and leave resources to the host](architecture/expose-embeddable-libraries.md) Project and retrieval behavior are public libraries with injected resources, bounded roots, typed failures and host-owned lifecycle.
* **Creation**: [Project the ordinary OKF graph](architecture/project-the-ordinary-okf-graph.md) The graph is OKF's own, with typed relationship edges beside it, projected in the project library and never a source of truth.
* **Creation**: [Serve MCP over the CLI's services](architecture/serve-mcp-over-shared-services.md) Validate, index, search, query and graph over local MCP stdio on the CLI's own services, with no HTTP, authentication or authoring tool.
* **Creation**: [Run explicit local operations from one CLI](architecture/run-explicit-local-operations.md) One CLI validates, indexes and searches; no command downloads a model or rebuilds an index implicitly.
* **Creation**: [Engine compatibility with OKF](architecture/engine-compatibility-with-okf.md) The four-part compatibility test and one row per engine behavior that reads, writes or reports on a bundle, redone for each OKF release.
* **Creation**: [Entry points](architecture/entry-points.md) Which interface serves which caller: the CLI, MCP, each public Dart library and the Flutter SDK, with the document that owns each.
* **Creation**: [Engine contract](architecture/engine-contract.md) The implementation guide and the two published JSON Schemas, ranked below OKF and above every Profile.
* **Creation**: [OKF Specification](architecture/okf-specification.md) The authoritative Open Knowledge Format specification that the engine contract and every Profile build on.
* **Area created**: [architecture](architecture/index.md) holds the system as a whole: the authority chain, the entry points, the CLI, MCP, graph and library boundaries, dependency policy, the OKF compatibility review.
* **Creation**: [Query live concepts exactly](retrieval/query-live-concepts-exactly.md) Read-only structured queries in the core project library, shared by CLI and MCP, with saved query ids in `.wayfinder/queries/`.
* **Creation**: [Bound ingestion and cite resolved sources](retrieval/bound-ingestion-and-cite-resolved-sources.md) Search Markdown shows the shared resolver's source decisions, encoder failure is attributed at its own calls, and ingestion is bounded by digests and a temporary spool.
* **Creation**: [Publish indexes as immutable plain-file generations](retrieval/publish-indexes-as-immutable-generations.md) Snapshot and vector generations with an atomically replaced pointer, readable during refresh, plus the model lookup order.
* **Creation**: [Retrieve with dense search only](retrieval/retrieve-with-dense-search-only.md) Library, CLI, MCP and evaluation searches are dense, with no lexical or hybrid mode and no implicit fallback.
* **Creation**: [Embed with a verified local model](retrieval/embed-with-a-local-model.md) Verified local Arctic Embed XS Q8_0 weights, chosen on size and cost.
* **Area created**: [retrieval](retrieval/index.md) holds finding knowledge: the embedding model, dense search, index storage, ingestion, exact queries.
* **Creation**: [Read Profile sources from the project's repository or a managed mirror](profiles/manage-profile-source-mirrors.md) Committed objects of the project's own repository are borrowed without a mirror, and abandoned mirrors are collected under sibling locks.
* **Creation**: [Keep every Profile independent](profiles/keep-every-profile-independent.md) Every Profile is its own package with its own parent and executable rules, and every rule sees the vocabulary of the whole chain plus the project.
* **Creation**: [Express Profile rules as data](profiles/express-rules-as-data.md) Rules are schemas over parsed facts or named builtins, facts carry no Profile's directory policy, the engine reads one package format, and generated output is pinned to the generator revision.
* **Creation**: [Profile Review Report](profiles/profile-review-report.md) A structured summary of a Profile Review that never becomes bundle content.
* **Creation**: [Profile Review](profiles/profile-review.md) A contextual review by a human or agent using a Profile's skill, distinct from validation.
* **Creation**: [Profile skill](profiles/profile-skill.md) A Profile's agent guidance, shipped in its package and installed by `wayfinder get`.
* **Creation**: [Builtin](profiles/builtin.md) A check the engine implements and versions, which any package's rule calls by name with `params`.
* **Creation**: [Profile Binding](profiles/profile-binding.md) The project-root `wayfinder.json` entry that selects one Profile for a whole bundle and adds project vocabulary.
* **Creation**: [Effective Profile](profiles/effective-profile.md) The chain and the project binding's additions composed into one set of vocabulary and rules.
* **Creation**: [Chain](profiles/chain.md) A Profile and the ancestors its package names through `extends`, root ancestor first.
* **Creation**: [Profile id](profiles/profile-id.md) A package's one name: finding namespace, configuration key, lock key and installed skill directory.
* **Creation**: [Profile package](profiles/profile-package.md) A directory at one Git revision holding `wayfinder-profile.json` and, optionally, a README, a changelog and a skill.
* **Creation**: [Profile](profiles/profile.md) A package of vocabulary and rules that adds requirements to OKF and is what `wayfinder validate` enforces.
* **Area created**: [profiles](profiles/index.md) holds what a Profile is and how one is expressed, composed and fetched.
* **Creation**: [Resolve path targets from the loaded inventory](validation/resolve-path-targets-from-the-inventory.md) One public resolver serves validation and retrieval, with inventory membership inside the bundle and disk lookup only outside it.
* **Creation**: [Publish upstream findings unchanged](validation/publish-upstream-findings-unchanged.md) okf's report is published as okf wrote it, Profile results use its finding grammar, and engine health stays in separate diagnostics.
* **Creation**: [Gate](validation/gate.md) The one result derived from OKF, Profile findings and diagnostics.
* **Creation**: [Engine diagnostic](validation/engine-diagnostic.md) A `wayfinder/<code>` report about the run itself, never about the bundle.
* **Creation**: [Profile Conformance](validation/profile-conformance.md) The gate `PASS` from `wayfinder validate` with that Profile selected.
* **Creation**: [OKF Conformance](validation/okf-conformance.md) The judgment, made by okf under the OKF Specification alone, that a bundle meets OKF's requirements.
* **Area created**: [validation](validation/index.md) holds what a validation result is: conformance, diagnostics, the gate, finding identity, path targets.
* **Initialization**: Established Wayfinder's own bundle under the `current-truth` Profile, which extends Bitwild 2026.3.
* **Area created**: [ways-of-working](ways-of-working/index.md) holds how this repository decides, checks and changes its knowledge.
* **Creation**: [Keep one living concept per subject](ways-of-working/keep-one-living-concept-per-subject.md) Every concept states current truth and is edited in place; nothing is deprecated or superseded, and the `current-truth` Profile enforces it.
* **Creation**: [Judge the bundle against its own checkout](ways-of-working/judge-the-bundle-against-its-own-checkout.md) The gate binds the working tree's Profile packages, the lock and installed skills are not committed, and every link, anchor and rule help link must resolve.
* **Creation**: [Keep published documents at their paths](ways-of-working/keep-published-documents-at-their-paths.md) The contract, the schemas, the user guides, package guides, Profile packages and skills stay where their readers' links point; `docs/` holds only the four user guides and the two schemas.
