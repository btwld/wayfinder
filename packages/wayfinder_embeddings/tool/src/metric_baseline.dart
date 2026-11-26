import 'dart:convert';
import 'dart:io';

/// Largest allowed drop below a baseline value.
const baselineTolerance = 0.01;

/// Describes each value that fell more than [baselineTolerance] below
/// [baseline], in the splits that [current] measured.
///
/// Both maps hold the [identity] keys and `split -> run -> metric -> value`.
/// A baseline recorded for a different identity fails as a whole.
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
    for (final MapEntry(key: run, value: metrics) in expected.entries) {
      final values = measured[run] as Map<String, Object?>?;
      for (final MapEntry(key: metric, value: floor)
          in (metrics! as Map<String, Object?>).entries) {
        final value = values?[metric] as num?;
        if (value == null) {
          failures.add('$split $run $metric: missing');
        } else if (value < (floor! as num) - baselineTolerance) {
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
