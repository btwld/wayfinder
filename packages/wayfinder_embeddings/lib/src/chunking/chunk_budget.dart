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
bool fitsNonWhitespaceBudget(String value, int maxLength) =>
    nonWhitespaceLength(value) <= maxLength;

/// Returns whether appending [addition] to [current] would fit the budget.
bool appendFitsNonWhitespaceBudget(
  String current,
  String addition,
  int maxLength,
) => nonWhitespaceLength(current) + nonWhitespaceLength(addition) <= maxLength;

bool _isWhitespaceCodeUnit(int codeUnit) => switch (codeUnit) {
  0x20 || >= 0x09 && <= 0x0D => true,
  _ => false,
};
