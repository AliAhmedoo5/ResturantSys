import 'package:sqflite_common/sqlite_api.dart';

Future<void> createManagerPresetsSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS manager_report_presets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    owner_staff_id INTEGER NOT NULL REFERENCES staff(id),
    is_shared INTEGER NOT NULL DEFAULT 0,
    family TEXT NOT NULL,
    period_kind TEXT NOT NULL,
    dynamic_period TEXT,
    start_date TEXT,
    end_date_exclusive TEXT,
    time_basis TEXT NOT NULL,
    grouping TEXT NOT NULL,
    filters_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_manager_presets_owner ON manager_report_presets(owner_staff_id, is_shared)');
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_manager_presets_owner_name ON manager_report_presets(owner_staff_id, name)');
}
