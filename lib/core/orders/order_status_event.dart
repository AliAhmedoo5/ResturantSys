import 'token_status.dart';

/// An observed cashier fulfillment transition, never reconstructed from history.
class OrderStatusEvent {
  OrderStatusEvent.fromMap(Map<String, Object?> row)
      : orderId = row['order_id'] as int,
        cashierId = row['cashier_id'] as int,
        fromStatus = TokenStatus.fromCode(row['from_status'] as String),
        toStatus = TokenStatus.fromCode(row['to_status'] as String),
        recordedAt = DateTime.parse(row['recorded_at'] as String);

  final int orderId, cashierId;
  final TokenStatus fromStatus, toStatus;
  final DateTime recordedAt;
}
