/// Represents a payment in the system.
class Payment {
  /// The unique identifier for the payment.
  final String id;

  /// The ID of the order this payment is for.
  final String orderId;

  /// The amount of the payment.
  final double amount;

  /// The currency of the payment.
  final String currency;

  /// The payment method used.
  final String paymentMethod;

  /// The payment token.
  final String paymentToken;

  /// The transaction ID from the payment processor.
  final String transactionId;

  /// The status of the payment.
  final PaymentStatus status;

  /// The date and time the payment was created.
  final DateTime createdAt;

  /// The date and time the payment was updated.
  final DateTime? updatedAt;

  /// Creates a new payment.
  Payment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.paymentToken,
    required this.transactionId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  /// Creates a copy of this payment with the given fields replaced with the new values.
  Payment copyWith({
    String? id,
    String? orderId,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? paymentToken,
    String? transactionId,
    PaymentStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Payment(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentToken: paymentToken ?? this.paymentToken,
      transactionId: transactionId ?? this.transactionId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Creates a payment from a JSON object.
  factory Payment.fromJson(Map<String, Object?> json) {
    return Payment(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      amount: json['amount'] as double,
      currency: json['currency'] as String,
      paymentMethod: json['paymentMethod'] as String,
      paymentToken: json['paymentToken'] as String,
      transactionId: json['transactionId'] as String,
      status: PaymentStatus.values.firstWhere(
        (e) => e.toString() == 'PaymentStatus.${json['status'] as String}',
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Converts this payment to a JSON object.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'amount': amount,
      'currency': currency,
      'paymentMethod': paymentMethod,
      'paymentToken': paymentToken,
      'transactionId': transactionId,
      'status': status.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'Payment{id: $id, orderId: $orderId, amount: $amount, currency: $currency, status: $status}';
  }
}

/// The status of a payment.
enum PaymentStatus {
  /// The payment is pending.
  pending,

  /// The payment is being processed.
  processing,

  /// The payment has been completed.
  completed,

  /// The payment has failed.
  failed,

  /// The payment has been refunded.
  refunded,

  /// The payment has been partially refunded.
  partiallyRefunded,

  /// The payment has been cancelled.
  cancelled,
}
