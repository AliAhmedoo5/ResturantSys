import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/historical_costs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('HistoricalCosts - Classification without string heuristics', () {
    test('relies on category column and explicit classification, avoiding string guessing on name', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);

      // Create schema
      await db.execute('''CREATE TABLE raw_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        storage_unit TEXT NOT NULL,
        current_stock REAL NOT NULL DEFAULT 0.0,
        low_stock_threshold REAL NOT NULL DEFAULT 0.0,
        cost_per_recipe_unit REAL NOT NULL DEFAULT 0.0,
        category TEXT,
        created_at TEXT NOT NULL
      )''');
      await db.execute('''CREATE TABLE order_cost_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        ingredient_id INTEGER NOT NULL,
        revision INTEGER NOT NULL,
        kind TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_cost_rupees REAL,
        cost_paisa INTEGER,
        source_event_id INTEGER,
        recorded_at TEXT NOT NULL,
        classification TEXT
      )''');

      // Ingredient 1: Has "takeaway packaging" in name but category is explicitly 'FOOD'
      final foodWithPackagingName = await db.insert('raw_ingredients', {
        'name': 'Takeaway Packaging Meal Sauce',
        'storage_unit': 'g',
        'current_stock': 1000,
        'cost_per_recipe_unit': 10,
        'category': 'FOOD',
        'created_at': '2026-10-30 10:00:00',
      });

      // Ingredient 2: Category is explicitly 'PACKAGING'
      final packagingItem = await db.insert('raw_ingredients', {
        'name': 'Cardboard Box',
        'storage_unit': 'count',
        'current_stock': 500,
        'cost_per_recipe_unit': 5,
        'category': 'PACKAGING',
        'created_at': '2026-10-30 10:00:00',
      });

      // Ingredient 3: Has "packaging" in name but category is null -> defaults to FOOD without string guessing
      final unclassifiedItem = await db.insert('raw_ingredients', {
        'name': 'Packaging Tape',
        'storage_unit': 'count',
        'current_stock': 10,
        'cost_per_recipe_unit': 15,
        'category': null,
        'created_at': '2026-10-30 10:00:00',
      });

      await HistoricalCosts.consume(
        db,
        1,
        0,
        {
          foodWithPackagingName: 100.0,
          packagingItem: 1.0,
          unclassifiedItem: 1.0,
        },
      );

      final events = await db.query('order_cost_events', orderBy: 'id ASC');
      expect(events, hasLength(3));

      // 1. Food with packaging in name must be classified as FOOD (not PACKAGING)
      expect(events[0]['ingredient_id'], foodWithPackagingName);
      expect(events[0]['classification'], 'FOOD');

      // 2. Explicit category PACKAGING must be PACKAGING
      expect(events[1]['ingredient_id'], packagingItem);
      expect(events[1]['classification'], 'PACKAGING');

      // 3. Unclassified with packaging in name must NOT be guessed as PACKAGING; defaults to FOOD
      expect(events[2]['ingredient_id'], unclassifiedItem);
      expect(events[2]['classification'], 'FOOD');

      // 4. Explicit classifications map parameter overrides row
      await HistoricalCosts.consume(
        db,
        2,
        0,
        {
          unclassifiedItem: 2.0,
        },
        classifications: {
          unclassifiedItem: 'PACKAGING',
        },
      );
      final explicitEvent = (await db.query('order_cost_events', where: 'order_id = 2')).first;
      expect(explicitEvent['classification'], 'PACKAGING');
    });
  });
}
