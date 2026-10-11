import 'dining_type.dart';
import 'order_item.dart';
import 'order_payment.dart';

/// A finalized commercial order transaction.
class Order {
  const Order({
    required this.id,
    required this.businessDayId,
    required this.shiftId,
    required this.cashierId,
    required this.tokenNumber,
    required this.diningType,
    required this.subtotal,
    this.discountAmount = 0.0,
    this.discountId,
    this.taxAmount = 0.0,
    required this.grandTotal,
    required this.paymentStatus,
    required this.createdAt,
    this.items = const [],
    this.payments = const [],
    this.cashierName,
  });

  final int id;
  final int businessDayId;
  final int shiftId;
  final int cashierId;
  final int tokenNumber;
  final DiningType diningType;
  final double subtotal;
  final double discountAmount;
  final int? discountId;
  final double taxAmount;
  final double grandTotal;
  final String paymentStatus;
  final DateTime createdAt;
  final List<OrderItem> items;
  final List<OrderPayment> payments;
  final String? cashierName;

  /// Formats the daily sequential token into a high-contrast label (e.g. #01, #02).
  String get tokenDisplay => '#${tokenNumber.toString().padLeft(2, '0')}';

  bool get isSettled => paymentStatus == 'SETTLED';
  bool get isVoided => paymentStatus == 'VOIDED';

  factory Order.fromMap(
    Map<String, Object?> map, {
    List<OrderItem> items = const [],
    List<OrderPayment> payments = const [],
    String? cashierName,
  }) {
    return Order(
      id: map['id'] as int,
      businessDayId: map['business_day_id'] as int,
      shiftId: map['shift_id'] as int,
      cashierId: map['cashier_id'] as int,
      tokenNumber: map['token_number'] as int,
      diningType: DiningType.fromCode(map['dining_type'] as String),
      subtotal: (map['subtotal'] as num).toDouble(),
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
      discountId: map['discount_id'] as int?,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (map['grand_total'] as num).toDouble(),
      paymentStatus: map['payment_status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items,
      payments: payments,
      cashierName: cashierName ?? map['cashier_name'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'business_day_id': businessDayId,
      'shift_id': shiftId,
      'cashier_id': cashierId,
      'token_number': tokenNumber,
      'dining_type': diningType.code,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'discount_id': discountId,
      'tax_amount': taxAmount,
      'grand_total': grandTotal,
      'payment_status': paymentStatus,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
