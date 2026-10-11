import 'payment_method.dart';

/// A payment transaction row settled against an order.
class OrderPayment {
  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.paymentMethod,
    required this.amountTendered,
    this.changeReturned = 0.0,
    this.referenceCode,
  });

  final int id;
  final int orderId;
  final PaymentMethod paymentMethod;
  final double amountTendered;
  final double changeReturned;
  final String? referenceCode;

  double get netPaid => amountTendered - changeReturned;

  factory OrderPayment.fromMap(Map<String, Object?> map) {
    return OrderPayment(
      id: map['id'] as int,
      orderId: map['order_id'] as int,
      paymentMethod: PaymentMethod.fromCode(map['payment_method'] as String),
      amountTendered: (map['amount_tendered'] as num).toDouble(),
      changeReturned: (map['change_returned'] as num?)?.toDouble() ?? 0.0,
      referenceCode: map['reference_code'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'order_id': orderId,
      'payment_method': paymentMethod.code,
      'amount_tendered': amountTendered,
      'change_returned': changeReturned,
      'reference_code': referenceCode,
    };
  }
}
