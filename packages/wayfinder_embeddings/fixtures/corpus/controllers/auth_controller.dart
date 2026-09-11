import '../services/auth_service.dart';
import '../utils/logger.dart';

/// Controller for handling authentication requests.
class AuthController {
  final AuthService _authService;
  final Logger _logger;

  /// Creates a new authentication controller.
  AuthController(this._authService, this._logger);

  /// Handles a login request.
  Future<Map<String, Object?>> login(Map<String, Object?> request) async {
    try {
      _logger.info('Handling login request');

      // Validate request
      if (!request.containsKey('email') || !request.containsKey('password')) {
        return {'success': false, 'message': 'Email and password are required'};
      }

      final email = request['email'] as String;
      final password = request['password'] as String;

      // Authenticate user
      final token = await _authService.login(email, password);

      if (token == null) {
        return {'success': false, 'message': 'Invalid email or password'};
      }

      return {'success': true, 'token': token};
    } catch (e) {
      _logger.error('Error handling login request: $e');
      return {'success': false, 'message': 'An error occurred during login'};
    }
  }

  /// Handles a registration request.
  Future<Map<String, Object?>> register(Map<String, Object?> request) async {
    try {
      _logger.info('Handling registration request');

      // Validate request
      if (!request.containsKey('email') ||
          !request.containsKey('password') ||
          !request.containsKey('firstName') ||
          !request.containsKey('lastName')) {
        return {
          'success': false,
          'message': 'Email, password, firstName, and lastName are required',
        };
      }

      final email = request['email'] as String;
      final password = request['password'] as String;
      final firstName = request['firstName'] as String;
      final lastName = request['lastName'] as String;

      // Register user
      final user = await _authService.register(
        email,
        password,
        firstName,
        lastName,
      );

      if (user == null) {
        return {
          'success': false,
          'message': 'Registration failed. Email may already be in use.',
        };
      }

      return {'success': true, 'message': 'Registration successful'};
    } catch (e) {
      _logger.error('Error handling registration request: $e');
      return {
        'success': false,
        'message': 'An error occurred during registration',
      };
    }
  }

  /// Handles a logout request.
  Future<Map<String, Object?>> logout(Map<String, Object?> request) async {
    try {
      _logger.info('Handling logout request');

      // Validate request
      if (!request.containsKey('token')) {
        return {'success': false, 'message': 'Token is required'};
      }

      final token = request['token'] as String;

      // Logout user
      final success = await _authService.logout(token);

      if (!success) {
        return {'success': false, 'message': 'Logout failed'};
      }

      return {'success': true, 'message': 'Logout successful'};
    } catch (e) {
      _logger.error('Error handling logout request: $e');
      return {'success': false, 'message': 'An error occurred during logout'};
    }
  }

  /// Handles a password reset request.
  Future<Map<String, Object?>> resetPassword(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling password reset request');

      // Validate request
      if (!request.containsKey('email')) {
        return {'success': false, 'message': 'Email is required'};
      }

      final email = request['email'] as String;

      // Reset password
      final success = await _authService.resetPassword(email);

      if (!success) {
        return {'success': false, 'message': 'Password reset failed'};
      }

      return {'success': true, 'message': 'Password reset email sent'};
    } catch (e) {
      _logger.error('Error handling password reset request: $e');
      return {
        'success': false,
        'message': 'An error occurred during password reset',
      };
    }
  }

  /// Handles a password change request.
  Future<Map<String, Object?>> changePassword(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling password change request');

      // Validate request
      if (!request.containsKey('userId') ||
          !request.containsKey('currentPassword') ||
          !request.containsKey('newPassword')) {
        return {
          'success': false,
          'message': 'UserId, currentPassword, and newPassword are required',
        };
      }

      final userId = request['userId'] as String;
      final currentPassword = request['currentPassword'] as String;
      final newPassword = request['newPassword'] as String;

      // Change password
      final success = await _authService.changePassword(
        userId,
        currentPassword,
        newPassword,
      );

      if (!success) {
        return {'success': false, 'message': 'Password change failed'};
      }

      return {'success': true, 'message': 'Password changed successfully'};
    } catch (e) {
      _logger.error('Error handling password change request: $e');
      return {
        'success': false,
        'message': 'An error occurred during password change',
      };
    }
  }

  /// Handles a token verification request.
  Future<Map<String, Object?>> verifyToken(Map<String, Object?> request) async {
    try {
      _logger.info('Handling token verification request');

      // Validate request
      if (!request.containsKey('token')) {
        return {'success': false, 'message': 'Token is required'};
      }

      final token = request['token'] as String;

      // Verify token
      final userId = await _authService.verifyToken(token);

      if (userId == null) {
        return {'success': false, 'message': 'Invalid or expired token'};
      }

      return {'success': true, 'userId': userId};
    } catch (e) {
      _logger.error('Error handling token verification request: $e');
      return {
        'success': false,
        'message': 'An error occurred during token verification',
      };
    }
  }
}
