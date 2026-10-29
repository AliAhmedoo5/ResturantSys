import 'package:sqflite_common/sqlite_api.dart';

/// Deliberately no historical backfill: old tenders have no receiving evidence.
Future<void> createPaymentEventsSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS payment_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_key TEXT NOT NULL UNIQUE,
    kind TEXT NOT NULL,
    amount_paisa INTEGER NOT NULL,
    payment_source TEXT NOT NULL,
    payment_method TEXT,
    actual_at TEXT,
    recorded_at TEXT NOT NULL,
    business_day_id INTEGER REFERENCES business_days(id),
    shift_id INTEGER REFERENCES shifts(id),
    order_id INTEGER REFERENCES orders(id),
    tender_id INTEGER UNIQUE REFERENCES order_payments(id),
    movement_id INTEGER UNIQUE REFERENCES cash_movements(id),
    settlement_id INTEGER,
    recorded_by INTEGER NOT NULL REFERENCES staff(id),
    approved_by INTEGER REFERENCES staff(id),
    recorded_by_name_snapshot TEXT,
    shift_owner_name_snapshot TEXT,
    change_paisa INTEGER NOT NULL DEFAULT 0,
    rounding_paisa INTEGER NOT NULL DEFAULT 0,
    source_table TEXT,
    source_id INTEGER
  )''');
  await db.execute('CREATE INDEX IF NOT EXISTS payment_events_receiving ON payment_events(business_day_id,shift_id,actual_at)');
  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS payment_events_no_${operation.toLowerCase()}
      BEFORE $operation ON payment_events BEGIN SELECT RAISE(ABORT,'Payment events are immutable'); END''');
  }
}
