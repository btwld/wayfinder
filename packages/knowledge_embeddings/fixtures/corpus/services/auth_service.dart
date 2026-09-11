import 'dart:convert';
import 'dart:math';

import '../config/app_config.dart';
import '../models/user.dart';
import '../utils/crypto_utils.dart';
import '../utils/logger.dart';
import 'database_service.dart';

/// Service for handling user authentication.
class AuthService {
  final DatabaseService _db;
  final Logger _logger;
  final CryptoUtils _crypto;
  final AuthConfig _config;

  /// Creates a new authentication service.
  AuthService(this._db, this._logger, this._crypto, this._config);

  /// Authenticates a user with email and password.
  ///
  /// Returns a token if authentication is successful, null otherwise.
  Future<String?> login(String email, String password) async {
    try {
      // Find user by email
      final user = await _db.findUserByEmail(email);

      if (user == null) {
        _logger.info('Login attempt failed: User not found for email $email');
        return null;
      }

      // Check if user is active
      if (!user.isActive) {
        _logger.info(
          'Login attempt failed: User account is inactive for email $email',
        );
        return null;
      }

      // Verify password
      if (!_crypto.verifyPassword(password, user.passwordHash)) {
        _logger.info('Login attempt failed: Invalid password for email $email');
        return null;
      }

      // Update last login time
      await _db.updateUser(user.copyWith(lastLoginAt: DateTime.now()));

      // Generate token
      final token = _generateJwtToken(user);

      _logger.info('User logged in successfully: ${user.id}');
      return token;
    } catch (e) {
      _logger.error('Error during login: $e');
      return null;
    }
  }

  /// Registers a new user.
  ///
  /// Returns the created user if registration is successful, null otherwise.
  Future<User?> register(
    String email,
    String password,
    String firstName,
    String lastName,
  ) async {
    try {
      // Check if user already exists
      final existingUser = await _db.findUserByEmail(email);

      if (existingUser != null) {
        _logger.info('Registration failed: Email already in use: $email');
        return null;
      }

      // Hash password
      final passwordHash = _crypto.hashPassword(password);

      // Create user
      final user = User(
        id: _generateId(),
        email: email,
        passwordHash: passwordHash,
        firstName: firstName,
        lastName: lastName,
        role: UserRole.customer,
        createdAt: DateTime.now(),
        isActive: true,
      );

      // Save user to database
      await _db.createUser(user);

      _logger.info('User registered successfully: ${user.id}');
      return user;
    } catch (e) {
      _logger.error('Error during registration: $e');
      return null;
    }
  }

  /// Logs out a user.
  ///
  /// Returns true if logout is successful, false otherwise.
  Future<bool> logout(String token) async {
    try {
      // In a real implementation, this would invalidate the token
      _logger.info('User logged out successfully');
      return true;
    } catch (e) {
      _logger.error('Error during logout: $e');
      return false;
    }
  }

  /// Resets a user's password.
  ///
  /// Returns true if password reset is successful, false otherwise.
  Future<bool> resetPassword(String email) async {
    try {
      // Find user by email
      final user = await _db.findUserByEmail(email);

      if (user == null) {
        _logger.info('Password reset failed: User not found for email $email');
        return false;
      }

      // In a real implementation, this would send a password reset email
      _logger.info('Password reset initiated for user: ${user.id}');
      return true;
    } catch (e) {
      _logger.error('Error during password reset: $e');
      return false;
    }
  }

  /// Changes a user's password.
  ///
  /// Returns true if password change is successful, false otherwise.
  Future<bool> changePassword(
    String userId,
    String currentPassword,
    String newPassword,
  ) async {
    try {
      // Find user by ID
      final user = await _db.findUserById(userId);

      if (user == null) {
        _logger.info('Password change failed: User not found: $userId');
        return false;
      }

      // Verify current password
      if (!_crypto.verifyPassword(currentPassword, user.passwordHash)) {
        _logger.info(
          'Password change failed: Invalid current password for user: $userId',
        );
        return false;
      }

      // Hash new password
      final newPasswordHash = _crypto.hashPassword(newPassword);

      // Update user
      await _db.updateUser(user.copyWith(passwordHash: newPasswordHash));

      _logger.info('Password changed successfully for user: $userId');
      return true;
    } catch (e) {
      _logger.error('Error during password change: $e');
      return false;
    }
  }

  /// Verifies a token and returns the user ID if valid.
  ///
  /// Returns the user ID if the token is valid, null otherwise.
  Future<String?> verifyToken(String token) async {
    try {
      // In a real implementation, this would verify the token
      // and extract the user ID

      // For this example, we'll just extract the user ID from the token
      final payload = _crypto.verifyJwt(token, _config.jwtSecret);

      if (payload == null) {
        _logger.info('Token verification failed: Invalid token');
        return null;
      }

      final userId = payload['sub'] as String;

      return userId;
    } catch (e) {
      _logger.error('Error during token verification: $e');
      return null;
    }
  }

  /// Generates a JWT token for a user.
  String _generateJwtToken(User user) {
    final payload = {
      'sub': user.id,
      'name': user.fullName,
      'email': user.email,
      'role': user.role.toString().split('.').last,
    };

    return _crypto.generateJwt(
      payload,
      _config.jwtSecret,
      expiry: _config.tokenExpiry,
    );
  }

  /// Generates a unique ID.
  String _generateId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(values);
  }
}
