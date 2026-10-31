import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('databases upgrading from v21..v25 to v26 safely receive category and classification columns', () async {
    final directory = await Directory.systemTemp.createTemp('v26-migration-safety-');
    final dbPath = '${directory.path}/legacy_v21.db';
    addTearDown(() async {
      await directory.delete(recursive: true);
    });

    final store = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
    var db = await store.initialize();

    // Verify current fresh install is at latest schema version
    final currentVersion = await db.getVersion();
    expect(currentVersion, PosDatabaseConstants.schemaVersion);

    // Simulate a database that was migrated at version 21 without category / classification columns
    // We recreate raw_ingredients and order_cost_events without those columns, then set version to 21
    await db.execute('DROP TABLE IF EXISTS order_cost_events');
    await db.execute('''CREATE TABLE order_cost_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id),
      ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id),
      revision INTEGER NOT NULL,
      kind TEXT NOT NULL,
      quantity REAL NOT NULL,
      unit_cost_rupees REAL,
      cost_paisa INTEGER,
      source_event_id INTEGER REFERENCES order_cost_events(id),
      recorded_at TEXT NOT NULL
    )''');

    // Simulate raw_ingredients table without category
    await db.execute('ALTER TABLE raw_ingredients RENAME TO raw_ingredients_backup');
    await db.execute('''CREATE TABLE raw_ingredients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      storage_unit TEXT NOT NULL,
      current_stock REAL NOT NULL DEFAULT 0.0,
      low_stock_threshold REAL NOT NULL DEFAULT 0.0,
      cost_per_recipe_unit REAL NOT NULL DEFAULT 0.0,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''INSERT INTO raw_ingredients(id, name, storage_unit, current_stock, low_stock_threshold, cost_per_recipe_unit, created_at)
      SELECT id, name, storage_unit, current_stock, low_stock_threshold, cost_per_recipe_unit, created_at FROM raw_ingredients_backup''');
    await db.execute('DROP TABLE raw_ingredients_backup');

    // Drop backup_attempts to simulate pre-v26 schema
    await db.execute('DROP TABLE IF EXISTS backup_attempts');

    // Set schema version to 21 (simulating upgraded from v21)
    await db.setVersion(21);
    await store.close();

    // Re-initialize to trigger _onUpgrade from 21 -> latest
    db = await store.initialize();
    final newVersion = await db.getVersion();
    expect(newVersion, PosDatabaseConstants.schemaVersion);

    // 1. raw_ingredients must safely have category column
    final ingCols = await db.rawQuery('PRAGMA table_info(raw_ingredients)');
    expect(ingCols.any((c) => c['name'] == 'category'), isTrue,
        reason: 'raw_ingredients must have category column after upgrading to v26');

    // 2. order_cost_events must safely have classification column
    final costCols = await db.rawQuery('PRAGMA table_info(order_cost_events)');
    expect(costCols.any((c) => c['name'] == 'classification'), isTrue,
        reason: 'order_cost_events must have classification column after upgrading to v26');

    // 3. backup_attempts table must exist
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='backup_attempts'");
    expect(tables, isNotEmpty, reason: 'backup_attempts table must exist after upgrading to v26');

    // 4. Foreign key check must pass
    final fkErrors = await db.rawQuery('PRAGMA foreign_key_check');
    expect(fkErrors, isEmpty);

    await store.close();
  });
}
