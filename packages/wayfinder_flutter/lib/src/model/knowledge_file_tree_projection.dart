import 'dart:collection';

import 'knowledge_files.dart';
import 'knowledge_models.dart';
import 'knowledge_severity.dart';

/// What a tree row stands for.
enum KnowledgeTreeNodeKind { bundle, folder, group, file }

final class KnowledgeFileTreeNode {
  const KnowledgeFileTreeNode({
    required this.id,
    required this.kind,
    required this.path,
    required this.label,
    required this.parentId,
    this.file,
    this.children = const [],
    this.fileCount = 0,
    this.attention,
  });

  /// Unique within one projection: `bundle:<path>`, `directory:<path>`,
  /// `type:<type>` (`type:<bundle>/<type>` under a bundle),
  /// `group:<kind>` (`group:<bundle>/<kind>` under a bundle) for a
  /// synthetic group, or `file:<path>`.
  final String id;
  final KnowledgeTreeNodeKind kind;

  /// A bundle's, folder's or file's path relative to the project root; a
  /// group's type, after its bundle's path when there are several bundles.
  final String path;
  final String label;
  final String? parentId;
  final KnowledgeFileEntry? file;
  final List<KnowledgeFileTreeNode> children;

  /// The files below a bundle, folder or group.
  final int fileCount;

  /// The most severe finding that needs attention in this file, or in any
  /// file below this bundle, folder or group.
  final KnowledgeSeverity? attention;

  bool get isDirectory => kind != KnowledgeTreeNodeKind.file;
}

typedef KnowledgeFileTreeRow = ({KnowledgeFileTreeNode node, int depth});

/// The group concepts without a type fall into.
const knowledgeUntypedGroup = 'Untyped';

/// The group of Markdown files that are not concepts, such as `index.md`.
const knowledgeOtherFilesGroup = 'Other files';

/// The group of attachments, when they are shown.
const knowledgeAttachmentsGroup = 'Attachments';

/// The tree of a project's files, by folder or by concept type.
///
/// With one bundle, its files sit at the top level: the tree does not
/// repeat the only bundle there is. With several [bundles], each is a
/// top-level section holding its own folders or types.
final class KnowledgeFileTreeProjection {
  KnowledgeFileTreeProjection(
    Iterable<KnowledgeFileEntry> entries, {
    this.grouping = KnowledgeTreeGrouping.folders,
    List<KnowledgeBundleSummary> bundles = const [],
  }) {
    final byPath = <String, KnowledgeFileEntry>{};
    for (final entry in entries) {
      byPath.putIfAbsent(entry.path, () => entry);
    }
    files = List.unmodifiable(byPath.values);
    List<KnowledgeFileTreeNode> children(
      Iterable<KnowledgeFileEntry> members, {
      String rootPrefix = '',
      String? parentId,
    }) => switch (grouping) {
      KnowledgeTreeGrouping.folders => _folders(members, rootPrefix, parentId),
      KnowledgeTreeGrouping.types => _types(members, parentId),
    };
    if (bundles.length < 2) {
      roots = children(files, rootPrefix: bundles.firstOrNull?.path ?? '');
    } else {
      final inBundle = {for (final bundle in bundles) bundle.path};
      roots = List.unmodifiable([
        for (final bundle in bundles)
          _parent(
            KnowledgeTreeNodeKind.bundle,
            bundleId(bundle.path),
            bundle.path,
            bundle.name,
            null,
            children(
              files.where((file) => file.bundle == bundle.path),
              rootPrefix: bundle.path,
              parentId: bundleId(bundle.path),
            ),
          ),
        // Files outside every bundle, such as wayfinder.json.
        ...children(files.where((file) => !inBundle.contains(file.bundle))),
      ]);
    }
    void index(List<KnowledgeFileTreeNode> nodes) {
      for (final node in nodes) {
        _byId[node.id] = node;
        index(node.children);
      }
    }

    index(roots);
  }

  final KnowledgeTreeGrouping grouping;
  late final List<KnowledgeFileEntry> files;
  late final List<KnowledgeFileTreeNode> roots;
  final _byId = <String, KnowledgeFileTreeNode>{};

  /// Every row, by its id.
  late final Map<String, KnowledgeFileTreeNode> byId = UnmodifiableMapView(
    _byId,
  );

  /// The id of the row that shows [path].
  static String fileId(String path) => 'file:$path';

  /// The id of the row that shows the folder at [path].
  static String folderId(String path) => 'directory:$path';

  /// The id of the row that shows the bundle at [path].
  static String bundleId(String path) => 'bundle:$path';

  Set<String> get directoryIds => {
    for (final node in byId.values)
      if (node.isDirectory) node.id,
  };

  List<KnowledgeFileTreeNode> _folders(
    Iterable<KnowledgeFileEntry> members,
    String rootPrefix,
    String? parentId,
  ) {
    final prefix = switch (rootPrefix) {
      '' || '.' => '',
      final value => value.endsWith('/') ? value : '$value/',
    };
    final root = _Branch('');
    for (final file in members) {
      final inside = prefix.isNotEmpty && file.path.startsWith(prefix);
      final relative = inside ? file.path.substring(prefix.length) : file.path;
      final segments = relative.split('/');
      var branch = root;
      for (var i = 0; i < segments.length - 1; i++) {
        final folder = segments.take(i + 1).join('/');
        branch = branch.directories.putIfAbsent(
          segments[i],
          () => _Branch(inside ? '$prefix$folder' : folder),
        );
      }
      branch.files[segments.last] = file;
    }
    return _folderChildren(root, parentId);
  }

  List<KnowledgeFileTreeNode> _folderChildren(
    _Branch branch,
    String? parentId,
  ) {
    final result = <KnowledgeFileTreeNode>[];
    final names = branch.directories.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in names) {
      var directory = branch.directories[name]!;
      var label = name;
      while (directory.files.isEmpty && directory.directories.length == 1) {
        final next = directory.directories.entries.single;
        label = '$label/${next.key}';
        directory = next.value;
      }
      final id = folderId(directory.path);
      final children = _folderChildren(directory, id);
      result.add(
        _parent(
          KnowledgeTreeNodeKind.folder,
          id,
          directory.path,
          label,
          parentId,
          children,
        ),
      );
    }
    result.addAll(_fileNodes(branch.files.values, parentId));
    return List.unmodifiable(result);
  }

  /// [members] by concept type; under a bundle (a [parentId]), each
  /// group's path starts with the bundle's.
  List<KnowledgeFileTreeNode> _types(
    Iterable<KnowledgeFileEntry> members,
    String? parentId,
  ) {
    final byType = <String, List<KnowledgeFileEntry>>{};
    final others = <KnowledgeFileEntry>[];
    final attachments = <KnowledgeFileEntry>[];
    final bundle = parentId?.substring('bundle:'.length);
    for (final file in members) {
      if (file.isConcept) {
        (byType[file.type.trim()] ??= []).add(file);
      } else if (file.isAttachment) {
        attachments.add(file);
      } else {
        others.add(file);
      }
    }
    final types = byType.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    KnowledgeFileTreeNode group(
      String name,
      List<KnowledgeFileEntry> files, {
      String? synthetic,
    }) {
      final path = bundle == null ? name : '$bundle/$name';
      final id = synthetic == null
          ? 'type:$path'
          : bundle == null
          ? 'group:$synthetic'
          : 'group:$bundle/$synthetic';
      return _parent(
        KnowledgeTreeNodeKind.group,
        id,
        path,
        name,
        parentId,
        _fileNodes(files, id),
      );
    }

    return List.unmodifiable([
      for (final type in types)
        group(
          type.isEmpty ? knowledgeUntypedGroup : type,
          byType[type]!,
          synthetic: type.isEmpty ? 'untyped' : null,
        ),
      if (others.isNotEmpty)
        group(knowledgeOtherFilesGroup, others, synthetic: 'other'),
      if (attachments.isNotEmpty)
        group(knowledgeAttachmentsGroup, attachments, synthetic: 'attachments'),
    ]);
  }

  static KnowledgeFileTreeNode _parent(
    KnowledgeTreeNodeKind kind,
    String id,
    String path,
    String label,
    String? parentId,
    List<KnowledgeFileTreeNode> children,
  ) {
    var count = 0;
    KnowledgeSeverity? attention;
    for (final child in children) {
      count += child.isDirectory ? child.fileCount : 1;
      final level = child.attention;
      if (level != null &&
          (attention == null || level.index < attention.index)) {
        attention = level;
      }
    }
    return KnowledgeFileTreeNode(
      id: id,
      kind: kind,
      path: path,
      label: label,
      parentId: parentId,
      children: children,
      fileCount: count,
      attention: attention,
    );
  }

  /// [members] as file rows: a folder's `index.md` first, then by label.
  static List<KnowledgeFileTreeNode> _fileNodes(
    Iterable<KnowledgeFileEntry> members,
    String? parentId,
  ) {
    final sorted = members.toList()
      ..sort((a, b) {
        final aIndex = a.kind == KnowledgeFileKind.indexFile ? 0 : 1;
        final bIndex = b.kind == KnowledgeFileKind.indexFile ? 0 : 1;
        if (aIndex != bIndex) return aIndex - bIndex;
        final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel != 0 ? byLabel : a.path.compareTo(b.path);
      });
    return [
      for (final file in sorted)
        KnowledgeFileTreeNode(
          id: fileId(file.path),
          kind: KnowledgeTreeNodeKind.file,
          path: file.path,
          label: file.label,
          parentId: parentId,
          file: file,
          attention: file.attention,
        ),
    ];
  }

  Iterable<String> ancestorsOf(String id) sync* {
    var parent = byId[id]?.parentId;
    while (parent != null) {
      yield parent;
      parent = byId[parent]?.parentId;
    }
  }

  /// The rows to show: a bundle's, folder's or group's children only while
  /// [isExpanded] says so. A [query] keeps the files whose label, path,
  /// type or tags contain it, with what holds them, and always [keep], the
  /// open document, so a filter never hides what is being read.
  List<KnowledgeFileTreeRow> visible(
    bool Function(String id) isExpanded, {
    String query = '',
    String? keep,
  }) {
    final needle = query.trim().toLowerCase();
    final matching = <String, bool>{};
    bool fileMatches(KnowledgeFileEntry file) {
      if (needle.isEmpty || file.path == keep) return true;
      return file.label.toLowerCase().contains(needle) ||
          file.path.toLowerCase().contains(needle) ||
          file.type.toLowerCase().contains(needle) ||
          file.tags.any((t) => t.toLowerCase().contains(needle));
    }

    bool matches(KnowledgeFileTreeNode node) => matching.putIfAbsent(
      node.id,
      () => node.file != null
          ? fileMatches(node.file!)
          : node.children.any(matches),
    );

    final rows = <KnowledgeFileTreeRow>[];
    void visit(List<KnowledgeFileTreeNode> nodes, int depth) {
      for (final node in nodes) {
        if (needle.isNotEmpty && !matches(node)) continue;
        rows.add((node: node, depth: depth));
        // A filter walks into a match, including one inside a collapsed
        // folder, and into [keep]. An empty query still obeys [isExpanded].
        if (node.isDirectory && (isExpanded(node.id) || needle.isNotEmpty)) {
          visit(node.children, depth + 1);
        }
      }
    }

    visit(roots, 0);
    return rows;
  }
}

final class _Branch {
  _Branch(this.path);
  final String path;
  final directories = <String, _Branch>{};
  final files = <String, KnowledgeFileEntry>{};
}
