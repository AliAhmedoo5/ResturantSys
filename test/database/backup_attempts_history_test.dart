import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/backup_attempts_schema.dart';
import 'package:resturant_sys/core/database/database_backup_service.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Ticket #85: Persist verified backup attempts and health history', () {
    late Directory tempRootDir;
    late Directory localBackupDir;
    late Directory secondaryBackupDir;
    late String sourceDbPath;
    late Database db;
    late DatabaseBackupService backupService;

    setUp(() async {
      tempRootDir = await Directory.systemTemp.createTemp('backup_attempts_test_');
      localBackupDir = Directory('${tempRootDir.path}${Platform.pathSeparator}local_backups');
      await localBackupDir.create(recursive: true);

      secondaryBackupDir = Directory('${tempRootDir.path}${Platform.pathSeparator}secondary_backups');
      await secondaryBackupDir.create(recursive: true);

      sourceDbPath = '${tempRootDir.path}${Platform.pathSeparator}pos_source.db';
      db = await databaseFactoryFfi.openDatabase(sourceDbPath);
      await db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, note TEXT);');
      await db.insert('sample', {'note': 'Active POS Record'});

      // Initialize backup_attempts schema
      await createBackupAttemptsSchema(db);

      backupService = DatabaseBackupService(database: db);
    });

    tearDown(() async {
      await db.close();
      if (await tempRootDir.exists()) {
        await tempRootDir.delete(recursive: true);
      }
    });

    test('backup_attempts table enforces immutable triggers against UPDATE and DELETE', () async {
      await db.insert('backup_attempts', {
        'attempted_at': '2026-10-30T10:00:00.000Z',
        'initiator': 'MANUAL',
        'manager_id': 1,
        'primary_status': 'SUCCESS',
        'primary_path': '/path/to/backup.zip',
        'secondary_status': 'NOT_CONFIGURED',
        'verification_status': 'VERIFIED',
        'failure_category': 'NONE',
        'created_at': '2026-10-30T10:00:01.000Z',
      });

      final rows = await db.query('backup_attempts');
      expect(rows, hasLength(1));
      final id = rows.first['id'] as int;

      // UPDATE must fail with constraint / trigger abort
      expect(
        () => db.update('backup_attempts', {'primary_status': 'FAILED'}, where: 'id = ?', whereArgs: [id]),
        throwsA(isA<DatabaseException>()),
      );

      // DELETE must fail with constraint / trigger abort
      expect(
        () => db.delete('backup_attempts', where: 'id = ?', whereArgs: [id]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('records verified manual backup attempt with primary success and target-specific outcomes', () async {
      final now = DateTime(2026, 10, 30, 14, 0, 0);
      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        timestamp: now,
        initiator: 'MANUAL',
        managerId: 42,
      );

      expect(result.success, isTrue, reason: result.warningMessage);
      expect(result.primaryStatus, 'SUCCESS');
      expect(result.secondaryStatus, 'NOT_CONFIGURED');
      expect(result.verificationStatus, 'VERIFIED');
      expect(result.failureCategory, 'NONE');

      final attempts = await db.query('backup_attempts');
      expect(attempts, hasLength(1));
      final row = attempts.first;
      expect(row['initiator'], 'MANUAL');
      expect(row['manager_id'], 42);
      expect(row['primary_status'], 'SUCCESS');
      expect(row['primary_path'], result.localBackupPath);
      expect(row['secondary_status'], 'NOT_CONFIGURED');
      expect(row['secondary_path'], isNull);
      expect(row['verification_status'], 'VERIFIED');
      expect(row['failure_category'], 'NONE');
    });

    test('records dual-target backup attempt with secondary success', () async {
      final now = DateTime(2026, 10, 30, 14, 30, 0);
      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        secondaryBackupDir: secondaryBackupDir.path,
        timestamp: now,
        initiator: 'SCHEDULED',
      );

      expect(result.success, isTrue);
      expect(result.primaryStatus, 'SUCCESS');
      expect(result.secondaryStatus, 'SUCCESS');
      expect(result.verificationStatus, 'VERIFIED');

      final attempts = await db.query('backup_attempts');
      expect(attempts, hasLength(1));
      final row = attempts.first;
      expect(row['initiator'], 'SCHEDULED');
      expect(row['manager_id'], isNull);
      expect(row['primary_status'], 'SUCCESS');
      expect(row['secondary_status'], 'SUCCESS');
      expect(row['secondary_path'], result.secondaryBackupPath);
      expect(row['verification_status'], 'VERIFIED');
      expect(row['failure_category'], 'NONE');
    });

    test('records secondary warning without invalidating primary success when secondary target is unreachable', () async {
      final now = DateTime(2026, 10, 30, 15, 0, 0);
      final unreachableDir = '${tempRootDir.path}${Platform.pathSeparator}missing_drive${Platform.pathSeparator}sub';
      final result = await backupService.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        secondaryBackupDir: unreachableDir,
        timestamp: now,
        initiator: 'MANUAL',
        managerId: 1,
      );

      expect(result.success, isTrue);
      expect(result.primaryStatus, 'SUCCESS');
      expect(result.secondaryStatus, 'WARNING');
      expect(result.verificationStatus, 'VERIFIED');
      expect(result.warningMessage, contains('Secondary backup target unreachable'));

      final attempts = await db.query('backup_attempts');
      expect(attempts, hasLength(1));
      final row = attempts.first;
      expect(row['primary_status'], 'SUCCESS');
      expect(row['secondary_status'], 'WARNING');
      expect(row['secondary_path'], isNull);
      expect(row['verification_status'], 'VERIFIED');
      expect(row['failure_category'], 'STORAGE_UNAVAILABLE');
      expect(row['failure_message'], contains('unreachable'));
    });

    test('preserves failed backup attempt with safe failure category when destination is invalid', () async {
      final media = Directory('${tempRootDir.path}/media');
      await media.create();
      final serviceWithMedia = DatabaseBackupService(database: db, catalogMediaDirectoryPath: media.path);

      final result = await serviceWithMedia.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: '${media.path}/inside_media',
        initiator: 'MANUAL',
        managerId: 10,
      );

      expect(result.success, isFalse);
      expect(result.primaryStatus, 'FAILED');
      expect(result.verificationStatus, 'FAILED');
      expect(result.failureCategory, 'DESTINATION_INVALID');

      final attempts = await db.query('backup_attempts');
      expect(attempts, hasLength(1));
      final row = attempts.first;
      expect(row['initiator'], 'MANUAL');
      expect(row['manager_id'], 10);
      expect(row['primary_status'], 'FAILED');
      expect(row['verification_status'], 'FAILED');
      expect(row['failure_category'], 'DESTINATION_INVALID');
      expect(row['failure_message'], contains('outside catalog media'));
    });

    test('preserves failed backup attempt with safe failure category when catalog photo reference is missing', () async {
      final media = Directory('${tempRootDir.path}/media_missing');
      await media.create();
      await db.execute('CREATE TABLE catalog_images (id INTEGER PRIMARY KEY, relative_file_path TEXT, thumbnail_path TEXT, byte_count INTEGER, sha256_checksum TEXT)');
      await db.insert('catalog_images', {
        'relative_file_path': 'nonexistent.jpg',
        'byte_count': 100,
        'sha256_checksum': 'abc',
      });

      final serviceWithMissingMedia = DatabaseBackupService(database: db, catalogMediaDirectoryPath: media.path);
      final result = await serviceWithMissingMedia.executeBackup(
        sourceDbPath: sourceDbPath,
        localBackupDir: localBackupDir.path,
        initiator: 'MANUAL',
        managerId: 7,
      );

      expect(result.success, isFalse);
      expect(result.primaryStatus, 'FAILED');
      expect(result.verificationStatus, 'FAILED');
      expect(result.failureCategory, 'MEDIA_CORRUPTED');

      final attempts = await db.query('backup_attempts');
      expect(attempts, hasLength(1));
      final row = attempts.first;
      expect(row['primary_status'], 'FAILED');
      expect(row['verification_status'], 'FAILED');
      expect(row['failure_category'], 'MEDIA_CORRUPTED');
      expect(row['failure_message'], contains('Referenced catalog photo is missing'));
    });

    test('finalizeBusinessDayWithZReport records automated backup attempt with initiator Z_CLOSE and manager ID', () async {
      await db.close();

      // Initialize full PosDatabase
      final posDbPath = '${tempRootDir.path}${Platform.pathSeparator}pos_full.db';
      final posDb = PosDatabase(factory: databaseFactoryFfi, customPath: posDbPath);
      final fullDb = await posDb.initialize();

      try {
        final shiftController = ShiftAndCashController(database: fullDb);
        await shiftController.openBusinessDay(openedByStaffId: 1);

        // Open and close a shift so Z-close succeeds
        final shift = await shiftController.openShift(
          staffId: 2,
          openingFloat: 500.0,
        );
        await shiftController.closeShift(
          shiftId: shift.id,
          staffId: 2,
          countedCash: 500.0,
        );

        final localDir = Directory('${tempRootDir.path}${Platform.pathSeparator}z_close_backups');
        await localDir.create();
        await fullDb.insert('system_settings', {
          'key': PosDatabaseConstants.settingLocalBackupPath,
          'value': localDir.path,
          'updated_at': DateTime.now().toIso8601String(),
        });

        await shiftController.finalizeBusinessDayWithZReport(
          closedByStaffId: 1,
          sourceDbPath: posDbPath,
        );

        final attempts = await fullDb.query('backup_attempts');
        expect(attempts, isNotEmpty);
        final zAttempt = attempts.firstWhere((a) => a['initiator'] == 'Z_CLOSE');
        expect(zAttempt['manager_id'], 1);
        expect(zAttempt['primary_status'], 'SUCCESS');
        expect(zAttempt['verification_status'], 'VERIFIED');
      } finally {
        await posDb.close();
      }
    });

    test('distinguishes configured backup directories from verified success when no attempt has run', () async {
      await db.execute('CREATE TABLE IF NOT EXISTS system_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)');
      await db.insert('system_settings', {
        'key': PosDatabaseConstants.settingLocalBackupPath,
        'value': '/configured/local/path',
        'updated_at': '2026-10-30 08:00:00',
      });
      await db.insert('system_settings', {
        'key': PosDatabaseConstants.settingSecondaryBackupPath,
        'value': '/configured/secondary/path',
        'updated_at': '2026-10-30 08:00:00',
      });

      // Settings exist, but backup_attempts table is empty
      final attempts = await db.query('backup_attempts');
      expect(attempts, isEmpty);
      // Configured settings alone do not constitute verified success
      final verifiedCount = ((await db.rawQuery(
        "SELECT COUNT(*) FROM backup_attempts WHERE verification_status = 'VERIFIED' AND primary_status = 'SUCCESS'",
      )).first.values.first as num).toInt();
      expect(verifiedCount, 0);
    });

    test('does not infer historical backup success from existing zip files on disk without durable database records', () async {
      // Simulate an unrecorded old ZIP archive placed directly in the backup directory
      final orphanZip = File('${localBackupDir.path}/pos_backup_20261001_120000_orphan.zip');
      await orphanZip.writeAsBytes([1, 2, 3, 4, 5]);

      // Database has no backup_attempts row for this orphan archive
      final attempts = await db.query('backup_attempts');
      expect(attempts, isEmpty);

      // Verify that durable health lookup yields no verified successes
      final verifiedCount = ((await db.rawQuery(
        "SELECT COUNT(*) FROM backup_attempts WHERE verification_status = 'VERIFIED' AND primary_status = 'SUCCESS'",
      )).first.values.first as num).toInt();
      expect(verifiedCount, 0);
    });
  });
}
