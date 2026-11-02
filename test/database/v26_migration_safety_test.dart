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
    // Drop those columns and drop backup_attempts, then set version to 21
    await db.execute('ALTER TABLE order_cost_events DROP COLUMN classification');
    await db.execute('ALTER TABLE raw_ingredients DROP COLUMN category');

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
