import 'dart:convert';
import 'dart:io';

/// Describes each difference between [current] and [baseline] that fails the
/// gate, in the splits that [current] measured.
///
/// Both maps hold the [identity] keys and `split -> run -> metric -> value`.
/// Any value below its baseline fails, so losing a single query fails. A
/// measured run or metric without a baseline value, and a baseline run or
/// metric that was not measured, fail too. A baseline recorded for a
/// different identity fails as a whole.
List<String> compareWithBaseline(
  Map<String, Object?> baseline,
  Map<String, Object?> current, {
  required List<String> identity,
}) {
  for (final key in identity) {
    if (baseline[key] != current[key]) {
      return ['baseline $key ${baseline[key]} differs from ${current[key]}'];
    }
  }
  final failures = <String>[];
  for (final split in current.keys.where((key) => !identity.contains(key))) {
    final measured = current[split]! as Map<String, Object?>;
    final expected = (baseline[split] as Map<String, Object?>?) ?? const {};
    for (final run in {...measured.keys, ...expected.keys}) {
      final values = measured[run] as Map<String, Object?>?;
      final floors = expected[run] as Map<String, Object?>?;
      if (floors == null) {
        failures.add('$split $run: no baseline');
        continue;
      }
      if (values == null) {
        failures.add('$split $run: not measured');
        continue;
      }
      for (final metric in {...values.keys, ...floors.keys}) {
        final value = values[metric] as num?;
        final floor = floors[metric] as num?;
        if (floor == null) {
          failures.add('$split $run $metric: no baseline');
        } else if (value == null) {
          failures.add('$split $run $metric: not measured');
        } else if (value < floor) {
          failures.add('$split $run $metric: $value < baseline $floor');
        }
      }
    }
  }
  return failures;
}

/// Writes [current] to [file], keeping the other splits of an existing
/// baseline with the same [identity].
Future<void> writeBaseline(
  File file,
  Map<String, Object?> current, {
  required List<String> identity,
}) async {
  var merged = current;
  if (await file.exists()) {
    final existing =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    if (identity.every((key) => existing[key] == current[key])) {
      merged = {...existing, ...current};
    }
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(merged)}\n',
  );
}
