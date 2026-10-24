import '../profile_package.dart';
import '../project/profile_resolver.dart';
import '../rules/profile.dart';
import 'seeds.dart';

/// Where the Profile package comes from: [path] inside the Git repository
/// [git], at [ref]. A null [ref] means the source's default branch, which
/// adoption pins in `wayfinder.json` as the commit it resolves to, so the
/// binding never moves until someone changes it.
final class AdoptionSource {
  const AdoptionSource({required this.git, required this.path, this.ref});

  /// A repository URL or local path; a relative path resolves from the
  /// project root, as it does in `wayfinder.json`.
  final String git;

  /// The package directory inside the repository.
  final String path;

  /// A branch, tag or commit; null for the default branch.
  final String? ref;
}

/// A concept to seed, as the whole Markdown document [text] at the
/// bundle-relative [path]. Adoption writes it as given and never invents
/// one: the host derives seed concepts from the repository's own code and
/// documentation, as the Profile's adoption guidance names them, and
/// confirms them with the person adopting.
final class AdoptionSeedConcept {
  const AdoptionSeedConcept({required this.path, required this.text});

  /// A POSIX path ending in `.md`, other than an `index.md` or `log.md`.
  final String path;
  final String text;
}

/// What to adopt: the Profile package at [source], applied to the bundle
/// directory [bundle] of the project at [projectRoot].
final class AdoptionRequest {
  const AdoptionRequest({
    required this.projectRoot,
    required this.source,
    this.profile,
    this.bundle = KnowledgeSeeds.bundle,
    this.ignoreOkfLock = true,
    this.bindExisting = false,
    this.concepts = const [],
    this.vocabulary = ProjectVocabulary.none,
    this.logAction = KnowledgeSeeds.logAction,
    this.logDescription = KnowledgeSeeds.logDescription,
    this.instructionLines = const [],
    this.date,
    this.offline = false,
    this.allowFetch,
    this.hostInputs = const [],
  });

  /// The directory that will hold `wayfinder.json`.
  final String projectRoot;

  /// The Profile id the request expects, which keys the `wayfinder.json`
  /// entry; null takes the id the package at [source] declares. When given,
  /// the package must declare it: planning throws
  /// `AdoptionProfileConflictException` (`adoption-profile-conflict`) for
  /// one that declares another.
  final ProfileId? profile;
  final AdoptionSource source;

  /// The bundle directory, relative to [projectRoot], as a POSIX path.
  final String bundle;

  /// Add a `.gitignore` line for the `.okf.lock` file okf keeps at the
  /// bundle root, unless `.gitignore` already ignores it.
  final bool ignoreOkfLock;

  /// Bind a [bundle] directory that already holds files instead of
  /// reporting it as a conflict. A bound bundle must pass OKF, and nothing
  /// is written in it. An absent directory, or one that holds nothing but
  /// okf's `.okf.lock`, is seeded either way.
  final bool bindExisting;

  /// Concepts to seed beside the root files. With any, every index is the
  /// one the Profile's generated-index rules expect, as `validate --fix`
  /// writes it.
  final List<AdoptionSeedConcept> concepts;

  /// The project's own types, tags, relationship names and actors, which
  /// `wayfinder.json` declares for the seed concepts that use them. Never
  /// the Profile's own vocabulary; usually empty at adoption.
  final ProjectVocabulary vocabulary;

  /// The first log entry. A Profile's adoption guidance may word it.
  final String logAction;
  final String logDescription;

  /// Lines a Profile's adoption guidance adds to the end of the
  /// `### Knowledge bundle` block the plan returns.
  final List<String> instructionLines;

  /// The first log entry's day; the adoption's clock when null.
  final DateTime? date;

  /// Never reach the network: planning reads the Profile cache as it is,
  /// without refreshing a branch, and throws
  /// `ProfileFetchRequiredException` (`fetch-required`), naming the fetch,
  /// when it still needs one.
  final bool offline;

  /// Decides each clone or refresh planning would make, when not [offline]:
  /// the named source, its default branch, and every parent the chain
  /// reaches, including one in another repository. A refused fetch throws
  /// `ProfileFetchRequiredException` naming it, before it runs; the fetches
  /// allowed before it stay in the Profile cache. Null allows every fetch.
  /// A host asks the person about the named source before planning, then
  /// about each fetch a refusal names, and plans again with it allowed.
  final ProfileFetchPolicy? allowFetch;

  /// Project files or directories, as project-relative POSIX paths, that
  /// the host read to make the request or that its own step writes, such
  /// as `AGENTS.md`. Planning digests each, as it does the files adoption
  /// writes, and applying refuses the plan with `adoption-stale` before
  /// writing anything when one changed since, absent or present, so the
  /// host's step shares adoption's staleness check.
  ///
  /// Each counts with what it resolves to: a symbolic link in its path, its
  /// own included, is followed, so `CLAUDE.md` linked to `AGENTS.md` counts
  /// with `AGENTS.md`'s bytes, and moving the link counts as a change.
  /// Planning throws `adoption-invalid` for one that resolves outside the
  /// project, to the project directory itself or into `.git`. A directory
  /// counts with every file below it, each read in full when planning and
  /// again when applying, so name the files the host reads rather than a
  /// large directory; a link below it counts by its target, not by what it
  /// points to.
  final List<String> hostInputs;
}
