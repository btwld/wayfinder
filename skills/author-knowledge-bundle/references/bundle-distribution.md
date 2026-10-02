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
When the user requests local evidence, install the selected locked source files
under `.wayfinder/sources/<bundle-name>/`. Link to those actual files from the
installed concepts and retain the upstream revision in citations or attribution.
Keep evidence and license files outside the searchable concept tree. Derived
indexes and Profile caches are local runtime data.

For the current Flutter demo, the concept tree is
`.wayfinder/bundles/flutter-dev-kit/`, evidence lives in
`.wayfinder/sources/flutter-dev-kit/`, and notices live in
`.wayfinder/licenses/flutter-dev-kit/`.

## Capability limits

Check the actual CLI and configuration schema before describing installation as
automatic. Current `wayfinder.json` binds Profiles to bundle paths; it does not
declare a reusable bundle name or Git installation source. A prototype
`wayfinder.bundle.json` is descriptive metadata, not configuration the CLI reads.
Do not claim that `wayfinder add` or a combined bundle installation lock exists
until those contracts are implemented. Label manual demos and partial corpora
clearly, and test the installed copy as well as the publisher.
