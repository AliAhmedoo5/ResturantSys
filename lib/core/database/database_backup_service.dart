import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

/// Service handling dual-target SQLite database backups to local storage
/// and secondary external/USB drive paths on Z-Report finalization.
class DatabaseBackupService {
  DatabaseBackupService({this.database});

  final Database? database;

  /// Resolves the default local backup directory on the host machine.
  static String resolveDefaultLocalBackupDir({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final win = isWindows ?? Platform.isWindows;
    if (win) {
      final env = environment ?? Platform.environment;
      final programData = env['ProgramData'] ?? r'C:\ProgramData';
      return '$programData\\${PosDatabaseConstants.defaultProgramDataFolder}\\${PosDatabaseConstants.defaultBackupsSubFolder}';
    }

    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? '.';
    return p.join(
      home,
      '.resturant_pos',
      PosDatabaseConstants.defaultBackupsSubFolder,
    );
  }

  /// Flushes the SQLite WAL journal and copies pos.db to the local archive
  /// and an optional secondary/USB drive path.
  Future<BackupResult> executeBackup({
    required String sourceDbPath,
    String? localBackupDir,
    String? secondaryBackupDir,
    DateTime? timestamp,
  }) async {
    final effectiveTime = timestamp ?? DateTime.now();

    // 1. Flush SQLite WAL journal to ensure pos.db contains all committed transactions
    if (database != null && database!.isOpen) {
      try {
        await database!.rawQuery('PRAGMA wal_checkpoint(FULL);');
      } catch (_) {
        // WAL checkpoint best-effort
      }
    }

    final sourceFile = File(sourceDbPath);
    if (!await sourceFile.exists()) {
      return BackupResult(
        success: false,
        warningMessage: 'Source database file not found: $sourceDbPath',
        timestamp: effectiveTime,
      );
    }

    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final formattedTimestamp = '${effectiveTime.year}'
        '${twoDigits(effectiveTime.month)}'
        '${twoDigits(effectiveTime.day)}_'
        '${twoDigits(effectiveTime.hour)}'
        '${twoDigits(effectiveTime.minute)}'
        '${twoDigits(effectiveTime.second)}';
    final backupFileName = 'pos_backup_$formattedTimestamp.db';

    // 2. Primary Local Backup
    final targetLocalDir = localBackupDir ?? resolveDefaultLocalBackupDir();
    final localDirObj = Directory(targetLocalDir);
    if (!await localDirObj.exists()) {
      await localDirObj.create(recursive: true);
    }

    final localTargetPath = p.join(targetLocalDir, backupFileName);
    await sourceFile.copy(localTargetPath);

    // 3. Secondary / External USB Backup Target
    String? secondaryTargetPath;
    String? warning;

    if (secondaryBackupDir != null && secondaryBackupDir.trim().isNotEmpty) {
      final cleanSecPath = secondaryBackupDir.trim();
      final secDirObj = Directory(cleanSecPath);
      try {
        if (await secDirObj.exists() || await secDirObj.parent.exists()) {
          if (!await secDirObj.exists()) {
            await secDirObj.create(recursive: true);
          }
          final secFilePath = p.join(cleanSecPath, backupFileName);
          await sourceFile.copy(secFilePath);
          secondaryTargetPath = secFilePath;
        } else {
          warning = 'Secondary backup target unreachable ($cleanSecPath). USB drive may be disconnected.';
        }
      } catch (e) {
        warning = 'Secondary backup target unreachable ($cleanSecPath): $e';
      }
    }

    return BackupResult(
      success: true,
      localBackupPath: localTargetPath,
      secondaryBackupPath: secondaryTargetPath,
      warningMessage: warning,
      timestamp: effectiveTime,
    );
  }
}
