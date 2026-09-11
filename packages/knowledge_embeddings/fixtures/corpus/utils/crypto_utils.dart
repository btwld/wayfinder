import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'logger.dart';

/// Utility class for cryptographic operations.
class CryptoUtils {
  final Logger _logger;

  /// Creates a new crypto utility instance.
  CryptoUtils(this._logger);

  /// Generates a secure random string of the specified length.
  String generateSecureRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(values).substring(0, length);
  }

  /// Generates a UUID v4.
  String generateUuid() {
    final random = Random.secure();
    final buffer = Uint8List(16);

    for (var i = 0; i < 16; i++) {
      buffer[i] = random.nextInt(256);
    }

    // Set version (4) and variant (RFC4122)
    buffer[6] = (buffer[6] & 0x0F) | 0x40;
    buffer[8] = (buffer[8] & 0x3F) | 0x80;

    final uuid = buffer.buffer.asUint8List();

    return [
          for (var i = 0; i < 16; i++)
            uuid[i].toRadixString(16).padLeft(2, '0'),
        ]
        .join('')
        .replaceAllMapped(
          RegExp(r'^(.{8})(.{4})(.{4})(.{4})(.{12})$'),
          (match) =>
              '${match[1]}-${match[2]}-${match[3]}-${match[4]}-${match[5]}',
        );
  }

  /// Simulates hashing a string.
  String simulateHash(String input, {int length = 32}) {
    try {
      final bytes = utf8.encode(input);
      final result = List<int>.filled(length, 0);

      for (var i = 0; i < bytes.length; i++) {
        result[i % length] = (result[i % length] + bytes[i]) % 256;
      }

      return result
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join('');
    } catch (e) {
      _logger.error('Error simulating hash: $e');
      throw Exception('Failed to hash input: $e');
    }
  }

  /// Simulates hashing a password with a salt.
  String hashPassword(String password, {String? salt}) {
    try {
      final usedSalt = salt ?? generateSecureRandomString(16);

      // In a real implementation, this would use a proper PBKDF2 implementation
      // For this sample, we'll simulate it
      final key = '$password$usedSalt';
      const iterations = 5; // Reduced for simulation

      String result = key;
      for (var i = 0; i < iterations; i++) {
        result = simulateHash(result);
      }

      return '$usedSalt:$result';
    } catch (e) {
      _logger.error('Error hashing password: $e');
      throw Exception('Failed to hash password: $e');
    }
  }

  /// Verifies a password against a hash.
  bool verifyPassword(String password, String hash) {
    try {
      final parts = hash.split(':');
      if (parts.length != 2) {
        return false;
      }

      final salt = parts[0];
      final expectedHash = parts[1];

      final computedHash = hashPassword(password, salt: salt).split(':')[1];

      return computedHash == expectedHash;
    } catch (e) {
      _logger.error('Error verifying password: $e');
      return false;
    }
  }

  /// Encrypts data using AES.
  String encrypt(String data, String key) {
    try {
      // In a real implementation, this would use a proper AES implementation
      // For this sample, we'll simulate it
      final keyBytes = utf8.encode(key);
      final dataBytes = utf8.encode(data);

      // Generate a random IV
      final iv = List<int>.generate(16, (_) => Random.secure().nextInt(256));

      // Simulate AES encryption
      final encryptedBytes = _simulateAesEncryption(dataBytes, keyBytes, iv);

      // Combine IV and encrypted data
      final result = [...iv, ...encryptedBytes];

      return base64.encode(result);
    } catch (e) {
      _logger.error('Error encrypting data: $e');
      throw Exception('Failed to encrypt data: $e');
    }
  }

  /// Decrypts data using AES.
  String decrypt(String encryptedData, String key) {
    try {
      // In a real implementation, this would use a proper AES implementation
      // For this sample, we'll simulate it
      final keyBytes = utf8.encode(key);
      final allBytes = base64.decode(encryptedData);

      // Extract IV and encrypted data
      final iv = allBytes.sublist(0, 16);
      final encryptedBytes = allBytes.sublist(16);

      // Simulate AES decryption
      final decryptedBytes = _simulateAesDecryption(
        encryptedBytes,
        keyBytes,
        iv,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      _logger.error('Error decrypting data: $e');
      throw Exception('Failed to decrypt data: $e');
    }
  }

  /// Generates a JWT token.
  String generateJwt(
    Map<String, Object?> payload,
    String secret, {
    Duration? expiry,
  }) {
    try {
      final header = {'alg': 'HS256', 'typ': 'JWT'};

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiryTime = now + (expiry?.inSeconds ?? 3600);

      final fullPayload = {...payload, 'iat': now, 'exp': expiryTime};

      final encodedHeader = base64Url.encode(utf8.encode(json.encode(header)));
      final encodedPayload = base64Url.encode(
        utf8.encode(json.encode(fullPayload)),
      );

      final dataToSign = '$encodedHeader.$encodedPayload';
      final signature = _simulateSignature(dataToSign, secret);

      return '$encodedHeader.$encodedPayload.$signature';
    } catch (e) {
      _logger.error('Error generating JWT: $e');
      throw Exception('Failed to generate JWT: $e');
    }
  }

  /// Verifies a JWT token.
  Map<String, Object?>? verifyJwt(String token, String secret) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return null;
      }

      final encodedHeader = parts[0];
      final encodedPayload = parts[1];
      final providedSignature = parts[2];

      final dataToSign = '$encodedHeader.$encodedPayload';
      final expectedSignature = _simulateSignature(dataToSign, secret);

      if (providedSignature != expectedSignature) {
        return null;
      }

      final payloadJson = utf8.decode(
        base64Url.decode(base64Url.normalize(encodedPayload)),
      );
      final payload = json.decode(payloadJson) as Map<String, Object?>;

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final exp = payload['exp'] as int?;

      if (exp != null && exp < now) {
        return null;
      }

      return payload;
    } catch (e) {
      _logger.error('Error verifying JWT: $e');
      return null;
    }
  }

  // Private methods for simulation

  List<int> _simulateAesEncryption(
    List<int> data,
    List<int> key,
    List<int> iv,
  ) {
    // This is a simulation, not actual AES encryption
    final result = List<int>.from(data);

    for (var i = 0; i < result.length; i++) {
      result[i] = result[i] ^ key[i % key.length] ^ iv[i % iv.length];
    }

    return result;
  }

  List<int> _simulateAesDecryption(
    List<int> data,
    List<int> key,
    List<int> iv,
  ) {
    // This is a simulation, not actual AES decryption
    final result = List<int>.from(data);

    for (var i = 0; i < result.length; i++) {
      result[i] = result[i] ^ key[i % key.length] ^ iv[i % iv.length];
    }

    return result;
  }

  String _simulateSignature(String data, String key) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);

    // Simple XOR-based signature
    final result = List<int>.filled(32, 0);

    for (var i = 0; i < dataBytes.length; i++) {
      result[i % 32] =
          result[i % 32] ^ dataBytes[i] ^ keyBytes[i % keyBytes.length];
    }

    return base64Url.encode(result);
  }
}
