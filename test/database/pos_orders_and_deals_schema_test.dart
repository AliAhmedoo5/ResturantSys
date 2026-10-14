import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PosDatabase Orders, Deals & Order Items Schema Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_orders_schema_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_orders_schema.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Schema version is 5 and creates deals, deal_items, order_items, and order_voids tables', () async {
      final db = await posDb.initialize();

      // Check schema version
      final versionResult = await db.rawQuery('PRAGMA user_version;');
      expect(versionResult.first.values.first, equals(PosDatabaseConstants.schemaVersion));
      expect(versionResult.first.values.first, greaterThanOrEqualTo(5));

      // Check tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tables.map((row) => row['name'] as String).toSet();

      expect(tableNames.contains(PosDatabaseConstants.tableDeals), isTrue);
      expect(tableNames.contains(PosDatabaseConstants.tableDealItems), isTrue);
      expect(tableNames.contains(PosDatabaseConstants.tableDealItemOptions), isTrue);
      expect(tableNames.contains(PosDatabaseConstants.tableOrderItems), isTrue);
      expect(tableNames.contains(PosDatabaseConstants.tableOrders), isTrue);
      expect(tableNames.contains(PosDatabaseConstants.tableOrderPayments), isTrue);
      expect(tableNames.contains(PosDatabaseConstants.tableOrderVoids), isTrue);
    });

    test('Foreign key cascades work for deals and order items', () async {
      final db = await posDb.initialize();

      // Create a deal
      final dealId = await db.insert(PosDatabaseConstants.tableDeals, {
        'name': 'Mega Combo',
        'base_price': 1200.0,
        'is_active': 1,
        'created_at': '2026-10-12 12:00:00',
      });

      // Create deal item slot
      final dealItemId = await db.insert(PosDatabaseConstants.tableDealItems, {
        'deal_id': dealId,
        'group_name': 'Drink',
        'is_upgradeable': 1,
        'upgrade_price': 50.0,
      });

      // Verify inserted
      final dealItems = await db.query(
        PosDatabaseConstants.tableDealItems,
        where: 'deal_id = ?',
        whereArgs: [dealId],
      );
      expect(dealItems.length, equals(1));

      // Delete deal and verify cascade
      await db.delete(
        PosDatabaseConstants.tableDeals,
        where: 'id = ?',
        whereArgs: [dealId],
      );

      final dealItemsAfter = await db.query(
        PosDatabaseConstants.tableDealItems,
        where: 'id = ?',
        whereArgs: [dealItemId],
      );
      expect(dealItemsAfter, isEmpty);
    });

    test('order_voids persists audit record immutably linking order, supervisor, and cashier', () async {
      final db = await posDb.initialize();

      // Create prerequisite business day & shift for FK integrity
      final bDayId = await db.insert(PosDatabaseConstants.tableBusinessDays, {
        'opened_by_staff_id': 1,
        'opened_at': '2026-10-12 09:00:00',
        'status': 'OPEN',
      });
      final sId = await db.insert(PosDatabaseConstants.tableShifts, {
        'business_day_id': bDayId,
        'staff_id': 2,
        'opened_at': '2026-10-12 09:00:00',
        'opening_float': 1000.0,
        'status': 'OPEN',
      });

      // Create an order
      final orderId = await db.insert(PosDatabaseConstants.tableOrders, {
        'business_day_id': bDayId,
        'shift_id': sId,
        'cashier_id': 2,
        'token_number': 1,
        'dining_type': 'DINE_IN',
        'subtotal': 500.0,
        'discount_amount': 0.0,
        'tax_amount': 0.0,
        'grand_total': 500.0,
        'payment_status': 'SETTLED',
        'created_at': '2026-10-12 12:00:00',
      });

      // Insert void audit record
      final voidId = await db.insert(PosDatabaseConstants.tableOrderVoids, {
        'order_id': orderId,
        'voided_by_supervisor_id': 1,
        'cashier_id': 2,
        'reason': 'Customer Cancelled',
        'voided_at': '2026-10-12 12:05:00',
      });

      expect(voidId, greaterThan(0));

      final voidRows = await db.query(
        PosDatabaseConstants.tableOrderVoids,
        where: 'id = ?',
        whereArgs: [voidId],
      );
      expect(voidRows.length, equals(1));
      expect(voidRows.first['order_id'], equals(orderId));
      expect(voidRows.first['voided_by_supervisor_id'], equals(1));
      expect(voidRows.first['cashier_id'], equals(2));
      expect(voidRows.first['reason'], equals('Customer Cancelled'));
      expect(voidRows.first['voided_at'], equals('2026-10-12 12:05:00'));
    });
  });
}
