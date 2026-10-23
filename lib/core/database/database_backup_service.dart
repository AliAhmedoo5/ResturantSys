import 'dart:isolate';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../catalog/catalog_media_service.dart';
import 'pos_database_constants.dart';

/// Result record of an automated or manual database backup execution.
class BackupResult {
  const BackupResult({
    required this.success,
    this.localBackupPath,
    this.secondaryBackupPath,
    this.warningMessage,
    required this.timestamp,
  });

  final bool success;
  final String? localBackupPath;
  final String? secondaryBackupPath;
  final String? warningMessage;
  final DateTime timestamp;
}

/// Creates independent SQLite snapshots without queuing compression on billing.
class DatabaseBackupService {
  DatabaseBackupService({this.database, this.catalogMediaDirectoryPath});

  final Database? database;
  final String? catalogMediaDirectoryPath;

  static String resolveDefaultLocalBackupDir({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final env = environment ?? Platform.environment;
    if (isWindows ?? Platform.isWindows) {
      final programData = env['ProgramData'] ?? r'C:\ProgramData';
      return '$programData\\${PosDatabaseConstants.defaultProgramDataFolder}\\${PosDatabaseConstants.defaultBackupsSubFolder}';
    }
    return p.join(env['HOME'] ?? '.', '.resturant_pos',
        PosDatabaseConstants.defaultBackupsSubFolder);
  }

  Future<BackupResult> executeBackup({
    required String sourceDbPath,
    String? localBackupDir,
    String? secondaryBackupDir,
    DateTime? timestamp,
  }) {
    final effectiveTime = timestamp ?? DateTime.now();
    // Only send values to the worker, never the live sqflite connection.
    final mediaPath = catalogMediaDirectoryPath ?? CatalogMediaService.defaultBaseDirectoryPath();
    final requireMedia = catalogMediaDirectoryPath != null;
    return Isolate.run(() => _createBackup(
          sourceDbPath, localBackupDir,
          secondaryBackupDir, effectiveTime, mediaPath, requireMedia,
        ));
  }
}

Future<BackupResult> _createBackup(String sourcePath, String? localDirectory,
    String? secondaryDirectory, DateTime timestamp, String mediaPath, bool requireMedia) async {
  Directory? staging;
  sqlite.Database? source;
  try {
    if (!await File(sourcePath).exists()) {
      throw FileSystemException('Source database file not found', sourcePath);
    }
    // Configures the same native library loader used by the desktop app.
    sqfliteFfiInit();
    source = sqlite.sqlite3.open(sourcePath, mode: sqlite.OpenMode.readWrite);
    source.execute('PRAGMA busy_timeout = 0');
    source.select('PRAGMA wal_checkpoint(PASSIVE)');

    if (source.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'system_settings'").isNotEmpty) {
      final settings = source.select('SELECT key, value FROM system_settings WHERE key IN (?, ?)',
          [PosDatabaseConstants.settingLocalBackupPath, PosDatabaseConstants.settingSecondaryBackupPath]);
      for (final row in settings) {
        if (row['key'] == PosDatabaseConstants.settingLocalBackupPath) {
          localDirectory ??= row['value'] as String?;
        } else {
          secondaryDirectory ??= row['value'] as String?;
        }
      }
    }
    final cleanLocal = localDirectory?.trim();
    final local = Directory(cleanLocal == null || cleanLocal.isEmpty
        ? DatabaseBackupService.resolveDefaultLocalBackupDir() : cleanLocal);
    final mediaRoot = p.normalize(p.absolute(mediaPath));
    final primaryRoot = p.normalize(p.absolute(local.path));
    if (p.equals(mediaRoot, primaryRoot) || p.isWithin(mediaRoot, primaryRoot)) {
      throw FileSystemException('Backup directory must be outside catalog media', local.path);
    }
    await local.create(recursive: true);
    staging = await local.createTemp('.backup-');
    final snapshotPath = p.join(staging.path, 'pos.db');
    final snapshot = sqlite.sqlite3.open(snapshotPath);
    final references = <Map<String, Object?>>[];
    try {
      await source.backup(snapshot, nPage: 64).drain<void>();
      if (snapshot.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'catalog_images'").isNotEmpty) {
        for (final row in snapshot.select('SELECT relative_file_path, thumbnail_path, byte_count, sha256_checksum FROM catalog_images')) {
          references.add({
            'path': row['relative_file_path'],
            'thumbnail': row['thumbnail_path'],
            'bytes': row['byte_count'],
            'checksum': row['sha256_checksum'],
          });
        }
      }
    } finally {
      snapshot.dispose();
    }
    source.dispose();
    source = null;

    final stagedMedia = await _stageCatalogMedia(
        mediaPath, staging.path, requireMedia, references);

    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${timestamp.year}${two(timestamp.month)}${two(timestamp.day)}_'
        '${two(timestamp.hour)}${two(timestamp.minute)}${two(timestamp.second)}';
    final unique = p.basename(staging.path).substring('.backup-'.length);
    final name = 'pos_backup_${stamp}_$unique.zip';
    final pending = p.join(staging.path, name);
    final encoder = ZipFileEncoder();
    encoder.create(pending);
    try {
      await encoder.addFile(File(snapshotPath), 'pos.db');
      encoder.addArchiveFile(ArchiveFile('catalog_media/', 0, <int>[])..isFile = false);
      await for (final entity in stagedMedia.list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: stagedMedia.path).split(p.separator).join('/');
        final name = 'catalog_media/$relative';
        if (entity is File) {
          await encoder.addFile(entity, name);
        } else if (entity is Directory) {
          encoder.addArchiveFile(ArchiveFile('$name/', 0, <int>[])..isFile = false);
        }
      }
    } finally {
      await encoder.close();
    }
    final primaryPath = p.join(local.path, name);
    await File(pending).rename(primaryPath);

    String? secondaryPath;
    String? warning;
    if (secondaryDirectory != null && secondaryDirectory.trim().isNotEmpty) {
      final secondary = Directory(secondaryDirectory.trim());
      String? secondaryPending;
      try {
        final secondaryRoot = p.normalize(p.absolute(secondary.path));
        if (p.equals(mediaRoot, secondaryRoot) || p.isWithin(mediaRoot, secondaryRoot)) {
          throw FileSystemException('Secondary backup directory must be outside catalog media', secondary.path);
        }
        if (!await secondary.exists() && !await secondary.parent.exists()) {
          throw FileSystemException('USB drive or share is disconnected', secondary.path);
        }
        await secondary.create(recursive: true);
        secondaryPath = p.join(secondary.path, name);
        if (p.equals(p.absolute(primaryPath), p.absolute(secondaryPath))) {
          secondaryPath = primaryPath;
        } else {
          secondaryPending = '$secondaryPath.partial';
          await File(primaryPath).copy(secondaryPending);
          await File(secondaryPending).rename(secondaryPath);
        }
      } catch (error) {
        secondaryPath = null;
        warning = 'Secondary backup target unreachable (${secondary.path}): $error';
      } finally {
        if (secondaryPending != null && await File(secondaryPending).exists()) {
          try {
            await File(secondaryPending).delete();
          } on FileSystemException {
            // A disconnected secondary must not invalidate the primary copy.
          }
        }
      }
    }
    return BackupResult(success: true, localBackupPath: primaryPath,
        secondaryBackupPath: secondaryPath, warningMessage: warning,
        timestamp: timestamp);
  } catch (error) {
    return BackupResult(success: false, warningMessage: 'Backup failed: $error',
        timestamp: timestamp);
  } finally {
    source?.dispose();
    if (staging != null && await staging.exists()) {
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // Completed primary archives remain valid even if staging cleanup fails.
      }
    }
  }
}

/// Copies media once, then validates and archives those same staged bytes.
Future<Directory> _stageCatalogMedia(String mediaPath, String stagingPath,
    bool requireMedia, List<Map<String, Object?>> references) async {
  final media = Directory(mediaPath);
  final staged = Directory(p.join(stagingPath, 'catalog_media'));
  await staged.create();
  if (await media.exists()) {
    await for (final entity in media.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: media.path);
      final target = p.join(staged.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entity.copy(target);
      } else {
        throw FileSystemException('Catalog media contains an unsupported link', entity.path);
      }
    }
  } else if (requireMedia) {
    throw FileSystemException('Catalog media directory not found', mediaPath);
  }

  File referencedFile(String relativePath) {
    final normalized = p.posix.normalize(relativePath.replaceAll('\\', '/'));
    if (p.posix.isAbsolute(normalized) || RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized == '..' || normalized.startsWith('../')) {
      throw FileSystemException('Invalid catalog media reference', relativePath);
    }
    return File(p.joinAll([staged.path, ...normalized.split('/')]));
  }

  for (final reference in references) {
    final file = referencedFile(reference['path'] as String);
    if (!await file.exists()) {
      throw FileSystemException('Referenced catalog photo is missing', reference['path'] as String);
    }
    final expectedBytes = reference['bytes'] as int?;
    if (expectedBytes != null && await file.length() != expectedBytes) {
      throw FileSystemException('Catalog photo size does not match the database', file.path);
    }
    final checksum = reference['checksum'] as String?;
    if (checksum != null && checksum.isNotEmpty &&
        (await sha256.bind(file.openRead()).first).toString() != checksum) {
      throw FileSystemException('Catalog photo checksum does not match the database', file.path);
    }
    final thumbnail = reference['thumbnail'] as String?;
    if (thumbnail != null && thumbnail.isNotEmpty && !await referencedFile(thumbnail).exists()) {
      throw FileSystemException('Referenced catalog thumbnail is missing', thumbnail);
    }
  }
  return staged;
}
