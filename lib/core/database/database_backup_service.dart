import 'dart:io';
import 'dart:isolate';

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
    this.initiator = 'MANUAL',
    this.managerId,
    this.primaryStatus = 'SUCCESS',
    this.secondaryStatus = 'NOT_CONFIGURED',
    this.verificationStatus = 'VERIFIED',
    this.failureCategory = 'NONE',
    this.failureMessage,
    this.attemptId,
  });

  final bool success;
  final String? localBackupPath;
  final String? secondaryBackupPath;
  final String? warningMessage;
  final DateTime timestamp;
  final String initiator;
  final int? managerId;
  final String primaryStatus;
  final String secondaryStatus;
  final String verificationStatus;
  final String failureCategory;
  final String? failureMessage;
  final int? attemptId;
}

abstract final class BackupFailureCategory {
  static const String none = 'NONE';
  static const String storageUnavailable = 'STORAGE_UNAVAILABLE';
  static const String mediaCorrupted = 'MEDIA_CORRUPTED';
  static const String destinationInvalid = 'DESTINATION_INVALID';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String databaseError = 'DATABASE_ERROR';
  static const String unknown = 'UNKNOWN';
}

String classifyBackupFailure(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('outside catalog media') ||
      message.contains('invalid catalog media reference') ||
      message.contains('this is a file, not a backup directory') ||
      message.contains('not a directory')) {
    return BackupFailureCategory.destinationInvalid;
  }
  if (message.contains('catalog photo') ||
      message.contains('photo size does not match') ||
      message.contains('checksum does not match') ||
      message.contains('thumbnail is missing') ||
      message.contains('unsupported link') ||
      message.contains('catalog media directory not found') ||
      message.contains('media reference')) {
    return BackupFailureCategory.mediaCorrupted;
  }
  if (message.contains('disconnected') ||
      message.contains('unreachable') ||
      message.contains('not found') ||
      message.contains('source database file not found') ||
      message.contains('no space') ||
      message.contains('disk full')) {
    return BackupFailureCategory.storageUnavailable;
  }
  if (message.contains('permission') ||
      message.contains('denied') ||
      message.contains('privilege') ||
      message.contains('access is denied')) {
    return BackupFailureCategory.permissionDenied;
  }
  if (message.contains('sqlite') ||
      message.contains('database') ||
      message.contains('locked') ||
      message.contains('busy')) {
    return BackupFailureCategory.databaseError;
  }
  return BackupFailureCategory.unknown;
}

String sanitizeBackupFailureMessage(String rawMessage) {
  var cleaned = rawMessage.replaceAll(RegExp(r'#\d+.*', multiLine: true), '').trim();
  if (cleaned.startsWith('Exception: ')) cleaned = cleaned.substring('Exception: '.length);
  if (cleaned.startsWith('FileSystemException: ')) cleaned = cleaned.substring('FileSystemException: '.length);
  cleaned = cleaned.replaceAll(RegExp(r'\b\d{4,6}\b'), '[REDACTED]');
  if (cleaned.length > 250) {
    cleaned = '${cleaned.substring(0, 247)}...';
  }
  return cleaned;
}

typedef _CatalogMediaReference = ({
  String path,
  String? thumbnail,
  int? byteCount,
  String? checksum,
});
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
    String initiator = 'MANUAL',
    int? managerId,
  }) async {
    final effectiveTime = timestamp ?? DateTime.now();
    // Only send values to the worker, never the live sqflite connection.
    final mediaPath = catalogMediaDirectoryPath ?? CatalogMediaService.defaultBaseDirectoryPath();
    final requireMedia = catalogMediaDirectoryPath != null;

    BackupResult rawResult;
    try {
      rawResult = await Isolate.run(() => _createBackup(
            sourceDbPath, localBackupDir,
            secondaryBackupDir, effectiveTime, mediaPath, requireMedia,
          ));
    } catch (e) {
      final category = classifyBackupFailure(e);
      final sanitized = sanitizeBackupFailureMessage(e.toString());
      rawResult = BackupResult(
        success: false,
        warningMessage: 'Backup failed: $e',
        timestamp: effectiveTime,
        initiator: initiator,
        managerId: managerId,
        primaryStatus: 'FAILED',
        secondaryStatus: secondaryBackupDir != null && secondaryBackupDir.trim().isNotEmpty
            ? 'FAILED'
            : 'NOT_CONFIGURED',
        verificationStatus: 'FAILED',
        failureCategory: category,
        failureMessage: sanitized,
      );
    }

    final bool isSuccess = rawResult.success;
    final String primaryStatus = isSuccess ? 'SUCCESS' : 'FAILED';
    final String verificationStatus = isSuccess ? 'VERIFIED' : 'FAILED';
    final String secondaryStatus = rawResult.secondaryBackupPath != null
        ? 'SUCCESS'
        : (rawResult.warningMessage != null && isSuccess
            ? 'WARNING'
            : (secondaryBackupDir != null && secondaryBackupDir.trim().isNotEmpty
                ? 'FAILED'
                : 'NOT_CONFIGURED'));
    final String failureCategory = !isSuccess
        ? classifyBackupFailure(rawResult.warningMessage ?? 'Unknown failure')
        : (secondaryStatus == 'WARNING'
            ? classifyBackupFailure(rawResult.warningMessage ?? 'Secondary target warning')
            : 'NONE');
    final String? failureMessage = rawResult.warningMessage != null
        ? sanitizeBackupFailureMessage(rawResult.warningMessage!)
        : null;

    int? attemptId;
    final attemptData = <String, Object?>{
      'attempted_at': effectiveTime.toIso8601String(),
      'initiator': initiator,
      'manager_id': managerId,
      'primary_status': primaryStatus,
      'primary_path': rawResult.localBackupPath,
      'secondary_status': secondaryStatus,
      'secondary_path': rawResult.secondaryBackupPath,
      'verification_status': verificationStatus,
      'failure_category': failureCategory,
      'failure_message': failureMessage,
      'created_at': effectiveTime.toIso8601String(),
    };

    if (database != null) {
      try {
        attemptId = await database!.insert(
          PosDatabaseConstants.tableBackupAttempts,
          attemptData,
        );
      } catch (_) {}
    } else if (File(sourceDbPath).existsSync()) {
      try {
        final ffiDb = sqlite.sqlite3.open(sourceDbPath);
        try {
          final tables = ffiDb.select("SELECT name FROM sqlite_master WHERE type='table' AND name='backup_attempts'");
          if (tables.isNotEmpty) {
            ffiDb.execute(
              'INSERT INTO backup_attempts (attempted_at, initiator, manager_id, primary_status, primary_path, secondary_status, secondary_path, verification_status, failure_category, failure_message, created_at) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                attemptData['attempted_at'],
                attemptData['initiator'],
                attemptData['manager_id'],
                attemptData['primary_status'],
                attemptData['primary_path'],
                attemptData['secondary_status'],
                attemptData['secondary_path'],
                attemptData['verification_status'],
                attemptData['failure_category'],
                attemptData['failure_message'],
                attemptData['created_at'],
              ],
            );
            attemptId = ffiDb.lastInsertRowId;
          }
        } finally {
          ffiDb.dispose();
        }
      } catch (_) {}
    }

    return BackupResult(
      success: isSuccess,
      localBackupPath: rawResult.localBackupPath,
      secondaryBackupPath: rawResult.secondaryBackupPath,
      warningMessage: rawResult.warningMessage,
      timestamp: effectiveTime,
      initiator: initiator,
      managerId: managerId,
      primaryStatus: primaryStatus,
      secondaryStatus: secondaryStatus,
      verificationStatus: verificationStatus,
      failureCategory: failureCategory,
      failureMessage: failureMessage,
      attemptId: attemptId,
    );
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
    final requestedLocal = cleanLocal == null || cleanLocal.isEmpty
        ? DatabaseBackupService.resolveDefaultLocalBackupDir() : cleanLocal;
    final mediaRoot = await _resolveDirectoryPath(mediaPath);
    final primaryRoot = await _resolveDirectoryPath(requestedLocal);
    final local = Directory(primaryRoot);
    if (p.equals(mediaRoot, primaryRoot) || p.isWithin(mediaRoot, primaryRoot)) {
      throw FileSystemException('Backup directory must be outside catalog media', local.path);
    }
    await local.create(recursive: true);
    staging = await local.createTemp('.backup-');
    final snapshotPath = p.join(staging.path, 'pos.db');
    final snapshot = sqlite.sqlite3.open(snapshotPath);
    final references = <_CatalogMediaReference>[];
    try {
      await source.backup(snapshot, nPage: 64).drain<void>();
      if (snapshot.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'catalog_images'").isNotEmpty) {
        for (final row in snapshot.select('SELECT relative_file_path, thumbnail_path, byte_count, sha256_checksum FROM catalog_images')) {
          references.add((
            path: row['relative_file_path'] as String,
            thumbnail: row['thumbnail_path'] as String?,
            byteCount: row['byte_count'] as int?,
            checksum: row['sha256_checksum'] as String?,
          ));
        }
      }
    } finally {
      snapshot.dispose();
    }
    source.dispose();
    source = null;

    final stagedMedia = await _stageCatalogMedia(
        mediaRoot, staging.path, requireMedia, references);

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
        final secondaryRoot = await _resolveDirectoryPath(secondary.path);
        if (p.equals(mediaRoot, secondaryRoot) || p.isWithin(mediaRoot, secondaryRoot)) {
          throw FileSystemException('Secondary backup directory must be outside catalog media', secondary.path);
        }
        if (!await secondary.exists() && !await secondary.parent.exists()) {
          throw FileSystemException('USB drive or share is disconnected', secondary.path);
        }
        await secondary.create(recursive: true);
        secondaryPath = p.join(secondary.path, name);
        if (p.equals(primaryRoot, secondaryRoot)) {
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
    return BackupResult(
      success: true,
      localBackupPath: primaryPath,
      secondaryBackupPath: secondaryPath,
      warningMessage: warning,
      timestamp: timestamp,
      primaryStatus: 'SUCCESS',
      secondaryStatus: secondaryPath != null
          ? 'SUCCESS'
          : (warning != null ? 'WARNING' : 'NOT_CONFIGURED'),
      verificationStatus: 'VERIFIED',
      failureCategory: warning != null ? classifyBackupFailure(warning) : 'NONE',
      failureMessage: warning != null ? sanitizeBackupFailureMessage(warning) : null,
    );
  } catch (error) {
    final category = classifyBackupFailure(error);
    final sanitized = sanitizeBackupFailureMessage(error.toString());
    return BackupResult(
      success: false,
      warningMessage: 'Backup failed: $error',
      timestamp: timestamp,
      primaryStatus: 'FAILED',
      secondaryStatus: secondaryDirectory != null && secondaryDirectory.trim().isNotEmpty
          ? 'FAILED'
          : 'NOT_CONFIGURED',
      verificationStatus: 'FAILED',
      failureCategory: category,
      failureMessage: sanitized,
    );
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

/// Resolves existing ancestors before appending new leaves. Follow links before
/// interpreting '..', since lexical normalization can hide a media ancestor.
Future<String> _resolveDirectoryPath(String path) async {
  final absolute = p.isAbsolute(path)
      ? path : '${Directory.current.path}${p.separator}$path';
  final segments = p.split(absolute);
  var resolved = await Directory(segments.first).resolveSymbolicLinks();
  for (final segment in segments.skip(1)) {
    if (segment == '.') continue;
    if (segment == '..') {
      resolved = p.dirname(resolved);
      continue;
    }
    final candidate = p.join(resolved, segment);
    if (await FileSystemEntity.type(candidate, followLinks: false) ==
        FileSystemEntityType.notFound) {
      resolved = candidate;
    } else {
      resolved = await Directory(candidate).resolveSymbolicLinks();
    }
  }
  return p.normalize(resolved);
}
/// Copies media once, then validates and archives those same staged bytes.
Future<Directory> _stageCatalogMedia(String mediaPath, String stagingPath,
    bool requireMedia, List<_CatalogMediaReference> references) async {
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
    final file = referencedFile(reference.path);
    if (!await file.exists()) {
      throw FileSystemException('Referenced catalog photo is missing', reference.path);
    }
    final expectedBytes = reference.byteCount;
    if (expectedBytes != null && await file.length() != expectedBytes) {
      throw FileSystemException('Catalog photo size does not match the database', file.path);
    }
    final checksum = reference.checksum;
    if (checksum != null && checksum.isNotEmpty &&
        (await sha256.bind(file.openRead()).first).toString() != checksum) {
      throw FileSystemException('Catalog photo checksum does not match the database', file.path);
    }
    final thumbnail = reference.thumbnail;
    if (thumbnail != null && thumbnail.isNotEmpty && !await referencedFile(thumbnail).exists()) {
      throw FileSystemException('Referenced catalog thumbnail is missing', thumbnail);
    }
  }
  return staged;
}
