# Public-source importer

The importer reads reviewed `sources.json`, resolves `sources.lock.json`, plans
reviewed changes and applies them with precondition checks. Run it with
`dart run tool/knowledge_import/bin/knowledge_import.dart` without arguments
to print the command syntax.

Source IDs are nonblank labels; cache paths hash the structured `[id, repository]`
identity. Existing `<id>/` mirrors from the old layout are no longer read.
After upgrading, the ignored `.wayfinder-import/cache/` directory may be deleted
while no importer is running; the next `resolve` recreates its mirrors. Keep
`sources.json` and `sources.lock.json`, which are outside that disposable cache.
