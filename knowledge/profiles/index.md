# Architecture Decision Record

* [Express Profile rules as data](express-rules-as-data.md) - Rules are schemas over parsed facts or named builtins, facts carry no Profile's directory policy, the engine reads one package format, and generated output is pinned to the generator revision.
* [Keep every Profile independent](keep-every-profile-independent.md) - Every Profile is its own package with its own parent and executable rules, and every rule sees the vocabulary of the whole chain plus the project.
* [Read Profile sources from the project's repository or a managed mirror](manage-profile-source-mirrors.md) - Committed objects of the project's own repository are borrowed without a mirror, and abandoned mirrors are collected under sibling locks.

# Glossary Definition

* [Builtin](builtin.md) - A check the engine implements and versions, which any package's rule calls by name with `params`.
* [Chain](chain.md) - A Profile and the ancestors its package names through `extends`, root ancestor first.
* [Effective Profile](effective-profile.md) - The chain and the project binding's additions composed into one set of vocabulary and rules.
* [Profile](profile.md) - A package of vocabulary and rules that adds requirements to OKF and is what `wayfinder validate` enforces.
* [Profile Binding](profile-binding.md) - The project-root `wayfinder.json` entry that selects one Profile for a whole bundle and adds project vocabulary.
* [Profile id](profile-id.md) - A package's one name: finding namespace, configuration key, lock key and installed skill directory.
* [Profile package](profile-package.md) - A directory at one Git revision holding `wayfinder-profile.json` and, optionally, a README, a changelog and a skill.
* [Profile Review](profile-review.md) - A contextual review by a human or agent using a Profile's skill, distinct from validation.
* [Profile Review Report](profile-review-report.md) - A structured summary of a Profile Review that never becomes bundle content.
* [Profile skill](profile-skill.md) - A Profile's agent guidance, shipped in its package and installed by `wayfinder get`.
