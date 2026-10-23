import 'dart:isolate';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
  DatabaseBackupService({this.database});

  final Database? database;

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
    final defaultLocal = resolveDefaultLocalBackupDir();
    return Isolate.run(() => _createBackup(
          sourceDbPath, localBackupDir ?? defaultLocal,
          secondaryBackupDir, effectiveTime,
        ));
  }
}

Future<BackupResult> _createBackup(String sourcePath, String localDirectory,
    String? secondaryDirectory, DateTime timestamp) async {
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

    if (secondaryDirectory == null && source.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'system_settings'").isNotEmpty) {
      final rows = source.select('SELECT value FROM system_settings WHERE key = ?',
          [PosDatabaseConstants.settingSecondaryBackupPath]);
      if (rows.isNotEmpty) secondaryDirectory = rows.first['value'] as String?;
    }
    final local = Directory(localDirectory);
    await local.create(recursive: true);
    staging = await local.createTemp('.backup-');
    final snapshotPath = p.join(staging.path, 'pos.db');
    final snapshot = sqlite.sqlite3.open(snapshotPath);
    try {
      await source.backup(snapshot, nPage: 64).drain<void>();
    } finally {
      snapshot.dispose();
    }
    source.dispose();
    source = null;

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
      await staging.delete(recursive: true);
    }
  }
}


