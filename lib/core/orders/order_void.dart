/// Mandatory reasons for cancelling and voiding a confirmed order.
abstract final class VoidReason {
  static const String customerCancelled = 'Customer Cancelled';
  static const String cashierMistake = 'Cashier Mistake';
  static const String paymentDeclined = 'Payment Declined';

  static const List<String> mandatoryReasons = [
    customerCancelled,
    cashierMistake,
    paymentDeclined,
  ];

  /// Validates if the given string is one of the mandatory reasons.
  static bool isValid(String reason) => mandatoryReasons.contains(reason);
}

/// Immutable audit record representing a supervisor-authorized order void.
class OrderVoid {
  const OrderVoid({
    required this.id,
    required this.orderId,
    required this.voidedBySupervisorId,
    required this.cashierId,
    required this.reason,
    required this.voidedAt,
    this.supervisorName,
    this.cashierName,
  });

  final int id;
  final int orderId;
  final int voidedBySupervisorId;
  final int cashierId;
  final String reason;
  final DateTime voidedAt;
  final String? supervisorName;
  final String? cashierName;

  factory OrderVoid.fromMap(
    Map<String, Object?> map, {
    String? supervisorName,
    String? cashierName,
  }) {
    return OrderVoid(
      id: map['id'] as int,
      orderId: map['order_id'] as int,
      voidedBySupervisorId: map['voided_by_supervisor_id'] as int,
      cashierId: map['cashier_id'] as int,
      reason: map['reason'] as String,
      voidedAt: DateTime.parse(map['voided_at'] as String),
      supervisorName: supervisorName ?? (map['supervisor_name'] as String?),
      cashierName: cashierName ?? (map['cashier_name'] as String?),
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id > 0) 'id': id,
      'order_id': orderId,
      'voided_by_supervisor_id': voidedBySupervisorId,
      'cashier_id': cashierId,
      'reason': reason,
      'voided_at': voidedAt.toIso8601String(),
    };
  }
}
