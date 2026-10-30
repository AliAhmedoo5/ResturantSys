import 'package:sqflite_common/sqlite_api.dart';

/// Schema definition and immutability triggers for durable backup attempt history.
Future<void> createBackupAttemptsSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS backup_attempts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      attempted_at TEXT NOT NULL,
      initiator TEXT NOT NULL CHECK(initiator IN ('MANUAL', 'SCHEDULED', 'Z_CLOSE')),
      manager_id INTEGER REFERENCES staff(id),
      primary_status TEXT NOT NULL CHECK(primary_status IN ('SUCCESS', 'FAILED', 'SKIPPED')),
      primary_path TEXT,
      secondary_status TEXT NOT NULL CHECK(secondary_status IN ('SUCCESS', 'FAILED', 'WARNING', 'NOT_CONFIGURED', 'SKIPPED')),
      secondary_path TEXT,
      verification_status TEXT NOT NULL CHECK(verification_status IN ('VERIFIED', 'FAILED', 'UNVERIFIED')),
      failure_category TEXT NOT NULL DEFAULT 'NONE',
      failure_message TEXT,
      created_at TEXT NOT NULL
    )
  ''');

  await db.execute('CREATE INDEX IF NOT EXISTS idx_backup_attempts_attempted_at ON backup_attempts(attempted_at DESC, id DESC);');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_backup_attempts_verification ON backup_attempts(verification_status, primary_status);');

  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS backup_attempts_no_$operation BEFORE $operation ON backup_attempts "
      "BEGIN SELECT RAISE(ABORT, 'Backup attempts are immutable'); END",
    );
  }
}
