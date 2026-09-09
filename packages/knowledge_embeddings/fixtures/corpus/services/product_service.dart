import 'dart:convert';
import 'dart:math';

import '../config/app_config.dart';
import '../models/product.dart';
import '../utils/crypto_utils.dart';
import '../utils/logger.dart';
import 'database_service.dart';

/// Service for managing products.
class ProductService {
  final DatabaseService _db;
  final Logger _logger;
  final CryptoUtils _crypto;
  final ApiConfig _config;

  /// Creates a new product service.
  ProductService(this._db, this._logger, this._crypto, this._config);

  /// Gets all products.
  Future<List<Product>> getAllProducts() async {
    _logger.debug('Getting all products');
    return await _db.listProducts();
  }

  /// Gets a product by ID.
  Future<Product?> getProduct(String id) async {
    _logger.debug('Getting product: $id');
    return await _db.findProductById(id);
  }

  /// Creates a new product.
  Future<Product> createProduct(Product product) async {
    _logger.debug('Creating product: ${product.name}');

    // Generate a unique ID if not provided
    final productWithId = product.id.isEmpty
        ? product.copyWith(id: _generateId())
        : product;

    return await _db.createProduct(productWithId);
  }

  /// Updates a product.
  Future<Product?> updateProduct(Product product) async {
    _logger.debug('Updating product: ${product.id}');
    return await _db.updateProduct(product);
  }

  /// Deletes a product.
  Future<bool> deleteProduct(String id) async {
    _logger.debug('Deleting product: $id');
    await _db.deleteProduct(id);
    return true;
  }

  /// Searches for products by name or description.
  Future<List<Product>> searchProducts(String query) async {
    _logger.debug('Searching products: $query');
    final products = await _db.listProducts();

    final lowercaseQuery = query.toLowerCase();
    return products.where((product) {
      return product.name.toLowerCase().contains(lowercaseQuery) ||
          product.description.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Gets products by category.
  Future<List<Product>> getProductsByCategory(String category) async {
    _logger.debug('Getting products by category: $category');
    final products = await _db.listProducts();

    return products
        .where((product) => product.categories.contains(category))
        .toList();
  }

  /// Gets products by price range.
  Future<List<Product>> getProductsByPriceRange(double min, double max) async {
    _logger.debug('Getting products by price range: $min - $max');
    final products = await _db.listProducts();

    return products.where((product) {
      return product.price >= min && product.price <= max;
    }).toList();
  }

  /// Exports product data as encrypted JSON.
  Future<String> exportProductData() async {
    _logger.debug('Exporting product data');
    final products = await _db.listProducts();

    final data = {
      'timestamp': DateTime.now().toIso8601String(),
      'products': products.map((p) => p.toJson()).toList(),
    };

    final jsonData = json.encode(data);
    final encryptionKey = _config.apiVersion + _generateSalt();

    // Encrypt the data
    final encryptedData = _crypto.encrypt(jsonData, encryptionKey);

    _logger.info('Exported ${products.length} products');
    return encryptedData;
  }

  /// Imports product data from encrypted JSON.
  Future<int> importProductData(
    String encryptedData,
    String encryptionKey,
  ) async {
    _logger.debug('Importing product data');

    try {
      // Decrypt the data
      final jsonData = _crypto.decrypt(encryptedData, encryptionKey);
      final data = json.decode(jsonData) as Map<String, Object?>;

      final products = (data['products'] as List<dynamic>)
          .map((p) => Product.fromJson(p as Map<String, Object?>))
          .toList();

      // Import each product
      for (final product in products) {
        await _db.createProduct(product);
      }

      _logger.info('Imported ${products.length} products');
      return products.length;
    } catch (e) {
      _logger.error('Error importing product data: $e');
      return 0;
    }
  }

  /// Generates a secure hash for a product.
  String generateProductHash(Product product) {
    final productData = json.encode(product.toJson());
    return _crypto.simulateHash(productData);
  }

  /// Verifies a product hash.
  bool verifyProductHash(Product product, String hash) {
    final productData = json.encode(product.toJson());
    final computedHash = _crypto.simulateHash(productData);
    return computedHash == hash;
  }

  /// Generates a unique ID.
  String _generateId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(values).substring(0, 22);
  }

  /// Generates a salt for encryption.
  String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(values).substring(0, 16);
  }
}
