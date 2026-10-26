# Preparing a reusable bundle

Use `adopt-knowledge-bundle` to seed its authoring project and this skill to
write and review its concepts. Before preparing an installable copy, validate
the publisher bundle with its own resolved Profile binding and test retrieval
with questions the content actually answers.

## Publisher and consumer files

Keep source acquisition manifests (`sources.json`, `sources.lock.json`),
reconciliation records (`provenance.json`), importer code, full repository
mirrors, staging, and evaluation queries in the publisher's authoring workspace.
They are build inputs; copying a whole authoring project is not installation.

A consumer receives the knowledge concepts, indexes and history, the required
Profile binding and lock, and attribution with the applicable license notices.
When the user requests local evidence, copy the selected locked source files to
a consumer-owned evidence directory. Link to those actual files from the
installed concepts and retain the upstream revision in citations or attribution.
Keep evidence and license files outside the searchable concept tree. Derived
indexes and Profile caches are local runtime data.

## Capability limits

Bundle installation is manual. `wayfinder.json` binds Profiles to existing
bundle paths; it does not install bundle contents from Git or define a combined
bundle-installation lock. Configure the consumer's chosen paths, resolve its
Profile with `wayfinder get`, and validate and test retrieval on the installed
copy. Label partial corpora clearly.
