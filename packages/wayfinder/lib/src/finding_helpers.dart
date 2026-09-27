String? nonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
