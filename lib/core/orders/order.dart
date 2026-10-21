import 'dining_type.dart';
import 'order_item.dart';
import 'order_payment.dart';
import 'token_status.dart';

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
    this.tokenStatus = TokenStatus.preparing,
    this.currentRevision = 1,
    this.items = const [],
    this.payments = const [],
    this.cashierName,
    this.deliveryAreaId,
    this.deliveryAreaName,
    this.deliveryAddress,
    this.customerPhone,
    this.customerName,
    this.deliveryFeePaisa = 0,
    this.cashRoundingPaisa = 0,
  });

  final int? deliveryAreaId;
  final int deliveryFeePaisa, cashRoundingPaisa;
  final String? deliveryAreaName, deliveryAddress, customerPhone, customerName;
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
  final TokenStatus tokenStatus;
  final int currentRevision;
  final List<OrderItem> items;
  final List<OrderPayment> payments;
  final String? cashierName;

  /// Formats the daily sequential token into a high-contrast label (e.g. #01, #02).
  String get tokenDisplay => '#${tokenNumber.toString().padLeft(2, '0')}';

  bool get isSettled => paymentStatus == 'SETTLED';
  bool get isVoided => paymentStatus == 'VOIDED';
  bool get isCancelled => paymentStatus == 'CANCELLED';
  bool get isRefundPending =>
      paymentStatus == 'REFUND_PENDING' || paymentStatus == 'REFUND_OWED';

  factory Order.fromMap(
    Map<String, Object?> map, {
    List<OrderItem> items = const [],
    List<OrderPayment> payments = const [],
    String? cashierName,
  }) {
    return Order(
      id: map['id'] as int,
      deliveryAreaId: map['delivery_area_id'] as int?,
      deliveryAreaName: map['delivery_area_name_snapshot'] as String?,
      deliveryAddress: map['delivery_address_snapshot'] as String?,
      deliveryFeePaisa: map['delivery_fee_paisa'] as int? ?? 0,
      cashRoundingPaisa: map['cash_rounding_paisa'] as int? ?? 0,
      customerPhone: map['customer_phone'] as String?,
      customerName: map['customer_name'] as String?,
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
      tokenStatus: map['token_status'] != null
          ? TokenStatus.fromCode(map['token_status'] as String)
          : TokenStatus.preparing,
      currentRevision: (map['current_revision'] as int?) ?? 1,
      items: items,
      payments: payments,
      cashierName: cashierName ?? map['cashier_name'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'delivery_area_id': deliveryAreaId,
      'delivery_area_name_snapshot': deliveryAreaName,
      'delivery_address_snapshot': deliveryAddress,
      'delivery_fee_paisa': deliveryFeePaisa,
      'cash_rounding_paisa': cashRoundingPaisa,
      'customer_phone': customerPhone,
      'customer_name': customerName,
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
      'token_status': tokenStatus.code,
      'current_revision': currentRevision,
    };
  }
}
