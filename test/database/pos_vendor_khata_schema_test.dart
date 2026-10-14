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

  group('PosDatabase Vendor Khata Schema Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_vendor_khata_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_vendor_khata_pos.db';
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

    test('creates tables vendor_khata and vendor_transactions with schemaVersion 7', () async {
      final db = await posDb.initialize();

      // Check system_settings schema_version
      final settings = await db.query(
        PosDatabaseConstants.tableSystemSettings,
        where: 'key = ?',
        whereArgs: ['schema_version'],
      );
      expect(settings.first['value'], equals('7'));

      // Check tables exist
      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tablesResult.map((r) => r['name'] as String).toList();

      expect(tableNames, contains(PosDatabaseConstants.tableVendorKhata));
      expect(tableNames, contains(PosDatabaseConstants.tableVendorTransactions));
    });

    test('vendor_transactions enforces foreign key reference to vendor_khata', () async {
      final db = await posDb.initialize();

      // Foreign key failure when vendor_id does not exist
      expect(
        () async => await db.insert(
          PosDatabaseConstants.tableVendorTransactions,
          {
            'vendor_id': 9999,
            'type': 'PURCHASE_CREDIT',
            'amount': 5000.0,
            'reference_slip': 'SLIP-001',
            'created_at': '2026-10-14 12:00:00',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('vendor_khata enforces unique vendor name constraint', () async {
      final db = await posDb.initialize();

      await db.insert(
        PosDatabaseConstants.tableVendorKhata,
        {
          'name': 'Al-Madina Poultry',
          'phone': '03001234567',
          'supplied_ingredients': 'Chicken Boti, Wings',
          'opening_balance': 15000.0,
          'current_balance': 15000.0,
          'created_at': '2026-10-14 12:00:00',
          'updated_at': '2026-10-14 12:00:00',
        },
      );

      // Duplicate vendor name must throw DatabaseException
      expect(
        () async => await db.insert(
          PosDatabaseConstants.tableVendorKhata,
          {
            'name': 'Al-Madina Poultry',
            'phone': '03217654321',
            'supplied_ingredients': 'Eggs',
            'opening_balance': 0.0,
            'current_balance': 0.0,
            'created_at': '2026-10-14 13:00:00',
            'updated_at': '2026-10-14 13:00:00',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
