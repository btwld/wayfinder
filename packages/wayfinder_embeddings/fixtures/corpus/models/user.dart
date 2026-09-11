/// User model representing a customer or admin in the e-commerce system.
class User {
  final String id;
  final String email;
  final String passwordHash;
  final String firstName;
  final String lastName;
  final UserRole role;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isActive;
  final Address? shippingAddress;
  final Address? billingAddress;

  /// Creates a new user.
  User({
    required this.id,
    required this.email,
    required this.passwordHash,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = true,
    this.shippingAddress,
    this.billingAddress,
  });

  /// Creates a user from JSON data.
  factory User.fromJson(Map<String, Object?> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      passwordHash: json['password_hash'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      role: UserRole.values.firstWhere(
        (role) => role.toString() == 'UserRole.${json['role'] as String}',
        orElse: () => UserRole.customer,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      shippingAddress: json['shipping_address'] != null
          ? Address.fromJson(json['shipping_address'] as Map<String, Object?>)
          : null,
      billingAddress: json['billing_address'] != null
          ? Address.fromJson(json['billing_address'] as Map<String, Object?>)
          : null,
    );
  }

  /// Converts the user to JSON.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'email': email,
      'password_hash': passwordHash,
      'first_name': firstName,
      'last_name': lastName,
      'role': role.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'is_active': isActive,
      'shipping_address': shippingAddress?.toJson(),
      'billing_address': billingAddress?.toJson(),
    };
  }

  /// Returns the full name of the user.
  String get fullName => '$firstName $lastName';

  /// Checks if the user is an admin.
  bool get isAdmin => role == UserRole.admin;

  /// Creates a copy of this user with the specified fields updated.
  User copyWith({
    String? id,
    String? email,
    String? passwordHash,
    String? firstName,
    String? lastName,
    UserRole? role,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
    Address? shippingAddress,
    Address? billingAddress,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      passwordHash: passwordHash ?? this.passwordHash,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      billingAddress: billingAddress ?? this.billingAddress,
    );
  }
}

/// Represents the role of a user in the system.
enum UserRole { customer, admin, support }

/// Represents a physical address.
class Address {
  final String street;
  final String city;
  final String state;
  final String postalCode;
  final String country;

  /// Creates a new address.
  Address({
    required this.street,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
  });

  /// Creates an address from JSON data.
  factory Address.fromJson(Map<String, Object?> json) {
    return Address(
      street: json['street'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
      postalCode: json['postal_code'] as String,
      country: json['country'] as String,
    );
  }

  /// Converts the address to JSON.
  Map<String, Object?> toJson() {
    return {
      'street': street,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'country': country,
    };
  }

  /// Returns the formatted address as a string.
  String get formattedAddress {
    return '$street, $city, $state $postalCode, $country';
  }
}
