# Architecture Decision Record

* [Publish upstream findings unchanged](publish-upstream-findings-unchanged.md) - okf's report is published as okf wrote it, Profile results use its finding grammar, and engine health stays in separate diagnostics.
* [Resolve path targets from the loaded inventory](resolve-path-targets-from-the-inventory.md) - One public resolver serves validation and retrieval, with inventory membership inside the bundle and disk lookup only outside it.

# Glossary Definition

* [Engine diagnostic](engine-diagnostic.md) - A `wayfinder/<code>` report about the run itself, never about the bundle.
* [Gate](gate.md) - The one result derived from OKF, Profile findings and diagnostics.
* [OKF Conformance](okf-conformance.md) - The judgment, made by okf under the OKF Specification alone, that a bundle meets OKF's requirements.
* [Profile Conformance](profile-conformance.md) - The gate `PASS` from `wayfinder validate` with that Profile selected.
