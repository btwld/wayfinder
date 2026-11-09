# 0.1.0 (unreleased)

- Initial model-free, revision-bound browsing implementation.
- Preserve written computation input targets, including relative paths and
  fragments, separately from their resolved concept IDs and file paths.
- Build native OKF loads from the reader's plain retained bundle with the
  top-level `buildOkfBundle` function, using core's shared file classifier.
  Malformed Markdown/UTF-8 refuses conversion; raw reader bytes stay accessible.
- Mark native retained loads with core's non-filesystem `retainedBundleRoot`;
  validation without an external-observation callback explicitly refuses disk
  fallback. No Profile resolution or implicit validation is performed.
- Capture outside-path existence observations within the granted project root
  for host-owned validation; missing observations remain explicitly unknown.
  Observation changes affect revision even when the byte manifest is unchanged.
- Reuse unchanged captures/projections after one full byte scan plus existence
  checks; retain canonical capture fingerprints via the shared pure function.
- Exclude hidden directories recursively by default; `includeHiddenDirectories`
  opts in, while hidden regular files remain included. The flag does not gate
  bundle loading or validation.
- Existing empty projects open successfully with no bundles; missing projects
  and configured bundles remain `notFound`.
- Match OKF loader inventory and document ordering in retained loads: exclude
  `.okf.lock` at every depth while retaining nested locks for browsing, and sort
  full relative paths so first-use actor findings match ordinary validation.
