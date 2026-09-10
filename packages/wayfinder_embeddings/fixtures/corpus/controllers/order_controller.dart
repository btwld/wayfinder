import '../models/order.dart';
import '../models/user.dart';
import '../services/database_service.dart';
import '../services/payment_service.dart';
import '../utils/logger.dart';

/// Controller for handling order requests.
class OrderController {
  final DatabaseService _db;
  final PaymentService _paymentService;
  final Logger _logger;

  /// Creates a new order controller.
  OrderController(this._db, this._paymentService, this._logger);

  /// Handles a request to create an order.
  Future<Map<String, Object?>> createOrder(Map<String, Object?> request) async {
    try {
      _logger.info('Handling create order request');

      // Validate request
      if (!_validateCreateOrderRequest(request)) {
        return {'success': false, 'message': 'Invalid order data'};
      }

      final userId = request['userId'] as String;
      final items = (request['items'] as List<dynamic>)
          .map((item) => item as Map<String, Object?>)
          .toList();
      final shippingAddress =
          request['shippingAddress'] as Map<String, Object?>;
      final billingAddress = request['billingAddress'] as Map<String, Object?>?;
      final paymentMethod = _parsePaymentMethod(
        request['paymentMethod'] as String,
      );
      final paymentDetails = request['paymentDetails'] as Map<String, Object?>;

      // Check if user exists
      final user = await _db.findUserById(userId);
      if (user == null) {
        return {'success': false, 'message': 'User not found'};
      }

      // Check if products exist and have sufficient stock
      final orderItems = <OrderItem>[];
      double subtotal = 0;

      for (final item in items) {
        final productId = item['productId'] as String;
        final quantity = item['quantity'] as int;

        final product = await _db.findProductById(productId);
        if (product == null) {
          return {'success': false, 'message': 'Product not found: $productId'};
        }

        if (product.stockQuantity < quantity) {
          return {
            'success': false,
            'message': 'Insufficient stock for product: ${product.name}',
          };
        }

        final orderItem = OrderItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: quantity,
          total: product.price * quantity,
        );

        orderItems.add(orderItem);
        subtotal += orderItem.total;
      }

      // Calculate tax and shipping
      final tax = subtotal * 0.1; // 10% tax
      const shippingCost = 10.0; // Flat shipping rate
      final total = subtotal + tax + shippingCost;

      // Create order
      final order = Order(
        id: _generateOrderId(),
        userId: userId,
        items: orderItems,
        subtotal: subtotal,
        tax: tax,
        shippingCost: shippingCost,
        total: total,
        status: OrderStatus.pending,
        paymentStatus: PaymentStatus.pending,
        paymentMethod: paymentMethod,
        shippingAddress: Address.fromJson(shippingAddress),
        billingAddress: billingAddress != null
            ? Address.fromJson(billingAddress)
            : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Process payment
      final transactionId = await _paymentService.processPayment(
        order,
        paymentMethod,
        paymentDetails,
      );

      if (transactionId == null) {
        return {'success': false, 'message': 'Payment processing failed'};
      }

      // Update order with transaction ID and payment status
      final updatedOrder = order.copyWith(
        transactionId: transactionId,
        paymentStatus: PaymentStatus.paid,
        status: OrderStatus.processing,
      );

      // Save order
      await _db.createOrder(updatedOrder);

      // Update product stock
      for (final item in orderItems) {
        final product = await _db.findProductById(item.productId);
        if (product != null) {
          final updatedProduct = product.updateStockAfterPurchase(
            item.quantity,
          );
          await _db.updateProduct(updatedProduct);
        }
      }

      return {'success': true, 'order': updatedOrder.toJson()};
    } catch (e) {
      _logger.error('Error handling create order request: $e');
      return {
        'success': false,
        'message': 'An error occurred while creating the order',
      };
    }
  }

  /// Handles a request to get an order by ID.
  Future<Map<String, Object?>> getOrderById(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling get order by ID request');

      // Validate request
      if (!request.containsKey('id')) {
        return {'success': false, 'message': 'Order ID is required'};
      }

      final id = request['id'] as String;

      // Get order
      final order = await _db.findOrderById(id);

      if (order == null) {
        return {'success': false, 'message': 'Order not found'};
      }

      return {'success': true, 'order': order.toJson()};
    } catch (e) {
      _logger.error('Error handling get order by ID request: $e');
      return {
        'success': false,
        'message': 'An error occurred while fetching the order',
      };
    }
  }

  /// Handles a request to get orders by user ID.
  Future<Map<String, Object?>> getOrdersByUserId(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling get orders by user ID request');

      // Validate request
      if (!request.containsKey('userId')) {
        return {'success': false, 'message': 'User ID is required'};
      }

      final userId = request['userId'] as String;

      // Get orders
      final orders = await _db.findOrdersByUserId(userId);

      return {
        'success': true,
        'orders': orders.map((o) => o.toJson()).toList(),
      };
    } catch (e) {
      _logger.error('Error handling get orders by user ID request: $e');
      return {
        'success': false,
        'message': 'An error occurred while fetching orders',
      };
    }
  }

  /// Handles a request to update an order's status.
  Future<Map<String, Object?>> updateOrderStatus(
    Map<String, Object?> request,
  ) async {
    try {
      _logger.info('Handling update order status request');

      // Validate request
      if (!request.containsKey('id') || !request.containsKey('status')) {
        return {
          'success': false,
          'message': 'Order ID and status are required',
        };
      }

      final id = request['id'] as String;
      final status = _parseOrderStatus(request['status'] as String);

      // Get order
      final order = await _db.findOrderById(id);

      if (order == null) {
        return {'success': false, 'message': 'Order not found'};
      }

      // Update order status
      final updatedOrder = order.updateStatus(status);
      await _db.updateOrder(updatedOrder);

      return {'success': true, 'order': updatedOrder.toJson()};
    } catch (e) {
      _logger.error('Error handling update order status request: $e');
      return {
        'success': false,
        'message': 'An error occurred while updating the order status',
      };
    }
  }

  /// Handles a request to cancel an order.
  Future<Map<String, Object?>> cancelOrder(Map<String, Object?> request) async {
    try {
      _logger.info('Handling cancel order request');

      // Validate request
      if (!request.containsKey('id')) {
        return {'success': false, 'message': 'Order ID is required'};
      }

      final id = request['id'] as String;

      // Get order
      final order = await _db.findOrderById(id);

      if (order == null) {
        return {'success': false, 'message': 'Order not found'};
      }

      // Check if order can be cancelled
      if (order.status == OrderStatus.delivered ||
          order.status == OrderStatus.cancelled) {
        return {'success': false, 'message': 'Order cannot be cancelled'};
      }

      // Cancel order
      final updatedOrder = order.updateStatus(OrderStatus.cancelled);
      await _db.updateOrder(updatedOrder);

      // Refund payment if necessary
      if (order.paymentStatus == PaymentStatus.paid &&
          order.transactionId != null) {
        final refunded = await _paymentService.refundPayment(
          order.transactionId!,
          order.total,
          'Order cancelled',
        );

        if (refunded) {
          final refundedOrder = updatedOrder.updatePaymentStatus(
            PaymentStatus.refunded,
          );
          await _db.updateOrder(refundedOrder);

          // Restore product stock
          for (final item in order.items) {
            final product = await _db.findProductById(item.productId);
            if (product != null) {
              final updatedProduct = product.copyWith(
                stockQuantity: product.stockQuantity + item.quantity,
                updatedAt: DateTime.now(),
              );
              await _db.updateProduct(updatedProduct);
            }
          }

          return {
            'success': true,
            'order': refundedOrder.toJson(),
            'message': 'Order cancelled and payment refunded',
          };
        } else {
          return {
            'success': true,
            'order': updatedOrder.toJson(),
            'message': 'Order cancelled but payment could not be refunded',
          };
        }
      }

      return {
        'success': true,
        'order': updatedOrder.toJson(),
        'message': 'Order cancelled',
      };
    } catch (e) {
      _logger.error('Error handling cancel order request: $e');
      return {
        'success': false,
        'message': 'An error occurred while cancelling the order',
      };
    }
  }

  /// Validates a create order request.
  bool _validateCreateOrderRequest(Map<String, Object?> request) {
    // Check required fields
    if (!request.containsKey('userId') ||
        !request.containsKey('items') ||
        !request.containsKey('shippingAddress') ||
        !request.containsKey('paymentMethod') ||
        !request.containsKey('paymentDetails')) {
      return false;
    }

    // Validate items
    final items = request['items'];
    if (items is! List || items.isEmpty) {
      return false;
    }

    for (final item in items) {
      if (item is! Map<String, Object?> ||
          !item.containsKey('productId') ||
          !item.containsKey('quantity')) {
        return false;
      }

      final quantity = item['quantity'];
      if (quantity is! int || quantity <= 0) {
        return false;
      }
    }

    // Validate shipping address
    final shippingAddress = request['shippingAddress'];
    if (shippingAddress is! Map<String, Object?> ||
        !shippingAddress.containsKey('street') ||
        !shippingAddress.containsKey('city') ||
        !shippingAddress.containsKey('state') ||
        !shippingAddress.containsKey('postalCode') ||
        !shippingAddress.containsKey('country')) {
      return false;
    }

    // Validate billing address if provided
    final billingAddress = request['billingAddress'];
    if (billingAddress != null) {
      if (billingAddress is! Map<String, Object?> ||
          !billingAddress.containsKey('street') ||
          !billingAddress.containsKey('city') ||
          !billingAddress.containsKey('state') ||
          !billingAddress.containsKey('postalCode') ||
          !billingAddress.containsKey('country')) {
        return false;
      }
    }

    // Validate payment method
    final paymentMethod = request['paymentMethod'];
    if (paymentMethod is! String || !_isValidPaymentMethod(paymentMethod)) {
      return false;
    }

    // Validate payment details
    final paymentDetails = request['paymentDetails'];
    if (paymentDetails is! Map<String, Object?>) {
      return false;
    }

    return true;
  }

  /// Checks if a payment method is valid.
  bool _isValidPaymentMethod(String method) {
    return [
      'creditCard',
      'paypal',
      'bankTransfer',
      'applePay',
      'googlePay',
    ].contains(method);
  }

  /// Parses a payment method string to enum.
  PaymentMethod _parsePaymentMethod(String method) {
    switch (method) {
      case 'creditCard':
        return PaymentMethod.creditCard;
      case 'paypal':
        return PaymentMethod.paypal;
      case 'bankTransfer':
        return PaymentMethod.bankTransfer;
      case 'applePay':
        return PaymentMethod.applePay;
      case 'googlePay':
        return PaymentMethod.googlePay;
      default:
        throw ArgumentError('Invalid payment method: $method');
    }
  }

  /// Parses an order status string to enum.
  OrderStatus _parseOrderStatus(String status) {
    switch (status) {
      case 'pending':
        return OrderStatus.pending;
      case 'processing':
        return OrderStatus.processing;
      case 'shipped':
        return OrderStatus.shipped;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'returned':
        return OrderStatus.returned;
      default:
        throw ArgumentError('Invalid order status: $status');
    }
  }

  /// Generates a unique order ID.
  String _generateOrderId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return 'ORD-$timestamp-$random';
  }
}
