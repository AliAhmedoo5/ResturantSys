import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('legacy tender upgrade preserves balances without inventing receiving events', () async {
    final directory = await Directory.systemTemp.createTemp('payment-event-migration-');
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: '${directory.path}/legacy.db');
    var db = await store.initialize();
    addTearDown(() async { await store.close(); await directory.delete(recursive: true); });
    await db.execute('DROP TABLE payment_events');
    final day = await db.insert('business_days', {'opened_at': '2026-10-29 18:00:00', 'status': 'CLOSED', 'opened_by_staff_id': 1});
    final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': 2, 'opened_at': '2026-10-29 18:00:00', 'status': 'CLOSED', 'opening_float': 100, 'counted_cash': 250});
    final order = await db.insert('orders', {'business_day_id': day, 'shift_id': shift, 'cashier_id': 2, 'token_number': 1, 'dining_type': 'TAKEAWAY', 'subtotal': 150, 'grand_total': 150, 'payment_status': 'SETTLED', 'created_at': '2026-10-29 18:15:00'});
    await db.insert('order_payments', {'order_id': order, 'payment_method': 'CASH', 'amount_tendered': 200, 'change_returned': 50, 'amount_tendered_paisa': 20000, 'change_returned_paisa': 5000});
    final oldTender = await db.query('order_payments');
    final oldShift = await db.query('shifts');
    await db.insert('report_runs', {'business_day_id': day, 'snapshot_json': '{"sealed":true}', 'content_hash': 'original-sealed-hash', 'created_by': 1, 'created_at': '2026-10-30T01:00:00Z'});
    final oldReports = await db.query('report_runs');
    await db.setVersion(21);
    await store.close();
    db = await store.initialize();
    expect(await db.query('order_payments'), oldTender);
    expect(await db.query('shifts'), oldShift);
    expect(await db.query('report_runs'), oldReports);
    expect(await db.query('payment_events'), isEmpty, reason: 'Legacy actual time and receiving attribution remain unknown');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
