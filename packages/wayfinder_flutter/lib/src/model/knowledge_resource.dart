final _gitResource = RegExp(r'^git:([0-9a-fA-F]{7,64})(?::(.*))?$');

/// A source resource as people read it. A `git:<commit>[:<path>]` pin is
/// `git · 3023a6d`, with the file's name after it when it names one
/// (`git · 3023a6d · guide.md`); anything else is returned as written.
/// Show the full resource in a tooltip or copy.
String knowledgeResourceLabel(String resource) {
  final match = _gitResource.firstMatch(resource.trim());
  if (match == null) return resource;
  final commit = match[1]!.substring(0, 7).toLowerCase();
  final path = match[2]?.trim() ?? '';
  final name = path.split('/').where((s) => s.isNotEmpty).lastOrNull;
  return name == null ? 'git · $commit' : 'git · $commit · $name';
}

/// Whether [resource] is a `git:<commit>` pin.
bool isKnowledgeGitResource(String resource) =>
    _gitResource.hasMatch(resource.trim());
