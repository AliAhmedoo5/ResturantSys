import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> createHistoricalCostSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS ingredient_cost_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT, ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id),
    unit_cost_rupees REAL NOT NULL, recorded_at TEXT NOT NULL)''');
  for (final operation in ['INSERT', 'UPDATE OF cost_per_recipe_unit']) {
    final name = operation.startsWith('UPDATE') ? 'change' : 'initial';
    await db.execute('''CREATE TRIGGER IF NOT EXISTS ingredient_cost_$name AFTER $operation ON raw_ingredients
      BEGIN INSERT INTO ingredient_cost_history(ingredient_id,unit_cost_rupees,recorded_at)
      VALUES(NEW.id,NEW.cost_per_recipe_unit,strftime('%Y-%m-%d %H:%M:%f','now','localtime')); END''');
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS order_cost_coverage (
    order_id INTEGER PRIMARY KEY REFERENCES orders(id), policy TEXT NOT NULL,
    recorded_at TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS order_cost_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL REFERENCES orders(id),
    ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id), revision INTEGER NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('CONSUME','RETURN','COOKED_WASTE')),
    quantity REAL NOT NULL CHECK(quantity > 0), unit_cost_rupees REAL,
    cost_paisa INTEGER, source_event_id INTEGER REFERENCES order_cost_events(id),
    recorded_at TEXT NOT NULL)''');
  await db.execute('CREATE INDEX IF NOT EXISTS order_cost_events_order ON order_cost_events(order_id,ingredient_id)');
  await db.execute('''CREATE TABLE IF NOT EXISTS order_discounts (
    order_id INTEGER NOT NULL REFERENCES orders(id), discount_id INTEGER NOT NULL,
    sequence INTEGER NOT NULL, name_snapshot TEXT NOT NULL, terms_json TEXT NOT NULL,
    amount_paisa INTEGER NOT NULL CHECK(amount_paisa >= 0),
    PRIMARY KEY(order_id,discount_id), UNIQUE(order_id,sequence))''');
  for (final table in ['ingredient_cost_history', 'order_cost_coverage', 'order_cost_events', 'order_discounts']) {
    for (final operation in ['UPDATE', 'DELETE']) {
      await db.execute("CREATE TRIGGER IF NOT EXISTS ${table}_no_$operation BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Historical evidence is immutable'); END");
    }
  }
}
