import 'dart:collection';

import '../profile_finding.dart';
import 'catalog.dart';
import 'facts.dart';
import 'profile.dart';

/// The engine: every rule of the selected catalog over every subject. A
/// schema rule that references a slot the vocabulary cannot provide is
/// skipped. Findings carry the catalog's release; the caller orders them.
List<ProfileFinding> evaluate(EffectiveProfile profile, BundleFacts facts) {
  final catalog = profile.catalog;
  final slots = profile.vocabulary.slots;
  final findings = <ProfileFinding>[];
  for (final rule in catalog.rules) {
    switch (rule.check) {
      case final SchemaCheck check:
        if (!check.slots.every(slots.containsKey)) continue;
        final predicate = check.compile(slots);
        for (final subject in facts.of(check.subject)) {
          final List<Object?> failing;
          if (check.each case final each?) {
            final elements = subject.facts[each];
            if (elements is! List<Object?>) continue;
            failing = [
              for (final element in elements)
                if (!predicate.test(SchemaCheck.element(element)))
                  SchemaCheck.value(element),
            ];
            if (failing.isEmpty) continue;
          } else {
            if (predicate.test(subject.facts)) continue;
            failing = const [];
          }
          findings.add(
            ProfileFinding(
              descriptor: rule.descriptor,
              message: _render(
                rule.message,
                failing: failing,
                facts: subject.facts,
              ),
              path: subject.locations[check.at]!,
              profileRelease: catalog.release,
            ),
          );
        }
      case BuiltinCheck(:final builtin, :final params):
        for (final violation in builtin.run(facts, params)) {
          findings.add(
            ProfileFinding(
              descriptor: rule.descriptor,
              message: _render(
                rule.message,
                failing: violation.failing,
                facts: violation.facts,
                messageId: violation.messageId,
              ),
              path: violation.location,
              profileRelease: catalog.release,
            ),
          );
        }
    }
  }
  return findings;
}

/// Plain substitution: `{failing}` renders the distinct failing values in
/// first-occurrence order, and `{name}` renders that fact. A placeholder no
/// fact fills stays visible in the output rather than failing the run.
String _render(
  RuleMessage message, {
  required List<Object?> failing,
  required Map<String, Object?> facts,
  String? messageId,
}) {
  final template = switch (message) {
    SingleMessage(:final template) => template,
    MessageVariants(:final byId) =>
      byId[messageId] ??
          (throw StateError('builtin named undeclared message id $messageId')),
  };
  return template.replaceAllMapped(placeholder, (match) {
    final name = match[1]!;
    if (name == 'failing') {
      return LinkedHashSet<Object?>.of(
        failing,
      ).map((value) => '$value').join(', ');
    }
    return facts.containsKey(name) ? '${facts[name]}' : match[0]!;
  });
}
