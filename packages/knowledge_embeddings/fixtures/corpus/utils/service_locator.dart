import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/data_encryption_service.dart';
import '../services/database_service.dart';
import '../services/product_service.dart';
import 'crypto_utils.dart';
import 'logger.dart';

/// Service locator for dependency injection.
class ServiceLocator {
  final Map<Type, dynamic> _services = {};

  /// The singleton instance of the service locator.
  static final ServiceLocator instance = ServiceLocator._();

  /// Creates a new service locator.
  ServiceLocator._();

  /// Initializes the service locator with the given environment.
  void initialize({Environment environment = Environment.development}) {
    // Create configuration
    final config = _createConfig(environment);
    register<AppConfig>(config);

    // Create utilities
    final logger = Logger(level: LogLevel.debug);
    register<Logger>(logger);

    final crypto = CryptoUtils(logger);
    register<CryptoUtils>(crypto);

    // Create services
    final db = DatabaseService(logger, config.database);
    register<DatabaseService>(db);

    final auth = AuthService(db, logger, crypto, config.auth);
    register<AuthService>(auth);

    final productService = ProductService(db, logger, crypto, config.api);
    register<ProductService>(productService);

    final dataEncryptionService = DataEncryptionService(
      logger,
      crypto,
      config.auth,
    );
    register<DataEncryptionService>(dataEncryptionService);

    logger.info('Service locator initialized for environment: $environment');
  }

  /// Creates a configuration for the given environment.
  AppConfig _createConfig(Environment environment) {
    switch (environment) {
      case Environment.development:
        return AppConfig.development();
      case Environment.production:
        return AppConfig.production();
      case Environment.test:
        return AppConfig.test();
    }
  }

  /// Registers a service with the service locator.
  void register<T>(T service) {
    _services[T] = service;
  }

  /// Gets a service from the service locator.
  T get<T>() {
    final service = _services[T];
    if (service == null) {
      throw Exception('Service not found: $T');
    }
    return service as T;
  }

  /// Checks if a service is registered with the service locator.
  bool isRegistered<T>() {
    return _services.containsKey(T);
  }

  /// Resets the service locator.
  void reset() {
    _services.clear();
  }
}
