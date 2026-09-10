/// Utility class for validating data.
class Validator {
  /// Validates an email address.
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  /// Validates a password.
  ///
  /// Password must be at least 8 characters long and contain at least one
  /// uppercase letter, one lowercase letter, one number, and one special character.
  static bool isValidPassword(String password) {
    if (password.length < 8) {
      return false;
    }

    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);

    return hasUppercase && hasLowercase && hasNumber && hasSpecialChar;
  }

  /// Validates a phone number.
  static bool isValidPhoneNumber(String phoneNumber) {
    final phoneRegex = RegExp(r'^\+?[0-9]{10,15}$');
    return phoneRegex.hasMatch(phoneNumber);
  }

  /// Validates a credit card number using the Luhn algorithm.
  static bool isValidCreditCardNumber(String cardNumber) {
    // Remove spaces and dashes
    final sanitized = cardNumber.replaceAll(RegExp(r'[\s-]'), '');

    // Check if the sanitized string contains only digits
    if (!RegExp(r'^[0-9]+$').hasMatch(sanitized)) {
      return false;
    }

    // Check length
    if (sanitized.length < 13 || sanitized.length > 19) {
      return false;
    }

    // Luhn algorithm
    int sum = 0;
    bool alternate = false;

    for (int i = sanitized.length - 1; i >= 0; i--) {
      int digit = int.parse(sanitized[i]);

      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }

      sum += digit;
      alternate = !alternate;
    }

    return sum % 10 == 0;
  }

  /// Validates a credit card expiry date.
  static bool isValidExpiryDate(int month, int year) {
    if (month < 1 || month > 12) {
      return false;
    }

    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    if (year < currentYear) {
      return false;
    }

    if (year == currentYear && month < currentMonth) {
      return false;
    }

    return true;
  }

  /// Validates a credit card CVV.
  static bool isValidCvv(String cvv) {
    return RegExp(r'^[0-9]{3,4}$').hasMatch(cvv);
  }

  /// Validates a postal code.
  static bool isValidPostalCode(String postalCode, String country) {
    switch (country.toUpperCase()) {
      case 'US':
        return RegExp(r'^\d{5}(-\d{4})?$').hasMatch(postalCode);
      case 'CA':
        return RegExp(
          r'^[A-Za-z]\d[A-Za-z] \d[A-Za-z]\d$',
        ).hasMatch(postalCode);
      case 'UK':
        return RegExp(
          r'^[A-Z]{1,2}\d[A-Z\d]? \d[A-Z]{2}$',
        ).hasMatch(postalCode);
      default:
        return postalCode.isNotEmpty;
    }
  }
}
