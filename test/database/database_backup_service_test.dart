import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/database_backup_service.dart';

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
  });
}
