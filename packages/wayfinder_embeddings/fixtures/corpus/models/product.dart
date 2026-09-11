/// Product model representing an item for sale in the e-commerce system.
class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final int stockQuantity;
  final List<String> categories;
  final List<String> imageUrls;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Creates a new product.
  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.stockQuantity,
    required this.categories,
    required this.imageUrls,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a product from JSON data.
  factory Product.fromJson(Map<String, Object?> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      stockQuantity: json['stock_quantity'] as int,
      categories: List<String>.from(json['categories'] as List<dynamic>),
      imageUrls: List<String>.from(json['image_urls'] as List<dynamic>),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Converts the product to JSON.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'stock_quantity': stockQuantity,
      'categories': categories,
      'image_urls': imageUrls,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Checks if the product is in stock.
  bool get isInStock => stockQuantity > 0;

  /// Checks if the product is on sale.
  bool get isOnSale => false; // Placeholder for sale logic

  /// Creates a copy of this product with the specified fields updated.
  Product copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    int? stockQuantity,
    List<String>? categories,
    List<String>? imageUrls,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      categories: categories ?? this.categories,
      imageUrls: imageUrls ?? this.imageUrls,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Updates the stock quantity after a purchase.
  Product updateStockAfterPurchase(int quantityPurchased) {
    if (quantityPurchased <= 0) {
      throw ArgumentError('Quantity purchased must be positive');
    }

    if (quantityPurchased > stockQuantity) {
      throw ArgumentError('Not enough stock available');
    }

    return copyWith(
      stockQuantity: stockQuantity - quantityPurchased,
      updatedAt: DateTime.now(),
    );
  }
}
