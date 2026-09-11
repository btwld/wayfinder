import '../config/app_config.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/user.dart';
import '../utils/logger.dart';

/// Service for interacting with the database.
class DatabaseService {
  final Logger _logger;
  final DatabaseConfig _config;

  // In-memory database for this example
  final Map<String, User> _users = {};
  final Map<String, Product> _products = {};
  final Map<String, Order> _orders = {};

  /// Creates a new database service.
  DatabaseService(this._logger, this._config);

  /// Initializes the database with sample data.
  Future<void> initialize() async {
    _logger.info(
      'Initializing database with connection string: ${_config.connectionString}',
    );
    _logger.info('Initializing database with sample data');

    // Add sample users
    final user1 = User(
      id: 'user1',
      email: 'john@example.com',
      passwordHash:
          'hash:value', // In a real app, this would be properly hashed
      firstName: 'John',
      lastName: 'Doe',
      role: UserRole.customer,
      createdAt: DateTime.now(),
      isActive: true,
    );

    final user2 = User(
      id: 'user2',
      email: 'admin@example.com',
      passwordHash:
          'hash:value', // In a real app, this would be properly hashed
      firstName: 'Admin',
      lastName: 'User',
      role: UserRole.admin,
      createdAt: DateTime.now(),
      isActive: true,
    );

    _users[user1.id] = user1;
    _users[user2.id] = user2;

    // Add sample products
    final product1 = Product(
      id: 'product1',
      name: 'Smartphone',
      description: 'Latest smartphone with amazing features',
      price: 999.99,
      stockQuantity: 50,
      categories: ['Electronics', 'Phones'],
      imageUrls: ['https://example.com/smartphone.jpg'],
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final product2 = Product(
      id: 'product2',
      name: 'Laptop',
      description: 'Powerful laptop for work and gaming',
      price: 1499.99,
      stockQuantity: 30,
      categories: ['Electronics', 'Computers'],
      imageUrls: ['https://example.com/laptop.jpg'],
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _products[product1.id] = product1;
    _products[product2.id] = product2;

    // Add sample orders
    final order1 = Order(
      id: 'order1',
      userId: user1.id,
      items: [
        OrderItem(
          productId: product1.id,
          productName: product1.name,
          price: product1.price,
          quantity: 1,
          total: product1.price,
        ),
      ],
      subtotal: product1.price,
      tax: product1.price * 0.1,
      shippingCost: 10.0,
      total: product1.price + (product1.price * 0.1) + 10.0,
      status: OrderStatus.delivered,
      paymentStatus: PaymentStatus.paid,
      paymentMethod: PaymentMethod.creditCard,
      transactionId: 'txn123',
      shippingAddress: Address(
        street: '123 Main St',
        city: 'Anytown',
        state: 'CA',
        postalCode: '12345',
        country: 'USA',
      ),
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
      updatedAt: DateTime.now().subtract(const Duration(days: 5)),
    );

    _orders[order1.id] = order1;

    _logger.info(
      'Database initialized with ${_users.length} users, ${_products.length} products, and ${_orders.length} orders',
    );
  }

  // User methods

  /// Finds a user by ID.
  Future<User?> findUserById(String id) async {
    _logger.debug('Finding user by ID: $id');
    return _users[id];
  }

  /// Finds a user by email.
  Future<User?> findUserByEmail(String email) async {
    _logger.debug('Finding user by email: $email');
    try {
      return _users.values.firstWhere((user) => user.email == email);
    } catch (e) {
      return null;
    }
  }

  /// Creates a new user.
  Future<User> createUser(User user) async {
    _logger.debug('Creating user: ${user.id}');
    _users[user.id] = user;
    return user;
  }

  /// Updates an existing user.
  Future<User> updateUser(User user) async {
    _logger.debug('Updating user: ${user.id}');
    _users[user.id] = user;
    return user;
  }

  /// Deletes a user.
  Future<void> deleteUser(String id) async {
    _logger.debug('Deleting user: $id');
    _users.remove(id);
  }

  /// Lists all users.
  Future<List<User>> listUsers() async {
    _logger.debug('Listing all users');
    return _users.values.toList();
  }

  // Product methods

  /// Finds a product by ID.
  Future<Product?> findProductById(String id) async {
    _logger.debug('Finding product by ID: $id');
    return _products[id];
  }

  /// Creates a new product.
  Future<Product> createProduct(Product product) async {
    _logger.debug('Creating product: ${product.id}');
    _products[product.id] = product;
    return product;
  }

  /// Updates an existing product.
  Future<Product> updateProduct(Product product) async {
    _logger.debug('Updating product: ${product.id}');
    _products[product.id] = product;
    return product;
  }

  /// Deletes a product.
  Future<void> deleteProduct(String id) async {
    _logger.debug('Deleting product: $id');
    _products.remove(id);
  }

  /// Lists all products.
  Future<List<Product>> listProducts() async {
    _logger.debug('Listing all products');
    return _products.values.toList();
  }

  /// Searches for products by name or description.
  Future<List<Product>> searchProducts(String query) async {
    _logger.debug('Searching products: $query');
    final lowercaseQuery = query.toLowerCase();
    return _products.values.where((product) {
      return product.name.toLowerCase().contains(lowercaseQuery) ||
          product.description.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Filters products by category.
  Future<List<Product>> filterProductsByCategory(String category) async {
    _logger.debug('Filtering products by category: $category');
    return _products.values.where((product) {
      return product.categories.contains(category);
    }).toList();
  }

  // Order methods

  /// Finds an order by ID.
  Future<Order?> findOrderById(String id) async {
    _logger.debug('Finding order by ID: $id');
    return _orders[id];
  }

  /// Creates a new order.
  Future<Order> createOrder(Order order) async {
    _logger.debug('Creating order: ${order.id}');
    _orders[order.id] = order;
    return order;
  }

  /// Updates an existing order.
  Future<Order> updateOrder(Order order) async {
    _logger.debug('Updating order: ${order.id}');
    _orders[order.id] = order;
    return order;
  }

  /// Deletes an order.
  Future<void> deleteOrder(String id) async {
    _logger.debug('Deleting order: $id');
    _orders.remove(id);
  }

  /// Lists all orders.
  Future<List<Order>> listOrders() async {
    _logger.debug('Listing all orders');
    return _orders.values.toList();
  }

  /// Finds orders by user ID.
  Future<List<Order>> findOrdersByUserId(String userId) async {
    _logger.debug('Finding orders by user ID: $userId');
    return _orders.values.where((order) => order.userId == userId).toList();
  }
}
