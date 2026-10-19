import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/database_backup_service.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseBackupService Dual-Target Automated Backup Tests', () {
    late Directory tempRootDir;
    late Directory localBackupDir;
    late Directory secondaryBackupDir;
    late String sourceDbPath;
    late Database db;
    late DatabaseBackupService backupService;

    setUp(() async {
      tempRootDir = await Directory.systemTemp.createTemp('pos_backup_test_');
      localBackupDir = Directory('${tempRootDir.path}${Platform.pathSeparator}local_backups');
      await localBackupDir.create(recursive: true);

      secondaryBackupDir = Directory('${tempRootDir.path}${Platform.pathSeparator}usb_drive_backups');
      await secondaryBackupDir.create(recursive: true);

      sourceDbPath = '${tempRootDir.path}${Platform.pathSeparator}pos_source.db';
      db = await databaseFactoryFfi.openDatabase(sourceDbPath);
      await db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, note TEXT);');
      await db.insert('sample', {'note': 'Active POS Record'});

      backupService = DatabaseBackupService(database: db);
    });

    tearDown(() async {
      await db.close();
      if (await tempRootDir.exists()) {
        await tempRootDir.delete(recursive: true);
      }
    });

    test('creates timestamped backup in local folder', () async {
      final now = DateTime(2026, 10, 15, 23, 30, 45);
      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        timestamp: now,
      );

      expect(result.success, isTrue);
      expect(result.localBackupPath, isNotNull);
      expect(result.localBackupPath, contains('pos_backup_20261015_233045.db'));

      final localFile = File(result.localBackupPath!);
      expect(await localFile.exists(), isTrue);
      expect(await localFile.length(), greaterThan(0));
    });

    test('copies backup to both local and secondary USB drive targets when configured', () async {
      final now = DateTime(2026, 10, 15, 23, 40, 10);
      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        secondaryBackupDir: secondaryBackupDir.path,
        timestamp: now,
      );

      expect(result.success, isTrue);
      expect(result.localBackupPath, isNotNull);
      expect(result.secondaryBackupPath, isNotNull);

      final localFile = File(result.localBackupPath!);
      final secondaryFile = File(result.secondaryBackupPath!);

      expect(await localFile.exists(), isTrue);
      expect(await secondaryFile.exists(), isTrue);
      expect(await localFile.length(), equals(await secondaryFile.length()));
    });

    test('gracefully completes local backup with warning if secondary drive is disconnected', () async {
      final now = DateTime(2026, 10, 15, 23, 45, 0);
      final nonExistentPath = '${tempRootDir.path}${Platform.pathSeparator}missing_usb_root${Platform.pathSeparator}unreachable';

      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        secondaryBackupDir: nonExistentPath,
        timestamp: now,
      );

      expect(result.success, isTrue);
      expect(result.localBackupPath, isNotNull);
      expect(await File(result.localBackupPath!).exists(), isTrue);
      expect(result.secondaryBackupPath, isNull);
      expect(result.warningMessage, isNotNull);
      expect(result.warningMessage, contains('Secondary backup target unreachable'));
    });

    test('uses secondary backup path configured in system_settings if secondaryBackupDir parameter is null', () async {
      await db.execute('''
        CREATE TABLE system_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
      ''');
      await db.insert('system_settings', {
        'key': 'secondary_backup_path',
        'value': secondaryBackupDir.path,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final now = DateTime(2026, 10, 15, 23, 50, 0);
      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        timestamp: now,
      );

      expect(result.success, isTrue);
      expect(result.localBackupPath, isNotNull);
      expect(result.secondaryBackupPath, isNotNull);
      expect(await File(result.secondaryBackupPath!).exists(), isTrue);
    });

    test('verifies schema v9 integrity upon backup and restore', () async {
      final v9DbPath = '${tempRootDir.path}${Platform.pathSeparator}pos_v9_source.db';
      final posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: v9DbPath,
      );
      final activeV9Db = await posDb.initialize();

      // Insert sample record into v9 delivery_areas
      await activeV9Db.insert('delivery_areas', {
        'name': 'DHA Phase 5',
        'code': 'DHA5',
        'delivery_fee_paisa': 20000,
        'min_order_paisa': 100000,
        'is_active': 1,
        'created_at': '2026-10-18 12:00:00',
        'updated_at': '2026-10-18 12:00:00',
      });

      final backupServiceV9 = DatabaseBackupService(database: activeV9Db);
      final backupResult = await backupServiceV9.executeBackup(
        sourceDbPath: v9DbPath,
        localBackupDir: localBackupDir.path,
        timestamp: DateTime(2026, 10, 18, 12, 30, 0),
      );

      expect(backupResult.success, isTrue);
      expect(backupResult.localBackupPath, isNotNull);

      await posDb.close();

      // Open the restored backup file directly and verify schema version & tables
      final restoredDb = await databaseFactoryFfi.openDatabase(backupResult.localBackupPath!);
      
      final versionResult = await restoredDb.rawQuery('PRAGMA user_version;');
      expect(versionResult.first.values.first, equals(PosDatabaseConstants.schemaVersion));

      final integrityResult = await restoredDb.rawQuery('PRAGMA integrity_check;');
      expect(integrityResult.first.values.first, equals('ok'));

      final areas = await restoredDb.query('delivery_areas');
      expect(areas.length, equals(1));
      expect(areas.first['name'], equals('DHA Phase 5'));
      expect(areas.first['delivery_fee_paisa'], equals(20000));

      await restoredDb.close();
    });
  });
}

