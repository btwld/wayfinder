# Decision

* [Define compatibility in the stability contract and release on main evidence](define-compatibility-and-release-evidence.md) - Public surfaces and obligations live in `docs/stability.md`, and a release needs successful CI from the exact commit's push to main plus hosted CLI resolution.
* [Judge the bundle against its own checkout](judge-the-bundle-against-its-own-checkout.md) - The gate binds the working tree's Profile packages, the lock and installed skills are not committed, and every link, anchor and rule help link must resolve.
* [Keep one living concept per subject](keep-one-living-concept-per-subject.md) - Every concept states current truth and is edited in place; nothing is deprecated or superseded, and the `current-truth` Profile enforces it.
* [Keep published documents at their paths](keep-published-documents-at-their-paths.md) - The contract, the schemas, the user guides, package guides, Profile packages and skills stay where their readers' links point; `docs/` holds only the four user guides and the two schemas.
* [Ration hosted runners](ration-hosted-runners.md) - Linux-only source tests, paused native distribution, zero jobs on a draft, heavy jobs skipped on a non-code diff, and the always-on knowledge job.

# Guide

* [Change a Profile](change-a-profile.md) - The same-change checklist for a Bitwild rule or vocabulary change, stable paths, and the skill wording search.
* [Change the engine contract](change-the-engine-contract.md) - The same-change checklist for a contract change and the review an OKF release needs.
* [Develop in the Dart workspace](develop-in-the-dart-workspace.md) - Workspace layout, ObjectBox installation, the pinned model and native bundle builds.
* [Regenerate schemas and goldens](regenerate-schemas-and-goldens.md) - When and how to regenerate the embedded schemas and each golden file.
* [Release Wayfinder](release-wayfinder.md) - Package tags, preparation, publication order, the read-only preflight, release gates, native distribution and partial recovery.
* [Run the contributor checks](run-contributor-checks.md) - The core commands, the test lanes, formatting, and the two knowledge commands.
