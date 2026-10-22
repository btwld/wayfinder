import '../profile_package.dart';
import '../project/exception.dart';
import '../project/profile_resolver.dart';

/// What a planned file is for.
enum AdoptionFileKind {
  configuration('configuration'),
  lock('lock'),
  bundle('bundle'),
  skill('skill'),
  gitignore('gitignore');

  const AdoptionFileKind(this.wireValue);
  final String wireValue;
}

/// What applying does to a planned file.
enum AdoptionFileAction {
  /// The file does not exist yet.
  create('create'),

  /// An existing file gains lines; its own bytes stay first.
  append('append'),

  /// A Wayfinder-owned file, such as a marked skill copy, is replaced.
  replace('replace');

  const AdoptionFileAction(this.wireValue);
  final String wireValue;
}

/// One file applying writes, by its project-relative POSIX [path]. [sha256]
/// and [size] describe the bytes the file holds once applied. [content] is
/// the text adoption composes: the whole file, or for [AdoptionFileAction.append]
/// the text appended. A skill file, copied from the Profile's locked commit,
/// carries only its digest.
final class AdoptionFile {
  const AdoptionFile({
    required this.path,
    required this.kind,
    required this.action,
    required this.sha256,
    required this.size,
    this.content,
  });

  final String path;
  final AdoptionFileKind kind;
  final AdoptionFileAction action;

  /// The SHA-256 of the bytes applying writes.
  final String sha256;
  final int size;
  final String? content;

  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind.wireValue,
    'action': action.wireValue,
    'sha256': sha256,
    'bytes': size,
    'content': ?content,
  };
}

/// Something in the project that stops applying. Nothing is written while a
/// plan has one; resolve it and plan again.
final class AdoptionConflict {
  const AdoptionConflict(this.code, this.path, this.message);

  /// One of:
  ///
  /// - `configuration-exists` and `lock-exists`: the project already has a
  ///   `wayfinder.json` or `wayfinder.lock`, so changing it is migration
  ///   work, not adoption;
  /// - `bundle-exists`: the bundle directory holds files and the request
  ///   does not bind an existing bundle;
  /// - `bundle-not-directory` and `bundle-link`: the bundle path or one of
  ///   its parents is a file, or a symbolic link adoption does not write
  ///   through;
  /// - `bundle-okf-invalid`: the existing bundle to bind fails OKF;
  /// - `gitignore-not-file`: `.gitignore` is not a regular file;
  /// - `skill-unowned`: a Profile skill directory exists without the marker
  ///   Wayfinder writes, so it belongs to someone else;
  /// - `skill-foreign`: a skill directory Wayfinder installed that this
  ///   adoption does not install, because its Profile is not in the chain or
  ///   ships no skill there; the next `wayfinder get` would delete it, and
  ///   adoption deletes nothing;
  /// - `skill-root-escapes`: `.claude/skills` or `.agents/skills` resolves
  ///   outside the project.
  final String code;

  /// The project-relative path it concerns.
  final String path;
  final String message;

  Map<String, Object?> toJson() => {
    'code': code,
    'path': path,
    'message': message,
  };

  @override
  String toString() => message;
}

/// Whether adoption seeds the bundle or binds one that is already there.
enum AdoptionBundleMode {
  /// Writes the root files and any seed concepts into a new bundle.
  seed('seed'),

  /// Binds an existing bundle and writes nothing in it.
  bind('bind');

  const AdoptionBundleMode(this.wireValue);
  final String wireValue;
}

/// The Profile a plan binds: the source as `wayfinder.json` will name it,
/// and the release and commit resolution locked.
final class AdoptionProfile {
  const AdoptionProfile({
    required this.id,
    required this.release,
    required this.git,
    required this.ref,
    required this.path,
    required this.commit,
    required this.chain,
  });

  final ProfileId id;
  final String release;
  final String git;

  /// The ref `wayfinder.json` records: the requested one, or the resolved
  /// commit when the request named none.
  final String ref;
  final String path;
  final String commit;

  /// The locked packages of the chain, root ancestor first.
  final List<LockedPackage> chain;

  Map<String, Object?> toJson() => {
    'id': id.value,
    'release': release,
    'source': {'git': git, 'ref': ref, 'path': path},
    'commit': commit,
    'chain': [
      for (final package in chain)
        {
          'id': package.id.value,
          'release': package.release,
          'commit': package.commit,
        },
    ],
  };
}

/// A step of `KnowledgeAdoption.apply`, in the order it runs.
enum AdoptionStep {
  /// Refuses a plan with conflicts or with inputs that changed.
  check('check'),

  /// Writes the seeded bundle, staged and renamed into place.
  bundle('bundle'),

  /// Writes `wayfinder.json`.
  configuration('configuration'),

  /// Writes `wayfinder.lock` and the Profile skills through
  /// `WayfinderProfileResolver.apply`.
  profile('profile'),

  /// Adds the `.okf.lock` line to `.gitignore`.
  gitignore('gitignore'),

  /// Runs the host's own writes, such as its `AGENTS.md` block, when
  /// `apply` was given them; skipped otherwise.
  host('host'),

  /// Validates the adopted bundle. Its outcome never undoes the steps
  /// before it: a gate other than `PASS` leaves adoption incomplete.
  validate('validate');

  const AdoptionStep(this.wireValue);
  final String wireValue;
}

/// How a step ended.
enum AdoptionStepOutcome {
  done('done'),

  /// Nothing to do, as for a bound bundle or a `.gitignore` that already
  /// ignores the lock.
  skipped('skipped'),

  /// The step failed; the steps before it were undone.
  failed('failed'),

  /// The step had finished, and a later failure undid it.
  undone('undone'),

  /// The step had finished, and undoing it after a later failure failed
  /// too, so the project may still hold some of what it wrote.
  undoFailed('undo-failed');

  const AdoptionStepOutcome(this.wireValue);
  final String wireValue;
}

/// One step's report: the project-relative [paths] it wrote or removed.
final class AdoptionStepReport {
  const AdoptionStepReport(
    this.step,
    this.outcome, {
    this.paths = const [],
    this.message,
  });

  final AdoptionStep step;
  final AdoptionStepOutcome outcome;
  final List<String> paths;
  final String? message;

  Map<String, Object?> toJson() => {
    'step': step.wireValue,
    'outcome': outcome.wireValue,
    'paths': paths,
    'message': ?message,
  };
}

/// Applying failed at a step and undid the steps before it, so the project
/// holds no partial bundle unless [steps] reports one `undo-failed`. [code]
/// is the cause's when it was a [WayfinderException]: `adoption-conflict`
/// for a plan with conflicts, `adoption-invalid` for one another
/// adoption's Profile cache planned, `adoption-stale` or `resolution-stale`
/// for one whose inputs changed, `resolution-busy` while a `get` or another
/// adoption holds the project, `cancelled`, and `adoption-failed` for any
/// other error.
final class KnowledgeAdoptionException extends WayfinderException {
  KnowledgeAdoptionException(
    super.code,
    super.message, {
    required this.steps,
    this.cause,
  });

  /// Each step's report, ending with the one that failed.
  final List<AdoptionStepReport> steps;

  /// The error the failed step raised.
  final Object? cause;
}
