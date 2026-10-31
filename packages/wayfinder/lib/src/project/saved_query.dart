import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'exception.dart';
import 'project_bundles.dart';
import 'query.dart';

/// Loads a local versioned query in the project that contains every selected
/// bundle. Definitions can never select roots or execute code.
Future<WayfinderQuery> loadWayfinderSavedQuery(
  Directory workingDirectory,
  List<ProjectBundle> bundles,
  String id,
) async {
  if (id.length > 64 || !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
    throw const WayfinderException(
      'query-invalid',
      'Saved query ID must be a lowercase slug of at most 64 characters.',
    );
  }
  final project = await WayfinderProject.discover(
    workingDirectory,
    searchAncestors: true,
  );
  final root = project.root;
  final canonicalRoots = await Future.wait(
    bundles.map((b) => Directory(b.root).resolveSymbolicLinks()),
  );
  if (canonicalRoots.any((path) => !p.isWithin(root, path))) {
    throw const WayfinderException(
      'query-scope',
      'Saved queries require a project containing the selected bundles.',
    );
  }
  final requested = p.join(root, '.wayfinder', 'queries');
  final directory = await Directory(requested).resolveSymbolicLinks();
  if (!p.isWithin(root, directory)) {
    throw const WayfinderException(
      'query-scope',
      'Saved query directory leaves the project.',
    );
  }
  final file = File(p.join(directory, '$id.json'));
  final canonical = await file.resolveSymbolicLinks();
  if (!p.isWithin(directory, canonical)) {
    throw const WayfinderException(
      'query-scope',
      'Saved query file leaves the queries directory.',
    );
  }
  final reader = await File(canonical).open();
  late List<int> bytes;
  try {
    bytes = await reader.read(65537);
  } finally {
    await reader.close();
  }
  if (bytes.length > 65536) {
    throw const WayfinderException(
      'query-invalid',
      'Saved query exceeds 64 KiB.',
    );
  }
  final text = utf8.decode(bytes);
  final decoded = jsonDecode(text);
  _rejectDuplicateKeys(text);
  if (decoded is! Map<String, Object?> ||
      (decoded['format'] is! int || decoded['format'] != 1)) {
    throw const WayfinderException(
      'query-invalid',
      'Saved query requires format 1.',
    );
  }
  return WayfinderQuery.fromJson({...decoded}..remove('format'));
}

// jsonDecode validates syntax but normally discards duplicate object keys.
// Walk its valid token stream to reject duplicates, including escaped keys.
void _rejectDuplicateKeys(String text) {
  final stack = <Set<String>?>[];
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '{') stack.add(<String>{});
    if (c == '[') stack.add(null);
    if (c == '}' || c == ']') stack.removeLast();
    if (c != '"') continue;
    final start = i++;
    while (text[i] != '"') {
      if (text[i] == r'\') i++;
      i++;
    }
    var next = i + 1;
    while (next < text.length && text[next].trim().isEmpty) {
      next++;
    }
    if (next < text.length && text[next] == ':') {
      final key = jsonDecode(text.substring(start, i + 1)) as String;
      if (!stack.last!.add(key)) {
        throw const WayfinderException(
          'query-invalid',
          'Saved query contains duplicate JSON keys.',
        );
      }
    }
  }
}
