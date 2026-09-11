import 'product.dart';
import 'user.dart';

/// Order model representing a customer purchase in the e-commerce system.
class Order {
  final String id;
  final String userId;
  final List<OrderItem> items;
  final double subtotal;
  final double tax;
  final double shippingCost;
  final double total;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final String? transactionId;
  final Address shippingAddress;
  final Address? billingAddress;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Creates a new order.
  Order({
    required this.id,
    required this.userId,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.shippingCost,
    required this.total,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    this.transactionId,
    required this.shippingAddress,
    this.billingAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates an order from JSON data.
  factory Order.fromJson(Map<String, Object?> json) {
    return Order(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      items: (json['items'] as List<dynamic>)
          .map((item) => OrderItem.fromJson(item as Map<String, Object?>))
          .toList(),
      subtotal: (json['subtotal'] as num).toDouble(),
      tax: (json['tax'] as num).toDouble(),
      shippingCost: (json['shipping_cost'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      status: OrderStatus.values.firstWhere(
        (status) =>
            status.toString() == 'OrderStatus.${json['status'] as String}',
      ),
      paymentStatus: PaymentStatus.values.firstWhere(
        (status) =>
            status.toString() ==
            'PaymentStatus.${json['payment_status'] as String}',
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (method) =>
            method.toString() ==
            'PaymentMethod.${json['payment_method'] as String}',
      ),
      transactionId: json['transaction_id'] as String?,
      shippingAddress: Address.fromJson(
        json['shipping_address'] as Map<String, Object?>,
      ),
      billingAddress: json['billing_address'] != null
          ? Address.fromJson(json['billing_address'] as Map<String, Object?>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Converts the order to JSON.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'tax': tax,
      'shipping_cost': shippingCost,
      'total': total,
      'status': status.toString().split('.').last,
      'payment_status': paymentStatus.toString().split('.').last,
      'payment_method': paymentMethod.toString().split('.').last,
      'transaction_id': transactionId,
      'shipping_address': shippingAddress.toJson(),
      'billing_address': billingAddress?.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Creates a copy of this order with the specified fields updated.
  Order copyWith({
    String? id,
    String? userId,
    List<OrderItem>? items,
    double? subtotal,
    double? tax,
    double? shippingCost,
    double? total,
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    PaymentMethod? paymentMethod,
    String? transactionId,
    Address? shippingAddress,
    Address? billingAddress,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Order(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      shippingCost: shippingCost ?? this.shippingCost,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      transactionId: transactionId ?? this.transactionId,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      billingAddress: billingAddress ?? this.billingAddress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Updates the order status.
  Order updateStatus(OrderStatus newStatus) {
    return copyWith(status: newStatus, updatedAt: DateTime.now());
  }

  /// Updates the payment status.
  Order updatePaymentStatus(PaymentStatus newStatus, {String? transactionId}) {
    return copyWith(
      paymentStatus: newStatus,
      transactionId: transactionId ?? this.transactionId,
      updatedAt: DateTime.now(),
    );
  }

  /// Calculates the total number of items in the order.
  int get totalItems {
    return items.fold(0, (sum, item) => sum + item.quantity);
  }
}

/// Represents an item in an order.
class OrderItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final double total;

  /// Creates a new order item.
  OrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.total,
  });

  /// Creates an order item from JSON data.
  factory OrderItem.fromJson(Map<String, Object?> json) {
    return OrderItem(
      productId: json['product_id'] as String,
      productName: json['product_name'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
      total: (json['total'] as num).toDouble(),
    );
  }

  /// Converts the order item to JSON.
  Map<String, Object?> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'quantity': quantity,
      'total': total,
    };
  }

  /// Creates an order item from a product.
  factory OrderItem.fromProduct(Product product, int quantity) {
    return OrderItem(
      productId: product.id,
      productName: product.name,
      price: product.price,
      quantity: quantity,
      total: product.price * quantity,
    );
  }
}

/// Represents the status of an order.
enum OrderStatus {
  pending,
  processing,
  shipped,
  delivered,
  cancelled,
  returned,
}

/// Represents the payment status of an order.
enum PaymentStatus { pending, authorized, paid, refunded, failed }

/// Represents the payment method used for an order.
enum PaymentMethod { creditCard, paypal, bankTransfer, applePay, googlePay }
