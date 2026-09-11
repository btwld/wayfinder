/// A simple calculator class.
class Calculator {
  /// Adds two numbers.
  double add(double a, double b) {
    return a + b;
  }

  /// Subtracts two numbers.
  double subtract(double a, double b) {
    return a - b;
  }

  /// Multiplies two numbers.
  double multiply(double a, double b) {
    return a * b;
  }

  /// Divides two numbers.
  double divide(double a, double b) {
    if (b == 0) {
      throw ArgumentError('Cannot divide by zero');
    }
    return a / b;
  }
}

/// A utility class for mathematical operations.
class MathUtils {
  /// Calculates the square of a number.
  static double square(double x) {
    return x * x;
  }

  /// Calculates the cube of a number.
  static double cube(double x) {
    return x * x * x;
  }
}
