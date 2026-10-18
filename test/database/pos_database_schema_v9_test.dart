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

  group('Schema Migration v9 & Constraints Seam', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_db_v9_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_v9.db';
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

    test('initializes cleanly to schema version 9', () async {
      final db = await posDb.initialize();

      final versionResult = await db.rawQuery('PRAGMA user_version;');
      expect(versionResult.first.values.first, equals(9));
      expect(PosDatabaseConstants.schemaVersion, equals(9));
    });

    test('creates all required v9 tables with strict schema constraints', () async {
      final db = await posDb.initialize();

      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tablesResult.map((r) => r['name'] as String).toList();

      expect(tableNames, contains(PosDatabaseConstants.tableDeliveryAreas));
      expect(tableNames, contains(PosDatabaseConstants.tableCustomerAddresses));
      expect(tableNames, contains(PosDatabaseConstants.tableOrderRevisions));
      expect(tableNames, contains(PosDatabaseConstants.tableOrderRevisionLines));
      expect(tableNames, contains(PosDatabaseConstants.tableRiderTrips));
      expect(tableNames, contains(PosDatabaseConstants.tableCatalogImages));
      expect(tableNames, contains(PosDatabaseConstants.tableReportOutbox));
      expect(tableNames, contains(PosDatabaseConstants.tableRoundingVarianceLedger));
    });

    test('enforces strict constraints on delivery_areas and customer_addresses', () async {
      final db = await posDb.initialize();

      // Insert valid delivery area
      final areaId = await db.insert(PosDatabaseConstants.tableDeliveryAreas, {
        'name': 'F-6 Blue Area',
        'code': 'F6-BA',
        'coverage_description': 'Main commercial zone',
        'delivery_fee_paisa': 15000, // Rs. 150.00
        'min_order_paisa': 50000, // Rs. 500.00
        'target_eta_minutes': 35,
        'sort_order': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      expect(areaId, greaterThan(0));

      // Negative delivery fee must violate CHECK constraint
      expect(
        () async => db.insert(PosDatabaseConstants.tableDeliveryAreas, {
          'name': 'Invalid Area',
          'delivery_fee_paisa': -500,
          'min_order_paisa': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      // Unique name constraint
      expect(
        () async => db.insert(PosDatabaseConstants.tableDeliveryAreas, {
          'name': 'F-6 Blue Area',
          'delivery_fee_paisa': 20000,
          'min_order_paisa': 0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<DatabaseException>()),
      );

      // Insert customer address referencing delivery area
      final addressId = await db.insert(PosDatabaseConstants.tableCustomerAddresses, {
        'customer_phone': '03001234567',
        'customer_name': 'Ali Khan',
        'delivery_area_id': areaId,
        'full_address': 'House 12, Street 34, F-6/1',
        'landmark': 'Near Super Market',
        'is_default': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      expect(addressId, greaterThan(0));
    });

    test('enforces strict constraints on order_revisions and order_revision_lines', () async {
      final db = await posDb.initialize();

      // Seed business day and shift and order
      final staff = await db.query('staff', limit: 1);
      final staffId = staff.first['id'] as int;

      final dayId = await db.insert('business_days', {
        'opened_at': '2026-10-18 10:00:00',
        'opened_by_staff_id': staffId,
        'status': 'OPEN',
      });

      final shiftId = await db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': staffId,
        'opened_at': '2026-10-18 10:05:00',
        'opening_float': 5000.0,
        'status': 'OPEN',
      });

      final orderId = await db.insert('orders', {
        'business_day_id': dayId,
        'shift_id': shiftId,
        'cashier_id': staffId,
        'token_number': 1,
        'dining_type': 'DINE_IN',
        'subtotal': 1500.0,
        'grand_total': 1500.0,
        'payment_status': 'PAID',
        'token_status': 'PREPARING',
        'created_at': '2026-10-18 10:10:00',
        'current_revision': 1,
        'cash_rounding_paisa': 0,
        'delivery_fee_paisa': 0,
      });

      // Insert order revision
      final revisionId = await db.insert(PosDatabaseConstants.tableOrderRevisions, {
        'order_id': orderId,
        'revision_no': 2,
        'prior_revision_id': null,
        'action': 'CHANGE',
        'reason': 'Customer requested extra patty',
        'cashier_id': staffId,
        'business_day_id': dayId,
        'created_at_utc': '2026-10-18T10:15:00Z',
        'old_total_paisa': 150000,
        'new_total_paisa': 180000,
        'money_delta_paisa': 30000,
        'prior_snapshot_json': '{"items":[]}',
        'new_snapshot_json': '{"items":[]}',
        'command_id': 'CMD-REV-001',
      });
      expect(revisionId, greaterThan(0));

      // Check unique command_id constraint
      expect(
        () async => db.insert(PosDatabaseConstants.tableOrderRevisions, {
          'order_id': orderId,
          'revision_no': 3,
          'action': 'CHANGE',
          'reason': 'Another change',
          'cashier_id': staffId,
          'business_day_id': dayId,
          'created_at_utc': '2026-10-18T10:16:00Z',
          'old_total_paisa': 180000,
          'new_total_paisa': 200000,
          'money_delta_paisa': 20000,
          'prior_snapshot_json': '{}',
          'new_snapshot_json': '{}',
          'command_id': 'CMD-REV-001', // duplicate command_id
        }),
        throwsA(isA<DatabaseException>()),
      );

      // Check action CHECK constraint
      expect(
        () async => db.insert(PosDatabaseConstants.tableOrderRevisions, {
          'order_id': orderId,
          'revision_no': 3,
          'action': 'INVALID_ACTION',
          'reason': 'Bad action',
          'cashier_id': staffId,
          'business_day_id': dayId,
          'created_at_utc': '2026-10-18T10:17:00Z',
          'old_total_paisa': 180000,
          'new_total_paisa': 200000,
          'money_delta_paisa': 20000,
          'prior_snapshot_json': '{}',
          'new_snapshot_json': '{}',
          'command_id': 'CMD-REV-002',
        }),
        throwsA(isA<DatabaseException>()),
      );

      // Insert revision line
      final lineId = await db.insert(PosDatabaseConstants.tableOrderRevisionLines, {
        'revision_id': revisionId,
        'original_order_line_id': 101,
        'item_id': 5,
        'action': 'ADD_ITEM',
        'old_qty_decimal': '1',
        'new_qty_decimal': '2',
        'line_price_delta_paisa': 30000,
        'bom_disposition': 'UNPREPARED_RAW',
        'ingredient_delta_snapshot_json': '[]',
      });
      expect(lineId, greaterThan(0));
    });

    test('enforces strict constraints on rider_trips, catalog_images, and report_outbox', () async {
      final db = await posDb.initialize();

      final staff = await db.query('staff', limit: 1);
      final staffId = staff.first['id'] as int;

      final dayId = await db.insert('business_days', {
        'opened_at': '2026-10-18 10:00:00',
        'opened_by_staff_id': staffId,
        'status': 'OPEN',
      });

      final shiftId = await db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': staffId,
        'opened_at': '2026-10-18 10:05:00',
        'opening_float': 5000.0,
        'status': 'OPEN',
      });

      // Insert rider trip
      final tripId = await db.insert(PosDatabaseConstants.tableRiderTrips, {
        'rider_staff_id': staffId,
        'shift_id': shiftId,
        'business_day_id': dayId,
        'status': 'DISPATCHED',
        'cash_expected_paisa': 450000,
        'cash_collected_paisa': 0,
        'dispatched_at': '2026-10-18 11:00:00',
        'created_at': '2026-10-18 11:00:00',
      });
      expect(tripId, greaterThan(0));

      // Insert catalog image
      final imageId = await db.insert(PosDatabaseConstants.tableCatalogImages, {
        'entity_type': 'menu_item',
        'entity_id': 1,
        'relative_file_path': 'media/menu_items/burger_hero.jpg',
        'is_primary': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(imageId, greaterThan(0));

      // Insert report outbox entry
      final outboxId = await db.insert(PosDatabaseConstants.tableReportOutbox, {
        'business_day_id': dayId,
        'channel': 'EMAIL',
        'recipient': 'owner@smashburger.pk',
        'payload_json': '{"report_type":"Z_REPORT","date":"2026-10-18"}',
        'status': 'PENDING',
        'retry_count': 0,
        'next_attempt_at': '2026-10-18 23:59:00',
        'created_at': '2026-10-18 23:55:00',
      });
      expect(outboxId, greaterThan(0));

      // Insert rounding variance ledger record
      final ledgerId = await db.insert(PosDatabaseConstants.tableRoundingVarianceLedger, {
        'shift_id': shiftId,
        'cash_rounding_paisa': -25,
        'reason': 'Cash checkout half-up rounding discount',
        'created_at': '2026-10-18 23:56:00',
      });
      expect(ledgerId, greaterThan(0));
    });

    test('preserves historical movements and makes approved_by nullable during safe table rebuild', () async {
      // 1. Setup a pre-v9 database (simulate v8)
      final v8DbPath = '${tempDir.path}${Platform.pathSeparator}test_v8_migration.db';
      final v8Db = await databaseFactoryFfi.openDatabase(
        v8DbPath,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, version) async {
            // Core v8 schema with cash_movements lacking nullable approved_by or having NOT NULL
            await db.execute('''
              CREATE TABLE departments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE system_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE staff (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                department_id INTEGER NOT NULL REFERENCES departments(id),
                pin_hash TEXT NOT NULL UNIQUE,
                role TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE business_days (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                opened_at TEXT NOT NULL,
                closed_at TEXT,
                opened_by_staff_id INTEGER NOT NULL REFERENCES staff(id),
                closed_by_staff_id INTEGER REFERENCES staff(id),
                status TEXT NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE shifts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                business_day_id INTEGER NOT NULL REFERENCES business_days(id),
                staff_id INTEGER NOT NULL REFERENCES staff(id),
                opened_at TEXT NOT NULL,
                closed_at TEXT,
                opening_float REAL NOT NULL,
                counted_cash REAL,
                expected_cash REAL,
                discrepancy REAL,
                discrepancy_status TEXT NOT NULL DEFAULT 'CLEAN',
                status TEXT NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE cash_movements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                shift_id INTEGER NOT NULL REFERENCES shifts(id),
                staff_id INTEGER NOT NULL REFERENCES staff(id),
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                category TEXT NOT NULL,
                notes TEXT NOT NULL,
                created_at TEXT NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                business_day_id INTEGER NOT NULL REFERENCES business_days(id),
                shift_id INTEGER NOT NULL REFERENCES shifts(id),
                cashier_id INTEGER NOT NULL REFERENCES staff(id),
                token_number INTEGER NOT NULL,
                dining_type TEXT NOT NULL,
                subtotal REAL NOT NULL,
                grand_total REAL NOT NULL,
                payment_status TEXT NOT NULL,
                token_status TEXT NOT NULL DEFAULT 'PREPARING',
                created_at TEXT NOT NULL
              );
            ''');
          },
        ),
      );

      // Seed departments, staff, shift, and historical cash movements
      await v8Db.insert('departments', {'name': 'Front Counter', 'created_at': '2026-10-18'});
      final staffId = await v8Db.insert('staff', {
        'name': 'Cashier 1',
        'department_id': 1,
        'pin_hash': 'abc123hash',
        'role': 'CASHIER',
        'is_active': 1,
        'created_at': '2026-10-18',
      });
      final dayId = await v8Db.insert('business_days', {
        'opened_at': '2026-10-18 09:00:00',
        'opened_by_staff_id': staffId,
        'status': 'OPEN',
      });
      final shiftId = await v8Db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': staffId,
        'opened_at': '2026-10-18 09:05:00',
        'opening_float': 5000.0,
        'status': 'OPEN',
      });

      // Insert historical cash movements before migration
      await v8Db.insert('cash_movements', {
        'id': 101,
        'shift_id': shiftId,
        'staff_id': staffId,
        'type': 'PAY_IN',
        'amount': 2500.0,
        'category': 'Float Addition',
        'notes': 'Added morning change float',
        'created_at': '2026-10-18 09:10:00',
      });
      await v8Db.insert('cash_movements', {
        'id': 102,
        'shift_id': shiftId,
        'staff_id': staffId,
        'type': 'PAY_OUT',
        'amount': 500.0,
        'category': 'Petty Cash',
        'notes': 'Emergency milk purchase',
        'created_at': '2026-10-18 09:30:00',
      });

      await v8Db.close();

      // 2. Open using PosDatabase (which performs v9 upgrade and table rebuild)
      final upgradedPosDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: v8DbPath,
      );
      final upgradedDb = await upgradedPosDb.initialize();

      // Verify schema version is now 9
      final versionResult = await upgradedDb.rawQuery('PRAGMA user_version;');
      expect(versionResult.first.values.first, equals(9));

      // Verify historical rows are perfectly preserved
      final rows = await upgradedDb.query('cash_movements', orderBy: 'id ASC');
      expect(rows.length, equals(2));
      expect(rows[0]['id'], equals(101));
      expect(rows[0]['amount'], equals(2500.0));
      expect(rows[0]['approved_by'], isNull);
      expect(rows[1]['id'], equals(102));
      expect(rows[1]['amount'], equals(500.0));
      expect(rows[1]['approved_by'], isNull);

      // Verify nullable approved_by allows INSERT with NULL
      final newMovementNullApprover = await upgradedDb.insert('cash_movements', {
        'shift_id': shiftId,
        'staff_id': staffId,
        'type': 'PAY_OUT',
        'amount': 300.0,
        'category': 'Ice Bag',
        'notes': 'Ice delivery payment',
        'approved_by': null,
        'created_at': '2026-10-18 10:00:00',
      });
      expect(newMovementNullApprover, greaterThan(0));

      // Verify approved_by allows valid staff reference
      final newMovementWithApprover = await upgradedDb.insert('cash_movements', {
        'shift_id': shiftId,
        'staff_id': staffId,
        'type': 'PAY_IN',
        'amount': 1000.0,
        'category': 'Drawer Correction',
        'notes': 'Manager approved cash top-up',
        'approved_by': staffId,
        'created_at': '2026-10-18 10:15:00',
      });
      expect(newMovementWithApprover, greaterThan(0));

      await upgradedPosDb.close();
    });
  });
}
