import 'package:sqflite_common/sqlite_api.dart';

/// Shared append-only evidence written inside the authorized operation's transaction.
abstract final class PaymentEvent {
  static Future<int> record(DatabaseExecutor txn, {
    required String eventKey, required String kind, required int amountPaisa,
    required String paymentSource, required int recordedBy,
    required DateTime recordedAt, DateTime? actualAt,
    int? businessDayId, int? shiftId, int? orderId, int? tenderId,
    int? movementId, int? settlementId, int? approvedBy,
    int changePaisa = 0, int roundingPaisa = 0,
    String? sourceTable, int? sourceId, String? paymentMethod,
  }) async {
    final actual = (actualAt ?? recordedAt).toUtc();
    if (eventKey.trim().isEmpty || actual.isAfter(recordedAt.toUtc())) {
      throw ArgumentError('Event identity and actual time must be valid.');
    }
    final actor = await txn.query('staff', where: 'id=? AND is_active=1 AND login_enabled=1', whereArgs: [recordedBy]);
    if (actor.isEmpty) throw StateError('An active recording actor is required.');
    String? ownerName;
    if (paymentSource == 'DRAWER' && shiftId == null) throw StateError('Drawer events require a receiving Shift.');
    if (shiftId != null) {
      final shifts = await txn.rawQuery('SELECT s.*,st.name AS owner_name FROM shifts s JOIN staff st ON st.id=s.staff_id WHERE s.id=?', [shiftId]);
      if (shifts.isEmpty || shifts.single['status'] != 'OPEN' || shifts.single['business_day_id'] != businessDayId || actual.isBefore(_instant(shifts.single['opened_at'] as String))) {
        throw StateError('Event must belong to its receiving open Shift.');
      }
      ownerName = shifts.single['owner_name'] as String?;
    }
    if (businessDayId != null) {
      final days = await txn.query('business_days', where: 'id=?', whereArgs: [businessDayId]);
      if (days.isEmpty || days.single['status'] != 'OPEN' || actual.isBefore(_instant(days.single['opened_at'] as String))) {
        throw StateError('Actual time must lie within the authorized open Business Day.');
      }
    }
    return txn.insert('payment_events', {
      'event_key': eventKey, 'kind': kind, 'amount_paisa': amountPaisa,
      'payment_source': paymentSource, 'payment_method': paymentMethod,
      'actual_at': actual.toIso8601String(), 'recorded_at': recordedAt.toUtc().toIso8601String(),
      'business_day_id': businessDayId, 'shift_id': shiftId, 'order_id': orderId,
      'tender_id': tenderId, 'movement_id': movementId, 'settlement_id': settlementId,
      'recorded_by': recordedBy, 'approved_by': approvedBy,
      'recorded_by_name_snapshot': actor.single['name'], 'shift_owner_name_snapshot': ownerName,
      'change_paisa': changePaisa, 'rounding_paisa': roundingPaisa,
      'source_table': sourceTable, 'source_id': sourceId,
    });
  }

  static DateTime _instant(String text) {
    final value = DateTime.parse(text);
    return RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(text)
        ? value.toUtc()
        : DateTime.utc(value.year, value.month, value.day, value.hour, value.minute, value.second).subtract(const Duration(hours: 5));
  }
}
