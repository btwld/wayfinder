import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../project/profile_skills.dart';

/// What adoption read of a project, by project-relative POSIX path: each
/// entry's type and a digest of its bytes, or of everything below a
/// directory. Applying reads the same paths again and refuses the plan when
/// any differs, so it never writes over a change it did not plan.
final class AdoptionInputs {
  const AdoptionInputs._(this.entries);

  final Map<String, String> entries;

  /// Reads the files adoption writes or checks, the bundle directory and
  /// every ancestor of it, the agent skill roots, and each of the host's
  /// [hostInputs] with everything below it.
  static Future<AdoptionInputs> read(
    String projectRoot,
    String bundle, {
    List<String> hostInputs = const [],
  }) async {
    final segments = p.posix.split(bundle);
    final entries = <String, String>{
      for (final path in const [
        'wayfinder.json',
        'wayfinder.lock',
        '.gitignore',
        '.claude',
        '.agents',
      ])
        path: await _describe(projectRoot, path, recursive: false),
      for (var index = 1; index < segments.length; index++)
        p.posix.joinAll(segments.take(index)): await _describe(
          projectRoot,
          p.posix.joinAll(segments.take(index)),
          recursive: false,
        ),
      bundle: await _describe(projectRoot, bundle, recursive: true),
      for (final root in ProfileSkills.roots)
        root: await _describe(projectRoot, root, recursive: true),
      for (final path in hostInputs)
        path: await _describe(projectRoot, path, recursive: true),
    };
    return AdoptionInputs._(Map.unmodifiable(entries));
  }

  /// The paths whose entries differ from [other]'s, in path order.
  List<String> changedSince(AdoptionInputs other) => [
    for (final path in {...entries.keys, ...other.entries.keys}.sorted())
      if (entries[path] != other.entries[path]) path,
  ];

  static Future<String> _describe(
    String projectRoot,
    String path, {
    required bool recursive,
  }) async {
    final native = p.joinAll([projectRoot, ...p.posix.split(path)]);
    switch (await FileSystemEntity.type(native, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return 'absent';
      case FileSystemEntityType.file:
        return 'file ${sha256.convert(await File(native).readAsBytes())}';
      case FileSystemEntityType.link:
        return 'link ${await Link(native).target()}';
      case FileSystemEntityType.directory when !recursive:
        return 'directory';
      case FileSystemEntityType.directory:
        final lines = <String>[];
        await for (final entity in Directory(
          native,
        ).list(recursive: true, followLinks: false)) {
          final relative = p.posix.joinAll(
            p.split(p.relative(entity.path, from: native)),
          );
          lines.add(switch (entity) {
            File() =>
              '$relative file ${sha256.convert(await entity.readAsBytes())}',
            Link() => '$relative link ${await entity.target()}',
            _ => '$relative directory',
          });
        }
        lines.sort();
        return 'directory ${sha256.convert(utf8.encode(lines.join('\n')))}';
      default:
        return 'other';
    }
  }
}
