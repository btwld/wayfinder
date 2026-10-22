import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../diagnostics.dart';
import '../profile_package.dart';
import '../rules/profile.dart';
import '../validation.dart';
import '../wayfinder_config.dart';
import 'cancellation.dart';
import 'exception.dart';
import 'file_lock.dart';
import 'git.dart';
import 'profile_skills.dart';
import 'profile_status.dart';

/// One package as `wayfinder get` pinned it. [extendsId] names another
/// entry of the same lock, so the lock stays flat however deep a chain is.
final class LockedPackage {
  const LockedPackage({
    required this.id,
    required this.release,
    required this.git,
    required this.requestedRef,
    required this.commit,
    required this.path,
    this.extendsId,
  });

  final ProfileId id;
  final String release;
  final String git;
  final String requestedRef;
  final String commit;
  final String path;
  final ProfileId? extendsId;

  WayfinderProfileSource get source =>
      WayfinderProfileSource(git: git, ref: requestedRef, path: path);

  SkillRevision get revision => (id: id, release: release, commit: commit);

  /// A locked package is identified by its source, (git, requested ref,
  /// path), as pub identifies a git dependency, and then by its commit.
  /// `select` and `_checkout` look entries up by that source, so two refs
  /// at one commit are still two packages and may not share one entry.
  bool isSameRevision(LockedPackage other) =>
      git == other.git &&
      requestedRef == other.requestedRef &&
      path == other.path &&
      commit == other.commit;

  static LockedPackage? _tryParse(ProfileId id, Object? value) {
    if (value case <String, Object?>{
      'source': final String git,
      'requested_ref': final String requestedRef,
      'resolved_commit': final String commit,
      'path': final String path,
      'release': final String release,
    } when RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      if (value.length == 5) {
        return LockedPackage(
          id: id,
          release: release,
          git: git,
          requestedRef: requestedRef,
          commit: commit,
          path: path,
        );
      }
      if (value.length == 6 && value['extends'] is String) {
        final extendsId = _profileIdOrNull(value['extends']! as String);
        if (extendsId != null) {
          return LockedPackage(
            id: id,
            release: release,
            git: git,
            requestedRef: requestedRef,
            commit: commit,
            path: path,
            extendsId: extendsId,
          );
        }
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'source': git,
    'requested_ref': requestedRef,
    'resolved_commit': commit,
    'path': path,
    'release': release,
    'extends': ?extendsId?.value,
  };

  @override
  String toString() => '$git $path at $requestedRef ($commit)';
}

/// `wayfinder.lock`: every package a project's Profiles need, one revision
/// per Profile id, keyed by id.
final class ProfileLock {
  const ProfileLock({
    required this.configurationSha256,
    required this.packages,
  });

  final String configurationSha256;
  final Map<ProfileId, LockedPackage> packages;

  /// Null for anything but the current shape, including an older lock,
  /// which `get` then rewrites.
  static ProfileLock? tryParse(Object? value) {
    if (value case <String, Object?>{
      'lock_version': 1,
      'configuration_sha256': final String sha,
      'packages': final Map<String, Object?> rawPackages,
    } when value.length == 3 && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      final packages = <ProfileId, LockedPackage>{};
      for (final entry in rawPackages.entries) {
        final id = _profileIdOrNull(entry.key);
        final package = id == null
            ? null
            : LockedPackage._tryParse(id, entry.value);
        if (package == null) return null;
        packages[package.id] = package;
      }
      if (packages.isEmpty) return null;
      return ProfileLock(
        configurationSha256: sha,
        packages: Map.unmodifiable(packages),
      );
    }
    return null;
  }

  /// Packages in id order, so the same packages always write the same bytes.
  Map<String, Object?> toJson() => {
    'lock_version': 1,
    'configuration_sha256': configurationSha256,
    'packages': {
      for (final id
          in packages.keys.toList()
            ..sort((left, right) => left.value.compareTo(right.value)))
        id.value: packages[id]!.toJson(),
    },
  };

  /// The chain of [id], root ancestor first, by following `extends`. Null
  /// when an entry is missing or the pointers loop, which only a hand-edited
  /// lock can do.
  List<LockedPackage>? chainOf(ProfileId id) {
    final chain = <LockedPackage>[];
    for (ProfileId? current = id; current != null;) {
      final package = packages[current];
      if (package == null || chain.any((member) => member.id == current)) {
        return null;
      }
      chain.insert(0, package);
      current = package.extendsId;
    }
    return chain;
  }
}

/// How a resolution reached the network for a Profile source.
enum ProfileFetchKind {
  /// Cloned a source the cache did not hold yet.
  clone('clone'),

  /// Refreshed a cached source's refs (`git remote update`).
  refresh('refresh');

  const ProfileFetchKind(this.wireValue);
  final String wireValue;
}

/// One Git fetch a resolution made into the Profile cache: [git] as the
/// configuration or a package spells it, [location] as Git reached it
/// ([WayfinderProfileSource.locationOf]), and the [ref] it was looking for,
/// or null for the source's default branch.
final class ProfileFetch {
  const ProfileFetch({
    required this.kind,
    required this.git,
    required this.location,
    required this.ref,
  });

  final ProfileFetchKind kind;
  final String git;
  final String location;
  final String? ref;

  Map<String, Object?> toJson() => {
    'kind': kind.wireValue,
    'git': git,
    'location': location,
    'ref': ref,
  };

  @override
  String toString() =>
      '${kind.wireValue} $git${ref == null ? '' : ' for $ref'}';
}

/// Whether a resolution may make [fetch], asked just before it runs. A
/// chain reaches each parent's source only once the child's package is
/// read, so a plan asks about every source it reaches, including a parent
/// in another repository that the configuration never names. Answer from
/// what the person already approved: the source's mirror stays locked
/// while the policy runs, so it must not wait for them. A refused fetch
/// throws [ProfileFetchRequiredException]; ask then, and plan again.
///
/// It is all a host needs for per-source consent. Every Git command a
/// resolution runs that can reach the network, a mirror's `clone` or its
/// `remote update`, follows the policy's yes for that command's
/// [ProfileFetch.location], which is the URL or path Git reaches. Every
/// other command reads a mirror already in the cache. Compare the location
/// with [WayfinderProfileSource.locationOf] of each source the person
/// approved.
typedef ProfileFetchPolicy = bool Function(ProfileFetch fetch);

/// `fetch-required`: resolving needs [fetch], and the request is offline or
/// its [ProfileFetchPolicy] refused it. Nothing was fetched for it; the
/// fetches made before it stay in the Profile cache.
final class ProfileFetchRequiredException extends WayfinderException {
  ProfileFetchRequiredException(this.fetch, {required bool offline})
    : super(
        'fetch-required',
        'Resolving needs to ${fetch.kind.wireValue} the Profile source '
            '${fetch.git}${fetch.ref == null ? '' : ' for ${fetch.ref}'}, '
            'and ${offline ? 'fetching is not allowed' : 'that fetch was not '
                      'allowed'}.',
      );

  /// The fetch resolving needs next.
  final ProfileFetch fetch;
}

final class ProfileResolutionResult {
  const ProfileResolutionResult({
    required this.projectRoot,
    required this.configPath,
    required this.lockPath,
    required this.reused,
    required this.upgraded,
    required this.packages,
    required this.skills,
    required this.removedSkills,
  });

  final String projectRoot;
  final String configPath;
  final String lockPath;

  /// The lock and every skill were already current, and every package came
  /// from the cache without fetching. After a plan that left skills alone,
  /// it says nothing of the skills.
  final bool reused;
  final bool upgraded;

  /// One revision per Profile id across every configured chain.
  final Map<ProfileId, LockedPackage> packages;

  /// One per locked package that ships a skill, in id order.
  final List<MaterializedSkill> skills;

  /// Project-relative directories deleted because their Profile no longer
  /// ships a skill or is no longer locked.
  final List<String> removedSkills;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'configuration': configPath,
    'lock': lockPath,
    'reused': reused,
    'upgraded': upgraded,
    'packages': {
      for (final package in packages.values) package.id.value: package.toJson(),
    },
    'skills': [for (final skill in skills) skill.toJson()],
    'removed_skills': removedSkills,
  };
}

/// What `get` would write, from [WayfinderProfileResolver.plan]. Planning
/// fetches into the Profile cache when a ref must move but writes nothing
/// in the project; [WayfinderProfileResolver.apply] writes it, and refuses
/// when the configuration, lock or cache it read has changed since.
final class ProfileResolutionPlan {
  ProfileResolutionPlan._({
    required this.projectRoot,
    required this.configPath,
    required this.lockPath,
    required this.upgrade,
    required this.lockedOnly,
    required this.includesSkills,
    required this.fetched,
    required this.fetches,
    required this.packages,
    required this.lockChanged,
    required this.skills,
    required this.removedSkills,
    required this.skillDirectories,
    required String lockText,
    required String configurationSha256,
    required String? lockSha256,
    required Map<ProfileId, List<SkillFile>> pending,
    required Map<String, String> snapshots,
  }) : _lockText = lockText,
       _configurationSha256 = configurationSha256,
       _lockSha256 = lockSha256,
       _pending = pending,
       _snapshots = snapshots;

  final String projectRoot;
  final String configPath;
  final String lockPath;
  final bool upgrade;

  /// The plan resolved exactly the commits `wayfinder.lock` pins, and leaves
  /// the lock as it is.
  final bool lockedOnly;

  /// Whether applying installs and prunes Profile skills. False for a plan
  /// made with `skills: false`, which read no skill file, refused no skill
  /// directory, and whose apply leaves every skill directory as it is.
  final bool includesSkills;

  /// Planning cloned or refreshed a Profile source.
  final bool fetched;

  /// Each clone or refresh planning made into the Profile cache, in order.
  final List<ProfileFetch> fetches;

  /// One revision per Profile id across every configured chain.
  final Map<ProfileId, LockedPackage> packages;

  /// Whether applying rewrites `wayfinder.lock`.
  final bool lockChanged;

  /// One per locked package that ships a skill, in id order; `written` is
  /// whether applying replaces its directories, never when the plan leaves
  /// skills alone ([includesSkills] is false).
  final List<MaterializedSkill> skills;

  /// Project-relative skill directories applying would delete; none when
  /// the plan leaves skills alone.
  final List<String> removedSkills;

  /// Every directory a locked package's skill installs into, with its
  /// state, in [skills] order and then in `ProfileSkills.roots` order: the
  /// protected paths applying writes, or would refuse. A plan that installs
  /// skills throws [ProfileSkillDirectoriesException] for an
  /// [ProfileSkillDirectoryState.unmarked] or
  /// [ProfileSkillDirectoryState.outside] directory, so it lists those only
  /// when it leaves skills alone, where they are reported rather than
  /// refused.
  final List<ProfileSkillDirectory> skillDirectories;

  final String _lockText;
  final String _configurationSha256;
  final String? _lockSha256;
  final Map<ProfileId, List<SkillFile>> _pending;

  /// Each Profile package file the plan read, by its cache path, with the
  /// SHA-256 of its bytes.
  final Map<String, String> _snapshots;

  Map<String, Object?> toJson() => {
    'project': projectRoot,
    'configuration': configPath,
    'lock': lockPath,
    'upgrade': upgrade,
    'locked_only': lockedOnly,
    'includes_skills': includesSkills,
    'fetched': fetched,
    'fetches': [for (final fetch in fetches) fetch.toJson()],
    'lock_changed': lockChanged,
    'packages': {
      for (final package in packages.values) package.id.value: package.toJson(),
    },
    'skills': [for (final skill in skills) skill.toJson()],
    'removed_skills': removedSkills,
    'skill_directories': [
      for (final directory in skillDirectories) directory.toJson(),
    ],
  };
}

/// Resolves Git Profile sources, persists their lock metadata, and selects
/// a bundle's Profile from them.
///
/// Its state lives under [dataDirectory]:
///
/// - `profiles/<sha256(location)>/`, a bare mirror of each source, and
///   beside it `profiles/<sha256(location)>.lock`, held while a planner
///   clones, refreshes or reads it; another planner waits for up to
///   [mirrorLockTimeout];
/// - `profiles/packages/<sha256(commit, path)>.json`, the package file of
///   each package a plan read, so [select] reads files and never runs Git;
///   [restoreCachedPackages] fills it from the mirrors for a cache an
///   earlier Wayfinder wrote;
/// - `projects/<sha256(root)>.get.lock`, held while [apply], [resolve] or
///   an adoption (`package:wayfinder/adoption.dart`) changes a project, and
///   recording that project's root.
///
/// Reading a Profile package runs its rules' tests, which run the package's
/// own patterns. Each read, whether a plan's or [select]'s, therefore runs
/// on an isolate of its own and fails with `profile-timeout` once it runs
/// past [packageTimeout] ([ProfilePackage.parseWithin]).
final class WayfinderProfileResolver {
  WayfinderProfileResolver({
    required this.dataDirectory,
    GitRunner git = runGit,
    this.packageTimeout = ProfilePackage.parseTimeout,
  }) : _runGit = git;

  final Directory dataDirectory;
  final GitRunner _runGit;

  /// How long reading one Profile package, its rules' tests included, may
  /// run before it fails with `profile-timeout`.
  final Duration packageTimeout;

  /// How long a planner waits while another holds a Profile source's mirror.
  static const mirrorLockTimeout = Duration(seconds: 120);

  /// Resolves every binding's chain, composes it so a broken chain fails
  /// here rather than at validation, locks one revision per Profile id, and
  /// reads each locked package's skill from its locked commit. Fetches only
  /// when the mirror is missing, a ref must move, or [upgrade] asks, and
  /// only what [allowFetch] allows (every fetch when it is null); never
  /// writes in the project.
  ///
  /// With [lockedOnly], the plan resolves exactly the commits
  /// `wayfinder.lock` pins and leaves the lock as it is, as a host does to
  /// bring a project's locked Profiles onto a machine. It fetches a source
  /// only when its mirror is missing or lacks the locked commit, and never
  /// re-resolves a ref, so the lock's commits stay as written; the refresh
  /// that fetches a missing commit still updates the mirror's own refs.
  /// Before any Git command it throws
  /// [ProfileLockChangeRequiredException] (`lock-change-required`) when the
  /// lock as written would change: when it is missing, its configuration
  /// hash is stale, it lacks a binding's chain or records another source
  /// for it, or it holds a package no chain reaches. A package whose own
  /// file disagrees with the lock it was locked from, as only an edited lock
  /// has, is refused the same way once it is read. [upgrade] cannot be set
  /// with it. [ProfileLockChangeRequiredException.change] says what would
  /// change.
  ///
  /// With [skills] false, the plan leaves Profile skills alone, as a host
  /// does to fill the Profile cache without touching `.claude/skills` or
  /// `.agents/skills`: it reads no skill file from a mirror, refuses no
  /// skill directory, and its apply writes and deletes none.
  /// [ProfileResolutionPlan.skillDirectories] still reports each skill
  /// directory's state, unmarked and outside ones included, rather than
  /// throwing [ProfileSkillDirectoriesException] for them.
  Future<ProfileResolutionPlan> plan(
    String project, {
    bool upgrade = false,
    bool lockedOnly = false,
    bool skills = true,
    ProfileFetchPolicy? allowFetch,
    WayfinderCancellation? cancel,
  }) async {
    if (upgrade && lockedOnly) {
      throw ArgumentError('A locked-only plan does not upgrade.', 'upgrade');
    }
    final (:projectRoot, :configFile) = await _locate(project);
    return _planFile(
      projectRoot,
      configFile,
      upgrade: upgrade,
      lockedOnly: lockedOnly,
      skills: skills,
      allowFetch: allowFetch,
      cancel: cancel,
    );
  }

  /// Writes [plan]: the lock, the skills it lists, and the removals, or
  /// only the lock for a plan that leaves skills alone. Holds the project's
  /// `get` lock and throws [ProfileResolutionBusyException]
  /// (`resolution-busy`) while another holder has it. Throws
  /// `resolution-stale` when `wayfinder.json`, `wayfinder.lock` or a
  /// package file the plan read in the cache has changed since [plan], and
  /// [ProfileSkillDirectoriesException] when a skill directory it would
  /// replace is no longer Wayfinder's.
  Future<ProfileResolutionResult> apply(ProfileResolutionPlan plan) =>
      _withProjectLock(plan.projectRoot, () => _apply(plan));

  /// `wayfinder get` and `upgrade`: [plan] then [apply] under one hold of
  /// the project's `get` lock. Converges: with the same configuration, lock
  /// and cache it fetches nothing and writes nothing in the project.
  Future<ProfileResolutionResult> resolve(
    String project, {
    bool upgrade = false,
    ProfileFetchPolicy? allowFetch,
    WayfinderCancellation? cancel,
  }) async {
    final (:projectRoot, :configFile) = await _locate(project);
    return _withProjectLock(
      projectRoot,
      () async => _apply(
        await _planFile(
          projectRoot,
          configFile,
          upgrade: upgrade,
          allowFetch: allowFetch,
          cancel: cancel,
        ),
      ),
    );
  }

  /// Validation's selection: the bundle's binding, its chain from the lock,
  /// each package from the local cache, composed. Never runs Git, never
  /// fetches, never writes, and reports every failure as exactly one
  /// diagnostic. A chain member's skill that `get` has not installed at the
  /// locked commit is a warning, so the rules still run. Without
  /// [configPath] it binds through the nearest `wayfinder.json` above
  /// [bundle], never above [projectRoot] when one is given
  /// ([WayfinderProjectConfig.bind]).
  Future<ProfileSelection> select(
    String bundle, {
    String? configPath,
    String? projectRoot,
  }) async {
    final BoundBundle bound;
    try {
      bound = await WayfinderProjectConfig.bind(
        bundle,
        configPath: configPath,
        projectRoot: projectRoot,
      );
    } on BundleBindingException catch (error) {
      return UnselectedProfile([error.diagnostic]);
    }
    final (:status, :selection) = await _assess(
      projectRoot: bound.projectRoot,
      raw: bound.source,
      lock: await _readProjectLock(bound.projectRoot),
      binding: bound.binding,
      config: bound.config,
    );
    return selection ?? UnselectedProfile([status.diagnostic!]);
  }

  /// Where each Profile the project at [project] binds stands on this
  /// machine, one [ProfileBindingStatus] per `wayfinder.json` binding in id
  /// order: [ProfileBindingState.resolved], or why [select] selects nothing
  /// for its bundles, with the diagnostic it reports.
  ///
  /// Offline and read-only, like [select]: it reads `wayfinder.json`,
  /// `wayfinder.lock`, the Profile cache and the installed skills' markers,
  /// never runs Git and writes nothing. It parses each cached package as
  /// [select] does, bounded by [packageTimeout]. It checks no bundle
  /// directory. Throws `config-invalid` when `wayfinder.json` cannot be read
  /// or parsed, and `profile-unresolved` when [project] holds none.
  ///
  /// Beside the state and diagnostic, each binding reports as data what a
  /// consent gate names: why the lock would change
  /// ([ProfileBindingStatus.lockChange]), whether each chain member's
  /// mirror and package file are in the cache
  /// ([ProfileBindingStatus.copies]), and each skill directory with its
  /// state ([ProfileBindingStatus.skillDirectories]).
  Future<ProfileResolutionStatus> status(String project) async {
    final (:projectRoot, :configFile) = await _locate(project);
    final String raw;
    final WayfinderProjectConfig config;
    try {
      raw = await configFile.readAsString();
      config = WayfinderProjectConfig.parse(raw);
    } on FileSystemException catch (error) {
      throw WayfinderException(
        'config-invalid',
        'Cannot read ${configFile.path}: ${error.message}.',
      );
    } on WayfinderConfigException catch (error) {
      throw WayfinderException('config-invalid', error.message);
    }
    final location = ProjectFileLocation(
      path: p.basename(configFile.path),
      file: configFile.path,
    );
    final ids = config.profiles.keys.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    // One read of the lock for the whole status, so the project's
    // lockChange and every binding's describe the same lock even while a
    // `get` replaces it.
    final lock = await _readProjectLock(projectRoot);
    ProfileLockChange? lockChange;
    if (lock.error case final error?) {
      lockChange = ProfileLockChange(
        ProfileLockChangeKind.lockMissing,
        error.message,
      );
    } else {
      try {
        _checkLockedOnly(raw, lock.lock);
      } on ProfileLockChangeRequiredException catch (error) {
        lockChange = error.change;
      }
    }
    return ProfileResolutionStatus(
      projectRoot: projectRoot,
      configPath: configFile.path,
      lockPath: p.join(projectRoot, 'wayfinder.lock'),
      lockChange: lockChange,
      bindings: List.unmodifiable([
        for (final id in ids)
          (await _assess(
            projectRoot: projectRoot,
            raw: raw,
            lock: lock,
            binding: config.profiles[id]!,
            config: location,
          )).status,
      ]),
    );
  }

  /// What [select] does for [binding] of the configuration [raw] at
  /// [config], in the project at [projectRoot] whose `wayfinder.lock` read
  /// as [lock]: its status, and the selection when it is resolved. Every
  /// failure is the one diagnostic [select] reports, at [config].
  Future<({ProfileBindingStatus status, SelectedProfile? selection})> _assess({
    required String projectRoot,
    required String raw,
    required _LockRead lock,
    required WayfinderProfileBinding binding,
    required ProjectFileLocation config,
  }) async {
    var chain = const <LockedPackage>[];
    var missing = const <LockedPackage>[];
    var copies = const <ProfileLocalCopy>[];
    ({ProfileBindingStatus status, SelectedProfile? selection}) failed(
      ProfileBindingState state,
      String message, {
      DiagnosticCode code = DiagnosticCode.profileUnresolved,
      DiagnosticRemedy? remedy,
      ProfileLockChange? lockChange,
    }) => (
      status: ProfileBindingStatus(
        id: binding.id,
        source: binding.source,
        appliesTo: binding.appliesTo,
        state: state,
        chain: chain,
        missing: missing,
        copies: copies,
        lockChange: lockChange,
        diagnostic: EngineDiagnostic(
          code,
          message,
          location: config,
          remedy: remedy,
          lockChange: lockChange?.kind,
        ),
      ),
      selection: null,
    );
    ({ProfileBindingStatus status, SelectedProfile? selection}) lockChanges(
      ProfileLockChange change,
    ) => failed(
      change.state,
      change.reason,
      remedy: DiagnosticRemedy.resolveProfiles,
      lockChange: change,
    );

    if (lock.error case final error?) {
      // A lock that exists but cannot be read: the error is the reason, and
      // what fixes it is the host's to find.
      return failed(
        ProfileBindingState.lockMissing,
        error.message,
        lockChange: ProfileLockChange(
          ProfileLockChangeKind.lockMissing,
          error.message,
        ),
      );
    }
    switch (_lockedChain(lock.lock, raw, binding)) {
      case final ProfileLockChange change:
        return lockChanges(change);
      case final List<LockedPackage> locked:
        chain = List.unmodifiable(locked);
    }
    try {
      copies = List.unmodifiable([
        for (final locked in chain)
          ProfileLocalCopy(
            locked: locked,
            location: _gitLocation(locked.git, projectRoot),
            hasMirror: await _repositoryCache(
              _gitLocation(locked.git, projectRoot),
            ).exists(),
            hasPackage: await _snapshotFile(
              locked.commit,
              locked.path,
            ).exists(),
          ),
      ]);
      missing = List.unmodifiable([
        for (final copy in copies)
          if (!copy.hasPackage) copy.locked,
      ]);
      final packages = <ProfilePackage>[];
      for (final (index, locked) in chain.indexed) {
        if (missing.contains(locked)) {
          final hasMirror = copies[index].hasMirror;
          return failed(
            ProfileBindingState.cacheMissing,
            hasMirror
                ? 'Profile ${locked.id} at ${locked.git} (${locked.commit}) '
                      'has no package file in the local cache, as in a cache '
                      'an earlier Wayfinder wrote.'
                : 'Profile ${locked.id} at ${locked.git} (${locked.commit}) '
                      'is not in the local cache.',
            remedy: hasMirror
                ? DiagnosticRemedy.resolveProfilesFromMirror
                : DiagnosticRemedy.resolveProfiles,
          );
        }
        final package = await _readCached(locked);
        if (package.release != locked.release) {
          return lockChanges(
            ProfileLockChange(
              ProfileLockChangeKind.packageChanged,
              'Profile ${locked.id} at ${locked.commit} declares release '
              '${package.release}; the lock records ${locked.release}.',
              profile: binding.id,
              packages: [locked.id],
            ),
          );
        }
        if (!_matchesLockedParent(
          package.parent,
          child: locked,
          lockedParent: index == 0 ? null : chain[index - 1],
        )) {
          return lockChanges(
            ProfileLockChange(
              ProfileLockChangeKind.packageChanged,
              'Profile ${locked.id} at ${locked.commit} declares another '
              'parent than the lock records.',
              profile: binding.id,
              packages: [locked.id],
            ),
          );
        }
        packages.add(package);
      }
      final profile = _compose(binding.id, packages, binding.project);
      final skillDirectories = <ProfileSkillDirectory>[];
      final notes = <EngineDiagnostic>[];
      for (final (index, locked) in chain.indexed) {
        if (packages[index].skill == null) continue;
        final directories = await ProfileSkills.inspect(
          projectRoot,
          locked.revision,
        );
        skillDirectories.addAll(directories);
        final stale = [
          for (final directory in directories)
            if (directory.installed != locked.revision) directory.path,
        ];
        if (stale.isEmpty) continue;
        notes.add(
          EngineDiagnostic(
            DiagnosticCode.profileSkillStale,
            'Profile ${locked.id} skill in ${stale.join(' and ')} is not the '
            'locked commit ${locked.commit}.',
            location: config,
            remedy: DiagnosticRemedy.resolveProfiles,
          ),
        );
      }
      return (
        status: ProfileBindingStatus(
          id: binding.id,
          source: binding.source,
          appliesTo: binding.appliesTo,
          state: ProfileBindingState.resolved,
          chain: chain,
          copies: copies,
          notes: List.unmodifiable(notes),
          skillDirectories: List.unmodifiable(skillDirectories),
        ),
        selection: SelectedProfile(
          profile,
          config: config,
          projectRoot: projectRoot,
          commits: {for (final locked in chain) locked.id: locked.commit},
          notes: notes,
        ),
      );
    } on WayfinderProfileResolutionException catch (error) {
      return failed(
        switch (error.diagnostic) {
          DiagnosticCode.profileInvalid => ProfileBindingState.packageInvalid,
          DiagnosticCode.profileUnsupported =>
            ProfileBindingState.packageUnsupported,
          DiagnosticCode.profileTimeout => ProfileBindingState.packageTimeout,
          DiagnosticCode.profileComposition =>
            ProfileBindingState.compositionFailed,
          _ => ProfileBindingState.lockStale,
        },
        error.message,
        code: error.diagnostic,
        remedy: error.remedy,
      );
    } on FileSystemException catch (error) {
      return failed(ProfileBindingState.cacheMissing, error.message);
    }
  }

  /// Copies each package file [select] reads for [bundle] that the cache
  /// lacks out of its source's mirror, as after upgrading from Wayfinder
  /// 0.2, whose cache kept only the mirrors. Runs only `git show` on a
  /// mirror that already exists, under its lock: never fetches, never
  /// waits for another holder of a mirror, and never writes in the project.
  /// Does nothing unless the lock is current and holds [bundle]'s chain.
  /// Binds [bundle] as [select] does. Returns how many files it wrote;
  /// [select] reports what is still missing.
  Future<int> restoreCachedPackages(
    String bundle, {
    String? configPath,
    String? projectRoot,
    WayfinderCancellation? cancel,
  }) async {
    var restored = 0;
    try {
      final bound = await WayfinderProjectConfig.bind(
        bundle,
        configPath: configPath,
        projectRoot: projectRoot,
      );
      final lock = await _readLock(
        File(p.join(bound.projectRoot, 'wayfinder.lock')),
      );
      if (lock == null ||
          lock.configurationSha256 !=
              canonicalConfigurationSha256(bound.source)) {
        return 0;
      }
      final session = _Session(
        projectRoot: bound.projectRoot,
        upgrade: false,
        previous: lock,
        cancel: cancel,
      );
      for (final locked
          in lock.chainOf(bound.binding.id) ?? <LockedPackage>[]) {
        final snapshot = _snapshotFile(locked.commit, locked.path);
        final mirror = _repositoryCache(
          _gitLocation(locked.git, bound.projectRoot),
        );
        if (await snapshot.exists() || !await mirror.exists()) continue;
        final held = await WayfinderFileLock.tryExclusive(_mirrorLock(mirror));
        if (held == null) continue;
        try {
          final result = await _git(session, [
            'show',
            '${locked.commit}:${locked.path}/wayfinder-profile.json',
          ], workingDirectory: mirror.path);
          if (result.exitCode != 0) continue;
          await _keep(snapshot, result.stdout);
          restored++;
        } finally {
          await held.release();
        }
      }
    } on BundleBindingException {
      // select reports the binding.
    } on FileSystemException {
      // select reports what it cannot read.
    } on FormatException {
      // select reports a configuration it cannot parse.
    } on ProcessException {
      // Git cannot run; select reports the missing file.
    } on WayfinderException catch (error) {
      if (error.code == 'cancelled') rethrow;
    }
    return restored;
  }

  static String canonicalConfigurationSha256(String raw) =>
      sha256.convert(utf8.encode(_canonicalJson(jsonDecode(raw)))).toString();

  Future<({String projectRoot, File configFile})> _locate(
    String project,
  ) async {
    final projectRoot = p.normalize(Directory(project).absolute.path);
    final configFile = File(p.join(projectRoot, 'wayfinder.json'));
    if (!await configFile.exists()) {
      throw WayfinderProfileResolutionException(
        'Project $projectRoot does not contain wayfinder.json.',
      );
    }
    return (projectRoot: projectRoot, configFile: configFile);
  }

  Future<ProfileResolutionPlan> _planFile(
    String projectRoot,
    File configFile, {
    required bool upgrade,
    bool lockedOnly = false,
    bool skills = true,
    ProfileFetchPolicy? allowFetch,
    WayfinderCancellation? cancel,
  }) async {
    throwIfCancelled(cancel);
    final configBytes = await configFile.readAsBytes();
    final lockBytes = await _readBytes(
      File(p.join(projectRoot, 'wayfinder.lock')),
    );
    final previous = _parseLock(lockBytes);
    if (lockedOnly) _checkLockedOnly(utf8.decode(configBytes), previous);
    return _plan(
      projectRoot,
      configPath: configFile.path,
      configBytes: configBytes,
      lockBytes: lockBytes,
      skills: skills,
      session: _Session(
        projectRoot: projectRoot,
        upgrade: upgrade,
        previous: previous,
        cancel: cancel,
        allowFetch: allowFetch,
        lockedOnly: lockedOnly,
      ),
    );
  }

  /// Throws [ProfileLockChangeRequiredException] unless [lock] holds, for
  /// the configuration [raw], exactly the chains its bindings name, so a
  /// locked-only plan can resolve them without changing it.
  static void _checkLockedOnly(String raw, ProfileLock? lock) {
    final config = WayfinderProjectConfig.parse(raw);
    final reached = <ProfileId>{};
    for (final binding in config.profiles.values) {
      switch (_lockedChain(lock, raw, binding)) {
        case final ProfileLockChange change:
          throw ProfileLockChangeRequiredException(change);
        case final List<LockedPackage> chain:
          reached.addAll([for (final locked in chain) locked.id]);
      }
    }
    final unreached = [
      for (final id in lock!.packages.keys)
        if (!reached.contains(id)) id,
    ]..sort((left, right) => left.value.compareTo(right.value));
    if (unreached.isNotEmpty) {
      throw ProfileLockChangeRequiredException(
        ProfileLockChange(
          ProfileLockChangeKind.packagesUnreached,
          'Profile lock records ${unreached.join(', ')}, which no configured '
          'chain reaches.',
          packages: List.unmodifiable(unreached),
        ),
      );
    }
  }

  /// The chain [lock] records for [binding] of the configuration [raw],
  /// root first, or the [ProfileLockChange] that says why it records none
  /// as resolving needs it.
  static Object _lockedChain(
    ProfileLock? lock,
    String raw,
    WayfinderProfileBinding binding,
  ) {
    final id = binding.id;
    if (lock == null) {
      return const ProfileLockChange(
        ProfileLockChangeKind.lockMissing,
        'Profile lock is missing or unreadable.',
      );
    }
    if (lock.configurationSha256 != canonicalConfigurationSha256(raw)) {
      return const ProfileLockChange(
        ProfileLockChangeKind.configurationChanged,
        'Profile lock is stale: the configuration changed after the lock was '
        'written.',
      );
    }
    final chain = lock.chainOf(id);
    if (chain == null) {
      return ProfileLockChange(
        ProfileLockChangeKind.chainMissing,
        'Profile lock has no complete chain for Profile $id.',
        profile: id,
      );
    }
    final leaf = chain.last;
    final source = binding.source;
    if (leaf.git != source.git ||
        leaf.requestedRef != source.ref ||
        leaf.path != source.path) {
      return ProfileLockChange(
        ProfileLockChangeKind.sourceChanged,
        'Profile lock records $id from ${leaf.git} at ${leaf.requestedRef} '
        '(${leaf.path}); the configuration names ${source.git} at '
        '${source.ref} (${source.path}).',
        profile: id,
        packages: [id],
      );
    }
    return chain;
  }

  /// Plans [configBytes] as the project's `wayfinder.json`. [lockBytes] is
  /// the lock [apply] expects to find. With [candidate], the configured
  /// bundles are not checked, because the caller creates and checks them;
  /// skill directories `get` could not install are recorded there instead
  /// of thrown; and each binding's composed Profile is kept. Without
  /// [skills], no skill file is read, no skill directory is refused, and
  /// the plan writes and prunes no skill.
  Future<ProfileResolutionPlan> _plan(
    String projectRoot, {
    required String configPath,
    required List<int> configBytes,
    required List<int>? lockBytes,
    required _Session session,
    bool skills = true,
    _CandidateSink? candidate,
  }) async {
    final cancel = session.cancel;
    final raw = utf8.decode(configBytes);
    final config = WayfinderProjectConfig.parse(raw);
    if (candidate == null) await _checkBundlePaths(config, projectRoot);

    final packages = <ProfileId, LockedPackage>{};
    final shipped = <ProfileId, String>{};
    for (final binding in config.profiles.values) {
      final chain = await _resolveChain(binding, session);
      final composed = _compose(binding.id, [
        for (final member in chain) member.package,
      ], binding.project);
      candidate?.profiles[binding.id] = composed;
      for (final member in chain) {
        _insert(packages, member.locked);
        if (member.package.skill case final skill?) {
          shipped[member.locked.id] = skill;
        }
      }
    }
    final ids = shipped.keys.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    final directories = {
      for (final id in ids)
        id: await ProfileSkills.inspect(projectRoot, packages[id]!.revision),
    };
    // Refused in the order get has always named them: by binding, then by
    // chain, as the Profiles were reached.
    final refused = [
      for (final id in shipped.keys)
        for (final directory in directories[id]!)
          if (_refuses(directory)) directory,
    ];
    if (candidate != null) {
      candidate.skillProblems = List.unmodifiable(refused);
    } else if (skills && refused.isNotEmpty) {
      throw ProfileSkillDirectoriesException(refused);
    }
    final pending = <ProfileId, List<SkillFile>>{};
    for (final id in skills ? ids : const <ProfileId>[]) {
      final locked = packages[id]!;
      if (directories[id]!.any(
        (directory) => directory.installed != locked.revision,
      )) {
        throwIfCancelled(cancel);
        if (!skillMarkerFits(locked.revision)) {
          // Its marker would read back as no revision, so the skill would
          // stay stale and the next get would refuse it as unowned.
          throw WayfinderProfileResolutionException(
            'Profile ${locked.id} release is too long for the '
            '${ProfileSkills.marker} marker, which wayfinder reads up to '
            '64 KiB, so wayfinder did not install its skill.',
          );
        }
        pending[id] = await _skillFiles(locked, shipped[id]!, session);
      }
    }
    final lock = ProfileLock(
      configurationSha256: canonicalConfigurationSha256(raw),
      packages: Map.unmodifiable(packages),
    );
    final text =
        '${const JsonEncoder.withIndent('  ').convert(lock.toJson())}\n';
    var lockChanged =
        lockBytes == null || !_sameBytes(lockBytes, utf8.encode(text));
    if (session.lockedOnly && lockChanged) {
      // The lock was checked before any fetch, so only a package that
      // disagrees with the lock it was locked from changes it now. A lock
      // that reads the same in other bytes is kept as written.
      final previous = session.previous!.packages;
      final changed = [
        for (final id in {...previous.keys, ...lock.packages.keys})
          if (jsonEncode(previous[id]?.toJson()) !=
              jsonEncode(lock.packages[id]?.toJson()))
            id,
      ]..sort((left, right) => left.value.compareTo(right.value));
      if (changed.isNotEmpty) {
        throw ProfileLockChangeRequiredException(
          ProfileLockChange(
            ProfileLockChangeKind.packageChanged,
            'Profile ${changed.join(', ')} '
            '${changed.length == 1 ? 'declares' : 'declare'} another release '
            'or parent than the lock records.',
            packages: List.unmodifiable(changed),
          ),
        );
      }
      lockChanged = false;
    }
    return ProfileResolutionPlan._(
      projectRoot: projectRoot,
      configPath: configPath,
      lockPath: p.join(projectRoot, 'wayfinder.lock'),
      upgrade: session.upgrade,
      lockedOnly: session.lockedOnly,
      includesSkills: skills,
      fetched: session.fetched,
      fetches: List.unmodifiable(session.fetches),
      packages: lock.packages,
      lockChanged: lockChanged,
      skills: List.unmodifiable([
        for (final id in ids)
          MaterializedSkill(
            id: id,
            directories: ProfileSkills.directories(id),
            written: pending.containsKey(id),
          ),
      ]),
      removedSkills: skills
          ? List.unmodifiable(
              await ProfileSkills.prunable(projectRoot, shipped.keys.toSet()),
            )
          : const [],
      skillDirectories: List.unmodifiable([
        for (final id in ids) ...directories[id]!,
      ]),
      lockText: text,
      configurationSha256: sha256.convert(configBytes).toString(),
      lockSha256: lockBytes == null
          ? null
          : sha256.convert(lockBytes).toString(),
      pending: Map.unmodifiable(pending),
      snapshots: {
        for (final package in packages.values)
          _snapshotFile(package.commit, package.path).path: session
              .snapshots[_snapshotFile(package.commit, package.path).path]!,
      },
    );
  }

  /// Writes [plan] once its inputs are unchanged. Without [prune], marked
  /// skill directories of other Profiles and interrupted copies stay for
  /// the next `get`. A plan that leaves skills alone writes only the lock.
  Future<ProfileResolutionResult> _apply(
    ProfileResolutionPlan plan, {
    bool prune = true,
  }) async {
    final configFile = File(plan.configPath);
    final lockFile = File(plan.lockPath);
    final configBytes = await _readBytes(configFile);
    if (configBytes == null ||
        sha256.convert(configBytes).toString() != plan._configurationSha256) {
      throw _stale('wayfinder.json');
    }
    final lockBytes = await _readBytes(lockFile);
    if ((lockBytes == null ? null : sha256.convert(lockBytes).toString()) !=
        plan._lockSha256) {
      throw _stale('wayfinder.lock');
    }
    await _checkSnapshots(plan);
    final projectRoot = plan.projectRoot;
    final shipped = {for (final skill in plan.skills) skill.id};
    if (plan.includesSkills) {
      await _checkSkillDirectories(projectRoot, [
        for (final id in shipped) plan.packages[id]!.revision,
      ]);
    }
    if (plan.lockChanged) await _writeLock(lockFile, plan._lockText);
    for (final MapEntry(key: id, value: files) in plan._pending.entries) {
      await ProfileSkills.write(
        projectRoot,
        plan.packages[id]!.revision,
        files,
      );
    }
    final removed = prune && plan.includesSkills
        ? await ProfileSkills.prune(projectRoot, shipped)
        : const <String>[];
    return ProfileResolutionResult(
      projectRoot: projectRoot,
      configPath: plan.configPath,
      lockPath: plan.lockPath,
      reused:
          !plan.upgrade &&
          !plan.lockChanged &&
          !plan.fetched &&
          plan._pending.isEmpty &&
          removed.isEmpty,
      upgraded: plan.upgrade,
      packages: plan.packages,
      skills: plan.skills,
      removedSkills: removed,
    );
  }

  /// Throws `resolution-stale` when a package file [plan] read in the cache
  /// has changed since.
  static Future<void> _checkSnapshots(ProfileResolutionPlan plan) async {
    for (final MapEntry(key: path, value: digest) in plan._snapshots.entries) {
      final bytes = await _readBytes(File(path));
      if (bytes == null || sha256.convert(bytes).toString() != digest) {
        throw _stale('The Profile cache');
      }
    }
  }

  static WayfinderException _stale(String what) => WayfinderException(
    'resolution-stale',
    '$what changed after resolution was planned.',
  );

  /// Deletes the `get` lock file of each project whose root no longer
  /// exists, such as a removed worktree, once no `get` has used it for
  /// [unusedFor], and returns the deleted files.
  ///
  /// A lock file records the root it guards. Its note is read only while
  /// no one holds the lock, because Windows refuses to read a held lock
  /// file, and a held lock is left for a later call. Like an index's lock
  /// file, it is deleted only once unused for the period: deleting one a
  /// `get` has just opened would let that `get` and the next hold different
  /// files.
  Future<List<String>> pruneProjectLocks({
    Duration unusedFor = const Duration(days: 30),
  }) async {
    final directory = Directory(p.join(dataDirectory.path, 'projects'));
    final removed = <String>[];
    if (!await directory.exists()) return removed;
    final now = DateTime.now();
    final name = RegExp(r'^([0-9a-f]{64})\.get\.lock$');
    for (final entry in await directory.list(followLinks: false).toList()) {
      final key = name.firstMatch(p.basename(entry.path))?[1];
      if (entry is! File || key == null) continue;
      if (await WayfinderFileLock.isHeld(entry)) continue;
      final String root;
      try {
        if (jsonDecode(await entry.readAsString()) case {
          'root': final String value,
        } when sha256.convert(utf8.encode(value)).toString() == key) {
          root = value;
        } else {
          continue;
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
      Future<bool> abandoned() async {
        if (await Directory(root).exists()) return false;
        final stat = await entry.stat();
        return stat.type == FileSystemEntityType.file &&
            now.difference(stat.modified) >= unusedFor;
      }

      if (!await abandoned()) continue;
      final lock = await WayfinderFileLock.tryExclusive(entry);
      if (lock == null) continue;
      try {
        // A `get` may have used it between the check and the lock.
        if (!await abandoned()) continue;
        // POSIX deletes an open file, so delete it while holding the lock;
        // Windows needs the handle closed first.
        if (Platform.isWindows) await lock.release();
        await entry.delete();
        removed.add(entry.path);
      } on FileSystemException {
        // Windows keeps a file another handle has open; a later call retries.
      } finally {
        await lock.release();
      }
    }
    return removed;
  }

  /// Runs [action] while holding the `get` lock of the project at
  /// [projectRoot], so one writer at a time changes its lock and skills.
  Future<T> _withProjectLock<T>(
    String projectRoot,
    Future<T> Function() action,
  ) async {
    final root = await Directory(projectRoot).resolveSymbolicLinks();
    final lock = await WayfinderFileLock.tryExclusive(
      File(
        p.join(
          dataDirectory.path,
          'projects',
          '${sha256.convert(utf8.encode(root))}.get.lock',
        ),
      ),
    );
    if (lock == null) throw ProfileResolutionBusyException.project(projectRoot);
    try {
      await lock.writeNote('${jsonEncode({'root': root})}\n');
      return await action();
    } finally {
      await lock.release();
    }
  }

  /// Throws [ProfileSkillDirectoriesException] when a skill of [revisions]
  /// could not be installed safely: a skill root resolves outside the
  /// project, or something occupies a skill directory without the marker
  /// for its id.
  static Future<void> _checkSkillDirectories(
    String projectRoot,
    Iterable<SkillRevision> revisions,
  ) async {
    final refused = [
      for (final revision in revisions)
        for (final directory in await ProfileSkills.inspect(
          projectRoot,
          revision,
        ))
          if (_refuses(directory)) directory,
    ];
    if (refused.isNotEmpty) throw ProfileSkillDirectoriesException(refused);
  }

  /// Whether `get` refuses to install a skill into [directory].
  static bool _refuses(ProfileSkillDirectory directory) =>
      switch (directory.state) {
        ProfileSkillDirectoryState.unmarked ||
        ProfileSkillDirectoryState.outside => true,
        ProfileSkillDirectoryState.current ||
        ProfileSkillDirectoryState.missing ||
        ProfileSkillDirectoryState.stale => false,
      };

  Future<void> _checkBundlePaths(
    WayfinderProjectConfig config,
    String projectRoot,
  ) async {
    final root = await Directory(projectRoot).resolveSymbolicLinks();
    final realPaths = <String>{};
    for (final bundle in config.bundles) {
      final configured = p.join(projectRoot, bundle.path);
      String real;
      try {
        real = await Directory(configured).resolveSymbolicLinks();
      } on FileSystemException {
        throw WayfinderProfileResolutionException(
          'Configured bundle ${bundle.path} does not exist or is unreadable.',
        );
      }
      if (!p.isWithin(root, real) || !realPaths.add(real)) {
        throw WayfinderProfileResolutionException(
          'Configured bundle ${bundle.path} escapes or duplicates a project bundle.',
        );
      }
    }
    for (final path in realPaths) {
      if (realPaths.any((other) => other != path && p.isWithin(other, path))) {
        throw WayfinderProfileResolutionException(
          'Configured bundle paths must not overlap after resolving symlinks.',
        );
      }
    }
  }

  Future<List<({LockedPackage locked, ProfilePackage package})>> _resolveChain(
    WayfinderProfileBinding binding,
    _Session session,
  ) async {
    final members =
        <
          ({
            WayfinderProfileSource source,
            String commit,
            ProfilePackage package,
          })
        >[];
    var source = binding.source;
    // The commit to read [source] at: resolved for each new source, and kept
    // for a parent at the same revision.
    String? commit;
    ProfileId? configured = binding.id;
    while (true) {
      throwIfCancelled(session.cancel);
      final expected = configured == null
          ? null
          : (configured, 'the configuration');
      final child = members.lastOrNull?.package.id;
      final (resolved, package) = await _withMirror(source, session, (
        location,
        mirror,
      ) async {
        final at =
            commit ??
            await _checkoutLocked(
              source,
              location,
              mirror,
              session,
              child: child,
            );
        return (
          at,
          await _readPackage(mirror, at, source, session, expected: expected),
        );
      });
      commit = resolved;
      if (members.any((member) => member.package.id == package.id)) {
        throw WayfinderProfileResolutionException(
          'Profile ${package.id} extends itself through '
          '${members.map((member) => member.package.id).join(', ')}.',
        );
      }
      members.add((source: source, commit: resolved, package: package));
      configured = null;
      switch (package.parent) {
        case null:
          return [
            for (var index = members.length - 1; index >= 0; index--)
              (
                locked: LockedPackage(
                  id: members[index].package.id,
                  release: members[index].package.release,
                  git: members[index].source.git,
                  requestedRef: members[index].source.ref,
                  commit: members[index].commit,
                  path: members[index].source.path,
                  extendsId: index + 1 < members.length
                      ? members[index + 1].package.id
                      : null,
                ),
                package: members[index].package,
              ),
          ];
        case SameRevision(:final path):
          source = WayfinderProfileSource(
            git: source.git,
            ref: source.ref,
            path: path,
          );
        case OtherRevision(source: final parent):
          source = parent;
          commit = null;
      }
    }
  }

  static void _insert(
    Map<ProfileId, LockedPackage> packages,
    LockedPackage package,
  ) {
    final existing = packages[package.id];
    if (existing == null) {
      packages[package.id] = package;
    } else if (!existing.isSameRevision(package)) {
      throw WayfinderProfileResolutionException(
        'Profile ${package.id} is needed from two sources: $existing and '
        '$package. A project locks one source per Profile id; the refs must '
        'agree.',
      );
    }
  }

  static bool _matchesLockedParent(
    PackageParent? parent, {
    required LockedPackage child,
    required LockedPackage? lockedParent,
  }) => switch (parent) {
    null => lockedParent == null,
    SameRevision(:final path) =>
      lockedParent != null &&
          lockedParent.git == child.git &&
          lockedParent.commit == child.commit &&
          lockedParent.path == path,
    OtherRevision(:final source) =>
      lockedParent != null &&
          lockedParent.git == source.git &&
          lockedParent.requestedRef == source.ref &&
          lockedParent.path == source.path,
  };

  EffectiveProfile _compose(
    ProfileId id,
    List<ProfilePackage> chain,
    ProjectVocabulary project,
  ) {
    try {
      return EffectiveProfile.compose(chain, project: project);
    } on ProfileCompositionException catch (error) {
      final failure = compositionFailure(id, error);
      throw WayfinderProfileResolutionException(
        failure.message,
        diagnostic: failure.code,
      );
    }
  }

  /// Runs [action] on the mirror of [source]'s repository while holding the
  /// mirror's lock, so no other planner clones, refreshes or reads it
  /// meanwhile. Waits up to [mirrorLockTimeout] for another holder. Callers
  /// never nest it: one mirror's lock at a time cannot deadlock.
  Future<T> _withMirror<T>(
    WayfinderProfileSource source,
    _Session session,
    Future<T> Function(String location, Directory mirror) action,
  ) async {
    final location = _gitLocation(source.git, session.projectRoot);
    final root = _repositoryCache(location);
    await root.parent.create(recursive: true);
    final WayfinderFileLock lock;
    try {
      lock = await WayfinderFileLock.exclusive(
        _mirrorLock(root),
        timeout: mirrorLockTimeout,
        cancel: session.cancel,
      );
    } on TimeoutException {
      throw ProfileResolutionBusyException.source(
        source.git,
        mirrorLockTimeout,
      );
    }
    try {
      return await action(location, root);
    } finally {
      await lock.release();
    }
  }

  static File _mirrorLock(Directory mirror) => File('${mirror.path}.lock');

  /// The commit of [source] to read from its mirror [root], under the
  /// mirror's lock. Keeps a commit the previous lock pinned for the same
  /// source unless upgrading, and fetches only when the mirror is missing or
  /// a ref must move. [child] is the package that names [source] as its
  /// parent; null for a configured source.
  Future<String> _checkoutLocked(
    WayfinderProfileSource source,
    String location,
    Directory root,
    _Session session, {
    ProfileId? child,
  }) async {
    final preferred = session.upgrade
        ? null
        : session.previous?.packages.values
              .where(
                (locked) =>
                    locked.git == source.git &&
                    locked.requestedRef == source.ref &&
                    locked.path == source.path,
              )
              .firstOrNull
              ?.commit;
    if (preferred == null && session.lockedOnly) {
      throw ProfileLockChangeRequiredException(
        ProfileLockChange(
          ProfileLockChangeKind.packageChanged,
          'Profile lock pins no commit of ${source.git} at ${source.ref} '
          '(${source.path}), which '
          '${child == null ? 'a locked package' : 'Profile $child'} names as '
          'its parent.',
          packages: [?child],
        ),
      );
    }
    if (!await root.exists()) {
      await _cloneMirror(source, location, root, session);
    } else if (preferred == null &&
        !_commitRef.hasMatch(source.ref) &&
        !session.offline) {
      session.fetch(ProfileFetchKind.refresh, source, location);
      final result = await _git(session, [
        'remote',
        'update',
        '--prune',
      ], workingDirectory: root.path);
      _checkGit(result, 'refresh Profile source ${source.git}');
    }
    if (preferred == null) {
      return _resolveRefWithFetch(root, source, session);
    }
    if (!await _hasCommit(root, preferred, session)) {
      session.fetch(ProfileFetchKind.refresh, source, location);
      final result = await _git(session, [
        'remote',
        'update',
        '--prune',
      ], workingDirectory: root.path);
      _checkGit(
        result,
        'refresh Profile source ${source.git} while finding locked commit '
        '$preferred',
      );
      if (!await _hasCommit(root, preferred, session)) {
        throw WayfinderProfileResolutionException(
          'Locked commit $preferred of ${source.git} is unavailable even '
          'after refreshing the source.',
          remedy: DiagnosticRemedy.upgradeProfiles,
        );
      }
    }
    return preferred;
  }

  /// Clones [source]'s repository at [location] into the mirror [root],
  /// under the mirror's lock.
  Future<void> _cloneMirror(
    WayfinderProfileSource source,
    String location,
    Directory root,
    _Session session, {
    bool defaultBranch = false,
  }) async {
    session.fetch(
      ProfileFetchKind.clone,
      source,
      location,
      defaultBranch: defaultBranch,
    );
    final temporary = Directory(
      '${root.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      // --progress keeps a long clone writing, so runGit's inactivity
      // timeout stops only a clone that stalls.
      final result = await _git(session, [
        'clone',
        '--mirror',
        '--progress',
        '--',
        location,
        temporary.path,
      ]);
      _checkGit(result, 'clone Profile source ${source.git}');
      await temporary.rename(root.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      rethrow;
    }
  }

  Future<GitResult> _git(
    _Session session,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    throwIfCancelled(session.cancel);
    return _runGit(
      arguments,
      workingDirectory: workingDirectory,
      cancel: session.cancel,
    );
  }

  Future<bool> _hasCommit(
    Directory repository,
    String commit,
    _Session session,
  ) async =>
      (await _git(session, [
        'cat-file',
        '-e',
        '$commit^{commit}',
      ], workingDirectory: repository.path)).exitCode ==
      0;

  Future<String> _resolveRefWithFetch(
    Directory repository,
    WayfinderProfileSource source,
    _Session session,
  ) async {
    final local = await _resolveRef(repository, source.ref, session);
    if (local != null) return local;
    session.fetch(
      ProfileFetchKind.refresh,
      source,
      _gitLocation(source.git, session.projectRoot),
    );
    final result = await _git(session, [
      'remote',
      'update',
      '--prune',
    ], workingDirectory: repository.path);
    _checkGit(
      result,
      'refresh Profile source ${source.git} while finding ref ${source.ref}',
    );
    final fetched = await _resolveRef(repository, source.ref, session);
    if (fetched != null) return fetched;
    throw WayfinderProfileResolutionException(
      'Profile ref ${source.ref} could not be resolved in ${source.git}.',
    );
  }

  Future<String?> _resolveRef(
    Directory repository,
    String ref,
    _Session session,
  ) async {
    final candidates = _commitRef.hasMatch(ref)
        ? <String>['$ref^{commit}']
        : <String>['refs/heads/$ref^{commit}', 'refs/tags/$ref^{commit}'];
    final matches = <String>[];
    for (final candidate in candidates) {
      final result = await _git(session, [
        'rev-parse',
        '--verify',
        candidate,
      ], workingDirectory: repository.path);
      if (result.exitCode == 0) matches.add(result.text.trim());
    }
    if (matches.length == 1) return matches.single;
    if (matches.length > 1) {
      throw WayfinderProfileResolutionException(
        'Profile ref $ref is ambiguous between a branch and a tag.',
      );
    }
    return null;
  }

  Directory _repositoryCache(String git) => Directory(
    p.join(
      dataDirectory.path,
      'profiles',
      sha256.convert(utf8.encode(git)).toString(),
    ),
  );

  /// Where a plan keeps the package file of [path] at [commit]. A commit
  /// fixes the file, so one copy serves every source that reaches it.
  File _snapshotFile(String commit, String path) => File(
    p.join(
      dataDirectory.path,
      'profiles',
      'packages',
      '${sha256.convert(utf8.encode('$commit\u0000$path'))}.json',
    ),
  );

  static String _gitLocation(String git, String projectRoot) =>
      WayfinderProfileSource.locationOf(git, projectRoot: projectRoot);

  static final _commitRef = RegExp(r'^[0-9a-fA-F]{7,40}$');

  static bool _plainRelativePath(String path) =>
      !path.contains(r'\') &&
      !RegExp(r'^[A-Za-z]:').hasMatch(path) &&
      path
          .split('/')
          .every((segment) => !const {'', '.', '..'}.contains(segment));

  /// [locked]'s package from the file a plan kept, without Git.
  Future<ProfilePackage> _readCached(LockedPackage locked) async =>
      _parsePackage(
        await _snapshotFile(locked.commit, locked.path).readAsBytes(),
        _packageOrigin(locked.source, locked.commit),
        expected: (locked.id, 'the lock'),
      );

  /// Every file of [locked]'s skill directory [skill] at its locked commit,
  /// read from the mirror the plan just resolved, under the mirror's lock.
  /// Only regular files at plain relative paths are installed: a symlink or
  /// submodule could point outside the skill, and git stores tree entry
  /// names such as `..` verbatim, so a crafted tree could name a path
  /// outside it.
  Future<List<SkillFile>> _skillFiles(
    LockedPackage locked,
    String skill,
    _Session session,
  ) => _withMirror(
    locked.source,
    session,
    (_, repository) => _readSkillFiles(repository, locked, skill, session),
  );

  Future<List<SkillFile>> _readSkillFiles(
    Directory repository,
    LockedPackage locked,
    String skill,
    _Session session,
  ) async {
    final tree = p.posix.join(locked.path, skill);
    final origin =
        'Profile ${locked.id} skill $tree at ${locked.git} (${locked.commit})';
    final listing = await _git(session, [
      'ls-tree',
      '-r',
      '-z',
      '${locked.commit}:$tree',
    ], workingDirectory: repository.path);
    if (listing.exitCode != 0) {
      throw WayfinderProfileResolutionException('$origin is not a directory.');
    }
    final files = <SkillFile>[];
    for (final entry in listing.text.split('\x00')) {
      if (entry.isEmpty) continue;
      final tab = entry.indexOf('\t');
      final [mode, _, object] = entry.substring(0, tab).split(' ');
      final path = entry.substring(tab + 1);
      if (!_plainRelativePath(path)) {
        throw WayfinderProfileResolutionException(
          '$origin holds ${jsonEncode(path)}, which is not a path inside the '
          'skill.',
        );
      }
      if (mode != '100644' && mode != '100755') {
        throw WayfinderProfileResolutionException(
          '$origin holds $path, which is not a regular file.',
        );
      }
      if (path == ProfileSkills.marker) {
        throw WayfinderProfileResolutionException(
          '$origin holds $path, which is the marker wayfinder writes to own '
          'the installed directory.',
        );
      }
      final blob = await _git(session, [
        'cat-file',
        'blob',
        object,
      ], workingDirectory: repository.path);
      _checkGit(blob, 'read $origin/$path');
      files.add((path: path, bytes: blob.stdout, executable: mode == '100755'));
    }
    final manifest = files.where((file) => file.path == 'SKILL.md').firstOrNull;
    if (manifest == null) {
      throw WayfinderProfileResolutionException('$origin has no SKILL.md.');
    }
    final name = _skillName(manifest.bytes);
    if (name != locked.id.value) {
      throw WayfinderProfileResolutionException(
        '$origin SKILL.md ${name == null ? 'has no name' : 'is named $name'}; '
        'agents key skills by that name, so it must be ${locked.id}.',
      );
    }
    return files;
  }

  /// The `name` of a SKILL.md's leading `---` frontmatter block, read as
  /// plain lines rather than YAML: the schema fixes it to the Profile id, so
  /// anything a line match cannot read is a wrong name.
  static String? _skillName(List<int> bytes) {
    final lines = const LineSplitter().convert(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (lines.firstOrNull?.trim() != '---') return null;
    for (final line in lines.skip(1)) {
      if (line.trim() == '---') return null;
      if (RegExp(r'^name:\s*(.*?)\s*$').firstMatch(line) case final match?) {
        final value = match[1]!;
        final quoted = RegExp(r'''^(["'])(.*)\1$''').firstMatch(value);
        return quoted?[2] ?? value;
      }
    }
    return null;
  }

  /// Reads [source]'s package at [commit] from [repository] and keeps its
  /// bytes in the cache for [select], before parsing, so even a package that
  /// fails here is selected later with the same diagnostic.
  Future<ProfilePackage> _readPackage(
    Directory repository,
    String commit,
    WayfinderProfileSource source,
    _Session session, {
    (ProfileId, String)? expected,
  }) async {
    final origin = _packageOrigin(source, commit);
    final result = await _git(session, [
      'show',
      '$commit:${source.path}/wayfinder-profile.json',
    ], workingDirectory: repository.path);
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        '$origin has no package at ${source.path}/wayfinder-profile.json.',
      );
    }
    final snapshot = _snapshotFile(commit, source.path);
    session.snapshots[snapshot.path] = await _keep(snapshot, result.stdout);
    return _parsePackage(result.stdout, origin, expected: expected);
  }

  static String _packageOrigin(WayfinderProfileSource source, String commit) =>
      'Profile package ${source.path} at ${source.git} ($commit)';

  /// Parses [bytes] as a package, bounded by [packageTimeout]. When
  /// [expected] names an id, a package declaring another is refused: the id
  /// is the finding namespace and the lock key, so the two must agree.
  Future<ProfilePackage> _parsePackage(
    List<int> bytes,
    String origin, {
    (ProfileId, String)? expected,
  }) async {
    final String json;
    try {
      json = utf8.decode(bytes);
    } on FormatException {
      throw WayfinderProfileResolutionException(
        '$origin cannot be evaluated by this validator: it is not UTF-8.',
        diagnostic: DiagnosticCode.profileInvalid,
      );
    }
    final ProfilePackage package;
    try {
      package = await ProfilePackage.parseWithin(json, timeout: packageTimeout);
    } on ProfilePackageException catch (error) {
      throw WayfinderProfileResolutionException(
        '$origin cannot be evaluated by this validator: $error.',
        diagnostic: error.timedOut
            ? DiagnosticCode.profileTimeout
            : error.unsupported
            ? DiagnosticCode.profileUnsupported
            : DiagnosticCode.profileInvalid,
      );
    }
    if (expected case (final id, final namer) when package.id != id) {
      throw WayfinderProfileResolutionException(
        '$origin declares id ${package.id}; $namer names it $id.',
        diagnostic: DiagnosticCode.profileInvalid,
      );
    }
    return package;
  }

  /// Writes [bytes] to [file] unless it already holds them, and returns
  /// their SHA-256.
  static Future<String> _keep(File file, List<int> bytes) async {
    final current = await _readBytes(file);
    if (current == null || !_sameBytes(current, bytes)) {
      await file.parent.create(recursive: true);
      final temp = File(
        '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      } on Object {
        if (await temp.exists()) await temp.delete();
        rethrow;
      }
    }
    return sha256.convert(bytes).toString();
  }

  static Future<List<int>?> _readBytes(File file) async {
    try {
      return await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<ProfileLock?> _readLock(File file) async =>
      _parseLock(await _readBytes(file));

  /// The `wayfinder.lock` of [projectRoot], read once for everything one
  /// [status] or [select] reports: the parsed lock, null when there is none
  /// or it does not parse, or the error that kept it from being read.
  Future<_LockRead> _readProjectLock(String projectRoot) async {
    try {
      return (
        lock: await _readLock(File(p.join(projectRoot, 'wayfinder.lock'))),
        error: null,
      );
    } on FileSystemException catch (error) {
      return (lock: null, error: error);
    }
  }

  static ProfileLock? _parseLock(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      return ProfileLock.tryParse(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeLock(File file, String text) async {
    final temp = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    } on Object {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  void _checkGit(GitResult result, String action) {
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        '$action failed (git exit ${result.exitCode}). Check the source and ref.',
      );
    }
  }
}

final class _CandidateSink {
  final profiles = <ProfileId, EffectiveProfile>{};
  List<ProfileSkillDirectory> skillProblems = const [];
}

/// A plan of `get` for a configuration that is not in the project yet, from
/// [planCandidateResolution]. Only `package:wayfinder/adoption.dart` uses
/// it; `project.dart` does not export it.
final class CandidateResolution {
  CandidateResolution._(this.plan, this.profiles, this.skillProblems);

  /// What [applyCandidateResolution] writes once the configuration is on
  /// disk with exactly the planned bytes and no lock exists.
  final ProfileResolutionPlan plan;

  /// Each binding's composed chain, by its Profile id.
  final Map<ProfileId, EffectiveProfile> profiles;

  /// The skill directories that stop [plan]'s skills from being installed,
  /// [ProfileSkillDirectoryState.unmarked] or
  /// [ProfileSkillDirectoryState.outside]; apply throws for them.
  final List<ProfileSkillDirectory> skillProblems;

  /// The files of each skill apply installs, by Profile id. Each lands in
  /// every directory of `ProfileSkills.directories`, beside the marker.
  Map<ProfileId, List<SkillFile>> get skillFiles => plan._pending;

  /// The `wayfinder.lock` text apply writes.
  String get lockText => plan._lockText;

  /// Throws `resolution-stale` when a package file the plan read in the
  /// cache has changed since, before anything is written.
  Future<void> checkCache() => WayfinderProfileResolver._checkSnapshots(plan);
}

/// Plans `get` for [configuration], the `wayfinder.json` bytes adoption will
/// write, before the file exists. Ignores any lock in the project, so the
/// plan expects none, and checks no configured bundle: the caller creates
/// and checks them. Unmarked or outside skill directories are reported in
/// [CandidateResolution.skillProblems] instead of thrown. With [offline],
/// refs resolve in the cached mirrors as they are, and a fetch the plan
/// still needs throws [ProfileFetchRequiredException]; otherwise
/// [allowFetch] decides each fetch.
Future<CandidateResolution> planCandidateResolution(
  WayfinderProfileResolver resolver, {
  required String projectRoot,
  required List<int> configuration,
  bool offline = false,
  ProfileFetchPolicy? allowFetch,
  WayfinderCancellation? cancel,
}) async {
  throwIfCancelled(cancel);
  final sink = _CandidateSink();
  final plan = await resolver._plan(
    projectRoot,
    configPath: p.join(projectRoot, 'wayfinder.json'),
    configBytes: configuration,
    lockBytes: null,
    session: _Session(
      projectRoot: projectRoot,
      upgrade: false,
      previous: null,
      cancel: cancel,
      offline: offline,
      allowFetch: allowFetch,
    ),
    candidate: sink,
  );
  return CandidateResolution._(
    plan,
    Map.unmodifiable(sink.profiles),
    sink.skillProblems,
  );
}

/// Runs [action] holding [resolver]'s `get` lock of the project at
/// [projectRoot], as [WayfinderProfileResolver.apply] does, so no `get`
/// changes the project meanwhile. Throws `resolution-busy` while another
/// holder has it. The lock does not nest: inside [action], write a plan
/// with [applyCandidateResolution], never with `apply`.
Future<T> withProjectLock<T>(
  WayfinderProfileResolver resolver,
  String projectRoot,
  Future<T> Function() action,
) => resolver._withProjectLock(projectRoot, action);

/// Writes [resolution] as [WayfinderProfileResolver.apply] would, refusing
/// changed inputs the same way, for a caller that already holds the
/// project's lock through [withProjectLock]. It deletes nothing: marked
/// skill directories of other Profiles are the caller's to report, and
/// interrupted copies wait for the next `get`.
Future<ProfileResolutionResult> applyCandidateResolution(
  WayfinderProfileResolver resolver,
  CandidateResolution resolution,
) => resolver._apply(resolution.plan, prune: false);

/// The commit at the default branch (`HEAD`) of the Profile source [git],
/// as resolving it from [projectRoot] reaches it. Clones the source into the
/// cache when it is missing and refreshes it otherwise, as [allowFetch]
/// allows, unless [offline], which reads a cached mirror as it is and
/// throws [ProfileFetchRequiredException] without one.
Future<({String commit, List<ProfileFetch> fetches})> resolveDefaultBranch(
  WayfinderProfileResolver resolver, {
  required String projectRoot,
  required String git,
  bool offline = false,
  ProfileFetchPolicy? allowFetch,
  WayfinderCancellation? cancel,
}) async {
  final session = _Session(
    projectRoot: projectRoot,
    upgrade: false,
    previous: null,
    cancel: cancel,
    offline: offline,
    allowFetch: allowFetch,
  );
  final source = WayfinderProfileSource(git: git, ref: 'HEAD', path: '.');
  final commit = await resolver._withMirror(source, session, (
    location,
    mirror,
  ) async {
    if (!await mirror.exists()) {
      await resolver._cloneMirror(
        source,
        location,
        mirror,
        session,
        defaultBranch: true,
      );
    } else if (!offline) {
      session.fetch(
        ProfileFetchKind.refresh,
        source,
        location,
        defaultBranch: true,
      );
      final result = await resolver._git(session, [
        'remote',
        'update',
        '--prune',
      ], workingDirectory: mirror.path);
      resolver._checkGit(result, 'refresh Profile source $git');
    }
    final result = await resolver._git(session, [
      'rev-parse',
      '--verify',
      'HEAD^{commit}',
    ], workingDirectory: mirror.path);
    if (result.exitCode != 0) {
      throw WayfinderProfileResolutionException(
        'Profile source $git has no default branch to resolve. Name a ref.',
      );
    }
    return result.text.trim();
  });
  return (
    commit: commit,
    fetches: List<ProfileFetch>.unmodifiable(session.fetches),
  );
}

/// A failure to resolve or select a Profile. [diagnostic] is how validation
/// reports it when it finds no usable Profile; [code] is its value.
final class WayfinderProfileResolutionException extends WayfinderException {
  WayfinderProfileResolutionException(
    String message, {
    this.diagnostic = DiagnosticCode.profileUnresolved,
    this.remedy,
  }) : super(diagnostic.slug, message);

  final DiagnosticCode diagnostic;

  /// What fixes it, when the resolver knows, for a host to word: the
  /// message names no command.
  final DiagnosticRemedy? remedy;
}

/// `profile-unresolved`: installing the locked Profile skills would replace
/// what Wayfinder may not, so nothing was written. [directories] lists each
/// refused directory: [ProfileSkillDirectoryState.outside] when its skill
/// root resolves outside the project through a symbolic link, and
/// [ProfileSkillDirectoryState.unmarked] when something is there without the
/// Profile's marker. The message names the roots outside the project, or
/// else the unmarked directories, and no remedy: moving them aside or
/// pointing the roots inside the project is the host's to say. A plan with
/// `skills: false` reports the same directories in
/// [ProfileResolutionPlan.skillDirectories] instead.
final class ProfileSkillDirectoriesException
    extends WayfinderProfileResolutionException {
  ProfileSkillDirectoriesException(List<ProfileSkillDirectory> directories)
    : directories = List.unmodifiable(directories),
      super(_message(directories));

  final List<ProfileSkillDirectory> directories;

  /// The skill roots that resolve outside the project, in
  /// `ProfileSkills.roots` order; empty when only unmarked directories are
  /// in the way.
  List<String> get outsideRoots => _outsideRoots(directories);

  static List<String> _outsideRoots(List<ProfileSkillDirectory> directories) =>
      [
        for (final root in ProfileSkills.roots)
          if (directories.any(
            (directory) =>
                directory.root == root &&
                directory.state == ProfileSkillDirectoryState.outside,
          ))
            root,
      ];

  static String _message(List<ProfileSkillDirectory> directories) {
    final outside = _outsideRoots(directories);
    if (skillRootsOutsideMessage(outside) case final message?) return message;
    final unmarked = [
      for (final directory in directories)
        if (directory.state == ProfileSkillDirectoryState.unmarked)
          directory.path,
    ];
    return '${unmarked.join(', ')} already exists without a '
        '${ProfileSkills.marker} marker, so wayfinder did not install it.';
  }
}

/// `resolution-busy`: another holder kept a lock that resolving needs.
/// [projectRoot] names the project whose `get` lock another `apply`,
/// `resolve` or adoption holds; [source] names the Profile source whose
/// mirror another planner held for longer than the resolver waits
/// ([WayfinderProfileResolver.mirrorLockTimeout]). Exactly one is set.
/// Retrying once the holder finishes is the remedy.
final class ProfileResolutionBusyException extends WayfinderException {
  ProfileResolutionBusyException.project(String this.projectRoot)
    : source = null,
      super(
        'resolution-busy',
        'Another Profile resolution is changing $projectRoot. Retry when it '
            'finishes.',
      );

  ProfileResolutionBusyException.source(String this.source, Duration waited)
    : projectRoot = null,
      super(
        'resolution-busy',
        'Another wayfinder process held the Profile source $source for '
            '${waited.inSeconds} seconds. Retry when it finishes.',
      );

  final String? projectRoot;

  /// The source as the configuration or a package spells its `git`.
  final String? source;
}

/// `wayfinder.lock` as one read found it: [lock] null when there is none or
/// it does not parse, and [error] set when it could not be read.
typedef _LockRead = ({ProfileLock? lock, FileSystemException? error});

final class _Session {
  _Session({
    required this.projectRoot,
    required this.upgrade,
    required this.previous,
    required this.cancel,
    this.offline = false,
    this.allowFetch,
    this.lockedOnly = false,
  });

  final String projectRoot;
  final bool upgrade;
  final ProfileLock? previous;
  final WayfinderCancellation? cancel;

  /// Resolve each source at the commit [previous] pins for it, and refuse
  /// a source it pins none for, so the lock stays as it is.
  final bool lockedOnly;

  /// Refuse to reach the network: a cached mirror is read as it is, without
  /// refreshing a branch or tag, and [fetch] throws `fetch-required`.
  final bool offline;

  /// Decides each fetch when not [offline]; null allows every one.
  final ProfileFetchPolicy? allowFetch;

  bool get fetched => fetches.isNotEmpty;

  /// Each clone or refresh, in order.
  final fetches = <ProfileFetch>[];

  /// Each package file read, by cache path, with the SHA-256 of its bytes.
  final snapshots = <String, String>{};

  /// Records a fetch of [source] that is about to run, or throws
  /// [ProfileFetchRequiredException] when [offline] or [allowFetch] refuses
  /// it.
  void fetch(
    ProfileFetchKind kind,
    WayfinderProfileSource source,
    String location, {
    bool defaultBranch = false,
  }) {
    final fetch = ProfileFetch(
      kind: kind,
      git: source.git,
      location: location,
      ref: defaultBranch ? null : source.ref,
    );
    if (offline || !(allowFetch?.call(fetch) ?? true)) {
      throw ProfileFetchRequiredException(fetch, offline: offline);
    }
    fetches.add(fetch);
  }
}

/// The validation the CLI and MCP server share: [resolver]'s selection for
/// [bundle], then [ProfileValidator.validate]. When no Profile is selected,
/// it first restores package files the cache lacks out of the existing
/// Profile mirrors ([WayfinderProfileResolver.restoreCachedPackages]) and
/// selects again, so a cache Wayfinder 0.2 wrote validates as it did. That
/// runs `git show` through the resolver's runner and never fetches; with a
/// complete cache, validation runs no Git. It writes nothing in the project
/// beyond what [fix] writes in [bundle]. [configPath] and [projectRoot]
/// bind [bundle] as [WayfinderProfileResolver.select] does.
Future<ProfileValidationResult> validateWithProfileSources(
  String bundle, {
  String? configPath,
  String? projectRoot,
  required WayfinderProfileResolver resolver,
  bool fix = false,
}) async {
  Future<ProfileSelection> select() =>
      resolver.select(bundle, configPath: configPath, projectRoot: projectRoot);
  var selection = await select();
  if (selection is UnselectedProfile &&
      await resolver.restoreCachedPackages(
            bundle,
            configPath: configPath,
            projectRoot: projectRoot,
          ) >
          0) {
    selection = await select();
  }
  return const ProfileValidator().validate(bundle, selection, fix: fix);
}

ProfileId? _profileIdOrNull(String value) {
  try {
    return ProfileId.parse(value);
  } on FormatException {
    return null;
  }
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}
