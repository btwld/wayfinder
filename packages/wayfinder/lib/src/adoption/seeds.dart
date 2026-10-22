import 'package:path/path.dart' as p;

import '../rules/profile.dart';
import '../wayfinder_config.dart';

/// The generic adoption seed: the project binding, OKF's two root files, and
/// the agent-instruction blocks (guide §2.1). A Profile's adoption guidance
/// may word the first log entry and add instruction lines, and a host
/// passes any concept it names as a seed concept. `KnowledgeAdoption`
/// writes the files and returns the blocks. The adopt-knowledge-bundle
/// skill's `SEEDING.md` shows the same text, and a test keeps the two
/// equal.
abstract final class KnowledgeSeeds {
  /// The conventional bundle directory.
  static const bundle = 'knowledge';

  /// The first log entry's action.
  static const logAction = 'Initialization';

  /// The first log entry's description.
  static const logDescription = 'Established the knowledge bundle.';

  /// `wayfinder.json` with one entry, keyed [profile], that applies the
  /// package at [path] of [git] at [ref] to [bundle], declaring
  /// [vocabulary].
  static String configuration({
    required String profile,
    required String git,
    required String ref,
    required String path,
    String bundle = KnowledgeSeeds.bundle,
    ProjectVocabulary vocabulary = ProjectVocabulary.none,
  }) => const WayfinderConfigEncoder().convert({
    'version': 1,
    'profiles': {
      profile: {
        'source': WayfinderProfileSource(
          git: git,
          ref: ref,
          path: path,
        ).toJson(),
        'applies_to': [WayfinderProfileBinding.explicitBundlePath(bundle)],
        ...vocabulary.toJson(),
      },
    },
  });

  /// The root `index.md` of a bundle that holds no concepts yet. It declares
  /// [okfVersion], the OKF release the Profile implements, and links only
  /// `log.md`. Once the bundle holds a concept, the generated index replaces
  /// it.
  static String rootIndex({required String okfVersion}) =>
      '---\n'
      'okf_version: ${_yamlString(okfVersion)}\n'
      '---\n'
      '\n'
      '# Bundle\n'
      '\n'
      '* [Knowledge Log](log.md)\n';

  /// The root `log.md` with its first entry, dated [date] (`YYYY-MM-DD`).
  static String log({
    required String date,
    String action = logAction,
    String description = logDescription,
  }) =>
      '# Knowledge Log\n'
      '\n'
      '## $date\n'
      '\n'
      '* **$action**: $description\n';

  /// The `### Knowledge bundle` block for `AGENTS.md`, ending with [lines],
  /// the lines the Profile's adoption guidance adds, as one paragraph.
  /// Adoption never writes it; a host or agent places it under
  /// `## Agent skills`.
  static String knowledgeBundleInstructions({
    String bundle = KnowledgeSeeds.bundle,
    List<String> lines = const [],
  }) {
    final root = _bundle(bundle);
    return '### Knowledge bundle\n'
        '\n'
        'Durable project documentation and knowledge live in the OKF bundle at\n'
        '`$root/`. `wayfinder.json` binds it to a Profile, and `wayfinder get`\n'
        "installs each Profile's skill under `.claude/skills/` and `.agents/skills/`.\n"
        'Start at `$root/index.md`, then the area index, then the concept.\n'
        '\n'
        'Follow the `author-knowledge-bundle` skill before writing anything under\n'
        '`$root/`, including before creating a directory there. It loads the\n'
        "skill of each Profile in the bundle's chain.\n"
        '${lines.isEmpty ? '' : '\n${lines.map((line) => '$line\n').join()}'}';
  }

  /// The `### Wayfinder` block for `AGENTS.md`, for a project that also
  /// runs the `wayfinder` command and MCP server. Adoption never writes it,
  /// nor the `.mcp.json` and hooks `wayfinder setup --hooks` writes.
  static String wayfinderInstructions({String bundle = KnowledgeSeeds.bundle}) {
    final root = _bundle(bundle);
    return '### Wayfinder\n'
        '\n'
        "Search the bundle before answering questions about the project's decisions,\n"
        'requirements, conventions, ownership or prior analysis. Use the `wayfinder` MCP\n'
        "server's `search` tool, or `wayfinder search $root \"<question>\"` when MCP is\n"
        'unavailable. Search never answers from a stale index: if it reports one, run\n'
        '`index` and search again. Verify cited passages before relying on them, and run\n'
        '`validate` before claiming the bundle conforms. The `use-wayfinder` skill has\n'
        'the details.\n'
        '\n'
        'Run `wayfinder setup --hooks` once per clone: it registers the MCP server in\n'
        '`.mcp.json` and refreshes the index after pulls, checkouts and rebases that\n'
        'change the bundle.\n';
  }

  /// The `.gitignore` line for the lock file okf keeps at [bundle]'s root.
  static String okfLockIgnore({String bundle = KnowledgeSeeds.bundle}) =>
      '${_bundle(bundle)}/.okf.lock';

  /// [date]'s calendar day as `YYYY-MM-DD`, the form a log heading takes.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _bundle(String bundle) => p.posix.normalize(bundle);

  /// A YAML double-quoted scalar, which JSON's string syntax is.
  static String _yamlString(String value) {
    final buffer = StringBuffer('"');
    for (final rune in value.runes) {
      buffer.write(switch (rune) {
        0x22 => r'\"',
        0x5c => r'\\',
        < 0x20 => '\\u${rune.toRadixString(16).padLeft(4, '0')}',
        _ => String.fromCharCode(rune),
      });
    }
    buffer.write('"');
    return buffer.toString();
  }
}
