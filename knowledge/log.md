# Knowledge Log

## 2026-11-18

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
