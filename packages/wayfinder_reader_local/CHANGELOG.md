# 0.1.0 (unreleased)

- Initial model-free, revision-bound browsing implementation.
- Preserve written computation input targets, including relative paths and
  fragments, separately from their resolved concept IDs and file paths.
- Add optional retained-byte Profile assessment inputs; reject uncaptured
  external observations, filtered inventories and malformed content instead of
  validating partial data.
- Reuse unchanged captures/projections after one full byte scan; expose the
  canonical manifest fingerprint through snapshots and captures.
- Add an explicit hidden-directory inventory policy (all regular files remains
  the default). Existing empty projects now open successfully with no bundles;
  missing projects/configured bundles remain `notFound`.
