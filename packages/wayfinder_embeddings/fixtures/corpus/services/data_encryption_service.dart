import 'dart:convert';
import 'dart:math';

import '../config/app_config.dart';
import '../utils/crypto_utils.dart';
import '../utils/logger.dart';

/// Service for encrypting and decrypting sensitive data.
class DataEncryptionService {
  final Logger _logger;
  final CryptoUtils _crypto;
  final AuthConfig _config;

  /// Creates a new data encryption service.
  DataEncryptionService(this._logger, this._crypto, this._config);

  /// Encrypts sensitive data.
  String encryptData(Map<String, Object?> data, {String? customKey}) {
    _logger.debug('Encrypting data');

    try {
      final jsonData = json.encode(data);
      final encryptionKey = customKey ?? _config.jwtSecret;

      return _crypto.encrypt(jsonData, encryptionKey);
    } catch (e) {
      _logger.error('Error encrypting data: $e');
      throw Exception('Failed to encrypt data: $e');
    }
  }

  /// Decrypts sensitive data.
  Map<String, Object?> decryptData(String encryptedData, {String? customKey}) {
    _logger.debug('Decrypting data');

    try {
      final encryptionKey = customKey ?? _config.jwtSecret;
      final jsonData = _crypto.decrypt(encryptedData, encryptionKey);

      return json.decode(jsonData) as Map<String, Object?>;
    } catch (e) {
      _logger.error('Error decrypting data: $e');
      throw Exception('Failed to decrypt data: $e');
    }
  }

  /// Encrypts a file.
  Future<String> encryptFile(List<int> fileData, {String? customKey}) async {
    _logger.debug('Encrypting file of size: ${fileData.length} bytes');

    try {
      final encryptionKey = customKey ?? _config.jwtSecret;
      final base64Data = base64.encode(fileData);

      return _crypto.encrypt(base64Data, encryptionKey);
    } catch (e) {
      _logger.error('Error encrypting file: $e');
      throw Exception('Failed to encrypt file: $e');
    }
  }

  /// Decrypts a file.
  Future<List<int>> decryptFile(
    String encryptedData, {
    String? customKey,
  }) async {
    _logger.debug('Decrypting file');

    try {
      final encryptionKey = customKey ?? _config.jwtSecret;
      final base64Data = _crypto.decrypt(encryptedData, encryptionKey);

      return base64.decode(base64Data);
    } catch (e) {
      _logger.error('Error decrypting file: $e');
      throw Exception('Failed to decrypt file: $e');
    }
  }

  /// Generates a secure encryption key.
  String generateEncryptionKey({int length = 32}) {
    _logger.debug('Generating encryption key');

    try {
      final random = Random.secure();
      final values = List<int>.generate(length, (_) => random.nextInt(256));

      return base64.encode(values);
    } catch (e) {
      _logger.error('Error generating encryption key: $e');
      throw Exception('Failed to generate encryption key: $e');
    }
  }

  /// Hashes sensitive data for storage.
  String hashSensitiveData(String data) {
    _logger.debug('Hashing sensitive data');

    try {
      return _crypto.simulateHash(data, length: 64);
    } catch (e) {
      _logger.error('Error hashing sensitive data: $e');
      throw Exception('Failed to hash sensitive data: $e');
    }
  }

  /// Encrypts a password for storage.
  String encryptPassword(String password) {
    _logger.debug('Encrypting password');

    try {
      return _crypto.hashPassword(password);
    } catch (e) {
      _logger.error('Error encrypting password: $e');
      throw Exception('Failed to encrypt password: $e');
    }
  }

  /// Verifies a password against an encrypted password.
  bool verifyPassword(String password, String encryptedPassword) {
    _logger.debug('Verifying password');

    try {
      return _crypto.verifyPassword(password, encryptedPassword);
    } catch (e) {
      _logger.error('Error verifying password: $e');
      return false;
    }
  }

  /// Generates a secure token.
  String generateSecureToken({int length = 32}) {
    _logger.debug('Generating secure token');

    try {
      final random = Random.secure();
      final values = List<int>.generate(length, (_) => random.nextInt(256));

      return base64Url.encode(values);
    } catch (e) {
      _logger.error('Error generating secure token: $e');
      throw Exception('Failed to generate secure token: $e');
    }
  }
}
