import 'package:sqflite_common/sqlite_api.dart';

Future<void> createHoldLifecycleSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS hold_lifecycle_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hold_id INTEGER NOT NULL,
    cashier_id INTEGER NOT NULL REFERENCES staff(id),
    event_type TEXT NOT NULL CHECK(event_type IN ('CREATED', 'RECALLED', 'REPLACED', 'DISCARDED', 'CONVERTED')),
    order_id INTEGER REFERENCES orders(id),
    previous_hold_id INTEGER,
    label TEXT NOT NULL,
    payload TEXT NOT NULL,
    recorded_at TEXT NOT NULL,
    CHECK (event_type != 'CONVERTED' OR order_id IS NOT NULL),
    CHECK (event_type != 'REPLACED' OR previous_hold_id IS NOT NULL),
    CHECK (order_id IS NULL OR event_type = 'CONVERTED'),
    CHECK (previous_hold_id IS NULL OR event_type IN ('REPLACED', 'CREATED'))
  )''');

  await db.execute('CREATE INDEX IF NOT EXISTS hold_lifecycle_hold_id ON hold_lifecycle_events(hold_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS hold_lifecycle_cashier ON hold_lifecycle_events(cashier_id, recorded_at)');
  await db.execute('CREATE INDEX IF NOT EXISTS hold_lifecycle_recorded ON hold_lifecycle_events(recorded_at)');

  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS hold_lifecycle_events_no_${operation.toLowerCase()}
      BEFORE $operation ON hold_lifecycle_events BEGIN SELECT RAISE(ABORT, 'Hold lifecycle events are immutable'); END''');
  }
}
