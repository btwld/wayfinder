import 'package:path/path.dart' as p;

/// Infers a content type identifier from the file extension of [path].
///
/// Returns a short string like `'dart'`, `'typescript'`, `'markdown'`, etc.
/// Falls back to `'unknown'` for unrecognized extensions.
String inferContentType(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.dart' => 'dart',
      '.ts' || '.tsx' => 'typescript',
      '.js' || '.jsx' => 'javascript',
      '.md' || '.markdown' => 'markdown',
      '.txt' => 'text',
      _ => 'unknown',
    };
