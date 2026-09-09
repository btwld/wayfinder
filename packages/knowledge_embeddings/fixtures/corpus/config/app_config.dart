/// Configuration for the application.
class AppConfig {
  /// The environment the application is running in.
  final Environment environment;

  /// The database configuration.
  final DatabaseConfig database;

  /// The authentication configuration.
  final AuthConfig auth;

  /// The API configuration.
  final ApiConfig api;

  /// The payment gateway configuration.
  final PaymentConfig payment;

  /// Creates a new application configuration.
  AppConfig({
    required this.environment,
    required this.database,
    required this.auth,
    required this.api,
    required this.payment,
  });

  /// Creates a development configuration.
  factory AppConfig.development() {
    return AppConfig(
      environment: Environment.development,
      database: DatabaseConfig(
        host: 'localhost',
        port: 5432,
        username: 'dev_user',
        password: 'dev_password',
        database: 'ecommerce_dev',
        enableSsl: false,
        connectionPoolSize: 5,
      ),
      auth: AuthConfig(
        jwtSecret: 'dev_secret_key',
        tokenExpiryInHours: 24,
        refreshTokenExpiryInDays: 7,
        passwordMinLength: 8,
        passwordRequireUppercase: true,
        passwordRequireLowercase: true,
        passwordRequireNumbers: true,
        passwordRequireSpecialChars: true,
      ),
      api: ApiConfig(
        baseUrl: 'http://localhost:8080',
        apiVersion: 'v1',
        enableCors: true,
        rateLimitPerMinute: 100,
      ),
      payment: PaymentConfig(
        stripeApiKey: 'sk_test_example',
        stripePublishableKey: 'pk_test_example',
        paypalClientId: 'test_client_id',
        paypalClientSecret: 'test_client_secret',
        enableTestMode: true,
      ),
    );
  }

  /// Creates a production configuration.
  factory AppConfig.production() {
    return AppConfig(
      environment: Environment.production,
      database: DatabaseConfig(
        host: 'db.example.com',
        port: 5432,
        username: 'prod_user',
        password: 'prod_password',
        database: 'ecommerce_prod',
        enableSsl: true,
        connectionPoolSize: 20,
      ),
      auth: AuthConfig(
        jwtSecret: 'prod_secret_key',
        tokenExpiryInHours: 12,
        refreshTokenExpiryInDays: 30,
        passwordMinLength: 10,
        passwordRequireUppercase: true,
        passwordRequireLowercase: true,
        passwordRequireNumbers: true,
        passwordRequireSpecialChars: true,
      ),
      api: ApiConfig(
        baseUrl: 'https://api.example.com',
        apiVersion: 'v1',
        enableCors: false,
        rateLimitPerMinute: 60,
      ),
      payment: PaymentConfig(
        stripeApiKey: 'sk_live_example',
        stripePublishableKey: 'pk_live_example',
        paypalClientId: 'live_client_id',
        paypalClientSecret: 'live_client_secret',
        enableTestMode: false,
      ),
    );
  }

  /// Creates a test configuration.
  factory AppConfig.test() {
    return AppConfig(
      environment: Environment.test,
      database: DatabaseConfig(
        host: 'localhost',
        port: 5432,
        username: 'test_user',
        password: 'test_password',
        database: 'ecommerce_test',
        enableSsl: false,
        connectionPoolSize: 2,
      ),
      auth: AuthConfig(
        jwtSecret: 'test_secret_key',
        tokenExpiryInHours: 1,
        refreshTokenExpiryInDays: 1,
        passwordMinLength: 8,
        passwordRequireUppercase: true,
        passwordRequireLowercase: true,
        passwordRequireNumbers: true,
        passwordRequireSpecialChars: true,
      ),
      api: ApiConfig(
        baseUrl: 'http://localhost:8080',
        apiVersion: 'v1',
        enableCors: true,
        rateLimitPerMinute: 1000,
      ),
      payment: PaymentConfig(
        stripeApiKey: 'sk_test_example',
        stripePublishableKey: 'pk_test_example',
        paypalClientId: 'test_client_id',
        paypalClientSecret: 'test_client_secret',
        enableTestMode: true,
      ),
    );
  }

  /// Returns whether the application is running in development mode.
  bool get isDevelopment => environment == Environment.development;

  /// Returns whether the application is running in production mode.
  bool get isProduction => environment == Environment.production;

  /// Returns whether the application is running in test mode.
  bool get isTest => environment == Environment.test;
}

/// The environment the application is running in.
enum Environment {
  /// Development environment.
  development,

  /// Production environment.
  production,

  /// Test environment.
  test,
}

/// Configuration for the database.
class DatabaseConfig {
  /// The database host.
  final String host;

  /// The database port.
  final int port;

  /// The database username.
  final String username;

  /// The database password.
  final String password;

  /// The database name.
  final String database;

  /// Whether to enable SSL for database connections.
  final bool enableSsl;

  /// The number of connections to maintain in the connection pool.
  final int connectionPoolSize;

  /// Creates a new database configuration.
  DatabaseConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.database,
    required this.enableSsl,
    required this.connectionPoolSize,
  });

  /// Returns the database connection string.
  String get connectionString {
    final sslParam = enableSsl ? '?sslmode=require' : '';
    return 'postgresql://$username:$password@$host:$port/$database$sslParam';
  }
}

/// Configuration for authentication.
class AuthConfig {
  /// The secret key used to sign JWT tokens.
  final String jwtSecret;

  /// The number of hours until a token expires.
  final int tokenExpiryInHours;

  /// The number of days until a refresh token expires.
  final int refreshTokenExpiryInDays;

  /// The minimum length for passwords.
  final int passwordMinLength;

  /// Whether passwords require uppercase letters.
  final bool passwordRequireUppercase;

  /// Whether passwords require lowercase letters.
  final bool passwordRequireLowercase;

  /// Whether passwords require numbers.
  final bool passwordRequireNumbers;

  /// Whether passwords require special characters.
  final bool passwordRequireSpecialChars;

  /// Creates a new authentication configuration.
  AuthConfig({
    required this.jwtSecret,
    required this.tokenExpiryInHours,
    required this.refreshTokenExpiryInDays,
    required this.passwordMinLength,
    required this.passwordRequireUppercase,
    required this.passwordRequireLowercase,
    required this.passwordRequireNumbers,
    required this.passwordRequireSpecialChars,
  });

  /// Returns the token expiry duration.
  Duration get tokenExpiry => Duration(hours: tokenExpiryInHours);

  /// Returns the refresh token expiry duration.
  Duration get refreshTokenExpiry => Duration(days: refreshTokenExpiryInDays);
}

/// Configuration for the API.
class ApiConfig {
  /// The base URL for the API.
  final String baseUrl;

  /// The API version.
  final String apiVersion;

  /// Whether to enable CORS.
  final bool enableCors;

  /// The number of requests allowed per minute.
  final int rateLimitPerMinute;

  /// Creates a new API configuration.
  ApiConfig({
    required this.baseUrl,
    required this.apiVersion,
    required this.enableCors,
    required this.rateLimitPerMinute,
  });

  /// Returns the full API URL.
  String get apiUrl => '$baseUrl/$apiVersion';
}

/// Configuration for payment gateways.
class PaymentConfig {
  /// The Stripe API key.
  final String stripeApiKey;

  /// The Stripe publishable key.
  final String stripePublishableKey;

  /// The PayPal client ID.
  final String paypalClientId;

  /// The PayPal client secret.
  final String paypalClientSecret;

  /// Whether to enable test mode for payments.
  final bool enableTestMode;

  /// Creates a new payment configuration.
  PaymentConfig({
    required this.stripeApiKey,
    required this.stripePublishableKey,
    required this.paypalClientId,
    required this.paypalClientSecret,
    required this.enableTestMode,
  });
}
