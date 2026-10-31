import 'dart:math';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:archive/archive_io.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
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

    test('restores catalog photos and empty media directories beside the snapshot', () async {
      final media = Directory('${tempRootDir.path}/media');
      await Directory('${media.path}/menu_items/7').create(recursive: true);
      await Directory('${media.path}/empty-gallery').create();
      await File('${media.path}/menu_items/7/burger.jpg').writeAsBytes([1, 7, 9, 23]);
      final service = DatabaseBackupService(
        database: db, catalogMediaDirectoryPath: media.path,
      );
      final result = await service.executeBackup(
        sourceDbPath: sourceDbPath, localBackupDir: localBackupDir.path,
      );
      expect(result.success, isTrue, reason: result.warningMessage);
      final restored = Directory('${tempRootDir.path}/media-restored');
      await extractFileToDisk(result.localBackupPath!, restored.path);
      expect(await File('${restored.path}/catalog_media/menu_items/7/burger.jpg').readAsBytes(), [1, 7, 9, 23]);
      expect(await Directory('${restored.path}/catalog_media/empty-gallery').exists(), isTrue);
      final restoredDb = await databaseFactoryFfi.openDatabase('${restored.path}/pos.db');
      try {
        expect(await restoredDb.query('sample'), [{'id': 1, 'note': 'Active POS Record'}]);
        expect((await restoredDb.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
      } finally {
        await restoredDb.close();
      }
    });
    test('uses the Manager saved primary backup directory without an override', () async {
      final configured = Directory('${tempRootDir.path}/manager-primary');
      await db.execute('CREATE TABLE system_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)');
      await db.insert('system_settings', {
        'key': PosDatabaseConstants.settingLocalBackupPath,
        'value': configured.path,
        'updated_at': '2026-10-23 18:00:00',
      });
      final result = await backupService.executeBackup(sourceDbPath: sourceDbPath);
      try {
        expect(result.success, isTrue, reason: result.warningMessage);
        expect(
          await File(result.localBackupPath!).parent.resolveSymbolicLinks(),
          await configured.resolveSymbolicLinks(),
        );
        expect(await File(result.localBackupPath!).exists(), isTrue);
      } finally {
        // The pre-implementation default is outside this test's temporary root.
        if (result.localBackupPath != null) await File(result.localBackupPath!).delete();
      }
    });
    test('publishes only media archives matching the database photo references', () async {
      final media = Directory('${tempRootDir.path}/checked-media');
      await media.create();
      await db.execute('CREATE TABLE catalog_images (id INTEGER PRIMARY KEY, relative_file_path TEXT, thumbnail_path TEXT, byte_count INTEGER, sha256_checksum TEXT)');
      await db.insert('catalog_images', {
        'relative_file_path': 'burger.jpg',
        'byte_count': 4,
        'sha256_checksum': '81e817df8a9c046e994d4f881f8b98812e49af97b24bc6bd4e2aededf2c40518',
      });
      final service = DatabaseBackupService(database: db, catalogMediaDirectoryPath: media.path);
      Future<BackupResult> backup() => service.executeBackup(
        sourceDbPath: sourceDbPath, localBackupDir: localBackupDir.path,
      );
      final missing = await backup();
      expect(missing.success, isFalse, reason: 'A database reference must not survive without its photo.');
      expect(await localBackupDir.list().toList(), isEmpty);

      await File('${media.path}/burger.jpg').writeAsBytes([9, 9, 9, 9]);
      final changed = await backup();
      expect(changed.success, isFalse, reason: 'Changed photo bytes cannot satisfy the snapshot checksum.');
      expect(await localBackupDir.list().toList(), isEmpty);

      await File('${media.path}/burger.jpg').writeAsBytes([1, 7, 9, 23]);
      final repaired = await backup();
      expect(repaired.success, isTrue, reason: repaired.warningMessage);
      final restored = Directory('${tempRootDir.path}/verified-media');
      await extractFileToDisk(repaired.localBackupPath!, restored.path);
      expect(await File('${restored.path}/catalog_media/burger.jpg').readAsBytes(), [1, 7, 9, 23]);
    });
    test('keeps distinct recoverable snapshots while billing writes to a pinned WAL', () async {
      await db.execute('PRAGMA journal_mode = WAL');
      await db.execute('PRAGMA wal_autocheckpoint = 0');
      await db.execute('CREATE TABLE billing_ledger (sale INTEGER, amount INTEGER)');
      Future<void> bill(int sale) => db.transaction((txn) async {
        await txn.insert('billing_ledger', {'sale': sale, 'amount': 12500});
        await txn.insert('billing_ledger', {'sale': sale, 'amount': -12500});
      });
      await bill(1);
      final reader = sqlite.sqlite3.open(sourceDbPath, mode: sqlite.OpenMode.readOnly);
      reader.execute('BEGIN');
      reader.select('SELECT * FROM sample');
      try {
        await bill(2);
        await db.insert('sample', {'note': 'Committed only in WAL'});
        expect(reader.select("SELECT * FROM sample WHERE note = 'Committed only in WAL'"), isEmpty);
        final media = Directory('${tempRootDir.path}/billing-media');
        await media.create();
        final random = Random(24);
        await File('${media.path}/photo.jpg').writeAsBytes(
          List<int>.generate(4 * 1024 * 1024, (_) => random.nextInt(256)),
        );
        final service = DatabaseBackupService(database: db, catalogMediaDirectoryPath: media.path);
        final stamp = DateTime(2026, 10, 23, 20);
        var completedBackups = 0;
        Future<BackupResult> start() => service.executeBackup(
          sourceDbPath: sourceDbPath, localBackupDir: localBackupDir.path, timestamp: stamp,
        ).then((result) {
          completedBackups++;
          return result;
        });
        final first = start();
        final second = start();
        var concurrentCommits = 0;
        Future<void> keepBilling() async {
          for (var sale = 3; sale <= 42; sale++) {
            await bill(sale);
            if (completedBackups < 2) concurrentCommits++;
          }
        }
        await keepBilling().timeout(const Duration(seconds: 30));
        final results = await Future.wait([first, second]).timeout(const Duration(seconds: 30));
        expect(concurrentCommits, greaterThan(0));
        expect(results.every((result) => result.success), isTrue,
          reason: results.map((result) => result.warningMessage).join('; '));
        expect(results[0].localBackupPath, isNot(results[1].localBackupPath));
        for (var index = 0; index < results.length; index++) {
          final restored = Directory('${tempRootDir.path}/wal-restored-$index');
          await extractFileToDisk(results[index].localBackupPath!, restored.path);
          final recovered = await databaseFactoryFfi.openDatabase('${restored.path}/pos.db');
          try {
            expect((await recovered.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
            expect(await recovered.rawQuery('PRAGMA foreign_key_check'), isEmpty);
            expect(await recovered.query('sample', where: 'note = ?', whereArgs: ['Committed only in WAL']), hasLength(1));
            final ledger = await recovered.rawQuery('SELECT sale, COUNT(*) AS entries, SUM(amount) AS balance FROM billing_ledger GROUP BY sale');
            expect(ledger.length, greaterThanOrEqualTo(2));
            for (final sale in ledger) {
              expect(sale['entries'], 2);
              expect(sale['balance'], 0);
            }
          } finally {
            await recovered.close();
          }
        }
        final retained = File(results.first.localBackupPath!);
        final retainedBytes = await retained.readAsBytes();
        final blocked = File('${tempRootDir.path}/blocked-primary');
        await blocked.writeAsString('This is a file, not a backup directory.');
        final failed = await service.executeBackup(sourceDbPath: sourceDbPath, localBackupDir: blocked.path);
        expect(failed.success, isFalse);
        expect(failed.localBackupPath, isNull);
        expect(await retained.readAsBytes(), retainedBytes);
      } finally {
        reader.execute('ROLLBACK');
        reader.dispose();
      }
    });
    test('rejects backup destinations aliased into catalog media before creating files', () async {
      final media = Directory('${tempRootDir.path}/physical-media');
      await media.create();
      final sourceAlias = Link('${tempRootDir.path}/source-media-alias');
      final targetAlias = Link('${tempRootDir.path}/backup-media-alias');
      try {
        await sourceAlias.create(media.path);
        await targetAlias.create(tempRootDir.path);
      } on FileSystemException catch (error) {
        if (Platform.isWindows && error.osError?.errorCode == 1314) {
          markTestSkipped('Windows runner lacks the symbolic-link creation privilege.');
          return;
        }
        rethrow;
      }
      final directSource = DatabaseBackupService(database: db, catalogMediaDirectoryPath: media.path);
      final aliasedTarget = await directSource.executeBackup(
        sourceDbPath: sourceDbPath, localBackupDir: '${targetAlias.path}/physical-media/new-primary',
      );
      expect(aliasedTarget.success, isFalse);
      expect(aliasedTarget.warningMessage, contains('outside catalog media'));
      expect(await media.list(followLinks: false).toList(), isEmpty);

      final aliasedSource = DatabaseBackupService(database: db, catalogMediaDirectoryPath: sourceAlias.path);
      final directTarget = await aliasedSource.executeBackup(
        sourceDbPath: sourceDbPath, localBackupDir: '${media.path}/another-primary',
      );
      expect(directTarget.success, isFalse);
      expect(directTarget.warningMessage, contains('outside catalog media'));
      expect(await media.list(followLinks: false).toList(), isEmpty);

      final secondary = await aliasedSource.executeBackup(
        sourceDbPath: sourceDbPath, localBackupDir: localBackupDir.path,
        secondaryBackupDir: '${targetAlias.path}/physical-media/new-secondary',
      );
      expect(secondary.success, isTrue, reason: secondary.warningMessage);
      expect(await File(secondary.localBackupPath!).exists(), isTrue);
      expect(secondary.secondaryBackupPath, isNull);
      expect(secondary.warningMessage, contains('outside catalog media'));
      expect(await media.list(followLinks: false).toList(), isEmpty);
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
      expect(result.localBackupPath, matches(r'pos_backup_20261015_233045_.*\.zip' r'$'));

      final localFile = File(result.localBackupPath!);
      expect(await localFile.exists(), isTrue);
      expect(await localFile.length(), greaterThan(0));
      final archive = ZipDecoder().decodeBytes(await localFile.readAsBytes());
      expect(archive.findFile('catalog_media/'), isNotNull);
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
      expect(await secondaryFile.readAsBytes(), await localFile.readAsBytes());
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
      final restoredDirectory = Directory('${tempRootDir.path}/restored');
      await extractFileToDisk(backupResult.localBackupPath!, restoredDirectory.path);
      final restoredDb = await databaseFactoryFfi.openDatabase('${restoredDirectory.path}/pos.db');
      
      final versionResult = await restoredDb.rawQuery('PRAGMA user_version;');
      expect(versionResult.first.values.first, equals(PosDatabaseConstants.schemaVersion));

      final integrityResult = await restoredDb.rawQuery('PRAGMA integrity_check;');
      expect(integrityResult.first.values.first, equals('ok'));
      expect(await restoredDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);

      final areas = await restoredDb.query('delivery_areas');
      expect(areas.length, equals(1));
      expect(areas.first['name'], equals('DHA Phase 5'));
      expect(areas.first['delivery_fee_paisa'], equals(20000));

      await restoredDb.close();
    });
  });
}
