import 'package:sqflite_common/sqlite_api.dart';

Future<void> createHistoricalCorrectionsSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS historical_corrections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    correction_key TEXT NOT NULL UNIQUE,
    affected_business_day_id INTEGER NOT NULL REFERENCES business_days(id),
    affected_shift_id INTEGER REFERENCES shifts(id),
    target_entity_type TEXT NOT NULL, target_entity_id INTEGER,
    correction_type TEXT NOT NULL, delta_amount_paisa INTEGER NOT NULL,
    payment_source TEXT NOT NULL, event_time TEXT,
    recorded_at TEXT NOT NULL, recorded_by_staff_id INTEGER NOT NULL REFERENCES staff(id),
    manager_name_snapshot TEXT NOT NULL, reason TEXT NOT NULL CHECK(length(reason)>=10),
    source_reference TEXT NOT NULL,
    reverses_correction_id INTEGER UNIQUE REFERENCES historical_corrections(id),
    original_source_table TEXT, original_source_id INTEGER,
    metric TEXT NOT NULL
  )''');
  await db.execute('CREATE INDEX IF NOT EXISTS corrections_day_cutoff ON historical_corrections(affected_business_day_id,recorded_at)');
  await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS corrections_source_once
    ON historical_corrections(source_reference) WHERE reverses_correction_id IS NULL''');
  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS historical_corrections_no_${operation.toLowerCase()}
      BEFORE $operation ON historical_corrections BEGIN SELECT RAISE(ABORT,'Historical corrections are immutable'); END''');
  }
}
