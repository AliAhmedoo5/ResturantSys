import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> createFeatureGapsSchema(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(discount_presets)');
  if (!columns.any((column) => column['name'] == 'rules_json')) {
    await db.execute("ALTER TABLE discount_presets ADD COLUMN rules_json TEXT NOT NULL DEFAULT '{}'");
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS stock_counts (
    id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT NOT NULL DEFAULT 'DRAFT'
      CHECK(status IN ('DRAFT','SUBMITTED','APPROVED','REJECTED','POSTED')),
    created_by INTEGER NOT NULL REFERENCES staff(id), created_at TEXT NOT NULL,
    submitted_at TEXT, submitted_by INTEGER REFERENCES staff(id), posted_by INTEGER REFERENCES staff(id), approved_by INTEGER REFERENCES staff(id), approved_at TEXT,
    posted_at TEXT, reason TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS stock_count_lines (
    count_id INTEGER NOT NULL REFERENCES stock_counts(id),
    ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id),
    expected REAL NOT NULL, snapshot_sequence INTEGER NOT NULL,
    counted REAL CHECK(counted >= 0), variance REAL, unit TEXT NOT NULL,
    estimated_cost_paisa INTEGER, movement_id INTEGER REFERENCES inventory_movements(id),
    PRIMARY KEY(count_id,ingredient_id))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS configuration_audit (
    id INTEGER PRIMARY KEY AUTOINCREMENT, actor_id INTEGER NOT NULL REFERENCES staff(id),
    kind TEXT NOT NULL, before_json TEXT NOT NULL, after_json TEXT NOT NULL,
    created_at TEXT NOT NULL)''');
  await db.execute("CREATE TRIGGER IF NOT EXISTS count_lines_no_insert BEFORE INSERT ON stock_count_lines WHEN (SELECT status FROM stock_counts WHERE id=NEW.count_id) != 'DRAFT' BEGIN SELECT RAISE(ABORT,'Count evidence is immutable'); END");
  await db.execute("CREATE TRIGGER IF NOT EXISTS approved_count_evidence_no_update BEFORE UPDATE OF counted,variance,expected,snapshot_sequence,ingredient_id,count_id,unit,estimated_cost_paisa ON stock_count_lines WHEN (SELECT status FROM stock_counts WHERE id=OLD.count_id)='APPROVED' BEGIN SELECT RAISE(ABORT,'Approved count evidence is immutable'); END");
  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute("CREATE TRIGGER IF NOT EXISTS configuration_audit_no_$operation BEFORE $operation ON configuration_audit BEGIN SELECT RAISE(ABORT,'Configuration audit is immutable'); END");
    await db.execute("CREATE TRIGGER IF NOT EXISTS posted_count_no_$operation BEFORE $operation ON stock_counts WHEN OLD.status IN ('POSTED','REJECTED') BEGIN SELECT RAISE(ABORT,'Completed count is immutable'); END");
    await db.execute("CREATE TRIGGER IF NOT EXISTS submitted_count_lines_no_$operation BEFORE $operation ON stock_count_lines WHEN (SELECT status FROM stock_counts WHERE id=OLD.count_id) IN ('SUBMITTED','REJECTED','POSTED') BEGIN SELECT RAISE(ABORT,'Count evidence is immutable'); END");
  }
}
