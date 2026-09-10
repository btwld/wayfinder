import '../util/checks.dart';

/// Counts non-whitespace characters for chunk budget decisions.
///
/// This approximates token pressure better than raw UTF-16 length because
/// indentation, line wrapping, and blank lines should not force chunk splits by
/// themselves.
int nonWhitespaceLength(String value) {
  var count = 0;
  for (var i = 0; i < value.length; i++) {
    if (!_isWhitespaceCodeUnit(value.codeUnitAt(i))) {
      count++;
    }
  }
  return count;
}

/// Returns whether [value] fits within a non-whitespace character budget.
bool fitsNonWhitespaceBudget(String value, int maxLength) {
  return nonWhitespaceLength(value) <= maxLength;
}

/// Returns whether appending [addition] to [current] would fit the budget.
bool appendFitsNonWhitespaceBudget(
  String current,
  String addition,
  int maxLength,
) {
  return nonWhitespaceLength(current) + nonWhitespaceLength(addition) <=
      maxLength;
}

/// Validates public chunk-budget configuration values.
int checkPositiveChunkConfig(int value, String name) =>
    checkPositive(value, name);

bool _isWhitespaceCodeUnit(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0B ||
      codeUnit == 0x0C ||
      codeUnit == 0x0D;
}
