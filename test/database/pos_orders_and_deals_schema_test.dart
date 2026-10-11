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

    test('Schema version is 4 and creates deals, deal_items, and order_items tables', () async {
      final db = await posDb.initialize();

      // Check schema version
      final versionResult = await db.rawQuery('PRAGMA user_version;');
      expect(versionResult.first.values.first, equals(4));

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
  });
}
