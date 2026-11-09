/// OKF file roles, independent of path validation and Profile conventions.
enum BundleFileKind {
  /// Reserved `index.md` document, at any depth.
  indexDocument,

  /// Reserved `log.md` document, at any depth.
  logDocument,

  /// Other case-sensitive `.md` document.
  concept,

  /// Every non-Markdown file; coordination-file exclusion is loader policy.
  asset,
}

/// Classifies a POSIX relative file path using OKF's case-sensitive suffix and
/// reserved basenames. This does not validate the path or read/parse the file.
BundleFileKind classifyBundleFile(String relativePath) {
  if (!relativePath.endsWith('.md')) return BundleFileKind.asset;
  return switch (relativePath.split('/').last) {
    'index.md' => BundleFileKind.indexDocument,
    'log.md' => BundleFileKind.logDocument,
    _ => BundleFileKind.concept,
  };
}
