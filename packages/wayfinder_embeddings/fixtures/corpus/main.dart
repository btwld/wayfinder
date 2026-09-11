import 'config/app_config.dart';
import 'models/product.dart';
import 'services/auth_service.dart';
import 'services/data_encryption_service.dart';
import 'services/database_service.dart';
import 'services/product_service.dart';
import 'utils/logger.dart';
import 'utils/service_locator.dart';

/// Main entry point for the application.
Future<void> main() async {
  // Initialize service locator
  ServiceLocator.instance.initialize(environment: Environment.development);

  // Get services
  final logger = ServiceLocator.instance.get<Logger>();
  final db = ServiceLocator.instance.get<DatabaseService>();
  final auth = ServiceLocator.instance.get<AuthService>();
  final productService = ServiceLocator.instance.get<ProductService>();
  final dataEncryption = ServiceLocator.instance.get<DataEncryptionService>();

  logger.info('Starting application');

  // Initialize database
  await db.initialize();

  // Register a user
  const email = 'john.doe@example.com';
  const password = 'Password123!';

  logger.info('Registering user: $email');
  final user = await auth.register(
    email,
    password,
    'John', // firstName
    'Doe', // lastName
  );

  if (user != null) {
    logger.info('User registered successfully: ${user.id}');

    // Login
    logger.info('Logging in user: $email');
    final token = await auth.login(email, password);

    if (token != null) {
      logger.info('User logged in successfully');
      logger.info('Token: $token');

      // Verify token
      logger.info('Verifying token');
      final verifiedUserId = await auth.verifyToken(token);

      if (verifiedUserId != null) {
        logger.info('Token verified successfully: $verifiedUserId');

        // Get user
        logger.info('Getting user: $verifiedUserId');
        final user = await db.findUserById(verifiedUserId);

        if (user != null) {
          logger.info('User retrieved successfully:');
          logger.info('  ID: ${user.id}');
          logger.info('  Email: ${user.email}');
          logger.info('  Full Name: ${user.firstName} ${user.lastName}');
          logger.info('  Role: ${user.role}');
          logger.info('  Created At: ${user.createdAt}');
          logger.info('  Last Login At: ${user.lastLoginAt}');

          // Change password
          logger.info('Changing password');
          const newPassword = 'NewPassword456!';
          final passwordChanged = await auth.changePassword(
            user.id,
            password,
            newPassword,
          );

          if (passwordChanged) {
            logger.info('Password changed successfully');

            // Login with new password
            logger.info('Logging in with new password');
            final newToken = await auth.login(email, newPassword);

            if (newToken != null) {
              logger.info('Login with new password successful');
            } else {
              logger.error('Login with new password failed');
            }
          } else {
            logger.error('Password change failed');
          }
        } else {
          logger.error('User not found');
        }
      } else {
        logger.error('Token verification failed');
      }
    } else {
      logger.error('Login failed');
    }
  } else {
    logger.error('Registration failed');
  }

  // Demonstrate product service and encryption
  logger.info('\nDemonstrating product service and encryption:');

  // Create a product
  final product = Product(
    id: '',
    name: 'Encrypted Notebook',
    description: 'A notebook with encrypted pages',
    price: 29.99,
    stockQuantity: 100,
    categories: ['Office Supplies', 'Stationery'],
    imageUrls: ['https://example.com/notebook.jpg'],
    isActive: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final createdProduct = await productService.createProduct(product);
  logger.info('Product created: ${createdProduct.id}');

  // Generate a product hash
  final productHash = productService.generateProductHash(createdProduct);
  logger.info('Product hash: $productHash');

  // Verify product hash
  final hashValid = productService.verifyProductHash(
    createdProduct,
    productHash,
  );
  logger.info('Product hash valid: $hashValid');

  // Export product data
  final exportedData = await productService.exportProductData();
  logger.info(
    'Exported product data (encrypted): ${exportedData.substring(0, 50)}...',
  );

  // Demonstrate data encryption service
  logger.info('\nDemonstrating data encryption service:');

  // Encrypt sensitive data
  final sensitiveData = {
    'creditCard': '4111111111111111',
    'expiryDate': '12/25',
    'cvv': '123',
    'address': '123 Main St, Anytown, USA',
  };

  final encryptionKey = dataEncryption.generateEncryptionKey();
  logger.info('Generated encryption key: ${encryptionKey.substring(0, 10)}...');

  final encryptedData = dataEncryption.encryptData(
    sensitiveData,
    customKey: encryptionKey,
  );
  logger.info('Encrypted data: ${encryptedData.substring(0, 50)}...');

  // Decrypt sensitive data
  final decryptedData = dataEncryption.decryptData(
    encryptedData,
    customKey: encryptionKey,
  );
  logger.info('Decrypted data: $decryptedData');

  // Hash sensitive data
  final hashedCreditCard = dataEncryption.hashSensitiveData(
    sensitiveData['creditCard']!,
  );
  logger.info('Hashed credit card: ${hashedCreditCard.substring(0, 20)}...');

  logger.info('Application completed');
}
