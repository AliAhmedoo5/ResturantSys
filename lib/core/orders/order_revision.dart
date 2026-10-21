import 'order_revision_line.dart';

/// An immutable snapshot recording an order modification or cancellation.
class OrderRevision {
  const OrderRevision({
    required this.id,
    required this.orderId,
    required this.revisionNo,
    this.priorRevisionId,
    required this.action,
    required this.reason,
    required this.cashierId,
    this.cashierName,
    required this.businessDayId,
    required this.createdAtUtc,
    required this.oldTotalPaisa,
    required this.newTotalPaisa,
    required this.moneyDeltaPaisa,
    required this.priorSnapshotJson,
    required this.newSnapshotJson,
    required this.commandId,
    this.lines = const [],
  });

  final int id;
  final int orderId;
  final int revisionNo;
  final int? priorRevisionId;
  final String action;
  final String reason;
  final int cashierId;
  final String? cashierName;
  final int businessDayId;
  final DateTime createdAtUtc;
  final int oldTotalPaisa;
  final int newTotalPaisa;
  final int moneyDeltaPaisa;
  final String priorSnapshotJson;
  final String newSnapshotJson;
  final String commandId;
  final List<OrderRevisionLine> lines;

  bool get isCancellation => action == 'CANCEL';
  bool get hasFinancialReduction => moneyDeltaPaisa < 0;

  factory OrderRevision.fromMap(
    Map<String, Object?> map, {
    List<OrderRevisionLine> lines = const [],
    String? cashierName,
  }) {
    return OrderRevision(
      id: map['id'] as int,
      orderId: map['order_id'] as int,
      revisionNo: map['revision_no'] as int,
      priorRevisionId: map['prior_revision_id'] as int?,
      action: map['action'] as String,
      reason: map['reason'] as String,
      cashierId: map['cashier_id'] as int,
      cashierName: cashierName ?? map['cashier_name'] as String?,
      businessDayId: map['business_day_id'] as int,
      createdAtUtc: DateTime.parse(map['created_at_utc'] as String),
      oldTotalPaisa: map['old_total_paisa'] as int,
      newTotalPaisa: map['new_total_paisa'] as int,
      moneyDeltaPaisa: map['money_delta_paisa'] as int,
      priorSnapshotJson: map['prior_snapshot_json'] as String,
      newSnapshotJson: map['new_snapshot_json'] as String,
      commandId: map['command_id'] as String,
      lines: lines,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'revision_no': revisionNo,
      'prior_revision_id': priorRevisionId,
      'action': action,
      'reason': reason,
      'cashier_id': cashierId,
      'business_day_id': businessDayId,
      'created_at_utc': createdAtUtc.toIso8601String(),
      'old_total_paisa': oldTotalPaisa,
      'new_total_paisa': newTotalPaisa,
      'money_delta_paisa': moneyDeltaPaisa,
      'prior_snapshot_json': priorSnapshotJson,
      'new_snapshot_json': newSnapshotJson,
      'command_id': commandId,
    };
  }
}
