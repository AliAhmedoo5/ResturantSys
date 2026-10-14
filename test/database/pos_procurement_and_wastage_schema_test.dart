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

  group('PosDatabase Procurement & Wastage Schema Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_procurement_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_procurement_pos.db';
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

    test('creates tables mandi_procurements and kitchen_wastage with schemaVersion 6', () async {
      final db = await posDb.initialize();

      // Check system_settings schema_version
      final settings = await db.query(
        PosDatabaseConstants.tableSystemSettings,
        where: 'key = ?',
        whereArgs: ['schema_version'],
      );
      expect(settings.first['value'], equals('6'));

      // Check tables exist
      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tablesResult.map((r) => r['name'] as String).toList();

      expect(tableNames, contains(PosDatabaseConstants.tableMandiProcurements));
      expect(tableNames, contains(PosDatabaseConstants.tableKitchenWastage));
    });

    test('mandi_procurements enforces foreign key references to raw_ingredients', () async {
      final db = await posDb.initialize();

      // Foreign key failure when raw ingredient does not exist
      expect(
        () async => await db.insert(
          PosDatabaseConstants.tableMandiProcurements,
          {
            'raw_ingredient_id': 9999,
            'traditional_unit': 'MANN',
            'quantity': 1.0,
            'total_cost': 4000.0,
            'converted_quantity': 40000.0,
            'cost_per_recipe_unit': 0.10,
            'created_at': '2026-10-14 12:00:00',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('kitchen_wastage enforces foreign key references to staff and raw_ingredients', () async {
      final db = await posDb.initialize();

      // Foreign key failure when staff does not exist
      expect(
        () async => await db.insert(
          PosDatabaseConstants.tableKitchenWastage,
          {
            'staff_id': 9999,
            'raw_ingredient_id': 1,
            'quantity': 500.0,
            'cost_loss': 50.0,
            'reason': 'BURNED',
            'created_at': '2026-10-14 12:00:00',
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
