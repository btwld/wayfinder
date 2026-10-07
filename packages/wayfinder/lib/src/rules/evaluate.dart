import 'dart:convert';

import '../profile_finding.dart';
import '../profile_rule_descriptors.dart';
import 'builtins.dart';
import 'catalog.dart';
import 'facts.dart';
import 'profile.dart';

({List<ProfileFinding> findings, List<ProfileSummaryEntry> summary}) evaluate(
  EffectiveProfile profile,
  BundleFacts facts,
) {
  final slots = profile.slots;
  final findings = <ProfileFinding>[];
  final summary = <ProfileSummaryEntry>[];
  for (final catalog in profile.catalogs) {
    for (final rule in catalog.rules) {
      _evaluate(rule, catalog.release, slots, facts, findings, summary);
    }
  }
  return (findings: findings, summary: summary);
}

void _evaluate(
  CatalogRule rule,
  String release,
  Map<Slot, List<String>> slots,
  BundleFacts facts,
  List<ProfileFinding> findings,
  List<ProfileSummaryEntry> summary,
) {
  void report(String message, String path) {
    switch (FindingDescriptor.of(rule.descriptor)) {
      case null:
        summary.add(
          ProfileSummaryEntry(
            descriptor: rule.descriptor,
            message: message,
            path: path,
            profileRelease: release,
          ),
        );
      case final descriptor:
        findings.add(
          ProfileFinding(
            descriptor: descriptor,
            message: message,
            path: path,
            profileRelease: release,
          ),
        );
    }
  }

  switch (rule.check) {
    case final SchemaCheck check:
      if (!check.slots.every(slots.containsKey)) return;
      final predicate = check.compile(slots);
      for (final subject in facts.of(check.subject)) {
        final List<Object?> failing;
        if (check.each case final each?) {
          if (!subject.facts.containsKey(each)) continue;
          failing = switch (subject.facts[each]) {
            final List<Object?> elements => [
              for (final element in elements)
                if (!predicate.test(SchemaCheck.element(element)))
                  SchemaCheck.value(element, check.failingField),
            ],
            final value =>
              predicate.test({'value': value}) ? const [] : [value],
          };
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

Map<String, String>? fixes(EffectiveProfile profile, BundleFacts facts) {
  Map<String, String>? files;
  for (final catalog in profile.catalogs) {
    for (final rule in catalog.rules) {
      if (rule.check case BuiltinCheck(
        builtin: Builtin(:final fix?),
        :final params,
      )) {
        (files ??= {}).addAll(fix(facts, params));
      }
    }
  }
  return files;
}

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
      return failing.toSet().map(_show).join(', ');
    }
    return facts.containsKey(name) ? _show(facts[name]) : match[0]!;
  });
}

String _show(Object? value) => value is String ? value : jsonEncode(value);
