import '../models/product.dart';
import '../services/database_service.dart';
import '../utils/logger.dart';

/// Controller for handling product requests.
class ProductController {
  final DatabaseService _db;
  final Logger _logger;

  /// Creates a new product controller.
  ProductController(this._db, this._logger);

  /// Handles a request to get all products.
  Future<Map<String, Object?>> getAllProducts() async {
    try {
      _logger.info('Handling get all products request');

      final products = await _db.listProducts();

      return {
        'success': true,
        'products': products.map((p) => p.toJson()).toList(),
      };
    } catch (e) {
      _logger.error('Error handling get all products request: $e');
      return {
        'success': false,
        'message': 'An error occurred while fetching products',
      };
    }
  }

  /// Handles a request to get a product by ID.
  Future<Map<String, Object?>> getProductById(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling get product by ID request');

      // Validate request
      if (!request.containsKey('id')) {
        return {'success': false, 'message': 'Product ID is required'};
      }

      final id = request['id'] as String;

      // Get product
      final product = await _db.findProductById(id);

      if (product == null) {
        return {'success': false, 'message': 'Product not found'};
      }

      return {'success': true, 'product': product.toJson()};
    } catch (e) {
      _logger.error('Error handling get product by ID request: $e');
      return {
        'success': false,
        'message': 'An error occurred while fetching the product',
      };
    }
  }

  /// Handles a request to search for products.
  Future<Map<String, Object?>> searchProducts(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling search products request');

      // Validate request
      if (!request.containsKey('query')) {
        return {'success': false, 'message': 'Search query is required'};
      }

      final query = request['query'] as String;

      // Search products
      final products = await _db.searchProducts(query);

      return {
        'success': true,
        'products': products.map((p) => p.toJson()).toList(),
      };
    } catch (e) {
      _logger.error('Error handling search products request: $e');
      return {
        'success': false,
        'message': 'An error occurred while searching for products',
      };
    }
  }

  /// Handles a request to filter products by category.
  Future<Map<String, Object?>> filterProductsByCategory(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling filter products by category request');

      // Validate request
      if (!request.containsKey('category')) {
        return {'success': false, 'message': 'Category is required'};
      }

      final category = request['category'] as String;

      // Filter products
      final products = await _db.filterProductsByCategory(category);

      return {
        'success': true,
        'products': products.map((p) => p.toJson()).toList(),
      };
    } catch (e) {
      _logger.error('Error handling filter products by category request: $e');
      return {
        'success': false,
        'message': 'An error occurred while filtering products',
      };
    }
  }

  /// Handles a request to create a product.
  Future<Map<String, Object?>> createProduct(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling create product request');

      // Validate request
      if (!_validateProductRequest(request)) {
        return {'success': false, 'message': 'Invalid product data'};
      }

      // Create product
      final product = Product(
        id: request['id'] as String,
        name: request['name'] as String,
        description: request['description'] as String,
        price: (request['price'] as num).toDouble(),
        stockQuantity: request['stockQuantity'] as int,
        categories: List<String>.from(request['categories'] as List<dynamic>),
        imageUrls: List<String>.from(request['imageUrls'] as List<dynamic>),
        isActive: request['isActive'] as bool? ?? true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _db.createProduct(product);

      return {'success': true, 'product': product.toJson()};
    } catch (e) {
      _logger.error('Error handling create product request: $e');
      return {
        'success': false,
        'message': 'An error occurred while creating the product',
      };
    }
  }

  /// Handles a request to update a product.
  Future<Map<String, Object?>> updateProduct(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling update product request');

      // Validate request
      if (!request.containsKey('id')) {
        return {'success': false, 'message': 'Product ID is required'};
      }

      final id = request['id'] as String;

      // Get existing product
      final existingProduct = await _db.findProductById(id);

      if (existingProduct == null) {
        return {'success': false, 'message': 'Product not found'};
      }

      // Update product
      final updatedProduct = existingProduct.copyWith(
        name: request['name'] as String?,
        description: request['description'] as String?,
        price: request['price'] != null
            ? (request['price'] as num).toDouble()
            : null,
        stockQuantity: request['stockQuantity'] as int?,
        categories: request['categories'] != null
            ? List<String>.from(request['categories'] as List<dynamic>)
            : null,
        imageUrls: request['imageUrls'] != null
            ? List<String>.from(request['imageUrls'] as List<dynamic>)
            : null,
        isActive: request['isActive'] as bool?,
        updatedAt: DateTime.now(),
      );

      await _db.updateProduct(updatedProduct);

      return {'success': true, 'product': updatedProduct.toJson()};
    } catch (e) {
      _logger.error('Error handling update product request: $e');
      return {
        'success': false,
        'message': 'An error occurred while updating the product',
      };
    }
  }

  /// Handles a request to delete a product.
  Future<Map<String, Object?>> deleteProduct(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling delete product request');

      // Validate request
      if (!request.containsKey('id')) {
        return {'success': false, 'message': 'Product ID is required'};
      }

      final id = request['id'] as String;

      // Check if product exists
      final product = await _db.findProductById(id);

      if (product == null) {
        return {'success': false, 'message': 'Product not found'};
      }

      // Delete product
      await _db.deleteProduct(id);

      return {'success': true, 'message': 'Product deleted successfully'};
    } catch (e) {
      _logger.error('Error handling delete product request: $e');
      return {
        'success': false,
        'message': 'An error occurred while deleting the product',
      };
    }
  }

  /// Validates a product request.
  bool _validateProductRequest(Map<String, Object?> request) {
    // Check required fields
    if (!request.containsKey('id') ||
        !request.containsKey('name') ||
        !request.containsKey('description') ||
        !request.containsKey('price') ||
        !request.containsKey('stockQuantity') ||
        !request.containsKey('categories') ||
        !request.containsKey('imageUrls')) {
      return false;
    }

    // Validate price
    final price = request['price'];
    if (price is! num || price <= 0) {
      return false;
    }

    // Validate stock quantity
    final stockQuantity = request['stockQuantity'];
    if (stockQuantity is! int || stockQuantity < 0) {
      return false;
    }

    // Validate categories
    final categories = request['categories'];
    if (categories is! List) {
      return false;
    }

    // Validate image URLs
    final imageUrls = request['imageUrls'];
    if (imageUrls is! List) {
      return false;
    }

    return true;
  }
}
