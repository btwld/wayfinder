import 'dart:async';
import 'dart:isolate';

import 'package:okf/okf_io.dart';

import 'profile_finding.dart';
import 'project/cancellation.dart';
import 'project/exception.dart';
import 'rules/evaluate.dart';
import 'rules/facts.dart';
import 'validation.dart';

/// What a Profile assessment judges, all in memory: okf's load results and
/// the [selection] they are judged with.
///
/// A write (`KnowledgeWriter.prepare`) judges the bundle as it stands
/// ([base]) and okf's prepared candidate ([candidate]). Adoption
/// (`KnowledgeAdoption`) judges one bundle, the one it seeds or binds, with
/// nothing to compare: its input has no [base].
///
/// It holds no file handle, lock or callback into the caller, so a host may
/// send it to another isolate and run [assess] there, as [assessWithin]
/// does.
final class KnowledgeAssessmentInput {
  /// A write's input: [base], the bundle as it stands, and [candidate], the
  /// bundle the write would leave.
  const KnowledgeAssessmentInput({
    required OkfBundleLoadResult this.base,
    required this.candidate,
    required this.selection,
    this.validator = const ProfileValidator(),
  });

  /// One [bundle] to judge with no base, as adoption judges the bundle it
  /// seeds or binds: [candidate] is [bundle], and [base] is null.
  const KnowledgeAssessmentInput.bundle({
    required OkfBundleLoadResult bundle,
    required this.selection,
    this.validator = const ProfileValidator(),
  }) : base = null,
       candidate = bundle;

  /// The bundle as it stands, for a write; null for one bundle judged on its
  /// own.
  final OkfBundleLoadResult? base;

  /// The bundle being judged: a write's candidate, or adoption's bundle.
  final OkfBundleLoadResult candidate;
  final ProfileSelection selection;
  final ProfileValidator validator;

  /// How long [assessWithin] lets an assessment run by default.
  static const assessTimeout = Duration(seconds: 30);

  /// Judges [candidate], and [base] when there is one, with
  /// `ProfileValidator.validateLoaded`. It runs the base's rules even when
  /// OKF blocks the base, so a write that repairs OKF is charged only with
  /// the findings it adds.
  ///
  /// Synchronous, and reads no bundle file and takes no lock; only the
  /// `path-targets-exist` builtin checks the disk, for a path target the
  /// loaded bundle does not hold. A Profile rule can be slow, such as a
  /// `pattern` that backtracks without end on a concept's text, and nothing
  /// on the calling isolate can interrupt it: [assessWithin] bounds it.
  KnowledgeAssessment assess() {
    final base = this.base;
    if (base == null) {
      return KnowledgeAssessment(
        base: null,
        candidate: validator.validateLoaded(candidate, selection),
        baseFindings: const [],
      );
    }
    final baseResult = validator.validateLoaded(base, selection);
    return KnowledgeAssessment(
      base: baseResult,
      candidate: validator.validateLoaded(candidate, selection),
      baseFindings: switch ((baseResult.profile, selection)) {
        (Assessed(:final findings), _) => findings,
        (BlockedByOkf(), SelectedProfile(:final profile)) => evaluate(
          profile,
          BundleFacts.project(
            base,
            profile: profile,
            buildGraph: validator.buildGraph,
          ),
        ).findings,
        _ => const [],
      },
    );
  }

  /// [assess], bounded: it runs on an isolate of its own, which is killed
  /// once it runs past [timeout] or [cancel] is cancelled. A host passes it
  /// as its [KnowledgeAssessor] to `KnowledgeWriter` and `KnowledgeAdoption`:
  ///
  /// ```dart
  /// assess: (input, cancel) => input.assessWithin(cancel: cancel),
  /// ```
  ///
  /// Returns what [assess] returns. Throws [WayfinderException] with the code
  /// `assessment-timeout` when the assessment ran past [timeout],
  /// `cancelled` ([WayfinderException.cancelled]) when [cancel] stopped it,
  /// and `assessment-failed` when it stopped on an error, such as a stack
  /// overflow in a rule, or no isolate could be started for it, as for an
  /// input with a `validator` that cannot be sent to one. Unlike
  /// `ProfilePackage.parseWithin`, it never falls back to the calling
  /// isolate, since its caller asked for a bound.
  ///
  /// The assessment isolate receives a copy of this input and reads no
  /// bundle file but the targets `path-targets-exist` checks, so killing it
  /// leaves no lock held and nothing written. Each call starts one isolate.
  Future<KnowledgeAssessment> assessWithin({
    Duration timeout = assessTimeout,
    WayfinderCancellation? cancel,
  }) async {
    throwIfCancelled(cancel);
    final port = ReceivePort();
    // The assessment, or the failure that stopped it.
    final outcome = Completer<Object>();
    void finish(Object result) {
      if (!outcome.isCompleted) outcome.complete(result);
    }

    // Sent on [port]: the assessment, the error report of an uncaught error
    // as a list, and null when the isolate exits.
    port.listen((Object? message) {
      switch (message) {
        case final KnowledgeAssessment assessment:
          finish(assessment);
        case [final error, _]:
          finish(
            WayfinderException(
              'assessment-failed',
              'The Profile assessment stopped on an error: $error',
            ),
          );
        default:
          finish(
            const WayfinderException(
              'assessment-failed',
              'The Profile assessment stopped without a result.',
            ),
          );
      }
    });
    Timer? deadline;
    final hook = _CancelHook();
    try {
      final Isolate isolate;
      try {
        isolate = await Isolate.spawn(
          _assessOnIsolate,
          (port.sendPort, this),
          onExit: port.sendPort,
          onError: port.sendPort,
          debugName: 'wayfinder-assessment',
        );
      } on Object catch (error) {
        // Spawning refuses an input it cannot send, such as a validator
        // holding a port, as well as a failed start.
        throw WayfinderException(
          'assessment-failed',
          'No isolate could be started for the Profile assessment: $error',
        );
      }
      void stop(WayfinderException failure) {
        if (outcome.isCompleted) return;
        isolate.kill(priority: Isolate.immediate);
        finish(failure);
      }

      deadline = Timer(
        timeout,
        () => stop(
          WayfinderException(
            'assessment-timeout',
            'The Profile assessment did not finish within '
                '${_describe(timeout)}, so it was stopped. A rule of the '
                'Profile ran too long on this bundle, as a pattern that '
                'backtracks without end can.',
          ),
        ),
      );
      // A cancellation outlives this call, so what it holds is only [hook],
      // which forgets the isolate and the outcome once the call ends.
      hook.action = () => stop(const WayfinderException.cancelled());
      if (cancel != null) unawaited(cancel.whenCancelled.then(hook.fire));
      final result = await outcome.future;
      if (result is KnowledgeAssessment) return result;
      throw result;
    } finally {
      hook.action = null;
      deadline?.cancel();
      port.close();
    }
  }

  static String _describe(Duration duration) =>
      duration.inMilliseconds % 1000 == 0
      ? '${duration.inSeconds} s'
      : '${duration.inMilliseconds} ms';
}

/// What a cancellation calls back into one
/// [KnowledgeAssessmentInput.assessWithin]: [action] while that call runs,
/// nothing once it has ended.
final class _CancelHook {
  void Function()? action;

  void fire(void _) => action?.call();
}

void _assessOnIsolate((SendPort, KnowledgeAssessmentInput) message) {
  final (port, input) = message;
  Isolate.exit(port, input.assess());
}

/// The verdicts [KnowledgeAssessmentInput.assess] reaches.
final class KnowledgeAssessment {
  KnowledgeAssessment({
    required this.base,
    required this.candidate,
    required Iterable<ProfileFinding> baseFindings,
  }) : baseFindings = List.unmodifiable(baseFindings);

  /// The input's base as `validate` reports it; null for an input with no
  /// base.
  final ProfileValidationResult? base;

  /// The input's candidate as `validate` would report it: a write's after
  /// the commit, or adoption's bundle.
  final ProfileValidationResult candidate;

  /// The Profile findings of the base's rules, even when OKF blocks the
  /// base; the candidate's findings are compared with these. Empty for an
  /// input with no base.
  final List<ProfileFinding> baseFindings;
}

/// Runs a Profile assessment for `KnowledgeWriter.prepare`, which calls it
/// once per plan after okf's shared claim on the bundle is released, and
/// for `KnowledgeAdoption`, which calls it once when planning and once for
/// the bundle it adopted. Either gives it only what okf loaded or prepared
/// in memory.
///
/// It returns what [KnowledgeAssessmentInput.assess] returns for [input].
/// The default runs that on the calling isolate. A host that must bound a
/// Profile's rules runs it on an isolate it kills at a deadline, or when
/// [cancel], the cancellation the caller was given, is cancelled, as
/// [KnowledgeAssessmentInput.assessWithin] does; whatever it throws, such as
/// [WayfinderException.cancelled], the caller throws or reports.
typedef KnowledgeAssessor =
    Future<KnowledgeAssessment> Function(
      KnowledgeAssessmentInput input,
      WayfinderCancellation? cancel,
    );

/// The default [KnowledgeAssessor]: [KnowledgeAssessmentInput.assess] on the
/// calling isolate, unbounded.
Future<KnowledgeAssessment> assessOnCallingIsolate(
  KnowledgeAssessmentInput input,
  WayfinderCancellation? cancel,
) async => input.assess();
