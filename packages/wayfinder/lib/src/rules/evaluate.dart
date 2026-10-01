import 'dart:collection';

import '../profile_finding.dart';
import '../profile_rule_descriptors.dart';
import 'catalog.dart';
import 'facts.dart';
import 'profile.dart';

/// The engine: every rule of the selected catalog over every subject. A
/// schema rule that references a slot the vocabulary cannot provide is
/// skipped. An error or advisory rule reports findings and a note rule
/// reports summary entries, each carrying the catalog's release; the caller
/// orders them.
({List<ProfileFinding> findings, List<ProfileSummaryEntry> summary}) evaluate(
  EffectiveProfile profile,
  BundleFacts facts,
) {
  final catalog = profile.catalog;
  final slots = profile.slots;
  final findings = <ProfileFinding>[];
  final summary = <ProfileSummaryEntry>[];
  for (final rule in catalog.rules) {
    void report(String message, String path) {
      if (rule.descriptor.severity == RuleSeverity.note) {
        summary.add(
          ProfileSummaryEntry(
            descriptor: rule.descriptor,
            message: message,
            path: path,
            profileRelease: catalog.release,
          ),
        );
      } else {
        findings.add(
          ProfileFinding(
            descriptor: rule.descriptor,
            message: message,
            path: path,
            profileRelease: catalog.release,
          ),
        );
      }
    }

    switch (rule.check) {
      case final SchemaCheck check:
        if (!check.slots.every(slots.containsKey)) continue;
        final predicate = check.compile(slots);
        for (final subject in facts.of(check.subject)) {
          final List<Object?> failing;
          if (check.each case final each?) {
            // An absent or null fact has no elements to judge; a present
            // value that is not an array fails whole, as its own failing
            // value.
            final elements = subject.facts[each];
            if (elements == null) continue;
            failing = elements is List<Object?>
                ? [
                    for (final element in elements)
                      if (!predicate.test(SchemaCheck.element(element)))
                        SchemaCheck.value(element, check.failingField),
                  ]
                : [elements];
            if (failing.isEmpty) continue;
          } else {
            if (predicate.test(subject.facts)) continue;
            failing = const [];
          }
          report(
            _render(rule.message, failing: failing, facts: subject.facts),
            subject.locations[check.at]!,
          );
        }
      case BuiltinCheck(:final builtin, :final params):
        for (final violation in builtin.run(facts, params)) {
          report(
            _render(
              rule.message,
              failing: violation.failing,
              facts: violation.facts,
              messageId: violation.messageId,
            ),
            violation.location,
          );
        }
    }
  }
  return (findings: findings, summary: summary);
}

/// The files `validate --fix` writes: the union of what every fixable
/// builtin rule of the selected catalog generates; null when the catalog
/// declares no fixable rule.
Map<String, String>? fixes(EffectiveProfile profile, BundleFacts facts) {
  Map<String, String>? files;
  for (final rule in profile.catalog.rules) {
    if (rule.check case BuiltinCheck(:final builtin, :final params)) {
      if (builtin.fix case final fix?) {
        (files ??= {}).addAll(fix(facts, params));
      }
    }
  }
  return files;
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
