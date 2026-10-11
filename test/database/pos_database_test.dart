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

  group('PosDatabase Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_db_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_pos.db';
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

    test('initializes SQLite database with WAL mode and foreign keys enabled', () async {
      final db = await posDb.initialize();

      // Verify WAL mode
      final journalModeResult = await db.rawQuery('PRAGMA journal_mode;');
      expect(
        journalModeResult.first.values.first.toString().toLowerCase(),
        equals('wal'),
      );

      // Verify Foreign Keys enabled
      final foreignKeysResult = await db.rawQuery('PRAGMA foreign_keys;');
      expect(
        foreignKeysResult.first.values.first,
        equals(1),
      );
    });

    test('creates core tables: departments, staff, and system_settings', () async {
      final db = await posDb.initialize();

      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tablesResult.map((row) => row['name'] as String).toList();

      expect(tableNames, contains('departments'));
      expect(tableNames, contains('staff'));
      expect(tableNames, contains('system_settings'));
    });

    test('seeds default departments: Front Counter, Kitchen, Management', () async {
      final db = await posDb.initialize();

      final departments = await db.query('departments', orderBy: 'id ASC');
      expect(departments.length, equals(3));

      final names = departments.map((d) => d['name']).toList();
      expect(names, containsAll(['Front Counter', 'Kitchen', 'Management']));
    });

    test('seeds initial Owner/Supervisor with valid 4-digit PIN hash', () async {
      final db = await posDb.initialize();

      final staffMembers = await db.query('staff');
      expect(staffMembers, isNotEmpty);

      final supervisor = staffMembers.firstWhere(
        (s) => s['role'] == 'SUPERVISOR' || s['role'] == 'OWNER',
      );
      expect(supervisor['name'], isNotNull);
      expect(supervisor['pin_hash'], isNotNull);
      expect((supervisor['pin_hash'] as String).length, equals(64)); // SHA-256 hash length
      expect(supervisor['is_active'], equals(1));
    });

    test('seeds default system settings and supports idempotent initialization', () async {
      final db = await posDb.initialize();

      final settings = await db.query('system_settings');
      expect(settings, isNotEmpty);

      // Running initialize again should not throw or duplicate default data
      await posDb.initialize();
      final departmentsAfter = await db.query('departments');
      expect(departmentsAfter.length, equals(3));
    });

    test('resolves default Windows %ProgramData% path correctly', () {
      final defaultPath = PosDatabase.resolveDefaultDatabasePath(
        environment: {'ProgramData': r'C:\ProgramData'},
        isWindows: true,
      );
      expect(defaultPath, equals(r'C:\ProgramData\ResturantPOS\data\pos.db'));
    });
  });
}
