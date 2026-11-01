import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('databases upgrading from v29 or skipped migration states receive payment_events and supplier_opening_adjustments', () async {
    final directory = await Directory.systemTemp.createTemp('v30-migration-safety-');
    final dbPath = '${directory.path}/legacy_v29.db';
    addTearDown(() async {
      await directory.delete(recursive: true);
    });

    final store = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
    var db = await store.initialize();

    // Verify baseline fresh install version
    expect(await db.getVersion(), PosDatabaseConstants.schemaVersion);

    // Simulate an existing database that had reached version 29, but missed payment_events
    // and supplier_opening_adjustments due to parallel branch merges.
    await db.execute('DROP TABLE IF EXISTS payment_events');
    await db.execute('DROP TABLE IF EXISTS supplier_opening_adjustments');
    await db.execute('DROP TRIGGER IF EXISTS reporting_name_payment_events_recorded_by');
    await db.execute('DROP TRIGGER IF EXISTS reporting_name_payment_events_approved_by');

    // Insert mock data into orders and order_payments
    final dayId = await db.insert('business_days', {
      'opened_at': '2026-11-01 10:00:00',
      'opened_by_staff_id': 1,
      'status': 'OPEN',
    });
    final shiftId = await db.insert('shifts', {
      'business_day_id': dayId,
      'staff_id': 2,
      'opened_at': '2026-11-01 10:00:00',
      'opening_float': 1000.0,
      'status': 'OPEN',
    });
    final orderId = await db.insert('orders', {
      'business_day_id': dayId,
      'shift_id': shiftId,
      'cashier_id': 2,
      'token_number': 3,
      'dining_type': 'DINE_IN',
      'subtotal': 650.0,
      'grand_total': 650.0,
      'payment_status': 'SETTLED',
      'created_at': '2026-11-01 10:15:00',
    });
    await db.insert('order_payments', {
      'order_id': orderId,
      'payment_method': 'CASH',
      'amount_tendered': 1000.0,
      'change_returned': 350.0,
      'amount_tendered_paisa': 100000,
      'change_returned_paisa': 35000,
    });

    // Artificially reset user_version to 29 (reproducing user environment)
    await db.setVersion(29);
    await store.close();

    // Re-initialize: PosDatabase must upgrade from 29 to 30 and heal missing schemas
    final upgradedStore = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
    final upgradedDb = await upgradedStore.initialize();
    addTearDown(() => upgradedStore.close());

    expect(await upgradedDb.getVersion(), 30);

    // Verify payment_events exists and has triggers and index
    final peTable = await upgradedDb.rawQuery("PRAGMA table_info('payment_events')");
    expect(peTable, isNotEmpty);
    final peCols = peTable.map((c) => c['name']).toSet();
    expect(peCols, containsAll(['id', 'event_key', 'kind', 'amount_paisa', 'order_id', 'tender_id']));

    final triggers = (await upgradedDb.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger'"))
        .map((r) => r['name'] as String).toSet();
    expect(triggers, contains('payment_events_no_update'));
    expect(triggers, contains('payment_events_no_delete'));
    expect(triggers, contains('reporting_name_payment_events_recorded_by'));
    expect(triggers, contains('reporting_name_payment_events_approved_by'));

    // Verify supplier_opening_adjustments exists and has triggers and index
    final soaTable = await upgradedDb.rawQuery("PRAGMA table_info('supplier_opening_adjustments')");
    expect(soaTable, isNotEmpty);
    expect(triggers, contains('supplier_opening_adjustments_no_UPDATE'));
    expect(triggers, contains('supplier_opening_adjustments_no_DELETE'));

    // Verify supplier_payment_allocations has created_at
    final spaCols = (await upgradedDb.rawQuery("PRAGMA table_info('supplier_payment_allocations')"))
        .map((c) => c['name']).toSet();
    expect(spaCols, contains('created_at'));

    // Verify Image 2 query (Blind shift handover) executes cleanly and sums correctly
    final handoverQuery = await upgradedDb.rawQuery('''
      SELECT COALESCE(SUM(
        COALESCE(op.amount_tendered_paisa, CAST(ROUND(op.amount_tendered * 100) AS INTEGER))
        - COALESCE(op.change_returned_paisa, CAST(ROUND(op.change_returned * 100) AS INTEGER))
      ), 0) AS receipt_paisa
      FROM order_payments op JOIN orders o ON o.id = op.order_id LEFT JOIN payment_events pe ON pe.tender_id=op.id
      WHERE COALESCE(pe.shift_id,o.shift_id) = ? AND op.payment_method = 'CASH'
        AND COALESCE(op.amount_tendered_paisa, CAST(ROUND(op.amount_tendered * 100) AS INTEGER)) > 0
        AND (pe.id IS NOT NULL OR o.payment_status IN ('SETTLED', 'REFUND_PENDING', 'CANCELLED', 'REFUNDED'))
    ''', [shiftId]);
    expect((handoverQuery.single['receipt_paisa'] as num).toInt(), 65000);

    // Verify Image 1 analytics queries execute cleanly
    final analyticsQuery = await upgradedDb.rawQuery('''
      SELECT x.*,o.business_day_id AS originating_business_day_id,o.shift_id AS originating_shift_id,s.staff_id AS shift_owner_id
      FROM payment_events x LEFT JOIN orders o ON o.id=x.order_id LEFT JOIN shifts s ON s.id=x.shift_id
    ''');
    expect(analyticsQuery, isEmpty);

    // Verify integrity and foreign key constraints
    expect((await upgradedDb.rawQuery('PRAGMA integrity_check')).single.values.first, 'ok');
    expect(await upgradedDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
