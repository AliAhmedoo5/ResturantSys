import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import '../auth/auth_service.dart';
import '../catalog/catalog_media_service.dart';
import '../settings/managed_configuration.dart';
import 'database_backup_service.dart';
import 'pos_database.dart';
import 'pos_database_constants.dart';

class PreparedRestore {
  const PreparedRestore(this.directory, this.archiveName, this.schemaVersion, this.orderCount, this.mediaCount);
  final String directory, archiveName;
  final int schemaVersion, orderCount, mediaCount;
  Future<void> discard() async {
    if (await Directory(directory).exists()) await Directory(directory).delete(recursive: true);
  }
}

/// Validation is isolated from live data. Replacement happens on next startup,
/// before any database connection/controller/background sender is created.
class DatabaseRestoreService {
  DatabaseRestoreService({required this.auth, String? mediaPath})
      : mediaPath = mediaPath ?? CatalogMediaService.defaultBaseDirectoryPath();
  final AuthService auth;
  final String mediaPath;

  Future<void> _authorize() async {
    final actor = auth.session.currentStaff;
    if (actor == null) throw StateError('Sign in as a Manager before restoring.');
    await requireManager(auth.database, actor.id);
    if ((await auth.database.query('business_days', where: "status='OPEN'")).isNotEmpty ||
        (await auth.database.query('shifts', where: "status='OPEN'")).isNotEmpty) {
      throw StateError('Close all shifts and the Business Day before restoring.');
    }
  }

  Future<PreparedRestore> prepare(String archivePath) async {
    await _authorize();
    if (auth.database.path == inMemoryDatabasePath) throw StateError('Restoration requires a saved database.');
    final root = await Directory(p.join(p.dirname(auth.database.path), 'restore-staging')).create(recursive: true);
    final staging = await root.createTemp('preview-');
    try {
      final result = await Isolate.run(() => _extractAndValidate(archivePath, staging.path));
      // PIN fingerprints require the original installation's credential key.
      final candidate = sqlite.sqlite3.open(p.join(staging.path, 'pos.db'), mode: sqlite.OpenMode.readOnly);
      try {
        final checks = candidate.select("SELECT key_check FROM auth_security_state WHERE scope='key'");
        if (checks.isNotEmpty) {
          final key = await auth.keyStore.read(auth.database.path);
          if (key == null || Hmac(sha256, base64Url.decode(key)).convert(utf8.encode('restaurant-pin-key-v1')).toString() != checks.single['key_check']) {
            throw StateError('This backup needs its original Windows PIN credential store. Restore that store before importing this archive.');
          }
        }
      } finally { candidate.dispose(); }
      return result;
    } catch (_) {
      await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<String> schedule(PreparedRestore prepared) async {
    await _authorize();
    final actor = auth.session.currentStaff!;
    final request = File('${auth.database.path}.restore-request.json');
    if (await request.exists()) throw StateError('A restore is already scheduled. Restart the application.');
    final backup = await DatabaseBackupService(database: auth.database, catalogMediaDirectoryPath: mediaPath)
      .executeBackup(sourceDbPath: auth.database.path);
    if (!backup.success) throw StateError('Safety backup failed: ${backup.warningMessage}');
    await _authorize();
    await auth.database.transaction((txn) async {
      await requireManager(txn, actor.id);
      await auditConfiguration(txn, actor.id, 'RESTORE_SCHEDULED', {'database': auth.database.path},
        {'archive': prepared.archiveName, 'safety_backup': backup.localBackupPath});
    });
    final stagedDb = File(p.join(prepared.directory, 'pos.db'));
    final data = {'directory': prepared.directory, 'media_path': mediaPath,
      'database_sha256': (await sha256.bind(stagedDb.openRead()).first).toString(),
      'manager_id': actor.id, 'archive': prepared.archiveName,
      'safety_backup': backup.localBackupPath, 'scheduled_at': DateTime.now().toIso8601String()};
    final temporary = File('${request.path}.partial');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(request.path);
    return backup.localBackupPath!;
  }

  static Future<void> cancelPending(String databasePath) async {
    final request = File('$databasePath.restore-request.json');
    if (!await request.exists()) return;
    final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final journal = File(p.join(data['directory'] as String, 'journal.json'));
    if (await journal.exists()) throw StateError('Retry recovery first so an interrupted swap can be rolled back.');
    await request.rename('${request.path}.cancelled-${DateTime.now().microsecondsSinceEpoch}');
  }

  /// Called only before opening SQLite. A durable journal rolls an interrupted
  /// swap back on the next launch. Originals and safety ZIP are retained.
  static Future<String?> applyPending({required String databasePath}) async {
    final request = File('$databasePath.restore-request.json');
    if (!await request.exists()) return null;
    final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final stage = Directory(data['directory'] as String);
    final media = Directory(data['media_path'] as String);
    final journal = File(p.join(stage.path, 'journal.json'));
    final old = Directory(p.join(stage.path, 'original'));
    final live = File(databasePath);
    final staged = File(p.join(stage.path, 'pos.db'));
    Future<void> writeJournal(Map<String, Object?> state) async {
      final temporary = File('${journal.path}.partial');
      await temporary.writeAsString(jsonEncode(state), flush: true);
      await temporary.rename(journal.path);
    }
    Future<void> rollback(Map<String, dynamic> state) async {
      for (final suffix in ['', '-wal', '-shm']) {
        final saved = File(p.join(old.path, 'pos.db$suffix'));
        final target = File('$databasePath$suffix');
        if (await saved.exists()) {
          if (await target.exists()) await target.delete();
          await saved.rename(target.path);
        } else if (!(state['files'] as List).contains(suffix) && await target.exists()) {
          await target.delete();
        }
      }
      final savedMedia = Directory(p.join(old.path, 'media'));
      if (await savedMedia.exists()) {
        if (await media.exists()) await media.delete(recursive: true);
        await savedMedia.rename(media.path);
      } else if (state['had_media'] == false && await media.exists()) {
        await media.delete(recursive: true);
      }
    }
    if (await journal.exists()) {
      final state = jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      if (state['phase'] != 'APPLIED') {
        await rollback(state);
        await request.rename('${request.path}.failed-${DateTime.now().microsecondsSinceEpoch}');
        return 'An interrupted restoration was rolled back. Original restaurant records were retained.';
      }
      await request.rename('${request.path}.completed-${DateTime.now().microsecondsSinceEpoch}');
      return 'Backup restored successfully. Sign in with a Manager PIN from the restored backup.';
    }
    final digest = (await sha256.bind(staged.openRead()).first).toString();
    if (digest != data['database_sha256']) throw StateError('Staged restore database changed; live records were not replaced.');
    await Isolate.run(() => _validateDirectory(stage.path));
    await old.create();
    final state = <String, Object?>{'phase': 'APPLYING', 'had_media': await media.exists(),
      'files': [for (final suffix in ['', '-wal', '-shm']) if (await File('$databasePath$suffix').exists()) suffix]};
    await writeJournal(state);
    try {
      for (final suffix in state['files'] as List<String>) {
        await File('$databasePath$suffix').rename(p.join(old.path, 'pos.db$suffix'));
      }
      if (await media.exists()) await media.rename(p.join(old.path, 'media'));
      await staged.rename(live.path);
      await Directory(p.dirname(media.path)).create(recursive: true);
      await Directory(p.join(stage.path, 'catalog_media')).rename(media.path);
      final restored = PosDatabase(customPath: databasePath, seedDefaultStaff: false);
      try {
        final db = await restored.initialize();
        if ((await db.rawQuery('PRAGMA integrity_check')).single.values.single != 'ok' ||
            (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) throw StateError('Restored database verification failed.');
        await db.insert('configuration_audit', {'actor_id': (await db.rawQuery("SELECT id FROM staff WHERE role IN ('MANAGER','OWNER','SUPERVISOR') AND is_active=1 AND login_enabled=1 LIMIT 1")).single['id'],
          'kind': 'RESTORE_APPLIED', 'before_json': '{}', 'after_json': jsonEncode(data), 'created_at': DateTime.now().toIso8601String()});
      } finally { await restored.close(); }
      state['phase'] = 'APPLIED';
      await writeJournal(state);
    } catch (_) {
      await rollback(state);
      await request.rename('${request.path}.failed-${DateTime.now().microsecondsSinceEpoch}');
      rethrow;
    }
    await request.rename('${request.path}.completed-${DateTime.now().microsecondsSinceEpoch}');
    return 'Backup restored successfully. Sign in using the restored staff PINs. Safety backup: ${data['safety_backup']}';
  }
}

Future<PreparedRestore> _extractAndValidate(String archivePath, String directory) async {
  if (await File(archivePath).length() > 512 * 1024 * 1024) throw const FormatException('Backup ZIP exceeds the 512 MB import limit.');
  final bytes = await File(archivePath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final names = <String>{};
  var size = 0, mediaCount = 0;
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    final normalized = p.posix.normalize(name);
    if (p.posix.isAbsolute(name) || name.contains(':') || name.split('/').contains('..') ||
        name.split('/').where((part) => part.isNotEmpty).any((part) =>
          part.endsWith('.') || part.endsWith(' ') || RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', caseSensitive: false).hasMatch(part)) ||
        !names.add(normalized.toLowerCase()) ||
        (normalized != 'pos.db' && normalized != 'catalog_media' && !normalized.startsWith('catalog_media/'))) {
      throw const FormatException('Invalid, duplicate or unsafe backup archive path.');
    }
    // Unix file type bits: refuse symlinks and other special entries.
    final type = entry.mode & 0xF000;
    if (type != 0 && type != 0x8000 && type != 0x4000) throw const FormatException('Backup contains unsupported links.');
    size += entry.size;
    if (size > 2 * 1024 * 1024 * 1024 || archive.length > 100000) throw const FormatException('Backup exceeds restoration limits.');
    final target = p.joinAll([directory, ...normalized.split('/')]);
    if (entry.isFile) {
      await Directory(p.dirname(target)).create(recursive: true);
      await File(target).writeAsBytes(entry.content as List<int>, flush: true);
      if (normalized.startsWith('catalog_media/')) mediaCount++;
    } else { await Directory(target).create(recursive: true); }
  }
  await Directory(p.join(directory, 'catalog_media')).create(recursive: true);
  final result = await _validateDirectory(directory);
  return PreparedRestore(directory, p.basename(archivePath), result.$1, result.$2, mediaCount);
}

Future<(int, int)> _validateDirectory(String directory) async {
  sqfliteFfiInit();
  final path = p.join(directory, 'pos.db');
  if (!await File(path).exists()) throw const FormatException('Backup has no pos.db database.');
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  try {
    final version = db.select('PRAGMA user_version').single.values.single as int;
    if (version < 18 || version > PosDatabaseConstants.schemaVersion) throw const FormatException('Backup schema is unsupported by this application version.');
    if (db.select('PRAGMA integrity_check').single.values.single != 'ok' || db.select('PRAGMA foreign_key_check').isNotEmpty) throw const FormatException('Backup database failed integrity or foreign key checks.');
    if (db.select("SELECT id FROM staff WHERE role IN ('MANAGER','OWNER','SUPERVISOR') AND is_active=1 AND login_enabled=1").isEmpty) throw const FormatException('Backup has no active Manager login.');
    for (final row in db.select('SELECT relative_file_path,thumbnail_path,byte_count,sha256_checksum FROM catalog_images')) {
      for (final column in ['relative_file_path', 'thumbnail_path']) {
        final relative = row[column] as String?;
        if (relative == null || relative.isEmpty) continue;
        final normalized = relative.replaceAll('\\', '/');
        if (p.posix.isAbsolute(normalized) || normalized.contains(':') || normalized.split('/').contains('..')) throw const FormatException('Unsafe catalog photo reference.');
        final file = File(p.joinAll([directory, 'catalog_media', ...normalized.split('/')]));
        if (!await file.exists()) throw const FormatException('Backup is missing a referenced catalog photo.');
        if (column == 'relative_file_path') {
          if (row['byte_count'] != null && await file.length() != row['byte_count']) throw const FormatException('Catalog photo size mismatch.');
          final checksum = row['sha256_checksum'] as String?;
          if (checksum != null && checksum.isNotEmpty && (await sha256.bind(file.openRead()).first).toString() != checksum) throw const FormatException('Catalog photo checksum mismatch.');
        }
      }
    }
    return (version, db.select('SELECT COUNT(*) AS n FROM orders').single['n'] as int);
  } finally { db.dispose(); }
}
